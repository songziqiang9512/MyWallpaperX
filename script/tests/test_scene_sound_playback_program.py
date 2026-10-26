#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PROGRAM_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneSoundPlaybackProgram.swift"
)
REGISTRY_SOURCE = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneSoundPlaybackRegistry.swift"
)
REGISTRY_SWIFT_SOURCES = [
    PROGRAM_SOURCE, REGISTRY_SOURCE,
    *(REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene" / path for path in [
        "Systems/Properties/SceneDynamicSnapshot.swift", "Systems/Media/SceneAudioSpectrum.swift",
        "Runtime/Frame/SceneSurfacePointerState.swift", "Runtime/Frame/SceneFrameContext.swift",
    ]),
    REPOSITORY_ROOT / "MyWallpaperX/Core/PlaybackControl/ScenePlaybackShortcut.swift",
]


def record_process(name, process):
    if destination := os.environ.get("MWX_SOUND_TEST_EVIDENCE"):
        root = Path(destination)
        root.mkdir(parents=True, exist_ok=True)
        (root / f"{name}.stdout").write_text(process.stdout)
        (root / f"{name}.stderr").write_text(process.stderr)
        (root / f"{name}.json").write_text(json.dumps({"returnCode": process.returncode}))

STUB_SOURCE = r'''
import AVFoundation
import Foundation

enum SceneDynamicField: Hashable {
    case volume
}

enum SceneDynamicTarget: Hashable {
    case layer(layerID: Int, field: SceneDynamicField)
}

enum SceneDynamicValue: Hashable {
    case scalar(Double)
}

struct SceneDynamicTargetDefinition {
    let target: SceneDynamicTarget
    let authoredValue: SceneDynamicValue
}

struct SceneDynamicResolvedValue {
    let value: SceneDynamicValue
}

struct SceneDynamicSnapshot {
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { nil }
}

struct SceneScriptMediaPlaybackCommand {
    enum Destination { case videoTexture, soundLayer }
    enum Action { case play, pause, stop, setCurrentTime(Double), setRate(Double), setLoop(Bool) }
    let layerID: Int
    let action: Action
    let destination: Destination
    init(layerID: Int, action: Action, destination: Destination = .videoTexture) {
        self.layerID = layerID; self.action = action; self.destination = destination
    }
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

// Prepared-plan carriers only: no filesystem, Root safety or byte-copy proof.
// The real Root/OwnedFile chain is executed by test_scene_sound_resource_input.
struct SceneResourceView {
    struct Handle: Hashable {
        let url: URL
        var diagnosticPath: String { url.path }
        var displayPath: String { url.path }
        var relativePath: String { url.lastPathComponent }
    }
    enum FileInput: Hashable { case resource(Handle) }
    enum ReadError: Error { case missing, unreadable, sourceChanged, invalidHandle, invalidPath, symlinkEscape }
    enum EntrySelection { case authoredLiteral, indexedReference }
    let resourcesByReference: [String: URL]

    func literalEntry(relativePath reference: String, selection: EntrySelection = .authoredLiteral) throws -> Handle? {
        // Controlled Root outcomes only. Real spelling/traversal, alias and
        // byte-consumption behavior is covered by the actual Root fixture.
        if ["../escape.flac", "../escape.ogg"].contains(reference) { throw ReadError.symlinkEscape }
        return resourcesByReference[reference].map { Handle(url: $0) }
    }

    func displayPath(for url: URL) -> String { url.path }
}

nonisolated final class SceneVideoOwnedFile: Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    func retainForLifetime(of asset: AVAsset) {}
    enum Operation: Equatable { case createSnapshot, writeSnapshot, closeSnapshot }
    enum Failure: Error {
        case invalidSourceURL
        case aggregateDiskBudgetExceeded
        case directoryCreation(domain: String, code: Int)
        case io(operation: Operation, code: Int32)
    }
    static func snapshot(from handle: SceneResourceView.Handle, cacheDirectory: URL,
        fileExtension: String, checkCancellation: (() throws -> Void)? = nil) throws -> SceneVideoOwnedFile {
        try checkCancellation?()
        return SceneVideoOwnedFile(url: handle.url)
    }
}
'''

PROGRAM_HARNESS_SOURCE = r'''
import AVFoundation
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
        minimumDistance: Double? = nil,
        startsSilent: Bool? = false,
        propertyKey: String? = nil
    ) -> SceneDocument.SceneSoundLayerDefinition {
        SceneDocument.SceneSoundLayerDefinition(
            paths: paths,
            authoredPathCount: paths.count,
            playbackMode: mode,
            startsSilent: startsSilent,
            muteInEditor: false,
            volume: 0.5,
            volumePropertyKey: propertyKey,
            minimumTime: minimumTime,
            maximumTime: maximumTime,
            spatialization: spatialization,
            attenuation: attenuation,
            minimumDistance: minimumDistance
        )
    }

    static func main() throws {
        let timedLoopLayerID = 101
        let firstAvailableSourceLayerID = 202
        let skipToNextSourceLayerID = 206
        let allSourcesUnavailableLayerID = 207
        let pathEscapeLayerID = 210
        let missingLegalSourceLayerID = 211
        let oggLayerID = 208
        let mixedCaseSingleLayerID = 209
        let nonLoopLayerID = 303
        let explicitlyNonspatialLayerID = 404
        let spatialLayerID = 505
        let invalidIntervals: [(Double?, Double?)] = [
            (nil, 2), (1, nil), (nil, nil), (-0.5, 2), (2, 1),
            (.nan, 2), (1, .infinity), (-.infinity, 2), (0, .nan), (0, -1),
        ]
        let document = SceneDocument(objects: [
            .init(id: 606, sound: sound(paths: ["audio/caps.mp3"], mode: "loop", startsSilent: true)),
            .init(id: 607, sound: sound(paths: ["audio/caps.mp3"], mode: "loop", startsSilent: nil)),
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
                id: firstAvailableSourceLayerID,
                sound: sound(
                    paths: ["audio/first.wav", "audio/second.flac"],
                    mode: "loop"
                )
            ),
            .init(
                id: skipToNextSourceLayerID,
                sound: sound(
                    paths: ["audio/missing.ogg", "audio/fallback.flac"],
                    mode: "single"
                )
            ),
            .init(
                id: allSourcesUnavailableLayerID,
                sound: sound(
                    paths: ["audio/gone.wav", "audio/also-gone.mp3"],
                    mode: "loop"
                )
            ),
            .init(
                id: pathEscapeLayerID,
                sound: sound(paths: ["../escape.flac"], mode: "loop")
            ),
            .init(
                id: missingLegalSourceLayerID,
                sound: sound(paths: ["audio/absent.mp3"], mode: "loop")
            ),
            .init(
                id: oggLayerID,
                sound: sound(paths: ["audio/native.ogg"], mode: "single")
            ),
            .init(
                id: 212,
                sound: sound(paths: ["renamed/first.OGG", "audio/first.wav"], mode: "loop")
            ),
            .init(
                id: 213,
                sound: sound(paths: ["audio/other.webm", "audio/caps.mp3"], mode: "loop")
            ),
            .init(
                id: 214,
                sound: sound(paths: ["audio/other.m4a"], mode: "single")
            ),
            .init(
                id: 215,
                sound: sound(paths: ["../escape.ogg"], mode: "loop")
            ),
            .init(id: 216, sound: sound(paths: ["audio/first.wav", "audio/unused.ogg"], mode: "loop")),
            .init(id: 217, sound: sound(paths: ["audio/gone.wav", "renamed/second.OGG"], mode: "single")),
            .init(id: 218, sound: sound(paths: ["audio/gone.ogg", "audio/missing.wav"], mode: "loop")),
            .init(
                id: mixedCaseSingleLayerID,
                sound: sound(paths: ["audio/caps.mp3"], mode: "Single")
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
            .init(id: 701, sound: sound(paths: ["audio/first.wav", "audio/second.flac"],
                mode: "random", minimumTime: 1, maximumTime: 2, startsSilent: true)),
            .init(id: 702, sound: sound(paths: ["renamed/clip-B.FLAC", "alternate/clip-A.WAV"],
                mode: "RaNdOm", minimumTime: 2.0, maximumTime: 2.0,
                propertyKey: "renamedRandomGain")),
            .init(id: 703, sound: sound(paths: ["audio/gone.wav", "audio/first.wav",
                "../escape.flac", "audio/other.webm", "audio/second.flac", "audio/absent.mp3"],
                mode: "random", minimumTime: 0, maximumTime: 4)),
            .init(id: 704, sound: sound(paths: ["audio/gone.wav", "audio/other.m4a"],
                mode: "random", minimumTime: 1, maximumTime: 2)),
            .init(id: 705, sound: sound(paths: [], mode: "random", minimumTime: 1, maximumTime: 2)),
            .init(id: 706, sound: sound(paths: ["audio/native.ogg", "audio/caps.mp3"],
                mode: "random", minimumTime: 0, maximumTime: 0)),
            .init(id: 707, sound: sound(paths: ["audio/first.wav"], mode: "random",
                minimumTime: 1, maximumTime: 2, spatialization: true)),
            .init(id: 708, sound: sound(paths: ["audio/first.wav", "../unused.flac"], mode: "single")),
        ] + invalidIntervals.enumerated().map { index, interval -> SceneDocument.Object in
            .init(id: 800 + index, sound: sound(paths: ["audio/first.wav"], mode: "random",
                minimumTime: interval.0, maximumTime: interval.1))
        })
        let resourceView = SceneResourceView(resourcesByReference: [
            "audio/timed-loop.mp3": URL(fileURLWithPath: "/fixture/timed-loop.mp3"),
            "audio/first.wav": URL(fileURLWithPath: "/fixture/first.wav"),
            "audio/second.flac": URL(fileURLWithPath: "/fixture/second.flac"),
            "audio/fallback.flac": URL(fileURLWithPath: "/fixture/fallback.flac"),
            "audio/caps.mp3": URL(fileURLWithPath: "/fixture/caps.mp3"),
            "audio/one-shot.wav": URL(fileURLWithPath: "/fixture/one-shot.wav"),
            "audio/nonspatial.mp3": URL(fileURLWithPath: "/fixture/nonspatial.mp3"),
            "audio/spatial.mp3": URL(fileURLWithPath: "/fixture/spatial.mp3"),
            "audio/native.ogg": URL(fileURLWithPath: "/fixture/native.ogg"),
            "renamed/first.OGG": URL(fileURLWithPath: "/fixture/renamed-first.ogg"),
            "audio/other.webm": URL(fileURLWithPath: "/fixture/other.webm"),
            "audio/other.m4a": URL(fileURLWithPath: "/fixture/other.m4a"),
            "renamed/second.OGG": URL(fileURLWithPath: "/fixture/second-renamed.ogg"),
            "renamed/clip-B.FLAC": URL(fileURLWithPath: "/fixture/renamed-clip-B.flac"),
            "alternate/clip-A.WAV": URL(fileURLWithPath: "/fixture/alternate-clip-A.wav"),
            "../escape.flac": URL(fileURLWithPath: "/fixture/escape.flac"),
        ])

        let program = try SceneSoundPlaybackProgram.compile(
            document: document,
            resourceView: resourceView
        , privateCacheDirectory: FileManager.default.temporaryDirectory)
        let unavailableOnly = try SceneSoundPlaybackProgram.compile(document: .init(
            objects: document.objects.filter { $0.id == allSourcesUnavailableLayerID }),
            resourceView: resourceView, privateCacheDirectory: FileManager.default.temporaryDirectory)
        let volumeDefinitions = program.bindings.map {
            SceneDynamicTargetDefinition(target: $0.volumeTarget, authoredValue: .scalar(0.5))
        }
        let consumers = program.sceneScriptVolumeConsumerTargets(for: volumeDefinitions,
            namedPropertyKeys: [.layer(layerID: 702, field: .volume): "renamedRandomGain"],
            resolvedPropertyVolumes: ["renamedRandomGain": 0.5])
        let payload: [String: Any] = [
            // This harness verifies preparation only; these resource carriers
            // do not pretend to contain encoded audio or prove playback.
            "platformOggPlayable": AVURLAsset.isPlayableExtendedMIMEType("audio/ogg"),
            "admittedLayerIDs": program.bindings.map(\.layerID),
            "bindings": program.bindings.map { binding in
                var result: [String: Any] = ["layerID": binding.layerID,
                    "sources": binding.resources.map(\.displayPath),
                    "resourceURLs": binding.resources.map { $0.file!.url.path },
                    "startsSilent": binding.startsSilent,
                    "volumeConsumer": consumers.contains(binding.volumeTarget)]
                switch binding.playbackMode {
                case .loop: result["mode"] = "loop"
                case .single: result["mode"] = "single"
                case let .random(minimum, maximum):
                    result["mode"] = "random"
                    result["minimumTime"] = minimum; result["maximumTime"] = maximum
                }
                return result
            },
            "invalidIntervalLayerIDs": invalidIntervals.indices.map { 800 + $0 },
            "unavailableOnlySummary": ["admitted": unavailableOnly.bindings.count,
                "rejected": unavailableOnly.layerRejectionCount,
                "skipped": unavailableOnly.skippedSourceCount,
                "diagnostics": unavailableOnly.diagnostics.count],
            "reports": program.reportLines,
            "diagnostics": program.diagnostics.map { diagnostic in
                [
                    "layerID": diagnostic.layerID,
                    "reason": diagnostic.reason.rawValue,
                    "detail": diagnostic.detail,
                ]
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

PLAYBACK_HARNESS_SOURCE = (
    REPOSITORY_ROOT / "script/tests/fixtures/SceneSoundPlaybackRegistryHarness.swift"
).read_text(encoding="utf-8")


def layer_diagnostics(payload, layer_id):
    return [
        (entry["reason"], entry["detail"])
        for entry in payload["diagnostics"]
        if entry["layerID"] == layer_id
    ]


def layer_binding_sources(payload, layer_id):
    return [
        source
        for entry in payload["bindings"]
        if entry["layerID"] == layer_id
        for source in entry["sources"]
    ]


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
        harness.write_text(PROGRAM_HARNESS_SOURCE, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                str(PROGRAM_SOURCE),
                str(stub),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
            shell=False,
        )
        record_process("program-compile", compilation)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        # /usr/bin/env keeps a literal executable anchor; the target is the
        # harness binary this test just compiled into its own temp directory.
        completed = subprocess.run(
            ["/usr/bin/env", str(binary)],
            capture_output=True,
            text=True,
            check=True,
            shell=False,
        )
        record_process("program", completed)
        cls.payload = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_explicit_startsilent_is_preserved_and_missing_value_is_rejected(self) -> None:
        binding = next(entry for entry in self.payload["bindings"] if entry["layerID"] == 606)
        self.assertTrue(binding["startsSilent"])
        self.assertEqual(layer_diagnostics(self.payload, 606), [])
        self.assertNotIn(607, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 607), [("startsSilentUnsupported", "nil")])

    def test_loop_with_minimum_and_maximum_time_remains_admitted(self) -> None:
        self.assertIn(101, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 101), [])

    def test_explicitly_disabled_spatial_metadata_remains_nonspatial(self) -> None:
        diagnostic_layer_ids = [
            entry["layerID"] for entry in self.payload["diagnostics"]
        ]
        self.assertNotIn(404, diagnostic_layer_ids)

    def test_single_mode_is_admitted(self) -> None:
        self.assertIn(209, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 209), ["/fixture/caps.mp3"]
        )
        self.assertEqual(layer_diagnostics(self.payload, 209), [])

    def test_multi_source_admits_first_available_source(self) -> None:
        self.assertIn(202, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 202), ["/fixture/first.wav"]
        )
        self.assertEqual(layer_diagnostics(self.payload, 202), [])

    def test_multi_source_skips_unusable_sources_to_first_available(self) -> None:
        self.assertIn(206, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_binding_sources(self.payload, 206), ["/fixture/fallback.flac"]
        )
        self.assertEqual(
            layer_diagnostics(self.payload, 206),
            [("resourceUnavailable", "audio/missing.ogg")]
            if self.payload["platformOggPlayable"]
            else [("audioFormatUnsupported", "ogg")],
        )

    def test_all_sources_unavailable_keep_their_per_source_reasons(self) -> None:
        self.assertNotIn(207, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 207),
            [
                ("resourceUnavailable", "audio/gone.wav"),
                ("resourceUnavailable", "audio/also-gone.mp3"),
            ],
        )
        self.assertEqual(self.payload["unavailableOnlySummary"],
                         {"admitted": 0, "rejected": 1, "skipped": 0, "diagnostics": 2})

    def test_path_escape_source_keeps_the_typed_path_reason(self) -> None:
        self.assertNotIn(210, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 210),
            [("malformedSourceList", "../escape.flac")],
        )

    def test_missing_source_with_legal_extension_keeps_resource_reason(self) -> None:
        self.assertNotIn(211, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 211),
            [("resourceUnavailable", "audio/absent.mp3")],
        )

    def test_ogg_source_admission_follows_platform_capability(self) -> None:
        if self.payload["platformOggPlayable"]:
            self.assertIn(208, self.payload["admittedLayerIDs"])
            self.assertEqual(layer_binding_sources(self.payload, 208), ["/fixture/native.ogg"])
            self.assertEqual(layer_diagnostics(self.payload, 208), [])
        else:
            self.assertNotIn(208, self.payload["admittedLayerIDs"])
            self.assertEqual(layer_diagnostics(self.payload, 208), [("audioFormatUnsupported", "ogg")])

    def test_platform_ogg_preserves_authored_first_source_and_case_normalization(self) -> None:
        supported = self.payload["platformOggPlayable"]
        self.assertIn(212, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_binding_sources(self.payload, 212),
                         ["/fixture/renamed-first.ogg" if supported else "/fixture/first.wav"])
        self.assertEqual(layer_diagnostics(self.payload, 212),
                         [] if supported else [("audioFormatUnsupported", "ogg")])

    def test_other_native_media_formats_do_not_expand_the_sound_profile(self) -> None:
        self.assertEqual(layer_binding_sources(self.payload, 213), ["/fixture/caps.mp3"])
        self.assertEqual(layer_diagnostics(self.payload, 213), [("audioFormatUnsupported", "webm")])
        self.assertNotIn(214, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 214), [("audioFormatUnsupported", "m4a")])

    def test_first_available_wav_ignores_later_missing_ogg(self) -> None:
        self.assertEqual(layer_binding_sources(self.payload, 216), ["/fixture/first.wav"])
        self.assertEqual(layer_diagnostics(self.payload, 216), [])

    def test_platform_ogg_can_be_the_second_available_source(self) -> None:
        supported = self.payload["platformOggPlayable"]
        self.assertEqual(layer_binding_sources(self.payload, 217),
                         ["/fixture/second-renamed.ogg"] if supported else [])
        self.assertEqual(layer_diagnostics(self.payload, 217),
                         [("resourceUnavailable", "audio/gone.wav")]
                         + ([] if supported else [("audioFormatUnsupported", "ogg")]))

    def test_missing_ogg_and_wav_preserve_both_attempt_reasons(self) -> None:
        self.assertNotIn(218, self.payload["admittedLayerIDs"])
        first = ("resourceUnavailable", "audio/gone.ogg") if self.payload["platformOggPlayable"] \
            else ("audioFormatUnsupported", "ogg")
        self.assertEqual(layer_diagnostics(self.payload, 218),
                         [first, ("resourceUnavailable", "audio/missing.wav")])

    def test_unsupported_ogg_skips_root_and_supported_ogg_keeps_path_failure_local(self) -> None:
        self.assertNotIn(215, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 215),
                         [("malformedSourceList", "../escape.ogg")] if self.payload["platformOggPlayable"]
                         else [("audioFormatUnsupported", "ogg")])

    def test_non_loop_mode_is_rejected_with_the_typed_reason(self) -> None:
        self.assertNotIn(303, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 303),
            [("playbackModeUnsupported", "once")],
        )

    def test_random_prepares_both_resources_in_authored_order(self) -> None:
        binding = next(entry for entry in self.payload["bindings"] if entry["layerID"] == 701)
        self.assertEqual(binding["mode"], "random")
        self.assertEqual(binding["sources"], ["/fixture/first.wav", "/fixture/second.flac"])
        self.assertEqual(binding["resourceURLs"], binding["sources"])
        self.assertEqual((binding["minimumTime"], binding["maximumTime"]), (1, 2))
        self.assertTrue(binding["startsSilent"])
        self.assertTrue(binding["volumeConsumer"])
        self.assertEqual(layer_diagnostics(self.payload, 701), [])

    def test_renamed_random_resources_equal_interval_and_volume_identity(self) -> None:
        binding = next(entry for entry in self.payload["bindings"] if entry["layerID"] == 702)
        self.assertEqual(binding["mode"], "random")
        self.assertEqual(binding["sources"], ["/fixture/renamed-clip-B.flac", "/fixture/alternate-clip-A.wav"])
        self.assertEqual((binding["minimumTime"], binding["maximumTime"]), (2, 2))
        self.assertTrue(binding["volumeConsumer"])
        self.assertEqual(layer_diagnostics(self.payload, 702), [])

    def test_random_keeps_per_source_failures_before_and_after_usable_resources(self) -> None:
        self.assertEqual(layer_binding_sources(self.payload, 703), ["/fixture/first.wav", "/fixture/second.flac"])
        self.assertEqual(layer_diagnostics(self.payload, 703), [
            ("resourceUnavailable", "audio/gone.wav"), ("malformedSourceList", "../escape.flac"),
            ("audioFormatUnsupported", "webm"), ("resourceUnavailable", "audio/absent.mp3")])

    def test_random_without_usable_resources_or_with_empty_list_is_rejected(self) -> None:
        self.assertNotIn(704, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 704), [
            ("resourceUnavailable", "audio/gone.wav"), ("audioFormatUnsupported", "m4a")])
        self.assertNotIn(705, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 705), [("malformedSourceList", "count=0")])

    def test_random_requires_explicit_finite_ordered_nonnegative_intervals(self) -> None:
        for layer_id in self.payload["invalidIntervalLayerIDs"]:
            with self.subTest(layer_id=layer_id):
                self.assertNotIn(layer_id, self.payload["admittedLayerIDs"])
                self.assertEqual([reason for reason, _ in layer_diagnostics(self.payload, layer_id)],
                                 ["intervalInvalid"])

    def test_zero_gap_random_keeps_the_platform_ogg_gate(self) -> None:
        binding = next(entry for entry in self.payload["bindings"] if entry["layerID"] == 706)
        supported = self.payload["platformOggPlayable"]
        self.assertEqual(binding["sources"], (["/fixture/native.ogg"] if supported else []) + ["/fixture/caps.mp3"])
        self.assertEqual((binding["minimumTime"], binding["maximumTime"]), (0, 0))
        self.assertEqual(layer_diagnostics(self.payload, 706), [] if supported else [("audioFormatUnsupported", "ogg")])

    def test_random_spatial_rejection_and_ordinary_tail_skipping_remain_local(self) -> None:
        self.assertNotIn(707, self.payload["admittedLayerIDs"])
        self.assertEqual(layer_diagnostics(self.payload, 707), [("spatialPlaybackUnsupported", "spatial-fields-present")])
        self.assertEqual(layer_binding_sources(self.payload, 708), ["/fixture/first.wav"])
        self.assertEqual(layer_diagnostics(self.payload, 708), [])
        self.assertIn(202, self.payload["admittedLayerIDs"])

    def test_binding_report_identifies_mode_and_prepared_candidate_count(self) -> None:
        self.assertTrue(any("layer=701 mode=random candidates=2" in line for line in self.payload["reports"]))
        self.assertTrue(any("layer=202 mode=loop candidates=1" in line for line in self.payload["reports"]))

    def test_enabled_spatial_playback_remains_typed_unsupported(self) -> None:
        self.assertNotIn(505, self.payload["admittedLayerIDs"])
        self.assertEqual(
            layer_diagnostics(self.payload, 505),
            [("spatialPlaybackUnsupported", "spatial-fields-present")],
        )


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneSoundPlaybackRegistryPlaybackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-sound-playback-"
        )
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        stub = root / "SceneSoundPlaybackRegistryStubs.swift"
        harness = root / "PlaybackHarness.swift"
        binary = root / "scene-sound-playback-registry"
        # The Registry lane uses the production typed snapshot and SceneClock.
        # Keep the document/resource/media carriers, without redefining the
        # dynamic types compiled from SceneDynamicSnapshot.swift below.
        _, separator, carriers = STUB_SOURCE.partition("struct SceneScriptMediaPlaybackCommand")
        if not separator:
            raise RuntimeError("media carrier boundary missing from shared Sound stub")
        stub.write_text("import AVFoundation\nimport Foundation\n\n" + separator + carriers, encoding="utf-8")
        harness.write_text(PLAYBACK_HARNESS_SOURCE, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                *map(str, REGISTRY_SWIFT_SOURCES),
                str(stub),
                str(harness),
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
            shell=False,
        )
        record_process("playback-compile", compilation)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        cls.result = subprocess.run(
            ["/usr/bin/env", str(binary)],
            capture_output=True,
            text=True,
            timeout=90,
            shell=False,
        )
        record_process("playback", cls.result)

    def test_single_mode_plays_to_end_without_restart(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("single-play-to-end-pass", self.result.stdout)

    def test_loop_mode_still_restarts(self) -> None:
        self.assertIn("loop-restart-pass", self.result.stdout)


    def test_single_completion_can_replay_on_the_same_player(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("single-replay-same-player-pass", self.result.stdout)

    def test_startsilent_and_ready_do_not_autoplay(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("startsilent-ready-host-resume-pass", self.result.stdout)

    def test_repeated_play_resets_single_progress(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("repeated-play-restarts-single-pass", self.result.stdout)

    def test_host_pause_is_independent_of_author_pause(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("author-pause-and-host-pause-independent-pass", self.result.stdout)

    def test_stop_rewinds_and_can_replay(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("stop-rewinds-and-replays-pass", self.result.stdout)

    def test_invalid_batches_have_no_partial_side_effects(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("atomic-command-rejection-pass", self.result.stdout)

    def test_commands_apply_in_author_order(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("ordered-author-commands-pass", self.result.stdout)

    def test_teardown_rejects_and_cannot_restart(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("teardown-rejects-and-does-not-revive-pass", self.result.stdout)

    def test_initial_host_pause_retains_autoplay_intent(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("initial-host-pause-retains-autoplay-intent-pass", self.result.stdout)

    def test_host_suspension_keeps_author_repeat_semantics(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("host-suspension-preserves-author-repeat-semantics-pass", self.result.stdout)

    def test_master_gain_and_mute_are_preserved(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("gain-and-mute-contract-pass", self.result.stdout)

    def test_layer_retirement_stops_only_its_source(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("layer-retirement-stops-only-its-source-pass", self.result.stdout)

    def test_random_uses_actual_natural_end_then_scene_clock(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-natural-end-scene-clock-single-item-pass", self.result.stdout)

    def test_random_keeps_admitted_urls_and_one_item_per_cadence(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-renamed-candidates-and-same-cadence-pass", self.result.stdout)

    def test_random_host_pause_uses_production_clock_and_gain_preserves_wait(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-real-clock-host-pause-drops-gap-pass", self.result.stdout)
        self.assertIn("random-gain-does-not-reset-pending-pass", self.result.stdout)

    def test_random_author_resume_and_running_play_preserve_pending_deadline(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-author-gap-resume-and-running-play-pass", self.result.stdout)
        self.assertIn("random-temporary-end-preserves-old-gap-pass", self.result.stdout)

    def test_random_replaced_item_late_completion_cannot_rearm(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-replaced-item-late-end-is-ignored-pass", self.result.stdout)

    def test_random_stop_retirement_and_epoch_do_not_revive(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-stop-replay-clears-wait-pass", self.result.stdout)
        self.assertIn("random-retire-and-epoch-late-events-do-not-revive-pass", self.result.stdout)

    def test_random_codec_failure_is_local_and_requires_explicit_retry(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertIn("random-codec-failure-local-and-explicit-retry-pass", self.result.stdout)

if __name__ == "__main__":
    unittest.main()
