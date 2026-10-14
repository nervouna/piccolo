// Helper for scripts/make-icon.sh and scripts/check-icon-render.sh. It inspects and
// normalizes the app icon artwork (design/icon.png), and checks the icon that the system
// renders for a built app.
//
// Usage:
//   icon-tool stats <artwork.png>
//       Alpha inside the artwork's interior: the base region reached from the centre through
//       pixels with alpha >= 128, eroded by 3 px so that the anti-aliased rim is left out.
//   icon-tool check <artwork.png>
//       Exits 1 unless every interior pixel is fully opaque (alpha 255).
//   icon-tool normalize <in.png> <out.png> [threshold]
//       Sets the alpha of every pixel with alpha >= threshold (default 240) to 255. Colour
//       channels are straight (unpremultiplied) and are not touched, so colours are preserved;
//       every other pixel is left as it was.
//   icon-tool render <app> <outdir> <size>...
//       Writes the icon that NSWorkspace returns for the bundle, drawn at each size, to
//       <outdir>/icon-<size>.png.
//   icon-tool panes <artwork.png> <render.png>
//       Splits the artwork into its panes (the colour regions inside the base), locates the
//       base in the render, and samples a 9x9 grid inside each pane's rendered counterpart.
//       A pane is flat when every sample has the pane's colour and the pane has no off-colour
//       pixels in its inset area. Exits 1 unless all panes are flat.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

struct Image {
    let width: Int
    let height: Int
    var pixels: [UInt8]  // straight RGBA, 4 bytes per pixel, row by row
    let colorSpace: CGColorSpace

    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func load(_ path: String) -> Image {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("\(path): cannot be read as an image") }
    // Only 8-bit straight RGBA in the byte order of the PNG is read directly, so that the colour
    // channels are exactly the ones stored in the file.
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32, image.alphaInfo == .last,
          image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == 0,
          let provider = image.dataProvider, let data = provider.data
    else { fail("\(path): expected an 8-bit straight RGBA image") }
    let bytes = CFDataGetBytePtr(data)!
    let rowBytes = image.bytesPerRow
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for i in 0..<(width * 4) {
            pixels[y * width * 4 + i] = bytes[y * rowBytes + i]
        }
    }
    return Image(width: width, height: height, pixels: pixels,
                 colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
}

func save(_ image: Image, to path: String) {
    guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
          let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8,
                                bitsPerPixel: 32, bytesPerRow: image.width * 4,
                                space: image.colorSpace,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
    else { fail("cannot write \(path)") }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(path)") }
}

// MARK: - Interior

struct Masks {
    var base: [Bool]      // reached from the centre through alpha >= 128
    var interior: [Bool]  // base pixels whose 7x7 neighbourhood is all base
}

func masks(_ image: Image) -> Masks {
    let w = image.width, h = image.height
    guard image.alpha(w / 2, h / 2) >= 128 else { fail("the centre of the artwork is not opaque") }
    var base = [Bool](repeating: false, count: w * h)
    let seed = (h / 2) * w + w / 2
    base[seed] = true
    var queue = [seed]
    var head = 0
    while head < queue.count {
        let p = queue[head]
        head += 1
        let x = p % w, y = p / w
        let neighbours = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        for (nx, ny) in neighbours where nx >= 0 && nx < w && ny >= 0 && ny < h {
            let q = ny * w + nx
            if !base[q] && image.pixels[q * 4 + 3] >= 128 {
                base[q] = true
                queue.append(q)
            }
        }
    }
    // Summed-area table of the base mask, to test each 7x7 neighbourhood in constant time.
    var sums = [Int](repeating: 0, count: (w + 1) * (h + 1))
    for y in 0..<h {
        var rowSum = 0
        for x in 0..<w {
            rowSum += base[y * w + x] ? 1 : 0
            sums[(y + 1) * (w + 1) + (x + 1)] = sums[y * (w + 1) + (x + 1)] + rowSum
        }
    }
    let r = 3
    let full = (2 * r + 1) * (2 * r + 1)
    var interior = [Bool](repeating: false, count: w * h)
    for y in r..<(h - r) {
        for x in r..<(w - r) where base[y * w + x] {
            let x0 = x - r, x1 = x + r + 1, y0 = y - r, y1 = y + r + 1
            let s = sums[y1 * (w + 1) + x1] - sums[y0 * (w + 1) + x1]
                - sums[y1 * (w + 1) + x0] + sums[y0 * (w + 1) + x0]
            if s == full { interior[y * w + x] = true }
        }
    }
    return Masks(base: base, interior: interior)
}

func stats(_ path: String) {
    let image = load(path)
    let m = masks(image)
    let w = image.width, h = image.height
    var histogram = [Int](repeating: 0, count: 256)
    var interiorCount = 0
    var lowest: (alpha: UInt8, x: Int, y: Int) = (255, 0, 0)
    var blockMin = [[Int]](repeating: [Int](repeating: -1, count: 16), count: 16)
    for y in 0..<h {
        for x in 0..<w where m.interior[y * w + x] {
            let a = image.alpha(x, y)
            interiorCount += 1
            histogram[Int(a)] += 1
            if a < lowest.alpha { lowest = (a, x, y) }
            let bx = min(x * 16 / w, 15), by = min(y * 16 / h, 15)
            if blockMin[by][bx] < 0 || Int(a) < blockMin[by][bx] { blockMin[by][bx] = Int(a) }
        }
    }
    let base = m.base.reduce(0) { $0 + ($1 ? 1 : 0) }
    print("base region: \(base) px, interior (rim removed): \(interiorCount) px")
    let notOpaque = interiorCount - histogram[255]
    print("interior pixels with alpha below 255: \(notOpaque)")
    print("interior pixels with alpha below 240: \(histogram[0..<240].reduce(0, +))")
    print("lowest interior alpha: \(lowest.alpha) at x=\(lowest.x) y=\(lowest.y)")
    print("interior alpha histogram (alpha: count):")
    var line = ""
    for a in stride(from: 255, through: 0, by: -1) where histogram[a] > 0 {
        line += "\(a): \(histogram[a])  "
    }
    print(line)
    print("minimum interior alpha per 1/16 block (rows top to bottom, '.' = no interior):")
    for row in blockMin {
        print(row.map { $0 < 0 ? "  ." : String(format: "%3d", $0) }.joined(separator: " "))
    }
}

func check(_ path: String) {
    let image = load(path)
    let m = masks(image)
    var notOpaque = 0
    var lowest: (alpha: UInt8, x: Int, y: Int) = (255, 0, 0)
    for y in 0..<image.height {
        for x in 0..<image.width where m.interior[y * image.width + x] {
            let a = image.alpha(x, y)
            if a < 255 {
                notOpaque += 1
                if a < lowest.alpha { lowest = (a, x, y) }
            }
        }
    }
    guard notOpaque == 0 else {
        var hint = "Run scripts/make-icon.sh --normalize to set every interior alpha of 240 or more to 255."
        if lowest.alpha < 240 {
            hint = "Pixels below alpha 240 are not normalized automatically; look at the artwork first."
        }
        fail("""
            \(path): the interior is not fully opaque: \(notOpaque) pixels below alpha 255, \
            the lowest is \(lowest.alpha) at x=\(lowest.x) y=\(lowest.y). macOS draws such an \
            icon with blotches (scripts/check-icon-render.sh shows them). \(hint)
            """)
    }
    print("interior fully opaque")
}

func normalize(_ input: String, _ output: String, threshold: UInt8) {
    var image = load(input)
    let original = image
    let m = masks(image)
    var changed = 0, changedInside = 0
    for p in 0..<(image.width * image.height) {
        let a = image.pixels[p * 4 + 3]
        if a >= threshold && a != 255 {
            image.pixels[p * 4 + 3] = 255
            changed += 1
            if m.interior[p] { changedInside += 1 }
        }
    }
    save(image, to: output)

    // Verify the written file: colour channels and every unchanged alpha are identical.
    let written = load(output)
    guard written.width == original.width, written.height == original.height else {
        fail("the written file has another size")
    }
    var colourDifferences = 0, alphaDifferences = 0
    for p in 0..<(original.width * original.height) {
        for c in 0..<3 where written.pixels[p * 4 + c] != original.pixels[p * 4 + c] {
            colourDifferences += 1
        }
        let a = original.pixels[p * 4 + 3]
        let expected: UInt8 = a >= threshold ? 255 : a
        if written.pixels[p * 4 + 3] != expected { alphaDifferences += 1 }
    }
    guard colourDifferences == 0, alphaDifferences == 0 else {
        fail("verification failed: \(colourDifferences) colour and \(alphaDifferences) alpha values differ")
    }
    print("alpha set to 255 on \(changed) pixels (\(changedInside) inside the interior, threshold \(threshold))")
    print("verified: colour channels identical everywhere, all other alpha values unchanged")
}

// MARK: - Rendering

func render(app: String, outDirectory: String, sizes: [Int]) {
    let icon = NSWorkspace.shared.icon(forFile: app)
    for size in sizes {
        guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep),
              let png = {
                  NSGraphicsContext.saveGraphicsState()
                  NSGraphicsContext.current = context
                  context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
                  icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
                            operation: .sourceOver, fraction: 1)
                  NSGraphicsContext.restoreGraphicsState()
                  return rep.representation(using: .png, properties: [:])
              }()
        else { fail("cannot render the icon at \(size) px") }
        let path = (outDirectory as NSString).appendingPathComponent("icon-\(size).png")
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            fail("cannot write \(path): \(error.localizedDescription)")
        }
        print("rendered \(size)x\(size) to \(path)")
    }
}

// MARK: - Panes

struct Box {
    var x0: Int, y0: Int, x1: Int, y1: Int, area: Int
}

// Connected components (4-neighbourhood) of the pixels for which member is true.
func components(width w: Int, height h: Int, _ member: (Int) -> Bool) -> [Box] {
    var seen = [Bool](repeating: false, count: w * h)
    var boxes: [Box] = []
    for start in 0..<(w * h) where !seen[start] && member(start) {
        seen[start] = true
        var queue = [start]
        var head = 0
        var box = Box(x0: w, y0: h, x1: -1, y1: -1, area: 0)
        while head < queue.count {
            let p = queue[head]
            head += 1
            let x = p % w, y = p / w
            box.area += 1
            box.x0 = min(box.x0, x); box.x1 = max(box.x1, x)
            box.y0 = min(box.y0, y); box.y1 = max(box.y1, y)
            let neighbours = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            for (nx, ny) in neighbours where nx >= 0 && nx < w && ny >= 0 && ny < h {
                let q = ny * w + nx
                if !seen[q] && member(q) {
                    seen[q] = true
                    queue.append(q)
                }
            }
        }
        boxes.append(box)
    }
    return boxes
}

typealias Colour = (r: Double, g: Double, b: Double)

func distance(_ a: Colour, _ b: Colour) -> Double {
    let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
    return (dr * dr + dg * dg + db * db).squareRoot()
}

// Index of the centre nearest to the colour, or -1 when none is within maxDistance.
func nearest(_ c: Colour, _ centres: [Colour], maxDistance: Double) -> Int {
    var best = -1
    var bestDistance = maxDistance
    for (i, centre) in centres.enumerated() {
        let d = distance(c, centre)
        if d <= bestDistance {
            best = i
            bestDistance = d
        }
    }
    return best
}

func colour(_ image: Image, _ x: Int, _ y: Int) -> Colour {
    let i = (y * image.width + x) * 4
    return (Double(image.pixels[i]), Double(image.pixels[i + 1]), Double(image.pixels[i + 2]))
}

// Finds the three colour regions of the artwork (cream base, brown panes, blue pane) by
// k-means over the base, seeded with the most common colours. Returns the centres in the
// order cream, brown, blue.
func paneColours(_ image: Image, _ base: [Bool]) -> [Colour] {
    var bins: [Int: Int] = [:]
    for p in 0..<(image.width * image.height) where base[p] {
        let i = p * 4
        let key = ((Int(image.pixels[i]) >> 4) << 8) | ((Int(image.pixels[i + 1]) >> 4) << 4)
            | (Int(image.pixels[i + 2]) >> 4)
        bins[key, default: 0] += 1
    }
    var seeds: [Colour] = []
    for (key, _) in bins.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key })
        where seeds.count < 3 {
        let c: Colour = (Double((key >> 8) & 15) * 16 + 8, Double((key >> 4) & 15) * 16 + 8,
                         Double(key & 15) * 16 + 8)
        if seeds.allSatisfy({ distance($0, c) >= 60 }) { seeds.append(c) }
    }
    guard seeds.count == 3 else { fail("the artwork does not have three distinct colour regions") }

    var centres = seeds
    var counts = [Int](repeating: 0, count: 3)
    for _ in 0..<8 {
        var sums = [Colour](repeating: (0, 0, 0), count: 3)
        counts = [0, 0, 0]
        for p in 0..<(image.width * image.height) where base[p] {
            let c = colour(image, p % image.width, p / image.width)
            let k = nearest(c, centres, maxDistance: .infinity)
            sums[k].r += c.r; sums[k].g += c.g; sums[k].b += c.b
            counts[k] += 1
        }
        for k in 0..<3 where counts[k] > 0 {
            let n = Double(counts[k])
            centres[k] = (sums[k].r / n, sums[k].g / n, sums[k].b / n)
        }
    }
    // The largest region is the cream base; of the other two, blue is the one with more blue than red.
    let order = [0, 1, 2].sorted { counts[$0] > counts[$1] }
    let cream = centres[order[0]]
    let others = [centres[order[1]], centres[order[2]]]
    let blue = others[0].b - others[0].r > others[1].b - others[1].r ? others[0] : others[1]
    let brown = others[0].b - others[0].r > others[1].b - others[1].r ? others[1] : others[0]
    return [cream, brown, blue]
}

func panes(artwork: String, rendered: String) {
    let art = load(artwork)
    let ren = load(rendered)
    let m = masks(art)
    let names = ["cream", "brown", "blue"]
    let centres = paneColours(art, m.base)
    print("artwork region colours: " + zip(names, centres).map { name, c in
        "\(name) (\(Int(c.r)), \(Int(c.g)), \(Int(c.b)))"
    }.joined(separator: ", "))

    // Label every artwork pixel of the base, and every render pixel that has alpha >= 128.
    let artLabel: [Int] = (0..<(art.width * art.height)).map { p in
        m.base[p] ? nearest(colour(art, p % art.width, p / art.width), centres, maxDistance: .infinity) : -1
    }
    let renLabel: [Int] = (0..<(ren.width * ren.height)).map { p in
        ren.pixels[p * 4 + 3] >= 128
            ? nearest(colour(ren, p % ren.width, p / ren.width), centres, maxDistance: 45) : -1
    }

    // The base: the largest cream component in each image.
    func largestCream(_ labels: [Int], _ w: Int, _ h: Int) -> Box? {
        components(width: w, height: h) { labels[$0] == 0 }.max { $0.area < $1.area }
    }
    guard let artBase = largestCream(artLabel, art.width, art.height),
          let renBase = largestCream(renLabel, ren.width, ren.height)
    else { fail("cannot find the base in the artwork or the render") }
    let sx = Double(renBase.x1 - renBase.x0 + 1) / Double(artBase.x1 - artBase.x0 + 1)
    let sy = Double(renBase.y1 - renBase.y0 + 1) / Double(artBase.y1 - artBase.y0 + 1)
    let ox = Double(renBase.x0) - Double(artBase.x0) * sx
    let oy = Double(renBase.y0) - Double(artBase.y0) * sy
    print(String(format: "base in artwork x %d-%d y %d-%d, in render x %d-%d y %d-%d, scale %.4f / %.4f",
                 artBase.x0, artBase.x1, artBase.y0, artBase.y1,
                 renBase.x0, renBase.x1, renBase.y0, renBase.y1, sx, sy))
    func renderX(_ x: Double) -> Int { min(max(Int((x * sx + ox).rounded(.down)), 0), ren.width - 1) }
    func renderY(_ y: Double) -> Int { min(max(Int((y * sy + oy).rounded(.down)), 0), ren.height - 1) }

    // Panes: brown and blue components of the artwork that are large enough to be a pane.
    var found: [(name: String, label: Int, box: Box)] = []
    for (label, name) in [(1, "brown"), (2, "blue")] {
        for box in components(width: art.width, height: art.height, { artLabel[$0] == label })
        where box.area >= (art.width * art.height) / 200 {
            found.append((name, label, box))
        }
    }
    print("panes in artwork: \(found.count)")

    var allFlat = found.count == 3
    for pane in found {
        let b = pane.box
        let insetX = Double(b.x1 - b.x0) * 0.12, insetY = Double(b.y1 - b.y0) * 0.12
        let ax0 = Double(b.x0) + insetX, ax1 = Double(b.x1) - insetX
        let ay0 = Double(b.y0) + insetY, ay1 = Double(b.y1) - insetY

        var samples: [Colour] = []
        var matches = 0
        for gy in 0..<9 {
            for gx in 0..<9 {
                let x = ax0 + (ax1 - ax0) * Double(gx) / 8
                let y = ay0 + (ay1 - ay0) * Double(gy) / 8
                let px = renderX(x), py = renderY(y)
                let c = colour(ren, px, py)
                samples.append(c)
                if nearest(c, centres, maxDistance: 45) == pane.label && ren.alpha(px, py) == 255 {
                    matches += 1
                }
            }
        }
        let median = Colour(
            r: samples.map { $0.r }.sorted()[samples.count / 2],
            g: samples.map { $0.g }.sorted()[samples.count / 2],
            b: samples.map { $0.b }.sorted()[samples.count / 2])
        var maxDeviation = 0.0
        for c in samples {
            maxDeviation = max(maxDeviation, abs(c.r - median.r), abs(c.g - median.g), abs(c.b - median.b))
        }

        // Every render pixel in the inset area, not only the grid.
        var inArea = 0, offColour = 0
        for py in renderY(ay0)...renderY(ay1) {
            for px in renderX(ax0)...renderX(ax1) {
                inArea += 1
                let label = nearest(colour(ren, px, py), centres, maxDistance: 45)
                if label != pane.label || ren.alpha(px, py) != 255 { offColour += 1 }
            }
        }
        let offFraction = Double(offColour) / Double(max(inArea, 1))
        let flat = matches == samples.count && maxDeviation <= 24 && offFraction < 0.005
        allFlat = allFlat && flat
        print(String(format: "%@ pane x %d-%d y %d-%d: grid %d/%d match, median (%d, %d, %d), max deviation %d, off-colour pixels %.2f%% of %d -> %@",
                     pane.name, b.x0, b.x1, b.y0, b.y1, matches, samples.count,
                     Int(median.r), Int(median.g), Int(median.b), Int(maxDeviation),
                     offFraction * 100, inArea, flat ? "flat" : "NOT FLAT"))
    }
    print(allFlat ? "verdict: all panes flat" : "verdict: panes NOT flat")
    if !allFlat { exit(1) }
}

// MARK: - Command line

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: icon-tool stats|check <artwork.png> | normalize <in.png> <out.png> [threshold] | render <app> <outdir> <size>... | panes <artwork.png> <render.png>")
}
switch arguments[1] {
case "stats":
    stats(arguments[2])
case "check":
    check(arguments[2])
case "normalize":
    guard arguments.count >= 4 else { fail("usage: icon-tool normalize <in.png> <out.png> [threshold]") }
    let threshold = arguments.count >= 5 ? UInt8(arguments[4]) ?? 240 : 240
    normalize(arguments[2], arguments[3], threshold: threshold)
case "render":
    guard arguments.count >= 5 else { fail("usage: icon-tool render <app> <outdir> <size>...") }
    let sizes = arguments[4...].map { Int($0) ?? 0 }
    guard sizes.allSatisfy({ $0 > 0 }) else { fail("sizes must be positive integers") }
    render(app: arguments[2], outDirectory: arguments[3], sizes: sizes)
case "panes":
    guard arguments.count >= 4 else { fail("usage: icon-tool panes <artwork.png> <render.png>") }
    panes(artwork: arguments[2], rendered: arguments[3])
default:
    fail("unknown command \(arguments[1])")
}
