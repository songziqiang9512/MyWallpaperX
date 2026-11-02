"""Run the actual DEBUG runner with D22-shaped peers; no product/Metal/AV proof."""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    ROOT / "MyWallpaperX/App/Debug/DebugSceneDaemonClientRunner+Startup.swift",
    ROOT / "MyWallpaperX/App/Debug/DebugSceneStartupMeasurement.swift",
    ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
    ROOT / "script/tests/fixtures/SceneStartupCrossRuntimeHarness.swift",
]


class SceneStartupCrossRuntimeTests(unittest.TestCase):
    def test_existing_modes_and_product_reentry_observation_boundaries(self):
        with tempfile.TemporaryDirectory(prefix="mwx-scene-reentry-runner-") as directory:
            root = Path(directory)
            scene = root / "3750342273"
            scene.mkdir()
            (scene / "project.json").write_text("{}")
            binary = root / "runner"
            compiled = subprocess.run(
                ["xcrun", "swiftc", "-D", "DEBUG", "-parse-as-library", *map(str, SOURCES),
                 "-o", str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)

            def run(mode, scenario):
                output = root / f"{mode}-{scenario}"
                output.mkdir()
                report = output / "report.json"
                argv = [str(binary), "--mwx-debug-scene-startup-mode", mode,
                        "--mwx-debug-scene-startup-report", str(report),
                        "--mwx-debug-scene-root", str(scene), "--mwx-debug-scene-daemon-stable",
                        "--mwx-debug-workshop-root", str(root), "--mwx-debug-user-defaults-suite",
                        "com.songziqiang.MyWallpaperX.Debug.RunnerFixture",
                        "--fixture-scenario", scenario]
                if mode == "lifecycle":
                    second = root / "second-scene"
                    second.mkdir(exist_ok=True)
                    (second / "project.json").write_text("{}")
                    argv += ["--mwx-debug-scene-startup-second-root", str(second),
                             "--mwx-debug-scene-property-key", "brightness",
                             "--mwx-debug-scene-property-type", "number",
                             "--mwx-debug-scene-property-value", "0.85", "--mwx-debug-scene-duration", "5"]
                result = subprocess.run(argv, env={**os.environ, "CFFIXED_USER_HOME": str(root)},
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(report.read_text()), result.stdout.strip()

            for mode, count in [("single", 1), ("sequence", 2)]:
                value, stdout = run(mode, "reuse")
                self.assertTrue(value["passed"])
                self.assertEqual(len(value["rows"]), count)
                self.assertNotIn("crossRuntimeObservation", value)
                self.assertEqual(stdout, "selections=" + ",".join(["scene"] * count))
            for scenario, reuse in [("baseline", False), ("reuse", True)]:
                value, stdout = run("reentry-video", scenario)
                cross = value["crossRuntimeObservation"]
                self.assertTrue(value["passed"])
                self.assertTrue(cross["passed"])
                self.assertEqual(stdout, "selections=scene,video,scene")
                self.assertEqual(len(value["rows"]), 2)
                self.assertTrue(cross["freshSceneSelectionAndExecution"])
                self.assertTrue(cross["sameAdmittedSource"])
                self.assertEqual(cross["sameSceneDaemonPID"], reuse)
                self.assertEqual(cross["sameTransportGeneration"], reuse)
                self.assertEqual(cross["video"]["oldSceneProcessStillRegistered"], reuse)
                self.assertEqual(len(cross["matchingStrongRetirementAcknowledgements"]), int(reuse))
                self.assertTrue(cross["video"]["oldSceneClientResourceSlotsReleased"])
            for scenario in ["video-failure", "partial-visible", "retained-scene"]:
                value, stdout = run("reentry-video", scenario)
                self.assertFalse(value["passed"])
                self.assertFalse(value["crossRuntimeObservation"]["passed"])
                self.assertEqual(len(value["rows"]), 1)
                self.assertEqual(stdout, "selections=scene,video")
            value, _ = run("reentry-video", "foreign-ack")
            self.assertTrue(value["crossRuntimeObservation"]["passed"])
            self.assertEqual(value["crossRuntimeObservation"]["matchingStrongRetirementAcknowledgements"], [])
            value, _ = run("reentry-video", "changed-source")
            self.assertTrue(all(row["passed"] for row in value["rows"]), "original Scene rows remain independent")
            self.assertFalse(value["passed"])
            self.assertFalse(value["crossRuntimeObservation"]["sameAdmittedSource"])
            self.assertFalse(value["crossRuntimeObservation"]["passed"])
            value, _ = run("reentry-video", "wire-overflow")
            self.assertFalse(value["passed"])
            self.assertTrue(value["crossRuntimeObservation"]["wireObservationOverflowed"])
            self.assertEqual(len(value["crossRuntimeObservation"]["wireObservations"]), 64)
            value, stdout = run("lifecycle", "reuse")
            self.assertTrue(value["passed"], value)
            lifecycle = value["lifecycleObservation"]
            self.assertEqual(stdout, "selections=scene,scene")
            self.assertEqual([row["phase"] for row in lifecycle["captures"]],
                             ["a-before", "a-property", "a-paused-first", "a-paused-second", "a-resumed", "b-presented"])
            for key in ("pauseClockFrozen", "resumeClockAdvanced", "freshBSelectionInSameDaemon",
                        "productStopClearedSelection", "shutdownCompletionObserved", "daemonUnregisteredAfterShutdown"):
                self.assertTrue(lifecycle[key], (key, value))
            self.assertTrue(lifecycle["propertyAcknowledgement"]["matchedPendingProperty"])
            self.assertTrue(lifecycle["aLaunchResourcesReleased"]["payload"]["gpuDrained"])
            for scenario, failure in [
                ("property-foreign-request", "property-acknowledgement-mismatch"),
                ("capture-foreign-request", "capture-or-host-association-missing"),
                ("pause-clock-moving", "pause-clock-did-not-freeze"),
                ("missing-drain", "control-or-resource-release-timeout"),
                ("new-pid", "switch-did-not-preserve-daemon-and-refresh-selection"),
            ]:
                value, _ = run("lifecycle", scenario)
                self.assertFalse(value["passed"], value)
                self.assertIn(failure, value["failure"], value)
                self.assertTrue(value["lifecycleObservation"]["shutdownCompletionObserved"], value)


if __name__ == "__main__":
    unittest.main()
