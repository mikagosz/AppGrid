import Foundation

/// What the Help window says: each section is a picture of the app with numbered points and the same
/// numbers in the steps next to it. Polish and English side by side; the language follows the system,
/// as the rest of AppGrid does — Polish on a Polish Mac, English on any other.
nonisolated enum HelpContent {
    /// One text in both languages.
    struct Text: Hashable {
        let pl: String
        let en: String
        var current: String { HelpContent.polish ? pl : en }
    }

    static var polish: Bool { Locale.preferredLanguages.first?.hasPrefix("pl") == true }

    /// Which picture stands next to the section; drawn by the app itself in HelpWindow.swift.
    enum Picture: CaseIterable { case window, edit, hidden, recent, invocation, looks, finder }

    struct Section {
        let title: Text
        let lead: Text
        /// Numbered like the points on the picture: the first step is point 1.
        let steps: [Text]
        /// The longer description, folded under "More".
        let more: Text?
        let picture: Picture
    }

    struct Card {
        let symbol: String
        let title: Text
        let text: Text
    }

    private static func t(_ pl: String, _ en: String) -> Text { Text(pl: pl, en: en) }

    static let menuItem = t("Pomoc AppGrid", "AppGrid Help")
    static let windowTitle = t("AppGrid — Pomoc", "AppGrid — Help")
    static let title = t("Pierwsze kroki z AppGrid", "Getting started with AppGrid")
    static let intro = t("Własne okno „Aplikacje”: pamięta rozmiar, pokazuje wszystkie programy i zawsze otwiera się na pełnej liście.",
                         "Your own Applications window: it remembers its size, shows every app you have and always opens on the full list.")

    static let sections: [Section] = [
        Section(title: t("Okno AppGrid", "The AppGrid window"),
                lead: t("Wszystkie programy w jednej siatce. Klawiatura wystarczy: piszesz, strzałkami wybierasz, Return uruchamia, Esc chowa okno.",
                        "Every app in one grid. The keyboard is enough: type, pick with the arrow keys, Return launches, Esc hides the window."),
                steps: [t("Szukaj — pole ma fokus cały czas, od razu możesz pisać.", "Search — the field keeps the focus, so you can type at once."),
                        t("Kategoria zawęża siatkę i nigdy nie wpisuje nic w szukajkę.", "A category narrows the grid and never types into the search field."),
                        t("Wielkość ikon.", "Icon size."),
                        t("Na dole: ile programów widać i przycisk Pomocy.", "At the bottom: how many apps are shown, and the Help button.")],
                more: t("Narzędzia systemowe (Terminal, Monitor aktywności i reszta z Narzędzi) stoją w osobnej sekcji, pod programami na co dzień. Programy dochodzą do listy same, bez restartu, gdy tylko pojawią się w Aplikacjach. ⌘R odświeża listę ręcznie. Kliknięcie obok okna albo Esc chowa je, a przy następnym otwarciu wraca pełna lista, bez starego wyszukiwania.",
                        "System utilities (Terminal, Activity Monitor and the rest of Utilities) stand in a section of their own, below your everyday apps. Apps join the list by themselves, without a restart, as soon as they appear in Applications. ⌘R refreshes the list by hand. A click outside the window or Esc hides it, and the next time it opens on the full list, without the old search."),
                picture: .window),
        Section(title: t("Twój układ", "Your own layout"),
                lead: t("Prawy przycisk na wolnym miejscu okna i „Edytuj układ…” — kolejność jest Twoja i zostaje zapisana.",
                        "Right-click an empty spot in the window and pick “Edit layout…” — the order is yours and it is saved."),
                steps: [t("Dodaj separator — nazwany podział siatki.", "Add separator — a named cut in the grid."),
                        t("Separator z nazwą: ciągnięty przenosi całą swoją sekcję (z ⌥ sam separator).",
                          "A named separator: dragged, it moves its whole section (with ⌥, the separator alone)."),
                        t("Ikony przeciągasz; ⌘ albo ⇧ zaznacza kilka naraz.", "Drag icons; ⌘ or ⇧ selects several at once."),
                        t("Gotowe kończy edycję.", "Done ends the editing.")],
                more: t("Ikonę można przeciągnąć także do sekcji narzędzi i z powrotem. „Przywróć kolejność alfabetyczną” w tym samym menu zaczyna od nowa.",
                        "An icon can also be dragged into the utilities section and back. “Restore alphabetical order” in the same menu starts afresh."),
                picture: .edit),
        Section(title: t("Ukryte programy", "Hidden apps"),
                lead: t("Program, którego nie otwierasz, schowasz prawym przyciskiem na ikonie → Ukryj. Wraca, gdy tylko go wyszukasz.",
                        "An app you never open is hidden with a right-click on its icon → Hide. It comes back the moment you search for it."),
                steps: [t("Lista ukrytych w Ustawieniach — stąd przywrócisz każdy z osobna.", "The list of hidden apps in Settings — bring any of them back from here.")],
                more: t("Ukrycie porządkuje widok, nie odbiera programu: wyszukiwanie zawsze go znajdzie, a filtr kategorii nie.",
                        "Hiding tidies the view, it does not take the app away: search always finds it, a category filter does not."),
                picture: .hidden),
        Section(title: t("Ostatnie programy", "Recent apps"),
                lead: t("Nad listą mogą stać programy ostatnio zainstalowane i ostatnio używane.",
                        "Above the list you can have the apps installed lately and the ones used lately."),
                steps: [t("Dwie osobne sekcje albo jeden wspólny rząd.", "Two separate sections, or one shared row."),
                        t("Ostatnio zainstalowane i ile ich pokazać.", "Recently installed, and how many to show."),
                        t("Ostatnio używane — liczone z uruchomień w AppGrid.", "Recently used — counted from launches in AppGrid.")],
                more: nil,
                picture: .recent),
        Section(title: t("Wywołanie", "Calling it up"),
                lead: t("AppGrid przychodzi na skrót klawiszowy albo na róg ekranu — z każdego programu.",
                        "AppGrid comes up on a keyboard shortcut or a screen corner — from any app."),
                steps: [t("Skrót globalny; drugie naciśnięcie chowa okno.", "The global shortcut; pressing it again hides the window."),
                        t("Róg ekranu, w który wjeżdżasz kursorem.", "A screen corner you push the pointer into."),
                        t("Tryb gry: róg milknie, gdy program działa na pełnym ekranie.", "Game mode: the corner stays quiet while an app runs full screen.")],
                more: t("Skrót i róg potrzebują zgody na Dostępność (Ustawienia systemowe → Prywatność i ochrona → Dostępność). Bez niej milkną, a reszta działa normalnie.",
                        "The shortcut and the corner need the Accessibility permission (System Settings → Privacy & Security → Accessibility). Without it they stay silent and everything else works."),
                picture: .invocation),
        Section(title: t("Wygląd", "Looks"),
                lead: t("Szerokość okna, przezroczystość tła i miejsce, w którym się otwiera.",
                        "The window's width, the background's transparency and where it opens."),
                steps: [t("Przezroczystość tła — od pełnego do prześwitującego.", "Transparency of the background — from solid to see-through."),
                        t("Szerokość okna.", "The window's width."),
                        t("Otwieraj na środku ekranu, na którym jest kursor.", "Open centred on the screen the pointer is on.")],
                more: nil,
                picture: .looks),
        Section(title: t("Okna Findera", "Finder windows"),
                lead: t("Na życzenie AppGrid daje oknom Findera stały rozmiar — jeden dla wszystkich folderów albo zapamiętany dla każdego.",
                        "On request AppGrid gives Finder windows a fixed size — one for every folder, or one remembered per folder."),
                steps: [t("Włącz.", "Turn it on."),
                        t("Jeden rozmiar dla wszystkich albo osobno dla każdego folderu.", "One size for all, or one per folder."),
                        t("Rozmiar i to, czy uczy się z Twoich zmian.", "The size, and whether it learns from your own changes.")],
                more: t("Potrzebuje zgody na sterowanie Finderem (Automatyzacja). Bez niej okna Findera zostają przy swoich rozmiarach.",
                        "It needs the permission to control Finder (Automation). Without it Finder windows keep their own sizes."),
                picture: .finder),
    ]

    static let goodToKnow = t("Dobrze wiedzieć", "Good to know")
    static let cards: [Card] = [
        Card(symbol: "power", title: t("Przy logowaniu", "At login"),
             text: t("Jeden przełącznik w Ustawieniach. Po zalogowaniu AppGrid czeka w tle bez okna, aż go wywołasz.",
                     "One switch in Settings. After login AppGrid waits in the background, with no window, until you call it.")),
        Card(symbol: "lock.shield", title: t("Uprawnienia", "Permissions"),
             text: t("Dostępność — tylko dla skrótu i rogu. Automatyzacja Findera — tylko dla rozmiarów jego okien. Wszystko inne działa bez nich.",
                     "Accessibility — only for the shortcut and the corner. Finder automation — only for its window sizes. Everything else works without them.")),
        Card(symbol: "globe", title: t("Język", "Language"),
             text: t("Polski albo angielski — za językiem systemu.", "Polish or English — following the system language.")),
        Card(symbol: "arrow.down.circle", title: t("Aktualizacje", "Updates"),
             text: t("Raz w miesiącu program pyta fractal8.eu o numer najnowszej wersji i nic więcej nie wysyła. Instaluje dopiero po kliknięciu „Zainstaluj”.",
                     "Once a month the app asks fractal8.eu for the newest version number and sends nothing else. It installs only when you click Install.")),
    ]

    static let more = t("Więcej", "More")
    static let less = t("Mniej", "Less")
    /// The line under the Fractal 8 Dev signature — the same as under the title on fractal8.eu.
    static let signatureLine = t("Natywne programy dla macOS, budowane według jednego wzoru.",
                                 "Native macOS software, built to a single pattern.")

    /// Every text of the window, for the check that none is missing a language.
    static var allTexts: [Text] {
        var all = [menuItem, windowTitle, title, intro, goodToKnow, more, less, signatureLine]
        for s in sections { all += [s.title, s.lead] + s.steps + (s.more.map { [$0] } ?? []) }
        for c in cards { all += [c.title, c.text] }
        return all
    }
}
