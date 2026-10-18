"""Build isolated helper and run maintained offline suites. Empty feed forbids network restore."""
import os
import json
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
            restored = subprocess.run([dotnet, 'restore', '--locked-mode', '--source', str(feed), '-p:NuGetAudit=false'],
                                      cwd=folder, check=False, timeout=120, text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(restored.returncode, 0, restored.stdout)
            result = subprocess.run([dotnet, 'build', '-c', 'Debug', '--no-restore', '-o', str(folder / 'out')],
                                    cwd=folder, check=False, timeout=120, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)
            for suite in ('protocol', 'auth', 'manifest', 'staging', 'download', 'query'):
                args = [dotnet, str(folder / 'out/SteamService.dll'), 'selftest', suite]
                if suite == 'protocol':
                    args += [str(ROOT / 'script/tests/fixtures/steam-protocol')]
                completed = subprocess.run(args, cwd=folder, timeout=30, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                self.assertEqual(completed.returncode, 0, completed.stdout)
                print(completed.stdout.splitlines()[-1])

            release = folder / 'release'
            built = subprocess.run([dotnet, 'build', '-c', 'Release', '--no-restore', '-o', str(release)],
                                   cwd=folder, text=True, capture_output=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            for entry in [('probe',), ('selftest', 'protocol')]:
                denied = subprocess.run([dotnet, str(release / 'SteamService.dll'), *entry],
                                        input='', text=True, capture_output=True, timeout=15)
                self.assertEqual(denied.returncode, 2, denied.stdout + denied.stderr)
                self.assertEqual(denied.stdout, '')
                self.assertEqual(denied.stderr, '')
            requests = [dict(v=1, type='request', requestId=name, command=command,
                             processEpoch=1, accountEpoch=0)
                        for name, command in [('ping', 'ping'), ('bad', 'unknown'), ('stop', 'shutdown')]]
            normal = subprocess.run([dotnet, str(release / 'SteamService.dll')],
                                    input=''.join(json.dumps(r) + '\n' for r in requests),
                                    text=True, capture_output=True, timeout=15)
            self.assertEqual(normal.returncode, 0, normal.stdout + normal.stderr)
            messages = [json.loads(line) for line in normal.stdout.splitlines()]
            self.assertEqual(messages[0]['type'], 'ready')
            results = {m['requestId']: m for m in messages if m['type'] == 'result'}
            self.assertTrue(results['ping']['ok'])
            self.assertFalse(results['bad']['ok'])
            self.assertEqual(results['bad']['error']['code'], 'protocolMismatch')
            self.assertTrue(results['stop']['ok'])

            # Inspect assembly metadata, without loading product code or contacting Steam.
            inspector = folder / 'metadata-inspector'
            inspector.mkdir()
            (inspector / 'Inspect.csproj').write_text(
                '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType>'
                '<TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>')
            (inspector / 'Program.cs').write_text(r'''
using System;
using System.IO;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text.Json;
using var pe = new PEReader(File.OpenRead(args[0]));
var reader = pe.GetMetadataReader();
var types = reader.TypeDefinitions.Select(h => reader.GetTypeDefinition(h))
    .Select(t => reader.GetString(t.Namespace) + "." + reader.GetString(t.Name)).ToArray();
var methods = reader.MethodDefinitions.Select(h => reader.GetString(reader.GetMethodDefinition(h).Name)).ToArray();
Console.WriteLine(JsonSerializer.Serialize(new { types, methods }));
''')
            restored = subprocess.run([dotnet, 'restore', '--source', str(feed), '-p:NuGetAudit=false'],
                                      cwd=inspector, capture_output=True, text=True, timeout=60)
            self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)
            compiled = subprocess.run([dotnet, 'build', '--no-restore', '-o', str(inspector / 'out')],
                                     cwd=inspector, capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            for configuration, assembly in [('Debug', folder / 'out/SteamService.dll'),
                                            ('Release', release / 'SteamService.dll')]:
                metadata = subprocess.run([dotnet, str(inspector / 'out/Inspect.dll'), str(assembly)],
                                          capture_output=True, text=True, timeout=15)
                self.assertEqual(metadata.returncode, 0, metadata.stderr)
                facts = json.loads(metadata.stdout)
                development_types = [t for t in facts['types'] if 'SelfTest' in t or t.startswith('SteamService.Probe.')]
                development_methods = [m for m in facts['methods']
                                       if m.endswith('ForTest') or m in
                                       ('get_TestActiveAttemptId', 'RunQuerySelfTest', 'SendDiagnostic')]
                if configuration == 'Release':
                    self.assertEqual(development_types, [])
                    self.assertEqual(development_methods, [])
                else:
                    self.assertIn('SteamService.ProtocolSelfTest', development_types)
                    self.assertIn('SteamService.Probe.ProbeHost', development_types)
                    self.assertIn('RunQuerySelfTest', development_methods)
                    self.assertIn('PublishAccountForTest', development_methods)
                    self.assertIn('WithDownloadChunkSlotForTest', development_methods)
                    self.assertIn('get_TestActiveAttemptId', development_methods)
            print('Debug offline suites retained; Release metadata/entry rejection/product protocol PASS')
