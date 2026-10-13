import CoreGraphics

extension JSONValue {
    /// A rect as `{"x", "y", "width", "height"}`, the form used for every frame in
    /// control responses and CLI output.
    public init(rect: CGRect) {
        self = .object([
            "x": .double(rect.origin.x),
            "y": .double(rect.origin.y),
            "width": .double(rect.size.width),
            "height": .double(rect.size.height),
        ])
    }

    /// The rect, or nil unless this is an object with numeric x, y, width and height.
    public var rectValue: CGRect? {
        guard let x = self["x"]?.doubleValue,
            let y = self["y"]?.doubleValue,
            let width = self["width"]?.doubleValue,
            let height = self["height"]?.doubleValue
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
