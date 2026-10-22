"""Exercise the production thumbnail scheduler and atomically observe permit handoffs."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def declaration(source, signature):
    """Read one top-level declaration without changing production visibility."""
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(signature)


class UIRequestSchedulerTests(unittest.TestCase):
    def test_bounded_handoffs_priority_and_release(self):
        online = (ROOT / 'MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryThumbnailPipeline.swift').read_text()
        # Keep the production actor intact, including its private methods.
        # The fixture's same-file extensions observe queue state in the release
        # actor turn: operation concurrency alone cannot detect wake/requeue storms.
        sources = '\n'.join([
            'import Foundation',
            declaration(online, 'nonisolated enum OLThumbnailRequestPriority'),
            declaration(online, 'actor OLThumbnailRequestScheduler'),
            (ROOT / 'script/tests/fixtures/UIRequestSchedulerHarness.swift').read_text(),
        ])
        with tempfile.TemporaryDirectory(prefix='mwx-ui-schedulers-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Harness.swift'
            source.write_text(sources)
            binary = work / 'schedulers'
            build = subprocess.run([
                'xcrun', 'swiftc', '-parse-as-library', str(source),
                '-module-cache-path', str(work / 'modules'), '-o', str(binary),
            ], capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            facts = json.loads(run.stdout)
            self.assertEqual(set(facts), {
                'onlineBoundedHandoffAndPriority', 'onlineExistingPrefetchAndVisibleLimits',
                'onlineNormalAndCancelledRelease',
            })
            for name, passed in facts.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
