import AppKit

/// Cieńszy pasek przewijania — zgłoszenie [U] 2026-09-05 (AG-29): *„ma być 3x cieńszy
/// niż obecny"*.
///
/// [U] ma w systemie **„Zawsze pokazuj paski przewijania"**, więc pasek jest w stylu
/// `legacy` i zabiera szerokość w układzie: zmierzone
/// `NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)` = **17 pt**.
/// Stąd „3× cieńszy" liczymy z wartości systemowej, a nie wpisujemy 6 na sztywno —
/// gdy [U] przełączy styl albo Apple zmieni liczbę, proporcja zostaje.
final class CienkiScroller: NSScroller {

    /// Dzielnik z zamówienia [U]. Jedna liczba, żeby nie rozjechała się między
    /// szerokością paska a szerokością gałki.
    static let dzielnik: CGFloat = 3

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat {
        super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle) / dzielnik
    }

    /// Gałka rysowana sama, bo systemowa ma własne marginesy policzone dla 17 pt
    /// i w wąskim pasku zostaje z niej kreska przyklejona do krawędzi.
    override func drawKnob() {
        let r = rect(for: .knob).insetBy(dx: 1, dy: 1)
        guard r.width > 0, r.height > 0 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.width / 2, yRadius: r.width / 2).fill()
    }

    /// Tło paska: w `legacy` system rysuje wyraźną rynnę policzoną na szeroki pasek.
    /// Przy 5,7 pt wygląda jak rysa, więc zostaje samo tło okna.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

/// Podmiana paska w widokach przewijania, które SwiftUI zbudował pod spodem.
enum PasekPrzewijania {

    /// Wstawia `CienkiScroller` do każdego `NSScrollView` w drzewie widoku.
    ///
    /// Wołane po pokazaniu okna, bo wcześniej `NSHostingView` nie ma jeszcze zbudowanej
    /// zawartości. Idempotentne — widok, który już ma cienki pasek, jest pomijany.
    @discardableResult
    static func zastosuj(w korzen: NSView) -> Int {
        var ile = 0
        for widok in wszystkieWidoki(od: korzen) {
            guard let scroll = widok as? NSScrollView else { continue }
            if scroll.verticalScroller is CienkiScroller { continue }
            let cienki = CienkiScroller()
            cienki.controlSize = scroll.verticalScroller?.controlSize ?? .regular
            scroll.verticalScroller = cienki
            scroll.hasVerticalScroller = true
            scroll.tile()
            ile += 1
        }
        return ile
    }

    /// Pomiar do sprawdzenia z zewnątrz: `APPGRID_POMIAR=1` przy uruchomieniu binarki
    /// wypisuje, co naprawdę siedzi w oknie. Bez tej zmiennej program milczy —
    /// diagnostyka nie ma prawa hałasować w normalnym użyciu.
    static func wypiszPomiar(korzen: NSView) {
        guard ProcessInfo.processInfo.environment["APPGRID_POMIAR"] == "1" else { return }
        let systemowa = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        var linie: [String] = ["POMIAR pasek: systemowa=\(systemowa)"]
        for widok in wszystkieWidoki(od: korzen) {
            guard let scroll = widok as? NSScrollView else { continue }
            let s = scroll.verticalScroller
            linie.append("POMIAR pasek: klasa=\(s.map { String(describing: type(of: $0)) } ?? "brak")"
                         + " szerokosc=\(s?.frame.width ?? -1)"
                         + " styl=\(scroll.scrollerStyle.rawValue)")
        }
        print(linie.joined(separator: "\n"))
        fflush(stdout)
    }

    private static func wszystkieWidoki(od widok: NSView) -> [NSView] {
        var wynik = [widok]
        for dziecko in widok.subviews { wynik += wszystkieWidoki(od: dziecko) }
        return wynik
    }
}
