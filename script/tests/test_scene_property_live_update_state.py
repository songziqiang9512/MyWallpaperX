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
    SOURCE_ROOT / "SceneUserProperty.swift",
    SOURCE_ROOT / "SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "ScenePropertyBindingProgram.swift",
    SOURCE_ROOT / "ScenePropertyBindingProgramValidator.swift",
    SOURCE_ROOT / "ScenePropertyLiveUpdateState.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let alphaOne = SceneDynamicTarget.layer(layerID: 1, field: .alpha)
    static let alphaTwo = SceneDynamicTarget.layer(layerID: 2, field: .alpha)
    static let alphaThree = SceneDynamicTarget.layer(layerID: 3, field: .alpha)
    static let color = SceneDynamicTarget.layer(layerID: 4, field: .color)

    static func main() throws {
        let liveProgram = program(
            bindings: [
                ("opacity", alphaOne, .scalar, .scalar(0.1)),
                ("opacity", alphaTwo, .scalar, .scalar(0.2)),
                ("accentOpacity", alphaThree, .scalar, .scalar(0.3)),
                ("tint", color, .vector3, .vector3(1, 1, 1)),
            ]
        )
        let initialValues: [String: SceneUserPropertyValue] = [
            "opacity": .number(0.5),
            "accentOpacity": .number(0.6),
            "tint": .string("0.1 0.2 0.3"),
        ]
        let alphaTargets: Set<SceneDynamicTarget> = [alphaOne, alphaTwo, alphaThree]
        var state = ScenePropertyLiveUpdateState(
            program: liveProgram,
            effectiveValues: initialValues,
            activeConsumerTargets: alphaTargets.union([color])
        )

        let initialEvaluatedAllTargets = scalar(state, alphaOne) == 0.5
            && scalar(state, alphaTwo) == 0.5
            && scalar(state, alphaThree) == 0.6
            && vector(state, color) == [0.1, 0.2, 0.3]
        let singleAccepted = state.apply(.number(0.75), forPropertyKey: "opacity")
        let singleUpdatedAllTargets = scalar(state, alphaOne) == 0.75
            && scalar(state, alphaTwo) == 0.75
            && vector(state, color) == [0.1, 0.2, 0.3]

        let beforeMissing = state
        let missingRejected = !state.apply(.number(0.4), forPropertyKey: "missing")
        let missingWasAtomic = unchanged(state, from: beforeMissing)

        let beforeTypeFailure = state
        let badTypeRejected = !state.apply(.string("0.2"), forPropertyKey: "opacity")
        let badTypeWasAtomic = unchanged(state, from: beforeTypeFailure)

        let beforeNonFinite = state
        let nonFiniteRejected = !state.apply(.number(.nan), forPropertyKey: "opacity")
        let nonFiniteWasAtomic = unchanged(state, from: beforeNonFinite)

        let colorAccepted = state.apply(.string("0.8 0.7 0.6"), forPropertyKey: "tint")
        let colorUpdated = vector(state, color) == [0.8, 0.7, 0.6]

        let beforeInvalidColor = state
        let invalidColorRejected = !state.apply(.string("0.2 0.4"), forPropertyKey: "tint")
        let invalidColorWasAtomic = unchanged(state, from: beforeInvalidColor)

        let beforeNonFiniteColor = state
        let nonFiniteColorRejected = !state.apply(
            .string("0.2 NaN 0.4"),
            forPropertyKey: "tint"
        )
        let nonFiniteColorWasAtomic = unchanged(state, from: beforeNonFiniteColor)

        let bulkAccepted = state.apply(
            replacements: [
                "opacity": .number(0.25),
                "accentOpacity": .number(0.35),
                "ignoredDefault": .number(99),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let bulkUpdatedAtomically = scalar(state, alphaOne) == 0.25
            && scalar(state, alphaTwo) == 0.25
            && scalar(state, alphaThree) == 0.35
            && state.effectiveValues["ignoredDefault"] == nil

        let beforeBulkFailure = state
        let badBulkRejected = !state.apply(
            replacements: [
                "opacity": .number(0.9),
                "accentOpacity": .string("bad"),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let badBulkWasAtomic = unchanged(state, from: beforeBulkFailure)

        let resetAccepted = state.apply(
            replacements: [
                "opacity": .number(0.5),
                "accentOpacity": .number(0.6),
                "tint": .string("1 1 1"),
            ],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let resetAppliedOnlyChangedKeys = scalar(state, alphaOne) == 0.5
            && scalar(state, alphaThree) == 0.6
            && vector(state, color) == [0.8, 0.7, 0.6]

        let beforeMissingResetDefault = state
        let missingResetDefaultRejected = !state.apply(
            replacements: ["opacity": .number(0.2)],
            changedPropertyKeys: ["opacity", "accentOpacity"]
        )
        let missingResetDefaultWasAtomic = unchanged(state, from: beforeMissingResetDefault)

        let beforeNoOp = state
        let noOpAccepted = state.apply(
            replacements: ["opacity": .number(0.99)],
            changedPropertyKeys: []
        )
        let noOpIgnoredReplacements = unchanged(state, from: beforeNoOp)

        let rebuildProgram = program(
            bindings: [("opacity", alphaOne, .scalar, .scalar(0.1))],
            rebuildRequiredKeys: ["opacity"]
        )
        var rebuildState = ScenePropertyLiveUpdateState(
            program: rebuildProgram,
            effectiveValues: ["opacity": .number(0.5)],
            activeConsumerTargets: [alphaOne]
        )
        let beforeRebuild = rebuildState
        let rebuildRejected = !rebuildState.apply(.number(0.8), forPropertyKey: "opacity")
        let rebuildWasAtomic = unchanged(rebuildState, from: beforeRebuild)

        let mixedProgram = program(bindings: [
            ("mixed", alphaOne, .scalar, .scalar(0.1)),
            ("mixed", color, .vector3, .vector3(1, 1, 1)),
        ], rebuildRequiredKeys: ["mixed"])
        var mixedState = ScenePropertyLiveUpdateState(
            program: mixedProgram,
            effectiveValues: ["mixed": .number(0.5)],
            activeConsumerTargets: [alphaOne, color]
        )
        let beforeMixed = mixedState
        let mixedRejected = !mixedState.apply(.number(0.7), forPropertyKey: "mixed")
        let mixedWasAtomic = unchanged(mixedState, from: beforeMixed)

        let payload: [String: Bool] = [
            "initialEvaluatedAllTargets": initialEvaluatedAllTargets,
            "singleAccepted": singleAccepted,
            "singleUpdatedAllTargets": singleUpdatedAllTargets,
            "missingRejected": missingRejected,
            "missingWasAtomic": missingWasAtomic,
            "badTypeRejected": badTypeRejected,
            "badTypeWasAtomic": badTypeWasAtomic,
            "nonFiniteRejected": nonFiniteRejected,
            "nonFiniteWasAtomic": nonFiniteWasAtomic,
            "colorAccepted": colorAccepted,
            "colorUpdated": colorUpdated,
            "invalidColorRejected": invalidColorRejected,
            "invalidColorWasAtomic": invalidColorWasAtomic,
            "nonFiniteColorRejected": nonFiniteColorRejected,
            "nonFiniteColorWasAtomic": nonFiniteColorWasAtomic,
            "bulkAccepted": bulkAccepted,
            "bulkUpdatedAtomically": bulkUpdatedAtomically,
            "badBulkRejected": badBulkRejected,
            "badBulkWasAtomic": badBulkWasAtomic,
            "resetAccepted": resetAccepted,
            "resetAppliedOnlyChangedKeys": resetAppliedOnlyChangedKeys,
            "missingResetDefaultRejected": missingResetDefaultRejected,
            "missingResetDefaultWasAtomic": missingResetDefaultWasAtomic,
            "noOpAccepted": noOpAccepted,
            "noOpIgnoredReplacements": noOpIgnoredReplacements,
            "rebuildRejected": rebuildRejected,
            "rebuildWasAtomic": rebuildWasAtomic,
            "mixedRejected": mixedRejected,
            "mixedWasAtomic": mixedWasAtomic,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func program(
        bindings: [(String, SceneDynamicTarget, SceneDynamicValueType, SceneDynamicValue)],
        rebuildRequiredKeys: [String] = []
    ) -> ScenePropertyBindingProgram {
        ScenePropertyBindingProgram(
            definitions: bindings.map {
                .init(target: $0.1, valueType: $0.2, authoredValue: $0.3)
            },
            instructions: bindings.map {
                .init(
                    propertyKey: $0.0,
                    path: .init(components: [.key($0.0)]),
                    target: $0.1,
                    valueType: $0.2
                )
            },
            rebuildRequiredPropertyKeys: rebuildRequiredKeys
        )
    }

    static func scalar(
        _ state: ScenePropertyLiveUpdateState,
        _ target: SceneDynamicTarget
    ) -> Double? {
        guard case let .scalar(value) = state.userValues[target] else { return nil }
        return value
    }

    static func vector(
        _ state: ScenePropertyLiveUpdateState,
        _ target: SceneDynamicTarget
    ) -> [Double]? {
        guard case let .vector3(x, y, z) = state.userValues[target] else { return nil }
        return [x, y, z]
    }

    static func unchanged(
        _ state: ScenePropertyLiveUpdateState,
        from before: ScenePropertyLiveUpdateState
    ) -> Bool {
        state.effectiveValues == before.effectiveValues
            && state.userValues == before.userValues
    }
}
'''


class ScenePropertyLiveUpdateStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-live-state-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-property-live-update-state"
        compilation = subprocess.run(
            ["swiftc", *(str(path) for path in SWIFT_SOURCES), str(harness), "-o", str(binary)],
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

    def test_initialization_and_single_key_fan_out(self) -> None:
        self.assertTrue(self.result["initialEvaluatedAllTargets"])
        self.assertTrue(self.result["singleAccepted"])
        self.assertTrue(self.result["singleUpdatedAllTargets"])

    def test_missing_instruction_and_invalid_values_fail_atomically(self) -> None:
        self.assertTrue(self.result["missingRejected"])
        self.assertTrue(self.result["missingWasAtomic"])
        self.assertTrue(self.result["badTypeRejected"])
        self.assertTrue(self.result["badTypeWasAtomic"])
        self.assertTrue(self.result["nonFiniteRejected"])
        self.assertTrue(self.result["nonFiniteWasAtomic"])

    def test_active_color_target_accepts_only_finite_vector3_strings(self) -> None:
        self.assertTrue(self.result["colorAccepted"])
        self.assertTrue(self.result["colorUpdated"])
        self.assertTrue(self.result["invalidColorRejected"])
        self.assertTrue(self.result["invalidColorWasAtomic"])
        self.assertTrue(self.result["nonFiniteColorRejected"])
        self.assertTrue(self.result["nonFiniteColorWasAtomic"])

    def test_bulk_updates_and_reset_only_change_requested_keys(self) -> None:
        self.assertTrue(self.result["bulkAccepted"])
        self.assertTrue(self.result["bulkUpdatedAtomically"])
        self.assertTrue(self.result["resetAccepted"])
        self.assertTrue(self.result["resetAppliedOnlyChangedKeys"])
        self.assertTrue(self.result["noOpAccepted"])
        self.assertTrue(self.result["noOpIgnoredReplacements"])

    def test_bulk_failure_and_missing_reset_default_are_atomic(self) -> None:
        self.assertTrue(self.result["badBulkRejected"])
        self.assertTrue(self.result["badBulkWasAtomic"])
        self.assertTrue(self.result["missingResetDefaultRejected"])
        self.assertTrue(self.result["missingResetDefaultWasAtomic"])

    def test_rebuild_required_keys_are_rejected_with_all_consumers_active(self) -> None:
        self.assertTrue(self.result["rebuildRejected"])
        self.assertTrue(self.result["rebuildWasAtomic"])
        self.assertTrue(self.result["mixedRejected"])
        self.assertTrue(self.result["mixedWasAtomic"])


if __name__ == "__main__":
    unittest.main()
