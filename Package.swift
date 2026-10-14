// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Piccolo",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "PiccoloCore", targets: ["PiccoloCore"]),
        .library(name: "PiccoloSystem", targets: ["PiccoloSystem"]),
        .library(name: "PiccoloControl", targets: ["PiccoloControl"]),
        .library(name: "PiccoloUI", targets: ["PiccoloUI"]),
        .executable(name: "piccoloctl", targets: ["piccoloctl"]),
    ],
    targets: [
        // Pure logic: geometry, presets, grid and divider model, config schema.
        .target(name: "PiccoloCore"),
        // Adapters for Accessibility, windows, screens and hotkeys.
        .target(
            name: "PiccoloSystem",
            dependencies: ["PiccoloCore"]
        ),
        // Request/response protocol, server and client of the local control channel.
        .target(name: "PiccoloControl"),
        // The Settings window: its model, the texts it shows and the SwiftUI and AppKit views.
        .target(
            name: "PiccoloUI",
            dependencies: ["PiccoloCore"],
            resources: [
                // The texts of the window, in all eight languages (see CLAUDE.md, "Localization").
                .process("Resources/Localizable.xcstrings"),
            ]
        ),
        // Command line client for the control channel and window/screen queries.
        .executableTarget(
            name: "piccoloctl",
            dependencies: ["PiccoloControl", "PiccoloSystem", "PiccoloCore"]
        ),
        .testTarget(
            name: "PiccoloCoreTests",
            dependencies: ["PiccoloCore"]
        ),
        .testTarget(
            name: "PiccoloControlTests",
            dependencies: ["PiccoloControl"]
        ),
        .testTarget(
            name: "PiccoloUITests",
            dependencies: ["PiccoloUI", "PiccoloCore"]
        ),
        .testTarget(
            name: "PiccoloSystemTests",
            dependencies: ["PiccoloSystem", "PiccoloCore"]
        ),
        // Desktop acceptance: drives the installed Debug Piccolo and the PiccoloFixture
        // app and measures real window frames. Skipped unless PICCOLO_ACCEPTANCE=1;
        // run it with scripts/accept.sh.
        .testTarget(
            name: "PiccoloAcceptanceTests",
            // PiccoloUI for the texts: the tests that compare what Piccolo shows ask it for the same
            // text in the language Piccolo runs in (see InterfaceTexts).
            dependencies: ["PiccoloControl", "PiccoloSystem", "PiccoloCore", "PiccoloUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
