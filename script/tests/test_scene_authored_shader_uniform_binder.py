#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneMaterialRenderState.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderExecutionPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderUniformBinder.swift",
]


HARNESS = r'''
import Foundation
import simd

@main
enum Harness {
    typealias Field = SceneAuthoredShaderUniformLayout.Field
    typealias Binding = SceneAuthoredShaderExecutionPlan.UniformBinding

    static func field(
        _ name: String,
        _ type: SceneAuthoredShaderValueType,
        _ offset: Int
    ) -> Field {
        .init(name: name, type: type, offset: offset)
    }

    static func plan() -> SceneAuthoredShaderExecutionPlan {
        let fields = [
            field("mwxRenderSize", .float2, 0),
            field("g_ModelViewProjectionMatrix", .float4x4, 16),
            field("g_Time", .float, 80),
            field("g_Daytime", .float, 84),
            field("g_Frametime", .float, 88),
            field("g_PointerPosition", .float2, 96),
            field("g_PointerPositionLast", .float2, 104),
            field("g_TexelSize", .float2, 112),
            field("g_TexelSizeHalf", .float2, 120),
            field("g_Screen", .float3, 128),
            field("g_Texture0Resolution", .float4, 144),
            field("u_Int", .int2, 160),
            field("u_UInt", .uint2, 168),
            field("u_Color", .float3, 176),
            field("u_Scalar", .float, 192),
        ]
        let sources: [Binding.Source] = [
            .renderSize,
            .modelViewProjection,
            .time,
            .dayTime,
            .frameTime,
            .pointerPosition,
            .pointerPositionLast,
            .texelSize(scale: 1),
            .texelSize(scale: 0.5),
            .screen,
            .textureResolution(slot: 0),
            .constant([-2, 3]),
            .constant([4, 5]),
            .constant([0.25, 0.5, 0.75]),
            .constant([1.5]),
        ]
        let layout = SceneAuthoredShaderUniformLayout(fields: fields, byteSize: 208)
        let program = SceneAuthoredShaderProgram(
            metalSource: "",
            vertexFunctionName: "vertex",
            fragmentFunctionName: "fragment",
            uniformLayout: layout,
            textureBindings: [.init(name: "g_Texture0", slot: 0)],
            staticLoopWork: 1
        )
        let renderState = SceneMaterialRenderState.compile(
            blending: "normal",
            depthTest: "disabled",
            depthWrite: "disabled",
            cullMode: "nocull",
            alphaWriting: nil
        )!
        return .init(
            cacheKey: "fixture",
            program: program,
            renderState: renderState,
            mappedSize: CGSize(width: 128, height: 64),
            framebufferTextureSlots: [0],
            uniformBindings: zip(fields, sources).map {
                .init(field: $0.0, source: $0.1)
            }
        )
    }

    static func inputs(
        screenSize: CGSize = CGSize(width: 1920, height: 1080),
        dayTime: Float = 0.5,
        pointer: SIMD2<Float> = SIMD2(-1, 1),
        textureSizes: [Int: CGSize] = [0: CGSize(width: 32, height: 16)]
    ) -> SceneAuthoredShaderUniformInputs {
        .init(
            renderSize: CGSize(width: 32, height: 16),
            screenSize: screenSize,
            modelViewProjection: simd_float4x4(columns: (
                SIMD4(0.0625, 0, 0, 0),
                SIMD4(0, 0.125, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(0, 0, 0, 1)
            )),
            sceneTime: 3.25,
            dayTime: dayTime,
            frameTime: 1.0 / 60.0,
            pointerCurrentNDC: pointer,
            pointerPreviousNDC: SIMD2(1, -1),
            texturePhysicalSizes: textureSizes
        )
    }

    static func float(_ data: Data, _ offset: Int) -> Float {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Float.self) }
    }

    static func int(_ data: Data, _ offset: Int) -> Int32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
    }

    static func uint(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    static func main() throws {
        let plan = plan()
        guard let data = SceneAuthoredShaderUniformBinder.encode(
            plan: plan,
            inputs: inputs()
        ) else {
            throw NSError(domain: "Harness", code: 1)
        }
        let floats: [String: Float] = [
            "renderWidth": float(data, 0),
            "renderHeight": float(data, 4),
            "mvpX": float(data, 16),
            "mvpY": float(data, 36),
            "time": float(data, 80),
            "dayTime": float(data, 84),
            "frameTime": float(data, 88),
            "pointerX": float(data, 96),
            "pointerY": float(data, 100),
            "pointerLastX": float(data, 104),
            "pointerLastY": float(data, 108),
            "texelX": float(data, 112),
            "texelY": float(data, 116),
            "halfTexelX": float(data, 120),
            "halfTexelY": float(data, 124),
            "screenWidth": float(data, 128),
            "screenHeight": float(data, 132),
            "screenAspect": float(data, 136),
            "physicalWidth": float(data, 144),
            "physicalHeight": float(data, 148),
            "mappedWidth": float(data, 152),
            "mappedHeight": float(data, 156),
            "colorR": float(data, 176),
            "colorG": float(data, 180),
            "colorB": float(data, 184),
            "scalar": float(data, 192),
        ]
        let result: [String: Any] = [
            "byteCount": data.count,
            "floats": floats,
            "int0": int(data, 160),
            "int1": int(data, 164),
            "uint0": uint(data, 168),
            "uint1": uint(data, 172),
            "float3PaddingZero": data[188..<192].allSatisfy { $0 == 0 },
            "missingTextureRejected": SceneAuthoredShaderUniformBinder.encode(
                plan: plan,
                inputs: inputs(textureSizes: [:])
            ) == nil,
            "invalidScreenRejected": SceneAuthoredShaderUniformBinder.encode(
                plan: plan,
                inputs: inputs(screenSize: .zero)
            ) == nil,
            "invalidDaytimeRejected": SceneAuthoredShaderUniformBinder.encode(
                plan: plan,
                inputs: inputs(dayTime: 1.1)
            ) == nil,
            "invalidPointerRejected": SceneAuthoredShaderUniformBinder.encode(
                plan: plan,
                inputs: inputs(pointer: SIMD2(.nan, 0))
            ) == nil,
            "invalidConstantsRejected": [
                SceneAuthoredShaderUniformBinder.canEncodeConstant([1.5], as: .int),
                SceneAuthoredShaderUniformBinder.canEncodeConstant([-1], as: .uint),
                SceneAuthoredShaderUniformBinder.canEncodeConstant([1], as: .bool),
                SceneAuthoredShaderUniformBinder.canEncodeConstant([1, 0, 0, 1], as: .float2x2),
                SceneAuthoredShaderUniformBinder.canEncodeConstant([Double.infinity], as: .float),
            ].allSatisfy { !$0 },
        ]
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: encoded, as: UTF8.self))
    }
}
'''


class SceneAuthoredShaderUniformBinderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-authored-shader-uniforms-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "authored-shader-uniforms"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_official_builtin_layout_and_fail_closed_inputs(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(result["byteCount"], 208)
        expected = {
            "renderWidth": 32,
            "renderHeight": 16,
            "mvpX": 0.0625,
            "mvpY": 0.125,
            "time": 3.25,
            "dayTime": 0.5,
            "frameTime": 1 / 60,
            "pointerX": 0,
            "pointerY": 0,
            "pointerLastX": 1,
            "pointerLastY": 1,
            "texelX": 1 / 1920,
            "texelY": 1 / 1080,
            "halfTexelX": 0.5 / 1920,
            "halfTexelY": 0.5 / 1080,
            "screenWidth": 1920,
            "screenHeight": 1080,
            "screenAspect": 1920 / 1080,
            "physicalWidth": 32,
            "physicalHeight": 16,
            "mappedWidth": 128,
            "mappedHeight": 64,
            "colorR": 0.25,
            "colorG": 0.5,
            "colorB": 0.75,
            "scalar": 1.5,
        }
        for name, value in expected.items():
            self.assertAlmostEqual(result["floats"][name], value, places=6, msg=name)
        self.assertEqual([result["int0"], result["int1"]], [-2, 3])
        self.assertEqual([result["uint0"], result["uint1"]], [4, 5])
        for key in (
            "float3PaddingZero",
            "missingTextureRejected",
            "invalidScreenRejected",
            "invalidDaytimeRejected",
            "invalidPointerRejected",
            "invalidConstantsRejected",
        ):
            self.assertTrue(result[key], key)


if __name__ == "__main__":
    unittest.main()
