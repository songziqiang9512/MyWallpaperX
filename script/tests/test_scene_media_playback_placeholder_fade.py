#!/usr/bin/env python3

"""Bounded stock placeholder fade compilation and stateful scalar playback."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeProgram.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeCompiler.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeRuntime.swift",
]
PROGRAM_COMPILER_SWIFT_SOURCES = [
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeProgram.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeCompiler.swift",
    SCENE_ROOT / "Properties/SceneMediaPlaybackPlaceholderFadeProgramCompiler.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

@main
enum Harness {
    static let firstTarget = SceneDynamicTarget.effectConstant(
        layerID: 10, effectIndex: 2, passIndex: 0, name: "alpha"
    )
    static let secondTarget = SceneDynamicTarget.effectConstant(
        layerID: 11, effectIndex: 0, passIndex: 1, name: "strength"
    )

    static func main() throws {
        let source = placeholderSource()
        let first = compile(source: source, target: firstTarget)
        let inverse = compile(
            source: placeholderSource(stoppedOperator: "+", activeOperator: "-"),
            authored: 0.4,
            target: secondTarget
        )
        let program = SceneMediaPlaybackPlaceholderFadeProgram.validated(
            bindings: [first, inverse].compactMap { $0 }
        )

        var runtime = SceneMediaPlaybackPlaceholderFadeRuntime(program: program!)
        let initial = scalar(runtime.values(frameTime: 0), firstTarget)
        let stoppedUnbounded = scalar(runtime.values(frameTime: 0.75), firstTarget)
        let playingReset = scalar(runtime.values(
            playbackEventState: 1, frameTime: 0.1
        ), firstTarget)
        let pausedUnbounded = scalar(runtime.values(
            playbackEventState: 2, frameTime: 1
        ), firstTarget)
        let unknownFrozen = scalar(runtime.values(
            playbackEventState: 99, frameTime: 10
        ), firstTarget)
        let stoppedReset = scalar(runtime.values(
            playbackEventState: 0, frameTime: 0
        ), firstTarget)
        let stoppedAdvance = scalar(runtime.values(frameTime: 0.25), firstTarget)
        let eventBeforeUpdate = scalar(runtime.values(
            playbackEventState: 1, frameTime: 0.25
        ), firstTarget)
        let invalidDeltaFrozen = scalar(runtime.values(
            playbackEventState: 0, frameTime: -1
        ), firstTarget)

        var inverseRuntime = SceneMediaPlaybackPlaceholderFadeRuntime(program: program!)
        let inverseInitial = scalar(inverseRuntime.values(frameTime: 0), secondTarget)
        let inverseStopped = scalar(inverseRuntime.values(frameTime: 0.75), secondTarget)
        let inversePlaying = scalar(inverseRuntime.values(
            playbackEventState: 1, frameTime: 0.1
        ), secondTarget)
        let inversePaused = scalar(inverseRuntime.values(
            playbackEventState: 2, frameTime: 1
        ), secondTarget)
        let inverseUnknown = scalar(inverseRuntime.values(
            playbackEventState: 99, frameTime: 10
        ), secondTarget)
        let inverseStoppedReset = scalar(inverseRuntime.values(
            playbackEventState: 0, frameTime: 0
        ), secondTarget)

        let duplicate = SceneMediaPlaybackPlaceholderFadeProgram.validated(
            bindings: [first, first].compactMap { $0 }
        )
        let wrongWrapper = compile(source: source, keys: ["script", "value", "user"])
        let userBound = compile(source: source, user: "opacity")
        let timelineBound = compile(source: source, timeline: 1)
        let timelineDiagnostic = compile(source: source, diagnostics: ["invalid"])
        let outOfBounds = compile(source: source, authored: 1.01)
        let wrongTarget = compile(
            source: source,
            target: .layer(layerID: 10, field: .alpha)
        )
        let samePositive = compile(source: placeholderSource(stoppedOperator: "+"))
        let sameNegative = compile(source: placeholderSource(activeOperator: "-"))
        let wrongMapping = compile(source: placeholderSource(playingMapping: 2))
        let wrongLowerBound = compile(source: placeholderSource(lowerOperator: ">"))
        let wrongUpperBound = compile(source: placeholderSource(upperBound: 0))
        let extraHook = compile(source: source + "\nexport function hidden() { return 1; }")
        let oversized = compile(source: source + String(repeating: " ", count: 17_000))

        let result: [String: Any] = [
            "renamedCommentedASICompiled": first != nil,
            "inversePolarityCompiled": inverse != nil,
            "activePolarityProjected": first?.plan == .activeRise,
            "stoppedPolarityProjected": inverse?.plan == .stoppedRise,
            "programValidated": program?.bindings.count == 2,
            "initial": initial,
            "stoppedUnbounded": stoppedUnbounded,
            "playingReset": playingReset,
            "pausedUnbounded": pausedUnbounded,
            "unknownFrozen": unknownFrozen,
            "stoppedReset": stoppedReset,
            "stoppedAdvance": stoppedAdvance,
            "eventBeforeUpdate": eventBeforeUpdate,
            "invalidDeltaFrozen": invalidDeltaFrozen,
            "inverseInitial": inverseInitial,
            "inverseStopped": inverseStopped,
            "inversePlaying": inversePlaying,
            "inversePaused": inversePaused,
            "inverseUnknown": inverseUnknown,
            "inverseStoppedReset": inverseStoppedReset,
            "duplicateRejected": duplicate == nil,
            "wrongWrapperRejected": wrongWrapper == nil,
            "userBindingRejected": userBound == nil,
            "timelineRejected": timelineBound == nil,
            "timelineDiagnosticRejected": timelineDiagnostic == nil,
            "authoredBoundsRejected": outOfBounds == nil,
            "wrongTargetRejected": wrongTarget == nil,
            "samePositivePolarityRejected": samePositive == nil,
            "sameNegativePolarityRejected": sameNegative == nil,
            "eventMappingRejected": wrongMapping == nil,
            "lowerBoundRejected": wrongLowerBound == nil,
            "upperBoundRejected": wrongUpperBound == nil,
            "extraHookRejected": extraHook == nil,
            "sourceBudgetRejected": oversized == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(
        source: String,
        authored: Double = 1,
        keys: [String] = ["value", "script"],
        user: String? = nil,
        timeline: Int? = nil,
        diagnostics: [String] = [],
        target: SceneDynamicTarget = firstTarget
    ) -> SceneMediaPlaybackPlaceholderFadeBinding? {
        SceneMediaPlaybackPlaceholderFadeCompiler.compile(
            value: SceneDocument.ShaderValue(
                rawValue: String(authored),
                valueKind: "binding",
                userBinding: user,
                components: [authored],
                timeline: timeline,
                timelineDiagnostics: diagnostics,
                scriptSource: source,
                bindingKeys: keys
            ),
            target: target
        )
    }

    static func scalar(
        _ values: [SceneDynamicTarget: SceneDynamicValue],
        _ target: SceneDynamicTarget
    ) -> Double {
        guard case let .scalar(value)? = values[target] else { return .nan }
        return value
    }

    static func placeholderSource(
        stoppedOperator: String = "-",
        activeOperator: String = "+",
        playingMapping: Int = 1,
        lowerOperator: String = "<",
        upperBound: Int = 1
    ) -> String {
        """
        'use strict'
        /* Project-owned fixture. Names intentionally differ from the observed stock source. */
        var secondsPerFade = 1
        var resultScale = 1 // scalar result multiplier
        var unusedPlaybackSlot = 0
        var scalarAccumulator = 0
        secondsPerFade = 1 / secondsPerFade
        var playbackBranch = 0

        export function mediaPlaybackChanged(playbackEvent) {
            if (playbackEvent.state == 0) {
                playbackBranch = 0
            } else if (playbackEvent.state == 1) {
                playbackBranch = \(playingMapping)
            } else if (playbackEvent.state == 2) {
                playbackBranch = 2
            } else {
                playbackBranch = 3
            }
        }

        export function update(authoredScalar) {
            if (playbackBranch == 0) {
                scalarAccumulator = scalarAccumulator \(stoppedOperator) (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator \(lowerOperator) 0) {
                    scalarAccumulator = 0
                }
            } else if (playbackBranch == 1) {
                scalarAccumulator = scalarAccumulator \(activeOperator) (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator > \(upperBound)) {
                    scalarAccumulator = 1
                }
            } else if (playbackBranch == 2) {
                scalarAccumulator = scalarAccumulator \(activeOperator) (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator > \(upperBound)) {
                    scalarAccumulator = 1
                }
            }
            return scalarAccumulator * resultScale
        }
        """
    }
}
'''


PROGRAM_COMPILER_HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

enum SceneJSONValue: Equatable {
    case number(Double)

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
}

enum SceneScriptBindingValueType {
    case number
}

struct SceneScriptBindingOwner {
    enum Kind {
        case pass
    }

    let kind: Kind
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
}

enum SceneScriptBindingPathComponent: Equatable {
    case key(String)
    case index(Int)
}

struct SceneScriptBindingIR {
    let source: String
    let owner: SceneScriptBindingOwner
    let targetPath: [SceneScriptBindingPathComponent]
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: SceneScriptBindingValueType

    var targetKey: String {
        guard case let .key(key) = targetPath.last else { return "" }
        return key
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let id: Int?
            let passIndex: Int
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let effectID: Int?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let layerIndex: Int
        let effects: [EffectDescriptor]
    }

    let layers: [Layer]
}

@main
enum ProgramCompilerHarness {
    static let layerID = 7_001
    static let effectID = 7_101
    static let passID = 7_201
    static let authored = 0.0
    static let target = SceneDynamicTarget.effectConstant(
        layerID: layerID,
        effectIndex: 0,
        passIndex: 0,
        name: "alpha"
    )

    static func main() throws {
        let descriptor = makeDescriptor()
        let validBinding = makeBinding()
        let validProgram = compile(descriptor: descriptor, bindings: [validBinding])

        let objectIndexMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(objectIndex: 1)]
        )
        let layerIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(layerID: layerID + 1)]
        )
        let effectIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(effectID: effectID + 1)]
        )
        let passIDMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(passID: passID + 1)]
        )
        let targetPathMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(targetPath: mismatchedPath())]
        )
        let sourceMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(source: placeholderSource() + "\n")]
        )
        let authoredBitPatternMismatch = compile(
            descriptor: descriptor,
            bindings: [makeBinding(authored: -0.0)]
        )
        let duplicateTarget = compile(
            descriptor: descriptor,
            bindings: [validBinding, validBinding]
        )

        let result: [String: Any] = [
            "validPassOwnedCompiled": validProgram?.bindings.count == 1,
            "exactTargetProjected": validProgram?.bindings.first?.definition.target == target,
            "objectIndexMismatchRejected": objectIndexMismatch?.bindings.isEmpty == true,
            "layerIDMismatchRejected": layerIDMismatch?.bindings.isEmpty == true,
            "effectIDMismatchRejected": effectIDMismatch?.bindings.isEmpty == true,
            "passIDMismatchRejected": passIDMismatch?.bindings.isEmpty == true,
            "targetPathMismatchRejected": targetPathMismatch?.bindings.isEmpty == true,
            "sourceMismatchRejected": sourceMismatch?.bindings.isEmpty == true,
            "authoredBitPatternMismatchRejected": authoredBitPatternMismatch?.bindings.isEmpty == true,
            "duplicateExactTargetRejected": duplicateTarget == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func compile(
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptBindingIR]
    ) -> SceneMediaPlaybackPlaceholderFadeProgram? {
        SceneMediaPlaybackPlaceholderFadeProgramCompiler.compile(
            descriptor: descriptor,
            scriptBindings: bindings
        )
    }

    static func makeDescriptor() -> SceneRenderDescriptor {
        SceneRenderDescriptor(layers: [
            .init(
                id: layerID,
                layerIndex: 0,
                effects: [.init(
                    effectID: effectID,
                    passes: [.init(
                        id: passID,
                        passIndex: 0,
                        constantShaderValues: [
                            "alpha": .init(
                                rawValue: String(authored),
                                valueKind: "binding",
                                userBinding: nil,
                                components: [authored],
                                timeline: nil,
                                timelineDiagnostics: [],
                                scriptSource: placeholderSource(),
                                bindingKeys: ["value", "script"]
                            )
                        ]
                    )]
                )]
            )
        ])
    }

    static func makeBinding(
        source: String? = nil,
        authored: Double = authored,
        objectIndex: Int = 0,
        layerID: Int = layerID,
        effectID: Int = effectID,
        passID: Int = passID,
        targetPath: [SceneScriptBindingPathComponent]? = nil
    ) -> SceneScriptBindingIR {
        SceneScriptBindingIR(
            source: source ?? placeholderSource(),
            owner: .init(
                kind: .pass,
                objectIndex: objectIndex,
                objectID: layerID,
                effectIndex: 0,
                effectID: effectID,
                passIndex: 0,
                passID: passID
            ),
            targetPath: targetPath ?? expectedPath(name: "alpha"),
            properties: [:],
            authoredValue: .number(authored),
            valueType: .number
        )
    }

    static func expectedPath(name: String) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(0),
            .key("effects"), .index(0),
            .key("passes"), .index(0),
            .key("constantshadervalues"), .key(name),
        ]
    }

    static func mismatchedPath() -> [SceneScriptBindingPathComponent] {
        [
            .key("object"), .index(0),
            .key("effects"), .index(0),
            .key("passes"), .index(0),
            .key("constantshadervalues"), .key("alpha"),
        ]
    }

    static func placeholderSource() -> String {
        """
        'use strict'
        var secondsPerFade = 1
        var resultScale = 1
        var unusedPlaybackSlot = 0
        var scalarAccumulator = 0
        secondsPerFade = 1 / secondsPerFade
        var playbackBranch = 0

        export function mediaPlaybackChanged(playbackEvent) {
            if (playbackEvent.state == 0) {
                playbackBranch = 0
            } else if (playbackEvent.state == 1) {
                playbackBranch = 1
            } else if (playbackEvent.state == 2) {
                playbackBranch = 2
            } else {
                playbackBranch = 3
            }
        }

        export function update(authoredScalar) {
            if (playbackBranch == 0) {
                scalarAccumulator = scalarAccumulator - (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator < 0) {
                    scalarAccumulator = 0
                }
            } else if (playbackBranch == 1) {
                scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator > 1) {
                    scalarAccumulator = 1
                }
            } else if (playbackBranch == 2) {
                scalarAccumulator = scalarAccumulator + (secondsPerFade * engine.frametime * 2)
                if (scalarAccumulator > 1) {
                    scalarAccumulator = 1
                }
            }
            return scalarAccumulator * resultScale
        }
        """
    }
}
'''


class SceneMediaPlaybackPlaceholderFadeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.tempdir = tempfile.TemporaryDirectory()
        directory = Path(cls.tempdir.name)
        harness = directory / "PlaceholderFadeHarness.swift"
        executable = directory / "placeholder-fade-harness"
        harness.write_text(HARNESS, encoding="utf-8")
        try:
            subprocess.run(
                [swiftc, *map(str, SWIFT_SOURCES), str(harness), "-o", str(executable)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as error:
            raise AssertionError(error.stderr) from error
        output = subprocess.run(
            [str(executable)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        cls.result = json.loads(output)

        program_harness = directory / "PlaceholderFadeProgramCompilerHarness.swift"
        program_executable = directory / "placeholder-fade-program-compiler-harness"
        program_harness.write_text(PROGRAM_COMPILER_HARNESS, encoding="utf-8")
        try:
            subprocess.run(
                [
                    swiftc,
                    *map(str, PROGRAM_COMPILER_SWIFT_SOURCES),
                    str(program_harness),
                    "-o",
                    str(program_executable),
                ],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as error:
            raise AssertionError(error.stderr) from error
        program_output = subprocess.run(
            [str(program_executable)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        cls.program_result = json.loads(program_output)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_project_owned_renamed_comment_and_asi_fixture_compiles(self) -> None:
        self.assertTrue(self.result["renamedCommentedASICompiled"])
        self.assertTrue(self.result["inversePolarityCompiled"])
        self.assertTrue(self.result["activePolarityProjected"])
        self.assertTrue(self.result["stoppedPolarityProjected"])
        self.assertTrue(self.result["programValidated"])

    def test_runtime_preserves_authored_asymmetric_counter_semantics(self) -> None:
        self.assertEqual(self.result["initial"], 0)
        self.assertEqual(self.result["stoppedUnbounded"], 0)
        self.assertAlmostEqual(self.result["playingReset"], 0.2)
        self.assertEqual(self.result["pausedUnbounded"], 1)
        self.assertEqual(self.result["unknownFrozen"], 1)
        self.assertEqual(self.result["stoppedReset"], 1)

    def test_event_is_applied_before_same_frame_update(self) -> None:
        self.assertEqual(self.result["stoppedAdvance"], 0.5)
        self.assertEqual(self.result["eventBeforeUpdate"], 1)
        self.assertEqual(self.result["invalidDeltaFrozen"], 1)

    def test_runtime_preserves_the_inverse_authored_polarity(self) -> None:
        self.assertEqual(self.result["inverseInitial"], 0)
        self.assertEqual(self.result["inverseStopped"], 1.5)
        self.assertEqual(self.result["inversePlaying"], 1)
        self.assertEqual(self.result["inversePaused"], -1)
        self.assertEqual(self.result["inverseUnknown"], -1)
        self.assertEqual(self.result["inverseStoppedReset"], 0)

    def test_non_profile_sources_and_ambiguous_programs_fail_closed(self) -> None:
        keys = [key for key in self.result if key.endswith("Rejected")]
        self.assertGreaterEqual(len(keys), 14)
        self.assertTrue(all(self.result[key] for key in keys), keys)

    def test_program_compiler_projects_only_lossless_pass_owned_ir(self) -> None:
        self.assertTrue(self.program_result["validPassOwnedCompiled"])
        self.assertTrue(self.program_result["exactTargetProjected"])
        rejected = [
            key for key in self.program_result if key.endswith("Rejected")
        ]
        self.assertEqual(len(rejected), 8)
        self.assertTrue(all(self.program_result[key] for key in rejected), rejected)


if __name__ == "__main__":
    unittest.main()
