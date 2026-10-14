import Foundation
import Testing

@testable import PiccoloCore

/// The sample file from the issue, with real UUIDs.
private let sampleJSON = #"""
    {
      "bindings": [
        {
          "action": { "frame": { "preset": "leftHalf" }, "type": "placeWindow" },
          "id": "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40",
          "shortcut": { "keyCode": 123, "modifiers": ["control", "option"] }
        },
        {
          "action": { "frame": { "custom": { "height": 1, "width": 0.5, "x": 0.25, "y": 0 } }, "type": "placeWindow" },
          "id": "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D"
        },
        { "action": { "direction": "next", "type": "moveToDisplay" }, "id": "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A" },
        { "action": { "columns": 2, "count": 4, "rows": 2, "type": "arrangeGrid" }, "id": "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F" },
        { "action": { "direction": "left", "type": "moveDivider" }, "id": "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D" }
      ],
      "animation": "fast",
      "destinationPreview": true,
      "gridFillOrder": "rows",
      "resizeStep": 0.05,
      "version": 1
    }
    """#

@Suite("Config model")
struct ConfigModelTests {
    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    // MARK: Round trips

    @Test("every preset survives a round trip", arguments: Preset.allCases)
    func presetRoundTrip(_ preset: Preset) throws {
        #expect(try roundTrip(preset) == preset)
        #expect(try roundTrip(FrameSpec.preset(preset)) == .preset(preset))
    }

    @Test(
        "every action case survives a round trip",
        arguments: [
            Action.placeWindow(.preset(.maximize)),
            Action.placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))),
            Action.moveToDisplay(.next),
            Action.moveToDisplay(.previous),
            Action.arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)),
            Action.moveDivider(.left),
            Action.moveDivider(.right),
            Action.moveDivider(.up),
            Action.moveDivider(.down),
        ])
    func actionRoundTrip(_ action: Action) throws {
        #expect(try roundTrip(action) == action)
    }

    @Test("a binding survives a round trip with and without a shortcut")
    func bindingRoundTrip() throws {
        let withShortcut = KeyBinding(
            id: Fixture.idA,
            action: .moveDivider(.left),
            shortcut: Shortcut(keyCode: 123, modifiers: [.control, .option]))
        let withoutShortcut = KeyBinding(id: Fixture.idB, action: .moveToDisplay(.next))
        #expect(try roundTrip(withShortcut) == withShortcut)
        #expect(try roundTrip(withoutShortcut) == withoutShortcut)
    }

    @Test("a config survives a round trip")
    func configRoundTrip() throws {
        let config = Config(resizeStep: 0.2, bindings: allKindsBindings)
        #expect(try roundTrip(config) == config)
    }

    @Test("the default config is version 1, step 0.05, no bindings")
    func defaultConfig() {
        #expect(Config.default == Config(version: 1, resizeStep: 0.05, bindings: []))
        #expect(Config.default.bindings.isEmpty)
    }

    @Test("the raw values are the vocabulary of the file format")
    func vocabulary() {
        #expect(
            Preset.allCases.map(\.rawValue) == [
                "leftHalf", "rightHalf", "topHalf", "bottomHalf",
                "topLeft", "topRight", "bottomLeft", "bottomRight",
                "leftThird", "centerThird", "rightThird",
                "leftTwoThirds", "rightTwoThirds",
                "maximize", "center",
            ])
        #expect(Modifier.allCases.map(\.rawValue) == ["command", "option", "control", "shift"])
        #expect(Direction.allCases.map(\.rawValue) == ["left", "right", "up", "down"])
        #expect(DisplayDirection.allCases.map(\.rawValue) == ["next", "previous"])
    }

    // MARK: Decoding the file format

    @Test("the sample file from the issue decodes to the expected config")
    func decodesSample() throws {
        let expected = Config(
            version: 1,
            resizeStep: 0.05,
            animation: .fast,
            gridFillOrder: .rows,
            destinationPreview: true,
            bindings: [
                KeyBinding(
                    id: Fixture.idA,
                    action: .placeWindow(.preset(.leftHalf)),
                    shortcut: Shortcut(keyCode: 123, modifiers: [.control, .option])),
                KeyBinding(
                    id: Fixture.idB,
                    action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1)))),
                KeyBinding(id: Fixture.idC, action: .moveToDisplay(.next)),
                KeyBinding(id: Fixture.idD, action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2))),
                KeyBinding(id: Fixture.idE, action: .moveDivider(.left)),
            ])
        #expect(try decode(Config.self, sampleJSON) == expected)
    }

    @Test("a binding with a null shortcut has no shortcut")
    func nullShortcut() throws {
        let json = #"{"action":{"direction":"next","type":"moveToDisplay"},"id":"5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40","shortcut":null}"#
        let binding = try decode(KeyBinding.self, json)
        #expect(binding.shortcut == nil)
    }

    @Test("an unknown action type is rejected")
    func unknownActionType() {
        #expect(throws: DecodingError.self) {
            _ = try decode(Action.self, #"{"type":"teleport"}"#)
        }
    }

    @Test("an unknown preset is rejected")
    func unknownPreset() {
        #expect(throws: DecodingError.self) {
            _ = try decode(FrameSpec.self, #"{"preset":"bigHalf"}"#)
        }
    }

    @Test(
        "a frame needs exactly one of preset or custom",
        arguments: [
            #"{}"#,
            #"{"preset":"leftHalf","custom":{"x":0,"y":0,"width":1,"height":1}}"#,
        ])
    func frameNeedsExactlyOneForm(json: String) {
        #expect(throws: DecodingError.self) {
            _ = try decode(FrameSpec.self, json)
        }
    }

    @Test("a grid action needs count, rows and columns")
    func gridNeedsAllFields() {
        #expect(throws: DecodingError.self) {
            _ = try decode(Action.self, #"{"type":"arrangeGrid","rows":2,"columns":2}"#)
        }
    }
}

@Suite("Config file format")
struct ConfigFileFormatTests {
    /// Saves one config holding `bindings` and returns the exact text written to disk.
    private func written(_ bindings: [KeyBinding]) throws -> String {
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try ConfigStore(url: url).save(Config(bindings: bindings))
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("a placeWindow binding with a preset writes sorted keys and sorted modifiers")
    func placeWindowPreset() throws {
        let binding = KeyBinding(
            id: Fixture.idA,
            action: .placeWindow(.preset(.leftHalf)),
            shortcut: Shortcut(keyCode: 123, modifiers: [.shift, .option, .command, .control]))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "frame" : {
                      "preset" : "leftHalf"
                    },
                    "type" : "placeWindow"
                  },
                  "id" : "5E0B7C1E-6C0A-4C55-9C5B-0B6C1D2E3F40",
                  "shortcut" : {
                    "keyCode" : 123,
                    "modifiers" : [
                      "command",
                      "control",
                      "option",
                      "shift"
                    ]
                  }
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }

    @Test("a placeWindow binding with a custom frame and no shortcut omits the shortcut key")
    func placeWindowCustom() throws {
        let binding = KeyBinding(
            id: Fixture.idB,
            action: .placeWindow(.custom(FractionalRect(x: 0.25, y: 0, width: 0.5, height: 1))))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "frame" : {
                      "custom" : {
                        "height" : 1,
                        "width" : 0.5,
                        "x" : 0.25,
                        "y" : 0
                      }
                    },
                    "type" : "placeWindow"
                  },
                  "id" : "7A1F3C2D-8B4E-4F6A-9C0D-1E2F3A4B5C6D"
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }

    @Test("a moveToDisplay binding writes its direction")
    func moveToDisplay() throws {
        let binding = KeyBinding(id: Fixture.idC, action: .moveToDisplay(.next))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "direction" : "next",
                    "type" : "moveToDisplay"
                  },
                  "id" : "0D9E8F7A-6B5C-4D3E-8F2A-1B0C9D8E7F6A"
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }

    @Test("an arrangeGrid binding writes count, rows and columns inside the action")
    func arrangeGrid() throws {
        let binding = KeyBinding(
            id: Fixture.idD,
            action: .arrangeGrid(GridSpec(count: 4, rows: 2, columns: 2)))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "columns" : 2,
                    "count" : 4,
                    "rows" : 2,
                    "type" : "arrangeGrid"
                  },
                  "id" : "2C4D6E8F-1A3B-4C5D-9E7F-0A1B2C3D4E5F"
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }

    @Test("an empty config writes its empty bindings array on one line")
    func emptyConfig() throws {
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        try withTemporaryDirectory { directory in
            let url = directory.appending(path: "config.json")
            try ConfigStore(url: url).save(.default)
            #expect(try String(contentsOf: url, encoding: .utf8) == expected)
        }
    }

    @Test("a shortcut without modifiers writes its empty modifiers array on one line")
    func emptyModifiers() throws {
        let binding = KeyBinding(
            id: Fixture.idE,
            action: .moveDivider(.left),
            shortcut: Shortcut(keyCode: 0, modifiers: []))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "direction" : "left",
                    "type" : "moveDivider"
                  },
                  "id" : "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D",
                  "shortcut" : {
                    "keyCode" : 0,
                    "modifiers" : []
                  }
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }

    @Test("a moveDivider binding with a shortcut writes both")
    func moveDivider() throws {
        let binding = KeyBinding(
            id: Fixture.idE,
            action: .moveDivider(.left),
            shortcut: Shortcut(keyCode: 0, modifiers: [.command, .shift]))
        let expected = """
            {
              "animation" : "fast",
              "bindings" : [
                {
                  "action" : {
                    "direction" : "left",
                    "type" : "moveDivider"
                  },
                  "id" : "9B8A7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D",
                  "shortcut" : {
                    "keyCode" : 0,
                    "modifiers" : [
                      "command",
                      "shift"
                    ]
                  }
                }
              ],
              "destinationPreview" : true,
              "gridFillOrder" : "rows",
              "resizeStep" : 0.05,
              "version" : 1
            }

            """
        #expect(try written([binding]) == expected)
    }
}
