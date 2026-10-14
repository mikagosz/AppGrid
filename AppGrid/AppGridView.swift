import AppKit
import SwiftUI

struct AppGridView: View {
    @ObservedObject var model: AppGridModel
    @FocusState private var szukajkaAktywna: Bool
    /// Co użytkownik właśnie ciągnie i nad czym trzyma. Z tych dwóch liczy się podgląd układu,
    /// żeby ikony rozstępowały się **w trakcie** ciągnięcia, a nie dopiero po upuszczeniu.
    ///
    /// Od 2026-10-13 to **grupa**: belka razem ze swoją sekcją albo zaznaczone ikony.
    @State private var przeciagany: [ElementUkladu]?
    /// Miejsce wstawienia w liście **bez** elementu ciągniętego, 0…count.
    @State private var indeksPodgladu: Int?
    /// Nad którą sekcją stoi teraz kursor. Od AG-23 sekcje są dwie i obie przyjmują
    /// upuszczenie, więc „gdzie" to już nie tylko indeks.
    @State private var celPrzeciagania: Sekcja?
    /// Ciągnięta jest cała sekcja (belka bez ⌥). Wtedy układ **stoi**: nic się nie
    /// rozstępuje, sekcja zostaje w ramce na swoim miejscu, a linia pokazuje granicę,
    /// na której wyląduje. Zgłoszenie z 2026-10-13: ikony przeskakiwały w trakcie ciągnięcia.
    @State private var ciagnietaSekcja = false
    /// Granica między sekcjami, nad którą stoi kursor przy ciągnięciu całej sekcji.
    @State private var celSekcji: CelSekcji?
    /// Szerokość każdej z siatek — z niej liczy się trafianie kursorem.
    @State private var szerokoscSiatki: [Sekcja: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            gornyPasek
            Divider()
            if model.trybEdycji {
                pasekEdycji
                Divider()
            }
            siatka
            Divider()
            dolnyPasek
        }
        .frame(minWidth: 520, minHeight: 320)
        .onAppear { szukajkaAktywna = true }
        // Menu układu wisi na CAŁYM oknie, nie na kafelkach — decyzja użytkownika 2026-08-22.
        // Kafelek ma własne menu, a menu wewnętrzne wygrywa z zewnętrznym, więc prawy
        // przycisk na ikonie dalej daje „Otwórz / Pokaż w Finderze / Ukryj".
        .contextMenu { menuUkladu }
    }

    private var gornyPasek: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($szukajkaAktywna)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        szukajkaAktywna = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            Picker(String(localized: "Category"), selection: $model.category) {
                ForEach(model.categories, id: \.self) { nazwa in
                    Text(nazwa).tag(nazwa)
                }
            }
            .labelsHidden()
            .frame(width: 190)
            .help("Filters the list — never types into the search field")

            Slider(
                value: Binding(
                    get: { Double(model.iconScale) },
                    set: { model.iconScale = Int($0.rounded()) }
                ),
                in: 1...5,
                step: 1
            )
            .frame(width: 90)
            .help("Icon size")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var siatka: some View {
        ScrollView {
            // Wybór strzałkami wyjeżdża poza kadr przy dłuższej liście — `ScrollViewReader`
            // jest tu jedynym sposobem, żeby siatka za nim nadążyła.
            ScrollViewReader { przewijanie in
            VStack(alignment: .leading, spacing: 14) {
                sekcjeOstatnich
                // W edycji obie sekcje są widoczne nawet puste — inaczej po wyniesieniu
                // ostatniej ikony nie byłoby gdzie jej oddać (AG-23).
                if model.trybEdycji || !model.visibleRegular.isEmpty {
                    if model.maSekcjeOstatnich, model.rysujWlasnyNaglowekWszystkich {
                        naglowekSekcji(String(localized: "All apps"))
                    }
                    grupaUlozona(.glowne)
                }
                if model.trybEdycji || !model.visibleUtilities.isEmpty {
                    naglowekSekcji(String(localized: "System utilities"))
                    grupaUlozona(.narzedzia)
                }
            }
            .padding(10)
            // Kliknięcie w wolne miejsce zdejmuje zaznaczenie. Tło leży POD treścią,
            // więc kafelki, pola nazw belek i przyciski dalej dostają swoje kliknięcia.
            .background {
                if model.trybEdycji {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.wyczyscZaznaczenie() }
                }
            }
            .onChange(of: model.wybrany) { _, nowy in
                guard let nowy else { return }
                withAnimation(.easeOut(duration: 0.15)) { przewijanie.scrollTo(nowy, anchor: .center) }
            }
            }
        }
    }

    // MARK: - Sekcje „ostatnie" (AG-1 + scalony rząd)

    /// Sekcje pokazują się tylko wtedy, gdy użytkownik je włączył i gdy lista nie jest zawężona
    /// szukajką ani kategorią — o to drugie dba `listaPelna` w modelu.
    @ViewBuilder
    private var sekcjeOstatnich: some View {
        switch model.ustawienia.trybOstatnich {
        case .osobneSekcje:
            let dodane = model.ostatnioDodane
            let uzywane = model.ostatnioUzywane
            if !dodane.isEmpty {
                naglowekSekcji(String(localized: "Recently installed"))
                grupa(dodane)
            }
            if !uzywane.isEmpty {
                naglowekSekcji(String(localized: "Recently used"))
                grupa(uzywane)
            }
        case .jedenRzad:
            if model.maSekcjeOstatnich {
                naglowekSekcji(String(localized: "Recent"))
                rzadOstatnich
            }
        }
    }

    /// Jeden rząd bez zawijania: mieści tyle ikon, ile wejdzie w szerokość okna.
    ///
    /// 🔴 Rząd **nie wie**, ile ikon się zmieści, i nie ma tego skąd wiedzieć — dostaje
    /// wszystkie kandydatki, a odcina je `RzadJednolity` w chwili układania, z prawdziwej
    /// szerokości. Poprzednia postać liczyła to z zmierzonej szerokości okna i rysowała
    /// sztywnym `HStack`-iem: rząd żądał wtedy swojej sumy (zmierzone: 820 pt przy oknie
    /// 700 pt), rozpychał kolumnę treści i całą siatkę było widać uciętą z obu stron.
    private var rzadOstatnich: some View {
        RzadJednolity(
            szerokoscKafelka: szerokoscKafelka,
            wysokoscKafelka: wysokoscKafelka,
            odstep: odstepPoziomy
        ) {
            ForEach(model.ostatnieScalone(ile: Self.najwiecejWRzedzie), id: \.id) { app in
                kafelek(app)
            }
        }
    }

    /// Górna granica liczby kandydatek do rzędu „Ostatnie".
    ///
    /// Nie jest to liczba rysowanych ikon — tyle najwyżej **rozważamy**. Przy najmniejszym
    /// kafelku (46 pt) czterdzieści sztuk wypełnia dwa metry ekranu, więc żaden monitor
    /// nie pokaże więcej. Kandydatki poza kadrem kosztują tyle, co wpis w tablicy: ikony
    /// wiszą w pamięci podręcznej, a `RzadJednolity` daje im zerowy rozmiar.
    private static let najwiecejWRzedzie = 40

    private var szerokoscKafelka: CGFloat { model.iconSize + 14 }

    // MARK: - Siatka

    private func naglowekSekcji(_ tytul: String) -> some View {
        HStack(spacing: 8) {
            Text(tytul)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, 4)
    }

    /// Belka wstawiona przez użytkownika. Bez nazwy jest samą kreską.
    ///
    /// W edycji cały ten rząd — uchwyt, wolne miejsce i kreska — jest powierzchnią
    /// do chwycenia. Wcześniej chwytała tylko sama ikonka uchwytu i kreska wysokości
    /// **1 pt**, więc trafienie w nią graniczyło ze snajperką (zgłoszenie użytkownika 2026-08-22).
    @ViewBuilder
    private func belkaSeparatora(_ belka: Separator) -> some View {
        HStack(spacing: 8) {
            if model.trybEdycji {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.secondary.opacity(0.18))
                    )
                    .help(String(localized: "Drag to move this separator"))
                TextField(String(localized: "Section name"), text: nazwaBelki(belka))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button {
                    model.usunSeparator(belka)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Remove this separator"))
            } else if !belka.nazwa.isEmpty {
                Text(belka.nazwa)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            // Kreska ma 1 pt, ale mieszka w polu wysokości całego rzędu — to ono jest
            // chwytane, nie ona.
            Rectangle()
                .fill(.secondary.opacity(model.trybEdycji ? 0.55 : 0.4))
                .frame(height: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(height: wysokoscBelki - 2 * odstepWewnatrzBelki)
        .padding(.vertical, odstepWewnatrzBelki)
        .modifier(Chwytanie(
            element: .belka(belka.id),
            aktywne: model.trybEdycji,
            // Belka ciągnie całą swoją sekcję (zgłoszenie z 2026-10-13); z ⌥ — samą siebie.
            zaczeto: {
                let samaBelka = NSEvent.modifierFlags.contains(.option)
                przeciagany = model.grupaDoCiagniecia(.belka(belka.id), samaBelka: samaBelka)
                ciagnietaSekcja = !samaBelka
                celSekcji = nil
            },
            podglad: {
                let ikon = model.grupaDoCiagniecia(.belka(belka.id), samaBelka: NSEvent.modifierFlags.contains(.option))
                    .filter { if case .program = $0 { return true } else { return false } }.count
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                    Text(belka.nazwa.isEmpty ? String(localized: "Separator") : belka.nazwa)
                        .font(.system(size: 11, weight: .semibold))
                    if ikon > 0 {
                        Text("+\(ikon)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.thickMaterial))
            }
        ))
    }

    /// Nazwa wpisywana wprost na belce — po to jest tryb edycji.
    private func nazwaBelki(_ belka: Separator) -> Binding<String> {
        Binding(
            get: { model.ustawienia.separator(belka.id)?.nazwa ?? "" },
            set: { model.ustawienia.zmienNazweSeparatora(belka.id, na: $0) }
        )
    }

    /// Zwykła siatka bez własnej kolejności i bez belek — sekcje „ostatnie".
    /// Tam kolejność wynika z dat, nie z układu użytkownika, więc nie ma czego przestawiać.
    /// Narzędzia systemowe od AG-23 tędy **nie** idą: mają własną kolejność.
    private func grupa(_ lista: [InstalledApp]) -> some View {
        LazyVGrid(columns: kolumny, alignment: .leading, spacing: odstepPionowy) {
            ForEach(lista, id: \.id) { app in
                kafelek(app)
            }
        }
    }

    /// Sekcja z własną kolejnością użytkownika: belki, przeciąganie i wymiana ikon z sąsiadem.
    ///
    /// Wszystko siedzi w **jednym** `UkladPlynny`, bo tylko rodzeństwo w jednym kontenerze
    /// SwiftUI potrafi przesunąć. Rozbicie na kawałki z osobnymi siatkami dawało zamiast
    /// ruchu znikanie i pojawianie się — tę samą ikonę narysowaną dwa razy.
    ///
    /// Od AG-23 ta sama funkcja rysuje „Wszystkie programy" i „Narzędzia systemowe" —
    /// dwa wywołania, dwa zapisy kolejności, jeden kod. Druga kopia tej mechaniki
    /// rozjechałaby się z pierwszą przy pierwszej poprawce.
    private func grupaUlozona(_ sekcja: Sekcja) -> some View {
        let pozycje = model.pozycje(sekcja, podglad: podglad)
        return VStack(alignment: .leading, spacing: 0) {
            UkladPlynny(metryka: metryka) {
                ForEach(pozycje) { pozycja in
                    switch pozycja {
                    case .belka(let belka):
                        belkaSeparatora(belka).jakoBelka()
                            .opacity(wyszarzone(pozycja) ? 0.35 : 1)
                    case .program(let app):
                        kafelek(app)
                            .opacity(wyszarzone(pozycja) ? 0.35 : 1)
                    }
                }
            }
            .overlay(alignment: .topLeading) { znacznikiSekcji(sekcja, pozycje: pozycje) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { szerokosc in
                szerokoscSiatki[sekcja] = szerokosc
                przeliczMapeNawigacji()
            }
            .onChange(of: model.visibleApps.map(\.id)) { _, _ in przeliczMapeNawigacji() }
            .onChange(of: model.iconScale) { _, _ in przeliczMapeNawigacji() }

            // Pusta sekcja ma zerową wysokość, więc nie da się na nią nic upuścić.
            // Ten pasek jest jej jedyną powierzchnią — bez niego ikona wyniesiona
            // z narzędzi nie miałaby drogi powrotnej.
            if model.trybEdycji, pozycje.isEmpty {
                pustaStrefa
            }
        }
        // 🔴 JEDNO miejsce odbioru na całą siatkę, zamiast jednego na każdym kafelku.
        // Kafelki w trakcie ciągnięcia przesuwają się pod kursorem, więc pytanie
        // „na czym stoję" nie ma stabilnej odpowiedzi — cele uciekały spod kursora
        // i upuszczenie lądowało nie tam, gdzie pokazywał podgląd. Pytanie „gdzie stoję"
        // odpowiedź ma, więc liczymy miejsce wstawienia z geometrii.
        .onDrop(of: [.utf8PlainText], delegate: OdbiorUpuszczenia(
            celuj: { celujWPunkcie($0, w: sekcja) },
            porzuc: { porzucCel(sekcja) },
            upusc: { zapiszPrzeniesienie() }
        ))
        // Ślizg, o który prosił użytkownik: ikony przesuwają się w trakcie ciągnięcia.
        .animation(.snappy(duration: 0.22), value: indeksPodgladu)
        .animation(.snappy(duration: 0.22), value: celPrzeciagania)
    }

    /// Element ciągniętej sekcji — przygaszony, dopóki kursor stoi nad siatką.
    private func wyszarzone(_ pozycja: UkladSiatki.Pozycja) -> Bool {
        guard ciagnietaSekcja, celSekcji != nil, let przeciagany else { return false }
        return przeciagany.contains { $0.id == pozycja.id }
    }

    /// Ramka wokół ciągniętej sekcji i linia granicy, na której wyląduje.
    ///
    /// Rysowane nad siatką, z tych samych ramek, z których liczy się trafianie —
    /// sama siatka przez cały czas ciągnięcia stoi w miejscu.
    @ViewBuilder
    private func znacznikiSekcji(_ sekcja: Sekcja, pozycje: [UkladSiatki.Pozycja]) -> some View {
        if ciagnietaSekcja, let cel = celSekcji, let przeciagany {
            let ramki = UkladSiatki.ramki(dla: pozycje, szerokosc: szerokoscSiatki[sekcja] ?? 0, metryka: metryka)
            let ciagniete = Set(przeciagany.map(\.id))
            let wlasne = zip(pozycje, ramki).filter { ciagniete.contains($0.0.id) }.map(\.1)
            ZStack(alignment: .topLeading) {
                if let pierwsza = wlasne.first {
                    let obrys = wlasne.dropFirst().reduce(pierwsza) { $0.union($1) }.insetBy(dx: -4, dy: -3)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                        .frame(width: obrys.width, height: obrys.height)
                        .offset(x: obrys.minX, y: obrys.minY)
                }
                if cel.sekcja == sekcja, !cel.brakZmiany {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: szerokoscSiatki[sekcja] ?? 0, height: 4)
                        .offset(y: cel.y - 2)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Powierzchnia do upuszczenia w sekcji, w której nic nie zostało.
    private var pustaStrefa: some View {
        Text(String(localized: "Drop icons here"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: wysokoscKafelka)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        .secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(Rectangle())
    }

    /// Gdzie leży każda ikona — dla chodzenia strzałkami.
    ///
    /// 🔴 Liczone **tym samym** `UkladSiatki.ramki`, który układa siatkę, a nie
    /// osobnym wzorem „indeks plus liczba kolumn". Tamten wzór zakłada równe rzędy,
    /// a rzędy równe nie są: belka łamie rząd w pół i sekcja narzędzi zaczyna własny.
    /// Stąd zgłoszenie użytkownika, że w dół „skacze dziwnie między sekcjami".
    ///
    /// Narzędzia dostają przesunięcie w dół o wysokość sekcji głównej, żeby obie
    /// siatki leżały w jednym układzie współrzędnych — inaczej pierwszy rząd narzędzi
    /// miałby ten sam `y` co pierwszy rząd programów i strzałka w dół nie miałaby
    /// gdzie pójść.
    private func przeliczMapeNawigacji() {
        var mapa: [AppGridModel.PolozenieIkony] = []
        var przesuniecie: CGFloat = 0

        for sekcja in [Sekcja.glowne, .narzedzia] {
            let pozycje = model.pozycje(sekcja, podglad: nil)
            let szerokosc = szerokoscSiatki[sekcja] ?? 0
            let ramki = UkladSiatki.ramki(dla: pozycje, szerokosc: szerokosc, metryka: metryka)
            for (pozycja, ramka) in zip(pozycje, ramki) {
                guard case .program(let app) = pozycja else { continue }
                mapa.append(.init(id: app.id, ramka: ramka.offsetBy(dx: 0, dy: przesuniecie)))
            }
            przesuniecie += UkladSiatki.wysokosc(ramek: ramki) + odstepMiedzySekcjami
        }

        if model.mapaNawigacji != mapa { model.mapaNawigacji = mapa }
        model.kolumnWRzedzie = UkladSiatki.kolumny(
            szerokosc: szerokoscSiatki[.glowne] ?? 0,
            szerokoscKafelka: szerokoscKafelka,
            odstep: odstepPoziomy
        )
    }

    /// Odstęp między sekcjami w `siatka` — ta sama liczba, co `spacing` tamtego `VStack`.
    private var odstepMiedzySekcjami: CGFloat { 14 }

    private var metryka: UkladSiatki.Metryka {
        UkladSiatki.Metryka(
            szerokoscKafelka: szerokoscKafelka,
            wysokoscKafelka: wysokoscKafelka,
            wysokoscBelki: wysokoscBelki,
            odstepPoziomy: odstepPoziomy,
            odstepPionowy: odstepPionowy,
            odstepPrzyBelce: odstepPrzyBelce
        )
    }

    /// Belka ma **stałą** wysokość, bo tę samą geometrię liczy rysowanie i trafianie
    /// kursorem. Wysokość zależna od treści rozjechałaby jedno z drugim.
    private var wysokoscBelki: CGFloat { model.trybEdycji ? 32 : 18 }

    /// Rzędy siatki mają **równą** wysokość — inaczej przejście ikony z rzędu do rzędu
    /// zmieniałoby wysokość obu i cała lista pod spodem podskakiwałaby przy każdym ruchu.
    ///
    /// Ikona plus miejsce na podpis. Miejsce na podpis **nie zależy od rozmiaru ikony**,
    /// bo podpis ma stały krój — stąd stała, nie proporcja.
    ///
    /// ⚠️ Za pierwszym razem dałem tu 34 pt i podpisy urwały się do jednej linijki
    /// („Album z czci…"): na dwie linijki zostawało 27 pt, a potrzeba około 30.
    /// Widać to dopiero na ekranie, bo `lineLimit(2)` nie zgłasza, że nie ma miejsca.
    private var wysokoscKafelka: CGFloat { model.iconSize + miejsceNaPodpis }

    /// 3 pt odstępu pod ikoną + dwie linijki podpisu po 11 pt + 2×2 pt marginesu, z zapasem.
    private var miejsceNaPodpis: CGFloat { 40 }

    /// Siatka sekcji bez elementu ciągniętego. To **ona** jest podstawą trafiania: jej
    /// ramki nie zmieniają się przez cały czas ciągnięcia, więc mapowanie „punkt → miejsce"
    /// jest stabilne. Liczenie na tym, co widać, zapętliłoby się — podgląd przesuwa
    /// kafelki, a przesunięte kafelki zmieniłyby wynik trafiania.
    private func pozycjeBezCiagnietego(_ sekcja: Sekcja) -> [UkladSiatki.Pozycja] {
        let wszystkie = model.pozycje(sekcja, podglad: nil)
        guard let przeciagany else { return wszystkie }
        let ciagniete = Set(przeciagany.map(\.id))
        return wszystkie.filter { !ciagniete.contains($0.id) }
    }

    /// Przeciąganie w toku, przełożone na „co, dokąd i przed czym".
    private var podglad: PodgladPrzeniesienia? {
        // Cała sekcja nie przesuwa układu w trakcie — patrz `ciagnietaSekcja`.
        guard !ciagnietaSekcja else { return nil }
        guard let przeciagany, let celPrzeciagania, let indeksPodgladu else { return nil }
        let baza = pozycjeBezCiagnietego(celPrzeciagania)
        guard indeksPodgladu < baza.count else {
            return PodgladPrzeniesienia(grupa: przeciagany, doSekcji: celPrzeciagania, przed: nil)
        }
        return PodgladPrzeniesienia(
            grupa: przeciagany,
            doSekcji: celPrzeciagania,
            przed: ElementUkladu(id: baza[indeksPodgladu].id)
        )
    }

    private func celujWPunkcie(_ punkt: CGPoint, w sekcja: Sekcja) {
        guard let przeciagany else { return }
        if ciagnietaSekcja {
            celujGranica(punkt, w: sekcja, grupa: przeciagany)
            return
        }
        let ramki = UkladSiatki.ramki(
            dla: pozycjeBezCiagnietego(sekcja),
            szerokosc: szerokoscSiatki[sekcja] ?? 0,
            metryka: metryka
        )
        celPrzeciagania = sekcja
        indeksPodgladu = UkladSiatki.indeksWstawienia(punkt: punkt, ramki: ramki)
    }

    /// Sekcja celuje w granice między sekcjami, nie w ikony. Układ jest pełny (nic nie
    /// wycięte), bo w tym trybie nic się nie przesuwa i ramki nie uciekają spod kursora.
    private func celujGranica(_ punkt: CGPoint, w sekcja: Sekcja, grupa: [ElementUkladu]) {
        let pozycje = model.pozycje(sekcja, podglad: nil)
        let ramki = UkladSiatki.ramki(dla: pozycje, szerokosc: szerokoscSiatki[sekcja] ?? 0, metryka: metryka)
        let czyBelka = pozycje.map { if case .belka = $0 { return true } else { return false } }
        let g = UkladSiatki.granicaSekcji(y: punkt.y, ramki: ramki, czyBelka: czyBelka, odstep: odstepPrzyBelce)
        let przed = g.indeks < pozycje.count ? ElementUkladu(id: pozycje[g.indeks].id) : nil

        // Granica tuż nad albo tuż pod własną sekcją to brak zmiany — linii nie rysujemy.
        let ciagniete = Set(grupa.map(\.id))
        let wlasne = pozycje.indices.filter { ciagniete.contains(pozycje[$0].id) }
        var brakZmiany = false
        if let a = wlasne.first, let b = wlasne.last { brakZmiany = g.indeks == a || g.indeks == b + 1 }
        if let przed, grupa.contains(przed) { brakZmiany = true }

        let nowy = CelSekcji(sekcja: sekcja, przed: przed, y: g.y, brakZmiany: brakZmiany)
        if celSekcji != nowy { celSekcji = nowy }
    }

    /// Kursor zszedł z sekcji. Kasujemy podgląd **tylko** wtedy, gdy to nadal ta sekcja
    /// jest celem: przy przejeździe z jednej do drugiej AppKit potrafi zgłosić wejście
    /// do nowej przed zejściem ze starej, a wtedy ślepe zerowanie zgasiłoby świeży cel.
    private func porzucCel(_ sekcja: Sekcja) {
        if celSekcji?.sekcja == sekcja { celSekcji = nil }
        guard celPrzeciagania == sekcja else { return }
        celPrzeciagania = nil
        indeksPodgladu = nil
    }

    /// Zapisuje **to, co widać**. Podgląd i zapis liczą się z tej samej trójki
    /// (co, dokąd, przed czym), więc ikona ląduje dokładnie tam, gdzie ją było widać.
    private func zapiszPrzeniesienie() -> Bool {
        defer {
            przeciagany = nil
            celPrzeciagania = nil
            indeksPodgladu = nil
            ciagnietaSekcja = false
            celSekcji = nil
        }
        if ciagnietaSekcja {
            guard let przeciagany, let cel = celSekcji, !cel.brakZmiany else { return false }
            model.przenies(przeciagany, doSekcji: cel.sekcja, przed: cel.przed)
            return true
        }
        guard let podglad else { return false }
        model.przenies(podglad.grupa, doSekcji: podglad.doSekcji, przed: podglad.przed)
        return true
    }

    // MARK: - Tryb edycji

    @ViewBuilder
    private var menuUkladu: some View {
        if model.trybEdycji {
            Button("Add separator") { model.dodajSeparator(przed: nil) }
            Button("Restore alphabetical order") { model.przywrocAlfabet() }
            Divider()
            Button("Done") { model.wyjdzZEdycji() }
        } else {
            Button("Edit layout…") { model.wejdzWEdycje() }
        }
    }

    private var pasekEdycji: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.arrow.down.square")
                .foregroundStyle(.secondary)
            Text(String(localized: "Edit mode — drag a separator to move its whole section (⌥ moves the separator alone). Click icons to select them, ⌘-click or ⇧-click to select several, then drag them together."))
                .font(.callout)
            Spacer()
            Button(String(localized: "Add separator")) { model.dodajSeparator(przed: nil) }
            Button(String(localized: "Done")) { model.wyjdzZEdycji() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// Kafelek. Chwytanie włącza się tylko w trybie edycji; upuszczenie odbiera
    /// **siatka**, nie kafelek — patrz `grupaUlozona`.
    private func kafelek(_ app: InstalledApp) -> some View {
        Kafelek(
            app: app,
            rozmiar: model.iconSize,
            ukryty: model.ustawienia.ukryte.contains(app.id),
            edycja: model.trybEdycji,
            uruchom: { model.launch(app) },
            pokazWFinderze: { model.revealInFinder(app) },
            przelaczUkrycie: { model.przelaczUkrycie(app) },
            wybrany: model.wybrany == app.id,
            zaznaczony: model.trybEdycji && model.zaznaczone.contains(app.id),
            kliknieto: { model.kliknietoWEdycji(app, modyfikatory: NSEvent.modifierFlags) }
        )
        .id(app.id)
        .modifier(Chwytanie(
            element: .program(app.id),
            aktywne: model.trybEdycji,
            // Zaznaczona ikona ciągnie wszystkie zaznaczone; niezaznaczona — tylko siebie.
            zaczeto: {
                przeciagany = model.grupaDoCiagniecia(.program(app.id), samaBelka: false)
                ciagnietaSekcja = false
                celSekcji = nil
            },
            podglad: {
                let ile = model.grupaDoCiagniecia(.program(app.id), samaBelka: false).count
                Image(nsImage: IkonyProgramow.ikona(app.url.path))
                    .resizable()
                    .frame(width: model.iconSize, height: model.iconSize)
                    .overlay(alignment: .topTrailing) {
                        if ile > 1 {
                            Text("\(ile)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 6, y: -6)
                        }
                    }
            }
        ))
    }

    private var kolumny: [GridItem] {
        [GridItem(.adaptive(minimum: szerokoscKafelka), spacing: odstepPoziomy)]
    }

    /// Odstęp góra/dół zmniejszony o 40% na życzenie użytkownika (2026-08-22).
    ///
    /// Liczy się suma, nie sama ta liczba: przerwa między rzędami to `odstepPionowy`
    /// plus dwa razy pionowy padding kafelka. Było 6 + 4 + 4 = 14 pt, jest 4 + 2 + 2 = 8 pt.
    /// Odstęp w poziomie został nietknięty — zgłoszenie dotyczyło wyłącznie góry i dołu.
    private var odstepPionowy: CGFloat { 4 }
    private var odstepPoziomy: CGFloat { 4 }

    /// Odstęp między ikoną a belką, zmniejszony o 30% na życzenie użytkownika (2026-08-22).
    ///
    /// Też jest sumą: odstęp kawałków `VStack` plus pionowy padding samej belki.
    /// Było 8 + 2 = 10 pt, jest 6 + 1 = **7 pt**.
    private var odstepPrzyBelce: CGFloat { 6 }
    private var odstepWewnatrzBelki: CGFloat { 1 }

    private var dolnyPasek: some View {
        HStack {
            Text(podsumowanie)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                HelpWindow.shared.show()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(HelpContent.menuItem.current)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var podsumowanie: String {
        let widoczne = model.visibleApps.count
        let wszystkie = model.apps.count
        if widoczne == wszystkie {
            return String(localized: "\(wszystkie) apps — all visible without searching")
        }
        return String(localized: "\(widoczne) of \(wszystkie) apps")
    }
}

/// Granica, na której wyląduje ciągnięta sekcja.
private struct CelSekcji: Equatable {
    let sekcja: Sekcja
    /// Przed tym elementem; `nil` = na koniec sekcji.
    let przed: ElementUkladu?
    /// Wysokość linii wstawienia w układzie siatki.
    let y: CGFloat
    /// Granica tuż przy własnej sekcji — upuszczenie nic nie zmienia.
    let brakZmiany: Bool
}

/// Pojedyncza ikona z podpisem.
private struct Kafelek: View {
    let app: InstalledApp
    let rozmiar: CGFloat
    /// Ukryty program widać tylko przez szukajkę — i wtedy jest przygaszony, żeby użytkownik
    /// wiedział, dlaczego nie ma go w siatce.
    let ukryty: Bool
    let edycja: Bool
    let uruchom: () -> Void
    let pokazWFinderze: () -> Void
    let przelaczUkrycie: () -> Void
    /// Ikona wskazana strzałkami. Rysowana inaczej niż najechanie myszą: wybór
    /// z klawiatury musi być widoczny także wtedy, gdy kursor stoi gdzie indziej.
    let wybrany: Bool
    /// Zaznaczony w trybie edycji — jedzie razem z innymi zaznaczonymi.
    let zaznaczony: Bool
    /// Kliknięcie w trybie edycji: zaznaczanie, nie uruchamianie.
    let kliknieto: () -> Void

    @State private var podswietlony = false

    var body: some View {
        zawartosc
            .opacity(ukryty ? 0.45 : 1)
            .onHover { podswietlony = $0 }
            .help(app.url.path)
            .contextMenu { menu }
    }

    /// W edycji kafelek przestaje być przyciskiem: kliknięcie ma chwytać ikonę,
    /// a nie odpalać program. Inaczej każde nieudane pociągnięcie uruchamiałoby coś.
    @ViewBuilder
    private var zawartosc: some View {
        if edycja {
            wnetrze
                .contentShape(Rectangle())
                .onTapGesture { kliknieto() }
        } else {
            Button(action: uruchom) { wnetrze }
                .buttonStyle(.plain)
        }
    }

    /// Bez pozycji układu — te siedzą w menu okna, nie na ikonie (decyzja użytkownika 2026-08-22).
    @ViewBuilder
    private var menu: some View {
        if !edycja {
            Button("Open") { uruchom() }
            Button("Show in Finder") { pokazWFinderze() }
            Divider()
        }
        Button(ukryty ? "Show again" : "Hide") { przelaczUkrycie() }
    }

    private var wnetrze: some View {
        Group {
            VStack(spacing: 3) {
                Image(nsImage: IkonyProgramow.ikona(app.url.path))
                    .resizable()
                    .frame(width: rozmiar, height: rozmiar)
                Text(app.name)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tloKafelka)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: (wybrany || zaznaczony) ? 2 : 0)
            )
        }
    }

    private var tloKafelka: Color {
        if edycja {
            if zaznaczony { return Color.accentColor.opacity(0.25) }
            return Color.primary.opacity(podswietlony ? 0.12 : 0.05)
        }
        if wybrany { return Color.accentColor.opacity(0.18) }
        return podswietlony ? Color.primary.opacity(0.08) : .clear
    }
}

/// Chwytanie i upuszczanie — tylko tam, gdzie kolejność ma się gdzie zapisać.
///
/// `.draggable` i `.dropDestination` nie mają przełącznika „aktywne/nieaktywne", więc
/// zakłada się je warunkowo. Bez tego poza trybem edycji jedno pociągnięcie ikony
/// przestawiałoby siatkę. Sekcje „ostatnie" nie chwytają w ogóle — ich kolejność
/// wynika z dat i nie ma czego zapisać.
private struct Chwytanie<Podglad: View>: ViewModifier {
    let element: ElementUkladu
    let aktywne: Bool
    let zaczeto: () -> Void
    /// Obrazek ciągnięty za kursorem. Podajemy go sami, bo domyślnie SwiftUI robi
    /// zrzut całego kafelka — a im cięższy widok, tym bardziej ten „duch" zostaje w tyle.
    @ViewBuilder let podglad: () -> Podglad

    func body(content: Content) -> some View {
        if aktywne {
            content
                // Cała powierzchnia, nie tylko narysowane piksele — inaczej przerwy
                // między elementami są martwe i trzeba celować.
                .contentShape(Rectangle())
                // `.onDrag`, a nie `.draggable`: tylko ono daje moment chwycenia, a bez
                // niego nie wiadomo, CO jest ciągnięte — a bez tego nie ma podglądu.
                .onDrag {
                    zaczeto()
                    return NSItemProvider(object: element.id as NSString)
                } preview: {
                    podglad()
                }
        } else {
            content
        }
    }
}

/// Odbiór upuszczenia dla **całej** siatki.
///
/// `DropDelegate`, a nie `dropDestination`, bo tylko on daje `location` **w trakcie**
/// przeciągania. Bez ciągłej pozycji kursora nie da się liczyć miejsca wstawienia
/// z geometrii, a bez geometrii cele uciekają spod kursora razem z podglądem.
private struct OdbiorUpuszczenia: DropDelegate {
    let celuj: (CGPoint) -> Void
    let porzuc: () -> Void
    let upusc: () -> Bool

    func validateDrop(info: DropInfo) -> Bool { true }
    func dropEntered(info: DropInfo) { celuj(info.location) }
    func dropExited(info: DropInfo) { porzuc() }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        celuj(info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool { upusc() }
}
