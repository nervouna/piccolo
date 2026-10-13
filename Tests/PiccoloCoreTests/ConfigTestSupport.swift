import Foundation

@testable import PiccoloCore

/// Runs `body` with a new, empty directory that is removed afterwards.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL.temporaryDirectory.appending(
        path: "piccolo-config-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// Names of the entries in `directory`, sorted.
func entryNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

/// Names of the files `load()` moves aside, for example `config.corrupt-20261014-103000.json`.
func corruptCopyNames(in directory: URL) throws -> [String] {
    try entryNames(in: directory).filter {
        $0.wholeMatch(of: #/config\.corrupt-\d{8}-\d{6}\.json/#) != nil
    }
}

/// Fixed IDs, so that expected file contents can be written out literally.
enum Fixture {
    static let idA = UUID(uuidString: "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40")!
    static let idB = UUID(uuidString: "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D")!
    static let idC = UUID(uuidString: "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A")!
    static let idD = UUID(uuidString: "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F")!
    static let idE = UUID(uuidString: "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D")!
}

/// One binding of each kind, with and without a shortcut.
let allKindsBindings: [Binding] = [
    Binding(
        id: Fixture.idA,
        action: .placeWindow(.preset(.leftHalf)),
        shortcut: Shortcut(keyCode: 123, modifiers: [.control, .option])),
    Binding(
        id: Fixture.idB,
        action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)))),
    Binding(id: Fixture.idC, action: .moveToDisplay(.next)),
    Binding(
        id: Fixture.idD,
        action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)),
        shortcut: Shortcut(keyCode: 18, modifiers: [.command, .shift])),
    Binding(
        id: Fixture.idE,
        action: .moveDivider(.left),
        shortcut: Shortcut(keyCode: 0, modifiers: []))
]
