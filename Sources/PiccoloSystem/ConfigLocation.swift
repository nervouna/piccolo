import Foundation

/// Where the config file lives.
public enum ConfigLocation {
    /// `~/Library/Application Support/Piccolo/config.json`. Nothing is created: a missing file
    /// means no bindings.
    public static var defaultURL: URL {
        let support =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Piccolo").appending(path: "config.json")
    }
}
