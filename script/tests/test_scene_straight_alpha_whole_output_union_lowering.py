#!/usr/bin/env python3

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

private struct Output: Codable {
    let accepted: Bool
    let sampleUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let wrongSlotRejected: Bool
    let extraBindingRejected: Bool
    let componentWriteRejected: Bool
    let outputReadRejected: Bool
    let earlyReturnRejected: Bool
    let helperCollisionRejected: Bool
}

@main
private struct WholeOutputUnionHarness {
    static func main() throws {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Output { float4 mwxFragColor [[color(0)]]; };
        fragment Output mwxGenericFragment(
            texture2d<float> g_Texture0 [[texture(0)]],
            sampler g_Texture0Smplr [[sampler(0)]]) {
            Output out = {};
            float4 albedo = g_Texture0.sample(g_Texture0Smplr, float2(0.5));
            if (albedo.w > 0.5) {
                out.mwxFragColor = float4(1.0);
            } else {
                out.mwxFragColor = albedo;
            }
            return out;
        }
        """
        func lower(_ value: String) -> String? {
            SceneGenericShaderStraightAlphaPreservingLowering
                .lowerWholeOutputUnion(value, expectedSlot: 0)
        }
        let accepted = lower(source)
        let extraBinding = source.replacingOccurrences(
            of: "texture2d<float> g_Texture0 [[texture(0)]],",
            with: "texture2d<float> g_Texture0 [[texture(0)]],\n"
                + "    texture2d<float> g_Texture1 [[texture(1)]],"
        )
        let componentWrite = source.replacingOccurrences(
            of: "out.mwxFragColor = float4(1.0);",
            with: "out.mwxFragColor.x = 1.0;"
        )
        let outputRead = source.replacingOccurrences(
            of: "    return out;",
            with: "    float4 leaked = out.mwxFragColor;\n    return out;"
        )
        let earlyReturn = source.replacingOccurrences(
            of: "    return out;",
            with: "    if (false) { return out; }\n    return out;"
        )
        let helperCollision = source.replacingOccurrences(
            of: "using namespace metal;",
            with: "using namespace metal;\nfloat4 mwxGenericPremultiply(float4 value);"
        )
        let output = Output(
            accepted: accepted != nil,
            sampleUnpremultiplied: accepted?.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample"
            ) == true,
            outputPremultiplied: accepted?.contains(
                "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);"
            ) == true,
            wrongSlotRejected: lower(
                source.replacingOccurrences(
                    of: "g_Texture0",
                    with: "g_Texture1"
                )
            ) == nil,
            extraBindingRejected: lower(extraBinding) == nil,
            componentWriteRejected: lower(componentWrite) == nil,
            outputReadRejected: lower(outputRead) == nil,
            earlyReturnRejected: lower(earlyReturn) == nil,
            helperCollisionRejected: lower(helperCollision) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneStraightAlphaWholeOutputUnionLoweringTests(unittest.TestCase):
    def test_whole_output_union_is_lowered_and_unsafe_shapes_fail_closed(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-straight-whole-output-union-"
        ) as directory:
            root = Path(directory)
            harness = root / "WholeOutputUnionHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "whole-output-union-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(
                root / "clang-module-cache"
            )
            environment["SWIFT_MODULECACHE_PATH"] = str(
                root / "swift-module-cache"
            )
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            output = json.loads(completed.stdout)
            self.assertEqual(
                output,
                {
                    "accepted": True,
                    "sampleUnpremultiplied": True,
                    "outputPremultiplied": True,
                    "wrongSlotRejected": True,
                    "extraBindingRejected": True,
                    "componentWriteRejected": True,
                    "outputReadRejected": True,
                    "earlyReturnRejected": True,
                    "helperCollisionRejected": True,
                },
            )


if __name__ == "__main__":
    unittest.main()
