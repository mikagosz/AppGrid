import AppKit
import Combine
import SwiftUI

@main
enum AppGridMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        _ = delegate            // delegat musi przeżyć uruchomienie pętli zdarzeń
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Uchwyt dla mostu diagnostycznego — most jest typem bez egzemplarza i nie ma
    /// innej drogi do modelu. Tylko odczyt i tylko w DEBUG (`AppGridBridge`).
    private(set) static weak var aktywny: AppDelegate?
    static var aktywnyModel: AppGridModel? { aktywny?.model }
    static var oknoWidoczne: Bool { aktywny?.window?.isVisible ?? false }

    fileprivate let model = AppGridModel()
    private let ustawienia = Ustawienia.shared
    private let skrot = SkrotGlobalny()
    private let aktywnyRog = AktywnyRog()
    private let oknaFindera = OknaFindera()

    private var window: NSWindow?
    private var oknoUstawien: NSWindow?
    private var tlo: TloOkna?
    private var subskrypcja: AnyCancellable?
    private var monitorKlawiszy: Any?

    /// Zaokrąglenie narożników okna — wyraźnie większe niż systemowe.
    private static let promienNaroznika: CGFloat = 22

    /// Nazwa, pod którą AppKit sam zapisuje ramkę okna głównego.
    private static let autosaveGlowne = "AppGridMainWindow"

    /// Najniższa wysokość okna. Szerokość granicy nie ma — tę ustawia [U] w ustawieniach.
    private static let minimalnaWysokosc: CGFloat = 320

    /// Ostatnio wgrany stan wywołania. Bez tego każde drgnięcie suwaka w ustawieniach
    /// przerejestrowywałoby skrót i przestawiało okna Findera.
    private var wgrane: StanWywolania?

    private struct StanWywolania: Equatable {
        var skrotWlaczony: Bool
        var klawisz: Int
        var modyfikatory: Int
        var rogWlaczony: Bool
        var rog: Int
        var rogGamemode: Bool
        var finderWlaczony: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Most diagnostyczny — w RELEASE `start` jest pusty, a cały kod mostu
        // wycięty przez `#if DEBUG` po stronie `AppGridBridge`.
        Self.aktywny = self
        AppGridBridge.uruchom()
        wlaczKlawiature()
        zbudujMenu()
        model.reload()
        pokazOkno()

        zastosujUstawienia()
        // Zmiany z okna ustawień wchodzą od razu, bez przycisku „zastosuj".
        subskrypcja = ustawienia.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.zastosujUstawienia() }
        }
    }

    /// Klik w ikonę w Docku, gdy program już działa.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pokazOkno()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Ustawienia w locie

    private func zastosujUstawienia() {
        tlo?.krycie = ustawienia.krycieTla
        tlo?.needsDisplay = true
        // Poza porównaniem `wgrane` niżej: szerokość ma wejść od razu przy każdym
        // drgnięciu suwaka, a `zablokujSzerokosc` samo nic nie robi, gdy się zgadza.
        if let window { zablokujSzerokosc(okna: window) }

        let stan = StanWywolania(
            skrotWlaczony: ustawienia.skrotWlaczony,
            klawisz: ustawienia.skrotKlawisz,
            modyfikatory: ustawienia.skrotModyfikatory,
            rogWlaczony: ustawienia.rogWlaczony,
            rog: ustawienia.rog.rawValue,
            rogGamemode: ustawienia.rogGamemode,
            finderWlaczony: ustawienia.finderWlaczony
        )
        guard stan != wgrane else { return }
        wgrane = stan

        if stan.skrotWlaczony {
            skrot.zarejestruj(
                klawisz: stan.klawisz,
                modyfikatory: NSEvent.ModifierFlags(rawValue: UInt(stan.modyfikatory))
            ) { [weak self] in
                self?.przelaczOkno()
            }
        } else {
            skrot.wyrejestruj()
        }

        if stan.rogWlaczony {
            aktywnyRog.wlacz(rog: ustawienia.rog, gamemode: stan.rogGamemode) { [weak self] in
                self?.pokazOkno()
            }
        } else {
            aktywnyRog.wylacz()
        }

        if stan.finderWlaczony {
            oknaFindera.wlacz()
        } else {
            oknaFindera.wylacz()
        }
    }

    // MARK: - Klawiatura

    /// Esc chowa okno, strzałki chodzą po ikonach, Enter uruchamia wskazaną.
    ///
    /// 🔴 Lokalny monitor zdarzeń, a nie `onKeyPress` w SwiftUI: szukajka dostaje
    /// ognisko przy **każdym** pokazaniu okna (`AppGridView.onAppear`), a pole tekstowe
    /// zjada strzałki na przesuwanie kursora, zanim dojdą one do widoku. Monitor
    /// ogląda zdarzenie wcześniej, więc strzałki działają bez klikania w siatkę.
    private func wlaczKlawiature() {
        guard monitorKlawiszy == nil else { return }
        monitorKlawiszy = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] zdarzenie in
            guard let self, let okno = self.window, okno.isVisible, okno.isKeyWindow else { return zdarzenie }
            // Skróty z modyfikatorem należą do systemu i do menu — ⌘← to nie jest
            // prośba o przejście na sąsiednią ikonę.
            let modyfikatory = zdarzenie.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modyfikatory.isDisjoint(with: [.command, .option, .control]) else { return zdarzenie }

            // Esc działa zawsze, także w trybie edycji: to jest wyjście z okna,
            // a stan edycji i tak gaśnie przy następnym pokazaniu (`resetForShow`).
            if zdarzenie.keyCode == Klawisz.esc {
                okno.orderOut(nil)
                return nil
            }
            // W edycji strzałki i Enter należą do pól z nazwami belek.
            guard !self.model.trybEdycji else { return zdarzenie }

            switch zdarzenie.keyCode {
            case Klawisz.lewo:  self.model.przesunWybor(.lewo);  return nil
            case Klawisz.prawo: self.model.przesunWybor(.prawo); return nil
            case Klawisz.gora:  self.model.przesunWybor(.gora);  return nil
            case Klawisz.dol:   self.model.przesunWybor(.dol);   return nil
            case Klawisz.enter, Klawisz.enterNumeryczny:
                // Bez wskazanej ikony Enter zostaje polu tekstowemu — inaczej odpalałby
                // coś, czego [U] nie widzi jako zaznaczone.
                guard self.model.wybrany != nil else { return zdarzenie }
                self.model.uruchomWybrany()
                return nil
            default:
                return zdarzenie
            }
        }
    }

    /// Kody klawiszy z `NSEvent.keyCode` — te same na każdej klawiaturze,
    /// niezależnie od układu i języka.
    private enum Klawisz {
        static let enter: UInt16 = 36
        static let esc: UInt16 = 53
        static let enterNumeryczny: UInt16 = 76
        static let lewo: UInt16 = 123
        static let prawo: UInt16 = 124
        static let dol: UInt16 = 125
        static let gora: UInt16 = 126
    }

    // MARK: - Okno

    /// Skrót działa jak przełącznik: drugie naciśnięcie chowa okno.
    private func przelaczOkno() {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            pokazOkno()
        }
    }

    private func pokazOkno() {
        let okno = window ?? zbudujOkno()
        model.resetForShow()
        if ustawienia.oknoNaSrodku { wysrodkuj(okno) }
        okno.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Cieńszy pasek przewijania (AG-29). Po pokazaniu okna, bo dopiero wtedy
        // `NSHostingView` ma zbudowane drzewo z `NSScrollView` w środku; przy każdym
        // pokazaniu, bo SwiftUI może przebudować zawartość między jednym a drugim.
        DispatchQueue.main.async { [weak self] in
            guard let widok = self?.tlo else { return }
            PasekPrzewijania.zastosuj(w: widok)
            PasekPrzewijania.wypiszPomiar(korzen: widok)
        }
    }

    /// Okno przykotwiczone centralnie — zgłoszenie [U] 2026-09-05 (AG-25).
    ///
    /// Liczone przy **każdym** pokazaniu, nie raz przy budowie: okno wolno przesunąć
    /// za tło, a przy następnym wywołaniu ma i tak wyjść na środku. Ramki po tym nie
    /// zapisujemy — pamiętany zostaje rozmiar, nie pozycja.
    ///
    /// `NSWindow.center()` tutaj nie wystarcza z dwóch powodów — oba z dokumentacji
    /// AppKitu, nie z pomiaru: bierze ekran główny, a nie ten, na którym stoi kursor,
    /// i sadza okno **powyżej** środka. [U] prosił o środek.
    private func wysrodkuj(_ okno: NSWindow) {
        let mysz = NSEvent.mouseLocation
        let ekran = NSScreen.screens.first { $0.frame.contains(mysz) } ?? okno.screen ?? NSScreen.main
        guard let pole = ekran?.visibleFrame else { return }

        let ramka = okno.frame
        // Zaciśnięte do obszaru użytecznego: okno wyższe od ekranu ma zacząć się u góry,
        // a nie wyjechać paskiem menu w górę i szukajką poniżej dolnej krawędzi.
        let x = min(max(pole.midX - ramka.width / 2, pole.minX), max(pole.maxX - ramka.width, pole.minX))
        let y = min(max(pole.midY - ramka.height / 2, pole.minY), max(pole.maxY - ramka.height, pole.minY))
        okno.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func zbudujOkno() -> NSWindow {
        let okno = OknoBezPaska(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        okno.title = "AppGrid"
        okno.isReleasedWhenClosed = false
        // Pasek tytułu zniknął razem z trzema kropkami, więc okno trzeba dać się przesunąć
        // za tło. AppKit sam nie łapie przeciągnięcia zaczętego na przycisku czy polu,
        // więc kafelki i szukajka dalej działają normalnie.
        okno.isMovableByWindowBackground = true

        // Przezroczystość WYMUSZONA własną warstwą.
        //
        // Natywne rozmycie (NSVisualEffectView) respektuje przełącznik dostępności
        // „Zmniejsz przezroczystość", który [U] ma włączony — i wtedy tło wychodzi matowe.
        // Systemowe okno „Aplikacje" to ustawienie ignoruje, więc my też: rysujemy własne
        // półprzezroczyste tło, niezależne od stanu tego przełącznika.
        let tlo = TloOkna()
        tlo.promien = Self.promienNaroznika
        tlo.krycie = ustawienia.krycieTla
        self.tlo = tlo

        let zawartosc = NSHostingView(rootView: AppGridView(model: model))
        // Bez tego SwiftUI dokłada u góry margines na pasek tytułu — a to właśnie ten pusty
        // pas [U] kazał skasować. Pasek już nie istnieje, ale margines po nim by został.
        zawartosc.safeAreaRegions = []
        zawartosc.translatesAutoresizingMaskIntoConstraints = false
        tlo.addSubview(zawartosc)
        NSLayoutConstraint.activate([
            zawartosc.leadingAnchor.constraint(equalTo: tlo.leadingAnchor),
            zawartosc.trailingAnchor.constraint(equalTo: tlo.trailingAnchor),
            zawartosc.topAnchor.constraint(equalTo: tlo.topAnchor),
            zawartosc.bottomAnchor.constraint(equalTo: tlo.bottomAnchor),
        ])

        okno.contentView = tlo
        okno.isOpaque = false
        okno.backgroundColor = .clear

        // To jest cała naprawa irytanta „okno wraca do małego rozmiaru":
        // AppKit sam zapisuje ramkę przy każdej zmianie i przywraca ją przy starcie.
        // Przy pierwszym uruchomieniu zapisu jeszcze nie ma — wtedy narzucamy własny
        // rozmiar, bo inaczej widok rozciąga okno na niemal całą wysokość ekranu.
        let autosave = Self.autosaveGlowne
        let bylZapis = UserDefaults.standard.object(forKey: "NSWindow Frame \(autosave)") != nil
        okno.setFrameAutosaveName(autosave)
        if !bylZapis {
            okno.setContentSize(NSSize(width: CGFloat(ustawienia.szerokoscOkna), height: 620))
            okno.center()
        }
        zablokujSzerokosc(okna: okno)

        // Klik gdziekolwiek poza oknem = okno znika. Ramka zostaje zapisana, bo
        // `orderOut` tylko chowa okno, nie niszczy go.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: okno,
            queue: .main
        ) { [weak okno] _ in
            // `queue: .main` — obsługa i tak biegnie na głównym wątku; Swift 6 chce to jawnie.
            MainActor.assumeIsolated { okno?.orderOut(nil) }
        }

        window = okno
        return okno
    }

    /// Zablokowana szerokość okna — decyzja [U] 2026-08-23 (AG-22).
    ///
    /// Równe `contentMinSize` i `contentMaxSize` w poziomie odbierają AppKitowi
    /// możliwość ciągnięcia za pionową krawędź; wysokość zostaje wolna. To jest
    /// świadomy odwrót po trzech rundach usterki „okno nie przeformatowuje się
    /// z dużego na małe": szerokość zmienia się teraz **skokiem**, z jednej ustalonej
    /// wartości na drugą, a nie płynnie pod kursorem.
    ///
    /// 🔴 Kolejność ma znaczenie: starą granicę trzeba zdjąć **przed** zmianą ramki,
    /// bo inaczej `setFrame` przytnie się do poprzedniej szerokości i nowa wartość
    /// z ustawień nigdy nie wejdzie.
    private func zablokujSzerokosc(okna okno: NSWindow) {
        let szerokosc = CGFloat(ustawienia.szerokoscOkna)

        okno.contentMinSize = NSSize(width: 0, height: Self.minimalnaWysokosc)
        okno.contentMaxSize = NSSize(width: Self.bezGranicy, height: Self.bezGranicy)

        if abs(okno.frame.width - szerokosc) > 0.5 {
            var ramka = okno.frame
            ramka.size.width = szerokosc
            okno.setFrame(ramka, display: true)
            // Ramkę zapisujemy sami: `orderOut` przy chowaniu okna nie jest zmianą
            // rozmiaru, więc AppKit nie miałby przy czym zapisać nowej szerokości.
            okno.saveFrame(usingName: Self.autosaveGlowne)
        }

        okno.contentMinSize = NSSize(width: szerokosc, height: Self.minimalnaWysokosc)
        okno.contentMaxSize = NSSize(width: szerokosc, height: Self.bezGranicy)
    }

    /// „Bez ograniczenia" dla AppKitu. Nie `.greatestFiniteMagnitude` — ta w kilku
    /// miejscach AppKitu wchodzi w mnożenie i wychodzi z niego jako `inf`.
    private static let bezGranicy: CGFloat = 100_000

    // MARK: - Okno ustawień

    @objc private func pokazUstawienia() {
        if let oknoUstawien {
            oknoUstawien.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let widok = UstawieniaView(ustawienia: ustawienia, skrot: skrot, finder: oknaFindera)
        let okno = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            // `.resizable` doszło razem z sekcjami „Ukryte programy" i „Separatory":
            // bez niego okna nie dało się rozciągnąć i lista ukrytych chowała się
            // w przewijaniu formularza, a T-2 z kolejki nie miał jak przejść.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        okno.title = String(localized: "AppGrid Settings")
        okno.contentView = NSHostingView(rootView: widok)
        okno.isReleasedWhenClosed = false
        // Osobna nazwa zapisu = osobna pamięć ramki. Główne okno i to nie mieszają
        // sobie rozmiarów, mimo że oba korzystają z tego samego mechanizmu AppKitu.
        okno.setFrameAutosaveName("AppGridUstawienia")
        okno.center()
        okno.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        oknoUstawien = okno
    }

    // MARK: - Menu

    /// Bez menu program nie ma nawet Cmd+Q ani Cmd+W.
    private func zbudujMenu() {
        let glowne = NSMenu()

        let pozycjaApp = NSMenuItem()
        let menuApp = NSMenu()
        menuApp.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(pokazUstawienia),
            keyEquivalent: ","
        ).target = self
        menuApp.addItem(.separator())
        menuApp.addItem(
            withTitle: String(localized: "Refresh list"),
            action: #selector(odswiez),
            keyEquivalent: "r"
        ).target = self
        menuApp.addItem(.separator())
        menuApp.addItem(
            withTitle: String(localized: "Hide AppGrid"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        menuApp.addItem(
            withTitle: String(localized: "Quit AppGrid"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        pozycjaApp.submenu = menuApp
        glowne.addItem(pozycjaApp)

        let pozycjaOkno = NSMenuItem()
        let menuOkno = NSMenu(title: String(localized: "Window"))
        // `performClose:` na oknie bez przycisku zamykania tylko piszczy. Program i tak
        // okna nie zamyka, tylko je chowa — tak działa skrót globalny i klik obok.
        menuOkno.addItem(
            withTitle: String(localized: "Close window"),
            action: #selector(schowajOkno),
            keyEquivalent: "w"
        ).target = self
        pozycjaOkno.submenu = menuOkno
        glowne.addItem(pozycjaOkno)

        NSApp.mainMenu = glowne
    }

    @objc private func odswiez() {
        model.reload()
    }

    @objc private func schowajOkno() {
        if let oknoUstawien, oknoUstawien.isKeyWindow {
            oknoUstawien.performClose(nil)
            return
        }
        window?.orderOut(nil)
    }
}

/// Okno bez paska tytułu.
///
/// `.borderless` samo z siebie **nie przyjmuje ognia klawiatury** — bez tych dwóch nadpisań
/// szukajka nigdy by się nie zafokusowała, a obserwator `didResignKey` nie miałby czego
/// obserwować, więc okno przestałoby się chować po kliknięciu obok.
final class OknoBezPaska: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Tło okna: półprzezroczysta, zaokrąglona płyta.
///
/// Rysowana ręcznie, bo natywne rozmycie znika przy włączonym „Zmniejsz przezroczystość".
final class TloOkna: NSView {

    var promien: CGFloat = 22
    var krycie: CGFloat = 0.95

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nieużywane") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        // Kolor bierzemy z bieżącego wyglądu, żeby tło szło za motywem jasny/ciemny.
        var tlo = NSColor.windowBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tlo = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)
                ?? NSColor.windowBackgroundColor
        }
        layer.backgroundColor = tlo.withAlphaComponent(krycie).cgColor
        layer.cornerRadius = promien
        layer.masksToBounds = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
