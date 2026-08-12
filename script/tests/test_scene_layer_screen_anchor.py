#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Rendering/SceneLayerScreenAnchor.swift",
    SCENE_ROOT / "Rendering/SceneTextLayerPivot.swift",
    SCENE_ROOT / "Rendering/SceneCameraProjection.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
]
TRANSFORMS_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer+LayerTransforms.swift"
RENDERER_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
EFFECT_EXECUTION_SOURCE = (
    SCENE_ROOT / "Rendering/SceneMetalRenderer+EffectExecution.swift"
)
UTILITY_FRAME_RENDERER_SOURCE = (
    SCENE_ROOT / "Rendering/SceneUtilityPlanFrameRenderer.swift"
)

# 随包 `projects/defaultprojects/dino_run/scene.json`：general.orthogonalprojection
# 是 343x193，两个记分标签都是 anchor=topright、origin.x=341.42999，
# label_coins 的 origin.y=185.129、size=780x291、scale=0.057（世界 44.46x16.59）。
# SceneLayerWorldFrameResolver 把作者的 y 向上坐标翻成世界 y 向下：193-185.129=7.871。
# 这些数字直接进 harness。camera 段缺省，nearZ/farZ 走 descriptor 默认 0.01/10000。

HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import Metal
import simd

// SceneCameraProjection 只用到 camera 描述符的这些字段。
struct SceneRenderDescriptor {
    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let nearZ: Float
        let farZ: Float
    }
}

@main
enum Harness {
    static let ortho = SIMD2<Float>(343, 193)
    // dino_run 的 camera：eye (0,0,0)、center (0,0,-1)、up (0,1,0)。
    static let camera = SceneRenderDescriptor.CameraDescriptor(
        eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
        orthoWidth: 343, orthoHeight: 193, nearZ: 0.01, farZ: 10_000
    )

    static func main() throws {
        let anchors = [
            "none", "center", "top", "topright", "right",
            "bottomright", "bottom", "bottomleft", "left", "topleft"
        ]
        // 人为收窄可见矩形，让 x/y 两轴同时能观察到锚点符号。
        var table: [String: [Float]] = [:]
        for anchor in anchors {
            table[anchor] = vector(SceneLayerScreenAnchor.offset(
                anchor: anchor, orthoSize: ortho,
                visibleHalfExtents: SIMD2(100, 50)
            ))
        }

        var gpu: Any = NSNull()
        if let coverage = try coverageTable() {
            gpu = coverage
        }

        let result: [String: Any] = [
            "table": table,
            "uppercase": vector(SceneLayerScreenAnchor.offset(
                anchor: "TopRight", orthoSize: ortho,
                visibleHalfExtents: SIMD2(100, 50)
            )),
            "missing": vector(SceneLayerScreenAnchor.offset(
                anchor: nil, orthoSize: ortho,
                visibleHalfExtents: SIMD2(100, 50)
            )),
            "unknown": vector(SceneLayerScreenAnchor.offset(
                anchor: "middleright", orthoSize: ortho,
                visibleHalfExtents: SIMD2(100, 50)
            )),
            "degenerateOrtho": vector(SceneLayerScreenAnchor.offset(
                anchor: "topright", orthoSize: .zero,
                visibleHalfExtents: SIMD2(100, 50)
            )),
            "degenerateViewport": vector(SceneLayerScreenAnchor.offset(
                anchor: "topright", orthoSize: ortho,
                visibleHalfExtents: .zero
            )),
            "widescreen": margins(width: 1_920, height: 1_080),
            "sixteenTen": margins(width: 1_920, height: 1_200),
            "ultrawide": margins(width: 2_560, height: 1_080),
            "gpu": gpu
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    // 用真实的 cover 半宽高算出「作者摆位」和「锚定后摆位」离可见边角的距离。
    static func margins(width: Int, height: Int) -> [String: Float] {
        let half = SceneCameraProjection.coverHalfExtents(
            orthoWidth: ortho.x,
            orthoHeight: ortho.y,
            viewportSize: CGSize(width: width, height: height)
        )
        let offset = SceneLayerScreenAnchor.offset(
            anchor: "topright", orthoSize: ortho,
            visibleHalfExtents: half
        )
        let sceneCenter = ortho * 0.5
        let visibleMaxX = sceneCenter.x + half.x
        let visibleMinY = sceneCenter.y - half.y
        let label = SIMD2<Float>(341.42999, 193 - 185.129)
        return [
            "halfX": half.x,
            "halfY": half.y,
            "offsetX": offset.x,
            "offsetY": offset.y,
            "authoredRightMargin": visibleMaxX - label.x,
            "authoredTopMargin": label.y - visibleMinY,
            "anchoredRightMargin": visibleMaxX - (label.x + offset.x),
            "anchoredTopMargin": (label.y + offset.y) - visibleMinY
        ]
    }

    // GPU 门：用真实 image layer pipeline 把 label_coins 的 quad 画进离屏纹理，
    // 直接观察锚定前后覆盖了哪些像素。16:9 是作者宽高比，21:9 会裁掉上下。
    static func coverageTable() throws -> [String: [String: Int]]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba8Unorm),
              let white = whiteTexture(device: device) else {
            return nil
        }
        var table: [String: [String: Int]] = [:]
        for (name, size) in [
            "widescreen": CGSize(width: 256, height: 144),
            "ultrawide": CGSize(width: 256, height: 108)
        ] {
            for anchor in ["none", "topright"] {
                guard let coverage = coverage(
                    anchor: anchor, viewportSize: size, device: device,
                    queue: queue, pipeline: pipeline, texture: white
                ) else {
                    return nil
                }
                table["\(name)-\(anchor)"] = coverage
            }
        }
        return table
    }

    static func coverage(
        anchor: String,
        viewportSize: CGSize,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        texture: MTLTexture
    ) -> [String: Int]? {
        let width = Int(viewportSize.width)
        let height = Int(viewportSize.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(
            texture: texture,
            mvp: labelMVP(anchor: anchor, viewportSize: viewportSize),
            uniforms: uniforms, encoder: encoder
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            target.getBytes(
                buffer.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0
            )
        }
        var count = 0
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return [
            "count": count, "minX": minX, "maxX": maxX,
            "minY": minY, "maxY": maxY, "width": width, "height": height
        ]
    }

    // 与 SceneMetalRenderer.imageModelMatrix 同一组合：
    // translation(shift) * world * sizeScale * translation(pivot)，
    // world 为 SceneLayerWorldFrameResolver 对 root layer 的 translation * euler * scale。
    static func labelMVP(anchor: String, viewportSize: CGSize) -> simd_float4x4 {
        let half = SceneCameraProjection.coverHalfExtents(
            orthoWidth: ortho.x, orthoHeight: ortho.y,
            viewportSize: viewportSize
        )
        let shift = SceneLayerScreenAnchor.offset(
            anchor: anchor, orthoSize: ortho,
            visibleHalfExtents: half
        )
        let world = SceneMatrix.translation(SIMD3(341.42999, 193 - 185.129, 0))
            * SceneMatrix.scale(SIMD3(repeating: 0.057))
        let sizeScale = SceneMatrix.scale(SIMD3(780, -291, 1))
        // label_coins 的作者对齐是 horizontalalign right / verticalalign center。
        let pivot = SceneTextLayerPivot.unitOffset(
            horizontal: "right", vertical: "center",
            renderSize: SIMD2(780, 291), padding: 0
        )
        let viewProjection = SceneCameraProjection.viewProjection(
            camera: camera, viewportSize: viewportSize
        )
        return viewProjection
            * SceneMatrix.translation(SIMD3(shift.x, shift.y, 0))
            * world
            * sizeScale
            * SceneMatrix.translation(SIMD3(pivot.x, pivot.y, 0))
    }

    static func whiteTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: [UInt8] = [255, 255, 255, 255]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &pixel, bytesPerRow: 4
        )
        return texture
    }

    static let uniforms = SceneLayerFragmentUniforms(
        time: 0, alpha: 1, dependencyBlendMode: 0, usesDependencyBlend: 0,
        cursorUV: .zero, _pad1: .zero, tint: SIMD4(repeating: 1),
        textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0)
    )

    static func vector(_ value: SIMD2<Float>) -> [Float] {
        [value.x, value.y]
    }
}
'''


class SceneLayerScreenAnchorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        missing = [path.name for path in SWIFT_SOURCES if not path.exists()]
        if missing:
            raise RuntimeError("Scene screen anchor sources are missing: " + ", ".join(missing))
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-anchor-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-layer-screen-anchor"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def assert_close(self, actual: object, expected: tuple[float, float]) -> None:
        self.assertIsInstance(actual, list)
        assert isinstance(actual, list)
        self.assertEqual(len(actual), 2)
        self.assertAlmostEqual(actual[0], expected[0], places=3)
        self.assertAlmostEqual(actual[1], expected[1], places=3)

    def test_anchor_value_domain_matches_official_typings(self) -> None:
        # lib.sceneScript.d.ts 的 ITextLayer：none/center/top/topright/right/
        # bottomright/bottom/bottomleft/left/topleft。可见半宽高 (100,50) 对
        # 作者半宽高 (171.5,96.5) 的差是 (-71.5,-46.5)，逐个锚点乘符号。
        table = self.result["table"]
        self.assert_close(table["none"], (0, 0))
        self.assert_close(table["center"], (0, 0))
        self.assert_close(table["top"], (0, 46.5))
        self.assert_close(table["topright"], (-71.5, 46.5))
        self.assert_close(table["right"], (-71.5, 0))
        self.assert_close(table["bottomright"], (-71.5, -46.5))
        self.assert_close(table["bottom"], (0, -46.5))
        self.assert_close(table["bottomleft"], (71.5, -46.5))
        self.assert_close(table["left"], (71.5, 0))
        self.assert_close(table["topleft"], (71.5, 46.5))
        self.assert_close(self.result["uppercase"], (-71.5, 46.5))

    def test_unknown_and_degenerate_inputs_never_move_the_layer(self) -> None:
        self.assert_close(self.result["missing"], (0, 0))
        self.assert_close(self.result["unknown"], (0, 0))
        self.assert_close(self.result["degenerateOrtho"], (0, 0))
        self.assert_close(self.result["degenerateViewport"], (0, 0))
        # 屏幕锚定跟随相机，所以 center 锚点的偏移就是相机偏移本身。

    def test_dino_run_score_label_keeps_its_corner_margin_across_aspects(self) -> None:
        # 作者宽高比（16:9）下偏移几乎为零：完全保留作者摆位。
        widescreen = self.result["widescreen"]
        self.assertAlmostEqual(widescreen["offsetX"], 0, places=3)
        self.assertAlmostEqual(widescreen["offsetY"], 0.03125, places=4)

        # 16:10 会裁掉左右，作者摆位下标签中心已经在可见矩形右侧之外。
        sixteen_ten = self.result["sixteenTen"]
        self.assertAlmostEqual(sixteen_ten["halfX"], 154.4, places=3)
        self.assertLess(sixteen_ten["authoredRightMargin"], -15)
        self.assertAlmostEqual(sixteen_ten["offsetX"], -17.1, places=3)
        self.assertAlmostEqual(sixteen_ten["offsetY"], 0, places=3)

        # 21:9 会裁掉上下，作者摆位下标签落在可见矩形上边之外。
        ultrawide = self.result["ultrawide"]
        self.assertAlmostEqual(ultrawide["halfY"], 72.3515625, places=3)
        self.assertLess(ultrawide["authoredTopMargin"], -16)
        self.assertAlmostEqual(ultrawide["offsetX"], 0, places=3)
        self.assertAlmostEqual(ultrawide["offsetY"], 24.1484375, places=3)

        # 三种宽高比锚定后离可见右上角的距离都等于作者画布上的那一份。
        for name in ("widescreen", "sixteenTen", "ultrawide"):
            margins = self.result[name]
            self.assertAlmostEqual(margins["anchoredRightMargin"], 1.57001, places=3)
            self.assertAlmostEqual(margins["anchoredTopMargin"], 7.871, places=3)

    def test_gpu_pass_draws_the_label_inside_the_visible_corner(self) -> None:
        # 真实 image layer pipeline + 真实 viewProjection 的离屏渲染门：作者宽高比下
        # 锚定不改变覆盖像素，21:9 下不锚定的 label 被裁光，锚定后回到右上角。
        gpu = self.result["gpu"]
        if gpu is None:
            self.skipTest("Metal device is unavailable")

        widescreen_plain = gpu["widescreen-none"]
        widescreen_anchored = gpu["widescreen-topright"]
        self.assertGreater(widescreen_plain["count"], 0)
        self.assertEqual(widescreen_plain, widescreen_anchored)

        # 21:9 裁掉上下 24 个世界单位，作者摆位的 label 整块落在可见矩形之上。
        self.assertEqual(gpu["ultrawide-none"]["count"], 0)
        anchored = gpu["ultrawide-topright"]
        # 锚定后覆盖像素与作者宽高比完全一致：396 px、x[222,254]、y[0,11]。
        for key in ("count", "minX", "maxX", "minY", "maxY"):
            self.assertEqual(anchored[key], widescreen_plain[key], key)
        self.assertGreater(anchored["minX"], anchored["width"] * 0.8)
        self.assertLess(anchored["maxY"], anchored["height"] * 0.5)
        # `horizontalalign: right` 的 pivot 让右边缘落在 origin.x=341.42999 对应的
        # 第 254 列，整块 quad 都在画布内，不再被右界裁掉（见 test_scene_text_layer_pivot）。
        self.assertEqual(anchored["maxX"], 254)

    def test_renderer_folds_screen_anchor_into_the_layer_translation(self) -> None:
        transforms = TRANSFORMS_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(transforms, re.compile(
            r"SceneLayerScreenAnchor\.offset\("
            r"[\s\S]{0,200}anchor:\s*layer\.textStyle\?\.screenAnchor"
            r"[\s\S]{0,240}visibleHalfExtents:\s*visibleHalfExtents"
        ))
        self.assertRegex(transforms, re.compile(
            r"let shift = parallax \+ screenAnchor"
            r"[\s\S]{0,400}SceneMatrix\.translation\(SIMD3\(shift\.x, shift\.y, 0\)\)"
        ))
        # 三个 imageModelMatrix 调用点都要喂真实的 cover 半宽高。
        renderer = RENDERER_SOURCE.read_text(encoding="utf-8")
        effect_execution = EFFECT_EXECUTION_SOURCE.read_text(encoding="utf-8")
        utility_frame_renderer = UTILITY_FRAME_RENDERER_SOURCE.read_text(
            encoding="utf-8"
        )
        self.assertIn("renderUtilityPlans(", renderer)
        self.assertIn("SceneUtilityPlanFrameRenderer.render(", effect_execution)
        self.assertEqual(renderer.count("imageModelMatrix("), 2)
        self.assertEqual(utility_frame_renderer.count("imageModelMatrix("), 1)
        self.assertEqual(
            renderer.count("visibleHalfExtents: cameraFrame.coverHalfExtents"), 2
        )
        self.assertEqual(
            utility_frame_renderer.count(
                "visibleHalfExtents: cameraFrame.coverHalfExtents"
            ),
            1,
        )


if __name__ == "__main__":
    unittest.main()
