#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
GENERAL_SOURCE = SCENE_ROOT / "Format/SceneDocument+General.swift"
NUMERIC_SOURCE = SCENE_ROOT / "Format/SceneDocument+NumericParsing.swift"
SHAKE_SOURCE = SCENE_ROOT / "Rendering/SceneCameraShake.swift"

HARNESS_SOURCE = r'''
import Foundation

struct SceneDocument {}

struct SceneDocumentLoader {
    nonisolated static func visibleValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let keyed = value as? [String: Any] { return keyed["value"] as? Bool }
        return nil
    }
}

struct SceneRenderDescriptor {
    struct CameraDescriptor {
        struct ShakeDescriptor {
            let enabled: Bool?
            let amplitude: Float?
            let roughness: Float?
            let speed: Float?
        }
        let orthoWidth: Float?
        let orthoHeight: Float?
        let shake: ShakeDescriptor
    }
}

@main
enum Harness {
    static func main() throws {
        let missingGeneral = SceneDocumentLoader.parseGeneral(nil)
        let missing = missingGeneral.cameraShake
        let literalGeneral = SceneDocumentLoader.parseGeneral([
            "orthogonalprojection": ["width": 2_560, "height": 1_440],
            "camerashake": true,
            "camerashakeamplitude": 0.23,
            "camerashakeroughness": 1.0,
            "camerashakespeed": 1.25,
        ])
        let literal = literalGeneral.cameraShake
        let wrappedGeneral = SceneDocumentLoader.parseGeneral([
            "orthogonalprojection": ["width": 1_000, "height": 500],
            "camerashake": ["user": "shake_enabled", "value": true],
            "camerashakeamplitude": ["value": 0.4],
            "camerashakeroughness": ["value": 0.0],
            "camerashakespeed": ["value": 2.0],
        ])
        let wrapped = wrappedGeneral.cameraShake
        let malformedGeneral = SceneDocumentLoader.parseGeneral([
            "orthogonalprojection": ["width": 1_000, "height": 500],
            "camerashake": "true",
            "camerashakeamplitude": Double.nan,
            "camerashakeroughness": "rough",
            "camerashakespeed": ["value": Double.infinity],
        ])
        let malformed = malformedGeneral.cameraShake

        let defaultConfiguration = descriptor(true, 0.5, 1, 1)
        let speedOne = descriptor(true, 0.5, 1, 1)
        let speedTwo = descriptor(true, 0.5, 1, 2)
        let roughnessZero = descriptor(true, 1, 0, 1)
        let roughnessOne = descriptor(true, 1, 1, 1)
        let roughnessTwo = descriptor(true, 1, 2, 1)
        let disabled = descriptor(false, 0.5, 1, 1)
        let amplitudeZero = descriptor(true, 0, 1, 1)
        let speedZero = descriptor(true, 0.5, 1, 0)
        let invalidRange = descriptor(true, 1.01, 1, 1)
        let invalidMissing = SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor(
            enabled: true, amplitude: nil, roughness: 1, speed: 1
        )

        let timeA = offset(defaultConfiguration, time: 0.75, height: 1_000)
        let timeB = offset(defaultConfiguration, time: 1.25, height: 1_000)
        let result: [String: Any] = [
            "missing": fields(missing),
            "literal": fields(literal),
            "wrapped": fields(wrapped),
            "malformed": fields(malformed),
            "missingAdmission": SceneCameraShake.admission(
                runtimeCamera(missingGeneral)
            ).reportValue,
            "literalAdmission": SceneCameraShake.admission(
                runtimeCamera(literalGeneral)
            ).reportValue,
            "wrappedAdmission": SceneCameraShake.admission(
                runtimeCamera(wrappedGeneral)
            ).reportValue,
            "malformedAdmission": SceneCameraShake.admission(
                runtimeCamera(malformedGeneral)
            ).reportValue,
            "rangeAdmission": admission(invalidRange),
            "missingScalarAdmission": admission(invalidMissing),
            "missingProjectionAdmission": SceneCameraShake.admission(
                camera(defaultConfiguration, width: nil, height: nil)
            ).reportValue,
            "disabledMissingProjectionAdmission": SceneCameraShake.admission(
                camera(disabled, width: nil, height: nil)
            ).reportValue,
            "disabledOffset": offset(disabled, time: 1, height: 1_000),
            "amplitudeZeroOffset": offset(amplitudeZero, time: 1, height: 1_000),
            "speedZeroA": offset(speedZero, time: 0, height: 1_000),
            "speedZeroB": offset(speedZero, time: 99, height: 1_000),
            "timeA": timeA,
            "timeB": timeB,
            "timeARepeat": offset(defaultConfiguration, time: 0.75, height: 1_000),
            "speedSquaredOne": offset(speedOne, time: 1, height: 100),
            "speedSquaredTwo": offset(speedTwo, time: 0.25, height: 100),
            "roughnessZero": offset(roughnessZero, time: 1, height: 100),
            "roughnessOne": offset(roughnessOne, time: 1, height: 100),
            "roughnessTwo": offset(roughnessTwo, time: 1, height: 100),
            "invalidHeight": offset(defaultConfiguration, time: 1, height: 0),
            "invalidTime": offset(defaultConfiguration, time: .infinity, height: 1_000),
            "report": SceneCameraShake.reportLine(runtimeCamera(literalGeneral)),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func descriptor(
        _ enabled: Bool?, _ amplitude: Float?, _ roughness: Float?, _ speed: Float?
    ) -> SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor {
        .init(enabled: enabled, amplitude: amplitude, roughness: roughness, speed: speed)
    }

    static func runtime(
        _ descriptor: SceneDocument.GeneralDescriptor.CameraShakeDescriptor
    ) -> SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor {
        .init(
            enabled: descriptor.enabled,
            amplitude: descriptor.amplitude,
            roughness: descriptor.roughness,
            speed: descriptor.speed
        )
    }

    static func runtimeCamera(
        _ descriptor: SceneDocument.GeneralDescriptor
    ) -> SceneRenderDescriptor.CameraDescriptor {
        .init(
            orthoWidth: descriptor.orthoWidth,
            orthoHeight: descriptor.orthoHeight,
            shake: runtime(descriptor.cameraShake)
        )
    }

    static func admission(
        _ descriptor: SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor
    ) -> String {
        SceneCameraShake.admission(camera(descriptor)).reportValue
    }

    static func camera(
        _ descriptor: SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor,
        width: Float? = 100,
        height: Float? = 100
    ) -> SceneRenderDescriptor.CameraDescriptor {
        .init(orthoWidth: width, orthoHeight: height, shake: descriptor)
    }

    static func offset(
        _ descriptor: SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor,
        time: TimeInterval,
        height: Float
    ) -> [Float] {
        let camera = camera(descriptor, width: 100, height: height)
        let value = SceneCameraShake.orthographicOffset(
            admission: SceneCameraShake.admission(camera),
            sceneTime: time
        )
        return [value.x, value.y]
    }

    static func fields(
        _ descriptor: SceneDocument.GeneralDescriptor.CameraShakeDescriptor
    ) -> [Any] {
        [
            descriptor.enabled as Any? ?? NSNull(),
            descriptor.amplitude as Any? ?? NSNull(),
            descriptor.roughness as Any? ?? NSNull(),
            descriptor.speed as Any? ?? NSNull(),
        ]
    }
}
'''


class SceneCameraShakeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-camera-shake-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-camera-shake"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-modules")
        environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-modules")
        subprocess.run(
            [
                swiftc,
                str(NUMERIC_SOURCE),
                str(GENERAL_SOURCE),
                str(SHAKE_SOURCE),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def assert_vector_almost_equal(
        self, actual: list[float], expected: list[float], places: int = 5
    ) -> None:
        self.assertEqual(len(actual), len(expected))
        for actual_value, expected_value in zip(actual, expected, strict=True):
            self.assertAlmostEqual(actual_value, expected_value, places=places)

    def test_general_defaults_wrappers_and_malformed_values(self) -> None:
        self.assertEqual(self.result["missing"], [False, 0.5, 1, 3])
        self.assertTrue(self.result["literal"][0])
        self.assert_vector_almost_equal(
            self.result["literal"][1:], [0.23, 1, 1.25]
        )
        self.assertTrue(self.result["wrapped"][0])
        self.assert_vector_almost_equal(self.result["wrapped"][1:], [0.4, 0, 2])
        self.assertEqual(self.result["malformed"], [None, None, None, None])
        self.assertEqual(self.result["missingAdmission"], "disabled")
        self.assertEqual(self.result["literalAdmission"], "executable")
        self.assertEqual(self.result["wrappedAdmission"], "executable")
        self.assertEqual(self.result["malformedAdmission"], "invalid")

    def test_admission_is_bounded_and_fail_closed(self) -> None:
        self.assertEqual(self.result["rangeAdmission"], "invalid")
        self.assertEqual(self.result["missingScalarAdmission"], "invalid")
        self.assertEqual(self.result["missingProjectionAdmission"], "invalid")
        self.assertEqual(
            self.result["disabledMissingProjectionAdmission"], "disabled"
        )
        self.assertEqual(self.result["disabledOffset"], [0, 0])
        self.assertEqual(self.result["amplitudeZeroOffset"], [0, 0])
        self.assertEqual(self.result["invalidHeight"], [0, 0])
        self.assertEqual(self.result["invalidTime"], [0, 0])

    def test_absolute_time_speed_and_roughness_contract(self) -> None:
        self.assertNotEqual(self.result["timeA"], self.result["timeB"])
        self.assertEqual(self.result["timeA"], self.result["timeARepeat"])
        self.assert_vector_almost_equal(
            self.result["speedSquaredOne"], self.result["speedSquaredTwo"]
        )
        self.assert_vector_almost_equal(
            self.result["speedZeroA"], [5, 0]
        )
        self.assertEqual(self.result["speedZeroA"], self.result["speedZeroB"])
        raw = [math.cos(1), math.sin(1.333)]
        self.assert_vector_almost_equal(self.result["roughnessZero"], raw)
        self.assert_vector_almost_equal(self.result["roughnessOne"], raw)
        raw_length = math.hypot(*raw)
        shaped = [component * (raw_length**8 / raw_length) for component in raw]
        self.assert_vector_almost_equal(self.result["roughnessTwo"], shaped)

    def test_report_and_single_camera_owner_wiring(self) -> None:
        self.assertEqual(
            self.result["report"],
            "camera shake: status=executable enabled=true amplitude=0.23"
            " roughness=1.0 speed=1.25",
        )
        camera_owner = (
            SCENE_ROOT / "Rendering/SceneMetalRenderer+Camera.swift"
        ).read_text(encoding="utf-8")
        renderer = (SCENE_ROOT / "Rendering/SceneMetalRenderer.swift").read_text(
            encoding="utf-8"
        )
        pointer = (
            SCENE_ROOT / "Rendering/SceneMetalRenderer+ParticlePointer.swift"
        ).read_text(encoding="utf-8")
        view = (SCENE_ROOT / "Rendering/SceneMetalView.swift").read_text(
            encoding="utf-8"
        )
        parallax = (SCENE_ROOT / "Rendering/SceneLayerParallax.swift").read_text(
            encoding="utf-8"
        )
        self.assertEqual(camera_owner.count("SceneParticleCameraFrame("), 1)
        self.assertNotIn("SceneParticleCameraFrame(", renderer)
        self.assertNotIn("SceneParticleCameraFrame(", pointer)
        self.assertIn("let cameraFrame = renderer.makeCameraFrame", view)
        self.assertGreaterEqual(view.count("cameraFrame: cameraFrame"), 2)
        self.assertIn("cameraFrame.cameraOrigin", camera_owner)
        self.assertIn("cameraOrigin: dynamic.origin + SIMD3", camera_owner)
        self.assertNotIn("SceneCameraShake", parallax)


if __name__ == "__main__":
    unittest.main()
