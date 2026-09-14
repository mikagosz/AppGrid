import AppKit

// Harness Etapu 1 — skaner aplikacji.
// Sedno skargi [U]: systemowe okno nie pokazuje wszystkiego. Ten sprawdzian pilnuje,
// zeby nasza lista byla pelna, bez duplikatow i zeby Finder w niej byl.

var passed = 0
var failed = 0

func check(_ label: String, _ condition: Bool) {
    if condition { passed += 1 } else { failed += 1; print("  CZERWONE: \(label)") }
}

func checkEqual<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) {
    if lhs == rhs { passed += 1 } else { failed += 1; print("  CZERWONE: \(label) — jest \(lhs), ma byc \(rhs)") }
}

let apps = AppScanner.scan()

// --- PROBKA KONTROLNA: czy skan w ogole cokolwiek widzi ---
// Bez tego "0 bledow" znaczyloby tyle samo przy dzialajacym i przy martwym skanerze.
print("PROBKA KONTROLNA: skan zwrocil \(apps.count) aplikacji")
check("skan zwraca cokolwiek", apps.count > 0)

// Liczba paczek .app policzona niezaleznie od skanera, prosto z dysku.
func policzNaDysku(_ sciezka: String) -> Int {
    let fm = FileManager.default
    guard let wpisy = try? fm.contentsOfDirectory(atPath: sciezka) else { return 0 }
    return wpisy.filter { $0.hasSuffix(".app") }.count
}

let naDyskuApplications = policzNaDysku("/Applications")
let naDyskuSystem = policzNaDysku("/System/Applications")
print("PROBKA KONTROLNA: /Applications = \(naDyskuApplications), /System/Applications = \(naDyskuSystem)")

let zApplications = apps.filter { $0.url.path.hasPrefix("/Applications/") && $0.url.pathComponents.count == 3 }
checkEqual("wszystkie programy z /Applications sa na liscie", zApplications.count, naDyskuApplications)

// --- brak duplikatow ---
let unikalne = Set(apps.map(\.id))
checkEqual("zadna aplikacja nie powtarza sie na liscie", unikalne.count, apps.count)

// --- Finder, ktory mieszka poza katalogami z aplikacjami ---
check("Finder jest na liscie", apps.contains { $0.url.lastPathComponent == "Finder.app" })

// --- nazwy sa czyste, bez rozszerzenia ---
check("nazwy nie koncza sie na .app", apps.allSatisfy { !$0.name.hasSuffix(".app") })
check("zadna nazwa nie jest pusta", apps.allSatisfy { !$0.name.isEmpty })

// --- programy systemowe dostaja kategorie systemowa ---
let systemowe = apps.filter { $0.url.path.hasPrefix("/System/") }
check("programy z /System maja kategorie systemowa",
      systemowe.allSatisfy { $0.category == AppScanner.systemowe })

// --- sortowanie alfabetyczne, bo lista ma byc do przegladania, nie do szukania ---
let nazwy: [String] = apps.map { $0.name }
let posortowane: [String] = nazwy.sorted { (a: String, b: String) -> Bool in
    a.localizedStandardCompare(b) == .orderedAscending
}
check("lista jest posortowana alfabetycznie", nazwy == posortowane)

// --- kilka programow, ktore na tym Macu byc musza ---
for oczekiwany in ["Safari", "Terminal"] {
    check("na liscie jest \(oczekiwany)", apps.contains { $0.name == oczekiwany })
}

// Xcode bywa zainstalowany jako "Xcode-beta" — sprawdzamy rodzine, nie dokladna nazwe.
check("na liscie jest jakis Xcode", apps.contains { $0.name.hasPrefix("Xcode") })

// --- rozdzial narzedzi systemowych od zwyklych programow ---
let narzedzia = apps.filter { $0.isUtility }
let zwykle = apps.filter { !$0.isUtility }
print("PROBKA KONTROLNA: narzedzia = \(narzedzia.count), zwykle = \(zwykle.count)")

check("narzedzia w ogole sie znalazly", narzedzia.count > 0)
check("zwykle programy w ogole sie znalazly", zwykle.count > 0)
checkEqual("kazda aplikacja jest po dokladnie jednej stronie podzialu",
           narzedzia.count + zwykle.count, apps.count)
check("wszystkie narzedzia leza w katalogu Utilities",
      narzedzia.allSatisfy { $0.url.pathComponents.contains("Utilities") })
check("zaden zwykly program nie lezy w Utilities",
      zwykle.allSatisfy { !$0.url.pathComponents.contains("Utilities") })
check("Monitor aktywnosci jest narzedziem",
      narzedzia.contains { $0.url.lastPathComponent == "Activity Monitor.app" })
check("Safari nie jest narzedziem",
      zwykle.contains { $0.name == "Safari" })

print("")
print("ZIELONE: \(passed), CZERWONE: \(failed)")
exit(failed == 0 ? 0 : 1)
