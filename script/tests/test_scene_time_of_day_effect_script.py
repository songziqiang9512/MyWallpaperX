#!/usr/bin/env python3

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
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptProgram.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptCompiler.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptProgramCompiler.swift",
    SOURCE_ROOT / "Properties/SceneTimeOfDayEffectScriptRuntime.swift",
]

HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let userValueKind: SceneShaderUserValueKind?
        let components: [Double]?
        let timeline: Int?
        let timelineDiagnostics: [String]
        let scriptSource: String?
        let bindingKeys: [String]
    }
}

enum SceneShaderUserValueKind {
    case null
    case number
    case string
}

struct SceneRenderDescriptor {
    struct Pass {
        let passIndex: Int
        let constantShaderValues: [String: SceneDocument.ShaderValue]
    }

    struct Effect {
        let passes: [Pass]
    }

    struct Layer {
        let id: Int
        let layerIndex: Int
        let effects: [Effect]
    }

    let layers: [Layer]
}

@main
enum Harness {
    static let target = SceneDynamicTarget.effectConstant(
        layerID: 42, effectIndex: 1, passIndex: 0, name: "multiply"
    )

    static func main() throws {
        let cyclic = binding(source: cyclicSource)
        let interval = binding(source: intervalSource)
        let invalidCall = binding(source: cyclicSource.replacingOccurrences(
            of: "Math.max", with: "Math.min"
        ))
        let extraFunction = binding(source: cyclicSource + "\nfunction hidden() { return 1; }")
        let wrongWrapper = binding(source: cyclicSource, keys: ["script", "value"])
        let userBound = binding(source: cyclicSource, user: "mode")
        let numericUser = binding(source: cyclicSource, userValueKind: .number)
        let malformed = binding(source: "export function update(value) { return 1; }")
        let oversizedSource =
            "/*" + String(repeating: " ", count: 16_385) + "*/\n" + cyclicSource
        let oversized = binding(source: oversizedSource)
        let commentedSource = cyclicSource.replacingOccurrences(
            of: "const MORNING = 7;",
            with: "/** author formatting must not select identity */\nconst MORNING = 7;"
        )
        let commented = binding(source: commentedSource)
        let sharedProgram = program(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: descriptor(constants: [
                "multiply": shaderValue(source: commentedSource),
                "renamedGain": shaderValue(source: commentedSource),
                "unsupported": shaderValue(
                    source: cyclicSource,
                    keys: ["script", "value"]
                ),
                ])
            )
        )
        let invalidLayerResult = SceneTimeOfDayEffectScriptProgramCompiler.compile(
            descriptor: descriptor(
                layerID: 42,
                layerIndex: 1,
                constants: ["renamedGain": shaderValue(source: cyclicSource)]
            )
        )
        let invalidPassResult = SceneTimeOfDayEffectScriptProgramCompiler.compile(
            descriptor: descriptor(
                passIndex: 1,
                constants: ["multiply": shaderValue(source: cyclicSource)]
            )
        )
        let sharedCohortProgram = program(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: .init(layers: [
                .init(id: 42, layerIndex: 0, effects: [
                    .init(passes: [.init(
                        passIndex: 0,
                        constantShaderValues: [
                            "multiply": shaderValue(source: cyclicSource),
                        ]
                    )]),
                    .init(passes: [.init(
                        passIndex: 0,
                        constantShaderValues: [
                            "multiply": shaderValue(source: intervalSource),
                        ]
                    )]),
                ]),
                .init(id: 77, layerIndex: 1, effects: [
                    .init(passes: [.init(
                        passIndex: 0,
                        constantShaderValues: [
                            "multiply": shaderValue(source: commentedSource),
                        ]
                    )]),
                    .init(passes: [.init(
                        passIndex: 0,
                        constantShaderValues: [
                            "multiply": shaderValue(source: intervalSource),
                        ]
                    )]),
                ]),
                ])
            )
        )

        let exactBudgetDescriptor = twoCandidateDescriptor(
            first: shaderValue(source: cyclicSource),
            second: shaderValue(source: intervalSource)
        )
        let exactSourceBytes = cyclicSource.utf8.count + intervalSource.utf8.count
        let exactBudgetLimits = limits(sourceBytes: exactSourceBytes)
        let exactBudgetProgram = program(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: exactBudgetLimits
            )
        )
        let layerBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(layers: 1, sourceBytes: exactSourceBytes)
            )
        )
        let effectBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(effects: 1, sourceBytes: exactSourceBytes)
            )
        )
        let passBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(passes: 1, sourceBytes: exactSourceBytes)
            )
        )
        let constantBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(constants: 3, sourceBytes: exactSourceBytes)
            )
        )
        let multiplyBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(multiplyCandidates: 1, sourceBytes: exactSourceBytes)
            )
        )
        let scriptBudgetFailure = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: exactBudgetDescriptor,
                limits: limits(scriptCandidates: 1, sourceBytes: exactSourceBytes)
            )
        )
        let sourceBudgetResult = SceneTimeOfDayEffectScriptProgramCompiler.compile(
            descriptor: exactBudgetDescriptor,
            limits: limits(sourceBytes: exactSourceBytes - 1)
        )
        let sourceBudgetFailure = failureCode(sourceBudgetResult)
        let sourceBudgetDiagnostic = failureDiagnostic(sourceBudgetResult)
        let oversizedSourceBudgetResult =
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: descriptor(constants: [
                    "multiply": shaderValue(source: oversizedSource),
                ])
            )
        let oversizedSourceBudgetFailure = failureCode(
            oversizedSourceBudgetResult
        )
        let oversizedSourceBudgetDiagnostic = failureDiagnostic(
            oversizedSourceBudgetResult
        )
        let unsupportedDescriptor = twoCandidateDescriptor(
            first: shaderValue(source: cyclicSource),
            second: shaderValue(source: intervalSource, keys: ["script", "value"])
        )
        let unsupportedWithinBudgetProgram = program(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: unsupportedDescriptor,
                limits: exactBudgetLimits
            )
        )
        let unsupportedStillConsumesBudget = failureCode(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: unsupportedDescriptor,
                limits: limits(scriptCandidates: 1, sourceBytes: exactSourceBytes)
            )
        )
        let noCandidateProgram = program(
            SceneTimeOfDayEffectScriptProgramCompiler.compile(
                descriptor: twoCandidateDescriptor(
                    first: shaderValue(source: cyclicSource),
                    second: shaderValue(source: intervalSource),
                    candidateName: "renamedGain"
                ),
                limits: limits(
                    multiplyCandidates: 0,
                    scriptCandidates: 0,
                    sourceBytes: 0
                )
            )
        )
        let candidateBindings = [cyclic].compactMap { $0 }
        let noConsumerConflictIgnored =
            SceneTimeOfDayEffectScriptProgram.validatedConsumers(
                candidates: candidateBindings,
                consumerTargets: [],
                conflictingTargets: [target]
            )?.bindings.isEmpty == true
        let liveConsumerConflictRejected =
            SceneTimeOfDayEffectScriptProgram.validatedConsumers(
                candidates: candidateBindings,
                consumerTargets: [target],
                conflictingTargets: [target]
            ) == nil
        let liveConsumerWithoutConflictAccepted =
            SceneTimeOfDayEffectScriptProgram.validatedConsumers(
                candidates: candidateBindings,
                consumerTargets: [target],
                conflictingTargets: []
            )?.bindings.count == 1

        let utc = TimeZone(secondsFromGMT: 0)!
        let cyclicProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: [cyclic].compactMap { $0 }
        )
        let intervalProgram = SceneTimeOfDayEffectScriptProgram(
            bindings: [interval].compactMap { $0 }
        )
        let cyclicValues = [6, 7, 12, 18, 20].map {
            scalar(SceneTimeOfDayEffectScriptRuntime.values(
                program: cyclicProgram, wallDate: date(hour: $0), timeZone: utc
            ))
        }
        let intervalValues = [6, 8, 12, 18, 20].map {
            scalar(SceneTimeOfDayEffectScriptRuntime.values(
                program: intervalProgram, wallDate: date(hour: $0), timeZone: utc
            ))
        }
        let result: [String: Any] = [
            "cyclicCompiled": cyclic != nil,
            "intervalCompiled": interval != nil,
            "invalidCallRejected": invalidCall == nil,
            "extraFunctionRejected": extraFunction == nil,
            "wrongWrapperRejected": wrongWrapper == nil,
            "userBindingRejected": userBound == nil,
            "nonNullUserRejected": numericUser == nil,
            "malformedRejected": malformed == nil,
            "oversizedSourceRejected": oversized == nil,
            "commentedSourceCompiled": commented != nil,
            "cyclicValues": cyclicValues,
            "intervalValues": intervalValues,
            "targetPreserved": cyclic?.definition.target == target,
            "sharedProgramIsIdentityFree": sharedProgram?.bindings.map {
                $0.definition.target
            } == [.effectConstant(
                layerID: 42,
                effectIndex: 0,
                passIndex: 0,
                name: "multiply"
            )],
            "invalidDescriptorRejected": failureCode(invalidLayerResult)
                == "invalid-layer-identity",
            "invalidPassRejected": failureCode(invalidPassResult)
                == "invalid-pass-identity",
            "sharedCohortCollected": sharedCohortProgram?.bindings.count == 4,
            "exactAggregateBudgetAccepted": exactBudgetProgram?.bindings.count == 2,
            "layerBudgetFailure": layerBudgetFailure,
            "effectBudgetFailure": effectBudgetFailure,
            "passBudgetFailure": passBudgetFailure,
            "constantBudgetFailure": constantBudgetFailure,
            "multiplyBudgetFailure": multiplyBudgetFailure,
            "scriptBudgetFailure": scriptBudgetFailure,
            "sourceBudgetFailure": sourceBudgetFailure,
            "sourceBudgetDiagnostic": sourceBudgetDiagnostic,
            "oversizedSourceBudgetFailure": oversizedSourceBudgetFailure,
            "oversizedSourceBudgetDiagnostic": oversizedSourceBudgetDiagnostic,
            "unsupportedSiblingSkippedWithinBudget":
                unsupportedWithinBudgetProgram?.bindings.count == 1,
            "unsupportedStillConsumesBudget": unsupportedStillConsumesBudget,
            "noCandidateSucceedsEmpty": noCandidateProgram?.bindings.isEmpty == true,
            "budgetFailuresAreProducerLocal": [
                SceneTimeOfDayEffectScriptProgramCompiler.Failure(
                    .layerBudgetExceeded
                ),
                .init(.effectBudgetExceeded),
                .init(.passBudgetExceeded),
                .init(.constantBudgetExceeded),
                .init(.multiplyCandidateBudgetExceeded),
                .init(.scriptCandidateBudgetExceeded),
                .init(.sourceBudgetExceeded),
                .init(.aggregateSourceBudgetExceeded),
            ].allSatisfy { !$0.isDescriptorIntegrityFailure },
            "descriptorFailuresInvalidateLaunch": [
                SceneTimeOfDayEffectScriptProgramCompiler.Failure(
                    .invalidLayerIdentity
                ),
                .init(.invalidPassIdentity),
                .init(.duplicateTarget),
            ].allSatisfy(\.isDescriptorIntegrityFailure),
            "noConsumerConflictIgnored": noConsumerConflictIgnored,
            "liveConsumerConflictRejected": liveConsumerConflictRejected,
            "liveConsumerWithoutConflictAccepted":
                liveConsumerWithoutConflictAccepted,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func binding(
        source: String,
        keys: [String] = ["script", "user", "value"],
        user: String? = nil,
        userValueKind: SceneShaderUserValueKind? = nil
    ) -> SceneTimeOfDayEffectScriptBinding? {
        SceneTimeOfDayEffectScriptCompiler.compile(
            value: shaderValue(
                source: source,
                keys: keys,
                user: user,
                userValueKind: userValueKind
            ),
            target: target
        )
    }

    static func shaderValue(
        source: String,
        keys: [String] = ["script", "user", "value"],
        user: String? = nil,
        userValueKind: SceneShaderUserValueKind? = nil
    ) -> SceneDocument.ShaderValue {
        .init(
            rawValue: "1", valueKind: "binding", userBinding: user,
            userValueKind: userValueKind
                ?? (user == nil && keys.contains("user") ? .null : nil),
            components: [1], timeline: nil, timelineDiagnostics: [],
            scriptSource: source, bindingKeys: keys
        )
    }

    static func descriptor(
        layerID: Int = 42,
        layerIndex: Int = 0,
        passIndex: Int = 0,
        constants: [String: SceneDocument.ShaderValue]
    ) -> SceneRenderDescriptor {
        .init(layers: [.init(
            id: layerID,
            layerIndex: layerIndex,
            effects: [.init(passes: [.init(
                passIndex: passIndex,
                constantShaderValues: constants
            )])]
        )])
    }

    static func twoCandidateDescriptor(
        first: SceneDocument.ShaderValue,
        second: SceneDocument.ShaderValue,
        candidateName: String = "multiply"
    ) -> SceneRenderDescriptor {
        .init(layers: [
            .init(id: 42, layerIndex: 0, effects: [
                .init(passes: [.init(
                    passIndex: 0,
                    constantShaderValues: [
                        candidateName: first,
                        "unrelated": shaderValue(source: cyclicSource),
                    ]
                )]),
            ]),
            .init(id: 77, layerIndex: 1, effects: [
                .init(passes: [.init(
                    passIndex: 0,
                    constantShaderValues: [
                        candidateName: second,
                        "unrelated": shaderValue(source: intervalSource),
                    ]
                )]),
            ]),
        ])
    }

    static func limits(
        layers: Int = 2,
        effects: Int = 2,
        passes: Int = 2,
        constants: Int = 4,
        multiplyCandidates: Int = 2,
        scriptCandidates: Int = 2,
        sourceBytes: Int
    ) -> SceneTimeOfDayEffectScriptProgramCompiler.Limits {
        .init(
            maximumLayerCount: layers,
            maximumEffectCount: effects,
            maximumPassCount: passes,
            maximumConstantShaderValueCount: constants,
            maximumMultiplyCandidateCount: multiplyCandidates,
            maximumScriptCandidateCount: scriptCandidates,
            maximumAggregateSourceUTF8ByteCount: sourceBytes
        )
    }

    static func program(
        _ result: Result<
            SceneTimeOfDayEffectScriptProgram,
            SceneTimeOfDayEffectScriptProgramCompiler.Failure
        >
    ) -> SceneTimeOfDayEffectScriptProgram? {
        guard case let .success(program) = result else { return nil }
        return program
    }

    static func failureCode(
        _ result: Result<
            SceneTimeOfDayEffectScriptProgram,
            SceneTimeOfDayEffectScriptProgramCompiler.Failure
        >
    ) -> String {
        guard case let .failure(failure) = result else { return "none" }
        return failure.code.rawValue
    }

    static func failureDiagnostic(
        _ result: Result<
            SceneTimeOfDayEffectScriptProgram,
            SceneTimeOfDayEffectScriptProgramCompiler.Failure
        >
    ) -> String {
        guard case let .failure(failure) = result else { return "none" }
        return failure.diagnostic
    }

    static func scalar(_ values: [SceneDynamicTarget: SceneDynamicValue]) -> Double {
        guard case let .scalar(value)? = values[target] else { return -1 }
        return value
    }

    static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = hour
        return components.date!
    }

    static let cyclicSource = """
    'use strict';
    import * as WEMath from 'WEMath';
    const MORNING = 7;
    const EVENING = 18;
    export function update(value) {
        return Math.max(
            WEMath.smoothStep(MORNING / 24, (MORNING - 0.004) / 24, engine.timeOfDay),
            WEMath.smoothStep((EVENING - 0.004) / 24, EVENING / 24, engine.timeOfDay)
        );
    }
    """

    static let intervalSource = """
    'use strict';
    import * as WEMath from 'WEMath';
    const OPEN = 7;
    const CLOSE = 18;
    const FADE = 0.004;
    export function update(value) {
        return WEMath.smoothStep((OPEN - FADE) / 24, OPEN / 24, engine.timeOfDay)
            * WEMath.smoothStep(CLOSE / 24, (CLOSE - FADE) / 24, engine.timeOfDay);
    }
    """
}
'''


class SceneTimeOfDayEffectScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-time-of-day-effect-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        binary = root / "time-of-day-effect"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_documented_time_of_day_expression_shapes_are_bounded(self) -> None:
        self.assertTrue(self.result["cyclicCompiled"])
        self.assertTrue(self.result["intervalCompiled"])
        self.assertEqual(self.result["cyclicValues"], [1, 0, 0, 1, 1])
        self.assertEqual(self.result["intervalValues"], [0, 1, 1, 0, 0])
        self.assertTrue(self.result["targetPreserved"])

    def test_shared_program_discovery_uses_typed_source_shape_not_effect_identity(self) -> None:
        self.assertTrue(self.result["sharedProgramIsIdentityFree"])
        self.assertTrue(self.result["invalidDescriptorRejected"])
        self.assertTrue(self.result["invalidPassRejected"])
        self.assertTrue(self.result["sharedCohortCollected"])
        self.assertTrue(self.result["commentedSourceCompiled"])

    def test_unknown_syntax_and_wrapper_mutations_fail_closed(self) -> None:
        for key in [
            "invalidCallRejected", "extraFunctionRejected", "wrongWrapperRejected",
            "userBindingRejected", "nonNullUserRejected", "malformedRejected",
            "oversizedSourceRejected",
        ]:
            self.assertTrue(self.result[key], key)

    def test_descriptor_scan_and_candidate_work_are_aggregate_bounded(self) -> None:
        self.assertTrue(self.result["exactAggregateBudgetAccepted"])
        self.assertEqual(self.result["layerBudgetFailure"], "layer-budget-exceeded")
        self.assertEqual(self.result["effectBudgetFailure"], "effect-budget-exceeded")
        self.assertEqual(self.result["passBudgetFailure"], "pass-budget-exceeded")
        self.assertEqual(
            self.result["constantBudgetFailure"], "constant-budget-exceeded"
        )
        self.assertEqual(
            self.result["multiplyBudgetFailure"],
            "multiply-candidate-budget-exceeded",
        )
        self.assertEqual(
            self.result["scriptBudgetFailure"],
            "script-candidate-budget-exceeded",
        )
        self.assertEqual(
            self.result["sourceBudgetFailure"],
            "aggregate-source-budget-exceeded",
        )
        self.assertRegex(
            self.result["sourceBudgetDiagnostic"],
            r"^aggregate-source-budget-exceeded observed=\d+ limit=\d+$",
        )
        self.assertEqual(
            self.result["oversizedSourceBudgetFailure"],
            "source-budget-exceeded",
        )
        self.assertEqual(
            self.result["oversizedSourceBudgetDiagnostic"],
            "source-budget-exceeded observed=16385 limit=16384",
        )

    def test_unsupported_candidates_count_but_no_candidate_succeeds_empty(self) -> None:
        self.assertTrue(self.result["unsupportedSiblingSkippedWithinBudget"])
        self.assertEqual(
            self.result["unsupportedStillConsumesBudget"],
            "script-candidate-budget-exceeded",
        )
        self.assertTrue(self.result["noCandidateSucceedsEmpty"])
        self.assertTrue(self.result["budgetFailuresAreProducerLocal"])
        self.assertTrue(self.result["descriptorFailuresInvalidateLaunch"])
        self.assertTrue(self.result["noConsumerConflictIgnored"])
        self.assertTrue(self.result["liveConsumerConflictRejected"])
        self.assertTrue(self.result["liveConsumerWithoutConflictAccepted"])


if __name__ == "__main__":
    unittest.main()
