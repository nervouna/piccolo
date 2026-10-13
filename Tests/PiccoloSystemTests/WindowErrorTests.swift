import ApplicationServices
import Testing

@testable import PiccoloSystem

@Suite("WindowError")
struct WindowErrorTests {
    @Test("a disabled Accessibility API maps to notTrusted")
    func apiDisabled() {
        #expect(WindowError(axError: .apiDisabled, operation: "read AXSize") == .notTrusted)
    }

    @Test("other Accessibility errors keep the operation and the raw code")
    func other() {
        let error = WindowError(axError: .cannotComplete, operation: "set AXPosition")
        #expect(error == .accessibility(operation: "set AXPosition", code: AXError.cannotComplete.rawValue))
    }

    @Test("every case has a distinct, non-empty description")
    func descriptions() {
        let errors: [WindowError] = [
            .notTrusted,
            .noFrontmostApplication,
            .noFocusedWindow,
            .windowGone,
            .ownWindow,
            .attributeNotSettable("AXSize"),
            .accessibility(operation: "read AXPosition", code: -25204),
        ]
        let descriptions = errors.compactMap(\.errorDescription)
        #expect(descriptions.count == errors.count)
        #expect(Set(descriptions).count == errors.count)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(WindowError.attributeNotSettable("AXSize").errorDescription?.contains("AXSize") == true)
    }
}
