"""Static and pure-function gates for the AS0 Apple Silicon release contract."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import os
import sys
import subprocess
import textwrap
import unittest
import json
import tempfile
import plistlib
import zipfile
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "script/validate_apple_silicon_release.py"


def load_validator():
    spec = spec_from_file_location("validate_apple_silicon_release", VALIDATOR_PATH)
    assert spec and spec.loader
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AppleSiliconReleaseContractTests(unittest.TestCase):
    def test_release_workflow_signs_media_observer_before_the_outer_app(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        sign_step = workflow.split("      - name: Sign app\n", 1)[1].split("      - name:", 1)[0]
        commands = textwrap.dedent(sign_step.split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory(prefix="mwx-release-signing-") as temporary:
            root = Path(temporary)
            app = root / "products/Build/Products/Release/MyWallpaperX.app"
            observer = app / "Contents/Resources/SceneMediaObserver/SceneMediaObserver.dylib"
            observer.parent.mkdir(parents=True)
            observer.write_bytes(b"observer fixture")
            tools = root / "tools"
            tools.mkdir()
            log = root / "codesign.jsonl"
            codesign = tools / "codesign"
            codesign.write_text(
                "#!/usr/bin/env python3\nimport json, os, sys\n"
                "with open(os.environ['MWX_CODESIGN_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            )
            codesign.chmod(0o755)
            scripts = root / "script"
            scripts.mkdir()
            (scripts / "sign-steam-helper.sh").write_text(
                '#!/bin/bash\ncodesign --force --timestamp --options runtime --sign "$2" "$1/SteamService"\n'
            )
            env = os.environ.copy()
            identity = "Developer ID Application: Test (TEST)"
            env.update(PATH=str(tools) + os.pathsep + env["PATH"],
                       MWX_CODESIGN_LOG=str(log), DERIVED_DATA_PATH=str(root / "products"),
                       CONFIGURATION="Release", APP_NAME="MyWallpaperX", DEVELOPER_ID_APPLICATION=identity)
            result = subprocess.run(["/bin/bash", "-eu", "-c", commands], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            signatures = [call for call in calls if "--sign" in call]
            signed_paths = [call[-1] for call in signatures]
            self.assertIn(str(observer), signed_paths, "the unsigned build's observer must be distribution-signed")
            self.assertLess(signed_paths.index(str(observer)), signed_paths.index(str(app)))
            observer_call = signatures[signed_paths.index(str(observer))]
            self.assertIn("--timestamp", observer_call)
            self.assertEqual(observer_call[observer_call.index("--options") + 1], "runtime")
            self.assertEqual(observer_call[observer_call.index("--sign") + 1], identity)
            self.assertTrue(all("--deep" not in call for call in signatures))
            app_call = signatures[signed_paths.index(str(app))]
            self.assertEqual(app_call[app_call.index("--entitlements") + 1],
                             "MyWallpaperX/HardenedRuntime.entitlements")
            with (ROOT / app_call[app_call.index("--entitlements") + 1]).open('rb') as stream:
                self.assertIs(plistlib.load(stream)['com.apple.security.automation.apple-events'], True)


    def test_bundle_rejects_development_residue_but_keeps_licenses(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            (resources / "LICENSE").write_text("license")
            validator.validate_resource_hygiene(app)
            for name in ("session.source", "sess_abc.json", "SteamService.pdb", "README.md"):
                path = resources / name
                path.write_text("fixture")
                with self.assertRaises(RuntimeError):
                    validator.validate_resource_hygiene(app)
                path.unlink()

    def test_helper_is_required_self_contained_and_embedded_by_xcode(self):
        validator = load_validator()
        self.assertIn(Path("Contents/Resources/SteamService/SteamService"), validator.REQUIRED_BUNDLE_EXECUTABLES)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(RuntimeError):
                validator.validate_steam_helper(root)
            for name in ("SteamService", "SteamService.dll", "SteamKit2.dll", "libhostfxr.dylib",
                         "libhostpolicy.dylib", "libcoreclr.dylib", "System.Private.CoreLib.dll", "NOTICE.md"):
                (root / name).write_bytes(b"fixture")
            (root / "licenses").mkdir()
            (root / "licenses/SteamKit2-LGPL-2.1.txt").write_text("fixture")
            config = root / "SteamService.runtimeconfig.json"
            config.write_text(json.dumps({"runtimeOptions": {"framework": {"name": "Microsoft.NETCore.App"}}}))
            with self.assertRaises(RuntimeError):
                validator.validate_steam_helper(root)
            config.write_text(json.dumps({"runtimeOptions": {"includedFrameworks": [{"name": "Microsoft.NETCore.App"}]}}))
            validator.validate_steam_helper(root)
        project = (ROOT / "MyWallpaperX.xcodeproj/project.pbxproj").read_text()
        self.assertIn("script/publish-steam-helper.sh", project)
        self.assertIn("script/sign-steam-helper.sh", (ROOT / ".github/workflows/build.yml").read_text())
        publish = (ROOT / "script/publish-steam-helper.sh").read_text()
        self.assertIn("-p:TargetName=SteamService", publish)
        self.assertIn('$FRESH_DIR/SteamService.dll', publish)
    def test_project_and_release_workflow_freeze_arm64(self):
        project = (ROOT / "MyWallpaperX.xcodeproj/project.pbxproj").read_text()
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        self.assertEqual(project.count("ARCHS = arm64;"), 2)
        self.assertNotIn("MACOSX_DEPLOYMENT_TARGET = 26.2", project)
        self.assertIn("ARCHS=arm64", workflow)
        self.assertIn("ONLY_ACTIVE_ARCH=NO", workflow)
        self.assertIn("script/validate_apple_silicon_release.py", workflow)
        self.assertNotIn("arm64e", project + workflow)
        self.assertNotIn("-mcpu=native", project + workflow)

    def test_validator_parses_effective_settings_and_dependencies(self):
        validator = load_validator()
        settings = validator.parse_build_settings(
            "    ARCHS = arm64\n"
            "    MACOSX_DEPLOYMENT_TARGET = 26.0\n"
            "ignored\n"
        )
        self.assertEqual(settings["ARCHS"], "arm64")
        self.assertEqual(settings["MACOSX_DEPLOYMENT_TARGET"], "26.0")
        dependencies = validator.dependency_names(
            "/tmp/tool:\n"
            "\t@rpath/Thing.framework/Thing (compatibility version 1.0.0)\n"
            "\t/System/Library/Frameworks/AppKit.framework/AppKit (compatibility version 45.0.0)\n"
        )
        self.assertEqual(
            dependencies,
            ["@rpath/Thing.framework/Thing", "/System/Library/Frameworks/AppKit.framework/AppKit"],
        )
        rpaths = validator.rpath_names(
            "Load command 1\n"
            "          cmd LC_RPATH\n"
            "      cmdsize 48\n"
            "         path @executable_path/../Frameworks (offset 12)\n"
        )
        self.assertEqual(rpaths, ["@executable_path/../Frameworks"])

    def test_validator_distinguishes_owned_and_third_party_bundle_code(self):
        validator = load_validator()
        self.assertFalse(validator.is_third_party(Path("Contents/MacOS/MyWallpaperX")))
        self.assertFalse(
            validator.is_third_party(Path("Contents/Helpers/MyWallpaperXWallpaperDaemon"))
        )
        self.assertTrue(validator.is_third_party(Path("Contents/Helpers/glslang")))
        self.assertTrue(validator.is_third_party(Path("Contents/Helpers/spirv-cross")))
        self.assertTrue(
            validator.is_third_party(
                Path("Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle")
            )
        )


    def test_signed_permission_audit_rejects_missing_permissions_and_wrong_identity(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / 'Test.app'
            for relative in validator.REQUIRED_BUNDLE_EXECUTABLES:
                path = app / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture')
                path.chmod(0o755)
            downloader = app / 'Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc'
            downloader.mkdir(parents=True)
            permissions = {
                str(app): {'com.apple.security.automation.apple-events': True},
                str(app / 'Contents/Resources/SteamService/SteamService'): {'com.apple.security.cs.allow-jit': True},
                str(downloader): {'com.apple.security.app-sandbox': True},
            }
            details = ('Authority=Developer ID Application: Fixture (TEAM)\n'
                       'TeamIdentifier=TEAM\nCodeDirectory v=20500 flags=0x10000(runtime)\nTimestamp=fixture\n')
            calls = []
            def invoke(command, **kwargs):
                calls.append((command, kwargs))
                if command[0] == 'file': return 'Mach-O arm64 executable'
                if '--entitlements' in command:
                    return plistlib.dumps(permissions[command[-1]]).decode()
                if '--display' in command: return details
                return ''
            with mock.patch.object(validator, 'run_checked', side_effect=invoke):
                validator.validate_codesign(app, 'TEAM')
                for path, values in permissions.items():
                    key = next(iter(values))
                    values[key] = False
                    with self.subTest(path=path), self.assertRaisesRegex(RuntimeError, 'Required signed entitlement'):
                        validator.validate_codesign(app, 'TEAM')
                    values[key] = True
                permissions[str(app)]['com.apple.security.get-task-allow'] = True
                with self.assertRaisesRegex(RuntimeError, 'Development debugging'):
                    validator.validate_codesign(app, 'TEAM')
                del permissions[str(app)]['com.apple.security.get-task-allow']
                for invalid in [details.replace('TeamIdentifier=TEAM', 'TeamIdentifier=OTHER'),
                                details.replace('Authority=Developer ID Application:', 'Authority=Apple Development:'),
                                details.replace('(runtime)', '()'), details.replace('Timestamp=fixture', '')]:
                    original = details
                    details = invalid
                    with self.assertRaisesRegex(RuntimeError, 'Incomplete Developer ID signature'):
                        validator.validate_codesign(app, 'TEAM')
                    details = original
            metadata_calls = [kwargs for command, kwargs in calls if '--verbose=4' in command]
            self.assertTrue(metadata_calls)
            self.assertTrue(all(row.get('include_stderr') for row in metadata_calls))

    def test_signature_cli_does_not_repeat_unsigned_preparation(self):
        validator = load_validator()
        with mock.patch.object(sys, 'argv', ['validator', '--app', '/fixture/Test.app',
                                            '--signatures-only', '--expected-team-id', 'TEAM']), \
             mock.patch.object(validator, 'validate_codesign') as signed, \
             mock.patch.object(validator, 'validate_project') as project, \
             mock.patch.object(validator, 'validate_bundle') as bundle:
            self.assertEqual(validator.main(), 0)
            signed.assert_called_once_with(Path('/fixture/Test.app'), 'TEAM')
            project.assert_not_called()
            bundle.assert_not_called()
        with mock.patch.object(sys, 'argv', ['validator', '--app', '/fixture/Test.app', '--signatures-only']):
            with self.assertRaises(SystemExit): validator.main()

    def test_entitlement_reader_uses_the_actual_mach_o_signature(self):
        validator = load_validator()
        with tempfile.TemporaryDirectory(prefix='mwx-signed-permission-') as raw:
            directory = Path(raw)
            binary = directory / 'fixture'
            subprocess.run(['xcrun', 'clang', '-x', 'c', '-', '-o', str(binary)],
                           input='int main(void) { return 0; }', text=True, check=True,
                           capture_output=True)
            entitlement = directory / 'permissions.plist'
            key = 'com.apple.security.automation.apple-events'
            entitlement.write_bytes(plistlib.dumps({key: True}))
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                            '--entitlements', str(entitlement), str(binary)],
                           check=True, capture_output=True)
            # Editing the source plist cannot alter the already signed claim.
            entitlement.write_bytes(plistlib.dumps({key: False}))
            self.assertIs(validator.signed_entitlements(binary)[key], True)
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none', str(binary)],
                           check=True, capture_output=True)
            with self.assertRaisesRegex(RuntimeError, 'Signed entitlements are missing'):
                validator.signed_entitlements(binary)

    def test_symbols_archive_contains_app_and_daemon_and_rejects_missing_daemon(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        step = workflow.split('      - name: Archive release artifacts\n', 1)[1].split('      - name:', 1)[0]
        commands = textwrap.dedent(step.split('        run: |\n', 1)[1])
        for include_daemon in [True, False]:
            with self.subTest(include_daemon=include_daemon), tempfile.TemporaryDirectory() as raw:
                directory = Path(raw)
                products = directory / 'derived/Build/Products/Release'
                names = ['MyWallpaperX.app.dSYM'] + (['MyWallpaperXWallpaperDaemon.dSYM'] if include_daemon else [])
                for name in names:
                    dwarf = products / name / 'Contents/Resources/DWARF'
                    dwarf.mkdir(parents=True)
                    (dwarf / 'symbol').write_text(name)
                dist = directory / 'dist'; dist.mkdir()
                (dist / 'package.dmg').write_bytes(b'dmg fixture')
                env = os.environ.copy()
                env.update(DERIVED_DATA_PATH=str(directory / 'derived'), CONFIGURATION='Release',
                           DIST_DIR=str(dist), PACKAGE_NAME='package', APP_NAME='MyWallpaperX',
                           RUNNER_TEMP=str(directory))
                result = subprocess.run(['/bin/bash', '-euo', 'pipefail', '-c', commands], env=env,
                                        capture_output=True, text=True)
                archive = dist / 'package.dSYM.zip'
                if include_daemon:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    with zipfile.ZipFile(archive) as zipped:
                        files = zipped.namelist()
                    for name in names:
                        self.assertTrue(any('/' + name + '/Contents/Resources/DWARF/symbol' in path for path in files))
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(archive.exists())


if __name__ == "__main__":
    unittest.main()
