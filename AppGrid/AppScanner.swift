import AppKit

/// Jedna zainstalowana aplikacja znaleziona na dysku.
struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let category: String
    let isSystem: Bool
    /// Narzędzie systemowe (katalog `Utilities`) — trzymane w osobnej sekcji,
    /// żeby nie zaśmiecało listy programów, których używa się na co dzień.
    let isUtility: Bool
    /// Kiedy paczka trafiła do katalogu — źródło sekcji „ostatnio zainstalowane".
    ///
    /// To `kMDItemDateAdded`, nie data utworzenia pliku. Zmierzone 2026-08-20:
    /// data utworzenia jest bezużyteczna, bo pochodzi z paczki producenta
    /// (Spotify: `1980-01-01`, VLC: `2025-12-18`), a data dodania siedzi na
    /// wszystkich 81 paczkach i zgadza się z tym, kiedy program naprawdę doszedł.
    let dataDodania: Date?

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Skanuje dysk w poszukiwaniu aplikacji.
///
/// Systemowe okno „Aplikacje" pokazuje część programów dopiero po wpisaniu nazwy —
/// tutaj lista jest pełna od pierwszej klatki, bo skanujemy wszystkie katalogi,
/// w których macOS trzyma programy.
enum AppScanner {

    static let systemowe = String(localized: "System")
    static let inne = String(localized: "Other")

    /// Katalogi przeszukiwane wraz z informacją, czy to obszar systemu.
    private static var searchRoots: [(url: URL, isSystem: Bool)] {
        var roots: [(URL, Bool)] = [
            (URL(fileURLWithPath: "/Applications"), false),
            (URL(fileURLWithPath: "/System/Applications"), true),
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: home.path) {
            roots.append((home, false))
        }
        return roots
    }

    static func scan() -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]

        for root in searchRoots {
            for url in bundles(in: root.url, depth: 2) {
                let app = describe(url, isSystem: root.isSystem)
                found[app.id] = app
            }
        }

        // Finder mieszka poza katalogami z aplikacjami, a jest programem jak każdy inny.
        if let finder = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.finder"
        ) {
            let app = describe(finder, isSystem: true)
            found[app.id] = app
        }

        return found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Zwraca paczki `.app` z katalogu, schodząc `depth` poziomów w podkatalogi
    /// (np. `/Applications/Utilities` albo folder producenta).
    private static func bundles(in directory: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        let fm = FileManager.default
        // Bez `.skipsHiddenFiles`: /Applications/Safari.app ma ustawiona flage "ukryty",
        // bo jest tylko dowiazaniem do systemowego Cryptexa. Ta opcja wycinala Safari
        // z listy (zmierzone: 38 wpisow bez opcji, 35 z opcja). Kropke na poczatku nazwy
        // odsiewamy sami — to wystarczy, a paczek .app nie gubi.
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .addedToDirectoryDateKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                result.append(contentsOf: bundles(in: entry, depth: depth - 1))
            }
        }
        return result
    }

    private static func describe(_ url: URL, isSystem: Bool) -> InstalledApp {
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let utility = url.pathComponents.contains("Utilities")
        let dodana = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
            .addedToDirectoryDate
        return InstalledApp(
            id: url.path,
            name: name,
            url: url,
            category: isSystem ? systemowe : category(of: url),
            isSystem: isSystem,
            isUtility: utility,
            dataDodania: dodana ?? nil
        )
    }

    /// Kategoria deklarowana przez samą aplikację w `Info.plist`.
    private static func category(of url: URL) -> String {
        guard let raw = Bundle(url: url)?
            .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        else { return inne }
        return nazwyKategorii[raw] ?? inne
    }

    private static let nazwyKategorii: [String: String] = [
        "public.app-category.developer-tools": String(localized: "Developer tools"),
        "public.app-category.graphics-design": String(localized: "Graphics and design"),
        "public.app-category.productivity": String(localized: "Productivity"),
        "public.app-category.utilities": String(localized: "Utilities"),
        "public.app-category.music": String(localized: "Music"),
        "public.app-category.video": String(localized: "Video"),
        "public.app-category.photography": String(localized: "Photography"),
        "public.app-category.entertainment": String(localized: "Entertainment"),
        "public.app-category.education": String(localized: "Education"),
        "public.app-category.social-networking": String(localized: "Social networking"),
        "public.app-category.business": String(localized: "Business"),
        "public.app-category.finance": String(localized: "Finance"),
        "public.app-category.reference": String(localized: "Reference"),
        "public.app-category.medical": String(localized: "Medical"),
        "public.app-category.healthcare-fitness": String(localized: "Health and fitness"),
        "public.app-category.lifestyle": String(localized: "Lifestyle"),
        "public.app-category.news": String(localized: "News"),
        "public.app-category.weather": String(localized: "Weather"),
        "public.app-category.travel": String(localized: "Travel"),
        "public.app-category.sports": String(localized: "Sports"),
        "public.app-category.medical-software": String(localized: "Medical"),
        "public.app-category.games": String(localized: "Games"),
    ]
}
