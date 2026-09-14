import SwiftUI

/// Znacznik: ten podwidok jest belką, więc dostaje cały rząd.
private struct CzyBelka: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Oznacza widok jako belkę dla `UkladPlynny`.
    func jakoBelka() -> some View {
        layoutValue(key: CzyBelka.self, value: true)
    }
}

/// Siatka ikon i belek w **jednym** kontenerze.
///
/// 🔴 Po co własny układ, skoro `LazyVGrid` rysuje to samo: dopóki każdy kawałek listy
/// miał swój `LazyVGrid`, przesunięcie belki było dla SwiftUI **usunięciem** ikony
/// z jednego kontenera i **wstawieniem** do drugiego. Takiego ruchu nie da się animować —
/// domyślne przejście rysowało tę samą ikonę dwa razy naraz, jedną na drugiej.
/// Tutaj belki i ikony są rodzeństwem, więc zmiana kolejności jest zwykłym przesunięciem
/// i animuje się ślizgiem (decyzja [U] 2026-08-22: „chcę ślizg").
///
/// Sama geometria mieszka w `UkladSiatki.ramki` — poza SwiftUI, żeby dała się sprawdzić
/// headless i żeby **to samo** liczenie obsługiwało trafianie kursorem przy przeciąganiu.
/// Dwie kopie tej matematyki oznaczałyby ikonę lądującą gdzie indziej, niż pokazał podgląd.
struct UkladPlynny: Layout {

    let metryka: UkladSiatki.Metryka
    /// Które podwidoki są belkami — w tej samej kolejności co `subviews`.
    /// Bierzemy to z `LayoutValueKey`, a nie z listy pozycji, żeby układ nie musiał
    /// wiedzieć nic o modelu.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let szerokosc = szerokoscDo(proposal.width)
        let ramki = UkladSiatki.ramki(dla: pozycje(subviews), szerokosc: szerokosc, metryka: metryka)
        return CGSize(width: szerokosc, height: UkladSiatki.wysokosc(ramek: ramki))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let ramki = UkladSiatki.ramki(
            dla: pozycje(subviews),
            szerokosc: szerokoscDo(bounds.width),
            metryka: metryka
        )
        for (i, ramka) in ramki.enumerated() where i < subviews.count {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + ramka.minX, y: bounds.minY + ramka.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: ramka.width, height: ramka.height)
            )
        }
    }

    /// 🔴 Szerokość bywa nieskończona, zerowa albo ujemna — SwiftUI tak sonduje układ.
    /// Nie wolno jej podać dalej: `Int(.infinity)` ubija proces.
    private func szerokoscDo(_ proponowana: CGFloat?) -> CGFloat {
        UkladSiatki.szerokoscDoOddania(proponowana, zapasowa: metryka.szerokoscKafelka)
    }

    /// Rodzaj każdego podwidoku, w postaci, której oczekuje `UkladSiatki.ramki`.
    /// Treść pozycji nie ma tu znaczenia — liczy się tylko „belka czy ikona".
    private func pozycje(_ subviews: Subviews) -> [UkladSiatki.Pozycja] {
        subviews.map { $0[CzyBelka.self] ? .belka(Self.atrapaBelki) : .program(Self.atrapaProgramu) }
    }

    private static let atrapaBelki = Separator()
    private static let atrapaProgramu = InstalledApp(
        id: "", name: "", url: URL(fileURLWithPath: "/"),
        category: "", isSystem: false, isUtility: false, dataDodania: nil
    )
}

/// Jeden rząd bez zawijania: pokazuje tyle ikon, ile **naprawdę** wchodzi w podaną szerokość.
///
/// 🔴 Po co osobny `Layout` zamiast `HStack`: zwykły rząd sztywnych kafelków **żąda swojej
/// sumy** i nie da się go od tego odwieść. Zmierzone 2026-08-23 na `NSHostingView`:
/// dziesięć kafelków po 78 pt w oknie 700 pt żąda **820 pt**, a `.frame(maxWidth: .infinity)`
/// plus `.clipped()` — lek zapisany przy AG-20 — podnosi tę liczbę do 820 zamiast ją zbić.
/// Rząd rozpychał więc kolumnę treści, `ScrollView` centrował ją szerszą od okna i widać
/// było ucięcie **z obu stron naraz**.
///
/// 🔴 I drugie, ważniejsze: liczba ikon nie wynika tu z żadnego zmierzonego stanu.
/// Rząd dostaje wszystkie kandydatki i sam odcina te, które nie wchodzą — więc nie ma
/// `@State`, nie ma `onGeometryChange`, nie ma opóźnienia o klatkę i nie ma jak powstać
/// pętla „rysuję tyle, ile zmierzyłem ostatnio".
struct RzadJednolity: Layout {

    let szerokoscKafelka: CGFloat
    let wysokoscKafelka: CGFloat
    let odstep: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(
            // Oddajemy dokładnie tyle, ile nam zaproponowano. Nigdy więcej — to jest
            // cała różnica między tym układem a `HStack`-iem.
            width: UkladSiatki.szerokoscDoOddania(proposal.width, zapasowa: szerokoscKafelka),
            height: subviews.isEmpty ? 0 : wysokoscKafelka
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let ile = UkladSiatki.kolumny(
            szerokosc: bounds.width,
            szerokoscKafelka: szerokoscKafelka,
            odstep: odstep
        )
        for (i, podwidok) in subviews.enumerated() {
            guard i < ile else {
                // Nadmiarowe dostają zerowy rozmiar zamiast wypaść poza kadr: element
                // o zerowej propozycji nic nie rysuje i niczego nie rozpycha.
                podwidok.place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                               anchor: .topLeading,
                               proposal: ProposedViewSize(width: 0, height: 0))
                continue
            }
            podwidok.place(
                at: CGPoint(x: bounds.minX + CGFloat(i) * (szerokoscKafelka + odstep), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: szerokoscKafelka, height: wysokoscKafelka)
            )
        }
    }
}
