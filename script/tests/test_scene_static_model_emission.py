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


def distance_fog_vectors() -> list[dict]:
    # Official half-gray flat-quad probes: the halfway distance yields RGB 96,
    # while a constant .5 density yields 64. These are different contracts.
    # The harness pixel is at world (0, 0, .5); camera positions preserve the
    # independently specified distance, including an off-axis radial control.
    cases = [
        ("quarter", [0, 4, 0, 1], [0, 0, 1.5], 0.0625),
        ("half", [0, 2, 0, 1], [0, 0, 1.5], 0.25),
        ("three-quarter", [0, 4 / 3, 0, 1], [0, 0, 1.5], 0.5625),
        ("offset", [0.5, 1.5, 0, 1], [0, 0, 1.5], 0.25),
        ("double-distance", [0, 4, 0, 1], [0, 0, 2.5], 0.25),
        ("off-axis", [0, 2, 0, 1], [1, 0, 1.5], 0.5),
        ("before-start", [2, 4, 0.2, 0.8], [0, 0, 1.5], 0.2),
        ("after-end", [0, 0.5, 0.2, 0.8], [0, 0, 1.5], 0.8),
        ("density-endpoints", [0, 2, 0.2, 0.8], [0, 0, 1.5], 0.35),
    ]
    return [dict(
        name=f"distance-fog-{name}", albedo=[0.5, 0.5, 0.5], opacity=1,
        normal=[0, 1, 0], ambient=[1, 1, 1], ambientResponse=1,
        hasMask=False, maskAlpha=0, emissiveColor=[1, 1, 1], brightness=0,
        fogRange=interval, cameraPosition=camera, expectedFogDensity=density,
        fogColor=[0.125, 0.25, 0.5] if name == "density-endpoints" else [0, 0, 0],
    ) for name, interval, camera, density in cases]


def surface_vectors() -> list[dict]:
    # Frozen own-plane official U8 centers (WE 2.8.0.42, 2026-10-09).
    # Translate the known receiver/light/camera together by +.5Z to the
    # existing 1px harness plane; no BRDF expression is used as the oracle.
    cases = [
        ("H1-point-axis", "point", 0, .7, [0, 0, 2.5], [0, 0, 4.5], 54),
        ("spot-axis", "spot", 0, .7, [0, 0, 2.5], [0, 0, 4.5], 54),
        ("H2-point-oblique", "point", 0, .7, [1.6, 0, 1.7], [0, 0, 4.5], 31),
        ("H3-spot-view60", "spot", 0, .7, [0, 0, 2.5], [math.sqrt(12), 0, 2.5], 52),
        ("H8-roughness-half", "spot", 0, .5, [0, 0, 2.5], [0, 0, 4.5], 66),
        ("H9-roughness-one", "spot", 0, 1, [0, 0, 2.5], [0, 0, 4.5], 51),
        ("H10-metal-view60", "spot", 1, .7, [0, 0, 2.5], [math.sqrt(12), 0, 2.5], 25),
    ]
    rows = [dict(name=name, lamp=lamp, surface=[m, r], lightPosition=position,
        cameraPosition=camera, expectedByte=expected, albedo=[1, 1, 1], tint=[.5, .5, .5],
        ambient=[0, 0, 0], emissiveColor=[1, 1, 1], brightness=0, opacity=1,
        hasMask=False, maskAlpha=0) for name, lamp, m, r, position, camera, expected in cases]
    rows.append(dict(rows[1], name="gray128-white-tint-pair",
        albedo=[128/255]*3, tint=[1, 1, 1]))
    # Local preservation controls use the old project's center, not an official BRDF claim.
    rows.append(dict(rows[0], name="legacy-point-preserved", surface=None, expectedByte=49))
    # The old directional preservation row inherited a surface profile while
    # asserting the legacy path. The official metallic single-variable probe
    # disproves that bypass; preserve the original 77 oracle on its nil domain.
    rows.append(dict(rows[0], name="directional-preserved", lamp="directional",
        surface=None, expectedByte=77))
    default_directional = dict(rows[-1], name="directional-default-preserved")
    del default_directional["surface"]
    rows.append(default_directional)
    # These axis fixtures place point/spot two units away at radius ten. Their
    # independently validated falloff is .64, so a directional intensity 1.28
    # supplies the same incident energy as intensity-two point/spot. Keep the
    # existing measured point/spot pixel oracles, rather than deriving a BRDF.
    for reference in ("H1-point-axis", "H9-roughness-one", "H10-metal-view60"):
        row = next(row for row in rows if row["name"] == reference)
        rows.append(dict(row, name=f"directional-{reference}", lamp="directional",
            lightIntensity=1.28, equivalentIncidentEnergy=reference))
    neutral = next(row for row in rows if row["name"] == "directional-H9-roughness-one")
    # Retain an interior metallic declaration matching the real author input;
    # its response must differ from zero, not just from the metallic endpoint.
    rows.append(dict(neutral, name="directional-metallic-point14", surface=[.14, 1],
        equivalentIncidentEnergy=None, expectedByte=None,
        materialResponseReference=neutral["name"]))
    rows.append(dict(neutral, name="directional-nil-at-same-energy", surface=None,
        equivalentIncidentEnergy=None, expectedByte=49))
    # Reproduced black output from early half(100000), despite a finite
    # metallic surface response. This checks storage safety, not official HDR parity.
    rows.append(dict(rows[0], name="metal-hdr-finite-response", surface=[1, .7],
        tint=[1, 1, 1], materialBrightness=100000, usesHDR=True, finiteSurface=True,
        expectedByte=108))
    rows.append(dict(rows[-1], name="directional-metal-hdr-finite-response",
        lamp="directional", lightIntensity=1.28,
        equivalentIncidentEnergy="metal-hdr-finite-response"))
    for profile in (None, [0, .7]):
        rows.append(dict(rows[0], name=f"directional-unlit-profile-{profile is not None}",
            lamp="directional", surface=profile, receivesLighting=False,
            albedo=ALBEDO, tint=[1, 1, 1], opacity=OPACITY, lightIntensity=100,
            ambient=[20, 30, 40], expectedByte=None,
            expectedUnlitPixel=[0.15, 0.225, 0.3, OPACITY]))
    return rows


def surface_storage_vectors() -> list[dict]:
    # Positive finite author values; low/high HDR and view tint cover both
    # optional-profile states. The high tint has unequal endpoints and an
    # interior view weight, so legacy half mixing yields inf rather than inf-inf.
    base = surface_vectors()[0]
    return [dict(base, name=f"surface-storage-{profile}-{brightness}-{tint}",
        surface=[0, .7] if profile else None, materialBrightness=brightness,
        usesHDR=True, viewTint=[tint, 1], cameraPosition=[math.sqrt(12), 0, 2.5],
        storageBoundary=True, expectedByte=None)
        for profile, brightness, tint in itertools.product([False, True], [1, 100000], [1, 100000])]


def expected_pixel(vector: dict) -> list[float]:
    # The additive material contract was established by controlled official
    # renders; known-normal cases carry measured response weights independently.
    if "expectedUnlitPixel" in vector:
        return vector["expectedUnlitPixel"]
    mask = vector["maskAlpha"] if vector["hasMask"] else 0.0
    radiance = [
        albedo * (ambient * vector.get("ambientResponse", 0.5)
                  + sky * vector.get("skyResponse", 0.5)
                  + color * mask * vector["brightness"])
        for albedo, ambient, sky, color in zip(
            vector["albedo"], vector["ambient"], vector.get("skylight", [0, 0, 0]), vector["emissiveColor"]
        )
    ]
    density = vector.get("expectedFogDensity", vector.get("fogDensity"))
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
                color: vector(input["tint"] as? [Double] ?? [1, 1, 1]), opacity: Float(input["opacity"] as! Double),
                receivesLighting: input["receivesLighting"] as? Bool ?? true,
                textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
                emissiveColor: vector(input["emissiveColor"] as! [Double]),
                emissiveBrightness: Float(input["brightness"] as! Double),
                brightness: Float(input["materialBrightness"] as? Double ?? 1),
                usesHDRBrightness: input["usesHDR"] as? Bool ?? false,
                viewTint: (input["viewTint"] as? [Double]).map {
                    .init(front: SIMD3(repeating: Float($0[0])),
                          back: SIMD3(repeating: Float($0[1])), exponent: 1.5,
                          usesDynamicBackColor: false)
                },
                surfaceProfile: (input["surface"] as? [Double]).map {
                    .init(metallic: Float($0[0]), roughness: Float($0[1]))
                }, cullMode: .none
            )
            let lamp = input["lamp"] as? String
            let lightIntensity = Float(input["lightIntensity"] as? Double ?? 2)
            let lightPosition = vector(input["lightPosition"] as? [Double] ?? [0, 0, 2.5])
            var lighting = SceneLightSnapshot(
                ambient: vector(input["ambient"] as! [Double]),
                skylight: vector(input["skylight"] as? [Double] ?? [0, 0, 0]),
                directional: lamp == "directional" ? [.init(
                    directionTowardLight: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: lightIntensity
                )] : [],
                point: lamp == "point" ? [.init(position: lightPosition,
                    color: SIMD3(repeating: 1), intensity: lightIntensity, radius: 10)] : [],
                spot: lamp == "spot" ? [.init(position: lightPosition,
                    directionFromLight: SIMD3(0, 0, -1), color: SIMD3(repeating: 1), intensity: lightIntensity,
                    radius: 10, innerConeCosine: cos(Float.pi/9),
                    outerConeCosine: cos(Float.pi*2/9), outerConeDegrees: 40)] : [],
                overflowCount: 0
            )
            if let density = input["fogDensity"] as? Double {
                let fogColor = vector(input["fogColor"] as! [Double])
                lighting.distanceFogColor = SIMD4(fogColor, 1)
                lighting.distanceFogRange = SIMD4(0, 20, Float(density), Float(density))
            }
            if let range = input["fogRange"] as? [Double] {
                lighting.distanceFogColor = SIMD4(vector(input["fogColor"] as! [Double]), 1)
                lighting.distanceFogRange = SIMD4(Float(range[0]), Float(range[1]), Float(range[2]), Float(range[3]))
            }
            precondition(pipeline.draw(
                mesh: mesh, texture: albedo, colorTextureIsPremultiplied: false,
                emissiveMask: mask, emissiveMaskTextureFrame: mask == nil ? nil : .identity,
                emissiveMaskSampling: mask == nil ? nil : .linearClamp, modelMatrix: matrix_identity_float4x4,
                viewProjection: matrix_identity_float4x4,
                cameraPosition: vector(input["cameraPosition"] as? [Double] ?? [0, 0, 10]),
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
            "POINT_LIGHT_SOURCE", "SPOT_LIGHT_SOURCE", "LIGHT_SOURCE", "VISIBILITY_SOURCE", "DYNAMIC_SNAPSHOT_SOURCE",
            "DYNAMIC_LAYER_VALUES_SOURCE", "PERFORMANCE_COUNTER_SOURCE", "MATERIAL_SOURCE", "PIPELINE_SOURCE", "SHADOW_SOURCE",
        ]]
        sources += [
            SCENE / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
            SCENE / "Resources/Textures/SceneResourceBudget.swift",
        ]
        cls.vectors = emission_vectors() + ambient_vectors() + distance_fog_vectors() + surface_vectors() + surface_storage_vectors()
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
            if "expectedByte" in vector and "expectedUnlitPixel" not in vector:
                continue
            for channel, (actual, expected) in enumerate(zip(row["pixel"], expected_pixel(vector))):
                with self.subTest(case=vector["name"], channel=channel):
                    actual = float(actual)
                    self.assertTrue(math.isfinite(actual), row)
                    self.assertAlmostEqual(actual, expected, delta=half_storage_tolerance(expected))

    def test_static_surface_response_matches_frozen_center_observations(self):
        for vector, row in zip(self.vectors, self.report["rows"]):
            if vector.get("expectedByte") is None:
                continue
            with self.subTest(case=vector["name"]):
                if vector.get("finiteSurface"):
                    self.assertTrue(all(math.isfinite(float(v)) and float(v) > 0 for v in row["pixel"][:3]))
                for actual in row["pixel"][:3]:
                    self.assertLessEqual(abs(float(actual)*255-vector["expectedByte"]), 1)

    def test_directional_profile_matches_incident_energy_and_preserves_legacy(self):
        by_name = {row["name"]: row for row in self.report["rows"]}
        for vector in self.vectors:
            reference = vector.get("equivalentIncidentEnergy")
            if reference is None:
                continue
            with self.subTest(case=vector["name"]):
                for actual, expected in zip(by_name[vector["name"]]["pixel"], by_name[reference]["pixel"]):
                    self.assertAlmostEqual(float(actual), float(expected),
                        delta=half_storage_tolerance(float(expected)))
        self.assertEqual(by_name["directional-preserved"]["pixel"],
            by_name["directional-default-preserved"]["pixel"])
        metallic = by_name["directional-metallic-point14"]["pixel"]
        neutral = by_name["directional-H9-roughness-one"]["pixel"]
        for actual, reference in zip(metallic[:3], neutral[:3]):
            self.assertGreater(float(actual), 0)
            self.assertLess(float(actual), float(reference))

    def test_finite_surface_storage_profile_and_legacy_boundaries(self):
        legacy = {(1, 1): 49/255, (1, 100000): MAX_HALF,
                  (100000, 1): 19200, (100000, 100000): MAX_HALF}
        for vector, row in zip(self.vectors, self.report["rows"]):
            if not vector.get("storageBoundary"):
                continue
            with self.subTest(case=vector["name"]):
                for channel in row["pixel"][:3]:
                    actual = float(channel)
                    self.assertTrue(math.isfinite(actual) and actual > 0)
                    self.assertLessEqual(actual, MAX_HALF)
                    if vector["surface"] is None:
                        expected = legacy[(vector["materialBrightness"], vector["viewTint"][0])]
                        self.assertAlmostEqual(actual, expected, delta=half_storage_tolerance(expected))
