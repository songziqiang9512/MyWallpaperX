#!/usr/bin/env python3
"""GPU 对拍 imageblending 32 模式表。

参考值不是抄来的常数表，而是按 WE `ApplyBlending` 的分派语义在 numpy 里独立
重算一遍，再和 Metal 实现逐像素比。两侧唯一共享的是"模式编号 -> 混合函数"这个
接口契约本身。

注意这条只证明 Metal 实现与混合模式的数学定义等价，不证明与官方渲染输出逐像素
相同 —— 后者需要官方客户端的像素 oracle，项目目前没有。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import numpy as np

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Effects/SceneTintPipeline.swift",
]

# 官方 tint.frag 的默认值，以及语料里实际出现过的另外两组取值。
TINT_COLORS = [(1.0, 0.0, 0.0), (0.25, 0.6, 0.9), (1.0, 1.0, 1.0)]
TINT_ALPHAS = [0.35, 1.0]
MAX_MODE = 32

HARNESS = r'''
import Foundation
import Metal
import simd

@main
enum Harness {
    static let size = 8

    static func sourceBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for index in 0 ..< (size * size) {
            let r = UInt8((Double(index % 4) / 3.0 * 255.0).rounded())
            let g = UInt8((Double((index / 4) % 4) / 3.0 * 255.0).rounded())
            let b = UInt8((Double((index / 16) % 4) / 3.0 * 255.0).rounded())
            bytes[index * 4 + 0] = b
            bytes[index * 4 + 1] = g
            bytes[index * 4 + 2] = r
            bytes[index * 4 + 3] = 255
        }
        return bytes
    }

    static func makeTexture(
        device: MTLDevice,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)
    }

    static func rgba(_ bytes: [UInt8]) -> [[Int]] {
        var pixels: [[Int]] = []
        pixels.reserveCapacity(size * size)
        for index in 0 ..< (size * size) {
            let b: Int = Int(bytes[index * 4 + 0])
            let g: Int = Int(bytes[index * 4 + 1])
            let r: Int = Int(bytes[index * 4 + 2])
            let a: Int = Int(bytes[index * 4 + 3])
            pixels.append([r, g, b, a])
        }
        return pixels
    }

    static func read(_ texture: MTLTexture) -> [[Int]] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return rgba(bytes)
    }

    static func main() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneTintPipeline(device: device),
              let source = makeTexture(device: device, usage: [.shaderRead, .shaderWrite]),
              let target = makeTexture(device: device, usage: [.renderTarget, .shaderRead])
        else {
            print("{\"metalUnavailable\": true}")
            return
        }

        let bytes = sourceBytes()
        source.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: size * 4
        )

        let colors: [SIMD3<Float>] = [
            SIMD3<Float>(1.0, 0.0, 0.0),
            SIMD3<Float>(0.25, 0.6, 0.9),
            SIMD3<Float>(1.0, 1.0, 1.0),
        ]
        let alphas: [Float] = [0.35, 1.0]

        var cases: [[String: Any]] = []
        var rejected: [[String: Any]] = []

        for mode in 0 ... 32 {
            for (colorIndex, color) in colors.enumerated() {
                for (alphaIndex, alpha) in alphas.enumerated() {
                    guard let buffer = queue.makeCommandBuffer() else { continue }
                    let encoded = pipeline.encode(
                        source: source,
                        target: target,
                        color: color,
                        alpha: alpha,
                        blendMode: mode,
                        commandBuffer: buffer
                    )
                    guard encoded,
                          let blit = buffer.makeBlitCommandEncoder() else { continue }
                    blit.synchronize(resource: target)
                    blit.endEncoding()
                    buffer.commit()
                    buffer.waitUntilCompleted()
                    cases.append([
                        "mode": mode,
                        "colorIndex": colorIndex,
                        "alphaIndex": alphaIndex,
                        "pixels": read(target),
                    ])
                }
            }
        }

        // 越界模式与非有限参数必须被拒绝，不能静默落回 Normal。
        for (label, mode, alpha) in [
            ("negativeMode", -1, Float(1.0)),
            ("aboveMaximumMode", 33, Float(1.0)),
            ("nonFiniteAlpha", 30, Float.nan),
            ("alphaAboveOne", 30, Float(1.5)),
        ] as [(String, Int, Float)] {
            guard let buffer = queue.makeCommandBuffer() else { continue }
            let encoded = pipeline.encode(
                source: source,
                target: target,
                color: SIMD3<Float>(1.0, 0.0, 0.0),
                alpha: alpha,
                blendMode: mode,
                commandBuffer: buffer
            )
            rejected.append(["label": label, "encoded": encoded])
        }

        let payload: [String: Any] = [
            "metalUnavailable": false,
            "source": rgba(bytes),
            "cases": cases,
            "rejected": rejected,
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


# —— numpy 参考实现：按 ApplyBlending 的分派语义独立重算 ——


def _screen(b, s):
    return 1.0 - (1.0 - b) * (1.0 - s)


def _overlay(b, s):
    return np.where(b < 0.5, 2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s))


def _soft_light(b, s):
    with np.errstate(invalid="ignore"):
        return np.where(
            s < 0.5,
            2.0 * b * s + b * b * (1.0 - 2.0 * s),
            np.sqrt(np.maximum(b, 0.0)) * (2.0 * s - 1.0) + 2.0 * b * (1.0 - s),
        )


def _color_dodge(b, s):
    with np.errstate(divide="ignore", invalid="ignore"):
        value = np.minimum(b / (1.0 - s), 1.0)
    return np.where(s == 1.0, s, value)


def _color_burn(b, s):
    with np.errstate(divide="ignore", invalid="ignore"):
        value = np.maximum(1.0 - (1.0 - b) / s, 0.0)
    return np.where(s == 0.0, s, value)


def _linear_light(b, s):
    return np.where(
        s < 0.5,
        np.maximum(b + 2.0 * s - 1.0, 0.0),
        b + 2.0 * (s - 0.5),
    )


def _vivid_light(b, s):
    return np.where(s < 0.5, _color_burn(b, 2.0 * s), _color_dodge(b, 2.0 * (s - 0.5)))


def _pin_light(b, s):
    return np.where(s < 0.5, np.minimum(b, 2.0 * s), np.maximum(b, 2.0 * (s - 0.5)))


def _hard_mix(b, s):
    return np.where(_vivid_light(b, s) < 0.5, 0.0, 1.0)


def _reflect(b, s):
    with np.errstate(divide="ignore", invalid="ignore"):
        value = np.minimum(b * b / (1.0 - s), 1.0)
    return np.where(s == 1.0, s, value)


def _rgb_to_hsl(c):
    lo = c.min(axis=-1)
    hi = c.max(axis=-1)
    delta = hi - lo
    lightness = (hi + lo) / 2.0
    with np.errstate(divide="ignore", invalid="ignore"):
        saturation = np.where(
            lightness < 0.5, delta / (hi + lo), delta / (2.0 - hi - lo)
        )
        d = [(((hi - c[..., i]) / 6.0) + (delta / 2.0)) / delta for i in range(3)]
    hue = np.where(
        c[..., 0] == hi,
        d[2] - d[1],
        np.where(c[..., 1] == hi, (1.0 / 3.0) + d[0] - d[2], (2.0 / 3.0) + d[1] - d[0]),
    )
    hue = np.where(hue < 0.0, hue + 1.0, np.where(hue > 1.0, hue - 1.0, hue))
    zero = delta == 0.0
    return np.stack(
        [
            np.where(zero, 0.0, hue),
            np.where(zero, 0.0, saturation),
            lightness,
        ],
        axis=-1,
    )


def _hue_to_rgb(f1, f2, hue):
    hue = np.where(hue < 0.0, hue + 1.0, np.where(hue > 1.0, hue - 1.0, hue))
    return np.where(
        6.0 * hue < 1.0,
        f1 + (f2 - f1) * 6.0 * hue,
        np.where(
            2.0 * hue < 1.0,
            f2,
            np.where(3.0 * hue < 2.0, f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0, f1),
        ),
    )


def _hsl_to_rgb(hsl):
    h, s, lightness = hsl[..., 0], hsl[..., 1], hsl[..., 2]
    f2 = np.where(
        lightness < 0.5, lightness * (1.0 + s), (lightness + s) - (s * lightness)
    )
    f1 = 2.0 * lightness - f2
    rgb = np.stack(
        [
            _hue_to_rgb(f1, f2, h + (1.0 / 3.0)),
            _hue_to_rgb(f1, f2, h),
            _hue_to_rgb(f1, f2, h - (1.0 / 3.0)),
        ],
        axis=-1,
    )
    return np.where((s == 0.0)[..., None], lightness[..., None], rgb)


def _hsl_mix(base, blend, take_hue, take_sat, take_lum):
    base_hsl = _rgb_to_hsl(base)
    blend_hsl = _rgb_to_hsl(blend)
    return _hsl_to_rgb(
        np.stack(
            [
                blend_hsl[..., 0] if take_hue else base_hsl[..., 0],
                blend_hsl[..., 1] if take_sat else base_hsl[..., 1],
                blend_hsl[..., 2] if take_lum else base_hsl[..., 2],
            ],
            axis=-1,
        )
    )


def apply_blending(mode, a, b, o):
    """a: (N,3) 基色；b: (N,3) 混合色；o: 标量不透明度。"""

    def mix(result):
        return a + (result - a) * o

    if mode == 1:
        return mix(np.minimum(b, a))
    if mode == 2:
        return mix(a * b)
    if mode == 3:
        return mix(_color_burn(a, b))
    if mode in (4, 20):
        return mix(np.maximum(a + b - 1.0, 0.0))
    if mode == 5:
        return np.minimum(a, b)  # 官方此处不乘 opacity
    if mode == 6:
        return mix(np.maximum(b, a))
    if mode == 7:
        return mix(_screen(a, b))
    if mode == 8:
        return mix(_color_dodge(a, b))
    if mode == 9:
        return mix(np.minimum(a + b, 1.0))
    if mode == 10:
        return np.maximum(a, b)  # 官方此处不乘 opacity
    if mode == 11:
        return mix(_overlay(a, b))
    if mode == 12:
        return mix(_soft_light(a, b))
    if mode == 13:
        return mix(_overlay(b, a))
    if mode == 14:
        return mix(_vivid_light(a, b))
    if mode == 15:
        return mix(_linear_light(a, b))
    if mode == 16:
        return mix(_pin_light(a, b))
    if mode == 17:
        return mix(_hard_mix(a, b))
    if mode == 18:
        return mix(np.abs(a - b))
    if mode == 19:
        return mix(a + b - 2.0 * a * b)
    if mode == 21:
        return mix(_reflect(a, b))
    if mode == 22:
        return mix(_reflect(b, a))
    if mode == 23:
        return mix(np.minimum(a, b) - np.maximum(a, b) + 1.0)
    if mode == 24:
        return mix((a + b) / 2.0)
    if mode == 25:
        return mix(1.0 - np.abs(1.0 - a - b))
    if mode == 26:
        return mix(_hsl_mix(a, b, True, False, False))
    if mode == 27:
        return mix(_hsl_mix(a, b, False, True, False))
    if mode == 28:
        return mix(_hsl_mix(a, b, True, True, False))
    if mode == 29:
        return mix(_hsl_mix(a, b, False, False, True))
    if mode == 30:
        return mix(a.max(axis=-1, keepdims=True) * b)
    if mode == 31:
        return a + b * o  # 官方此处不是 mix
    if mode == 32:
        return mix(a + a * b)
    return mix(b)


class SceneBlendModeTableTests(unittest.TestCase):
    result: dict

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-blend-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-blend-mode-table"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_every_mode_matches_the_independent_numpy_reference(self) -> None:
        source = np.asarray(self.result["source"], dtype=np.float64) / 255.0
        base = source[:, :3]
        worst = 0.0
        worst_label = ""
        for entry in self.result["cases"]:
            mode = entry["mode"]
            color = np.asarray(
                TINT_COLORS[entry["colorIndex"]], dtype=np.float64
            )
            alpha = TINT_ALPHAS[entry["alphaIndex"]]
            blend = np.broadcast_to(color, base.shape)
            expected = np.clip(apply_blending(mode, base, blend, alpha), 0.0, 1.0)
            actual = np.asarray(entry["pixels"], dtype=np.float64)[:, :3] / 255.0
            deviation = float(np.abs(expected - actual).max())
            if deviation > worst:
                worst = deviation
                worst_label = f"mode={mode} color={entry['colorIndex']} alpha={alpha}"
        self.assertLessEqual(
            worst,
            2.5 / 255.0,
            f"最大偏差 {worst:.5f} 出现在 {worst_label}（容差 2.5/255）",
        )

    def test_covers_the_entire_official_dispatch_table(self) -> None:
        modes = {entry["mode"] for entry in self.result["cases"]}
        self.assertEqual(modes, set(range(0, MAX_MODE + 1)))

    def test_modes_five_and_ten_ignore_opacity(self) -> None:
        # 官方这两个分支直接 return min/max，不乘 opacity。若误写成 mix，
        # 两个不同 alpha 的输出就会不同。
        for mode in (5, 10):
            grouped: dict[int, list] = {}
            for entry in self.result["cases"]:
                if entry["mode"] != mode:
                    continue
                grouped.setdefault(entry["colorIndex"], []).append(entry["pixels"])
            for color_index, pixel_sets in grouped.items():
                self.assertEqual(
                    len(pixel_sets), len(TINT_ALPHAS), f"mode={mode} 用例不全"
                )
                self.assertEqual(
                    pixel_sets[0],
                    pixel_sets[1],
                    f"mode={mode} color={color_index} 的输出随 alpha 变化了",
                )

    def test_mode_zero_forces_opaque_alpha(self) -> None:
        # 官方 tint.frag 在 BLENDMODE == 0 时把 albedo.a 写死为 1。
        for entry in self.result["cases"]:
            if entry["mode"] != 0:
                continue
            alphas = {pixel[3] for pixel in entry["pixels"]}
            self.assertEqual(alphas, {255})

    def test_other_modes_preserve_source_alpha(self) -> None:
        source_alphas = [pixel[3] for pixel in self.result["source"]]
        for entry in self.result["cases"]:
            if entry["mode"] == 0:
                continue
            self.assertEqual(
                [pixel[3] for pixel in entry["pixels"]],
                source_alphas,
                f"mode={entry['mode']} 改动了 alpha",
            )

    def test_rejects_out_of_range_modes_and_nonfinite_alpha(self) -> None:
        rejected = {entry["label"]: entry["encoded"] for entry in self.result["rejected"]}
        self.assertEqual(
            rejected,
            {
                "negativeMode": False,
                "aboveMaximumMode": False,
                "nonFiniteAlpha": False,
                "alphaAboveOne": False,
            },
        )


if __name__ == "__main__":
    unittest.main()
