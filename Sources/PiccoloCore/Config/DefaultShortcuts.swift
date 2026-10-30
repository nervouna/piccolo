import Foundation

extension Config {
    /// The config a new install starts with: version 1, the default settings (resize step, window
    /// animation, grid fill order, destination preview) and the 27 bindings below, in this order.
    /// Each call makes new binding IDs, so two calls never share one.
    ///
    /// At launch, Piccolo writes this config to the default location when there is no file there
    /// (see `ShortcutManager.loadAtLaunch(from:)`). Settings restores only its bindings, through
    /// `defaultShortcuts.bindings`, and keeps the settings. Key codes are macOS virtual key codes
    /// (`kVK_*`).
    public static var defaultShortcuts: Config {
        Config(
            version: currentVersion,
            resizeStep: defaultResizeStep,
            animation: defaultAnimation,
            gridFillOrder: defaultGridFillOrder,
            destinationPreview: defaultDestinationPreview,
            bindings: defaultBindings)
    }

    private static var defaultBindings: [KeyBinding] {
        let controlOption: Set<Modifier> = [.control, .option]
        let controlOptionCommand: Set<Modifier> = [.control, .option, .command]
        let controlOptionShift: Set<Modifier> = [.control, .option, .shift]

        func binding(_ action: Action, _ keyCode: Int, _ modifiers: Set<Modifier>) -> KeyBinding {
            KeyBinding(id: UUID(), action: action, shortcut: Shortcut(keyCode: keyCode, modifiers: modifiers))
        }

        return [
            // Halves, quarters, thirds and the other places in a display.
            binding(.placeWindow(.preset(.leftHalf)), DefaultKey.leftArrow, controlOption),
            binding(.placeWindow(.preset(.rightHalf)), DefaultKey.rightArrow, controlOption),
            binding(.placeWindow(.preset(.topHalf)), DefaultKey.upArrow, controlOption),
            binding(.placeWindow(.preset(.bottomHalf)), DefaultKey.downArrow, controlOption),
            binding(.placeWindow(.preset(.topLeft)), DefaultKey.u, controlOption),
            binding(.placeWindow(.preset(.topRight)), DefaultKey.i, controlOption),
            binding(.placeWindow(.preset(.bottomLeft)), DefaultKey.j, controlOption),
            binding(.placeWindow(.preset(.bottomRight)), DefaultKey.k, controlOption),
            binding(.placeWindow(.preset(.leftThird)), DefaultKey.d, controlOption),
            binding(.placeWindow(.preset(.centerThird)), DefaultKey.f, controlOption),
            binding(.placeWindow(.preset(.rightThird)), DefaultKey.g, controlOption),
            binding(.placeWindow(.preset(.leftTwoThirds)), DefaultKey.e, controlOption),
            binding(.placeWindow(.preset(.rightTwoThirds)), DefaultKey.t, controlOption),
            binding(.placeWindow(.preset(.maximize)), DefaultKey.returnKey, controlOption),
            binding(.placeWindow(.preset(.center)), DefaultKey.c, controlOption),
            // Displays.
            binding(.moveToDisplay(.left), DefaultKey.leftArrow, controlOptionCommand),
            binding(.moveToDisplay(.right), DefaultKey.rightArrow, controlOptionCommand),
            binding(.moveToDisplay(.up), DefaultKey.upArrow, controlOptionCommand),
            binding(.moveToDisplay(.down), DefaultKey.downArrow, controlOptionCommand),
            // Grids of the most recently focused windows.
            binding(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), DefaultKey.two, controlOptionShift),
            binding(.arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3)), DefaultKey.three, controlOptionShift),
            binding(.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)), DefaultKey.four, controlOptionShift),
            binding(.arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3)), DefaultKey.six, controlOptionShift),
            // Linked resize. Not implemented yet: these bindings do nothing when pressed.
            binding(.moveDivider(.left), DefaultKey.leftArrow, controlOptionShift),
            binding(.moveDivider(.right), DefaultKey.rightArrow, controlOptionShift),
            binding(.moveDivider(.up), DefaultKey.upArrow, controlOptionShift),
            binding(.moveDivider(.down), DefaultKey.downArrow, controlOptionShift),
        ]
    }
}

/// The macOS virtual key codes the default shortcuts use (`kVK_*`).
private enum DefaultKey {
    static let leftArrow = 123
    static let rightArrow = 124
    static let downArrow = 125
    static let upArrow = 126
    static let returnKey = 36
    static let u = 32
    static let i = 34
    static let j = 38
    static let k = 40
    static let d = 2
    static let f = 3
    static let g = 5
    static let e = 14
    static let t = 17
    static let c = 8
    static let two = 19
    static let three = 20
    static let four = 21
    static let six = 22
}
