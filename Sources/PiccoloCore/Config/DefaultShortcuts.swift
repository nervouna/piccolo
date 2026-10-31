import Foundation

extension Config {
    /// The config a new install starts with: version 1, the default settings (resize step, window
    /// animation, grid fill order, destination preview, window gap) and the 33 bindings below, in
    /// this order.
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
            gap: defaultGap,
            bindings: defaultBindings)
    }

    private static var defaultBindings: [KeyBinding] {
        let controlOption: Set<Modifier> = [.control, .option]
        let controlOptionCommand: Set<Modifier> = [.control, .option, .command]
        let controlOptionShift: Set<Modifier> = [.control, .option, .shift]

        func binding(_ action: Action, _ keyCode: Int, _ modifiers: Set<Modifier>) -> KeyBinding {
            KeyBinding(id: UUID(), action: action, shortcut: Shortcut(keyCode: keyCode, modifiers: modifiers))
        }

        // Top Half and Bottom Half have no default shortcut: their keymap rows show none.
        return [
            // Halves, quarters, thirds and the other places in a display.
            binding(.placeWindow(.preset(.leftHalf)), DefaultKey.h, controlOption),
            binding(.placeWindow(.preset(.rightHalf)), DefaultKey.l, controlOption),
            binding(.placeWindow(.preset(.topLeft)), DefaultKey.u, controlOption),
            binding(.placeWindow(.preset(.topRight)), DefaultKey.i, controlOption),
            binding(.placeWindow(.preset(.bottomLeft)), DefaultKey.j, controlOption),
            binding(.placeWindow(.preset(.bottomRight)), DefaultKey.k, controlOption),
            binding(.placeWindow(.preset(.leftThird)), DefaultKey.a, controlOption),
            binding(.placeWindow(.preset(.centerThird)), DefaultKey.s, controlOption),
            binding(.placeWindow(.preset(.rightThird)), DefaultKey.d, controlOption),
            binding(.placeWindow(.preset(.leftTwoThirds)), DefaultKey.q, controlOption),
            binding(.placeWindow(.preset(.rightTwoThirds)), DefaultKey.e, controlOption),
            binding(.placeWindow(.preset(.maximize)), DefaultKey.r, controlOption),
            binding(.placeWindow(.preset(.center)), DefaultKey.c, controlOption),
            // Back to where Piccolo found the window.
            binding(.restoreWindow, DefaultKey.delete, controlOption),
            // Displays.
            binding(.moveToDisplay(.next), DefaultKey.rightBracket, controlOption),
            binding(.moveToDisplay(.previous), DefaultKey.leftBracket, controlOption),
            binding(.moveToDisplay(.left), DefaultKey.leftArrow, controlOptionCommand),
            binding(.moveToDisplay(.right), DefaultKey.rightArrow, controlOptionCommand),
            binding(.moveToDisplay(.up), DefaultKey.upArrow, controlOptionCommand),
            binding(.moveToDisplay(.down), DefaultKey.downArrow, controlOptionCommand),
            // Grids of the most recently focused windows.
            binding(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), DefaultKey.two, controlOption),
            binding(.arrangeGrid(GridSpec(count: 3, rows: 1, columns: 3)), DefaultKey.three, controlOption),
            binding(.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 2)), DefaultKey.four, controlOption),
            binding(.arrangeGrid(GridSpec(count: 6, rows: 2, columns: 3)), DefaultKey.six, controlOption),
            // Linked resize: move a divider of the group Piccolo arranged.
            binding(.moveDivider(.left), DefaultKey.minus, controlOption),
            binding(.moveDivider(.right), DefaultKey.equal, controlOption),
            binding(.moveDivider(.up), DefaultKey.minus, controlOptionShift),
            binding(.moveDivider(.down), DefaultKey.equal, controlOptionShift),
            // Swap the focused window with its neighbour in the group Piccolo arranged.
            binding(.swapWindow(.left), DefaultKey.leftArrow, controlOption),
            binding(.swapWindow(.right), DefaultKey.rightArrow, controlOption),
            binding(.swapWindow(.up), DefaultKey.upArrow, controlOption),
            binding(.swapWindow(.down), DefaultKey.downArrow, controlOption),
            // A custom area: centred, half the width and 65% of the height, 10% from the top.
            binding(
                .placeWindow(.custom(FractionalRect(x: 0.25, y: 0.1, width: 0.5, height: 0.65))),
                DefaultKey.w, controlOption),
        ]
    }
}

/// The macOS virtual key codes the default shortcuts use (`kVK_*`).
private enum DefaultKey {
    static let leftArrow = 123
    static let rightArrow = 124
    static let downArrow = 125
    static let upArrow = 126
    static let delete = 51
    static let a = 0
    static let s = 1
    static let d = 2
    static let h = 4
    static let c = 8
    static let q = 12
    static let w = 13
    static let e = 14
    static let r = 15
    static let u = 32
    static let i = 34
    static let j = 38
    static let k = 40
    static let l = 37
    static let two = 19
    static let three = 20
    static let four = 21
    static let six = 22
    static let equal = 24
    static let minus = 27
    static let rightBracket = 30
    static let leftBracket = 33
}
