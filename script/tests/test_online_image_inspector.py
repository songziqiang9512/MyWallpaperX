"""Real online Inspector layout/actions/cache consumers, with controlled I/O leaves.

The product view, footer, preview and page/session cancellation code run unchanged.
Frozen copies expose private state and count the real asset predicates and
progress delivery; the original comparison and controls call remain in place.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from script.tests.test_video_thumbnail_prefetch import SWIFT_ISOLATION_FLAGS
from script.tests.test_wallpaper_library_inspector import prepare_image_primary_sources
from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == "darwin", "real AppKit requires macOS")
class OnlineImageInspectorTests(unittest.TestCase):
    def test_footer_actions_grid_thumbnail_reuse_and_page_scope_cancellation(self):
        paths = [ROOT / name for name in (
            "MyWallpaperX/Shared/ThumbnailRequest.swift",
            "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift",
            "MyWallpaperX/Models/WallpaperReference.swift",
            "MyWallpaperX/Models/WallpaperContent.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageModels.swift",
            "MyWallpaperX/Core/OnlineImages/OnlineImageContentProjection.swift",
            "MyWallpaperX/Shared/UI/WallpaperInspectorActions.swift",
            "MyWallpaperX/Shared/Components/WallpaperLibraryControlStyle.swift",
            "MyWallpaperX/Shared/UI/InspectorFooterMetrics.swift",
            "MyWallpaperX/Shared/UI/InspectorFadingScrollView.swift",
            "MyWallpaperX/Modules/StaticImageLibrary/UI/SILInspectorSupport.swift",
            "MyWallpaperX/Shared/UI/OnlineImageInspectorView.swift",
            "script/tests/fixtures/OnlineImageLibraryAppStub.swift",
            "script/tests/fixtures/OnlineImageInspectorHarness.swift",
        )]
        identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [*paths, Path(__file__)]}
        with tempfile.TemporaryDirectory(prefix="mwx-online-image-inspector-", dir="/private/tmp") as directory:
            work = Path(directory)
            primary_sources, primary_inputs = prepare_image_primary_sources(ROOT, work)
            paths += [p for p in primary_sources if p not in paths]
            identities.update({str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in primary_inputs})
            frozen = []
            for path in paths:
                copied = work / path.name
                source = path.read_text()
                if path.name in ("OnlineImageInspectorView.swift", "SILInspectorSupport.swift"):
                    source = re.sub(r"\bprivate\s+", "", source)
                if path.name == "OnlineImageInspectorView.swift":
                    self.assertEqual(source.count("NSWorkspace.shared.open("), 1)
                    source = source.replace("NSWorkspace.shared.open(", "InspectorBrowserProbe.open(")
                    asset = "assets.first { $0.id == assetID }"
                    self.assertEqual(source.count(asset), 1)
                    source = source.replace(asset, "assets.first { OnlineImageInspectorHarness.assetVisits += 1; return $0.id == assetID }")
                    membership = "assets.contains(where: { $0.id == assetID })"
                    self.assertLessEqual(source.count(membership), 1)
                    source = source.replace(membership,
                        "assets.contains(where: { OnlineImageInspectorHarness.membershipVisits += 1; return $0.id == assetID })")
                    progress = declaration(source, "        library.$progress.receive(on: DispatchQueue.main).sink ")
                    self.assertEqual(progress.count("_ in"), 1)
                    observed = progress.replace("_ in", """values in
            let beforeVisits = OnlineImageInspectorHarness.assetVisits
            let beforeCalls = OnlineImageInspectorHarness.controlsCalls
            defer {
                OnlineImageInspectorHarness.progressObservations.append((values[OnlineImageInspectorHarness.progressMarker],
                    OnlineImageInspectorHarness.controlsCalls - beforeCalls, OnlineImageInspectorHarness.assetVisits - beforeVisits))
            }
""", 1)
                    source = source.replace(progress, observed, 1)
                    controls = "    func updateControls() {"
                    self.assertEqual(source.count(controls), 1)
                    source = source.replace(controls, controls + "\n        OnlineImageInspectorHarness.controlsCalls += 1", 1)
                copied.write_text(source)
                frozen.append(copied)
            home = work / "home"; home.mkdir()
            environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            binary = work / "checks"
            build = subprocess.run(["xcrun", "swiftc", *SWIFT_ISOLATION_FLAGS, "-warnings-as-errors", "-parse-as-library",
                *map(str, frozen), "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=35, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            checks = json.loads(result.stdout)
            self.assertTrue(checks)
            for name, passed in checks.items():
                with self.subTest(check=name): self.assertIs(passed, True, result.stderr)
            print(json.dumps(checks, sort_keys=True))
            observations = [json.loads(line.removeprefix("Inspector lookup work: "))
                for line in result.stderr.splitlines() if line.startswith("Inspector lookup work: ")]
            self.assertEqual(len(observations), 1, result.stderr)
            print(json.dumps({"lookupWork": observations[0]}, sort_keys=True))
            budgets = {
                "progress": {phase + suffix: {"calls": 0 if suffix else 1,
                        "asset": 0 if suffix or phase in ("local", "switchingRemote") else 64}
                    for phase in ("remote", "local", "switchingRemote", "remoteAgain")
                    for suffix in ("", "Unrelated", "Duplicate")},
                "metadata": {"remote": {"asset": 192, "membership": 0}, "local": {"asset": 64, "membership": 0},
                    "switchingRemote": {"asset": 64, "membership": 0}, "remoteAgain": {"asset": 192, "membership": 0},
                    "missing": {"asset": 192, "membership": 0}},
                "authors": {"remote": 64, "missing": 64, "completeLocal": 0, "partialLocal": 64,
                    "nameMissingLocal": 64, "bothMissingLocal": 64, "emptyID": 0, "emptyName": 64,
                    "absentIdentity": 64, "wallhavenName": 0},
            }
            budgets["progress"].update({"sameProgressSetup": {"calls": 1, "asset": 0},
                "queuedPageSameProgress": {"calls": 0, "asset": 0}, "localEndAfterPage": {"calls": 1, "asset": 0},
                "stalePayloadFirst": {"calls": 0, "asset": 0}, "stalePayloadLatest": {"calls": 0, "asset": 0},
                "remountEnd": {"calls": 1, "asset": 0}})
            work = observations[0]
            self.assertEqual(set(work), set(budgets))
            for group in ("progress", "metadata"):
                self.assertEqual(set(work[group]), set(budgets[group]))
                for phase, limits in budgets[group].items():
                    self.assertEqual(set(work[group][phase]), set(limits))
                    for metric, limit in limits.items():
                        with self.subTest(group=group, phase=phase, metric=metric):
                            self.assertGreaterEqual(work[group][phase][metric], 0)
                            self.assertLessEqual(work[group][phase][metric], limit, result.stderr)
            self.assertEqual(set(work["authors"]), set(budgets["authors"]))
            for phase, limit in budgets["authors"].items():
                with self.subTest(author=phase):
                    self.assertGreaterEqual(work["authors"][phase], 0)
                    self.assertLessEqual(work["authors"][phase], limit, result.stderr)
        self.assertEqual(identities, {str(path): hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in identities})


if __name__ == "__main__":
    unittest.main()
