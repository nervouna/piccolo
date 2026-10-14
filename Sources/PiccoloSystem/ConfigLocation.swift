import Foundation

/// Where the config file lives.
public enum ConfigLocation {
    /// `~/Library/Application Support/Piccolo/config.json`. Loading never creates it, except at
    /// launch, when a missing file is written with the default shortcuts (`ShortcutManager.loadAtLaunch(from:)`).
    /// Any other load of a missing file means no bindings.
    public static var defaultURL: URL {
        let support =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Piccolo").appending(path: "config.json")
    }
}
