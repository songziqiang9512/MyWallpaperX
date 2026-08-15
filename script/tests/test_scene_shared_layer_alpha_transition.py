#!/usr/bin/env python3

"""Strict shared-boolean layer-alpha compilation and scene-lifetime runtime."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxBody.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+Syntax.swift",
    SCENE / "Properties/SceneSharedLayerAlphaProgram.swift",
    SCENE / "Properties/SceneSharedLayerAlphaSyntax.swift",
    SCENE / "Properties/SceneSharedLayerAlphaCompiler.swift",
    SCENE / "Properties/SceneSharedLayerAlphaRuntime.swift",
]

HARNESS = r'''
import Foundation

enum SceneJSONValue: Equatable {
    case bool(Bool), number(Double), string(String), object([String: SceneJSONValue])
    var boolValue: Bool? { if case let .bool(value) = self { value } else { nil } }
    var stringValue: String? { if case let .string(value) = self { value } else { nil } }
}
enum SceneScriptBindingValueType { case boolean, number, string }
enum SceneScriptBindingPathComponent: Equatable { case key(String), index(Int) }
struct SceneScriptBindingOwner: Equatable {
    enum Kind: Equatable { case object }
    let kind: Kind
    let objectIndex: Int?, objectID: Int?
}
struct SceneScriptBindingIR {
    let source: String, owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?, valueType: SceneScriptBindingValueType
    let wrapperKeys: [String]?
    var targetKey: String { if case let .key(key) = targetPath.last { key } else { "" } }
}
struct SceneScriptSourceEvidenceIR {
    let source: String, owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent], wrapperKeys: [String]
}
struct SceneLayerDisplayScriptOwnership: Equatable {
    let visible: Bool, alpha: Bool
}
struct SceneScriptBindingDefinition {
    let host: String, source: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int, layerIndex: Int, visible: Bool?, alpha: Double?
        var displayScriptOwnership: SceneLayerDisplayScriptOwnership?
        let scriptBindings: [SceneScriptBindingDefinition]?
    }
    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let sourceWithProperty = ramp(
            condition: true, upper: "scriptProperties.limit", rise: 1, fall: 1,
            property: true
        )
        let exactWorkshopSource = """
        'use strict';

        export var scriptProperties = createScriptProperties()
          .addSlider({
            name: 'touming',
            label: 'New Slider',
            value: 50,
            min: 0,
            max: 100,
            integer: false
          })
          .finish();

        export function update(value) {
          if(shared.b == true){
            value += engine.frametime;
            if (value >= scriptProperties.touming) {
              value = scriptProperties.touming;
            }
          }else if(shared.b != true){
            value -= engine.frametime;
            if (value <= 0.0) {
              value = 0.0;
            }
          }
          return value;
        }
        """
        let bindings = [
            binding(index: 1, id: 101, value: 0, source: sourceWithProperty,
                    properties: ["limit": .object([
                        "user": .string("opacity"),
                        "value": .object(["user": .string("legacy"), "value": .number(50)])
                    ])]),
            binding(index: 2, id: 102, value: 0,
                    source: ramp(condition: true, upper: "1.0", rise: 2, fall: 6)),
            binding(index: 3, id: 103, value: 1,
                    source: ramp(condition: false, upper: "1.0", rise: 2, fall: 6)),
            binding(index: 5, id: 105, value: 0,
                    source: exactWorkshopSource,
                    properties: ["touming": .object([
                        "user": .string("newproperty22"),
                        "value": .object([
                            "user": .string("legacy"),
                            "value": .number(50)
                        ])
                    ])]),
        ]
        let descriptor = makeDescriptor(exactWorkshopSource: exactWorkshopSource)
        let evidences = [initializer()] + bindings.map(evidence)
        let program = SceneSharedLayerAlphaProgramCompiler.compile(
            descriptor: descriptor, scriptBindings: bindings,
            scriptSourceEvidence: evidences
        )!
        let projected = SceneSharedLayerAlphaProjection.apply(program: program, to: descriptor)
        var runtime = SceneSharedLayerAlphaRuntime(program: program)
        let inputs: [String: SceneUserPropertyValue] = [
            "opacity": .number(0.5),
            "newproperty22": .number(0.5),
        ]
        let first = runtime.values(effectivePropertyValues: inputs, frameTime: 0.25)
        let second = runtime.values(effectivePropertyValues: inputs, frameTime: 0.25)
        let badFrame = runtime.values(effectivePropertyValues: inputs, frameTime: -.infinity)
        let changedInputs: [String: SceneUserPropertyValue] = [
            "opacity": .number(0.3)
        ]
        let changed = runtime.values(
            effectivePropertyValues: changedInputs, frameTime: 0.1
        )

        let malformed = binding(
            index: 4, id: 104, value: 0,
            source: ramp(condition: true, upper: "1.0", rise: 2, fall: 6)
                .replacingOccurrences(of: "engine.frametime", with: "engine.runtime"),
            properties: [:]
        )
        let malformedProgram = SceneSharedLayerAlphaProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: bindings + [malformed],
            scriptSourceEvidence: evidences + [evidence(malformed)]
        )!
        let wrongIdentity = binding(
            index: 4, id: 999, value: 0,
            source: ramp(condition: true, upper: "1.0", rise: 2, fall: 6),
            properties: [:]
        )
        let wrongProgram = SceneSharedLayerAlphaProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: bindings + [wrongIdentity],
            scriptSourceEvidence: evidences + [evidence(wrongIdentity)]
        )!
        let duplicateInitializerProgram = SceneSharedLayerAlphaProgramCompiler.compile(
            descriptor: descriptor, scriptBindings: bindings,
            scriptSourceEvidence: evidences + [initializer(source: "'use strict'; shared={b:false};")]
        )!
        let unknownFlag = binding(
            index: 4, id: 104, value: 0,
            source: ramp(condition: true, upper: "1.0", rise: 2, fall: 6)
                .replacingOccurrences(of: "shared.b", with: "shared.unknown"),
            properties: [:]
        )
        let unknownProgram = SceneSharedLayerAlphaProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: bindings + [unknownFlag],
            scriptSourceEvidence: evidences + [evidence(unknownFlag)]
        )!
        let attacks = [
            sourceWithProperty + " shared.b=true;",
            sourceWithProperty.replacingOccurrences(of: "shared.b", with: "shared['b']"),
            sourceWithProperty.replacingOccurrences(of: "return value;", with: "eval('x'); return value;"),
            sourceWithProperty.replacingOccurrences(of: "value +=", with: "value *=")
        ]
        let result: [String: Any] = [
            "bindingCount": program.bindings.count,
            "flags": program.initialFlags,
            "layerIDs": program.layerIDs,
            "projectedOwnership": projected.layers[1...3].map {
                [$0.displayScriptOwnership!.visible, $0.displayScriptOwnership!.alpha]
            },
            "first": [scalar(first, 101), scalar(first, 102), scalar(first, 103)],
            "second": [scalar(second, 101), scalar(second, 102), scalar(second, 103)],
            "exactWorkshopValue": scalar(second, 105),
            "badFrame": scalar(badFrame, 101),
            "changedUpper": scalar(changed, 101),
            "malformedBindingCount": malformedProgram.bindings.count,
            "wrongIdentityBindingCount": wrongProgram.bindings.count,
            "duplicateInitializerBindingCount": duplicateInitializerProgram.bindings.count,
            "unknownFlagBindingCount": unknownProgram.bindings.count,
            "attackRejections": attacks.map { SceneSharedLayerAlphaSyntax.parse($0) == nil },
            "formatVariantAccepted": SceneSharedLayerAlphaSyntax.parse(
                sourceWithProperty.replacingOccurrences(of: "name: 'limit',\nlabel: 'Limit',", with: "label:'Limit', name:'limit',")
            ) != nil,
            "exactWorkshopAccepted": SceneSharedLayerAlphaSyntax.parse(exactWorkshopSource) != nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func makeDescriptor(exactWorkshopSource: String) -> SceneRenderDescriptor {
        .init(layers: [
            .init(id: 200, layerIndex: 0, visible: true, alpha: nil,
                  displayScriptOwnership: .init(visible: true, alpha: false),
                  scriptBindings: nil),
            .init(id: 101, layerIndex: 1, visible: nil, alpha: 0,
                  displayScriptOwnership: .init(visible: false, alpha: true),
                  scriptBindings: [resolvedBinding(
                    source: ramp(condition: true, upper: "scriptProperties.limit", rise: 1, fall: 1, property: true),
                    value: 0, properties: ["limit": .object(["user": .string("opacity"), "value": .number(0.5)])]
                  )]),
            .init(id: 102, layerIndex: 2, visible: nil, alpha: 0,
                  displayScriptOwnership: .init(visible: false, alpha: true),
                  scriptBindings: [resolvedBinding(
                    source: ramp(condition: true, upper: "1.0", rise: 2, fall: 6), value: 0
                  )]),
            .init(id: 103, layerIndex: 3, visible: nil, alpha: 1,
                  displayScriptOwnership: .init(visible: false, alpha: true),
                  scriptBindings: [resolvedBinding(
                    source: ramp(condition: false, upper: "1.0", rise: 2, fall: 6), value: 1
                  )]),
            .init(id: 104, layerIndex: 4, visible: nil, alpha: 0,
                  displayScriptOwnership: .init(visible: false, alpha: true),
                  scriptBindings: nil),
            .init(id: 105, layerIndex: 5, visible: nil, alpha: 0,
                  displayScriptOwnership: .init(visible: false, alpha: true),
                  scriptBindings: [resolvedBinding(
                    source: exactWorkshopSource, value: 0,
                    properties: ["touming": .object([
                        "user": .string("newproperty22"),
                        "value": .number(0.5)
                    ])]
                  )]),
        ])
    }

    static func resolvedBinding(
        source: String, value: Double,
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingDefinition {
        .init(host: "alpha", source: source, properties: properties,
              authoredValue: .number(value))
    }

    static func initializer(source: String = "'use strict'; shared={a:false,b:true,c:true};") -> SceneScriptSourceEvidenceIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: 0, objectID: 200),
              targetPath: [.key("objects"), .index(0), .key("visible")],
              wrapperKeys: ["script", "value"])
    }

    static func binding(
        index: Int, id: Int, value: Double, source: String,
        properties: [String: SceneJSONValue] = [:]
    ) -> SceneScriptBindingIR {
        .init(source: source, owner: .init(kind: .object, objectIndex: index, objectID: id),
              targetPath: [.key("objects"), .index(index), .key("alpha")],
              properties: properties, authoredValue: .number(value), valueType: .number,
              wrapperKeys: properties.isEmpty ? ["script", "value"] : ["script", "scriptproperties", "value"])
    }

    static func evidence(_ binding: SceneScriptBindingIR) -> SceneScriptSourceEvidenceIR {
        .init(source: binding.source, owner: binding.owner, targetPath: binding.targetPath,
              wrapperKeys: binding.wrapperKeys!)
    }

    static func ramp(
        condition: Bool, upper: String, rise: Double, fall: Double,
        property: Bool = false
    ) -> String {
        let builder = property ? """
        export var scriptProperties=createScriptProperties()
          .addSlider({
        name: 'limit',
        label: 'Limit',
        value: 50,
        min: 0,
        max: 100,
        integer: false
        }).finish();
        """ : ""
        return """
        'use strict';
        \(builder)
        export function update(value) {
          if (shared.b == \(condition)) {
            value += engine.frametime * \(rise);
            if (value >= \(upper)) { value = \(upper); }
          } else if (shared.b != \(condition)) {
            value -= engine.frametime * \(fall);
            if (value <= 0.0) { value = 0.0; }
          }
          return value;
        }
        """
    }

    static func scalar(
        _ values: [SceneDynamicTarget: SceneDynamicValue], _ layerID: Int
    ) -> Double {
        guard case let .scalar(value)? = values[.layer(layerID: layerID, field: .alpha)] else {
            return -999
        }
        return value
    }
}
'''


class SceneSharedLayerAlphaTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.tempdir = tempfile.TemporaryDirectory()
        directory = Path(cls.tempdir.name)
        harness = directory / "Harness.swift"
        executable = directory / "harness"
        harness.write_text(HARNESS, encoding="utf-8")
        result = subprocess.run(
            [swiftc, *map(str, SOURCES), str(harness), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        output = subprocess.run(
            [str(executable)], cwd=ROOT, check=True, capture_output=True, text=True,
        ).stdout
        cls.result = json.loads(output)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tempdir.cleanup()

    def test_complete_public_family_advances_once_per_frame(self) -> None:
        self.assertEqual(self.result["flags"], {"a": False, "b": True, "c": True})
        self.assertEqual(self.result["bindingCount"], 4)
        self.assertEqual(self.result["layerIDs"], [101, 102, 103, 105])
        self.assertEqual(self.result["first"], [0.25, 0.5, 0])
        self.assertEqual(self.result["second"], [0.5, 1, 0])
        self.assertEqual(self.result["badFrame"], 0.5)
        self.assertEqual(self.result["changedUpper"], 0.3)
        self.assertEqual(self.result["exactWorkshopValue"], 0.5)

    def test_only_admitted_alpha_ownership_is_released(self) -> None:
        self.assertEqual(
            self.result["projectedOwnership"],
            [[False, False], [False, False], [False, False]],
        )
        self.assertEqual(self.result["malformedBindingCount"], 4)
        self.assertEqual(self.result["wrongIdentityBindingCount"], 4)
        self.assertEqual(self.result["unknownFlagBindingCount"], 4)
        self.assertEqual(self.result["duplicateInitializerBindingCount"], 0)

    def test_parser_is_format_tolerant_but_semantically_closed(self) -> None:
        self.assertTrue(self.result["formatVariantAccepted"])
        self.assertTrue(self.result["exactWorkshopAccepted"])
        self.assertTrue(all(self.result["attackRejections"]))


if __name__ == "__main__":
    unittest.main()
