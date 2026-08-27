#!/usr/bin/env python3
"""Typed color inputs lower only the exact bound provider slot."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]


HARNESS = r'''
import Foundation

private struct Result: Codable {
    let boundedAccepted: Bool
    let boundedWrapsOnlySlotOne: Bool
    let boundedUntypedCacheEntryStaysRaw: Bool
    let boundedMissingSlotRejected: Bool
    let genericWrapsOnlySlotOne: Bool
    let genericMissingSlotRejected: Bool
}

@main
private enum Harness {
    static func main() throws {
        let vertex = """
        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;
        varying vec2 v_TexCoord;
        void main() {
            gl_Position = vec4(a_Position, 1.0);
            v_TexCoord = a_TexCoord;
        }
        """
        let fragment = """
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1;
        uniform sampler2D g_Texture2;
        varying vec2 v_TexCoord;
        void main() {
            vec4 base = texSample2D(g_Texture0, v_TexCoord);
            vec4 provider = texSample2D(g_Texture1, v_TexCoord);
            float data = texSample2D(g_Texture2, v_TexCoord).r;
            gl_FragColor = vec4(
                mix(base.rgb, provider.rgb, data),
                base.a
            );
        }
        """
        let bounded = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha,
            premultipliedColorInputSlots: [1]
        )
        let boundedSource = bounded.program?.metalSource ?? ""
        let boundedCompact = boundedSource.replacingOccurrences(
            of: " ",
            with: ""
        )
        let untyped = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha
        )
        let untypedCompact = (untyped.program?.metalSource ?? "")
            .replacingOccurrences(of: " ", with: "")
        let missing = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex,
            fragmentSource: fragment,
            provenColorTransfer: .premultipliedAlpha,
            premultipliedColorInputSlots: [3]
        )

        let genericMSL = """
        #include <metal_stdlib>
        using namespace metal;
        inline float4 mwxGenericUnpremultiply(float4 color) {
            return color;
        }
        fragment float4 mwxGenericFragment(
            texture2d<float> g_Texture0 [[texture(0)]],
            texture2d<float> g_Texture1 [[texture(1)]],
            texture2d<float> g_Texture2 [[texture(2)]],
            sampler linearSampler [[sampler(0)]]
        ) {
            float4 base = g_Texture0.sample(linearSampler, float2(0.5));
            float4 provider = g_Texture1.sample(linearSampler, float2(0.5));
            float data = g_Texture2.sample(linearSampler, float2(0.5)).r;
            return float4(mix(base.rgb, provider.rgb, data), base.a);
        }
        """
        let generic = SceneGenericShaderArtifactBuilder
            .lowerPremultipliedColorInputs(genericMSL, slots: [1]) ?? ""
        let genericCompact = generic.replacingOccurrences(of: " ", with: "")
        let missingGeneric = SceneGenericShaderArtifactBuilder
            .lowerPremultipliedColorInputs(genericMSL, slots: [3])

        let result = Result(
            boundedAccepted:
                bounded.diagnostics.isEmpty && bounded.program != nil,
            boundedWrapsOnlySlotOne:
                boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture1.sample("
                )
                && !boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture0.sample("
                )
                && !boundedCompact.contains(
                    "mwxUnpremultiply(mwxTexture2.sample("
                ),
            boundedUntypedCacheEntryStaysRaw:
                untyped.program != nil
                && !untypedCompact.contains(
                    "mwxUnpremultiply(mwxTexture1.sample("
                ),
            boundedMissingSlotRejected:
                missing.program == nil
                && missing.diagnostics.contains(where: {
                    $0.code == .unsupportedSampler
                }),
            genericWrapsOnlySlotOne:
                genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture1.sample("
                )
                && !genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture0.sample("
                )
                && !genericCompact.contains(
                    "mwxGenericUnpremultiply(g_Texture2.sample("
                ),
            genericMissingSlotRejected: missingGeneric == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    }
}
'''


class SceneGenericShaderTypedInputLoweringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-typed-input-lowering-test-"
        )
        build_root = Path(cls.build_directory.name)
        harness = build_root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "typed-input-lowering-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        completed = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_exact_provider_slot_is_lowered_and_other_slots_remain_raw(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            json.loads(completed.stdout),
            {
                "boundedAccepted": True,
                "boundedWrapsOnlySlotOne": True,
                "boundedUntypedCacheEntryStaysRaw": True,
                "boundedMissingSlotRejected": True,
                "genericWrapsOnlySlotOne": True,
                "genericMissingSlotRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
