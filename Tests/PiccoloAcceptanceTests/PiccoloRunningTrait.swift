import Testing

/// Makes sure a Piccolo is running before every acceptance test starts.
///
/// A test that restarts Piccolo and fails to start it again must fail by itself, with the real
/// reason, and not take every test after it along with "nothing is listening on the control
/// service". So each test begins by asking Piccolo for its status, and launches the installed
/// bundle when nothing answers (see ``PiccoloProcess/ensureRunning(timeout:)``). When even that
/// fails, the test that was about to run fails with what the launch reported.
///
/// It is applied once, to the root suite, and every nested suite inherits it.
struct PiccoloRunningTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    /// The scope is provided around each test, not around the suites that contain them.
    func scopeProvider(for test: Test, testCase: Test.Case?) -> PiccoloRunningTrait? {
        test.isSuite ? nil : self
    }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        if let launch = try await PiccoloProcess.ensureRunning() {
            print(
                "Piccolo was not running before '\(test.name)'; launched it (pid \(launch.pid), \(launch.openCalls) open call(s), \(launch.failedOpens.count) failed)"
            )
        }
        try await function()
    }
}

extension Trait where Self == PiccoloRunningTrait {
    /// Piccolo is running when the test starts: it is launched if it is not.
    static var piccoloRunning: Self { Self() }
}
