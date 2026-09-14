import AppKit
import CoreGraphics

/// Czy na wierzchu stoi coś, co zajmuje cały ekran — gra albo film.
///
/// Służy „trybowi gry": aktywny róg ma wtedy milczeć, żeby przypadkowy zjazd kursorem
/// w narożnik nie schował pełnoekranowego okna cudzym oknem AppGrida.
enum PelnyEkran {

    /// Zwykłe okna programów siedzą na warstwie 0.
    ///
    /// 🔴 Zmierzone 2026-08-22: **Dock zgłasza okno o rozmiarze całego ekranu**
    /// (3200×1800 przy ekranie 3200×1800), tylko na warstwie 20; Window Server siedzi
    /// na 24. Bez tego filtru sito byłoby zawsze prawdziwe i róg nie odpaliłby nigdy.
    nonisolated static let warstwaZwyklychOkien = 0

    /// Ile punktów luzu na każdym boku jeszcze uznajemy za „cały ekran".
    nonisolated static let tolerancja: CGFloat = 2

    /// Czy program z pierwszego planu zakrywa wskazany ekran.
    ///
    /// Zmierzone 2026-08-22 z paczki **bez** zgody na Nagrywanie ekranu
    /// (`CGPreflightScreenCaptureAccess() == false`, 7 cudzych okien jako kontrola
    /// dodatnia): ramki i nazwy programów przychodzą dla wszystkich 7 okien, redagowany
    /// jest wyłącznie **tytuł** okna — 1 z 7. Tytułu tutaj nie potrzebujemy, więc ta
    /// ścieżka nie prosi [U] o żadną nową zgodę.
    static func naWierzchu(ekran: CGRect) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        return zakrywa(okna: oknaProgramu(pid: pid), ekran: ekran)
    }

    /// Ramki okien jednego programu, przeliczone już na układ Cocoa.
    static func oknaProgramu(pid: pid_t) -> [(ramka: CGRect, warstwa: Int)] {
        guard let lista = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // Układ Quartza ma początek w lewym GÓRNYM rogu ekranu głównego, a `NSScreen.frame`
        // i `NSEvent.mouseLocation` w lewym DOLNYM. Bez przeliczenia porównanie ramek
        // rozjechałoby się na każdym zestawie z więcej niż jednym ekranem.
        let wysokoscGlownego = NSScreen.screens.first?.frame.height ?? 0

        return lista.compactMap { okno in
            guard (okno[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let warstwa = okno[kCGWindowLayer as String] as? Int,
                  let slownik = okno[kCGWindowBounds as String] as? [String: CGFloat],
                  let ramka = CGRect(dictionaryRepresentation: slownik as CFDictionary)
            else { return nil }
            return (naUkladCocoa(ramka, wysokoscEkranuGlownego: wysokoscGlownego), warstwa)
        }
    }

    // MARK: - Logika bez okien (sprawdzana headless)

    /// Przelicza ramkę z układu Quartza na układ Cocoa.
    nonisolated static func naUkladCocoa(_ ramka: CGRect, wysokoscEkranuGlownego: CGFloat) -> CGRect {
        CGRect(
            x: ramka.minX,
            y: wysokoscEkranuGlownego - ramka.maxY,
            width: ramka.width,
            height: ramka.height
        )
    }

    /// Czy któreś ze zwykłych okien przykrywa cały ekran.
    ///
    /// Ramki przychodzą tu **już w układzie Cocoa**, w tym samym co `ekran`.
    nonisolated static func zakrywa(okna: [(ramka: CGRect, warstwa: Int)], ekran: CGRect) -> Bool {
        let cel = ekran.insetBy(dx: tolerancja, dy: tolerancja)
        return okna.contains { okno in
            okno.warstwa == warstwaZwyklychOkien && okno.ramka.contains(cel)
        }
    }
}
