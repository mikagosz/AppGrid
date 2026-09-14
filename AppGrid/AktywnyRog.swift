import AppKit

/// Wywołanie okna przez dojechanie kursorem do rogu ekranu.
///
/// Systemowe „aktywne rogi" (`com.apple.dock`, klucze `wvous-*`) umieją odpalić wyłącznie
/// czynność systemu — dowolnego programu nie uruchomią. Stąd własny mechanizm.
@MainActor
final class AktywnyRog {

    /// Bok kwadratu w narożniku, który uzbraja wywołanie.
    nonisolated static let bokStrefy: CGFloat = 5
    /// Dopóki kursor nie wyjedzie poza ten kwadrat, drugie wywołanie się nie odpali.
    /// Bez tego okno migałoby przy każdym drgnięciu myszy w rogu.
    nonisolated static let bokRozbrojenia: CGFloat = 60

    private var zegar: Timer?
    private var uzbrojony = true

    // SKRÓT: odpytywanie pozycji myszy co 0,2 s zamiast nasłuchu zdarzeń.
    // Sufit: reakcja opóźniona najwyżej o jeden takt, 5 sprawdzeń pozycji na sekundę.
    // Droga wyjścia: NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) — ale
    // najpierw trzeba zmierzyć, czy w tej wersji macOS działa bez zgody na Dostępność.
    // Zegar nie wymaga żadnej zgody, więc nie wciąga [U] w klikanie w Ustawieniach.
    private static let taktSekundy: TimeInterval = 0.2

    func wlacz(rog: RogEkranu, gamemode: Bool, akcja: @escaping () -> Void) {
        wylacz()
        uzbrojony = true
        zegar = Timer.scheduledTimer(withTimeInterval: Self.taktSekundy, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.takt(rog: rog, gamemode: gamemode, akcja: akcja)
            }
        }
    }

    func wylacz() {
        zegar?.invalidate()
        zegar = nil
    }

    private func takt(rog: RogEkranu, gamemode: Bool, akcja: @escaping () -> Void) {
        let punkt = NSEvent.mouseLocation
        let ekran = (NSScreen.screens.first { $0.frame.contains(punkt) } ?? NSScreen.main)?.frame
        guard let ekran else { return }

        let wynik = Self.krok(punkt: punkt, ekran: ekran, rog: rog, uzbrojony: uzbrojony)
        uzbrojony = wynik.uzbrojony
        guard wynik.odpal else { return }

        // Tryb gry połyka wywołanie, ale maszyna uzbrojenia i tak zrobiła swój krok —
        // dzięki temu po wyjściu z pełnego ekranu okno nie wyskakuje dlatego, że kursor
        // przez cały ten czas stał w rogu. Musi z niego najpierw wyjechać.
        if gamemode, PelnyEkran.naWierzchu(ekran: ekran) { return }

        akcja()
    }

    // MARK: - Logika bez okien (sprawdzana headless)

    /// Czy punkt leży w kwadracie o boku `bok` przy wskazanym rogu ekranu.
    ///
    /// Układ współrzędnych jest ten sam co w `NSEvent.mouseLocation` i `NSScreen.frame`:
    /// początek w **lewym dolnym** rogu ekranu głównego, oś Y rośnie do góry.
    nonisolated static func wStrefie(punkt: CGPoint, ekran: CGRect, rog: RogEkranu, bok: CGFloat) -> Bool {
        let poLewej  = punkt.x <= ekran.minX + bok
        let poPrawej = punkt.x >= ekran.maxX - bok
        let uGory    = punkt.y >= ekran.maxY - bok
        let uDolu    = punkt.y <= ekran.minY + bok

        // Punkt spoza ekranu nie należy do żadnej strefy.
        guard ekran.insetBy(dx: -1, dy: -1).contains(punkt) else { return false }

        switch rog {
        case .lewyGorny:  return poLewej && uGory
        case .prawyGorny: return poPrawej && uGory
        case .lewyDolny:  return poLewej && uDolu
        case .prawyDolny: return poPrawej && uDolu
        }
    }

    /// Jeden takt maszyny stanów: odpalamy przy **wjechaniu** w róg, a nie przez cały czas
    /// postoju w nim. Ponowne uzbrojenie dopiero po wyjeździe poza większy kwadrat.
    nonisolated static func krok(
        punkt: CGPoint,
        ekran: CGRect,
        rog: RogEkranu,
        uzbrojony: Bool
    ) -> (uzbrojony: Bool, odpal: Bool) {
        if uzbrojony, wStrefie(punkt: punkt, ekran: ekran, rog: rog, bok: bokStrefy) {
            return (false, true)
        }
        if !wStrefie(punkt: punkt, ekran: ekran, rog: rog, bok: bokRozbrojenia) {
            return (true, false)
        }
        return (uzbrojony, false)
    }
}
