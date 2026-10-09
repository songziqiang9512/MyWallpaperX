"""Real static-model ambient and emission pixels through the shared GPU harness."""

from __future__ import annotations

import itertools
import math
import unittest

from script.tests import test_scene_static_model_pipeline as model_fixture
from script.tests.test_scene_directional_shadow import SCENE, run_swift


ALBEDO = [0.2, 0.3, 0.4]
OPACITY = 0.75
MAX_HALF = 65504.0
MAX_FLOAT = 3.4028234663852886e38


def emission_vectors() -> list[dict]:
    vectors = [
        {
            "name": f"mask-{mask}-gain-{gain}-ambient-{light}-color-{color}",
            "albedo": ALBEDO,
            "maskAlpha": mask,
            "hasMask": True,
            "brightness": gain,
            "ambient": [0.0, 0.0, 0.0] if light == 0 else [0.4, 0.6, 0.8],
            "emissiveColor": [1.0, 1.0, 1.0] if color == 0 else [0.5, 0.25, 0.75],
            "opacity": OPACITY,
        }
        for mask, gain, light, color in itertools.product(
            [0.0, 0.25, 1.0], [0.0, 0.25, 1.0, 4.0, 10.0, 100000.0], range(2), range(2)
        )
    ]
    def extra(name, *, gain, albedo=ALBEDO, color=(1.0, 1.0, 1.0), ambient=(0.4, 0.6, 0.8),
              has_mask=True, fog_density=None):
        vectors.append({
            "name": name, "albedo": albedo, "maskAlpha": 1.0, "hasMask": has_mask,
            "brightness": gain, "ambient": ambient, "emissiveColor": color, "opacity": OPACITY,
            "fogDensity": fog_density, "fogColor": [0.125, 0.25, 0.5],
        })
    for gain in [1.0, 100000.0]:
        extra(f"black-albedo-gain-{gain}", gain=gain, albedo=[0.0, 0.0, 0.0])
        for light in range(2):
            extra(f"no-mask-gain-{gain}-ambient-{light}", gain=gain, has_mask=False,
                  ambient=[0.0, 0.0, 0.0] if light == 0 else [0.4, 0.6, 0.8])
    extra("final-premultiplied-storage-limit", gain=100000.0, albedo=[1.0, 1.0, 1.0])
    extra("max-float-zero-emissive-color", gain=MAX_FLOAT, color=[0.0, 0.0, 0.0])
    extra("max-float-black-albedo", gain=MAX_FLOAT, albedo=[0.0, 0.0, 0.0])
    extra("full-fog-extreme-emission", gain=1e30, color=[1e30, 1e30, 1e30], fog_density=1.0)
    extra("partial-fog-extreme-storage-limit", gain=1e30, color=[1e30, 1e30, 1e30], fog_density=0.5)
    extra("partial-fog-before-storage-limit", gain=100000.0, albedo=[1.0, 1.0, 1.0], fog_density=0.5)
    return vectors


def ambient_vectors() -> list[dict]:
    # Official fixed-unit-normal inputs (2026-10-09), half-gray albedo:
    # ambient-only bytes 0,32,64,96,128; sky-only endpoints/midpoint 128,64,0.
    cases = [
        (f"ambient-y-{y}", [math.sqrt(1-y*y), y, 0], [0.4, 0.6, 0.8], [0, 0, 0], a, 0)
        for y, a in [(-1, 0), (-0.5, 0.25), (0, 0.5), (0.5, 0.75), (1, 1)]
    ] + [
        (f"sky-y-{y}", [math.sqrt(1-y*y), y, 0], [0, 0, 0], [0.4, 0.6, 0.8], 0, sky)
        for y, sky in [(-1, 1), (0, 0.5), (1, 0)]
    ] + [
        ("mixed-y-zero", [1, 0, 0], [0.2, 0.4, 0.6], [0.6, 0.4, 0.2], 0.5, 0.5),
        ("ambient-z-plus1", [0, 0, 1], [0.4, 0.6, 0.8], [0, 0, 0], 0.5, 0),
    ]
    return [
        {"name": name, "normal": normal, "ambient": ambient, "skylight": sky,
         "ambientResponse": a, "skyResponse": k, "albedo": ALBEDO,
         "hasMask": False, "maskAlpha": 0, "emissiveColor": [1, 1, 1],
         "brightness": 0, "opacity": OPACITY}
        for name, normal, ambient, sky, a, k in cases
    ]


def expected_pixel(vector: dict) -> list[float]:
    # The additive material contract was established by controlled official
    # renders; known-normal cases carry measured response weights independently.
    mask = vector["maskAlpha"] if vector["hasMask"] else 0.0
    radiance = [
        albedo * (ambient * vector.get("ambientResponse", 0.5)
                  + sky * vector.get("skyResponse", 0.5)
                  + color * mask * vector["brightness"])
        for albedo, ambient, sky, color in zip(
            vector["albedo"], vector["ambient"], vector.get("skylight", [0, 0, 0]), vector["emissiveColor"]
        )
    ]
    density = vector.get("fogDensity")
    if density is not None:
        radiance = [lit * (1.0 - density) + fog * density
                    for lit, fog in zip(radiance, vector["fogColor"])]
    return [min(MAX_HALF, max(0.0, lit * vector["opacity"])) for lit in radiance] + [vector["opacity"]]


def half_storage_tolerance(expected: float) -> float:
    # Two Float16 ULPs allow texture sample and final storage rounding without
    # allowing a gain plateau, an emission mix, or early storage clamping.
    exponent = math.floor(math.log2(abs(expected))) if expected else -14
    return 2.0 ** (max(-14, exponent) - 9)


PIXEL_MAIN = r'''
@main enum StaticModelEmissionProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float)!
        let inputs = try JSONSerialization.jsonObject(with: Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )) as! [[String: Any]]
        func vector(_ values: [Double]) -> SIMD3<Float> {
            SIMD3(Float(values[0]), Float(values[1]), Float(values[2]))
        }
        func texture(_ rgb: [Double], alpha: Float) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false
            )
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            let result = device.makeTexture(descriptor: descriptor)!
            var value = [Float(rgb[0]), Float(rgb[1]), Float(rgb[2]), alpha]
            value.withUnsafeMutableBytes {
                result.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 16)
            }
            return result
        }
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0.5), SIMD3(1, -1, 0.5), SIMD3(1, 1, 0.5), SIMD3(-1, 1, 0.5),
        ]
        let commandBuffer = queue.makeCommandBuffer()!
        var buffers: [MTLBuffer] = []
        for input in inputs {
            let vertices = positions.map {
                SceneMdlStaticModel.Vertex(position: $0, normal: vector(input["normal"] as? [Double] ?? [0, 0, 1]),
                    tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.5, 0.5))
            }
            let mesh = pipeline.makeMesh(vertices: vertices, indices: [0, 1, 2, 0, 2, 3])!
            let albedo = texture(input["albedo"] as! [Double], alpha: 1)
            let mask: MTLTexture? = (input["hasMask"] as! Bool)
                ? texture([0, 0, 0], alpha: Float(input["maskAlpha"] as! Double)) : nil
            let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false
            )
            colorDescriptor.storageMode = .private
            colorDescriptor.usage = .renderTarget
            let output = device.makeTexture(descriptor: colorDescriptor)!
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false
            )
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = .renderTarget
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            pass.depthAttachment.texture = device.makeTexture(descriptor: depthDescriptor)!
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 0
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
            let material = SceneStaticModelMaterial(
                color: SIMD3(repeating: 1), opacity: Float(input["opacity"] as! Double),
                receivesLighting: true, textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
                emissiveColor: vector(input["emissiveColor"] as! [Double]),
                emissiveBrightness: Float(input["brightness"] as! Double), brightness: 1,
                usesHDRBrightness: false, viewTint: nil, cullMode: .none
            )
            var lighting = SceneLightSnapshot(
                ambient: vector(input["ambient"] as! [Double]),
                skylight: vector(input["skylight"] as? [Double] ?? [0, 0, 0]),
                directional: [], point: [], spot: [], overflowCount: 0
            )
            if let density = input["fogDensity"] as? Double {
                let fogColor = vector(input["fogColor"] as! [Double])
                lighting.distanceFogColor = SIMD4(fogColor, 1)
                lighting.distanceFogRange = SIMD4(0, 20, Float(density), Float(density))
            }
            precondition(pipeline.draw(
                mesh: mesh, texture: albedo, colorTextureIsPremultiplied: false,
                emissiveMask: mask, emissiveMaskTextureFrame: mask == nil ? nil : .identity,
                emissiveMaskSampling: mask == nil ? nil : .linearClamp, modelMatrix: matrix_identity_float4x4,
                viewProjection: matrix_identity_float4x4, cameraPosition: SIMD3(0, 0, 10),
                textureFrame: .identity, sampling: .linearClamp, layerAlpha: 1,
                material: material, lighting: lighting, writesDepth: true, frameEpoch: 1,
                commandBuffer: commandBuffer, encoder: encoder
            ))
            encoder.endEncoding()
            let buffer = device.makeBuffer(length: 256, options: .storageModeShared)!
            let blit = commandBuffer.makeBlitCommandEncoder()!
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0), sourceSize: .init(width: 1, height: 1, depth: 1),
                to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
            blit.endEncoding()
            buffers.append(buffer)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let completed = commandBuffer.status == .completed && commandBuffer.error == nil
        let rows = zip(inputs, buffers).map { input, buffer -> [String: Any] in
            let pixel = buffer.contents().bindMemory(to: UInt16.self, capacity: 4)
            let channels = (0..<4).map {
                Float(Float16(bitPattern: pixel[$0]))
            }
            return ["name": input["name"]!, "pixel": channels.map {
                $0.isFinite ? $0 as Any : String(describing: $0) as Any
            }, "completed": completed]
        }
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: ["rows": rows], options: [.sortedKeys]
        ), as: UTF8.self))
    }
}
'''


class SceneStaticModelEmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sources = [getattr(model_fixture, name) for name in [
            "MODEL_SOURCE", "SAMPLING_SOURCE", "UV_TRANSFORM_SOURCE", "DIRECTIONAL_LIGHT_SOURCE",
            "POINT_LIGHT_SOURCE", "SPOT_LIGHT_SOURCE", "LIGHT_SOURCE", "DYNAMIC_SNAPSHOT_SOURCE",
            "DYNAMIC_LAYER_VALUES_SOURCE", "PERFORMANCE_COUNTER_SOURCE", "PIPELINE_SOURCE", "SHADOW_SOURCE",
        ]]
        sources += [
            SCENE / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
            SCENE / "Resources/Textures/SceneResourceBudget.swift",
        ]
        cls.vectors = emission_vectors() + ambient_vectors()
        cls.report = run_swift(
            sources, "import Foundation\nimport Metal\nimport simd\n" + model_fixture.LIGHTING_STUB + PIXEL_MAIN,
            label="model-emission", metal_sources=[model_fixture.METAL_SOURCE], input_value=cls.vectors,
        )

    def test_matrix_completes_with_finite_premultiplied_pixels(self):
        rows = self.report["rows"]
        self.assertEqual(len(rows), len(self.vectors))
        for vector, row in zip(self.vectors, rows):
            with self.subTest(case=vector["name"]):
                self.assertEqual(row["name"], vector["name"])
                self.assertTrue(row["completed"])
                self.assertEqual(len(row["pixel"]), 4)
                self.assertTrue(all(math.isfinite(float(value)) for value in row["pixel"]))
                self.assertEqual(row["pixel"][3], vector["opacity"])

    def test_additive_emission_pixels_match_numeric_contract(self):
        for vector, row in zip(self.vectors, self.report["rows"]):
            for channel, (actual, expected) in enumerate(zip(row["pixel"], expected_pixel(vector))):
                with self.subTest(case=vector["name"], channel=channel):
                    actual = float(actual)
                    self.assertTrue(math.isfinite(actual), row)
                    self.assertAlmostEqual(actual, expected, delta=half_storage_tolerance(expected))
