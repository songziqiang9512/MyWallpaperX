#!/usr/bin/env python3

"""Generic QuickJS Vec3 owner and previous-current boundary."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
VM = SCENE / "Runtime/SceneScript"
QUICKJS = VM / "QuickJSNG"
SOURCES = [
    SCENE / "Format/SceneJSONValue.swift",
    SCENE / "Format/SceneScriptBindingDefinition.swift",
    SCENE / "Properties/SceneDynamicSnapshot.swift",
    SCENE / "Properties/SceneUserProperty.swift",
    VM / "SceneScriptScalarRuntime.swift",
    VM / "SceneScriptEffectHandleBridge.swift",
    VM / "SceneScriptVectorProgram.swift",
    VM / "SceneScriptVectorRuntime.swift",
]

HARNESS = r'''
import Foundation

struct SceneFrameTiming {
    let wallDate: Date
    let simulationFrameTime: TimeInterval
    let sceneTime: TimeInterval
}

struct SceneScriptMaterialFunctionMutation: Equatable, Sendable {
    let layerID: Int
    let effectIndex: Int
    let functionName: String
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        let name: String?
    }
    struct Layer {
        let id: Int
        let layerIndex: Int
        var visible: Bool?
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let scaleHasScript: Bool?
        let effects: [EffectDescriptor]
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
                scaleHasScript: true, effects: [.init(name: "history")]
            ),
        ])
        let domain = try SceneScriptQuickJSDomain()
        let program = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .object(["user": .string("x1"), "value": .number(20)]),
                    "y": .object(["user": .string("y1"), "value": .number(2250)]),
                ]),
                binding(key: "scale", source: scaleSource, value: "1.5 1.5 1.5", properties: [
                    "size": .object(["user": .string("size"), "value": .number(1.5)]),
                ]),
            ],
            userPropertyDefinitions: [],
            generation: 7
        )
        let frame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 1.0 / 60.0,
            sceneTime: 2
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let result = program.evaluate(
            inputs: [
                .layer(layerID: 10, field: .origin): .vector3(20, 2250, 0),
                .layer(layerID: 10, field: .scale): .vector3(1.5, 1.5, 1.5),
            ],
            effectivePropertyValues: [
                "x1": .number(40), "y1": .number(2100), "size": .number(1.25),
            ],
            frame: frame
        )
        let bad = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin",
                source: "export function update(value) { return {}; }",
                value: "20 2250 0",
                properties: [:]
            )],
            userPropertyDefinitions: [],
            generation: 8
        )
        let badResult = bad.evaluate(
            inputs: [.layer(layerID: 10, field: .origin): .vector3(20, 2250, 0)],
            effectivePropertyValues: [:],
            frame: frame
        )
        let duplicate = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .number(20), "y": .number(2250),
                ]),
                binding(key: "origin", source: originSource, value: "20 2250 0", properties: [
                    "x": .number(20), "y": .number(2250),
                ]),
            ],
            userPropertyDefinitions: [],
            generation: 9
        )
        let payload: [String: Any] = [
            "bindings": program.bindings.count,
            "origin": vector(result.values[.layer(layerID: 10, field: .origin)]),
            "scale": vector(result.values[.layer(layerID: 10, field: .scale)]),
            "failures": result.failures.count,
            "mutations": result.materialFunctionMutations.map {
                ["layerID": $0.layerID, "effectIndex": $0.effectIndex,
                 "name": $0.functionName] as [String: Any]
            },
            "badReturn": badResult.failures.values.first?.code ?? "",
            "badPublished": !badResult.values.isEmpty,
            "duplicateRejected": duplicate.bindings.isEmpty,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func vector(_ value: SceneDynamicValue?) -> [Double] {
        guard case let .vector3(x, y, z)? = value else { return [] }
        return [x, y, z]
    }

    static func binding(
        key: String,
        source: String,
        value: String,
        properties: [String: SceneJSONValue]
    ) -> SceneScriptBindingIR {
        .init(
            source: source,
            owner: .init(
                kind: .object, objectIndex: 0, objectID: 10,
                effectIndex: nil, effectID: nil, passIndex: nil, passID: nil
            ),
            targetPath: [.key("objects"), .index(0), .key(key)],
            properties: properties,
            authoredValue: .string(value),
            valueType: .string,
            wrapperKeys: ["script", "scriptproperties", "value"]
        )
    }

    static let originSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'x',label:'X',value:20,min:0,max:3800,integer:false})
      .addSlider({name:'y',label:'Y',value:2250,min:0,max:3800,integer:false})
      .finish();
    export function update(value) {
      thisLayer.getEffect('history').executeMaterialFunction('clearHistory');
      value.x = scriptProperties.x;
      value.y = scriptProperties.y - 0;
      return value;
    }
    """

    static let scaleSource = """
    'use strict';
    export var scriptProperties = createScriptProperties()
      .addSlider({name:'size',label:'Size',value:1.5,min:1,max:3,integer:false})
      .finish();
    export function update(value) { return scriptProperties.size; }
    """
}
'''


class ScenePropertyVectorScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        clang = shutil.which("clang")
        if clang is None:
            raise unittest.SkipTest("clang is required")
        cls.temp_dir = tempfile.TemporaryDirectory(prefix="mwx-scene-vec3-")
        temp = Path(cls.temp_dir.name)
        objects: list[Path] = []
        for source in [
            VM / "SceneQuickJS.c", QUICKJS / "quickjs.c", QUICKJS / "dtoa.c",
            QUICKJS / "libregexp.c", QUICKJS / "libunicode.c",
        ]:
            output = temp / f"{source.stem}.o"
            subprocess.run([
                clang, "-std=c11", "-O0", "-c", str(source), "-o", str(output),
                "-I", str(VM), "-I", str(QUICKJS),
            ], check=True, capture_output=True, text=True)
            objects.append(output)
        harness = temp / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = temp / "property-vector-script"
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-O",
            "-import-objc-header", str(VM / "SceneQuickJS.h"),
            "-Xcc", f"-I{VM}",
            "-o", str(cls.binary), *map(str, SOURCES), str(harness),
            *map(str, objects), "-Xlinker", "-lm",
        ], check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp_dir.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [str(self.binary)], check=True, capture_output=True, text=True
        )
        return json.loads(completed.stdout)

    def test_generic_vec3_executes_script_properties_and_scalar_splat(self) -> None:
        value = self.result()
        self.assertEqual(value["bindings"], 2)
        self.assertEqual(value["origin"], [40, 2100, 0])
        self.assertEqual(value["scale"], [1.25, 1.25, 1.25])
        self.assertEqual(value["failures"], 0)
        self.assertEqual(value["mutations"], [
            {"layerID": 10, "effectIndex": 0, "name": "clearHistory"},
        ])

    def test_bad_return_is_local_and_duplicate_target_is_rejected(self) -> None:
        value = self.result()
        self.assertEqual(value["badReturn"], "bad-return")
        self.assertFalse(value["badPublished"])
        self.assertTrue(value["duplicateRejected"])


if __name__ == "__main__":
    unittest.main()
