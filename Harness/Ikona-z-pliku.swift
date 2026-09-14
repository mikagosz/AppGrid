import AppKit

// Wstawianie WLASNEJ ikony [U] do gniazda AppIcon.
//
// Robi trzy rzeczy, ktorych `sips` nie zrobi:
//  1. wycina biale tlo (plik od [U] nie ma kanalu alfa — zmierzone 2026-08-20),
//  2. odbieliwa krawedz, czyli odwraca zmieszanie piksela z bialym tlem,
//  3. wypuszcza wszystkie 7 rozmiarow i SPRAWDZA liczbe pikseli w zapisanym pliku.
//
// Dwa warianty, bo to decyzja [U], nie moja:
//   pelna — ksztalt na calym plotnie, tak jak w oryginale
//   macos — ksztalt zmniejszony do proporcji systemowych (824 z 1024), czyli tak,
//           jak siedza ikony sasiadow w Docku
//
//   cp Harness/Ikona-z-pliku.swift /tmp/main.swift
//   swiftc -O /tmp/main.swift -o /tmp/ikona && /tmp/ikona <zrodlo.png> <katalog-wyjsciowy>

let argumenty = CommandLine.arguments
guard argumenty.count > 2 else { print("uzycie: ikona <zrodlo.png> <katalog>"); exit(2) }
let zrodloSciezka = argumenty[1]
let katalog = argumenty[2]

let BOK = 1024
/// Proporcja z systemowej siatki ikon macOS: ksztalt zajmuje 824 z 1024 px plotna.
let PROPORCJA_MACOS = 824.0 / 1024.0
/// Piksel uznajemy za tlo, gdy jest praktycznie bialy. Zmierzone: tlo ma rowno 255,
/// a przejscie w ciemny ksztalt trwa 2–3 px, wiec prog moze byc wysoki.
let PROG_BIELI = 245

func wczytajRGBA(_ sciezka: String) -> NSBitmapImageRep? {
    guard let dane = FileManager.default.contents(atPath: sciezka),
          let zrodlo = NSBitmapImageRep(data: dane) else { return nil }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: BOK, pixelsHigh: BOK,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: BOK * 4, bitsPerPixel: 32
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    zrodlo.draw(in: NSRect(x: 0, y: 0, width: BOK, height: BOK))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard let rep = wczytajRGBA(zrodloSciezka), let bajty = rep.bitmapData else {
    print("nie da sie wczytac \(zrodloSciezka)"); exit(1)
}

// --- 1. Wypelnienie od krawedzi: tlem jest TYLKO biel polaczona z brzegiem. ---
// Bez tego bialy dymek iMessage i tarcza zegara w srodku ikony tez zniknelyby.
var tlo = [Bool](repeating: false, count: BOK * BOK)
var stos: [Int] = []
func bialy(_ i: Int) -> Bool {
    let o = i * 4
    return Int(bajty[o]) >= PROG_BIELI && Int(bajty[o+1]) >= PROG_BIELI && Int(bajty[o+2]) >= PROG_BIELI
}
for x in 0..<BOK {
    for i in [x, (BOK - 1) * BOK + x, x * BOK, x * BOK + BOK - 1] where !tlo[i] && bialy(i) {
        tlo[i] = true; stos.append(i)
    }
}
while let i = stos.popLast() {
    let x = i % BOK, y = i / BOK
    for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
        let nx = x + dx, ny = y + dy
        guard nx >= 0, nx < BOK, ny >= 0, ny < BOK else { continue }
        let j = ny * BOK + nx
        if !tlo[j], bialy(j) { tlo[j] = true; stos.append(j) }
    }
}

// --- 2. Maska: erozja o 1 px zdejmuje bialy rabek po antyaliasingu, ---
//        rozmycie 3x3 wygladza schodki.
var maska = [Float](repeating: 0, count: BOK * BOK)
for i in 0..<(BOK * BOK) where !tlo[i] { maska[i] = 1 }
var poErozji = maska
for y in 0..<BOK {
    for x in 0..<BOK where maska[y * BOK + x] == 1 {
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let nx = x + dx, ny = y + dy
            if nx < 0 || nx >= BOK || ny < 0 || ny >= BOK || tlo[ny * BOK + nx] {
                poErozji[y * BOK + x] = 0
            }
        }
    }
}
var wygladzona = poErozji
for y in 1..<(BOK - 1) {
    for x in 1..<(BOK - 1) {
        var suma: Float = 0
        for dy in -1...1 { for dx in -1...1 { suma += poErozji[(y + dy) * BOK + x + dx] } }
        wygladzona[y * BOK + x] = suma / 9
    }
}

// --- 3. Odbielenie krawedzi: piksel polprzezroczysty byl zmieszany z bialym tlem, ---
//        wiec odwracamy to mieszanie, zeby nie zostala jasna obwodka.
for i in 0..<(BOK * BOK) {
    let a = wygladzona[i]
    let o = i * 4
    if a <= 0.004 {
        bajty[o] = 0; bajty[o+1] = 0; bajty[o+2] = 0; bajty[o+3] = 0
        continue
    }
    if a < 0.996 {
        for k in 0..<3 {
            let zmieszany = Float(bajty[o + k])
            let czysty = (zmieszany - 255 * (1 - a)) / a
            bajty[o + k] = UInt8(max(0, min(255, czysty)))
        }
    }
    bajty[o + 3] = UInt8(max(0, min(255, a * 255)))
}

let wyciety = NSImage(size: NSSize(width: BOK, height: BOK))
wyciety.addRepresentation(rep)

// --- 4. Zapis obu wariantow ---
func zapisz(wariant: String, proporcja: Double) -> Int {
    let sciezka = "\(katalog)/\(wariant)"
    try? FileManager.default.createDirectory(atPath: sciezka, withIntermediateDirectories: true)
    var bledy = 0
    // KAZDE gniazdo musi miec WLASNY plik, nawet gdy dwa gniazda maja te sama
    // liczbe pikseli (16@2x i 32 to oba 32 px). Przy wspolnym pliku actool
    // wpuszcza do .icns tylko pierwsze gniazdo i po cichu gubi resztę —
    // zmierzone 2026-08-20: z 10 gniazd do paczki weszly 4.
    for (nazwa, bok) in [("16", 16), ("16@2x", 32), ("32", 32), ("32@2x", 64),
                         ("128", 128), ("128@2x", 256), ("256", 256), ("256@2x", 512),
                         ("512", 512), ("512@2x", 1024)] {
        guard let cel = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: bok, pixelsHigh: bok,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: bok * 4, bitsPerPixel: 32
        ) else { bledy += 1; continue }
        cel.size = NSSize(width: bok, height: bok)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: cel)
        NSGraphicsContext.current?.imageInterpolation = .high
        let widoczny = Double(bok) * proporcja
        let margines = (Double(bok) - widoczny) / 2
        wyciety.draw(in: NSRect(x: margines, y: margines, width: widoczny, height: widoczny),
                     from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = cel.representation(using: .png, properties: [:]) else { bledy += 1; continue }
        try? png.write(to: URL(fileURLWithPath: "\(sciezka)/AppGrid-\(nazwa).png"))
        // PROBKA KONTROLNA: wymiary czytane z zapisanego pliku, nie z zamiaru.
        guard let sprawdzenie = NSBitmapImageRep(data: png),
              sprawdzenie.pixelsWide == bok, sprawdzenie.pixelsHigh == bok,
              sprawdzenie.hasAlpha else { print("  CZERWONE: \(wariant)/AppGrid-\(nazwa).png"); bledy += 1; continue }
    }
    print("  \(wariant): 10 plikow, kanal alfa obecny, wymiary zgodne \(bledy == 0 ? "OK" : "— BLEDY: \(bledy)")")
    return bledy
}

var bledy = zapisz(wariant: "pelna", proporcja: 1.0)
bledy += zapisz(wariant: "macos", proporcja: PROPORCJA_MACOS)

// Ile plotna zajmuje ksztalt — liczba do porownania, nie wrazenie.
let widocznych = maska.reduce(into: 0) { if $1 > 0 { $0 += 1 } }
print(String(format: "ksztalt zajmuje %.1f%% plotna zrodla (systemowa siatka macOS: 65%% powierzchni)",
             Double(widocznych) / Double(BOK * BOK) * 100))
print(bledy == 0 ? "gotowe" : "BLEDY: \(bledy)")
exit(bledy == 0 ? 0 : 1)
