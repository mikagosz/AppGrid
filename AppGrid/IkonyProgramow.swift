import AppKit

/// Ikony programów, wczytane raz i trzymane w pamięci.
///
/// 🔴 Zmierzone 2026-08-22: `NSWorkspace.icon(forFile:)` dla 83 programów kosztuje
/// **6,503 ms**, a wołanie stało w `body` kafelka — więc płaciliśmy je przy **każdym**
/// przerysowaniu siatki. Przy 60 klatkach na sekundę budżet klatki to 16,7 ms, czyli
/// same ikony zjadały 39% klatki. Dla porównania przeliczenie całego układu razem
/// z podglądem przeciągania: **0,054 ms** — sto dwadzieścia razy taniej.
///
/// To był prawdziwy powód lagów przy ciągnięciu belki. Układ był niewinny.
@MainActor
enum IkonyProgramow {

    private static var pamiec: [String: NSImage] = [:]

    static func ikona(_ sciezka: String) -> NSImage {
        if let gotowa = pamiec[sciezka] { return gotowa }
        let swieza = NSWorkspace.shared.icon(forFile: sciezka)
        pamiec[sciezka] = swieza
        return swieza
    }

    /// Odświeżenie listy (`⌘R`) ma odświeżyć też ikony — program mógł dostać nową.
    static func zapomnij() {
        pamiec.removeAll()
    }
}
