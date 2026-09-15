"""Static and pure-function gates for the AS0 Apple Silicon release contract."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
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
