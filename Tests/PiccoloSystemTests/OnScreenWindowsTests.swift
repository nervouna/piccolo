import CoreGraphics
import Testing

@testable import PiccoloSystem

@Suite("OnScreenWindows")
struct OnScreenWindowsTests {
    private func entry(
        number: Int, pid: Int, owner: String?, layer: Int, bounds: CGRect
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "kCGWindowNumber": number,
            "kCGWindowOwnerPID": pid,
            "kCGWindowLayer": layer,
            "kCGWindowBounds": bounds.dictionaryRepresentation,
        ]
        if let owner { entry["kCGWindowOwnerName"] = owner }
        return entry
    }

    @Test("keeps the order of the list, which is front to back")
    func keepsOrder() {
        let list = [
            entry(number: 30, pid: 1, owner: "A", layer: 0, bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            entry(number: 20, pid: 2, owner: "B", layer: 0, bounds: CGRect(x: 5, y: 5, width: 20, height: 20)),
            entry(number: 10, pid: 3, owner: "C", layer: 0, bounds: CGRect(x: 9, y: 9, width: 30, height: 30)),
        ]
        #expect(OnScreenWindows.parse(list).map(\.windowNumber) == [30, 20, 10])
    }

    @Test("drops windows that are not on layer 0")
    func filtersLayers() {
        let list = [
            entry(number: 1, pid: 1, owner: "Menubar", layer: 24, bounds: CGRect(x: 0, y: 0, width: 1440, height: 24)),
            entry(number: 2, pid: 2, owner: "App", layer: 0, bounds: CGRect(x: 0, y: 30, width: 400, height: 300)),
            entry(number: 3, pid: 3, owner: "Dock", layer: 20, bounds: CGRect(x: 0, y: 800, width: 1440, height: 100)),
        ]
        #expect(OnScreenWindows.parse(list).map(\.windowNumber) == [2])
    }

    @Test("reads number, pid, owner name and frame")
    func fields() {
        let bounds = CGRect(x: 200.5, y: -40, width: 900, height: 600.25)
        let windows = OnScreenWindows.parse([
            entry(number: 77, pid: 321, owner: "Finder", layer: 0, bounds: bounds)
        ])
        #expect(
            windows == [OnScreenWindow(windowNumber: 77, pid: 321, ownerName: "Finder", frame: bounds)])
    }

    @Test("a window without an owner name gets an empty one")
    func missingOwnerName() {
        let windows = OnScreenWindows.parse([
            entry(number: 5, pid: 9, owner: nil, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1, height: 1))
        ])
        #expect(windows.map(\.ownerName) == [""])
    }

    @Test("entries that miss required fields are skipped")
    func malformedEntries() {
        let good = entry(
            number: 1, pid: 1, owner: "A", layer: 0, bounds: CGRect(x: 0, y: 0, width: 5, height: 5))
        var noNumber = good
        noNumber["kCGWindowNumber"] = nil
        var noPID = good
        noPID["kCGWindowOwnerPID"] = nil
        var noBounds = good
        noBounds["kCGWindowBounds"] = nil
        var noLayer = good
        noLayer["kCGWindowLayer"] = nil
        #expect(OnScreenWindows.parse([noNumber, noPID, noBounds, noLayer, good]).map(\.windowNumber) == [1])
    }
}
