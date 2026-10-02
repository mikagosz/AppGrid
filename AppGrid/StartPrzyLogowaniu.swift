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
    /// albo klik w Dock, a nie wyskakiwać na ekran. Dwie drogi, bo żadna osobno nie jest
    /// pewna:
    ///
    /// 1. Zdarzenie `oapp` od systemu niesie znacznik `keyAELaunchedAsLogInItem` — tak
    ///    rzeczy otwierane przy logowaniu zgłaszały się zawsze. Czytane w
    ///    `applicationDidFinishLaunching`, bo tylko wtedy `currentAppleEvent` to `oapp`.
    /// 2. Zapas na wypadek, gdyby znacznika nie było: wpis przy logowaniu jest włączony,
    ///    a od zalogowania na konsoli (`utmpx`) minęło mniej niż dwie minuty. Ręczne
    ///    odpalenie w tym oknie czasowym też da cichy start — wtedy wystarczy klik w Dock.
    static func uruchomionoPrzyLogowaniu() -> Bool {
        if let zdarzenie = NSAppleEventManager.shared().currentAppleEvent,
           zdarzenie.eventID == kAEOpenApplication,
           zdarzenie.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        guard SMAppService.mainApp.status == .enabled,
              let zalogowano = czasLogowaniaNaKonsoli() else { return false }
        return Date().timeIntervalSince(zalogowano) < 120
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
