"""Run the production DEBUG pointer schedule against the existing capture sink."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


class SceneDebugDoubleClickTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-double-click-")
        cls.addClassCleanup(cls.directory.cleanup)
        root = Path(__file__).resolve().parents[2]
        output = Path(cls.directory.name)
        cls.binary = output / "schedule"
        debug = root / "MyWallpaperX/App/Debug"
        sources = [debug / f"DebugScenePlaybackRunner+{part}.swift"
                   for part in ("EvidenceSchedule", "PointerDrag", "Arguments")]
        sources += [root / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift",
                    root / "script/tests/fixtures/SceneDebugPointerScheduleHarness.swift"]
        subprocess.run(["swiftc", "-D", "DEBUG", "-parse-as-library", *map(str, sources),
                        "-module-cache-path", str(output / "modules"), "-o", str(cls.binary)],
                       capture_output=True, text=True, check=True, timeout=120)

    def test_double_click_delivers_two_complete_edges_before_capture(self):
        for subframe in (False, True):
            with self.subTest(subframe=subframe):
                args = [str(self.binary), "success", "--mwx-debug-scene-primary-double-click",
                        "--mwx-debug-scene-hover-pointer-json", '{"x":0.25,"y":-0.5}']
                if subframe:
                    args.append("--mwx-debug-scene-primary-click-subframe")
                result = subprocess.run(args, capture_output=True, text=True, check=True, timeout=15)
                payload = json.loads(result.stdout)
                self.assertTrue(payload["click"])
                events = payload["events"]
                first = next(i for i, row in enumerate(events) if row["event"] == "pointer:down")
                capture = next(i for i, row in enumerate(events) if row["event"] == "capture:hover")
                edges = [row for row in events[first:capture] if row["event"].startswith("pointer:")]
                self.assertEqual([row["event"] for row in edges],
                                 ["pointer:down", "pointer:up", "pointer:down", "pointer:up"])
                self.assertTrue(all(row["point"] == [0.25, -0.5] for row in edges))
                self.assertGreater(edges[2]["time"], edges[1]["time"])
                self.assertGreater(events[capture]["time"], edges[-1]["time"])
                for start in [i for i, row in enumerate(events) if row["event"] == "pointer:down"]:
                    names = [row["event"] for row in events[start:]]
                    self.assertEqual(names.index("pointer:up") < names.index("turn-after-press"), subframe)


if __name__ == "__main__":
    unittest.main()
