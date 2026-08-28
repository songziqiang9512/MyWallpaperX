#!/usr/bin/env python3

"""Full Program-first owner conservation for authored scalar fallback targets."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests import test_scene_resolved_material_execution_capability as base


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def replace_once(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"owner conservation harness marker drifted: {old[:80]!r}")
    return source.replace(old, new, 1)


def owner_conservation_sources() -> tuple[str, str]:
    support = replace_once(
        base.SUPPORT,
        """struct SceneXRayExecutionPlan {}
struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var xRay: SceneXRayExecutionPlan? = nil
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedHistoryTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var pulse: HarnessDedicatedAudioExecutionPlan? { nil }
    var liveConsumerTargets: Set<SceneDynamicTarget> { [] }
}
""",
        """struct SceneXRayExecutionPlan {}
struct HarnessDedicatedAudioExecutionPlan { let audio: Bool? }

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var fixtureLiveConsumerTargets: Set<SceneDynamicTarget> = []
    var xRay: SceneXRayExecutionPlan? = nil
    var supportsUnifiedLogicalTargetStage = false
    var supportsUnifiedHistoryTargetStage = false
    var supportsUnifiedFullFrameComposeStage = false
    var supportsUtilityCapture = true
    var shake: HarnessDedicatedAudioExecutionPlan? { nil }
    var fixturePulse: HarnessDedicatedAudioExecutionPlan? = nil
    var pulse: HarnessDedicatedAudioExecutionPlan? { fixturePulse }
    var liveConsumerTargets: Set<SceneDynamicTarget> {
        fixtureLiveConsumerTargets
    }
}
""",
    )
    harness = replace_once(
        base.HARNESS,
        """    supportsUtilityCapture: Bool = false
) -> SceneEffectStageProgram {
""",
        """    supportsUtilityCapture: Bool = false,
    liveConsumerTargets: Set<SceneDynamicTarget> = [],
    fallbackOwner: String? = nil
) -> SceneEffectStageProgram {
""",
    )
    harness = replace_once(
        harness,
        """            inputRole: inputRole,
            supportsUnifiedLogicalTargetStage: logicalTargetStage,
            supportsUnifiedFullFrameComposeStage: fullFrameComposeStage,
            supportsUtilityCapture: supportsUtilityCapture
""",
        """            inputRole: inputRole,
            fixtureLiveConsumerTargets: liveConsumerTargets,
            xRay: fallbackOwner == "xray" ? .init() : nil,
            supportsUnifiedLogicalTargetStage: logicalTargetStage,
            supportsUnifiedFullFrameComposeStage: fullFrameComposeStage,
            supportsUtilityCapture: supportsUtilityCapture,
            fixturePulse: fallbackOwner == "pulse" ? .init(audio: nil) : nil
""",
    )
    harness = replace_once(
        harness,
        """        let fallbackDedicatedLeafCatalog = Catalog(
""",
        """        func missingProducerDedicatedCatalog(
            fallbackOwner: String?
        ) -> Catalog {
            let program = dedicatedProgram(
                graph: pairGraph,
                effectIndex: 0,
                inputRole: .layerSource,
                liveConsumerTargets: [dynamicTarget()],
                fallbackOwner: fallbackOwner
            )
            let candidates =
                SceneResolvedMaterialExecutionCapabilityAdmission.compile(
                    descriptor: pairDescriptor,
                    authoredPlans: [pairGraph],
                    dedicatedStagePrograms: [program]
                )
            return Catalog(
                admissionCandidates: candidates,
                materialCatalog: materialCatalog(graph: pairGraph, omitNode: 0),
                dedicatedStageFamilies: [firstKey: "fixture-dedicated"],
                dedicatedLeafKeys: [firstKey]
            )
        }
        let pulseMissingProducer = missingProducerDedicatedCatalog(
            fallbackOwner: "pulse"
        )
        let xRayMissingProducer = missingProducerDedicatedCatalog(
            fallbackOwner: "xray"
        )
        let requiredLiveMissingProducer = missingProducerDedicatedCatalog(
            fallbackOwner: nil
        )
        let directUniforms = [0: [dynamicUniform(
            contributors: [.userProperty("strength-property")],
            directComponentCount: 1
        )]]
        func ordinaryFallbackCatalog(
            producers: Set<SceneDynamicUserPropertyProducer>
        ) -> Catalog {
            catalog(
                descriptor: pairDescriptor,
                graphs: [pairGraph],
                materials: materialCatalog(
                    graph: pairGraph,
                    uniformsByNode: directUniforms
                ),
                dynamicProducers: .init(
                    userProperties: producers,
                    authoredFallbackTargets: [dynamicTarget()],
                    timelineTargets: [],
                    sceneScriptTargets: []
                )
            )
        }
        let ordinaryAbsentFallback = ordinaryFallbackCatalog(producers: [])
        let ordinarySoleProducer = ordinaryFallbackCatalog(producers: [.init(
            propertyKey: "strength-property",
            target: dynamicTarget(),
            valueType: .scalar
        )])
        let ordinaryExtraSameTarget = ordinaryFallbackCatalog(producers: [
            .init(
                propertyKey: "strength-property",
                target: dynamicTarget(),
                valueType: .scalar
            ),
            .init(
                propertyKey: "wrong-property",
                target: dynamicTarget(),
                valueType: .vector2
            ),
        ])
        let ordinaryWrongIdentity = ordinaryFallbackCatalog(producers: [.init(
            propertyKey: "strength-property",
            target: dynamicTarget(passIndex: 1),
            valueType: .scalar
        )])

        let fallbackDedicatedLeafCatalog = Catalog(
""",
    )
    harness = replace_once(
        harness,
        """            "rejections": [
""",
        """            "fallbackOwnerConservation": [
                "pulseMissingProducerUsesDedicated": pulseMissingProducer
                    .claim(layerID: layerID).flatMap {
                        pulseMissingProducer.resolve($0.token)
                    }?.stages.first?.subject?.family == "fixture-dedicated",
                "xRayMissingProducerUsesDedicated": xRayMissingProducer
                    .claim(layerID: layerID).flatMap {
                        xRayMissingProducer.resolve($0.token)
                    }?.stages.first?.subject?.family == "fixture-dedicated",
                "requiredLiveMissingProducerRejected": reportHas(
                    requiredLiveMissingProducer,
                    "dedicated-leaf-unsupported"
                ) && requiredLiveMissingProducer.claim(layerID: layerID) == nil,
                "ordinaryAbsentFallbackUsesProgram": ordinaryAbsentFallback
                    .claim(layerID: layerID).flatMap {
                        ordinaryAbsentFallback.resolve($0.token)
                    }?.stages.first?.subject?.family == "resolved-material",
                "ordinarySoleProducerUsesProgram": ordinarySoleProducer
                    .claim(layerID: layerID).flatMap {
                        ordinarySoleProducer.resolve($0.token)
                    }?.stages.first?.subject?.family == "resolved-material",
                "extraSameTargetCannotUseProgram": ordinaryExtraSameTarget
                    .claim(layerID: layerID).flatMap {
                        ordinaryExtraSameTarget.resolve($0.token)
                    }?.stages.first?.visualFailureReasonCode
                        == "material-dynamic-uniform-producer-unavailable",
                "sameKeyWrongTargetCannotAppearAbsent": reportHas(
                    ordinaryWrongIdentity,
                    "dynamic-uniform-unavailable"
                ) && ordinaryWrongIdentity.claim(layerID: layerID) == nil,
            ],
            "rejections": [
""",
    )
    return support, harness


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAuthoredFallbackOwnerConservationTests(unittest.TestCase):
    def test_program_first_preserves_exact_owner_conservation(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-authored-fallback-owner-conservation-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "Harness.swift"
            binary = root / "owner-conservation-test"
            support_source, harness_source = owner_conservation_sources()
            support.write_text(support_source, encoding="utf-8")
            harness.write_text(harness_source, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                    str(support),
                    str(Path(base.__file__).with_name("fixtures")
                        / "SceneSignalCapabilitySupport.swift"),
                    *(str(path) for path in base.SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path", str(root / "module-cache"),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

        checks = json.loads(completed.stdout)["fallbackOwnerConservation"]
        self.assertTrue(all(checks.values()), checks)


if __name__ == "__main__":
    unittest.main()
