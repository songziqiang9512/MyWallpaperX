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
    SOURCE_ROOT / "Format/ScenePointLightDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
]

SCENE_FIXTURE = {
    "version": 3,
    "camera": {
        "eye": "-2 0.5 10",
        "center": "-1.8 0.5 9",
        "up": "0 1 0",
    },
    "general": {"fov": 50, "nearz": 0.01, "farz": 10000},
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
        {
            "id": 60,
            "light": "lpoint",
            "color": {"script": "return value;", "value": "0.1 0.2 0.3"},
            "intensity": {"script": "return value;", "value": 2.5},
            "radius": 40,
        },
        {
            "id": 70,
            "light": "point",
            "color": "1 0.5 0.25",
            "intensity": 1.5,
            "radius": 20,
        },
        {
            "id": 80,
            "light": "pointless",
            "color": "1 1 1",
            "intensity": 1,
            "radius": 10,
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
        let invalidPoint = ScenePointLightDefinition.parse([
            "light": "lpoint", "color": "1 invalid 0 0",
            "intensity": true, "radius": Double.infinity,
        ])!
        precondition(invalidPoint.colorRGB == nil)
        precondition(invalidPoint.intensity == nil)
        precondition(invalidPoint.radius == nil)
        let invalidDirectional = SceneDirectionalLightDefinition.parse([
            "light": "ldirectional", "color": "1 nan 0",
            "intensity": false,
        ])!
        precondition(invalidDirectional.colorRGB == nil)
        precondition(invalidDirectional.intensity == nil)
        let invalidSpot = SceneSpotLightDefinition.parse([
            "light": "lspot", "color": "1 inf 0",
            "intensity": Double.nan, "radius": true,
            "innercone": Double.infinity, "outercone": false,
        ])!
        precondition(invalidSpot.colorRGB == nil)
        precondition(invalidSpot.intensity == nil)
        precondition(invalidSpot.radius == nil)
        precondition(invalidSpot.innerConeDegrees == nil)
        precondition(invalidSpot.outerConeDegrees == nil)

        let fog: [String: Any] = [
            "fogdistance": true, "fogdistancecolor": "0.1 0.2 0.3",
            "fogdistancestart": 10, "fogdistanceend": 100,
            "fogdistancestartdensity": 0.2, "fogdistanceenddensity": 0.8
        ]
        let parsedFog = SceneDocumentLoader.parseGeneral(fog).distanceFog
        precondition(parsedFog?.color == [0.1, 0.2, 0.3])
        precondition(parsedFog?.start == 10 && parsedFog?.end == 100)
        precondition(parsedFog?.startDensity == 0.2 && parsedFog?.endDensity == 0.8)
        for (key, value) in [
            ("fogdistance", false as Any), ("fogdistanceend", 10 as Any),
            ("fogdistancecolor", "nan 0 0" as Any),
            ("fogdistanceenddensity", 1.1 as Any)
        ] {
            var invalid = fog
            invalid[key] = value
            precondition(SceneDocumentLoader.parseGeneral(invalid).distanceFog == nil)
        }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sourceURL)
        let objects = document.objects.map { object in
            [
                "id": object.id,
                "model": object.staticModelPath ?? "-",
                "perspective": object.usesPerspective as Any? ?? NSNull(),
                "pointKind": object.pointLight?.kind as Any? ?? NSNull(),
                "pointColor": object.pointLight?.colorRGB as Any? ?? NSNull(),
                "pointIntensity": object.pointLight?.intensity as Any? ?? NSNull(),
                "pointRadius": object.pointLight?.radius as Any? ?? NSNull(),
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "objects": objects,
            "referenced": document.referencedResourcePaths,
            "fov": document.general.fovDegrees as Any? ?? NSNull(),
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

    def test_projection_override_preserves_authored_presence(self) -> None:
        objects = {entry["id"]: entry for entry in self.result["objects"]}
        self.assertTrue(objects[10]["perspective"])
        self.assertIsNone(objects[20]["perspective"])
        self.assertIsNone(objects[30]["perspective"])
        self.assertIsNone(objects[40]["perspective"])
        self.assertFalse(objects[50]["perspective"])

    def test_native_perspective_fov_is_retained(self) -> None:
        self.assertEqual(self.result["fov"], 50)

    def test_point_light_aliases_and_wrapped_fallbacks_are_retained(self) -> None:
        objects = {entry["id"]: entry for entry in self.result["objects"]}
        self.assertEqual(objects[60]["pointKind"], "lpoint")
        for actual, expected in zip(objects[60]["pointColor"], [0.1, 0.2, 0.3]):
            self.assertAlmostEqual(actual, expected)
        self.assertEqual(objects[60]["pointIntensity"], 2.5)
        self.assertEqual(objects[60]["pointRadius"], 40)
        self.assertEqual(objects[70]["pointKind"], "point")
        self.assertEqual(objects[70]["pointColor"], [1, 0.5, 0.25])
        self.assertEqual(objects[70]["pointIntensity"], 1.5)
        self.assertEqual(objects[70]["pointRadius"], 20)
        self.assertIsNone(objects[80]["pointKind"])


if __name__ == "__main__":
    unittest.main()
