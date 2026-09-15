"""Build isolated helper and run maintained offline suites. Empty feed forbids network restore."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SteamHelperOfflineTests(unittest.TestCase):
    def test_helper_suites(self):
        dotnet = os.environ.get('DOTNET') or shutil.which('dotnet') or str(Path.home() / '.dotnet/dotnet')
        if not Path(dotnet).is_file():
            self.fail('dotnet SDK required for helper offline tests')
        with tempfile.TemporaryDirectory(prefix='mwx-steam-helper-test-') as directory:
            folder = Path(directory)
            for source in (ROOT / 'SteamService').iterdir():
                if source.suffix in ('.cs', '.csproj') or source.name in ('packages.lock.json', 'global.json'):
                    shutil.copy2(source, folder / source.name)
            shutil.copytree(ROOT / 'SteamService/Probe', folder / 'Probe')
            feed = folder / 'empty-feed'; feed.mkdir()
            subprocess.run([dotnet, 'restore', '--locked-mode', '--source', str(feed), '-p:NuGetAudit=false'],
                           cwd=folder, check=True, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            result = subprocess.run([dotnet, 'build', '--no-restore', '-o', str(folder / 'out')],
                                    cwd=folder, check=False, timeout=120, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)
            for suite in ('protocol', 'auth', 'manifest', 'staging', 'download', 'query'):
                args = [dotnet, str(folder / 'out/SteamService.dll'), 'selftest', suite]
                if suite == 'protocol':
                    args += [str(ROOT / 'script/tests/fixtures/steam-protocol')]
                completed = subprocess.run(args, cwd=folder, timeout=30, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(completed.returncode, 0, completed.stdout)
                print(completed.stdout.splitlines()[-1])
