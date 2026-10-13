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
        .library(name: "PiccoloControl", targets: ["PiccoloControl"]),
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
            name: "PiccoloSystemTests",
            dependencies: ["PiccoloSystem", "PiccoloCore"]
        ),
        // Desktop acceptance: drives the installed Debug Piccolo and the PiccoloFixture
        // app and measures real window frames. Skipped unless PICCOLO_ACCEPTANCE=1;
        // run it with scripts/accept.sh.
        .testTarget(
            name: "PiccoloAcceptanceTests",
            dependencies: ["PiccoloControl", "PiccoloSystem", "PiccoloCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
