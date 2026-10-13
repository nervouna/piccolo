import Foundation
import PiccoloCore
import PiccoloSystem

/// The shortcuts the config tests may use. The tests register real global hotkeys on a
/// machine somebody works at, so they stay with combinations nobody else uses: all four
/// modifiers with F13 to F19.
enum TestShortcut {
    static let modifiers: Set<Modifier> = [.control, .option, .shift, .command]

    static let f13 = hyper(FunctionKey.f13)
    static let f14 = hyper(FunctionKey.f14)
    static let f15 = hyper(FunctionKey.f15)
    static let f16 = hyper(FunctionKey.f16)
    static let f17 = hyper(FunctionKey.f17)
    static let f18 = hyper(FunctionKey.f18)
    static let f19 = hyper(FunctionKey.f19)

    static func hyper(_ keyCode: Int) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: modifiers)
    }
}

/// A temporary directory that holds the config files of one test.
struct ConfigDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "piccolo-config-acceptance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Where a file called `name` lives in the directory.
    func file(_ name: String = "config.json") -> URL {
        url.appending(path: name)
    }

    /// Writes a config with `bindings` as `name`, the way Piccolo itself would, and returns its URL.
    @discardableResult
    func write(_ bindings: [KeyBinding], as name: String = "config.json") throws -> URL {
        let target = file(name)
        try ConfigStore(url: target).save(Config(bindings: bindings))
        return target
    }

    /// Writes `text` as `name`, whatever it is.
    @discardableResult
    func write(text: String, as name: String = "config.json") throws -> URL {
        let target = file(name)
        try Data(text.utf8).write(to: target)
        return target
    }

    /// The names of the files in the directory, sorted.
    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}

/// Runs `body` with a temporary directory for config files and makes sure that afterwards
/// Piccolo runs with its default config again, with nothing of the test left behind, whether
/// `body` succeeded or not:
///
/// - `config.reload` always runs, so that the test's hotkeys are released;
/// - `config.status.path` is the default location again;
/// - the temporary directory is removed;
/// - the default config directory holds what it held before.
func withConfigDirectory<Result>(
    _ body: (ConfigDirectory) async throws -> Result
) async throws -> Result {
    let piccolo = PiccoloClient()
    let directory = try ConfigDirectory()
    let defaultFolder = ConfigLocation.defaultURL.deletingLastPathComponent()
    let before = configFolderListing(of: defaultFolder)

    func tearDown() throws {
        defer { try? FileManager.default.removeItem(at: directory.url) }
        let status = try piccolo.reloadConfig()
        guard status.path == ConfigLocation.defaultURL.path else {
            throw AcceptanceFailure(
                "after config.reload Piccolo reports the config path \(status.path), not the default location \(ConfigLocation.defaultURL.path)"
            )
        }
        let after = configFolderListing(of: defaultFolder)
        guard after == before else {
            throw AcceptanceFailure(
                "the default config folder changed during the test: it held \(before.map(String.init(describing:)) ?? "nothing"), it now holds \(after.map(String.init(describing:)) ?? "nothing")"
            )
        }
    }

    let result: Result
    do {
        result = try await body(directory)
    } catch {
        try? tearDown()
        throw error
    }
    try tearDown()
    return result
}

/// The sorted names of the files in `folder`, or nil when it does not exist.
private func configFolderListing(of folder: URL) -> [String]? {
    try? FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
}
