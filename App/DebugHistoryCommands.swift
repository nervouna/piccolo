#if DEBUG
import Foundation
import PiccoloControl
import PiccoloCore
import PiccoloSystem

/// The control command about what Piccolo remembers of the windows it moved. Debug builds only, like
/// the control server itself.
extension DebugControlServer {
    /// Registers `history.list`: `[{"window": number, "origin": rect, "lastAchieved": rect,
    /// "preset"?: name, "step"?: 0 | 1 | 2}]`, the window records Piccolo holds, ordered by window
    /// number, in canonical coordinates. `preset` and `step` are there when the window was last placed
    /// by a cycling preset. Empty when there is none.
    nonisolated static func registerHistoryCommands(
        in router: inout ControlRouter, executor: @escaping @Sendable () -> ActionExecutor
    ) {
        router.register("history.list") { _ in
            .array(
                executor().windowRecords.map { window, record -> JSONValue in
                    var entry: [String: JSONValue] = [
                        "window": .int(Int(window.rawValue)),
                        "origin": JSONValue(rect: record.origin),
                        "lastAchieved": JSONValue(rect: record.lastAchieved),
                    ]
                    if let cycle = record.cycle {
                        entry["preset"] = .string(cycle.preset.rawValue)
                        entry["step"] = .int(cycle.step)
                    }
                    return .object(entry)
                })
        }
    }
}
#endif
