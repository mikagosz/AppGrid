import AppKit
import Carbon.HIToolbox

// Harness Etapu 1b + 2 + AG-1 … AG-9 — logika, ktora da sie sprawdzic bez okien.
// GUI testuje [U]; tutaj pilnujemy tego, co ma jednoznaczna odpowiedz:
// strefy aktywnego rogu, wybor rozmiaru okna Findera i budowa sekcji "ostatnie".

var passed = 0
var failed = 0

func check(_ label: String, _ condition: Bool) {
    if condition { passed += 1 } else { failed += 1; print("  CZERWONE: \(label)") }
}

func checkEqual<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) {
    if lhs == rhs { passed += 1 } else { failed += 1; print("  CZERWONE: \(label) — jest \(lhs), ma byc \(rhs)") }
}

// ─────────────────────────────────────────────────────────────────────
// AKTYWNY ROG
// Uklad wspolrzednych: poczatek w LEWYM DOLNYM rogu, os Y w gore.
// Ekran wziety z pomiaru na Mac mini [U] (2026-08-20).
// ─────────────────────────────────────────────────────────────────────
let ekran = CGRect(x: 0, y: 0, width: 3200, height: 1800)
let bok = AktywnyRog.bokStrefy

print("PROBKA KONTROLNA: ekran \(Int(ekran.width))x\(Int(ekran.height)), strefa \(Int(bok)) px, rozbrojenie \(Int(AktywnyRog.bokRozbrojenia)) px")

func wStrefie(_ x: CGFloat, _ y: CGFloat, _ rog: RogEkranu, bok: CGFloat = AktywnyRog.bokStrefy) -> Bool {
    AktywnyRog.wStrefie(punkt: CGPoint(x: x, y: y), ekran: ekran, rog: rog, bok: bok)
}

check("lewy gorny lapie punkt przy (2, 1798)", wStrefie(2, 1798, .lewyGorny))
check("prawy gorny NIE lapie punktu z lewej strony", !wStrefie(2, 1798, .prawyGorny))
check("prawy gorny lapie punkt przy (3198, 1798)", wStrefie(3198, 1798, .prawyGorny))
check("lewy dolny lapie punkt przy (2, 2)", wStrefie(2, 2, .lewyDolny))
check("prawy dolny lapie punkt przy (3198, 2)", wStrefie(3198, 2, .prawyDolny))
check("srodek ekranu nie nalezy do zadnego rogu",
      RogEkranu.allCases.allSatisfy { !wStrefie(1600, 900, $0) })
check("punkt daleko poza ekranem nie nalezy do zadnego rogu",
      RogEkranu.allCases.allSatisfy { !wStrefie(-500, 3000, $0) })
check("kazdy rog lapie wlasny naroznik i tylko swoj", RogEkranu.allCases.allSatisfy { rog in
    let punkt: (CGFloat, CGFloat)
    switch rog {
    case .lewyGorny:  punkt = (1, 1799)
    case .prawyGorny: punkt = (3199, 1799)
    case .lewyDolny:  punkt = (1, 1)
    case .prawyDolny: punkt = (3199, 1)
    }
    return RogEkranu.allCases.allSatisfy { inny in
        wStrefie(punkt.0, punkt.1, inny) == (inny == rog)
    }
})

// Maszyna stanow: odpalamy przy WJECHANIU, nie przez caly czas postoju.
func krok(_ x: CGFloat, _ y: CGFloat, _ uzbrojony: Bool) -> (uzbrojony: Bool, odpal: Bool) {
    AktywnyRog.krok(punkt: CGPoint(x: x, y: y), ekran: ekran, rog: .lewyGorny, uzbrojony: uzbrojony)
}

let wjazd = krok(1, 1799, true)
check("wjazd w rog odpala", wjazd.odpal)
check("po odpaleniu jest rozbrojony", !wjazd.uzbrojony)

let postoj = krok(1, 1799, wjazd.uzbrojony)
check("postoj w rogu NIE odpala drugi raz", !postoj.odpal)

// 30 px od rogu: juz poza strefa odpalenia, ale wciaz w strefie rozbrojenia.
let blisko = krok(30, 1770, postoj.uzbrojony)
check("drgniecie myszy o 30 px nie uzbraja ponownie", !blisko.uzbrojony && !blisko.odpal)

let daleko = krok(1600, 900, blisko.uzbrojony)
check("odjazd na srodek ekranu uzbraja ponownie", daleko.uzbrojony && !daleko.odpal)
check("kolejny wjazd odpala znowu", krok(1, 1799, daleko.uzbrojony).odpal)

// ─────────────────────────────────────────────────────────────────────
// SKROT GLOBALNY — przeliczanie modyfikatorow
// ─────────────────────────────────────────────────────────────────────
checkEqual("sam Command przeklada sie na cmdKey",
           SkrotGlobalny.carbonModyfikatory([.command]), UInt32(cmdKey))
checkEqual("pusty zestaw modyfikatorow to zero",
           SkrotGlobalny.carbonModyfikatory([]), UInt32(0))
let trzy = SkrotGlobalny.carbonModyfikatory([.control, .option, .command])
check("trzy modyfikatory skladaja sie w jedna maske",
      trzy == UInt32(controlKey | optionKey | cmdKey))
check("maska trzech zawiera kazdy skladnik z osobna",
      trzy & UInt32(controlKey) != 0 && trzy & UInt32(optionKey) != 0 && trzy & UInt32(cmdKey) != 0)
checkEqual("klawisz bez znaku ma stala nazwe",
           SkrotGlobalny.nazwaKlawisza(kVK_Space), "Space")
let opis = SkrotGlobalny.opis(klawisz: kVK_Space, modyfikatory: [.control, .option, .command])
checkEqual("opis skrotu w kolejnosci jak w menu systemowych", opis, "⌃⌥⌘Space")

// ─────────────────────────────────────────────────────────────────────
// OKNA FINDERA — wybor rozmiaru i klucz folderu
// ─────────────────────────────────────────────────────────────────────
let globalny = CGSize(width: 1100, height: 720)
let zapamietane = ["/Users/x/Downloads": [900.0, 600.0], "/Users/x/Zle": [0.0, 600.0]]

checkEqual("klucz folderu zdejmuje schemat file:// i koncowy ukosnik",
           OknaFindera.kluczFolderu("file:///Users/x/Downloads/"), "/Users/x/Downloads")
checkEqual("ta sama sciezka bez ukosnika daje ten sam klucz",
           OknaFindera.kluczFolderu("file:///Users/x/Downloads"), "/Users/x/Downloads")
check("pusty dokument nie daje klucza", OknaFindera.kluczFolderu("") == nil)
check("brak dokumentu nie daje klucza", OknaFindera.kluczFolderu(nil) == nil)

checkEqual("tryb JEDEN DLA WSZYSTKICH ignoruje zapamietany folder",
           OknaFindera.rozmiarDlaFolderu(folder: "/Users/x/Downloads", tryb: .jedenDlaWszystkich,
                                         zapamietane: zapamietane, globalny: globalny),
           globalny)
checkEqual("tryb OSOBNO bierze rozmiar zapamietany dla folderu",
           OknaFindera.rozmiarDlaFolderu(folder: "/Users/x/Downloads", tryb: .osobnoPerFolder,
                                         zapamietane: zapamietane, globalny: globalny),
           CGSize(width: 900, height: 600))
// Decyzja [U] 2026-09-12: w trybie OSOBNO rozmiar globalny nie obowiazuje wcale.
// Folder bez wpisu ma zostac taki, jak otworzyl go Finder — czyli nil, nie globalny.
check("tryb OSOBNO bez wpisu NIE rusza okna",
      OknaFindera.rozmiarDlaFolderu(folder: "/Users/x/Nowy", tryb: .osobnoPerFolder,
                                    zapamietane: zapamietane, globalny: globalny) == nil)
check("nierozpoznany folder w trybie OSOBNO NIE rusza okna",
      OknaFindera.rozmiarDlaFolderu(folder: nil, tryb: .osobnoPerFolder,
                                    zapamietane: zapamietane, globalny: globalny) == nil)
check("zepsuty wpis (zerowa szerokosc) NIE rusza okna",
      OknaFindera.rozmiarDlaFolderu(folder: "/Users/x/Zle", tryb: .osobnoPerFolder,
                                    zapamietane: zapamietane, globalny: globalny) == nil)
checkEqual("tryb JEDEN DLA WSZYSTKICH narzuca globalny takze folderowi bez wpisu",
           OknaFindera.rozmiarDlaFolderu(folder: "/Users/x/Nowy", tryb: .jedenDlaWszystkich,
                                         zapamietane: zapamietane, globalny: globalny),
           globalny)

// Folder okna z paska okruszkow: AXDocument dla okien Findera NIE ISTNIEJE
// (zmierzone 2026-09-12: blad -25212, i to nie znika po sekundzie), wiec sciezke
// bierzemy z ostatniego elementu listy okruszkow.
func okruszek(_ sciezka: String) -> (nazwa: String, adres: URL) {
    (URL(fileURLWithPath: sciezka).lastPathComponent, URL(fileURLWithPath: sciezka))
}
let doFolderu = [okruszek("/"), okruszek("/Users"), okruszek("/Users/x/Downloads")]

checkEqual("folder okna to okruszek o nazwie z tytulu okna",
           OknaFindera.folderZOkruszkow(doFolderu, tytulOkna: "Downloads"), "/Users/x/Downloads")
// Pasek pokazuje sciezke do ZAZNACZONEGO elementu — ostatni okruszek bywa plikiem.
checkEqual("zaznaczony plik na koncu paska nie zostaje kluczem",
           OknaFindera.folderZOkruszkow(doFolderu + [okruszek("/Users/x/Downloads/plik.txt")],
                                        tytulOkna: "Downloads"),
           "/Users/x/Downloads")
// Zaznaczony pakiet aplikacji tez jest katalogiem — sprawdzanie „czy katalog" by go przepuscilo.
checkEqual("zaznaczona aplikacja w oknie Aplikacje nie zostaje kluczem",
           OknaFindera.folderZOkruszkow([okruszek("/"), (nazwa: "Aplikacje", adres: URL(fileURLWithPath: "/Applications")),
                                         okruszek("/Applications/AppGrid.app")],
                                        tytulOkna: "Aplikacje"),
           "/Applications")
checkEqual("przy powtorzonej nazwie w sciezce wygrywa OSTATNIE trafienie",
           OknaFindera.folderZOkruszkow([okruszek("/"), okruszek("/x"), okruszek("/x/robota"),
                                         okruszek("/x/robota/x")], tytulOkna: "x"),
           "/x/robota/x")
check("nic nie pasuje do tytulu — okno zostaje nietkniete",
      OknaFindera.folderZOkruszkow(doFolderu, tytulOkna: "Ostatnie") == nil)
check("brak tytulu okna nie daje klucza",
      OknaFindera.folderZOkruszkow(doFolderu, tytulOkna: nil) == nil)
check("pusta lista nie daje folderu", OknaFindera.folderZOkruszkow([], tytulOkna: "x") == nil)
checkEqual("sam korzen daje korzen",
           OknaFindera.folderZOkruszkow([(nazwa: "Macintosh HD", adres: URL(fileURLWithPath: "/"))],
                                        tytulOkna: "Macintosh HD"), "/")

// ─────────────────────────────────────────────────────────────────────
// SEKCJE "OSTATNIE" (AG-1)
// ─────────────────────────────────────────────────────────────────────
func app(_ nazwa: String, dni: Double?, system: Bool = false) -> InstalledApp {
    InstalledApp(
        id: "/Applications/\(nazwa).app",
        name: nazwa,
        url: URL(fileURLWithPath: "/Applications/\(nazwa).app"),
        category: "Inne",
        isSystem: system,
        isUtility: false,
        dataDodania: dni.map { Date(timeIntervalSinceNow: -$0 * 86_400) }
    )
}

let probka = [
    app("Swiezy", dni: 1),
    app("Wczorajszy", dni: 2),
    app("Stary", dni: 100),
    app("BezDaty", dni: nil),
    app("Systemowy", dni: 0.5, system: true),
]
let dodane = OstatnieProgramy.ostatnioDodane(probka, ile: 3)
print("PROBKA KONTROLNA: z \(probka.count) programow sekcja 'ostatnio dodane' wybrala \(dodane.count): \(dodane.map(\.name))")

checkEqual("sekcja przycieta do zamowionej liczby", dodane.count, 3)
checkEqual("najswiezszy jest pierwszy", dodane.first?.name, "Swiezy")
check("program systemowy nie wchodzi do 'ostatnio zainstalowanych'",
      !dodane.contains { $0.isSystem })
check("program bez daty dodania nie wchodzi",
      !dodane.contains { $0.name == "BezDaty" })
check("kolejnosc jest malejaca po dacie", zip(dodane, dodane.dropFirst()).allSatisfy {
    ($0.dataDodania ?? .distantPast) >= ($1.dataDodania ?? .distantPast)
})
checkEqual("zero pozycji daje pusta sekcje", OstatnieProgramy.ostatnioDodane(probka, ile: 0).count, 0)

// Remis dat rozstrzyga nazwa — inaczej kolejnosc tanczylaby przy kazdym odswiezeniu.
let remis = [app("Zebra", dni: 5), app("Alfa", dni: 5)]
checkEqual("remis dat rozstrzyga nazwa",
           OstatnieProgramy.ostatnioDodane(remis, ile: 2).map(\.name), ["Alfa", "Zebra"])

let dziennik = [
    "/Applications/Stary.app": Date(timeIntervalSinceNow: -3600),
    "/Applications/Swiezy.app": Date(timeIntervalSinceNow: -60),
]
let uzywane = OstatnieProgramy.ostatnioUzywane(probka, dziennik: dziennik, ile: 5)
checkEqual("'ostatnio uzywane' bierze tylko programy z dziennika", uzywane.count, 2)
checkEqual("ostatnio odpalony jest pierwszy", uzywane.first?.name, "Swiezy")
checkEqual("pusty dziennik daje pusta sekcje",
           OstatnieProgramy.ostatnioUzywane(probka, dziennik: [:], ile: 5).count, 0)
check("wpis w dzienniku dla programu, ktorego juz nie ma na dysku, nie wywraca sekcji",
      OstatnieProgramy.ostatnioUzywane(probka, dziennik: ["/Applications/Duch.app": Date()], ile: 5).isEmpty)

// Dziennik nie moze rosnac bez konca.
var duzy: [String: Date] = [:]
for i in 0..<300 { duzy["/Applications/App\(i).app"] = Date(timeIntervalSinceNow: -Double(i)) }
let przyciety = OstatnieProgramy.przytnij(duzy, do: 200)
checkEqual("dziennik przyciety do pojemnosci", przyciety.count, 200)
check("po przycieciu zostaja NAJSWIEZSZE wpisy", przyciety["/Applications/App0.app"] != nil)
check("po przycieciu najstarsze wpisy znikaja", przyciety["/Applications/App299.app"] == nil)
checkEqual("maly dziennik zostaje nietkniety",
           OstatnieProgramy.przytnij(dziennik, do: 200).count, dziennik.count)

// ─────────────────────────────────────────────────────────────────────
// SCALONY RZAD "OSTATNIE" (2026-08-22)
// Program wchodzi po NOWSZEJ z dwoch dat; systemowy tylko przez uzycie.
// ─────────────────────────────────────────────────────────────────────
let dziennikScalania = [
    "/Applications/Stary.app": Date(timeIntervalSinceNow: -60),      // dodany dawno, uzyty przed chwila
    "/Applications/Terminal.app": Date(timeIntervalSinceNow: -120),  // systemowy, tylko z uzycia
]
let doScalenia = probka + [app("Terminal", dni: 900, system: true)]

let scalone = OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                       zDodanych: true, zUzywanych: true, ile: 10)
check("scalony rzad nie powiela programu, ktory ma obie daty",
      scalone.filter { $0.name == "Stary" }.count == 1)
checkEqual("nowsza z dwoch dat wygrywa — 'Stary' uzyty przed chwila jest pierwszy",
           scalone.first?.name, "Stary")
check("systemowy wchodzi do rzedu przez uzycie", scalone.contains { $0.name == "Terminal" })
check("kolejnosc rzedu jest malejaca po dacie", zip(scalone, scalone.dropFirst()).allSatisfy { a, b in
    func kiedy(_ x: InstalledApp) -> Date {
        max(x.isSystem ? .distantPast : (x.dataDodania ?? .distantPast),
            dziennikScalania[x.id] ?? .distantPast)
    }
    return kiedy(a) >= kiedy(b)
})

let tylkoUzywane = OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                            zDodanych: false, zUzywanych: true, ile: 10)
checkEqual("z wylaczonymi 'zainstalowanymi' zostaja same uzywane", tylkoUzywane.count, 2)
let tylkoDodane = OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                           zDodanych: true, zUzywanych: false, ile: 10)
check("z wylaczonymi 'uzywanymi' systemowy wypada", !tylkoDodane.contains { $0.isSystem })
checkEqual("oba przelaczniki wylaczone daja pusty rzad",
           OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                    zDodanych: false, zUzywanych: false, ile: 10).count, 0)
checkEqual("rzad na zero pozycji jest pusty",
           OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                    zDodanych: true, zUzywanych: true, ile: 0).count, 0)
checkEqual("rzad przycina sie do zadanej liczby",
           OstatnieProgramy.scalone(doScalenia, dziennik: dziennikScalania,
                                    zDodanych: true, zUzywanych: true, ile: 2).count, 2)

// ─────────────────────────────────────────────────────────────────────
// TRYB GRY — czy cos zakrywa caly ekran
// Liczby z pomiaru 2026-08-22 (paczka BEZ zgody na Nagrywanie ekranu).
// ─────────────────────────────────────────────────────────────────────
let pelny = CGRect(x: 0, y: 0, width: 3200, height: 1800)
check("okno na caly ekran, warstwa 0 — to jest pelny ekran",
      PelnyEkran.zakrywa(okna: [(pelny, 0)], ekran: ekran))
// 🔴 Dock ZGLASZA okno 3200x1800. Bez filtru warstwy sito bylo by zawsze prawdziwe.
check("Dock (3200x1800, warstwa 20) NIE liczy sie jako pelny ekran",
      !PelnyEkran.zakrywa(okna: [(pelny, 20)], ekran: ekran))
check("Window Server (warstwa 24) tez nie liczy sie jako pelny ekran",
      !PelnyEkran.zakrywa(okna: [(pelny, 24)], ekran: ekran))
check("zmierzone okno Chrome 2699x1689 nie jest pelnym ekranem",
      !PelnyEkran.zakrywa(okna: [(CGRect(x: 343, y: 31, width: 2699, height: 1689), 0)], ekran: ekran))
check("brak okien znaczy brak pelnego ekranu", !PelnyEkran.zakrywa(okna: [], ekran: ekran))
check("okno wieksze niz ekran tez zakrywa ekran",
      PelnyEkran.zakrywa(okna: [(CGRect(x: -10, y: -10, width: 3220, height: 1820), 0)], ekran: ekran))
check("okno mniejsze o 1 px na bok wciaz miesci sie w tolerancji",
      PelnyEkran.zakrywa(okna: [(CGRect(x: 1, y: 1, width: 3198, height: 1798), 0)], ekran: ekran))
check("okno mniejsze o 10 px na bok juz nie zakrywa ekranu",
      !PelnyEkran.zakrywa(okna: [(CGRect(x: 10, y: 10, width: 3180, height: 1780), 0)], ekran: ekran))
check("pelny ekran na DRUGIM monitorze nie liczy sie na tym, gdzie jest kursor",
      !PelnyEkran.zakrywa(okna: [(CGRect(x: 3200, y: 0, width: 3200, height: 1800), 0)], ekran: ekran))

// Przeliczenie Quartz -> Cocoa. Quartz ma poczatek w LEWYM GORNYM rogu.
checkEqual("okno na calym ekranie po przeliczeniu siada na (0, 0)",
           PelnyEkran.naUkladCocoa(CGRect(x: 0, y: 0, width: 3200, height: 1800),
                                   wysokoscEkranuGlownego: 1800),
           CGRect(x: 0, y: 0, width: 3200, height: 1800))
checkEqual("okno tuz pod menu bar (Quartz y=30) ma w Cocoa gorna krawedz na 1770",
           PelnyEkran.naUkladCocoa(CGRect(x: 0, y: 30, width: 800, height: 600),
                                   wysokoscEkranuGlownego: 1800).maxY,
           1770)

// ─────────────────────────────────────────────────────────────────────
// UKLAD SIATKI — wlasna kolejnosc i ciecie belkami (0.2.9)
// ─────────────────────────────────────────────────────────────────────
let lista = [app("Alfa", dni: 1), app("Beta", dni: 2), app("Gamma", dni: 3), app("Delta", dni: 4)]
func nazwy(_ segmenty: [UkladSiatki.Segment]) -> [String] { segmenty.flatMap { $0.programy }.map(\.name) }

// Pusta kolejnosc = alfabet. To jest stan wyjsciowy kazdego swiezego profilu.
let alfabet = UkladSiatki.ulozenie(programy: lista, kolejnosc: [], separatory: [], pokazujPusteBelki: false)
checkEqual("pusta kolejnosc daje jeden kawalek", alfabet.count, 1)
checkEqual("i uklada programy alfabetycznie", nazwy(alfabet), ["Alfa", "Beta", "Delta", "Gamma"])
checkEqual("pusta lista nie daje zadnego kawalka",
           UkladSiatki.ulozenie(programy: [], kolejnosc: [], separatory: [], pokazujPusteBelki: false).count, 0)

// Domkniecie: pierwsze pociagniecie ikony musi najpierw utrwalic to, co widac na ekranie.
let domkniete = UkladSiatki.domknij([], programy: lista)
checkEqual("domkniecie pustej kolejnosci bierze wszystkie programy", domkniete.count, 4)
checkEqual("i to w kolejnosci alfabetycznej", domkniete.map(\.id),
           ["p:/Applications/Alfa.app", "p:/Applications/Beta.app",
            "p:/Applications/Delta.app", "p:/Applications/Gamma.app"])
let domkniete2 = UkladSiatki.domknij(domkniete, programy: lista)
checkEqual("domkniecie drugi raz niczego nie dubluje", domkniete2.count, 4)
checkEqual("i niczego nie przestawia", domkniete2.map(\.id), domkniete.map(\.id))

// Swiezo doinstalowany program ma isc na koniec, a nie w srodek cudzego ukladu.
let zNowym = UkladSiatki.ulozenie(programy: lista + [app("Aaa", dni: 0)],
                                  kolejnosc: domkniete, separatory: [], pokazujPusteBelki: false)
checkEqual("program nieznany kolejnosci laduje na koncu, mimo ze nazwa jest pierwsza",
           nazwy(zNowym).last, "Aaa")
checkEqual("i nie gubi zadnego z pozostalych", nazwy(zNowym).count, 5)

// Przesuwanie.
let alfa = ElementUkladu.program("/Applications/Alfa.app")
let gamma = ElementUkladu.program("/Applications/Gamma.app")
let poPrzeniesieniu = UkladSiatki.przenies(alfa, przed: gamma, w: domkniete)
checkEqual("przeniesiony program siada tuz przed celem",
           nazwy(UkladSiatki.ulozenie(programy: lista, kolejnosc: poPrzeniesieniu,
                                      separatory: [], pokazujPusteBelki: false)),
           ["Beta", "Delta", "Alfa", "Gamma"])
checkEqual("przeniesienie nie gubi ani nie dubluje elementu", poPrzeniesieniu.count, domkniete.count)
checkEqual("upuszczenie na samego siebie nic nie zmienia",
           UkladSiatki.przenies(alfa, przed: alfa, w: domkniete).map(\.id), domkniete.map(\.id))
checkEqual("cel nil znaczy 'na sam koniec'",
           nazwy(UkladSiatki.ulozenie(programy: lista,
                                      kolejnosc: UkladSiatki.przenies(alfa, przed: nil, w: domkniete),
                                      separatory: [], pokazujPusteBelki: false)),
           ["Beta", "Delta", "Gamma", "Alfa"])
checkEqual("przeniesienie elementu spoza kolejnosci nie rusza niczego",
           UkladSiatki.przenies(.program("/Applications/Duch.app"), przed: gamma, w: domkniete).map(\.id),
           domkniete.map(\.id))

// Belki.
let belka = Separator(nazwa: "Robota")
let zBelka = UkladSiatki.wstawBelke(belka, przed: gamma, w: domkniete)
let ciete = UkladSiatki.ulozenie(programy: lista, kolejnosc: zBelka,
                                 separatory: [belka], pokazujPusteBelki: false)
checkEqual("belka tnie liste na dwa kawalki", ciete.count, 2)
checkEqual("pierwszy kawalek nie ma nad soba belki", ciete.first?.belka == nil, true)
checkEqual("pierwszy kawalek konczy sie przed belka", ciete.first?.programy.map(\.name), ["Alfa", "Beta", "Delta"])
checkEqual("drugi kawalek zaczyna sie od programu spod belki", ciete.last?.programy.map(\.name), ["Gamma"])
checkEqual("belka niesie swoja nazwe", ciete.last?.belka?.nazwa, "Robota")
checkEqual("po podziale nie ginie ani nie dubluje sie zaden program",
           nazwy(ciete), ["Alfa", "Beta", "Delta", "Gamma"])

let naPoczatku = UkladSiatki.wstawBelke(belka, przed: nil, w: domkniete)
checkEqual("belka bez celu ladzie na samym poczatku", naPoczatku.first?.id, "b:\(belka.id.uuidString)")
checkEqual("belka na poczatku nie robi pustego kawalka nad soba",
           UkladSiatki.ulozenie(programy: lista, kolejnosc: naPoczatku,
                                separatory: [belka], pokazujPusteBelki: false).count, 1)

// Belka, pod ktora nic nie zostalo. Poza edycja znika, w edycji MUSI byc widoczna —
// inaczej nie ma na co upuscic ikony i pusta sekcja jest nie do zapelnienia.
let belkaNaKoncu = UkladSiatki.wstawBelke(belka, przed: nil, w: [])
checkEqual("pusta belka poza edycja nie rysuje sie w siatce",
           UkladSiatki.ulozenie(programy: [], kolejnosc: belkaNaKoncu,
                                separatory: [belka], pokazujPusteBelki: false).count, 0)
checkEqual("ta sama pusta belka w edycji jest widoczna",
           UkladSiatki.ulozenie(programy: [], kolejnosc: belkaNaKoncu,
                                separatory: [belka], pokazujPusteBelki: true).count, 1)

// Belka skasowana z listy separatorow nie moze rozciac listy „duchem".
checkEqual("belka bez wpisu w separatorach jest pomijana",
           UkladSiatki.ulozenie(programy: lista, kolejnosc: zBelka,
                                separatory: [], pokazujPusteBelki: false).count, 1)
checkEqual("i nie gubi przy tym zadnego programu",
           nazwy(UkladSiatki.ulozenie(programy: lista, kolejnosc: zBelka,
                                      separatory: [], pokazujPusteBelki: false)),
           ["Alfa", "Beta", "Delta", "Gamma"])

// Zawezona lista (szukajka, filtr kategorii, ukrywanie) nie moze wywracac ukladu.
let zawezone = UkladSiatki.ulozenie(programy: [lista[0], lista[2]], kolejnosc: zBelka,
                                    separatory: [belka], pokazujPusteBelki: false)
checkEqual("zawezona lista zachowuje kolejnosc z ukladu", nazwy(zawezone), ["Alfa", "Gamma"])
checkEqual("i nie pokazuje kawalka, w ktorym nic nie zostalo",
           zawezone.allSatisfy { !$0.programy.isEmpty }, true)

// Ladunek przeciagania: ikona i belka jada jednym kanalem, wiec musi sie odwracac.
checkEqual("ladunek programu odczytuje sie z powrotem", ElementUkladu(id: alfa.id), alfa)
checkEqual("ladunek belki odczytuje sie z powrotem",
           ElementUkladu(id: ElementUkladu.belka(belka.id).id), ElementUkladu.belka(belka.id))
check("smiec w ladunku nie tworzy elementu", ElementUkladu(id: "cokolwiek") == nil)
check("belka z popsutym UUID nie tworzy elementu", ElementUkladu(id: "b:nie-jest-uuid") == nil)

// Podglad przeciagania — ten sam `przenies`, tylko wynik nie idzie do zapisu.
// Tu pilnujemy, ze podglad NIE gubi i NIE dubluje niczego, bo liczy sie go przy
// kazdym drgnieciu myszy nad kazdym celem.
let ciagniety = ElementUkladu.program("/Applications/Delta.app")
for cel in domkniete + [ElementUkladu.belka(belka.id)] {
    let podglad = UkladSiatki.przenies(ciagniety, przed: cel, w: domkniete)
    checkEqual("podglad nad \(cel.id) nie zmienia liczby elementow", podglad.count, domkniete.count)
    checkEqual("podglad nad \(cel.id) nie gubi zadnego programu",
               Set(podglad.map(\.id)), Set(domkniete.map(\.id)))
}
checkEqual("podglad 'na koniec' tez nic nie gubi",
           Set(UkladSiatki.przenies(ciagniety, przed: nil, w: domkniete).map(\.id)),
           Set(domkniete.map(\.id)))

// Zasiew naglowka „Wszystkie programy": belka na gorze JEST naglowkiem sekcji.
// Warunkiem nie jest „uklad jest swiezy" — [U] moze juz cos miec poukladane.
func pierwszaJestBelka(_ k: [ElementUkladu]) -> Bool {
    if case .belka = k.first { return true }
    return false
}
check("swiezy uklad nie zaczyna sie belka — zasiew ma sie odpalic", !pierwszaJestBelka(domkniete))
let zZasianym = UkladSiatki.wstawBelke(belka, przed: nil, w: domkniete)
check("po zasiewie na gorze stoi belka", pierwszaJestBelka(zZasianym))
checkEqual("zasiew nie gubi zadnego programu",
           Set(zZasianym.compactMap { if case .program(let p) = $0 { return p } else { return nil } }),
           Set(domkniete.compactMap { if case .program(let p) = $0 { return p } else { return nil } }))
check("uklad, ktory JUZ zaczyna sie belka, drugiego naglowka nie dostaje",
      pierwszaJestBelka(zZasianym))
checkEqual("belka z gory tnie liste tak, ze nad nia nie ma pustego kawalka",
           UkladSiatki.ulozenie(programy: lista, kolejnosc: zZasianym,
                                separatory: [belka], pokazujPusteBelki: false).count, 1)
checkEqual("i wszystkie programy siedza pod nia",
           nazwy(UkladSiatki.ulozenie(programy: lista, kolejnosc: zZasianym,
                                      separatory: [belka], pokazujPusteBelki: false)).count, 4)

// Plaska lista pozycji — postac, w ktorej siatke rysuje UkladPlynny (jeden kontener).
func idy(_ p: [UkladSiatki.Pozycja]) -> [String] { p.map(\.id) }

let plaskie = UkladSiatki.pozycje(programy: lista, kolejnosc: zBelka,
                                  separatory: [belka], pokazujPusteBelki: false)
checkEqual("plaska lista ma wszystkie programy plus belke", plaskie.count, lista.count + 1)
checkEqual("belka stoi dokladnie przed swoim programem",
           idy(plaskie).firstIndex(of: "b:\(belka.id.uuidString)").map { $0 + 1 },
           idy(plaskie).firstIndex(of: "p:/Applications/Gamma.app"))
checkEqual("kolejnosc programow w plaskiej liscie zgadza sie z ta z kawalkow",
           plaskie.compactMap { if case .program(let a) = $0 { return a.name } else { return nil } },
           nazwy(ciete))
check("kazda pozycja ma inny identyfikator", Set(idy(plaskie)).count == plaskie.count)

// Belka bez niczego pod soba: poza edycja nie ma jej w ogole, w edycji jest.
let osieroconaBelka = UkladSiatki.wstawBelke(belka, przed: nil, w: [])
checkEqual("pusta belka poza edycja nie trafia na plaska liste",
           UkladSiatki.pozycje(programy: [], kolejnosc: osieroconaBelka,
                               separatory: [belka], pokazujPusteBelki: false).count, 0)
checkEqual("pusta belka w edycji trafia na plaska liste",
           UkladSiatki.pozycje(programy: [], kolejnosc: osieroconaBelka,
                               separatory: [belka], pokazujPusteBelki: true).count, 1)

// Dwie belki pod rzad — pierwsza jest pusta.
let druga = Separator(nazwa: "Druga")
let dwieBelki = UkladSiatki.wstawBelke(druga, przed: .belka(belka.id), w: zBelka)
checkEqual("dwie belki pod rzad poza edycja daja tylko te z programami",
           UkladSiatki.pozycje(programy: lista, kolejnosc: dwieBelki,
                               separatory: [belka, druga], pokazujPusteBelki: false)
               .filter { if case .belka = $0 { return true } else { return false } }.count, 1)
checkEqual("a w edycji obie",
           UkladSiatki.pozycje(programy: lista, kolejnosc: dwieBelki,
                               separatory: [belka, druga], pokazujPusteBelki: true)
               .filter { if case .belka = $0 { return true } else { return false } }.count, 2)

// KONTROLA SPOJNOSCI: ulozenie() wychodzi z pozycje(), wiec obie postacie musza
// niesc dokladnie te same programy w tej samej kolejnosci — dla kazdego przypadku.
for (nazwa, k, sep) in [("prosty", zBelka, [belka]), ("dwie belki", dwieBelki, [belka, druga]),
                        ("bez belek", domkniete, [Separator]())] {
    for edycja in [false, true] {
        let zPlaskiej = UkladSiatki.pozycje(programy: lista, kolejnosc: k, separatory: sep,
                                            pokazujPusteBelki: edycja)
            .compactMap { if case .program(let a) = $0 { return a.name } else { return nil } }
        let zKawalkow = nazwy(UkladSiatki.ulozenie(programy: lista, kolejnosc: k, separatory: sep,
                                                   pokazujPusteBelki: edycja))
        checkEqual("[\(nazwa), edycja=\(edycja)] obie postacie niosa te same programy",
                   zPlaskiej, zKawalkow)
    }
}

// Liczenie kolumn. Tu program sie WYWALIL 2026-08-22: SwiftUI proponuje szerokosc
// nieskonczona, a Int(.infinity) to EXC_BREAKPOINT, nie wyjatek.
func kol(_ szer: CGFloat) -> Int {
    UkladSiatki.kolumny(szerokosc: szer, szerokoscKafelka: 100, odstep: 4)
}
checkEqual("880 px przy kafelku 100 i odstepie 4 daje 8 kolumn", kol(880), 8)
checkEqual("dokladnie na jeden kafelek daje 1 kolumne", kol(100), 1)
checkEqual("mniej niz jeden kafelek to nadal 1 kolumna, nie 0", kol(30), 1)
checkEqual("SZEROKOSC NIESKONCZONA nie wywala programu", kol(.infinity), 1)
checkEqual("szerokosc NaN nie wywala programu", kol(.nan), 1)
checkEqual("szerokosc zero nie wywala programu", kol(0), 1)
checkEqual("szerokosc ujemna nie wywala programu", kol(-500), 1)
checkEqual("zerowa szerokosc kafelka nie dzieli przez zero",
           UkladSiatki.kolumny(szerokosc: 800, szerokoscKafelka: 0, odstep: 4), 1)
check("kolumn przybywa wraz z szerokoscia", kol(400) < kol(800) && kol(800) < kol(1600))

// [U] 2026-08-22: „udalo mi sie tylko jedna przestawic". Sprawdzamy KAZDA pare,
// nie jedna — przy jednej probce ten blad przechodzil niezauwazony.
let wszystkieElementy = UkladSiatki.wstawBelke(belka, przed: nil, w: domkniete)
var zleZlozone: [String] = []
var zgubione: [String] = []
for a in wszystkieElementy {
    for b in wszystkieElementy where b != a {
        let wynik = UkladSiatki.przenies(a, przed: b, w: wszystkieElementy)
        if wynik.count != wszystkieElementy.count || Set(wynik.map(\.id)) != Set(wszystkieElementy.map(\.id)) {
            zgubione.append("\(a.id)->\(b.id)")
            continue
        }
        guard let ia = wynik.firstIndex(of: a), let ib = wynik.firstIndex(of: b), ia + 1 == ib else {
            zleZlozone.append("\(a.id)->\(b.id)")
            continue
        }
    }
}
let par = wszystkieElementy.count * (wszystkieElementy.count - 1)
print("PROBKA KONTROLNA: sprawdzono \(par) par przeniesien")
check("zadne przeniesienie nie gubi ani nie dubluje elementu (pierwsze zle: \(zgubione.first ?? "-"))",
      zgubione.isEmpty)
check("po KAZDYM przeniesieniu element stoi tuz przed celem (pierwsze zle: \(zleZlozone.first ?? "-"))",
      zleZlozone.isEmpty)
check("kontrola dodatnia — par jest wiecej niz jedna", par > 1)

// Przeniesienie na koniec, tez dla kazdego elementu.
check("przeniesienie na koniec dziala dla kazdego elementu", wszystkieElementy.allSatisfy { a in
    let w = UkladSiatki.przenies(a, przed: nil, w: wszystkieElementy)
    return w.last == a && w.count == wszystkieElementy.count
})

// ─────────────────────────────────────────────────────────────────────
// GEOMETRIA SIATKI I TRAFIANIE KURSOREM (0.2.23)
// Tu mieszka odpowiedz na „gdzie wyladuje ikona". Rysowanie i trafianie licza
// z TEJ SAMEJ funkcji, wiec rozjazd o punkt = ikona ladujaca gdzie indziej,
// niz pokazal podglad.
// ─────────────────────────────────────────────────────────────────────
let m = UkladSiatki.Metryka(szerokoscKafelka: 100, wysokoscKafelka: 100,
                            wysokoscBelki: 32, odstepPoziomy: 4,
                            odstepPionowy: 4, odstepPrzyBelce: 6)
func poz(_ n: Int) -> [UkladSiatki.Pozycja] { (0..<n).map { .program(app("A\($0)", dni: Double($0))) } }

// 5 ikon po 100 px + 4 px odstepu w szerokosci 528 -> 5 kolumn, jeden rzad.
let r5 = UkladSiatki.ramki(dla: poz(5), szerokosc: 528, metryka: m)
checkEqual("piec ikon w jednym rzedzie", Set(r5.map(\.minY)).count, 1)
checkEqual("pierwsza ikona przy lewej krawedzi", r5[0].minX, 0)
checkEqual("druga ikona za odstepem", r5[1].minX, 104)
checkEqual("wysokosc jednego rzedu", UkladSiatki.wysokosc(ramek: r5), 100)

// Ta sama piatka w wezszym oknie ma sie ZAWINAC — to jest test na zgloszenie [U],
// ze przy zwezaniu okna ikony nie przestawialy sie z powrotem.
let rWaskie = UkladSiatki.ramki(dla: poz(5), szerokosc: 320, metryka: m)
checkEqual("w 320 px mieszcza sie 3 kolumny", Set(rWaskie.map(\.minX)).count, 3)
checkEqual("wiec powstaja dwa rzedy", Set(rWaskie.map(\.minY)).count, 2)
checkEqual("i siatka jest wyzsza", UkladSiatki.wysokosc(ramek: rWaskie), 204)
check("zwezanie NIGDY nie daje mniej rzedow niz rozszerzanie",
      Set(rWaskie.map(\.minY)).count >= Set(r5.map(\.minY)).count)

// Belka zajmuje caly rzad i lamie biezacy.
let zBelkaWSrodku: [UkladSiatki.Pozycja] = [.program(app("A", dni: 1)), .belka(Separator(nazwa: "X")),
                                            .program(app("B", dni: 2))]
let rb = UkladSiatki.ramki(dla: zBelkaWSrodku, szerokosc: 528, metryka: m)
checkEqual("belka jest na cala szerokosc", rb[1].width, 528)
checkEqual("belka zaczyna sie od lewej", rb[1].minX, 0)
check("belka stoi PONIZEJ ikony przed nia", rb[1].minY > rb[0].minY)
check("ikona po belce stoi PONIZEJ belki", rb[2].minY > rb[1].minY)
checkEqual("ikona po belce wraca do pierwszej kolumny", rb[2].minX, 0)

// TRAFIANIE. Lewa polowa kafelka = przed nim, prawa = za nim.
func trafienie(_ x: CGFloat, _ y: CGFloat, _ ramki: [CGRect]) -> Int {
    UkladSiatki.indeksWstawienia(punkt: CGPoint(x: x, y: y), ramki: ramki)
}
checkEqual("lewa polowa pierwszej ikony daje 0", trafienie(10, 50, r5), 0)
checkEqual("prawa polowa pierwszej ikony daje 1", trafienie(90, 50, r5), 1)
checkEqual("lewa polowa trzeciej ikony daje 2", trafienie(218, 50, r5), 2)
checkEqual("prawa polowa ostatniej daje koniec listy", trafienie(520, 50, r5), 5)
checkEqual("punkt na lewo od siatki daje poczatek", trafienie(-50, 50, r5), 0)
checkEqual("punkt daleko pod siatka trafia w ostatni rzad", trafienie(520, 9999, r5), 5)
checkEqual("pusta siatka daje 0", trafienie(10, 10, []), 0)

// KAZDA ikona musi byc osiagalna — to jest zgloszenie [U] „udalo sie tylko jedna".
let r12 = UkladSiatki.ramki(dla: poz(12), szerokosc: 528, metryka: m)
var nieosiagalne: [Int] = []
for (i, r) in r12.enumerated() {
    if trafienie(r.minX + 5, r.midY, r12) != i { nieosiagalne.append(i) }
}
checkEqual("kazde miejsce wstawienia jest osiagalne kursorem (zle: \(nieosiagalne))",
           nieosiagalne, [])
check("kontrola dodatnia — sprawdzono wiecej niz jedno miejsce", r12.count > 1)

// Ramki nie moga na siebie nachodzic — inaczej trafianie bywaloby niejednoznaczne.
var nachodzace = 0
for i in 0..<r12.count { for j in (i+1)..<r12.count where r12[i].intersects(r12[j]) { nachodzace += 1 } }
checkEqual("zadne dwie ramki na siebie nie nachodza", nachodzace, 0)

// Szerokosci, na ktorych program sie wywalal.
for zla in [CGFloat.infinity, .nan, 0, -100] {
    check("szerokosc \(zla) nie wywala rozkladu",
          UkladSiatki.ramki(dla: poz(3), szerokosc: zla, metryka: m).count == 3)
}

// ─────────────────────────────────────────────────────────────────────
// AG-23 — PRZENOSZENIE MIEDZY SEKCJAMI (0.2.24)
// Zgloszenie [U]: ikony z "Narzedzi systemowych" maja dac sie wyciagac,
// a do tej sekcji ma dac sie dolozyc inne. Sekcje sa wiec DWIE i obie maja
// wlasna kolejnosc; ruch miedzy nimi to jedna operacja na dwoch zapisach.
// ─────────────────────────────────────────────────────────────────────
let narzedzia = [app("Monitor", dni: 1), app("Terminal", dni: 2)]
let kolGlowna = UkladSiatki.domknij([], programy: lista)
let kolNarzedzi = UkladSiatki.domknij([], programy: narzedzia)
let terminal = ElementUkladu.program("/Applications/Terminal.app")
let beta = ElementUkladu.program("/Applications/Beta.app")

print("PROBKA KONTROLNA: sekcja glowna \(kolGlowna.count) pozycji, narzedzia \(kolNarzedzi.count)")
checkEqual("sekcje sa dokladnie dwie", Sekcja.allCases.count, 2)

// Wyciagniecie narzedzia do programow — to jest samo zgloszenie [U].
let wyjscie = UkladSiatki.przenies(terminal, zKolejnosci: kolNarzedzi, doKolejnosci: kolGlowna, przed: beta)
check("wyciagniete narzedzie znika ze swojej sekcji", !wyjscie.zrodlo.contains(terminal))
check("i pojawia sie w docelowej", wyjscie.cel.contains(terminal))
checkEqual("laduje dokladnie przed celem",
           wyjscie.cel.firstIndex(of: terminal).map { wyjscie.cel[$0 + 1] }, beta)
checkEqual("zrodlo traci dokladnie jedna pozycje", wyjscie.zrodlo.count, kolNarzedzi.count - 1)
checkEqual("cel zyskuje dokladnie jedna", wyjscie.cel.count, kolGlowna.count + 1)
// KONTROLA DODATNIA na "znika": bez niej zero znaczyloby tylko tyle, ze sito nie dziala.
check("kontrola dodatnia — przed przeniesieniem narzedzie BYLO w swojej sekcji",
      kolNarzedzi.contains(terminal))

// Ikona nie moze zostac w obu sekcjach naraz — to jest cala trudnosc tego ruchu.
let wSzystkich = Set(wyjscie.zrodlo.map(\.id)).intersection(Set(wyjscie.cel.map(\.id)))
checkEqual("zadna pozycja nie stoi w obu sekcjach naraz", wSzystkich, [])

// Droga powrotna: to samo w druga strone ma oddac stan wyjsciowy.
let powrot = UkladSiatki.przenies(terminal, zKolejnosci: wyjscie.cel, doKolejnosci: wyjscie.zrodlo, przed: nil)
checkEqual("powrot oddaje sekcji glownej jej wlasny sklad", powrot.cel.count, kolNarzedzi.count)
checkEqual("i nie zostawia sladu w tej, z ktorej wrocil", powrot.zrodlo.map(\.id), kolGlowna.map(\.id))

// Cel nil = na koniec sekcji docelowej.
let naKoniec = UkladSiatki.przenies(terminal, zKolejnosci: kolNarzedzi, doKolejnosci: kolGlowna, przed: nil)
checkEqual("cel nil sadza ikone na koncu sekcji docelowej", naKoniec.cel.last, terminal)

// Cel, ktorego w sekcji docelowej nie ma, tez znaczy "na koniec" — inaczej ruch
// przepadalby po cichu, gdy cel zniknal miedzy podgladem a upuszczeniem.
let obcyCel = UkladSiatki.przenies(terminal, zKolejnosci: kolNarzedzi, doKolejnosci: kolGlowna,
                                   przed: .program("/Applications/Nie-ma-mnie.app"))
checkEqual("nieznany cel tez znaczy 'na koniec'", obcyCel.cel.last, terminal)

// Przenosiny tam i z powrotem nie moga dublowac: element wycinamy takze z celu.
let podwojnie = UkladSiatki.przenies(terminal, zKolejnosci: kolNarzedzi, doKolejnosci: kolNarzedzi, przed: nil)
checkEqual("ten sam element nie zdublowal sie w celu",
           podwojnie.cel.filter { $0 == terminal }.count, 1)

// Belka tez umie zmienic sekcje — jest zwyklym elementem kolejnosci.
let belkaNarzedzi = Separator(nazwa: "Moje")
let zBelkaWNarzedziach = UkladSiatki.wstawBelke(belkaNarzedzi, przed: nil, w: kolNarzedzi)
let belkaWyszla = UkladSiatki.przenies(.belka(belkaNarzedzi.id), zKolejnosci: zBelkaWNarzedziach,
                                       doKolejnosci: kolGlowna, przed: beta)
check("belka tez przechodzi miedzy sekcjami", belkaWyszla.cel.contains(.belka(belkaNarzedzi.id)))
check("i znika z sekcji, z ktorej wyszla", !belkaWyszla.zrodlo.contains(.belka(belkaNarzedzi.id)))

// Pusta sekcja docelowa: po wyniesieniu ostatniej ikony musi dac sie tam wrocic.
let doPustej = UkladSiatki.przenies(terminal, zKolejnosci: kolNarzedzi, doKolejnosci: [], przed: nil)
checkEqual("do pustej sekcji da sie upuscic", doPustej.cel, [terminal])
checkEqual("pusta siatka daje miejsce wstawienia 0",
           UkladSiatki.indeksWstawienia(punkt: CGPoint(x: 40, y: 40), ramki: []), 0)

// ─────────────────────────────────────────────────────────────────────
// AG-24 — STRAZNIK SZEROKOSCI ODDAWANEJ RODZICOWI (0.2.25)
// Oba uklady oddaja rodzicowi DOKLADNIE tyle, ile dostaly. Rzad "Ostatnie"
// robil inaczej: byl sztywnym HStackiem i zadal swojej sumy — zmierzone
// 820 pt przy oknie 700 pt — przez co rozpychal kolumnie tresci i cala
// siatke bylo widac ucieta z obu stron.
// ─────────────────────────────────────────────────────────────────────
checkEqual("zaproponowana szerokosc jest oddawana bez zmian",
           UkladSiatki.szerokoscDoOddania(700, zapasowa: 78), 700)
checkEqual("szerokosc mniejsza od kafelka tez jest oddawana — to nie jest minimum",
           UkladSiatki.szerokoscDoOddania(30, zapasowa: 78), 30)
for zla in [CGFloat.infinity, .nan, 0, -100] {
    checkEqual("szerokosc \(zla) schodzi na wartosc zapasowa, nie ubija procesu",
               UkladSiatki.szerokoscDoOddania(zla, zapasowa: 78), 78)
}
checkEqual("brak propozycji tez schodzi na zapasowa",
           UkladSiatki.szerokoscDoOddania(nil, zapasowa: 78), 78)

// Liczba ikon w rzedzie liczy sie z TEJ SAMEJ funkcji co kolumny siatki —
// dwie kopie tej arytmetyki rozjechalyby rzad z reszta okna.
checkEqual("w 680 pt miesci sie 8 kafelkow po 78 z odstepem 4",
           UkladSiatki.kolumny(szerokosc: 680, szerokoscKafelka: 78, odstep: 4), 8)
checkEqual("w 200 pt tylko 2", UkladSiatki.kolumny(szerokosc: 200, szerokoscKafelka: 78, odstep: 4), 2)
checkEqual("zwezanie NIGDY nie daje wiecej kolumn niz szersze okno",
           UkladSiatki.kolumny(szerokosc: 200, szerokoscKafelka: 78, odstep: 4)
           <= UkladSiatki.kolumny(szerokosc: 1380, szerokoscKafelka: 78, odstep: 4), true)
check("kontrola dodatnia — szersze okno naprawde daje wiecej kolumn",
      UkladSiatki.kolumny(szerokosc: 1380, szerokoscKafelka: 78, odstep: 4) > 8)

print("")
print("ZIELONE: \(passed), CZERWONE: \(failed)")
exit(failed == 0 ? 0 : 1)
