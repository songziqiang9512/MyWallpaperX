"""Exercise the unchanged production AVFoundation async/cancellation bridge with an owned tiny clip."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Modules/Pixabay/UI/AppKitPixabayDownloadsItem.swift'
FIXTURE = ROOT / 'script/tests/fixtures/PixabayDownloadedThumbnailHarness.swift'


def declaration(source, signature):
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 0
    for index in range(opening, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(signature)


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('ffmpeg'), 'macOS and ffmpeg fixture generator required')
class PixabayDownloadedThumbnailGenerationTests(unittest.TestCase):
    def test_actual_async_generation_cancellation_failure_and_retry(self):
        with tempfile.TemporaryDirectory(prefix='mwx-online-video-', dir='/private/tmp') as directory:
            work = Path(directory)
            clip = work / 'owned.mp4'
            generate = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi',
                '-i', 'testsrc2=size=512x288:rate=2', '-t', '1', '-c:v', 'mpeg4',
                '-q:v', '3', '-threads', '1', str(clip)], capture_output=True, text=True, timeout=15)
            self.assertEqual(generate.returncode, 0, generate.stdout + generate.stderr)
            source = work / 'Harness.swift'
            source.write_text('import AppKit\nimport AVFoundation\nimport Foundation\n' +
                declaration(SOURCE.read_text(), 'nonisolated private final class PixabayThumbnailVideoGeneration') +
                '\n' + FIXTURE.read_text())
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (SOURCE, FIXTURE)}
            binary = work / 'video-generation'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-default-isolation', 'MainActor',
                str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            proof = None
            if destination := os.environ.get('MWX_ONLINE_IMAGE_THUMBNAIL_SCHEDULING_PROOF_DIR'):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix='downloaded-video-', dir=destination))
                (proof / 'compile.log').write_text(build.stdout + build.stderr)
                (proof / 'inputs.json').write_text(json.dumps({'inputs': inputs,
                    'scope': __doc__, 'transforms': ['extract complete unchanged production bridge declaration']}, indent=2))
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (SOURCE, FIXTURE)})
            result = subprocess.run([str(binary), str(clip)], capture_output=True, text=True, timeout=20)
            if proof:
                (proof / 'stdout.log').write_text(result.stdout)
                (proof / 'stderr.log').write_text(result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            facts = json.loads(result.stdout)
            self.assertEqual(set(facts), {'realFrameAndDimensions', 'missingMediaCompletes',
                'cancelledGenerationsDrain', 'retryAfterCancellation'})
            self.assertTrue(all(facts.values()), facts)


if __name__ == '__main__':
    unittest.main()
