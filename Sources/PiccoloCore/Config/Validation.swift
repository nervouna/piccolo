import Foundation

/// A value that breaks a rule of the configuration model.
public enum ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A number that must be finite is NaN or infinite.
    case notFinite(field: String)
    /// A value is outside its allowed range. `rule` states the requirement, for example "must be >= 0".
    case outOfRange(field: String, rule: String)
    /// Two bindings share this ID.
    case duplicateBindingID(UUID)
    /// The config's version is not the one this build reads and writes.
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .notFinite(let field):
            "\(field) must be a finite number"
        case .outOfRange(let field, let rule):
            "\(field) \(rule)"
        case .duplicateBindingID(let id):
            "duplicate binding id \(id.uuidString)"
        case .unsupportedVersion(let version):
            "config version \(version) is not supported"
        }
    }
}

// Validation is internal: `ConfigStore` applies it on save and on load.

extension FractionalRect {
    /// Slack on the `x + width <= 1` and `y + height <= 1` bounds, for rounding noise in fractions.
    static let edgeTolerance = 1e-9

    func validate() throws(ValidationError) {
        for (field, value) in [("x", x), ("y", y), ("width", width), ("height", height)] {
            guard value.isFinite else { throw .notFinite(field: field) }
        }
        guard x >= 0 else { throw .outOfRange(field: "x", rule: "must be >= 0") }
        guard y >= 0 else { throw .outOfRange(field: "y", rule: "must be >= 0") }
        guard width > 0 else { throw .outOfRange(field: "width", rule: "must be > 0") }
        guard height > 0 else { throw .outOfRange(field: "height", rule: "must be > 0") }
        guard x + width <= 1 + Self.edgeTolerance else {
            throw .outOfRange(field: "x + width", rule: "must be <= 1")
        }
        guard y + height <= 1 + Self.edgeTolerance else {
            throw .outOfRange(field: "y + height", rule: "must be <= 1")
        }
    }
}

extension GridSpec {
    func validate() throws(ValidationError) {
        guard rows >= 1 else { throw .outOfRange(field: "rows", rule: "must be >= 1") }
        guard columns >= 1 else { throw .outOfRange(field: "columns", rule: "must be >= 1") }
        guard count >= 1 else { throw .outOfRange(field: "count", rule: "must be >= 1") }
        // A product that overflows is larger than any count, so it caps at `Int.max`.
        let (cells, overflow) = rows.multipliedReportingOverflow(by: columns)
        let capacity = overflow ? Int.max : cells
        guard count <= capacity else {
            throw .outOfRange(field: "count", rule: "must be <= rows * columns")
        }
    }
}

extension Shortcut {
    func validate() throws(ValidationError) {
        guard keyCode >= 0 else { throw .outOfRange(field: "keyCode", rule: "must be >= 0") }
    }
}

extension Action {
    func validate() throws(ValidationError) {
        switch self {
        case .placeWindow(.preset), .moveToDisplay, .moveDivider:
            return
        case .placeWindow(.custom(let rect)):
            try rect.validate()
        case .arrangeGrid(let grid):
            try grid.validate()
        }
    }
}

extension Binding {
    func validate() throws(ValidationError) {
        try action.validate()
        try shortcut?.validate()
    }
}

extension Config {
    func validate() throws(ValidationError) {
        guard version == Config.currentVersion else { throw .unsupportedVersion(version) }
        try Config.validateResizeStep(resizeStep)
        var seen: Set<UUID> = []
        for binding in bindings {
            try binding.validate()
            guard seen.insert(binding.id).inserted else {
                throw .duplicateBindingID(binding.id)
            }
        }
    }

    static func validateResizeStep(_ value: Double) throws(ValidationError) {
        guard value.isFinite else { throw .notFinite(field: "resizeStep") }
        guard value > 0, value <= 0.5 else {
            throw .outOfRange(field: "resizeStep", rule: "must be > 0 and <= 0.5")
        }
    }
}
