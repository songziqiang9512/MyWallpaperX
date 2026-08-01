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
    SCENE_ROOT / "Rendering/SceneTextLayerPivot.swift",
    SCENE_ROOT / "Rendering/SceneCameraProjection.swift",
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
]
TRANSFORMS_SOURCE = SCENE_ROOT / "Rendering/SceneMetalRenderer+LayerTransforms.swift"
TEXT_LOADER_SOURCE = SCENE_ROOT / "Text/SceneTextTextureLoader.swift"

# 判据来自随包 `projects/defaultprojects/dino_run/scene.json`（ortho 343x193）：
# label_coins  origin 341.42999/185.129  size 780x291  scale 0.057  horizontalalign right
# label_top    origin 341.42999/172.88385 size 390x145 scale 0.057  horizontalalign right
# 两者宽度差一倍却共用同一个 origin.x，只有「origin 就是右边缘」才解释得通；
# 三个 preset text layer（previewcountdown/previewclock/preview3dclock）都是
# center/center 且 origin.x 正好是 256 画布的中心 128，取中心 pivot 不动。
# 世界 y 向下：193-185.129=7.871、193-172.88385=20.11615。

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

struct Label {
    let name: String
    let originX: Float
    let authoredOriginY: Float
    let sizeX: Float
    let sizeY: Float
}

@main
enum Harness {
    static let ortho = SIMD2<Float>(343, 193)
    static let scale: Float = 0.057
    // dino_run 的 camera 段缺省，nearZ/farZ 走 descriptor 默认 0.01/10000。
    static let camera = SceneRenderDescriptor.CameraDescriptor(
        eye: [0, 0, 0], center: [0, 0, -1], up: [0, 1, 0],
        orthoWidth: 343, orthoHeight: 193, nearZ: 0.01, farZ: 10_000
    )
    static let labels = [
        Label(name: "coins", originX: 341.42999, authoredOriginY: 185.129, sizeX: 780, sizeY: 291),
        Label(name: "top", originX: 341.42999, authoredOriginY: 172.88385, sizeX: 390, sizeY: 145)
    ]

    static func main() throws {
        var table: [String: [Float]] = [:]
        for horizontal in ["left", "center", "right", "Right"] {
            for vertical in ["top", "center", "bottom"] {
                table["\(horizontal)-\(vertical)"] = vector(
                    SceneTextLayerPivot.unitOffset(
                        horizontal: horizontal, vertical: vertical,
                        renderSize: SIMD2(100, 50), padding: 0
                    )
                )
            }
        }
        let result: [String: Any] = [
            "table": table,
            "missing": vector(SceneTextLayerPivot.unitOffset(
                horizontal: nil, vertical: nil, renderSize: SIMD2(100, 50), padding: 10
            )),
            "unknown": vector(SceneTextLayerPivot.unitOffset(
                horizontal: "justify", vertical: "baseline",
                renderSize: SIMD2(100, 50), padding: 10
            )),
            "padded": paddedTable(),
            "clockPair": clockPair(),
            "gpu": (try coverageTable()) ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func paddedTable() -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: [
            ("left", SceneTextLayerPivot.unitOffset(
                horizontal: "left", vertical: "center",
                renderSize: SIMD2(100, 50), padding: 10
            )),
            ("right", SceneTextLayerPivot.unitOffset(
                horizontal: "right", vertical: "center",
                renderSize: SIMD2(100, 50), padding: 10
            )),
            ("top", SceneTextLayerPivot.unitOffset(
                horizontal: "center", vertical: "top",
                renderSize: SIMD2(100, 50), padding: 10
            )),
            ("bottom", SceneTextLayerPivot.unitOffset(
                horizontal: "center", vertical: "bottom",
                renderSize: SIMD2(100, 50), padding: 10
            )),
        ].map { ($0.0, vector($0.1)) })
    }

    static func clockPair() -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: [
            ("shadow", contentEdges(size: SIMD2(202, 126), padding: 32)),
            ("face", contentEdges(size: SIMD2(302, 226), padding: 82)),
        ])
    }

    static func contentEdges(size: SIMD2<Float>, padding: Float) -> [Float] {
        let pivot = SceneTextLayerPivot.unitOffset(
            horizontal: "right", vertical: "center",
            renderSize: size, padding: padding
        )
        let outerLeft = (-0.5 + pivot.x) * size.x
        let outerRight = (0.5 + pivot.x) * size.x
        return [outerLeft + padding, outerRight - padding]
    }

    // GPU 门：用真实 image layer pipeline 与真实 viewProjection 把两个记分标签的 quad
    // 画进 256x144（作者 16:9）离屏纹理，分别用几何中心 pivot 和作者对齐 pivot。
    static func coverageTable() throws -> [String: [String: Int]]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba8Unorm),
              let white = whiteTexture(device: device) else {
            return nil
        }
        var table: [String: [String: Int]] = [:]
        for label in labels {
            for (key, alignment) in [
                "center": ("center", "center"),
                "right": ("right", "center"),
                "left": ("left", "center"),
                "top": ("center", "top"),
                "bottom": ("center", "bottom")
            ] {
                guard let coverage = coverage(
                    label: label, horizontal: alignment.0, vertical: alignment.1,
                    device: device, queue: queue, pipeline: pipeline, texture: white
                ) else {
                    return nil
                }
                table["\(label.name)-\(key)"] = coverage
            }
        }
        return table
    }

    static func coverage(
        label: Label,
        horizontal: String,
        vertical: String,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        texture: MTLTexture
    ) -> [String: Int]? {
        let width = 256
        let height = 144
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
            texture: texture, shakeMaskTexture: nil, waterMaskTexture: nil,
            foliageMaskTexture: nil, auxMaskTexture: nil,
            mvp: labelMVP(
                label: label, horizontal: horizontal, vertical: vertical,
                viewportSize: CGSize(width: width, height: height)
            ),
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
    // translation(shift) * world * sizeScale * translation(pivot)，这里 shift 为零。
    static func labelMVP(
        label: Label,
        horizontal: String,
        vertical: String,
        viewportSize: CGSize
    ) -> simd_float4x4 {
        let world = SceneMatrix.translation(
            SIMD3(label.originX, ortho.y - label.authoredOriginY, 0)
        ) * SceneMatrix.scale(SIMD3(repeating: scale))
        let sizeScale = SceneMatrix.scale(SIMD3(label.sizeX, -label.sizeY, 1))
        let pivot = SceneTextLayerPivot.unitOffset(
            horizontal: horizontal, vertical: vertical,
            renderSize: SIMD2(label.sizeX, label.sizeY), padding: 0
        )
        let viewProjection = SceneCameraProjection.viewProjection(
            camera: camera, viewportSize: viewportSize
        )
        return viewProjection
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
        time: 0, alpha: 1, effectFlags: 0, dependencyBlendMode: 0,
        cursorUV: .zero, _pad1: .zero, tint: SIMD4(repeating: 1),
        effectParams0: .zero, effectParams1: .zero, effectParams2: .zero,
        effectParams3: .zero, effectParams4: .zero, effectParams5: SIMD4(1, 1, 0, 0),
        textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0)
    )

    static func vector(_ value: SIMD2<Float>) -> [Float] {
        [value.x, value.y]
    }
}
'''


class SceneTextLayerPivotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        missing = [path.name for path in SWIFT_SOURCES if not path.exists()]
        if missing:
            raise RuntimeError("Scene text pivot sources are missing: " + ", ".join(missing))
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-text-pivot-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-text-layer-pivot"
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
        self.assertAlmostEqual(actual[0], expected[0], places=5)
        self.assertAlmostEqual(actual[1], expected[1], places=5)

    def test_pivot_offsets_cover_the_official_value_domain(self) -> None:
        # lib.sceneScript.d.ts：horizontalalign 为 left/center/right，
        # verticalalign 为 center/top/bottom。单位 quad 里被命名的那条边推到 origin，
        # sizeScale 的 -size.y 把 +y 翻成画面上边，所以 top 与 left 一样取 -0.5。
        table = self.result["table"]
        self.assert_close(table["left-center"], (0.5, 0))
        self.assert_close(table["center-center"], (0, 0))
        self.assert_close(table["right-center"], (-0.5, 0))
        self.assert_close(table["center-top"], (0, -0.5))
        self.assert_close(table["center-bottom"], (0, 0.5))
        self.assert_close(table["right-top"], (-0.5, -0.5))
        self.assert_close(table["left-bottom"], (0.5, 0.5))
        self.assert_close(table["Right-center"], (-0.5, 0))

    def test_missing_and_unknown_alignment_keeps_the_geometric_center(self) -> None:
        self.assert_close(self.result["missing"], (0, 0))
        self.assert_close(self.result["unknown"], (0, 0))

    def test_padding_keeps_the_named_content_edge_on_the_origin(self) -> None:
        padded = self.result["padded"]
        self.assert_close(padded["left"], (0.4, 0))
        self.assert_close(padded["right"], (-0.4, 0))
        self.assert_close(padded["top"], (0, -0.3))
        self.assert_close(padded["bottom"], (0, 0.3))

        clock_pair = self.result["clockPair"]
        self.assert_close(clock_pair["shadow"], (-138, 0))
        self.assert_close(clock_pair["face"], (-138, 0))

    def test_gpu_pass_lines_up_both_score_labels_on_the_authored_origin(self) -> None:
        # 真实 image layer pipeline + 真实 viewProjection 的离屏渲染门。256px 对应
        # 作者 343 宽，1 世界单位 = 0.74636 px；origin.x=341.42999 落在第 254 列。
        gpu = self.result["gpu"]
        if gpu is None:
            self.skipTest("Metal device is unavailable")

        # 几何中心 pivot：两个标签宽度差一倍，右边缘都越过画布右界被裁在最后一列，
        # 且可见宽度互不相同 —— 这就是修正前的偏差。
        coins_center = gpu["coins-center"]
        top_center = gpu["top-center"]
        self.assertEqual(coins_center["maxX"], 255)
        self.assertEqual(top_center["maxX"], 255)
        self.assertNotEqual(coins_center["minX"], top_center["minX"])

        # 作者对齐 pivot：两个右对齐标签的右边缘齐平在同一列，且不再被右界裁掉。
        coins_right = gpu["coins-right"]
        top_right = gpu["top-right"]
        self.assertEqual(coins_right["maxX"], 254)
        self.assertEqual(top_right["maxX"], 254)
        self.assertLess(coins_right["maxX"], coins_right["width"] - 1)

        # 右对齐后可见像素变多（此前被裁掉的部分回到画面内），高度不变。
        self.assertGreater(coins_right["count"], coins_center["count"])
        self.assertEqual(coins_right["minY"], coins_center["minY"])
        self.assertEqual(coins_right["maxY"], coins_center["maxY"])

        # 世界宽 780*0.057=44.46 → 33.19 px：整块 quad 33 列全部可见。
        self.assertEqual(coins_right["maxX"] - coins_right["minX"] + 1, 33)
        # 世界宽 390*0.057=22.23 → 16.59 px。
        self.assertEqual(top_right["maxX"] - top_right["minX"] + 1, 17)

        # left 与 right 关于 origin 镜像：整块 quad 落在 origin 右侧，只剩边界那一列。
        self.assertEqual(gpu["coins-left"]["minX"], 255)
        self.assertEqual(gpu["coins-left"]["maxX"], 255)

        # 垂直 pivot：top 把框推到 origin 下方，bottom 推到上方，各挪半个高度。
        # 291*0.057/2=8.2935 世界单位 → 6.19 px：y[0,11] 变成 y[6,17]。
        coins_top = gpu["coins-top"]
        coins_bottom = gpu["coins-bottom"]
        self.assertEqual(coins_top["minY"], 6)
        self.assertEqual(coins_top["maxY"], 17)
        self.assertEqual(coins_bottom["maxY"], 5)
        self.assertGreater(coins_top["minY"], coins_center["minY"])
        self.assertLess(coins_bottom["maxY"], coins_center["maxY"])

    def test_renderer_folds_the_pivot_after_the_size_scale(self) -> None:
        transforms = TRANSFORMS_SOURCE.read_text(encoding="utf-8")
        self.assertRegex(transforms, re.compile(
            r"SceneTextLayerPivot\.unitOffset\("
            r"[\s\S]{0,160}horizontal:\s*layer\.textStyle\?\.horizontalAlignment"
            r"[\s\S]{0,160}vertical:\s*layer\.textStyle\?\.verticalAlignment"
            r"[\s\S]{0,160}renderSize:\s*size"
            r"[\s\S]{0,160}padding:\s*layer\.textStyle\?\.padding"
        ))
        # pivot 必须排在 sizeScale 之后，否则不会被作者 size 与 layer scale 缩放。
        self.assertRegex(transforms, re.compile(
            r"\*\s*sizeScale\s*\n\s*\*\s*SceneMatrix\.translation\(SIMD3\(pivot\.x, pivot\.y, 0\)\)"
        ))
        # 同一组对齐字段仍然继续喂 CoreText 的框内排版，不是二选一。
        loader = TEXT_LOADER_SOURCE.read_text(encoding="utf-8")
        self.assertIn("textAlignment(style.horizontalAlignment)", loader)
        self.assertIn("alignment: style.verticalAlignment", loader)


if __name__ == "__main__":
    unittest.main()
