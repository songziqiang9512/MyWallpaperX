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
    RUNTIME_ROOT / "SceneEffectExecutionFrameTrace.swift",
    RUNTIME_ROOT / "SceneEffectExecutionTelemetry.swift",
]
GRAPH_COMPOSITION_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/"
    "SceneResolvedMaterialGraphComposition.swift"
)
PLAN_BACKEND_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/EffectCompilation/"
    "SceneEffectStageExecutionPlan+Backend.swift"
)

HARNESS = r'''
import Foundation
import Metal

nonisolated final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

enum HarnessError: Error {
    case missingCohort
}

@main
enum Harness {
    static func main() throws {
        let collector = LogCollector()
        let telemetry = SceneEffectExecutionTelemetry { collector.append($0) }

        let failureThenSuccess = telemetry.makeFrame(frameIndex: 1)
        let identityA = SceneEffectExecutionIdentity(
            layerID: 7, effectIndex: 2, descriptorID: "descriptor A"
        )
        failureThenSuccess.recordExact(
            identity: identityA, origin: .image, family: "Tint Family",
            backend: "program", outcome: .failed(reasonCode: "pipeline-missing")
        )
        failureThenSuccess.recordExact(
            identity: identityA, origin: .image, family: "Tint Family",
            backend: "program", outcome: .failed(reasonCode: "pipeline-missing")
        )
        failureThenSuccess.recordExact(
            identity: identityA, origin: .image, family: "Tint Family",
            backend: "program", outcome: .encodedOutput
        )
        failureThenSuccess.recordExact(
            identity: identityA, origin: .image, family: "Tint Family",
            backend: "program", outcome: .encodedOutput
        )

        let successThenFailure = telemetry.makeFrame(frameIndex: 2)
        let identityB = SceneEffectExecutionIdentity(
            layerID: 8, effectIndex: 5, descriptorID: "descriptor-B"
        )
        successThenFailure.recordExact(
            identity: identityB, origin: .text, family: "Opacity",
            backend: "dedicated", outcome: .encodedOutput
        )
        successThenFailure.recordExact(
            identity: identityB, origin: .text, family: "Opacity",
            backend: "dedicated", outcome: .failed(reasonCode: "late-failure")
        )

        let concurrentDuplicates = telemetry.makeFrame(frameIndex: 3)
        let identityC = SceneEffectExecutionIdentity(
            layerID: 9, effectIndex: 1, descriptorID: "concurrent"
        )
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            concurrentDuplicates.recordExact(
                identity: identityC, origin: .quad, family: "Godrays",
                backend: "dedicated", outcome: .encodedOutput
            )
        }

        let routeTransitions = telemetry.makeFrame(frameIndex: 10)
        routeTransitions.recordRouteOperation(
            layerID: 70, origin: .utilityComposition, operation: "source capture",
            outcome: .failed(reasonCode: "missing-target")
        )
        routeTransitions.recordRouteOperation(
            layerID: 70, origin: .utilityComposition, operation: "source capture",
            outcome: .failed(reasonCode: "missing-target")
        )
        routeTransitions.recordRouteOperation(
            layerID: 70, origin: .utilityComposition, operation: "source capture",
            outcome: .encoded
        )
        routeTransitions.recordRouteOperation(
            layerID: 70, origin: .utilityComposition, operation: "source capture",
            outcome: .encoded
        )

        let hashTraceA = telemetry.makeFrame(frameIndex: 20)
        recordHashCohort(on: hashTraceA, reverse: false)
        guard let cohortA = hashTraceA.freeze() else { throw HarnessError.missingCohort }
        let postFreezeAccepted = hashTraceA.recordExact(
            identity: .init(layerID: 99, effectIndex: 0, descriptorID: "late"),
            origin: .image, family: "Late", backend: "none",
            outcome: .encodedOutput
        )

        let hashTraceB = telemetry.makeFrame(frameIndex: 21)
        recordHashCohort(on: hashTraceB, reverse: true)
        guard let cohortB = hashTraceB.freeze() else { throw HarnessError.missingCohort }

        let emptyTrace = telemetry.makeFrame(frameIndex: 30)
        let emptyReduced = telemetry.reduceSharedCommandBufferStatus(
            for: emptyTrace, status: .completed
        )

        let failedFrame = telemetry.makeFrame(frameIndex: 41)
        failedFrame.recordRouteOperation(
            layerID: 410, origin: .utilityFullscreen, operation: "final-composite",
            outcome: .failed(reasonCode: "encoder-unavailable")
        )
        let firstFrameCompletion = telemetry.reduceSharedCommandBufferStatus(
            for: failedFrame, status: .completed
        )
        let duplicateFrameCompletion = telemetry.reduceSharedCommandBufferStatus(
            for: failedFrame, status: .completed
        )

        let laterFrame = telemetry.makeFrame(frameIndex: 42)
        laterFrame.recordExact(
            identity: .init(
                layerID: 420, effectIndex: 0, descriptorID: "iris-suffix"
            ),
            origin: .utilityProject, family: "IrisSuffix",
            backend: "program", outcome: .encodedOutput
        )
        let laterFrameCompletion = telemetry.reduceSharedCommandBufferStatus(
            for: laterFrame, status: .completed
        )
        let laterFrameFailure = telemetry.reduceSharedCommandBufferStatus(
            for: laterFrame, status: .failed
        )
        let duplicateLaterFrameFailure = telemetry.reduceSharedCommandBufferStatus(
            for: laterFrame, status: .failed
        )

        var metalAvailable = false
        var emptyObserved = false
        var realObserved = false
        var metalLogs: [String] = []
        if let device = MTLCreateSystemDefaultDevice(),
           let queue = device.makeCommandQueue(),
           let emptyCommand = queue.makeCommandBuffer(),
           let command = queue.makeCommandBuffer() {
            metalAvailable = true
            let metalCollector = LogCollector()
            let metalTelemetry = SceneEffectExecutionTelemetry { metalCollector.append($0) }
            emptyObserved = metalTelemetry.observeSharedCommandBuffer(
                for: metalTelemetry.makeFrame(frameIndex: 39), on: emptyCommand
            )

            let realFrame = metalTelemetry.makeFrame(frameIndex: 40)
            realFrame.recordExact(
                identity: SceneEffectExecutionIdentity(
                    layerID: 400, effectIndex: 6, descriptorID: "metal-completion"
                ),
                origin: .solid, family: "Opacity", backend: "program",
                outcome: .encodedOutput
            )
            realObserved = metalTelemetry.observeSharedCommandBuffer(
                for: realFrame, on: command
            )
            let completion = DispatchSemaphore(value: 0)
            command.addCompletedHandler { _ in completion.signal() }
            command.commit()
            _ = completion.wait(timeout: .now() + 5)
            metalLogs = metalCollector.snapshot()
        }

        let payload: [String: Any] = [
            "logs": collector.snapshot(),
            "cohortA": cohortPayload(cohortA),
            "cohortB": cohortPayload(cohortB),
            "postFreezeAccepted": postFreezeAccepted,
            "emptyReduced": emptyReduced,
            "frameReducerTransitions": [
                firstFrameCompletion, duplicateFrameCompletion,
                laterFrameCompletion, laterFrameFailure, duplicateLaterFrameFailure,
            ],
            "metalAvailable": metalAvailable,
            "emptyObserved": emptyObserved,
            "realObserved": realObserved,
            "metalLogs": metalLogs,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func recordHashCohort(
        on trace: SceneEffectExecutionFrameTrace,
        reverse: Bool
    ) {
        let identity = SceneEffectExecutionIdentity(
            layerID: 20, effectIndex: 3, descriptorID: "same descriptor"
        )
        let operations: [() -> Void] = [
            {
                trace.recordExact(
                    identity: identity, origin: .image, family: "Tint Space",
                    backend: "program", outcome: .encodedOutput
                )
            },
            {
                trace.recordExact(
                    identity: identity, origin: .image, family: "Tint Space",
                    backend: "program", outcome: .failed(reasonCode: "late-error")
                )
            },
            {
                trace.recordRouteOperation(
                    layerID: 22, origin: .utilityProject, operation: "source-copy",
                    outcome: .encoded
                )
            },
            {
                trace.recordRouteOperation(
                    layerID: 22, origin: .utilityProject, operation: "source-copy",
                    outcome: .failed(reasonCode: "route-error")
                )
            },
        ]
        (reverse ? operations.reversed() : operations).forEach { $0() }
        trace.recordExact(
            identity: identity, origin: .image, family: "Tint Space",
            backend: "program", outcome: .encodedOutput
        )
    }

    private static func cohortPayload(
        _ cohort: SceneEffectExecutionFrameCohort
    ) -> [String: Any] {
        [
            "frame": cohort.frameIndex,
            "attemptedEffects": cohort.attemptedEffects,
            "returnedOutputs": cohort.returnedOutputs,
            "failedInvocations": cohort.failedInvocations,
            "routeOperations": cohort.routeOperations,
            "sha256": cohort.cohortSHA256,
        ]
    }
}
'''


class SceneEffectExecutionTelemetryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-effect-execution-telemetry-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-effect-execution-telemetry-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
        compilation = subprocess.run(
            [
                "swiftc",
                "-swift-version",
                "6",
                "-default-isolation",
                "MainActor",
                "-strict-concurrency=complete",
                "-warnings-as-errors",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
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
        cls.metal_logs = cls.result["metalLogs"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_cpu_outcomes_are_independent_sticky_transitions(self) -> None:
        failure_then_success = [line for line in self.logs if "descriptor=descriptor%20A" in line]
        self.assertEqual(len(failure_then_success), 2)
        self.assertEqual(
            {self._field(line, "outcome") for line in failure_then_success},
            {"encoded-output", "failed"},
        )
        success_then_failure = [line for line in self.logs if "descriptor=descriptor-B" in line]
        self.assertEqual(len(success_then_failure), 2)
        self.assertEqual(
            {self._field(line, "outcome") for line in success_then_failure},
            {"encoded-output", "failed"},
        )
        concurrent = [line for line in self.logs if "descriptor=concurrent" in line]
        self.assertEqual(len(concurrent), 1)

    def test_cpu_log_schema_and_token_encoding_are_exact(self) -> None:
        line = next(
            line
            for line in self.logs
            if "descriptor=descriptor%20A" in line and "outcome=failed" in line
        )
        self.assertRegex(
            line,
            re.compile(
                r"^MWX DEBUG SCENE: schema=1 axis=effect-cpu-invocation "
                r"frame=1 origin=image subject=effect layer=7 effect=2 "
                r"descriptor=descriptor%20A family=Tint%20Family "
                r"backend=program outcome=failed reason=pipeline-missing$"
            ),
        )

    def test_route_outcomes_are_independent_and_deduplicated(self) -> None:
        lines = [line for line in self.logs if "operation=source%20capture" in line]
        self.assertEqual(len(lines), 2)
        self.assertEqual(
            {self._field(line, "outcome") for line in lines},
            {"encoded", "failed"},
        )
        self.assertTrue(
            all("axis=effect-route-operation" in line for line in lines)
        )

    def test_frozen_cohort_counts_unique_subjects_and_has_stable_hash(self) -> None:
        cohort_a = self.result["cohortA"]
        cohort_b = self.result["cohortB"]
        self.assertEqual(cohort_a["attemptedEffects"], 1)
        self.assertEqual(cohort_a["returnedOutputs"], 1)
        self.assertEqual(cohort_a["failedInvocations"], 1)
        self.assertEqual(cohort_a["routeOperations"], 1)
        self.assertEqual(cohort_a["sha256"], cohort_b["sha256"])
        self.assertRegex(cohort_a["sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(cohort_a["sha256"], self._expected_cohort_hash())
        self.assertFalse(self.result["postFreezeAccepted"])

    def test_empty_frame_is_not_observed(self) -> None:
        self.assertFalse(self.result["emptyReduced"])
        self.assertFalse(self.result["emptyObserved"])
        self.assertFalse(any("frame=30 " in line for line in self.logs))
        self.assertFalse(
            any("frame=39 " in line for line in self.logs + self.metal_logs)
        )

    def test_frame_status_reducer_keeps_completed_and_failed_facts(self) -> None:
        self.assertEqual(
            self.result["frameReducerTransitions"],
            [True, False, False, True, False],
        )
        frame_41 = [
            line
            for line in self.logs
            if "axis=scene-frame-command-buffer frame=41 " in line
        ]
        self.assertEqual(len(frame_41), 1)
        self.assertEqual(self._field(frame_41[0], "status"), "completed")
        frame_42 = [
            line
            for line in self.logs
            if "axis=scene-frame-command-buffer frame=42 " in line
        ]
        self.assertEqual(len(frame_42), 1)
        self.assertEqual(self._field(frame_42[0], "status"), "failed")
        self.assertEqual(
            len(
                [line for line in self.logs if "axis=scene-frame-command-buffer" in line]
            ),
            2,
        )

    def test_real_metal_completion_uses_only_scene_frame_axis(self) -> None:
        if not self.result["metalAvailable"]:
            self.skipTest("Metal device is unavailable")
        self.assertTrue(self.result["realObserved"])
        frame_line = next(
            line
            for line in self.metal_logs
            if "axis=scene-frame-command-buffer frame=40 " in line
        )
        self.assertRegex(
            frame_line,
            re.compile(
                r"^MWX DEBUG SCENE: schema=1 axis=scene-frame-command-buffer "
                r"frame=40 attemptedEffects=1 returnedOutputs=1 "
                r"failedInvocations=0 routeOperations=0 "
                r"cohortSHA256=[0-9a-f]{64} status=completed$"
            ),
        )
        joined = "\n".join(self.logs + self.metal_logs).lower()
        self.assertNotIn("axis=effect-gpu", joined)
        self.assertNotIn("stage gpu", joined)
        self.assertNotIn("succeeded", joined)

    def test_unified_execution_uses_single_backend_identity(self) -> None:
        composition = GRAPH_COMPOSITION_SOURCE.read_text(encoding="utf-8")
        plan_backend = PLAN_BACKEND_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "family: runtime.executionEvidenceFamily(for: subject.key)",
            composition,
        )
        self.assertIn('backend: "resolved-material-graph"', composition)
        self.assertIn("backend.stableName", plan_backend)
        self.assertNotIn("authoredShader", plan_backend)

    @staticmethod
    def _field(line: str, name: str) -> str:
        match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", line)
        if match is None:
            raise AssertionError(f"missing {name}= in {line!r}")
        return match.group(1)

    @staticmethod
    def _expected_cohort_hash() -> str:
        lines = [
            "effect|origin=image|subject=effect|layer=20|effect=3|"
            "descriptor=same%20descriptor|family=Tint%20Space|"
            "backend=program|outcome=encoded-output|reason=-",
            "effect|origin=image|subject=effect|layer=20|effect=3|"
            "descriptor=same%20descriptor|family=Tint%20Space|"
            "backend=program|outcome=failed|reason=late-error",
            "route|origin=utility-project|layer=22|operation=source-copy|"
            "outcome=encoded|reason=-",
            "route|origin=utility-project|layer=22|operation=source-copy|"
            "outcome=failed|reason=route-error",
        ]
        return hashlib.sha256("\n".join(sorted(lines)).encode()).hexdigest()


if __name__ == "__main__":
    unittest.main()
