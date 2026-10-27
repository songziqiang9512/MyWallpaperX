"""Self-authored CPU fixture for the isolated benchmark sample contract.

The process double only emits the public debug evidence grammar and small PNGs;
no product App, GPU, author script, real media or private reference is executed.
"""

from __future__ import annotations

import inspect
import json
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest import mock
from scene_sample_snapshot import tree_manifest


PERFORMANCE_LOG = (
    "MWX DEBUG SCENE: phase=performance targetFPS=60 warmupSeconds=30 "
    "elapsed=6.833 callbacks=410 submitted=410 completed=409 failed=0 "
    "submittedFPS=60.004 completedFPS=59.857 "
    "presented=408 presentStreams=1 presentIntervals=407 "
    "presentP50MS=16.667 presentP95MS=16.700 presentP99MS=20.000 "
    "presentMaxMS=34.000 presentOver1_5Budget=1 "
    "callbackP50MS=16.666 callbackP95MS=16.698 callbackMaxMS=17.171 "
    "callbackOver16=199 callbackOver33=0 "
    "discontinuities=1 droppedMS=750.000 maxRawFrameMS=1000.000 "
    "drawableMissed=0 drawableWaitP95MS=0.013 drawableWaitMaxMS=0.034 "
    "preEncodeP95MS=7.671 preEncodeMaxMS=7.868 mainFrameP95MS=8.097 "
    "mainFrameMaxMS=8.311 cpuP50MS=0.348 cpuP95MS=0.380 cpuMaxMS=0.578 "
    "cpuOver16=0 cpuOver33=0 gpuSamples=409 "
    "gpuP50MS=2.279 gpuP95MS=3.886 gpuMaxMS=4.752 gpuOver16=0 gpuOver33=0\n"
    "MWX DEBUG SCENE: phase=performance-stages "
    "layer-loop=p50:4.000ms p95:5.500ms n:407 "
    "prologue=p50:1.000ms p95:1.500ms n:407\n"
    "MWX DEBUG SCENE: phase=performance-resources samples=8 "
    "processSamples=8 processFootprintSampledPeakBytes=134217728 "
    "processCPUTimeMS=2387.500 processCPUTimeStatus=available "
    "gpuAllocatedSampledPeakBytes=67108864 "
    "renderTargetPoolSampledPeakBytes=33554432\n"
)


def write_png(path: Path, *, black: bool = False, shifted: bool = False) -> None:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(
            ">I", zlib.crc32(kind + payload) & 0xFFFFFFFF
        )

    width = height = 8
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend((0, 0, 0) if black else (
                40 + x * 8 + (15 if shifted else 0), 50 + y * 8, 120
            ))
        rows.append(bytes(row))
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + chunk(b"IEND", b"")
    )


def normalize_fixture_paths(value: Any, root: Path) -> Any:
    if isinstance(value, str):
        return value.replace(str(root), "<fixture>")
    if isinstance(value, dict):
        return {key: normalize_fixture_paths(item, root) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize_fixture_paths(item, root) for item in value]
    return value


def run_sample_fixture(
    benchmark: ModuleType,
    *,
    sample_overrides: dict[str, Any] | None = None,
    no_execution_observations: bool = False,
    control: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], list[str]]:
    control = control or {}
    sample = {"id": "123", "expected_runtime_evidence_schema": 1}
    sample.update(sample_overrides or {})
    owner = inspect.getmodule(benchmark.run_sample)
    if owner is None:
        raise AssertionError("sample runner owner is unavailable")
    with tempfile.TemporaryDirectory(prefix="mwx-scene-tool-self-fixture-") as directory:
        root = Path(directory)
        source = root / "samples/Scene/123"
        source.mkdir(parents=True)
        (source / "project.json").write_text(json.dumps({
            "type": "scene", "file": "scene.json"
        }))
        if control.get("loose_source"):
            (source / "scene.json").write_text('{"objects":[]}')
        else:
            (source / "scene.pkg").write_bytes(b"SELF-FIXTURE-PACKAGE")
        if control.get("installation_marker"):
            (source / ".mywallpaperx-steam-version.json").write_text("installation identity")
            (source / ".mywallpaperx-steam-version.json.author").write_text("author identity")
        if control.get("expect_current_tree"):
            sample["tree_sha256"] = tree_manifest(source)[0]
        output = root / "output"
        runtime = output / "runtime"
        runtime.mkdir(parents=True)
        observed_command: list[str] = []

        class EvidenceProcess:
            def __init__(self, command: list[str], **options: Any) -> None:
                observed_command.extend(command)
                environment = options["env"]
                if environment["HOME"] != environment["CFFIXED_USER_HOME"]:
                    raise AssertionError("isolated HOME identity differs")
                result_dir = Path(command[command.index(
                    "--mwx-debug-scene-evidence-dir"
                ) + 1])
                if "observed_runtime_files" in control:
                    runtime_source = Path(command[command.index("--mwx-debug-scene-root") + 1])
                    control["observed_runtime_files"].extend(sorted(
                        path.name for path in runtime_source.iterdir()
                    ))
                evidence_path = result_dir / "scene-runtime-evidence.json"
                payload = {
                    "schemaVersion": 1,
                    "sourceEntryPath": "scene.json",
                    "runtimeInput": {"shaderContracts": [], "renderDescriptor": {
                        "layers": [{"id": 1, "visible": True, "contentKind": "image"}],
                    }},
                }
                if control.get("malformed_runtime"):
                    payload["runtimeInput"]["shaderContracts"] = "bad"
                evidence_path.write_text(json.dumps(payload))
                recorded_path = (
                    root / "foreign-runtime-evidence.json"
                    if control.get("foreign_runtime_path") else evidence_path
                )
                if control.get("foreign_runtime_path"):
                    recorded_path.write_text(json.dumps(payload))
                preview = [
                    "loaded: 1 / 3", "text loaded: 0 / 0", "particle loaded: 0 / 0",
                    "solidLayerCount: 0", "utilityLayerCount: 0",
                    "utilityCaptureCount: 0", "utilityDependencyEdgeCount: 0",
                    "utilityNamedTargetPlannedCount: 0", "utilityNamedConsumerCount: 0",
                    "camera: projection=cover parallax=false amount=0 mouseInfluence=0",
                ]
                preview.extend(control.get("preview_lines", []))
                (result_dir / "scene-preview.log").write_text("\n".join(preview) + "\n")
                messages = []
                if not control.get("missing_ready"):
                    messages.append(
                        "MWX DEBUG SCENE: phase=ready fixture=cpu layers=1 "
                        "imageLayers=1 effects=0 surfaces=1 startupElapsedMS=10 "
                        f"runtimeEvidence={recorded_path}"
                    )
                if not control.get("missing_performance"):
                    messages.append(control.get("performance_log", PERFORMANCE_LOG))
                messages.append("MWX DEBUG SCENE: phase=stopped surfacesBefore=1 surfacesAfter=0")
                messages.extend(control.get("log_lines", []))
                options["stdout"].write("\n".join(messages) + "\n")
                options["stdout"].flush()
                write_png(result_dir / "scene-ready-window.png", black=control.get("black", False))
                write_png(result_dir / "scene-after-window.png", black=control.get("black", False), shifted=True)
                self.wait_count = 0

            def wait(self, timeout: float) -> int:
                self.wait_count += 1
                if "observed_wait_timeouts" in control:
                    control["observed_wait_timeouts"].append(timeout)
                if control.get("timeout") and self.wait_count == 1:
                    raise subprocess.TimeoutExpired(observed_command, timeout)
                return control.get("exit_code", 0)

            def terminate(self) -> None:
                pass

            def kill(self) -> None:
                pass

        with mock.patch.object(owner.subprocess, "Popen", EvidenceProcess):
            result = benchmark.run_sample(
                runtime_binary=root / "self-fixture-executable",
                sample_root=root / "samples",
                sample=sample,
                output_dir=output,
                runtime_root=runtime,
                duration=7,
                performance_fps=60,
                after_snapshot_delay=None,
                no_execution_observations=no_execution_observations,
                startup_timeout_allowance=control.get("startup_timeout_allowance", 60),
            )
        return normalize_fixture_paths(result, root), normalize_fixture_paths(observed_command, root)
