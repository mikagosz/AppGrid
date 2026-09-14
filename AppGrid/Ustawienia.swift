import AppKit
import Carbon.HIToolbox

/// Który róg ekranu wywołuje okno.
enum RogEkranu: Int, CaseIterable, Identifiable {
    case lewyGorny = 0, prawyGorny = 1, lewyDolny = 2, prawyDolny = 3

    var id: Int { rawValue }

    var nazwa: String {
        switch self {
        case .lewyGorny:  return String(localized: "Top left")
        case .prawyGorny: return String(localized: "Top right")
        case .lewyDolny:  return String(localized: "Bottom left")
        case .prawyDolny: return String(localized: "Bottom right")
        }
    }
}

/// Jak moduł traktuje rozmiary okien Findera.
enum TrybOkienFindera: Int, CaseIterable, Identifiable {
    /// Jeden rozmiar narzucany każdemu nowemu oknu (decyzja [U] 2026-08-14).
    case jedenDlaWszystkich = 0
    /// Każdy folder pamięta swój własny rozmiar.
    case osobnoPerFolder = 1

    var id: Int { rawValue }

    var nazwa: String {
        switch self {
        case .jedenDlaWszystkich: return String(localized: "One size for every window")
        case .osobnoPerFolder:    return String(localized: "Each folder remembers its own")
        }
    }
}

/// Jak pokazujemy programy „ostatnie" u góry listy.
enum TrybOstatnich: Int, CaseIterable, Identifiable {
    /// Dwie osobne sekcje, każda z własnym licznikiem — układ z AG-1.
    case osobneSekcje = 0
    /// Jeden wspólny rząd bez zawijania; liczbę ikon decyduje szerokość okna.
    case jedenRzad = 1

    var id: Int { rawValue }

    var nazwa: String {
        switch self {
        case .osobneSekcje: return String(localized: "Two separate sections")
        case .jedenRzad:    return String(localized: "One shared row")
        }
    }
}

/// Ustawienia programu — jedno miejsce, jeden zapis do `UserDefaults`.
///
/// Wszystko, co [U] przestawia w oknie ustawień, siedzi tutaj. Każda właściwość
/// zapisuje się od razu w `didSet`, tak samo jak `iconScale` w [`AppGridModel`] —
/// dzięki temu nie ma osobnego kroku „zapisz" i nie da się zgubić zmiany przy
/// zamknięciu okna.
@MainActor
final class Ustawienia: ObservableObject {

    static let shared = Ustawienia()

    // MARK: - Wywołanie

    @Published var skrotWlaczony: Bool { didSet { zapisz(skrotWlaczony, K.skrotWlaczony) } }
    /// Kod klawisza w numeracji Carbona (`kVK_*`).
    @Published var skrotKlawisz: Int { didSet { zapisz(skrotKlawisz, K.skrotKlawisz) } }
    /// Modyfikatory jako surowa wartość `NSEvent.ModifierFlags`.
    @Published var skrotModyfikatory: Int { didSet { zapisz(skrotModyfikatory, K.skrotModyfikatory) } }

    @Published var rogWlaczony: Bool { didSet { zapisz(rogWlaczony, K.rogWlaczony) } }
    @Published var rog: RogEkranu { didSet { zapisz(rog.rawValue, K.rog) } }
    /// Tryb gry: przy pełnoekranowym oknie na wierzchu róg ma milczeć.
    @Published var rogGamemode: Bool { didSet { zapisz(rogGamemode, K.rogGamemode) } }

    // MARK: - Wygląd

    /// 1,0 = nieprzezroczyste. 0,95 = 5% przezroczystości (wartość zamówiona przez [U]).
    @Published var krycieTla: Double { didSet { zapisz(krycieTla, K.krycieTla) } }

    // MARK: - Okno główne (AG-22)

    /// Szerokość okna głównego, ustawiana **tutaj**, a nie myszą.
    ///
    /// Decyzja [U] 2026-08-23 po trzeciej rundzie usterki „okno nie przeformatowuje się
    /// z dużego na małe": skoro zwężanie ciągnięciem za krawędź psuło układ za każdym
    /// razem, krawędź przestaje być ruchoma. Wysokość zostaje wolna — zgłoszenie
    /// dotyczyło wyłącznie szerokości.
    /// Zakres pilnowany **tutaj**, nie w widoku: od AG-26 wartość wchodzi dwiema drogami
    /// — suwakiem i wpisana z palca — a granica ma być jedna. Przypisanie wewnątrz
    /// `didSet` nie woła `didSet` ponownie, więc to się nie zapętla.
    @Published var szerokoscOkna: Double {
        didSet {
            let zacisniete = min(max(szerokoscOkna, Self.zakresSzerokosciOkna.lowerBound),
                                 Self.zakresSzerokosciOkna.upperBound)
            if zacisniete != szerokoscOkna { szerokoscOkna = zacisniete }
            zapisz(szerokoscOkna, K.szerokoscOkna)
        }
    }

    /// Czy okno ma wychodzić na środku ekranu, cokolwiek zapisała ostatnia pozycja.
    ///
    /// Zgłoszenie [U] 2026-09-05 z testu 0.2.25 (AG-25). Rozmiar dalej jest pamiętany —
    /// `setFrameAutosaveName` zostaje, przestawiamy wyłącznie początek ramki.
    @Published var oknoNaSrodku: Bool { didSet { zapisz(oknoNaSrodku, K.oknoNaSrodku) } }

    /// Dolna granica to `minWidth` widoku (520 pt) — poniżej niej treść zaczyna się urywać,
    /// bo górny pasek ma stałą szerokość filtra i suwaka.
    static let zakresSzerokosciOkna: ClosedRange<Double> = 520...2400

    // MARK: - Sekcje u góry listy (AG-1)

    @Published var trybOstatnich: TrybOstatnich { didSet { zapisz(trybOstatnich.rawValue, K.trybOstatnich) } }
    @Published var pokazujOstatnioDodane: Bool { didSet { zapisz(pokazujOstatnioDodane, K.pokazujOstatnioDodane) } }
    @Published var ileOstatnioDodanych: Int { didSet { zapisz(ileOstatnioDodanych, K.ileOstatnioDodanych) } }
    @Published var pokazujOstatnioUzywane: Bool { didSet { zapisz(pokazujOstatnioUzywane, K.pokazujOstatnioUzywane) } }
    @Published var ileOstatnioUzywanych: Int { didSet { zapisz(ileOstatnioUzywanych, K.ileOstatnioUzywanych) } }

    // MARK: - Ukryte programy

    /// Ścieżki programów, których [U] nie chce widzieć w siatce.
    ///
    /// Wracają, gdy tylko coś wpiszesz w szukajkę — ukrycie porządkuje widok, nie odbiera
    /// dostępu do programu.
    @Published private(set) var ukryte: Set<String> { didSet { zapisz(ukryte.sorted(), K.ukryte) } }

    func przelaczUkrycie(_ id: String) {
        if ukryte.contains(id) { ukryte.remove(id) } else { ukryte.insert(id) }
    }

    func odkryj(_ id: String) { ukryte.remove(id) }

    func odkryjWszystkie() { ukryte = [] }

    // MARK: - Układ siatki: kolejność i separatory

    /// Własna kolejność ikon i belek w sekcji „Wszystkie programy".
    ///
    /// Pusta = siatka leci alfabetycznie, tak jak zawsze. Wypełnia się dopiero przy
    /// pierwszym przesunięciu albo pierwszej belce.
    @Published private(set) var kolejnosc: [ElementUkladu] { didSet { zapisz(zakoduj(kolejnosc), K.kolejnosc) } }

    /// To samo dla sekcji „Narzędzia systemowe" (AG-23). Osobny zapis, bo to osobna
    /// sekcja — ale ta sama matematyka i ten sam kod rysujący.
    @Published private(set) var kolejnoscNarzedzi: [ElementUkladu] { didSet { zapisz(zakoduj(kolejnoscNarzedzi), K.kolejnoscNarzedzi) } }

    /// Belki obu sekcji leżą w jednej puli — każda i tak siedzi w dokładnie jednej
    /// kolejności, a jej `id` mówi w której.
    @Published private(set) var separatory: [Separator] { didSet { zapisz(zakoduj(separatory), K.separatory) } }

    func separator(_ id: UUID) -> Separator? {
        separatory.first { $0.id == id }
    }

    func kolejnosc(_ sekcja: Sekcja) -> [ElementUkladu] {
        sekcja == .glowne ? kolejnosc : kolejnoscNarzedzi
    }

    private func ustawKolejnosc(_ nowa: [ElementUkladu], _ sekcja: Sekcja) {
        switch sekcja {
        case .glowne:    kolejnosc = nowa
        case .narzedzia: kolejnoscNarzedzi = nowa
        }
    }

    // MARK: - Przypisanie programu do sekcji (AG-23)

    /// Programy przełożone ręcznie do drugiej sekcji — wbrew temu, gdzie posłał je skaner.
    ///
    /// Trzymamy **tylko odstępstwa**: program, który siedzi tam, gdzie trafił sam, nie ma
    /// tu wpisu. Dzięki temu zmiana w skanerze (nowy katalog „Utilities") nie musi
    /// przepisywać zapisu, a przełożenie ikony z powrotem po prostu kasuje wpis.
    @Published private(set) var przypisania: [String: Int] { didSet { zapisz(przypisania, K.przypisania) } }

    func sekcja(_ id: String, domyslna: Sekcja) -> Sekcja {
        przypisania[id].flatMap(Sekcja.init(rawValue:)) ?? domyslna
    }

    func przypisz(_ id: String, do sekcja: Sekcja, domyslna: Sekcja) {
        if sekcja == domyslna {
            przypisania.removeValue(forKey: id)
        } else {
            przypisania[id] = sekcja.rawValue
        }
    }

    /// Odsyła wszystkie przełożone programy tam, gdzie posłał je skaner. Kolejności
    /// nie rusza — to osobna rzecz i osobny przycisk.
    func wyczyscPrzypisania() { przypisania = [:] }

    /// Wstawia nową belkę przed wskazanym elementem — albo na początku, gdy `cel == nil`.
    func dodajSeparator(przed cel: ElementUkladu?, w sekcja: Sekcja, wsrod programy: [InstalledApp]) {
        let belka = Separator()
        separatory.append(belka)
        ustawKolejnosc(
            UkladSiatki.wstawBelke(
                belka,
                przed: cel,
                w: UkladSiatki.domknij(kolejnosc(sekcja), programy: programy)
            ),
            sekcja
        )
    }

    /// Zasiewa układ przy pierwszym wejściu w edycję.
    ///
    /// Utrwala to, co [U] widzi na ekranie, i zakłada na górze belkę „Wszystkie programy".
    /// Dzięki temu nagłówek tej sekcji przestaje być wmurowany w widok i staje się zwykłą
    /// belką — da się go przesunąć, przemianować i wstawić coś **nad** nim. O to prosił
    /// [U] 2026-08-22: „żebym mógł na górę poukładać swoją kategorię".
    func zasiej(programy: [InstalledApp], nazwaPierwszejBelki: String) {
        let domknieta = UkladSiatki.domknij(kolejnosc, programy: programy)
        // Belka na samej górze JEST nagłówkiem tej sekcji. Warunkiem nie jest więc
        // „układ jest świeży" — bo [U] mógł już coś poukładać, a wtedy zasiew by się
        // nie odpalił i nagłówek zostałby wmurowany na zawsze.
        if case .belka = domknieta.first {
            kolejnosc = domknieta
            return
        }
        let belka = Separator(nazwa: nazwaPierwszejBelki)
        separatory.append(belka)
        kolejnosc = UkladSiatki.wstawBelke(belka, przed: nil, w: domknieta)
    }

    func usunSeparator(_ belka: Separator) {
        separatory.removeAll { $0.id == belka.id }
        // Belka mogła zostać przeciągnięta do drugiej sekcji, więc szukamy w obu.
        kolejnosc.removeAll { $0 == .belka(belka.id) }
        kolejnoscNarzedzi.removeAll { $0 == .belka(belka.id) }
    }

    func zmienNazweSeparatora(_ id: UUID, na nazwa: String) {
        guard let i = separatory.firstIndex(where: { $0.id == id }) else { return }
        separatory[i].nazwa = nazwa
    }

    /// Przesuwa ikonę albo belkę — także **do drugiej sekcji** (AG-23).
    ///
    /// `przed == nil` znaczy „na sam koniec sekcji docelowej". Gdy sekcja się zmienia,
    /// program dostaje przy okazji przypisanie: bez niego wróciłby na swoje stare miejsce
    /// przy pierwszym `⌘R`, bo o sekcji decydowałby znowu skaner.
    ///
    /// `programyCelu` liczymy **przed** zmianą przypisania, więc domknięcie kolejności celu
    /// nie dopisze przenoszonego programu na koniec — wstawiamy go sami, tam gdzie trzeba.
    func przenies(
        _ co: ElementUkladu,
        z zrodlo: Sekcja,
        do cel: Sekcja,
        przed: ElementUkladu?,
        programyZrodla: [InstalledApp],
        programyCelu: [InstalledApp],
        domyslnaSekcja: Sekcja
    ) {
        let zZrodla = UkladSiatki.domknij(kolejnosc(zrodlo), programy: programyZrodla)

        guard zrodlo != cel else {
            ustawKolejnosc(UkladSiatki.przenies(co, przed: przed, w: zZrodla), zrodlo)
            return
        }

        let doCelu = UkladSiatki.domknij(kolejnosc(cel), programy: programyCelu)
        let wynik = UkladSiatki.przenies(co, zKolejnosci: zZrodla, doKolejnosci: doCelu, przed: przed)

        if case .program(let sciezka) = co {
            przypisz(sciezka, do: cel, domyslna: domyslnaSekcja)
        }
        ustawKolejnosc(wynik.zrodlo, zrodlo)
        ustawKolejnosc(wynik.cel, cel)
    }

    /// Kasuje własny układ — obie siatki wracają do alfabetu, belki znikają.
    ///
    /// Przypisań do sekcji **nie rusza**: to osobna decyzja [U] („to narzędzie ma stać
    /// wśród programów"), a nie kolejność. Do cofnięcia jest osobny przycisk.
    func przywrocAlfabet() {
        kolejnosc = []
        kolejnoscNarzedzi = []
        separatory = []
    }

    private func zakoduj<T: Encodable>(_ wartosc: T) -> Data? {
        try? JSONEncoder().encode(wartosc)
    }

    // MARK: - Okna Findera (etap 2)

    @Published var finderWlaczony: Bool { didSet { zapisz(finderWlaczony, K.finderWlaczony) } }
    @Published var finderTryb: TrybOkienFindera { didSet { zapisz(finderTryb.rawValue, K.finderTryb) } }
    @Published var finderSzerokosc: Double { didSet { zapisz(finderSzerokosc, K.finderSzerokosc) } }
    @Published var finderWysokosc: Double { didSet { zapisz(finderWysokosc, K.finderWysokosc) } }
    /// Czy zmiana rozmiaru okna przez [U] ma nadpisywać zapamiętaną wartość.
    @Published var finderUczySie: Bool { didSet { zapisz(finderUczySie, K.finderUczySie) } }

    private init() {
        let d = UserDefaults.standard

        skrotWlaczony      = d.object(forKey: K.skrotWlaczony) as? Bool ?? true
        skrotKlawisz       = d.object(forKey: K.skrotKlawisz) as? Int ?? kVK_ANSI_A
        skrotModyfikatory  = d.object(forKey: K.skrotModyfikatory) as? Int
            ?? Int(NSEvent.ModifierFlags([.control, .option, .command]).rawValue)

        rogWlaczony        = d.object(forKey: K.rogWlaczony) as? Bool ?? false
        rog                = RogEkranu(rawValue: d.object(forKey: K.rog) as? Int ?? 0) ?? .lewyGorny
        // Domyślnie włączony: sam róg startuje wyłączony, więc nikomu to nic nie zmienia,
        // a włączając róg [U] dostaje od razu zachowanie, o które prosił.
        rogGamemode        = d.object(forKey: K.rogGamemode) as? Bool ?? true

        krycieTla          = d.object(forKey: K.krycieTla) as? Double ?? 0.95

        // Zaciśnięte przy wczytaniu, nie tylko w suwaku: zapis mógł powstać przed AG-22,
        // gdy okno dało się rozciągnąć myszą do czegokolwiek.
        let zapisanaSzerokosc = d.object(forKey: K.szerokoscOkna) as? Double ?? 900
        szerokoscOkna      = min(max(zapisanaSzerokosc, Self.zakresSzerokosciOkna.lowerBound),
                                 Self.zakresSzerokosciOkna.upperBound)

        // Domyślnie włączone: to jest zachowanie zamówione przez [U] w zgłoszeniu,
        // a zapisana pozycja i tak nikomu nie służyła — okno wracało tam, gdzie
        // ostatnio je odsunięto.
        oknoNaSrodku       = d.object(forKey: K.oknoNaSrodku) as? Bool ?? true

        trybOstatnich          = TrybOstatnich(rawValue: d.object(forKey: K.trybOstatnich) as? Int ?? 0) ?? .osobneSekcje
        pokazujOstatnioDodane  = d.object(forKey: K.pokazujOstatnioDodane) as? Bool ?? false
        ileOstatnioDodanych    = d.object(forKey: K.ileOstatnioDodanych) as? Int ?? 8
        pokazujOstatnioUzywane = d.object(forKey: K.pokazujOstatnioUzywane) as? Bool ?? false
        ileOstatnioUzywanych   = d.object(forKey: K.ileOstatnioUzywanych) as? Int ?? 8

        ukryte             = Set(d.stringArray(forKey: K.ukryte) ?? [])
        przypisania        = (d.dictionary(forKey: K.przypisania) as? [String: Int]) ?? [:]
        let wczytaneBelki = (d.data(forKey: K.separatory))
            .flatMap { try? JSONDecoder().decode([Separator].self, from: $0) } ?? []
        let wczytanaKolejnosc = (d.data(forKey: K.kolejnosc))
            .flatMap { try? JSONDecoder().decode([ElementUkladu].self, from: $0) } ?? []
        let wczytaneNarzedzia = (d.data(forKey: K.kolejnoscNarzedzi))
            .flatMap { try? JSONDecoder().decode([ElementUkladu].self, from: $0) } ?? []

        // Belka, której nie ma w kolejności, nie ma jak się pokazać ani jak zostać
        // złapana — w siatce jej nie widać, a w ustawieniach wisiałaby jako duch.
        // Dotyczy zapisów sprzed 0.2.9, gdzie belka kotwiczyła się przy programie,
        // a kolejności w ogóle nie było.
        // Od AG-23 kolejności są dwie, więc belka jest żywa, jeśli stoi w KTÓREJKOLWIEK.
        let belkiWKolejnosci = Set((wczytanaKolejnosc + wczytaneNarzedzia).compactMap { element -> UUID? in
            if case .belka(let uuid) = element { return uuid }
            return nil
        })
        kolejnosc          = wczytanaKolejnosc
        kolejnoscNarzedzi  = wczytaneNarzedzia
        separatory         = wczytaneBelki.filter { belkiWKolejnosci.contains($0.id) }

        finderWlaczony     = d.object(forKey: K.finderWlaczony) as? Bool ?? false
        finderTryb         = TrybOkienFindera(rawValue: d.object(forKey: K.finderTryb) as? Int ?? 0) ?? .jedenDlaWszystkich
        finderSzerokosc    = d.object(forKey: K.finderSzerokosc) as? Double ?? 1100
        finderWysokosc     = d.object(forKey: K.finderWysokosc) as? Double ?? 720
        finderUczySie      = d.object(forKey: K.finderUczySie) as? Bool ?? true
    }

    private func zapisz(_ wartosc: Any?, _ klucz: String) {
        UserDefaults.standard.set(wartosc, forKey: klucz)
    }

    /// Opis skrótu do pokazania w oknie ustawień, np. `⌃⌥⌘A`.
    var opisSkrotu: String {
        SkrotGlobalny.opis(
            klawisz: skrotKlawisz,
            modyfikatory: NSEvent.ModifierFlags(rawValue: UInt(skrotModyfikatory))
        )
    }

    private enum K {
        static let skrotWlaczony          = "AppGrid.skrot.wlaczony"
        static let skrotKlawisz           = "AppGrid.skrot.klawisz"
        static let skrotModyfikatory      = "AppGrid.skrot.modyfikatory"
        static let rogWlaczony            = "AppGrid.rog.wlaczony"
        static let rog                    = "AppGrid.rog.ktory"
        static let rogGamemode            = "AppGrid.rog.gamemode"
        static let krycieTla              = "AppGrid.krycieTla"
        static let szerokoscOkna          = "AppGrid.okno.szerokosc"
        static let oknoNaSrodku           = "AppGrid.okno.naSrodku"
        static let trybOstatnich          = "AppGrid.ostatnie.tryb"
        static let pokazujOstatnioDodane  = "AppGrid.ostatnioDodane.wlaczone"
        static let ileOstatnioDodanych    = "AppGrid.ostatnioDodane.ile"
        static let pokazujOstatnioUzywane = "AppGrid.ostatnioUzywane.wlaczone"
        static let ileOstatnioUzywanych   = "AppGrid.ostatnioUzywane.ile"
        static let ukryte                 = "AppGrid.ukryte"
        static let separatory             = "AppGrid.separatory"
        static let kolejnosc              = "AppGrid.kolejnosc"
        static let kolejnoscNarzedzi      = "AppGrid.kolejnosc.narzedzia"
        static let przypisania            = "AppGrid.sekcje.przypisania"
        static let finderWlaczony         = "AppGrid.finder.wlaczony"
        static let finderTryb             = "AppGrid.finder.tryb"
        static let finderSzerokosc        = "AppGrid.finder.szerokosc"
        static let finderWysokosc         = "AppGrid.finder.wysokosc"
        static let finderUczySie          = "AppGrid.finder.uczySie"
    }
}
