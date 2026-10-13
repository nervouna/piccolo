/// The macOS virtual key codes of the function keys F1 to F20 (`kVK_F1` and so on).
public enum FunctionKey {
    public static let f1 = 122
    public static let f2 = 120
    public static let f3 = 99
    public static let f4 = 118
    public static let f5 = 96
    public static let f6 = 97
    public static let f7 = 98
    public static let f8 = 100
    public static let f9 = 101
    public static let f10 = 109
    public static let f11 = 103
    public static let f12 = 111
    public static let f13 = 105
    public static let f14 = 107
    public static let f15 = 113
    public static let f16 = 106
    public static let f17 = 64
    public static let f18 = 79
    public static let f19 = 80
    public static let f20 = 90

    private static let codes: Set<Int> = [
        f1, f2, f3, f4, f5, f6, f7, f8, f9, f10,
        f11, f12, f13, f14, f15, f16, f17, f18, f19, f20,
    ]

    /// Whether `keyCode` is the code of one of F1 to F20.
    public static func isFunctionKey(_ keyCode: Int) -> Bool {
        codes.contains(keyCode)
    }
}
