"""Build the same real Runtime fixture in both configurations and compare behavior."""
from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from uuid import UUID


def _declaration(source: str, marker: str) -> str:
    start = source.index(marker)
    body = source.index("{", start)
    depth, end = 1, body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


# Reuse the existing no-request telemetry leaf. Its render/blit methods create
# real Metal encoders; only timing observations are outside these behavior gates.
# Particle admission, simulation, instance buffers and renderer decisions remain
# the real product sources. The separate timestamp gate tests that diagnostic.
NO_TIMESTAMP_OBSERVATION_SUPPORT = "#if DEBUG\nimport Metal\n" + _declaration(
    (Path(__file__).with_name("fixtures") / "SceneColorBlendCaptureRegionHarness.swift").read_text(),
    "enum SceneGPUStageTimestampHook {",
) + "\n#endif\n"


def compile_runtime_configurations(cls, source_root, swift_sources, harness_sources) -> None:
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        raise unittest.SkipTest("swiftc is unavailable")
    cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-runtime-")
    cls.addClassCleanup(cls.temporary_directory.cleanup)
    directory = Path(cls.temporary_directory.name)
    # Reuse the two complete production methods; no renderer decision is stubbed.
    model_source = (source_root / "Rendering/Frame/SceneMetalRenderer+LayerTransforms.swift").read_text()

    model_methods = "extension SceneMetalRenderer {\n" + "\n".join(
        _declaration(model_source, marker) for marker in ["    func particleModelMatrix(", "    private func parallaxOffset("]
    ) + "\n}\n"
    prepared_harnesses = []
    for source in harness_sources:
        if source.name == "SceneParticleRuntimeHarness.swift":
            copied = directory / source.name
            copied.write_text(NO_TIMESTAMP_OBSERVATION_SUPPORT
                              + source.read_text().replace("// PRODUCTION_PARTICLE_MODEL_METHODS", model_methods))
            prepared_harnesses.append(copied)
        else:
            prepared_harnesses.append(source)
    cls.binaries = {}
    for configuration, flags in (("debug", ["-D", "DEBUG"]), ("release", ["-O"])):
        binary = directory / f"scene-particle-runtime-{configuration}"
        compilation = subprocess.run([
            swiftc, *flags, *(str(path) for path in swift_sources),
            *(str(path) for path in prepared_harnesses),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(directory / "module-cache"), "-o", str(binary),
        ], capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(f"{configuration}: {compilation.stderr}")
        cls.binaries[configuration] = binary


class SceneParticleRuntimeConfigurationCases:
    def test_release_keeps_real_runtime_transactions_and_output(self) -> None:
        # Exact report projections omitted by #if DEBUG. Actual admission,
        # positions, allocation budgets, frozen-state rollback, RNG, instance
        # buffers, child retirement and teardown fields are compared unchanged.
        report_keys = {
            "diagnostics", "diagnosticKinds", "diagnosticDetails", "missingSpriteRenderer",
            "staticChildScaleBounded", "staticChildUnsupportedDetails",
            "rawControlPointCopyBounded", "hiddenMentioned", "freezeDiagnostic",
            "liveIdentityFollowsCurrent", "liveIdentityFrozen", "liveRotatedFollowsCurrent",
            "liveRotatedFrozen", "resumeDiagnostic", "localFreezeDiagnosticAbsent",
            "vanishingWriteResumeDiagnostic", "singleDiagnostics", "prewarmDiagnostics",
            "staticDiagnostics", "eventspawnDiagnostics", "eventdeathDiagnostics",
            "eventfollowDiagnostics", "nestedDiagnostics", "eventColorMarkers",
            "invalidEventColorDetails", "childUnsupportedLayers", "budgetDetails",
            "audioChildDetails", "childScaleDetails", "unsupportedForceReported",
            "rejectedChurnObservationCount", "churnObservationsAfterRestore",
            "retryChurnObservationCount", "retryChurnObservationPaths", "laterChurnObservationCount",
        }

        def functional(value, keys):
            if isinstance(value, dict):
                return {key: functional(item, keys) for key, item in value.items() if key not in keys}
            if isinstance(value, list):
                return [functional(item, keys) for item in value]
            return value

        for mode in (
            "playback-control", "lifecycle-synthetic", "frame-transaction-synthetic",
            "worldspace-freeze-recovery", "worldspace-gravity-frame", "child-capacity-synthetic",
            "eventfollow-synthetic", "static-scaled-rope-synthetic", "rope-trail-synthetic",
            "rope-synthetic", "subframe-lifetime-synthetic", "subframe-child-lifecycle-synthetic",
            "layer-alpha-synthetic", "synthetic", "child-pointer-control-point-synthetic",
            "batch-evidence-synthetic",
        ):
            with self.subTest(mode=mode):
                debug = self.run_harness(mode)
                release = self.run_harness(mode, configuration="release")
                if mode == "lifecycle-synthetic":
                    # Each fresh process owns a different real session UUID.
                    # Prove the returned teardown identity before normalizing it.
                    for result in (debug, release):
                        self.assertEqual(str(UUID(result["identity"])).upper(), result["identity"])
                        self.assertEqual(result["identity"], result["observationIdentity"])
                        result["identity"] = result["observationIdentity"] = "current-session"
                # Never strip Release reports: retained fields fail this equality.
                keys = report_keys | ({"initial", "discarded", "dormant", "beforeCommit",
                                       "afterDiscard", "committed"}
                                      if mode == "batch-evidence-synthetic" else set())
                self.assertEqual(release, functional(debug, keys))

    def test_release_has_no_runtime_report_storage_but_keeps_definition_diagnostics(self) -> None:
        for configuration in ("debug", "release"):
            with self.subTest(configuration=configuration):
                result = self.run_harness("configuration-storage", configuration=configuration)
                for field in ("runtimeDiagnostics", "runtimeAdoptionReport", "snapshotAdoptionReport",
                              "compilationDiagnostics"):
                    self.assertEqual(result[field], configuration == "debug", field)
                self.assertTrue(result["definitionDiagnostics"])
