"""Production process and visible network sampling with controlled native reads.

Both configurations execute the production sampler; no timer, status item,
window, network read or GPU sample is created by this gate.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from script.tests.test_ui_library_algorithms import declaration

ROOT = Path(__file__).resolve().parents[2]


class SystemMonitorStatsTests(unittest.TestCase):
    def test_visible_process_sampling_identity_units_and_lifetime(self):
        product = ROOT / "MyWallpaperX/Core/System/SystemMonitor.swift"
        fixture = ROOT / "script/tests/fixtures/SystemMonitorStatsHarness.swift"
        inputs = [product, fixture, Path(__file__).resolve()]
        hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        source = product.read_text()
        fields = []
        for pattern in (r"^    private\(set\) var stats =.*$", r"^    private var processSamples:.*$",
                        r"^    private var lastProcessSampleTime:.*$"):
            matches = re.findall(pattern, source, re.MULTILINE)
            self.assertEqual(len(matches), 1, pattern)
            fields.append(matches[0])
        fields.append(declaration(source, "    private let processSecondsPerTick:").replace(
            "mach_timebase_info(", "MonitorProcessRead.timebase(") + "()")
        runtime_fields = [line for line in source.splitlines() if any(
            line.startswith('    private var ' + field + ':')
            for field in ('lastNetUp', 'lastNetDown', 'lastNetSampleTime'))]
        self.assertEqual(len(runtime_fields), 3)
        runtime = '\n'.join(declaration(source, signature) for signature in (
            '    func refreshRuntimeStats(', '    func endNetworkSampling(', '    private func readNetwork('))
        runtime = runtime.replace('Date()', 'MonitorRuntimeRead.now')
        reader = declaration(source, "    func refreshApplicationStats(")
        self.assertEqual(reader.count("proc_pid_rusage("), 1)
        reader = reader.replace("proc_pid_rusage(", "MonitorProcessRead.read(", 1)
        reader = reader.replace("ProcessInfo.processInfo.systemUptime", "MonitorProcessRead.now")
        body = fixture.read_text().replace("// ACTUAL_SYSTEM_STATS", declaration(source, "struct SystemStats"))
        body = body.replace("// ACTUAL_FORMATTING", declaration(source, "extension SystemStats"))
        body = body.replace("// ACTUAL_PROCESS_STATE", "\n".join(fields)).replace("// ACTUAL_PROCESS_SAMPLER", reader)
        body = body.replace('// ACTUAL_RUNTIME_STATE', '\n'.join(runtime_fields)).replace('// ACTUAL_RUNTIME_SAMPLER', runtime)
        results = []
        with tempfile.TemporaryDirectory(prefix="mwx-system-monitor-stats-", dir="/private/tmp") as temporary:
            work = Path(temporary)
            harness = work / "Checks.swift"
            harness.write_text(body)
            for configuration, flags in (("debug", ["-D", "DEBUG"]), ("release", ["-O", "-whole-module-optimization"])):
                binary = work / configuration
                build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                    "-default-isolation", "MainActor", *flags, str(harness),
                    "-module-cache-path", str(work / "modules"), "-o", str(binary)],
                    capture_output=True, text=True, timeout=90)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                checks = json.loads(run.stdout)
                self.assertTrue(checks)
                for name, passed in checks.items():
                    with self.subTest(configuration=configuration, name=name):
                        self.assertIs(passed, True, run.stdout + run.stderr)
                results.append(checks)
            self.assertEqual(results[0], results[1])
            print(json.dumps(results[0], sort_keys=True))
        self.assertEqual(hashes, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
