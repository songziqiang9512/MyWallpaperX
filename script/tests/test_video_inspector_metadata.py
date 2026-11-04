"""Complete production Video metadata helper: synchronous template and async facts.

Compiles the whole Support file, retaining its actual isolation annotations,
with the real VideoWallpaper model and AVFoundation. A generated rotated H264
MOV, malformed video, generated PNG and absent path exercise real metadata,
file facts and AV fallback. Test-copy entries record the original attributes,
DateFormatter and AV initialization threads under one lock. A MainActor probe
holds only final delivery; no file/AV result, cancellation or executor is replaced.
Checks cover call placement, output and this H264 sample's duration, rotated
size and codec. They do not establish accuracy for arbitrary media, I/O latency,
native Inspector animation or full-App behavior.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(os.environ.get("MWX_VIDEO_METADATA_SUPPORT_SOURCE", ROOT / "MyWallpaperX/Modules/VideoLibrary/Core/WallpaperLibrarySupport.swift"))
MODEL = ROOT / "MyWallpaperX/Models/VideoWallpaper.swift"
FIXTURE = ROOT / "script/tests/fixtures/VideoInspectorMetadataHarness.swift"


def observe_production(source):
    for statement, stage in (
        ('let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]', 'attributes'),
        ('let dateFormatter = DateFormatter()', 'formatter'),
        ('let asset = AVURLAsset(url: url)', 'av'),
    ):
        pattern = r'(?m)^([ \t]*)' + re.escape(statement) + r'$'
        if len(re.findall(pattern, source)) != 1:
            raise AssertionError('production observation entry is no longer unique: ' + statement)
        source = re.sub(pattern, lambda match: match[1] + 'InspectorMetadataWorkProbe.shared.record(path, stage: "' + stage + '")\n' + match[0], source)
    # Both arms retain their own original delivery cancellation check. The old
    # source remains synchronous before its Task; no compatibility scheduler.
    old = '        await MainActor.run {'
    current = '        guard !Task.isCancelled else { return }\n        completion(details)'
    if source.count(old) == 1:
        source = source.replace(old, '        await InspectorMetadataDeliveryProbe.waitIfHeld(path)\n' + old, 1)
        delivery = 'before original MainActor.run'
    elif source.count(current) == 1:
        source = source.replace(current, '        await InspectorMetadataDeliveryProbe.waitIfHeld(path)\n' + current, 1)
        delivery = 'before original final cancellation guard'
    else:
        raise AssertionError('production final delivery boundary is no longer unique')
    return source, delivery


class VideoInspectorMetadataTests(unittest.TestCase):
    def test_real_helper_publishes_complete_template_before_return_and_honors_cancellation(self):
        production, delivery = observe_production(SUPPORT.read_text())
        paths = [SUPPORT, MODEL, FIXTURE, Path(__file__).resolve()]
        inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
        with tempfile.TemporaryDirectory(prefix="mwx-inspector-metadata-", dir="/private/tmp") as folder:
            work = Path(folder)
            helper = work / "Production.swift"; helper.write_text(production)
            home = work / "home"; home.mkdir()
            env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
            command = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor",
                "-warnings-as-errors", str(MODEL), str(helper), str(FIXTURE),
                "-module-cache-path", str(work / "modules"), "-o", str(work / "checks")]
            build = subprocess.run(command, capture_output=True, text=True, env=env, timeout=120)
            proof = None
            if destination := os.environ.get("MWX_VIDEO_METADATA_PROOF_DIR"):
                Path(destination).mkdir(parents=True, exist_ok=True)
                proof = Path(tempfile.mkdtemp(prefix="metadata-", dir=destination))
                (proof / "inputs.json").write_text(json.dumps({"inputs": inputs, "command": command, "scope": __doc__,
                    "transforms": ["compile complete production Support; retain all isolation annotations", "record actual attributes/DateFormatter/AV initialization threads under a lock", "await scheduling probe " + delivery + "; original cancellation check and all results retained"]}, indent=2))
                (proof / "compile.log").write_text(build.stdout + build.stderr)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(work / "checks"), str(work)], capture_output=True, text=True, env=env, timeout=45)
            if proof:
                (proof / "stdout.log").write_text(run.stdout)
                (proof / "stderr.log").write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            self.assertTrue(checks)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})
            print(json.dumps(checks, sort_keys=True))
            for name, passed in checks.items():
                with self.subTest(check=name):
                    self.assertIs(passed, True, name + "\n" + run.stderr)


if __name__ == "__main__":
    unittest.main()
