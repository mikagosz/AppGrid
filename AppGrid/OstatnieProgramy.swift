import AppKit

/// Sekcje „ostatnio zainstalowane" i „ostatnio używane" u góry listy (pozycja AG-1).
///
/// Obie są **opcjami** — domyślnie wyłączone, włącza je [U] w ustawieniach.
enum OstatnieProgramy {

    /// Ile wpisów najwyżej trzymamy w dzienniku uruchomień.
    static let pojemnoscDziennika = 200

    /// Ostatnio zainstalowane — po dacie dodania paczki do katalogu.
    ///
    /// Programy systemowe są pomijane świadomie: wszystkie mają jeden znacznik z chwili
    /// instalacji systemu, więc po czystej instalacji zalałyby sekcję kilkudziesięcioma
    /// pozycjami z tą samą datą — a żadna z nich nie jest „świeżo dodana" w sensie,
    /// o który chodzi. Wpisy bez daty odpadają, bo nie ma czego po nich sortować.
    nonisolated static func ostatnioDodane(_ lista: [InstalledApp], ile: Int) -> [InstalledApp] {
        guard ile > 0 else { return [] }
        return lista
            .filter { !$0.isSystem && $0.dataDodania != nil }
            .sorted { a, b in
                let da = a.dataDodania ?? .distantPast
                let db = b.dataDodania ?? .distantPast
                if da != db { return da > db }
                // Remis rozstrzygamy nazwą, żeby kolejność nie tańczyła między odświeżeniami.
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            .prefix(ile)
            .map { $0 }
    }

    /// Ostatnio używane — z własnego dziennika uruchomień.
    ///
    /// Systemowa lista ostatnich programów obejmuje wyłącznie te odpalone przez Dock,
    /// więc uruchomienia z AppGrida i tak by w niej nie było. Liczymy sami.
    nonisolated static func ostatnioUzywane(
        _ lista: [InstalledApp],
        dziennik: [String: Date],
        ile: Int
    ) -> [InstalledApp] {
        guard ile > 0 else { return [] }
        return lista
            .compactMap { app -> (InstalledApp, Date)? in
                guard let kiedy = dziennik[app.id] else { return nil }
                return (app, kiedy)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
            }
            .prefix(ile)
            .map { $0.0 }
    }

    /// Jeden wspólny rząd: „ostatnio zainstalowane" i „ostatnio używane" razem w linii.
    ///
    /// Program trafia do rzędu po **nowszej** z dwóch dat. Systemowy wchodzi wyłącznie
    /// przez datę użycia — daty dodania mają wszystkie jedną, z chwili instalacji systemu,
    /// więc zalałyby rząd (ten sam powód co w `ostatnioDodane`).
    ///
    /// `zDodanych` i `zUzywanych` to te same dwa przełączniki co przy osobnych sekcjach:
    /// decydują, co w ogóle wchodzi do rzędu, a nie ile.
    nonisolated static func scalone(
        _ lista: [InstalledApp],
        dziennik: [String: Date],
        zDodanych: Bool,
        zUzywanych: Bool,
        ile: Int
    ) -> [InstalledApp] {
        guard ile > 0, zDodanych || zUzywanych else { return [] }
        return lista
            .compactMap { app -> (InstalledApp, Date)? in
                var kiedy: Date?
                if zDodanych, !app.isSystem, let dodany = app.dataDodania {
                    kiedy = dodany
                }
                if zUzywanych, let uzyty = dziennik[app.id] {
                    kiedy = max(kiedy ?? .distantPast, uzyty)
                }
                guard let kiedy else { return nil }
                return (app, kiedy)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
            }
            .prefix(ile)
            .map { $0.0 }
    }

    /// Przycina dziennik do pojemności, zostawiając najświeższe wpisy.
    nonisolated static func przytnij(_ dziennik: [String: Date], do ile: Int = pojemnoscDziennika) -> [String: Date] {
        guard dziennik.count > ile else { return dziennik }
        let zostaja = dziennik.sorted { $0.value > $1.value }.prefix(ile)
        return Dictionary(uniqueKeysWithValues: zostaja.map { ($0.key, $0.value) })
    }
}

/// Dziennik uruchomień: ścieżka programu → kiedy ostatnio odpalony z AppGrida.
@MainActor
final class DziennikUruchomien {

    private static let klucz = "AppGrid.dziennikUruchomien"

    private(set) var wpisy: [String: Date]

    init() {
        wpisy = UserDefaults.standard.dictionary(forKey: Self.klucz) as? [String: Date] ?? [:]
    }

    func zapiszUruchomienie(_ app: InstalledApp, kiedy: Date = Date()) {
        wpisy[app.id] = kiedy
        wpisy = OstatnieProgramy.przytnij(wpisy)
        UserDefaults.standard.set(wpisy, forKey: Self.klucz)
    }

    func wyczysc() {
        wpisy = [:]
        UserDefaults.standard.removeObject(forKey: Self.klucz)
    }
}
