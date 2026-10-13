import CoreGraphics
import Foundation

/// Why an acceptance step failed, in words that say what was expected and what was
/// measured. Thrown by the support code; the tests let it propagate.
struct AcceptanceFailure: Error, CustomStringConvertible, LocalizedError {
    let message: String
    /// False when waiting longer cannot help (for example nothing listens on a control
    /// service), so that polling loops give up at once instead of at their timeout.
    let isRetryable: Bool

    init(_ message: String, isRetryable: Bool = true) {
        self.message = message
        self.isRetryable = isRetryable
    }

    var description: String { message }
    var errorDescription: String? { message }
}

/// Switches and locations shared by the acceptance tests.
enum Acceptance {
    /// The acceptance tests move real windows, so they only run when asked to.
    static let environmentVariable = "PICCOLO_ACCEPTANCE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentVariable] == "1"
    }

    /// The stress tests repeat one operation many times to catch what fails once in a while. They
    /// take minutes and are not part of a normal acceptance run.
    static let stressEnvironmentVariable = "PICCOLO_STRESS"

    static var isStressEnabled: Bool {
        ProcessInfo.processInfo.environment[stressEnvironmentVariable] == "1"
    }

    /// How many rounds a stress test makes: `PICCOLO_STRESS_COUNT`, 30 by default.
    static var stressCount: Int {
        ProcessInfo.processInfo.environment["PICCOLO_STRESS_COUNT"].flatMap { Int($0) }.map { max($0, 1) } ?? 30
    }

    /// The number of active displays. Read through CoreGraphics so that it can be asked
    /// from a test trait, off the main thread.
    static var displayCount: Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    /// The checkout this file belongs to.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PiccoloAcceptanceTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root

    /// The built fixture. `scripts/accept.sh` passes it in `PICCOLO_FIXTURE_APP`; without
    /// the variable it is the one `scripts/build.sh debug` leaves in `build/`.
    static var fixtureAppURL: URL {
        if let path = ProcessInfo.processInfo.environment["PICCOLO_FIXTURE_APP"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return repositoryRoot.appendingPathComponent("build/PiccoloFixture.app")
    }
}
