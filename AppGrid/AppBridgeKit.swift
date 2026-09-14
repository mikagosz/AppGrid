//
//  AppBridgeKit.swift — CAŁY most w jednym pliku.
//
//  🔴 PLIK GENEROWANY. Nie poprawiaj go ręcznie — poprawki przepadną przy
//  następnym uruchomieniu `Skrypty/splaszcz.sh`. Źródła: AppBridgeKit/Sources/.
//
//  Wpięcie do własnej aplikacji (wariant bez ruszania project.pbxproj):
//
//    1. Skopiuj ten plik do katalogu celu w Xcode (przy grupach zsynchronizowanych
//       Xcode wciągnie go sam; inaczej przeciągnij go do projektu).
//    2. W `applicationDidFinishLaunching` albo w `init()` głównej struktury:
//
//         BridgeServer.start(port: 8776, appName: "mojaaplikacja")
//
//    3. Dopisz aplikację do `mcp-server/targets.json` pod tym samym portem.
//
//  Wypięcie: skasuj ten plik i wywołanie z punktu 2.
//
//  W RELEASE cała implementacja jest wycięta przez `#if DEBUG` — zostaje puste
//  API, żeby kod aplikacji kompilował się w obu konfiguracjach bez warunków
//  w każdym miejscu wywołania.
//
//  ⚠️ Ścieżka budowania z nazwą konta w binarce RELEASE — jedna liczba zamiast
//  obietnicy. Pakiet lokalny dokłada do tablicy symboli gospodarza sześć wpisów
//  z obcego modułu `AppBridgeKit.build`. Wariant jednoplikowy kompiluje się razem
//  z celem gospodarza, więc **dokłada JEDEN** wpis (`AppBridgeKit.o`) do tych,
//  które gospodarz i tak ma — mniej, ale nie zero.
//
//  🔴 Do 2026-09-02 stało tu, że wariant „nie dokłada osobnych wpisów i tego
//  problemu nie ma". To była nieprawda i zgłosił to audyt (E5B-P2-04): zmierzone
//  `nm -pa` na binarce RELEASE TestRoomu — sześć wpisów SO/OSO z nazwą konta,
//  z czego jeden wskazuje na `AppBridgeKit.o`. README mówił to poprawnie i z liczbą
//  trzy sekcje dalej; nagłówek istnieje po to, żeby README nie było konieczne.
//
//  Co z tym zrobić: aplikacja przeznaczona do rozdania powinna mieć przepisywanie
//  prefiksów ścieżek (`-debug-prefix-map` / `-file-prefix-map`) tak czy inaczej —
//  most tylko powiększa problem, który zwykle już tam jest.
//

import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import Network
import UniformTypeIdentifiers
import os

#if canImport(AppKit)
import AppKit
#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeActions.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` na poziomie pliku, nie w środku — zamek na dyrektywie, nie na
// optymalizatorze (§3 pkt 1 planu, i naprawa E5N-P1-01 z 2026-08-29). Typ `BridgeAkcja`
// i punkty rejestracji są publiczne, więc gdyby plik stał wyłącznie pod
// `canImport(AppKit)`, jego ciała jechałyby do wydania gospodarza przy pierwszym
// odwołaniu spoza dyrektywy — i żaden dzisiejszy pomiar by tego nie zapowiedział.
#if DEBUG && canImport(AppKit)

/// Czy skutek akcji da się cofnąć — i czym.
///
/// 🔴 **Powód istnienia (plan rozwoju warstwy akcji, poz. 1).** Do 2026-09-03 most
/// nie miał ani jednego pola, w którym gospodarz mógłby powiedzieć „ta akcja jest
/// nieodwracalna". Odpowiedź na pytanie 7 przepisu audytu — *„co most potrafi ZMIENIĆ
/// i czy da się to cofnąć"* — mieszkała w **prozie README** i w komentarzach autora.
/// Zmierzone przy pierwszym wpięciu do gospodarza (poligonie, 2026-09-02): zakres
/// akcji dobierałem ręcznie i uzasadniałem akapitem w `POLIGON.md`, a `GET /akcje`
/// oddawało wyłącznie `nazwa` i `opis`. Agent nie miał jak się dowiedzieć niczego
/// **przed** wywołaniem.
///
/// Nazwa akcji cofającej siedzi w przypadku, a nie obok niego — dzięki temu nie da
/// się zadeklarować „cofa inna akcja" i zapomnieć powiedzieć która.
///
/// Cztery przypadki układają się w drabinkę od najtańszego do najdroższego:
/// most cofa sam → most cofa inną akcją → cofa człowiek → **nie da się**.
/// Potwierdzenia wymaga wyłącznie ostatni szczebel.
public enum BridgeOdwracalnosc: Sendable, Equatable {
    /// Przełącznik — drugie wywołanie tej samej akcji przywraca stan.
    case samaSoba
    /// Cofa **inna** zarejestrowana akcja, o podanej nazwie.
    case innaAkcja(String)
    /// Da się cofnąć, ale **nie akcją mostu** — zrobi to człowiek przy komputerze.
    ///
    /// 🔴 Ten przypadek dołożył **drugi gospodarz, nie projekt** (2026-09-03).
    /// Trzy przypadki wyżej wystarczały na demie; w poligonie pierwsza akcja,
    /// która się w nich nie mieściła, pojawiła się w pierwszej godzinie:
    /// `zamknij-biezace-okno` zamyka okno **na wierzchu**, więc most nie wie, które
    /// zamknął, i nie umie nazwać akcji, która je przywróci. Nic przy tym nie ginie —
    /// użytkownik otwiera okno z powrotem sam.
    ///
    /// Bez tego przypadku trzeba by skłamać (`.innaAkcja` wskazująca nie to okno)
    /// albo przesadzić (`.nieodwracalna`, czyli pytanie o potwierdzenie przy zamykaniu
    /// okna — dokładnie ten hałas, który uczy agenta klikać „tak" odruchowo).
    case przezUzytkownika
    /// 🔴 Mostem nie da się tego cofnąć. Wymaga jawnego potwierdzenia w żądaniu.
    case nieodwracalna

    /// Postać do `GET /akcje` i do odpowiedzi `POST /akcja`.
    public var nazwa: String {
        switch self {
        case .samaSoba:        return "samaSoba"
        case .innaAkcja:       return "innaAkcja"
        case .przezUzytkownika: return "przezUzytkownika"
        case .nieodwracalna:   return "nieodwracalna"
        }
    }

    /// Nazwa akcji cofającej — wyłącznie dla `.innaAkcja`.
    public var cofaJa: String? {
        if case .innaAkcja(let nazwa) = self { return nazwa }
        return nil
    }

    /// Czy wywołanie wymaga jawnego potwierdzenia w ciele żądania.
    public var wymagaPotwierdzenia: Bool { self == .nieodwracalna }
}

/// Czy tę akcję da się **teraz** wykonać — i jeśli nie, to dlaczego.
///
/// 🔴 **Powód istnienia (plan rozwoju mostu po 1.2.14, poz. 2).** Zmierzone:
/// `klikniecie` na przycisku wyłączonym daje `klikniec = 0, zmienilo = []`, a kontrola
/// dodatnia na tym samym przycisku włączonym — `klikniec = 1, zmienilo = ["klikniec"]`.
/// Odpowiedź jest uczciwa i **bezużyteczna**: agent nie odróżni „nic się nie stało,
/// bo akcja nic nie robi" od „nic się nie stało, bo przycisk był szary". To samo
/// z `zamknij-biezace-okno` przy zamkniętych oknach — akcja istnieje, jest bezsensowna,
/// i most o tym nie mówi.
///
/// Ta sama filozofia co przy `BridgeOdwracalnosc`: wiedza, którą ma **wyłącznie autor
/// aplikacji**, podana raz przy rejestracji, zamiast zgadywania po stronie mostu.
///
/// 🔴 **Powód jest w przypadku, nie obok niego.** `dostepna: false` bez zdania jest
/// dokładnie tak samo bezużyteczne jak dzisiejsze `zmienilo: []` — mówi, że coś jest
/// nie tak, i nie mówi co. Ten kształt (jak `.innaAkcja(String)`) nie pozwala
/// zadeklarować niedostępności i zapomnieć powiedzieć dlaczego.
public enum BridgeDostepnosc: Sendable, Equatable {
    /// Akcję da się teraz wykonać.
    case tak
    /// Nie da się — i to jest powód, zdaniem dla człowieka po drugiej stronie.
    case nie(String)

    /// Powód odmowy, albo `nil` gdy akcja jest dostępna.
    public var powod: String? {
        if case .nie(let zdanie) = self { return zdanie }
        return nil
    }

    public var czyDostepna: Bool { self == .tak }
}

/// Co wolno przysłać jako wartość argumentu akcji.
///
/// 🔴 **Tu stoi granica, na której trzyma się bezpieczeństwo całej warstwy.**
/// Sedno warstwy brzmi: *akcje są NAZWANE, nigdy współrzędne* — „kliknij Usuń" jest
/// niemożliwe, jeśli nikt tego nie zarejestrował, a pętla „znajdź przez `/hit`
/// i kliknij" jest z tego kształtu niedomykalna. Argument o **dowolnej treści**
/// otworzyłby tę granicę po cichu: akcja `otworz(nazwaOkna:)` przyjmująca dowolny
/// napis jest o krok od `kliknij(x:y:)`.
///
/// Dlatego **nie ma tu przypadku „dowolny napis"** i nie wolno go dopisać. Wartość
/// pochodzi albo z **zamkniętej listy**, którą wypisał gospodarz, albo z **zakresu
/// liczbowego**, który wyznaczył gospodarz, albo jest wartością logiczną. Nic, co
/// przyszło z sieci, nie jedzie do domknięcia bez przejścia przez jedno z tych trzech.
///
/// Ten kształt jest wzięty wprost z `BridgeDefaults.allow`, gdzie biała lista sprawdza
/// **wartość**, nie sam klucz — naprawa E5-P2-02 z 2026-08-28, po tym jak pod
/// „Double 9…24" wchodził napis, słownik i miliard.
///
/// ⚠️ Czego to NIE obiecuje: gospodarz może własnymi rękami napisać akcję
/// `kliknij(x:y:)` na dwóch zakresach liczbowych. Most mu tego nie zabroni i nie
/// udaje, że zabrania — obiecuje co innego: **sam nigdy takiej akcji nie oferuje
/// i nigdy nie szuka widoków**. Granica dotyczy mostu, nie cudzej wyobraźni.
public enum BridgeDozwolone: Sendable {
    /// Zamknięta lista dopuszczalnych napisów, wypisana przez gospodarza.
    case lista([String])
    /// Zakres liczb całkowitych wyznaczony przez gospodarza.
    case zakres(ClosedRange<Int>)
    /// Wartość logiczna.
    case logiczna

    var opisDlaAgenta: String {
        switch self {
        case .lista(let wartosci): return "jedna z: " + wartosci.joined(separator: ", ")
        case .zakres(let z):       return "liczba całkowita \(z.lowerBound)…\(z.upperBound)"
        case .logiczna:            return "true albo false"
        }
    }

    /// Sprawdza wartość z żądania i oddaje ją w postaci, którą dostanie domknięcie.
    /// Rzuca zdaniem mówiącym, co było wolno — nigdy gołym „zła wartość".
    func sprawdz(_ surowa: Any?, nazwa: String, akcja: String) throws -> Any {
        switch self {
        case .lista(let wartosci):
            guard let napis = surowa as? String else {
                throw BridgeError.badRequest(
                    "Argument \"\(nazwa)\" akcji \"\(akcja)\" ma być napisem — \(opisDlaAgenta)."
                )
            }
            guard wartosci.contains(napis) else {
                throw BridgeError.badRequest(
                    "Argument \"\(nazwa)\" akcji \"\(akcja)\" dostał "
                    + "\"\(BridgeDefaults.skrocony(napis, do: 40))\", a wolno \(opisDlaAgenta)."
                )
            }
            return napis
        case .zakres(let zakres):
            guard let liczba = surowa as? Int else {
                throw BridgeError.badRequest(
                    "Argument \"\(nazwa)\" akcji \"\(akcja)\" ma być liczbą całkowitą — \(opisDlaAgenta)."
                )
            }
            guard zakres.contains(liczba) else {
                throw BridgeError.badRequest(
                    "Argument \"\(nazwa)\" akcji \"\(akcja)\" dostał \(liczba), a wolno \(opisDlaAgenta)."
                )
            }
            return liczba
        case .logiczna:
            guard let wartosc = surowa as? Bool else {
                throw BridgeError.badRequest(
                    "Argument \"\(nazwa)\" akcji \"\(akcja)\" ma być \(opisDlaAgenta)."
                )
            }
            return wartosc
        }
    }
}

/// Jeden argument, który gospodarz **świadomie** wystawia razem z akcją.
public struct BridgeParametr: Sendable {
    public let nazwa: String
    public let opis: String
    public let dozwolone: BridgeDozwolone

    public init(nazwa: String, opis: String = "", dozwolone: BridgeDozwolone) {
        self.nazwa = nazwa
        self.opis = opis
        self.dozwolone = dozwolone
    }
}

/// Jedna akcja, którą gospodarz **świadomie** wystawia mostowi.
///
/// 🔴 Sedno bezpieczeństwa całej warstwy (§3 pkt 3 planu): most **nie klika w punkt**.
/// Wywołać da się wyłącznie to, co autor aplikacji zarejestrował pod nazwą — więc
/// nawet obejście zamka nr 3 nie daje dostępu do niczego, czego nikt nie wystawił.
/// Pętla „znajdź przez `/hit` i kliknij" jest z tego kształtu **niemożliwa do domknięcia**.
@MainActor
public struct BridgeAkcja {
    /// Nazwa w żądaniu `POST /akcja {"akcja": "..."}`. Bez rozróżniania wielkości liter.
    public let nazwa: String
    /// Zdanie dla człowieka po drugiej stronie mostu — co ta akcja robi.
    public let opis: String
    /// Czy skutek da się cofnąć. **Bez wartości domyślnej i to jest celowe** —
    /// most nie zgaduje, tak samo jak biała lista `BridgeDefaults` nie zgaduje typu.
    /// Autor, który nie chce się nad tym zastanowić, ma się nad tym zastanowić.
    public let odwracalnosc: BridgeOdwracalnosc
    /// Ile najdłużej most ma czekać, aż sonda TEJ akcji przestanie się zmieniać.
    /// `nil` = sufit projektu (`BridgeLimity.sufitUstabilizowaniaMs`).
    ///
    /// 🔴 **Deklaruje GOSPODARZ, nigdy agent** (plan rozwoju, poz. 4). Reguła projektu
    /// „sufitów nie dobiera agent" zostaje nienaruszona: to nie jest liczba w żądaniu,
    /// tylko wiedza autora aplikacji o własnym oknie, podana raz przy rejestracji.
    /// Autor wie, że jego widok buduje się pół sekundy — most nie ma jak tego zgadnąć.
    ///
    /// Zmierzone 2026-09-02 na poligonie: `czekanoMs` **66 ms** dla akcji bez skutku
    /// i **95–152 ms** dla otwierającej okno SwiftUI. Jeden sufit obsługuje oba, ale
    /// przełącznik tytułu i budowa ciężkiego widoku to nie ten sam rząd wielkości.
    public let sufitUstabilizowaniaMs: Int?
    /// Argumenty, które ta akcja przyjmuje. Puste = akcja bez argumentów.
    /// Każdy ma **zamkniętą** dziedzinę wartości — patrz `BridgeDozwolone`.
    public let parametry: [BridgeParametr]
    /// Kilka liczb albo napisów o stanie, próbkowanych **przed** akcją i **po**.
    ///
    /// ⚠️ **Kontrakt: sonda ma być tania i bez skutków ubocznych.** Most woła ją
    /// wielokrotnie — przed akcją, po niej i w pętli ustabilizowania. Sonda, która
    /// coś zmienia, zmierzy własny skutek.
    public let sonda: @MainActor () -> [String: Any]
    /// Czy akcję da się **teraz** wykonać. `nil` = gospodarz nie zadeklarował,
    /// więc most zakłada, że da się — i mówi to wprost zamiast zgadywać.
    ///
    /// 🔴 **Predykat to SONDA, nie akcja.** Obowiązuje go ten sam kontrakt: tani,
    /// bez skutków ubocznych. Most woła go przy każdym `GET /akcje` i raz przed
    /// wykonaniem, więc predykat, który coś zmienia, zmieni to przy zwykłym pytaniu
    /// o listę — czyli przy odczycie, o którym cały most obiecuje, że nie zmienia
    /// tego, co mierzy.
    public let dostepnosc: (@MainActor () -> BridgeDostepnosc)?
    /// Samo działanie. Rzucenie kończy się odpowiedzią 500 **razem z sondą „po"**,
    /// bo akcja mogła zdążyć coś zmienić, zanim rzuciła.
    ///
    /// Dostaje **sprawdzone** wartości argumentów — nigdy surowego JSON-a z żądania.
    /// Akcja bez argumentów dostaje pusty słownik i może go zignorować.
    public let wykonaj: @MainActor ([String: Any]) throws -> Void

    public init(
        nazwa: String,
        opis: String = "",
        odwracalnosc: BridgeOdwracalnosc,
        sufitUstabilizowaniaMs: Int? = nil,
        parametry: [BridgeParametr] = [],
        sonda: @escaping @MainActor () -> [String: Any],
        dostepnosc: (@MainActor () -> BridgeDostepnosc)? = nil,
        wykonaj: @escaping @MainActor ([String: Any]) throws -> Void
    ) {
        self.nazwa = nazwa
        self.opis = opis
        self.odwracalnosc = odwracalnosc
        self.sufitUstabilizowaniaMs = sufitUstabilizowaniaMs
        self.parametry = parametry
        self.sonda = sonda
        self.dostepnosc = dostepnosc
        self.wykonaj = wykonaj
    }

    /// Akcja bez argumentów — domknięcie nie musi przyjmować pustego słownika.
    public init(
        nazwa: String,
        opis: String = "",
        odwracalnosc: BridgeOdwracalnosc,
        sufitUstabilizowaniaMs: Int? = nil,
        sonda: @escaping @MainActor () -> [String: Any],
        dostepnosc: (@MainActor () -> BridgeDostepnosc)? = nil,
        wykonaj: @escaping @MainActor () throws -> Void
    ) {
        self.init(nazwa: nazwa, opis: opis, odwracalnosc: odwracalnosc,
                  sufitUstabilizowaniaMs: sufitUstabilizowaniaMs, parametry: [],
                  sonda: sonda, dostepnosc: dostepnosc, wykonaj: { _ in try wykonaj() })
    }
}

/// Warstwa akcji nazwanych — jedyna droga, którą most może cokolwiek zrobić
/// w interfejsie gospodarza.
///
/// 🔴 **„Wyłącznie odczyt" przestaje być regułą całego mostu i staje się stanem
/// DOMYŚLNYM**, który gospodarz wyłącza świadomie i punktowo (§2 planu). Dwa zamki
/// naraz i oba są konieczne:
/// 1. `#if DEBUG` — warstwy nie ma w wydaniu w ogóle,
/// 2. `wlacz()` — w samym DEBUG też jest wyłączona, dopóki gospodarz jej nie włączy.
///    Build DEBUG chodzi na maszynie dewelopera cały dzień; sama dyrektywa nie wystarcza.
@MainActor
public enum BridgeActions {

    private static var akcje: [BridgeAkcja] = []
    private static var wlaczona = false

    /// Czy warstwa jest włączona. Do `/routes` i do komunikatów odmowy.
    public static var czyWlaczona: Bool { wlaczona }

    /// Włącza warstwę akcji. **Wywołaj świadomie**, obok `BridgeServer.start`.
    ///
    /// W RELEASE pusta — powód ten sam co przy `BridgeRegistry.registerOnMainActor`:
    /// `@inlinable` z pustym ciałem pozwala optymalizatorowi wyrzucić także literały,
    /// które gospodarz zbudował w miejscu wywołania.
    @inlinable
    public static func wlacz() {
        #if DEBUG
        ustawWlaczona(true)
        #endif
    }

    /// Publiczna, bo woła ją `@inlinable` wyżej.
    public static func ustawWlaczona(_ wartosc: Bool) {
        #if DEBUG
        wlaczona = wartosc
        #endif
    }

    /// Zgłasza mostowi akcję, którą wolno wywołać.
    ///
    /// ```swift
    /// BridgeActions.register(
    ///     nazwa: "nie-teraz",
    ///     opis: "Zamyka okno aktywacji bez podawania klucza",
    ///     odwracalnosc: .innaAkcja("otworz-aktywacje"),
    ///     sonda: { ["okien": NSApp.windows.filter(\.isVisible).count] }
    /// ) {
    ///     oknoAktywacji.close()
    /// }
    /// ```
    @inlinable
    public static func register(
        nazwa: String,
        opis: String = "",
        odwracalnosc: BridgeOdwracalnosc,
        sufitUstabilizowaniaMs: Int? = nil,
        sonda: @escaping @MainActor () -> [String: Any],
        dostepnosc: (@MainActor () -> BridgeDostepnosc)? = nil,
        _ wykonaj: @escaping @MainActor () throws -> Void
    ) {
        #if DEBUG
        zarejestruj(BridgeAkcja(nazwa: nazwa, opis: opis, odwracalnosc: odwracalnosc,
                                sufitUstabilizowaniaMs: sufitUstabilizowaniaMs,
                                sonda: sonda, dostepnosc: dostepnosc, wykonaj: wykonaj))
        #endif
    }

    /// Zgłasza akcję **z argumentami**. Dziedzinę każdego wypisuje gospodarz.
    ///
    /// ```swift
    /// BridgeActions.register(
    ///     nazwa: "otworz-okno",
    ///     opis: "Otwiera jedno z okien programu",
    ///     odwracalnosc: .innaAkcja("zamknij-biezace-okno"),
    ///     parametry: [.init(nazwa: "ktore", dozwolone: .lista(["ustawienia", "pomoc"]))],
    ///     sonda: { BridgeActions.sondaOkien() }
    /// ) { argumenty in
    ///     otworz(argumenty["ktore"] as? String)   // wartość JUŻ sprawdzona
    /// }
    /// ```
    @inlinable
    public static func register(
        nazwa: String,
        opis: String = "",
        odwracalnosc: BridgeOdwracalnosc,
        sufitUstabilizowaniaMs: Int? = nil,
        parametry: [BridgeParametr],
        sonda: @escaping @MainActor () -> [String: Any],
        dostepnosc: (@MainActor () -> BridgeDostepnosc)? = nil,
        _ wykonaj: @escaping @MainActor ([String: Any]) throws -> Void
    ) {
        #if DEBUG
        zarejestruj(BridgeAkcja(nazwa: nazwa, opis: opis, odwracalnosc: odwracalnosc,
                                sufitUstabilizowaniaMs: sufitUstabilizowaniaMs,
                                parametry: parametry, sonda: sonda,
                                dostepnosc: dostepnosc, wykonaj: wykonaj))
        #endif
    }

    /// Skrót na najczęstszy przypadek — kliknięcie w przycisk, który gospodarz
    /// i tak trzyma u siebie.
    ///
    /// 🔴 **To jest cukier na domknięciu, nie druga droga.** Most nadal nie szuka
    /// widoków po nazwie i nie zna hierarchii — przycisk przychodzi z kodu gospodarza.
    /// Gdyby most umiał go znaleźć sam, pętla „znajdź przez `/hit` i kliknij" byłaby
    /// do domknięcia, a tego §5 planu zabrania wprost.
    ///
    /// ⚠️ **Dwie flagi przycisku, tylko jedna z nich zatrzymuje wywołanie** —
    /// zmierzone (audyt warstwy klikania 2026-09-02, E1-P3-02):
    /// - `isEnabled == false` → **akcja NIE odpala się** (0 wywołań; kontrola
    ///   dodatnia na tym samym przycisku włączonym: 1). Zakaz, który użytkownik
    ///   widzi na ekranie jako wyszarzenie, obowiązuje też most.
    /// - `isHidden == true` → **akcja ODPALA SIĘ** (1 wywołanie). Ukrycie kontrolki
    ///   nie jest w AppKicie zakazem, więc przycisk na niewidocznej zakładce albo
    ///   w zamkniętym panelu da się wcisnąć mostem.
    ///
    /// Jeśli niewidoczność ma być u Ciebie zakazem, sprawdź ją w domknięciu akcji —
    /// most tego za Ciebie nie zrobi, bo nie wie, co w Twoim programie znaczy
    /// „schowane".
    @inlinable
    public static func klikniecie(
        nazwa: String,
        opis: String = "",
        odwracalnosc: BridgeOdwracalnosc,
        przycisk: NSControl,
        sonda: @escaping @MainActor () -> [String: Any]
    ) {
        #if DEBUG
        // 🔴 Dostępność za darmo, bez pracy gospodarza — bo TU most zna przycisk.
        // To jedyne miejsce w warstwie, w którym most może odpowiedzieć na pytanie
        // „czy da się to teraz zrobić" sam, nie zgadując: `isEnabled` jest zakazem
        // AppKitu, ten sam, który zatrzymuje `performClick`. Wszędzie indziej wiedzę
        // tę ma wyłącznie autor aplikacji i musi ją podać.
        register(
            nazwa: nazwa, opis: opis, odwracalnosc: odwracalnosc, sonda: sonda,
            dostepnosc: {
                przycisk.isEnabled
                    ? .tak
                    : .nie("Przycisk stojący za akcją \"\(nazwa)\" jest wyłączony "
                           + "(isEnabled == false), więc kliknięcie nic by nie zrobiło. "
                           + "To zakaz, który użytkownik widzi na ekranie jako wyszarzenie.")
            }
        ) {
            przycisk.performClick(nil)
        }
        #endif
    }

    /// Czy dwie nazwy akcji znaczą to samo.
    ///
    /// 🔴 **Jedno miejsce, bo do 2026-09-02 były dwa i znaczyły co innego**
    /// (audyt warstwy klikania, E1-P3-01): rejestracja odsiewała po `lowercased()`,
    /// czyli niezależnie od ustawień regionalnych, a wyszukanie szło przez
    /// `localizedCaseInsensitiveCompare`, czyli zależnie od nich. Przy niepolskich
    /// ustawieniach rejestr i wyszukanie mogły się rozjechać: nazwa odsiana przy
    /// rejestracji jako duplikat i nieznaleziona przy wywołaniu.
    ///
    /// Porównanie jest **nielokalizowane** świadomie. Nazwa akcji to identyfikator
    /// w protokole, nie tekst dla człowieka — ma znaczyć to samo na każdej maszynie,
    /// niezależnie od tego, jaki region ustawił u siebie autor gospodarza.
    static func taSamaNazwa(_ jedna: String, _ druga: String) -> Bool {
        jedna.compare(druga, options: [.caseInsensitive]) == .orderedSame
    }

    /// Rejestracja właściwa. Publiczna, bo wołają ją `@inlinable` wyżej.
    public static func zarejestruj(_ akcja: BridgeAkcja) {
        #if DEBUG
        // Podmiana przy tej samej nazwie jest zamierzona — ale do 2026-09-02 była
        // CICHA, więc gospodarz rejestrujący „Zapisz" i „ZAPISZ" tracił jedną akcję
        // i nigdzie się o tym nie dowiadywał (E1-P3-01).
        if let poprzednia = akcje.first(where: { taSamaNazwa($0.nazwa, akcja.nazwa) }) {
            print("""
                [AppBridge] ⚠️ Akcja \"\(poprzednia.nazwa)\" została zastąpiona przez \
                \"\(akcja.nazwa)\" — most nie rozróżnia wielkości liter w nazwach akcji, \
                więc obie znaczą to samo i zostaje ostatnia zgłoszona.
                """)
        }
        akcje.removeAll { taSamaNazwa($0.nazwa, akcja.nazwa) }
        akcje.append(akcja)
        #endif
    }

    /// Zgłoszone akcje — do `/akcje` i do komunikatów odmowy.
    public static var zgloszone: [BridgeAkcja] { akcje }

    /// Czyści rejestr i gasi warstwę. **Wyłącznie dla testów** — powód ten sam
    /// co w `BridgeWindows.wyczysc`: rejestr jest globalny dla procesu.
    static func wyczysc() {
        akcje.removeAll()
        wlaczona = false
        torZajety = false
        wKolejce.removeAll()
    }

    // MARK: - Sonda gotowa

    /// Sonda okien do wzięcia jednym wywołaniem — punkt startu, nie obowiązek.
    ///
    /// 🔴 **Powód istnienia (plan rozwoju, poz. 3): pierwszy autor sondy wybrał
    /// niedokładnie w pierwszej godzinie, i tym autorem byłem ja.** Zmierzone
    /// 2026-09-02 na poligonie: akcja `otworz-informacje-o-urzadzeniu` wywołana
    /// przy JUŻ otwartym oknie oddała `zmienilo: []` i to była prawda — ale okno
    /// prawdopodobnie wyszło na wierzch, czego moja sonda nie mierzyła. Liczyła okna,
    /// tytuły i stan panelu; **nie liczyła, które okno jest na wierzchu**.
    ///
    /// Most nadal nie zgaduje, co obserwować — to jest wiedza gospodarza. Przestaje
    /// za to kazać każdemu autorowi wymyślać od zera cztery pola, które w aplikacji
    /// okienkowej są potrzebne prawie zawsze.
    ///
    /// Kontrakt sondy jest tu **spełniony z definicji**: sam odczyt `NSApplication`,
    /// zero skutków ubocznych, same napisy i liczby. Okna techniczne mostu odsiane
    /// tym samym sitem co w `GET /windows` — jedno pojęcie „okna aplikacji" w całym
    /// kicie, żeby sonda nie liczyła ikonki mostu jako okna gospodarza.
    ///
    /// Dokładanie własnych pól:
    /// ```swift
    /// sonda: {
    ///     var stan = BridgeActions.sondaOkien()
    ///     stan["niezapisanych"] = magazyn.brudne.count
    ///     return stan
    /// }
    /// ```
    public static func sondaOkien() -> [String: Any] {
        let czyOknoAplikacji: (NSWindow) -> Bool = {
            $0.isVisible && BridgeViewLookup.powodOdsiania($0) == nil
        }
        let widoczne = NSApplication.shared.windows.filter(czyOknoAplikacji)

        // 🔴 `orderedWindows`, NIE `keyWindow` — i to jest poprawka z pomiaru, nie
        // z lektury. Pierwsza wersja tej sondy (ten sam dzień, godzinę wcześniej)
        // brała `keyWindow` i na żywym demie oddawała **pusty napis przed akcją i po
        // niej**: `keyWindow` jest `nil`, dopóki aplikacja nie jest aktywna — czyli
        // dokładnie w sytuacji, w której most jest używany, bo agent nie klika w okna.
        // Pole miało łapać „okno wyszło na wierzch" i nie łapało go ani razu.
        //
        // `orderedWindows` daje kolejność od przodu w obrębie aplikacji i nie pyta,
        // czy aplikacja jest na wierzchu ekranu.
        let odPrzodu = NSApplication.shared.orderedWindows.filter(czyOknoAplikacji)

        return [
            "okienWidocznych": widoczne.count,
            "tytuly": widoczne.map(\.title).filter { !$0.isEmpty }.sorted().joined(separator: " | "),
            // To pole jest powodem, dla którego ta sonda istnieje.
            "oknoNaWierzchu": odPrzodu.first?.title ?? "",
            // Kolejność ma znaczenie: sam zbiór tytułów nie odróżnia „okno wyszło
            // na wierzch" od „nic się nie stało".
            "kolejnoscOkien": odPrzodu.map(\.title).joined(separator: " | "),
        ]
    }

    // MARK: - Tor akcji (jedna naraz)

    /// Czy jakaś akcja jest właśnie w toku — od wywołania domknięcia do końca
    /// pomiaru „po".
    private static var torZajety = false

    /// Akcje czekające na swoją kolej, w kolejności zgłoszenia.
    private static var wKolejce: [CheckedContinuation<Void, Never>] = []

    /// 🔴 **Akcje idą jedna po drugiej — decyzja [U] 2026-09-02 („kolejka").**
    ///
    /// Powód (audyt warstwy klikania, E1-P1-02): do tego dnia dwie akcje potrafiły
    /// się przepleść i **pomiar jednej łapał skutek drugiej**. Zmierzone na demie —
    /// sześć równoległych `POST /akcja przelacz-tytul`, trzy odpowiedzi z sześciu
    /// mówiły `zmienilo: []`, choć każde przełączenie się wykonało.
    ///
    /// Ciało akcji jest synchroniczne, więc przerwać się nie dawało nigdy. Przeplatał
    /// się POMIAR: `ustabilizuj` czeka przez `await`, a to zwalnia głównego aktora
    /// dokładnie tak, jak zrobiłaby zagnieżdżona pętla główna — czyli daje ten sam
    /// skutek, przed którym broni się komentarz przy `wykonaj`.
    ///
    /// Zakleszczenie jest tu niemożliwe i warto wiedzieć dlaczego: żeby akcja
    /// zaczekała na samą siebie, musiałaby zawołać most **w trakcie** własnego
    /// domknięcia — a domknięcie jest synchroniczne i nie ma jak w nim czekać na
    /// odpowiedź HTTP. Akcja, która zleca coś na później, wraca tu normalną drogą,
    /// czyli po zwolnieniu toru.
    /// Ilu czeka przede mną w chwili wejścia do kolejki. Do odpowiedzi — czekanie
    /// samo w sobie nie mówi, czy most jest wolny, czy po prostu zajęty przez innych.
    private static func zajmijTor() async -> Int {
        guard torZajety else { torZajety = true; return 0 }
        let przedeMna = wKolejce.count + 1
        await withCheckedContinuation { kontynuacja in
            wKolejce.append(kontynuacja)
        }
        // Wznowienie znaczy, że tor jest już nasz — poprzednik przekazał go wprost,
        // nie zwalniając. Gdyby zwalniał, między jego `false` a naszym `true`
        // zmieściłaby się trzecia akcja.
        return przedeMna
    }

    /// Ile akcji jest **teraz** w torze — bez zajmowania go i bez czekania.
    ///
    /// 🔴 Powód istnienia (audyt 1.2.15–1.2.18, P2-02): podgląd świadomie nie zajmuje
    /// toru, bo nic nie zmienia — i to zostaje. Ale `wykonaj` zwalnia głównego aktora
    /// na `await ustabilizuj(...)`, więc podgląd może wejść **w środek cudzej akcji**
    /// i zawołać sondę gospodarza, gdy stan jest w połowie zmiany. `wykonaj` oddaje
    /// wtedy `przedeMnaWkolejce`, a podgląd do 1.2.18 nie oddawał nic — człowiek
    /// widział liczby, które za sekundę będą inne, i nie miał jak tego poznać.
    ///
    /// Odczyt, nie zajęcie: podgląd ma zostać tani i nieblokujący. Obie zmienne stoją
    /// pod głównym aktorem, więc to sięgnięcie nie rozluźnia niczego.
    static var akcjeWtoku: Int {
        (torZajety ? 1 : 0) + wKolejce.count
    }

    private static func zwolnijTor() {
        if wKolejce.isEmpty {
            torZajety = false
        } else {
            wKolejce.removeFirst().resume()
        }
    }

    // MARK: - Wykonanie

    /// Sufity tej warstwy mieszkają w `BridgeLimity` razem z resztą sufitów projektu.
    /// Te dwie nazwy zostają, żeby czytelnik tego pliku nie musiał skakać do drugiego.
    static var sufitUstabilizowaniaMs: Int { BridgeLimity.sufitUstabilizowaniaMs }

    /// Sprawdza argumenty żądania wobec deklaracji gospodarza.
    ///
    /// Trzy rodzaje odmowy, każda ze zdaniem mówiącym, co było wolno:
    /// brak wymaganego argumentu, wartość spoza dziedziny, argument nieznany.
    ///
    /// 🔴 Nieznany argument to **odmowa, nie ciche pominięcie**. Ciche pominięcie
    /// znaczyłoby, że literówka w nazwie argumentu wykonuje akcję z wartością
    /// domyślną — czyli coś innego, niż wołający zamówił, przy kodzie 200.
    /// Ta sama zasada, co przy białej liście `/defaults`.
    static func sprawdzArgumenty(_ akcja: BridgeAkcja, surowe: [String: Any]) throws -> [String: Any] {
        let zadeklarowane = Set(akcja.parametry.map(\.nazwa))
        if let obcy = surowe.keys.first(where: { !zadeklarowane.contains($0) }) {
            let lista = akcja.parametry.isEmpty
                ? "ta akcja nie przyjmuje żadnych argumentów"
                : "przyjmuje: " + akcja.parametry.map(\.nazwa).joined(separator: ", ")
            throw BridgeError.badRequest(
                "Akcja \"\(akcja.nazwa)\" nie zna argumentu "
                + "\"\(BridgeDefaults.skrocony(obcy, do: 40))\" — \(lista). "
                + "Pełny opis argumentów daje GET /akcje."
            )
        }

        var wynik: [String: Any] = [:]
        for parametr in akcja.parametry {
            guard let surowa = surowe[parametr.nazwa] else {
                throw BridgeError.badRequest(
                    "Akcja \"\(akcja.nazwa)\" wymaga argumentu \"\(parametr.nazwa)\" — "
                    + "\(parametr.dozwolone.opisDlaAgenta)."
                    + (parametr.opis.isEmpty ? "" : " \(parametr.opis)")
                )
            }
            wynik[parametr.nazwa] = try parametr.dozwolone.sprawdz(
                surowa, nazwa: parametr.nazwa, akcja: akcja.nazwa
            )
        }
        return wynik
    }

    /// Sufit obowiązujący TĘ akcję: deklaracja gospodarza albo wartość projektu.
    /// Wartość niedodatnia jest traktowana jak brak deklaracji — sufit zerowy nie
    /// oznaczałby „nie czekaj", tylko „nie mierz", a to jest cała ta warstwa.
    static func sufitDlaAkcji(_ akcja: BridgeAkcja) -> Int {
        guard let wlasny = akcja.sufitUstabilizowaniaMs, wlasny > 0 else {
            return BridgeLimity.sufitUstabilizowaniaMs
        }
        return wlasny
    }
    static var krokProbkowaniaMs: Int { BridgeLimity.krokProbkowaniaMs }

    /// Wykonuje akcję i **mierzy jej skutek**.
    ///
    /// 🔴 Powód istnienia całej tej funkcji: sama zgoda niczego nie dowodzi. Puste
    /// okno aktywacji z 2026-09-01 odpowiadało `200` i to była prawda — brakowało nie
    /// kodu odpowiedzi, tylko pomiaru. Dlatego odpowiedź niesie stan **przed** i **po**,
    /// a różnicę wylicza most, nie czytający.
    ///
    /// `async`, bo czekanie na ustabilizowanie idzie przez `await` w zadaniu, w którym
    /// most i tak już jest (`BridgeServer.swift`, gałąź `.akcja`). Zagnieżdżonej pętli
    /// głównej **nie ma i nie może być** — obsłużyłaby w międzyczasie inne żądania,
    /// czyli akcja mogłaby zostać przerwana inną akcją.
    /// Co ta akcja zastanie — **bez wykonania jej**.
    ///
    /// 🔴 **Powód istnienia (plan rozwoju mostu po 1.2.14, poz. 3).** Zamek potwierdzenia
    /// (1.2.10) mówi agentowi: *„Zanim to zrobisz, upewnij się, że użytkownik tego chce"* —
    /// a agent nie ma jak **pokazać**, czego. Ma nazwę akcji, opis i tyle; to za mało,
    /// żeby człowiek świadomie powiedział „tak" przy działaniu bez drogi powrotnej.
    /// Zmierzone 2026-09-03 na poligonie: `/routes` wymieniało **26 tras** i ani jednej,
    /// która odpowiada na pytanie „co się stanie, gdy to zawołam".
    ///
    /// 🔴 **Argumenty sprawdzane PRZED suchym biegiem, nie po** (§4 planu). Sucha
    /// odpowiedź, która nie przeszła walidacji, kłamie o tym, co się stanie: pokazywałaby
    /// skutek wywołania, które i tak skończy się odmową 400.
    ///
    /// ⚠️ **Nie zajmuje toru akcji i nie liczy się do licznika zmian** — nic nie zmienia,
    /// więc nie ma czego szeregować ani pokazywać użytkownikowi jako zmianę. Dlatego
    /// stoi za **własną trasą**, nie za flagą w `POST /akcja`: tamta trasa jest w kicie
    /// oznaczona jako pisząca, więc suchy bieg dziedziczyłby po niej sufit dla zapisu
    /// i wpis `zmienil: true` w historii — czyli kłamałby w `GET /historia` o tym,
    /// że coś zmienił.
    ///
    /// 🔴 **Czego to NIE robi: nie przewiduje skutku.** Most nie zna treści domknięcia
    /// gospodarza i nie umie go zasymulować. Suchy bieg pokazuje **stan teraz** i to,
    /// co gospodarz **zadeklarował** — nigdy „tak będzie po". Nazwa „na sucho" obiecuje
    /// więcej, niż da się dotrzymać, więc odpowiedź mówi to wprost, zamiast pozwolić
    /// czytającemu się domyślić.
    static func podglad(
        nazwa surowaNazwa: String,
        argumenty: [String: Any] = [:]
    ) throws -> [String: Any] {
        guard wlaczona else {
            throw BridgeError.badRequest(
                "Warstwa akcji jest wyłączona i to jest stan domyślny — most jest do odczytu, "
                + "dopóki aplikacja nie zdecyduje inaczej. Podgląd akcji też jest wtedy "
                + "pytaniem o nic. Żeby ją włączyć, dopisz w niej BridgeActions.wlacz() "
                + "obok BridgeServer.start."
            )
        }
        guard let akcja = akcje.first(where: { taSamaNazwa($0.nazwa, surowaNazwa) }) else {
            let dostepne = akcje.isEmpty ? "(żadnych)" : akcje.map(\.nazwa).joined(separator: ", ")
            throw BridgeError.notFound(
                "Ta aplikacja nie zgłosiła akcji \"\(BridgeDefaults.skrocony(surowaNazwa, do: 40))\". "
                + "Dostępne: \(dostepne)"
            )
        }

        // 🔴 PRZED próbkowaniem, nie po — patrz uwaga w dokumentacji wyżej.
        let sprawdzone = try sprawdzArgumenty(akcja, surowe: argumenty)

        var wynik: [String: Any] = [
            "akcja": akcja.nazwa,
            "opis": akcja.opis,
            "odwracalnosc": akcja.odwracalnosc.nazwa,
            "wymagaPotwierdzenia": akcja.odwracalnosc.wymagaPotwierdzenia,
            // Stan **teraz**, tą samą sondą, którą most weźmie jako „przed" przy
            // prawdziwym wywołaniu. Ta sama droga, więc podgląd nie pokazuje czegoś
            // innego niż to, co potem trafi do odpowiedzi akcji.
            "stan": try probkuj(akcja, kiedy: "podgląd"),
            // Argumenty PO sprawdzeniu — to, co naprawdę dojedzie do domknięcia
            // gospodarza, a nie to, co przysłał klient.
            "argumenty": sprawdzone,
            "sufitUstabilizowaniaMs": sufitDlaAkcji(akcja),
            "wykonano": false,
            // 🔴 Zdanie, bez którego cała ta odpowiedź wprowadza w błąd.
            "czegoToNieMowi": "To jest stan aplikacji TERAZ i deklaracje jej autora — "
                + "nie prognoza skutku. Most nie zna treści tej akcji i nie umie jej "
                + "zasymulować; pokazuje, co zastanie, a nie co zostawi. Po wykonaniu "
                + "porównaj to z polem \"po\" w odpowiedzi POST /akcja.",
        ]
        if let cofaJa = akcja.odwracalnosc.cofaJa { wynik["cofaJa"] = cofaJa }

        // Dostępność jest tu **informacją, nie odmową** (poz. 2): podgląd niczego nie
        // zmienia, więc odcinanie go przy akcji chwilowo niedostępnej byłoby hałasem —
        // a pytanie „co ta akcja zastanie, gdy znów będzie można" jest sensowne.
        if let dostepnosc = akcja.dostepnosc {
            let stan = dostepnosc()
            wynik["dostepna"] = stan.czyDostepna
            if let powod = stan.powod {
                wynik["powodNiedostepnosci"] = BridgeDefaults.skrocony(powod, do: 300)
            }
        } else {
            wynik["dostepna"] = true
            wynik["dostepnoscNiezadeklarowana"] = true
        }

        // 🔴 Stan toru w chwili próbkowania (P2-02). Bez tego pola „stan" wygląda
        // na zdjęcie spokojnej aplikacji także wtedy, gdy inna akcja właśnie ją
        // zmienia — a to jest jedyne miejsce, w którym ten endpoint zarabia na siebie:
        // pokazanie człowiekowi stanu przed działaniem NIEODWRACALNYM.
        let wToku = akcjeWtoku
        wynik["akcjeWtoku"] = wToku
        wynik["stanPrzejsciowy"] = wToku > 0
        if wToku > 0 {
            wynik["uwagaOstan"] = "Most wykonuje teraz inną akcję (w toku: \(wToku)). "
                + "Ten stan może być przejściowy — sonda mogła trafić w połowę cudzej "
                + "zmiany. Jeśli pokazujesz go człowiekowi przed działaniem "
                + "nieodwracalnym, poczekaj i zapytaj ponownie."
        }
        return wynik
    }

    /// - Parameter budzetMs: ile czasu **klient** dał temu żądaniu. Domyślnie `nil`,
    ///   czyli „nie wiem" — wtedy most nie sprawdza budżetu i zachowuje się jak przedtem.
    static func wykonaj(
        nazwa surowaNazwa: String,
        potwierdzone: Bool = false,
        budzetMs: Int? = nil,
        argumenty: [String: Any] = [:]
    ) async throws -> [String: Any] {
        guard wlaczona else {
            throw BridgeError.badRequest(
                "Warstwa akcji jest wyłączona i to jest stan domyślny — most jest do odczytu, "
                + "dopóki aplikacja nie zdecyduje inaczej. Żeby ją włączyć, dopisz w niej "
                + "BridgeActions.wlacz() obok BridgeServer.start."
            )
        }
        guard !akcje.isEmpty else {
            throw BridgeError.notFound(
                "Ta aplikacja nie zgłosiła mostowi żadnej akcji. Most nie klika w punkty — "
                + "wywołać da się wyłącznie to, co program sam wystawił: "
                + "BridgeActions.register(nazwa:opis:sonda:) { … }."
            )
        }
        guard let akcja = akcje.first(where: { taSamaNazwa($0.nazwa, surowaNazwa) }) else {
            let dostepne = akcje.map(\.nazwa).joined(separator: ", ")
            throw BridgeError.notFound(
                "Ta aplikacja nie zgłosiła akcji \"\(BridgeDefaults.skrocony(surowaNazwa, do: 40))\". "
                + "Dostępne: \(dostepne)"
            )
        }

        // 🔴 Argumenty sprawdzane PRZED wszystkim innym — przed potwierdzeniem,
        // przed kolejką i przed sondą (plan rozwoju, poz. 5).
        //
        // Kolejność nie jest kosmetyczna i wyszła z testu: proszenie o potwierdzenie
        // żądania, które i tak jest źle sformułowane, uczy odruchu „dopisz potwierdzam".
        // Najpierw „to żądanie ma literówkę", potem dopiero „ta akcja jest nieodwracalna".
        //
        // Do domknięcia gospodarza jedzie WYŁĄCZNIE to, co przeszło przez
        // `BridgeDozwolone` — zamkniętą listę albo zakres, które wypisał on sam.
        // Surowy JSON z sieci nie dociera tam nigdy.
        let sprawdzone = try sprawdzArgumenty(akcja, surowe: argumenty)

        // 🔴 Zamek nr 3 warstwy akcji: akcja NIEODWRACALNA nie wykona się bez jawnego
        // potwierdzenia w żądaniu (plan rozwoju, poz. 1).
        //
        // Do 2026-09-03 jedyną obroną przed „agent kliknął Usuń" było to, że nikt
        // takiej akcji nie zarejestrował. Obrona prawdziwa, ale JEDYNA — a warstwa
        // istnieje po to, żeby ludzie takie akcje rejestrowali.
        //
        // Potwierdzenie jest wymagane **tylko** przy `.nieodwracalna`, i to jest cała
        // różnica między zamkiem a hałasem: gdyby pytało przy każdej akcji, agent
        // nauczyłby się dopisywać `potwierdzam` odruchowo i zamek zamieniłby się
        // w pole do wypełnienia.
        if akcja.odwracalnosc.wymagaPotwierdzenia && !potwierdzone {
            throw BridgeError.badRequest(
                "Akcja \"\(akcja.nazwa)\" jest NIEODWRACALNA — most nie umie cofnąć jej skutku, "
                + "bo nie zna jej treści. \(akcja.opis.isEmpty ? "" : "Co robi: \(akcja.opis). ")"
                + "Jeśli na pewno o to chodzi, powtórz żądanie z {\"akcja\": \"\(akcja.nazwa)\", "
                + "\"potwierdzam\": true}. Zanim to zrobisz, upewnij się, że użytkownik tego chce — "
                + "most wykona ją bez pytania i bez drogi powrotnej. "
                // 🔴 Zdanie „upewnij się" było do 1.2.16 odesłaniem donikąd — ta sama
                // rodzina co „sprawdź stan" przy 504, którą zamknęła poz. 1.
                + "Żeby pokazać użytkownikowi, czego dotyczy: POST /akcja/podglad "
                + "z tym samym ciałem oddaje stan programu i sprawdzone argumenty "
                + "BEZ wykonania."
            )
        }

        // 🔴 Domknięcie pętli z sufitem klienta (plan rozwoju, poz. 4).
        //
        // `BridgeServer.sprawdzSufitDlaZapisu` odsiewa przed handlerem, ale zna tylko
        // sufit PROJEKTU — nie wie, którą akcję zaraz zawołamy, bo ciała żądania jeszcze
        // nie czytał. Akcja z własnym, dłuższym sufitem przeszłaby tamto sito i wpadła
        // dokładnie w usterkę, którą 1.2.9 zamknęło: 504 po WYKONANEJ akcji.
        //
        // Tu wiemy już obie liczby, więc odmowa idzie ZANIM cokolwiek ruszy stan.
        if let budzetMs, sufitDlaAkcji(akcja) > budzetMs {
            throw BridgeError.badRequest(
                "Akcja \"\(akcja.nazwa)\" mierzy skutek przez \(sufitDlaAkcji(akcja)) ms "
                + "(tyle zgłosiła aplikacja), a to żądanie ma na wszystko \(budzetMs) ms. "
                + "Most odmawia TERAZ, bo później odmowa byłaby nieuczciwa: akcja zdążyłaby "
                + "się wykonać, a Ty dostałbyś 504 i nie wiedziałbyś, czy stan aplikacji "
                + "jest już zmieniony. Sufity poszczególnych akcji wymienia GET /akcje."
            )
        }

        // Odmowy wyżej NIE zajmują toru — nic nie wykonują, więc nie mają
        // czego szeregować, a czekanie w kolejce po to, żeby usłyszeć „nie ma takiej
        // akcji", zjadałoby sufit czasu żądania bez powodu.
        let startKolejki = Date()
        let przedeMnaWkolejce = await zajmijTor()
        defer { zwolnijTor() }
        let czekanoWkolejceMs = Int(Date().timeIntervalSince(startKolejki) * 1000)

        // 🔴 DRUGIE sprawdzenie budżetu — po kolejce, przed dotknięciem czegokolwiek
        // (plan rozwoju, poz. 6).
        //
        // Pierwsze, przed kolejką, patrzyło na sam sufit akcji. Ale czekanie na cudze
        // akcje zjada ten sam budżet: zmierzone na demie 2026-09-03 — dwanaście akcji
        // naraz i ostatnia czekała **1108 ms**, zanim w ogóle ruszyła. Przy suficie
        // szesnastu połączeń i akcji mierzącej 1,5 s ostatnia czekałaby ponad dwadzieścia
        // sekund, czyli grubo powyżej domyślnego budżetu klienta MCP (9 s) — i dostałaby
        // 504 PO wykonaniu, czyli dokładnie usterkę, którą 1.2.9 zamknęło.
        //
        // Tu wiadomo już, ile naprawdę zeszło na czekaniu, więc odmowa jest liczona
        // z pomiaru, nie z prognozy. Nadal NIC nie zostało wykonane: sonda „przed"
        // idzie dopiero niżej.
        //
        // Świadomie NIE ma tu sufitu liczby czekających: byłaby to nowa liczba, a te
        // dobiera [U]. Budżet odsiewa sam z siebie i mówi przy tym prawdę o powodzie.
        if let budzetMs, czekanoWkolejceMs + sufitDlaAkcji(akcja) > budzetMs {
            throw BridgeError.failed(
                "Akcja \"\(akcja.nazwa)\" czekała \(czekanoWkolejceMs) ms w kolejce za innymi "
                + "(przede mną: \(przedeMnaWkolejce)), a jej własny pomiar potrzebuje jeszcze "
                + "\(sufitDlaAkcji(akcja)) ms — razem ponad \(budzetMs) ms, na które umówił się "
                + "ten klient. Most odmawia PRZED wykonaniem: akcja nie ruszyła i stan aplikacji "
                + "jest nietknięty. Powtórz ją, gdy most nie będzie zajęty, albo daj żądaniu "
                + "więcej czasu."
            )
        }

        // 🔴 Zamek dostępności — PO kolejce, i to jest cała decyzja (plan rozwoju
        // mostu po 1.2.14, poz. 2).
        //
        // Sprawdzenie przed kolejką byłoby szybsze i **nieprawdziwe**: akcje szeregują
        // się jedna za drugą, więc cudza akcja przed nami mogła w międzyczasie włączyć
        // przycisk, który sekundę wcześniej był szary. Odmowa wydana na stanie sprzed
        // czekania mówiłaby o świecie, którego już nie ma. Tu nic jeszcze nie zostało
        // wykonane — sonda „przed" idzie linijkę niżej — więc odmowa nadal nic nie kosztuje.
        //
        // ⚠️ To **nie zastępuje** sprawdzenia w domknięciu gospodarza. `dostepna: true`
        // z listy sprzed sekundy nie znaczy, że jest nadal; ten zamek zamyka okno do
        // rozmiaru jednego wywołania, nie do zera.
        if let dostepnosc = akcja.dostepnosc, case .nie(let powod) = dostepnosc() {
            throw BridgeError.badRequest(
                "Akcji \"\(akcja.nazwa)\" nie da się teraz wykonać: "
                + "\(BridgeDefaults.skrocony(powod, do: 300)) "
                + "Most odmawia PRZED wykonaniem, więc stan aplikacji jest nietknięty. "
                + "Gdyby ją mimo to wykonać, odpowiedź byłaby na 200 z pustym \"zmienilo\" — "
                + "czyli nie do odróżnienia od akcji, która po prostu nic nie robi. "
                + "Które akcje są teraz dostępne, mówi GET /akcje."
            )
        }

        let przed = try probkuj(akcja, kiedy: "przed")

        var bladWykonania: Error?
        do { try akcja.wykonaj(sprawdzone) } catch { bladWykonania = error }

        let po: [String: Any]
        let czekanoMs: Int
        let ustabilizowalo: Bool
        do {
            (po, czekanoMs, ustabilizowalo) = try await ustabilizuj(akcja, od: przed)
        } catch {
            // 🔴 Sonda przestała być zapisywalna w JSON DOPIERO PO akcji (E1-P2-01).
            // Do 2026-09-02 odmowa była tu połknięta przez `try?`, a w jej miejsce
            // wchodziła próbka SPRZED akcji — więc most oddawał 200, stary stan jako
            // nowy i `zmienilo: []`, czyli „akcja nie zrobiła nic" o akcji, która
            // zrobiła. Cicha podmiana jest jedynym wariantem, który nie może zostać:
            // zamek przeciw rodzinie P0-02 ma odmawiać zdaniem, nie zgadywać.
            let coRzucilo = bladWykonania.map {
                " Sama akcja rzuciła wcześniej: \(BridgeDefaults.skrocony($0.localizedDescription, do: 200))."
            } ?? ""
            throw BridgeError.failed(
                "Akcja \"\(akcja.nazwa)\" WYKONAŁA SIĘ, ale stanu po niej nie da się zmierzyć: "
                + "\(BridgeDefaults.skrocony((error as? BridgeError)?.errorDescription ?? "\(error)", do: 300))"
                + coRzucilo
                + " Stan aplikacji jest zmieniony — most nie ma tylko jak go opisać."
            )
        }

        if let bladWykonania {
            // Sonda „po" leci nawet przy rzucie — akcja mogła zdążyć coś zmienić,
            // a bez tej informacji odpowiedź 500 nic nie mówi o stanie aplikacji.
            // Komunikat gospodarza jest cudzym napisem o nieznanej długości, więc
            // skraca się tak samo jak sonda obok (E1-P3-03).
            throw BridgeError.failed(
                "Akcja \"\(akcja.nazwa)\" rzuciła: "
                + "\(BridgeDefaults.skrocony(bladWykonania.localizedDescription, do: 200)). "
                + "Stan po niej: \(opisZwiezly(po))"
            )
        }

        var wynik: [String: Any] = [
            "akcja": akcja.nazwa,
            "opis": akcja.opis,
            // Droga powrotna jedzie RAZEM ze skutkiem, nie tylko w `GET /akcje`:
            // agent dowiaduje się, jak wrócić, dokładnie w chwili, w której zmienił
            // stan — a nie musi po to zadawać drugiego pytania.
            "odwracalnosc": akcja.odwracalnosc.nazwa,
            "przed": przed,
            "po": po,
            "zmienilo": roznice(przed: przed, po: po),
            "ustabilizowalo": ustabilizowalo,
            "czekanoMs": czekanoMs,
            // Czekanie w kolejce jest widoczne, a nie schowane w `czekanoMs`:
            // tamto mierzy USTABILIZOWANIE tej akcji, to — cudzą akcję przed nią.
            // Zlanie obu w jedną liczbę robiłoby z pomiaru zgadywankę.
            "czekanoWkolejceMs": czekanoWkolejceMs,
            // Samo czekanie nie mówi, czy most jest wolny, czy zajęty przez innych.
            "przedeMnaWkolejce": przedeMnaWkolejce,
            "sufitUstabilizowaniaMs": sufitDlaAkcji(akcja),
        ]
        if let cofaJa = akcja.odwracalnosc.cofaJa { wynik["cofaJa"] = cofaJa }
        return wynik
    }

    /// Próbka sondy, sprawdzona pod kątem zapisywalności w JSON.
    ///
    /// 🔴 Bez tego sprawdzenia sonda zwracająca `Date`, `URL` albo `NaN` wywracałaby
    /// **całą odpowiedź** na `.json(...)` — czyli rodzina P0-02 z audytu 2026-08-02,
    /// która zabijała proces gospodarza wyjątkiem Objective-C nie do złapania przez `try?`.
    /// Odmowa ze zdaniem jest tu jedyną uczciwą drogą.
    private static func probkuj(_ akcja: BridgeAkcja, kiedy: String) throws -> [String: Any] {
        let wynik = akcja.sonda()
        guard JSONSerialization.isValidJSONObject(wynik) else {
            throw BridgeError.failed(
                "Sonda akcji \"\(akcja.nazwa)\" zwróciła (\(kiedy)) wartość, której nie da się "
                + "zapisać w JSON — najczęściej Date, URL albo NaN. Oddawaj z niej liczby, "
                + "napisy i wartości logiczne; most nie ma jak odesłać reszty."
            )
        }
        return wynik
    }

    /// Czeka, aż sonda przestanie się zmieniać — albo do terminu.
    ///
    /// 🔴 Czekanie sterowane **sondą, nie liczbą w żądaniu**. Gdyby agent podawał
    /// `poczekajMs`, każde wywołanie niosłoby magiczną liczbę, a projekt ma regułę
    /// wprost: sufitów nie dobiera agent. Tu liczba jest jedna i jest **terminem**,
    /// a odpowiedź mówi, czy termin wystarczył.
    ///
    /// Warunek stabilności to **dwie kolejne zgodne próbki**, nie jedna: pojedyncza
    /// zgodność złapałaby okno w połowie budowania, gdy nic akurat nie drgnęło.
    ///
    /// 🔴 **Rzuca**, gdy sonda przestanie być zapisywalna w JSON w trakcie czekania.
    /// Do 2026-09-02 stało tu `try?` i cicha podmiana na poprzednią próbkę — czyli
    /// most oddawał stary stan jako nowy (E1-P2-01). „Sonda nie zdążyła" wolno
    /// przemilczeć; „sonda oddała coś, czego nie da się zapisać" — nie wolno.
    private static func ustabilizuj(
        _ akcja: BridgeAkcja,
        od przed: [String: Any]
    ) async throws -> (po: [String: Any], czekanoMs: Int, ustabilizowalo: Bool) {
        let sufit = sufitDlaAkcji(akcja)
        let start = Date()
        var poprzednia = przed
        var zgodnychPodRzad = 0

        while Int(Date().timeIntervalSince(start) * 1000) < sufit {
            try? await _Concurrency.Task.sleep(for: .milliseconds(krokProbkowaniaMs))
            let biezaca = try probkuj(akcja, kiedy: "po")

            if odcisk(biezaca) == odcisk(poprzednia) {
                zgodnychPodRzad += 1
                // Dwie zgodne próbki Z RZĘDU i przynajmniej jedna zmiana za sobą —
                // albo dwie zgodne przy braku zmian, co też jest wynikiem.
                if zgodnychPodRzad >= 2 {
                    return (biezaca, Int(Date().timeIntervalSince(start) * 1000), true)
                }
            } else {
                zgodnychPodRzad = 0
            }
            poprzednia = biezaca
        }
        return (poprzednia, Int(Date().timeIntervalSince(start) * 1000), false)
    }

    /// Odcisk próbki do porównania. JSON, bo sonda i tak musi być w nim zapisywalna,
    /// a `[String: Any]` nie jest `Equatable`.
    static func odcisk(_ probka: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(probka),
              let dane = try? JSONSerialization.data(withJSONObject: probka, options: [.sortedKeys])
        else { return String(describing: probka) }
        return String(decoding: dane, as: UTF8.self)
    }

    /// Nazwy pól, które zmieniły wartość. Pusta lista przy `ustabilizowalo: true`
    /// znaczy **„akcja nie zrobiła nic widocznego"** — i to jest wynik, nie awaria.
    static func roznice(przed: [String: Any], po: [String: Any]) -> [String] {
        var nazwy: Set<String> = Set(przed.keys).union(po.keys)
        nazwy = nazwy.filter { klucz in
            odcisk([klucz: przed[klucz] ?? NSNull()]) != odcisk([klucz: po[klucz] ?? NSNull()])
        }
        return nazwy.sorted()
    }

    private static func opisZwiezly(_ probka: [String: Any]) -> String {
        BridgeDefaults.skrocony(odcisk(probka), do: 120)
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeActivity.swift
// ────────────────────────────────────────────────────────────────────────


/// Co dokładnie zrobiło żądanie — dokładka do wpisu historii.
///
/// 🔴 Powód istnienia (plan rozwoju mostu po 1.2.14, poz. 1): sama ścieżka nie
/// rozróżnia akcji. Dziesięć różnych akcji gospodarza idzie tą samą trasą
/// `POST /akcja`, więc historia bez tego pola mówi agentowi „coś zmieniłeś
/// dziesięć razy" i ani słowa o tym **co**. To ta sama rodzina co „panel
/// pokazywał zapis jak odczyt" (1.2.10), tylko o warstwę dalej.
///
/// Ślad składa **handler**, nie serwer: tylko on wie, czym było żądanie. Jedzie
/// na `BridgeResponse`, a nie przez stan globalny — inaczej odczyt lecący
/// równolegle w tle mógłby zabrać ślad cudzej akcji.
nonisolated public struct BridgeActivitySlad: Sendable {
    /// Nazwa akcji — to, czego ścieżka nie niesie.
    public let szczegol: String
    /// Pola sondy gospodarza, które po akcji mają inną wartość.
    ///
    /// ⚠️ Puste znaczy „nic, na co patrzy **sonda**, się nie zmieniło", a nie „akcja
    /// nic nie zrobiła" — nauka z poligonu `poligonie` 2026-09-02. Sonda jest tak
    /// dobra, jak dobrze autor gospodarza wybrał, co w niej umieścić.
    public let zmienilo: [String]

    public init(szczegol: String, zmienilo: [String] = []) {
        self.szczegol = szczegol
        self.zmienilo = zmienilo
    }
}

/// Czym skończyło się żądanie, które **dostało już 504**.
///
/// 🔴 Handler po terminie liczy dalej — nie da się go przerwać
/// (`BridgeServer.pilnujCzasuHandlera`). Do 2026-09-03 jego wynik szedł do kosza
/// i **do logu**, a klient zostawał z 504 i zdaniem „sprawdź stan", nie mając czym.
/// Dopisujemy to do wpisu, który już istnieje, zamiast zakładać drugi: dwa wiersze
/// o jednym żądaniu z dwoma kodami to ta sama nieprawda, przed którą broni się
/// `przejmijPrawoDoOdpowiedzi`.
nonisolated public struct BridgeActivityPoTerminie: Sendable {
    /// Kod, który handler chciał oddać, gdyby zdążył.
    public let status: Int
    /// Ile handler naprawdę liczył — licząc od żądania, nie od terminu.
    public let durationMs: Double
    public let slad: BridgeActivitySlad?

    public init(status: Int, durationMs: Double, slad: BridgeActivitySlad? = nil) {
        self.status = status
        self.durationMs = durationMs
        self.slad = slad
    }
}

/// Pojedynczy wpis w historii — jedno pytanie zadane przez Claude Code.
nonisolated public struct BridgeActivityEntry: Sendable {
    /// Numer wpisu, rosnący od startu procesu.
    ///
    /// Istnieje po to, żeby dało się **wrócić do konkretnego wpisu** po tym, jak
    /// został zapisany (`domknij(_:)`). Para metoda+ścieżka do tego nie wystarcza:
    /// dwa identyczne żądania w tej samej sekundzie wyglądają identycznie, a domknięcie
    /// trafiłoby w losowe z nich.
    public let id: Int
    public let time: Date
    public let method: String
    public let path: String
    public let status: Int
    public let durationMs: Double

    /// Czy to żądanie poszło **trasą, która zmienia stan aplikacji**.
    ///
    /// Znaczy „miało prawo coś zmienić", a nie „na pewno zmieniło" — odmowa na takiej
    /// trasie też dostaje ten znacznik, bo dla człowieka patrzącego w panel próba
    /// zapisu jest informacją. Czy się udało, mówi obok kod odpowiedzi, a licznik
    /// `zmian` liczy **wyłącznie te bez błędu**, żeby odrzucone próby nie puchły
    /// w liczbie, na którą użytkownik patrzy.
    ///
    /// 🔴 Powód istnienia (plan rozwoju warstwy akcji, poz. 2): do 2026-09-03 panel
    /// pokazywał wykonaną akcję **identycznie jak odczyt** — `POST /akcja ✓ 200` —
    /// a nagłówek sekcji brzmiał „Ostatnie pytania". Słowo z czasów, gdy most tylko
    /// czytał. Audyt warstwy klikania pytał, czy **autor aplikacji** wie, co oddaje
    /// agentowi; nikt nie zapytał, **czy użytkownik widzi**, że agent coś zrobił.
    /// Jedynym śladem był wiersz w logu i nieodróżnialna linijka w panelu.
    public let zmienil: Bool

    /// Co to było — nazwa akcji i zmienione pola sondy. `nil` przy zwykłym odczycie.
    public let slad: BridgeActivitySlad?

    /// Wypełnione dopiero wtedy, gdy handler skończył **po** odesłaniu 504.
    ///
    /// `var`, bo to jedyne pole wpisu, które z natury poznaje się później niż resztę:
    /// w chwili zapisu handler jeszcze liczy.
    public internal(set) var poTerminie: BridgeActivityPoTerminie?

    /// - Parameter id: numer wpisu nadaje `BridgeActivity.record`. Domyślne zero jest
    ///   dla wpisów budowanych poza historią (widok panelu, testy) — takich, których
    ///   nikt nie będzie domykał.
    public init(
        id: Int = 0,
        time: Date,
        method: String,
        path: String,
        status: Int,
        durationMs: Double,
        zmienil: Bool = false,
        slad: BridgeActivitySlad? = nil,
        poTerminie: BridgeActivityPoTerminie? = nil
    ) {
        self.id = id
        self.time = time
        self.method = method
        self.path = path
        self.status = status
        self.durationMs = durationMs
        self.zmienil = zmienil
        self.slad = slad
        self.poTerminie = poTerminie
    }

    public var isError: Bool { Self.czyBlad(status) }

    /// Czy ten kod HTTP jest błędem. Statyczna, bo o kodzie trzeba orzec także **zanim**
    /// powstanie wpis — przy domknięciu po terminie znany jest sam numer.
    static func czyBlad(_ status: Int) -> Bool { status >= 400 }

    /// Np. „12:34:56  GET /ping  ✓ 3 ms", a przy zapisie „12:34:56  ✎ POST /akcja  ✓ 152 ms".
    ///
    /// Znacznik stoi **przed metodą**, nie na końcu: kolumny zostają równe, a oko
    /// szukające zmian w historii ma jedno miejsce do sprawdzenia zamiast czytania
    /// całych wierszy.
    public var summary: String {
        let stan = isError ? "✗ \(status)" : "✓"
        let zapis = zmienil ? "✎ " : ""
        // Nazwa akcji dopisana w nawiasie, bo bez niej dziesięć różnych akcji daje
        // w panelu dziesięć identycznych wierszy — patrz `BridgeActivitySlad`.
        let co = slad.map { " (\($0.szczegol))" } ?? ""
        return "\(Self.godzina(time))   \(zapis)\(method) \(path)\(co)   \(stan) \(Int(durationMs)) ms"
    }

    /// Wpis w postaci, w jakiej czyta go agent przez `GET /historia`.
    ///
    /// Składany tutaj, obok `summary`, a nie w serwerze: format wpisu należy do wpisu.
    /// Czas idzie w ISO 8601 ze strefą — agent porównuje go z własnymi znacznikami,
    /// a „12:34:56" z `summary` nie mówi nawet, którego dnia.
    ///
    /// 🔴 Ciało pod `#if DEBUG`, choć typ jest w `PUSTE_API` i **nazwa** ma zostać
    /// w wydaniu — ta sama zasada co przy `BridgeExecution.opis` (poz. 14 kolejki).
    /// Niżej stoi całe zdanie po polsku o odmowie z terminu; w binarce rozdawanej
    /// ludziom nie ma czego szukać.
    public var slownik: [String: Any] {
        #if DEBUG
        var wpis: [String: Any] = [
            "id": id,
            "czas": Self.iso(time),
            "metoda": method,
            "sciezka": path,
            "kod": status,
            "czasMs": Int(durationMs),
            // Nazwa pola ta sama co znacznik wpisu w panelu i w `BridgeActivityEntry` —
            // „miało prawo coś zmienić", nie „na pewno zmieniło".
            "zmienil": zmienil,
        ]
        if let slad {
            wpis["akcja"] = slad.szczegol
            wpis["zmienilo"] = slad.zmienilo
        }
        if let poTerminie {
            // 🔴 To jest odpowiedź na komunikat 504 („zanim ponowisz, sprawdź stan").
            // Zdanie jest przy danych, a nie w dokumentacji, bo czyta to agent
            // dokładnie w chwili, w której nie wie, czy powtórzyć żądanie.
            var domkniecie: [String: Any] = [
                "kod": poTerminie.status,
                "czasMs": Int(poTerminie.durationMs),
                "opis": "To żądanie dostało 504, ale handler SKOŃCZYŁ pracę po terminie "
                    + "z kodem \(poTerminie.status). Jego wynik nie poszedł do Ciebie. "
                    + "Jeśli to była trasa pisząca, stan aplikacji jest już zmieniony.",
            ]
            if let slad = poTerminie.slad {
                domkniecie["akcja"] = slad.szczegol
                domkniecie["zmienilo"] = slad.zmienilo
            }
            wpis["poTerminie"] = domkniecie
        }
        return wpis
        #else
        return [:]
        #endif
    }

    /// Kalendarz w UTC — jeden na proces, nie jeden na wpis.
    ///
    /// `Calendar` jest typem **wartościowym** i po zbudowaniu nikt go tu nie zmienia,
    /// więc współdzielenie nie wnosi tego ryzyka, przed którym broni się komentarz
    /// przy `godzina`: tam chodziło o `DateFormatter`, czyli obiekt referencyjny
    /// niebezpieczny do współdzielenia między wątkami.
    private static let kalendarzUTC: Calendar = {
        var kalendarz = Calendar(identifier: .gregorian)
        kalendarz.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return kalendarz
    }()

    /// Znacznik ISO 8601 w UTC — składany z komponentów, bez `ISO8601DateFormatter`.
    ///
    /// 🔴 Powód (audyt 1.2.15–1.2.18, P3-01): formatter budował się **przy każdym
    /// wpisie**, tuż obok `godzina`, która identyczny problem rozwiązała bez niego.
    /// Jedno `GET /historia` z pełną historią budowało dwanaście formatterów.
    /// `ISO8601DateFormatter` jest drogi w budowie, a tu nie ma czego parsować.
    ///
    /// Strefa jest **UTC i ma taka zostać**: `ISO8601DateFormatter` bez ustawionej
    /// strefy też stoi na GMT, więc ten zapis oddaje dokładnie ten sam ciąg, co kod
    /// sprzed naprawy. Pilnuje tego `test_isoZgadzaSieZISO8601DateFormatter`, który
    /// porównuje obie drogi na przełomie roku, na sekundzie zerowej i w obu porach
    /// roku — bez niego ta naprawa byłaby gorsza od zaniechania.
    static func iso(_ date: Date) -> String {
        let c = kalendarzUTC.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    /// Godzina składana z komponentów, a nie przez współdzielony `DateFormatter`.
    ///
    /// Wcześniej stał tu statyczny `DateFormatter` wspólny dla wszystkich wpisów.
    /// `DateFormatter` nie jest bezpieczny do współdzielenia między wątkami, a typ
    /// jest publiczny, więc aplikacja mogła sięgnąć po `summary` skądkolwiek.
    /// `Calendar` to typ wartościowy — ten zapis nie ma czego współdzielić.
    private static func godzina(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

/// Licznik ruchu na moście — zasila ikonkę w pasku menu.
///
/// W RELEASE nic nie zapisuje.
/// Cały stan pod zamkiem `lock` — patrz uwaga przy `BridgeRegistry`.
nonisolated public final class BridgeActivity: @unchecked Sendable {

    public static let shared = BridgeActivity()

    private let lock = NSLock()
    private var _total = 0
    private var _zmian = 0
    private var _errors = 0
    private var _recent: [BridgeActivityEntry] = []
    private var _lastTime: Date?
    private var _nastepnyId = 1

    private var _onChange: (@Sendable (BridgeActivityEntry) -> Void)?

    /// Ustawia obserwatora wywoływanego po każdym żądaniu.
    ///
    /// ⚠️ Obserwator dostaje wywołanie **stamtąd, gdzie skończył się handler** —
    /// z kolejki sieciowej przy `registerInBackground`, ale **z głównego aktora**
    /// przy `registerOnMainActor` (i przy żądaniu odrzuconym przez parser).
    /// Przeskok na interfejs robi u siebie ten, kto go dotyka; skok był kiedyś tutaj,
    /// co wyglądało wygodnie, ale ukrywało, skąd naprawdę leci wywołanie.
    ///
    /// 🔴 Do 2026-08-10 stało tu „zawsze z kolejki sieciowej, nie z głównego wątku"
    /// — nieprawda, i to taka, która zaprasza do `MainActor.assumeIsolated` przy
    /// następnej zmianie. Dziś skutku nie ma, bo jedyny konsument i tak przeskakuje
    /// przez `Task { @MainActor }`, co jest poprawne z obu stron. Audyt, E2-P3-02.
    ///
    /// Celowo metoda, a nie zwykła właściwość: ustawia ją główny wątek
    /// (ikonka w pasku menu), a czyta wątek sieciowy. Bez zamka po obu
    /// stronach zamek po jednej niczego nie chroni.
    func setOnChange(_ handler: (@Sendable (BridgeActivityEntry) -> Void)?) {
        lock.withLock { _onChange = handler }
    }

    /// Ile wpisów most trzyma w pamięci.
    ///
    /// 🔴 **Liczbę dobrał Claude, nie [U]** — stoi tu od czasów, gdy jedynym czytelnikiem
    /// historii było menu w pasku, gdzie dwanaście wierszy to tyle, ile się mieści.
    /// Od 1.2.15 czyta ją także agent przez `GET /historia`, gdzie ta sama liczba znaczy
    /// co innego: dwanaście żądań agent zadaje w kilkanaście sekund. Zmiana wartości
    /// jest zmianą jednej linijki i **należy do [U]**, tak samo jak `maksRunow`
    /// i `sufitUstabilizowaniaMs`.
    ///
    /// Publiczne, bo `GET /historia` podaje tę liczbę w odpowiedzi — inaczej agent
    /// wziąłby brak starszego wpisu za dowód, że żądania nie było.
    public static let maxRecent = 12

    /// Jedyna reguła licznika `zmian` — jedno miejsce dla obu wołających.
    ///
    /// 🔴 Powód wydzielenia (audyt 1.2.15–1.2.18, P2-01): reguła stała wyłącznie
    /// w ciele `record`, a `domknij` — który dowiaduje się o skutku żądania **później** —
    /// nie ruszał żadnego licznika. Akcja domknięta po 504 zmieniała stan gospodarza,
    /// wiersz w panelu to pokazywał, a liczba obok zostawała zaniżona. Przepisanie
    /// tego samego warunku obok byłoby rodziną „zasięg naprawy krótszy niż zasięg
    /// reguły", którą ten projekt zna z czterech audytów.
    static func liczyDoZmian(zmienil: Bool, status: Int) -> Bool {
        zmienil && !BridgeActivityEntry.czyBlad(status)
    }

    private init() {}

    public var total: Int { lock.withLock { _total } }
    public var errors: Int { lock.withLock { _errors } }

    /// Ile żądań **zmieniło stan aplikacji**. Osobno od `total`, bo to jest jedyna
    /// liczba w panelu, która mówi użytkownikowi coś o jego programie, a nie o moście.
    public var zmian: Int { lock.withLock { _zmian } }
    public var lastTime: Date? { lock.withLock { _lastTime } }
    public var recent: [BridgeActivityEntry] { lock.withLock { _recent } }

    /// Najdłuższa ścieżka trzymana w historii.
    ///
    /// Bez tego jedno żądanie z bardzo długą ścieżką rozciąga menu w pasku na całą
    /// szerokość ekranu — panel przestaje być czytelny, a jest jedynym wizualnym
    /// potwierdzeniem, że most żyje. Znalezione 2026-08-09 przy ostrzale innym gospodarzu
    /// żądaniem `GET /aaa…` o długości 8000 znaków.
    ///
    /// Skracamy przy **zapisie**, nie przy rysowaniu: inaczej takie ścieżki leżałyby
    /// w pamięci przez kilkanaście wpisów historii, a każdy widok musiałby pamiętać
    /// o własnym przycięciu.
    private static let maxPathLength = 60

    /// - Returns: numer zapisanego wpisu, do późniejszego `domknij(_:)`. `nil` w RELEASE,
    ///   gdzie ta metoda nic nie zapisuje i nie ma czego domykać.
    @discardableResult
    func record(
        method: String,
        path: String,
        status: Int,
        durationMs: Double,
        zmienil: Bool = false,
        slad: BridgeActivitySlad? = nil
    ) -> Int? {
        #if DEBUG
        // 🔴 Neutralizacja PRZED przycięciem — drugie ujście pozycji 10 (E2-P2-01).
        // Panel paska menu jest drugim miejscem, w które trafia ścieżka z żądania,
        // i do 2026-09-02 tnął wyłącznie długość, tak jak `skrocony`.
        let bezpieczna = BridgeDefaults.bezLamaczyWiersza(path)
        let skroconaSciezka = bezpieczna.count > Self.maxPathLength
            ? String(bezpieczna.prefix(Self.maxPathLength)) + "…"
            : bezpieczna

        // 🔴 Nazwa akcji to **cudze wejście** — przychodzi w ciele żądania i tak samo
        // jak ścieżka trafia do menu w pasku menu. Bez tego wiersza pozycja 10 (E2-P2-01)
        // dostałaby trzecie ujście: nazwa z `\n` rozbijałaby panel, a ścieżka obok
        // byłaby czyszczona. Skracamy tą samą drogą, jedną liczbą.
        // `skrocony` neutralizuje sam, jedną drogą — patrz `BridgeDefaults.skrocony`.
        let czystySlad = slad.map {
            BridgeActivitySlad(
                szczegol: BridgeDefaults.skrocony($0.szczegol, do: Self.maxPathLength),
                zmienilo: $0.zmienilo.map { BridgeDefaults.skrocony($0, do: Self.maxPathLength) }
            )
        }

        lock.lock()
        let numer = _nastepnyId
        _nastepnyId += 1
        let entry = BridgeActivityEntry(
            id: numer,
            time: Date(),
            method: method,
            path: skroconaSciezka,
            status: status,
            durationMs: durationMs,
            zmienil: zmienil,
            slad: czystySlad
        )
        _total += 1
        if entry.isError { _errors += 1 }
        if Self.liczyDoZmian(zmienil: entry.zmienil, status: entry.status) { _zmian += 1 }
        _lastTime = entry.time
        _recent.insert(entry, at: 0)
        if _recent.count > Self.maxRecent { _recent.removeLast() }
        let handler = _onChange
        lock.unlock()

        handler?(entry)
        return numer
        #else
        return nil
        #endif
    }

    /// Dopisuje do wpisu, który dostał 504, czym naprawdę skończył się jego handler.
    ///
    /// Wpis mógł już wypaść z historii — dwanaście żądań później nie ma czego domykać
    /// i to nie jest błąd. Metoda milczy w takim wypadku zamiast zakładać nowy wiersz:
    /// wpis o kodzie 200 bez wcześniejszego 504 kłamałby o tym, co dostał klient.
    ///
    /// 🔴 Domyka **wyłącznie wpis, który dostał 504** (P3-02). Kontrakt stał do 1.2.18
    /// w zwyczaju wołającego, nie w kodzie: jedyny wołający woła to po odesłaniu 504,
    /// więc skutku nie było. Ale pole `poTerminie` renderuje się zdaniem *„to żądanie
    /// dostało 504"*, więc pomyłkowe wywołanie na wpisie 200 wyprodukowałoby zdanie
    /// **nieprawdziwe** w miejscu, któremu agent ma ufać przy decyzji o ponowieniu akcji.
    /// Kontrakt ma stać w warunku, nie w zwyczaju.
    ///
    /// - Returns: `true`, gdy wpis się znalazł, miał 504 i został domknięty.
    @discardableResult
    func domknij(
        _ id: Int?,
        status: Int,
        durationMs: Double,
        slad: BridgeActivitySlad? = nil
    ) -> Bool {
        #if DEBUG
        guard let id else { return false }
        let domkniety: BridgeActivityEntry? = lock.withLock {
            guard let i = _recent.firstIndex(where: { $0.id == id }) else { return nil }
            // Dwa warunki, nie jeden: 504 to kontrakt (P3-02), a `poTerminie == nil`
            // pilnuje, żeby to samo domknięcie nie weszło dwa razy. Dziś drugie
            // wywołanie nie ma skąd przyjść (`BridgeServer.wpisyPoTerminie` zdejmuje
            // wpis przy pierwszym), ale licznik zmian niżej **zakłada to wprost**,
            // zamiast opierać się na zwyczaju drugiego pliku.
            guard _recent[i].status == 504, _recent[i].poTerminie == nil else { return nil }
            _recent[i].poTerminie = BridgeActivityPoTerminie(
                status: status, durationMs: durationMs, slad: slad
            )
            // 🔴 Licznik zmian dopiero TERAZ (P2-01). Przy zapisie wpis miał 504,
            // czyli błąd, więc reguła go nie policzyła — i słusznie: w tamtej chwili
            // nikt nie wiedział, czy akcja się wykonała. Wiadomo dopiero tutaj.
            // Podwójnego zliczenia pilnuje guard wyżej: wpis z 504 nigdy nie wszedł
            // do `_zmian`, a domknąć da się go tylko raz.
            if Self.liczyDoZmian(zmienil: _recent[i].zmienil, status: status) { _zmian += 1 }
            return _recent[i]
        }
        // Obserwator dostaje wywołanie POZA zamkiem — tak samo jak przy `record`.
        // Panel ma się przerysować, bo wiersz zmienił treść.
        guard let domkniety else { return false }
        lock.withLock { _onChange }?(domkniety)
        return true
        #else
        return false
        #endif
    }

    /// Ostatnie wpisy dla agenta — najnowszy pierwszy, `limit` przycina od najnowszych.
    ///
    /// Sufit i licznik wszystkich żądań jadą razem z wpisami przez `GET /historia`,
    /// więc tu zostaje samo cięcie.
    func ostatnie(limit: Int) -> [BridgeActivityEntry] {
        let wszystkie = recent
        guard limit > 0 else { return [] }
        return Array(wszystkie.prefix(limit))
    }
}

// ────────────────────────────────────────────────────────────────────────
// BridgeAppearance.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` dołożone 2026-08-29 (audyt, E5N-P1-01). Do tego dnia ten plik znikał
// z RELEASE **wyłącznie dlatego, że nic się do niego nie odwoływało** — jedyne wywołania
// stoją w `registerBuiltInWyglad`, która jest pod dyrektywą. Zamek oparty na tym, że
// optymalizator usunie martwy kod, jest zamkiem cudzym: wystarczy jedno nowe odwołanie
// spoza `#if DEBUG`, żeby cały plik pojechał do wydania gospodarza, i żaden pomiar tego
// nie zapowie. Ta sama uwaga stoi w przepisie audytu przy `BridgeScreenshot` (pytanie 4d).
#if DEBUG && canImport(AppKit)

/// Wymuszenie jasnego albo ciemnego wyglądu w żywej aplikacji.
///
/// 🔴 Poprawka do pierwszej wersji planu (2026-08-27): stało tam, że „nie da się
/// przełączyć jasnego bez ruszania ustawień systemowych [U]" — i to była **nieprawda**.
/// Wygląd ustawia się na aplikacji albo na oknie (`NSApp.appearance`), a nie na
/// systemie. Zgłosił to [U] zdaniem *„na innych programach sam przełączałeś sobie
/// do testu"*. Morał szerszy niż ten endpoint: „nie da się" wymaga takiego samego
/// dowodu jak każde inne zdanie.
///
/// Ustawienie jest **widoczne dla użytkownika** — okno na ekranie zmienia kolory,
/// i to niemal w całości: zmierzone 2026-08-28 przez `/render` + `/diff`, ciemny
/// kontra jasny to **99,72 % różniących się pikseli**.
///
/// 🔴 **`{"wyglad": "system"}` NIE jest powrotem do stanu sprzed wywołania** — do
/// 2026-08-28 stało tu, że jest, i była to nieprawda. `system` ustawia
/// `NSApp.appearance = nil`, czyli oddaje wygląd systemowi. To jest to samo tylko
/// wtedy, gdy program przed wizytą mostu niczego nie wymuszał. Aplikacja, która
/// sama ustawia `NSApp.appearance` (bo np. chce zawsze jasny motyw), po jednym
/// `POST /appearance` traciła swoje ustawienie **bez możliwości odtworzenia**.
/// Dlatego kit zapamiętuje teraz stan przy pierwszej zmianie i wystawia go jako
/// `wyjsciowy`, a `{"wyglad": "przywroc"}` wraca dokładnie do niego.
@MainActor
enum BridgeAppearance {

    /// Wygląd zastany przy **pierwszej** zmianie w tym procesie.
    ///
    /// Zapamiętywany raz: druga i kolejna zmiana nie mają go nadpisywać, bo wtedy
    /// „przywróć" cofałoby o jeden krok zamiast do stanu sprzed wizyty mostu.
    private static var wyjsciowy: NSAppearance?
    private static var wyjsciowyZapamietany = false

    /// Zapomina zapamiętany stan wyjściowy. **Wyłącznie dla testów** — powód ten sam
    /// co w `BridgeWindows.wyczysc` i `BridgeDrawnRects.wyczysc`: pamięć jest globalna
    /// dla procesu, więc bez tego szwu test „przywroc bez wcześniejszej zmiany odmawia"
    /// zależałby od kolejności testów.
    ///
    /// 🔴 Dołożone 2026-08-28 z audytu, E5-P2-05. Bez tego szwu tamten test **nie miał
    /// jak istnieć uczciwie** — i nie istniał: połykał wyjątek przez `try?`, więc
    /// przechodził także przy odmowie usuniętej z kodu (kontrola mutacyjna).
    /// Najpierw szew, potem test.
    ///
    /// ⚠️ To **nie jest** cofnięcie wyglądu. Kasuje wyłącznie pamięć mostu; `NSApp.appearance`
    /// zostaje takie, jakie jest. Do cofnięcia służy `{"wyglad": "przywroc"}`.
    static func wyczysc() {
        wyjsciowy = nil
        wyjsciowyZapamietany = false
    }

    /// Nazwy przyjmowane w żądaniu → wygląd AppKit. `nil` znaczy „oddaj systemowi".
    static func wyglad(dla nazwa: String) -> NSAppearance?? {
        switch nazwa.lowercased() {
        case "dark", "ciemny", "darkaqua":
            return NSAppearance(named: .darkAqua)
        case "light", "jasny", "aqua":
            return NSAppearance(named: .aqua)
        case "system", "systemowy", "auto":
            // Podwójny opcjonał niesie różnicę, której pojedynczy nie uniesie:
            // `.some(nil)` to „ustaw nil, czyli oddaj systemowi", a `nil` to
            // „nie rozpoznaję takiej nazwy".
            return .some(nil)
        default:
            return nil
        }
    }

    /// Ustawia wygląd całej aplikacji. Zwraca opis stanu po zmianie.
    ///
    /// Przy pierwszym wywołaniu zapamiętuje stan zastany, żeby dało się do niego
    /// wrócić — patrz `przywroc` i uwaga w nagłówku typu.
    static func ustaw(_ nazwa: String) throws -> [String: Any] {
        let app = NSApplication.shared

        if ["przywroc", "przywróć", "restore"].contains(nazwa.lowercased()) {
            guard wyjsciowyZapamietany else {
                throw BridgeError.badRequest(
                    "Nie ma czego przywracać: most nie zmieniał w tym procesie wyglądu, "
                    + "więc stan jest wciąż taki, jaki ustawiła aplikacja."
                )
            }
            app.appearance = wyjsciowy
            return stan()
        }

        guard let wybor = wyglad(dla: nazwa) else {
            throw BridgeError.badRequest(
                "Nie znam wyglądu \"\(nazwa)\". Dozwolone: dark, light, system, przywroc."
            )
        }

        // Zapamiętanie MUSI być przed zmianą i tylko raz — inaczej „przywróć" cofa
        // o jeden krok, a nie do stanu sprzed wizyty mostu.
        if !wyjsciowyZapamietany {
            wyjsciowy = app.appearance
            wyjsciowyZapamietany = true
        }

        app.appearance = wybor
        return stan()
    }

    /// Co jest ustawione teraz — osobno wymuszenie, osobno wygląd faktycznie użyty.
    ///
    /// Rozróżnienie jest istotne przy czytaniu pomiaru: `wymuszony: null` przy
    /// `efektywny: "NSAppearanceNameDarkAqua"` znaczy „ciemny, bo tak ma system",
    /// a nie „ciemny, bo most tak ustawił".
    static func stan() -> [String: Any] {
        let app = NSApplication.shared
        // `map` zamiast `??`: lewa strona jest `String?`, prawa `NSNull`, więc
        // zwykłe scalanie opcjonała nie ma wspólnego typu do złączenia.
        let wymuszony: Any = app.appearance.map { $0.name.rawValue as Any } ?? NSNull()
        // `wyjsciowy` to stan zastany przy pierwszej zmianie — jedyna informacja,
        // po której da się wrócić tam, gdzie aplikacja była przed wizytą mostu.
        // `null` przy `zapamietany: true` znaczy „program niczego nie wymuszał",
        // co jest czym innym niż „jeszcze nie wiemy" (`zapamietany: false`).
        let wyjsciowyOpis: Any = wyjsciowyZapamietany
            ? (wyjsciowy.map { $0.name.rawValue as Any } ?? NSNull())
            : NSNull()
        return [
            "wymuszony": wymuszony,
            "efektywny": app.effectiveAppearance.name.rawValue,
            "ciemny": app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            "wyjsciowy": wyjsciowyOpis,
            "zapamietany": wyjsciowyZapamietany,
            "kierunekUkladu": opisKierunku(app.userInterfaceLayoutDirection),
            "odPrawej": app.userInterfaceLayoutDirection == .rightToLeft,
        ]
    }

    /// Kierunek układu w postaci, którą da się przeczytać bez zaglądania do AppKit.
    ///
    /// 🔴 Pozycja 4h, 2026-08-29. Do tego dnia **ani jedna** odpowiedź warstwy wyglądu
    /// nie wspominała o kierunku układu — `/appearance`, `/windows`, `/defaults`
    /// i `/routes` milczały. Most nie kłamał; on tego kierunku po prostu nie znał,
    /// więc czytający zrzut z arabskiego albo hebrajskiego interfejsu nie miał skąd
    /// wiedzieć, że „lewa krawędź" znaczy tam koniec wiersza, a nie początek.
    /// Zmierzone na alt-tab-macos w prawdziwym RTL.
    /// Nagłówek niosący kierunek układu tam, gdzie odpowiedzią jest obrazek, nie JSON.
    static let naglowekKierunku = "x-bridge-kierunek-ukladu"

    /// Kierunek układu **tego okna**, nie aplikacji.
    ///
    /// 🔴 Okno może wymusić swój kierunek niezależnie od aplikacji, więc pytanie
    /// „w którą stronę idzie ten interfejs" ma sens tylko przy konkretnym oknie —
    /// a wszystkie endpointy współrzędnych pracują na jednym oknie (poz. 21).
    static func kierunekOkna(_ okno: NSWindow) -> String {
        opisKierunku(
            okno.contentView?.userInterfaceLayoutDirection
                ?? NSApplication.shared.userInterfaceLayoutDirection
        )
    }

    nonisolated static func opisKierunku(_ kierunek: NSUserInterfaceLayoutDirection) -> String {
        switch kierunek {
        case .rightToLeft: return "odPrawejDoLewej"
        case .leftToRight: return "odLewejDoPrawej"
        @unknown default: return "nieznany"
        }
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeDefaults.swift
// ────────────────────────────────────────────────────────────────────────


/// Ustawienia programu dostępne z terminala — po białej liście, którą deklaruje
/// sam program.
///
/// Powód powstania (2026-08-27, praca nad wyglądem `Like Xcode` w MarkRead): okno
/// Ustawień (⌘,) jest z zewnątrz nieosiągalne, a każdy wygląd trzeba obejrzeć
/// w kilku wariantach i przy kilku rozmiarach kroju. Bez tego pomiar wygląda tak,
/// że [U] klika, a agent patrzy — czyli robota na dwie osoby zamiast na jedną.
///
/// 🔴 **Biała lista jest obowiązkowa i nie ma trybu „wszystko".** Most, który
/// pozwala ustawić dowolny klucz `UserDefaults`, potrafi przestawić aplikacji
/// ścieżkę do sejfu, adres serwera albo token — a jest to jedyny endpoint kitu,
/// który **trwale zmienia stan** poza czasem życia procesu. Program wymienia
/// klucze, którymi wolno ruszać, i tylko te są widoczne.
///
/// Cały stan siedzi za `lock`, stąd `@unchecked Sendable` — jak w `BridgeRegistry`.
nonisolated public final class BridgeDefaults: @unchecked Sendable {

    public static let shared = BridgeDefaults()

    /// Typ, jakiego program spodziewa się pod kluczem.
    ///
    /// 🔴 Dołożone 2026-08-28 z audytu warstwy wyglądu. Do tego dnia biała lista
    /// sprawdzała **wyłącznie nazwę klucza**, więc klucz opisany jako
    /// „Rozmiar kroju (Double, 9…24)" przyjmował napis, słownik i miliard —
    /// wszystkie trzy zmierzone, wszystkie z kodem 200. Typ był wtedy **prozą
    /// w opisie**, czyli czymś, czego kit nie ma jak egzekwować. Program, który
    /// czyta taką wartość rzutowaniem wymuszonym (`object(forKey:) as! Double`),
    /// ginie kilkanaście linijek od mostu i nic nie wskazuje na most.
    ///
    /// Deklaracja jest **dobrowolna**: `nil` znaczy „sprawdzaj tylko klucz",
    /// czyli zachowanie sprzed tej zmiany. Dzięki temu żadne istniejące wywołanie
    /// `allow` się nie psuje.
    public enum Typ: String, Sendable {
        case napis
        case liczba
        case logiczna
        case tablica
        case slownik

        func pasuje(_ wartosc: Any) -> Bool {
            switch self {
            // `Bool` w JSON-ie przychodzi jako `NSNumber`, więc kolejność ma znaczenie:
            // najpierw pytamy o wartość logiczną, potem dopiero o liczbę.
            case .logiczna: return wartosc is Bool || (wartosc as? NSNumber).map(Self.jestLogiczna) == true
            case .liczba: return wartosc is NSNumber && !(Self.jestLogiczna(wartosc as! NSNumber))
            case .napis: return wartosc is String
            case .tablica: return wartosc is [Any]
            case .slownik: return wartosc is [String: Any]
            }
        }

        /// `NSNumber` opakowujący `Bool` ma typ `c` (char) — inaczej `true` i `1`
        /// są tym samym i deklaracja typu przestaje cokolwiek znaczyć.
        private static func jestLogiczna(_ liczba: NSNumber) -> Bool {
            CFGetTypeID(liczba) == CFBooleanGetTypeID()
        }

        var opisDlaCzlowieka: String {
            switch self {
            case .napis: return "napis"
            case .liczba: return "liczba"
            case .logiczna: return "wartość logiczna (true/false)"
            case .tablica: return "tablica"
            case .slownik: return "słownik"
            }
        }
    }

    /// Jeden klucz, którym wolno ruszać z zewnątrz.
    ///
    /// 🔴 **Zakresu nie da się zadeklarować bez typu i to jest celowe.** Do 2026-08-28
    /// oba pola były w inicjalizatorze niezależne, więc `.init(klucz:zakres:)`
    /// kompilowało się i czytało jak ograniczenie — a `GET /defaults` taki zakres
    /// **ogłaszał agentowi**, podczas gdy `ustaw` go **nie sprawdzał**, bo całe
    /// sprawdzenie stało pod `if let typ`. Zmierzone: wpis „9…24" bez typu przyjmował
    /// 1 000 000 000 z kodem 200. Wpis z samym zakresem był więc dokładnie tak samo
    /// bezbronny jak przed naprawą WW-P2-01, a odpowiedź mówiła, że nie jest.
    /// Audyt 2026-08-28, E5-P2-02.
    public struct Wpis: Sendable {
        public let klucz: String
        public let opis: String
        /// Typ egzekwowany przy zapisie. `nil` = sprawdzana jest tylko nazwa klucza.
        public let typ: Typ?
        /// Dopuszczalny zakres. Niepusty **wyłącznie** razem z `typ == .liczba` —
        /// pilnuje tego inicjalizator, więc stanu „zakres bez typu" nie da się zapisać.
        public let zakres: ClosedRange<Double>?

        public init(klucz: String, opis: String = "", typ: Typ? = nil) {
            self.klucz = klucz
            self.opis = opis
            self.typ = typ
            self.zakres = nil
        }

        /// Klucz liczbowy z zakresem. Osobny inicjalizator, a nie kolejny argument
        /// z wartością domyślną: zakres bez typu nie jest deklaracją, tylko obietnicą
        /// bez pokrycia, i ma się **nie kompilować** — u tego, kto ją pisze.
        public init(klucz: String, opis: String = "", zakres: ClosedRange<Double>) {
            self.klucz = klucz
            self.opis = opis
            self.typ = .liczba
            self.zakres = zakres
        }
    }

    private let lock = NSLock()
    private var wpisy: [String: Wpis] = [:]
    /// Miejsce zapisu. `UserDefaults.standard`, dopóki program nie wskaże innego.
    private var suiteName: String?

    private init() {}

    /// Miejsce zapisu, odczytane **pod zamkiem**.
    ///
    /// 🔴 Do 2026-08-28 `suiteName` było tu czytane bez zamka, choć nagłówek typu mówi
    /// „cały stan siedzi za `lock`" — a klasa jest `@unchecked Sendable`, czyli sama
    /// bierze na siebie obowiązek synchronizacji. `wpisy` miały zamek, `suiteName` nie.
    /// Równoczesny odczyt i zapis pola typu referencyjnego to nie jest „stara wartość",
    /// tylko zachowanie niezdefiniowane — w procesie gospodarza. Drogę zamykał dotąd
    /// wyłącznie drugi zamek: wszystkie realne wywołania są na głównym aktorze.
    /// Ale `allow` jest `nonisolated public` i niczego takiego nie wymaga.
    /// Audyt 2026-08-28, E5-P2-07.
    private var defaults: UserDefaults {
        let nazwa = lock.withLock { suiteName }
        guard let nazwa, let inne = UserDefaults(suiteName: nazwa) else {
            return .standard
        }
        return inne
    }

    /// Zgłasza klucze, którymi most może ruszać.
    ///
    /// ```swift
    /// BridgeDefaults.shared.allow([
    ///     .init(klucz: "rozmiarKroju", opis: "Rozmiar kroju w edytorze (Double)"),
    ///     .init(klucz: "motyw", opis: "like-xcode | klasyczny"),
    /// ])
    /// ```
    ///
    /// W RELEASE nic nie robi — jak cała reszta kitu.
    public func allow(_ nowe: [Wpis], suiteName: String? = nil) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        if let suiteName {
            // 🔴 `UserDefaults(suiteName:)` oddaje `nil` dla nazw, których nie przyjmuje
            // (m.in. własny identyfikator pakietu i domena globalna). Do 2026-08-28
            // kit spadał wtedy po cichu na `.standard`, czyli zapisywał **gdzie indziej,
            // niż program poprosił**, i nikt się o tym nie dowiadywał. Cisza jest tu
            // gorsza od hałasu: to jedyny endpoint zmieniający stan trwale.
            if UserDefaults(suiteName: suiteName) != nil {
                self.suiteName = suiteName
            } else {
                print(
                    "[AppBridge] 🔴 BridgeDefaults.allow: nie mogę otworzyć suity "
                    + "\"\(suiteName)\" — UserDefaults jej nie przyjmuje (tak jest m.in. "
                    + "dla własnego identyfikatora pakietu i domeny globalnej). "
                    + "Ustawienia z mostu pójdą do UserDefaults.standard, NIE do tej suity."
                )
            }
        }
        for wpis in nowe { wpisy[wpis.klucz] = wpis }
        #endif
    }

    /// Wygodniejszy wariant, gdy opisy nie są potrzebne.
    public func allow(_ klucze: [String], suiteName: String? = nil) {
        allow(klucze.map { Wpis(klucz: $0) }, suiteName: suiteName)
    }

    /// Biała lista razem z wartościami, które klucze mają w tej chwili.
    func stan() -> [[String: Any]] {
        let lista = lock.withLock { wpisy.values.sorted { $0.klucz < $1.klucz } }
        let ustawienia = defaults
        return lista.map { wpis in
            var opis: [String: Any] = ["klucz": wpis.klucz, "opis": wpis.opis]
            // Typ i zakres w odpowiedzi, żeby agent po drugiej stronie wiedział, czego
            // wolno spróbować, ZANIM dostanie 400. Pole pojawia się tylko wtedy, gdy
            // program je zadeklarował — brak pola znaczy „sprawdzany jest sam klucz".
            if let typ = wpis.typ { opis["typ"] = typ.rawValue }
            if let zakres = wpis.zakres {
                opis["zakres"] = ["od": zakres.lowerBound, "do": zakres.upperBound]
            }
            // `object(forKey:)` oddaje `Any?`; brak wartości znaczy „program używa
            // własnej domyślnej", i to jest inna informacja niż `null` zapisany ręcznie.
            if let wartosc = ustawienia.object(forKey: wpis.klucz) {
                // `Date` i `Data` są w UserDefaults legalne, a w JSON nie — wpuszczone
                // wprost wywróciłyby całą odpowiedź na `.json(...)` (P0-02). Opisujemy
                // je tekstem zamiast gubić cały endpoint przez jeden klucz.
                opis["wartosc"] = JSONSerialization.isValidJSONObject([wartosc])
                    ? wartosc
                    : String(describing: wartosc)
                opis["ustawione"] = true
            } else {
                opis["ustawione"] = false
            }
            return opis
        }
    }

    /// Ustawia jeden klucz. Rzuca `BridgeError`, gdy klucza nie ma na białej liście,
    /// gdy wartość nie pasuje do typu zadeklarowanego przez program albo gdy nie
    /// nadaje się do `UserDefaults`.
    func ustaw(klucz: String, wartosc: Any) throws {
        let wpis = try sprawdzKlucz(klucz)
        let ustawienia = defaults

        // `NSNull` to jedyna droga, którą JSON potrafi powiedzieć „skasuj".
        if wartosc is NSNull {
            ustawienia.removeObject(forKey: klucz)
            return
        }

        // `UserDefaults` przy wartości spoza listy dozwolonych typów nie zwraca
        // błędu — rzuca wyjątek Objective-C, który kończy proces gospodarza.
        // Ten sam mechanizm, który zabijał aplikację przez `.json(...)`
        // (audyt 2026-08-02, P0-02), więc sprawdzamy PRZED zapisem.
        guard Self.dozwolonaWartosc(wartosc) else {
            throw BridgeError.badRequest(
                "Wartość typu \(type(of: wartosc)) nie nadaje się do UserDefaults. "
                + "Dozwolone: napis, liczba, wartość logiczna, tablica i słownik z takich wartości."
            )
        }

        // Typ zadeklarowany przez program. Sprawdzany po tamtym, bo tamten chroni
        // **proces**, a ten chroni **stan aplikacji** — najpierw nie dać się zabić,
        // potem nie dać się wprowadzić w zły stan.
        if let typ = wpis.typ {
            guard typ.pasuje(wartosc) else {
                throw BridgeError.badRequest(
                    "Klucz \"\(Self.skrocony(klucz))\" jest zadeklarowany jako "
                    + "\(typ.opisDlaCzlowieka), a dostał wartość typu \(type(of: wartosc)). "
                    + "Most nie zapisuje wartości niezgodnej z deklaracją, bo program "
                    + "odczyta ją swoim typem i albo dostanie śmieć, albo zginie na rzutowaniu."
                )
            }
        }

        // 🔴 Zakres sprawdzany NIEZALEŻNIE od typu, choć inicjalizator gwarantuje, że
        // jedno bez drugiego nie powstanie. Dwa zamki zamiast jednego, bo poprzednia
        // wersja tego kodu miała ten warunek zagnieżdżony w `if let typ` i to była
        // cała usterka E5-P2-02: wystarczyło, że zakres istniał bez typu, żeby zniknął
        // z egzekwowania, nie znikając z odpowiedzi `/defaults`.
        if let zakres = wpis.zakres, let liczba = (wartosc as? NSNumber)?.doubleValue {
            guard zakres.contains(liczba) else {
                throw BridgeError.badRequest(
                    "Klucz \"\(Self.skrocony(klucz))\" przyjmuje wartości z zakresu "
                    + "\(zakres.lowerBound)…\(zakres.upperBound), a dostał \(liczba)."
                )
            }
        }

        ustawienia.set(wartosc, forKey: klucz)
    }

    /// Nazwa klucza przycięta na potrzeby komunikatu błędu.
    ///
    /// Bez tego żądanie z kluczem o 100 000 znaków wracało z **całą** nazwą w treści
    /// odpowiedzi (zmierzone 2026-08-28). Ścieżka w panelu ikonki ma własne przycinanie
    /// od 2026-08-09; nazwa klucza go nie miała.
    static func skrocony(_ klucz: String, do limit: Int = 60) -> String {
        let bezpieczny = bezLamaczyWiersza(klucz)
        guard bezpieczny.count > limit else { return bezpieczny }
        // Liczba w ogonie opisuje WEJŚCIE, nie wynik zamiany — inaczej „(212 znaków)"
        // przy stu powrotach karetki mówiłoby o naszym zapisie, nie o tym, co przyszło.
        return bezpieczny.prefix(limit) + "… (\(klucz.count) znaków)"
    }

    /// Zamienia łamacze wiersza i znaki sterujące na **widoczny** zapis.
    ///
    /// 🔴 Pozycja 10 kolejki, audyt 2026-09-02 (E2-P2-01). Do tego dnia `skrocony`
    /// przycinał wyłącznie **długość**, więc `%0D%0A` w ścieżce przechodziło przez
    /// `decode` i rozbijało jeden wiersz logu gospodarza na dwa — drugi z prefiksem
    /// `[AppBridge]`, nie do odróżnienia od prawdziwego wpisu mostu. Ładunek wjeżdżał
    /// tym samym żądaniem, które zamek nr 3 odrzuca, więc odmowa go nie zatrzymywała.
    ///
    /// Naprawiane **przed** warstwą klikania, nie po: §3 pkt 4
    /// [[Plan-warstwa-klikania-w-moscie]] obiecuje ślad w dzienniku, po którym da się
    /// odpowiedzieć, co kliknął most, a co człowiek. Obietnica stoi na tym logu.
    ///
    /// Zamiana, nie skasowanie: log ma odpowiadać na pytanie „co przyszło z zewnątrz",
    /// a ciche zjedzenie znaku tę odpowiedź zabiera.
    ///
    /// ⚠️ Sito musi patrzeć na **skalary**, nie na znaki. `"\r\n"` jest w Swifcie
    /// JEDNYM grafemem, więc `String.contains("\n")` zwraca dla niego `false` przy
    /// obecnych skalarach 13 i 10 — pierwsza wersja testów tej naprawy przechodziła
    /// tak na zielono przy nienaprawionym kodzie. Ta sama rodzina co E5-P1-01.
    static func bezLamaczyWiersza(_ tekst: String) -> String {
        var wynik = ""
        wynik.reserveCapacity(tekst.count)
        for skalar in tekst.unicodeScalars {
            switch skalar.value {
            case 0x0A: wynik += "\\n"
            case 0x0D: wynik += "\\r"
            case 0x09: wynik += "\\t"
            // Separatory wiersza i akapitu Unicode łamią wiersz w części czytników
            // logów tak samo jak `\n`, a znakami sterującymi ASCII nie są.
            case 0x2028: wynik += "\\u2028"
            case 0x2029: wynik += "\\u2029"
            case 0x00...0x1F, 0x7F:
                // Reszta sterujących — w tym ESC (0x1B), czyli początek sekwencji
                // ANSI, którą terminal wykona zamiast pokazać.
                wynik += String(format: "\\x%02X", skalar.value)
            default:
                wynik.unicodeScalars.append(skalar)
            }
        }
        return wynik
    }

    /// Kasuje jeden klucz albo — gdy `klucz` jest `nil` — wszystkie z białej listy.
    /// Zwraca nazwy skasowanych kluczy.
    @discardableResult
    func zresetuj(klucz: String?) throws -> [String] {
        let ustawienia = defaults
        if let klucz {
            try sprawdzKlucz(klucz)
            ustawienia.removeObject(forKey: klucz)
            return [klucz]
        }
        let wszystkie = lock.withLock { wpisy.keys.sorted() }
        for k in wszystkie { ustawienia.removeObject(forKey: k) }
        return wszystkie
    }

    @discardableResult
    private func sprawdzKlucz(_ klucz: String) throws -> Wpis {
        let (wpis, dostepne) = lock.withLock {
            (wpisy[klucz], wpisy.keys.sorted())
        }
        guard let wpis else {
            guard !dostepne.isEmpty else {
                throw BridgeError.notFound(
                    "Ta aplikacja nie zgłosiła żadnego ustawienia do zmiany z mostu. "
                    + "Dopisz w niej BridgeDefaults.shared.allow([…]) — most nie rusza "
                    + "kluczy, których program sam nie wymienił."
                )
            }
            throw BridgeError.notFound(
                // Nazwa przycięta: bez tego klucz o 100 000 znaków wracał w całości
                // w treści odpowiedzi.
                "Klucz \"\(Self.skrocony(klucz))\" nie jest na białej liście tej aplikacji. "
                + "Dostępne: \(dostepne.joined(separator: ", "))"
            )
        }
        return wpis
    }

    /// Typy, które `UserDefaults` przyjmuje bez wywracania procesu.
    static func dozwolonaWartosc(_ wartosc: Any) -> Bool {
        switch wartosc {
        case is String, is NSNumber, is Bool, is Data, is Date:
            return true
        case let tablica as [Any]:
            return tablica.allSatisfy { dozwolonaWartosc($0) }
        case let slownik as [String: Any]:
            return slownik.values.allSatisfy { dozwolonaWartosc($0) }
        default:
            return false
        }
    }
}

// ────────────────────────────────────────────────────────────────────────
// BridgeDrawnRects.swift
// ────────────────────────────────────────────────────────────────────────


#if canImport(AppKit)

/// Prostokąt, który aplikacja **sama narysowała** — tło bloku kodu, obrys tabeli,
/// zaznaczenie, ramka wstawki.
///
/// Powód (2026-08-27, MarkRead): blok kodu miał **dwa nakładające się tła** — rysowane
/// pudełko i tło per run, o kilka punktów przesunięte. Wyszło to dopiero na powiększonym
/// wycinku PNG. Gdyby program mógł zgłosić prostokąty, które narysował, byłaby to jedna
/// linijka liczb, a nie oględziny.
///
/// Kit daje **kształt odpowiedzi**, program wypełnia — inaczej się nie da, bo tylko
/// program wie, co narysował własną ręką w `draw(_:)`.
@MainActor
public struct BridgeDrawnRect {
    /// Nazwa z kodu rysującego, np. „tło bloku kodu". Po niej rozpoznaje się winowajcę.
    public let nazwa: String
    /// Prostokąt we współrzędnych widoku `wUkladzie` (albo okna, gdy go nie podano).
    public let rect: CGRect
    /// Warstwa rysowania: im większa, tym wyżej. Po tym widać, co zasłania co.
    public let warstwa: Int
    /// Widok, w którego układzie podano `rect`. Dzięki temu most przelicza prostokąt
    /// na współrzędne **obrazka** — te same, którymi wskazuje się punkt w `/hit`.
    public let wUkladzie: NSView?

    public init(nazwa: String, rect: CGRect, warstwa: Int = 0, wUkladzie: NSView? = nil) {
        self.nazwa = nazwa
        self.rect = rect
        self.warstwa = warstwa
        self.wUkladzie = wUkladzie
    }
}

/// Rejestr dostawców prostokątów. Konwencja, nie magia: program zgłasza domknięcie,
/// które oddaje listę, a most ją tylko przelicza i podaje dalej.
@MainActor
public enum BridgeDrawnRects {

    public typealias Dostawca = @MainActor () -> [BridgeDrawnRect]

    private static var dostawcy: [(nazwa: String, dostawca: Dostawca)] = []

    /// Zgłasza mostowi, skąd wziąć listę narysowanych prostokątów.
    ///
    /// ```swift
    /// BridgeDrawnRects.registerProvider(nazwa: "edytor") {
    ///     tlaBlokowKodu.map { BridgeDrawnRect(nazwa: "tło bloku kodu", rect: $0, wUkladzie: self) }
    /// }
    /// ```
    ///
    /// W RELEASE pusta — powód ten sam co przy `BridgeRegistry.registerOnMainActor`.
    @inlinable
    public static func registerProvider(nazwa: String, _ dostawca: @escaping Dostawca) {
        #if DEBUG
        register(nazwa: nazwa, dostawca)
        #endif
    }

    /// Rejestracja właściwa. Publiczna, bo woła ją `@inlinable` wyżej.
    public static func register(nazwa: String, _ dostawca: @escaping Dostawca) {
        #if DEBUG
        dostawcy.removeAll { $0.nazwa == nazwa }
        dostawcy.append((nazwa, dostawca))
        #endif
    }

    static var zarejestrowani: [String] { dostawcy.map(\.nazwa) }

    /// Czyści rejestr. **Wyłącznie dla testów** — powód ten sam co w `BridgeWindows`.
    static func wyczysc() {
        dostawcy.removeAll()
    }

    // 🔴 Pod `#if DEBUG` od 2026-08-29 (audyt, E5N-P1-01). Ten typ jest w `PUSTE_API`,
    // czyli WOLNO mu zostać w wydaniu — ale wolno mu zostać jako **nazwa bez ciała**.
    // Funkcje niżej wołają `BridgeViewLookup`, czyli implementację, więc bez tej
    // dyrektywy wciągałyby ją z powrotem do binarki gospodarza. Puste API przestaje
    // być puste dokładnie w tym miejscu.
    #if DEBUG
    /// Zbiera prostokąty ze wszystkich dostawców i przelicza je na układ obrazka.
    static func zbierz(okno tytulOkna: String?) throws -> [String: Any] {
        guard !dostawcy.isEmpty else {
            throw BridgeError.notFound(
                "Ta aplikacja nie zgłasza narysowanych prostokątów. Kit daje tylko kształt "
                + "odpowiedzi — listę wypełnia program: BridgeDrawnRects.registerProvider(nazwa:) { … }. "
                + "Sensu nabiera to tam, gdzie program rysuje coś własną ręką w draw(_:)."
            )
        }

        let okno = try BridgeViewLookup.wybierzOkno(tytul: tytulOkna)
        let ramka = try BridgeViewLookup.widokRamki(okno)

        var wynik: [[String: Any]] = []
        for (nazwaDostawcy, dostawca) in dostawcy {
            for prostokat in dostawca() {
                var opis: [String: Any] = [
                    "dostawca": nazwaDostawcy,
                    "nazwa": prostokat.nazwa,
                    "warstwa": prostokat.warstwa,
                    "rect": [
                        "x": zaokraglij(prostokat.rect.minX),
                        "y": zaokraglij(prostokat.rect.minY),
                        "szerokosc": zaokraglij(prostokat.rect.width),
                        "wysokosc": zaokraglij(prostokat.rect.height),
                    ],
                ]
                if let widok = prostokat.wUkladzie, widok.window === okno {
                    // 🔴 Przez `prostokatWObrazie`, nie własną arytmetyką: inaczej
                    // `wObrazie` wychodzi poza kadr zrzutu i kłóci się z `/hit`
                    // dla tego samego widoku (poz. 13, 2026-09-02).
                    opis["wObrazie"] = BridgeViewLookup.prostokatWObrazie(
                        widok.convert(prostokat.rect, to: ramka),
                        ramka: ramka,
                        setne: true
                    )
                    opis["widok"] = String(describing: type(of: widok))
                }
                wynik.append(opis)
            }
        }

        return [
            "okno": okno.title,
            // `wObrazie` mówi o ZWROCIE osi (początek w lewym górnym rogu, jak na
            // zrzucie), a nie o jednostce — ta jest ta sama co w `/hit`: punkty.
            "jednostkaWspolrzednych": "pt",
            // Kierunek układu przy współrzędnych — powód przy tym samym polu
            // w `BridgeHitTest.zbadaj` (poz. 21).
            "kierunekUkladu": BridgeAppearance.kierunekOkna(okno),
            "dostawcow": dostawcy.count,
            "prostokatow": wynik.count,
            "prostokaty": wynik,
        ]
    }

    /// Prostokąty zawierające punkt podany w układzie obrazka — dla `/hit`.
    static func podPunktem(_ punktWObrazie: CGPoint, okno: NSWindow) -> [[String: Any]] {
        guard let ramka = try? BridgeViewLookup.widokRamki(okno) else { return [] }
        var trafione: [[String: Any]] = []
        for (nazwaDostawcy, dostawca) in dostawcy {
            for prostokat in dostawca() {
                guard let widok = prostokat.wUkladzie, widok.window === okno else { continue }
                let wRamce = widok.convert(prostokat.rect, to: ramka)
                // Trafienie sprawdzamy na PEŁNYM prostokącie, a opisujemy przyciętym.
                // Dla punktu z wnętrza kadru obie odpowiedzi są te same (punkt spoza
                // części wspólnej leżałby poza obrazkiem), ale liczby w odpowiedzi
                // mają znaczyć to samo co w `lancuchWidokow`.
                guard BridgeViewLookup.wObrazie(wRamce, ramka: ramka).contains(punktWObrazie)
                else { continue }
                trafione.append([
                    "dostawca": nazwaDostawcy,
                    "nazwa": prostokat.nazwa,
                    "warstwa": prostokat.warstwa,
                    "wObrazie": BridgeViewLookup.prostokatWObrazie(
                        wRamce, ramka: ramka, setne: true
                    ),
                ])
            }
        }
        // Od wierzchu w dół: pierwsze w liście jest to, co widać.
        return trafione.sorted { ($0["warstwa"] as? Int ?? 0) > ($1["warstwa"] as? Int ?? 0) }
    }
    #endif

    /// Pół punktu wystarczy do rozpoznania przesunięcia, a pełna precyzja robi
    /// z liczb nieczytelne ogony (`23.999999999998`).
    static func zaokraglij(_ wartosc: CGFloat) -> Double {
        (Double(wartosc) * 100).rounded() / 100
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeHitTest.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` dołożone 2026-08-29 (audyt, E5N-P1-01). Do tego dnia ten plik znikał
// z RELEASE **wyłącznie dlatego, że nic się do niego nie odwoływało** — jedyne wywołania
// stoją w `registerBuiltInWyglad`, która jest pod dyrektywą. Zamek oparty na tym, że
// optymalizator usunie martwy kod, jest zamkiem cudzym: wystarczy jedno nowe odwołanie
// spoza `#if DEBUG`, żeby cały plik pojechał do wydania gospodarza, i żaden pomiar tego
// nie zapowie. Ta sama uwaga stoi w przepisie audytu przy `BridgeScreenshot` (pytanie 4d).
#if DEBUG && canImport(AppKit)

/// Sonda „co jest pod tym punktem".
///
/// Zamyka pytania typu „czy ta ramka to obrys tabeli, czy tło komórki" — zadawane
/// zwykle po obejrzeniu powiększonego wycinka PNG. Początek układu jest **jak na
/// obrazku**, w lewym górnym rogu; zamianę na układ AppKit (lewy dolny) robi most.
///
/// 🔴 **Jednostką są PUNKTY, nie piksele zrzutu.** Do 2026-08-28 stało tu, że
/// współrzędne bierze się „wprost z podglądu zrzutu", i była to nieprawda:
/// `/screenshot` rysuje w skali ekranu (2× na każdym Macu tego projektu), więc liczba
/// odczytana z PNG jest dwa razy za duża. Dla zewnętrznych trzech czwartych obrazka
/// kończyło się to odmową, ale dla wewnętrznej ćwiartki — odpowiedzią o zupełnie innym
/// miejscu, z kodem 200. Skalę do przeliczenia podaje teraz `/screenshot` w nagłówku
/// `x-bridge-skala`, a każda odpowiedź tego endpointu niesie oba rozmiary.
/// [[Problem-hit-czyta-punkty-a-zrzut-oddaje-piksele]]
@MainActor
enum BridgeHitTest {

    static func zbadaj(query: [String: String]) throws -> [String: Any] {
        guard let xTekst = query["x"], let yTekst = query["y"],
              let x = Double(xTekst), let y = Double(yTekst) else {
            throw BridgeError.badRequest(
                "Podaj punkt: /hit?x=120&y=340 — początek układu w lewym górnym rogu, "
                + "jak na zrzucie, ale w PUNKTACH, nie w pikselach PNG. Skalę podaje "
                + "/screenshot w nagłówku x-bridge-skala (zwykle 2), więc współrzędną "
                + "odczytaną z obrazka podziel przez nią."
            )
        }

        let okno = try BridgeViewLookup.wybierzOkno(tytul: query["window"])
        let ramka = try BridgeViewLookup.widokRamki(okno)
        let punktWObrazie = CGPoint(x: x, y: y)
        let punkt = BridgeViewLookup.punktZObrazu(x: CGFloat(x), y: CGFloat(y), ramka: ramka)

        let skala = okno.backingScaleFactor
        guard ramka.bounds.contains(punkt) else {
            throw BridgeError.badRequest(
                komunikatPozaOknem(
                    x: CGFloat(x), y: CGFloat(y),
                    szerokoscPt: ramka.bounds.width, wysokoscPt: ramka.bounds.height,
                    skala: skala
                )
            )
        }

        // `hitTest` chce punktu w układzie NADRZĘDNEGO widoku. Widok ramki nadrzędnego
        // nie ma, więc jego układ jest układem okna — i dokładnie w nim liczymy `punkt`.
        let trafiony = ramka.hitTest(punkt)

        var wynik: [String: Any] = [
            "okno": okno.title,
            // Nazwy pól mówią jednostkę wprost. Dawne `rozmiarObrazu` niosło punkty,
            // a czytało się jak rozmiar pliku PNG — i to była połowa tej usterki.
            "jednostkaWspolrzednych": "pt",
            "punktWObrazie": ["x": Int(x), "y": Int(y)],
            "rozmiarWPunktach": [
                "szerokosc": Int(ramka.bounds.width),
                "wysokosc": Int(ramka.bounds.height),
            ],
            "rozmiarWPikselach": [
                "szerokosc": Int((ramka.bounds.width * skala).rounded()),
                "wysokosc": Int((ramka.bounds.height * skala).rounded()),
            ],
            "skala": Int(skala.rounded()),
            // 🔴 Kierunek jedzie razem ze współrzędnymi (poz. 21, 2026-09-02).
            // Do tego dnia miały go dokładnie te dwa endpointy, które współrzędnych
            // NIE niosą (`/appearance`, `/windows`), a wszystkie cztery, które je
            // niosą, milczały — czyli pole stało tam, gdzie było najmniej potrzebne.
            // W interfejsie RTL „lewa krawędź" znaczy koniec wiersza, nie początek.
            "kierunekUkladu": BridgeAppearance.kierunekOkna(okno),
        ]

        guard let trafiony else {
            // Brak trafienia to wynik, nie błąd: tak wygląda punkt w obszarze, który
            // nie przyjmuje zdarzeń (tło okna, wyłączony widok).
            wynik["widok"] = NSNull()
            wynik["uwaga"] = "W tym punkcie żaden widok nie przyjmuje zdarzeń — "
                + "to zwykle tło okna albo widok wyłączony."
            wynik["narysowanePodPunktem"] = BridgeDrawnRects.podPunktem(punktWObrazie, okno: okno)
            // 🔴 Tabela liczy się TAKŻE tutaj (pozycja 4d, 2026-08-29). Do tego dnia brak
            // trafienia wychodził tą gałęzią i blok „tabela" nie powstawał w ogóle — a
            // `narysowanePodPunktem` w tej samej odpowiedzi meldowało prostokąt wiersza
            // pod tym punktem. Jedna odpowiedź mówiła naraz „wiersza nie ma" i „wiersz
            // jest tutaj". Tabelę szukamy wtedy po GEOMETRII, bo łańcucha widoków nie ma.
            if let tabela = tabelaPodPunktem(punkt, ramka: ramka) {
                wynik["tabela"] = opiszTabele(tabela, punktWRamce: punkt, ramka: ramka)
            }
            return wynik
        }

        wynik["widok"] = opiszWidok(trafiony, ramka: ramka)
        wynik["lancuchWidokow"] = lancuch(od: trafiony, do: ramka)
        wynik["narysowanePodPunktem"] = BridgeDrawnRects.podPunktem(punktWObrazie, okno: okno)

        if let tekst = trafiony as? NSTextView ?? nadrzednyTextView(trafiony) {
            wynik["tekst"] = opiszTekst(tekst, punktWRamce: punkt, ramka: ramka)
        }
        if let tabela = trafiony as? NSTableView ?? nadrzednaTabela(trafiony) {
            wynik["tabela"] = opiszTabele(tabela, punktWRamce: punkt, ramka: ramka)
        }
        if let element = opiszDostepnosc(punktWRamce: punkt, okno: okno, ramka: ramka) {
            wynik["dostepnosc"] = element
        }
        // 🔴 Granica odczytu, powiedziana wprost zamiast udawana (pozycja 4j).
        //
        // Dla AppKitu drzewo dostępności schodzi do konkretu (`AXButton` z etykietą,
        // `AXStaticText`) — zmierzone 2026-08-29. Dla SwiftUI **nie schodzi**: widok
        // hostujący melduje się jako `AXGroup` i ma ZERO dzieci, bo SwiftUI buduje
        // swoje elementy dostępności dopiero, gdy do procesu podłączy się klient
        // dostępności. Włączyć to można wyłącznie ustawiając aplikacji
        // `AXEnhancedUserInterface`, czyli **zmieniając zachowanie gospodarza** —
        // a odczyt nie ma prawa zmieniać tego, co mierzy (decyzja [U] 2026-08-27).
        //
        // 🔴 Stoi to na `trafiony`, czyli na widoku z `hitTest` — **nie** na elemencie
        // z drzewa dostępności (poz. 20, 2026-09-02). Zmierzone sondą: widok, który
        // nie jest elementem dostępności, sprowadza `accessibilityHitTest` do samego
        // `NSWindow`, więc gałąź warta całej pozycji 4j nie odpalała się dla niego
        // ani razu — a odpowiedź wracała z rolą `AXWindow` i prostokątem całego okna,
        // czyli dokładnie tym, co 4j miało ukrócić.
        if let host = rozpoznajNieprzezroczysteWnetrze(trafiony, ramka: ramka) {
            let dzieci = trafiony.accessibilityChildren()?.count ?? 0
            // Widać wnętrze, gdy most odróżnił konkret — sama liczba dzieci nie
            // wystarcza: przycisk SwiftUI ma zero dzieci, a jest konkretem.
            let widoczne = dzieci > 0 || czyKonkret(trafiony)
            var opis: [String: Any] = [
                "stan": widoczne ? "widoczne" : "niedostepne",
                "rodzaj": host.rodzaj,
                "rozpoznanePo": host.rozpoznanoPo,
                "dzieciDostepnosci": dzieci,
            ]
            if !widoczne { opis["uwaga"] = host.uwaga }
            wynik["wnetrze"] = opis
        }
        return wynik
    }

    /// Komunikat odmowy przy punkcie poza oknem.
    ///
    /// Wydzielony, żeby dało się go sprawdzić testem bez okna na ekranie: to jedyne
    /// zdanie, po którym wołający ma poznać, że pomylił jednostkę. Podaje oba rozmiary
    /// i gotowe przeliczenie — bo „obrazek ma 520×448 punktów" przy PNG 1040×896
    /// czytało się jak sprzeczność, a nie jak wskazówka.
    nonisolated static func komunikatPozaOknem(
        x: CGFloat, y: CGFloat,
        szerokoscPt: CGFloat, wysokoscPt: CGFloat,
        skala: CGFloat
    ) -> String {
        let pxSzer = Int((szerokoscPt * skala).rounded())
        let pxWys = Int((wysokoscPt * skala).rounded())
        var tekst = "Punkt (\(Int(x)), \(Int(y))) leży poza oknem. "
            + "Okno ma \(Int(szerokoscPt))×\(Int(wysokoscPt)) pt, "
            + "a zrzut ze /screenshot \(pxSzer)×\(pxWys) px (skala \(Int(skala.rounded()))). "
            + "/hit liczy w PUNKTACH."
        // Podpowiedź tylko wtedy, gdy podzielenie przez skalę naprawdę wpada w okno —
        // inaczej byłaby to rada, która nie działa, czyli gorsza niż jej brak.
        if skala > 1, x / skala < szerokoscPt, y / skala < wysokoscPt {
            tekst += " Jeśli te liczby odczytałeś z PNG, podziel je przez \(Int(skala.rounded())): "
                + "/hit?x=\(Int((x / skala).rounded()))&y=\(Int((y / skala).rounded()))"
        }
        return tekst
    }

    // MARK: - Opisy

    static func opiszWidok(_ view: NSView, ramka: NSView) -> [String: Any] {
        var opis: [String: Any] = [
            "klasa": String(describing: type(of: view)),
            "wObrazie": BridgeViewLookup.prostokatWObrazie(view, ramka: ramka),
            "ukryty": view.isHidden,
            "nieprzezroczysty": view.isOpaque,
        ]
        let id = view.identifier?.rawValue ?? ""
        if !id.isEmpty { opis["identyfikator"] = id }
        let dostepnosc = view.accessibilityIdentifier()
        if !dostepnosc.isEmpty { opis["identyfikatorDostepnosci"] = dostepnosc }
        if let kontrolka = view as? NSControl {
            opis["etykieta"] = kontrolka.stringValue
            opis["wlaczona"] = kontrolka.isEnabled
        }
        if let warstwa = view.layer, let tlo = warstwa.backgroundColor {
            opis["tloWarstwy"] = BridgeTextAttributes.opiszKolor(NSColor(cgColor: tlo) ?? .clear)
        }
        return opis
    }

    /// Łańcuch od trafionego widoku w górę, do ramki okna. Po nim widać, w czym
    /// dokładnie siedzi punkt — bo „NSView 300×20" samo w sobie nie mówi nic.
    static func lancuch(od widok: NSView, do ramka: NSView) -> [[String: Any]] {
        var wynik: [[String: Any]] = []
        var biezacy: NSView? = widok
        while let view = biezacy {
            wynik.append([
                "klasa": String(describing: type(of: view)),
                "wObrazie": BridgeViewLookup.prostokatWObrazie(view, ramka: ramka),
            ])
            if view === ramka { break }
            biezacy = view.superview
        }
        return wynik
    }

    static func opiszTekst(_ textView: NSTextView, punktWRamce: CGPoint, ramka: NSView) -> [String: Any] {
        guard let storage = textView.textStorage,
              let layout = textView.layoutManager,
              let kontener = textView.textContainer else {
            return ["uwaga": "pole tekstowe nie ma warstwy układu (TextKit)"]
        }

        // Początek kontenera tekstu nie pokrywa się z początkiem widoku — jest
        // przesunięty o wcięcia. Bez tej poprawki indeks znaku myli się o kilka
        // znaków przy każdym kliknięciu blisko krawędzi.
        let wWidoku = textView.convert(punktWRamce, from: ramka)
        let poczatek = textView.textContainerOrigin
        let wKontenerze = CGPoint(x: wWidoku.x - poczatek.x, y: wWidoku.y - poczatek.y)

        var ulamek: CGFloat = 0
        let indeksGlifu = layout.glyphIndex(
            for: wKontenerze,
            in: kontener,
            fractionOfDistanceThroughGlyph: &ulamek
        )
        let indeksZnaku = layout.characterIndexForGlyph(at: indeksGlifu)

        guard indeksZnaku < storage.length else {
            return [
                "klasa": String(describing: type(of: textView)),
                "uwaga": "punkt leży za końcem tekstu",
                "znakow": storage.length,
            ]
        }

        var zasieg = NSRange(location: 0, length: 0)
        let atrybuty = storage.attributes(at: indeksZnaku, effectiveRange: &zasieg)
        var opis = BridgeTextAttributes.opiszRun(storage: storage, zasieg: zasieg, atrybuty: atrybuty)
        opis["klasa"] = String(describing: type(of: textView))
        opis["indeksZnaku"] = indeksZnaku
        opis["wiersz"] = numerWiersza(storage.string, indeks: indeksZnaku)
        return opis
    }

    /// Numer wiersza liczony od 1 — tak, jak pokazuje go edytor, a nie od zera.
    static func numerWiersza(_ tekst: String, indeks: Int) -> Int {
        let ns = tekst as NSString
        let doPunktu = ns.substring(to: min(indeks, ns.length))
        return doPunktu.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    // MARK: - Wnętrze SwiftUI (drzewo dostępności)

    /// Co jest pod punktem **według drzewa dostępności** — jedyna droga do wnętrza SwiftUI.
    ///
    /// 🔴 Pozycja 4j, 2026-08-29. Zmierzone na MacDirStat: cztery różne punkty w oknie
    /// zwracały ten sam `NSHostingView` i ten sam prostokąt, więc most nie odróżniał
    /// przycisku od tła. To nie była nieuczciwość — SwiftUI **nie ma `NSView` na element**,
    /// więc `hitTest` nie ma czego zwrócić poza widokiem hostującym. Dokładnie ta sama
    /// postać odpowiedzi co przy `WKWebView`.
    ///
    /// Drzewo dostępności widzi to, czego nie widzi hierarchia widoków, i jest jedynym
    /// miejscem, w którym SwiftUI opisuje swoje elementy. Pytamy o nie **zawsze**, nie
    /// tylko przy SwiftUI — przy zwykłym AppKicie potwierdza rolę i etykietę.
    ///
    /// 🔴 `accessibilityHitTest` chce punktu w układzie **EKRANU**, nie okna. Pomyłka
    /// na tym kroku nie daje błędu, tylko odpowiedź o zupełnie innym miejscu — czyli
    /// dokładnie ten rodzaj cichego kłamstwa, po którym była naprawa jednostek w 1.0.18.
    static func opiszDostepnosc(punktWRamce: CGPoint, okno: NSWindow, ramka: NSView) -> [String: Any]? {
        let wOknie = ramka.convert(punktWRamce, to: nil)
        let naEkranie = okno.convertPoint(toScreen: wOknie)
        // 🔴 Pytamy OKNO, nie widok zawartości. Zmierzone 2026-08-29: dla tego samego
        // punktu `contentView.accessibilityHitTest` oddaje `NSWindow` (czyli nic), a
        // `okno.accessibilityHitTest` schodzi do `NSButtonCell`. Kolejność jest tu
        // całą różnicą między odpowiedzią a jej brakiem.
        guard let trafiony = okno.accessibilityHitTest(naEkranie)
                ?? okno.contentView?.accessibilityHitTest(naEkranie) else { return nil }

        var opis: [String: Any] = ["rola": rolaOpis(trafiony)]
        if let element = trafiony as? NSAccessibilityProtocol {
            if let etykieta = element.accessibilityLabel(), !etykieta.isEmpty {
                opis["etykieta"] = etykieta
            }
            if let tytul = element.accessibilityTitle(), !tytul.isEmpty {
                opis["tytul"] = tytul
            }
            if let wartosc = element.accessibilityValue() as? CustomStringConvertible {
                let tekst = String(describing: wartosc)
                if !tekst.isEmpty {
                    // 🔴 Sufit liczony w UTF-16 i cięty na granicy sekwencji złożonej —
                    // ta sama funkcja, którą tnie `/text-attributes`. Sam sufit stoi
                    // w `BridgeLimity`, powód w jego komentarzu (poz. 19).
                    let dlugosc = (tekst as NSString).length
                    let (pokazany, pokryto) = BridgeTextAttributes.skrot(
                        tekst, budzet: BridgeLimity.maksZnakowWartosci
                    )
                    opis["wartosc"] = pokazany
                    opis["wartoscObcieta"] = pokryto < dlugosc
                    if pokryto < dlugosc {
                        // W jednostkach UTF-16 — tych samych, którymi liczą `od` i `do`
                        // w `/text-attributes`, gdzie po tę treść się idzie dalej.
                        opis["wartoscZnakow"] = dlugosc
                    }
                }
            }
            let podrola = element.accessibilitySubrole()?.rawValue ?? ""
            if !podrola.isEmpty { opis["podrola"] = podrola }
            opis["wlaczony"] = element.isAccessibilityEnabled()

            // Prostokąt elementu przychodzi w układzie ekranu — sprowadzamy go do obrazka
            // tą samą drogą co wszystko inne, żeby dało się go przyłożyć do zrzutu.
            let naEkranieProstokat = element.accessibilityFrame()
            if !naEkranieProstokat.isEmpty {
                let wOknieProstokat = okno.convertFromScreen(naEkranieProstokat)
                opis["wObrazie"] = BridgeViewLookup.prostokatWObrazie(
                    ramka.convert(wOknieProstokat, from: nil), ramka: ramka
                )
            }
        }
        opis["klasa"] = String(describing: type(of: trafiony))

        return opis
    }

    // MARK: - Widoki, których wnętrza most nie widzi

    /// Widok, który zajmuje obszar interfejsu, ale most nie odróżni w nim elementów.
    struct NieprzezroczysteWnetrze {
        /// Czym to jest — o ile nazwa klasy pozwala to powiedzieć.
        let rodzaj: String
        /// `klasa` albo `objaw`. 🔴 To pole trzyma **poziom pewności**: rozpoznanie
        /// po klasie mówi, co to jest; rozpoznanie po objawie mówi tylko, że wnętrza
        /// nie widać. Bez tego rozróżnienia wołający nie wie, ile wolno mu wyczytać.
        let rozpoznanoPo: String
        let uwaga: String
    }

    /// Ile okna musi zająć widok bez rozpoznanej klasy, żeby jego nieodróżnialne
    /// wnętrze było wiadomością, a nie szumem.
    ///
    /// 🔴 Bez tego progu ostrzeżenie doklejałoby się do **każdego** pustego `NSView` —
    /// tła, przekładki, paska — gdzie „most nie odróżni tu elementów" jest prawdą
    /// bez treści. Ćwiartka okna to obszar, który wołający wziąłby za interfejs.
    static let minimalnaCzescOknaHosta = 0.25

    /// Czy wnętrze tego widoku jest dla mostu nieprzezroczyste — i skąd to wiadomo.
    ///
    /// 🔴 **Dwie drogi, bo sama nazwa klasy nie wystarcza** (poz. 20, 2026-09-02).
    /// Do tego dnia stało tu `String(describing:).contains("NSHostingView")`, czyli
    /// pytanie o nazwę klasy **konkretnej**. Zmierzone sondą: goły `NSHostingView<Text>`
    /// trafiał, a `MojHost: NSHostingView<Text>` — czyli to, co pisze się w prawdziwej
    /// aplikacji — **nie trafiał** i most milczał o granicy, dla której ta gałąź istnieje.
    ///
    /// 1. **Łańcuch dziedziczenia** — łapie podklasy i nazywa rodzaj.
    /// 2. **Objaw** — element bez dzieci w drzewie dostępności, o roli grupy, którego
    ///    `hitTest` nie odróżnia punktów. Ta droga obejmuje też `WKWebView` i widoki
    ///    Metala, o których pierwsza nic nie wie.
    static func rozpoznajNieprzezroczysteWnetrze(
        _ widok: NSView, ramka: NSView
    ) -> NieprzezroczysteWnetrze? {
        if let rodzaj = rodzajPoKlasie(widok) {
            return NieprzezroczysteWnetrze(
                rodzaj: rodzaj, rozpoznanoPo: "klasa", uwaga: uwagaOWnetrzu(rodzaj: rodzaj)
            )
        }
        // 🔴 Przodkowie, nie tylko sam trafiony (2026-09-02, znalezione powierzchnią
        // demo z pozycji 23). `hitTest` w prawdziwym ekranie SwiftUI **nie zatrzymuje
        // się na hoście**: zmierzone na demie, punkt w przycisku oddaje
        // `SwiftUIAppKitButton`, a punkt obok — goły `NSView`. Host jest wtedy dopiero
        // przodkiem, więc sito pytające wyłącznie o trafiony widok nie odpalało się
        // na żadnym prawdziwym ekranie SwiftUI. Pomiar audytu („goły NSHostingView
        // trafia") był robiony na jednym `Text` i tego nie pokazał.
        if let rodzaj = rodzajPrzodka(widok, ramka: ramka) {
            return NieprzezroczysteWnetrze(
                rodzaj: rodzaj, rozpoznanoPo: "przodek", uwaga: uwagaOWnetrzu(rodzaj: rodzaj)
            )
        }
        guard czyWnetrzeNieodroznialne(widok, ramka: ramka) else { return nil }
        return NieprzezroczysteWnetrze(
            rodzaj: "nieznany", rozpoznanoPo: "objaw", uwaga: uwagaOWnetrzu(rodzaj: nil)
        )
    }

    /// Rodzaj najbliższego przodka, który jest widokiem hostującym. Szukamy do ramki
    /// okna włącznie — wyżej nie ma już nic, co należałoby do gospodarza.
    static func rodzajPrzodka(_ widok: NSView, ramka: NSView) -> String? {
        var biezacy = widok.superview
        while let view = biezacy {
            if let rodzaj = rodzajPoKlasie(view) { return rodzaj }
            if view === ramka { return nil }
            biezacy = view.superview
        }
        return nil
    }

    /// Czy most **odróżnił** ten punkt, czy oddał anonimowy prostokąt.
    ///
    /// 🔴 To rozstrzyga o `stan`, a przez to o tym, czy w odpowiedzi stanie zdanie
    /// „most nie odróżni tu przycisku od tła". Wewnątrz hosta SwiftUI **oba przypadki
    /// są prawdziwe naraz**: punkt w przycisku oddaje `AXButton` z etykietą, a punkt
    /// dwa piksele obok — widok bez roli i bez nazwy. Jedno zdanie na całą powierzchnię
    /// hosta kłamałoby w połowie punktów.
    static func czyKonkret(_ widok: NSView) -> Bool {
        let rola = widok.accessibilityRole()?.rawValue ?? ""
        if !rola.isEmpty,
           rola != NSAccessibility.Role.group.rawValue,
           rola != NSAccessibility.Role.unknown.rawValue {
            return true
        }
        if let etykieta = widok.accessibilityLabel(), !etykieta.isEmpty { return true }
        if let tytul = widok.accessibilityTitle(), !tytul.isEmpty { return true }
        return false
    }

    /// Rodzaj hosta z **łańcucha** klas — nie z nazwy klasy konkretnej.
    ///
    /// `NSHostingView` jest generyczny, więc `as? NSHostingView` bez znajomości
    /// parametru się nie uda; zostaje nazwa, ale czytana w górę po przodkach.
    nonisolated static func rodzajPoKlasie(_ widok: NSView) -> String? {
        var klasa: AnyClass? = type(of: widok)
        while let biezaca = klasa {
            let nazwa = String(describing: biezaca)
            if nazwa.contains("NSHostingView") { return "SwiftUI" }
            if nazwa.contains("WKWebView") { return "WebKit" }
            if nazwa.contains("MTKView") { return "Metal" }
            klasa = biezaca.superclass()
        }
        return nil
    }

    /// Zachowany dla czytelności wywołań i testów: czy widok hostuje SwiftUI.
    nonisolated static func czyHostSwiftUI(_ widok: NSView) -> Bool {
        rodzajPoKlasie(widok) == "SwiftUI"
    }

    /// Objaw: obszar interfejsu, w którym most nie umie wskazać elementu.
    ///
    /// Trzy warunki naraz — każdy z osobna daje fałszywe trafienia:
    /// 1. zero dzieci w drzewie dostępności,
    /// 2. rola grupy albo nieznana (przycisk czy pole tekstowe **są** konkretem
    ///    i nie mają być tak oznaczane),
    /// 3. `hitTest` zwraca ten sam widok dla punktów rozrzuconych po całym obszarze —
    ///    kontener z widokami potomnymi odpada już tutaj.
    static func czyWnetrzeNieodroznialne(_ widok: NSView, ramka: NSView) -> Bool {
        guard (widok.accessibilityChildren()?.count ?? 0) == 0 else { return false }

        let rola = widok.accessibilityRole()?.rawValue ?? ""
        let rolaBezKonkretu = rola.isEmpty
            || rola == NSAccessibility.Role.group.rawValue
            || rola == NSAccessibility.Role.unknown.rawValue
        guard rolaBezKonkretu else { return false }

        let obszar = widok.bounds.width * widok.bounds.height
        let obszarRamki = ramka.bounds.width * ramka.bounds.height
        guard obszarRamki > 0, Double(obszar / obszarRamki) >= minimalnaCzescOknaHosta else {
            return false
        }

        // Punkty w ćwiartkach i w środku. Wszystkie muszą wrócić tym samym widokiem —
        // inaczej most JEDNAK odróżnia punkty w tym obszarze i nie ma o czym ostrzegać.
        let ulamki: [(CGFloat, CGFloat)] = [(0.5, 0.5), (0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
        for (ux, uy) in ulamki {
            let wSwoim = CGPoint(
                x: widok.bounds.minX + widok.bounds.width * ux,
                y: widok.bounds.minY + widok.bounds.height * uy
            )
            let wRamce = widok.convert(wSwoim, to: ramka)
            guard ramka.bounds.contains(wRamce) else { continue }
            guard ramka.hitTest(wRamce) === widok else { return false }
        }
        return true
    }

    private static func uwagaOWnetrzu(rodzaj: String?) -> String {
        let wstep: String
        switch rodzaj {
        case "SwiftUI":
            // 🔴 Zdanie poprawione 2026-09-02 po pomiarze na demie. Do tego dnia stało
            // tu „SwiftUI nie ma osobnego NSView na element" i „każdy punkt tego obszaru
            // da tę samą odpowiedź" — i to przestało być prawdą: `hitTest` schodzi dziś
            // do widoków wewnętrznych SwiftUI (zmierzone: punkt w przycisku oddaje
            // `SwiftUIAppKitButton`, punkt obok — `HostProbny`). Nie zmienia to wniosku,
            // bo nazwy klas wewnętrznych SwiftUI nie są żadnym kontraktem, a DRZEWO
            // DOSTĘPNOŚCI dalej zatrzymuje się na hoście — ale mówimy to, co zmierzone.
            wstep = "Punkt leży w widoku hostującym SwiftUI. Drzewo dostępności zatrzymuje "
                + "się na hoście (AXGroup bez dzieci), więc most nie poda tu roli ani "
                + "etykiety elementu. Hierarchia widoków bywa głębsza — nazwy klas "
                + "wewnętrznych SwiftUI nie są jednak kontraktem i potrafią zniknąć "
                + "z wersji na wersję, "
        case "WebKit":
            wstep = "To jest widok WebKita. Treść strony żyje w osobnym procesie i nie ma "
                + "osobnego NSView na element, "
        case "Metal":
            wstep = "To jest widok rysowany Metalem. Jego zawartość to jedna tekstura bez "
                + "osobnych NSView i bez drzewa dostępności, "
        default:
            wstep = "Ten widok zajmuje obszar interfejsu, ale nie ma ani widoków potomnych, "
                + "ani dzieci w drzewie dostępności, "
        }
        return wstep
            + "więc na tym punkcie most nie ma czym nazwać elementu. Do rozpoznania "
            + "użyj /screenshot i /diff. Most NIE włącza sobie trybu rozszerzonej "
            + "dostępności, bo to zmieniłoby zachowanie mierzonej aplikacji."
    }

    private static func rolaOpis(_ element: Any) -> String {
        guard let obiekt = element as? NSAccessibilityProtocol,
              let rola = obiekt.accessibilityRole()?.rawValue, !rola.isEmpty else {
            return "nieznana"
        }
        return rola
    }

    // MARK: - Tabele i drzewa

    /// Opis tabeli pod punktem — spójny sam ze sobą.
    ///
    /// 🔴 Pozycja 4d, 2026-08-29. `/hit` potrafił zgubić wiersz i **w tej samej
    /// odpowiedzi** podać prostokąt tego wiersza jako zawierający pytany punkt.
    /// Dwie przyczyny, obie usunięte tutaj:
    /// 1. blok „tabela" powstawał tylko wtedy, gdy `hitTest` cokolwiek zwrócił —
    ///    przy braku trafienia znikał, choć tabela pod punktem była,
    /// 2. wynik opierał się wyłącznie na `row(at:)`, bez drugiego zdania. Teraz przy
    ///    `-1` pytamy niezależnym `rows(in:)` i mówimy wprost, że odpowiedzi się różnią.
    ///
    /// Dochodzi `wierszWObrazie` — prostokąt wiersza w tym samym układzie co reszta
    /// odpowiedzi, żeby dało się go przyłożyć do zrzutu bez przeliczania.
    static func opiszTabele(_ tabela: NSTableView, punktWRamce: CGPoint, ramka: NSView) -> [String: Any] {
        let wTabeli = tabela.convert(punktWRamce, from: ramka)
        var opis: [String: Any] = [
            "klasa": String(describing: type(of: tabela)),
            "kolumna": tabela.column(at: wTabeli),
            "wierszy": tabela.numberOfRows,
        ]

        let zApi = tabela.row(at: wTabeli)
        // Drugie, niezależne zdanie o tym samym punkcie: prostokąt 1×1 zamiast punktu.
        let zGeometrii = tabela.rows(in: CGRect(origin: wTabeli, size: CGSize(width: 1, height: 1)))
        let wierszZGeometrii = zGeometrii.location == NSNotFound || zGeometrii.length == 0
            ? -1
            : zGeometrii.location

        let wiersz = zApi >= 0 ? zApi : wierszZGeometrii
        opis["wiersz"] = wiersz
        opis["zrodloWiersza"] = zApi >= 0 ? "row(at:)" : (wiersz >= 0 ? "rows(in:)" : "brak")

        if zApi < 0 && wierszZGeometrii >= 0 {
            opis["uwaga"] = "row(at:) nie wskazał wiersza, ale punkt leży w prostokącie "
                + "wiersza \(wierszZGeometrii) — biorę odpowiedź z geometrii. "
                + "Tak wygląda punkt w wierszu, ale poza obszarem etykiety."
        } else if zApi >= 0 && wierszZGeometrii >= 0 && zApi != wierszZGeometrii {
            // 🔴 Pozycja 22, 2026-09-02. Drugie zdanie o tym samym punkcie liczyło się
            // bezwarunkowo, ale konsultowane było **tylko** przy braku pierwszego —
            // więc gdy oba odpowiadały, a co innego, most brał pierwsze i nie mówił ani
            // słowa. Koszt tego zdania jest już zapłacony trzy linijki wyżej; milczenie
            // o rozjeździe nie oszczędzało niczego poza informacją.
            opis["wierszZGeometrii"] = wierszZGeometrii
            opis["uwaga"] = "Dwa niezależne zdania o tym samym punkcie nie zgadzają się: "
                + "row(at:) mówi \(zApi), rows(in:) — \(wierszZGeometrii). Biorę row(at:), "
                + "bo to droga podstawowa, a obie liczby masz w odpowiedzi. Tak wygląda "
                + "tabela w trakcie animacji rozwijania albo po reloadData bez przebiegu "
                + "układu — zanim policzysz cokolwiek na tym numerze, sprawdź, czy tabela "
                + "jest w stanie ustalonym."
        } else if wiersz < 0 {
            opis["uwaga"] = "W tym punkcie nie ma wiersza — ani row(at:), ani rows(in:) "
                + "go nie widzą. To zwykle nagłówek, obszar pod ostatnim wierszem albo margines."
        }

        if wiersz >= 0, wiersz < tabela.numberOfRows {
            opis["wierszWObrazie"] = prostokatZTabeli(
                tabela.rect(ofRow: wiersz), tabela: tabela, ramka: ramka
            )
        }
        if wiersz >= 0, let etykieta = etykietaWiersza(tabela, wiersz: wiersz), !etykieta.isEmpty {
            opis["etykieta"] = etykieta
        }
        if let drzewo = tabela as? NSOutlineView, wiersz >= 0 {
            opis["poziomZagniezdzenia"] = drzewo.level(forRow: wiersz)
            if let pozycja = drzewo.item(atRow: wiersz) {
                opis["rozwiniety"] = drzewo.isItemExpanded(pozycja)
                opis["rozwijalny"] = drzewo.isExpandable(pozycja)
            }
        }
        return opis
    }

    /// Treść etykiety wiersza — czyli to, co widać, a nie nazwa klasy komórki.
    ///
    /// 🔴 `makeIfNecessary: false` jest tu **warunkiem, nie optymalizacją**: odczyt nie
    /// ma prawa zbudować komórki, której gospodarz jeszcze nie pokazał. Dla wiersza poza
    /// widocznym zakresem odpowiedź brzmi `nil` i to jest uczciwe — most opisuje to,
    /// co jest na ekranie (pozycja 4e, 2026-08-29).
    static func etykietaWiersza(_ tabela: NSTableView, wiersz: Int) -> String? {
        for kolumna in 0..<max(tabela.numberOfColumns, 0) {
            guard let komorka = tabela.view(atColumn: kolumna, row: wiersz, makeIfNecessary: false) else {
                continue
            }
            if let tekst = pierwszyNapis(w: komorka) { return tekst }
        }
        return nil
    }

    /// Pierwszy niepusty napis w poddrzewie komórki, w kolejności rysowania.
    private static func pierwszyNapis(w widok: NSView) -> String? {
        if let pole = widok as? NSTextField, !pole.stringValue.isEmpty { return pole.stringValue }
        if let kontrolka = widok as? NSControl, !kontrolka.stringValue.isEmpty { return kontrolka.stringValue }
        for pod in widok.subviews {
            if let tekst = pierwszyNapis(w: pod) { return tekst }
        }
        return nil
    }

    /// Tabela leżąca pod punktem, szukana po geometrii — dla gałęzi bez trafienia.
    /// Bierzemy **najgłębszą**, żeby tabela w tabeli nie zgubiła tej właściwej.
    static func tabelaPodPunktem(_ punktWRamce: CGPoint, ramka: NSView) -> NSTableView? {
        var znaleziona: NSTableView?
        func zejdz(_ view: NSView) {
            for pod in view.subviews { zejdz(pod) }
            guard znaleziona == nil, let tabela = view as? NSTableView, !tabela.isHidden else { return }
            let wTabeli = tabela.convert(punktWRamce, from: ramka)
            if tabela.bounds.contains(wTabeli) { znaleziona = tabela }
        }
        zejdz(ramka)
        return znaleziona
    }

    /// Prostokąt z układu tabeli do układu obrazka. Zwrot osi i przycięcie do kadru
    /// robi `prostokatWObrazie` — nic nie dokładamy do okna gospodarza.
    static func prostokatZTabeli(_ prostokat: CGRect, tabela: NSTableView, ramka: NSView) -> [String: Any] {
        BridgeViewLookup.prostokatWObrazie(tabela.convert(prostokat, to: ramka), ramka: ramka)
    }

    static func nadrzednyTextView(_ view: NSView) -> NSTextView? {
        var biezacy: NSView? = view.superview
        while let v = biezacy {
            if let text = v as? NSTextView { return text }
            biezacy = v.superview
        }
        return nil
    }

    static func nadrzednaTabela(_ view: NSView) -> NSTableView? {
        var biezacy: NSView? = view.superview
        while let v = biezacy {
            if let tabela = v as? NSTableView { return tabela }
            biezacy = v.superview
        }
        return nil
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeIkona.swift
// ────────────────────────────────────────────────────────────────────────


#if DEBUG && canImport(AppKit)

/// Ikonka mostu w pasku menu: cała ikonka [U], w której **świeci ramka, a młotek stoi**.
///
/// 🔴 **Grafika jest [U], nie moja.** Plik przyszedł jako `~/Desktop/Xcode.svg`
/// (polecenie [U] 2026-08-27: *„wstaw nową ikonkę zamiast antenki"*) i siedzi niżej
/// **bajt w bajt** — bez skalowania, przycinania, wycinania tła i dobierania kolorów.
/// Kod robi z nim dwie rzeczy, obie na polecenie [U]:
/// 1. rysuje go w całości jako szablon paska menu (system dobiera czerń albo biel),
/// 2. przy pytaniu od Claude Code zapala **ramkę** na pomarańczowo (`#D97706`, kolor
///    podany przez [U]), zostawiając młotek w barwie paska.
///
/// 🔴 Który kawałek świeci, rozstrzygnięte przez [U] 2026-08-27 **po obejrzeniu obu
/// wariantów w prawdziwym pasku menu**: najpierw świecił młotek, po porównaniu
/// zostało odwrotnie. Powód jest widoczny dopiero przy 16 punktach — ramka to duża
/// wypełniona bryła, a młotek cienka ukośna kreska, więc pomarańcz na ramce widać
/// kątem oka, a na młotku prawie nie. **Nie odwracaj tego z powrotem** bez pytania.
///
/// Podział na „młotek" i „ramkę" **nie jest przeróbką pliku** — to odczyt tego, co
/// w nim jest: młotek jest osobną spójną wyspą pikseli (zmierzone 2026-08-27 —
/// pięć wysp, młotek jako jedyna sięga od dolnej do górnej krawędzi).
///
/// Dlaczego treść pliku siedzi w kodzie, a nie ścieżka do niego: kit wpina się
/// do kolejnych aplikacji i jedzie między dwoma Makami. Ścieżka do Biurka nie
/// istnieje na drugiej maszynie ani w żadnej aplikacji-gospodarzu — ikonka
/// znikałaby po cichu, a najmniej przydatna awaria to taka, której nie widać.
///
/// `@MainActor`, bo `NSImage` nie jest `Sendable`, a ikonka i tak żyje wyłącznie
/// w pasku menu.
@MainActor
enum BridgeIkona {

    /// Rozmiar w pasku menu. 16 punktów to wysokość, przy której systemowe ikonki
    /// stoją równo z resztą paska.
    /// Bok ikonki w punktach.
    ///
    /// 16 → **18** na polecenie [U] 2026-09-03 („powiększyć ikonę w menu bar").
    /// Pasek menu ma 22 pt wysokości, więc 18 to widoczna zmiana, która nadal zostawia
    /// margines nad i pod. Jedna zmiana, nie skok — jeśli [U] chce jeszcze większą,
    /// zmienia się TUTAJ i nigdzie indziej: `szablon`, mrugnięcie i maska młotka liczą
    /// się z tej samej liczby.
    static let bok: CGFloat = 18

    /// Ile pikseli na punkt trzyma bitmapa. 4× (64 px) to zapas ponad Retinę —
    /// z tej samej bitmapy liczy się maskę młotka, a przy 16 px wyspy zlewałyby się
    /// antyaliasingiem w jedną plamę i podział przestałby działać.
    static let skala = 4

    /// Barwa mrugnięcia. Polecenie [U] 2026-08-27: *„kolor ma być pomarańczowy #D97706"*.
    /// Wcześniej zieleń (do 2026-08-27), przez chwilę czerwień — obie zdjęte na polecenie.
    static let barwaMrugniecia = NSColor(
        srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255, alpha: 1
    )

    /// Cała ikonka jako szablon paska menu — stan spoczynku i stan awarii.
    static let szablon: NSImage? = {
        guard let obraz = wczytajSVG() else {
            // Zapas: systemowy młotek. Gdyby ImageIO kiedyś przestało czytać SVG,
            // ikonka nie zniknie — zmieni się, i to widać.
            let zapas = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Most AppBridge")
            zapas?.isTemplate = true
            return zapas
        }
        obraz.size = NSSize(width: bok, height: bok)
        // Szablon = pasek menu dobiera barwę sam, a `contentTintColor` ma co tynkować.
        // Tint działa WYŁĄCZNIE na szablonach — to ta sama pułapka, przez którą awaria
        // świeciła kiedyś kolorem „wszystko gra" (2026-08-11).
        obraz.isTemplate = true
        obraz.accessibilityDescription = "Most AppBridge"
        return obraz
    }()

    /// Ikonka mrugnięcia: ramka w `barwaMrugniecia`, młotek w barwie paska.
    ///
    /// Nie jest szablonem — szablon z definicji ma jedną barwę, a tu chodzi
    /// dokładnie o to, żeby dwie części miały różne. Dlatego barwę części stałej
    /// (młotka) podaje wołający, dobraną do wyglądu paska w tej chwili.
    ///
    /// - Parameter barwaStala: barwa młotka, czyli tego, co **nie** mruga.
    static func zMrugnieciem(barwaStala: NSColor) -> NSImage? {
        guard let maska = maskaMlotka, let piksele = rastr else { return nil }

        let bokPx = Int(bok) * skala
        guard let cel = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: bokPx, pixelsHigh: bokPx,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: bokPx * 4, bitsPerPixel: 32
        ), let bufor = cel.bitmapData else { return nil }

        let mlotekRGB = skladowe(barwaStala)
        let ramkaRGB = skladowe(barwaMrugniecia)

        for i in 0..<(bokPx * bokPx) {
            let alfa = piksele[i * 4 + 3]
            guard alfa > 0 else {
                bufor[i * 4] = 0; bufor[i * 4 + 1] = 0; bufor[i * 4 + 2] = 0; bufor[i * 4 + 3] = 0
                continue
            }
            // Maska wskazuje młotek — czyli część, która NIE mruga.
            let barwa = maska[i] ? mlotekRGB : ramkaRGB
            // Premnożenie przez alfę: `NSBitmapImageRep` bez jawnego formatu trzyma
            // składowe premnożone. Bez tego krawędzie antyaliasingu wychodzą jasną obwódką.
            let a = Double(alfa) / 255
            bufor[i * 4] = UInt8((barwa.0 * a).rounded())
            bufor[i * 4 + 1] = UInt8((barwa.1 * a).rounded())
            bufor[i * 4 + 2] = UInt8((barwa.2 * a).rounded())
            bufor[i * 4 + 3] = alfa
        }

        let obraz = NSImage(size: NSSize(width: bok, height: bok))
        obraz.addRepresentation(cel)
        obraz.isTemplate = false
        obraz.accessibilityDescription = "Most AppBridge — pytanie od Claude Code"
        return obraz
    }

    // MARK: - Odczyt pliku [U]

    static func wczytajSVG() -> NSImage? {
        guard let dane = svgXcode.data(using: .utf8) else { return nil }
        return NSImage(data: dane)
    }

    /// Ikonka narysowana do bufora RGBA — źródło i dla maski, i dla obrazka mrugnięcia.
    static let rastr: UnsafeMutablePointer<UInt8>? = {
        let bokPx = Int(bok) * skala
        guard let obraz = wczytajSVG(),
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: bokPx, pixelsHigh: bokPx,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .calibratedRGB, bytesPerRow: bokPx * 4, bitsPerPixel: 32
              ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        obraz.draw(in: NSRect(x: 0, y: 0, width: bokPx, height: bokPx))
        NSGraphicsContext.restoreGraphicsState()

        // Bitmapa zostaje żywa razem z `rep` — trzymamy oba, żeby wskaźnik nie osierociał.
        zrodlowyRep = rep
        return rep.bitmapData
    }()

    private static var zrodlowyRep: NSBitmapImageRep?

    // MARK: - Która wyspa jest młotkiem

    /// Maska pikseli młotka: `true` tam, gdzie rysunek należy do młotka — czyli tam,
    /// gdzie przy mrugnięciu barwa **zostaje** taka jak w spoczynku.
    ///
    /// Liczona raz. Podział jest odczytem rysunku, nie jego przeróbką: młotek jest
    /// osobną spójną wyspą, bo w tej ikonce jest **wycięty** z ramki wąskim prześwitem.
    /// Rozpoznajemy go po tym, że jako jedyny sięga od dolnej krawędzi do górnej
    /// (zmierzone na pliku [U] 2026-08-27: pięć wysp, wysokości 128, 113, 96, 79, 85 px).
    static let maskaMlotka: [Bool]? = {
        let bokPx = Int(bok) * skala
        guard let piksele = rastr else { return nil }

        var nalezy = [Bool](repeating: false, count: bokPx * bokPx)
        for i in 0..<(bokPx * bokPx) { nalezy[i] = piksele[i * 4 + 3] > 127 }

        var etykieta = [Int](repeating: 0, count: bokPx * bokPx)
        var ile = 0
        var wysokosci: [Int: (min: Int, max: Int, pole: Int)] = [:]

        for start in 0..<(bokPx * bokPx) where nalezy[start] && etykieta[start] == 0 {
            ile += 1
            var stos = [start]
            etykieta[start] = ile
            var minY = Int.max, maxY = Int.min, pole = 0

            while let i = stos.popLast() {
                let x = i % bokPx, y = i / bokPx
                pole += 1
                minY = min(minY, y); maxY = max(maxY, y)
                // Osiem sąsiadów, nie cztery: przy ukośnej rączce sąsiedztwo czterokierunkowe
                // rwie ją na kawałki i „najwyższa wyspa" przestaje być młotkiem.
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < bokPx, ny >= 0, ny < bokPx else { continue }
                    let j = ny * bokPx + nx
                    if nalezy[j], etykieta[j] == 0 { etykieta[j] = ile; stos.append(j) }
                }
            }
            wysokosci[ile] = (minY, maxY, pole)
        }

        guard ile >= 2,
              let najwyzsza = wysokosci.max(by: { ($0.value.max - $0.value.min) < ($1.value.max - $1.value.min) })
        else { return nil }

        // Kontrola: młotek ma przecinać ikonkę wzdłuż. Gdyby [U] wstawił kiedyś inną
        // ikonkę, w której nic takiego nie ma, wolę oddać `nil` i zapalić całość,
        // niż zostawić ciemny losowy kawałek cudzego rysunku.
        let wysokosc = najwyzsza.value.max - najwyzsza.value.min
        guard Double(wysokosc) >= 0.9 * Double(bokPx) else { return nil }

        return etykieta.map { $0 == najwyzsza.key }
    }()

    static func skladowe(_ kolor: NSColor) -> (Double, Double, Double) {
        guard let sRGB = kolor.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        return (sRGB.redComponent * 255, sRGB.greenComponent * 255, sRGB.blueComponent * 255)
    }

    /// Plik [U] w całości. Nie poprawiaj tego napisu ręcznie — przy nowej ikonce
    /// podmienia się go w całości plikiem od [U].
    static let svgXcode = #"""
<svg role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Xcode</title><path d="M19.06 5.3327c.4517-.1936.7744-.2581 1.097-.1936.5163.1291.7744.5163.968.7098.1936.3872.9034.7744 1.2261.8389.2581.0645.7098-.6453 1.0325-1.2906.3227-.5808.5163-1.3552.4517-1.5488-.0645-.1936-.968-.5808-1.1616-.5808-.1291 0-.3872.1291-.8389.0645-.4517-.0645-.9034-.5808-1.1616-.968-.4517-.6453-1.097-1.0325-1.6778-1.3552-.6453-.3227-1.3552-.5163-2.065-.6453-1.0325-.2581-2.065-.4517-3.0975-.3227-.5808.0645-1.2906.1291-1.8069.3227-.0645 0-.1936.1936-.0645.1936s.5808.0645.5808.0645-.5807.1292-.5807.2583c0 .1291.0645.1291.1291.1291.0645 0 1.4842-.0645 2.065 0 .6453.1291 1.3552.4517 1.8069 1.2261.7744 1.4197.4517 2.7749.2581 3.2266-.968 2.1295-8.6472 15.2294-9.0344 16.1328-.3873.9034-.5163 1.4842.5807 2.065s1.6778.3227 2.0005-.0645c.3872-.5163 7.0339-17.1654 9.2925-18.2624zm-3.6138 8.7117h1.5488c1.0325 0 1.2261.5163 1.2261.7098.0645.5163-.1936 1.1616-1.2261 1.1616h-.968l.7744 1.2906c.4517.7744.2581 1.1616 0 1.4197-.3872.3872-1.2261.3872-1.6778-.4517l-.9034-1.5488c-.6453 1.4197-1.2906 2.9684-2.065 4.7753h4.0009c1.9359 0 3.5492-1.6133 3.5492-3.5492V6.5588c-.0645-.1291-.1936-.0645-.2581 0-.3872.4517-1.4842 2.0004-4.001 7.4856zm-9.8087 8.0019h-.3227c-2.3231 0-4.1945-1.8714-4.1945-4.1945V7.0105c0-2.3231 1.8714-4.1945 4.1945-4.1945h9.3571c-.1936-.1936-.968-.5163-1.7423-.4517-.3227 0-.968.1291-1.3552-.1291-.3872-.3227-.3227-.5163-.9034-.5163H4.9277c-2.6458 0-4.7753 2.1295-4.7753 4.7753v11.7447c0 2.6458 2.1295 4.7753 4.4527 4.7108.6452 0 .8388-.5162 1.0324-.9034zM20.4152 6.9459v10.9058c0 2.3231-1.8714 4.1945-4.1945 4.1945H11.897s-.3872 1.0325.8389 1.0325h3.8719c2.6458 0 4.7753-2.1295 4.7753-4.7753V8.8173c.0646-.9034-.7098-1.4842-.9679-1.8714zm-18.5851.0646v10.8413c0 1.9359 1.6133 3.5492 3.5492 3.5492h.5808c0-.0645.7744-1.4197 2.4522-4.2591.1936-.3872.4517-.7744.7098-1.2261H4.4114c-.5808 0-.9034-.3872-.968-.7098-.1291-.5163.1936-1.1616.9034-1.1616h2.3877l3.033-5.2916s-.7098-1.2906-.9034-1.6133c-.2582-.4517-.1291-.9034.129-1.1615.3872-.3872 1.0325-.5808 1.6778.4517l.2581.3872.2581-.3872c.5808-.8389.968-.7744 1.2906-.7098.5163.1291.8389.7098.3872 1.6133L8.864 14.0444h1.3552c.4517-.7744.9034-1.5488 1.3552-2.3877-.0645-.3227-.1291-.7098-.0645-1.0325.0645-.5163.3227-.968.6453-1.3552l.3872.6453c1.2261-2.1295 2.1295-3.9364 2.3877-4.6463.1291-.3872.3227-1.1616.1291-1.8069H5.3794c-2.0005.0001-3.5493 1.6134-3.5493 3.5494zM4.605 17.7872c0-.0645.7744-1.4197.7744-1.4197 1.2261-.3227 1.8069.4517 1.8714.5163 0 0-.8389 1.4842-1.097 1.7423s-.5808.3227-.9034.2581c-.5164-.129-.839-.6453-.6454-1.097z"/></svg>
"""#
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeImageDiff.swift
// ────────────────────────────────────────────────────────────────────────

// Do cofania i nakładania premultiplikacji. `CGBitmapContext` **nie umie** trzymać
// RGBA bez premultiplikacji (`kCGImageAlphaLast` jest dla niego nieobsługiwane),
// więc format z dokumentacji da się utrzymać wyłącznie osobnym przebiegiem.

// 🔴 `#if DEBUG` dołożone 2026-08-29 (audyt, E5N-P1-01). Do tego dnia ten plik znikał
// z RELEASE **wyłącznie dlatego, że nic się do niego nie odwoływało** — jedyne wywołania
// stoją w `registerBuiltInWyglad`, która jest pod dyrektywą. Zamek oparty na tym, że
// optymalizator usunie martwy kod, jest zamkiem cudzym: wystarczy jedno nowe odwołanie
// spoza `#if DEBUG`, żeby cały plik pojechał do wydania gospodarza, i żaden pomiar tego
// nie zapowie. Ta sama uwaga stoi w przepisie audytu przy `BridgeScreenshot` (pytanie 4d).
#if DEBUG

/// Porównanie dwóch bitmap z tolerancją — regresja wyglądu jako liczba, a nie jako
/// pytanie do oka.
///
/// Powód (2026-08-27): „czy poprawka w blokach kodu ruszyła coś w tabelach" było
/// pytaniem, na które odpowiadało się oglądaniem dwóch PNG obok siebie.
///
/// 🔴 **Tolerancja jest obowiązkowa, nie kosmetyczna.** Antyaliasing subpikselowy
/// potrafi dać kilka procent różnicy między dwoma przebiegami tego samego renderu
/// na tej samej maszynie. Próg trzeba **zmierzyć** na swojej parze obrazków, a nie
/// zgadnąć — dlatego odpowiedź podaje też największą znalezioną różnicę składowej
/// (`najwiekszaRoznica`), po której ten próg się dobiera.
///
/// Celowo bez AppKit: to czysta arytmetyka na pikselach, więc endpoint może lecieć
/// w tle i nie dotyka głównego aktora ani stanu aplikacji.
nonisolated enum BridgeImageDiff {

    struct Bitmapa {
        let szerokosc: Int
        let wysokosc: Int
        /// RGBA, 8 bitów na składową, **bez premultiplikacji**.
        ///
        /// 🔴 Do 2026-09-02 to zdanie kłamało o kodzie pod sobą: bufor powstawał
        /// w kontekście `premultipliedLast`, więc przy alfie mniejszej niż 255 składowe
        /// były przemnożone przez nią. Nic to wtedy nie zmieniało (zrzuty okien są
        /// nieprzezroczyste), ale dokumentacja opisywała inny format niż kod.
        /// **Decyzja [U] 2026-09-02: prostujemy FORMAT, nie zdanie** — `wczytaj` cofa
        /// premultiplikację, `zakodujNaMiejscu` nakłada ją z powrotem tuż przed
        /// zbudowaniem obrazka. Dla danych nieprzezroczystych oba przebiegi są
        /// tożsamością, więc zmierzone progi tolerancji `/diff` **nie ruszają się**
        /// na żadnym dzisiejszym pomiarze; ruszą się dopiero na obrazkach z alfą.
        let piksele: [UInt8]
    }

    static let domyslnaTolerancja = 0.02

    // MARK: - Wejście

    static func porownaj(cialo: [String: Any]) throws -> [String: Any] {
        guard let aBase64 = cialo["a"] as? String, let bBase64 = cialo["b"] as? String else {
            throw BridgeError.badRequest(
                "Potrzebne są dwa obrazki PNG w base64: {\"a\": \"…\", \"b\": \"…\"}. "
                + "Weź je z /screenshot albo /render."
            )
        }
        let tolerancja = (cialo["tolerancja"] as? NSNumber)?.doubleValue ?? domyslnaTolerancja
        guard tolerancja >= 0, tolerancja <= 1 else {
            throw BridgeError.badRequest("tolerancja musi być z zakresu 0…1 (ułamek pełnej skali składowej)")
        }

        let a = try wczytaj(base64: aBase64, nazwa: "a")
        let b = try wczytaj(base64: bBase64, nazwa: "b")

        guard a.szerokosc == b.szerokosc, a.wysokosc == b.wysokosc else {
            throw BridgeError.badRequest(
                "Obrazki mają różne rozmiary: a \(a.szerokosc)×\(a.wysokosc), "
                + "b \(b.szerokosc)×\(b.wysokosc). Porównanie z tolerancją zakłada ten sam "
                + "rozmiar — użyj /render?width=… dla obu przebiegów."
            )
        }
        return porownaj(a: a, b: b, tolerancja: tolerancja)
    }

    static func wczytaj(base64: String, nazwa: String) throws -> Bitmapa {
        guard let dane = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw BridgeError.badRequest("Pole \"\(nazwa)\" nie jest poprawnym base64")
        }
        guard let zrodlo = CGImageSourceCreateWithData(dane as CFData, nil) else {
            throw BridgeError.badRequest("Pole \"\(nazwa)\" nie daje się odczytać jako obrazek")
        }

        // 🔴 Wymiary sprawdzamy z NAGŁÓWKA, zanim cokolwiek zdekodujemy — i to jest
        // cała obrona przed bombą dekompresyjną. Limit ciała żądania (8 MiB) mierzy
        // PLIK, a jednolity PNG 12000 × 12000 waży 567 kB; zmierzone 2026-08-28:
        // takie dwa obrazki dawały 4,4 GB w procesie gospodarza i 178 s liczenia,
        // z czego 3,9 GB nie wracało ([[Problem-brak-sufitu-na-powierzchnie-obrazka]]).
        // `CGImageSourceCopyPropertiesAtIndex` czyta sam nagłówek, bez alokacji na piksele.
        if let wlasciwosci = CGImageSourceCopyPropertiesAtIndex(zrodlo, 0, nil) as? [CFString: Any],
           let szer = wlasciwosci[kCGImagePropertyPixelWidth] as? Int,
           let wys = wlasciwosci[kCGImagePropertyPixelHeight] as? Int {
            try BridgeLimity.sprawdzPowierzchnie(
                szerokosc: szer, wysokosc: wys, co: "Obrazek \"\(nazwa)\""
            )
        }

        guard let obraz = CGImageSourceCreateImageAtIndex(zrodlo, 0, nil) else {
            throw BridgeError.badRequest("Pole \"\(nazwa)\" nie daje się odczytać jako obrazek")
        }
        return try zrasteryzuj(obraz)
    }

    /// Zawsze przez własny kontekst RGBA8/sRGB — obrazki z różnych źródeł mają różne
    /// układy składowych i profile, a porównywanie surowych bajtów bez ujednolicenia
    /// dawałoby różnicę tam, gdzie zmienił się wyłącznie zapis pliku.
    static func zrasteryzuj(_ obraz: CGImage) throws -> Bitmapa {
        let szerokosc = obraz.width
        let wysokosc = obraz.height
        guard szerokosc > 0, wysokosc > 0 else {
            throw BridgeError.badRequest("Obrazek ma zerowy rozmiar")
        }
        // Drugie sprawdzenie tego samego sufitu, tuż przed alokacją. `wczytaj` łapie
        // obrazki z żądania, ale `zrasteryzuj` jest publiczną drogą dla każdego
        // `CGImage` — a to tutaj powstaje bufor na piksele.
        try BridgeLimity.sprawdzPowierzchnie(
            szerokosc: szerokosc, wysokosc: wysokosc, co: "Obrazek do porównania"
        )
        var piksele = [UInt8](repeating: 0, count: szerokosc * wysokosc * 4)
        let przestrzen = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        let udalo = piksele.withUnsafeMutableBytes { bufor -> Bool in
            guard let kontekst = CGContext(
                data: bufor.baseAddress,
                width: szerokosc,
                height: wysokosc,
                bitsPerComponent: 8,
                bytesPerRow: szerokosc * 4,
                space: przestrzen,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            kontekst.draw(obraz, in: CGRect(x: 0, y: 0, width: szerokosc, height: wysokosc))
            // Kontekst rysuje premultiplikowane — cofamy to, żeby `Bitmapa.piksele`
            // niosło format, który obiecuje (poz. 17).
            var wRam = vImage_Buffer(
                data: bufor.baseAddress,
                height: vImagePixelCount(wysokosc),
                width: vImagePixelCount(szerokosc),
                rowBytes: szerokosc * 4
            )
            return vImageUnpremultiplyData_RGBA8888(&wRam, &wRam, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
        guard udalo else {
            throw BridgeError.failed(
                "Nie udało się przygotować bufora na obrazek (kontekst rysowania albo cofnięcie premultiplikacji)"
            )
        }
        return Bitmapa(szerokosc: szerokosc, wysokosc: wysokosc, piksele: piksele)
    }

    // MARK: - Samo porównanie

    static func porownaj(a: Bitmapa, b: Bitmapa, tolerancja: Double) -> [String: Any] {
        let prog = Int((tolerancja * 255).rounded())
        let wszystkich = a.szerokosc * a.wysokosc

        var roznych = 0
        var najwieksza = 0
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var maska = [Bool](repeating: false, count: wszystkich)

        for y in 0..<a.wysokosc {
            for x in 0..<a.szerokosc {
                let i = (y * a.szerokosc + x) * 4
                var roznica = 0
                for skladowa in 0..<4 {
                    let d = abs(Int(a.piksele[i + skladowa]) - Int(b.piksele[i + skladowa]))
                    if d > roznica { roznica = d }
                }
                if roznica > najwieksza { najwieksza = roznica }
                if roznica > prog {
                    roznych += 1
                    maska[y * a.szerokosc + x] = true
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        var wynik: [String: Any] = [
            "rozmiar": ["szerokosc": a.szerokosc, "wysokosc": a.wysokosc],
            "wszystkichPikseli": wszystkich,
            "roznychPikseli": roznych,
            "procentRoznych": (Double(roznych) / Double(wszystkich) * 10_000).rounded() / 100,
            "tolerancja": tolerancja,
            "progSkladowej": prog,
            // Po tej liczbie dobiera się próg: gdy przy identycznych przebiegach
            // wychodzi 3, tolerancja 0,02 (czyli 5) jest właściwa, a 0,0 da fałszywy alarm.
            "najwiekszaRoznicaSkladowej": najwieksza,
            "identyczne": roznych == 0,
        ]
        if roznych > 0 {
            wynik["prostokat"] = [
                "x": minX, "y": minY,
                "szerokosc": maxX - minX + 1,
                "wysokosc": maxY - minY + 1,
            ]
            if let podglad = podglad(a: a, maska: maska) {
                wynik["podgladPNG"] = podglad.base64EncodedString()
            }
        } else {
            wynik["prostokat"] = NSNull()
        }
        return wynik
    }

    /// Podgląd: pierwszy obrazek przygaszony do szarości, różnice na magentę.
    ///
    /// Magenta, bo w interfejsach macOS praktycznie nie występuje — czerwień gubi się
    /// na tle błędów i podkreśleń, a różnicy szuka się wzrokiem w jednej chwili.
    static func podglad(a: Bitmapa, maska: [Bool]) -> Data? {
        var piksele = [UInt8](repeating: 0, count: a.szerokosc * a.wysokosc * 4)
        for indeks in 0..<(a.szerokosc * a.wysokosc) {
            let i = indeks * 4
            if maska[indeks] {
                piksele[i] = 255; piksele[i + 1] = 0; piksele[i + 2] = 255; piksele[i + 3] = 255
            } else {
                let r = Double(a.piksele[i]), g = Double(a.piksele[i + 1]), b = Double(a.piksele[i + 2])
                let szary = UInt8(min(255, (0.299 * r + 0.587 * g + 0.114 * b) * 0.35 + 150))
                piksele[i] = szary; piksele[i + 1] = szary; piksele[i + 2] = szary; piksele[i + 3] = 255
            }
        }
        return zakodujNaMiejscu(piksele: &piksele, szerokosc: a.szerokosc, wysokosc: a.wysokosc)
    }

    /// Wygodne wejście dla wołających, którzy mają **wartość** — testy i drobne bitmapy.
    ///
    /// Robi kopię, bo `withUnsafeMutableBytes` na tablicy, do której ktoś inny wciąż
    /// trzyma referencję, i tak by ją zrobiło (kopiowanie przy zapisie). Gorąca droga
    /// — `podglad` — woła wariant `inout` i tej kopii nie płaci.
    static func zakoduj(piksele: [UInt8], szerokosc: Int, wysokosc: Int) -> Data? {
        var kopia = piksele
        return zakodujNaMiejscu(piksele: &kopia, szerokosc: szerokosc, wysokosc: wysokosc)
    }

    /// Kodowanie bez kopii bufora.
    ///
    /// 🔴 Pozycja 18, 2026-09-02. Do tego dnia stało tu `var kopia = piksele` na tablicy,
    /// którą `podglad` właśnie zbudował i której już nie używał — a że wołający trzymał
    /// ją dalej, kopiowanie przy zapisie **naprawdę kopiowało**. Przy suficie 40 Mpx
    /// (`BridgeLimity.maksPikseli`) to 160 MB zbędnego szczytu w pamięci gospodarza,
    /// obok 160 MB, które już tam leżały.
    ///
    /// 🔴 **Bufor jest ZUŻYWANY, nie tylko czytany** (poz. 17, 2026-09-02): wejście
    /// jest bez premultiplikacji, a `CGBitmapContext` innego formatu nie przyjmuje,
    /// więc funkcja nakłada ją **na miejscu**. Po powrocie bufor niesie wartości
    /// premultiplikowane. Dla danych nieprzezroczystych to tożsamość. Wołający
    /// (`podglad`) i tak go już nie używa — po to jest `inout`.
    static func zakodujNaMiejscu(piksele: inout [UInt8], szerokosc: Int, wysokosc: Int) -> Data? {
        let przestrzen = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let obraz: CGImage? = piksele.withUnsafeMutableBytes { bufor in
            var wRam = vImage_Buffer(
                data: bufor.baseAddress,
                height: vImagePixelCount(wysokosc),
                width: vImagePixelCount(szerokosc),
                rowBytes: szerokosc * 4
            )
            guard vImagePremultiplyData_RGBA8888(&wRam, &wRam, vImage_Flags(kvImageNoFlags))
                == kvImageNoError else { return nil }
            guard let kontekst = CGContext(
                data: bufor.baseAddress,
                width: szerokosc,
                height: wysokosc,
                bitsPerComponent: 8,
                bytesPerRow: szerokosc * 4,
                space: przestrzen,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return kontekst.makeImage()
        }
        guard let obraz else { return nil }

        let dane = NSMutableData()
        guard let cel = CGImageDestinationCreateWithData(
            dane as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(cel, obraz, nil)
        guard CGImageDestinationFinalize(cel) else { return nil }
        return dane as Data
    }
}
#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeRegistry.swift
// ────────────────────────────────────────────────────────────────────────


/// Spis endpointów, które aplikacja udostępnia mostowi.
///
/// W buildzie RELEASE wszystkie metody są puste — nic się nie rejestruje
/// i nic nie nasłuchuje. API istnieje tylko po to, żeby kod aplikacji
/// kompilował się w obu konfiguracjach bez `#if DEBUG` w każdym miejscu.
/// Cały stan siedzi za zamkiem `lock`, a `routes` nie wychodzi na zewnątrz inaczej
/// niż jako kopia — stąd `@unchecked Sendable`. „Unchecked" znaczy tu „sprawdzone
/// ręcznie", nie „pominięte": każde dotknięcie `routes` w tym pliku jest pod zamkiem.
nonisolated public final class BridgeRegistry: @unchecked Sendable {
    public static let shared = BridgeRegistry()

    private let lock = NSLock()
    private var routes: [String: BridgeRoute] = [:]

    private init() {}

    /// Rejestruje endpoint. Wywołuj przy starcie aplikacji.
    public func register(_ route: BridgeRoute) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        routes[Self.key(method: route.method, path: route.path)] = route
        #endif
    }

    /// Endpoint **dotykający interfejsu albo stanu aplikacji** — dokumentu, sceny,
    /// warstw, okien. To domyślny wybór dla większości endpointów.
    ///
    /// Handler jest izolowany do głównego aktora, więc sięganie po stan aplikacji
    /// jest tu bezpieczne i kompilator to potwierdza.
    /// `@inlinable` + puste ciało w RELEASE nie są kosmetyką: bez nich **opisy
    /// endpointów zostają w binarce wydania jako czytelny tekst**. Są argumentami
    /// budowanymi w kodzie aplikacji, więc samo `#if DEBUG` w `register(_:)` ich
    /// nie usuwa — dopiero gdy całe wywołanie da się wstawić w miejscu użycia
    /// i okaże się puste, optymalizator wyrzuca je razem z literałami.
    /// Zmierzone 2026-08-09 na CWMac: 1 → 0 trafień w RELEASE.
    @inlinable
    public func registerOnMainActor(
        method: String = "GET",
        path: String,
        description: String = "",
        handler: @escaping BridgeMainActorHandler
    ) {
        #if DEBUG
        register(.onMainActor(method: method, path: path, description: description, handler: handler))
        #endif
    }

    /// Endpoint **liczący w tle**, żeby interfejs nie zamarzł na czas długiej roboty.
    ///
    /// ⚠️ Handler nie jest izolowany do głównego aktora, więc **nie wolno mu dotykać
    /// interfejsu ani stanu aplikacji**. Naiwne sięgnięcie po cokolwiek izolowane
    /// do głównego aktora **nie skompiluje się** i to jest zmierzone — ale kontrakt
    /// broni przed pomyłką, nie przed obejściem.
    /// Jeśli długa robota musi ruszać stan aplikacji, zostaw ją na głównym aktorze
    /// i podziel na kawałki; przeniesienie jej tutaj to droga do awarii przy okazji.
    ///
    /// 🔴 **Obejścia są TRZY i każde kompiluje się bez jednego ostrzeżenia.**
    /// Sonda kompilacyjna 2026-09-02, tryb języka Swift 6, z kontrolą ujemną
    /// (naiwne sięgnięcie → błąd kompilacji, czyli sprawdzanie żyje).
    /// Wypisane **od najcichszego**, bo najgłośniejsze najłatwiej zauważyć.
    /// Audyt 2026-08-10 (E3a-P1-01) i 2026-09-02 (E3-P1-01).
    ///
    /// **1. `DispatchQueue.main.sync` — najgroźniejsze, bo zwykle DZIAŁA.**
    /// Zmierzone 2026-09-02, trzy przypadki:
    ///
    /// | co robi główny wątek | wynik |
    /// |---|---|
    /// | stoi wolny w pętli zdarzeń | **przechodzi, kod 0** — bez awarii, bez logu |
    /// | czeka na kolejkę mostu | **zakleszczenie**, bez awarii i bez śladu |
    /// | to sam handler na głównym aktorze | SIGTRAP, kod 133 |
    ///
    /// ```swift
    /// registerInBackground(path: "/cos") { _ in
    ///     DispatchQueue.main.sync { menedzer.stan }    // ⛔ przejdzie w testach
    /// }                                               //    i zawiesi u użytkownika
    /// ```
    ///
    /// Pierwszy wiersz tabeli jest tu sednem: taki kod **przechodzi w testach**
    /// i wisi dopiero wtedy, gdy zbiegnie się czas. Jedna litera dzieli go od
    /// poprawnego `DispatchQueue.main.async`, który niczego nie blokuje — ale
    /// `async` nie odda wyniku do odpowiedzi, więc jeśli go potrzebujesz, ten
    /// endpoint należy do `registerOnMainActor`, a nie tutaj.
    ///
    /// **2. `nonisolated(unsafe)` na obiekcie interfejsu — wyłącza sprawdzanie.**
    ///
    /// ```swift
    /// nonisolated(unsafe) var okno: NSWindow?          // ⛔ zdejmuje zamek,
    /// registerInBackground(path: "/cos") { _ in        //    nie rozwiązuje problemu
    ///     .json(["tytul": okno?.title ?? ""])
    /// }
    /// ```
    ///
    /// Kompiluje się czysto, a w czasie wykonania czyta stan AppKitu z obcego
    /// wątku — czyli robi dokładnie to, przed czym tryb języka Swift 6 miał bronić.
    /// Skutek jest niezdefiniowany, więc bywa, że nie widać go miesiącami.
    ///
    /// **3. `MainActor.assumeIsolated` — ubija proces, ale przynajmniej głośno.**
    ///
    /// ```swift
    /// registerInBackground(path: "/cos") { _ in
    ///     MainActor.assumeIsolated { menedzer.stan }   // ⛔ nie rób tego
    /// }
    /// ```
    ///
    /// `assumeIsolated` nie sprawdza, czy jesteś na głównym aktorze — **zapewnia**,
    /// że jesteś. Tutaj to nieprawda, więc program kończy się pułapką (SIGTRAP,
    /// kod 133; zmierzone 2026-08-10). Ślad stosu pokaże wnętrze Swifta, nie nazwę
    /// Twojego endpointu, więc awaria wygląda na błąd biblioteki.
    ///
    /// **Właściwe wyjścia są dwa i żadne nie jest obejściem:**
    /// `registerOnMainActor` z pracą podzieloną na kawałki (most mierzy 2 262
    /// żądania/s na głównym aktorze, więc próg jest wyżej, niż się wydaje) albo
    /// wzorzec zlecenia — `Task` plus natychmiastowe potwierdzenie, wzór
    /// `ErrorUpdateBridge` w `Przyklady/`.
    ///
    /// ⚠️ **Ta lista nie ogłasza się kompletną.** Poprzednia wersja tego akapitu
    /// mówiła „jedyna furtka" o pozycji 3 — i po trzech tygodniach (2026-08-10 →
    /// 2026-09-02) sonda znalazła dwie następne, obie cichsze. Zdanie, które ogłasza
    /// kompletność listy, starzeje się gorzej niż zdanie, które jej nie ogłasza.
    ///
    /// Powód `@inlinable` — patrz `registerOnMainActor`.
    @inlinable
    public func registerInBackground(
        method: String = "GET",
        path: String,
        description: String = "",
        handler: @escaping BridgeBackgroundHandler
    ) {
        #if DEBUG
        register(.inBackground(method: method, path: path, description: description, handler: handler))
        #endif
    }

    func route(method: String, path: String) -> BridgeRoute? {
        lock.lock()
        defer { lock.unlock() }
        return routes[Self.key(method: method, path: path)]
    }

    /// Lista zarejestrowanych endpointów — zwracana przez wbudowany `/routes`.
    func allRoutes() -> [BridgeRoute] {
        lock.lock()
        defer { lock.unlock() }
        return routes.values.sorted { $0.path < $1.path }
    }

    private static func key(method: String, path: String) -> String {
        "\(method.uppercased()) \(path)"
    }
}

// ────────────────────────────────────────────────────────────────────────
// BridgeRender.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` tutaj, a nie samo `#if canImport(AppKit)` — decyzja [U] 2026-08-28,
// wariant (a) z [[Problem-harness-renderujacy-zostaje-w-wydaniu]].
//
// Do 2026-08-28 ten plik stał wyłącznie pod `canImport(AppKit)`, więc
// `BridgeRenderHarness` był **jedyną** częścią mostu, która przeżywała build RELEASE
// razem z implementacją — zmierzone TestRoomem: `renderPNG` 2 w DEBUG i 2 w RELEASE.
// Powód był świadomy (harness miał działać także z celu budowanego bez mostu), ale
// skutkiem ubocznym było to, że kod rysujący widoki do bitmapy jechał do wydania
// każdej aplikacji z wpiętym mostem — i łamał jedyną własność, którą projekt
// reklamuje bezwarunkowo.
//
// Cena wybrana świadomie: harnessu **nie da się już użyć z celu zbudowanego
// w Release**. Cel testowy gospodarza buduje się w Debug, więc tam gdzie miał być,
// nadal jest.
#if DEBUG && canImport(AppKit)

/// Render **samego widoku**, nie okna — i ten sam mechanizm udostępniony programom,
/// które mostu jeszcze nie mają wpiętego.
///
/// Powód (2026-08-27): zrzut okna niesie cień, zaokrąglone rogi, belkę tytułową
/// i aktualny motyw systemu — same rzeczy, które przy porównywaniu dwóch wersji
/// zmieniają się bez powodu. Do porównania z tolerancją (`POST /diff`) potrzebna jest
/// bitmapa deterministyczna, czyli widok o zadanej szerokości i zadanym wyglądzie.
///
/// `renderPNG(budujWidok:)` to przeniesiony do kitu harness, który 2026-08-27
/// odblokował robotę nad wyglądem w MarkRead (`Tests/render-shot.swift`). Tamten
/// mieszkał w jednym programie; ten stoi w kicie, więc korzysta z niego każdy —
/// **także program bez uruchomionego mostu**, z poziomu testu albo małego celu.
@MainActor
public enum BridgeRenderHarness {

    /// Jedyne okno robocze harnessu w całym procesie.
    ///
    /// Trzymane, a nie zamykane, bo NSWindow raz utworzonego nie da się bezpiecznie
    /// zdjąć z listy `NSApplication.shared.windows` (szczegóły przy wywołaniu).
    /// Skoro jedno zostanie i tak — niech zostanie **jedno**, a nie po jednym
    /// na każdy render.
    private static var oknoRoboczeMagazyn: NSWindow?

    static func oknoRobocze() -> NSWindow {
        if let istniejace = oknoRoboczeMagazyn { return istniejace }
        let nowe = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        nowe.isReleasedWhenClosed = false
        oknoRoboczeMagazyn = nowe
        return nowe
    }

    /// Renderuje widok stojący już w oknie aplikacji.
    ///
    /// ⚠️ Podanie `szerokosc` **tymczasowo zmienia ramkę widoku** i przywraca ją po
    /// renderze. Innej drogi nie ma: żeby zobaczyć układ przy 400 punktach, widok
    /// musi przez chwilę mieć 400 punktów. Przy widoku żywego okna zobaczy to
    /// użytkownik jako mignięcie — dlatego bez `szerokosc` nic się nie rusza.
    public static func renderPNG(
        widok: NSView,
        szerokosc: CGFloat? = nil,
        wysokosc: CGFloat? = nil,
        wyglad: NSAppearance?? = nil
    ) throws -> Data {
        let pierwotnaRamka = widok.frame
        let pierwotnyWyglad = widok.appearance
        // Szerokość pojemnika tekstu zapamiętujemy osobno od ramki: przy zmianie
        // szerokości trzeba ją przestawić, żeby tekst przelał się na nowo (patrz
        // `przeliczZawijanie`), a sama ramka jej nie cofa.
        let pierwotnyKontener = (widok as? NSTextView)?.textContainer?.containerSize
        // `defer` przywraca stan także wtedy, gdy render rzuci — inaczej nieudany
        // pomiar zostawiałby aplikację [U] z widokiem w rozmiarze testowym.
        defer {
            if szerokosc != nil || wysokosc != nil { widok.frame = pierwotnaRamka }
            if wyglad != nil { widok.appearance = pierwotnyWyglad }
            if let pierwotnyKontener {
                (widok as? NSTextView)?.textContainer?.containerSize = pierwotnyKontener
            }
            widok.layoutSubtreeIfNeeded()
        }

        if let wyglad { widok.appearance = wyglad }
        if szerokosc != nil || wysokosc != nil {
            let nowaSzerokosc = szerokosc ?? pierwotnaRamka.width
            var nowaWysokosc = wysokosc ?? pierwotnaRamka.height
            if wysokosc == nil {
                // Bez podanej wysokości pytamy widok, ile miejsca chce przy tej
                // szerokości. `fittingSize` zwraca zero dla widoków bez ograniczeń
                // Auto Layout — wtedy zostaje wysokość pierwotna, a nie zero pikseli.
                widok.frame = CGRect(x: 0, y: 0, width: nowaSzerokosc, height: pierwotnaRamka.height)
                przeliczZawijanie(widok, szerokosc: nowaSzerokosc)
                widok.layoutSubtreeIfNeeded()
                let chciana = widok.fittingSize.height
                if chciana > 1 { nowaWysokosc = chciana }
            } else {
                przeliczZawijanie(widok, szerokosc: nowaSzerokosc)
            }
            // 🔴 Ramka ustawiana JAKO OSTATNIA i to nie jest kosmetyka kolejności.
            // `przeliczZawijanie` woła `sizeToFit`, który dla pola tekstowego dobiera
            // wysokość do treści — postawiony po tej linijce **nadpisywał jawnie
            // zamówioną wysokość**. Złapane pomiarem 2026-08-28: `height=20000`
            // wracało jako 527 pt, czyli tyle, ile chciał tekst.
            widok.frame = CGRect(x: 0, y: 0, width: nowaSzerokosc, height: nowaWysokosc)
        }

        widok.layoutSubtreeIfNeeded()
        return try bitmapa(widok)
    }

    /// Harness: stawia widok w oknie **poza ekranem** i renderuje go do PNG.
    ///
    /// Nie wymaga działającego mostu ani widocznego okna — nadaje się do testu
    /// wyglądu w CI i do pracy nad układem, zanim program w ogóle da się uruchomić.
    ///
    /// ```swift
    /// let png = try BridgeRenderHarness.renderPNG(szerokosc: 720, wyglad: .ciemny) {
    ///     MarkdownEditor(tekst: przykład)
    /// }
    /// ```
    public static func renderPNG(
        szerokosc: CGFloat,
        wysokosc: CGFloat? = nil,
        wyglad: Wyglad = .systemowy,
        budujWidok: () -> NSView
    ) throws -> Data {
        let widok = budujWidok()
        let wstepnaWysokosc = wysokosc ?? max(widok.fittingSize.height, 1)
        widok.frame = CGRect(x: 0, y: 0, width: szerokosc, height: wstepnaWysokosc)

        // Okno bez ramki i poza ekranem: widok potrzebuje okna, żeby mieć kontekst
        // rysowania i wygląd, ale nic z tego okna nie ma trafić na obrazek.
        //
        // 🔴 Okno jest JEDNO NA PROCES i wraca przy każdym wywołaniu. Do 2026-08-28
        // powstawało nowe za każdym razem i **żadne nie znikało**: zmierzone
        // 20 wywołań = 20 okien w `NSApplication.shared.windows`, każde z własnym
        // buforem rysowania. Ta ścieżka jest reklamowana jako „nadaje się do testu
        // wyglądu w CI", czyli do wołania w pętli — więc wyciek rósł dokładnie tam,
        // gdzie ta funkcja ma być używana.
        //
        // Dlaczego nie `close()`: nie zdejmuje okna z listy (zmierzone: 0 → 1, okno
        // dalej żyje). Dlaczego nie `isReleasedWhenClosed = true`: licznik owszem
        // wraca do zera, ale proces ginie sygnałem 11 — okno zwalnia AppKit i drugi
        // raz ARC. Zmierzone, nie wywnioskowane; dopisane do Pulapki-narzedziowe.
        //
        // Podkładania się pod wybór okna mostu to nie wprowadza: okno nigdy nie jest
        // pokazywane, więc `isVisible` jest fałszem i `BridgeViewLookup.kandydaci()`
        // go nie widzi — zmierzone, 0 kandydatów po dziesięciu renderach.
        let okno = oknoRobocze()
        okno.setContentSize(widok.frame.size)
        // Wygląd zerowany JAWNIE przy każdym wywołaniu. Bez tego okno z odzysku
        // niosłoby motyw poprzedniego renderu i `.systemowy` znaczyłoby „to, co było
        // ostatnio", a nie „systemowy". To jest cena recyklingu i jedyna.
        okno.appearance = wyglad.appearance
        okno.contentView = widok
        okno.layoutIfNeeded()

        if wysokosc == nil {
            let chciana = widok.fittingSize.height
            if chciana > 1 {
                widok.frame = CGRect(x: 0, y: 0, width: szerokosc, height: chciana)
                okno.setContentSize(CGSize(width: szerokosc, height: chciana))
                okno.layoutIfNeeded()
            }
        }

        widok.layoutSubtreeIfNeeded()
        defer { okno.contentView = nil }
        return try bitmapa(widok)
    }

    /// Przelewa tekst na nowo przy zmienionej szerokości.
    ///
    /// 🔴 Bez tego `?width=` zmieniał **tylko szerokość obrazka**, a wysokość zostawała
    /// ta sprzed wywołania — zmierzone 2026-08-28 na `AppBridgeDemo`: szerokości
    /// 100, 200, 300, 700 pt dały cztery różne szerokości PNG i **za każdym razem
    /// tę samą wysokość 1190 px**. Dla widoku tekstu to jest niemożliwe, jeśli tekst
    /// naprawdę przelał się przy nowej szerokości — czyli obrazek pokazywał układ
    /// przycięty albo z pustym marginesem, zamiast układu przy zamówionej szerokości.
    /// `fittingSize` sam z siebie tego nie przelicza, bo pojemnik tekstu trzyma
    /// własną szerokość niezależnie od ramki.
    /// [[Problem-render-oddaje-inny-rozmiar-niz-zamowiony]]
    static func przeliczZawijanie(_ widok: NSView, szerokosc: CGFloat) {
        guard let tekst = widok as? NSTextView, let kontener = tekst.textContainer else { return }
        kontener.containerSize = NSSize(
            width: max(szerokosc - tekst.textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        // Bez wymuszenia układu `fittingSize` odda wysokość sprzed zmiany — pojemnik
        // już wie o nowej szerokości, ale tekst jeszcze się nie przelał.
        if let layout = tekst.layoutManager {
            layout.ensureLayout(for: kontener)
            tekst.sizeToFit()
        }
    }

    /// Wygląd do wymuszenia przy renderze.
    ///
    /// Osobny typ, a nie `NSAppearance?`, bo przy opcjonalu „systemowy" i „nie ruszaj"
    /// wyglądają tak samo w miejscu wywołania — a to dwie różne rzeczy.
    public enum Wyglad: Sendable {
        case jasny
        case ciemny
        case systemowy

        var appearance: NSAppearance? {
            switch self {
            case .jasny: return NSAppearance(named: .aqua)
            case .ciemny: return NSAppearance(named: .darkAqua)
            case .systemowy: return nil
            }
        }
    }

    /// Wspólne rysowanie widoku do PNG.
    ///
    /// `display()` przed `cacheDisplay` nie jest ostrożnością na zapas: widok okna
    /// stojącego w tle bywa nieodświeżony i `cacheDisplay` skopiowałoby pustkę
    /// (ten sam mechanizm, który dawał puste zrzuty przy arkuszu zapisu).
    static func bitmapa(_ widok: NSView) throws -> Data {
        let bounds = widok.bounds

        // 🔴 Sufit powierzchni PRZED alokacją — po niej jest już za późno.
        // Bitmapa powstaje w skali ekranu, więc 20000 punktów to 40000 pikseli:
        // liczymy piksele, nie punkty. Zmierzone 2026-08-28: bez tego sprawdzenia
        // `width=20000&height=20000` brało 5,5 GB w procesie gospodarza
        // ([[Problem-brak-sufitu-na-powierzchnie-obrazka]]).
        let skala = widok.window?.backingScaleFactor ?? 2
        try BridgeLimity.sprawdzPowierzchnie(
            szerokosc: Int((bounds.width * skala).rounded()),
            wysokosc: Int((bounds.height * skala).rounded()),
            co: "Render widoku \(String(describing: type(of: widok)))"
        )

        guard bounds.width >= 1, bounds.height >= 1 else {
            throw BridgeError.failed(
                "Widok \(String(describing: type(of: widok))) ma rozmiar "
                + "\(Int(bounds.width))×\(Int(bounds.height)) — nie ma czego narysować. "
                + "Podaj szerokość (?width=), jeśli widok nie ma własnego rozmiaru."
            )
        }
        guard let rep = widok.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw BridgeError.failed("Nie udało się przygotować bitmapy dla widoku")
        }
        widok.layoutSubtreeIfNeeded()
        widok.display()
        widok.cacheDisplay(in: bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw BridgeError.failed("Nie udało się zakodować renderu do PNG")
        }
        return png
    }
}

/// Obsługa `GET /render?view=&width=&height=&appearance=`.
@MainActor
enum BridgeRenderEndpoint {

    static func render(query: [String: String]) throws -> BridgeResponse {
        let okno = try BridgeViewLookup.wybierzOkno(tytul: query["window"])
        let (widok, trafien) = try BridgeViewLookup.znajdzWidokZLiczba(query["view"], w: okno)

        let szerokosc = try liczba(query["width"], nazwa: "width")
        let wysokosc = try liczba(query["height"], nazwa: "height")

        var wyglad: NSAppearance?? = nil
        if let nazwa = query["appearance"], !nazwa.isEmpty {
            guard let wybor = BridgeAppearance.wyglad(dla: nazwa) else {
                throw BridgeError.badRequest(
                    "Nie znam wyglądu \"\(nazwa)\". Dozwolone: dark, light, system."
                )
            }
            wyglad = wybor
        }

        let png = try BridgeRenderHarness.renderPNG(
            widok: widok,
            szerokosc: szerokosc,
            wysokosc: wysokosc,
            wyglad: wyglad
        )

        // Rozmiar czytamy z gotowego PNG, a nie z widoku: ramkę przywraca `defer`,
        // więc po powrocie z renderu widok już nie wie, w czym go narysowano.
        let skala = okno.backingScaleFactor
        guard let (px, py) = rozmiarPNG(png) else {
            return .png(png)
        }
        let pt = (szer: CGFloat(px) / skala, wys: CGFloat(py) / skala)

        var naglowki = naglowkiRozmiaru(png: png, skala: skala)
        // Ten sam nagłówek co przy `/screenshot` — to PNG idzie potem do `/diff`,
        // więc czytający musi wiedzieć, w którą stronę biegnie na nim układ (poz. 21).
        naglowki[BridgeAppearance.naglowekKierunku] = BridgeAppearance.kierunekOkna(okno)

        // 🔴 Który widok naprawdę narysowano. `/render` był jedynym endpointem warstwy,
        // który tego nie mówił — `/text-attributes`, `/hit` i `/drawn-rects` oddają
        // nazwę widoku w treści, a ten oddawał samo PNG. A to właśnie jego produkt
        // idzie potem do `/diff`, więc pomyłka w `?view=` dawała wiarygodną liczbę
        // o niewłaściwym widoku. Audyt 2026-08-28, E5-P2-06.
        naglowki["x-bridge-widok"] = String(describing: type(of: widok))
        let identyfikator = widok.identifier?.rawValue ?? widok.accessibilityIdentifier()
        if !identyfikator.isEmpty {
            naglowki["x-bridge-widok-id"] = BridgeViewLookup.doNaglowka(identyfikator)
        }
        // Więcej niż jedno trafienie znaczy, że wskazanie było niejednoznaczne i wybór
        // padł na pierwszy w kolejności rysowania. Nie odmawiamy — mówimy.
        naglowki["x-bridge-trafien"] = "\(trafien)"

        // 🔴 Sedno naprawy z 2026-08-28. Przy widoku zarządzanym przez Auto Layout
        // przypisanie do `frame` ginie w przebiegu układu, więc `?width=200` oddawało
        // bitmapę w szerokości okna — z kodem 200 i bez jednego słowa ostrzeżenia.
        // Zmierzone: 200, 300 i 700 pt dawały ten sam obraz co do bajta (952×530 px).
        // Cicha rozbieżność jest tu gorsza od odmowy, bo `/diff` porównuje wtedy dwa
        // obrazki zrobione przy zupełnie innej szerokości, niż się zamawiało, a wynik
        // wygląda wiarygodnie. [[Problem-render-oddaje-inny-rozmiar-niz-zamowiony]]
        let rozjazd = rozjazdRozmiaru(zamowionaSzer: szerokosc, zamowionaWys: wysokosc, oddane: pt)
        if let rozjazd {
            naglowki["x-bridge-rozjazd"] = "tak"
            guard query["dopuscInnyRozmiar"] == "1" else {
                throw BridgeError.badRequest(
                    rozjazd
                    + " Dwie typowe przyczyny: (1) widok jest zarządzany przez Auto Layout, "
                    + "więc jego rozmiar wyznaczają ograniczenia nadwidoku, a przypisanie "
                    + "ramki ginie w przebiegu układu; (2) widok dobiera sobie rozmiar do "
                    + "treści (np. pole tekstowe rosnące w pionie), więc nie zmieści się "
                    + "w mniejszym, niż potrzebuje. Co zrobić: zamów rozmiar zgodny "
                    + "z układem, wskaż widok, który sam trzyma rozmiar (?view=), albo "
                    + "dopisz &dopuscInnyRozmiar=1, jeśli świadomie chcesz bitmapę w takim "
                    + "rozmiarze, jaki widok ma naprawdę. Rozmiar oddany jest zawsze "
                    + "w nagłówku x-bridge-rozmiar-pt."
                )
            }
        }

        return .png(png, naglowki: naglowki)
    }

    /// Opis rozjazdu albo `nil`, gdy zamówienie zostało spełnione.
    ///
    /// Tolerancja jednego punktu, bo między punktami a pikselami wchodzi
    /// zaokrąglenie przy skali ekranu — a rozjazd, o który tu chodzi, liczy się
    /// w setkach punktów, nie w jednym.
    /// `nonisolated`, bo to czysta arytmetyka na dwóch liczbach — nie dotyka ani
    /// widoku, ani niczego z AppKit. Bez tego przypięcie do głównego aktora
    /// dziedziczy się z typu i zmusza każdego wołającego (w tym test) do skoku
    /// na główny wątek po nic.
    nonisolated static func rozjazdRozmiaru(
        zamowionaSzer: CGFloat?,
        zamowionaWys: CGFloat?,
        oddane: (szer: CGFloat, wys: CGFloat)
    ) -> String? {
        var powody: [String] = []
        if let z = zamowionaSzer, abs(z - oddane.szer) > 1 {
            powody.append("zamówiono szerokość \(Int(z)) pt, a widok oddał \(Int(oddane.szer.rounded())) pt")
        }
        if let z = zamowionaWys, abs(z - oddane.wys) > 1 {
            powody.append("zamówiono wysokość \(Int(z)) pt, a widok oddał \(Int(oddane.wys.rounded())) pt")
        }
        guard !powody.isEmpty else { return nil }
        return "Render nie ma zamówionego rozmiaru: " + powody.joined(separator: "; ") + "."
    }

    /// Trzy nagłówki mówiące, **w czym** oddany jest obrazek.
    ///
    /// 🔴 Wspólne dla `/render` i `/screenshot` od 2026-08-28, wariant (b)
    /// z [[Problem-hit-czyta-punkty-a-zrzut-oddaje-piksele]]. Do tego dnia miał je
    /// wyłącznie `/render`, a `/screenshot` oddawał gołe PNG — więc jedyną informacją
    /// o jednostce był komentarz w kodzie, i to nieprawdziwy: bitmapa powstaje w skali
    /// ekranu (2×), a `/hit` czyta punkty. Kto brał współrzędną wprost z podglądu zrzutu,
    /// dostawał dla wewnętrznej ćwiartki obrazka odpowiedź o zupełnie innym miejscu.
    ///
    /// Oddajemy oba układy i skalę, żeby przeliczenie było odczytem, a nie domysłem.
    nonisolated static func naglowkiRozmiaru(png: Data, skala: CGFloat) -> [String: String] {
        guard let (px, py) = rozmiarPNG(png), skala > 0 else { return [:] }
        let szerPt = Int((CGFloat(px) / skala).rounded())
        let wysPt = Int((CGFloat(py) / skala).rounded())
        return [
            "x-bridge-rozmiar-px": "\(px)x\(py)",
            "x-bridge-rozmiar-pt": "\(szerPt)x\(wysPt)",
            "x-bridge-skala": "\(Int(skala.rounded()))",
            // Jedyny nagłówek, który mówi wprost, czego chcą endpointy współrzędnych.
            // Bez niego „obrazek ma 520×448" czyta się jak rozmiar pliku PNG.
            "x-bridge-jednostka-wspolrzednych": "pt",
        ]
    }

    /// Rozmiar PNG odczytany z nagłówka IHDR — bez dekodowania obrazka.
    ///
    /// Dekodowanie tylko po to, żeby poznać wymiary, byłoby drugą alokacją tej samej
    /// wielkości co render; IHDR stoi zawsze w tym samym miejscu, zaraz po sygnaturze.
    /// `nonisolated` z tego samego powodu co `rozjazdRozmiaru` — czyta osiem bajtów
    /// nagłówka, nic więcej.
    nonisolated static func rozmiarPNG(_ dane: Data) -> (Int, Int)? {
        let sygnatura: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard dane.count >= 24, Array(dane.prefix(8)) == sygnatura else { return nil }
        let bajty = Array(dane[dane.startIndex.advanced(by: 16)..<dane.startIndex.advanced(by: 24)])
        let szer = bajty[0..<4].reduce(0) { $0 << 8 | Int($1) }
        let wys = bajty[4..<8].reduce(0) { $0 << 8 | Int($1) }
        guard szer > 0, wys > 0 else { return nil }
        return (szer, wys)
    }

    static func liczba(_ tekst: String?, nazwa: String) throws -> CGFloat? {
        guard let tekst, !tekst.isEmpty else { return nil }
        guard let wartosc = Double(tekst), wartosc > 0, wartosc <= 20_000 else {
            throw BridgeError.badRequest(
                "Parametr \(nazwa)=\(tekst) nie jest liczbą punktów z zakresu 1…20000"
            )
        }
        return CGFloat(wartosc)
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeRoute.swift
// ────────────────────────────────────────────────────────────────────────


/// Żądanie, które przyszło z zewnątrz (od Claude Code przez serwer MCP).
nonisolated public struct BridgeRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    /// Nagłówki żądania, **nazwy zawsze małymi literami** (`content-type`, nie
    /// `Content-Type`) — parser normalizuje je przy wczytywaniu, więc aplikacja
    /// nie musi zgadywać, jak klient je zapisał.
    ///
    /// Do 2026-08-10 tego pola nie było: parser budował słownik nagłówków, czytał
    /// z niego wyłącznie `content-length` i wyrzucał resztę. Skutek był większy niż
    /// brak wygody — aplikacja **fizycznie nie mogła** sprawdzić, kto ją woła,
    /// nawet gdyby chciała. Audyt 2026-08-10, E3a-P0-01.
    ///
    /// Sam most odsiewa żądania z przeglądarki jeszcze przed routingiem
    /// (`BridgeServer.zrodloZabronione`), więc handler dostaje to pole do decyzji
    /// **własnych**, a nie do powtarzania tamtego sita.
    public let headers: [String: String]
    public let body: Data

    /// - Parameter headers: nazwy nagłówków małymi literami. Domyślnie pusty słownik,
    ///   żeby testy i ręcznie budowane żądania nie musiały go podawać.
    public init(
        method: String,
        path: String,
        query: [String: String],
        headers: [String: String] = [:],
        body: Data
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Ciało żądania odczytane jako słownik JSON. Pusty słownik, gdy ciała nie ma.
    ///
    /// Serializacja jest opakowana świadomie. `JSONSerialization` przy niepoprawnej
    /// **składni** rzuca własny błąd Foundation, zanim wykona się `guard` niżej —
    /// a ten błąd nie jest `BridgeError`, więc łapał go ogólny `catch` w serwerze
    /// i odsyłał **500 z angielskim komunikatem systemowym**. Zepsute ciało żądania
    /// to wina tego, kto je wysłał, czyli 400; komunikat ma być po polsku jak reszta
    /// mostu. Znalezione 2026-08-09 przy ostrzale innym gospodarzu.
    public func jsonBody() throws -> [String: Any] {
        guard !body.isEmpty else { return [:] }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: body)
        } catch {
            throw BridgeError.badRequest("Ciało żądania nie jest poprawnym JSON-em")
        }

        guard let slownik = object as? [String: Any] else {
            throw BridgeError.badRequest("Ciało żądania nie jest obiektem JSON")
        }
        return slownik
    }

    /// Ciało żądania zdekodowane do własnego typu `Decodable`.
    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }
}

/// Odpowiedź odsyłana do Claude Code.
nonisolated public struct BridgeResponse: Sendable {
    public let status: Int
    public let contentType: String
    public let body: Data

    /// Wypełnione tylko wtedy, gdy `.json(...)` dostał dane niedające się zapisać
    /// w JSON. Sama odpowiedź nie wie, kto ją zbudował, więc nazwę endpointu
    /// dokłada do logu serwer — patrz `BridgeServer.handle`.
    private(set) var serializationFailure: String?

    /// Czym było to żądanie, w słowach, których ścieżka nie niesie — nazwa akcji
    /// i zmienione pola sondy. Serwer przepisuje to do historii (`GET /historia`).
    ///
    /// 🔴 Jedzie **na odpowiedzi**, a nie przez stan globalny licznika ruchu. Most
    /// obsługuje do szesnastu połączeń naraz i odczyt w tle potrafi skończyć się
    /// w środku akcji — „ostatni ślad" trzymany globalnie trafiłby wtedy do cudzego
    /// wpisu. Tu ślad i wpis pochodzą z tego samego żądania z definicji.
    ///
    /// ⚠️ **Zna go tylko droga, która oddała odpowiedź.** Odmowa rzucona wyjątkiem
    /// (`BridgeError` z warstwy akcji) idzie do historii z samą ścieżką i kodem —
    /// wystarcza, bo odmowy warstwy akcji lecą **przed** wykonaniem i stan gospodarza
    /// jest wtedy nietknięty.
    private(set) var slad: BridgeActivitySlad?

    /// Ta sama odpowiedź, z dopisanym śladem dla historii.
    ///
    /// Osobna metoda, a nie parametr `json(_:)`: ślad ma dokładać **handler, który wie,
    /// co zrobił**, i tylko on. Gdyby wszedł do fabryki, każdy endpoint dostałby pole,
    /// którego nie ma czym wypełnić.
    public func zeSladem(_ slad: BridgeActivitySlad?) -> BridgeResponse {
        var kopia = self
        kopia.slad = slad
        return kopia
    }

    /// Dodatkowe nagłówki odpowiedzi, nazwy małymi literami.
    ///
    /// Dołożone 2026-08-28 dla `/render`, który oddaje goły PNG i **nie miał jak
    /// powiedzieć, jakiego rozmiaru bitmapę naprawdę zrobił** — a przy widoku
    /// w Auto Layout potrafi to być inny rozmiar niż zamówiony
    /// ([[Problem-render-oddaje-inny-rozmiar-niz-zamowiony]]).
    ///
    /// Czyszczone tak samo jak `contentType`: wartość z `\r\n` w środku pozwalałaby
    /// dopisać dowolne nagłówki i własne ciało odpowiedzi (audyt 2026-08-10, E2-P3-04).
    /// Nagłówki, które most składa sam (`content-type`, `content-length`,
    /// `connection`), są odrzucane — inaczej dałoby się je zdublować.
    public let headers: [String: String]

    private static let naglowkiZastrzezone: Set<String> = [
        "content-type", "content-length", "connection",
    ]

    public init(
        status: Int = 200,
        contentType: String,
        body: Data,
        headers: [String: String] = [:]
    ) {
        self.status = status
        self.contentType = Self.bezpiecznyContentType(contentType)
        self.body = body
        self.headers = Self.bezpieczneNaglowki(headers)
    }

    private static func bezpieczneNaglowki(_ raw: [String: String]) -> [String: String] {
        var czyste: [String: String] = [:]
        for (nazwa, wartosc) in raw {
            let n = nazwa.lowercased().filter { !$0.isNewline && $0 != "\r" && $0 != ":" }
                .trimmingCharacters(in: .whitespaces)
            let w = wartosc.filter { !$0.isNewline && $0 != "\r" }
                .trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, !w.isEmpty, !naglowkiZastrzezone.contains(n) else { continue }
            czyste[n] = w
        }
        return czyste
    }

    /// Wycina z typu zawartości znaki, którymi da się dopisać własne nagłówki.
    ///
    /// Ten init jest **publiczny**, a `contentType` trafia wprost do nagłówków
    /// odpowiedzi (`BridgeServer.send`). Napis z `\r\n` w środku wstrzykiwał tam
    /// dowolne nagłówki, a przy dwóch `\r\n` — również własne ciało odpowiedzi.
    /// Trzy fabryki pakietu (`json`, `png`, `text`) podają stałe, więc same z siebie
    /// są bezpieczne; droga otwierała się dopiero wtedy, gdy aplikacja zbudowała
    /// `contentType` z danych żądania. Audyt 2026-08-10, E2-P3-04.
    ///
    /// Czyścimy zamiast rzucać błędem, bo init nie może rzucać, a cicha odmowa
    /// zbudowania odpowiedzi byłaby gorsza od poprawnego nagłówka.
    private static func bezpiecznyContentType(_ raw: String) -> String {
        let czysty = raw.filter { !$0.isNewline && $0 != "\r" }
            .trimmingCharacters(in: .whitespaces)
        return czysty.isEmpty ? "application/octet-stream" : czysty
    }

    /// Odpowiedź JSON. Przyjmuje słownik lub tablicę.
    ///
    /// Obiekt jest sprawdzany **przed** serializacją, bo `try?` w tym miejscu
    /// niczego nie chroni: przy niedozwolonej wartości (`NaN`, nieskończoność,
    /// `Date`, `URL`) `JSONSerialization` nie zwraca błędu Swift, tylko rzuca
    /// wyjątek Objective-C. Taki wyjątek przelatuje przez `try?`, jakby go tam
    /// nie było, i kończy proces całej aplikacji-gospodarza przez `abort()` —
    /// z głównego wątku, bo handlery domyślnie tam lecą. Audyt 2026-08-02, P0-02.
    public static func json(_ object: Any, status: Int = 200) -> BridgeResponse {
        guard JSONSerialization.isValidJSONObject(object) else {
            // Szczegółowa diagnostyka istnieje wyłącznie w DEBUG, bo `JSONProblem`
            // od 2026-08-29 stoi pod tą samą dyrektywą co reszta implementacji kitu.
            // W RELEASE ta gałąź jest nieosiągalna od strony mostu — nikt nie rejestruje
            // handlerów, więc nikt nie zwraca odpowiedzi — a gospodarz wołający
            // `BridgeResponse.json` wprost dostaje zdanie ogólne zamiast wskazania pola.
            // Cena świadoma: w zamian ani jedna funkcja implementacji nie jedzie
            // do binarki wydania. Audyt 2026-08-29, E5N-P1-01.
            #if DEBUG
            let powod = JSONProblem.opisz(object)
            #else
            let powod = "gdzieś w danych siedzi wartość niedozwolona w JSON"
            #endif
            let komunikat = "Endpoint zwrócił dane, których nie da się zapisać w JSON: \(powod)"
            // Ten słownik jest poprawny z definicji — jeden klucz, jeden napis.
            let data = (try? JSONSerialization.data(
                withJSONObject: ["error": komunikat],
                options: [.sortedKeys]
            )) ?? Data("{\"error\":\"Odpowiedź zawierała wartość niedozwoloną w JSON\"}".utf8)

            var response = BridgeResponse(status: 500, contentType: "application/json", body: data)
            response.serializationFailure = powod
            return response
        }

        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        return BridgeResponse(status: status, contentType: "application/json", body: data)
    }

    /// Odpowiedź z obrazkiem PNG (używane przez `/screenshot` i `/render`).
    ///
    /// - Parameter naglowki: dodatkowe nagłówki — `/render` podaje tędy rozmiar
    ///   bitmapy, bo w samym PNG nie ma gdzie napisać, czy zamówienie zostało
    ///   spełnione.
    public static func png(_ data: Data, naglowki: [String: String] = [:]) -> BridgeResponse {
        BridgeResponse(status: 200, contentType: "image/png", body: data, headers: naglowki)
    }

    public static func text(_ string: String, status: Int = 200) -> BridgeResponse {
        BridgeResponse(status: status, contentType: "text/plain; charset=utf-8", body: Data(string.utf8))
    }
}

/// Handler dotykający interfejsu i stanu aplikacji. Izolowany do głównego aktora,
/// więc kompilator sam pilnuje, że sięga po te rzeczy z właściwego miejsca.
public typealias BridgeMainActorHandler = @MainActor @Sendable (BridgeRequest) throws -> BridgeResponse

/// Handler akcji — jedyny `async` w kicie. Powód przy `BridgeExecution.akcjaNaGlownymAktorze`.
public typealias BridgeAsyncMainActorHandler =
    @MainActor @Sendable (BridgeRequest) async throws -> BridgeResponse

/// Handler liczący w tle. **Nie ma prawa dotykać interfejsu ani stanu aplikacji** —
/// i nie jest to prośba: sięgnięcie po cokolwiek izolowane do głównego aktora
/// nie skompiluje się w tym miejscu.
public typealias BridgeBackgroundHandler = @Sendable (BridgeRequest) throws -> BridgeResponse

/// Gdzie wykonuje się handler.
///
/// Dawniej decydował o tym `Bool` przy rejestracji (`runsOnMainThread`), którego
/// nikt nie sprawdzał — ani kompilator, ani test, ani sam most. Ustawienie go na
/// `false` przy handlerze sięgającym po stan aplikacji przenosiło dostęp do
/// interfejsu na kolejkę sieciową i kończyło się awarią przy zbiegu czasów,
/// trudną do powiązania z przyczyną. Audyt 2026-08-02, P1-01.
///
/// Teraz wybór jest wyrażony w typie handlera, więc zły wybór **nie kompiluje się**.
nonisolated public enum BridgeExecution: Sendable {
    case onMainActor(BridgeMainActorHandler)
    case inBackground(BridgeBackgroundHandler)
    /// Endpoint, który **zmienia** interfejs i musi poczekać na skutek.
    ///
    /// 🔴 Trzeci rodzaj, a nie parametr przy pierwszym, bo różnica jest w typie:
    /// handler jest `async`. Warstwa akcji po wykonaniu czeka, aż sonda gospodarza
    /// przestanie się zmieniać — a to `await` w zadaniu, w którym most już jest.
    /// Gdyby robić to synchronicznie, jedyną drogą byłaby zagnieżdżona pętla główna,
    /// która obsłużyłaby w międzyczasie inne żądania i pozwoliła jednej akcji
    /// przerwać drugą. [[Projekt-API-warstwy-klikania]], sekcja 3.
    case akcjaNaGlownymAktorze(BridgeAsyncMainActorHandler)

    /// Krótki opis dla `/routes` — żeby po drugiej stronie mostu było widać,
    /// który endpoint dotyka interfejsu.
    ///
    /// 🔴 Ciało pod `#if DEBUG`, choć typ jest w `PUSTE_API` i **nazwa** ma zostać
    /// w wydaniu. „Puste API" znaczy nazwa bez ciała, a te trzy zdania są ciałem —
    /// i to takim, które opisuje most po polsku w binarce rozdawanej ludziom.
    /// Zmierzone 2026-09-02 na binarce RELEASE TestRoomu: `w tle (nie dotyka
    /// interfejsu)` **przeżywało wydanie**. Dwa pozostałe też tam były; `strings`
    /// pokazał jeden, bo tnie ciągi na polskich znakach.
    /// Pozycja 14 kolejki — i to jest dokładnie ten wyciek, którego brakującego
    /// alarmu ta pozycja dotyczy.
    public var opis: String {
        #if DEBUG
        switch self {
        case .onMainActor: return "główny aktor (dotyka interfejsu)"
        case .inBackground: return "w tle (nie dotyka interfejsu)"
        case .akcjaNaGlownymAktorze: return "główny aktor, AKCJA (zmienia interfejs)"
        }
        #else
        return ""
        #endif
    }

    /// Czy ta trasa **zmienia stan gospodarza**, a nie tylko go czyta.
    ///
    /// 🔴 Powód istnienia (audyt warstwy klikania 2026-09-02, E1-P2-02): sufit czasu
    /// znaczy co innego dla odczytu i dla zapisu. Wyrzucony wynik ODCZYTU nic nie
    /// kosztuje — pytanie można powtórzyć. Wyrzucony wynik ZAPISU zostawia klienta
    /// z odpowiedzią „nie wiadomo", podczas gdy stan aplikacji jest już zmieniony,
    /// a najbliższy odruch po takiej odpowiedzi to ponowienie.
    ///
    /// Dziś pisze dokładnie jeden rodzaj wykonania. Gdy dojdzie drugi, ma trafić tutaj,
    /// a nie do warunku w `BridgeServer` — inaczej reguła rozjedzie się o jedno miejsce,
    /// czyli powtórzy najczęstszy kształt znalezisk tego projektu.
    var czyPisze: Bool {
        switch self {
        case .akcjaNaGlownymAktorze: return true
        case .onMainActor, .inBackground: return false
        }
    }
}

/// Pojedynczy endpoint udostępniony przez aplikację.
nonisolated public struct BridgeRoute: Sendable {
    public let method: String
    public let path: String
    public let description: String
    public let execution: BridgeExecution

    /// Endpoint dotykający interfejsu albo stanu aplikacji — czyli domyślny wybór
    /// dla wszystkiego, co odczytuje dokument, scenę, warstwy czy okna.
    public static func onMainActor(
        method: String = "GET",
        path: String,
        description: String = "",
        handler: @escaping BridgeMainActorHandler
    ) -> BridgeRoute {
        BridgeRoute(method: method, path: path, description: description,
                    execution: .onMainActor(handler))
    }

    /// Endpoint liczący w tle — wolno mu tylko to, co nie dotyka aplikacji.
    public static func inBackground(
        method: String = "GET",
        path: String,
        description: String = "",
        handler: @escaping BridgeBackgroundHandler
    ) -> BridgeRoute {
        BridgeRoute(method: method, path: path, description: description,
                    execution: .inBackground(handler))
    }

    public init(
        method: String = "GET",
        path: String,
        description: String = "",
        execution: BridgeExecution
    ) {
        self.method = method.uppercased()
        self.path = path.hasPrefix("/") ? path : "/" + path
        self.description = description
        self.execution = execution
    }
}

/// Wspólne sufity dla endpointów pracujących na obrazkach.
///
/// Powstało 2026-08-28 z audytu warstwy wyglądu
/// ([[Problem-brak-sufitu-na-powierzchnie-obrazka]]). Zmierzone tam: `/render`
/// przy `width=20000&height=20000` brał **5,5 GB** w procesie gospodarza i 16 s
/// jego głównego wątku, a `/diff` na dwóch jednolitych PNG-ach 12000 × 12000
/// (plik 567 kB, ciało żądania 1,5 MB przy limicie 8 MiB) — **4,4 GB**, z czego
/// 3,9 GB nie wracało.
///
/// 🔴 Sufit stoi na **powierzchni**, a nie na wymiarach z osobna, bo to iloczyn
/// kosztuje pamięć. Limit ciała żądania (8 MiB) tego nie zastępuje: mierzy plik,
/// a jednolity PNG kompresuje się do niczego — na tym stoi bomba dekompresyjna.
nonisolated public enum BridgeLimity {

    /// Najwyższa dopuszczalna liczba pikseli jednej bitmapy.
    ///
    /// 40 Mpx to ok. 6300 × 6300, czyli z zapasem ponad zrzut ekranu 6K w skali 2×
    /// (~24 Mpx) — a zamyka wariant, w którym jedno żądanie bierze gigabajty.
    /// Liczba dobrana 2026-08-28; jeśli okaże się ciasna przy prawdziwym monitorze,
    /// zmienia się ją tutaj i nigdzie indziej.
    public static let maksPikseli = 40_000_000

    /// Sufit na pole `wartosc` w `/hit`, **w jednostkach UTF-16**.
    ///
    /// `accessibilityValue` pola tekstowego to CAŁA jego treść — zmierzone na demie
    /// 2026-08-29: jedno `/hit` w akapicie próbki wysypywało 1,4 kB tekstu, który ma
    /// już swój endpoint (`/text-attributes`). Odpowiedź sondy „co jest pod punktem"
    /// ma być odpowiedzią, a nie zrzutem dokumentu.
    ///
    /// 🔴 **UTF-16, nie grafemy** (poz. 19, 2026-09-02). Do tego dnia sufit ciął przez
    /// `prefix(200)`, czyli po grafemach Swifta: 200 grafemów to 200 B przy ASCII,
    /// ale **5 600 B** przy fladze z sekwencją tagów. Sufit, który przy jednej treści
    /// przepuszcza dwadzieścia osiem razy więcej niż przy drugiej, nie jest sufitem.
    /// Ta sama rodzina usterki co `maksZnakowWRunie` (2026-08-28).
    public static let maksZnakowWartosci = 200

    /// Najwyższy dopuszczalny `?limit=` w `/text-attributes`.
    ///
    /// 🔴 Do 2026-09-02 sufit miał **tylko podłogę** (`max(1, …)`) i nic w drugą stronę:
    /// `limit=2000000000` wracało z kodem **200**. Waga odpowiedzi to zmierzone ok. 449 B
    /// na run, więc milion runów to rzędu 450 MB budowane w pamięci gospodarza pod
    /// odpowiedź, której i tak nikt nie odbierze.
    ///
    /// **2000 to decyzja [U] z 2026-09-02**, dobrana tuż pod sufitem klienta MCP:
    /// 1 MiB ÷ 449 B ≈ **2335 runów**. Powyżej tej liczby odpowiedź zostaje odrzucona
    /// po drugiej stronie, więc most odmawia zamiast budować coś, czego nikt nie odczyta.
    /// Liczby nie dobiera agent — jeśli okaże się ciasna, zmienia ją [U] i tutaj.
    public static let maksRunow = 2000

    /// Ile najdłużej most czeka, aż sonda akcji przestanie się zmieniać.
    ///
    /// 🔴 **Liczbę dobrał Claude, nie [U]** — tak samo jak sufit 40 Mpx i sufit 90 s,
    /// i tak samo czeka na rozstrzygnięcie (audyt warstwy klikania 2026-09-02,
    /// E1-P2-04). Agent wartości nie dobiera; jeśli okaże się zła, zmienia ją [U]
    /// i **tutaj**, w jednej linijce.
    ///
    /// Wyraźnie poniżej sufitu pracy handlera (90 s) — inaczej dwa sufity zaczęłyby
    /// się ścigać i odmowa mówiłaby o niewłaściwym.
    ///
    /// Mieszka w `BridgeLimity`, a nie przy warstwie akcji, od 2026-09-02: sufit
    /// czasu żądania sprawdza go **przed** wywołaniem handlera, a tamten kod nie
    /// stoi na głównym aktorze, więc nie sięgnąłby do stałej izolowanej `@MainActor`.
    /// Przy okazji wszystkie sufity projektu są znowu w jednym miejscu.
    public static let sufitUstabilizowaniaMs = 1_500

    /// Co ile most próbkuje sondę w pętli ustabilizowania.
    public static let krokProbkowaniaMs = 30

    /// Rzuca `BridgeError`, gdy bitmapa nie mieści się w suficie. Wołane **przed**
    /// alokacją — po niej byłoby już za późno.
    static func sprawdzPowierzchnie(szerokosc: Int, wysokosc: Int, co: String) throws {
        let pikseli = szerokosc * wysokosc
        guard pikseli > 0 else { return }
        guard pikseli <= maksPikseli else {
            let mpx = Double(pikseli) / 1_000_000
            let limit = Double(maksPikseli) / 1_000_000
            throw BridgeError.badRequest(
                "\(co): \(szerokosc)×\(wysokosc) to \(String(format: "%.1f", mpx)) Mpx, "
                + "a sufit wynosi \(String(format: "%.0f", limit)) Mpx. "
                + "Taka bitmapa zajęłaby w pamięci aplikacji rzędu "
                + "\(String(format: "%.1f", Double(pikseli) * 21 / 1_000_000_000)) GB. "
                + "Zmniejsz rozmiar albo porównuj wycinek."
            )
        }
    }
}

nonisolated public enum BridgeError: LocalizedError, Sendable {
    case badRequest(String)
    case notFound(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .badRequest(let message): return message
        case .notFound(let message): return message
        case .failed(let message): return message
        }
    }

    var httpStatus: Int {
        switch self {
        case .badRequest: return 400
        case .notFound: return 404
        case .failed: return 500
        }
    }
}

// ────────────────────────────────────────────────────────────────────────
// BridgeScreenshot.swift
// ────────────────────────────────────────────────────────────────────────


// `#if DEBUG` dołożone 2026-08-28 razem z wariantem (a) dla `BridgeRenderHarness`
// ([[Problem-harness-renderujacy-zostaje-w-wydaniu]]). Nie jest to osobna decyzja,
// tylko jej konsekwencja: `capturePNG` woła `BridgeRenderHarness.bitmapa`, a to
// jedyne wywołanie harnessu spoza obszaru `#if DEBUG` — bez tego RELEASE przestaje
// się kompilować.
//
// Nic to nie zmienia w binarce: `BridgeScreenshot` jest `internal`, wołany wyłącznie
// z `registerBuiltInRoutes` (też pod `#if DEBUG`), i znikał z RELEASE już wcześniej
// — zmierzone TestRoomem: `capturePNG` 1 w DEBUG, 0 w RELEASE. Zmienia się tylko to,
// że teraz nie jest w RELEASE **kompilowany**, zamiast być kompilowanym i wyrzucanym.
// Gałąź `#else` niżej zostaje i nadal daje pusty typ o tej samej nazwie.
#if DEBUG && canImport(AppKit)

/// Zrzut ekranu **własnego** okna aplikacji.
///
/// Świadomie nie używamy `CGWindowListCreateImage` ani ScreenCaptureKit:
/// tamte wymagają od użytkownika zgody „Nagrywanie ekranu" w Ustawieniach
/// systemowych. Rysowanie własnego okna do bitmapy działa od razu, bez
/// żadnych uprawnień — a most i tak potrzebuje tylko okna tej aplikacji.
///
/// Wybór okna mieszka od 2026-08-27 w `BridgeViewLookup` — dzieli go z `/render`,
/// `/text-attributes`, `/hit` i `/drawn-rects`, bo trzy kopie tej samej reguły
/// rozjeżdżają się po pierwszej poprawce.
nonisolated enum BridgeScreenshot {

    /// Poniżej tego rozmiaru „okno" prawie na pewno nie jest interfejsem, tylko
    /// czymś technicznym, co przecisnęło się przez filtry.
    ///
    /// `@MainActor`, bo próg mieszka razem z resztą wyszukiwania okien — a to całe
    /// jest izolowane do głównego aktora.
    @MainActor
    static var minimalnyBokOkna: CGFloat { BridgeViewLookup.minimalnyBokOkna }

    /// Izolowane do głównego aktora, bo sięga po `NSApplication` i rysuje widoki.
    ///
    /// Dawniej gwarancja „wywoływane z głównego wątku" wisiała **wyłącznie w tym
    /// komentarzu** i trzymała się na wartości `Bool` podanej przy rejestracji trasy.
    /// Teraz pilnuje jej kompilator. Audyt 2026-08-02, P1-01.
    ///
    /// - Parameters:
    ///   - windowTitle: fragment tytułu **albo nazwy klasy** okna. 🔴 Arkusz wskazuje
    ///     się klasą (`SheetPresentation`), bo arkusze mają tytuł pusty.
    ///   - scrollToLine: numer wiersza (od 1), do którego przewinąć pole tekstowe
    ///     przed zrzutem. Bez tego trafienie w konkretny blok tekstu to strzelanie
    ///     ułamkiem dokumentu — 2026-08-27 kosztowało trzy zrzuty (0,62 · 0,80 · 0,85).
    ///   - find: fragment tekstu, do którego przewinąć. Gdy nie ma go w dokumencie,
    ///     zrzut **nie powstaje** — zamiast obrazka „z czymś innym" wraca 404.
    @MainActor
    static func capturePNG(
        windowTitle: String?,
        scrollToLine: Int? = nil,
        find: String? = nil,
        widok wskaznikWidoku: String? = nil
    ) throws -> Data {
        try zrzutZOpisem(
            windowTitle: windowTitle,
            scrollToLine: scrollToLine,
            find: find,
            widok: wskaznikWidoku
        ).png
    }

    /// Zrzut **razem z opisem, w czym go oddano** — do złożenia odpowiedzi HTTP.
    ///
    /// 🔴 Osobna funkcja, bo skalę zna wyłącznie okno, a `capturePNG` je wybiera
    /// wewnątrz. Wybieranie okna drugi raz po to, żeby odczytać `backingScaleFactor`,
    /// mogłoby trafić w inne okno niż to, które właśnie narysowano.
    /// [[Problem-hit-czyta-punkty-a-zrzut-oddaje-piksele]], naprawa wariantem (b).
    @MainActor
    static func zrzutZOpisem(
        windowTitle: String?,
        scrollToLine: Int? = nil,
        find: String? = nil,
        widok wskaznikWidoku: String? = nil
    ) throws -> (png: Data, naglowki: [String: String]) {
        let window = try BridgeViewLookup.wybierzOkno(tytul: windowTitle)

        if scrollToLine != nil || (find?.isEmpty == false) {
            try przewin(
                w: window,
                widok: wskaznikWidoku,
                doWiersza: scrollToLine,
                szukajac: find
            )
        }

        // Drugie sito, niezależne od nazw klas AppKit. Jeśli pierwsze (nazwa klasy,
        // w `BridgeViewLookup`) przestanie działać po aktualizacji systemu, tu wyjdzie
        // czytelny błąd zamiast obrazka 32×32 udającego zrzut interfejsu.
        let rozmiar = window.frame.size
        guard rozmiar.width >= minimalnyBokOkna, rozmiar.height >= minimalnyBokOkna else {
            let (widoczne, kandydaci) = BridgeViewLookup.kandydaci()
            throw BridgeError.failed(
                "Wybrane okno ma \(Int(rozmiar.width))×\(Int(rozmiar.height)) punktów — "
                + "to za mało, żeby był to interfejs aplikacji. "
                + "Prawdopodobnie zrzut trafił na okno techniczne (ikonka paska menu, popover). "
                + "Widocznych okien: \(widoczne.count), odsianych po nazwie klasy: "
                + "\(widoczne.count - kandydaci.count). "
                + "Wskaż okno po tytule: /screenshot?window=fragment-tytułu"
            )
        }

        // Celowo bierzemy nadrzędny widok ramki, a nie samo `contentView`.
        //
        // `contentView` to wyłącznie wnętrze okna — bez tła okna i bez belki
        // tytułowej. W trybie ciemnym daje to biały tekst na białym tle, czyli
        // obraz wyglądający na pusty. Widok ramki zawiera tło i belkę, więc
        // zrzut wygląda tak, jak okno naprawdę wygląda na ekranie.
        let view = try BridgeViewLookup.widokRamki(window)
        let png = try BridgeRenderHarness.bitmapa(view)
        var naglowki = BridgeRenderEndpoint.naglowkiRozmiaru(png: png, skala: window.backingScaleFactor)
        // Odpowiedzią jest obrazek, więc kierunek układu jedzie nagłówkiem (poz. 21).
        naglowki[BridgeAppearance.naglowekKierunku] = BridgeAppearance.kierunekOkna(window)
        return (png, naglowki)
    }

    // MARK: - Przewijanie przed zrzutem

    /// Przewija pole tekstowe okna do wskazanego wiersza albo do pierwszego trafienia
    /// szukanego tekstu.
    ///
    /// Zaznaczenia **nie ruszamy** — przewinięcie jest odwracalne i niewidoczne
    /// w treści, a przestawione zaznaczenie zostałoby [U] na ekranie po pomiarze.
    @MainActor
    static func przewin(
        w okno: NSWindow,
        widok wskaznik: String?,
        doWiersza: Int?,
        szukajac: String?
    ) throws {
        let textView = try BridgeViewLookup.znajdzTextView(wskaznik, w: okno)
        let tekst = textView.string as NSString

        var zakres: NSRange
        if let szukajac, !szukajac.isEmpty {
            let trafienie = tekst.range(of: szukajac, options: [.caseInsensitive])
            guard trafienie.location != NSNotFound else {
                throw BridgeError.notFound(
                    "Nie znalazłem \"\(szukajac)\" w tym polu tekstowym (\(tekst.length) znaków). "
                    + "Zrzut nie powstał — obrazek z innego miejsca dokumentu byłby gorszy "
                    + "niż brak obrazka."
                )
            }
            zakres = trafienie
        } else if let doWiersza {
            guard doWiersza >= 1 else {
                throw BridgeError.badRequest("scrollToLine liczy się od 1, dostałem \(doWiersza)")
            }
            guard let poczatek = poczatekWiersza(tekst, numer: doWiersza) else {
                throw BridgeError.notFound(
                    "Dokument ma mniej niż \(doWiersza) wierszy (\(liczbaWierszy(tekst)) łącznie)"
                )
            }
            zakres = NSRange(location: poczatek, length: 0)
        } else {
            return
        }

        textView.scrollRangeToVisible(zakres)
        // Przewinięcie idzie przez warstwę układu, która przelicza się leniwie —
        // bez wymuszenia zrzut łapałby stan sprzed przewinięcia.
        textView.layoutSubtreeIfNeeded()
        textView.enclosingScrollView?.contentView.layoutSubtreeIfNeeded()
        textView.enclosingScrollView?.reflectScrolledClipView(
            textView.enclosingScrollView?.contentView ?? NSClipView()
        )
    }

    /// Indeks pierwszego znaku wiersza o podanym numerze (licząc od 1) albo `nil`,
    /// gdy dokument ma mniej wierszy.
    static func poczatekWiersza(_ tekst: NSString, numer: Int) -> Int? {
        guard numer >= 1 else { return nil }
        if numer == 1 { return 0 }

        var wiersz = 1
        var indeks = 0
        while indeks < tekst.length {
            if tekst.character(at: indeks) == 10 {  // "\n"
                wiersz += 1
                if wiersz == numer { return indeks + 1 }
            }
            indeks += 1
        }
        return nil
    }

    static func liczbaWierszy(_ tekst: NSString) -> Int {
        var wiersze = 1
        for indeks in 0..<tekst.length where tekst.character(at: indeks) == 10 {
            wiersze += 1
            _ = indeks
        }
        return wiersze
    }
}

#else

nonisolated enum BridgeScreenshot {
    @MainActor
    static func capturePNG(
        windowTitle: String?,
        scrollToLine: Int? = nil,
        find: String? = nil,
        widok: String? = nil
    ) throws -> Data {
        throw BridgeError.failed("Zrzuty ekranu są dostępne tylko na macOS")
    }

    @MainActor
    static func zrzutZOpisem(
        windowTitle: String?,
        scrollToLine: Int? = nil,
        find: String? = nil,
        widok: String? = nil
    ) throws -> (png: Data, naglowki: [String: String]) {
        throw BridgeError.failed("Zrzuty ekranu są dostępne tylko na macOS")
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeServer.swift
// ────────────────────────────────────────────────────────────────────────


/// Lokalny serwer HTTP wbudowany w aplikację.
///
/// **W buildzie RELEASE nie robi nic.** Cała implementacja jest zamknięta
/// w `#if DEBUG`, więc do wersji wysyłanej testerom czy na App Store nie
/// trafia żaden kod nasłuchujący. Nasłuch zawsze i wyłącznie na 127.0.0.1,
/// czyli tylko z tego samego komputera.
///
/// Cały zmienny stan siedzi za `stateLock` albo `connectionsLock`, stąd
/// `@unchecked Sendable` — patrz uwaga przy `BridgeRegistry`.
nonisolated public final class BridgeServer: @unchecked Sendable {

    public static let shared = BridgeServer()

    private let stateLock = NSLock()
    private var _activePort: UInt16 = 0

    /// Port, na którym most **faktycznie** nasłuchuje (0 = nie działa).
    ///
    /// Zapisuje go kolejka sieciowa, czyta główny wątek (ikonka w pasku menu),
    /// stąd zamek po obu stronach.
    ///
    /// 🔴 **„Faktyczny", nie „żądany" — decyzja [U] 2026-09-02, pozycja 12.** Do tego
    /// dnia stan `.ready` zapisywał tu numer **z żądania**, więc `port=0` (czyli
    /// „przydziel dowolny wolny") dawało `activePort == 0`, a `isRunning` — fałsz przy
    /// działającym moście. Blokowało to naturalną naprawę doboru portu w testach, które
    /// **losowały** numer z puli efemerycznej, tej samej, którą rozdaje system: jedna
    /// przegrana w losowaniu kładła całą klasę testów (zaobserwowane 2026-09-02,
    /// 76 porażek z 22 testów).
    ///
    /// Skutek dla czytającego: przy `port=0` odpowiedź poda **inny numer niż żądanie**
    /// — i to jest właśnie ta informacja, po którą się tu sięga.
    public var activePort: UInt16 { stateLock.withLock { _activePort } }

    /// Czy most jest uruchomiony.
    public var isRunning: Bool { activePort != 0 }

    private init() {}

    private func setActivePort(_ value: UInt16) {
        stateLock.withLock { _activePort = value }
    }

    #if DEBUG
    /// Numer portu, który przydzielił system. `nil`, gdy nasłuchu nie ma.
    ///
    /// Czytamy przez `stateLock`, a nie przez domknięcie trzymające `NWListener` —
    /// domknięcie stanu należy do samego nasłuchu, więc mocna referencja na niego
    /// byłaby cyklem.
    private func portNasluchu() -> UInt16? {
        stateLock.withLock { _listener?.port?.rawValue }
    }
    #endif

    #if DEBUG
    // Wszystko poniżej pod `stateLock`. Wcześniej zamek miał wyłącznie `_activePort`,
    // a `listener`, `appName` i `startedAt` chodziły bez żadnej bariery, choć
    // `stopServer()` woła je z kolejki sieciowej, a `startServer` z wątku
    // wywołującego. Audyt 2026-08-02, P2-03.
    private var _listener: NWListener?
    private var _appName: String = "app"
    private var _startedAt = Date()

    /// Sufit czasu handlera obowiązujący **ten** most, osobno od stałej `maksCzasHandleraSekundy`.
    ///
    /// Istnieje dla jednego powodu: test gniazdowy musi go skrócić do sekundy,
    /// bo sprawdzanie odmowy 504 przy dziewięćdziesięciu sekundach trwałoby półtorej
    /// minuty i po tygodniu nikt by tego testu nie uruchamiał. Zmienna **instancji**
    /// pod `stateLock`, a nie `static var` — globalna zmienna nie przechodzi w trybie
    /// Swift 6, a `nonisolated(unsafe)` wyłączyłoby sprawdzanie zamiast je spełnić
    /// (ta sama decyzja, co przy porcie w `BridgeServerGniazdoTests`).
    private var _maksCzasHandlera: Double = BridgeServer.maksCzasHandleraSekundy

    var maksCzasHandlera: Double { stateLock.withLock { _maksCzasHandlera } }

    /// Skraca sufit czasu handlera. **Do testów** — aplikacja nie ma powodu tego wołać.
    func ustawMaksCzasHandlera(_ sekundy: Double) {
        stateLock.withLock { _maksCzasHandlera = sekundy }
    }

    private let queue = DispatchQueue(label: "AppBridgeKit.server", qos: .utility)

    /// Kolejka **wyłącznie dla strażników czasu**. Nic tu nie liczy i nic nie czyta
    /// z gniazda — same zegary.
    ///
    /// 🔴 Nie jest to ozdoba, tylko warunek działania obu strażników. Do 2026-08-28
    /// planowały się przez `queue.asyncAfter`, czyli **na tej samej szeregowej
    /// kolejce, którą blokuje długi handler** — a więc nie mogły zadziałać dokładnie
    /// wtedy, kiedy są potrzebne: przy `/diff` liczącym minutę zegar bezczynności
    /// stał w tym samym szeregu, co robota, na którą miał patrzeć. Strażnik, który
    /// milczy razem z tym, czego pilnuje, nie jest strażnikiem.
    ///
    /// Wolno stąd dotykać `connections` (zamek `connectionsLock` już to pokrywa)
    /// i wołać `cancel()`/`send` na `NWConnection` — oba są bezpieczne z wielu
    /// wątków. Nie wolno stąd wykonywać handlerów — od tego jest `robocza`.
    /// [[Problem-dlugie-zadanie-glusza-caly-most]], WW-P1-03.
    private let zegar = DispatchQueue(label: "AppBridgeKit.zegar", qos: .utility)

    /// Kolejka **wykonawcza dla handlerów `.inBackground`** — i jedyne miejsce,
    /// gdzie liczy się cokolwiek dłuższego niż chwila.
    ///
    /// 🔴 To jest naprawa WW-P1-03 wariantem (a), czyli przyczyny, a nie objawu.
    /// Do 2026-08-28 handler tła wykonywał się **wprost na `queue`**, czyli na tej
    /// samej **szeregowej** kolejce, na której `NWConnection` odbiera bajty. Dopóki
    /// `/diff` przemielał trzydzieści sześć milionów pikseli, kolejne żądanie nie
    /// zostawało nawet **odczytane** — nie było go komu odebrać, więc most milczał
    /// na wszystko, także na `/ping`. Zmierzone: `/ping` odpowiadał 1 raz na 9 prób
    /// w trakcie `/diff`, przy 5/5 i ~1 ms na moście bezczynnym.
    ///
    /// Kolejka jest **równoległa** (`.concurrent`), bo szeregowa robocza dawałaby
    /// to samo głuszenie o jedno piętro niżej: drugi wolny handler czekałby na
    /// pierwszy. Sufit równoległości niesie już pula szesnastu połączeń.
    ///
    /// 🔴 Czego ta zmiana **nie** dotyczy — i to jest zmierzone, nie założone:
    /// gałąź `.onMainActor` zostaje bez zmian, bo już dziś leci przez
    /// `Task { @MainActor }` i nie blokuje odbioru (2,676 s kontra 0,002 s do
    /// pierwszego `/ping`). Stan współdzielony też zostaje: `connections`
    /// i `ConnectionState` są pod `connectionsLock`, pola serwera pod `stateLock`,
    /// rejestr tras ma własny zamek, a `NWConnection` jest bezpieczne wielowątkowo.
    ///
    /// Tego, że handlery naprawdę nie wracają na `queue`, pilnuje test
    /// `test_pingOdpowiadaWTrakcieHandleraTla` w `BridgeServerGniazdoTests`.
    private let robocza = DispatchQueue(
        label: "AppBridgeKit.handlery", qos: .utility, attributes: .concurrent
    )
    private var connections: [ObjectIdentifier: ConnectionState] = [:]
    private let connectionsLock = NSLock()

    /// Numery wpisów historii, którym zegar odesłał 504, a ich handler **liczy dalej**.
    ///
    /// 🔴 Osobno od `connections`, bo przy 504 gniazdo wraca do puli od razu
    /// (`forget`) — a domknięcie wpisu przychodzi dopiero wtedy, gdy handler skończy,
    /// czyli po tym, jak stan połączenia już nie istnieje.
    ///
    /// ⚠️ `ObjectIdentifier` to **adres**, a adres zwolnionego `NWConnection` system
    /// potrafi wydać ponownie. Dlatego wpis jest kasowany w `accept` przy każdym nowym
    /// połączeniu: świeże połączenie nie może odziedziczyć cudzego domknięcia.
    /// Pod `connectionsLock`, tak jak `connections`.
    private var wpisyPoTerminie: [ObjectIdentifier: Int] = [:]

    /// Ile sekund połączenie może milczeć, zanim je zamkniemy. Bez tego klient,
    /// który się połączy i nic nie wyśle, zostaje w pamięci do zamknięcia mostu —
    /// jedyne miejsce w projekcie, gdzie zasoby rosły bez sufitu (P2-04).
    static let idleTimeoutSeconds: Double = 20

    /// Ile połączeń most obsługuje jednocześnie. Nadmiarowe dostają 503 i lecą
    /// od razu — kolejkowanie ich trzymałoby w pamięci dokładnie to, przed czym
    /// ten sufit ma bronić.
    ///
    /// Po drugiej stronie stoi jeden serwer MCP wysyłający żądania po kolei, więc
    /// 16 to zapas rzędu wielkości, a nie ciasny gorset. Zmierzone przed naprawą:
    /// 20 połączeń po 7 MB niedokończonego ciała = **+143 MB** w pamięci
    /// aplikacji-gospodarza, bez żadnego progu po drodze. Audyt 2026-08-10, E2-P1-01.
    static let maxConnections = 16

    /// Twardy limit życia połączenia liczony od `accept`, **niezależny od ciszy**.
    ///
    /// Strażnik bezczynności mierzy przerwę między fragmentami, więc klient wysyłający
    /// jeden bajt co 19 s jest dla niego nieodróżnialny od wolnego łącza i trzyma
    /// swoje 8 MB dowolnie długo (zmierzone: 34 s podtrzymywania, zero zamkniętych
    /// połączeń przy limicie 20 s). Ten limit patrzy na zegar, nie na ruch.
    ///
    /// 🔴 Dotyczy **wyłącznie kompletowania żądania**. Połączenie z pracującym
    /// handlerem (`wTrakcieObslugi`) jest z niego wyłączone — inaczej ucięłoby
    /// długie endpointy aplikacji, np. `/enhance/start` w innym gospodarzu.
    static let maxConnectionLifetimeSeconds: Double = 30

    /// Ile sekund handler może pracować, zanim klient dostanie `504` zamiast ciszy.
    ///
    /// Do 2026-08-28 pracujący handler nie miał **żadnego** ogranicznika: był celowo
    /// zwolniony z obu strażników wyżej, więc endpoint, który się zawiesił, trzymał
    /// gniazdo i milczał do zamknięcia aplikacji. Po szesnastu takich most był martwy
    /// na zawsze i nie umiał powiedzieć dlaczego.
    ///
    /// 🔴 Ten sufit **nie odblokowuje handlera** — przerwać go nie można, więc liczy
    /// do końca, a jego spóźniony wynik idzie do kosza. Zmienia tyle, że cisza staje
    /// się odpowiedzią z nazwą winnego endpointu, a gniazdo wraca do puli.
    ///
    /// Do 2026-08-28 zabierał ze sobą **cały most**: handler tła stał na kolejce
    /// sieciowej, więc `/ping` też nie odpowiadał do jego końca. Tej części już nie
    /// ma — handlery `.inBackground` liczą na `robocza` (wariant (a), WW-P1-03).
    ///
    /// Skąd 90: najdłuższy handler, jaki most potrafi wywołać z własnych endpointów,
    /// to `/diff` na dwóch bitmapach przy suficie 40 Mpx. Zmierzone (nie wyliczone)
    /// 2026-08-28 — patrz notatka. 90 s daje nad tym zapas i zostawia miejsce
    /// na wolniejszą maszynę. Endpoint aplikacji, który ma prawo trwać dłużej, należy
    /// przerobić na zlecenie (`Task` + natychmiastowe potwierdzenie, wzór
    /// `ErrorUpdateBridge` w `Przyklady/`) — bo blokowanie mostu na minuty jest
    /// usterką także wtedy, gdy jest zamierzone.
    static let maksCzasHandleraSekundy: Double = 90

    /// Ile czekamy po wysłaniu odmowy `504`, zanim zamkniemy gniazdo.
    ///
    /// Pół sekundy wystarcza z ogromnym zapasem: odmowa to kilkaset bajtów przez
    /// pętlę lokalną, więc mieści się w buforze gniazda niezależnie od tego, jak
    /// wolno klient czyta. Zwłoka jest tu nie dla sieci, tylko dlatego, że
    /// `NWConnection.cancel()` wywołane od razu po `send` **ucina wysyłkę** zamiast
    /// ją dosłać — patrz komentarz w `pilnujCzasuHandlera`.
    static let zwlokaPrzedZamknieciemSekundy: Double = 0.5

    var appName: String { stateLock.withLock { _appName } }
    var startedAt: Date { stateLock.withLock { _startedAt } }
    #endif

    // MARK: - Start / stop

    /// Uruchamia most. Wywołaj raz przy starcie aplikacji.
    /// - Parameters:
    ///   - port: port TCP na 127.0.0.1. Każda aplikacja powinna mieć własny.
    ///   - appName: nazwa raportowana w `/ping` — ułatwia rozpoznanie, z czym rozmawiamy.
    ///   - showMenuBarIcon: ikonka w pasku menu pokazująca ruch na moście.
    ///     Ustaw `false`, jeśli aplikacja nie ma interfejsu graficznego.
    public static func start(
        port: UInt16 = 8765,
        appName: String = "app",
        showMenuBarIcon: Bool = true
    ) {
        shared.startServer(port: port, appName: appName, showMenuBarIcon: showMenuBarIcon)
    }

    public static func stop() {
        shared.stopServer()
    }

    private func startServer(port: UInt16, appName: String, showMenuBarIcon: Bool) {
        #if DEBUG
        let juzDziala = stateLock.withLock { _listener != nil }
        guard !juzDziala else {
            log("Most już działa na porcie \(activePort) — pomijam ponowny start.")
            return
        }

        stateLock.withLock {
            _appName = appName
            _startedAt = Date()
        }
        registerBuiltInRoutes()

        // Ikonka powstaje OD RAZU, a nie dopiero w stanie `.ready`.
        //
        // Wcześniej instalowała się wyłącznie po udanym starcie, więc zajęty port
        // dawał brak ikonki i brak komunikatu — czyli dokładnie to samo, co
        // „zapomniałem wystartować most". Teraz ikonka jest zawsze i sama pokazuje,
        // że coś poszło nie tak. Audyt 2026-08-02, P2-05.
        #if canImport(AppKit)
        if showMenuBarIcon {
            BridgeStatusIcon.install(appName: appName, port: port)
        }
        #endif

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            report(failure: "Nieprawidłowy numer portu: \(port)")
            return
        }

        let parameters = NWParameters.tcp
        // Klucz do bezpieczeństwa: wiążemy się wyłącznie z pętlą lokalną.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            stateLock.withLock { _listener = listener }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    // Port bierzemy z NASŁUCHU, nie z żądania — patrz `activePort`.
                    // Zapasowo `port`, żeby jedno `nil` nie zamieniło działającego
                    // mostu w „zatrzymany" (`isRunning` to `activePort != 0`).
                    let faktyczny = self.portNasluchu() ?? port
                    self.setActivePort(faktyczny)
                    self.log("Most gotowy: http://127.0.0.1:\(faktyczny) (aplikacja: \(appName))")
                    #if canImport(AppKit)
                    if showMenuBarIcon {
                        BridgeStatusIcon.markReady(port: faktyczny)
                    }
                    #endif
                case .failed(let error):
                    self.setActivePort(0)
                    self.report(failure:
                        "Most padł: \(error.localizedDescription). Czy port \(port) nie jest zajęty?")
                    // Zwalniamy zasoby, ale ikonki NIE zdejmujemy — przekreślona
                    // antena z powodem awarii jest jedynym śladem, jaki użytkownik
                    // dostaje po nieudanym starcie. Wcześniej szło tędy pełne
                    // `stopServer()`, które w tej samej milisekundzie kasowało
                    // ikonkę ustawioną linijkę wyżej przez `report(failure:)`.
                    // Audyt 2026-08-02 P2-05 kontra 2026-08-10 E3b-P2-01;
                    // rozstrzygnięte na korzyść P2-05 dla ścieżki awarii. REG-01.
                    self.zamknijNasluchIPolaczenia()
                case .cancelled:
                    self.setActivePort(0)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.start(queue: queue)
        } catch {
            report(failure: "Nie udało się uruchomić mostu: \(error.localizedDescription)")
        }
        #endif
    }

    /// Rozmyślne zatrzymanie mostu — zdejmuje **wszystko**, razem z ikonką.
    ///
    /// Jedyna droga, którą `BridgeStatusIcon.remove()` ma prawo pojechać. Ścieżka
    /// awarii startu woła samo `zamknijNasluchIPolaczenia()` i ikonkę zostawia.
    private func stopServer() {
        #if DEBUG
        zamknijNasluchIPolaczenia()

        // Ikonka znika razem z mostem. Wcześniej `remove()` nie było wołane **ani
        // razu** — antena zostawała w pasku menu cudzej aplikacji i do najbliższego
        // otwarcia menu wyglądała, jakby most nadal nasłuchiwał. Sama metoda była
        // przez to martwym kodem. Audyt 2026-08-10, E3b-P2-01.
        #if canImport(AppKit)
        BridgeStatusIcon.remove()
        #endif
        #endif
    }

    #if DEBUG
    /// Zwalnia nasłuch i otwarte połączenia. **Ikonki nie dotyka.**
    ///
    /// Wydzielone z `stopServer()`, żeby ścieżka awarii startu mogła posprzątać
    /// zasoby bez kasowania przekreślonej anteny. Rozróżnienie jest tutaj — w tym,
    /// którą funkcję woła który powód zatrzymania — a nie w parametrze `Bool`,
    /// bo w miejscu wywołania `stopServer(false)` nie mówi nic o ikonce.
    ///
    /// 🔴 Nie da się tego załatwić po stronie samej ikonki („`remove()` niech
    /// sprawdzi, czy jest powód awarii"): `markFailed()` i `remove()` idą na główny
    /// aktor jako dwa osobne, niestrukturalne `Task`i, więc ich kolejność nie jest
    /// gwarantowana. Przy odwrotnej `markFailed()` trafiłoby na zdjęty już
    /// `statusItem` i wyszło przez `guard` — ten sam brak ikonki, tylko losowy.
    private func zamknijNasluchIPolaczenia() {
        // Zamek zdejmowany PRZED `cancel()` — wołanie cudzego kodu spod zamka
        // to prosta droga do zakleszczenia, bo `cancel()` wywołuje
        // `stateUpdateHandler`, który znowu sięga po ten sam stan.
        let doZamkniecia: NWListener? = stateLock.withLock {
            let l = _listener
            _listener = nil
            _activePort = 0
            return l
        }
        doZamkniecia?.cancel()

        connectionsLock.lock()
        let open = connections.values.map(\.connection)
        connections.removeAll()
        connectionsLock.unlock()
        open.forEach { $0.cancel() }
    }
    #endif

    // MARK: - Implementacja (tylko DEBUG)

    #if DEBUG

    private func registerBuiltInRoutes() {
        let registry = BridgeRegistry.shared

        // `/ping` i `/routes` nie dotykają aplikacji — czytają tylko własny stan
        // mostu, który jest za zamkiem. Dlatego wolno im lecieć w tle.
        registry.registerInBackground(
            method: "GET",
            path: "/ping",
            description: "Sprawdzenie, czy aplikacja żyje i most odpowiada"
        ) { _ in
            let server = BridgeServer.shared
            let uptime = Int(Date().timeIntervalSince(server.startedAt))
            return .json([
                "ok": true,
                "app": server.appName,
                "pid": ProcessInfo.processInfo.processIdentifier,
                "uptimeSeconds": uptime,
                "bridgeVersion": BridgeServer.version,
            ])
        }

        registry.registerInBackground(
            method: "GET",
            path: "/routes",
            description: "Lista endpointów udostępnionych przez tę aplikację"
        ) { _ in
            let list = BridgeRegistry.shared.allRoutes().map { route in
                [
                    "method": route.method,
                    "path": route.path,
                    "description": route.description,
                    "wykonanie": route.execution.opis,
                ]
            }
            return .json(["routes": list])
        }

        // 🔴 Historia jest odpowiedzią na komunikat, który most już wysyła. Trasa
        // pisząca odmawia z terminu zdaniem „zanim ponowisz, sprawdź stan" — i do
        // 1.2.14 nie dawała **czym**: `BridgeActivity` szła wyłącznie do menu w pasku,
        // czyli do człowieka. Agent po 504 miał dwie drogi, zgadnąć albo powtórzyć,
        // i obie były złe (plan rozwoju mostu po 1.2.14, poz. 1).
        //
        // Leci w tle, tak jak `/ping` i `/routes`: czyta własny stan mostu spod zamka
        // i nie dotyka aplikacji ani jednym wywołaniem.
        registry.registerInBackground(
            method: "GET",
            path: "/historia",
            description: "Ostatnie żądania do tego mostu — co agent już w tej aplikacji zmienił (?limit=N)"
        ) { request in
            let sufit = BridgeActivity.maxRecent
            // Bez `?limit=` oddajemy wszystko, co most trzyma. Liczba spoza zakresu
            // nie jest odmową: sufit i tak stoi wyżej, a odmowa za „limit=0" byłaby
            // hałasem przy pytaniu, które nic nie zmienia.
            let zadany = request.query["limit"].flatMap(Int.init) ?? sufit
            let limit = min(max(zadany, 1), sufit)
            let wpisy = BridgeActivity.shared.ostatnie(limit: limit)
            let wszystkich = BridgeActivity.shared.total
            // 🔴 Liczone wobec tego, co most TRZYMA, a nie wobec tego, ile oddał.
            // Zmierzone na żywym poligonie 2026-09-03: przy `?limit=2` i sześciu
            // żądaniach odpowiedź mówiła „starszych 4 nie widać — wypadły z pamięci",
            // choć wszystkie sześć tam było, a uciął je limit z TEGO żądania.
            // Liczba, która myli własne cięcie z zapominaniem, jest gorsza od jej braku.
            let wPamieci = BridgeActivity.shared.recent.count

            return .json([
                "wpisy": wpisy.map(\.slownik),
                // 🔴 Bez tych dwóch liczb cisza w historii wygląda jak dowód, że
                // żądania nie było. Most trzyma ostatnie `sufitHistorii` wpisów
                // i tyle — starsze wypadły, a nie „nie istniały".
                "sufitHistorii": sufit,
                "zadanOdStartu": wszystkich,
                "pominietych": max(wszystkich - wPamieci, 0),
                // Ile most trzyma w tej chwili — żeby dało się odróżnić „uciąłem
                // limitem" od „tego już nie ma".
                "wPamieci": wPamieci,
                "zmian": BridgeActivity.shared.zmian,
                "bledow": BridgeActivity.shared.errors,
            ])
        }

        // Zrzut rysuje widoki, więc musi być na głównym aktorze — i teraz nie da
        // się tego zarejestrować inaczej, bo `capturePNG` jest do niego izolowane.
        registry.registerOnMainActor(
            method: "GET",
            path: "/screenshot",
            description: "Zrzut PNG okna (?window=tytuł/klasa, ?scrollToLine=N, ?find=tekst, ?view=); rozmiar i skala w nagłówkach x-bridge-*"
        ) { request in
            let wiersz = request.query["scrollToLine"].flatMap(Int.init)
            // Nagłówki z rozmiarem i skalą, tak samo jak przy `/render`. W samym PNG
            // nie ma gdzie napisać, w jakiej jednostce liczą się potem `/hit`
            // i `/drawn-rects` — a to jest jedyna droga, żeby wołający to wiedział.
            let (data, naglowki) = try BridgeScreenshot.zrzutZOpisem(
                windowTitle: request.query["window"],
                scrollToLine: wiersz,
                find: request.query["find"],
                widok: request.query["view"]
            )
            return .png(data, naglowki: naglowki)
        }

        registerBuiltInWyglad(registry)
    }

    /// Endpointy do pracy nad **wyglądem** — dopisane 2026-08-27 z listy braków
    /// spisanej przy doprowadzaniu `Like Xcode` w MarkRead do zgodności z Xcode
    /// (`Plan-most-do-pracy-nad-wygladem` w sejfie).
    ///
    /// Wydzielone z `registerBuiltInRoutes`, bo tamta funkcja opisywała **czym most
    /// jest** (żyje, ma trasy, umie się pokazać), a te opisują, **co umie zmierzyć**.
    /// Jedna funkcja na trzydzieści linii rejestracji przestaje się czytać.
    private func registerBuiltInWyglad(_ registry: BridgeRegistry) {
        #if canImport(AppKit)

        // MARK: Okna

        registry.registerOnMainActor(
            method: "GET",
            path: "/windows",
            description: "Okna aplikacji, okna odsiane jako techniczne i zgłoszone sposoby otwierania"
        ) { _ in
            .json([
                // `okna` to dokładnie to, co `wybierzOkno` uzna za okno — jedna definicja
                // na całą warstwę. `odsiane` niesie resztę razem z powodem, żeby naprawa
                // nie zabrała informacji, tylko odebrała jej fałszywą etykietę. E5-P2-01.
                "okna": BridgeWindows.opisWidocznychOkien(),
                "odsiane": BridgeWindows.opisOdsianychOkien(),
                "otwieranie": BridgeWindows.zgloszone.map { ["nazwa": $0.nazwa, "opis": $0.opis] },
            ])
        }

        // 🔴 Jedyna akcja mostu, którą użytkownik zobaczy bez własnej intencji —
        // okno pojawia się na ekranie. Dlatego jest to osobne, jawne wywołanie,
        // a nie automat w `/screenshot` (decyzja [U] 2026-08-27).
        registry.registerOnMainActor(
            method: "POST",
            path: "/window/open",
            description: "Otwiera okno aplikacji: {\"okno\": \"nazwa\"} — sposób zgłasza program"
        ) { request in
            let cialo = try request.jsonBody()
            let nazwa = cialo["okno"] as? String
            let uzyty = try BridgeWindows.otworz(nazwa: nazwa)
            return .json([
                "otwarto": uzyty,
                // Odpowiedź mówi, co JEST na ekranie po akcji, a nie „ok". Domknięcie
                // programu mogło nie zrobić nic — wtedy lista okien jest jedynym
                // dowodem, i to ona ma rozstrzygać, nie kod 200.
                "okna": BridgeWindows.opisWidocznychOkien(),
            ])
        }

        // MARK: Wygląd

        registry.registerOnMainActor(
            method: "GET",
            path: "/appearance",
            description: "Jaki wygląd jest ustawiony i jaki działa (jasny/ciemny)"
        ) { _ in .json(BridgeAppearance.stan()) }

        registry.registerOnMainActor(
            method: "POST",
            path: "/appearance",
            description: "Wymusza wygląd: {\"wyglad\": \"dark\" | \"light\" | \"system\" | \"przywroc\"} — WIDOCZNE dla użytkownika"
        ) { request in
            let cialo = try request.jsonBody()
            guard let nazwa = cialo["wyglad"] as? String else {
                throw BridgeError.badRequest("Podaj {\"wyglad\": \"dark\" | \"light\" | \"system\"}")
            }
            return .json(try BridgeAppearance.ustaw(nazwa))
        }

        // MARK: Tekst, geometria, sonda

        registry.registerOnMainActor(
            method: "GET",
            path: "/text-attributes",
            description: "Atrybuty runów tekstu: krój, waga, kolor w sRGB z alfą (?from=&to=)"
        ) { request in
            // `liczbaZQuery`, a nie `flatMap(Int.init)`: parametr, który jest, ale nie
            // jest liczbą, ma dać 400, a nie zniknąć. Audyt 2026-08-28, E5-P3-01.
            .json(try BridgeTextAttributes.odczytaj(
                okno: request.query["window"],
                widok: request.query["view"],
                od: try BridgeTextAttributes.liczbaZQuery(request.query, "from"),
                do: try BridgeTextAttributes.liczbaZQuery(request.query, "to"),
                limit: try BridgeTextAttributes.liczbaZQuery(request.query, "limit")
            ))
        }

        registry.registerOnMainActor(
            method: "GET",
            path: "/render",
            description: "PNG samego widoku, bez cienia i belki (?view=&width=&height=&appearance=)"
        ) { request in
            // Endpoint sam składa odpowiedź, bo dokłada nagłówki z rozmiarem oddanej
            // bitmapy — w samym PNG nie ma gdzie napisać, czy zamówienie spełniono.
            try BridgeRenderEndpoint.render(query: request.query)
        }

        // 🔴 Jedyny endpoint mostu, który mierzy **sam most**, a nie gospodarza —
        // i dlatego jest w tej czwórce najsłabszy, co plan mówi wprost. Zarabia na
        // siebie inaczej: wygląd ikonki poprawiało się w tej sesji dwa razy i za
        // każdym razem pomiarem był zrzut przysłany przez [U], bo obie drogi mostu
        // były zamknięte (`screencapture` bez zgody systemowej, `/screenshot` na oknie
        // 38×33 pt odsiane przez sito „za małe na interfejs").
        registry.registerOnMainActor(
            method: "GET",
            path: "/ikonka",
            description: "PNG własnej ikonki mostu w pasku menu — bez zgody na nagrywanie ekranu (?tlo=ciemne|jasne)"
        ) { request in
            // 🔴 Bez `?tlo=` bierzemy wygląd SYSTEMU, nie stałą. Ikonka jest szablonem,
            // więc barwę nadał jej pasek w wyglądzie, który akurat obowiązuje — i most
            // jej nie przelicza. Dorysowanie tła „na wszelki wypadek ciemnego" dawało
            // przy jasnym systemie jasny młotek na jasnym tle, czyli obraz, którego
            // nigdzie nie ma (zobaczone na żywym gospodarzu 2026-09-03).
            let ciemne: Bool? = switch request.query["tlo"] {
            case "ciemne": true
            case "jasne": false
            case nil: nil
            case .some(let inne):
                throw BridgeError.badRequest(
                    "Parametr tlo przyjmuje \"ciemne\" albo \"jasne\", a dostał "
                    + "\"\(BridgeDefaults.skrocony(inne, do: 40))\". Bez tego parametru most "
                    + "bierze wygląd systemu — i tylko wtedy obrazek pokazuje to, "
                    + "co użytkownik naprawdę widzi."
                )
            }
            let (dane, naglowki) = try BridgeStatusIcon.podglad(naCiemnym: ciemne)
            return .png(dane, naglowki: naglowki)
        }

        registry.registerOnMainActor(
            method: "GET",
            path: "/drawn-rects",
            description: "Prostokąty, które program narysował sam — listę zgłasza program"
        ) { request in
            .json(try BridgeDrawnRects.zbierz(okno: request.query["window"]))
        }

        registry.registerOnMainActor(
            method: "GET",
            path: "/hit",
            description: "Co jest pod punktem okna, w PUNKTACH (piksele PNG podziel przez x-bridge-skala): /hit?x=120&y=340"
        ) { request in
            .json(try BridgeHitTest.zbadaj(query: request.query))
        }

        // MARK: Ustawienia

        registry.registerOnMainActor(
            method: "GET",
            path: "/defaults",
            description: "Ustawienia wystawione przez program (biała lista) i ich wartości"
        ) { _ in
            .json(["ustawienia": BridgeDefaults.shared.stan()])
        }

        registry.registerOnMainActor(
            method: "POST",
            path: "/defaults",
            description: "Ustawia jeden klucz z białej listy: {\"klucz\": \"…\", \"wartosc\": …}"
        ) { request in
            let cialo = try request.jsonBody()
            guard let klucz = cialo["klucz"] as? String else {
                throw BridgeError.badRequest("Podaj {\"klucz\": \"nazwa\", \"wartosc\": …}")
            }
            guard let wartosc = cialo["wartosc"] else {
                throw BridgeError.badRequest(
                    "Brak pola \"wartosc\". Żeby skasować klucz, podaj wartosc: null "
                    + "albo zawołaj POST /defaults/reset."
                )
            }
            try BridgeDefaults.shared.ustaw(klucz: klucz, wartosc: wartosc)
            return .json(["ustawienia": BridgeDefaults.shared.stan()])
        }

        registry.registerOnMainActor(
            method: "POST",
            path: "/defaults/reset",
            description: "Kasuje jeden klucz ({\"klucz\": \"…\"}) albo wszystkie z białej listy"
        ) { request in
            let cialo = try request.jsonBody()
            let skasowane = try BridgeDefaults.shared.zresetuj(klucz: cialo["klucz"] as? String)
            return .json([
                "skasowane": skasowane,
                "ustawienia": BridgeDefaults.shared.stan(),
            ])
        }
        #endif

        // MARK: Akcje — jedyne miejsce, w którym most COKOLWIEK zmienia na polecenie

        // 🔴 Obie trasy stoją tutaj, czyli za tym samym routingiem i tym samym sitem
        // co reszta (§3b planu). Warstwa akcji **nie ma własnej, luźniejszej ścieżki
        // wejścia** — żądanie z `Origin` przeglądarki dostaje 403 zanim akcja
        // się wykona, tak samo jak przy każdym innym endpoincie.
        registry.registerOnMainActor(
            method: "GET",
            path: "/akcje",
            description: "Akcje zgłoszone przez aplikację i czy warstwa jest włączona"
        ) { _ in
            // 🔴 Lista niesie DROGĘ POWROTNĄ, nie tylko nazwę i opis (plan rozwoju
            // warstwy akcji, poz. 1). Agent ma wiedzieć PRZED wywołaniem, czy skutek
            // da się cofnąć i czym — do 2026-09-03 ta wiedza mieszkała w prozie README
            // i w głowie autora gospodarza.
            let zgloszone = BridgeActions.zgloszone
            let nazwy = Set(zgloszone.map { $0.nazwa.lowercased() })
            return .json([
                "wlaczona": BridgeActions.czyWlaczona,
                "akcje": zgloszone.map { akcja -> [String: Any] in
                    var wpis: [String: Any] = [
                        "nazwa": akcja.nazwa,
                        "opis": akcja.opis,
                        "odwracalnosc": akcja.odwracalnosc.nazwa,
                        "wymagaPotwierdzenia": akcja.odwracalnosc.wymagaPotwierdzenia,
                        // Ile ta akcja mierzy skutek — żeby klient wiedział, na jaki
                        // timeout się umówić, ZANIM dostanie odmowę za zbyt krótki.
                        "sufitUstabilizowaniaMs": BridgeActions.sufitDlaAkcji(akcja),
                        // Argumenty razem z ich DZIEDZINĄ — agent ma wiedzieć, co wolno
                        // przysłać, zanim spróbuje, a nie dowiadywać się tego z odmów.
                        "argumenty": akcja.parametry.map { p -> [String: Any] in
                            ["nazwa": p.nazwa, "opis": p.opis, "dozwolone": p.dozwolone.opisDlaAgenta]
                        },
                    ]
                    // 🔴 Dostępność liczona TERAZ, przy każdym pytaniu o listę —
                    // to jest jej cała wartość (plan rozwoju po 1.2.14, poz. 2).
                    // Predykat obowiązuje kontrakt sondy: tani i bez skutków ubocznych.
                    // Gospodarz, który go nie zadeklarował, dostaje `true` i zdanie
                    // mówiące wprost, że nikt tego nie sprawdzał — a nie ciszę, którą
                    // dałoby się wziąć za pomiar.
                    if let dostepnosc = akcja.dostepnosc {
                        let stan = dostepnosc()
                        wpis["dostepna"] = stan.czyDostepna
                        if let powod = stan.powod {
                            wpis["powodNiedostepnosci"] = BridgeDefaults.skrocony(powod, do: 300)
                        }
                    } else {
                        wpis["dostepna"] = true
                        wpis["dostepnoscNiezadeklarowana"] = true
                    }
                    if let cofaJa = akcja.odwracalnosc.cofaJa {
                        wpis["cofaJa"] = cofaJa
                        // Deklaracja gospodarza sprawdzana wobec rejestru, a nie
                        // powtarzana na słowo: „cofa ją akcja X", gdy X nie istnieje,
                        // jest gorsze niż brak deklaracji — brzmi jak droga powrotna,
                        // a nią nie jest. Sprawdzane TUTAJ, nie przy rejestracji,
                        // bo akcja cofająca bywa zgłoszona później niż ta, którą cofa.
                        if !nazwy.contains(cofaJa.lowercased()) {
                            wpis["uwaga"] = "Akcja \"\(cofaJa)\" nie jest zgłoszona — "
                                + "deklarowana droga powrotna nie istnieje."
                        }
                    }
                    return wpis
                },
            ])
        }

        // 🔴 Suchy bieg stoi za WŁASNĄ trasą, nie za flagą w `POST /akcja` — i to jest
        // decyzja, nie wygoda (plan rozwoju po 1.2.14, poz. 3). Tamta trasa jest
        // `.akcjaNaGlownymAktorze`, czyli **pisząca**: dziedziczyłby po niej odmowę
        // przy krótkim suficie klienta, miejsce w kolejce akcji i wpis `zmienil: true`
        // w `GET /historia`. Ostatnie z tych trzech byłoby wprost nieprawdą — podgląd
        // niczego nie zmienia, a historia od 1.2.15 jest tym, czym agent sprawdza,
        // co zmienił. Tutaj `.onMainActor`: czyta sondę gospodarza i nic więcej.
        //
        // POST, choć trasa nie pisze, bo podgląd niesie **argumenty w ciele** —
        // metoda opisuje kształt żądania, a `BridgeExecution` opisuje skutek. To są
        // dwie różne rzeczy i tylko druga rządzi sufitami, kolejką i historią.
        registry.registerOnMainActor(
            method: "POST",
            path: "/akcja/podglad",
            description: "Co ta akcja zastanie — stan, sprawdzone argumenty i deklaracje autora, BEZ wykonania: {\"akcja\": \"nazwa\", \"argumenty\": {…}}"
        ) { request in
            let cialo = try request.jsonBody()
            guard let nazwa = cialo["akcja"] as? String, !nazwa.isEmpty else {
                throw BridgeError.badRequest(
                    "Podaj {\"akcja\": \"nazwa\"}. Nazwy zgłoszone przez tę aplikację "
                    + "wymienia GET /akcje."
                )
            }
            let argumenty = cialo["argumenty"] as? [String: Any] ?? [:]
            return .json(try BridgeActions.podglad(nazwa: nazwa, argumenty: argumenty))
        }

        registry.register(BridgeRoute(
            method: "POST",
            path: "/akcja",
            description: "Wykonuje akcję zgłoszoną przez aplikację: {\"akcja\": \"nazwa\", \"argumenty\": {…}} — ZMIENIA interfejs. Akcja nieodwracalna wymaga {\"potwierdzam\": true}",
            execution: .akcjaNaGlownymAktorze { request in
                let cialo = try request.jsonBody()
                guard let nazwa = cialo["akcja"] as? String, !nazwa.isEmpty else {
                    throw BridgeError.badRequest(
                        "Podaj {\"akcja\": \"nazwa\"}. Nazwy zgłoszone przez tę aplikację "
                        + "wymienia GET /akcje."
                    )
                }
                // Potwierdzenie musi być JAWNIE `true`. Sama obecność klucza nie
                // wystarcza — `{"potwierdzam": false}` i `{"potwierdzam": "nie"}`
                // mają znaczyć „nie", a nie „ktoś o tym pomyślał".
                let potwierdzone = (cialo["potwierdzam"] as? Bool) == true
                // Budżet TEGO żądania — ta sama liczba, na której stoi zegar handlera.
                // Warstwa akcji porówna go z sufitem konkretnej akcji, czego sito
                // przed handlerem zrobić nie mogło: nie znało jeszcze nazwy akcji.
                let wlasny = BridgeServer.shared.maksCzasHandlera
                let budzet = (try? Self.sufitZadania(naglowki: request.headers, wlasny: wlasny).sufit) ?? wlasny
                // Argumenty jadą osobnym polem, nie wymieszane z `akcja`
                // i `potwierdzam` — inaczej argument o nazwie „potwierdzam"
                // byłby jednocześnie argumentem akcji i zamkiem potwierdzenia.
                let argumenty = cialo["argumenty"] as? [String: Any] ?? [:]
                let wynik = try await BridgeActions.wykonaj(
                    nazwa: nazwa, potwierdzone: potwierdzone,
                    budzetMs: Int(budzet * 1000), argumenty: argumenty
                )
                // 🔴 Ślad dla historii składa się TUTAJ, bo tylko tutaj wiadomo,
                // która akcja poszła. `POST /akcja` to jedna ścieżka na wszystkie
                // akcje gospodarza — bez tego historia mówi „coś zmieniłeś".
                // Nazwa brana z WYNIKU, nie z żądania: `wykonaj` dopasowuje ją bez
                // względu na wielkość liter, więc to wynik zna nazwę zgłoszoną
                // przez aplikację, a nie tę wpisaną przez agenta.
                let slad = BridgeActivitySlad(
                    szczegol: (wynik["akcja"] as? String) ?? nazwa,
                    zmienilo: (wynik["zmienilo"] as? [String]) ?? []
                )
                return BridgeResponse.json(wynik).zeSladem(slad)
            }
        ))

        // Porównanie bitmap to czysta arytmetyka — nie dotyka aplikacji ani AppKit,
        // więc leci w tle i nie zamraża interfejsu na czas liczenia pikseli.
        registry.registerInBackground(
            method: "POST",
            path: "/diff",
            description: "Porównuje dwa PNG w base64: {\"a\", \"b\", \"tolerancja\"} → procent i prostokąt"
        ) { request in
            .json(try BridgeImageDiff.porownaj(cialo: try request.jsonBody()))
        }
    }

    /// Stan jednego połączenia.
    ///
    /// Bufor trzymamy w **klasie**, a nie przekazujemy przez parametr. Wcześniej
    /// każdy nadchodzący fragment robił `var buffer = buffer; buffer.append(chunk)`
    /// przy dwóch żywych referencjach, więc `Data` kopiowało się w całości za każdym
    /// razem — koszt rósł kwadratowo z rozmiarem ciała. Przy ciele bliskim limitowi
    /// 8 MB to setki megabajtów przepisywania. Audyt 2026-08-02, P2-06.
    ///
    /// `@unchecked Sendable`, bo `buffer`, `znacznikRuchu` i `wTrakcieObslugi`
    /// są dotykane **wyłącznie** pod `connectionsLock` — sprawdzone ręcznie, każde
    /// wystąpienie w tym pliku. `connection` jest niezmienne, a `NWConnection` samo
    /// w sobie jest bezpieczne do wołania z wielu wątków.
    private final class ConnectionState: @unchecked Sendable {
        let connection: NWConnection
        var buffer = Data()
        /// Rośnie przy każdym odebranym fragmencie — po tym strażnik bezczynności
        /// poznaje, czy od jego zaplanowania cokolwiek przyszło.
        var znacznikRuchu = 0
        /// Gdy handler już pracuje, strażnik ma nie zamykać połączenia — długi
        /// endpoint to nie to samo co klient, który milczy.
        var wTrakcieObslugi = false
        /// Kiedy ruszył handler. `nil` znaczy „nic nie liczy" — po tym zegar
        /// z `pilnujCzasuHandlera` poznaje, czy ma jeszcze czego pilnować.
        var startHandlera: Date?
        /// Co pracuje — do komunikatu odmowy, do logu i do licznika ruchu. Bez tego
        /// 504 mówi „coś trwa za długo", a szuka się tego potem po całej aplikacji.
        ///
        /// Osobno, a nie jako gotowy napis: licznik ruchu bierze je **rozdzielone**
        /// (`record(method:path:)`), a komunikat odmowy składa je przez
        /// `BridgeServer.skroconyOpis(metoda:sciezka:)`, żeby cudze wejście dostało
        /// tam skrócenie. Własność `opisZadania` sklejająca je „na wszelki wypadek"
        /// stała tu do 2026-08-29 i **nikt jej nigdy nie zawołał** — sklejaj przez
        /// `skroconyOpis`, nie przez nową własność.
        var metodaZadania = ""
        var sciezkaZadania = ""
        /// Czy na to połączenie poszła już odpowiedź.
        ///
        /// 🔴 Prawo do odpowiedzi bierze się **raz**: albo zegar odsyła 504, albo
        /// handler oddaje wynik. Dwie odpowiedzi na jednym połączeniu to nie
        /// opóźnienie, tylko rozjechany protokół — klient przeczytałby ogon
        /// pierwszej jako początek drugiej.
        var odpowiedziano = false

        init(_ connection: NWConnection) { self.connection = connection }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let state = ConnectionState(connection)

        // Sufit sprawdzany pod TYM SAMYM zamknięciem zamka, pod którym rośnie
        // słownik. Odczyt `connections.count` osobno, przed wpisem, byłby wyścigiem:
        // dwa połączenia zdążyłyby zobaczyć „jest jeszcze miejsce" i weszłyby oba.
        let przyjete: Bool = connectionsLock.withLock {
            // Adres po zwolnionym połączeniu bywa wydany ponownie — patrz
            // `wpisyPoTerminie`. Czyścimy zawsze, także przy odmowie niżej: świeże
            // połączenie nie ma nic wspólnego z cudzym handlerem sprzed 504.
            wpisyPoTerminie.removeValue(forKey: id)
            guard connections.count < Self.maxConnections else { return false }
            connections[id] = state
            return true
        }

        // Nadmiarowe połączenie dostaje odpowiedź, a nie nieme zerwanie — po drugiej
        // stronie stoi `mcp-server`, który z zerwanego gniazda potrafi powiedzieć
        // tylko „ECONNRESET". Kod 503 z powodem po polsku trafia prosto do logu
        // narzędzia `bridge_call`.
        guard przyjete else {
            log("Sufit \(Self.maxConnections) jednoczesnych połączeń osiągnięty — odrzucam kolejne.")
            connection.start(queue: queue)
            send(.json([
                "error": "Most obsługuje najwyżej \(Self.maxConnections) połączeń naraz. Spróbuj ponownie za chwilę.",
            ], status: 503), on: connection)
            return
        }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.forget(id)
            default:
                break
            }
        }

        connection.start(queue: queue)
        pilnujBezczynnosci(id, znacznik: 0)
        pilnujCzasuZycia(id)
        receive(id)
    }

    private func forget(_ id: ObjectIdentifier) {
        connectionsLock.lock()
        connections.removeValue(forKey: id)
        connectionsLock.unlock()
    }

    /// Ile połączeń most trzyma **w tej chwili**.
    ///
    /// 🔴 Szew dołożony 2026-08-28 z audytu, E2-P2-01. Sufit szesnastu połączeń miał
    /// test, ale nic nie sprawdzało dwóch rzeczy, na których stoi cała pula: czy
    /// słownik **wraca do zera** po zamknięciu połączeń i czy gniazdo wraca do puli
    /// **od razu po odmowie 504**, a nie dopiero po końcu zawieszonego handlera.
    /// Pierwszy wyciek objawiłby się jako „most przestał przyjmować połączenia po
    /// godzinie pracy" — czyli najgorszy z możliwych objawów, bo myli się go z awarią
    /// aplikacji-gospodarza.
    ///
    /// Celowo `internal`, nie `public`: to jest okno do diagnostyki i do testów,
    /// a nie kolejny symbol w binarce RELEASE gospodarza. Czyta pod tym samym zamkiem,
    /// pod którym słownik rośnie i maleje.
    var liczbaOtwartychPolaczen: Int {
        connectionsLock.withLock { connections.count }
    }

    /// Zamyka połączenie, jeśli od zaplanowania tego strażnika nic nie przyszło
    /// i handler nie zaczął pracować.
    private func pilnujBezczynnosci(_ id: ObjectIdentifier, znacznik: Int) {
        zegar.asyncAfter(deadline: .now() + Self.idleTimeoutSeconds) { [weak self] in
            guard let self else { return }

            connectionsLock.lock()
            let state = connections[id]
            let bezczynne = state.map { !$0.wTrakcieObslugi && $0.znacznikRuchu == znacznik } ?? false
            connectionsLock.unlock()

            guard bezczynne, let state else { return }
            self.log("Połączenie milczało \(Int(Self.idleTimeoutSeconds)) s — zamykam.")
            state.connection.cancel()
        }
    }

    /// Zamyka połączenie, które w `maxConnectionLifetimeSeconds` od `accept` nie
    /// zdążyło skompletować żądania.
    ///
    /// Planowany **raz**, przy przyjęciu połączenia — i to jest cała różnica wobec
    /// strażnika bezczynności, który planuje się od nowa przy każdym fragmencie
    /// i przez to daje się odsuwać w nieskończoność jednym bajtem.
    ///
    /// Warunek `!wTrakcieObslugi` jest ten sam, co u tamtego: gdy handler już liczy,
    /// połączenie nie jest zaniedbane, tylko zajęte.
    private func pilnujCzasuZycia(_ id: ObjectIdentifier) {
        zegar.asyncAfter(deadline: .now() + Self.maxConnectionLifetimeSeconds) { [weak self] in
            guard let self else { return }

            let przeterminowane: ConnectionState? = self.connectionsLock.withLock {
                guard let state = self.connections[id], !state.wTrakcieObslugi else { return nil }
                return state
            }

            guard let state = przeterminowane else { return }
            self.log("""
                Połączenie nie skompletowało żądania w \
                \(Int(Self.maxConnectionLifetimeSeconds)) s — zamykam.
                """)
            state.connection.cancel()
        }
    }

    /// Zapisuje, że dla tego połączenia ruszył handler, i nastawia zegar odmowy.
    ///
    /// Wołane dla **obu** rodzajów handlera. Zawieszony handler głównego aktora jest
    /// gorszy od zawieszonego handlera tła, nie lepszy: zabiera razem z mostem także
    /// interfejs aplikacji.
    private func rozpocznijPraceHandlera(
        _ id: ObjectIdentifier,
        metoda: String,
        sciezka: String,
        sufit: Double,
        zrodlo: ZrodloSufitu,
        pisze: Bool
    ) {
        connectionsLock.withLock {
            guard let state = connections[id] else { return }
            state.startHandlera = Date()
            state.metodaZadania = metoda
            state.sciezkaZadania = sciezka
        }
        pilnujCzasuHandlera(id, sufit: sufit, zrodlo: zrodlo, pisze: pisze)
    }

    /// Zwraca `true`, gdy wolno odesłać odpowiedź na to połączenie — i **zużywa**
    /// to prawo, żeby drugi chętny dostał już `false`.
    ///
    /// Brak wpisu w `connections` też znaczy `false`: połączenia nie ma, więc nie ma
    /// komu odpowiadać. Tą drogą idzie handler, który skończył po odmowie 504 —
    /// zegar zdjął wtedy wpis celowo.
    private func przejmijPrawoDoOdpowiedzi(_ id: ObjectIdentifier) -> Bool {
        connectionsLock.withLock {
            guard let state = connections[id], !state.odpowiedziano else { return false }
            state.odpowiedziano = true
            state.startHandlera = nil
            return true
        }
    }

    /// Trzeci strażnik: zamyka sprawę połączenia, którego handler pracuje za długo.
    ///
    /// Różnica wobec dwóch poprzednich jest zasadnicza i warto ją mieć na oku przy
    /// każdej zmianie w tym pliku: tamte pilnują **klienta**, który milczy, ten
    /// pilnuje **nas**. Dlatego jako jedyny nie kończy się samym `cancel()`, tylko
    /// najpierw odsyła odpowiedź z powodem — zerwane gniazdo po drugiej stronie
    /// wygląda identycznie jak padnięta aplikacja, a to jest właśnie ten mylący
    /// obraz, od którego zaczęło się WW-P1-03.
    ///
    /// 🔴 Handler **liczy dalej**. Nie da się go przerwać: to zwykłe domknięcie
    /// aplikacji, w środku dowolny kod, a Swift nie ma bezpiecznego sposobu, żeby
    /// wyrwać wątek z takiej pracy. Zdejmujemy więc wpis połączenia (gniazdo wraca
    /// do puli szesnastu) i odbieramy handlerowi prawo do odpowiedzi, a on kończy
    /// w swoim czasie i jego wynik idzie do kosza.
    private func pilnujCzasuHandlera(_ id: ObjectIdentifier, sufit: Double, zrodlo: ZrodloSufitu, pisze: Bool) {
        zegar.asyncAfter(deadline: .now() + sufit) { [weak self] in
            guard let self else { return }

            let spozniony: (NWConnection, String, String, Date)? = self.connectionsLock.withLock {
                guard let state = self.connections[id],
                      let start = state.startHandlera,
                      !state.odpowiedziano else { return nil }
                state.odpowiedziano = true
                return (state.connection, state.metodaZadania, state.sciezkaZadania, start)
            }
            guard let (connection, metoda, sciezka, start) = spozniony else { return }

            let opis = Self.skroconyOpis(metoda: metoda, sciezka: sciezka)
            let powod = Self.komunikatPrzeterminowanegoHandlera(opis: opis, sekundy: sufit, zrodlo: zrodlo, pisze: pisze)
            self.log("🔴 \(powod)")
            // Numer wpisu zostaje po to, żeby handler — który liczy dalej i którego
            // nie da się przerwać — miał gdzie dopisać, czym naprawdę skończył.
            // Bez tego zdanie „sprawdź stan" w komunikacie 504 jest odesłaniem donikąd
            // (plan rozwoju mostu po 1.2.14, poz. 1).
            let numerWpisu = BridgeActivity.shared.record(
                method: metoda,
                path: sciezka,
                status: 504,
                durationMs: Date().timeIntervalSince(start) * 1000,
                zmienil: pisze
            )
            if let numerWpisu {
                self.connectionsLock.withLock { self.wpisyPoTerminie[id] = numerWpisu }
            }
            self.send(.json(["error": powod], status: 504), on: connection)

            // 🔴 `cancel()` NIE dosyła tego, co czeka w kolejce nadawczej — ucina.
            // Zmierzone 2026-08-28 na tym samym teście gniazdowym: `cancel()` tuż
            // po `send` dawał klientowi **pustą odpowiedź** i zamknięte gniazdo
            // w 1,17 s; ten sam kod ze zwłoką oddaje pełne 504 w 1,10 s. Domknięcie
            // z `send` nas nie uratuje, bo wykonuje się na kolejce sieciowej, czyli
            // na tej zablokowanej — dlatego zamykamy stąd, ale dopiero po zwłoce.
            self.zegar.asyncAfter(deadline: .now() + Self.zwlokaPrzedZamknieciemSekundy) {
                connection.cancel()
            }

            // Gniazdo wraca do puli od razu, nie dopiero po końcu handlera —
            // inaczej szesnaście zawieszonych żądań zabija most na stałe.
            self.forget(id)
        }
    }

    /// Nagłówek, którym klient mówi, **ile czasu ma na odpowiedź**.
    ///
    /// Wartość to liczba milisekund, po których klient sam porzuci żądanie — już
    /// pomniejszona o jego własny margines. Margines liczy strona, która zna swój
    /// limit; most nie odejmuje tu nic po cichu, bo wtedy komunikat 504 nie mógłby
    /// uczciwie podać liczby, według której naprawdę odmówił.
    static let naglowekSufituCzasu = "x-bridge-sufit-czasu-ms"

    /// Czyj sufit zamknął sprawę — bo bez tego komunikat 504 wprowadza w błąd.
    ///
    /// Odmowa po dziewięciu sekundach przy suficie mostu ustawionym na dziewięćdziesiąt
    /// czyta się jak awaria zegara, dopóki nie wiadomo, że liczbę przysłał klient.
    nonisolated enum ZrodloSufitu: Sendable {
        case mostu
        case klienta
    }

    /// Sufit obowiązujący to jedno żądanie: **mniejszy z dwóch**.
    ///
    /// 🔴 Powód istnienia (WW-P1-03, decyzja [U] 2026-08-28 „leć 3"): sufit mostu wynosi
    /// 90 s, a `bridge_call` w kliencie MCP porzucał żądanie po 10 s — więc **agent nigdy
    /// nie widział odmowy 504**, którą most wysyłał. Pełne 504 dawało się zobaczyć
    /// wyłącznie `curl`em i w logu, a agent dostawał gołe „timeout" bez nazwy wiszącego
    /// endpointu i bez zdania o szeregowej kolejce.
    ///
    /// Dwa odrzucone warianty i powód odrzucenia:
    /// - **zejść suficie mostu poniżej 10 s** — legalne `/diff` powyżej ~6,5 Mpx
    ///   przestaje działać dla **wszystkich**, żeby jeden klient zobaczył komunikat,
    /// - **zostawić 90 s** — to jest stan sprzed tej zmiany, czyli sama usterka.
    ///
    /// Wartość niebędąca dodatnią liczbą to **błąd wołającego**, nie brak nagłówka —
    /// ta sama konwencja co w `/text-attributes` (E5-P3-01). Ciche wzięcie własnego
    /// sufitu przy śmieciu w nagłówku odtwarzałoby dokładnie tę usterkę, którą ta
    /// funkcja zamyka: klient czekałby w ciszy, przekonany, że umówił się na krócej.
    nonisolated static func sufitZadania(
        naglowki: [String: String],
        wlasny: Double
    ) throws -> (sufit: Double, zrodlo: ZrodloSufitu) {
        guard let surowa = naglowki[naglowekSufituCzasu]?.trimmingCharacters(in: .whitespaces),
              !surowa.isEmpty else {
            return (wlasny, .mostu)
        }
        guard let ms = Int(surowa), ms > 0 else {
            throw BridgeError.badRequest(
                "Nagłówek \(naglowekSufituCzasu)=\(BridgeDefaults.skrocony(surowa, do: 40)) "
                + "nie jest dodatnią liczbą milisekund. Most nie zgaduje, na ile czasu "
                + "umówił się z nim klient — pomyłka w tę stronę kończy się ciszą po "
                + "stronie wołającego, czyli dokładnie tym, przed czym ten nagłówek chroni. "
                + "Pomiń nagłówek, żeby wziąć sufit mostu (\(Int(wlasny)) s)."
            )
        }
        let zKlienta = Double(ms) / 1000
        return zKlienta < wlasny ? (zKlienta, .klienta) : (wlasny, .mostu)
    }

    /// Odmawia, gdy klient umówił się na krócej, niż trasa PISZĄCA potrafi trwać.
    ///
    /// Statyczna i czysta celowo — ta sama zasada, co przy `zrodloZabronione`
    /// i `komunikatPrzeterminowanegoHandlera`: decyzja „wykonać czy odmówić" ma być
    /// sprawdzalna testem bez stawiania gniazda.
    ///
    /// Sufit mostu (90 s) nigdy tu nie przegrywa, więc odmowa dotyczy wyłącznie liczby
    /// przysłanej przez klienta — i mówi mu wprost, ile ta trasa potrzebuje.
    nonisolated static func sprawdzSufitDlaZapisu(
        _ wykonanie: BridgeExecution,
        sufit: (sufit: Double, zrodlo: ZrodloSufitu)
    ) throws {
        guard wykonanie.czyPisze, sufit.zrodlo == .klienta else { return }

        // 🔴 To sito stoi PRZED handlerem, więc nie zna jeszcze nazwy akcji — a od
        // 1.2.12 każda akcja może mieć własny sufit pomiaru. Dlatego porównuje się tu
        // z **podłogą pomiaru**, a nie z sufitem projektu: poniżej trzech kroków
        // próbkowania żadnej akcji nie da się zmierzyć (warunek stabilności to dwie
        // zgodne próbki z rzędu), więc odmowa jest zawsze słuszna. Dokładne porównanie
        // z sufitem KONKRETNEJ akcji robi `BridgeActions.wykonaj`, też przed wykonaniem.
        //
        // Pierwsza wersja porównywała z sufitem projektu (1500 ms) i odrzucała żądanie
        // na akcję zadeklarowaną jako 800 ms przy budżecie 1000 ms — zmierzone na demie
        // tego samego dnia. Sito było ostrzejsze od potrzeby i kasowało cały zysk
        // z deklaracji gospodarza.
        let podlogaMs = BridgeLimity.krokProbkowaniaMs * 3
        let dostalMs = Int(sufit.sufit * 1000)
        guard dostalMs < podlogaMs else { return }
        throw BridgeError.badRequest(
            "Ta trasa ZMIENIA stan aplikacji i mierzy skutek zmiany, więc nie da się jej "
            + "wykonać w \(dostalMs) ms — sam pomiar potrzebuje co najmniej \(podlogaMs) ms "
            + "(dwie zgodne próbki z rzędu co \(BridgeLimity.krokProbkowaniaMs) ms). "
            + "Most odmawia TERAZ, bo później odmowa byłaby nieuczciwa: akcja zdążyłaby "
            + "się wykonać, a Ty dostałbyś 504 i nie wiedziałbyś, czy stan aplikacji jest "
            + "już zmieniony. Sufit każdej akcji z osobna wymienia GET /akcje."
        )
    }

    /// Treść odmowy `504`.
    ///
    /// Statyczna i czysta celowo — to jedyne zdanie, które w tej usterce widzi
    /// człowiek po drugiej stronie, więc ma być sprawdzalne testem bez stawiania
    /// gniazda (ta sama zasada, co przy `zrodloZabronione`).
    static func komunikatPrzeterminowanegoHandlera(
        opis: String,
        sekundy: Double,
        zrodlo: ZrodloSufitu = .mostu,
        pisze: Bool = false
    ) -> String {
        let skad = zrodlo == .klienta
            ? "Limit przysłał klient nagłówkiem \(naglowekSufituCzasu); sufit samego mostu "
              + "jest wyższy, więc handler liczy dalej i może jeszcze skończyć — tyle że "
              + "jego wynik nie ma już do kogo wrócić. "
            : ""
        // 🔴 Zdanie osobne dla tras, które PISZĄ (E1-P2-02). Dla odczytu „wynik poszedł
        // do kosza" jest całą prawdą — pytanie można powtórzyć za darmo. Dla zapisu
        // brakowało jedynej rzeczy, która tu waży: stan aplikacji JEST już zmieniony,
        // więc ponowienie nie jest powtórzeniem pytania, tylko drugim zapisem.
        let zapis = pisze
            ? "🔴 TA TRASA ZMIENIA STAN APLIKACJI: akcja mogła się już wykonać, mimo że "
              + "nie dostałeś wyniku. Zanim ponowisz, sprawdź stan — ponowienie może być "
              + "drugim zapisem, nie powtórzeniem pytania. "
            : ""
        return "Handler \(opis) pracuje ponad \(Int(sekundy)) s i nie oddał wyniku. "
            + zapis
            + skad
            + "Most nie padł, aplikacja żyje, a inne żądania — łącznie z /ping — są "
            + "obsługiwane normalnie: handlery tła liczą obok kolejki sieciowej. "
            + "Tego handlera nie da się bezpiecznie przerwać, więc policzy do końca, "
            + "tyle że jego wynik pójdzie do kosza. Jeśli ten endpoint ma prawo trwać "
            + "tak długo, przerób go na zlecenie: natychmiastowe potwierdzenie i wynik "
            + "odbierany osobnym żądaniem."
    }

    private func receive(_ id: ObjectIdentifier) {
        connectionsLock.lock()
        let state = connections[id]
        connectionsLock.unlock()
        guard let state else { return }

        state.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            if error != nil {
                state.connection.cancel()
                return
            }

            // Wszystko, co dotyka `state`, pod jednym zamknięciem zamka — łącznie
            // z rozmiarem bufora. Czytanie `state.buffer.count` osobno, już po
            // zwolnieniu zamka, byłoby wyścigiem.
            //
            // Parsowanie też jest pod zamkiem, ale bufora NIE kopiuje: `parse`
            // dostaje `Data` przez wartość, czyli tylko dokłada referencję, a nic
            // w trakcie nie mutuje. Kopia przy zapisie zdarza się dopiero przy
            // zmianie, a ta jest wyżej, przed parsowaniem.
            let (znacznik, wynik, rozmiarBufora) = self.connectionsLock.withLock {
                () -> (Int, HTTPRequestParser.Result, Int) in
                if let chunk, !chunk.isEmpty { state.buffer.append(chunk) }
                state.znacznikRuchu += 1
                return (state.znacznikRuchu, HTTPRequestParser.parse(state.buffer), state.buffer.count)
            }

            switch wynik {
            case .incomplete:
                if isComplete {
                    state.connection.cancel()
                } else if rozmiarBufora > HTTPRequestParser.maxBodyLength {
                    self.zapiszOdrzucone(id, status: 413)
                    self.send(.text("Żądanie za duże", status: 413), on: state.connection)
                } else {
                    self.pilnujBezczynnosci(id, znacznik: znacznik)
                    self.receive(id)
                }

            case .invalid(let reason):
                self.zapiszOdrzucone(id, status: 400)
                self.send(.json(["error": reason], status: 400), on: state.connection)

            case .unsupported(let reason):
                self.zapiszOdrzucone(id, status: 501)
                self.send(.json(["error": reason], status: 501), on: state.connection)

            case .complete(let request):
                self.connectionsLock.withLock { state.wTrakcieObslugi = true }
                self.handle(request, on: state.connection)
            }
        }
    }

    /// Nagłówki, których sama obecność znaczy „to żądanie zbudowała przeglądarka".
    ///
    /// Prawowity klient mostu nie wysyła żadnego z nich: `fetch` w `mcp-server`
    /// (Node, `undici`) ani `curl` z ręki. Zmierzone 2026-08-10 na surowych bajtach
    /// w czterech wariantach — GET, POST z ciałem, POST bez ciała, `/screenshot` —
    /// przy kontroli dodatniej curlem, który na żądanie potrafi je dosłać.
    ///
    /// Przeglądarka wysyła `origin` przy każdym żądaniu z obcego origin i przy każdym
    /// `POST`, a `sec-fetch-site` **przy wszystkich** — także z tej samej strony.
    /// Drugi nagłówek jest tu po to, żeby zwykły `GET` z lokalnej strony też nie
    /// przeszedł. Świadomie **nie** ma tu `sec-fetch-mode`: to jedyny z tej rodziny,
    /// który dokłada również `undici` — sito na nim zerwałoby most.
    static let naglowkiPrzegladarki = ["origin", "sec-fetch-site"]

    /// Zwraca nazwę nagłówka, przez który żądanie zostaje odrzucone — albo `nil`,
    /// gdy nic nie wskazuje na przeglądarkę.
    ///
    /// Statyczna i bez `private` celowo: to jedyne miejsce, w którym zapada decyzja
    /// „wykonać czy odrzucić", więc ma być sprawdzalne testem bez stawiania gniazda.
    static func zrodloZabronione(_ request: BridgeRequest) -> String? {
        naglowkiPrzegladarki.first { request.headers[$0] != nil }
    }

    /// Metoda i ścieżka w postaci nadającej się do komunikatu — obie **skrócone**.
    ///
    /// 🔴 Powód (audyt 2026-08-29, E2N-P2-02): odmowa „Nieznany endpoint" wklejała
    /// `request.path` bez skracania i odbijała cudze wejście 1:1. Zmierzone na demie:
    /// ścieżka 1 000 000 B → odpowiedź 1 000 451 B. Wystarczy do tego nieznana
    /// ścieżka, czyli najłatwiejsza rzecz, jaką da się wysłać.
    ///
    /// Konwencja „cudze wejście w komunikacie skraca się" istniała w projekcie już
    /// dwa razy — `BridgeDefaults.skrocony` i `BridgeActivity.maxPathLength = 60`,
    /// to drugie znalezione 2026-08-09 przy ostrzale innym gospodarzu ścieżką o 8000 znakach.
    /// Stosowana była wszędzie **poza** tą jedną odmową. Ten pomocnik jest po to, żeby
    /// następne miejsce nie musiało jej odkrywać po raz czwarty.
    ///
    /// Limit ścieżki ten sam co w historii (60), żeby wpis w panelu i treść odmowy
    /// mówiły o tym samym. Metoda idzie osobno i krócej: przychodzi z pierwszej linii
    /// żądania i jest cudzym napisem dokładnie tak samo jak ścieżka.
    static func skroconyOpis(metoda: String, sciezka: String) -> String {
        "\(BridgeDefaults.skrocony(metoda, do: 20)) \(BridgeDefaults.skrocony(sciezka))"
    }

    /// Ta sama rzecz dla gotowego żądania. Dwie wersje, bo odmowa 504 powstaje na
    /// zegarze, gdzie `BridgeRequest` już nie żyje — zostały z niego dwa napisy
    /// w `ConnectionState`, i one też są cudzym wejściem.
    static func skroconyOpis(_ request: BridgeRequest) -> String {
        skroconyOpis(metoda: request.method, sciezka: request.path)
    }

    /// Zapisuje w historii żądanie **odrzucone przez parser** — zanim powstał
    /// `BridgeRequest`, więc metody i ścieżki nie zna nikt poza surowym buforem.
    ///
    /// Do 2026-08-10 takie żądania nie zostawiały żadnego śladu: nie ruszały licznika,
    /// nie trafiały do panelu w pasku menu, nie szły do logu. Panel jest reklamowany
    /// jako dowód, że most żyje — przy ostrzale nie drgnął ani razu (zmierzone:
    /// 10 × 400 → licznik bez zmian). Ślad po próbie nadużycia jest wart więcej niż
    /// ślad po udanym pytaniu. Audyt 2026-08-10, E2-P2-01.
    ///
    /// Wpis liczy się jako błąd (`status >= 400`), więc trafia do osobnego licznika
    /// `BridgeActivity.errors` i pokazuje się w panelu na czerwono.
    private func zapiszOdrzucone(_ id: ObjectIdentifier, status: Int) {
        let (metoda, sciezka) = pierwszaLinia(id)
        log("Odrzucone żądanie: \(metoda) \(sciezka) → \(status)")
        BridgeActivity.shared.record(method: metoda, path: sciezka, status: status, durationMs: 0)
    }

    /// Wyciąga metodę i ścieżkę z pierwszej linii surowego bufora — na tyle, na ile
    /// się da. Żądanie jest z definicji popsute, więc to jest opis dla człowieka
    /// patrzącego w panel, a nie parsowanie.
    private func pierwszaLinia(_ id: ObjectIdentifier) -> (String, String) {
        let bufor = connectionsLock.withLock { connections[id]?.buffer }
        guard let bufor, !bufor.isEmpty else { return ("?", "(puste żądanie)") }

        // Sam początek bufora: dłuższy fragment nic tu nie doda, a przy 8 MB ciała
        // kosztowałby przepisanie całości do napisu.
        let poczatek = bufor.prefix(200)
        guard let tekst = String(data: poczatek, encoding: .utf8) else {
            return ("?", "(żądanie nie jest tekstem)")
        }

        let linia = tekst.split(separator: "\r\n", maxSplits: 1).first
            ?? tekst.split(separator: "\n", maxSplits: 1).first
            ?? ""
        let czesci = linia.split(separator: " ")
        guard czesci.count >= 2 else { return ("?", "(nieczytelna pierwsza linia)") }
        return (String(czesci[0]), String(czesci[1]))
    }

    private func handle(_ request: BridgeRequest, on connection: NWConnection) {
        // Sito PRZED wyszukaniem trasy: żądanie z przeglądarki nie ma prawa dotknąć
        // handlera aplikacji, nawet takiego, który tylko czyta.
        //
        // Dlaczego to wystarcza: przeglądarka blokuje odczyt odpowiedzi z obcego
        // origin, ale nie blokuje jej wysłania — żądania proste (`GET`, `POST`
        // z `text/plain`) lecą bez preflightu i most je dotąd wykonywał. Cała obrona
        // CORS opiera się na tym, że serwer sam takie żądanie odrzuci. Zmierzone
        // w prawdziwej przeglądarce przeciw własnemu demu: licznik aplikacji
        // 2 → 8, `POST /echo ✓ 200`. Audyt 2026-08-10, E3a-P0-01.
        if let naglowek = Self.zrodloZabronione(request) {
            // 🔴 Wartość nagłówka to cudze wejście i do 2026-09-02 szła do logu
            // BEZ skracania: `Origin` o 200 000 znaków dawał wiersz 196 420 znaków
            // (audyt 2026-09-02, E2-P2-01, druga połowa). Nazwa nagłówka też —
            // przychodzi z tego samego żądania.
            let wartosc = BridgeDefaults.skrocony(request.headers[naglowek] ?? "", do: 80)
            log("""
                Odrzucone: \(Self.skroconyOpis(request)) niesie nagłówek \
                \(BridgeDefaults.skrocony(naglowek, do: 40)): \(wartosc) \
                — takie żądanie buduje przeglądarka, nie most.
                """)
            BridgeActivity.shared.record(
                method: request.method,
                path: request.path,
                status: 403,
                durationMs: 0
            )
            send(.json([
                "error": """
                    Most przyjmuje żądania wyłącznie od własnego klienta. \
                    Żądanie niosące nagłówek \(naglowek) pochodzi z przeglądarki \
                    i nie zostanie wykonane.
                    """,
            ], status: 403), on: connection)
            return
        }

        guard let route = BridgeRegistry.shared.route(method: request.method, path: request.path) else {
            let known = BridgeRegistry.shared.allRoutes().map { "\($0.method) \($0.path)" }
            BridgeActivity.shared.record(
                method: request.method,
                path: request.path,
                status: 404,
                durationMs: 0
            )
            send(.json([
                "error": "Nieznany endpoint: \(Self.skroconyOpis(request))",
                "available": known,
            ], status: 404), on: connection)
            return
        }

        // Sufit czasu dla TEGO żądania — mniejszy z sufitu mostu i limitu przysłanego
        // przez klienta. Liczony PRZED startem handlera, bo po jego starcie zegar jest
        // już nastawiony i zmiana liczby niczego by nie cofnęła.
        let sufitZadania: (sufit: Double, zrodlo: ZrodloSufitu)
        do {
            sufitZadania = try Self.sufitZadania(naglowki: request.headers, wlasny: maksCzasHandlera)
            // 🔴 Trasa, która PISZE, nie przyjmuje sufitu krótszego, niż sama potrafi
            // (E1-P2-02). Odmowa idzie tutaj, ZANIM cokolwiek ruszy stan gospodarza —
            // to jedyny moment, w którym odmowa jeszcze nic nie kosztuje. Zmierzone
            // przed naprawą: `x-bridge-sufit-czasu-ms: 50` → 504, a tytuł okna
            // ZMIENIONY, czyli akcja wykonana i klient o tym nie wie.
            //
            // Decyzja [U] 2026-09-02 („kolejka") pogarsza to samo z drugiej strony:
            // akcja czekająca na cudzą zjada czas z tego samego sufitu, więc okno
            // „504 mimo wykonanej akcji" robi się szersze, nie węższe.
            try Self.sprawdzSufitDlaZapisu(route.execution, sufit: sufitZadania)
        } catch {
            let powod = (error as? BridgeError)?.errorDescription ?? "\(error)"
            BridgeActivity.shared.record(
                method: request.method,
                path: request.path,
                status: 400,
                durationMs: 0
            )
            send(.json(["error": powod], status: 400), on: connection)
            return
        }

        let id = ObjectIdentifier(connection)

        let dokoncz: @Sendable (BridgeResponse, Date) -> Void = { [weak self] response, start in
            guard let self else { return }
            // Odpowiedź nie wie, kto ją zbudował — nazwę endpointu można dopisać
            // tylko tutaj. Bez tego log mówi „coś zwróciło NaN", a szuka się długo.
            if let failure = response.serializationFailure {
                self.log("Endpoint \(Self.skroconyOpis(request)) zwrócił dane nie do zapisania w JSON: \(failure)")
            }

            // Prawo do odpowiedzi zużywa się raz — patrz `przejmijPrawoDoOdpowiedzi`.
            // Gdy zegar zdążył wcześniej, wynik nie jedzie nigdzie: klient dostał już
            // 504 i zamknięte gniazdo, a dopisanie tu drugiego wpisu do licznika
            // ruchu pokazywałoby to samo żądanie dwa razy, z dwoma różnymi kodami.
            guard self.przejmijPrawoDoOdpowiedzi(id) else {
                self.log("""
                    Endpoint \(Self.skroconyOpis(request)) skończył po \
                    \(Int(Date().timeIntervalSince(start))) s, czyli po terminie — \
                    wynik idzie do kosza, klient dostał 504.
                    """)
                // Do kosza idzie **odpowiedź**, nie wiedza o niej. Wpis 504 dostaje
                // dopisek: jakim kodem to się skończyło i co się zmieniło — czyli to,
                // po co agent sięga do `GET /historia` po odmowie z terminu.
                let numer = self.connectionsLock.withLock { self.wpisyPoTerminie.removeValue(forKey: id) }
                BridgeActivity.shared.domknij(
                    numer,
                    status: response.status,
                    durationMs: Date().timeIntervalSince(start) * 1000,
                    slad: response.slad
                )
                return
            }

            // Ślad zna wyłącznie handler — serwer go tylko przepisuje. Przy odczycie
            // jest `nil` i wpis wygląda dokładnie jak przed 1.2.15.
            BridgeActivity.shared.record(
                method: request.method,
                path: request.path,
                status: response.status,
                durationMs: Date().timeIntervalSince(start) * 1000,
                zmienil: route.execution.czyPisze,
                slad: response.slad
            )
            self.send(response, on: connection)
        }

        // Zegar rusza PRZED handlerem i obejmuje oba rodzaje — także czekanie
        // w kolejce głównego aktora, bo klient po drugiej stronie i tak mierzy
        // od swojego żądania, a nie od chwili, w której handler dostał procesor.
        rozpocznijPraceHandlera(id, metoda: request.method, sciezka: request.path,
                                sufit: sufitZadania.sufit, zrodlo: sufitZadania.zrodlo,
                                pisze: route.execution.czyPisze)

        switch route.execution {
        case .onMainActor(let handler):
            _Concurrency.Task { @MainActor in
                let start = Date()
                dokoncz(Self.wynik { try handler(request) }, start)
            }

        case .akcjaNaGlownymAktorze(let handler):
            // Ta sama droga co `.onMainActor` — różnica jest jedna: `await`.
            // Warstwa akcji czeka w niej na ustabilizowanie sondy gospodarza,
            // więc zadanie żyje dłużej niż samo wywołanie handlera.
            _Concurrency.Task { @MainActor in
                let start = Date()
                dokoncz(await Self.wynikAsync { try await handler(request) }, start)
            }

        case .inBackground(let handler):
            // 🔴 `robocza.async`, nie wykonanie wprost: handler tła policzony tutaj,
            // na kolejce sieciowej, zatrzymuje ODBIÓR wszystkich innych połączeń.
            // To jest cała naprawa WW-P1-03 — patrz komentarz przy `robocza`.
            robocza.async {
                let start = Date()
                dokoncz(Self.wynik { try handler(request) }, start)
            }
        }
    }

    /// Wspólna zamiana rzuconego błędu na odpowiedź HTTP — jedna dla obu rodzajów
    /// handlera, żeby komunikaty nie rozjechały się między ścieżkami.
    ///
    /// Domknięcie jest nieuciekające, więc dziedziczy izolację miejsca wywołania —
    /// ta sama funkcja obsługuje handler głównego aktora i handler tła.
    /// Asynchroniczny bliźniak `wynik(_:)` — ta sama zamiana błędu na odpowiedź.
    ///
    /// Osobna funkcja, a nie `async` przy tamtej: tamtą wołają dwie gałęzie
    /// synchroniczne i przerobienie jej na `async` zmusiłoby je do `await` po nic.
    /// `@MainActor`, bo woła ją wyłącznie gałąź akcji, która i tak jest na głównym
    /// aktorze — bez tego domknięcie przekraczałoby granicę izolacji i tryb języka
    /// Swift 6 słusznie odmawia („sending value of non-Sendable type").
    @MainActor
    private static func wynikAsync(
        _ body: @MainActor () async throws -> BridgeResponse
    ) async -> BridgeResponse {
        do {
            return try await body()
        } catch let error as BridgeError {
            return .json(["error": error.localizedDescription], status: error.httpStatus)
        } catch {
            return .json(["error": error.localizedDescription], status: 500)
        }
    }

    private static func wynik(_ body: () throws -> BridgeResponse) -> BridgeResponse {
        do {
            return try body()
        } catch let error as BridgeError {
            return .json(["error": error.localizedDescription], status: error.httpStatus)
        } catch {
            return .json(["error": error.localizedDescription], status: 500)
        }
    }

    private func send(_ response: BridgeResponse, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(for: response.status))\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        // Nagłówki własne endpointu. Kolejność ustalona (posortowana), żeby dwa
        // przebiegi tego samego żądania dawały bajt w bajt tę samą odpowiedź —
        // inaczej `/diff` na dwóch zrzutach odpowiedzi pokazywałby różnicę tam,
        // gdzie zmieniła się wyłącznie kolejność w słowniku.
        for nazwa in response.headers.keys.sorted() {
            head += "\(nazwa): \(response.headers[nazwa] ?? "")\r\n"
        }
        head += "Connection: close\r\n\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Opis kodu HTTP. Dziś most używa tylko kodów z listy, ale gdyby aplikacja
    /// zwróciła własny, klient dostanie poprawną nazwę zamiast słowa „Status",
    /// które w logach wygląda na błąd implementacji (P3-04).
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default:
            // Nazwa wg klasy kodu — poprawna dla wszystkiego, czego nie ma wyżej.
            switch status / 100 {
            case 1: return "Informational"
            case 2: return "Success"
            case 3: return "Redirection"
            case 4: return "Client Error"
            case 5: return "Server Error"
            default: return "Unknown"
            }
        }
    }

    private func log(_ message: String) {
        print("[AppBridge] \(message)")
        Self.logger.debug("\(message, privacy: .public)")
    }

    /// Awaria startu mostu — musi być widoczna także wtedy, gdy aplikacja
    /// nie została uruchomiona z Xcode.
    ///
    /// Wcześniej leciał sam `print`, którego nikt poza Xcode nie zobaczy, a ikonka
    /// w pasku menu **w ogóle nie powstawała**, bo instalowała się dopiero w stanie
    /// `.ready`. Użytkownik widział brak ikonki i brak komunikatu — czyli to samo,
    /// co przy „zapomniałem wystartować most". Audyt 2026-08-02, P2-05.
    ///
    /// Teraz idą trzy drogi naraz: `print` (terminal), `Logger` na poziomie błędu
    /// (Console.app, `log stream --predicate 'subsystem == "AppBridgeKit"'`)
    /// oraz ikonka, która pokazuje przekreśloną antenę i powód w podpowiedzi.
    private func report(failure message: String) {
        print("[AppBridge] ⚠️ \(message)")
        Self.logger.error("\(message, privacy: .public)")
        #if canImport(AppKit)
        BridgeStatusIcon.markFailed(reason: message)
        #endif
    }

    private static let logger = os.Logger(subsystem: "AppBridgeKit", category: "most")

    #endif

    /// Wersja mostu raportowana przez `/ping`.
    ///
    /// 🔴 Trzymać zgodnie z `mcp-server/package.json`. Serwer MCP sam porównuje obie
    /// przy każdym `/ping` i krzyczy w logu, gdy się rozjadą — bo Swift i Node nie
    /// mają wspólnego miejsca, z którego mogłyby to czytać (P3-02).
    public static let version = "1.2.20"
}

// MARK: - Minimalny parser HTTP

#if DEBUG
nonisolated enum HTTPRequestParser {

    enum Result {
        case incomplete
        case invalid(String)
        /// Żądanie jest poprawne wg specyfikacji, ale most nie umie go obsłużyć —
        /// odpowiedź 501, nie 400. Rozróżnienie jest tu z tego samego powodu, dla
        /// którego brak okna gospodarza to 404, a nie 500: kod odpowiedzi ma mówić,
        /// po czyjej stronie jest rzecz. `Transfer-Encoding: chunked` jest legalny
        /// w HTTP/1.1 — to most go nie implementuje.
        case unsupported(String)
        case complete(BridgeRequest)
    }

    /// Górny limit ciała żądania. Ten sam próg, którym `BridgeServer.receive`
    /// ogranicza bufor — trzymany w jednym miejscu, żeby obie strony nie
    /// rozjechały się przy pierwszej zmianie.
    static let maxBodyLength = 8 * 1024 * 1024

    static func parse(_ buffer: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            // Klient, który zakończył nagłówki samym `LF LF`, nie doczeka się nigdy
            // separatora `CRLF CRLF` — przed 2026-08-10 takie połączenie **wisiało
            // w ciszy** aż do strażnika bezczynności, zamiast dostać odpowiedź.
            // Milczenie jest tu gorsze od odmowy: wygląda jak zawieszony most.
            // Audyt 2026-08-10, E2-P3-03 (3).
            if buffer.range(of: Data("\n\n".utf8)) != nil {
                return .invalid("Nagłówki muszą kończyć się CRLF CRLF, a nie samym LF LF")
            }
            return .incomplete
        }

        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Nagłówki nie są poprawnym UTF-8")
        }

        // Bez `guard !lines.isEmpty` — `components(separatedBy:)` zwraca zawsze co
        // najmniej jeden element, także dla napisu pustego (`[""]`), więc ta gałąź
        // była nieosiągalna. Puste żądanie odsiewa strażnik pierwszej linii niżej
        // (zmierzone: `\r\n\r\n` → „Nieprawidłowa pierwsza linia żądania").
        // Audyt 2026-08-10, E2-P3-01.
        var lines = headerText.components(separatedBy: "\r\n")

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid("Nieprawidłowa pierwsza linia żądania") }

        let method = String(requestLine[0]).uppercased()
        let target = zdejmijPostacAbsolutna(String(requestLine[1]))

        var headers: [String: String] = [:]
        for line in lines {
            // Linia bez dwukropka nie jest nagłówkiem. RFC każe takie żądanie
            // odrzucić; przed 2026-08-10 znikała po cichu (`continue`), więc literówka
            // w nazwie nagłówka wyglądała jak jego brak. Audyt, E2-P3-03 (4).
            guard let colon = line.firstIndex(of: ":") else {
                return .invalid("Linia nagłówka bez dwukropka: \"\(line)\"")
            }
            // 🔴 Nazwę sprawdzamy PRZED przycięciem. `trimmingCharacters` zdejmuje
            // spację, więc `"Host "` stawało się `"host"` i żądanie przechodziło
            // z kodem 200 — a RFC 7230 §3.2.4 każe takie odrzucić. Dziś nie boli:
            // most stoi na pętli lokalnej, bez pośrednika, a jedynym klientem jest
            // `mcp-server`, który buduje nagłówki przez `fetch` i spacji nie wyśle.
            // Zaczyna boleć w dniu, w którym cokolwiek stanie przed mostem — bo wtedy
            // dwie strony mogą policzyć nagłówki inaczej, a rozbieżność w interpretacji
            // nagłówków to jest cała mechanika przemytu żądań.
            // Audyt 2026-08-28, E2-P3-01.
            let surowaNazwa = line[line.startIndex..<colon]
            if surowaNazwa.last?.isWhitespace == true {
                return .invalid(
                    "Spacja między nazwą nagłówka a dwukropkiem: \"\(surowaNazwa)\". "
                    + "RFC 7230 §3.2.4 każe takie żądanie odrzucić — dwie strony potrafią "
                    + "policzyć taki nagłówek inaczej."
                )
            }
            let name = surowaNazwa.trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            // Powtórzony nagłówek odrzucamy zamiast nadpisywać. Przy dwóch
            // `Content-Length` (`3` i `100`) wygrywał ostatni i żądanie czekało na
            // 100 bajtów — RFC nakazuje tu odmowę, bo rozbieżność jest dokładnie tym,
            // na czym stoi przemyt żądań. Audyt, E2-P3-03 (1).
            if headers[name] != nil {
                return .invalid("Nagłówek \"\(name)\" powtórzony — żądanie odrzucone")
            }
            headers[name] = value
        }

        // 🔴 `Transfer-Encoding` odrzucamy, zamiast czytać żądanie jako puste.
        //
        // Parser nie zna kodowania porcjowego i nigdy go nie znał: bez `Content-Length`
        // `expectedLength` wychodziło 0, więc żądanie było **kompletne z pustym ciałem**,
        // a dane w chunkach zostawały w buforze i przepadały. Zmierzone 2026-08-29 na
        // żywym demie, surowym gniazdem, z kontrolą dodatnią w tym samym przebiegu:
        // to samo ciało przez `Content-Length` wracało poprawnie, przez chunked znikało,
        // oba razy z kodem **200**. Handler aplikacji dostawał puste ciało zamiast
        // prawdziwego i potwierdzał operację, której dane nigdy nie dojechały.
        //
        // Dwa przypadki, dwa kody — RFC 7230 §3.3.3:
        //   • `Transfer-Encoding` **i** `Content-Length` naraz to rozbieżność ramkowania,
        //     czyli ta sama rodzina co dwa `Content-Length` wyżej: **400**. Do dziś taka
        //     para dawała 400 z powodu, który kłamał („ciało nie jest poprawnym JSON-em" —
        //     parser brał bajty ramkowania chunków za treść),
        //   • samo `Transfer-Encoding` to żądanie legalne, którego most nie umie
        //     zdekodować: **501**, bo rzecz jest po stronie mostu, nie klienta.
        //
        // Dziś ta droga jest zamknięta po stronie klienta — `mcp-server` buduje ciało
        // przez `JSON.stringify`, czyli napis o znanej długości, a `undici` wysyła wtedy
        // `Content-Length`. To jest dokładnie to samo zdanie co przy spacji przed
        // dwukropkiem: zaczyna boleć w dniu, w którym cokolwiek stanie przed mostem.
        // Audyt 2026-08-29, E2N-P2-01.
        if let kodowanie = headers["transfer-encoding"] {
            if headers["content-length"] != nil {
                return .invalid(
                    "Transfer-Encoding i Content-Length w jednym żądaniu "
                    + "(\"\(BridgeDefaults.skrocony(kodowanie, do: 40))\"). RFC 7230 §3.3.3 "
                    + "każe takie żądanie odrzucić — dwie strony potrafią policzyć granicę "
                    + "ciała inaczej, a na tej rozbieżności stoi przemyt żądań."
                )
            }
            return .unsupported(
                "Most nie obsługuje Transfer-Encoding "
                + "(\"\(BridgeDefaults.skrocony(kodowanie, do: 40))\") — ciało żądania musi "
                + "być zapowiedziane nagłówkiem Content-Length. Odmawiam zamiast czytać "
                + "żądanie jako puste: puste ciało wyglądałoby jak udana operacja bez danych."
            )
        }

        // Deklarowaną długość trzeba odsiać ZANIM trafi do indeksowania bufora.
        //
        // `Int("-1")` zwraca -1, a nie nil, więc wartość ujemna przechodziła dalej:
        // strażnik `availableBody >= expectedLength` jest dla niej zawsze prawdziwy,
        // a `index(bodyStart, offsetBy: -1)` cofa indeks przed początek ciała i tworzy
        // zakres `lowerBound > upperBound`. To pułapka wykonania, nie rzucony błąd —
        // nie łapie jej żaden `catch`, ginie cały proces aplikacji-gospodarza.
        // Audyt 2026-08-02, P0-01.
        let expectedLength: Int
        if let declared = headers["content-length"] {
            // `Int("+5")` zwraca 5, nie `nil` — a RFC dopuszcza tu wyłącznie cyfry.
            // Stąd sprawdzenie zbioru znaków **przed** konwersją, a nie po niej;
            // sama konwersja jest zbyt liberalna. Audyt 2026-08-10, E2-P3-03 (2).
            guard !declared.isEmpty, declared.allSatisfy(\.isNumber) else {
                return .invalid("Nagłówek Content-Length musi być liczbą nieujemną, a jest: \"\(declared)\"")
            }
            guard let value = Int(declared), value >= 0 else {
                return .invalid("Nagłówek Content-Length musi być liczbą nieujemną, a jest: \"\(declared)\"")
            }
            guard value <= maxBodyLength else {
                return .invalid("Zadeklarowane ciało \(value) B przekracza limit \(maxBodyLength) B")
            }
            expectedLength = value
        } else {
            expectedLength = 0
        }

        let bodyStart = headerEnd.upperBound
        let availableBody = buffer.count - buffer.distance(from: buffer.startIndex, to: bodyStart)
        guard availableBody >= expectedLength else { return .incomplete }

        let bodyEnd = buffer.index(bodyStart, offsetBy: expectedLength)
        let body = Data(buffer[bodyStart..<bodyEnd])

        let (path, query) = splitTarget(target)
        // Nagłówki jadą dalej w całości. Do 2026-08-10 ten słownik kończył życie
        // w tej funkcji — po `content-length` nikt już do niego nie zaglądał, więc
        // ani most, ani aplikacja nie miały jak sprawdzić, kto wysłał żądanie.
        return .complete(BridgeRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: body
        ))
    }

    /// Zamienia postać absolutną celu (`GET http://127.0.0.1:8765/ping`) na samą
    /// ścieżkę. RFC 7230 wymaga, żeby serwer ją przyjmował; przed 2026-08-10 cały
    /// adres szedł do routingu i dawał 404 na endpoincie, który istnieje.
    /// Audyt 2026-08-10, E2-P3-03 (5).
    private static func zdejmijPostacAbsolutna(_ target: String) -> String {
        guard let zakres = target.range(of: "://") else { return target }
        let poSchemacie = target[zakres.upperBound...]
        // Pierwszy ukośnik po nazwie hosta zaczyna ścieżkę. Gdy go nie ma
        // (`http://127.0.0.1:8765`), celem jest korzeń.
        guard let ukosnik = poSchemacie.firstIndex(of: "/") else { return "/" }
        return String(poSchemacie[ukosnik...])
    }

    private static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let questionMark = target.firstIndex(of: "?") else {
            return (decode(target), [:])
        }

        let path = decode(String(target[target.startIndex..<questionMark]))
        let rawQuery = String(target[target.index(after: questionMark)...])

        var query: [String: String] = [:]
        for pair in rawQuery.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first, !name.isEmpty else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            query[decode(String(name))] = decode(value.replacingOccurrences(of: "+", with: " "))
        }
        return (path, query)
    }

    private static func decode(_ string: String) -> String {
        string.removingPercentEncoding ?? string
    }
}
#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeStatusItem.swift
// ────────────────────────────────────────────────────────────────────────


#if DEBUG && canImport(AppKit)

/// Nieizolowana fasada ikonki.
///
/// Most woła te metody z kolejki sieciowej, a cała reszta pliku żyje na głównym
/// aktorze. Przeskok jest tutaj, w jednym miejscu — dzięki temu `BridgeStatusItem`
/// nie musi w każdej metodzie pamiętać o `DispatchQueue.main.async`, a kompilator
/// pilnuje, że nikt nie sięgnie po AppKit z niewłaściwej strony.
nonisolated enum BridgeStatusIcon {
    static func install(appName: String, port: UInt16) {
        _Concurrency.Task { @MainActor in BridgeStatusItem.shared.install(appName: appName, port: port) }
    }

    /// - Parameter port: port **faktyczny**. Przy instalacji ikonka dostaje port
    ///   ŻĄDANY, a te dwa mogą się różnić — `port=0` znaczy „przydziel dowolny wolny",
    ///   i wtedy menu pokazywałoby `127.0.0.1:0`, czyli adres, pod który nikt nie wejdzie.
    static func markReady(port: UInt16) {
        _Concurrency.Task { @MainActor in BridgeStatusItem.shared.markReady(port: port) }
    }

    static func markFailed(reason: String) {
        _Concurrency.Task { @MainActor in BridgeStatusItem.shared.markFailed(reason: reason) }
    }

    static func remove() {
        _Concurrency.Task { @MainActor in BridgeStatusItem.shared.remove() }
    }

    /// PNG własnego przycisku w pasku menu — patrz `BridgeStatusItem.podglad`.
    ///
    /// Bez przeskoku przez `Task`, w odróżnieniu od reszty tej fasady: woła to handler,
    /// który **już jest** na głównym aktorze (`registerOnMainActor`) i musi dostać
    /// wynik, a nie obietnicę. Tamte cztery są poleceniami bez odpowiedzi i dlatego
    /// mogą polecieć w tle.
    /// - Parameter naCiemnym: `nil` znaczy „weź wygląd systemu" — jedyny wariant,
    ///   w którym obrazek pokazuje to, co użytkownik naprawdę widzi.
    @MainActor
    static func podglad(naCiemnym: Bool?) throws -> (Data, [String: String]) {
        try BridgeStatusItem.shared.podglad(naCiemnym: naCiemnym)
    }
}

/// Ikonka w pasku menu (górny prawy róg ekranu) pokazująca stan mostu.
///
/// Widać po niej trzy rzeczy: czy most stoi, ile pytań przyszło od Claude Code
/// i co dokładnie było pytane. Ikonka to plik [U] (patrz `BridgeIkona`); przy każdym
/// pytaniu zapala się w niej **ramka**, na pomarańczowo `#D97706`, a młotek zostaje
/// w barwie paska — więc od razu widać, że coś się dzieje. Gdy most **nie wstał**, ikonka też jest — cała czerwona,
/// z powodem w podpowiedzi (audyt 2026-08-02, P2-05).
///
/// Cały plik jest pod `#if DEBUG` — w wersji dla użytkowników nie istnieje.
@MainActor
final class BridgeStatusItem: NSObject, NSMenuDelegate {

    fileprivate static let shared = BridgeStatusItem()

    private var statusItem: NSStatusItem?
    private var appName = "app"
    private var port: UInt16 = 0
    private var resetTimer: Foundation.Timer?
    /// Powód nieudanego startu — pokazywany w podpowiedzi i w menu.
    private var powodAwarii: String?

    /// Czy ikonka **w tej chwili** mruga. Zapisywane przy każdym przerysowaniu,
    /// bo `podglad` musi powiedzieć, który z trzech stanów sfotografował — a z samej
    /// bitmapy tego nie widać (audyt 1.2.15–1.2.18, P1-01).
    private var mrugaTeraz = false

    private override init() { super.init() }

    /// Czy to okno jest oknem **naszej** ikonki w pasku menu.
    ///
    /// 🔴 Rozstrzyga tożsamość obiektu, nie nazwa klasy. Gdy most chodzi
    /// z `showMenuBarIcon: false`, `statusItem` jest `nil` i odpowiedź brzmi `false`
    /// dla każdego okna — łącznie z oknami paska menu GOSPODARZA, które są wtedy
    /// jego interfejsem, a nie naszym przyrządem (pozycja 4a, 2026-08-29).
    static func toOknoIkonkiMostu(_ okno: NSWindow) -> Bool {
        guard let nasze = shared.statusItem?.button?.window else { return false }
        return nasze === okno
    }

    // MARK: - Instalacja

    /// Wołane **przy próbie startu**, a nie po jego powodzeniu.
    ///
    /// Wcześniej ikonka powstawała dopiero w stanie `.ready`, więc zajęty port
    /// dawał brak ikonki i brak komunikatu — nie do odróżnienia od „zapomniałem
    /// wystartować most".
    fileprivate func install(appName: String, port: UInt16) {
        self.appName = appName
        self.port = port

        guard statusItem == nil else {
            refreshIcon(active: false)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        refreshIcon(active: false)

        BridgeActivity.shared.setOnChange { _ in
            // `record` woła to z tego miejsca, w którym skończył się handler:
            // dla tras `registerInBackground` z kolejki sieciowej, dla
            // `registerOnMainActor` **z głównego aktora**. Przeskok robimy tu i jest
            // poprawny w obu przypadkach — `Task { @MainActor }` z głównego aktora
            // po prostu nic nie przenosi. (Poprzedni komentarz twierdził, że
            // wywołanie leci zawsze z kolejki sieciowej; audyt 2026-08-10, E2-P3-02.)
            _Concurrency.Task { @MainActor in BridgeStatusItem.shared.flash() }
        }
    }

    fileprivate func markReady(port: UInt16) {
        self.port = port
        powodAwarii = nil
        refreshIcon(active: false)
    }

    /// Most nie wstał. Ikonka zostaje na ekranie i **mówi dlaczego**.
    fileprivate func markFailed(reason: String) {
        powodAwarii = reason
        refreshIcon(active: false)
    }

    fileprivate func remove() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - Licznik pytań obok ikonki

    /// Liczba pytań od Claude Code, **na czerwonym tle, obok ikonki**.
    /// Polecenie [U] 2026-09-03.
    ///
    /// 🔴 Dlaczego tytułem, a nie domalowaniem do obrazka: ikonka jedzie do paska jako
    /// **szablon**, czyli pasek menu sam dobiera jej barwę do swojego tła (i tylko
    /// szablon da się tynkować `contentTintColor`, na czym ten kod już raz się
    /// przejechał — awaria świeciła kolorem „wszystko gra", 2026-08-11). Wmalowanie
    /// czerwonego tła w ten sam obrazek odebrałoby mu szablonowość i ikonka przestałaby
    /// się dopasowywać. Tytuł stoi obok obrazka i ma własne barwy, więc oba zachowania
    /// da się mieć naraz.
    ///
    /// Przy zerze licznika **nie ma go wcale** — pusty pasek menu jest stanem
    /// normalnym przed pierwszym użyciem i nie ma po co zajmować w nim miejsca zerem.
    /// Wysokość plakietki licznika w punktach. Mniejsza od ikonki, żeby nie przykrywała
    /// jej wzrokowo — licznik jest dodatkiem, nie drugim bohaterem paska.
    static let bokLicznika: CGFloat = 14

    /// Promień zaokrąglenia rogów plakietki. Polecenie [U] 2026-09-03:
    /// *„nadaj jakiś promień r na te ostre krawędzie licznika"*.
    ///
    /// 4 pt na 14 pt wysokości to wyraźnie zaokrąglony prostokąt, a nie pigułka —
    /// pigułka wychodzi przy `bokLicznika / 2`, czyli 7. Jedna liczba, jedno miejsce.
    static let promienLicznika: CGFloat = 4

    /// Liczba do narysowania albo `nil`, gdy licznika nie ma być wcale.
    ///
    /// Statyczna i czysta celowo — ta sama zasada, co przy `zrodloZabronione`
    /// i `komunikatPrzeterminowanegoHandlera`: reguła „co widzi człowiek" ma być
    /// sprawdzalna testem bez stawiania paska menu. Wyglądu tym nie zmierzę, ale
    /// regułę owszem.
    ///
    /// Przy zerze **nie ma go wcale** — pusty pasek przed pierwszym użyciem jest stanem
    /// normalnym i nie ma po co zajmować w nim miejsca zerem.
    /// Które tło dorysować pod przyciskiem: `nil` znaczy „to, w którym przycisk
    /// został pomalowany".
    ///
    /// Statyczna i czysta z tego samego powodu co `tekstLicznika`: reguła „co widzi
    /// człowiek" ma być sprawdzalna testem **bez stawiania paska menu** i bez zależności
    /// od tego, czy maszyna akurat chodzi w ciemnym wyglądzie. Pierwsza wersja tej
    /// reguły siedziała w ciele `podglad` jako `zadaneCiemne ?? true` i kontrola
    /// mutacyjna 2026-09-03 **przeszła na zielono** — bo maszyna była ciemna, więc
    /// stała dawała ten sam wynik co odczyt. Test, który zależy od ustawień systemu,
    /// nie pilnuje reguły.
    static func tloDlaPodgladu(zadane: Bool?, ciemnyWyglad: Bool) -> Bool {
        zadane ?? ciemnyWyglad
    }

    /// Który z trzech stanów ikonki widać na obrazku z `GET /ikonka`.
    ///
    /// 🔴 Powód istnienia (audyt 1.2.15–1.2.18, P1-01): z samej bitmapy nie da się
    /// tego poznać, a różnica jest zasadnicza. **Mrugnięcie** to obrazek o dwóch
    /// barwach — widać na nim osobno ramkę i młotek. **Spoczynek i awaria** to
    /// szablon, czyli obrazek, w którym liczy się wyłącznie alfa: pasek menu (i tak
    /// samo ten podgląd) wypełnia go JEDNĄ barwą i młotek przestaje się odróżniać
    /// od ramki. To nie jest wada renderu — tak wygląda ikonka w pasku.
    ///
    /// Audyt tego samego dnia wziął płaską sylwetkę spoczynku za dowód, że podgląd
    /// kłamie. Pomiar 2026-09-03 to obalił: maski tuszu mrugnięcia i spoczynku
    /// pokrywają się w 98,86 % kadru (różnice to same krawędzie antyaliasingu),
    /// a tusz spoczynku ma **jedną** barwę — dokładnie tak, jak działa szablon.
    /// Nazwa stanu jedzie więc nagłówkiem, żeby nikt nie musiał tego zgadywać z obrazka.
    ///
    /// Statyczna i czysta z tego samego powodu co `tloDlaPodgladu` i `tekstLicznika`.
    static func stanIkonki(mruga: Bool, powodAwarii: String?) -> String {
        if powodAwarii != nil { return "awaria" }
        return mruga ? "mrugniecie" : "spoczynek"
    }

    /// Czy w tym stanie ikonka jest szablonem — czyli czy na obrazku ma prawo być
    /// tylko jedna barwa. Idzie w parze z `stanIkonki` i z tego samego powodu.
    static func czySzablon(stanIkonki: String) -> Bool { stanIkonki != "mrugniecie" }

    static func tekstLicznika(_ ile: Int) -> String? {
        guard ile > 0 else { return nil }
        return "\(ile)"
    }

    /// Plakietka licznika jako **obrazek**, nie jako tło pod tekstem.
    ///
    /// 🔴 Dlaczego rysowana, a nie `.backgroundColor` w atrybutach: atrybut tła maluje
    /// ciasny **prostokąt** wokół znaków i nie ma jak zaokrąglić mu rogów ani dać
    /// prawdziwego marginesu. Pierwsza wersja (1.2.11-wcześniejsza tego dnia) stała
    /// właśnie na nim i [U] od razu zobaczył ostre krawędzie.
    ///
    /// 🔴 Dlaczego mimo to nie domalowujemy tego do ikonki: ikonka jedzie do paska jako
    /// **szablon**, czyli pasek menu sam dobiera jej barwę do swojego tła (i tylko
    /// szablon da się tynkować `contentTintColor`, na czym ten kod już raz się
    /// przejechał — awaria świeciła kolorem „wszystko gra", 2026-08-11). Wmalowanie
    /// czerwieni w ten sam obrazek odebrałoby mu szablonowość. Plakietka wchodzi więc
    /// **załącznikiem w tytule**: obok ikonki, z własnymi barwami, obok szablonu.
    ///
    /// Barwy: tło `BridgeIkona.barwaMrugniecia` (#D97706), cyfry czarne — [U] 2026-09-03.
    static func obrazLicznika(_ ile: Int) -> NSImage? {
        guard let tekst = tekstLicznika(ile) else { return nil }

        let krój = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        // Cyfry CZARNE, nie białe — polecenie [U] 2026-09-03. Na pomarańczu #D97706
        // czerń ma kontrast ok. 6,4:1, biel ok. 3,3:1; przy dziesięciu punktach kroju
        // to jest różnica między „czytam" a „domyślam się".
        let atrybuty: [NSAttributedString.Key: Any] = [.font: krój, .foregroundColor: NSColor.black]
        let rozmiarTekstu = (tekst as NSString).size(withAttributes: atrybuty)

        // Szerokość rośnie z liczbą cyfr, ale nigdy nie jest mniejsza od wysokości —
        // przy jednej cyfrze plakietka ma zostać kwadratem, a nie pionową kreską.
        let szerokosc = max(bokLicznika, ceil(rozmiarTekstu.width) + 8)
        let obraz = NSImage(size: NSSize(width: szerokosc, height: bokLicznika))

        obraz.lockFocus()
        defer { obraz.unlockFocus() }
        // 🔴 Ta sama barwa co mrugnięcie ikonki (`#D97706`, decyzja [U] 2026-08-27),
        // a nie osobna czerwień — polecenie [U] 2026-09-03. Pasek mówi wtedy jednym
        // kolorem: pomarańcz znaczy „tu był Claude Code", czy to na ramce ikonki przy
        // pojedynczym pytaniu, czy na liczniku wszystkich.
        BridgeIkona.barwaMrugniecia.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: szerokosc, height: bokLicznika),
            xRadius: promienLicznika, yRadius: promienLicznika
        ).fill()
        (tekst as NSString).draw(
            at: NSPoint(x: (szerokosc - rozmiarTekstu.width) / 2,
                        y: (bokLicznika - rozmiarTekstu.height) / 2),
            withAttributes: atrybuty
        )

        // 🔴 NIE szablon: plakietka ma zostać pomarańczowa niezależnie od tła paska.
        obraz.isTemplate = false
        obraz.accessibilityDescription = "Pytań od Claude Code: \(ile)"
        return obraz
    }

    private func odswiezLicznik(_ button: NSStatusBarButton) {
        guard let plakietka = obrazLicznikaDlaPaska() else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let zalacznik = NSTextAttachment()
        zalacznik.image = plakietka
        // Opuszczenie względem linii pisma — bez tego plakietka wisi nad środkiem ikonki.
        zalacznik.bounds = NSRect(x: 0, y: -3, width: plakietka.size.width, height: plakietka.size.height)

        let tytul = NSMutableAttributedString(string: " ")
        tytul.append(NSAttributedString(attachment: zalacznik))
        button.attributedTitle = tytul
    }

    private func obrazLicznikaDlaPaska() -> NSImage? {
        Self.obrazLicznika(BridgeActivity.shared.total)
    }

    // MARK: - Podgląd własnego paska

    /// PNG **własnego przycisku w pasku menu** razem z opisem, co na nim widać.
    ///
    /// 🔴 **Powód istnienia (plan rozwoju mostu po 1.2.14, poz. 4).** Wyglądu licznika
    /// nie dało się sprawdzić dwa razy tego samego dnia, obiema drogami:
    /// - `screencapture -x` → *„could not create image from display"* (brak zgody
    ///   na nagrywanie ekranu — a to zgoda **systemowa**, której agent nie kliknie),
    /// - `GET /screenshot?window=NSStatusBarWindow` → **500**: okno paska ma 38×33 pt,
    ///   więc odsiewa je sito „za małe, żeby być interfejsem aplikacji".
    ///
    /// Trzy z czterech poprawek licznika wyszły ze **zrzutu przysłanego przez [U]**,
    /// nie z pomiaru mostu. Zmierzyć dało się wyłącznie szerokość okna: 32 → 66 pt.
    ///
    /// Tędy zgoda systemowa **nie jest potrzebna**: to własny widok procesu, rysowany
    /// tak samo jak przy `GET /render`. Most nie czyta ekranu — prosi swój własny
    /// przycisk, żeby narysował się do bitmapy.
    ///
    /// ⚠️ **Tło jest dorysowane, nie sfotografowane.** Prawdziwy pasek menu podkłada
    /// pod przycisk swoje tło i sam dobiera barwę szablonowej ikonki; renderując sam
    /// widok, dostajemy go na przezroczystości — czyli ciemną ikonkę na niczym.
    /// Podkładamy więc jednolity prostokąt w barwie zbliżonej do paska i **mówimy
    /// o tym w nagłówku**, żeby nikt nie wziął podglądu za zrzut ekranu.
    ///
    /// 🔴 **Barwa ikonki NIE idzie za dorysowanym tłem — i to jest zmierzone, nie
    /// obawa.** Ikonka jedzie do paska jako **szablon**, więc barwę nadaje jej pasek
    /// w wyglądzie, który akurat obowiązuje w systemie. Render kopiuje ją taką, jaka
    /// jest. Pierwsza wersja tego endpointu przyjmowała `?tlo=jasne` i oddawała
    /// **jasny młotek na jasnym tle**, czyli obraz, którego nigdzie nie ma —
    /// zobaczone na obrazku z żywego gospodarza 2026-09-03, zaraz po napisaniu.
    ///
    /// Przeliczyć się tego nie da bez ruszenia `appearance` **żywego przycisku**,
    /// czyli bez zmiany tego, co użytkownik ma w tej chwili na ekranie. Odczyt, który
    /// zmienia to, co mierzy, jest w tym projekcie zakazany, więc domyślne tło idzie
    /// za **aktualnym wyglądem systemu**, a rozjazd dostaje nagłówek z ostrzeżeniem.
    fileprivate func podglad(naCiemnym zadaneCiemne: Bool?) throws -> (Data, [String: String]) {
        guard let button = statusItem?.button else {
            throw BridgeError.notFound(
                "Ta aplikacja nie ma ikonki mostu w pasku menu — most wystartował "
                + "z showMenuBarIcon: false albo ikonka została zdjęta. Nie ma czego pokazać."
            )
        }

        // 🔴 Wygląd czytamy z SAMEGO PRZYCISKU, nie z `NSApp`, i dopiero TU — po
        // sprawdzeniu, że przycisk w ogóle jest. Dwa powody, oba zmierzone:
        //
        // 1. `NSApp` jest w Swifcie `NSApplication!`, więc w procesie bez aplikacji
        //    AppKit (testy, narzędzie wiersza poleceń) samo sięgnięcie po niego
        //    **kończy proces** — nie odmową, tylko awarią gospodarza. Rodzina P0-02.
        //    Zobaczone w testach 2026-09-03: `Fatal error: Unexpectedly found nil`.
        // 2. Merytorycznie to i tak zła pytana strona. Barwę, którą kopiujemy, dostał
        //    ten konkretny widok — więc pytamy jego, nie aplikacji.
        let ciemnySystem = button.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let naCiemnym = Self.tloDlaPodgladu(zadane: zadaneCiemne, ciemnyWyglad: ciemnySystem)

        let rozmiar = button.bounds.size
        guard rozmiar.width > 0, rozmiar.height > 0 else {
            throw BridgeError.failed(
                "Przycisk ikonki ma rozmiar \(Int(rozmiar.width))×\(Int(rozmiar.height)) punktów "
                + "— nie ma z czego zrobić bitmapy. Pasek menu mógł go jeszcze nie rozłożyć."
            )
        }

        let tlo = NSView(frame: NSRect(origin: .zero, size: rozmiar))
        tlo.wantsLayer = true
        // Barwy zbliżone do paska menu w obu wyglądach. To **przybliżenie dla oka**,
        // nie odwzorowanie — pasek jest półprzezroczysty i zależy od tapety.
        tlo.layer?.backgroundColor = (naCiemnym
            ? NSColor(white: 0.13, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)).cgColor

        // 🔴 Przycisk rysujemy do bitmapy i wklejamy jako obraz, zamiast wkładać go
        // do cudzego widoku. Wyjęcie żywego `NSStatusBarButton` z hierarchii paska
        // menu zabrałoby go użytkownikowi z ekranu — podgląd ma pokazywać ikonkę,
        // a nie ją kraść.
        let przycisk = try BridgeRenderHarness.bitmapa(button)
        guard let obraz = NSImage(data: przycisk) else {
            throw BridgeError.failed("Nie udało się odczytać bitmapy przycisku paska.")
        }
        let warstwa = NSImageView(frame: NSRect(origin: .zero, size: rozmiar))
        warstwa.image = obraz
        warstwa.imageScaling = .scaleNone
        tlo.addSubview(warstwa)

        let dane = try BridgeRenderHarness.bitmapa(tlo)

        var naglowki: [String: String] = [
            "x-bridge-ikonka-szerokosc-pt": String(format: "%.0f", rozmiar.width),
            "x-bridge-ikonka-wysokosc-pt": String(format: "%.0f", rozmiar.height),
            "x-bridge-ikonka-tlo": naCiemnym ? "dorysowane-ciemne" : "dorysowane-jasne",
            "x-bridge-ikonka-wyglad-systemu": ciemnySystem ? "ciemny" : "jasny",
            "x-bridge-ikonka-stan": powodAwarii == nil
                ? (BridgeServer.shared.isRunning ? "most-stoi" : "most-nie-nasluchuje")
                : "most-padl",
            // Liczba, którą plakietka POWINNA pokazywać — do porównania z tym, co widać
            // na obrazku. Rozjazd między nimi jest usterką rysowania, nie licznika.
            "x-bridge-ikonka-licznik": Self.tekstLicznika(BridgeActivity.shared.total) ?? "(brak)",
        ]

        // 🔴 Który stan widać i czy to szablon (P1-01). Bez tych dwóch nagłówków
        // obrazek spoczynku wygląda na „ikonkę, która zgubiła szczegóły", a jest
        // wierną kopią tego, co robi pasek menu z obrazkiem szablonowym.
        let stanIkonki = Self.stanIkonki(mruga: mrugaTeraz, powodAwarii: powodAwarii)
        naglowki["x-bridge-ikonka-stan-ikonki"] = stanIkonki
        if Self.czySzablon(stanIkonki: stanIkonki) {
            naglowki["x-bridge-ikonka-szablon"] = "tak"
            naglowki["x-bridge-ikonka-o-szablonie"] = "Ikonka jest w tym stanie SZABLONEM: "
                + "liczy sie sama alfa, a barwe nadaje jedna dla calego rysunku. Mlotek "
                + "NIE odroznia sie wtedy od ramki i tak samo wyglada w pasku menu — "
                + "to nie jest wada renderu. Zeby zobaczyc mlotek i ramke osobno, "
                + "zapytaj o ikonke zaraz po innym zadaniu (stan mrugniecie, 0,45 s)."
        } else {
            naglowki["x-bridge-ikonka-szablon"] = "nie"
        }
        if let powodAwarii {
            naglowki["x-bridge-ikonka-powod-awarii"] = BridgeDefaults.skrocony(powodAwarii, do: 120)
        }
        // 🔴 Ostrzeżenie przy rozjeździe, bo obrazek wygląda wtedy na poprawny
        // i nie ma na nim śladu, że pokazuje stan, którego nie ma.
        if naCiemnym != ciemnySystem {
            naglowki["x-bridge-ikonka-uwaga"] = "Tlo dorysowane wbrew wygladowi systemu. "
                + "Ikonka jest szablonem, wiec jej barwe nadal pasek w wygladzie "
                + "\(ciemnySystem ? "ciemnym" : "jasnym") i most jej NIE przelicza — "
                + "moze byc nieczytelna na tym tle. Zeby zobaczyc prawde, przelacz wyglad "
                + "systemu i zapytaj bez parametru tlo."
        }
        return (dane, naglowki)
    }

    // MARK: - Ikonka

    private func refreshIcon(active: Bool) {
        guard let button = statusItem?.button else { return }

        let running = BridgeServer.shared.isRunning

        // 🔴 Kształt jest JEDEN i nie zmienia się nigdy: ikonka [U] z `~/Desktop/Xcode.svg`
        // (polecenie 2026-08-27 — „zamiast antenki"). Wcześniej kształt niósł komunikat
        // „most stoi" przez podmianę symbolu na antenę z ukośnikiem; teraz cały komunikat
        // idzie **barwą**, bo ikonka [U] wariantu z ukośnikiem nie ma, a dorabiać go nie wolno.
        //
        // Historia, do której nie ma po co wracać: jeszcze wcześniej mrugnięcie podmieniało
        // symbol na `….circle.fill`, przez co ikonka nie mrugała, tylko skakała między
        // kropką a anteną ([U], 2026-08-11).
        //
        // Trzy stany:
        //   • pytanie od Claude Code → świeci RAMKA na `#D97706`, młotek zostaje
        //     w barwie paska. [U] obejrzał 2026-08-27 oba warianty w prawdziwym pasku
        //     i wybrał ten: przy 16 punktach pomarańcz na dużej bryle widać kątem oka,
        //     a na cienkiej kresce młotka prawie nie. Wcześniej zieleń, przez chwilę
        //     czerwień, przez chwilę świecący młotek — wszystkie zdjęte.
        //   • most nie wstał         → cała ikonka czerwona, na stałe
        //   • spoczynek              → szablon bez barwy: pasek menu sam dobiera czerń
        //     albo biel do swojego tła, a tego żadna wypalona barwa nie zrobi
        //
        // 🔴 `contentTintColor` tynkuje WYŁĄCZNIE szablony — dlatego stan spoczynku
        // i awarii idą szablonem, a mrugnięcie osobnym obrazkiem o dwóch barwach.
        // Symbole anteny szablonami nie były i miały wbudowany `systemGreen`; przez to
        // awaria świeciła kiedyś kolorem „wszystko gra" (test GUI [U], 2026-08-11).
        if active, powodAwarii == nil, let zapalona = BridgeIkona.zMrugnieciem(barwaStala: barwaRamki(button)) {
            button.image = zapalona
            button.contentTintColor = nil
            mrugaTeraz = true
        } else {
            mrugaTeraz = false
            button.image = BridgeIkona.szablon
            button.image?.isTemplate = true
            button.contentTintColor = powodAwarii != nil ? .systemRed : nil
        }

        odswiezLicznik(button)

        if powodAwarii != nil {
            button.toolTip = "AppBridge NIE WSTAŁ: \(powodAwarii ?? "")"
        } else {
            button.toolTip = running
                ? "AppBridge: \(appName) na porcie \(port) — obsłużonych pytań: \(BridgeActivity.shared.total)"
                : "AppBridge: most zatrzymany"
        }
    }

    /// Barwa części, która na czas mrugnięcia **nie** świeci (młotka).
    ///
    /// Obrazek mrugnięcia nie jest szablonem (ma dwie barwy naraz), więc barwy paska
    /// nie dobierze już system — trzeba ją odczytać samemu, w wyglądzie **tego**
    /// przycisku. Inaczej na ciemnym pasku młotek byłby czarny na czarnym.
    private func barwaRamki(_ button: NSStatusBarButton) -> NSColor {
        var barwa = NSColor.labelColor
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            barwa = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return barwa
    }

    /// Mrugnięcie przy każdym pytaniu od Claude Code.
    ///
    /// Brał wcześniej `BridgeActivityEntry`, którego nie używał ani razu — Swift nie
    /// ostrzega o nieużywanych parametrach, więc nic tego nie zgłaszało (audyt
    /// 2026-08-10, E3b-P3-01). Parametr zdjęty zamiast „użyty na siłę": mrugnięcie
    /// wygląda dziś tak samo dla `200` i dla `404`, a zmiana tego jest decyzją
    /// o wyglądzie, nie sprzątaniem długu. Gdyby kiedyś miała zapaść — wpis jest
    /// pod ręką w `setOnChange` i wraca tu jednym parametrem.
    private func flash() {
        refreshIcon(active: true)
        resetTimer?.invalidate()
        resetTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
            _Concurrency.Task { @MainActor in BridgeStatusItem.shared.refreshIcon(active: false) }
        }
    }

    // MARK: - Menu (przebudowywane przy każdym otwarciu)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let running = BridgeServer.shared.isRunning
        let activity = BridgeActivity.shared

        menu.addItem(header("AppBridge — \(appName)"))

        if let powodAwarii {
            menu.addItem(info("⚠️  Most nie wystartował"))
            // Po ". ", nie po samej kropce. Powód awarii powstaje z
            // `error.localizedDescription` systemu, więc jego treści nikt tu nie
            // kontroluje — prawdziwy komunikat o zajętym porcie zawiera
            // `Network.NWError` i rozpadał się na CZTERY pozycje menu. Adres
            // `127.0.0.1` zrobiłby to samo. Audyt 2026-08-10, E3b-P3-01.
            for linia in powodAwarii.components(separatedBy: ". ") where !linia.isEmpty {
                menu.addItem(info("      " + linia.trimmingCharacters(in: .whitespaces)))
            }
        } else {
            menu.addItem(info(running ? "●  Nasłuchuje na 127.0.0.1:\(port)" : "○  Zatrzymany"))
        }

        if running {
            var licznik = "Pytania od Claude Code: \(activity.total)"
            if activity.errors > 0 { licznik += "   (błędów: \(activity.errors))" }
            // 🔴 Liczba, która jako jedyna mówi o TWOIM programie, a nie o moście:
            // ile razy agent coś w nim zmienił. Pokazywana tylko wtedy, gdy jest
            // niezerowa — most jest domyślnie do odczytu i taki zostaje u większości.
            if activity.zmian > 0 { licznik += "   ✎ zmian: \(activity.zmian)" }
            menu.addItem(info(licznik))

            if activity.total == 0 {
                menu.addItem(info("Jeszcze nic nie pytał — to normalne przed pierwszym użyciem."))
            }
        }

        menu.addItem(.separator())

        let recent = activity.recent
        if recent.isEmpty {
            menu.addItem(header("Historia pusta"))
        } else {
            // Nagłówek mówi prawdę o tym, co jest na liście. „Ostatnie pytania"
            // przy wykonanej akcji było zdaniem z czasów mostu wyłącznie do odczytu.
            menu.addItem(header(recent.contains(where: \.zmienil)
                                ? "Ostatnie pytania i zmiany"
                                : "Ostatnie pytania"))
            for entry in recent {
                let item = info(entry.summary)
                item.attributedTitle = NSAttributedString(
                    string: entry.summary,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        // Zapis dostaje pełną moc koloru, odczyt drugoplanową.
                        // Błąd wygrywa z obydwoma — czerwień zostaje czerwienią.
                        .foregroundColor: entry.isError ? NSColor.systemRed
                            : (entry.zmienil ? NSColor.labelColor : NSColor.secondaryLabelColor),
                    ]
                )
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        if running {
            let kopiuj = NSMenuItem(
                title: "Kopiuj adres mostu",
                action: #selector(copyAddress),
                keyEquivalent: ""
            )
            kopiuj.target = self
            menu.addItem(kopiuj)

            let sprawdz = NSMenuItem(
                title: "Sprawdź w przeglądarce",
                action: #selector(openPing),
                keyEquivalent: ""
            )
            sprawdz.target = self
            menu.addItem(sprawdz)
        }

        menu.addItem(info("Widoczny tylko w buildzie DEBUG"))
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Akcje

    @objc private func copyAddress() {
        let address = "http://127.0.0.1:\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    @objc private func openPing() {
        guard let url = URL(string: "http://127.0.0.1:\(port)/ping") else { return }
        NSWorkspace.shared.open(url)
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeTextAttributes.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` dołożone 2026-08-29 (audyt, E5N-P1-01). Do tego dnia ten plik znikał
// z RELEASE **wyłącznie dlatego, że nic się do niego nie odwoływało** — jedyne wywołania
// stoją w `registerBuiltInWyglad`, która jest pod dyrektywą. Zamek oparty na tym, że
// optymalizator usunie martwy kod, jest zamkiem cudzym: wystarczy jedno nowe odwołanie
// spoza `#if DEBUG`, żeby cały plik pojechał do wydania gospodarza, i żaden pomiar tego
// nie zapowie. Ta sama uwaga stoi w przepisie audytu przy `BridgeScreenshot` (pytanie 4d).
#if DEBUG && canImport(AppKit)

/// Odczyt **atrybutów tekstu**, a nie pikseli.
///
/// Powód powstania, wprost z roboty 2026-08-27 (wygląd `Like Xcode` w MarkRead):
/// padło pytanie „czy kod ma 0,7 alfy, czy tylko tak wygląda". Ze zrzutu **nie da się**
/// tego rozstrzygnąć — antyaliasing, tło i profil kolorów robią z 0,70 i 0,74 ten sam
/// obrazek. Ten endpoint zamienia „wygląda podobnie" w liczbę.
@MainActor
enum BridgeTextAttributes {

    /// Ile znaków runu pokazujemy. Pełny tekst dokumentu nie jest tu potrzebny —
    /// chodzi o rozpoznanie runu, nie o odczyt treści. Przy okazji trzyma to
    /// odpowiedź w rozmiarze, który da się przeczytać.
    ///
    /// 🔴 **Znak znaczy tu jednostkę UTF-16 — tę samą, w której liczą `od`, `do`
    /// i `znakowWDokumencie`.** Do 2026-08-28 ten sufit liczył w grafemach Swifta,
    /// czyli w czymś innym niż cała reszta odpowiedzi. Zmierzone: run z 80 emoji
    /// rodziny (`👨‍👩‍👧‍👦`) to **80 grafemów, ale 880 jednostek UTF-16** — przechodził
    /// z `tekstObciety: false`, choć sufit obiecywał 80. Ta sama rodzina usterki
    /// co E5-P1-01 (punkty kontra piksele): dwie liczby w dwóch jednostkach,
    /// bez słowa o tym, że są różne.
    ///
    /// 🔴 `nonisolated`, bo ta stała jest **wartością domyślną parametru**
    /// `skrot(_:budzet:)`. Wyrażenia domyślnych argumentów Swift liczy w kontekście
    /// nieizolowanym — niezależnie od tego, że otaczający typ jest `@MainActor`.
    /// Bez tego gospodarz budowany ze ścisłą współbieżnością (`-default-isolation
    /// MainActor` + `GlobalActorIsolatedTypesUsability`) dostaje ostrzeżenie
    /// „main actor-isolated static property … can not be referenced from
    /// a nonisolated context; this is an error in the Swift 6 language mode".
    /// Zmierzone 2026-09-11 przy wpięciu do innym gospodarzu — sam pakiet buduje się
    /// bez tego ostrzeżenia, bo nie ma tych flag. Stała jest niezmienną liczbą,
    /// więc izolacja nic tu nie chroniła.
    nonisolated static let maksZnakowWRunie = 80

    /// Domyślny sufit liczby runów. Notatka z tysiącem kolorowanych fragmentów
    /// dałaby odpowiedź na kilka megabajtów, z czego nikt niczego nie odczyta.
    static let domyslnyLimitRunow = 200

    /// Liczba z zapytania — albo `nil`, gdy parametru nie podano.
    ///
    /// 🔴 Parametr, który jest, ale nie jest liczbą, to **błąd wołającego**, a nie brak
    /// parametru. Do 2026-08-28 `flatMap(Int.init)` zamieniał jedno w drugie po cichu:
    /// `?from=abc` oddawało cały dokument z kodem 200, a `?limit=abc` — limit domyślny.
    /// Wołający dostawał wiarygodną odpowiedź na pytanie, którego nie zadał. To jest ta
    /// sama rodzina co WW-P1-01, i `/render` rozstrzyga ją odwrotnie: odmawia z instrukcją.
    /// Jedna warstwa ma mieć jedną konwencję. Audyt 2026-08-28, E5-P3-01.
    nonisolated static func liczbaZQuery(_ query: [String: String], _ nazwa: String) throws -> Int? {
        guard let surowa = query[nazwa], !surowa.isEmpty else { return nil }
        guard let liczba = Int(surowa) else {
            throw BridgeError.badRequest(
                "Parametr \(nazwa)=\(BridgeDefaults.skrocony(surowa, do: 40)) nie jest liczbą. "
                + "Most nie zgaduje, co miało się stać z niepoprawnym parametrem — odpowiedź "
                + "na inne pytanie wygląda tak samo wiarygodnie jak na to zadane."
            )
        }
        return liczba
    }

    static func odczytaj(
        okno tytulOkna: String?,
        widok: String?,
        od: Int?,
        do doZnaku: Int?,
        limit: Int?
    ) throws -> [String: Any] {
        let okno = try BridgeViewLookup.wybierzOkno(tytul: tytulOkna)
        let textView = try BridgeViewLookup.znajdzTextView(widok, w: okno)

        guard let storage = textView.textStorage else {
            throw BridgeError.failed("Pole tekstowe nie ma zawartości (textStorage jest pusty)")
        }

        let dlugosc = storage.length
        let zakres = try zakresDoOdczytu(od: od, do: doZnaku, w: storage.string as NSString)

        if let limit, limit > BridgeLimity.maksRunow {
            // Odmowa, nie ciche przycięcie: `/render?width=99999` w tej samej warstwie
            // odmawia z instrukcją, a odpowiedź na inne pytanie niż zadane wygląda tak
            // samo wiarygodnie jak na zadane. Poz. 15, sufit z decyzji [U] 2026-09-02.
            throw BridgeError.badRequest(
                "Parametr limit=\(limit) przekracza sufit \(BridgeLimity.maksRunow) runów. "
                + "Jeden run waży w odpowiedzi ok. 449 B (zmierzone), więc \(limit) runów "
                + "to rzędu \(limit * 449 / 1_000_000) MB budowane w pamięci mierzonej "
                + "aplikacji — a klient MCP i tak odrzuci wszystko powyżej 1 MiB, czyli "
                + "ok. 2335 runów. Podaj limit najwyżej \(BridgeLimity.maksRunow) albo "
                + "czytaj dokument kawałkami przez from/to."
            )
        }
        let sufit = max(1, limit ?? domyslnyLimitRunow)
        var runy: [[String: Any]] = []
        var obciete = false

        storage.enumerateAttributes(in: zakres, options: []) { atrybuty, zasieg, stop in
            guard runy.count < sufit else {
                obciete = true
                stop.pointee = true
                return
            }
            runy.append(opiszRun(storage: storage, zasieg: zasieg, atrybuty: atrybuty))
        }

        return [
            "okno": okno.title,
            "widok": String(describing: type(of: textView)),
            // Kierunek układu przy współrzędnych — powód przy tym samym polu
            // w `BridgeHitTest.zbadaj` (poz. 21). Tu rozstrzyga dodatkowo o tym,
            // z której strony zaczyna się wiersz, do którego odnoszą się `od`/`do`.
            "kierunekUkladu": BridgeAppearance.kierunekOkna(okno),
            "znakowWDokumencie": dlugosc,
            "zakres": ["od": zakres.location, "do": zakres.location + zakres.length],
            "runow": runy.count,
            "obciete": obciete,
            "runy": runy,
        ]
    }

    // MARK: - Zakres odczytu

    /// Zamienia `from`/`to` z zapytania na zakres, albo odmawia z instrukcją.
    ///
    /// Stoi osobno od `odczytaj`, bo `odczytaj` potrzebuje żywego okna i widoku,
    /// a cała decyzja o zakresie jest czystą arytmetyką na napisie — i tylko tak
    /// da się ją zmierzyć testem, zamiast wnioskować o niej z lektury kodu.
    ///
    /// Trzy reguły, każda z innym uzasadnieniem:
    /// - **zakres odwrócony → odmowa.** Do 2026-08-28 `from=10&to=5` oddawało
    ///   `{od: 10, do: 10, runow: 0}` z kodem 200 — a to czyta się jak „w tym zakresie
    ///   nie ma atrybutów", nie jak „nie zrozumiałem zakresu",
    /// - **wyjście poza dokument → ciche przycięcie.** Tam intencja jest jednoznaczna
    ///   („do końca", „od początku") i odmowa niczego by nie wyjaśniła,
    /// - **granica w środku znaku → odmowa.** Patrz `sprawdzGranice`.
    nonisolated static func zakresDoOdczytu(od: Int?, do doZnaku: Int?, w tekst: NSString) throws -> NSRange {
        let dlugosc = tekst.length
        if let od, let doZnaku, doZnaku < od {
            throw BridgeError.badRequest(
                "Zakres jest odwrócony: from=\(od) jest większe niż to=\(doZnaku). "
                + "Podaj from mniejsze albo równe to; dokument ma \(dlugosc) znaków."
            )
        }

        let poczatek = max(0, min(od ?? 0, dlugosc))
        let koniec = max(poczatek, min(doZnaku ?? dlugosc, dlugosc))
        try sprawdzGranice(poczatek, nazwa: "from", w: tekst)
        try sprawdzGranice(koniec, nazwa: "to", w: tekst)

        return NSRange(location: poczatek, length: koniec - poczatek)
    }

    // MARK: - Opis jednego runu

    static func opiszRun(
        storage: NSAttributedString,
        zasieg: NSRange,
        atrybuty: [NSAttributedString.Key: Any]
    ) -> [String: Any] {
        let pelnyTekst = storage.attributedSubstring(from: zasieg).string
        let (pokazany, pokryto) = skrot(pelnyTekst)
        var run: [String: Any] = [
            "od": zasieg.location,
            "do": zasieg.location + zasieg.length,
            "tekst": pokazany,
            // Pole `obciete` na górze odpowiedzi mówi o liczbie RUNÓW, nie o treści.
            // Bez tego run o długości 204 znaków wracał z 81 i rozpoznać to dało się
            // tylko po różnicy `do − od` albo po wielokropku — a dokument kończący
            // akapit wielokropkiem jest wtedy nieodróżnialny. E5-P3-01.
            "tekstObciety": pokazany != pelnyTekst,
            // Ile jednostek UTF-16 pokrywa pole `tekst` — czyli w tej samej jednostce,
            // w której liczą `od` i `do`. Bez tej liczby run przycięty nie dawał się
            // zestawić z zakresem: `do − od` mówiło o dokumencie, a `tekst` o tym,
            // co widać, i przy emoji te dwie liczby różniły się jedenastokrotnie.
            "pokazanoZnakow": pokryto,
        ]

        if let font = atrybuty[.font] as? NSFont {
            run["kroj"] = opiszKroj(font)
        }
        if let kolor = atrybuty[.foregroundColor] as? NSColor {
            run["kolor"] = opiszKolor(kolor)
        }
        if let tlo = atrybuty[.backgroundColor] as? NSColor {
            run["tlo"] = opiszKolor(tlo)
        }
        if let podkreslenie = atrybuty[.underlineStyle] as? NSNumber, podkreslenie.intValue != 0 {
            run["podkreslenie"] = podkreslenie.intValue
        }
        if let przekreslenie = atrybuty[.strikethroughStyle] as? NSNumber, przekreslenie.intValue != 0 {
            run["przekreslenie"] = przekreslenie.intValue
        }
        if let link = atrybuty[.link] {
            run["link"] = (link as? URL)?.absoluteString ?? String(describing: link)
        }
        if let odstep = atrybuty[.kern] as? NSNumber {
            run["kerning"] = zaokraglij(CGFloat(odstep.doubleValue))
        }
        if let baselineOffset = atrybuty[.baselineOffset] as? NSNumber, baselineOffset.doubleValue != 0 {
            run["przesuniecieLinii"] = zaokraglij(CGFloat(baselineOffset.doubleValue))
        }
        if let akapit = atrybuty[.paragraphStyle] as? NSParagraphStyle {
            run["akapit"] = [
                "interlinia": zaokraglij(akapit.lineSpacing),
                "mnoznikInterlinii": zaokraglij(akapit.lineHeightMultiple),
                "wciecieGlowy": zaokraglij(akapit.headIndent),
                "wciecieOgona": zaokraglij(akapit.tailIndent),
                "przedAkapitem": zaokraglij(akapit.paragraphSpacingBefore),
                "poAkapicie": zaokraglij(akapit.paragraphSpacing),
            ]
        }

        // Wszystko, czego kit nie zna z nazwy, to atrybut własny programu — i to
        // zwykle **jego** się szuka („czy blok kodu ma mój znacznik"). Nazwy oddajemy
        // zawsze, wartości tylko wtedy, gdy dają się zapisać w JSON.
        let znane: Set<NSAttributedString.Key> = [
            .font, .foregroundColor, .backgroundColor, .underlineStyle, .strikethroughStyle,
            .link, .kern, .baselineOffset, .paragraphStyle,
        ]
        let wlasne = atrybuty.filter { !znane.contains($0.key) }
        if !wlasne.isEmpty {
            run["wlasne"] = wlasne.reduce(into: [String: Any]()) { wynik, para in
                let wartosc = para.value
                wynik[para.key.rawValue] = JSONSerialization.isValidJSONObject([wartosc])
                    ? wartosc
                    : String(describing: wartosc)
            }
        }
        return run
    }

    static func opiszKroj(_ font: NSFont) -> [String: Any] {
        let deskryptor = font.fontDescriptor
        let traity = deskryptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let waga = (traity?[.weight] as? NSNumber)?.doubleValue
        let symboliczne = deskryptor.symbolicTraits

        var opis: [String: Any] = [
            "nazwa": font.fontName,
            "rodzina": font.familyName ?? font.fontName,
            "rozmiar": zaokraglij(font.pointSize),
            "pogrubiony": symboliczne.contains(.bold),
            "kursywa": symboliczne.contains(.italic),
            "monospace": symboliczne.contains(.monoSpace),
        ]
        // Waga w skali AppKit: −1 (ultralight) … 0 (regular) … 1 (black). To ta sama
        // liczba, którą podaje się w `NSFont.systemFont(ofSize:weight:)`, więc da się
        // ją wprost porównać z kodem, który krój ustawia.
        if let waga { opis["waga"] = zaokraglij(CGFloat(waga)) }
        return opis
    }

    /// Kolor **w sRGB, razem z alfą** — bo o alfę w tej robocie zawsze chodzi.
    ///
    /// Kolory katalogowe (`NSColor.labelColor`, kolory z Asset Catalog) nie mają
    /// składowych, dopóki nie zamieni się ich na konkretną przestrzeń; bez tego
    /// `redComponent` rzuca wyjątek i zabija proces gospodarza. Stąd `usingColorSpace`
    /// i uczciwe „nie dało się" zamiast liczby wziętej znikąd.
    static func opiszKolor(_ kolor: NSColor) -> [String: Any] {
        guard let sRGB = kolor.usingColorSpace(.sRGB) else {
            return [
                "opis": "\(kolor)",
                "przestrzen": nazwaPrzestrzeni(kolor),
                "uwaga": "koloru nie da się przeliczyć na sRGB (kolor wzorkowy albo katalogowy)",
            ]
        }
        return [
            "r": zaokraglij(sRGB.redComponent),
            "g": zaokraglij(sRGB.greenComponent),
            "b": zaokraglij(sRGB.blueComponent),
            "a": zaokraglij(sRGB.alphaComponent),
            "hex": String(
                format: "#%02X%02X%02X",
                Int((sRGB.redComponent * 255).rounded()),
                Int((sRGB.greenComponent * 255).rounded()),
                Int((sRGB.blueComponent * 255).rounded())
            ),
            "przestrzen": "sRGB",
            "zrodlo": nazwaPrzestrzeni(kolor),
        ]
    }

    /// Nazwa przestrzeni koloru **bez sięgania po `colorSpace` na oślep**.
    ///
    /// `NSColor.colorSpace` jest legalne wyłącznie dla kolorów składowych — na kolorze
    /// wzorkowym albo katalogowym (`NSColor.labelColor`, kolory z Asset Catalog) rzuca
    /// wyjątek Objective-C, którego Swift nie złapie: proces gospodarza ginie. Ta sama
    /// rodzina pułapki co `.json(...)` z wartością niedozwoloną (audyt 2026-08-02, P0-02).
    static func nazwaPrzestrzeni(_ kolor: NSColor) -> String {
        switch kolor.type {
        case .componentBased:
            return kolor.colorSpace.localizedName ?? "nieznana"
        case .catalog:
            // Najczęstszy przypadek w interfejsach macOS: `labelColor` i spółka.
            // Warto to widzieć w odpowiedzi, bo kolor katalogowy zmienia się razem
            // z wyglądem — a wartość niżej jest z chwili pomiaru.
            return "katalogowy (\(kolor.catalogNameComponent).\(kolor.colorNameComponent))"
        case .pattern:
            return "wzorek"
        @unknown default:
            return "nieznany rodzaj koloru"
        }
    }

    /// Cztery miejsca po przecinku. 0,70 i 0,74 mają się różnić w odpowiedzi —
    /// zaokrąglenie do dwóch miejsc kasowałoby dokładnie tę różnicę, dla której
    /// ten endpoint powstał.
    static func zaokraglij(_ wartosc: CGFloat) -> Double {
        (Double(wartosc) * 10_000).rounded() / 10_000
    }

    /// Skrót runu **liczony w UTF-16**, cięty na granicy sekwencji złożonej.
    ///
    /// Dwie rzeczy naraz, bo jedna bez drugiej nie ma sensu:
    /// 1. budżet jest w tej samej jednostce co `od`/`do`, więc `tekst` da się
    ///    zestawić z zakresem runu bez zgadywania,
    /// 2. cięcie cofa się do początku sekwencji złożonej (`rangeOfComposedCharacterSequence`
    ///    z Foundation, szczebel 3 drabinki), więc nigdy nie rozdziera pary zastępczej
    ///    ani emoji z ZWJ — a napis z osieroconą połówką pary **nie zapisuje się w JSON**
    ///    i wywracał całą odpowiedź na 500.
    ///
    /// Znak dłuższy niż cały budżet pokazujemy w całości. Zwrócenie samego wielokropka
    /// byłoby formalnie zgodne z sufitem i bezużyteczne.
    ///
    /// - Returns: napis do pokazania oraz `pokryto` — ile jednostek UTF-16 **runu**
    ///   ten napis obejmuje. Wielokropek do `pokryto` nie wchodzi: to liczba do
    ///   zestawienia z `od`/`do`, a nie długość pola.
    /// - Parameter budzet: sufit w jednostkach UTF-16. Domyślnie runowy; `/hit` podaje
    ///   swój własny (`BridgeLimity.maksZnakowWartosci`), bo tam sufit dotyczy całej
    ///   wartości elementu, nie fragmentu o jednolitych atrybutach.
    static func skrot(_ tekst: String, budzet: Int = maksZnakowWRunie) -> (tekst: String, pokryto: Int) {
        let ns = tekst as NSString
        guard ns.length > budzet else { return (tekst, ns.length) }

        let granica = ns.rangeOfComposedCharacterSequence(at: budzet).location
        let ciecie = granica > 0 ? granica : ns.rangeOfComposedCharacterSequence(at: 0).length
        return (ns.substring(to: ciecie) + "…", ciecie)
    }

    /// Czy `indeks` leży na granicy znaku, czy w środku sekwencji złożonej.
    ///
    /// Koniec dokumentu jest granicą legalną — `to=długość dokumentu` znaczy „do końca".
    nonisolated static func naGranicyZnaku(_ indeks: Int, w tekst: NSString) -> Bool {
        guard indeks > 0, indeks < tekst.length else { return true }
        return tekst.rangeOfComposedCharacterSequence(at: indeks).location == indeks
    }

    /// Odmawia, gdy granica zakresu wypada w środku znaku — i podaje obie liczby,
    /// które są legalne, żeby wołający nie musiał ich szukać po omacku.
    nonisolated static func sprawdzGranice(_ indeks: Int, nazwa: String, w tekst: NSString) throws {
        guard !naGranicyZnaku(indeks, w: tekst) else { return }

        let sekwencja = tekst.rangeOfComposedCharacterSequence(at: indeks)
        let przed = sekwencja.location
        let po = sekwencja.location + sekwencja.length
        throw BridgeError.badRequest(
            "Parametr \(nazwa)=\(indeks) wypada w środku znaku zajmującego \(sekwencja.length) "
            + "jednostek UTF-16 (\(przed)…\(po)). Podaj \(nazwa)=\(przed) albo \(nazwa)=\(po). "
            + "Most liczy w jednostkach UTF-16 — tych samych, które oddaje w polach od, do "
            + "i znakowWDokumencie — a emoji, flaga albo litera z osobnym znakiem diakrytycznym "
            + "zajmuje ich kilka. Przecięcie takiego znaku dałoby tekst, którego nie da się "
            + "zapisać w JSON, więc most odmawia teraz zamiast wywracać całą odpowiedź."
        )
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeViewLookup.swift
// ────────────────────────────────────────────────────────────────────────


// 🔴 `#if DEBUG` dołożone 2026-08-29 (audyt, E5N-P1-01). Do tego dnia ten plik znikał
// z RELEASE **wyłącznie dlatego, że nic się do niego nie odwoływało** — jedyne wywołania
// stoją w `registerBuiltInWyglad`, która jest pod dyrektywą. Zamek oparty na tym, że
// optymalizator usunie martwy kod, jest zamkiem cudzym: wystarczy jedno nowe odwołanie
// spoza `#if DEBUG`, żeby cały plik pojechał do wydania gospodarza, i żaden pomiar tego
// nie zapowie. Ta sama uwaga stoi w przepisie audytu przy `BridgeScreenshot` (pytanie 4d).
#if DEBUG && canImport(AppKit)

/// Wspólne wyszukiwanie okien i widoków dla wszystkich endpointów oglądających
/// wygląd: `/screenshot`, `/render`, `/text-attributes`, `/hit`, `/drawn-rects`.
///
/// Wydzielone, bo do 2026-08-27 wybór okna mieszkał w całości w `BridgeScreenshot`
/// i każdy nowy endpoint musiałby go przepisać — a razem z nim dwa sita (nazwa klasy
/// i rozmiar) oraz obie decyzje o arkuszach. Trzy kopie tej samej reguły rozjeżdżają
/// się po pierwszej poprawce.
@MainActor
enum BridgeViewLookup {

    /// Poniżej tego rozmiaru „okno" prawie na pewno nie jest interfejsem, tylko
    /// czymś technicznym, co przecisnęło się przez filtry.
    static let minimalnyBokOkna: CGFloat = 120

    // MARK: - Okna

    /// Widoczne okna po odsianiu ikonki paska menu i popoverów.
    ///
    /// ⚠️ Nazwy klas wewnętrznych AppKit nie są częścią żadnego kontraktu — po zmianie
    /// w systemie ten filtr przestanie odsiewać. Dlatego **nie jest jedynym sitem**:
    /// przy zrzucie stoi drugie, niezależne, oparte na rozmiarze (audyt 2026-08-02,
    /// P2-07). Gdy pierwsze umrze po cichu, drugie zgłosi błąd.
    ///
    /// 🔴 **To jest JEDYNE miejsce, w którym rozstrzyga się, co jest oknem aplikacji.**
    /// Do 2026-08-28 `GET /windows` szedł wprost po `NSApplication.shared.windows`
    /// i pokazywał okno, które ten filtr odrzuca — czyli dwa endpointy tej samej warstwy
    /// miały dwie definicje okna. Zmierzone na MarkReadzie i na demie: `/windows`
    /// zwracał `NSStatusBarWindow | Item-0 | 32×33`, a `?window=Item-0` wracało z 404
    /// i listą, w której tego okna nie było. Audyt 2026-08-28, E5-P2-01.
    static func kandydaci() -> (widoczne: [NSWindow], kandydaci: [NSWindow]) {
        let widoczne = NSApplication.shared.windows.filter(\.isVisible)
        let kandydaci = widoczne.filter { powodOdsiania($0) == nil }
        return (widoczne, kandydaci)
    }

    /// Dlaczego to okno **nie** jest oknem interfejsu aplikacji — albo `nil`, gdy jest.
    ///
    /// 🔴 O oknie paska menu rozstrzyga **tożsamość obiektu**, nie nazwa klasy —
    /// patrz `powodOdsiania(klasa:toIkonkaMostu:)`.
    static func powodOdsiania(_ okno: NSWindow) -> String? {
        powodOdsiania(
            klasa: String(describing: type(of: okno)),
            toIkonkaMostu: BridgeStatusItem.toOknoIkonkiMostu(okno)
        )
    }

    /// Sam wyrok, po nazwie klasy. `nonisolated` i na napisie, żeby dało się sprawdzić
    /// testem bez stawiania okna na ekranie — a to jest reguła, która rozstrzyga
    /// o odpowiedzi pięciu endpointów, więc ma mieć test.
    ///
    /// 🔴 **`toIkonkaMostu` jest osobnym parametrem, bo nazwa klasy tego nie rozstrzyga.**
    /// Do 2026-08-29 każde okno klasy `NSStatusBarWindow` szło do kosza z uzasadnieniem
    /// „należy do ikonki mostu" — **także wtedy, gdy most żadnej ikonki nie postawił**
    /// (`showMenuBarIcon: false`) i gdy okno należało do GOSPODARZA. W aplikacji paska
    /// menu, gdzie okno statusu **jest** całym interfejsem, oślepiało to most na wszystko:
    /// `/windows` pustka, a `/screenshot`, `/render`, `/hit` i `/text-attributes` odmowa
    /// braku okna. Zmierzone na dwóch niezależnych gospodarzach — Stats i alt-tab-macos
    /// (kampania na cudzym kodzie, 2026-08-29, pozycja 4a).
    ///
    /// Przyrząd ma nie zmieniać wyniku pomiaru, ale wolno mu odsiać **wyłącznie własną**
    /// ikonkę, rozpoznaną po tożsamości okna, nie po nazwie jego klasy.
    nonisolated static func powodOdsiania(klasa: String, toIkonkaMostu: Bool) -> String? {
        if klasa.contains("StatusBar") {
            // Okno paska menu GOSPODARZA jest jego interfejsem — zostaje.
            guard toIkonkaMostu else { return nil }
            // A to jest okno ikonki MOSTU, czyli przyrządu. Meldowanie go jako okna
            // programu znaczyłoby, że przyrząd zmienia wynik pomiaru.
            return "okno techniczne paska menu (\(klasa)) — należy do ikonki mostu, "
                + "nie do aplikacji"
        }
        if klasa.contains("PopoverWindow") {
            return "popover (\(klasa)), nie okno aplikacji"
        }
        return nil
    }

    /// Wybiera okno: po fragmencie tytułu lub klasy, a bez wskazania — automatycznie.
    ///
    /// 🔴 Arkusz wskazuje się **klasą, nie tytułem** (`?window=SheetPresentation`):
    /// arkusze mają `title` pusty, więc do 2026-08-12 furtka `?window=` była dla nich
    /// martwa. Wybór automatyczny arkusze pomija — systemowy arkusz zapisu nie żyje
    /// w procesie aplikacji i `cacheDisplay` zwraca z niego **pustą klatkę przy kodzie
    /// 200** (zmierzone 2026-08-11).
    static func wybierzOkno(tytul: String?) throws -> NSWindow {
        let (widoczne, kandydaci) = kandydaci()

        guard !kandydaci.isEmpty else {
            throw bladBrakuOkna(widoczne: widoczne, kandydaci: kandydaci)
        }

        guard let tytul, !tytul.isEmpty else {
            // Wybór automatyczny: aktywne → główne → największe zdolne być głównym
            // → największe jakiekolwiek. Rozmiar jako ostateczne kryterium, bo okno
            // z interfejsem jest praktycznie zawsze największe.
            let bezArkuszy = kandydaci.filter { !$0.isSheet }
            let pula = bezArkuszy.isEmpty ? kandydaci : bezArkuszy
            let najwieksze: (NSWindow, NSWindow) -> Bool = { a, b in
                a.frame.width * a.frame.height < b.frame.width * b.frame.height
            }
            let wybrane = pula.first(where: \.isKeyWindow)
                ?? pula.first(where: \.isMainWindow)
                ?? pula.filter(\.canBecomeMain).max(by: najwieksze)
                ?? pula.max(by: najwieksze)!
            try sprawdzRozmiar(wybrane, widoczne: widoczne, kandydaci: kandydaci)
            return wybrane
        }

        let poTytule = kandydaci.first { $0.title.localizedCaseInsensitiveContains(tytul) }
        let poKlasie = kandydaci.first {
            String(describing: type(of: $0)).localizedCaseInsensitiveContains(tytul)
        }
        guard let match = poTytule ?? poKlasie else {
            throw BridgeError.notFound(
                "Nie znaleziono okna pasującego do \"\(tytul)\" — ani tytułem, ani klasą. "
                + "Dostępne: \(opisOkien(kandydaci))"
            )
        }
        return match
    }

    /// Drugie, niezależne sito: **rozmiar**.
    ///
    /// 🔴 Nazwy prywatnych klas AppKit nie są częścią żadnego kontraktu (audyt
    /// 2026-08-02, P2-07), więc pierwsze sito — po nazwie klasy — może po zmianie
    /// w systemie przestać odsiewać **po cichu**. Odpowiedzią było sito po rozmiarze.
    ///
    /// Do 2026-08-28 stało ono w jednym miejscu, w `BridgeScreenshot`. Gdy refaktor
    /// z 2026-08-27 wyprowadził wybór okna tutaj i podpiął pod niego pięć kolejnych
    /// endpointów, sito zostało tam, gdzie było — więc `/render`, `/hit`,
    /// `/text-attributes` i `/drawn-rects` **nie miały drugiego zamka wcale**. Gdyby
    /// macOS przemianował `NSStatusBarWindow`, zrzut zgłosiłby błąd, a tamte cztery
    /// oddałyby kod 200: obrazek wielkości ikonki paska menu, atrybuty tekstu z okna
    /// bez tekstu, trafienie w punkt spoza interfejsu. Audyt 2026-08-28, E1-P2-01.
    ///
    /// ⚠️ Sprawdzane **wyłącznie przy wyborze automatycznym**. Kto podaje `?window=`,
    /// ten wie, czego chce — a aplikacja z celowo małym oknem narzędziowym ma prawo
    /// je zrenderować. Zrzut zachowuje własne, bezwarunkowe sprawdzenie.
    /// Odmowa, gdy aplikacja nie ma ani jednego okna z interfejsem.
    ///
    /// 🔴 **404, nie 500.** Do 2026-08-28 leciało stąd `.failed`, czyli
    /// `500 Internal Server Error` — a to nieprawda w dwie strony: most działa
    /// (odpowiada na `/ping` w tej samej sekundzie), a aplikacja jest zdrowa.
    /// Zmierzone na `innym gospodarzu`: ten program po zamknięciu okna **z zasady**
    /// chodzi dalej w pasku menu (decyzja [U] 2026-08-20), więc „nie ma okna" jest
    /// tam **normalnym stanem pracy**, a nie awarią. `wybierzOkno` odpowiadało na
    /// dwa bliźniacze braki dwoma różnymi kodami: „nie ma okna pasującego do tytułu"
    /// → 404, „nie ma okna w ogóle" → 500. Ta sama funkcja, ta sama rodzina stanu.
    ///
    /// Kod stanu jest jedyną częścią odmowy, którą czyta pośrednik: 5xx znaczy
    /// „ponów, coś się zepsuło", a tu ponawianie nic nie da, dopóki okna nie otworzy
    /// człowiek albo `POST /window/open`.
    ///
    /// 🔴 Nie mieszać z `sprawdzRozmiar` niżej — TAMTA odmowa zostaje na 500,
    /// bo opisuje defekt **mostu** (sito nazw klas przestało odsiewać), a nie stan
    /// aplikacji.
    static func bladBrakuOkna(widoczne: [NSWindow], kandydaci: [NSWindow]) -> BridgeError {
        let openery = BridgeWindows.zgloszone.map(\.nazwa)
        let podpowiedz = openery.isEmpty
            ? "Aplikacja nie zgłosiła też żadnego sposobu otwarcia okna "
              + "(BridgeWindows.registerOpener)."
            : "Otwórz je najpierw: POST /window/open {\"okno\": \"\(openery[0])\"}. "
              + "Zgłoszone okna: \(openery.joined(separator: ", "))."
        // 🔴 Licznik liczy KANDYDATÓW, nie wszystkie widoczne. Do 2026-08-28 podawał
        // `widoczne.count` sprzed sita, więc przy samej ikonce paska menu komunikat
        // brzmiał "nie ma żadnego widocznego okna… Widocznych okien łącznie: 1"
        // i przeczył sam sobie. Zmierzone na MarkReadzie. E5-P2-01.
        let odsiane = widoczne.count - kandydaci.count
        let opisOdsianych = odsiane == 0
            ? ""
            : " Okien odsianych jako techniczne: \(odsiane) "
              + "(\(opisOkien(widoczne.filter { powodOdsiania($0) != nil }))). "
              + "Widać je w GET /windows w polu \"odsiane\", razem z powodem."
        return BridgeError.notFound(
            "Aplikacja nie ma żadnego okna z interfejsem. \(podpowiedz) "
            + "Zrzut celowo nie otwiera okna sam — decyzja [U] 2026-08-27: "
            + "odczyt nie ma zmieniać tego, co widać na ekranie."
            + opisOdsianych
        )
    }

    static func sprawdzRozmiar(
        _ okno: NSWindow,
        widoczne: [NSWindow],
        kandydaci: [NSWindow]
    ) throws {
        let rozmiar = okno.frame.size
        guard rozmiar.width < minimalnyBokOkna || rozmiar.height < minimalnyBokOkna else { return }

        // 🔴 Okno paska menu GOSPODARZA jest małe z natury i to jest jego interfejs,
        // a nie objaw zepsutego sita (pozycja 4a, 2026-08-29). Bez tego wyjątku naprawa
        // 4a przesuwałaby tylko odmowę: zamiast „brak okna" z /windows dostawalibyśmy
        // 500 z tego zamka, na aplikacji paska menu za każdym razem.
        guard !String(describing: type(of: okno)).contains("StatusBar") else { return }

        throw BridgeError.failed(
            "Automatycznie wybrane okno ma \(Int(rozmiar.width))×\(Int(rozmiar.height)) punktów "
            + "— to za mało, żeby był to interfejs aplikacji. Prawdopodobnie sito nazw klas "
            + "przestało odsiewać okna techniczne (popover, arkusz) i wybór padł "
            + "na jedno z nich. Okna paska menu gospodarza są z tego zamka wyjęte świadomie. "
            + "Widocznych okien: \(widoczne.count), kandydatów: \(kandydaci.count). "
            + "Jeśli to okno naprawdę jest tym, o które chodzi, wskaż je wprost: ?window=\(okno.title.isEmpty ? String(describing: type(of: okno)) : okno.title)"
        )
    }

    /// Lista okien w postaci, z której da się wybrać następne wywołanie.
    ///
    /// Sama kolekcja tytułów dawała przy arkuszach `"", "", ""` — z czego nie da się
    /// wybrać niczego. Klasa, rozmiar i znacznik arkusza mówią, co jest do wzięcia.
    static func opisOkien(_ okna: [NSWindow]) -> String {
        okna.map { okno -> String in
            let klasa = String(describing: type(of: okno))
            let rozmiar = "\(Int(okno.frame.width))×\(Int(okno.frame.height))"
            let arkusz = okno.isSheet ? " [arkusz]" : ""
            let nazwa = okno.title.isEmpty ? "(bez tytułu)" : "\"\(okno.title)\""
            return "\(nazwa) — \(klasa), \(rozmiar)\(arkusz)"
        }.joined(separator: "; ")
    }

    /// Widok ramki okna — ten sam, który rysuje `/screenshot`.
    ///
    /// Celowo nadrzędny widok ramki, a nie samo `contentView`: `contentView` to
    /// wyłącznie wnętrze okna, bez tła i belki tytułowej, co w trybie ciemnym daje
    /// biały tekst na białym tle. Wszystkie współrzędne obrazkowe liczą się względem
    /// **tego** widoku, żeby punkt odczytany z PNG dało się podać w `/hit`.
    static func widokRamki(_ okno: NSWindow) throws -> NSView {
        guard let content = okno.contentView else {
            throw BridgeError.failed("Okno \"\(okno.title)\" nie ma zawartości do narysowania")
        }
        return content.superview ?? content
    }

    // MARK: - Widoki

    /// Wszystkie widoki okna, od korzenia w głąb, w kolejności rysowania.
    static func wszystkieWidoki(w okno: NSWindow) -> [NSView] {
        guard let korzen = try? widokRamki(okno) else { return [] }
        var wynik: [NSView] = []
        func zejdz(_ view: NSView) {
            wynik.append(view)
            for pod in view.subviews { zejdz(pod) }
        }
        zejdz(korzen)
        return wynik
    }

    /// Znajduje widok po wskazaniu: identyfikator dostępności, `identifier` albo
    /// fragment nazwy klasy. Bez wskazania oddaje widok ramki.
    ///
    /// Kolejność dopasowania jest od najbardziej jednoznacznego do najluźniejszego,
    /// żeby `view=Editor` nie trafiało w przypadkowy widok wewnętrzny, gdy w oknie
    /// stoi widok o dokładnie takim identyfikatorze.
    static func znajdzWidok(_ wskaznik: String?, w okno: NSWindow) throws -> NSView {
        try znajdzWidokZLiczba(wskaznik, w: okno).widok
    }

    /// To samo, ale mówi też, **ilu** widoków dotyczyło wskazanie.
    ///
    /// 🔴 Dopasowanie jest luźne z rozmysłu — bez fragmentów trzeba by znać dokładny
    /// identyfikator. Ceną jest to, że jedna litera trafia w cokolwiek: zmierzone
    /// 2026-08-28 na demie, `?view=View` wybierało `NSVisualEffectView` (widok
    /// **wewnętrzny AppKit**), a `?view=e` — pole tekstowe. Przy dwóch pasujących
    /// wygrywa pierwszy w kolejności rysowania i nikt się o drugim nie dowiaduje.
    /// Dlatego liczba trafień wychodzi na zewnątrz i `/render` podaje ją w nagłówku:
    /// luźne sito wolno mieć, milczeć o jego wyniku — nie. Audyt 2026-08-28, E5-P2-06.
    static func znajdzWidokZLiczba(
        _ wskaznik: String?,
        w okno: NSWindow
    ) throws -> (widok: NSView, trafien: Int) {
        let korzen = try widokRamki(okno)
        guard let wskaznik, !wskaznik.isEmpty else { return (korzen, 1) }

        let widoki = wszystkieWidoki(w: okno)
        let dokladnyIdentyfikator = widoki.first {
            $0.identifier?.rawValue.localizedCaseInsensitiveCompare(wskaznik) == .orderedSame
                || $0.accessibilityIdentifier().localizedCaseInsensitiveCompare(wskaznik) == .orderedSame
        }
        let fragmentIdentyfikatora = widoki.first {
            ($0.identifier?.rawValue.localizedCaseInsensitiveContains(wskaznik) ?? false)
                || $0.accessibilityIdentifier().localizedCaseInsensitiveContains(wskaznik)
        }
        let poKlasie = widoki.first {
            String(describing: type(of: $0)).localizedCaseInsensitiveContains(wskaznik)
        }

        guard let znaleziony = dokladnyIdentyfikator ?? fragmentIdentyfikatora ?? poKlasie else {
            throw BridgeError.notFound(
                "Nie znaleziono widoku pasującego do \"\(wskaznik)\" w oknie "
                + "\(okno.title.isEmpty ? String(describing: type(of: okno)) : okno.title). "
                + "Dostępne: \(opisWidokow(widoki))"
            )
        }
        // Liczymy trafienia tego samego szczebla, na którym padł wybór — inaczej
        // „trafień: 7" przy dokładnym identyfikatorze straszyłoby bez powodu.
        let trafien: Int
        if dokladnyIdentyfikator != nil {
            trafien = widoki.count {
                $0.identifier?.rawValue.localizedCaseInsensitiveCompare(wskaznik) == .orderedSame
                    || $0.accessibilityIdentifier().localizedCaseInsensitiveCompare(wskaznik) == .orderedSame
            }
        } else if fragmentIdentyfikatora != nil {
            trafien = widoki.count {
                ($0.identifier?.rawValue.localizedCaseInsensitiveContains(wskaznik) ?? false)
                    || $0.accessibilityIdentifier().localizedCaseInsensitiveContains(wskaznik)
            }
        } else {
            trafien = widoki.count {
                String(describing: type(of: $0)).localizedCaseInsensitiveContains(wskaznik)
            }
        }
        return (znaleziony, trafien)
    }

    /// Identyfikator widoku do nagłówka odpowiedzi — przycięty i czysto ASCII.
    ///
    /// Nagłówki HTTP są z definicji ASCII, a identyfikator dostępności bywa tekstem
    /// dla człowieka, więc mógłby nieść ogonki albo emoji.
    nonisolated static func doNaglowka(_ tekst: String, limit: Int = 80) -> String {
        let czysty = tekst.unicodeScalars
            .filter { $0.value >= 32 && $0.value < 127 && $0 != ":" }
            .map(Character.init)
        let napis = String(czysty)
        return napis.count > limit ? String(napis.prefix(limit)) + "…" : napis
    }

    /// Pierwszy `NSTextView` w oknie — albo ten wskazany przez `view=`.
    static func znajdzTextView(_ wskaznik: String?, w okno: NSWindow) throws -> NSTextView {
        let widoki = wszystkieWidoki(w: okno)
        if let wskaznik, !wskaznik.isEmpty {
            let widok = try znajdzWidok(wskaznik, w: okno)
            if let text = widok as? NSTextView { return text }
            // Wskazano kontener (np. NSScrollView) — bierzemy pole tekstowe w środku.
            if let text = widoki.first(where: { $0 is NSTextView && $0.isDescendant(of: widok) })
                as? NSTextView {
                return text
            }
            // Widok się znalazł, ale nie jest tekstem — to inna pomyłka niż „nie ma
            // żadnego pola tekstowego", więc i komunikat musi być inny.
            throw BridgeError.notFound(
                "Widok \"\(wskaznik)\" to \(String(describing: type(of: widok))), "
                + "a nie pole tekstowe. Pola tekstowe w tym oknie: "
                + "\(opisWidokow(widoki.filter { $0 is NSTextView }))"
            )
        }
        guard let text = widoki.compactMap({ $0 as? NSTextView }).first else {
            throw BridgeError.notFound(
                "To okno nie ma pola tekstowego (NSTextView). Widoki w oknie: "
                + "\(opisWidokow(widoki))"
            )
        }
        return text
    }

    /// Krótki opis listy widoków do komunikatów błędu. Bez tego „nie znalazłem"
    /// nie prowadzi do niczego — nie wiadomo, czego szukać zamiast.
    static func opisWidokow(_ widoki: [NSView], limit: Int = 25) -> String {
        guard !widoki.isEmpty else { return "brak" }
        let opisy = widoki.prefix(limit).map { view -> String in
            let klasa = String(describing: type(of: view))
            let id = view.identifier?.rawValue ?? view.accessibilityIdentifier()
            let nazwa = id.isEmpty ? "" : " #\(id)"
            return "\(klasa)\(nazwa) \(Int(view.bounds.width))×\(Int(view.bounds.height))"
        }.joined(separator: "; ")
        return widoki.count > limit ? "\(opisy) … (\(widoki.count) łącznie)" : opisy
    }

    // MARK: - Współrzędne

    /// Punkt w **zwrocie osi obrazka** (początek w lewym górnym rogu, jak w PNG
    /// ze `/screenshot`) na współrzędne widoku ramki (AppKit: początek w lewym dolnym).
    ///
    /// 🔴 Zamieniany jest **wyłącznie zwrot osi, nie jednostka**. Do 2026-08-28 stało
    /// tu, że dzięki temu `/hit` da się wołać „współrzędnymi odczytanymi wprost
    /// z podglądu zrzutu" — i to była nieprawda: PNG powstaje w skali ekranu, więc
    /// liczba z obrazka jest `backingScaleFactor` razy za duża. Skalę podaje teraz
    /// `/screenshot` w nagłówku, a `/hit` nazywa jednostkę w każdej odpowiedzi.
    /// [[Problem-hit-czyta-punkty-a-zrzut-oddaje-piksele]]
    static func punktZObrazu(x: CGFloat, y: CGFloat, ramka: NSView) -> CGPoint {
        CGPoint(x: x, y: ramka.bounds.height - y)
    }

    /// Prostokąt widoku w układzie **obrazka** — początek w lewym górnym rogu, w punktach.
    ///
    /// 🔴 **Pola `x`/`y`/`szerokosc`/`wysokosc` są przycięte do obrazka i nigdy z niego
    /// nie wychodzą** (pozycja 4c, 2026-08-29). Do tego dnia `wObrazie` potrafiło wskazać
    /// miejsce, którego na zrzucie nie ma: widok dokumentu w `NSScrollView` ma `bounds`
    /// całej przewijanej treści, więc zgłaszał wysokość **693 pt przy obrazku 448 pt** na
    /// demie i **34 360 pt przy 848 pt** — czterdziestokrotnie — w sidebarze NetNewsWire'a.
    /// Nazwa pola obiecywała „w obrazie", a wołający brał te liczby do oglądania PNG.
    ///
    /// Geometrii nie gubimy: gdy widok wystaje, dochodzi `przyciety: true` i `pelny`
    /// z prawdziwym prostokątem. Gdy leży w całości poza kadrem — `widoczny: false`
    /// i wymiary zerowe, bo „widać go tu i tu" byłoby wtedy kłamstwem.
    static func prostokatWObrazie(_ view: NSView, ramka: NSView) -> [String: Any] {
        prostokatWObrazie(view.convert(view.bounds, to: ramka), ramka: ramka)
    }

    /// Ta sama reguła dla gotowego prostokąta w układzie ramki — bez widoku.
    ///
    /// 🔴 Osobna, bo prostokąt wiersza tabeli nie ma swojego `NSView`, a **dokładanie
    /// pomocniczego widoku do okna gospodarza jest zakazane**: odczyt nie ma zmieniać
    /// tego, co widać na ekranie (decyzja [U] 2026-08-27).
    /// Sam zwrot osi Y — bez przycięcia i bez opisu.
    ///
    /// 🔴 Osobna, bo do 2026-09-02 tę samą arytmetykę liczyły **trzy miejsca**
    /// (`prostokatWObrazie` i dwa razy `BridgeDrawnRects`), a przycięcie z pozycji 4c
    /// weszło tylko do jednego. `/drawn-rects` oddawał wtedy wysokość 527 pt na obrazku
    /// 448 pt, podczas gdy `/hit` dla tego samego widoku mówił 282 z `przyciety: true` —
    /// obie liczby w jednej odpowiedzi. Kto potrzebuje prostokąta, a nie opisu, woła to.
    static func wObrazie(_ wRamce: CGRect, ramka: NSView) -> CGRect {
        CGRect(
            x: wRamce.minX,
            y: ramka.bounds.height - wRamce.maxY,
            width: wRamce.width,
            height: wRamce.height
        )
    }

    /// - Parameter setne: `true` oddaje liczby z dokładnością do setnych punktu zamiast
    ///   pełnych. Bierze to `/drawn-rects`, bo tam **cała rzecz polega** na wyłapaniu
    ///   przesunięcia o ułamek punktu między dwoma tłami — po zaokrągleniu do jedności
    ///   znikłoby dokładnie to, czego się szuka.
    static func prostokatWObrazie(_ wRamce: CGRect, ramka: NSView, setne: Bool = false) -> [String: Any] {
        let pelny = wObrazie(wRamce, ramka: ramka)
        let kadr = CGRect(origin: .zero, size: ramka.bounds.size)
        let widoczny = pelny.intersection(kadr)

        func liczba(_ wartosc: CGFloat) -> Any {
            setne ? (Double(wartosc) * 100).rounded() / 100 : Int(wartosc.rounded())
        }

        func opisz(_ r: CGRect) -> [String: Any] {
            [
                "x": liczba(r.minX),
                "y": liczba(r.minY),
                "szerokosc": liczba(r.width),
                "wysokosc": liczba(r.height),
            ]
        }

        // `intersection` daje `.null` przy braku części wspólnej — a `.null` ma
        // nieskończone współrzędne i po zaokrągleniu wysypałby JSON.
        guard !widoczny.isNull, !widoczny.isEmpty else {
            var opis: [String: Any] = opisz(.zero)
            opis["widoczny"] = false
            opis["przyciety"] = true
            opis["pelny"] = opisz(pelny)
            opis["uwaga"] = "Ten widok w całości leży poza kadrem zrzutu — na obrazku go nie ma."
            return opis
        }

        var opis: [String: Any] = opisz(widoczny)
        opis["widoczny"] = true
        let wystaje = !kadr.contains(pelny)
        opis["przyciety"] = wystaje
        if wystaje {
            opis["pelny"] = opisz(pelny)
            opis["uwaga"] = "Widok wystaje poza kadr zrzutu (zwykle treść w NSScrollView). "
                + "Pola x/y/szerokosc/wysokosc opisują WIDOCZNY wycinek; cały prostokąt jest w \"pelny\"."
        }
        return opis
    }
}

#endif

// ────────────────────────────────────────────────────────────────────────
// BridgeWindows.swift
// ────────────────────────────────────────────────────────────────────────


#if canImport(AppKit)

/// Sposób otwarcia jednego okna, zgłoszony przez aplikację.
///
/// Most jest generyczny z założenia i **nie wie nic o konkretnej aplikacji** —
/// „otwórz okno" jest z natury wiedzą aplikacji, nie biblioteki. Dlatego kit daje
/// tu wyłącznie gniazdo, a wiedzę wnosi program jednym wywołaniem przy starcie.
/// Decyzja [U] 2026-08-27 (plan „Most musi umieć otworzyć sobie okno", pytanie 1).
nonisolated public struct BridgeWindowOpener: Sendable {
    /// Nazwa używana w `POST /window/open {"okno": "..."}`. Bez rozróżniania wielkości liter.
    public let nazwa: String
    /// Zdanie dla człowieka po drugiej stronie mostu — co to okno pokazuje.
    public let opis: String
    /// Samo otwarcie. Wykonywane na głównym aktorze, bo dotyka interfejsu.
    public let otworz: @MainActor @Sendable () -> Void

    public init(
        nazwa: String,
        opis: String = "",
        otworz: @escaping @MainActor @Sendable () -> Void
    ) {
        self.nazwa = nazwa
        self.opis = opis
        self.otworz = otworz
    }
}

/// Okna aplikacji widziane od strony mostu: co jest otwarte i czym to otworzyć.
///
/// 🔴 **Akcja widoczna dla użytkownika** — okno pojawia się na ekranie, potencjalnie
/// na wierzchu tego, co właśnie robi. Zmierzone 2026-08-28: po `POST /window/open`
/// aplikacją na wierzchu przestaje być ta, w której [U] pisał (Finder → demo),
/// podczas gdy `GET /windows` i `GET /screenshot` ogniska nie ruszają.
///
/// ⚠️ **Nie jest to JEDYNA taka akcja i do 2026-08-28 dokumentacja twierdziła inaczej.**
/// Zmierzone tym samym mostem: `POST /appearance` przemalowuje **99,72 %** pikseli
/// widoku, a `POST /defaults` potrafi zmienić układ tak, że widok rośnie 3,5×
/// (920×1050 → 920×3696 px przy zmianie rozmiaru kroju). Trzecia to `GET /render`
/// z `?width=`, który na chwilę zmienia ramkę żywego widoku — o czym mówi komentarz
/// w `BridgeRender.swift`. Pełna tabela „czy [U] to zobaczy" jest w `README.md`.
///
/// Dwie decyzje [U] z 2026-08-27, których nie zmieniaj bez pytania:
/// - **Okno zostaje otwarte po zrzucie.** Most nie zamyka cudzych okien, bo nie ma
///   jak odróżnić okna, które sam przed chwilą otworzył, od tego, które w międzyczasie
///   otworzył użytkownik.
/// - **`/screenshot` nie otwiera okna sam.** Zrzut zostaje operacją tylko do odczytu;
///   gdy okna nie ma, komunikat błędu odsyła do `POST /window/open`.
@MainActor
public enum BridgeWindows {

    private static var openery: [BridgeWindowOpener] = []

    /// Zgłasza mostowi, jak otworzyć okno tej aplikacji.
    ///
    /// Wywołaj przy starcie, obok `BridgeServer.start`. Nazwa jest kluczem w żądaniu;
    /// przy jednym oknie wystarczy zostawić domyślną.
    ///
    /// ```swift
    /// BridgeWindows.registerOpener(nazwa: "procesy", opis: "Lista procesów") {
    ///     ProcesyWindowController.shared.showWindow(nil)
    /// }
    /// ```
    ///
    /// W RELEASE metoda jest pusta — powód i mechanizm ten sam co przy
    /// `BridgeRegistry.registerOnMainActor`: `@inlinable` z pustym ciałem pozwala
    /// optymalizatorowi wyrzucić także literały nazwy i opisu, które są argumentami
    /// budowanymi w kodzie aplikacji, więc samo `#if DEBUG` w środku ich nie usuwa.
    @inlinable
    public static func registerOpener(
        nazwa: String = "domyslne",
        opis: String = "",
        _ otworz: @escaping @MainActor @Sendable () -> Void
    ) {
        #if DEBUG
        register(BridgeWindowOpener(nazwa: nazwa, opis: opis, otworz: otworz))
        #endif
    }

    /// Rejestracja gotowym opisem. Publiczna, bo woła ją `@inlinable` wyżej.
    public static func register(_ opener: BridgeWindowOpener) {
        #if DEBUG
        openery.removeAll { $0.nazwa.lowercased() == opener.nazwa.lowercased() }
        openery.append(opener)
        #endif
    }

    /// Zgłoszone sposoby otwierania — do `/windows` i do komunikatów błędu.
    public static var zgloszone: [BridgeWindowOpener] { openery }

    /// Czyści rejestr. **Wyłącznie dla testów** — rejestr jest globalny, więc bez
    /// tego test „aplikacja nic nie zgłosiła" zależałby od kolejności testów.
    /// Celowo `internal`: aplikacja-gospodarz nie ma powodu wypinać openerów w locie.
    static func wyczysc() {
        openery.removeAll()
    }

    /// Otwiera okno o podanej nazwie (albo jedyne zgłoszone, gdy nazwy nie podano).
    ///
    /// Zwraca nazwę użytego openera. Rzuca `BridgeError`, gdy aplikacja nic nie
    /// zgłosiła albo gdy nazwa nie pasuje — w obu wypadkach komunikat mówi, co zrobić,
    /// zamiast po cichu nie zrobić nic.
    static func otworz(nazwa: String?) throws -> String {
        guard !openery.isEmpty else {
            throw BridgeError.notFound(
                "Ta aplikacja nie zgłosiła mostowi, jak otworzyć swoje okno. "
                + "Most nie zgaduje: dopisz w niej jedno wywołanie "
                + "BridgeWindows.registerOpener { … } obok BridgeServer.start "
                + "(README, sekcja „Otwieranie okna z paska menu\")."
            )
        }

        let opener: BridgeWindowOpener
        if let nazwa, !nazwa.isEmpty {
            guard let znaleziony = openery.first(where: {
                $0.nazwa.localizedCaseInsensitiveCompare(nazwa) == .orderedSame
            }) else {
                let dostepne = openery.map(\.nazwa).joined(separator: ", ")
                throw BridgeError.notFound(
                    "Aplikacja nie zgłosiła okna o nazwie \"\(nazwa)\". Dostępne: \(dostepne)"
                )
            }
            opener = znaleziony
        } else {
            opener = openery[0]
        }

        opener.otworz()
        return opener.nazwa
    }

    // 🔴 Pod `#if DEBUG` od 2026-08-29 (audyt, E5N-P1-01). Ten typ jest w `PUSTE_API`,
    // czyli WOLNO mu zostać w wydaniu — ale wolno mu zostać jako **nazwa bez ciała**.
    // Funkcje niżej wołają `BridgeViewLookup`, czyli implementację, więc bez tej
    // dyrektywy wciągałyby ją z powrotem do binarki gospodarza. Puste API przestaje
    // być puste dokładnie w tym miejscu.
    #if DEBUG
    /// Opis okien **aplikacji** — tych, które reszta warstwy uznaje za okna.
    ///
    /// Sama lista tytułów bywa bezużyteczna: arkusze mają `title` pusty, więc przy
    /// trzech arkuszach dostawało się `"", "", ""`. Klasa, rozmiar i znacznik arkusza
    /// mówią, co w ogóle jest do wzięcia (znalezisko 2026-08-12).
    ///
    /// 🔴 Lista idzie z `BridgeViewLookup.kandydaci()`, czyli z **tego samego sita**,
    /// którym `wybierzOkno` wybiera okno dla `/screenshot`, `/render`, `/hit`,
    /// `/text-attributes` i `/drawn-rects`. Do 2026-08-28 ta funkcja czytała wprost
    /// `NSApplication.shared.windows` i pokazywała okno ikonki paska menu — czyli okno
    /// **mostu** — którego wszystkie pozostałe endpointy odrzucały z 404 i listą,
    /// w której go nie było. Audyt 2026-08-28, E5-P2-01.
    static func opisWidocznychOkien() -> [[String: Any]] {
        BridgeViewLookup.kandydaci().kandydaci.map(opis)
    }

    /// Okna odsiane jako techniczne — **razem z powodem**.
    ///
    /// Informacja nie znika, tylko przestaje udawać okno gospodarza. Bez tej listy
    /// naprawa E5-P2-01 zabierałaby agentowi wiedzę, że coś w ogóle jest na ekranie.
    static func opisOdsianychOkien() -> [[String: Any]] {
        let (widoczne, _) = BridgeViewLookup.kandydaci()
        return widoczne.compactMap { okno in
            guard let powod = BridgeViewLookup.powodOdsiania(okno) else { return nil }
            var wpis = opis(okno)
            wpis["powod"] = powod
            return wpis
        }
    }

    private static func opis(_ okno: NSWindow) -> [String: Any] {
        [
            "tytul": okno.title,
            "klasa": String(describing: type(of: okno)),
            "szerokosc": Int(okno.frame.width),
            "wysokosc": Int(okno.frame.height),
            "arkusz": okno.isSheet,
            "kluczowe": okno.isKeyWindow,
            "glowne": okno.isMainWindow,
            // 🔴 Kierunek układu jest per okno, nie tylko per aplikacja — okno może
            // wymusić swój (pozycja 4h, 2026-08-29). Bez tego pola czytający zrzut
            // z interfejsu RTL nie wie, że „lewa krawędź" znaczy tam koniec wiersza.
            "kierunekUkladu": BridgeAppearance.kierunekOkna(okno),
        ]
    }
    #endif
}

#endif

// ────────────────────────────────────────────────────────────────────────
// JSONProblem.swift
// ────────────────────────────────────────────────────────────────────────


/// Tłumaczy „ten obiekt nie nadaje się na JSON" na zdanie, po którym widać,
/// **którego pola** szukać w kodzie endpointu.
///
/// `JSONSerialization.isValidJSONObject` mówi tylko tak albo nie. Przy słowniku
/// stanu aplikacji z kilkunastoma polami sama odmowa nie wystarcza — stąd
/// przejście po strukturze i wskazanie pierwszej winnej wartości ze ścieżką.
// 🔴 Cały plik pod `#if DEBUG` — tak jak reszta implementacji kitu.
//
// Do 2026-08-29 był JEDYNYM plikiem implementacji bez tej dyrektywy i jako jedyny typ
// spoza `PUSTE_API` przeżywał build RELEASE razem z ciałami trzech funkcji (zmierzone
// `nm -a` na binarce TestRoomu: 6 trafień w RELEASE, przy 0 dla dwunastu pozostałych
// implementacji). Kod był martwy — jedyne wywołanie stoi w `BridgeResponse.json`,
// której w wydaniu nikt nie woła — ale zdanie „w RELEASE nie ma nic" przestawało
// przez niego być prawdziwe.
//
// 🔴 Nie wykrył tego `Skrypty/testroom.sh`, bo mierzył `nm -gU`, czyli same symbole
// GLOBALNE, a ten typ jest `internal`. Naprawa ma dwie połowy i druga jest w skrypcie.
// Audyt 2026-08-29, E5N-P1-01.
#if DEBUG
nonisolated enum JSONProblem {

    static func opisz(_ object: Any) -> String {
        guard object is [String: Any] || object is [Any] else {
            return "najwyższy poziom musi być słownikiem albo tablicą, a jest \(opisWartosci(object))"
        }
        return znajdz(object, sciezka: "")
            ?? "gdzieś w danych siedzi wartość niedozwolona w JSON"
    }

    /// Zwraca opis pierwszej wartości, której nie da się zapisać, albo `nil`,
    /// gdy cała struktura jest w porządku.
    private static func znajdz(_ value: Any, sciezka: String) -> String? {
        switch value {
        case let slownik as [String: Any]:
            // Kolejność posortowana, żeby ten sam błąd zawsze dawał ten sam
            // komunikat — inaczej dwa przebiegi wskazywałyby różne pola.
            //
            // Wartość bierzemy z pary, a nie przez `slownik[klucz]` — indeksowanie
            // zwraca `Any?`, więc do dalszej wędrówki poszedłby zawinięty opcjonał
            // i `type(of:)` raportowałby `Optional<Any>` zamiast prawdziwego typu.
            for (klucz, wartosc) in slownik.sorted(by: { $0.key < $1.key }) {
                let podsciezka = sciezka.isEmpty ? klucz : "\(sciezka).\(klucz)"
                if let problem = znajdz(wartosc, sciezka: podsciezka) {
                    return problem
                }
            }
            return nil

        case let tablica as [Any]:
            for (indeks, element) in tablica.enumerated() {
                if let problem = znajdz(element, sciezka: "\(sciezka)[\(indeks)]") {
                    return problem
                }
            }
            return nil

        default:
            // Pojedynczej wartości nie da się sprawdzić wprost — `isValidJSONObject`
            // wymaga na wejściu kontenera. Opakowanie w tablicę omija to ograniczenie.
            guard !JSONSerialization.isValidJSONObject([value]) else { return nil }

            let gdzie = sciezka.isEmpty ? "wartość" : "pole \"\(sciezka)\""
            if value is [AnyHashable: Any] {
                return "\(gdzie) → słownik, którego klucze nie są napisami"
            }
            return "\(gdzie) → \(opisWartosci(value))"
        }
    }

    private static func opisWartosci(_ value: Any) -> String {
        if let liczba = value as? Double {
            if liczba.isNaN {
                return "Double NaN — wynik dzielenia przez zero albo operacji nieokreślonej"
            }
            if liczba.isInfinite {
                return liczba < 0 ? "Double minus nieskończoność" : "Double nieskończoność"
            }
        }
        if let liczba = value as? Float {
            if liczba.isNaN {
                return "Float NaN — wynik dzielenia przez zero albo operacji nieokreślonej"
            }
            if liczba.isInfinite {
                return liczba < 0 ? "Float minus nieskończoność" : "Float nieskończoność"
            }
        }
        return "wartość typu \(type(of: value))"
    }
}
#endif
