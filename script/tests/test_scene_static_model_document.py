#!/usr/bin/env python3
"""Direct static-model object identity entering SceneDocument."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Particles/SceneParticleRemapValue.swift",
    SOURCE_ROOT / "Particles/SceneParticleReduceMovement.swift",
    SOURCE_ROOT / "Particles/SceneParticleCollisionPlane.swift",
    SOURCE_ROOT / "Particles/SceneParticlePositionAroundControlPoint.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleInitializer.swift",
    SOURCE_ROOT / "Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
]

SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Direct model",
            "model": r"models\Earth\Earth.mdl",
            "perspective": True,
        },
        {
            "id": 20,
            "name": "Duplicate model reference",
            "model": "models/Earth/Earth.mdl",
        },
        {
            "id": 30,
            "name": "Ordinary image",
            "image": "models/user/card.json",
            "perspective": "true",
        },
        {
            "id": 40,
            "name": "Malformed model field",
            "model": 42,
        },
        {
            "id": 50,
            "name": "Empty model field",
            "model": "",
            "perspective": False,
        },
    ],
}

HARNESS = r'''
import Foundation

struct SceneTextDescriptor: Codable {
    let padding: Float
    init(padding: Float = 0) { self.padding = padding }
    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

enum SceneUserPropertyValue {}
enum SceneUserPropertyKind { case sceneTexture }

struct SceneUserPropertyDefinition {
    let key: String
    let kind: SceneUserPropertyKind
}

struct SceneUserPropertyCatalog {
    let definitions: [SceneUserPropertyDefinition]
    static let empty = SceneUserPropertyCatalog(definitions: [])
}

struct SceneUserPropertyResolution {
    let root: [String: Any]
}

struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        SceneUserPropertyResolution(root: root)
    }
}

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog
    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}

@main
enum Harness {
    static func main() throws {
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sourceURL)
        let objects = document.objects.map { object in
            [
                "id": object.id,
                "model": object.staticModelPath ?? "-",
                "perspective": object.usesPerspective,
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "objects": objects,
            "referenced": document.referencedResourcePaths,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneStaticModelDocumentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory(prefix="mwx-static-model-document-")
        root = Path(cls._tmp.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        scene = root / "scene.json"
        scene.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        binary = root / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        completed = subprocess.run(
            [str(binary), str(scene)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_object_model_path_is_retained_and_normalized(self) -> None:
        objects = {entry["id"]: entry for entry in self.result["objects"]}
        self.assertEqual(objects[10]["model"], "models/Earth/Earth.mdl")
        self.assertEqual(objects[20]["model"], "models/Earth/Earth.mdl")
        self.assertEqual(objects[30]["model"], "-")
        self.assertEqual(objects[40]["model"], "-")
        self.assertEqual(objects[50]["model"], "-")

    def test_model_path_joins_the_deduplicated_resource_index(self) -> None:
        self.assertEqual(
            self.result["referenced"],
            ["models/Earth/Earth.mdl", "models/user/card.json"],
        )

    def test_perspective_requires_an_authored_boolean_true(self) -> None:
        objects = {entry["id"]: entry for entry in self.result["objects"]}
        self.assertTrue(objects[10]["perspective"])
        self.assertFalse(objects[20]["perspective"])
        self.assertFalse(objects[30]["perspective"])
        self.assertFalse(objects[40]["perspective"])
        self.assertFalse(objects[50]["perspective"])


if __name__ == "__main__":
    unittest.main()
