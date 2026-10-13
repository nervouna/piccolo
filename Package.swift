// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Piccolo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "PiccoloCore", targets: ["PiccoloCore"]),
        .library(name: "PiccoloSystem", targets: ["PiccoloSystem"]),
    ],
    targets: [
        // Pure logic: geometry, presets, grid and divider model, config schema.
        .target(name: "PiccoloCore"),
        // Adapters for Accessibility, windows, screens and hotkeys.
        .target(name: "PiccoloSystem"),
        .testTarget(
            name: "PiccoloCoreTests",
            dependencies: ["PiccoloCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
