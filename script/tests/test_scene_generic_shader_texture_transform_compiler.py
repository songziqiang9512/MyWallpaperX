#!/usr/bin/env python3

"""Real Swift generic compiler artifacts through Program/PassEncoder and Metal."""

from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_material_texture_transform import (
    COORDINATE_HARNESS,
    REPOSITORY_ROOT,
    SCENE_ROOT,
    SUPPORT,
    SWIFT_SOURCES,
    assert_companion_pixels,
    assert_companion_rejections,
    assert_coordinate_pixels,
    fixture_environment,
    preserve_evidence,
    source_hashes,
)
from scene_swift_source_sets import scene_swift_sources


GENERIC_SOURCES = list(dict.fromkeys([
    *SWIFT_SOURCES,
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialGenericShaderRequest.swift",
]))

HARNESS = COORDINATE_HARNESS + r'''
@main private enum Main {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let bundle = Bundle(path: CommandLine.arguments[1]) else {
            throw NSError(domain: "compiler-bundle", code: 1)
        }
        let cache = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var artifacts: [String: Any] = [:]
        let compileFixture: (CoordinateFixture) throws -> SceneAuthoredShaderProgram = { fixture in
            let key = SceneResolvedMaterialGenericShaderRequest.key(
                vertexSource: fixture.vertex, fragmentSource: fixture.fragment,
                outputSemantics: .color, expectedColorTransfer: nil,
                premultipliedColorInputSlots: [])
            let url: URL
            switch SceneGenericShaderCompiler.compile(requestKey: key,
                vertexSource: fixture.vertex, fragmentSource: fixture.fragment,
                cacheRoot: cache, bundle: bundle) {
            case let .success(value): url = value
            case let .failure(failure):
                throw NSError(domain: "actual-swift-compiler-\(fixture.name)", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(describing: failure)])
            }
            let data = try Data(contentsOf: url)
            let artifact = try JSONDecoder().decode(SceneGenericShaderProgramArtifact.self,
                from: data)
            // The source-proven output contract is the same authority used by Program.
            // It is not a hand-authored MSL artifact or a substitute compiler.
            guard let contract = SceneAuthoredShaderFrontend.compile(
                    vertexSource: fixture.vertex, fragmentSource: fixture.fragment).program,
                  let frontend = artifact.makeProgram(expectedKey: key,
                    expectedColorTransfer: contract.colorTransfer,
                    expectedFragmentOutputChannelUse: contract.fragmentOutputChannelUse) else {
                throw NSError(domain: "artifact-program-\(fixture.name)", code: 1)
            }
            artifacts[fixture.name] = [
                "requestKey": key, "schemaVersion": artifact.schemaVersion,
                "artifactSHA256": SceneGenericShaderProgramArtifact.sha256(data),
                "publishedPath": url.path,
                "metalSHA256": artifact.program.metalSourceSHA256,
            ]
            return frontend
        }
        var result = try runCoordinates(generic: true, frontend: compileFixture)
        result["companions"] = try runCompanions(generic: true, frontend: compileFixture)
        result["artifacts"] = artifacts
        result["compiler"] = "SceneGenericShaderCompiler.compile"
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
    }
}
'''


def compiler_bundle(root: Path) -> Path:
    """Copy and sign only temporary helpers, preserving the real resolver checks."""
    resources = REPOSITORY_ROOT / "MyWallpaperX/Resources"
    bundle = root / "Compiler.bundle"
    contents = bundle / "Contents"
    (contents / "Resources").mkdir(parents=True)
    (contents / "Helpers").mkdir()
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.mywallpaperx.self-authored-coordinate-test",
        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1",
    }))
    shutil.copytree(resources / "SceneShaderCompilerLicenses.bundle",
                    contents / "Resources/SceneShaderCompilerLicenses.bundle")
    signing_identity = os.environ.get(
        "MWX_SCENE_TEST_SIGNING_IDENTITY",
        "Developer ID Application: Ziqiang Song (H9QWU9XN8R)",
    )
    for name in ("glslang", "spirv-cross"):
        target = contents / "Helpers" / name
        shutil.copy2(resources / "SceneShaderCompilerTools" / name, target)
        signed = subprocess.run([
            "/usr/bin/codesign", "--force", "--sign", signing_identity,
            "--timestamp=none", str(target),
        ], capture_output=True, text=True, timeout=30)
        if signed.returncode:
            raise RuntimeError("Temporary product helper signing failed: " + signed.stderr)
    return bundle


class SceneGenericShaderTextureTransformCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-generic-coordinate-")
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        root = Path(cls.temporary_directory.name)
        bundle = compiler_bundle(root)
        support, harness, binary = root / "Support.swift", root / "Harness.swift", root / "probe"
        support.write_text(SUPPORT, encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        inputs = [*GENERIC_SOURCES, support, harness,
            *(path for path in bundle.rglob("*") if path.is_file())]
        before = source_hashes(inputs)
        command = [
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            str(support), *map(str, GENERIC_SOURCES), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "Security",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ]
        environment = fixture_environment(root)
        compilation = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
            capture_output=True, text=True, timeout=180)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary), str(bundle), str(root / "artifacts")],
            cwd=root, env=environment, capture_output=True, text=True, timeout=120)
        after = source_hashes(inputs)
        preserve_evidence(root, "generic", before, after, command, compilation, completed)
        if before != after:
            raise RuntimeError("Compilation inputs changed during the generic coordinate gate")
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["metalAvailable"]:
            raise unittest.SkipTest("Metal is unavailable; no generic coordinate behavior evidence")

    def test_actual_swift_compiler_artifact_preserves_authored_coordinates_on_gpu(self) -> None:
        assert_coordinate_pixels(self, self.result, "genericCompilerArtifact")
        self.assertEqual(self.result["compiler"], "SceneGenericShaderCompiler.compile")
        all_fixtures = self.result["fixtures"] | self.result["companions"]["fixtures"]
        self.assertEqual(set(self.result["artifacts"]), set(all_fixtures))
        for name, artifact in self.result["artifacts"].items():
            with self.subTest(fixture=name):
                self.assertEqual(artifact["metalSHA256"], all_fixtures[name]["metalSHA256"])
                self.assertEqual(len(artifact["requestKey"]), 64)
                self.assertEqual(len(artifact["artifactSHA256"]), 64)

    def test_reviewed_companion_profiles_use_actual_compiler_and_gpu(self) -> None:
        assert_companion_pixels(self, self.result, "genericCompilerArtifact")

    def test_compiled_companion_shape_binding_and_program_boundaries_fail_closed(self) -> None:
        assert_companion_rejections(self, self.result)


if __name__ == "__main__":
    unittest.main()
