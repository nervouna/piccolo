import Foundation

/// The shortcuts from a config that may be registered as global hotkeys, and the reasons others were skipped.
///
/// Build one with `resolve(_:sourceIndices:)`. It applies these rules in binding order:
/// - a binding without a shortcut is skipped silently;
/// - a shortcut that is not registrable (see `Shortcut.isRegistrable`) is skipped with an issue;
/// - a shortcut equal to one already accepted (same key code and modifier set) is skipped with an
///   issue that names both bindings. The first binding keeps the shortcut.
public struct ShortcutPlan: Equatable, Sendable {
    /// One shortcut to register, under the ID of the binding it came from.
    public struct Registration: Equatable, Sendable {
        public let id: UUID
        public let shortcut: Shortcut

        public init(id: UUID, shortcut: Shortcut) {
            self.id = id
            self.shortcut = shortcut
        }
    }

    /// The accepted shortcuts, in binding order.
    public let registrations: [Registration]
    /// One human-readable line per skipped shortcut, in binding order. Each names its binding as
    /// `bindings[i]`, where `i` is the binding's position in the file when `resolve(_:sourceIndices:)`
    /// was given it, and its zero-based position in the input otherwise.
    public let issues: [String]

    /// Decides which shortcuts of `bindings` may be registered.
    ///
    /// - Parameter sourceIndices: The position in the file of each binding, by ID, as
    ///   `LoadResult.sourceIndices` gives it. Issues name a binding by that position. A binding
    ///   that is not in the map is named by its position in `bindings` instead. Without a map,
    ///   every issue names the position in `bindings`.
    public static func resolve(
        _ bindings: [KeyBinding], sourceIndices: [UUID: Int] = [:]
    ) -> ShortcutPlan {
        var registrations: [Registration] = []
        var issues: [String] = []
        // Accepted shortcuts with the position of their binding, so that a duplicate can name the first one.
        var accepted: [(position: Int, shortcut: Shortcut)] = []

        for (index, binding) in bindings.enumerated() {
            guard let shortcut = binding.shortcut else {
                continue
            }
            let position = sourceIndices[binding.id] ?? index
            guard shortcut.isRegistrable else {
                issues.append(
                    "bindings[\(position)] shortcut needs command, option or control, or a function key; it is not registered")
                continue
            }
            if let first = accepted.first(where: { $0.shortcut == shortcut }) {
                issues.append(
                    "bindings[\(position)] has the same shortcut as bindings[\(first.position)], which keeps it; bindings[\(position)] is not registered")
                continue
            }
            accepted.append((position: position, shortcut: shortcut))
            registrations.append(Registration(id: binding.id, shortcut: shortcut))
        }

        return ShortcutPlan(registrations: registrations, issues: issues)
    }
}
