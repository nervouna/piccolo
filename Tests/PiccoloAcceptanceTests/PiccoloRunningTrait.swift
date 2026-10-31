import Testing

/// Makes sure a Piccolo is running, on the config of a fresh install, before every acceptance test
/// starts.
///
/// A test that restarts Piccolo and fails to start it again must fail by itself, with the real
/// reason, and not take every test after it along with "nothing is listening on the control
/// service". So each test begins by asking Piccolo for its status, and launches the installed
/// bundle when nothing answers (see ``PiccoloProcess/ensureRunning(timeout:)``). When even that
/// fails, the test that was about to run fails with what the launch reported.
///
/// Then it loads the config of a fresh install (``FreshInstallConfig``) from a temporary directory:
/// whatever the config at the default location holds, a test starts from the default settings and
/// bindings, and an edit in Settings that a test makes without a config of its own lands in the
/// temporary file. A test that needs other settings loads its own config (`withConfigDirectory`,
/// which hands Piccolo back to the fresh-install config when it is done). When the test is over,
/// whether it passed or not, Piccolo loads the default location again and the temporary directory is
/// removed, so that a run which is not started by `scripts/accept.sh` leaves Piccolo as it found it;
/// the script also reloads the default location itself, for a run that is interrupted.
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

        let fresh = try FreshInstallConfig()
        var failure: Error?
        do {
            try fresh.load()
            try await FreshInstallConfig.$current.withValue(fresh) {
                try await function()
            }
        } catch {
            failure = error
        }
        // Back to the default location, and the temporary file goes. A Piccolo that no longer answers
        // is the business of the next test (see above), not of this one.
        _ = try? PiccoloClient().reloadConfig()
        fresh.remove()
        if let failure { throw failure }
    }
}

extension Trait where Self == PiccoloRunningTrait {
    /// Piccolo is running when the test starts, on the config of a fresh install: it is launched if
    /// it is not.
    static var piccoloRunning: Self { Self() }
}
