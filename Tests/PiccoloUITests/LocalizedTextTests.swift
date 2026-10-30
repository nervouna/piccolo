import Foundation
import Testing

import PiccoloCore

@testable import PiccoloUI

/// The texts of the window in Simplified Chinese, read from the folder of that language in PiccoloUI's
/// resources (the running test process is in English), against the English ones.
@Suite("Localized texts")
struct LocalizedTextTests {
    private let english = AppLanguage.en.textBundle!
    private let chinese = AppLanguage.zhHans.textBundle!

    /// Whether `text` still holds a format specifier such as `%@` or `%1$lld`.
    private static func hasUnfilledArgument(_ text: String) -> Bool {
        !StringCatalog.specifiers(in: text).isEmpty
    }

    // MARK: Action summaries

    private static let allPresets = Preset.allCases

    @Test("every preset has a Simplified Chinese name that differs from the English one", arguments: allPresets)
    func presetNames(_ preset: Preset) {
        let en = ActionSummary.name(of: preset, bundle: english)
        let zh = ActionSummary.name(of: preset, bundle: chinese)

        #expect(!zh.isEmpty)
        #expect(zh != en, "\(preset) reads \"\(zh)\" in Simplified Chinese and \"\(en)\" in English")
        #expect(ActionSummary.text(for: .placeWindow(.preset(preset)), bundle: chinese) == zh)
    }

    @Test("the preset names in Simplified Chinese")
    func presetNamesExactly() {
        let expected: [Preset: String] = [
            .leftHalf: "左半屏", .rightHalf: "右半屏", .topHalf: "上半屏", .bottomHalf: "下半屏",
            .topLeft: "左上角", .topRight: "右上角", .bottomLeft: "左下角", .bottomRight: "右下角",
            .leftThird: "左侧三分之一", .centerThird: "中间三分之一", .rightThird: "右侧三分之一",
            .leftTwoThirds: "左侧三分之二", .rightTwoThirds: "右侧三分之二", .maximize: "最大化", .center: "居中",
        ]
        #expect(expected.count == Preset.allCases.count)
        for (preset, name) in expected {
            #expect(ActionSummary.name(of: preset, bundle: chinese) == name, "\(preset)")
        }
    }

    @Test("a custom frame lists its four percentages in Simplified Chinese")
    func customFrame() {
        let frame = FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)
        let action = Action.placeWindow(.custom(frame))

        #expect(ActionSummary.text(for: action, bundle: english) == "Custom (25%, 0%, 50% × 100%)")
        #expect(ActionSummary.text(for: action, bundle: chinese) == "自定义（25%，0%，50% × 100%）")
    }

    @Test("both display directions")
    func displays() {
        #expect(ActionSummary.text(for: .moveToDisplay(.next), bundle: chinese) == "下一个显示器")
        #expect(ActionSummary.text(for: .moveToDisplay(.previous), bundle: chinese) == "上一个显示器")
        #expect(ActionSummary.text(for: .moveToDisplay(.left), bundle: chinese) == "左侧显示器")
        #expect(ActionSummary.text(for: .moveToDisplay(.right), bundle: chinese) == "右侧显示器")
        #expect(ActionSummary.text(for: .moveToDisplay(.up), bundle: chinese) == "上方显示器")
        #expect(ActionSummary.text(for: .moveToDisplay(.down), bundle: chinese) == "下方显示器")
        for direction in DisplayDirection.allCases {
            let action = Action.moveToDisplay(direction)
            #expect(ActionSummary.text(for: action, bundle: chinese) != ActionSummary.text(for: action, bundle: english))
        }
    }

    @Test("a grid keeps its numbers in the order the Chinese sentence needs")
    func grids() {
        let grid = Action.arrangeGrid(GridSpec(count: 3, rows: 2, columns: 4))

        #expect(ActionSummary.text(for: grid, bundle: english) == "Arrange 3 in 2 × 4")
        #expect(ActionSummary.text(for: grid, bundle: chinese) == "将 3 个窗口排成 2 × 4")
    }

    @Test("every divider direction", arguments: [
        (Direction.left, "向左移动分隔线"), (.right, "向右移动分隔线"), (.up, "向上移动分隔线"),
        (.down, "向下移动分隔线"),
    ] as [(Direction, String)])
    func dividers(_ direction: Direction, _ text: String) {
        let action = Action.moveDivider(direction)

        #expect(ActionSummary.text(for: action, bundle: chinese) == text)
        #expect(ActionSummary.text(for: action, bundle: chinese) != ActionSummary.text(for: action, bundle: english))
    }

    @Test("the four directions have names")
    func directionNames() {
        #expect(Direction.allCases.map { ActionSummary.name(of: $0, bundle: chinese) } == ["左侧", "右侧", "上方", "下方"])
        #expect(Direction.allCases.map { ActionSummary.name(of: $0, bundle: english) } == ["Left", "Right", "Up", "Down"])
    }

    @Test("every kind of action has a name in Simplified Chinese")
    func kinds() {
        for kind in ActionKind.allCases {
            let zh = kind.title(bundle: chinese)
            #expect(!zh.isEmpty)
            #expect(zh != kind.title(bundle: english), "\(kind)")
        }
        #expect(ActionKind.allCases.map { $0.title(bundle: chinese) } == ["放置窗口", "移到显示器", "网格排列", "移动分隔线"])
    }

    @Test("the percentages are written the same in every language")
    func percentagesAreNotTranslated() {
        #expect(ActionSummary.percent(1.0 / 3.0) == "33.33%")
    }

    // MARK: Every language has the summaries

    @Test("every language answers for every action, with a text that is not empty", arguments: AppLanguage.languages)
    func everyLanguageAnswers(_ language: AppLanguage) throws {
        let bundle = try #require(language.textBundle)
        let actions: [Action] =
            Preset.allCases.map { .placeWindow(.preset($0)) }
            + [.placeWindow(.custom(FractionalRect(x: 0, y: 0, width: 1, height: 1)))]
            + DisplayDirection.allCases.map { .moveToDisplay($0) }
            + [.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))]
            + Direction.allCases.map { .moveDivider($0) }
        for action in actions {
            let text = ActionSummary.text(for: action, bundle: bundle)
            #expect(!text.isEmpty, "\(action) in \(language.rawValue)")
            #expect(!Self.hasUnfilledArgument(text), "\(action) in \(language.rawValue) reads \"\(text)\": an argument was not filled in")
        }
        for kind in ActionKind.allCases {
            #expect(!kind.title(bundle: bundle).isEmpty)
        }
    }

    // MARK: Shortcut text

    @Test("Space and the fallback name are translated, the symbols and function keys are not")
    func keyNames() {
        let none: (Int) -> String? = { _ in nil }

        #expect(ShortcutText.keyName(49, bundle: english, character: none) == "Space")
        #expect(ShortcutText.keyName(49, bundle: chinese, character: none) == "空格")
        #expect(ShortcutText.keyName(87, bundle: english, character: none) == "Keypad 5")
        #expect(ShortcutText.keyName(87, bundle: chinese, character: none) == "Keypad 5")
        #expect(ShortcutText.keyName(200, bundle: english, character: none) == "Key 200")
        #expect(ShortcutText.keyName(200, bundle: chinese, character: none) == "按键 200")
        #expect(ShortcutText.keyName(123, bundle: chinese, character: none) == "←")
        let hyper = Shortcut(keyCode: FunctionKey.f14, modifiers: [.control, .option, .shift, .command])
        #expect(ShortcutText.string(for: hyper, bundle: chinese, character: none) == "⌃⌥⇧⌘F14")
    }

    // MARK: Messages

    @Test(
        "every validation message has a Simplified Chinese text that differs from the English one",
        arguments: [
            ValidationError.notFinite(field: "x"),
            .notFinite(field: "width"),
            .notFinite(field: "resizeStep"),
            .outOfRange(field: "x", rule: ""),
            .outOfRange(field: "y", rule: ""),
            .outOfRange(field: "width", rule: ""),
            .outOfRange(field: "height", rule: ""),
            .outOfRange(field: "x + width", rule: ""),
            .outOfRange(field: "y + height", rule: ""),
            .outOfRange(field: "rows", rule: ""),
            .outOfRange(field: "columns", rule: ""),
            .outOfRange(field: "count", rule: "must be >= 1"),
            .outOfRange(field: "count", rule: "must be <= rows * columns"),
            .outOfRange(field: "resizeStep", rule: ""),
        ])
    func validationMessages(_ error: ValidationError) {
        let en = SettingsMessages.describe(error, bundle: english)
        let zh = SettingsMessages.describe(error, bundle: chinese)

        #expect(!zh.isEmpty)
        #expect(zh != en, "\(error) reads \"\(zh)\" in Simplified Chinese and \"\(en)\" in English")
        #expect(!Self.hasUnfilledArgument(zh), "\"\(zh)\" has an argument that was not filled in")
    }

    @Test("the percentages stay in the messages that name them")
    func messagesKeepTheirNumbers() {
        let step = SettingsMessages.describe(.outOfRange(field: "resizeStep", rule: ""), bundle: chinese)
        #expect(step.contains("0%") && step.contains("50%"), "\(step)")
        let cells = SettingsMessages.describe(.outOfRange(field: "count", rule: "must be <= rows * columns"), bundle: chinese)
        #expect(cells.contains("×"), "\(cells)")
    }

    @Test("the English messages are the ones the window has always shown")
    func englishMessages() {
        #expect(
            SettingsMessages.describe(.outOfRange(field: "count", rule: "must be <= rows * columns"), bundle: english)
                == "The number of windows cannot be more than rows × columns.")
        #expect(
            SettingsMessages.describe(.notFinite(field: "x"), bundle: english) == "Left must be a number.")
        #expect(
            SettingsMessages.describe(.outOfRange(field: "resizeStep", rule: ""), bundle: english)
                == "The resize step must be more than 0% and at most 50%.")
    }

    @Test("a field without a sentence of its own is named as the model names it")
    func unknownField() {
        #expect(SettingsMessages.describe(.outOfRange(field: "gap", rule: "must be >= 0"), bundle: chinese) == "gap must be >= 0.")
        #expect(SettingsMessages.describe(.notFinite(field: "gap"), bundle: english) == "Gap must be a number.")
    }

    @Test("the other messages put their arguments where the Chinese sentence needs them")
    func otherMessages() {
        #expect(SettingsMessages.bindingGone(bundle: chinese) == "该快捷键绑定已不存在。")
        #expect(
            SettingsMessages.notRegistrable("⇧A", bundle: chinese) == "⇧A 不能用作全局快捷键：需要包含 ⌃、⌥ 或 ⌘，或使用功能键。")
        #expect(SettingsMessages.alreadyUsed("⌃⌥F13", by: "左半屏", bundle: chinese) == "⌃⌥F13 已被“左半屏”使用。")
        #expect(
            SettingsMessages.alreadyUsed("⌃⌥F13", by: "Left Half", bundle: english) == "⌃⌥F13 is already used by Left Half.")
        #expect(SettingsMessages.notSaved("disk full", bundle: chinese) == "无法存储更改：disk full")
        #expect(SettingsMessages.restartFailed("no helper", bundle: chinese) == "Piccolo 无法重新启动：no helper")
        #expect(SettingsMessages.restartFailed("no helper", bundle: english) == "Piccolo could not restart: no helper")
    }

    @Test("the login item messages, turned on and off, with and without a reason")
    func loginItemMessages() {
        for enabling in [true, false] {
            for reason in ["", "Operation not permitted"] {
                let en = SettingsMessages.loginItemFailed(enabling: enabling, reason: reason, bundle: english)
                let zh = SettingsMessages.loginItemFailed(enabling: enabling, reason: reason, bundle: chinese)
                #expect(zh != en)
                #expect(reason.isEmpty || zh.contains(reason))
                #expect(reason.isEmpty || en.contains(reason))
                #expect(en.hasPrefix("Launch at login could not be turned \(enabling ? "on" : "off")"))
            }
        }
        #expect(
            SettingsMessages.loginItemFailed(enabling: true, reason: "", bundle: chinese) == "无法开启“登录时打开”。")
        #expect(
            SettingsMessages.loginItemFailed(enabling: false, reason: "x", bundle: chinese) == "无法关闭“登录时打开”：x")
    }

    // MARK: The running app

    @Test("the texts of the model follow the bundle of the running app: English in a test")
    func defaultIsTheRunningApp() {
        #expect(ActionSummary.text(for: .placeWindow(.preset(.leftHalf))) == "Left Half")
        #expect(ActionKind.arrangeGrid.title == "Arrange Grid")
    }
}
