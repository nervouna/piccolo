// Frames a window capture for the README: the window, with a soft shadow, on the cream radial
// gradient of the banner.
//
//     swift design/frame-screenshot.swift <capture.png> <output.png>
//
// The capture is a `screencapture -x -o -l <window>` of a Settings window at 2x (no system shadow,
// transparent corners). The output is the capture plus 176 px on the sides, 150 px above and
// 200 px below, at the same scale, so the README shows it at half its pixel width.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: frame-screenshot.swift <capture.png> <output.png>\n".utf8))
    exit(64)
}
guard let capture = NSImage(contentsOfFile: arguments[1]),
      let window = capture.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("cannot read \(arguments[1])\n".utf8))
    exit(66)
}

let windowWidth = CGFloat(window.width), windowHeight = CGFloat(window.height)
let padSide: CGFloat = 176, padTop: CGFloat = 150, padBottom: CGFloat = 200
let width = windowWidth + 2 * padSide, height = windowHeight + padTop + padBottom

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background: light cream in the middle, slightly above the window's centre, warmer at the edges.
let gradient = CGGradient(
    colorsSpace: space, colors: [color(0xFCF5EC), color(0xEFDDC6)] as CFArray, locations: nil)!
let centre = CGPoint(x: width * 0.5, y: height * 0.6)
context.drawRadialGradient(
    gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: height * 0.75,
    options: [.drawsAfterEndLocation])

// The window with two shadows, a wide soft one and a tight contact one. y points up here.
let frame = CGRect(x: padSide, y: padBottom, width: windowWidth, height: windowHeight)
for (offset, blur, alpha) in [(CGFloat(-36), CGFloat(110), CGFloat(0.32)), (-2, 6, 0.18)] {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: offset), blur: blur, color: color(0x000000, alpha: alpha))
    context.draw(window, in: frame)
    context.restoreGState()
}

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: arguments[2]))
