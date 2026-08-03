#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
CONTEXT_SOURCE = SCENE_ROOT / "Format/SceneCompatibilityContext.swift"
PROJECT_SOURCE = SCENE_ROOT / "Format/SceneProject.swift"
DOCUMENT_SOURCE = SCENE_ROOT / "Format/SceneDocument.swift"
RUNTIME_MODEL_SOURCE = SCENE_ROOT / "Runtime/SceneRuntimeModel.swift"


HARNESS = r'''
import Foundation

@main
enum Harness {
    static func describe(_ value: SceneDeclaredInteger) -> String {
        switch value {
        case .missing: return "missing"
        case .value(let integer): return "value:\(integer)"
        case .invalidType(let type): return "invalid-type:\(type)"
        case .outOfRange(let raw): return "out-of-range:\(raw)"
        }
    }

    static func main() throws {
        let projectRoot: [String: Any] = ["version": 50]
        let sceneRoot: [String: Any] = ["version": 4]
        let project = SceneDeclaredInteger.parse(
            root: projectRoot,
            fieldName: "version"
        )
        let scene = SceneDeclaredInteger.parse(
            root: sceneRoot,
            fieldName: "version"
        )
        let context = SceneCompatibilityContext(
            projectVersion: .init(
                value: project,
                sourceKind: .projectJSON,
                sourceRelativePath: "project.json",
                fieldName: "version"
            ),
            sceneVersion: .init(
                value: scene,
                sourceKind: .sceneEntry,
                sourceRelativePath: "nested/scene.json",
                fieldName: "version"
            )
        )
        let encoded = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(
            SceneCompatibilityContext.self,
            from: encoded
        )
        let cases: [String: SceneDeclaredInteger] = [
            "missing": .parse(root: [:], fieldName: "version"),
            "zero": .parse(root: ["version": 0], fieldName: "version"),
            "boolean": .parse(root: ["version": true], fieldName: "version"),
            "string": .parse(root: ["version": "5"], fieldName: "version"),
            "fraction": .parse(root: ["version": 1.5], fieldName: "version"),
            "overflow": .parse(
                root: ["version": NSDecimalNumber(string: "9223372036854775808")],
                fieldName: "version"
            ),
        ]
        let output: [String: Any] = [
            "cases": cases.mapValues(describe),
            "project": describe(context.projectVersion.value),
            "scene": describe(context.sceneVersion.value),
            "projectSource": context.projectVersion.sourceKind.rawValue,
            "sceneSource": context.sceneVersion.sourceRelativePath,
            "roundTrip": decoded == context,
            "schema": context.schemaVersion,
        ]
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: output,
            options: [.sortedKeys]
        ), as: UTF8.self))
    }
}
'''


class SceneCompatibilityContextTests(unittest.TestCase):
    def test_declared_versions_preserve_presence_type_range_and_provenance(self) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-scene-compatibility-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "compatibility-context"
            compilation = subprocess.run(
                [swiftc, str(CONTEXT_SOURCE), str(harness), "-o", str(binary)],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertEqual(result["cases"], {
            "missing": "missing",
            "zero": "value:0",
            "boolean": "invalid-type:boolean",
            "string": "invalid-type:string",
            "fraction": "invalid-type:non-integer-number",
            "overflow": "out-of-range:9223372036854775808",
        })
        self.assertEqual(result["project"], "value:50")
        self.assertEqual(result["scene"], "value:4")
        self.assertEqual(result["projectSource"], "project-json")
        self.assertEqual(result["sceneSource"], "nested/scene.json")
        self.assertEqual(result["schema"], 1)
        self.assertTrue(result["roundTrip"])

    def test_project_document_and_runtime_keep_the_two_axes_separate(self) -> None:
        project = PROJECT_SOURCE.read_text(encoding="utf-8")
        document = DOCUMENT_SOURCE.read_text(encoding="utf-8")
        runtime = RUNTIME_MODEL_SOURCE.read_text(encoding="utf-8")
        self.assertIn("let declaredVersion: SceneDeclaredInteger", project)
        self.assertIn("SceneDeclaredInteger.parse(", project)
        self.assertIn("let declaredVersion: SceneDeclaredInteger", document)
        self.assertIn("SceneDeclaredInteger.parse(", document)
        self.assertIn("var compatibilityContext: SceneCompatibilityContext", runtime)
        self.assertIn("projectVersion: .init(", runtime)
        self.assertIn("sceneVersion: .init(", runtime)
        self.assertNotIn("effectiveVersion", runtime)


if __name__ == "__main__":
    unittest.main()
