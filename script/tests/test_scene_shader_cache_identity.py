#!/usr/bin/env python3
"""Build producer changes invalidate; unrelated UI edits preserve warm identity."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "script"))
from generate_scene_shader_cache_identity import (
    SEMANTIC_DIRECTORIES, SEMANTIC_FILES, TOOLCHAIN_FILES,
    build_identity, write_identity,
)
from scene_shader_compiler_request_contract import request_cache_key
from script.tests.test_scene_shader_compiler_request_contract import request


class SceneShaderCacheBuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mwx-cache-identity-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for path in SEMANTIC_DIRECTORIES:
            (self.root / path).mkdir(parents=True, exist_ok=True)
            (self.root / path / "Producer.swift").write_text("let value = 1\n")
        for path in (*SEMANTIC_FILES, *TOOLCHAIN_FILES):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"bounded fixture\n")

    def test_content_add_remove_and_shared_input_change_identity(self):
        original = build_identity(self.root)
        new = self.root / SEMANTIC_DIRECTORIES[0] / "NewRule.swift"
        new.write_text("let rule = 1\n")
        added = build_identity(self.root)
        self.assertNotEqual(original["semantics"], added["semantics"])
        new.write_text("let rule = 2\n")
        self.assertNotEqual(added["semantics"], build_identity(self.root)["semantics"])
        new.unlink()
        self.assertEqual(original, build_identity(self.root))
        (self.root / SEMANTIC_FILES[0]).write_text("changed shared ABI\n")
        self.assertNotEqual(original["semantics"], build_identity(self.root)["semantics"])

    def test_root_mtime_and_unrelated_app_change_do_not_invalidate(self):
        original = build_identity(self.root)
        source = self.root / SEMANTIC_FILES[0]
        source.touch()
        ui = self.root / "MyWallpaperX/Shell/NewUI.swift"
        ui.parent.mkdir(parents=True)
        ui.write_text("let unrelated = true\n")
        self.assertEqual(original, build_identity(self.root))
        other = self.root / "copy"
        shutil.copytree(self.root / "MyWallpaperX", other / "MyWallpaperX")
        shutil.copytree(self.root / "script", other / "script")
        self.assertEqual(original, build_identity(other))

    def test_tool_binary_manifest_and_compilation_configuration(self):
        original = build_identity(self.root)
        for path in TOOLCHAIN_FILES:
            target = self.root / path
            snapshot = target.read_bytes()
            target.write_bytes(snapshot + b"changed")
            changed = build_identity(self.root)
            self.assertNotEqual(original["toolchain"], changed["toolchain"])
            self.assertEqual(original["semantics"], changed["semantics"])
            target.write_bytes(snapshot)
        self.assertNotEqual(original["semantics"],
                            build_identity(self.root, {"SWIFT_VERSION": "6"})["semantics"])

    def test_real_external_sampler_purpose_rule_is_part_of_producer(self):
        # This actual call-site dependency changes cached sourceProvenPurpose,
        # even when no authored shader or Compilation source changes.
        relative = Path("MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneStockTextureSemanticRegistry.swift")
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / relative).read_bytes())
        before = build_identity(self.root)
        target.write_text(target.read_text().replace('case "effects/waterripplenormal": .normal', 'case "effects/waterripplenormal": .phase'))
        after = build_identity(self.root)
        self.assertNotEqual(before["semantics"], after["semantics"])

    def test_same_identity_does_not_rewrite_output(self):
        output = self.root / "result/SceneShaderCacheIdentity.json"
        identity = build_identity(self.root)
        self.assertTrue(write_identity(output, identity))
        self.assertEqual(output.stat().st_mode & 0o777, 0o644)
        before = output.stat().st_mtime_ns
        output.chmod(0o600)
        self.assertFalse(write_identity(output, identity))
        self.assertEqual(output.stat().st_mode & 0o777, 0o644)
        self.assertEqual(before, output.stat().st_mtime_ns)
        self.assertEqual(json.loads(output.read_text()), identity)

    def test_missing_or_symlink_input_fails_the_build(self):
        target = self.root / TOOLCHAIN_FILES[0]
        target.unlink()
        with self.assertRaises(ValueError):
            build_identity(self.root)
        target.symlink_to(self.root / SEMANTIC_FILES[0])
        with self.assertRaises(ValueError):
            build_identity(self.root)

    def test_current_request_identity_and_historical_replay(self):
        legacy = request()
        current = {**legacy, "schemaVersion": 8,
                   "compilerIdentity": "a" * 64, "toolchainIdentity": "b" * 64}
        self.assertNotEqual(request_cache_key(legacy), request_cache_key(current))
        for name in ("compilerIdentity", "toolchainIdentity"):
            changed = {**current, name: "c" * 64}
            self.assertNotEqual(request_cache_key(current), request_cache_key(changed))
        self.assertEqual(request_cache_key(current), request_cache_key(copy.deepcopy(current)))
        # Old App exports used schema7 with v34 after the Python v33 contract.
        import hashlib
        fields = ["mwx-generic-shader-request-v34", legacy["sourceDialect"],
                  "color", *(stage["source"] for stage in legacy["stages"]),
                  "independent-alpha-signal-preserving:1", "2", "0,3",
                  "color=0,3|output=premultiplied-alpha|signal=0", "0,3,7", "{}"]
        # Build the known v34 candidate by replacing only the historical framed
        # prefix in a schema7 key; the exported requestID must select it.
        from scene_shader_compiler_input_color_contract import ordinary_boundary_cache_key
        fields[-3] = ordinary_boundary_cache_key(legacy["colorBoundary"])
        digest = hashlib.sha256()
        for value in fields:
            encoded = value.encode()
            digest.update(len(encoded).to_bytes(8, "big"))
            digest.update(encoded)
        captured = {**legacy, "requestID": digest.hexdigest()}
        self.assertEqual(request_cache_key(captured), captured["requestID"])

    @unittest.skipUnless(shutil.which("swiftc"), "swiftc required")
    def test_runtime_reads_valid_metadata_once_and_missing_metadata_is_process_private(self):
        source = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderCacheIdentity.swift"
        harness = self.root / "Probe.swift"
        harness.write_text('''import Foundation
@main enum Probe {
    static func main() throws {
        let first = SceneShaderCacheIdentity.semantics
        if CommandLine.arguments.count > 1 {
            try Data("invalid".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print(first + ":" + SceneShaderCacheIdentity.semantics + ":" + SceneShaderCacheIdentity.toolchain)
    }
}
''')
        binary = self.root / "probe"
        subprocess.run(["swiftc", "-parse-as-library", str(source), str(harness),
                        "-module-cache-path", str(self.root / "module-cache"), "-o", str(binary)],
                       check=True, capture_output=True, text=True)
        resource = self.root / "SceneShaderCacheIdentity.json"
        identity = {"schemaVersion": 1, "semantics": "a" * 64, "toolchain": "b" * 64}
        write_identity(resource, identity)
        observed = subprocess.check_output([str(binary), str(resource)], text=True).strip()
        self.assertEqual(observed, ":".join(["a" * 64, "a" * 64, "b" * 64]))
        missing1 = subprocess.check_output([str(binary)], text=True).strip()
        missing2 = subprocess.check_output([str(binary)], text=True).strip()
        self.assertNotEqual(missing1, missing2)
        self.assertTrue(missing1.startswith("process-private-"))


if __name__ == "__main__":
    unittest.main()
