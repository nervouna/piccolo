import AppKit
import PiccoloCore
import Testing

@testable import PiccoloUI

/// The keys that undo and redo in the Settings window, and what closing the window drops.
@MainActor
@Suite("Settings undo keys")
struct SettingsUndoKeyTests {
    private let host = SettingsHost(
        isAccessibilityTrusted: { true },
        openAccessibilitySettings: {},
        revealConfigInFinder: {},
        appVersion: "0.1.0 (1)")

    /// The controllers the tests made: a controller follows its model only while it lives.
    private static var made: [SettingsWindowController] = []

    private let left = KeyBinding(id: UIFixture.idA, action: .placeWindow(.preset(.leftHalf)), shortcut: UIFixture.f13)
    private let right = KeyBinding(id: UIFixture.idB, action: .placeWindow(.preset(.rightHalf)), shortcut: UIFixture.f14)

    private func makeController() -> (controller: SettingsWindowController, model: SettingsModel, window: NSWindow) {
        let backend = InMemorySettingsBackend(config: Config(gap: 16, bindings: [left, right]))
        let model = SettingsModel(backend: backend, loginItem: FakeLoginItem(), language: FakeLanguage())
        let controller = SettingsWindowController(
            model: model, host: host, frameName: "PiccoloSettingsTests.\(UUID().uuidString)")
        controller.visibleFrameProvider = { _ in CGRect(x: 0, y: 0, width: 2000, height: 1600) }
        controller.animatesFrameChanges = false
        let window = controller.ensureWindow()
        Self.made.append(controller)
        return (controller, model, window)
    }

    /// A key-down as the window receives it.
    private func keyDown(
        _ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in window: NSWindow
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: keyCode))
    }

    private func commandZ(in window: NSWindow) throws -> NSEvent {
        try keyDown("z", keyCode: 6, modifiers: [.command], in: window)
    }

    private func shiftCommandZ(in window: NSWindow) throws -> NSEvent {
        try keyDown("Z", keyCode: 6, modifiers: [.command, .shift], in: window)
    }

    // MARK: Which keys

    @Test("⌘Z is undo and ⇧⌘Z is redo, whatever the other state keys say")
    func commands() {
        func command(_ characters: String?, _ keyCode: Int, _ modifiers: Set<Modifier>) -> SettingsUndoKey.Command? {
            SettingsUndoKey.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
        }
        #expect(command("z", 6, [.command]) == .undo)
        #expect(command("Z", 6, [.command, .shift]) == .redo)
        #expect(command("z", 6, [.command, .shift]) == .redo)

        // No other combination is one.
        #expect(command("z", 6, []) == nil)
        #expect(command("z", 6, [.shift]) == nil)
        #expect(command("z", 6, [.control]) == nil)
        #expect(command("z", 6, [.option, .command]) == nil)
        #expect(command("z", 6, [.control, .command]) == nil)
        #expect(command("z", 6, [.option, .command, .shift]) == nil)
        #expect(command("y", 16, [.command]) == nil)
        #expect(command("x", 7, [.command]) == nil)
    }

    @Test("the key is the one that types Z on the layout; on a layout without Latin letters it is the Z of a US keyboard")
    func layouts() {
        func command(_ characters: String?, _ keyCode: Int) -> SettingsUndoKey.Command? {
            SettingsUndoKey.command(characters: characters, keyCode: keyCode, modifiers: [.command])
        }
        // AZERTY puts Z where a US keyboard has W, and W where it has Z.
        #expect(command("z", 13) == .undo)
        #expect(command("w", 6) == nil)
        // QWERTZ swaps Y and Z.
        #expect(command("z", 16) == .undo)
        #expect(command("y", 6) == nil)
        // A layout with no Latin letters types something else on the Z key; macOS matches ⌘ shortcuts by
        // the key then.
        #expect(command("я", 6) == .undo)
        #expect(command("я", 0) == nil)
        #expect(command(nil, 6) == .undo)
        #expect(command("", 6) == .undo)
        #expect(command(nil, 7) == nil)
    }

    // MARK: Undo and redo with the window

    @Test("⌘Z undoes the last change and ⇧⌘Z redoes it; the press is taken")
    func undoAndRedoByKey() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)

        #expect(controller.take(try commandZ(in: window)))
        #expect(model.gap == 16)
        #expect(controller.take(try shiftCommandZ(in: window)))
        #expect(model.gap == 20)
    }

    @Test("a press with nothing to undo is taken all the same, and changes nothing")
    func nothingToUndoByKey() throws {
        let (controller, model, window) = makeController()

        #expect(controller.take(try commandZ(in: window)))
        #expect(controller.take(try shiftCommandZ(in: window)))

        #expect(model.gap == 16)
        #expect(model.error == nil)
    }

    @Test("other keys are not taken")
    func otherKeys() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)

        #expect(!controller.take(try keyDown("z", keyCode: 6, modifiers: [], in: window)))
        #expect(!controller.take(try keyDown("y", keyCode: 16, modifiers: [.command], in: window)))
        #expect(!controller.take(try keyDown("z", keyCode: 6, modifiers: [.command, .option], in: window)))
        #expect(!controller.take(try keyDown("w", keyCode: 13, modifiers: [.command], in: window)))

        #expect(model.gap == 20)
    }

    @Test("caps lock does not stop ⌘Z")
    func otherFlags() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)

        #expect(controller.take(try keyDown("z", keyCode: 6, modifiers: [.command, .capsLock], in: window)))

        #expect(model.gap == 16)
    }

    // MARK: A text field

    @Test("a text field and its field editor keep ⌘Z: the press is not taken and nothing is undone")
    func textFieldKeepsItsUndo() throws {
        let (controller, model, window) = makeController()
        let contentView = try #require(window.contentView)
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        contentView.addSubview(field)
        model.setGap(20)

        #expect(window.makeFirstResponder(field))
        #expect(controller.firstResponderKind == .textField)
        #expect(!controller.take(try commandZ(in: window)))
        #expect(!controller.take(try shiftCommandZ(in: window)))
        #expect(model.gap == 20)

        // Once the focus has left the field, the window undoes again.
        #expect(window.makeFirstResponder(nil))
        #expect(controller.take(try commandZ(in: window)))
        #expect(model.gap == 16)
    }

    @Test("a control that is not a text field does not keep ⌘Z")
    func otherControlDoesNotKeepIt() throws {
        final class Focusable: NSView {
            override var acceptsFirstResponder: Bool { true }
        }
        let (controller, model, window) = makeController()
        let contentView = try #require(window.contentView)
        let focusable = Focusable(frame: NSRect(x: 10, y: 10, width: 100, height: 22))
        contentView.addSubview(focusable)
        model.setGap(20)
        #expect(window.makeFirstResponder(focusable))
        #expect(controller.firstResponderKind == .other)

        #expect(controller.take(try commandZ(in: window)))

        #expect(model.gap == 16)
    }

    // MARK: A sheet

    // A window that is not on screen cannot hold a sheet, so the `attachedSheet` half of the rule is not
    // unit tested; the model's request for the sheet (`layoutEditor`) is what the view shows it for.
    @Test("while the sheet of a layout is asked for or open, ⌘Z is left alone")
    func sheetKeepsIt() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)
        model.editLayout(.new(.grids))

        #expect(!controller.take(try commandZ(in: window)))
        #expect(model.gap == 20)

        model.dismissLayoutEditor()
        #expect(controller.take(try commandZ(in: window)))
        #expect(model.gap == 16)
    }

    // MARK: Recording

    @Test("while a row records, ⌘Z is a shortcut like any other: it is recorded and nothing is undone")
    func recordedWhileRecording() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)
        let topLeft = KeymapRowID.builtIn(.placeWindow(.preset(.topLeft)))
        model.beginRecording(topLeft)

        #expect(controller.take(try commandZ(in: window)))

        #expect(model.gap == 20, "the press undid the gap")
        #expect(model.recordingRow == nil)
        let recorded = Shortcut(keyCode: 6, modifiers: [.command])
        #expect(model.bindings.contains { $0.action == .placeWindow(.preset(.topLeft)) && $0.shortcut == recorded })

        // The recording is a change like any other, and the next ⌘Z undoes it.
        #expect(controller.take(try commandZ(in: window)))
        #expect(!model.bindings.contains { $0.shortcut == recorded })
        #expect(model.gap == 20)
    }

    @Test("⇧⌘Z while a row records is recorded too")
    func redoKeyRecordedWhileRecording() throws {
        let (controller, model, window) = makeController()
        model.setGap(20)
        model.undo()
        model.beginRecording(.builtIn(.placeWindow(.preset(.topLeft))))

        #expect(controller.take(try shiftCommandZ(in: window)))

        #expect(model.gap == 16, "the press redid the gap")
        #expect(model.canUndo)
        #expect(model.bindings.contains { $0.shortcut == Shortcut(keyCode: 6, modifiers: [.command, .shift]) })
    }

    // MARK: Closing the window

    @Test("closing the window drops a pending conflict, so that it does not come back with the window")
    func closingDropsConflict() throws {
        let (controller, model, _) = makeController()
        model.beginRecording(.builtIn(.placeWindow(.preset(.rightHalf))))
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(model.pendingConflict == nil)
        // Nothing was replaced.
        #expect(model.bindings == [left, right])
    }

    @Test("closing the window through the controller drops a pending conflict")
    func closeDropsConflict() {
        let (controller, model, _) = makeController()
        model.beginRecording(.builtIn(.placeWindow(.preset(.rightHalf))))
        model.record(UIFixture.f13)
        #expect(model.pendingConflict != nil)

        controller.close()

        #expect(model.pendingConflict == nil)
        #expect(model.bindings == [left, right])
    }

    @Test("closing the window keeps the history: it is the config's, not the window's")
    func closingKeepsHistory() {
        let (controller, model, _) = makeController()
        model.setGap(20)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(model.canUndo)
    }
}
