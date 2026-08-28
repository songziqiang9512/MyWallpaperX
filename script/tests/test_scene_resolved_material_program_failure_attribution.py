#!/usr/bin/env python3

"""Loss-preserving Program rejection attribution for function-bearing graphs."""

from __future__ import annotations

import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CAPABILITY_FIXTURE = runpy.run_path(
    str(
        REPOSITORY_ROOT
        / "script/tests/test_scene_resolved_material_execution_capability.py"
    )
)
ENVELOPE_SUPPORT = CAPABILITY_FIXTURE["ENVELOPE_SUPPORT"]
ENVELOPE_SWIFT_SOURCES = CAPABILITY_FIXTURE["ENVELOPE_SWIFT_SOURCES"]
CAPABILITY_STAGES_SOURCE = CAPABILITY_FIXTURE["CAPABILITY_STAGES_SOURCE"]
CAPABILITY_PROGRAM_FIRST_SOURCE = CAPABILITY_FIXTURE[
    "CAPABILITY_PROGRAM_FIRST_SOURCE"
]
GENERIC_SHADER_CACHE_SOURCE = CAPABILITY_FIXTURE["GENERIC_SHADER_CACHE_SOURCE"]
GENERIC_SHADER_CACHE_TELEMETRY_SOURCE = CAPABILITY_FIXTURE[
    "GENERIC_SHADER_CACHE_TELEMETRY_SOURCE"
]
ENVELOPE_HARNESS = CAPABILITY_FIXTURE["ENVELOPE_HARNESS"].replace(
    '            "functionFrontendAttribution": attribution(functionFrontendFailure),\n',
    '            "functionFrontendAttribution": attribution(functionFrontendFailure),\n'
    '            "functionFrontendClaim":\n'
    '                functionFrontendFailure.claim(layerID: layerID) != nil,\n'
    '            "functionFrontendFallback":\n'
    '                functionFrontendFailure.reportLines.contains {\n'
    '                    $0.contains("outcome=effect-local-passthrough")\n'
    '                },\n',
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialProgramFailureAttributionTests(unittest.TestCase):
    def test_generic_owner_revocation_retains_local_failure_boundaries(
        self,
    ) -> None:
        stages = CAPABILITY_STAGES_SOURCE.read_text(encoding="utf-8")
        program_first = CAPABILITY_PROGRAM_FIRST_SOURCE.read_text(
            encoding="utf-8"
        )
        generic_cache = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (
                GENERIC_SHADER_CACHE_SOURCE,
                GENERIC_SHADER_CACHE_TELEMETRY_SOURCE,
            )
        )

        self.assertIn(
            "materialFailure.mapsToGenericOwnerRevokedVisualFailure", stages
        )
        self.assertNotIn("boundedDetails.contains", stages)
        self.assertIn(
            'reasonCode: "material-generic-owner-revoked"',
            stages,
        )
        for contract in (
            ".conditionalStraightUnionSourceSlot(",
            "routeDecision",
            "recordExecution(",
        ):
            self.assertIn(contract, generic_cache)
        self.assertNotIn("WorkshopShadow", generic_cache)

        owner_start = program_first.index(
            "let retainedDedicatedProgram = programsByKey[effect.key]?.first"
        )
        owner_end = program_first.index(
            "guard product.clearFunctions.functions.isEmpty else",
            owner_start,
        )
        owner_branch = program_first[owner_start:owner_end]
        clear_guard = "product.clearFunctions.functions.isEmpty"
        passthrough_call = (
            "visualFailureMayPassthrough(\n"
            "                           programFailure,"
        )
        hard_rejection = "return .failure(programFailure)"
        for contract in (
            "retainedDedicatedProgram == nil",
            "programFailure.revokesDedicatedProductOwner",
            'programFailure.code == "material-generic-owner-revoked"',
            clear_guard,
            passthrough_call,
            "dependencyOwnership: admitted.dependencyOwnership",
            hard_rejection,
        ):
            self.assertIn(contract, owner_branch)
        self.assertIn(
            "if product.clearFunctions.functions.isEmpty,\n"
            "                       visualFailureMayPassthrough(",
            owner_branch,
        )
        self.assertLess(
            owner_branch.index(clear_guard),
            owner_branch.index(passthrough_call),
        )
        self.assertLess(
            owner_branch.index(passthrough_call),
            owner_branch.index(hard_rejection),
        )
        self.assertIn(
            "guard let program = retainedDedicatedProgram else",
            program_first[owner_end:],
        )

        passthrough_start = program_first.index(
            "private static func visualFailureMayPassthrough("
        )
        passthrough_end = program_first.index(
            "private static func dedicatedDynamicTargetsAreExecutable(",
            passthrough_start,
        )
        passthrough = program_first[passthrough_start:passthrough_end]
        for contract in (
            "case .none, .graphInternal:",
            "case .externalPrimary:",
            '"material-generic-owner-revoked",',
        ):
            self.assertIn(contract, passthrough)
        external_primary = passthrough.index("case .externalPrimary:")
        reason_allowlist = passthrough.index(
            '"material-generic-owner-revoked",'
        )
        self.assertIn("return false", passthrough[external_primary:reason_allowlist])

    def test_function_graph_retains_exact_program_failure_without_admission(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-program-failure-attribution-"
        ) as directory:
            root = Path(directory)
            support = root / "Support.swift"
            harness = root / "AttributionHarness.swift"
            binary = root / "program-failure-attribution-test"
            support.write_text(ENVELOPE_SUPPORT, encoding="utf-8")
            harness.write_text(ENVELOPE_HARNESS, encoding="utf-8")
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    "-parse-as-library",
                    str(support),
                    *(str(path) for path in ENVELOPE_SWIFT_SOURCES),
                    str(harness),
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
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

        payload = json.loads(completed.stdout)
        self.assertTrue(payload["functionPositiveClaim"], payload)
        self.assertFalse(payload["functionFrontendClaim"], payload)
        self.assertFalse(payload["functionFrontendFallback"], payload)
        failure = payload["functionFrontendFailure"]
        self.assertIn("material-variant-envelope-frontend", failure)
        self.assertNotIn("function-invocation-executor-unavailable", failure)

        attribution = payload["functionFrontendAttribution"]
        for field in (
            "schema=program-failure-attribution-v1",
            "layer=981",
            "effectOrdinal=0",
            "effectDescriptor=envelope",
            "node=0",
            "material=materials/envelope-0.json",
            "materialPass=envelope-0",
            "shader=fixture/frontend-failure",
            "reason=material-variant-envelope-frontend",
            "producer=launch-envelope",
            "envelope=frontend",
            "phase=frontend",
            "code=shaderFrontendFailed",
            "slot=none",
        ):
            self.assertIn(field, attribution)
        self.assertNotIn("details=-", attribution)

        source_route = payload["capturedMainNoGraphInputAttribution"]
        for field in (
            "schema=program-failure-attribution-v1",
            "layer=981",
            "effectOrdinal=0",
            "effectDescriptor=envelope",
            "node=0",
            "material=materials/envelope-0.json",
            "materialPass=envelope-0",
            "shader=fixture/captured-main-no-graph-input",
            "reason=utility-source-program-unsupported",
            "producer=source-route",
            "envelope=none",
            "phase=source-route",
            "code=capturedMainTargetTextureUnsupported",
            "slot=none",
            "details=captured-main-target-program-contract-unproven",
        ):
            self.assertIn(field, source_route)


if __name__ == "__main__":
    unittest.main()
