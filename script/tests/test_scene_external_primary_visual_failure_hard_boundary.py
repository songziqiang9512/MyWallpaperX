#!/usr/bin/env python3

"""External-primary runtime visual failures stay hard until their own V1 atom."""

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import unittest


EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"]
BASE_HARNESS = EXECUTOR_FIXTURE["HARNESS"]
compile_harness = EXECUTOR_FIXTURE["compile_harness"]


def replace_once(source: str, marker: str, replacement: str) -> str:
    if source.count(marker) != 1:
        raise RuntimeError(f"expected one harness marker: {marker!r}")
    return source.replace(marker, replacement, 1)


HARNESS = replace_once(
    BASE_HARNESS,
    '        var crossLayerFailure = "setup"\n',
    '''        var crossLayerFailure = "setup"
        var crossLayerProgramKey: String?
''',
)
HARNESS = replace_once(
    HARNESS,
    '''                crossLayerPrepared = true
                crossLayerEncoded = executor.encode(prepared, commandBuffer: command)
''',
    '''                crossLayerPrepared = true
                crossLayerProgramKey = prepared.stages[0].programCacheKeys.first
                crossLayerEncoded = executor.encode(prepared, commandBuffer: command)
''',
)
HARNESS = replace_once(
    HARNESS,
    "        let missingProvider = rejectedCrossLayerPreparation(\n",
    r'''        var externalPrimaryRuntimeFailureRemainsHard = false
        var externalPrimaryRuntimeFailureCode = "setup"
        if let claim = crossLayerClaim,
           let capability = crossLayerCapability,
           case .externalPrimary = capability.dependencyOwnership,
           let resource = providerResource,
           let failedKey = crossLayerProgramKey,
           let leases = makeChainedLeases(
                capability,
                device: device,
                generation: 62
           ), let executor = Executor(
                device: device,
                capabilities: crossLayerCapabilities
           ), let command = queue.makeCommandBuffer() {
            executor.materialEncoder.installTestingPreparationFailure(
                .libraryCompilationRejected(diagnostic: "external-fixture"),
                preparedKey: failedKey
            )
            let failed = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(60),
                sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                dedicatedInputs: .init(dependencyEffect: .init(
                    frameEpoch: 60,
                    namedReference: namedReference,
                    reservedMaterialResource: resource
                )),
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            externalPrimaryRuntimeFailureCode = failureCode(failed)
            if case let .failure(.materialPassPreparationRejected(
                stageIndex,
                nodeIndex,
                materialOrdinal,
                programKey,
                failure
            )) = failed {
                externalPrimaryRuntimeFailureRemainsHard = stageIndex == 0
                    && nodeIndex == 0
                    && materialOrdinal == 0
                    && programKey == failedKey
                    && failure.code == "library-compilation"
                    && command.status == .notEnqueued
                    && !externalPrimaryRuntimeFailureCode.contains(
                        "visual-failure-passthrough"
                    )
            }
        }

        let missingProvider = rejectedCrossLayerPreparation(
''',
)
HARNESS = replace_once(
    HARNESS,
    '            "crossLayerExactOwnershipClaimed": {\n',
    '''            "externalPrimaryRuntimeFailureRemainsHard":
                externalPrimaryRuntimeFailureRemainsHard,
            "crossLayerExactOwnershipClaimed": {
''',
)
HARNESS = replace_once(
    HARNESS,
    '                "crossLayer": crossLayerFailure,\n',
    '''                "externalPrimaryRuntimeFailure":
                    externalPrimaryRuntimeFailureCode,
                "crossLayer": crossLayerFailure,
''',
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ExternalPrimaryVisualFailureHardBoundaryTests(unittest.TestCase):
    def test_runtime_pipeline_failure_does_not_bypass_dependency_owner(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertTrue(
            payload["results"]["externalPrimaryRuntimeFailureRemainsHard"],
            payload,
        )
        self.assertIn(
            "pass-library-compilation-rejected",
            payload["failureCodes"]["externalPrimaryRuntimeFailure"],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
