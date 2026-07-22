#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/SceneDynamicSnapshot.swift"

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let values: [SceneDynamicValue] = [
            .bool(true),
            .scalar(1.5),
            .vector2(1, 2),
            .vector3(1, 2, 3),
            .vector4(1, 2, 3, 4),
            .string("scene"),
        ]
        let targets: [SceneDynamicTarget] = [
            .scene(.bloomEnabled),
            .camera(.parallaxAmount),
            .layer(layerID: 10, field: .alpha),
            .effectVisibility(layerID: 10, effectIndex: 2),
            .effectConstant(layerID: 10, effectIndex: 2, passIndex: 1, name: "strength"),
            .text(layerID: 11, field: .content),
            .particle(layerID: 12, field: .controlPoint(3)),
            .scriptInstanceProperty(layerID: 13, path: ["settings", "speed"]),
        ]
        let coderRoundTrip = try roundTrip(values) == values && roundTrip(targets) == targets

        let alpha = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
        let text = SceneDynamicTarget.text(layerID: 2, field: .content)
        let vector = SceneDynamicTarget.layer(layerID: 3, field: .size)
        let unknown = SceneDynamicTarget.layer(layerID: 99, field: .volume)
        let duplicate = SceneDynamicTarget.camera(.parallaxDelay)
        let authoredMismatch = SceneDynamicTarget.layer(layerID: 4, field: .color)
        let authoredNonFinite = SceneDynamicTarget.effectConstant(
            layerID: 5,
            effectIndex: 0,
            passIndex: 0,
            name: "amount"
        )
        let definitions: [SceneDynamicTargetDefinition] = [
            .init(target: alpha, valueType: .scalar, authoredValue: .scalar(0.1)),
            .init(target: text, valueType: .string, authoredValue: .string("authored")),
            .init(target: vector, valueType: .vector2, authoredValue: .vector2(1, 2)),
            .init(target: duplicate, valueType: .scalar, authoredValue: .scalar(1)),
            .init(target: duplicate, valueType: .scalar, authoredValue: .scalar(2)),
            .init(target: authoredMismatch, valueType: .vector3, authoredValue: .scalar(1)),
            .init(target: authoredNonFinite, valueType: .scalar, authoredValue: .scalar(.infinity)),
        ]
        let resolver = SceneDynamicSnapshotResolver()
        let first = resolver.resolve(
            frameIndex: 42,
            generation: 7,
            definitions: definitions,
            userValues: dictionary([
                (alpha, .scalar(0.2)),
                (text, .string("user")),
                (vector, .scalar(8)),
                (unknown, .scalar(1)),
                (duplicate, .scalar(3)),
                (authoredMismatch, .vector3(1, 2, 3)),
                (authoredNonFinite, .scalar(1)),
            ]),
            timelineValues: dictionary([
                (alpha, .scalar(0.3)),
                (vector, .vector2(3, 4)),
                (duplicate, .scalar(4)),
            ]),
            sceneScriptValues: dictionary([
                (alpha, .scalar(0.4)),
                (vector, .vector2(.nan, 9)),
                (duplicate, .scalar(5)),
            ])
        )
        let second = resolver.resolve(
            frameIndex: 42,
            generation: 7,
            definitions: definitions.reversed(),
            userValues: dictionary([
                (duplicate, .scalar(3)),
                (unknown, .scalar(1)),
                (vector, .scalar(8)),
                (text, .string("user")),
                (alpha, .scalar(0.2)),
                (authoredNonFinite, .scalar(1)),
                (authoredMismatch, .vector3(1, 2, 3)),
            ]),
            timelineValues: dictionary([
                (duplicate, .scalar(4)),
                (vector, .vector2(3, 4)),
                (alpha, .scalar(0.3)),
            ]),
            sceneScriptValues: dictionary([
                (duplicate, .scalar(5)),
                (vector, .vector2(.nan, 9)),
                (alpha, .scalar(0.4)),
            ])
        )
        let dottedPath = SceneDynamicTarget.scriptInstanceProperty(
            layerID: 20,
            path: ["a.b"]
        )
        let splitPath = SceneDynamicTarget.scriptInstanceProperty(
            layerID: 20,
            path: ["a", "b"]
        )
        let collisionForward = resolver.resolve(
            frameIndex: 0,
            generation: 0,
            definitions: [],
            userValues: dictionary([(dottedPath, .scalar(1)), (splitPath, .scalar(1))])
        )
        let collisionReverse = resolver.resolve(
            frameIndex: 0,
            generation: 0,
            definitions: [],
            userValues: dictionary([(splitPath, .scalar(1)), (dottedPath, .scalar(1))])
        )
        let empty = SceneDynamicSnapshot.empty(frameIndex: 9, generation: 4)
        let payload: [String: Any] = [
            "coderRoundTrip": coderRoundTrip,
            "valueTypes": values.map { $0.valueType.rawValue },
            "finite": values.map(\.isFinite),
            "frameIndex": first.snapshot.frameIndex,
            "generation": first.snapshot.generation,
            "count": first.snapshot.count,
            "alpha": resolved(first.snapshot[alpha]),
            "text": resolved(first.snapshot[text]),
            "vector": resolved(first.snapshot[vector]),
            "duplicateMissing": first.snapshot[duplicate] == nil,
            "mismatchMissing": first.snapshot[authoredMismatch] == nil,
            "nonFiniteMissing": first.snapshot[authoredNonFinite] == nil,
            "diagnostics": first.diagnostics.map { diagnostic($0) },
            "deterministic": first == second,
            "collisionDeterministic": collisionForward == collisionReverse,
            "collisionOrder": collisionForward.diagnostics.map { targetPath($0.target) },
            "empty": [empty.frameIndex, empty.generation, UInt64(empty.count)],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    static func dictionary(
        _ entries: [(SceneDynamicTarget, SceneDynamicValue)]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        Dictionary(uniqueKeysWithValues: entries)
    }

    static func resolved(_ value: SceneDynamicResolvedValue?) -> [String] {
        guard let value else { return [] }
        return [String(describing: value.value), value.source.rawValue]
    }

    static func diagnostic(_ value: SceneDynamicSnapshotDiagnostic) -> [String] {
        [value.source.rawValue, value.code.rawValue]
    }

    static func targetPath(_ target: SceneDynamicTarget) -> String {
        guard case let .scriptInstanceProperty(_, path) = target else { return "other" }
        return path.map { "[\($0)]" }.joined()
    }
}
'''


class SceneDynamicSnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-dynamic-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-dynamic-snapshot"
        compilation = subprocess.run(
            ["swiftc", str(SOURCE), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_values_and_targets_are_typed_and_codable(self) -> None:
        self.assertTrue(self.result["coderRoundTrip"])
        self.assertEqual(
            self.result["valueTypes"],
            ["bool", "scalar", "vector2", "vector3", "vector4", "string"],
        )
        self.assertEqual(self.result["finite"], [True] * 6)

    def test_resolution_uses_fixed_source_priority(self) -> None:
        self.assertEqual(self.result["frameIndex"], 42)
        self.assertEqual(self.result["generation"], 7)
        self.assertEqual(self.result["alpha"], ["scalar(0.4)", "sceneScript"])
        self.assertEqual(self.result["text"], ['string("user")', "userProperty"])

    def test_invalid_higher_priority_value_keeps_last_valid_value(self) -> None:
        self.assertEqual(self.result["vector"], ["vector2(3.0, 4.0)", "timeline"])

    def test_duplicate_and_invalid_definitions_fail_closed(self) -> None:
        self.assertTrue(self.result["duplicateMissing"])
        self.assertTrue(self.result["mismatchMissing"])
        self.assertTrue(self.result["nonFiniteMissing"])
        self.assertEqual(self.result["count"], 3)

    def test_diagnostics_are_complete_and_deterministic(self) -> None:
        self.assertTrue(self.result["deterministic"])
        self.assertEqual(
            self.result["diagnostics"],
            [
                ["authored", "duplicateDefinition"],
                ["authored", "authoredTypeMismatch"],
                ["authored", "nonFiniteValue"],
                ["userProperty", "valueTypeMismatch"],
                ["userProperty", "unknownTarget"],
                ["sceneScript", "nonFiniteValue"],
            ],
        )
        self.assertTrue(self.result["collisionDeterministic"])
        self.assertEqual(self.result["collisionOrder"], ["[a][b]", "[a.b]"])

    def test_empty_snapshot_preserves_frame_identity(self) -> None:
        self.assertEqual(self.result["empty"], [9, 4, 0])


if __name__ == "__main__":
    unittest.main()
