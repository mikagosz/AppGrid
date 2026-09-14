//
//  AppGridBridge.swift
//  AppGrid
//
//  Podłączenie do AppBridge — pozwala odczytać stan działającego AppGrida
//  zamiast wnioskować z zrzutu ekranu i z `defaults read`.
//
//  Wariant jednoplikowy: `AppBridgeKit.swift` leży obok, w module gospodarza,
//  więc **nie ma `import AppBridgeKit`**.
//
//  Cały plik jest pod `#if DEBUG`. Bez tego opisy endpointów zostają w binarce
//  wydania jako zwykły tekst, nawet gdy serwer śpi — zmierzone na CWMac 2026-08-09.
//

import AppKit
import Foundation

enum AppGridBridge {

    /// Port AppGrida. Każdy gospodarz mostu ma własny, żeby dwa programy uruchomione
    /// naraz nie biły się o to samo gniazdo.
    private static let port: UInt16 = 8777

    @MainActor
    static func uruchom() {
        #if DEBUG
        BridgeServer.start(port: port, appName: "appgrid")
        zarejestruj()
        #endif
    }

    // Wszystkie endpointy są WYŁĄCZNIE odczytem.
    //
    // AppGrid uruchamia cudze programy, przestawia rozmiary okien Findera i zmienia
    // ustawienia systemowego Docka. Żadna z tych rzeczy nie jest tu wystawiona
    // i nie ma być dopisana bez osobnej decyzji [U]: most jest diagnostyką,
    // nie pilotem do cudzego komputera.

    #if DEBUG
    /// `@MainActor`, bo `Ustawienia.shared` należy do głównego aktora — bez tego
    /// Swift 6 zamienia dzisiejsze ostrzeżenie w błąd kompilacji.
    @MainActor
    private static func zarejestruj() {
        let R = BridgeRegistry.shared
        let u = Ustawienia.shared

        R.registerOnMainActor(
            method: "GET", path: "/status",
            description: "Przegląd: wersja programu, rezerwacja pasa u dołu, stan systemowego Docka"
        ) { _ in
            .json([
                "wersja": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                "rezerwacjaDolna": rezerwacjaDolna(),
                "dockKafelek": kafelekDocka(),
                "dockAutohide": autohideDocka(),
            ])
        }

        R.registerOnMainActor(
            method: "GET", path: "/wybor",
            description: "Chodzenie strzałkami: wskazana ikona, liczba kolumn, długość listy"
        ) { _ in
            let model = AppDelegate.aktywnyModel
            let lista = model?.kolejnoscNawigacji ?? []
            let wybrany = model?.wybrany
            // Kolejność czytania — ta sama, po której chodzą strzałki.
            let mapa = (model?.mapaNawigacji ?? []).sorted {
                $0.ramka.minY == $1.ramka.minY ? $0.ramka.minX < $1.ramka.minX
                                               : $0.ramka.minY < $1.ramka.minY
            }
            let ramka = mapa.first { $0.id == wybrany }?.ramka
            return .json([
                "wybrany": wybrany ?? "",
                "nazwaWybranej": lista.first { $0.id == wybrany }?.name ?? "",
                "indeksWybranej": mapa.firstIndex { $0.id == wybrany } ?? -1,
                "x": ramka.map { Double($0.minX) } ?? -1,
                "y": ramka.map { Double($0.minY) } ?? -1,
                "ikon": mapa.count,
                "kolumnWRzedzie": model?.kolumnWRzedzie ?? 0,
                "oknoWidoczne": AppDelegate.oknoWidoczne,
            ])
        }

        R.registerOnMainActor(
            method: "GET", path: "/ekran",
            description: "Geometria ekranów: pełna ramka, obszar użyteczny i ile zabiera dół"
        ) { _ in
            .json([
                "ekrany": NSScreen.screens.map { ekran -> [String: Any] in
                    let f = ekran.frame, v = ekran.visibleFrame
                    return [
                        "frame": ["x": f.minX, "y": f.minY, "w": f.width, "h": f.height],
                        "visibleFrame": ["x": v.minX, "y": v.minY, "w": v.width, "h": v.height],
                        "zarezerwowaneDol": v.minY - f.minY,
                        "zarezerwowaneGora": f.maxY - v.maxY,
                        "glowny": ekran == NSScreen.main,
                    ]
                },
            ])
        }

        R.registerOnMainActor(
            method: "GET", path: "/ustawienia",
            description: "Ustawienia w jednym miejscu: skrót, róg, wygląd okna, okna Findera"
        ) { _ in
            .json([
                "skrotWlaczony": u.skrotWlaczony,
                "opisSkrotu": u.opisSkrotu,
                "rogWlaczony": u.rogWlaczony,
                "szerokoscOkna": u.szerokoscOkna,
                "krycieTla": u.krycieTla,
                "finderWlaczony": u.finderWlaczony,
                "finderTryb": u.finderTryb == .osobnoPerFolder ? "osobno per folder" : "jeden dla wszystkich",
                "finderSzerokosc": u.finderSzerokosc,
                "finderWysokosc": u.finderWysokosc,
                "finderUczySie": u.finderUczySie,
            ])
        }
    }

    // MARK: - Odczyty pomocnicze

    /// Ile punktów zabiera dziś dół ekranu. To jest liczba, przez którą przechodzi
    /// cały wariant rezerwacji — most oddaje ją wprost, żeby nie trzeba było
    /// wnioskować ze zrzutu ekranu.
    private static func rezerwacjaDolna() -> Double {
        guard let ekran = NSScreen.main else { return 0 }
        return ekran.visibleFrame.minY - ekran.frame.minY
    }

    private static func kafelekDocka() -> Int {
        CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? Int ?? 0
    }

    private static func autohideDocka() -> Bool {
        CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    }
    #endif
}
