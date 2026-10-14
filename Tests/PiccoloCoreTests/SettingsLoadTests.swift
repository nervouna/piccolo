import Foundation
import Testing

@testable import PiccoloCore

/// The window animation, grid fill order and destination preview as the config file holds them.
@Suite("Config store: window settings")
struct SettingsLoadTests {
    private func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    @Test("a file without the three keys loads the defaults without issues")
    func missingKeys() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(#"{"bindings":[],"resizeStep":0.05,"version":1}"#, to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.animation == .fast)
            #expect(result.config.gridFillOrder == .rows)
            #expect(result.config.destinationPreview == true)
            #expect(result.issues.isEmpty)
            #expect(result.droppedEntries == false)
        }
    }

    @Test("every value of each setting survives a save and a load")
    func roundTrip() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(url: directory.appending(path: "config.json"))
            for animation in WindowAnimation.allCases {
                for order in GridFillOrder.allCases {
                    for preview in [true, false] {
                        let config = Config(
                            resizeStep: 0.2, animation: animation, gridFillOrder: order,
                            destinationPreview: preview, bindings: allKindsBindings)
                        try store.save(config)
                        let result = try store.load()
                        #expect(result.config == config, "saved \(animation), \(order), \(preview)")
                        #expect(result.issues.isEmpty)
                        #expect(result.droppedEntries == false)
                    }
                }
            }
        }
    }

    @Test("the file holds the three settings under their keys, with the vocabulary of the format")
    func fileVocabulary() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try ConfigStore(url: url).save(
                Config(animation: .slow, gridFillOrder: .columns, destinationPreview: false))
            let text = try String(contentsOf: url, encoding: .utf8)

            #expect(text.contains(#""animation" : "slow""#))
            #expect(text.contains(#""gridFillOrder" : "columns""#))
            #expect(text.contains(#""destinationPreview" : false"#))
            #expect(text.contains(#""version" : 1"#))
        }
    }

    @Test(
        "an unreadable setting falls back to its default, with one issue naming the key, and reports dropped entries",
        arguments: [
            ("animation", #""bounce""#),
            ("animation", "2"),
            ("animation", "null"),
            ("gridFillOrder", #""diagonal""#),
            ("gridFillOrder", "true"),
            ("gridFillOrder", "null"),
            ("destinationPreview", #""yes""#),
            ("destinationPreview", "1"),
            ("destinationPreview", "null"),
        ])
    func unreadableSetting(key: String, value: String) throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                """
                {
                  "bindings": [
                    { "action": { "frame": { "preset": "leftHalf" }, "type": "placeWindow" },
                      "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40" }
                  ],
                  "\(key)": \(value),
                  "version": 1
                }
                """,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.issues.count == 1, "the issues are \(result.issues)")
            #expect(result.issues.first?.contains(key) == true, "the issue is \(result.issues)")
            #expect(result.issues.first?.contains("default") == true, "the issue is \(result.issues)")
            #expect(result.droppedEntries)
            #expect(result.config.bindings.map(\.id) == [Fixture.idA])
            #expect(result.config.resizeStep == Config.defaultResizeStep)
            // The file holds no other setting, so all three are at their defaults.
            #expect(result.config.animation == Config.defaultAnimation)
            #expect(result.config.gridFillOrder == Config.defaultGridFillOrder)
            #expect(result.config.destinationPreview == Config.defaultDestinationPreview)
        }
    }

    @Test("the other settings of a file keep their values when one setting is unreadable")
    func otherSettingsKept() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try writeText(
                #"{"animation":"bounce","bindings":[],"destinationPreview":false,"gridFillOrder":"columns","version":1}"#,
                to: url)

            let result = try ConfigStore(url: url).load()

            #expect(result.config.animation == .fast)
            #expect(result.config.gridFillOrder == .columns)
            #expect(result.config.destinationPreview == false)
            #expect(result.issues.count == 1)
        }
    }
}
