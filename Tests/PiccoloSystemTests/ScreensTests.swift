import CoreGraphics
import Testing

@testable import PiccoloSystem

@Suite("Screens")
struct ScreensTests {
    @Test("the first screen is primary and keeps its frame")
    func primaryOnly() {
        let screens = Screens.make(from: [
            (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
        ])
        #expect(
            screens == [
                ScreenInfo(
                    index: 0, isPrimary: true,
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    // AppKit's visible frame excludes the menu bar at the top, which is
                    // y = 0 in canonical space.
                    visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
            ])
    }

    @Test("a display above the primary has negative canonical y, a display to the left negative x")
    func secondaryDisplays() {
        let screens = Screens.make(from: [
            (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)),
            (frame: CGRect(x: 0, y: 900, width: 1920, height: 1080),
             visibleFrame: CGRect(x: 0, y: 900, width: 1920, height: 1080)),
            (frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
             visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)),
        ])
        #expect(screens.map(\.index) == [0, 1, 2])
        #expect(screens.map(\.isPrimary) == [true, false, false])
        #expect(screens[1].frame == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(screens[1].visibleFrame == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(screens[2].frame == CGRect(x: -1920, y: -180, width: 1920, height: 1080))
        #expect(screens[2].visibleFrame == CGRect(x: -1920, y: -180 + 25, width: 1920, height: 1055))
    }

    @Test("no screens yields an empty list")
    func empty() {
        #expect(Screens.make(from: []).isEmpty)
    }
}
