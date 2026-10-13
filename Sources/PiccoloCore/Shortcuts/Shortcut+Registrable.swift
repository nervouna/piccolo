extension Shortcut {
    /// Whether this shortcut may be registered as a global hotkey.
    ///
    /// A shortcut needs `command`, `option` or `control`, or a function key. A function key
    /// is registrable with any modifiers, including none. `shift` alone does not qualify,
    /// because an ordinary key with only `shift` is typing and must not be taken over.
    public var isRegistrable: Bool {
        if FunctionKey.isFunctionKey(keyCode) {
            return true
        }
        return !modifiers.isDisjoint(with: [.command, .option, .control])
    }
}
