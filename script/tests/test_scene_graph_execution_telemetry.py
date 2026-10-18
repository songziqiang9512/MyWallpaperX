#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGraphExecutionObservation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGraphExecutionTelemetry.swift",
]

HARNESS = (REPOSITORY_ROOT / "script/tests/fixtures/SceneGraphExecutionTelemetryHarness.swift").read_text(encoding="utf-8")


class SceneGraphExecutionTelemetryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-graph-execution-telemetry-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-graph-execution-telemetry-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
        compilation = subprocess.run(
            [
                "swiftc", "-D", "DEBUG",
                "-swift-version", "6",
                "-default-isolation", "MainActor",
                "-strict-concurrency=complete",
                "-warnings-as-errors",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        cls.logs = cls.result["logs"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_node_and_ordinal_conservation_are_exact(self) -> None:
        first = self._line(
            self.logs,
            frame="10",
            trigger="first-frame+reset+first-success+gpu-completed",
        )
        self.assertEqual(self._field(first, "authoredNodes"), "4")
        self.assertEqual(self._field(first, "materialNodes"), "2")
        self.assertEqual(self._field(first, "copyNodes"), "1")
        self.assertEqual(self._field(first, "swapNodes"), "1")
        self.assertEqual(self._field(first, "composeNodes"), "1")
        self.assertEqual(self._field(first, "rejectedNodes"), "0")
        self.assertEqual(self._field(first, "materialOrdinals"), "2")
        self.assertEqual(self._field(first, "commandOrdinals"), "2")
        self.assertEqual(self._field(first, "composeSlotBefore"), "primary")
        self.assertEqual(self._field(first, "composeSlotAfter"), "primary")
        self.assertEqual(self.result["conservationError"], "invalidNodeConservation")
        self.assertEqual(self.result["ordinalError"], "invalidOrdinals")
        self.assertEqual(self.result["prunedMaterialOrdinalCount"], 2)
        self.assertEqual(
            self.result["descendingMaterialOrdinalError"],
            "invalidOrdinals",
        )
        self.assertEqual(
            self.result["negativeMaterialOrdinalError"],
            "invalidOrdinals",
        )
        self.assertEqual(self.result["rejectedPassthroughSameSlotError"], "none")
        self.assertEqual(
            self.result["ordinaryRejectedSameSlotError"],
            "invalidCompose",
        )

    def test_node_indices_exactly_match_authoritative_stage_sequence(self) -> None:
        self.assertEqual(self.result["shiftedIndices"], [5, 6, 7, 8])
        self.assertEqual(self.result["sparseIndices"], [5, 7, 9, 11])
        self.assertEqual(self.result["authorityMismatchError"], "invalidNodeOrder")
        self.assertEqual(self.result["descendingAuthorityError"], "invalidNodeOrder")

    def test_copy_swap_and_rejected_command_mapping_replay_is_exact(self) -> None:
        self.assertEqual(self.result["copyAdvanceError"], "invalidLogicalMapping")
        self.assertEqual(self.result["swapNoAdvanceError"], "invalidLogicalMapping")
        self.assertEqual(
            self.result["rejectedSwapAdvanceError"],
            "invalidLogicalMapping",
        )
        self.assertEqual(
            self.result["rejectedSwapHashBefore"],
            self.result["rejectedSwapHashAfter"],
        )

    def test_zero_fbo_mapping_is_valid_but_physical_alias_is_not(self) -> None:
        self.assertEqual(self.result["emptyMappingError"], "none")
        self.assertEqual(self.result["physicalAliasError"], "invalidLogicalMapping")
        self.assertEqual(
            self.result["sameCommandIdentityError"],
            "invalidCommandIdentity",
        )

    def test_pair_output_is_independent_from_fbo_mapping_and_has_generation(self) -> None:
        self.assertEqual(self.result["finalOutputMappingError"], "none")
        self.assertEqual(self.result["wrongPhysicalOutputError"], "none")
        self.assertEqual(self.result["publicationGenerationError"], "invalidFinalOutput")

    def test_gpu_completion_and_outcome_are_bidirectionally_consistent(self) -> None:
        self.assertEqual(self.result["successGPUFailedError"], "invalidOutcome")
        self.assertEqual(self.result["successMissingGPUError"], "invalidOutcome")
        self.assertEqual(self.result["failureGPUCompletedError"], "invalidOutcome")
        completed = [
            line
            for line in self.logs
            if self._field(line, "gpuCompletion") == "completed"
        ]
        failed = self._line(self.logs, gpuCompletion="failed")
        self.assertTrue(completed)
        self.assertTrue(all(self._field(line, "outcome") == "succeeded" for line in completed))
        self.assertEqual(self._field(failed, "outcome"), "failed")
        self.assertEqual(self._field(failed, "finalOutput"), "-")
        self.assertEqual(self._field(failed, "publication"), "-")
        self.assertEqual(self._field(failed, "compositorConsumed"), "false")
        self.assertEqual(self._field(failed, "rejectedNodes"), "4")
        self.assertEqual(self._field(failed, "materialNodes"), "0")
        self.assertEqual(self._field(failed, "copyNodes"), "0")
        self.assertEqual(self._field(failed, "swapNodes"), "0")
        self.assertEqual(self._field(failed, "composeNodes"), "0")
        self.assertEqual(
            self._field(failed, "mappingBeforeSHA256"),
            self._field(failed, "mappingAfterSHA256"),
        )
        self.assertEqual(self._field(failed, "composeSlotBefore"), "none")
        self.assertEqual(self._field(failed, "composeSlotAfter"), "none")

    def test_program_generation_subject_key_rebuilds_first_and_sticky_evidence(self) -> None:
        reparsed = self._line(self.logs, frame="22")
        self.assertEqual(
            self._field(reparsed, "trigger"),
            "first-frame+reset+first-success+gpu-completed",
        )
        self.assertEqual(self.result["programResults"], [True, True])
        self.assertEqual(len(self.result["programLogs"]), 2)
        self.assertEqual(
            {self._field(line, "trigger") for line in self.result["programLogs"]},
            {"first-frame+first-success+gpu-completed"},
        )

    def test_first_and_next_active_frames_and_sticky_facts_are_bounded(self) -> None:
        self.assertEqual(
            self.result["lifecycleResults"],
            [
                True, False, True, False, True, False, False,
                True, False, True, False, False, True, False,
            ],
        )
        self.assertEqual(self._field(self._line(self.logs, trigger="next-frame"), "frame"), "12")
        generation_one = [line for line in self.logs if self._field(line, "effectGeneration") == "1"]
        self.assertEqual(
            sum("first-success" in self._field(line, "trigger") for line in generation_one),
            1,
        )
        self.assertEqual(
            sum("first-failure" in self._field(line, "trigger") for line in generation_one),
            1,
        )

    def test_failure_never_publishes_partial_output(self) -> None:
        self.assertEqual(self.result["failureResults"], [True, False])
        self.assertEqual(self.result["partialOutputError"], "invalidOutcome")
        failure = self._line(self.result["failureLogs"], outcome="failed")
        self.assertEqual(self._field(failure, "finalOutput"), "-")
        self.assertEqual(self._field(failure, "publication"), "-")
        self.assertEqual(self._field(failure, "publicationGeneration"), "-")
        self.assertEqual(self._field(failure, "compositorConsumed"), "false")
        self.assertEqual(self._field(failure, "gpuCompletion"), "-")

    def test_duplicate_transaction_consume_is_diagnosed_once(self) -> None:
        self.assertEqual(self.result["consumeResults"], [True, False, False])
        logs = self.result["consumeLogs"]
        self.assertEqual(len(logs), 2)
        normal = self._line(
            logs,
            trigger="first-frame+first-success+compositor-consume+gpu-completed",
        )
        diagnostic = self._line(logs, diagnostic="duplicate-compositor-consume")
        self.assertEqual(self._field(normal, "transaction"), "consume-transaction")
        self.assertEqual(self._field(diagnostic, "transaction"), "consume-transaction")

    def test_publication_identity_conflict_is_diagnosed_once(self) -> None:
        self.assertEqual(self.result["publicationResults"], [True, False, False])
        logs = self.result["publicationLogs"]
        self.assertEqual(len(logs), 2)
        self._line(logs, diagnostic="transaction-publication-conflict")

    def test_transaction_mapping_and_generation_drift_are_diagnosed_once(self) -> None:
        self.assertEqual(
            self.result["signatureResults"],
            [
                True, False, False,
                True, False, False,
                True, False, False,
            ],
        )
        diagnostics = [
            line for line in self.result["signatureLogs"]
            if " diagnostic=transaction-signature-conflict " in f" {line} "
        ]
        self.assertEqual(len(diagnostics), 3)
        self._line(diagnostics, descriptor="mapping-drift")
        self._line(diagnostics, descriptor="allocation-generation-drift")
        self._line(diagnostics, descriptor="mapping-generation-drift")

    def test_saturation_emits_one_bounded_diagnostic(self) -> None:
        self.assertEqual(self.result["boundedResults"], [True, False, False])
        logs = self.result["boundedLogs"]
        self.assertEqual(len(logs), 2)
        self._line(logs, diagnostic="subject-capacity-saturated")

    def test_transaction_history_rolls_without_normal_playback_diagnostic(self) -> None:
        results = self.result["transactionCapacityResults"]
        self.assertEqual(len(results), 66)
        self.assertEqual(sum(results), 2)
        logs = self.result["transactionCapacityLogs"]
        self.assertEqual(len(logs), 2)
        self.assertFalse(any(" diagnostic=" in f" {line} " for line in logs))

    def test_concurrent_duplicates_remain_bounded_without_order_claim(self) -> None:
        logs = self.result["concurrentLogs"]
        self.assertEqual(len(logs), 1)
        self.assertEqual(self._field(logs[0], "descriptor"), "concurrent")

    def test_all_identities_and_reasons_reject_whitespace_only(self) -> None:
        self.assertEqual(
            self.result["whitespaceErrors"],
            [
                "invalidIdentity",
                "invalidExecutionIdentity",
                "invalidExecutionIdentity",
                "invalidFinalOutput",
                "invalidFinalOutput",
                "invalidNodeDisposition",
                "invalidOutcome",
                "invalidLogicalMapping",
                "invalidCommandIdentity",
            ],
        )

    def test_node_and_mapping_hashes_are_stable(self) -> None:
        expected_nodes = hashlib.sha256("\n".join(self._node_lines()).encode()).hexdigest()
        before = hashlib.sha256("\n".join(sorted(self._mapping_before())).encode()).hexdigest()
        after = hashlib.sha256("\n".join(sorted(self._mapping_after())).encode()).hexdigest()
        self.assertEqual(self.result["nodeHashA"], expected_nodes)
        self.assertEqual(self.result["nodeHashB"], expected_nodes)
        self.assertEqual(self.result["mappingBeforeHashA"], before)
        self.assertEqual(self.result["mappingBeforeHashB"], before)
        self.assertEqual(self.result["mappingAfterHashA"], after)
        self.assertEqual(self.result["mappingAfterHashB"], after)
        self.assertTrue(self.result["canonicalLine"].startswith(
            "graph-execution|runtime=runtime-fixture|frame=90|"
        ))

    def test_target_descriptors_are_complete_stable_and_transition_safe(self) -> None:
        lines = sorted(
            f"logical={logical}|extent=4x2|format=rgbaBackbuffer"
            for logical in (
                "history-a",
                "history-b",
                "effect%20output/%25%20%E4%B8%AD",
            )
        )
        expected = hashlib.sha256("\n".join(lines).encode()).hexdigest()
        self.assertEqual(self.result["targetDescriptorsHash"], expected)
        self.assertEqual(
            self.result["targetDescriptorCounts"],
            "4x2/rgbaBackbuffer:3",
        )
        self.assertEqual(
            self.result["descriptorTransitionError"],
            "invalidTargetDescriptors",
        )
        self.assertEqual(
            self.result["partialDescriptorError"],
            "invalidTargetDescriptors",
        )

    def test_lifecycle_fields_reject_inconsistent_copy_on_write(self) -> None:
        self.assertEqual(
            self.result["copyOnWriteWithoutCopiesError"],
            "invalidLifecycle",
        )
        self.assertEqual(self.result["copyAndDiscardError"], "invalidLifecycle")
        resized = self._line(self.logs, frame="20")
        self.assertEqual(self._field(resized, "inputWidth"), "962")
        self.assertEqual(self._field(resized, "inputHeight"), "542")
        self.assertEqual(self._field(resized, "historyRehydrateCopyCount"), "0")
        self.assertEqual(self._field(resized, "historyContentDiscarded"), "false")

    def test_log_schema_tokens_and_transaction_publication_are_stable(self) -> None:
        self.assertEqual(self.result["encodedToken"], "A%20%25%3D%E4%B8%AD%0A")
        first = self._line(self.logs, frame="10")
        self.assertRegex(
            first,
            re.compile(
                r"^MWX DEBUG SCENE: schema=1 axis=graph-execution "
                r"runtime=runtime-fixture frame=10 "
                r"trigger=first-frame\+reset\+first-success\+gpu-completed "
                r"layer=7 effect=2 descriptor=Graph%20A%25%3D%E4%B8%AD "
            ),
        )
        self.assertEqual(self._field(first, "transaction"), "tx-1-10")
        self.assertEqual(self._field(first, "physicalIdentity"), "texture-output")
        self.assertEqual(self._field(first, "publication"), "pub-1-10")

    @staticmethod
    def _field(line: str, name: str) -> str:
        match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", line)
        if match is None:
            raise AssertionError(f"missing {name}= in {line!r}")
        return match.group(1)

    @classmethod
    def _line(cls, lines: list[str], **fields: str) -> str:
        matches = []
        for line in lines:
            try:
                is_match = all(
                    cls._field(line, name) == value
                    for name, value in fields.items()
                )
            except AssertionError:
                continue
            if is_match:
                matches.append(line)
        if len(matches) != 1:
            raise AssertionError(f"expected one line for {fields!r}, got {matches!r}")
        return matches[0]

    @staticmethod
    def _node_lines() -> list[str]:
        return [
            "node=0|kind=material|materialOrdinal=0|commandOrdinal=-|"
            "commandSource=-|commandTarget=-|compose=false|disposition=executed|reason=-",
            "node=1|kind=copy|materialOrdinal=-|commandOrdinal=0|"
            "commandSource=history-a|commandTarget=history-b|compose=false|"
            "disposition=executed|reason=-",
            "node=2|kind=swap|materialOrdinal=-|commandOrdinal=1|"
            "commandSource=history-a|commandTarget=history-b|compose=false|"
            "disposition=executed|reason=-",
            "node=3|kind=material|materialOrdinal=1|commandOrdinal=-|"
            "commandSource=-|commandTarget=-|compose=true|disposition=executed|reason=-",
        ]

    @staticmethod
    def _mapping_before() -> list[str]:
        return [
            "logical=history-a|physical=texture-0",
            "logical=history-b|physical=texture-1",
            "logical=effect%20output/%25%20%E4%B8%AD|physical=texture-output",
        ]

    @staticmethod
    def _mapping_after() -> list[str]:
        return [
            "logical=history-a|physical=texture-1",
            "logical=history-b|physical=texture-0",
            "logical=effect%20output/%25%20%E4%B8%AD|physical=texture-output",
        ]


if __name__ == "__main__":
    unittest.main()
