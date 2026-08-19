#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PIPELINE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneLightShaftsPipeline.swift"
)
LAYER_RENDERER = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLightShaftsLayerRenderer.swift"
)


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

struct SceneLightShaftsPerspectiveTransform {
    let row0: SIMD3<Float>
    let row1: SIMD3<Float>
    let row2: SIMD3<Float>

    var isFinite: Bool {
        [row0, row1, row2].allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        }
    }
}

enum SceneLightShaftsProfile: Float {
    case linearGradient = 0
    case radialColor = 1

    var requiresGradientTexture: Bool { self == .linearGradient }
}

struct SceneLightShaftsExecutionPlan {
    let profile: SceneLightShaftsProfile
    let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    let effectUVTransform: SceneLightShaftsPerspectiveTransform
    let startColor: SIMD3<Float>
    let endColor: SIMD3<Float>
    let feather: SIMD2<Float>
    let scale: SIMD2<Float>
    let radius: Float
    let noiseAmount: Float
    let noiseScale: Float
    let smoothness: Float
    let speed: Float
    let intensity: Float
    let exponent: Float
    let startAngle: Float
    let endAngle: Float
    let noiseTexturePath: String
    let gradientTexturePath: String
}

struct SceneLightShaftsEffectTextures {
    let noise: MTLTexture?
    let gradient: MTLTexture?
    let noisePath: String
    let gradientPath: String

    func matches(_ plan: SceneLightShaftsExecutionPlan) -> Bool {
        noise != nil
            && noisePath == plan.noiseTexturePath
            && (
                !plan.profile.requiresGradientTexture
                    || (gradient != nil && gradientPath == plan.gradientTexturePath)
            )
    }
}

@main
enum Harness {
    static let size = 64

    static func texture(
        device: MTLDevice,
        width: Int,
        height: Int,
        format: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func upload(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        to texture: MTLTexture
    ) {
        var value = bytes
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &value,
            bytesPerRow: width * 4
        )
    }

    static func makeResources(
        device: MTLDevice,
        includeGradient: Bool = true
    ) -> SceneLightShaftsEffectTextures {
        let noise = texture(
            device: device,
            width: 8,
            height: 8,
            format: .rgba8Unorm,
            usage: [.shaderRead]
        )
        let noiseBytes = (0..<(8 * 8)).flatMap { index -> [UInt8] in
            let x = index % 8
            let y = index / 8
            return [
                UInt8((x * 31 + y * 17) % 256),
                UInt8((x * 11 + y * 47 + 71) % 256),
                UInt8((x * 53 + y * 7 + 29) % 256),
                255,
            ]
        }
        upload(noiseBytes, width: 8, height: 8, to: noise)
        let gradient = texture(
            device: device,
            width: 2,
            height: 1,
            format: .rgba8Unorm,
            usage: [.shaderRead]
        )
        upload(
            [255, 64, 16, 255, 16, 128, 255, 255],
            width: 2,
            height: 1,
            to: gradient
        )
        return .init(
            noise: noise,
            gradient: includeGradient ? gradient : nil,
            noisePath: "materials/util/noise",
            gradientPath: "materials/gradient/gradient_iridescent"
        )
    }

    static func plan(
        profile: SceneLightShaftsProfile = .linearGradient,
        transform: SceneLightShaftsPerspectiveTransform = .init(
            row0: SIMD3<Float>(1.6666667, 0, -0.33333334),
            row1: SIMD3<Float>(0, 1.6666667, -0.33333334),
            row2: SIMD3<Float>(0, 0, 1)
        ),
        radius: Float = 0.14,
        noiseAmount: Float = 0.33,
        noiseScale: Float = 1.17,
        scale: SIMD2<Float> = SIMD2(0.8, 0.5),
        feather: SIMD2<Float> = SIMD2(0.12, 0.12),
        startColor: SIMD3<Float> = SIMD3(1, 1, 1),
        endColor: SIMD3<Float> = SIMD3(0.435294, 0.886274, 1),
        intensity: Float = 2.5,
        exponent: Float = 0.6,
        startAngle: Float = 0,
        endAngle: Float = 1
    ) -> SceneLightShaftsExecutionPlan {
        .init(
            profile: profile,
            points: (
                SIMD2<Float>(0.2, 0.2),
                SIMD2<Float>(0.8, 0.2),
                SIMD2<Float>(0.8, 0.8),
                SIMD2<Float>(0.2, 0.8)
            ),
            effectUVTransform: transform,
            startColor: startColor,
            endColor: endColor,
            feather: feather,
            scale: scale,
            radius: radius,
            noiseAmount: noiseAmount,
            noiseScale: noiseScale,
            smoothness: 0.85,
            speed: 0.7,
            intensity: intensity,
            exponent: exponent,
            startAngle: startAngle,
            endAngle: endAngle,
            noiseTexturePath: "materials/util/noise",
            gradientTexturePath: "materials/gradient/gradient_iridescent"
        )
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneLightShaftsPipeline,
        resources: SceneLightShaftsEffectTextures,
        plan: SceneLightShaftsExecutionPlan,
        time: Float,
        alpha: Float
    ) -> (accepted: Bool, bytes: [UInt8]) {
        let target = texture(
            device: device,
            width: size,
            height: size,
            format: .bgra8Unorm,
            usage: [.renderTarget]
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let accepted = pipeline.draw(
            plan: plan,
            resources: resources,
            mvp: simd_float4x4(diagonal: SIMD4<Float>(2, 2, 1, 1)),
            time: time,
            alpha: alpha,
            encoder: encoder
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return (accepted, bytes)
    }

    static func alphaTotal(_ bytes: [UInt8], xRange: Range<Int>) -> Int {
        var total = 0
        for y in 16..<48 {
            for x in xRange {
                total += Int(bytes[(y * size + x) * 4 + 3])
            }
        }
        return total
    }

    static func visibleRuns(_ bytes: [UInt8], y: Int, threshold: UInt8) -> Int {
        var runs = 0
        var inside = false
        for x in 0..<size {
            let visible = bytes[(y * size + x) * 4 + 3] > threshold
            if visible && !inside { runs += 1 }
            inside = visible
        }
        return runs
    }

    static func supportWidth(_ bytes: [UInt8], y: Int) -> Int {
        (0..<size).filter { bytes[(y * size + $0) * 4 + 3] > 3 }.count
    }

    static func alphaCentroidX(_ bytes: [UInt8]) -> Double {
        var weighted = 0
        var total = 0
        for y in 8..<40 {
            for x in 0..<size {
                let alpha = Int(bytes[(y * size + x) * 4 + 3])
                weighted += x * alpha
                total += alpha
            }
        }
        return total > 0 ? Double(weighted) / Double(total) : 0
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneLightShaftsPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let resources = makeResources(device: device)
        let noGradientResources = makeResources(device: device, includeGradient: false)
        let authoredPlan = plan()
        let first = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: authoredPlan,
            time: 0,
            alpha: 1
        )
        let second = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: authoredPlan,
            time: 1.25,
            alpha: 1
        )
        let phaseFrames = [Float(0), 3, 6, 9].map { phaseTime in
            render(
                device: device,
                queue: queue,
                pipeline: pipeline,
                resources: resources,
                plan: authoredPlan,
                time: phaseTime,
                alpha: 1
            )
        }
        let half = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: authoredPlan,
            time: 0,
            alpha: 0.5
        )
        let invalid = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: authoredPlan,
            time: 0,
            alpha: 1.1
        )
        let invalidPlan = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: plan(radius: .nan),
            time: 0,
            alpha: 1
        )
        let alternate = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: plan(transform: .init(
                row0: SIMD3<Float>(1.25, 0, -0.125),
                row1: SIMD3<Float>(0, 1.25, -0.125),
                row2: SIMD3<Float>(0, 0, 1)
            )),
            time: 0,
            alpha: 1
        )
        let narrowRadius = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: plan(radius: 0.01),
            time: 0,
            alpha: 1
        )
        let noModulation = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: plan(noiseAmount: 0),
            time: 0,
            alpha: 1
        )
        let coarseNoise = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            plan: plan(noiseScale: 0.35),
            time: 0,
            alpha: 1
        )
        let radialPlan = plan(
            profile: .radialColor,
            transform: .init(
                row0: SIMD3<Float>(1, 0, 0),
                row1: SIMD3<Float>(0, 1, 0),
                row2: SIMD3<Float>(0, 0, 1)
            ),
            scale: SIMD2(0.66, 1.01),
            feather: SIMD2(0, 0.07),
            startColor: SIMD3(0.509804, 0.447059, 0.580392),
            endColor: SIMD3(0.603922, 0.176471, 0.603922),
            intensity: 1.16,
            exponent: 0,
            startAngle: 0,
            endAngle: 1
        )
        let radialFrames = [Float(0), 2, 4, 6].map { phaseTime in
            render(
                device: device,
                queue: queue,
                pipeline: pipeline,
                resources: noGradientResources,
                plan: radialPlan,
                time: phaseTime,
                alpha: 1
            )
        }
        let missingLinearGradient = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: noGradientResources,
            plan: authoredPlan,
            time: 0,
            alpha: 1
        )
        let alphaValues = stride(from: 3, to: first.bytes.count, by: 4).map {
            first.bytes[$0]
        }
        let halfAlpha = stride(from: 3, to: half.bytes.count, by: 4).map {
            half.bytes[$0]
        }
        let premultiplied = stride(from: 0, to: first.bytes.count, by: 4)
            .allSatisfy { offset in
                max(
                    first.bytes[offset],
                    first.bytes[offset + 1],
                    first.bytes[offset + 2]
                ) <= first.bytes[offset + 3]
            }
        let centerOffset = ((size / 2) * size + size / 2) * 4
        let continuousColumns = (16..<48).filter { x in
            (16..<48).filter { y in
                first.bytes[(y * size + x) * 4 + 3] > 3
            }.count >= 24
        }.count
        let sustainedAcrossPhases = phaseFrames.allSatisfy { frame in
            stride(from: 3, to: frame.bytes.count, by: 4).filter {
                frame.bytes[$0] > 3
            }.count > 200
        }
        let bilateralAcrossPhases = phaseFrames.allSatisfy { frame in
            let left = alphaTotal(frame.bytes, xRange: 16..<32)
            let right = alphaTotal(frame.bytes, xRange: 32..<48)
            return left > 1_000 && right > 1_000
        }
        let minimumBeamRuns = phaseFrames.map { frame in
            var runs = 0
            var inside = false
            for x in 14..<50 {
                let visible = frame.bytes[(24 * size + x) * 4 + 3] > 24
                if visible && !inside { runs += 1 }
                inside = visible
            }
            return runs
        }.min() ?? 0
        let unitQuad = SceneLightShaftsPipeline.unitQuadVertices
        let fixedUnitGeometry = unitQuad.count == 4
            && unitQuad.map(\.position) == [
                SIMD2<Float>(-0.5, -0.5), SIMD2<Float>(0.5, -0.5),
                SIMD2<Float>(-0.5, 0.5), SIMD2<Float>(0.5, 0.5),
            ]
            && unitQuad.map(\.texcoord) == [
                SIMD2<Float>(0, 1), SIMD2<Float>(1, 1),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            ]
        let radialAlphas = radialFrames.map { frame in
            stride(from: 3, to: frame.bytes.count, by: 4).map { frame.bytes[$0] }
        }
        let radialPremultiplied = radialFrames.allSatisfy { frame in
            stride(from: 0, to: frame.bytes.count, by: 4).allSatisfy { offset in
                max(
                    frame.bytes[offset],
                    frame.bytes[offset + 1],
                    frame.bytes[offset + 2]
                ) <= frame.bytes[offset + 3]
            }
        }
        let radialSustained = radialAlphas.allSatisfy {
            $0.filter { $0 > 3 }.count > 120
        }
        let radialBilateral = radialFrames.allSatisfy { frame in
            alphaTotal(frame.bytes, xRange: 4..<32) > 500
                && alphaTotal(frame.bytes, xRange: 32..<60) > 500
        }
        let radialBeamRuns = radialFrames.map {
            visibleRuns($0.bytes, y: 18, threshold: 8)
        }.min() ?? 0
        let radialCentroids = radialFrames.map { alphaCentroidX($0.bytes) }
        let radialMoves = (radialCentroids.max() ?? 0) - (radialCentroids.min() ?? 0) > 0.15
        let radialFansUp = radialFrames.allSatisfy {
            supportWidth($0.bytes, y: 14) > supportWidth($0.bytes, y: 54) + 4
        }
        let radialVisibleOffsets = stride(
            from: 0,
            to: radialFrames[0].bytes.count,
            by: 4
        ).filter { radialFrames[0].bytes[$0 + 3] > 3 }
        let radialUsesAuthoredPurple = radialVisibleOffsets.reduce(
            into: (blue: 0, green: 0, red: 0)
        ) { totals, offset in
            totals.blue += Int(radialFrames[0].bytes[offset])
            totals.green += Int(radialFrames[0].bytes[offset + 1])
            totals.red += Int(radialFrames[0].bytes[offset + 2])
        }
        let result: [String: Any] = [
            "metalUnavailable": false,
            "accepted": first.accepted && second.accepted && half.accepted,
            "invalidRejected": !invalid.accepted && !invalidPlan.accepted,
            "centerAlpha": first.bytes[centerOffset + 3],
            "cornerAlpha": first.bytes[3],
            "nonzeroPixels": alphaValues.filter { $0 > 0 }.count,
            "premultiplied": premultiplied,
            "timeChangesOutput": first.bytes != second.bytes,
            "continuousShaftColumns": continuousColumns,
            "sustainedAcrossPhases": sustainedAcrossPhases,
            "bilateralAcrossPhases": bilateralAcrossPhases,
            "minimumBeamRuns": minimumBeamRuns,
            "semiTransparent": (alphaValues.max() ?? 255) <= 160,
            "radiusChangesOutput": first.bytes != narrowRadius.bytes,
            "noiseAmountChangesOutput": first.bytes != noModulation.bytes,
            "noiseScaleChangesOutput": first.bytes != coarseNoise.bytes,
            "halfAlphaLower": (halfAlpha.max() ?? 0) < (alphaValues.max() ?? 0),
            "fixedUnitGeometry": fixedUnitGeometry,
            "perspectiveChangesOutput": first.bytes != alternate.bytes,
            "linearNeedsGradient": !missingLinearGradient.accepted,
            "radialAcceptedWithoutGradient": radialFrames.allSatisfy(\.accepted),
            "radialPremultiplied": radialPremultiplied,
            "radialSustained": radialSustained,
            "radialBilateral": radialBilateral,
            "radialBeamRuns": radialBeamRuns,
            "radialMoves": radialMoves,
            "radialFansUp": radialFansUp,
            "radialSemiTransparent": radialAlphas.flatMap { $0 }.max() ?? 255 <= 128,
            "radialUsesAuthoredPurple":
                radialUsesAuthoredPurple.blue > radialUsesAuthoredPurple.green
                    && radialUsesAuthoredPurple.red > radialUsesAuthoredPurple.green,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLightShaftsRenderingTests(unittest.TestCase):
    def test_product_quad_route_is_resolved_only_and_legacy_renderer_is_unit_only(
        self,
    ) -> None:
        source = LAYER_RENDERER.read_text(encoding="utf-8")
        legacy_renderer, product_routes = source.split(
            "extension SceneMetalRenderer {",
            maxsplit=1,
        )
        draw_quad, resolved_direct = product_routes.split(
            "    func drawResolvedDirectDrawQuad(",
            maxsplit=1,
        )
        draw_body = draw_quad.split(") -> Bool {", maxsplit=1)[1]

        self.assertIn("if let resolvedFramePlan {", draw_body)
        self.assertIn("return drawResolvedDirectDrawQuad(", draw_body)
        self.assertTrue(draw_body.rstrip().endswith("return true\n    }"), draw_body)
        for retired_product_call in (
            "SceneAuthoredEffectExecutionChain",
            "effectTextures.",
            "makeLightShaftsPipeline()",
            "SceneLightShaftsLayerRenderer.draw(",
            "authoredEffectTelemetry.record(",
        ):
            self.assertNotIn(retired_product_call, draw_body)

        self.assertIn("imageCompositor.drawResolvedDirectDrawQuad(", resolved_direct)
        self.assertIn("framePlan: framePlan", resolved_direct)
        self.assertIn("executionTrace: executionTrace", resolved_direct)

        self.assertIn("enum SceneLightShaftsLayerRenderer", legacy_renderer)
        self.assertIn("let encoded = pipeline.draw(", legacy_renderer)
        self.assertIn("executionTrace.recordExact(", legacy_renderer)
        self.assertIn('family: "light-shafts"', legacy_renderer)

    def test_quad_is_animated_feathered_and_premultiplied(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-light-shafts-rendering-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-light-shafts-rendering"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    str(PIPELINE),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if result["metalUnavailable"]:
            self.skipTest("Metal is unavailable")
        self.assertTrue(result["accepted"], result)
        self.assertTrue(result["invalidRejected"], result)
        self.assertGreater(result["centerAlpha"], 0, result)
        self.assertEqual(result["cornerAlpha"], 0, result)
        self.assertGreater(result["nonzeroPixels"], 0, result)
        self.assertTrue(result["premultiplied"], result)
        self.assertTrue(result["timeChangesOutput"], result)
        self.assertGreaterEqual(result["continuousShaftColumns"], 4, result)
        self.assertTrue(result["sustainedAcrossPhases"], result)
        self.assertTrue(result["bilateralAcrossPhases"], result)
        self.assertGreaterEqual(result["minimumBeamRuns"], 2, result)
        self.assertTrue(result["semiTransparent"], result)
        self.assertTrue(result["radiusChangesOutput"], result)
        self.assertTrue(result["noiseAmountChangesOutput"], result)
        self.assertTrue(result["noiseScaleChangesOutput"], result)
        self.assertTrue(result["halfAlphaLower"], result)
        self.assertTrue(result["fixedUnitGeometry"], result)
        self.assertTrue(result["perspectiveChangesOutput"], result)
        self.assertTrue(result["linearNeedsGradient"], result)
        self.assertTrue(result["radialAcceptedWithoutGradient"], result)
        self.assertTrue(result["radialPremultiplied"], result)
        self.assertTrue(result["radialSustained"], result)
        self.assertTrue(result["radialBilateral"], result)
        self.assertGreaterEqual(result["radialBeamRuns"], 3, result)
        self.assertTrue(result["radialMoves"], result)
        self.assertTrue(result["radialFansUp"], result)
        self.assertTrue(result["radialSemiTransparent"], result)
        self.assertTrue(result["radialUsesAuthoredPurple"], result)


if __name__ == "__main__":
    unittest.main()
