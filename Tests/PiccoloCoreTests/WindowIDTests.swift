import Foundation
import Testing

@testable import PiccoloCore

@Suite("Window ID")
struct WindowIDTests {
    @Test("a window ID keeps the window number it wraps")
    func wrapsWindowNumber() {
        #expect(WindowID(rawValue: 42).rawValue == 42)
    }

    @Test("window IDs with the same number are equal and hash alike")
    func equalityAndHashing() {
        #expect(WindowID(rawValue: 7) == WindowID(rawValue: 7))
        #expect(WindowID(rawValue: 7) != WindowID(rawValue: 8))
        #expect(Set([WindowID(rawValue: 7), WindowID(rawValue: 7)]).count == 1)
    }

    @Test("a window ID survives a round trip through Codable, including the largest window number")
    func codableRoundTrip() throws {
        for raw: UInt32 in [0, 1, 4_294_967_295] {
            let id = WindowID(rawValue: raw)
            let data = try JSONEncoder().encode(id)
            #expect(try JSONDecoder().decode(WindowID.self, from: data) == id)
        }
    }
}
