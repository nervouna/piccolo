#if DEBUG
import CoreGraphics
import Foundation
import PiccoloControl
import PiccoloCore

/// The control command about the failure notice: `notice.state`. Debug builds only, like the control
/// server itself.
extension DebugControlServer {
    /// Registers `notice.state`, which answers `{visible: Bool, last?: {kind, text, frame}}`:
    ///
    /// - `visible`: whether a notice is on screen (a window of the app's own process, on layer 25).
    /// - `last`: the latest notice shown since launch. `kind` is the stable name of the notice
    ///   (`FailureNotice.rawValue`, for example `noGroup`), `text` the text shown and `frame` the panel's
    ///   frame in canonical coordinates.
    ///
    /// `action.run` never shows a notice, so a notice here always came from a hotkey.
    nonisolated static func registerNoticeCommands(in router: inout ControlRouter) {
        router.register("notice.state") { _ in
            onMainActor {
                let controller = NoticeController.shared
                var state: [String: JSONValue] = ["visible": .bool(controller.isVisible)]
                if let last = controller.last {
                    state["last"] = .object([
                        "kind": .string(last.notice.rawValue),
                        "text": .string(last.text),
                        "frame": JSONValue(rect: last.frame),
                    ])
                }
                return .object(state)
            }
        }
    }
}
#endif
