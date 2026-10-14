#if DEBUG
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The control command about the destination preview: `preview.state`. Debug builds only, like the
/// control server itself. The commands that hold and release a shortcut (`hotkey.press`,
/// `hotkey.release`, `hotkey.escape`) are in `DebugConfigCommands.swift`.
extension DebugControlServer {
    /// Registers `preview.state`, which answers
    /// `{visible, frames: [rect], windows?: [number], heldBindingID?, escapeRegistered, planningError?, last?}`:
    ///
    /// - `visible` and `frames`: whether the highlight is on screen, and the frames it is drawn at, in
    ///   canonical coordinates. A window of the app's own process is on screen at each of them (at a
    ///   window level above ordinary windows, so not among the layer 0 windows).
    /// - `windows`: the window each frame is for, in the order of the frames; only for an arrangement or
    ///   a divider move.
    /// - `heldBindingID`: the binding whose shortcut is down, until it is released.
    /// - `escapeRegistered`: whether the temporary Escape hotkey is registered.
    /// - `planningError`: why the latest plan showed nothing, when it failed.
    /// - `last`: what became of the last hold: `{bindingID, result: "ran" | "cancelled", previewShown}`.
    ///   `previewShown` is true when the highlight reached the screen during that hold. With the preview
    ///   off, a press is a run and `previewShown` is false.
    nonisolated static func registerPreviewCommands(in router: inout ControlRouter) {
        router.register("preview.state") { _ in
            onMainActor {
                let controller = ConfigController.shared
                let preview = controller.preview
                var state: [String: JSONValue] = [
                    "visible": .bool(preview.isVisible),
                    "frames": .array(preview.frames.map { JSONValue(rect: $0) }),
                    "escapeRegistered": .bool(controller.escapeIsRegistered),
                ]
                if let windows = preview.windows {
                    state["windows"] = .array(windows.map { .int(Int($0.rawValue)) })
                }
                if let held = controller.held {
                    state["heldBindingID"] = .string(held.id.uuidString)
                }
                if let error = preview.lastError {
                    state["planningError"] = .string(error)
                }
                if let last = controller.lastHold {
                    state["last"] = .object([
                        "bindingID": .string(last.id.uuidString),
                        "result": .string(last.result.rawValue),
                        "previewShown": .bool(last.previewShown && preview.lastShowPresented),
                    ])
                }
                return .object(state)
            }
        }
    }
}
#endif
