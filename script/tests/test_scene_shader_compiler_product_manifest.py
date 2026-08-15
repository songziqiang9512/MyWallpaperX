#!/usr/bin/env python3

import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
DEVELOPMENT_MANIFEST = ROOT / "script/scene_shader_compiler_dependencies.json"
RESOURCE_ROOT = ROOT / "MyWallpaperX/Resources"
LICENSE_BUNDLE = RESOURCE_ROOT / "SceneShaderCompilerLicenses.bundle"
PRODUCT_MANIFEST = LICENSE_BUNDLE / "Contents/Resources/product-manifest.json"
TOOL_ROOT = RESOURCE_ROOT / "SceneShaderCompilerTools"
PROJECT = ROOT / "MyWallpaperX.xcodeproj/project.pbxproj"


class SceneShaderCompilerProductManifestTests(unittest.TestCase):
    def test_product_manifest_matches_reproducible_source_artifacts(self):
        development = json.loads(DEVELOPMENT_MANIFEST.read_text(encoding="utf-8"))
        product = json.loads(PRODUCT_MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(product["schemaVersion"], 1)
        self.assertTrue(product["productExecutionAuthorized"])
        self.assertEqual(product["backendID"], development["backendID"])
        self.assertEqual(product["limits"], development["limits"])
        for product_name, development_name, file_name in (
            ("glslang", "glslang", "glslang"),
            ("spirvCross", "spirvCross", "spirv-cross"),
        ):
            product_tool = product["helpers"][product_name]
            development_tool = development["tools"][development_name]
            self.assertEqual(product_tool["fileName"], file_name)
            for key in ("revision", "versionProbeContains", "versionProbeExitCode"):
                self.assertEqual(product_tool[key], development_tool[key])
            data = (TOOL_ROOT / file_name).read_bytes()
            self.assertEqual(
                hashlib.sha256(data).hexdigest(),
                product_tool["sourceArtifactSHA256"],
            )

    def test_helpers_are_arm64_mach_o_and_codesigned_on_copy(self):
        project = PROJECT.read_text(encoding="utf-8")
        for file_name in ("glslang", "spirv-cross"):
            output = subprocess.run(
                ["/usr/bin/file", str(TOOL_ROOT / file_name)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            self.assertIn("Mach-O 64-bit executable arm64", output)
            self.assertIn(
                f"Resources/SceneShaderCompilerTools/{file_name}", project
            )
            self.assertRegex(
                project,
                rf"{file_name} in CopyFiles.*CodeSignOnCopy",
            )
        self.assertIn("dstPath = Contents/Helpers;", project)

    def test_all_declared_upstream_licenses_are_bundled(self):
        development = json.loads(DEVELOPMENT_MANIFEST.read_text(encoding="utf-8"))
        resources = LICENSE_BUNDLE / "Contents/Resources"
        for name in ("glslang", "spirvCross"):
            folder = resources / ("spirv-cross" if name == "spirvCross" else name)
            for relative in development["tools"][name]["licenseFiles"]:
                self.assertTrue((folder / Path(relative).name).is_file(), relative)
        with (LICENSE_BUNDLE / "Contents/Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertEqual(info["CFBundlePackageType"], "BNDL")


if __name__ == "__main__":
    unittest.main()
