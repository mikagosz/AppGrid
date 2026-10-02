import Combine
import Foundation
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
}
