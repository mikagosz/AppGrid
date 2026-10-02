import AppKit
import Combine
import Darwin
import ServiceManagement

/// Uruchamianie AppGrid przy logowaniu — zamówienie [U] 2026-10-03.
///
/// Stanu **nie trzymamy** w `UserDefaults`: prawdę zna system (Ustawienia systemowe →
/// Ogólne → Rzeczy otwierane przy logowaniu), a [U] może tam przełącznik zdjąć sam.
/// Własna kopia w defaults rozjechałaby się z systemem przy pierwszej takiej zmianie,
/// więc za każdym razem pytamy `SMAppService` o bieżący stan.
@MainActor
final class StartPrzyLogowaniu: ObservableObject {

    static let shared = StartPrzyLogowaniu()

    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    /// Ostatni błąd rejestracji, do pokazania pod przełącznikiem.
    @Published private(set) var blad: String?

    private init() {}

    /// `.requiresApproval` też liczymy jako „włączone": wpis jest zarejestrowany,
    /// brakuje tylko zgody w Ustawieniach systemowych — przełącznik ma wtedy stać
    /// na „tak", a pod nim ma wisieć podpowiedź, gdzie kliknąć.
    var wlaczone: Bool { status == .enabled || status == .requiresApproval }

    var czekaNaZgode: Bool { status == .requiresApproval }

    func odswiez() {
        status = SMAppService.mainApp.status
    }

    func ustaw(_ wlacz: Bool) {
        blad = nil
        do {
            if wlacz {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            blad = error.localizedDescription
        }
        odswiez()
    }

    func otworzUstawieniaSystemowe() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Ciche startowanie

    /// Czy ten start to start z logowania — wtedy okno ma się **nie** pokazać.
    ///
    /// Zamówienie [U] 2026-10-03: po zalogowaniu AppGrid ma czekać w tle na skrót, róg
    /// albo klik w Dock, a nie wyskakiwać na ekran. Wzór wzięty z ColorMyFolder 0.1.17,
    /// gdzie zmierzono oba haczyki niżej:
    ///
    /// 1. Zdarzenie `oapp` od systemu niesie znacznik `keyAELaunchedAsLogInItem` — ale
    ///    macOS 27 otwiera rzeczy przy logowaniu **bez** tego znacznika, czasem w ogóle
    ///    bez zdarzenia. Czytane w `applicationWillFinishLaunching`, bo tam
    ///    `currentAppleEvent` to jeszcze `oapp`.
    /// 2. Dlatego zapas: start w ciągu trzech minut od zalogowania na konsoli (`utmpx`)
    ///    też liczy się jako start z logowania. Ręczne odpalenie w tym oknie czasowym da
    ///    cichy start — wtedy wystarczy klik w Dock.
    static func uruchomionoPrzyLogowaniu(start: Date) -> Bool {
        let zdarzenie = NSAppleEventManager.shared().currentAppleEvent
        if zdarzenie?.eventID == AEEventID(kAEOpenApplication),
           zdarzenie?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        return startTuzPoZalogowaniu(start: start, zalogowano: czasLogowaniaNaKonsoli())
    }

    nonisolated static let oknoPoZalogowaniu: TimeInterval = 180

    nonisolated static func startTuzPoZalogowaniu(start: Date, zalogowano: Date?) -> Bool {
        guard let zalogowano else { return false }
        let minelo = start.timeIntervalSince(zalogowano)
        return minelo >= 0 && minelo < oknoPoZalogowaniu
    }

    /// Po starcie z logowania system potrafi chwilę później sam przysłać „reopen" —
    /// jak klik w Dock. Przez pierwsze pół minuty go ignorujemy; klik [U] po tym czasie
    /// otwiera okno normalnie. Zmierzone w ColorMyFolder 0.1.17.
    nonisolated static let ciszaPoStarcie: TimeInterval = 30

    nonisolated static func reopenOdSystemu(startZLogowania: Bool, odStartu: TimeInterval) -> Bool {
        startZLogowania && odStartu < ciszaPoStarcie
    }

    /// Chwila zalogowania bieżącego użytkownika na konsoli — najświeższy wpis `utmpx`.
    private static func czasLogowaniaNaKonsoli() -> Date? {
        let ja = NSUserName()
        var najnowszy: Date?
        setutxent()
        defer { endutxent() }
        while let wpis = getutxent() {
            guard wpis.pointee.ut_type == USER_PROCESS else { continue }
            let uzytkownik = withUnsafeBytes(of: wpis.pointee.ut_user) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let linia = withUnsafeBytes(of: wpis.pointee.ut_line) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            guard uzytkownik == ja, linia == "console" else { continue }
            let tv = wpis.pointee.ut_tv
            let data = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
            if najnowszy.map({ data > $0 }) ?? true { najnowszy = data }
        }
        return najnowszy
    }
}
