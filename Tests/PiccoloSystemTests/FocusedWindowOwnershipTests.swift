import Foundation
import Testing

@testable import PiccoloSystem

@Suite("Focused window: Piccolo's own windows")
struct FocusedWindowOwnershipTests {
    private func app(pid: pid_t) -> FrontmostApplication {
        FrontmostApplication(pid: pid, bundleID: "io.damao.piccolo", name: "Piccolo")
    }

    @Test("when Piccolo itself is frontmost no window is offered")
    func ownApplication() {
        #expect(throws: WindowError.ownWindow) {
            try FocusedWindow.refuseOwnWindows(of: app(pid: 4242), ownPID: 4242)
        }
    }

    @Test("another application is let through")
    func otherApplication() throws {
        try FocusedWindow.refuseOwnWindows(of: app(pid: 4243), ownPID: 4242)
    }

    @Test("the error says that Piccolo does not move its own windows")
    func message() {
        #expect(WindowError.ownWindow.errorDescription?.contains("Piccolo") == true)
        #expect(WindowError.ownWindow.errorDescription != WindowError.noFocusedWindow.errorDescription)
    }
}
