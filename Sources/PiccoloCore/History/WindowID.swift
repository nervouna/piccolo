/// Identifies one window by the window number the system assigns to it.
public struct WindowID: Hashable, Sendable, Codable {
    /// The system's window number.
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
