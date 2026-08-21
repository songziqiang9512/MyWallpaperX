#!/usr/bin/env python3

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/SceneMaterialRenderState.swift"
)

HARNESS = r"""
import Foundation

@main
enum Harness {
    static func main() throws {
        let enabled = SceneMaterialRenderState.compile(
            blending: " Normal ",
            depthTest: "DISABLED",
            depthWrite: "disabled",
            cullMode: "NoCull",
            alphaWriting: "enabled"
        )
        let unspecified = SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )
        let defaultAlpha = SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: "default"
        )
        let particleDefault = SceneMaterialRenderState.compile(
            blending: nil,
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil,
            missingBlending: .translucent
        )
        let result: [String: Any] = [
            "enabledCompiled": enabled != nil,
            "enabledRawPreserved": enabled?.rawValues.blending == " Normal ",
            "enabledMatches": enabled?.matchesFullscreenOverwrite(
                alphaWriting: .enabled
            ) == true,
            "enabledDoesNotMatchUnspecified": enabled?.matchesFullscreenOverwrite(
                alphaWriting: .unspecified
            ) == false,
            "enabledResolvedOverwrite": enabled?.supportsResolvedMaterialFullscreenOverwrite == true,
            "unspecifiedMatches": unspecified?.matchesFullscreenOverwrite(
                alphaWriting: .unspecified
            ) == true,
            "unspecifiedResolvedOverwrite": unspecified?.supportsResolvedMaterialFullscreenOverwrite == true,
            "defaultPreserved": defaultAlpha?.alphaWriting == .default,
            "defaultNotExecutableAsEnabled": defaultAlpha?.matchesFullscreenOverwrite(
                alphaWriting: .enabled
            ) == false,
            "defaultResolvedOverwriteRejected": defaultAlpha?.supportsResolvedMaterialFullscreenOverwrite == false,
            "particleDefaultTyped": particleDefault?.blending == .translucent,
            "particleDefaultRawMissing": particleDefault?.rawValues.blending == nil,
            "stateIdentityIncludesAlpha": enabled != unspecified,
            "unknownBlendRejected": SceneMaterialRenderState.compile(
                blending: "multiply",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull",
                alphaWriting: nil
            ) == nil,
            "unknownAlphaRejected": SceneMaterialRenderState.compile(
                blending: "normal",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull",
                alphaWriting: "sometimes"
            ) == nil,
            "missingDepthRejected": SceneMaterialRenderState.compile(
                blending: "normal",
                depthTest: nil,
                depthWrite: "disabled",
                cullMode: "nocull",
                alphaWriting: nil
            ) == nil,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
"""


class SceneMaterialRenderStateCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-material-render-state-"
        )
        build_root = Path(cls.temporary_directory.name)
        harness = build_root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "material-render-state"
        subprocess.run(
            [swiftc, str(SOURCE), str(harness), "-o", str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_known_state_is_typed_and_raw_values_are_preserved(self) -> None:
        self.assertTrue(self.result["enabledCompiled"])
        self.assertTrue(self.result["enabledRawPreserved"])
        self.assertTrue(self.result["enabledMatches"])
        self.assertTrue(self.result["enabledDoesNotMatchUnspecified"])
        self.assertTrue(self.result["unspecifiedMatches"])
        self.assertTrue(self.result["defaultPreserved"])
        self.assertTrue(self.result["defaultNotExecutableAsEnabled"])
        self.assertTrue(self.result["stateIdentityIncludesAlpha"])

    def test_caller_default_does_not_replace_authored_raw_identity(self) -> None:
        self.assertTrue(self.result["particleDefaultTyped"])
        self.assertTrue(self.result["particleDefaultRawMissing"])

    def test_unknown_or_incomplete_state_fails_closed(self) -> None:
        self.assertTrue(self.result["unknownBlendRejected"])
        self.assertTrue(self.result["unknownAlphaRejected"])
        self.assertTrue(self.result["missingDepthRejected"])


if __name__ == "__main__":
    unittest.main()
