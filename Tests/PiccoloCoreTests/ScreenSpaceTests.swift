import CoreGraphics
import Testing

@testable import PiccoloCore

/// Fixtures use AppKit's global screen space (origin at the bottom-left of the
/// primary display, y up) on one side and the canonical space (origin at the
/// top-left of the primary display, y down) on the other.
@Suite("ScreenSpace")
struct ScreenSpaceTests {
    /// A 1440x900 primary display.
    static let primaryHeight: CGFloat = 900

    // MARK: AppKit to canonical

    @Test("primary display frame keeps its position and size")
    func primaryDisplayFrame() {
        let appKit = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test("a rect at the bottom-left of the primary display lands at the bottom in canonical space")
    func bottomLeftOfPrimary() {
        let appKit = CGRect(x: 0, y: 0, width: 100, height: 100)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: 0, y: 800, width: 100, height: 100))
    }

    @Test("a rect at the top-left of the primary display lands at y = 0")
    func topLeftOfPrimary() {
        let appKit = CGRect(x: 0, y: 800, width: 100, height: 100)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test("a display above the primary has negative canonical y")
    func displayAbovePrimary() {
        // 1920x1080 display directly above the primary.
        let appKit = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        #expect(canonical.maxY == 0)
    }

    @Test("a display to the left of the primary has negative x, bottom-aligned with the primary")
    func displayLeftOfPrimary() {
        // 1920x1080 display to the left, bottom edges aligned.
        let appKit = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: -1920, y: -180, width: 1920, height: 1080))
        #expect(canonical.maxY == Self.primaryHeight)
    }

    @Test("a display below the primary has canonical y beyond the primary's height")
    func displayBelowPrimary() {
        let appKit = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: 0, y: 900, width: 1920, height: 1080))
    }

    @Test("a rect spanning two displays converts as one rect")
    func rectSpanningDisplays() {
        // Straddles the border between the primary and the display to its left.
        let appKit = CGRect(x: -50, y: 100, width: 200, height: 300)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == CGRect(x: -50, y: 500, width: 200, height: 300))
    }

    // MARK: Canonical to AppKit

    @Test("canonical to AppKit mirrors the primary display frame")
    func canonicalPrimaryDisplayFrame() {
        let canonical = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let appKit = ScreenSpace.appKitRect(
            fromCanonical: canonical, primaryDisplayHeight: Self.primaryHeight)
        #expect(appKit == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test("canonical to AppKit for a display above the primary")
    func canonicalDisplayAbovePrimary() {
        let canonical = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let appKit = ScreenSpace.appKitRect(
            fromCanonical: canonical, primaryDisplayHeight: Self.primaryHeight)
        #expect(appKit == CGRect(x: 0, y: 900, width: 1920, height: 1080))
    }

    @Test("canonical to AppKit for a display to the left of the primary")
    func canonicalDisplayLeftOfPrimary() {
        let canonical = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
        let appKit = ScreenSpace.appKitRect(
            fromCanonical: canonical, primaryDisplayHeight: Self.primaryHeight)
        #expect(appKit == CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    }

    // MARK: Round trips

    @Test(
        "AppKit to canonical and back returns the original rect",
        arguments: [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 1920, height: 1080),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            CGRect(x: -1920, y: -1080, width: 1920, height: 1080),
            CGRect(x: 12.5, y: 33.25, width: 640.75, height: 480.5),
            CGRect(x: -50, y: 100, width: 200, height: 300),
        ])
    func roundTripFromAppKit(appKit: CGRect) {
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        let back = ScreenSpace.appKitRect(
            fromCanonical: canonical, primaryDisplayHeight: Self.primaryHeight)
        #expect(back == appKit)
    }

    @Test(
        "canonical to AppKit and back returns the original rect",
        arguments: [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            CGRect(x: -1920, y: -180, width: 1920, height: 1080),
            CGRect(x: 100.5, y: 200.25, width: 300.5, height: 400.75),
        ])
    func roundTripFromCanonical(canonical: CGRect) {
        let appKit = ScreenSpace.appKitRect(
            fromCanonical: canonical, primaryDisplayHeight: Self.primaryHeight)
        let back = ScreenSpace.canonicalRect(
            fromAppKit: appKit, primaryDisplayHeight: Self.primaryHeight)
        #expect(back == canonical)
    }

    @Test("size is preserved by both conversions")
    func sizeIsPreserved() {
        let rect = CGRect(x: -300, y: 450, width: 321, height: 123)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: rect, primaryDisplayHeight: Self.primaryHeight)
        let appKit = ScreenSpace.appKitRect(
            fromCanonical: rect, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical.size == rect.size)
        #expect(appKit.size == rect.size)
    }

    @Test("a rect with a negative size is normalized")
    func nonStandardizedInput() {
        let flipped = CGRect(x: 100, y: 200, width: -40, height: -60)
        let canonical = ScreenSpace.canonicalRect(
            fromAppKit: flipped, primaryDisplayHeight: Self.primaryHeight)
        #expect(canonical == ScreenSpace.canonicalRect(
            fromAppKit: flipped.standardized, primaryDisplayHeight: Self.primaryHeight))
        #expect(canonical.width == 40)
        #expect(canonical.height == 60)
    }
}
