import Foundation

/// Pilnuje katalogów z programami i odświeża listę, gdy coś w nich dojdzie albo zniknie (0.2.41).
///
/// Do 0.2.40 lista powstawała raz, przy starcie (`AppGridModel.reload()` w `applicationDidFinishLaunching`),
/// więc program zainstalowany w trakcie pojawiał się dopiero po restarcie albo „Odśwież” w menu
/// (zgłoszenie [U] 2026-10-01). FSEvents patrzy rekurencyjnie, czyli łapie też podkatalogi
/// (`Utilities`, foldery producentów) — te same, które skanuje `AppScanner`.
///
/// Instalacja to setki zapisów do wnętrza paczki — zdarzenia zbierają się przez `opoznienie`
/// i dopiero po ciszy idzie jedno odświeżenie.
final class ObserwatorProgramow {
    private var strumien: FSEventStreamRef?
    private var odroczone: DispatchWorkItem?
    private let zmiana: () -> Void

    /// Ile sekund ciszy po ostatnim zdarzeniu, zanim lista się odświeży.
    static let opoznienie: TimeInterval = 2

    init(zmiana: @escaping () -> Void) {
        self.zmiana = zmiana
    }

    func start(katalogi: [URL]) {
        stop()
        let sciezki = katalogi.map(\.path) as CFArray
        var kontekst = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let wywolanie: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ObserwatorProgramow>.fromOpaque(info).takeUnretainedValue().odroczOdswiezenie()
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, wywolanie, &kontekst, sciezki,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        strumien = s
    }

    func stop() {
        odroczone?.cancel()
        guard let s = strumien else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        strumien = nil
    }

    private func odroczOdswiezenie() {
        odroczone?.cancel()
        let zadanie = DispatchWorkItem { [weak self] in self?.zmiana() }
        odroczone = zadanie
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.opoznienie, execute: zadanie)
    }

    deinit { stop() }
}
