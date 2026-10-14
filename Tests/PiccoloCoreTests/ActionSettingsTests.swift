import Foundation
import Testing

@testable import PiccoloCore

@Suite("Action settings")
struct ActionSettingsTests {
    @Test("the settings of a config are the fields an action reads")
    func fromConfig() {
        let config = Config(
            resizeStep: 0.2, animation: .slow, gridFillOrder: .columns, destinationPreview: false,
            bindings: allKindsBindings)
        let settings = ActionSettings(config)

        #expect(settings.resizeStep == 0.2)
        #expect(settings.animation == .slow)
        #expect(settings.gridFillOrder == .columns)
    }

    @Test("the default settings are those of the default config")
    func defaults() {
        #expect(ActionSettings.default == ActionSettings(Config.default))
        #expect(ActionSettings.default.resizeStep == Config.defaultResizeStep)
        #expect(ActionSettings.default.animation == .fast)
        #expect(ActionSettings.default.gridFillOrder == .rows)
    }

    @Test("the initialiser defaults to the default config's settings")
    func initialiserDefaults() {
        #expect(ActionSettings() == ActionSettings.default)
        #expect(ActionSettings(resizeStep: 0.1) == ActionSettings(resizeStep: 0.1, animation: .fast, gridFillOrder: .rows))
    }

    @Test("the window animations last 0, 0.15, 0.25 and 0.4 seconds, with the raw values of the file format")
    func animations() {
        #expect(WindowAnimation.allCases.map(\.duration) == [0, 0.15, 0.25, 0.4])
        #expect(WindowAnimation.allCases.map(\.rawValue) == ["off", "fast", "medium", "slow"])
    }

    @Test("the grid fill orders have the raw values of the file format")
    func fillOrders() {
        #expect(GridFillOrder.allCases.map(\.rawValue) == ["rows", "columns"])
    }
}
