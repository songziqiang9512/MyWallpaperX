#!/usr/bin/env python3

"""Bounded slider-backed SceneScript layer-origin/scale producer."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    SCENE / "Properties/SceneLaunchOriginTransitionCompiler+SyntaxLexer.swift",
    SCENE / "Properties/ScenePropertyVectorScriptSyntax.swift",
    SCENE / "Properties/ScenePropertyVectorScriptProgram.swift",
    SCENE / "Properties/ScenePropertyVectorScriptCompiler.swift",
    SCENE / "Properties/ScenePropertyVectorScriptRuntime.swift",
]

HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let layerIndex: Int
        var visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let scaleHasScript: Bool?
    }
    var layers: [Layer]
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(
                id: 10, layerIndex: 0, visible: true,
                originXYZ: [20, 2250, 0], scaleXYZ: [1.5, 1.5, 1.5],
                scaleHasScript: true
            ),
            .init(
                id: 11, layerIndex: 1, visible: true,
                originXYZ: [100, 200, 3], scaleXYZ: [2, 2, 2],
                scaleHasScript: true
            ),
        ])
        let origin = binding(
            objectIndex: 0, objectID: 10, key: "origin", source: originSource,
            properties: [
                "x": .object(["user": .string("x1"), "value": .number(20)]),
                "y": .object(["user": .string("y1"), "value": .number(2250)]),
            ], value: "20.00000 2250.00000 0.00000"
        )
        let scale = binding(
            objectIndex: 0, objectID: 10, key: "scale", source: scaleSource,
            properties: [
                "newSlider": .object([
                    "user": .string("size"), "value": .number(1.5),
                ]),
            ], value: "1.50000 1.50000 1.50000"
        )
        let constantScale = binding(
            objectIndex: 1, objectID: 11, key: "scale", source: scaleSource,
            properties: ["newSlider": .number(2)],
            value: "2.00000 2.00000 2.00000"
        )
        let program = ScenePropertyVectorScriptProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: [origin, scale, constantScale]
        )
        let defaults = ScenePropertyVectorScriptRuntime.values(
            program: program, effectivePropertyValues: [:]
        )
        let overridden = ScenePropertyVectorScriptRuntime.values(
            program: program,
            effectivePropertyValues: [
                "x1": .number(40), "y1": .number(2100), "size": .number(1.25),
            ]
        )
        let malformedProgram = ScenePropertyVectorScriptProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: [binding(
                objectIndex: 0, objectID: 10, key: "scale",
                source: scaleSource.replacingOccurrences(
                    of: "return value;", with: "value.y = scriptProperties.newSlider; return value;"
                ),
                properties: ["newSlider": .number(1.5)],
                value: "1.50000 1.50000 1.50000"
            )]
        )
        let wrongIdentity = ScenePropertyVectorScriptProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: [binding(
                objectIndex: 0, objectID: 11, key: "scale", source: scaleSource,
                properties: ["newSlider": .number(1.5)],
                value: "1.50000 1.50000 1.50000"
            )]
        )
        let duplicate = ScenePropertyVectorScriptProgramCompiler.compile(
            descriptor: descriptor, scriptBindings: [origin, origin]
        )

        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "targets": program.definitions.map { String(describing: $0.target) },
            "admittedScale": Array(program.admittedScaleLayerIDs).sorted(),
            "defaultOrigin": vector(defaults, layer: 10, field: .origin),
            "defaultScale": vector(defaults, layer: 10, field: .scale),
            "constantScale": vector(defaults, layer: 11, field: .scale),
            "overrideOrigin": vector(overridden, layer: 10, field: .origin),
            "overrideScale": vector(overridden, layer: 10, field: .scale),
            "originSyntax": ScenePropertyVectorScriptSyntax.parse(originSource) != nil,
            "scaleSyntax": ScenePropertyVectorScriptSyntax.parse(scaleSource) != nil,
            "extraStatementRejected": malformedProgram.bindings.isEmpty,
            "wrongIdentityRejected": wrongIdentity.bindings.isEmpty,
            "duplicateTargetRejected": duplicate.bindings.isEmpty,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(
        objectIndex: Int, objectID: Int, key: String, source: String,
        properties: [String: SceneJSONValue], value: String
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: objectIndex, objectID: objectID,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(objectIndex), .key(key)],
            properties: properties, authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
    }

    static func vector(
        _ values: [SceneDynamicTarget: SceneDynamicValue], layer: Int,
        field: SceneDynamicLayerField
    ) -> [Double] {
        guard case let .vector3(x, y, z)? = values[
            .layer(layerID: layer, field: field)
        ] else { return [] }
        return [x, y, z]
    }

    static let originSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'x',label:'x',value:20,min:0,max:3800,integer:false})
      .addSlider({name:'y',label:'y',value:2250,min:0,max:3800,integer:false})
      .finish();
    export function update(value) {
      value.x = scriptProperties.x
      value.y = scriptProperties.y
      return value;
    }
    """

    static let scaleSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'newSlider',label:'New Slider',value:1.50,min:1,max:3,integer:false})
      .finish();
    export function update(value) {
      value = scriptProperties.newSlider
      return value;
    }
    """
}
'''


class ScenePropertyVectorScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp_dir = tempfile.TemporaryDirectory()
        temp = Path(cls.temp_dir.name)
        harness = temp / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temp / "property-vector-script"
        subprocess.run(
            [
                "xcrun", "swiftc", "-parse-as-library", "-O", "-o",
                str(cls.binary), *map(str, SOURCES), str(harness),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_exact_origin_and_scale_scripts_compile_and_follow_live_properties(self) -> None:
        value = self.result()
        self.assertEqual(value["bindings"], 3)
        self.assertEqual(value["admittedScale"], [10, 11])
        self.assertEqual(value["defaultOrigin"], [20, 2250, 0])
        self.assertEqual(value["defaultScale"], [1.5, 1.5, 1.5])
        self.assertEqual(value["constantScale"], [2, 2, 2])
        self.assertEqual(value["overrideOrigin"], [40, 2100, 0])
        self.assertEqual(value["overrideScale"], [1.25, 1.25, 1.25])
        self.assertTrue(value["originSyntax"])
        self.assertTrue(value["scaleSyntax"])

    def test_unproven_source_identity_and_duplicate_targets_fail_closed(self) -> None:
        value = self.result()
        self.assertTrue(value["extraStatementRejected"])
        self.assertTrue(value["wrongIdentityRejected"])
        self.assertTrue(value["duplicateTargetRejected"])


if __name__ == "__main__":
    unittest.main()
