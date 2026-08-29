#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROGRAM_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneSoundPlaybackProgram.swift"
)

STUB_SOURCE = r'''
import Foundation

enum SceneDynamicField: Hashable {
    case volume
}

enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicField)
}

struct SceneDocument {
    struct SceneSoundLayerDefinition {
        let paths: [String]
        let authoredPathCount: Int
        let playbackMode: String?
        let startsSilent: Bool?
        let muteInEditor: Bool?
        let volume: Double?
        let volumePropertyKey: String?
        let minimumTime: Double?
        let maximumTime: Double?
        let spatialization: Bool?
        let attenuation: Double?
        let minimumDistance: Double?
    }

    struct Object {
        let id: Int
        let sound: SceneSoundLayerDefinition?
    }

    let objects: [Object]
}

struct SceneResource {
    let url: URL
}

struct SceneResourceView {
    let resourcesByReference: [String: URL]

    func resource(forReference reference: String) -> SceneResource? {
        guard let url = resourcesByReference[reference] else { return nil }
        return SceneResource(url: url)
    }

    func displayPath(for url: URL) -> String {
        url.path
    }
}
'''

HARNESS_SOURCE = r'''
import Foundation

@main
enum Harness {
    static func sound(
        paths: [String],
        mode: String,
        minimumTime: Double? = nil,
        maximumTime: Double? = nil,
        spatialization: Bool? = nil,
        attenuation: Double? = nil,
        minimumDistance: Double? = nil
    ) -> SceneDocument.SceneSoundLayerDefinition {
        SceneDocument.SceneSoundLayerDefinition(
            paths: paths,
            authoredPathCount: paths.count,
            playbackMode: mode,
            startsSilent: false,
            muteInEditor: false,
            volume: 0.5,
            volumePropertyKey: nil,
            minimumTime: minimumTime,
            maximumTime: maximumTime,
            spatialization: spatialization,
            attenuation: attenuation,
            minimumDistance: minimumDistance
        )
    }

    static func main() throws {
        let timedLoopLayerID = 101
        let multipleSourceLayerID = 202
        let nonLoopLayerID = 303
        let explicitlyNonspatialLayerID = 404
        let spatialLayerID = 505
        let document = SceneDocument(objects: [
            .init(
                id: timedLoopLayerID,
                sound: sound(
                    paths: ["audio/timed-loop.mp3"],
                    mode: "loop",
                    minimumTime: 2.5,
                    maximumTime: 7.5
                )
            ),
            .init(
                id: multipleSourceLayerID,
                sound: sound(
                    paths: ["audio/first.wav", "audio/second.flac"],
                    mode: "loop"
                )
            ),
            .init(
                id: nonLoopLayerID,
                sound: sound(paths: ["audio/one-shot.wav"], mode: "once")
            ),
            .init(
                id: explicitlyNonspatialLayerID,
                sound: sound(
                    paths: ["audio/nonspatial.mp3"],
                    mode: "loop",
                    spatialization: false,
                    attenuation: 1,
                    minimumDistance: 1
                )
            ),
            .init(
                id: spatialLayerID,
                sound: sound(
                    paths: ["audio/spatial.mp3"],
                    mode: "loop",
                    spatialization: true,
                    attenuation: 1,
                    minimumDistance: 1
                )
            ),
        ])
        let resourceView = SceneResourceView(resourcesByReference: [
            "audio/timed-loop.mp3": URL(fileURLWithPath: "/fixture/timed-loop.mp3"),
            "audio/first.wav": URL(fileURLWithPath: "/fixture/first.wav"),
            "audio/second.flac": URL(fileURLWithPath: "/fixture/second.flac"),
            "audio/one-shot.wav": URL(fileURLWithPath: "/fixture/one-shot.wav"),
            "audio/nonspatial.mp3": URL(fileURLWithPath: "/fixture/nonspatial.mp3"),
            "audio/spatial.mp3": URL(fileURLWithPath: "/fixture/spatial.mp3"),
        ])

        let program = SceneSoundPlaybackProgram.compile(
            document: document,
            resourceView: resourceView
        )
        let multipleSourceTypedRejection = program.diagnostics.contains {
            $0.layerID == multipleSourceLayerID
                && $0.reason == .multipleSourcesUnsupported
        }
        let nonLoopTypedRejection = program.diagnostics.contains {
            $0.layerID == nonLoopLayerID
                && $0.reason == .playbackModeUnsupported
        }
        let spatialTypedRejection = program.diagnostics.contains {
            $0.layerID == spatialLayerID
                && $0.reason == .spatialPlaybackUnsupported
        }
        let payload: [String: Any] = [
            "admittedLayerIDs": program.bindings.map(\.layerID),
            "diagnosticLayerIDs": program.diagnostics.map(\.layerID),
            "diagnosticReasons": program.diagnostics.map { $0.reason.rawValue },
            "multipleSourceTypedRejection": multipleSourceTypedRejection,
            "nonLoopTypedRejection": nonLoopTypedRejection,
            "spatialTypedRejection": spatialTypedRejection,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSoundPlaybackProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-sound-program-"
        )
        root = Path(cls.temporary_directory.name)
        stub = root / "SceneSoundPlaybackProgramStubs.swift"
        harness = root / "Harness.swift"
        binary = root / "scene-sound-playback-program"
        stub.write_text(STUB_SOURCE, encoding="utf-8")
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        compilation = subprocess.run(
            [
                shutil.which("swiftc"),
                str(PROGRAM_SOURCE),
                str(stub),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.payload = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_loop_with_minimum_and_maximum_time_remains_admitted(self) -> None:
        self.assertEqual(self.payload["admittedLayerIDs"], [101, 404])

    def test_explicitly_disabled_spatial_metadata_remains_nonspatial(self) -> None:
        self.assertNotIn(404, self.payload["diagnosticLayerIDs"])

    def test_multiple_sources_are_rejected_with_the_typed_reason(self) -> None:
        self.assertTrue(self.payload["multipleSourceTypedRejection"])
        self.assertIn("multipleSourcesUnsupported", self.payload["diagnosticReasons"])

    def test_non_loop_mode_is_rejected_with_the_typed_reason(self) -> None:
        self.assertTrue(self.payload["nonLoopTypedRejection"])
        self.assertIn("playbackModeUnsupported", self.payload["diagnosticReasons"])
        self.assertEqual(self.payload["diagnosticLayerIDs"], [202, 303, 505])

    def test_enabled_spatial_playback_remains_typed_unsupported(self) -> None:
        self.assertTrue(self.payload["spatialTypedRejection"])
        self.assertIn("spatialPlaybackUnsupported", self.payload["diagnosticReasons"])


if __name__ == "__main__":
    unittest.main()
