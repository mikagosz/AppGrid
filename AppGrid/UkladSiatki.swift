import Foundation

/// Belka pozioma, którą [U] wstawia między ikony, żeby porobić sobie własne sekcje.
///
/// Od 0.2.9 belka **nie jest przywiązana do programu** — siedzi na swojej pozycji
/// w `kolejnosc`, tak samo jak ikony. Inaczej nie dałoby się jej przesunąć ani
/// zostawić pustej, a przesuwanie ikon było właśnie tym, czego brakowało.
struct Separator: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Podpis sekcji. Pusty = sama kreska.
    var nazwa: String = ""
}

/// Jeden element układu siatki: program albo belka.
enum ElementUkladu: Codable, Hashable, Identifiable {
    case program(String)
    case belka(UUID)

    /// Ten sam string służy za tożsamość w `ForEach` i za ładunek przeciągania —
    /// dzięki temu ikona i belka jadą jednym kanałem i nie trzeba dwóch typów.
    var id: String {
        switch self {
        case .program(let sciezka): return "p:" + sciezka
        case .belka(let uuid):      return "b:" + uuid.uuidString
        }
    }

    init?(id tekst: String) {
        if tekst.hasPrefix("p:") {
            self = .program(String(tekst.dropFirst(2)))
        } else if tekst.hasPrefix("b:"), let uuid = UUID(uuidString: String(tekst.dropFirst(2))) {
            self = .belka(uuid)
        } else {
            return nil
        }
    }
}

/// Która sekcja siatki ma własną kolejność [U].
///
/// Do 0.2.23 kolejność miały tylko „Wszystkie programy", a narzędzia systemowe leciały
/// alfabetycznie i nie przyjmowały upuszczenia. Decyzja [U] 2026-08-23 (AG-23): obie
/// sekcje mają swoją kolejność i **wymieniają się ikonami** — narzędzie da się wyciągnąć
/// do programów, a program wciągnąć do narzędzi.
enum Sekcja: Int, Codable, Hashable, CaseIterable, Identifiable {
    case glowne = 0
    case narzedzia = 1

    var id: Int { rawValue }
}

/// Układanie siatki: własna kolejność [U] i cięcie jej belkami.
enum UkladSiatki {

    /// Kawałek listy: belka nad nim (albo jej brak) i programy do następnej belki.
    struct Segment: Identifiable {
        let id: String
        let belka: Separator?
        let programy: [InstalledApp]
    }

    /// Jedna rzecz do narysowania w siatce — belka albo program.
    ///
    /// To jest postać, w której siatkę rysuje `UkladPlynny`: **płaska**, bo wszystkie
    /// elementy muszą być rodzeństwem w jednym kontenerze. Dopóki każdy kawałek miał
    /// swój `LazyVGrid`, przesunięcie belki było dla SwiftUI usunięciem ikony z jednego
    /// kontenera i wstawieniem do drugiego — a takiego ruchu nie da się animować.
    enum Pozycja: Identifiable {
        case belka(Separator)
        case program(InstalledApp)

        var id: String {
            switch self {
            case .belka(let b):   return "b:" + b.id.uuidString
            case .program(let a): return "p:" + a.id
            }
        }
    }

    /// Wymiary siatki. Wszystkie stałe w jednym miejscu, bo tę samą geometrię liczy
    /// i rysowanie, i trafianie kursorem — gdyby rozjechały się choć o punkt, ikona
    /// lądowałaby gdzie indziej, niż pokazuje podgląd.
    struct Metryka {
        let szerokoscKafelka: CGFloat
        let wysokoscKafelka: CGFloat
        let wysokoscBelki: CGFloat
        let odstepPoziomy: CGFloat
        let odstepPionowy: CGFloat
        let odstepPrzyBelce: CGFloat
    }

    /// Ile kolumn zmieści się w podanej szerokości.
    ///
    /// 🔴 Wydzielone i sprawdzane headless, bo dokładnie tutaj program się **wywalił**
    /// (raport awarii 2026-08-22): SwiftUI w przelotowych przebiegach pomiarowych
    /// proponuje szerokość **nieskończoną**, a `Int(.infinity)` to nie wyjątek do złapania,
    /// tylko `EXC_BREAKPOINT` i koniec procesu. Zero i wartości ujemne przychodzą tak samo.
    nonisolated static func kolumny(szerokosc: CGFloat, szerokoscKafelka: CGFloat, odstep: CGFloat) -> Int {
        guard szerokosc.isFinite, szerokosc > 0, szerokoscKafelka > 0 else { return 1 }
        return max(1, Int((szerokosc + odstep) / (szerokoscKafelka + odstep)))
    }

    /// Szerokość, którą układ może oddać rodzicowi.
    ///
    /// 🔴 SwiftUI sonduje układy szerokością nieskończoną, zerową, ujemną i `nil`.
    /// Żadnej z nich nie wolno podać dalej — `Int(.infinity)` to nie wyjątek do złapania,
    /// tylko koniec procesu. Wspólne dla obu układów, żeby nie było dwóch strażników
    /// z własnym zdaniem.
    nonisolated static func szerokoscDoOddania(_ proponowana: CGFloat?, zapasowa: CGFloat) -> CGFloat {
        guard let proponowana, proponowana.isFinite, proponowana > 0 else { return zapasowa }
        return proponowana
    }

    /// Prostokąty wszystkich pozycji: ikony płyną w rzędach, belki zajmują cały rząd.
    ///
    /// Czysta funkcja, bez SwiftUI — dzięki temu ten sam rozkład sprawdza się headless
    /// i używają go oba miejsca: `UkladPlynny` przy rysowaniu i trafianie kursorem
    /// przy przeciąganiu.
    nonisolated static func ramki(
        dla pozycje: [Pozycja],
        szerokosc proponowana: CGFloat,
        metryka m: Metryka
    ) -> [CGRect] {
        let szerokosc = (proponowana.isFinite && proponowana > 0) ? proponowana : m.szerokoscKafelka
        let liczbaKolumn = kolumny(szerokosc: szerokosc, szerokoscKafelka: m.szerokoscKafelka, odstep: m.odstepPoziomy)

        var ramki: [CGRect] = []
        ramki.reserveCapacity(pozycje.count)
        var y: CGFloat = 0
        var kolumna = 0
        var wysokoscRzedu: CGFloat = 0
        var poprzedniaBelka: Bool?

        func zamknijRzad(nastepnaBelka: Bool) {
            guard let poprzedniaBelka else { return }
            y += wysokoscRzedu + ((poprzedniaBelka || nastepnaBelka) ? m.odstepPrzyBelce : m.odstepPionowy)
            wysokoscRzedu = 0
            kolumna = 0
        }

        for pozycja in pozycje {
            switch pozycja {
            case .belka:
                zamknijRzad(nastepnaBelka: true)
                ramki.append(CGRect(x: 0, y: y, width: szerokosc, height: m.wysokoscBelki))
                wysokoscRzedu = m.wysokoscBelki
                poprzedniaBelka = true
                // Następna ikona zaczyna nowy rząd, a nie dosiada się do belki.
                kolumna = liczbaKolumn
            case .program:
                if kolumna >= liczbaKolumn { zamknijRzad(nastepnaBelka: false) }
                ramki.append(CGRect(
                    x: CGFloat(kolumna) * (m.szerokoscKafelka + m.odstepPoziomy),
                    y: y,
                    width: m.szerokoscKafelka,
                    height: m.wysokoscKafelka
                ))
                wysokoscRzedu = max(wysokoscRzedu, m.wysokoscKafelka)
                kolumna += 1
                poprzedniaBelka = false
            }
        }
        return ramki
    }

    /// Wysokość całej siatki dla podanych ramek.
    nonisolated static func wysokosc(ramek ramki: [CGRect]) -> CGFloat {
        ramki.map(\.maxY).max() ?? 0
    }

    /// Gdzie wstawić ciągnięty element, jeśli kursor stoi w tym punkcie.
    ///
    /// Zwraca indeks **w podanej liście**, od 0 do `ramki.count`. Lista musi być tą
    /// **bez** elementu ciągniętego — inaczej celem bywałby on sam, a przeniesienie
    /// czegoś przed samo siebie jest brakiem zmiany. To był błąd zgłoszony przez [U]
    /// 2026-08-22 („udało się przestawić tylko jedną ikonę").
    ///
    /// Trafianie idzie po **geometrii**, a nie po tym, który kafelek zgłosi się jako cel.
    /// Kafelki w trakcie ciągnięcia przesuwają się pod kursorem, więc pytanie „na czym
    /// stoję" nie ma stabilnej odpowiedzi; pytanie „gdzie stoję" ma.
    nonisolated static func indeksWstawienia(punkt: CGPoint, ramki: [CGRect]) -> Int {
        guard !ramki.isEmpty else { return 0 }

        // Najpierw rząd: ten, którego pion obejmuje punkt, a jak żaden — najbliższy.
        var najlepszy = 0
        var najmniejszaOdleglosc = CGFloat.greatestFiniteMagnitude
        for (i, r) in ramki.enumerated() {
            let odlegloscPionowa: CGFloat
            if punkt.y < r.minY { odlegloscPionowa = r.minY - punkt.y }
            else if punkt.y > r.maxY { odlegloscPionowa = punkt.y - r.maxY }
            else { odlegloscPionowa = 0 }
            // W tym samym rzędzie rozstrzyga poziom; między rzędami — pion.
            let odleglosc = odlegloscPionowa * 1000 + abs(punkt.x - r.midX)
            if odleglosc < najmniejszaOdleglosc {
                najmniejszaOdleglosc = odleglosc
                najlepszy = i
            }
        }
        // Lewa połowa kafelka = przed nim, prawa = za nim.
        return punkt.x > ramki[najlepszy].midX ? najlepszy + 1 : najlepszy
    }

    private static let poczatek = "poczatek"

    /// Układa programy według zapisanej kolejności i tnie je belkami.
    ///
    /// Programy, których `kolejnosc` jeszcze nie zna — świeżo doinstalowane — lądują
    /// na końcu, alfabetycznie. Nie wpychamy ich w środek cudzego układu.
    ///
    /// `pokazujPusteBelki` włącza tryb edycji: belka bez ani jednego programu pod sobą
    /// musi być wtedy widoczna, bo inaczej nie dałoby się na nią nic upuścić. Poza edycją
    /// taka belka znika, żeby nie wisiała w siatce jako kreska donikąd.
    nonisolated static func pozycje(
        programy: [InstalledApp],
        kolejnosc: [ElementUkladu],
        separatory: [Separator],
        pokazujPusteBelki: Bool
    ) -> [Pozycja] {
        var poSciezce: [String: InstalledApp] = [:]
        for app in programy { poSciezce[app.id] = app }
        var belkiPoId: [UUID: Separator] = [:]
        for belka in separatory { belkiPoId[belka.id] = belka }

        var wynik: [Pozycja] = []
        // Belka czeka na pierwszy program pod sobą. Bez niego jest kreską donikąd
        // i poza trybem edycji w ogóle się nie pokazuje.
        var czekajaca: Separator?
        var uzyte = Set<String>()

        for element in kolejnosc {
            switch element {
            case .belka(let uuid):
                guard let belka = belkiPoId[uuid] else { continue }
                if pokazujPusteBelki, let poprzednia = czekajaca {
                    wynik.append(.belka(poprzednia))
                }
                czekajaca = belka
            case .program(let sciezka):
                guard let app = poSciezce[sciezka] else { continue }
                if let belka = czekajaca {
                    wynik.append(.belka(belka))
                    czekajaca = nil
                }
                wynik.append(.program(app))
                uzyte.insert(sciezka)
            }
        }

        let nieznane = programy
            .filter { !uzyte.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !nieznane.isEmpty, let belka = czekajaca {
            wynik.append(.belka(belka))
            czekajaca = nil
        }
        wynik.append(contentsOf: nieznane.map { Pozycja.program($0) })

        if pokazujPusteBelki, let belka = czekajaca {
            wynik.append(.belka(belka))
        }
        return wynik
    }

    /// Ta sama treść pocięta na kawałki. Wyprowadzona z `pozycje`, żeby obie postacie
    /// nie miały własnej prawdy i nie rozjechały się przy pierwszej poprawce.
    nonisolated static func ulozenie(
        programy: [InstalledApp],
        kolejnosc: [ElementUkladu],
        separatory: [Separator],
        pokazujPusteBelki: Bool
    ) -> [Segment] {
        var segmenty: [Segment] = []
        var belka: Separator?
        var biezace: [InstalledApp] = []
        var otwarty = false

        func domknij() {
            guard otwarty else { return }
            segmenty.append(Segment(id: belka?.id.uuidString ?? poczatek, belka: belka, programy: biezace))
        }

        for pozycja in pozycje(programy: programy, kolejnosc: kolejnosc,
                               separatory: separatory, pokazujPusteBelki: pokazujPusteBelki) {
            switch pozycja {
            case .belka(let b):
                domknij()
                belka = b
                biezace = []
                otwarty = true
            case .program(let a):
                otwarty = true
                biezace.append(a)
            }
        }
        domknij()
        return segmenty
    }

    /// Dopisuje do kolejności programy, których jeszcze w niej nie ma.
    ///
    /// Wołane przed każdym przesunięciem: dopóki kolejność jest pusta, siatka leci
    /// alfabetycznie i nie ma czego przestawiać. Pierwsze pociągnięcie ikony musi więc
    /// najpierw utrwalić to, co [U] widzi na ekranie, a dopiero potem ruszyć jeden element.
    nonisolated static func domknij(_ kolejnosc: [ElementUkladu], programy: [InstalledApp]) -> [ElementUkladu] {
        var znane = Set<String>()
        for element in kolejnosc {
            if case .program(let sciezka) = element { znane.insert(sciezka) }
        }
        let brakujace = programy
            .filter { !znane.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ElementUkladu.program($0.id) }
        return kolejnosc + brakujace
    }

    /// Przenosi element tuż przed `cel`. `cel == nil` znaczy „na sam koniec".
    ///
    /// Upuszczenie elementu na samego siebie nic nie zmienia — bez tego jedno drgnięcie
    /// myszy przy chwycie liczyłoby się jako przenosiny i lista drgałaby bez powodu.
    nonisolated static func przenies(
        _ co: ElementUkladu,
        przed cel: ElementUkladu?,
        w kolejnosc: [ElementUkladu]
    ) -> [ElementUkladu] {
        guard co != cel else { return kolejnosc }
        var wynik = kolejnosc
        guard let skad = wynik.firstIndex(of: co) else { return kolejnosc }
        wynik.remove(at: skad)

        guard let cel, let dokad = wynik.firstIndex(of: cel) else {
            wynik.append(co)
            return wynik
        }
        wynik.insert(co, at: dokad)
        return wynik
    }

    /// Przenosi element **między sekcjami**: z jednej kolejności do drugiej (AG-23).
    ///
    /// Zwraca obie listy naraz, bo to jest jedna operacja na dwóch zapisach. Samo
    /// wstawienie bez usunięcia zostawiłoby ikonę w obu sekcjach jednocześnie, a samo
    /// usunięcie bez wstawienia — nigdzie.
    ///
    /// `przed == nil` znaczy „na koniec sekcji docelowej". Element wycinamy też z celu,
    /// bo przy przenosinach tam i z powrotem mógł tam jeszcze zostać po starym zapisie.
    nonisolated static func przenies(
        _ co: ElementUkladu,
        zKolejnosci zrodlo: [ElementUkladu],
        doKolejnosci cel: [ElementUkladu],
        przed: ElementUkladu?
    ) -> (zrodlo: [ElementUkladu], cel: [ElementUkladu]) {
        var zZrodla = zrodlo
        zZrodla.removeAll { $0 == co }

        var doCelu = cel
        doCelu.removeAll { $0 == co }

        guard let przed, przed != co, let dokad = doCelu.firstIndex(of: przed) else {
            doCelu.append(co)
            return (zZrodla, doCelu)
        }
        doCelu.insert(co, at: dokad)
        return (zZrodla, doCelu)
    }

    /// Wstawia nową belkę tuż przed `cel` (albo na sam początek, gdy `cel == nil`).
    nonisolated static func wstawBelke(
        _ belka: Separator,
        przed cel: ElementUkladu?,
        w kolejnosc: [ElementUkladu]
    ) -> [ElementUkladu] {
        var wynik = kolejnosc
        let element = ElementUkladu.belka(belka.id)
        guard let cel, let dokad = wynik.firstIndex(of: cel) else {
            wynik.insert(element, at: 0)
            return wynik
        }
        wynik.insert(element, at: dokad)
        return wynik
    }
}
