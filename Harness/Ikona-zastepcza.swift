import AppKit

// Generator ZASTEPCZEJ ikony AppGrida.
//
// Nie jest czescia programu — Harness lezy poza grupa synchronizowana, wiec nie
// trafia do targetu. Sluzy do jednego: zeby gniazdo AppIcon nie bylo puste, dopoki
// [U] nie wstawi wlasnej grafiki. Podmiana wlasnej ikony NIE wymaga tego skryptu —
// wystarczy podmienic pliki PNG w AppGrid/Assets.xcassets/AppIcon.appiconset/.
//
// Uruchomienie:
//   cp Harness/Ikona-zastepcza.swift /tmp/main.swift
//   swiftc -O /tmp/main.swift -o /tmp/ikona && /tmp/ikona <katalog-docelowy>

let katalog = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// UWAGA: rysujemy do jawnej mapy bitowej o zadanej liczbie PIKSELI.
// NSImage.lockFocus() bierze skale ekranu — na Retinie kazdy plik wyszedl
// dwa razy wiekszy, niz mial (zmierzone 2026-08-20: 2048 px zamiast 1024).
func narysuj(bok: Int) -> NSBitmapImageRep? {
    let rozmiar = CGFloat(bok)
    guard let mapa = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: bok, pixelsHigh: bok,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    mapa.size = NSSize(width: rozmiar, height: rozmiar)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mapa)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Plyta w ksztalcie systemowej ikony: margines ~7%, mocno zaokraglone rogi.
    let margines = rozmiar * 0.07
    let plyta = NSRect(x: margines, y: margines,
                       width: rozmiar - 2 * margines, height: rozmiar - 2 * margines)
    let ksztalt = NSBezierPath(roundedRect: plyta,
                               xRadius: plyta.width * 0.235, yRadius: plyta.width * 0.235)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.44, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.24, blue: 0.80, alpha: 1),
    ])
    gradient?.draw(in: ksztalt, angle: -90)

    // Siatka 3x3 — sam znak firmowy: to jest "grid" z nazwy.
    let pole = plyta.width
    let kafel = pole * 0.205
    let odstep = pole * 0.075
    let szerokoscSiatki = 3 * kafel + 2 * odstep
    let start = NSPoint(x: plyta.minX + (pole - szerokoscSiatki) / 2,
                        y: plyta.minY + (pole - szerokoscSiatki) / 2)

    for wiersz in 0..<3 {
        for kolumna in 0..<3 {
            let ramka = NSRect(
                x: start.x + CGFloat(kolumna) * (kafel + odstep),
                y: start.y + CGFloat(wiersz) * (kafel + odstep),
                width: kafel, height: kafel
            )
            // Lekka roznica krycia daje glebie bez cieni, ktore w malych rozmiarach znikaja.
            let krycie = 0.82 + 0.06 * Double((wiersz + kolumna) % 3)
            NSColor(white: 1, alpha: krycie).setFill()
            NSBezierPath(roundedRect: ramka,
                         xRadius: kafel * 0.28, yRadius: kafel * 0.28).fill()
        }
    }
    return mapa
}

var bledy = 0
for bok in [16, 32, 64, 128, 256, 512, 1024] {
    guard let mapa = narysuj(bok: bok),
          let png = mapa.representation(using: .png, properties: [:]) else {
        print("  CZERWONE: nie udalo sie narysowac \(bok) px"); bledy += 1; continue
    }
    try? png.write(to: URL(fileURLWithPath: "\(katalog)/AppGrid-\(bok).png"))

    // PROBKA KONTROLNA: liczba pikseli odczytana z zapisanego pliku, nie z zamiaru.
    guard let sprawdzenie = NSBitmapImageRep(data: png) else { bledy += 1; continue }
    let zgadza = sprawdzenie.pixelsWide == bok && sprawdzenie.pixelsHigh == bok
    print("  AppGrid-\(bok).png -> \(sprawdzenie.pixelsWide)x\(sprawdzenie.pixelsHigh) px \(zgadza ? "OK" : "ZLE")")
    if !zgadza { bledy += 1 }
}
print(bledy == 0 ? "ikona zastepcza gotowa" : "BLEDY: \(bledy)")
exit(bledy == 0 ? 0 : 1)
