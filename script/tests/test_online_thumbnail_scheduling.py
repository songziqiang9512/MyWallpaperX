"""Production OnlineLibrary actors: HTTP leases, queue cancellation/promotion and decode/clear epochs.

The actual decoder and decoded memory owner are retained. Only maintenance trim
is stubbed; URLProtocol controls HTTP replies, and a suspended real decode queue
makes cancellation and single-flight assertions deterministic. No user media,
external network, UI performance claim or app activation is involved.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / 'MyWallpaperX/Modules/OnlineLibrary/Core/OnlineLibraryThumbnailPipeline.swift'
SOURCES = [PIPELINE,
           ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift',
           ROOT / 'MyWallpaperX/Shared/UI/DecodedThumbnailMemoryCache.swift',
           ROOT / 'script/tests/fixtures/OnlineThumbnailSchedulingHarness.swift']


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit decoding requires macOS')
class OnlineThumbnailSchedulingTests(unittest.TestCase):
    def test_actual_request_actors_cancel_promote_coalesce_and_reject_late_publication(self):
        with tempfile.TemporaryDirectory(prefix='mwx-online-scheduling-', dir='/private/tmp') as directory:
            work = Path(directory)
            environment = os.environ.copy()
            for name in ('home', 'tmp'):
                (work / name).mkdir()
            environment.update(HOME=str(work / 'home'), CFFIXED_USER_HOME=str(work / 'home'),
                               TMPDIR=str(work / 'tmp') + '/')
            # Same-file extensions observe the real private actors without adding product diagnostics.
            source = work / 'Harness.swift'
            source.write_text('\n'.join(path.read_text() for path in SOURCES))
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES}
            binary = work / 'online-scheduling'
            command = ['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                       str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            build = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=150)
            proof = None
            if destination := os.environ.get('MWX_ONLINE_SCHEDULING_PROOF_DIR'):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix='online-', dir=destination))
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command,
                    'scope': __doc__, 'transforms': ['concatenate unmodified production sources and fixture']}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in SOURCES})
            result = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
            if proof:
                (proof / 'stdout.log').write_text(result.stdout)
                (proof / 'stderr.log').write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertEqual(set(facts), {'networkConsumerLeases', 'pendingCancellationAndPromotion',
                                         'boundedCoalescedDecode', 'fullRequestClearEpoch', 'diskReadContract'})
            self.assertTrue(all(facts.values()), facts)


if __name__ == '__main__':
    unittest.main()
