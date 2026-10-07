"""Static and pure-function gates for the AS0 Apple Silicon release contract."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import os
import subprocess
import textwrap
import unittest
import json
import tempfile


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


if __name__ == "__main__":
    unittest.main()
