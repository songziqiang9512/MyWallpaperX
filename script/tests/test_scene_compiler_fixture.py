"""Execute both the unmodified product trust policy and isolated fixture policy."""
import os
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from script.tests.scene_compiler_fixture import RESOLVER, compiler_bundle, fixture_sources

PROBE = r'''
import Foundation
@main enum Probe {
    static func main() {
        guard let bundle = Bundle(path: CommandLine.arguments[1]) else { fatalError("bundle") }
        switch SceneGenericShaderCompilerBundle.resolve(bundle: bundle) {
        case .success: print("resolved")
        case let .failure(failure): print(String(describing: failure))
        }
    }
}
'''


class SceneCompilerFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-compiler-fixture-trust-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        # Any accidental return to the personal identity dependency fails here.
        with patch.dict(os.environ, {"MWX_SCENE_TEST_SIGNING_IDENTITY": "Unavailable CI identity"}):
            cls.original_bundle = compiler_bundle(cls.root)
        fixture = fixture_sources(cls.root, cls.original_bundle, [RESOLVER])
        probe = cls.root / "Probe.swift"
        probe.write_text(PROBE)
        cls.binaries = {}
        for mode, sources in (("product", [RESOLVER]), ("fixture", fixture)):
            binary = cls.root / mode
            built = subprocess.run(["swiftc", "-parse-as-library", *map(str, sources), str(probe),
                "-framework", "Security", "-module-cache-path", str(cls.root / "cache"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            if built.returncode:
                raise AssertionError(built.stderr)
            cls.binaries[mode] = binary

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mwx-compiler-fixture-case-", dir=self.root)
        self.addCleanup(temporary.cleanup)
        self.bundle = Path(temporary.name) / "Compiler.bundle"
        shutil.copytree(self.original_bundle, self.bundle)
        self.helper = self.bundle / "Contents/Helpers/glslang"

    def resolve(self, mode="fixture"):
        result = subprocess.run([str(self.binaries[mode]), str(self.bundle)],
            capture_output=True, text=True, check=True, timeout=15)
        return result.stdout.strip()

    def test_fixture_runs_without_personal_signing_identity(self):
        self.assertEqual(self.resolve(), "resolved")

    def test_unmodified_product_policy_rejects_fixture_authority(self):
        self.assertEqual(self.resolve("product"), 'helperSignatureInvalid("glslang")')

    def test_modified_code_is_rejected_even_with_original_code_directory(self):
        data = bytearray(self.helper.read_bytes())
        self.assertGreater(len(data), 8192)
        data[8192] ^= 1
        self.helper.write_bytes(data)
        self.assertEqual(self.resolve(), 'helperSignatureInvalid("glslang")')

    def test_validly_resigned_other_program_is_rejected(self):
        shutil.copyfile("/usr/bin/true", self.helper)
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(self.helper)],
            capture_output=True, check=True)
        self.assertEqual(self.resolve(), 'helperSignatureInvalid("glslang")')

    def test_helper_identities_cannot_be_swapped(self):
        shutil.copy2(self.bundle / "Contents/Helpers/spirv-cross", self.helper)
        self.assertEqual(self.resolve(), 'helperSignatureInvalid("glslang")')

    def test_symbolic_link_is_rejected_before_signature_validation(self):
        self.helper.unlink()
        self.helper.symlink_to(self.original_bundle / "Contents/Helpers/glslang")
        self.assertEqual(self.resolve(), 'helperUnavailable("glslang")')

    def test_manifest_authorization_is_still_required(self):
        manifest = self.bundle / "Contents/Resources/SceneShaderCompilerLicenses.bundle/Contents/Resources/product-manifest.json"
        data = json.loads(manifest.read_text())
        data["productExecutionAuthorized"] = False
        manifest.write_text(json.dumps(data))
        self.assertEqual(self.resolve(), "productExecutionUnauthorized")

    def test_fixture_edits_select_security_and_actual_compiler_regressions(self):
        from script.verify_scene_change import load_registry, mapped_tests
        modules, _, _ = mapped_tests(["script/tests/scene_compiler_fixture.py"], load_registry())
        self.assertEqual(modules, {"test_scene_compiler_fixture",
            "test_scene_generic_shader_texture_transform_compiler", "test_scene_previous_composite_scale"})
        unrelated, _, _ = mapped_tests(["script/tests/scene_compiler_fixture_notes.py"], load_registry())
        self.assertEqual(unrelated, set())
