import CoreGraphics
import Foundation

/// A window as the window server reports it.
public struct OnScreenWindow: Sendable, Equatable {
    public var windowNumber: Int
    public var pid: pid_t
    public var ownerName: String
    /// In canonical coordinates: the window server already uses the global,
    /// top-left-origin space.
    public var frame: CGRect

    public init(windowNumber: Int, pid: pid_t, ownerName: String, frame: CGRect) {
        self.windowNumber = windowNumber
        self.pid = pid
        self.ownerName = ownerName
        self.frame = frame
    }
}

public enum OnScreenWindows {
    /// The ordinary windows (layer 0) that are on screen right now, front to back.
    ///
    /// Window titles are left out on purpose: the window server only reports them to
    /// processes with the Screen Recording permission.
    public static func list() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return parse(info)
    }

    /// Converts the window server's dictionaries. Order is preserved; entries that are
    /// not on layer 0 or that lack a required field are dropped.
    static func parse(_ entries: [[String: Any]]) -> [OnScreenWindow] {
        entries.compactMap { entry in
            guard let layer = entry["kCGWindowLayer"] as? Int, layer == 0,
                let number = entry["kCGWindowNumber"] as? Int,
                let pid = (entry["kCGWindowOwnerPID"] as? Int).flatMap({ pid_t(exactly: $0) }),
                let bounds = entry["kCGWindowBounds"] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return OnScreenWindow(
                windowNumber: number,
                pid: pid,
                ownerName: entry["kCGWindowOwnerName"] as? String ?? "",
                frame: frame)
        }
    }
}
