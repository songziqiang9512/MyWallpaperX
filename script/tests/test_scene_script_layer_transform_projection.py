#!/usr/bin/env python3

"""Executable admission checks for generic SceneScript layer transforms."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneScript"
    / "SceneScriptVectorCandidateCatalog.swift"
)

HARNESS = r'''
import Foundation

nonisolated enum SceneScriptScalarRuntimeFailure: Error, Sendable {
    case invalid
}

nonisolated enum SceneDynamicValueType: String, Sendable {
    case vector2, vector3
}

nonisolated enum SceneDynamicValue: Equatable, Sendable {
    case vector2(Double, Double)
    case vector3(Double, Double, Double)
}

nonisolated enum SceneDynamicLayerField: Hashable, Sendable {
    case origin, scale, angles
}

nonisolated enum SceneDynamicTarget: Hashable, Sendable {
    case layer(layerID: Int, field: SceneDynamicLayerField)
    case effectConstant(layerID: Int, effectIndex: Int, passIndex: Int, name: String)
}

nonisolated struct SceneDynamicTargetDefinition: Sendable {
    let target: SceneDynamicTarget
    let valueType: SceneDynamicValueType
    let authoredValue: SceneDynamicValue
}

nonisolated enum SceneJSONValue: Sendable {
    case number(Double)
    case string(String)

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

nonisolated enum SceneScriptBindingValueType: Sendable {
    case string
}

nonisolated enum SceneScriptBindingPathComponent: Equatable, Sendable {
    case key(String)
    case index(Int)
}

nonisolated struct SceneScriptBindingOwner: Sendable {
    enum Kind: Sendable { case object, pass }
    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
}

nonisolated struct SceneScriptBindingIR: Sendable {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: SceneScriptBindingValueType
    let wrapperKeys: [String]?

    var targetKey: String {
        guard case let .key(key)? = targetPath.last else { return "" }
        return key
    }
}

nonisolated struct SceneScriptPropertyInput: Sendable {}

nonisolated struct SceneRenderDescriptor: Sendable {
    enum SceneShaderUserValueKind: Sendable { case null }

    struct ShaderValue: Sendable {
        let scriptSource: String?
        let components: [Double]?
        let userValueKind: SceneShaderUserValueKind?
    }

    struct Pass: Sendable {
        let passIndex: Int
        let id: Int?
        let constantShaderValues: [String: ShaderValue]
    }

    struct Effect: Sendable {
        let effectID: Int?
        let passes: [Pass]
    }

    struct Layer: Sendable {
        let id: Int
        let layerIndex: Int
        let originXYZ: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let effects: [Effect]
    }

    let layers: [Layer]
}

nonisolated enum SceneScriptVectorProgram {
    static func passConstantPath(
        objectIndex: Int, effectIndex: Int, passIndex: Int, name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }

    static func vector2(_ value: String) -> SIMD2<Double>? {
        let values = value.split(separator: " ").compactMap { Double($0) }
        guard values.count == 2, values.allSatisfy(\.isFinite) else { return nil }
        return .init(values[0], values[1])
    }

    static func vector3(_ value: String) -> SIMD3<Double>? {
        let values = value.split(separator: " ").compactMap { Double($0) }
        guard values.count == 3, values.allSatisfy(\.isFinite) else { return nil }
        return .init(values[0], values[1], values[2])
    }

    static func validName(_ value: String) -> Bool {
        !value.isEmpty
    }

    static func propertyInput(_ value: SceneJSONValue) -> SceneScriptPropertyInput? {
        guard case let .number(number) = value, number.isFinite else { return nil }
        return .init()
    }
}

func binding(
    key: String,
    value: String,
    pathKey: String? = nil
) -> SceneScriptBindingIR {
    .init(
        source: "export function update(value) { return value; }",
        owner: .init(
            kind: .object,
            objectIndex: 0,
            objectID: 101,
            effectIndex: nil,
            effectID: nil,
            passIndex: nil,
            passID: nil
        ),
        targetPath: [
            .key("objects"), .index(0), .key(pathKey ?? key),
        ],
        properties: [:],
        authoredValue: .string(value),
        valueType: .string,
        wrapperKeys: ["script", "value"]
    )
}

@main
enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [.init(
            id: 101,
            layerIndex: 0,
            originXYZ: [1, 2, 3],
            scaleXYZ: [4, 5, 6],
            anglesXYZ: [7, 8, 9],
            effects: []
        )])
        let family = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "origin", value: "1 2 3"),
                binding(key: "scale", value: "4 5 6"),
                binding(key: "angles", value: "7 8 9"),
            ]
        )
        let duplicate = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "angles", value: "7 8 9"),
                binding(key: "angles", value: "7 8 9"),
            ]
        )
        let mismatched = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [binding(key: "angles", value: "7 8 10")]
        )
        let wrongPath = SceneScriptVectorProgram.project(
            descriptor: descriptor,
            scriptBindings: [
                binding(key: "angles", value: "7 8 9", pathKey: "origin"),
            ]
        )
        let expectedTargets: Set<SceneDynamicTarget> = [
            .layer(layerID: 101, field: .origin),
            .layer(layerID: 101, field: .scale),
            .layer(layerID: 101, field: .angles),
        ]
        let payload: [String: Any] = [
            "familyTargetsComplete": family.targets == expectedTargets,
            "angleDefinition": family.definitions.contains {
                $0.target == .layer(layerID: 101, field: .angles)
                    && $0.valueType == .vector3
                    && $0.authoredValue == .vector3(7, 8, 9)
            },
            "duplicateRejected": duplicate.uniqueCandidates.isEmpty
                && duplicate.duplicateTargets == [
                    .layer(layerID: 101, field: .angles),
                ],
            "mismatchRejected": mismatched.candidates.isEmpty,
            "wrongPathRejected": wrongPath.candidates.isEmpty,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneScriptLayerTransformProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-script-layer-transform-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "layer-transform-projection"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = json.loads(subprocess.run(
            [str(binary)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_full_authored_transform_family_is_projected(self) -> None:
        self.assertTrue(self.result["familyTargetsComplete"])
        self.assertTrue(self.result["angleDefinition"])

    def test_identity_and_duplicate_fail_closed(self) -> None:
        self.assertTrue(self.result["duplicateRejected"])
        self.assertTrue(self.result["mismatchRejected"])
        self.assertTrue(self.result["wrongPathRejected"])


if __name__ == "__main__":
    unittest.main()
