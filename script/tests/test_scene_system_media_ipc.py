"""Execute Scene's production song IPC reducer and acknowledged sender."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
IPC = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC'
MEDIA = ROOT / 'MyWallpaperX/Core/Playback/SystemMedia'


class SceneSystemMediaIPCTests(unittest.TestCase):
    def test_identity_chunks_metadata_clear_and_latest_sender(self):
        with tempfile.TemporaryDirectory(prefix='mwx-scene-media-ipc-') as directory:
            work = Path(directory)
            sources = [
                MEDIA / 'SystemMediaSnapshotStore.swift', MEDIA / 'SystemMediaSnapshot.swift',
                ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/SceneMediaThumbnailInbox.swift',
                IPC / 'SceneDaemonMediaProtocol.swift', IPC / 'SceneDaemonMediaReceiver.swift',
                IPC / 'SceneDaemonClient+SystemMedia.swift',
                ROOT / 'script/tests/fixtures/SceneSystemMediaIPCChecks.swift',
            ]
            compiled = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                '-strict-concurrency=complete', '-warnings-as-errors',
                *map(str, sources), '-module-cache-path', str(work / 'cache'),
                '-o', str(work / 'checks')], capture_output=True, text=True, timeout=90)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            completed = subprocess.run([str(work / 'checks')], capture_output=True,
                text=True, timeout=20)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            checks = json.loads(completed.stdout)
            self.assertGreaterEqual(len(checks), 20)
            for name, passed in checks.items():
                with self.subTest(behavior=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
