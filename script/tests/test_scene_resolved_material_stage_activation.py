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
SWIFT_SOURCES = [
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialStageActivation.swift",
]
ELIGIBILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialColorBlendEligibility.swift"
)
CAPABILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+Stages.swift"
)

HARNESS = r'''
import Foundation

@main
enum Harness {
    static let target = SceneDynamicTarget.effectVisibility(
        layerID: 42,
        effectIndex: 3
    )

    static func snapshot(
        type: SceneDynamicValueType,
        authored: SceneDynamicValue,
        user: SceneDynamicValue? = nil
    ) -> SceneDynamicSnapshot {
        SceneDynamicSnapshotResolver().resolve(
            frameIndex: 7,
            generation: 9,
            definitions: [.init(
                target: target,
                valueType: type,
                authoredValue: authored
            )],
            userValues: user.map { [target: $0] } ?? [:]
        ).snapshot
    }

    static func label(
        _ decision: SceneResolvedMaterialStageActivationPolicy.Decision
    ) -> String {
        switch decision {
        case .active: "active"
        case let .inactive(reason): "inactive:\(reason)"
        case let .rejected(reason): "rejected:\(reason)"
        }
    }

    static func main() throws {
        let visibility = SceneResolvedMaterialStageActivationPolicy(
            effectVisibilityTarget: target,
            requiresPointerPositionProvider: false,
            scalarMinimum: nil
        )
        let pointer = SceneResolvedMaterialStageActivationPolicy(
            effectVisibilityTarget: nil,
            requiresPointerPositionProvider: true,
            scalarMinimum: nil
        )
        let combined = SceneResolvedMaterialStageActivationPolicy(
            effectVisibilityTarget: target,
            requiresPointerPositionProvider: true,
            scalarMinimum: nil
        )
        let sizeTarget = SceneDynamicTarget.effectConstant(
            layerID: 42,
            effectIndex: 3,
            passIndex: 0,
            name: "size"
        )
        let sized = SceneResolvedMaterialStageActivationPolicy(
            effectVisibilityTarget: nil,
            requiresPointerPositionProvider: false,
            scalarMinimum: .init(
                target: sizeTarget,
                authoredFallback: 0.16,
                authoredRange: 0 ... 1,
                minimum: 0.001
            )
        )
        let payload = [
            "fallbackActive": label(visibility.evaluate(
                dynamicValues: .empty(frameIndex: 1),
                pointerIsInside: false
            )),
            "visibleActive": label(visibility.evaluate(
                dynamicValues: snapshot(type: .bool, authored: .bool(true)),
                pointerIsInside: false
            )),
            "hiddenInactive": label(visibility.evaluate(
                dynamicValues: snapshot(
                    type: .bool,
                    authored: .bool(true),
                    user: .bool(false)
                ),
                pointerIsInside: true
            )),
            "pointerInside": label(pointer.evaluate(
                dynamicValues: .empty(frameIndex: 1),
                pointerIsInside: true
            )),
            "pointerOutside": label(pointer.evaluate(
                dynamicValues: .empty(frameIndex: 1),
                pointerIsInside: false
            )),
            "visibilityPrecedesPointer": label(combined.evaluate(
                dynamicValues: snapshot(
                    type: .bool,
                    authored: .bool(false)
                ),
                pointerIsInside: false
            )),
            "wrongTypeRejected": label(visibility.evaluate(
                dynamicValues: snapshot(
                    type: .scalar,
                    authored: .scalar(1)
                ),
                pointerIsInside: true
            )),
            "smallSizeInactive": label(sized.evaluate(
                dynamicValues: SceneDynamicSnapshotResolver().resolve(
                    frameIndex: 7,
                    generation: 9,
                    definitions: [.init(
                        target: sizeTarget,
                        valueType: .scalar,
                        authoredValue: .scalar(0.16)
                    )],
                    userValues: [sizeTarget: .scalar(0)]
                ).snapshot,
                pointerIsInside: true
            )),
            "negativeSizeUsesAuthoredFallback": label(sized.evaluate(
                dynamicValues: SceneDynamicSnapshotResolver().resolve(
                    frameIndex: 7,
                    generation: 9,
                    definitions: [.init(
                        target: sizeTarget,
                        valueType: .scalar,
                        authoredValue: .scalar(0.16)
                    )],
                    userValues: [sizeTarget: .scalar(-0.5)]
                ).snapshot,
                pointerIsInside: true
            )),
            "oversizedUsesAuthoredFallback": label(sized.evaluate(
                dynamicValues: SceneDynamicSnapshotResolver().resolve(
                    frameIndex: 7,
                    generation: 9,
                    definitions: [.init(
                        target: sizeTarget,
                        valueType: .scalar,
                        authoredValue: .scalar(0.16)
                    )],
                    userValues: [sizeTarget: .scalar(1.5)]
                ).snapshot,
                pointerIsInside: true
            )),
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
class SceneResolvedMaterialStageActivationTests(unittest.TestCase):
    def test_provider_backed_pointer_stage_reuses_exact_passthrough_contract(
        self,
    ) -> None:
        eligibility = ELIGIBILITY_SOURCE.read_text(encoding="utf-8")
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            ".providerBackedGraphInputSpatialWeightedColorBlend.rawValue",
            eligibility,
        )
        self.assertIn(
            "dependencyOwnership.preEncodeVisualFailureSlots(",
            capability,
        )
        self.assertNotIn(
            "guard dependencyOwnership == .none",
            capability,
        )

    def test_typed_visibility_and_pointer_provider_activation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-stage-activation-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "stage-activation"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            if compilation.returncode != 0:
                self.fail(compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertEqual(result["fallbackActive"], "active")
        self.assertEqual(result["visibleActive"], "active")
        self.assertEqual(
            result["hiddenInactive"],
            "inactive:effect-activation-visibility-disabled",
        )
        self.assertEqual(result["pointerInside"], "active")
        self.assertEqual(
            result["pointerOutside"],
            "inactive:effect-activation-pointer-provider-unavailable",
        )
        self.assertEqual(
            result["visibilityPrecedesPointer"],
            "inactive:effect-activation-visibility-disabled",
        )
        self.assertEqual(
            result["wrongTypeRejected"],
            "rejected:effect-activation-visibility-type-invalid",
        )
        self.assertEqual(
            result["smallSizeInactive"],
            "inactive:effect-activation-scalar-below-minimum",
        )
        self.assertEqual(result["negativeSizeUsesAuthoredFallback"], "active")
        self.assertEqual(result["oversizedUsesAuthoredFallback"], "active")


if __name__ == "__main__":
    unittest.main()
