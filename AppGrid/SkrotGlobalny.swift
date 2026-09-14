import AppKit
import Carbon.HIToolbox

/// Akcja skrótu. Ustawiana i czytana wyłącznie na głównym wątku — uchwyt Carbona
/// jest zwykłym wskaźnikiem na funkcję C i nie potrafi nic domknąć.
nonisolated(unsafe) private var akcjaSkrotu: (() -> Void)?

/// Globalny skrót klawiszowy przez Carbon `RegisterEventHotKey`.
///
/// Zmierzone 2026-08-20: rejestracja zwraca `noErr` przy `AXIsProcessTrusted() == false`,
/// czyli **bez zgody na Dostępność**. Druga droga — `NSEvent.addGlobalMonitorForEvents`
/// na zdarzeniach klawiatury — tej zgody wymaga, więc jest tu niepotrzebna.
@MainActor
final class SkrotGlobalny: ObservableObject {

    /// `false`, gdy kombinacja jest zajęta przez inny program — okno ustawień to pokazuje.
    @Published private(set) var zarejestrowany = true

    private var uchwyt: EventHotKeyRef?
    private var obsluga: EventHandlerRef?

    /// `'AGRD'` — własny podpis, żeby nie mylić się z cudzymi skrótami.
    private static let podpis: OSType = 0x41475244

    /// Rejestruje skrót. Zwraca `false`, gdy kombinacja jest już zajęta przez inny program.
    @discardableResult
    func zarejestruj(klawisz: Int, modyfikatory: NSEvent.ModifierFlags, akcja: @escaping () -> Void) -> Bool {
        wyrejestruj()
        akcjaSkrotu = akcja
        zainstalujObsluge()

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(klawisz),
            Self.carbonModyfikatory(modyfikatory),
            EventHotKeyID(signature: Self.podpis, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            zarejestrowany = false
            return false
        }
        uchwyt = ref
        zarejestrowany = true
        return true
    }

    func wyrejestruj() {
        if let uchwyt {
            UnregisterEventHotKey(uchwyt)
            self.uchwyt = nil
        }
    }

    /// Obsługa zdarzenia instaluje się raz na proces i zostaje do końca.
    private func zainstalujObsluge() {
        guard obsluga == nil else { return }
        var typ = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                // Carbon woła nas na głównym wątku, ale przeskok przez kolejkę
                // zdejmuje wywołanie ze stosu obsługi zdarzenia systemowego.
                DispatchQueue.main.async { akcjaSkrotu?() }
                return noErr
            },
            1,
            &typ,
            nil,
            &obsluga
        )
    }

    // MARK: - Przeliczanie modyfikatorów i opis dla oka

    nonisolated static func carbonModyfikatory(_ flagi: NSEvent.ModifierFlags) -> UInt32 {
        var wynik: UInt32 = 0
        if flagi.contains(.command) { wynik |= UInt32(cmdKey) }
        if flagi.contains(.option)  { wynik |= UInt32(optionKey) }
        if flagi.contains(.control) { wynik |= UInt32(controlKey) }
        if flagi.contains(.shift)   { wynik |= UInt32(shiftKey) }
        return wynik
    }

    /// `⌃⌥⌘A` — kolejność znaków jak w menu systemowych.
    nonisolated static func opis(klawisz: Int, modyfikatory: NSEvent.ModifierFlags) -> String {
        var tekst = ""
        if modyfikatory.contains(.control) { tekst += "⌃" }
        if modyfikatory.contains(.option)  { tekst += "⌥" }
        if modyfikatory.contains(.shift)   { tekst += "⇧" }
        if modyfikatory.contains(.command) { tekst += "⌘" }
        return tekst + nazwaKlawisza(klawisz)
    }

    /// Nazwa klawisza — najpierw klawisze bez znaku, potem znak z **bieżącego układu
    /// klawiatury**, żeby opis zgadzał się z tym, co [U] ma wymalowane na klawiszu.
    nonisolated static func nazwaKlawisza(_ kod: Int) -> String {
        if let stala = klawiszeBezZnaku[kod] { return stala }
        if let znak = znakZUkladu(kod) { return znak.uppercased() }
        return "#\(kod)"
    }

    private nonisolated static let klawiszeBezZnaku: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Pyta system, jaki znak siedzi pod kodem klawisza w aktywnym układzie.
    private nonisolated static func znakZUkladu(_ kod: Int) -> String? {
        guard let zrodlo = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let wskaznik = TISGetInputSourceProperty(zrodlo, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let dane = Unmanaged<CFData>.fromOpaque(wskaznik).takeUnretainedValue() as Data

        return dane.withUnsafeBytes { bufor -> String? in
            guard let uklad = bufor.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return nil }
            var martwyKlawisz: UInt32 = 0
            var dlugosc = 0
            var znaki = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                uklad,
                UInt16(kod),
                UInt16(kUCKeyActionDisplay),
                0,                                  // bez modyfikatorów: goła litera
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &martwyKlawisz,
                znaki.count,
                &dlugosc,
                &znaki
            )
            guard status == noErr, dlugosc > 0 else { return nil }
            return String(utf16CodeUnits: znaki, count: dlugosc)
        }
    }
}
