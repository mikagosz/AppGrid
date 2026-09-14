import AppKit
import SwiftUI

/// Okno ustawień programu.
struct UstawieniaView: View {
    @ObservedObject var ustawienia: Ustawienia
    @ObservedObject var skrot: SkrotGlobalny
    @ObservedObject var finder: OknaFindera

    var body: some View {
        Form {
            sekcjaWywolanie
            sekcjaWyglad
            sekcjaGoraListy
            sekcjaUkryte
            sekcjaSeparatory
            sekcjaFinder
            sekcjaOProgramie
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { finder.odswiezZgode() }
    }

    // MARK: - Wywołanie

    private var sekcjaWywolanie: some View {
        Section(String(localized: "Invocation")) {
            Toggle(String(localized: "Global keyboard shortcut"), isOn: $ustawienia.skrotWlaczony)

            HStack {
                Text(String(localized: "Shortcut"))
                Spacer()
                NagrywanieSkrotu(ustawienia: ustawienia)
            }
            .disabled(!ustawienia.skrotWlaczony)

            if ustawienia.skrotWlaczony && !skrot.zarejestrowany {
                Label(
                    String(localized: "This combination is taken by another app — pick a different one."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }

            Toggle(String(localized: "Screen corner"), isOn: $ustawienia.rogWlaczony)
            Picker(String(localized: "Corner"), selection: $ustawienia.rog) {
                ForEach(RogEkranu.allCases) { rog in
                    Text(rog.nazwa).tag(rog)
                }
            }
            .disabled(!ustawienia.rogWlaczony)

            Toggle(String(localized: "Game mode — corner stays quiet in full screen"), isOn: $ustawienia.rogGamemode)
                .disabled(!ustawienia.rogWlaczony)
            Text(String(localized: "Stops a stray flick of the mouse into the corner from hiding a game or a film."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "The Dock icon always works — these two are extras."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Wygląd

    private var sekcjaWyglad: some View {
        Section(String(localized: "Appearance")) {
            HStack {
                Text(String(localized: "Transparency"))
                Slider(
                    value: Binding(
                        get: { (1 - ustawienia.krycieTla) * 100 },
                        set: { ustawienia.krycieTla = 1 - ($0 / 100) }
                    ),
                    in: 0...40,
                    step: 1
                )
                Text(verbatim: "\(Int(((1 - ustawienia.krycieTla) * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            Text(String(localized: "Forced by our own layer, so it works with “Reduce transparency” switched on."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(String(localized: "Window width"))
                Slider(
                    value: $ustawienia.szerokoscOkna,
                    in: Ustawienia.zakresSzerokosciOkna,
                    step: 10
                )
                // Suwak nie trafia w konkretną liczbę — stąd pole do wpisania z palca
                // (AG-26). `TextField(value:format:)` zatwierdza na Enterze i przy wyjściu
                // z pola, nie przy każdym znaku, więc wpisywanie „900" nie przelicza okna
                // trzy razy po drodze. Zakres zaciska `Ustawienia`, nie widok.
                TextField(String(localized: "Window width"),
                          value: $ustawienia.szerokoscOkna,
                          format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .frame(width: 64)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text(verbatim: "pt")
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "The window no longer stretches sideways by dragging its edge — the width is set here and changes right away. Height still follows the edge."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "Type an exact value in the box — the slider moves in steps of 10 pt, and anything outside 520–2400 pt is pulled back into range."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle(String(localized: "Always open centered"), isOn: $ustawienia.oknoNaSrodku)
            Text(String(localized: "The window shows up in the middle of the screen the pointer is on, wherever it was dragged last time. Its size is still remembered."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sekcje u góry listy

    private var sekcjaGoraListy: some View {
        Section(String(localized: "Sections at the top of the list")) {
            Picker(String(localized: "Layout"), selection: $ustawienia.trybOstatnich) {
                ForEach(TrybOstatnich.allCases) { tryb in
                    Text(tryb.nazwa).tag(tryb)
                }
            }
            .pickerStyle(.radioGroup)

            Divider()

            Toggle(String(localized: "Recently installed"), isOn: $ustawienia.pokazujOstatnioDodane)
            Stepper(
                String(localized: "Items: \(ustawienia.ileOstatnioDodanych)"),
                value: $ustawienia.ileOstatnioDodanych,
                in: 1...20
            )
            .disabled(!ustawienia.pokazujOstatnioDodane || jedenRzad)

            Divider()

            Toggle(String(localized: "Recently used"), isOn: $ustawienia.pokazujOstatnioUzywane)
            Stepper(
                String(localized: "Items: \(ustawienia.ileOstatnioUzywanych)"),
                value: $ustawienia.ileOstatnioUzywanych,
                in: 1...20
            )
            .disabled(!ustawienia.pokazujOstatnioUzywane || jedenRzad)

            if jedenRzad {
                Text(String(localized: "In one shared row the window width decides how many icons fit — the counters are off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "“Recently used” counts launches from AppGrid — the system list only covers the Dock."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var jedenRzad: Bool { ustawienia.trybOstatnich == .jedenRzad }

    // MARK: - Ukryte programy

    private var sekcjaUkryte: some View {
        Section(String(localized: "Hidden apps")) {
            if ustawienia.ukryte.isEmpty {
                Text(String(localized: "Nothing is hidden."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ukrytePosortowane, id: \.id) { pozycja in
                    HStack {
                        Text(pozycja.nazwa)
                        Spacer()
                        Button(String(localized: "Show")) { ustawienia.odkryj(pozycja.id) }
                    }
                }
                Button(String(localized: "Restore all")) { ustawienia.odkryjWszystkie() }
            }

            Text(String(localized: "Hide an app with the right mouse button on its icon. Hidden apps come back the moment you type in the search field."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Nazwy bierzemy ze ścieżek, bez wciągania tu skanera — okno ustawień nie ma
    /// i nie potrzebuje listy programów.
    private var ukrytePosortowane: [(id: String, nazwa: String)] {
        ustawienia.ukryte
            .map { (id: $0, nazwa: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }
            .sorted { $0.nazwa.localizedStandardCompare($1.nazwa) == .orderedAscending }
    }

    // MARK: - Separatory

    private var sekcjaSeparatory: some View {
        Section(String(localized: "Grid layout")) {
            if ustawienia.separatory.isEmpty {
                Text(String(localized: "No separators yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ustawienia.separatory) { belka in
                    HStack {
                        TextField(String(localized: "Section name"), text: nazwaSeparatora(belka))
                            .frame(width: 200)
                        Spacer()
                        Button(String(localized: "Remove")) { ustawienia.usunSeparator(belka) }
                    }
                }
            }

            Button(String(localized: "Restore alphabetical order")) { ustawienia.przywrocAlfabet() }
                .disabled(ustawienia.kolejnosc.isEmpty
                          && ustawienia.kolejnoscNarzedzi.isEmpty
                          && ustawienia.separatory.isEmpty)

            Button(String(localized: "Send apps back to their own sections")) { ustawienia.wyczyscPrzypisania() }
                .disabled(ustawienia.przypisania.isEmpty)

            Text(String(localized: "Right-click an icon and pick “Edit layout…” — then you can drag icons around, add separators and name them."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "The layout covers “All apps” and “System utilities”, each with its own order — and you can drag icons from one to the other. The “recent” sections keep their own order."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "“Restore alphabetical order” only clears the order and the separators. Icons moved to the other section are brought back by the separate button."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func nazwaSeparatora(_ belka: Separator) -> Binding<String> {
        Binding(
            get: { ustawienia.separator(belka.id)?.nazwa ?? "" },
            set: { ustawienia.zmienNazweSeparatora(belka.id, na: $0) }
        )
    }

    // MARK: - O programie

    /// Numer wersji w ustawieniach — zamówienie [U] 2026-09-05 (AG-27).
    private var sekcjaOProgramie: some View {
        Section(String(localized: "About")) {
            HStack {
                Text(String(localized: "Version"))
                Spacer()
                Text(verbatim: Self.wersjaProgramu)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// Czytane z paczki, nie ze stałej w kodzie.
    ///
    /// Stała musiałaby być przepisywana ręcznie przy każdym podbiciu `MARKETING_VERSION`
    /// i pierwsze przeoczenie dałoby okno meldujące inną wersję niż paczka — dokładnie
    /// ta pułapka, która kosztowała całe wydanie [[CWMac]] (patrz `Tagi-i-wersje`).
    ///
    /// Numeru buildu tu **nie ma** — decyzja [U] 2026-09-05 (AG-28): *„ma być samo
    /// v.0.2.28"*. `CURRENT_PROJECT_VERSION` dalej rośnie, tylko nie wychodzi na wierzch.
    private static var wersjaProgramu: String {
        let wersja = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v.\(wersja)"
    }

    // MARK: - Okna Findera

    private var sekcjaFinder: some View {
        Section(String(localized: "Finder windows")) {
            Toggle(String(localized: "Manage Finder window size"), isOn: $ustawienia.finderWlaczony)

            if !finder.zgodaJest {
                HStack {
                    Label(
                        String(localized: "Needs Accessibility permission"),
                        systemImage: "lock"
                    )
                    .foregroundStyle(.orange)
                    Spacer()
                    Button(String(localized: "Grant…")) { finder.poprosOZgode() }
                }
            }

            if OknaFindera.podpisAdHoc() {
                Label(
                    String(localized: "This build is ad-hoc signed: every rebuild voids the Accessibility permission, even though the switch stays on. Remove AppGrid from the list and add it again after each build."),
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Picker(String(localized: "Mode"), selection: $ustawienia.finderTryb) {
                ForEach(TrybOkienFindera.allCases) { tryb in
                    Text(tryb.nazwa).tag(tryb)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(!ustawienia.finderWlaczony)

            HStack {
                Text(String(localized: "Size"))
                // Etykiety są ukryte wizualnie, ale VoiceOver je czyta — pole bez
                // etykiety zgłasza się jako „pole tekstowe" i nic więcej.
                TextField(String(localized: "Width"), value: $ustawienia.finderSzerokosc,
                          format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .frame(width: 70)
                Text(verbatim: "×")
                TextField(String(localized: "Height"), value: $ustawienia.finderWysokosc,
                          format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .frame(width: 70)
                Spacer()
                Button(String(localized: "Take from front window")) {
                    finder.wezRozmiarZBiezacegoOkna()
                }
            }
            // W trybie „każdy folder pamięta swój własny" rozmiar globalny nie jest
            // do niczego używany — wygaszamy go, żeby nie wyglądał na obowiązujący
            // (zgłoszenie [U] 2026-09-12).
            .disabled(!ustawienia.finderWlaczony || ustawienia.finderTryb == .osobnoPerFolder)

            if ustawienia.finderTryb == .osobnoPerFolder {
                Text(String(localized: "In this mode the size comes from windows you resize by hand. A folder with no remembered size stays exactly as Finder opened it."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                String(localized: "Learn from windows I resize by hand"),
                isOn: $ustawienia.finderUczySie
            )
            .disabled(!ustawienia.finderWlaczony)

            HStack {
                Button(String(localized: "Apply to all open windows")) {
                    finder.zastosujDoWszystkich()
                }
                if ustawienia.finderTryb == .osobnoPerFolder {
                    Button(String(localized: "Forget folder sizes")) {
                        finder.zapomnijFoldery()
                    }
                }
                Spacer()
            }
            .disabled(!ustawienia.finderWlaczony)

            if !finder.opisStanu.isEmpty {
                Text(finder.opisStanu)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Przycisk nagrywający skrót: klik → naciśnij kombinację.
private struct NagrywanieSkrotu: View {
    @ObservedObject var ustawienia: Ustawienia
    @State private var nagrywa = false
    @State private var podgladacz: Any?

    var body: some View {
        Button(nagrywa ? String(localized: "Press keys…") : ustawienia.opisSkrotu) {
            nagrywa ? przerwij() : zacznij()
        }
        .frame(minWidth: 120)
        .onDisappear { przerwij() }
    }

    private func zacznij() {
        nagrywa = true
        podgladacz = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { zdarzenie in
            guard zdarzenie.type == .keyDown else { return nil }
            let modyfikatory = zdarzenie.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])
            // Skrót globalny bez modyfikatora zjadałby zwykłe pisanie w każdym programie.
            guard !modyfikatory.isEmpty else { return nil }
            ustawienia.skrotKlawisz = Int(zdarzenie.keyCode)
            ustawienia.skrotModyfikatory = Int(modyfikatory.rawValue)
            przerwij()
            return nil
        }
    }

    private func przerwij() {
        if let podgladacz { NSEvent.removeMonitor(podgladacz) }
        podgladacz = nil
        nagrywa = false
    }
}
