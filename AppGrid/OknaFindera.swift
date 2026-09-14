import AppKit
import ApplicationServices
import Security

/// Etap 2 — rozmiar okien Findera.
///
/// Dwa tryby, bo to dwie różne rzeczy (patrz [`TrybOkienFindera`]):
///
/// - **jeden dla wszystkich** — każde nowo otwarte okno dostaje ten sam rozmiar,
///   niezależnie od tego, który folder pokazuje. To była decyzja [U] 2026-08-14.
/// - **osobno per folder** — rozmiar zapamiętywany pod ścieżką folderu, a folder bez
///   zapamiętanego wpisu **zostaje nietknięty**. Rozmiar globalny w tym trybie nie
///   obowiązuje i dlatego jego pola są w ustawieniach wygaszone (decyzja [U] 2026-09-12).
///
/// Folder okna rozpoznajemy z **paska okruszków** (`AXURL` ostatniego elementu), bo
/// `AXDocument` okien Findera nie obsługuje — szczegóły i pomiar przy [`folderZListyUrl`].
///
/// Uwaga do drugiego trybu: Finder **sam** trzyma bounds okna per folder w `.DS_Store`,
/// i to jest właśnie źródło bałaganu, na który [U] narzekał. Tryb „osobno" nie naprawia
/// tamtego mechanizmu, tylko dokłada nad nim własną warstwę tam, gdzie [U] sam ustawił
/// rozmiar. Folder, którego [U] nie ustawiał, zostaje w rękach Findera.
///
/// Cały moduł wymaga zgody na **Dostępność**. Bez niej nie robi nic i mówi o tym wprost.
@MainActor
final class OknaFindera: ObservableObject {

    @Published private(set) var zgodaJest = AXIsProcessTrusted()
    /// Krótka diagnostyka dla [U] — ile okien moduł widzi i ile z nich rozpoznaje po folderze.
    @Published private(set) var opisStanu = ""

    private let ustawienia = Ustawienia.shared
    private var obserwator: AXObserver?
    private var aplikacjaFindera: AXUIElement?
    private var wlaczony = false

    /// Ignoruje własne zmiany rozmiaru, żeby moduł nie „uczył się" tego, co sam przed chwilą ustawił.
    private var wlasnaZmiana = false
    private var zegarNauki: Timer?

    private static let kluczFolderow = "AppGrid.finder.rozmiaryFolderow"
    private nonisolated static let idFindera = "com.apple.finder"

    // MARK: - Włączanie

    func wlacz() {
        odswiezZgode()
        guard zgodaJest, !wlaczony else { opiszStan(); return }
        wlaczony = true
        podepnijSieDoFindera()
        obserwujRestartFindera()
        zastosujDoWszystkich()
    }

    func wylacz() {
        wlaczony = false
        odepnijSie()
        opiszStan()
    }

    func odswiezZgode() {
        zgodaJest = AXIsProcessTrusted()
    }

    /// Czy paczka jest podpisana ad-hoc.
    ///
    /// To nie ciekawostka, tylko ostrzeżenie: przy podpisie ad-hoc designated requirement
    /// jest gołym hashem binarki, więc **każde przebudowanie to dla systemu inny program**.
    /// Wpis w Ustawieniach zostaje wtedy włączony i wygląda na przyznany, a
    /// `AXIsProcessTrusted()` dalej zwraca `false`. Opisane w sejfie:
    /// `Programy MacOS/Podpisywanie-kodu-macOS.md`, sekcja „Problem, który to rozwiązuje".
    nonisolated static func podpisAdHoc() -> Bool {
        var kod: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &kod) == errSecSuccess,
              let kod else { return false }
        var informacje: CFDictionary?
        guard SecCodeCopySigningInformation(kod, SecCSFlags(rawValue: 0), &informacje) == errSecSuccess,
              let slownik = informacje as? [String: Any],
              let flagi = slownik[kSecCodeInfoFlags as String] as? UInt32
        else { return false }
        return flagi & 0x2 != 0        // kSecCodeSignatureAdhoc
    }

    /// Otwiera systemowe okno z prośbą o zgodę na Dostępność.
    func poprosOZgode() {
        let opcje = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opcje)
    }

    // MARK: - Rozmiary

    /// Rozmiar, jaki należy się oknu pokazującemu dany folder.
    ///
    /// `nil` znaczy **nie dotykaj tego okna** — zostaje takie, jak otworzył je Finder.
    ///
    /// 🔴 Decyzja [U] 2026-09-12: *„jeżeli jest zaznaczone, aby pamiętał wymiar okna,
    /// to rozmiar w programie powinien być wygaszony"*. W trybie „każdy folder pamięta
    /// swój własny" rozmiar globalny **nie obowiązuje w ogóle** — folder bez wpisu
    /// nie dostaje nic. Wcześniej spadał do globalnego i to właśnie wyglądało jak
    /// „program wymusza swój rozmiar mimo trybu per folder".
    nonisolated static func rozmiarDlaFolderu(
        folder: String?,
        tryb: TrybOkienFindera,
        zapamietane: [String: [Double]],
        globalny: CGSize
    ) -> CGSize? {
        // Jeden rozmiar dla wszystkich: narzucamy go każdemu oknu, folder bez znaczenia.
        guard tryb == .osobnoPerFolder else { return globalny }
        guard let folder,
              let para = zapamietane[folder],
              para.count == 2,
              para[0] > 0, para[1] > 0
        else { return nil }
        return CGSize(width: para[0], height: para[1])
    }

    /// Folder, który okno pokazuje, wyprowadzony z **paska okruszków** — listy
    /// elementów niosących `AXURL`.
    ///
    /// 🔴 Dlaczego nie `AXDocument`: okna Findera tego atrybutu **nie mają**.
    /// Zmierzone 2026-09-12 sondą AX — odczyt oddaje `-25212` (atrybut nieobsługiwany),
    /// a powtórzony po 0,05 · 0,1 · 0,2 · 0,4 · 0,8 i 1,6 s dalej daje `NIL`. Przez to
    /// każde okno wyglądało jak „folder nieznany" i tryb „każdy folder pamięta swój
    /// własny" nie miał jak zadziałać.
    ///
    /// 🔴 Dlaczego nie sam ostatni okruszek: **pasek pokazuje ścieżkę do zaznaczonego
    /// elementu, nie do folderu**. Zmierzone 2026-09-12 — przy zaznaczonym pliku ostatni
    /// okruszek to `plik1.txt`, a w oknie „Aplikacje" z zaznaczoną apką: `AppGrid.app`.
    /// Pierwsza wersja tej poprawki zapamiętała pod takimi kluczami dwa śmieciowe wpisy,
    /// zanim pomiar to pokazał. Sprawdzanie „czy to katalog" nie wystarcza: zaznaczony
    /// **folder** też jest katalogiem, a pakiet aplikacji tym bardziej.
    ///
    /// Dlatego folder rozpoznajemy po **tytule okna**: bierzemy ostatni okruszek o tej
    /// samej nazwie. Obie wartości robi ten sam Finder, więc lokalizacja się zgadza
    /// (`/Applications` → okruszek „Aplikacje" i tytuł „Aplikacje"). Nic nie pasuje —
    /// oddajemy `nil` i okno zostaje nietknięte, zamiast zgadywać.
    nonisolated static func folderZOkruszkow(_ okruszki: [(nazwa: String, adres: URL)],
                                             tytulOkna: String?) -> String? {
        guard let tytulOkna, !tytulOkna.isEmpty else { return nil }
        guard let trafiony = okruszki.last(where: { $0.nazwa == tytulOkna }),
              let plik = (trafiony.adres as NSURL).filePathURL
        else { return nil }
        var sciezka = plik.path
        if sciezka.count > 1, sciezka.hasSuffix("/") { sciezka.removeLast() }
        return sciezka.isEmpty ? nil : sciezka
    }

    /// Ścieżka folderu z atrybutu `AXDocument` okna Findera (`file:///…` → `/…`).
    nonisolated static func kluczFolderu(_ dokument: String?) -> String? {
        guard let dokument, !dokument.isEmpty else { return nil }
        guard let url = URL(string: dokument), url.isFileURL else { return dokument }
        var sciezka = url.path
        // Bez końcowego ukośnika, żeby „/Users/x" i „/Users/x/" nie były dwoma wpisami.
        if sciezka.count > 1, sciezka.hasSuffix("/") { sciezka.removeLast() }
        return sciezka
    }

    private var globalnyRozmiar: CGSize {
        CGSize(width: ustawienia.finderSzerokosc, height: ustawienia.finderWysokosc)
    }

    private var zapamietaneFoldery: [String: [Double]] {
        get { UserDefaults.standard.dictionary(forKey: Self.kluczFolderow) as? [String: [Double]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.kluczFolderow) }
    }

    func zapomnijFoldery() {
        UserDefaults.standard.removeObject(forKey: Self.kluczFolderow)
        opiszStan()
    }

    var ileZapamietanychFolderow: Int { zapamietaneFoldery.count }

    /// Bierze rozmiar z okna Findera, które jest teraz na wierzchu — żeby [U] nie musiał
    /// wpisywać liczb z palca.
    @discardableResult
    func wezRozmiarZBiezacegoOkna() -> Bool {
        guard zgodaJest, let finder = aplikacjaFindera ?? zbudujElementFindera() else { return false }
        for okno in okna(finder) where czyZwykleOkno(okno) {
            guard let rozmiar = rozmiar(okno) else { continue }
            ustawienia.finderSzerokosc = Double(rozmiar.width)
            ustawienia.finderWysokosc = Double(rozmiar.height)
            opiszStan()
            return true
        }
        return false
    }

    /// Narzuca zapamiętany rozmiar wszystkim otwartym oknom Findera.
    func zastosujDoWszystkich() {
        guard zgodaJest, let finder = aplikacjaFindera ?? zbudujElementFindera() else { opiszStan(); return }
        for okno in okna(finder) where czyZwykleOkno(okno) {
            zastosuj(do: okno)
            zarejestrujZmianeRozmiaru(okno)
        }
        opiszStan()
    }

    private func zastosuj(do okno: AXUIElement) {
        wlasnaZmiana = true
        ustawRozmiar(okno)
        // Finder potrafi nadpisać rozmiar tuż po otwarciu, wczytując bounds z `.DS_Store`.
        // Drugie podejście po chwili jest tańsze niż walka z tamtym zapisem.
        //
        // Rozmiar liczymy w nim **od nowa**, a nie z wartości zapamiętanej na starcie:
        // gdyby okruszki nie były jeszcze gotowe w chwili otwarcia, pierwsze podejście
        // poszłoby rozmiarem globalnym i drugie powtórzyłoby ten sam błąd.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.ustawRozmiar(okno)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.wlasnaZmiana = false }
        }
    }

    private func ustawRozmiar(_ okno: AXUIElement) {
        guard var docelowy = Self.rozmiarDlaFolderu(
            folder: sciezkaFolderu(okno),
            tryb: ustawienia.finderTryb,
            zapamietane: zapamietaneFoldery,
            globalny: globalnyRozmiar
        ) else { return }        // folder bez zapamiętanego rozmiaru — okno zostaje, jak jest
        guard docelowy.width > 0, docelowy.height > 0 else { return }
        guard let wartosc = AXValueCreate(.cgSize, &docelowy) else { return }
        AXUIElementSetAttributeValue(okno, kAXSizeAttribute as CFString, wartosc)
    }

    /// Zapamiętuje rozmiar po tym, jak [U] ręcznie zmienił okno.
    private func zapamietaj(z okno: AXUIElement) {
        guard ustawienia.finderUczySie, !wlasnaZmiana, let rozmiar = rozmiar(okno) else { return }
        guard rozmiar.width > 200, rozmiar.height > 150 else { return }   // okno w trakcie animacji

        zegarNauki?.invalidate()
        let folder = sciezkaFolderu(okno)
        // Ciągnięcie za róg sypie dziesiątkami powiadomień — zapisujemy dopiero, gdy ucichnie.
        zegarNauki = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch self.ustawienia.finderTryb {
                case .jedenDlaWszystkich:
                    self.ustawienia.finderSzerokosc = Double(rozmiar.width)
                    self.ustawienia.finderWysokosc = Double(rozmiar.height)
                case .osobnoPerFolder:
                    guard let folder else { return }
                    var wpisy = self.zapamietaneFoldery
                    wpisy[folder] = [Double(rozmiar.width), Double(rozmiar.height)]
                    self.zapamietaneFoldery = wpisy
                }
                self.opiszStan()
            }
        }
    }

    // MARK: - Podpięcie do Findera

    private func zbudujElementFindera() -> AXUIElement? {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.idFindera).first
        else { return nil }
        let element = AXUIElementCreateApplication(finder.processIdentifier)
        aplikacjaFindera = element
        return element
    }

    private func podepnijSieDoFindera() {
        odepnijSie()
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.idFindera).first
        else { return }

        var obs: AXObserver?
        let wynik = AXObserverCreate(finder.processIdentifier, { _, element, powiadomienie, refcon in
            guard let refcon else { return }
            let modul = Unmanaged<OknaFindera>.fromOpaque(refcon).takeUnretainedValue()
            // Powiadomienia AX przychodzą na tej pętli zdarzeń, do której podpięliśmy
            // źródło — czyli na głównej.
            MainActor.assumeIsolated {
                modul.przyjmij(powiadomienie: powiadomienie as String, element: element)
            }
        }, &obs)
        guard wynik == .success, let obs else { return }

        let element = zbudujElementFindera() ?? AXUIElementCreateApplication(finder.processIdentifier)
        aplikacjaFindera = element
        let ja = Unmanaged.passUnretained(self).toOpaque()

        for powiadomienie in [kAXWindowCreatedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, element, powiadomienie as CFString, ja)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        obserwator = obs
    }

    private func odepnijSie() {
        if let obserwator {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obserwator), .defaultMode)
        }
        obserwator = nil
        aplikacjaFindera = nil
        zegarNauki?.invalidate()
        zegarNauki = nil
    }

    /// Finder bywa ubijany i wstaje z nowym PID-em — wtedy stary obserwator jest martwy.
    private func obserwujRestartFindera() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] powiadomienie in
            let program = powiadomienie.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            guard program?.bundleIdentifier == Self.idFindera else { return }
            MainActor.assumeIsolated {
                guard let self, self.wlaczony else { return }
                self.podepnijSieDoFindera()
                self.zastosujDoWszystkich()
            }
        }
    }

    private func przyjmij(powiadomienie: String, element: AXUIElement) {
        guard wlaczony, czyZwykleOkno(element) else { return }
        switch powiadomienie {
        case kAXWindowCreatedNotification:
            zastosuj(do: element)
            zarejestrujZmianeRozmiaru(element)
            opiszStan()
        case kAXWindowResizedNotification, kAXResizedNotification:
            zapamietaj(z: element)
        default:
            break
        }
    }

    /// Część okien zgłasza zmianę rozmiaru sama, a nie przez element aplikacji —
    /// dlatego dokładamy nasłuch również na samym oknie.
    private func zarejestrujZmianeRozmiaru(_ okno: AXUIElement) {
        guard let obserwator else { return }
        AXObserverAddNotification(
            obserwator, okno, kAXResizedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    // MARK: - Odczyt atrybutów

    private func okna(_ aplikacja: AXUIElement) -> [AXUIElement] {
        var wartosc: CFTypeRef?
        guard AXUIElementCopyAttributeValue(aplikacja, kAXWindowsAttribute as CFString, &wartosc) == .success
        else { return [] }
        return wartosc as? [AXUIElement] ?? []
    }

    /// Zwykłe okno przeglądania, a nie pulpit, panel „Informacje" czy pasek postępu.
    private func czyZwykleOkno(_ element: AXUIElement) -> Bool {
        tekst(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    private func tekst(_ element: AXUIElement, _ atrybut: String) -> String? {
        var wartosc: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, atrybut as CFString, &wartosc) == .success
        else { return nil }
        return wartosc as? String
    }

    /// Folder okna: najpierw tani `AXDocument` (gdyby Apple kiedyś go dołożyło),
    /// potem pasek okruszków — patrz [`folderZListyUrl`].
    private func sciezkaFolderu(_ okno: AXUIElement) -> String? {
        if let zDokumentu = Self.kluczFolderu(tekst(okno, kAXDocumentAttribute)) { return zDokumentu }
        return folderZDrzewa(okno, tytulOkna: tekst(okno, kAXTitleAttribute), glebokosc: 0)
    }

    /// Głębokość wystarczająca na `okno → AXSplitGroup → AXSplitGroup → AXList`
    /// (zmierzone: okruszki siedzą na czwartym poziomie), z zapasem jednego piętra.
    private static let maksGlebokoscSzukania = 5

    private func folderZDrzewa(_ element: AXUIElement, tytulOkna: String?, glebokosc: Int) -> String? {
        guard glebokosc <= Self.maksGlebokoscSzukania else { return nil }
        if tekst(element, kAXRoleAttribute) == "AXList" {
            let okruszki: [(nazwa: String, adres: URL)] = dzieci(element).compactMap { element in
                guard let adres = adres(element),
                      let nazwa = tekst(element, kAXValueAttribute) ?? tekst(element, kAXTitleAttribute)
                else { return nil }
                return (nazwa, adres)
            }
            if let folder = Self.folderZOkruszkow(okruszki, tytulOkna: tytulOkna) { return folder }
        }
        for dziecko in dzieci(element) {
            if let folder = folderZDrzewa(dziecko, tytulOkna: tytulOkna, glebokosc: glebokosc + 1) {
                return folder
            }
        }
        return nil
    }

    private func dzieci(_ element: AXUIElement) -> [AXUIElement] {
        var wartosc: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &wartosc) == .success
        else { return [] }
        return wartosc as? [AXUIElement] ?? []
    }

    private func adres(_ element: AXUIElement) -> URL? {
        var wartosc: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &wartosc) == .success
        else { return nil }
        return wartosc as? URL
    }

    private func rozmiar(_ okno: AXUIElement) -> CGSize? {
        var wartosc: CFTypeRef?
        guard AXUIElementCopyAttributeValue(okno, kAXSizeAttribute as CFString, &wartosc) == .success,
              let wartosc, CFGetTypeID(wartosc) == AXValueGetTypeID()
        else { return nil }
        var rozmiar = CGSize.zero
        guard AXValueGetValue(wartosc as! AXValue, .cgSize, &rozmiar) else { return nil }
        return rozmiar
    }

    private func opiszStan() {
        guard zgodaJest else {
            opisStanu = String(localized: "No Accessibility permission — the module does nothing.")
            return
        }
        guard let finder = aplikacjaFindera ?? zbudujElementFindera() else {
            opisStanu = String(localized: "Finder is not running.")
            return
        }
        let wszystkie = okna(finder).filter { czyZwykleOkno($0) }
        let zFolderem = wszystkie.filter { sciezkaFolderu($0) != nil }
        opisStanu = String(
            localized: "Finder: \(wszystkie.count) windows, \(zFolderem.count) recognised by folder, \(ileZapamietanychFolderow) remembered."
        )
    }
}
