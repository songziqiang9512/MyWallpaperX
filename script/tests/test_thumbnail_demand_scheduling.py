"""Bounded real ThumbnailCache demand, cancellation, priority and atomic clear."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ThumbnailDemandSchedulingTests(unittest.TestCase):
    def test_real_cache_demand_lifetime_and_short_disk_lane(self):
        with tempfile.TemporaryDirectory(prefix="mwx-thumbnail-demand-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            sources = [ROOT / "MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift",
                       ROOT / "MyWallpaperX/Shared/UI/ThumbnailCache.swift",
                       ROOT / "script/tests/fixtures/ThumbnailDemandSchedulingHarness.swift"]
            # This one case evicts only decoded memory to prove a real disk
            # return. Expose the original owner only in this compiled copy.
            cache = sources[1].read_text()
            self.assertEqual(cache.count("private let imageCache:"), 1)
            deletion = "if detached { try? FileManager.default.removeItem(at: retired) }"
            self.assertEqual(cache.count(deletion), 1)
            cache = cache.replace(deletion, "if detached { ThumbnailClearObservation.remove(retired) }")
            # Observe actual encoders and finish returns in this temporary copy;
            # cancellation, image decoding and publication stay production code.
            for encoding in ("jpeg", "png"):
                marker = f"private static func {encoding}Data(_ image: NSImage) -> Data? {{"
                self.assertEqual(cache.count(marker), 1)
                cache = cache.replace(marker, marker +
                    f'\n        ThumbnailEncodingObservation.encodings.record("{encoding}")')
            finish = "cachesFailure: Bool = false) -> Bool {"
            self.assertEqual(cache.count(finish), 1)
            cache = cache.replace(finish, finish +
                "\n        defer { ThumbnailEncodingObservation.finishes.record(key) }")
            cache_copy = work / "ThumbnailCache.swift"
            cache_copy.write_text(cache.replace("private let imageCache:", "let imageCache:", 1))
            sources[1] = cache_copy
            build = subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-D", "D17_SCHEDULING",
                                    *map(str, sources), "-module-cache-path", str(work / "modules"),
                                    "-o", str(work / "checks")], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            home = work / "home"
            home.mkdir()
            run = subprocess.run([str(work / "checks")], env=dict(os.environ,
                                 HOME=str(home), CFFIXED_USER_HOME=str(home)),
                                 capture_output=True, text=True, timeout=45)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            for name, passed in facts["checks"].items():
                with self.subTest(name=name):
                    self.assertTrue(passed)
            self.assertGreaterEqual(len(facts["checks"]), 75)
            if proof := os.environ.get("MWX_DEMAND_PROOF_DIR"):
                target = Path(proof)
                target.mkdir(parents=True, exist_ok=True)
                (target / "results.json").write_text(json.dumps(facts, indent=2) + "\n")
                (target / "build.log").write_text(build.stdout + build.stderr)
                (target / "runtime.log").write_text(run.stderr)


if __name__ == "__main__":
    unittest.main()
