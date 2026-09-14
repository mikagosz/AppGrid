import AppKit
import Combine
import SwiftUI

/// Przeciąganie w toku: co jedzie, do której sekcji i przed czym stanie.
///
/// `przed == nil` znaczy „na koniec sekcji docelowej". Z tej jednej pary liczy się
/// **i** podgląd, **i** zapis — dzięki temu ikona ląduje dokładnie tam, gdzie ją było
/// widać przed puszczeniem.
struct PodgladPrzeniesienia: Equatable {
    let co: ElementUkladu
    let doSekcji: Sekcja
    let przed: ElementUkladu?
}

/// Stan okna: lista aplikacji, wpisany tekst, wybrana kategoria, rozmiar ikon.
@MainActor
final class AppGridModel: ObservableObject {

    @Published var apps: [InstalledApp] = []
    @Published var query: String = ""
    @Published var category: String = wszystkie

    /// Suwak 1–5. Zapisywany od razu, bo ma przeżyć zamknięcie okna.
    @Published var iconScale: Int {
        didSet { UserDefaults.standard.set(iconScale, forKey: Self.kluczRozmiaru) }
    }

    static let wszystkie = String(localized: "All")
    private static let kluczRozmiaru = "AppGrid.iconScale"

    let ustawienia = Ustawienia.shared
    private let dziennik = DziennikUruchomien()
    private var subskrypcja: AnyCancellable?

    init() {
        let zapisany = UserDefaults.standard.integer(forKey: Self.kluczRozmiaru)
        iconScale = (1...5).contains(zapisany) ? zapisany : 3
        // Przełączniki sekcji siedzą w ustawieniach, a rysuje je ten sam widok —
        // bez tego mostka zmiana w oknie ustawień nie odświeżyłaby listy.
        subskrypcja = ustawienia.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var iconSize: CGFloat { CGFloat(32 + iconScale * 16) }

    var categories: [String] {
        let zebrane = Set(apps.map(\.category))
        return [Self.wszystkie] + zebrane.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var visibleApps: [InstalledApp] {
        var lista = apps
        if category != Self.wszystkie {
            lista = lista.filter { $0.category == category }
        }
        let szukane = query.trimmingCharacters(in: .whitespaces)
        if szukane.isEmpty {
            // Ukryte wracają dopiero na wpisany tekst. Filtr kategorii ich nie odsłania —
            // ukrycie ma porządkować widok, a nie odbierać dostęp do programu.
            lista = lista.filter { !ustawienia.ukryte.contains($0.id) }
        } else {
            lista = lista.filter { $0.name.localizedCaseInsensitiveContains(szukane) }
        }
        return lista
    }

    /// W której sekcji stoi program.
    ///
    /// Skaner tylko **proponuje** (katalog `Utilities` → narzędzie), a ostatnie słowo ma
    /// [U]: ikonę przeciągniętą do drugiej sekcji trzyma tam przypisanie w ustawieniach.
    /// Decyzja [U] 2026-08-23 (AG-23).
    func sekcja(_ app: InstalledApp) -> Sekcja {
        ustawienia.sekcja(app.id, domyslna: domyslnaSekcja(app))
    }

    /// Gdzie posłałby program sam skaner, bez ręki [U].
    private func domyslnaSekcja(_ app: InstalledApp) -> Sekcja {
        app.isUtility ? .narzedzia : .glowne
    }

    /// Programy, których używa się na co dzień.
    var visibleRegular: [InstalledApp] {
        visibleApps.filter { sekcja($0) == .glowne }
    }

    /// Narzędzia systemowe — osobno, na dole, żeby nie zaśmiecały listy.
    var visibleUtilities: [InstalledApp] {
        visibleApps.filter { sekcja($0) == .narzedzia }
    }

    // MARK: - Sekcje u góry listy (AG-1)

    /// Sekcje mają sens tylko przy pełnej liście — przy szukaniu i filtrze kategorii
    /// tylko zabierałyby miejsce wynikom.
    var listaPelna: Bool {
        category == Self.wszystkie && query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var ostatnioDodane: [InstalledApp] {
        guard ustawienia.trybOstatnich == .osobneSekcje else { return [] }
        guard ustawienia.pokazujOstatnioDodane, listaPelna else { return [] }
        return OstatnieProgramy.ostatnioDodane(apps, ile: ustawienia.ileOstatnioDodanych)
    }

    var ostatnioUzywane: [InstalledApp] {
        guard ustawienia.trybOstatnich == .osobneSekcje else { return [] }
        guard ustawienia.pokazujOstatnioUzywane, listaPelna else { return [] }
        return OstatnieProgramy.ostatnioUzywane(
            apps,
            dziennik: dziennik.wpisy,
            ile: ustawienia.ileOstatnioUzywanych
        )
    }

    /// Jeden wspólny rząd. `ile` liczy widok z szerokości okna, bo w tym trybie to
    /// szerokość decyduje, ile ikon wejdzie — nie suwak w ustawieniach.
    func ostatnieScalone(ile: Int) -> [InstalledApp] {
        guard ustawienia.trybOstatnich == .jedenRzad, listaPelna else { return [] }
        return OstatnieProgramy.scalone(
            visibleApps,
            dziennik: dziennik.wpisy,
            zDodanych: ustawienia.pokazujOstatnioDodane,
            zUzywanych: ustawienia.pokazujOstatnioUzywane,
            ile: ile
        )
    }

    /// Czy nad listą „wszystkie programy" cokolwiek stoi — od tego zależy jej nagłówek.
    ///
    /// W trybie jednego rzędu pytamy o jedną pozycję zamiast o pełny rząd, bo szerokość
    /// okna liczy dopiero widok, a nagłówek trzeba znać wcześniej.
    var maSekcjeOstatnich: Bool {
        switch ustawienia.trybOstatnich {
        case .osobneSekcje: return !ostatnioDodane.isEmpty || !ostatnioUzywane.isEmpty
        case .jedenRzad:    return !ostatnieScalone(ile: 1).isEmpty
        }
    }

    // MARK: - Ukrywanie i separatory

    func przelaczUkrycie(_ app: InstalledApp) {
        ustawienia.przelaczUkrycie(app.id)
    }

    // MARK: - Tryb edycji układu

    /// Stan sesji, nie ustawienie: po zamknięciu okna edycja ma się kończyć sama.
    @Published private(set) var trybEdycji = false

    func wejdzWEdycje() {
        // Przestawianie ikon przy włączonym filtrze albo wpisanej szukajce pokazywałoby
        // kawałek układu, a zapisywałoby całość — z widoku nie dałoby się przewidzieć wyniku.
        query = ""
        category = Self.wszystkie
        // Nagłówek „Wszystkie programy" zamienia się w zwykłą belkę dopiero tutaj —
        // przed pierwszą edycją siatka ma wyglądać dokładnie tak, jak wyglądała.
        ustawienia.zasiej(programy: programyDoUkladu(.glowne), nazwaPierwszejBelki: String(localized: "All apps"))
        trybEdycji = true
    }

    func wyjdzZEdycji() { trybEdycji = false }

    /// Programy, których dotyczy własna kolejność danej sekcji.
    ///
    /// Bierzemy je z pełnej listy, nie z widocznej — inaczej ukryty program wypadłby
    /// z układu i po odkryciu wracałby na koniec zamiast na swoje miejsce.
    private func programyDoUkladu(_ sekcja: Sekcja) -> [InstalledApp] {
        apps.filter { self.sekcja($0) == sekcja }
    }

    /// W której sekcji stoi teraz ciągnięty element.
    ///
    /// Program mówi to sam przez swoje przypisanie; belka — przez to, w której
    /// kolejności leży. Nieznana ścieżka (program odinstalowany w trakcie) trafia
    /// do głównej, bo tam nikomu nie zaszkodzi.
    func sekcjaElementu(_ co: ElementUkladu) -> Sekcja {
        switch co {
        case .program(let sciezka):
            guard let app = apps.first(where: { $0.id == sciezka }) else { return .glowne }
            return sekcja(app)
        case .belka:
            return ustawienia.kolejnoscNarzedzi.contains(co) ? .narzedzia : .glowne
        }
    }

    /// Płaska zawartość sekcji — w tej postaci rysuje siatkę `UkladPlynny`.
    ///
    /// `podglad` to przeciąganie w toku. Liczymy z niego układ **bez zapisywania**, więc
    /// ikony rozstępują się już w trakcie ciągnięcia — także wtedy, gdy ciągniemy je
    /// do **drugiej** sekcji: ta, z której wychodzą, zaciska się w tym samym momencie.
    func pozycje(_ sekcja: Sekcja, podglad: PodgladPrzeniesienia?) -> [UkladSiatki.Pozycja] {
        UkladSiatki.pozycje(
            programy: programyWidoczne(sekcja, podglad: podglad),
            kolejnosc: kolejnosciZPodgladem(podglad)[sekcja] ?? [],
            separatory: ustawienia.separatory,
            pokazujPusteBelki: trybEdycji
        )
    }

    /// Widoczne programy sekcji z uwzględnieniem podglądu: przeciągana ikona jest już
    /// „u sąsiada", choć zapis jeszcze o tym nie wie.
    private func programyWidoczne(_ sekcja: Sekcja, podglad: PodgladPrzeniesienia?) -> [InstalledApp] {
        var lista = visibleApps.filter { self.sekcja($0) == sekcja }
        guard let podglad, case .program(let sciezka) = podglad.co,
              let app = apps.first(where: { $0.id == sciezka }),
              self.sekcja(app) != podglad.doSekcji else { return lista }

        if sekcja == podglad.doSekcji {
            // Dokładamy tylko to, co i tak byłoby widoczne — ukrytego program nie odsłaniamy.
            if visibleApps.contains(where: { $0.id == sciezka }) { lista.append(app) }
        } else if sekcja == self.sekcja(app) {
            lista.removeAll { $0.id == sciezka }
        }
        return lista
    }

    /// Kolejności **obu** sekcji naraz, z naniesionym podglądem.
    ///
    /// Obie w jednym przebiegu, bo ruch między sekcjami zmienia je jednocześnie —
    /// liczone osobno mogłyby się rozjechać i ikona mignęłaby w dwóch miejscach.
    private func kolejnosciZPodgladem(_ podglad: PodgladPrzeniesienia?) -> [Sekcja: [ElementUkladu]] {
        var wynik: [Sekcja: [ElementUkladu]] = [:]
        for s in Sekcja.allCases {
            wynik[s] = UkladSiatki.domknij(ustawienia.kolejnosc(s), programy: programyDoUkladu(s))
        }
        guard let podglad else { return wynik }

        let zrodlo = sekcjaElementu(podglad.co)
        guard zrodlo != podglad.doSekcji else {
            wynik[zrodlo] = UkladSiatki.przenies(podglad.co, przed: podglad.przed, w: wynik[zrodlo] ?? [])
            return wynik
        }
        let ruch = UkladSiatki.przenies(
            podglad.co,
            zKolejnosci: wynik[zrodlo] ?? [],
            doKolejnosci: wynik[podglad.doSekcji] ?? [],
            przed: podglad.przed
        )
        wynik[zrodlo] = ruch.zrodlo
        wynik[podglad.doSekcji] = ruch.cel
        return wynik
    }

    /// Czy nagłówek „Wszystkie programy" ma jeszcze rysować widok.
    ///
    /// Po zasianiu układu robi to belka, a nie widok — dwa nagłówki jeden nad drugim
    /// wyglądałyby jak usterka.
    var rysujWlasnyNaglowekWszystkich: Bool {
        if case .belka = ustawienia.kolejnosc.first { return false }
        return true
    }

    func dodajSeparator(przed cel: ElementUkladu?, w sekcja: Sekcja = .glowne) {
        ustawienia.dodajSeparator(przed: cel, w: sekcja, wsrod: programyDoUkladu(sekcja))
    }

    /// Zapisuje przeniesienie — w tej samej sekcji albo do drugiej.
    func przenies(_ co: ElementUkladu, doSekcji cel: Sekcja, przed: ElementUkladu?) {
        let zrodlo = sekcjaElementu(co)
        ustawienia.przenies(
            co,
            z: zrodlo,
            do: cel,
            przed: przed,
            programyZrodla: programyDoUkladu(zrodlo),
            programyCelu: programyDoUkladu(cel),
            domyslnaSekcja: domyslnaSekcjaElementu(co)
        )
    }

    private func domyslnaSekcjaElementu(_ co: ElementUkladu) -> Sekcja {
        guard case .program(let sciezka) = co,
              let app = apps.first(where: { $0.id == sciezka }) else { return .glowne }
        return domyslnaSekcja(app)
    }

    func usunSeparator(_ belka: Separator) {
        ustawienia.usunSeparator(belka)
    }

    func przywrocAlfabet() {
        ustawienia.przywrocAlfabet()
    }

    func wyczyscHistorieUzycia() {
        dziennik.wyczysc()
        objectWillChange.send()
    }

    func reload() {
        // Ikony wiszą w pamięci między przerysowaniami, więc odświeżenie listy musi je
        // wyrzucić — inaczej program po aktualizacji zostałby ze starą ikoną do restartu.
        IkonyProgramow.zapomnij()
        apps = AppScanner.scan()
    }

    /// Wywoływane przy KAŻDYM pokazaniu okna.
    ///
    /// Systemowy widok wraca do ostatniego wyszukiwania — ten wraca do pełnej listy.
    /// Kategoria też się zeruje: filtr jest stanem sesji, nie ustawieniem.
    func resetForShow() {
        query = ""
        category = Self.wszystkie
        trybEdycji = false
        wybrany = nil
    }

    // MARK: - Chodzenie po ikonach strzałkami

    /// Ikona wskazana z klawiatury. `nil` znaczy „nic nie wybrano": pierwsza strzałka
    /// staje wtedy na pierwszej ikonie, a Enter nie ma czego uruchomić.
    @Published var wybrany: InstalledApp.ID?

    /// Ile ikon mieści się w rzędzie — sama liczba, do podglądu na moście.
    @Published var kolumnWRzedzie: Int = 1

    /// Gdzie naprawdę leży każda ikona. Ustawia to **widok**, bo tylko on zna szerokość
    /// siatki, a układ liczy `UkladSiatki.ramki` — ten sam kod, który ikony rysuje.
    ///
    /// 🔴 Bez tego strzałka w dół była skokiem o stałą liczbę kolumn i myliła się
    /// wszędzie tam, gdzie rząd jest krótszy: belka łamie rząd w pół, a sekcja
    /// „Narzędzia systemowe" zaczyna własny. Zgłoszenie [U]: „w dół skacze dziwnie
    /// między sekcjami zamiast lecieć po prostu w dół".
    @Published var mapaNawigacji: [PolozenieIkony] = []

    struct PolozenieIkony: Equatable {
        let id: InstalledApp.ID
        let ramka: CGRect
    }

    enum Kierunek { case lewo, prawo, gora, dol }

    /// Ikony w tej samej kolejności, w jakiej rysuje je siatka: najpierw sekcja główna,
    /// potem narzędzia systemowe. Belki się pomija — na separatorze nie da się stanąć.
    ///
    /// 🔴 Kolejność bierzemy z `pozycje`, a nie z `visibleApps`, bo to `pozycje` widzi
    /// układ poustawiany ręką [U]. Liczone z `visibleApps` strzałki chodziłyby alfabetem,
    /// czyli nie tak, jak ikony leżą na ekranie.
    var kolejnoscNawigacji: [InstalledApp] {
        (pozycje(.glowne, podglad: nil) + pozycje(.narzedzia, podglad: nil)).compactMap {
            if case .program(let app) = $0 { return app }
            return nil
        }
    }

    func przesunWybor(_ kierunek: Kierunek) {
        // Kolejność czytania: rząd po rzędzie, w rzędzie od lewej. Ta sama, w jakiej
        // ikony leżą na ekranie — także przez belki i przez granicę sekcji.
        let mapa = mapaNawigacji.sorted {
            $0.ramka.minY == $1.ramka.minY ? $0.ramka.minX < $1.ramka.minX
                                           : $0.ramka.minY < $1.ramka.minY
        }
        guard !mapa.isEmpty else { return }
        // Pierwsze naciśnięcie tylko wskazuje start — także wtedy, gdy poprzedni wybór
        // zniknął z listy po wpisaniu czegoś w szukajkę.
        guard let teraz = wybrany, let i = mapa.firstIndex(where: { $0.id == teraz }) else {
            wybrany = mapa.first?.id
            return
        }
        let tu = mapa[i]

        switch kierunek {
        case .lewo:
            // Lewo i prawo idą kolejnością czytania: z początku rzędu wchodzi się
            // na koniec poprzedniego, dokładnie tak jak wraca kursor w tekście.
            if i > 0 { wybrany = mapa[i - 1].id }
        case .prawo:
            if i + 1 < mapa.count { wybrany = mapa[i + 1].id }
        case .gora, .dol:
            let wDol = (kierunek == .dol)
            // Najbliższy rząd w tę stronę…
            let rzedy = mapa.filter { wDol ? $0.ramka.minY > tu.ramka.minY : $0.ramka.minY < tu.ramka.minY }
            guard let rzad = wDol ? rzedy.map(\.ramka.minY).min() : rzedy.map(\.ramka.minY).max() else { return }
            // …a w nim ikona najbliżej tej kolumny, w której stoimy. Rząd bywa krótszy
            // (belka albo koniec sekcji), więc „ta sama kolumna" nie zawsze istnieje.
            let kandydaci = mapa.filter { $0.ramka.minY == rzad }
            wybrany = kandydaci.min {
                abs($0.ramka.midX - tu.ramka.midX) < abs($1.ramka.midX - tu.ramka.midX)
            }?.id
        }
    }

    func uruchomWybrany() {
        guard let id = wybrany, let app = kolejnoscNawigacji.first(where: { $0.id == id }) else { return }
        launch(app)
    }

    func launch(_ app: InstalledApp) {
        dziennik.zapiszUruchomienie(app)
        objectWillChange.send()
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }
}
