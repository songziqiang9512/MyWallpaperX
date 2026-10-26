#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
MAP_SOURCES = [
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerImageEmissionMap.swift",
]

from script.tests import test_scene_solid_layers as descriptor_fixture
from script.tests import test_scene_bc_texture_uploader as upload_fixture
from script.tests.scene_particle_runtime_configuration_cases import NO_TIMESTAMP_OBSERVATION_SUPPORT
from script.scene_swift_source_sets import scene_swift_sources

SOURCES = list(dict.fromkeys(path.resolve() for path in [
    *MAP_SOURCES, *descriptor_fixture.SWIFT_SOURCES, *upload_fixture.SWIFT_SOURCES,
    *scene_swift_sources("authored_shader_frontend_support"),
    SOURCE_ROOT / "Resources/Assets/SceneModelResourceIdentity.swift",
    SOURCE_ROOT / "Compilation/ShaderContract/SceneBuiltinShaderIdentity.swift",
    SOURCE_ROOT / "Compilation/Material/SceneMaterialRenderState+Compilation.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleLayerImageEmitterCompiler.swift",
]))
# Use the real descriptor/loader/compiler. Reuse existing link-only asset shells;
# remove their unused particle shells because this harness links real particles.
DESCRIPTOR_SUPPORT = descriptor_fixture.HARNESS_SOURCE.split("@main", 1)[0].replace(
    "struct SceneParticleInstanceOverride: Codable {}\n\n"
    "struct SceneParticleDefinitionParser {\n"
    "    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }\n"
    "}\n", "").replace(
    "var shaderContracts: [Never] { [] }",
    "var shaderContracts: [SceneShaderContract] { [] }",
).replace(
    "let puppetAttachments: [SceneMdlPuppetAttachment]",
    "let puppetAttachments: [SceneMdlPuppetAttachment]\n        var passthrough: Bool? = nil",
)
# This fixture passes an empty model/material/shader catalog to the real
# descriptor builder. Keep that explicit empty input while matching its current
# DTO types. Identity matching and material-state compilation remain product
# sources; no shader compiler/diagnostic platform or alternate emitter is added.
RUNTIME_DECLARATIONS = (SOURCE_ROOT / "Systems/Particles/SceneParticleRuntimeModels.swift").read_text().split(
    "struct SceneParticleDrawBatch", 1)[0]
HARNESS_SOURCE = (NO_TIMESTAMP_OBSERVATION_SUPPORT + DESCRIPTOR_SUPPORT
                  + upload_fixture.HARNESS.split("@main", 1)[0]
                  + RUNTIME_DECLARATIONS + r'''
@main enum Harness {
    enum Failure: Error { case allocation, decode, compile }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-emitter-map-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = try makeDescriptor(root: root)
        var results: [String: Any] = [:]
        let original = try makeRGBA(device: device, format: .bgra8Unorm, width: 4, height: 2,
            rgba: Data([0,0,0,255] + Array(repeating: UInt8(0), count: 24) + [0,0,0,255]))
        let oldMap = SceneParticleLayerImageEmissionMap(texture: original, sourceSize: SIMD2(40,20))!
        results["positions"] = oldMap.positions.map { [$0.x,$0.y,$0.z] }
        let zero = try makeRGBA(device: device, format: .rgba8Unorm, width: 8, height: 4,
            rgba: Data(repeating: 0, count: 128))
        results["transparentRejected"] = rejected(descriptor: descriptor, texture: zero)
        var cases: [String: Any] = [:]
        for (name, format, pixelFormat, block) in [
            ("bc1TransparentSelectors", UInt32(7), MTLPixelFormat.bc1_rgba,
                Data([0xe0,0x07,0x1f,0xf8,0xe4,0x1b,0x72,0x8d])),
            ("bc2MixedAlpha", UInt32(6), MTLPixelFormat.bc2_rgba,
                Data([0x10,0x32,0x54,0x76,0x98,0xba,0xdc,0xfe,
                      0x1f,0xf8,0xe0,0x07,0xe4,0x1b,0x72,0x8d])),
            ("bc3InterpolatedAlpha", UInt32(4), MTLPixelFormat.bc3_rgba,
                Data([203,19,0x88,0xc6,0xfa,0x88,0xc6,0xfa,
                      0x1f,0xf8,0xe0,0x07,0xe4,0x1b,0x72,0x8d])),
            ("bc3ZeroAndFullAlpha", UInt32(4), MTLPixelFormat.bc3_rgba,
                Data([19,203,0x88,0xc6,0xfa,0x88,0xc6,0xfa,
                      0x1f,0xf8,0xe0,0x07,0xe4,0x1b,0x72,0x8d])),
        ] {
            let blocks = block + block
            let container = SceneTexContainer(format: format, flags: 2,
                textureWidth: 8, textureHeight: 4, imageWidth: 8, imageHeight: 4,
                containerVersion: .texb0002, freeImageFormat: -1, isVideoMp4: false,
                images: [.init(mips: [.init(width: 8,height: 4,data: blocks)])],spriteFrames: [])
            guard case let .loaded(texture) = SceneCompressedTextureUploader.upload(
                container: container, pixelFormat: pixelFormat,
                purpose: .straightAlbedo, device: device),
                let decoded = SceneBCTextureDecoder.decode(blockData: blocks,
                    storedWidth: 8, storedHeight: 4, imageWidth: 8, imageHeight: 4,
                    format: SceneBCTextureDecoder.Format(texFormat: format)!) else { throw Failure.decode }
            let compilation = SceneParticleLayerImageEmitterCompiler.compile(
                descriptor: descriptor, texturesByLayerID: [1:texture])
            guard let actual = compilation.mapsByLayerID[2] else { throw Failure.compile }
            var referenceResults: [String: Bool] = [:]
            for (label, rgbaFormat) in [("RGBA",MTLPixelFormat.rgba8Unorm),
                ("BGRA",.bgra8Unorm),("RGBAsRGB",.rgba8Unorm_srgb),("BGRAsRGB",.bgra8Unorm_srgb)] {
                let referenceTexture = try makeRGBA(device: device,format: rgbaFormat,
                    width: 8,height: 4,rgba: decoded.rgba)
                let referenceCompilation = SceneParticleLayerImageEmitterCompiler.compile(
                    descriptor: descriptor,texturesByLayerID: [1:referenceTexture])
                guard let reference = referenceCompilation.mapsByLayerID[2] else { throw Failure.compile }
                var first = SceneParticleRandomGenerator(state: 919)
                var second = SceneParticleRandomGenerator(state: 919)
                var sameSamples = true
                for _ in 0..<1024 {
                    sameSamples = sameSamples && actual.sample(using: &first) == reference.sample(using: &second)
                }
                referenceResults[label] = actual.positions == reference.positions && sameSamples
#if DEBUG
                referenceResults[label] = referenceResults[label]! && referenceCompilation.diagnostics.isEmpty
#endif
            }
            let renamed = try makeDescriptor(root: root,provider: 11,consumer: 29,name: "Renamed image")
            let renamedCompilation = SceneParticleLayerImageEmitterCompiler.compile(
                descriptor: renamed,texturesByLayerID: [11:texture])
            let positiveCount = stride(from: 3, to: decoded.rgba.count, by: 4)
                .filter { decoded.rgba[$0] > 0 }.count
            var facts: [String: Any] = [
                "nativeSource": !device.supportsBCTextureCompression || texture.pixelFormat == pixelFormat,
                "positivePixelCount": positiveCount,"positionsCount": actual.positions.count,
                "references": referenceResults,
                "renamedIdentitySamePositions": renamedCompilation.mapsByLayerID[29]?.positions == actual.positions,
                "animatedSourceRejected": SceneParticleLayerImageEmitterCompiler.compile(
                    descriptor: descriptor,texturesByLayerID: [1:texture],animatedSourceLayerIDs: [1])
                    .mapsByLayerID[2] == nil]
#if DEBUG
            facts["diagnosticsEmpty"] = compilation.diagnostics.isEmpty
#endif
            cases[name] = facts
        }
        results["cases"] = cases
        var rejections: [String: Bool] = [:]
        for (name, format, width, height, mode) in [
            ("privateRGBA",MTLPixelFormat.rgba8Unorm,8,4,MTLStorageMode.private),
            ("privateBC",.bc3_rgba,8,4,.private),
            ("pixelBudgetRGBA",.rgba8Unorm,1028,1024,.shared),
            ("pixelBudgetBC",.bc3_rgba,1028,1024,.shared),
            ("unsupportedR8",.r8Unorm,8,4,.shared),
        ] {
            if (format == .bc3_rgba) && !device.supportsBCTextureCompression { continue }
            let spec = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width,height: height,mipmapped: false)
            spec.storageMode = mode; spec.usage = .shaderRead
            guard let texture = device.makeTexture(descriptor: spec) else { throw Failure.allocation }
            rejections[name] = rejected(descriptor: descriptor,texture: texture)
        }
        results["rejections"] = rejections
        let transparentBC = SceneTexContainer(format: 7, flags: 2,textureWidth: 4,textureHeight: 4,
            imageWidth: 4,imageHeight: 4,containerVersion: .texb0002,freeImageFormat: -1,isVideoMp4: false,
            images: [.init(mips: [.init(width: 4,height: 4,
                data: Data([0,0,255,255,255,255,255,255]))])],spriteFrames: [])
        guard case let .loaded(transparent) = SceneCompressedTextureUploader.upload(
            container: transparentBC,pixelFormat: .bc1_rgba,purpose: .straightAlbedo,device: device)
            else { throw Failure.allocation }
        results["transparentBCRejected"] = rejected(descriptor: descriptor,texture: transparent)
        results["compilationHasDiagnosticStorage"] = Mirror(reflecting: SceneParticleLayerImageEmitterCompilation.empty)
            .children.contains { $0.label == "diagnostics" }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results),as: UTF8.self))
    }

    static func rejected(descriptor: SceneRenderDescriptor,texture: MTLTexture) -> Bool {
        let value = SceneParticleLayerImageEmitterCompiler.compile(
            descriptor: descriptor,texturesByLayerID: [1:texture])
        guard value.mapsByLayerID[2] == nil else { return false }
#if DEBUG
        return value.diagnostics.count == 1
            && value.diagnostics[0].kind == .layerImageEmitterUnsupported
            && value.diagnostics[0].detail == "unsupportedOrEmptyEmissionBitmap:1"
#else
        return true
#endif
    }

    static func makeRGBA(device: MTLDevice,format: MTLPixelFormat,width: Int,height: Int,
                         rgba: Data) throws -> MTLTexture {
        let spec = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: width,height: height,mipmapped: false)
        spec.storageMode = .shared;spec.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: spec) else { throw Failure.allocation }
        var pixels = [UInt8](rgba)
        if format == .bgra8Unorm || format == .bgra8Unorm_srgb {
            for offset in stride(from: 0,to: pixels.count,by: 4) { pixels.swapAt(offset,offset+2) }
        }
        pixels.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0,0,width,height),
            mipmapLevel: 0,withBytes: $0.baseAddress!,bytesPerRow: width*4) }
        return texture
    }

    static func makeDescriptor(root: URL,provider: Int = 1,consumer: Int = 2,
                               name: String = "Source image") throws -> SceneRenderDescriptor {
        let url = root.appendingPathComponent("scene-\(provider)-\(consumer).json")
        let fixture: [String: Any] = ["version":3,"general":["orthogonalprojection":["width":100,"height":100]],
            "objects":[["id":provider,"name":name,"image":"models/owned-image.json","size":"80 40"],
                       ["id":consumer,"name":"Particle consumer","particle":"particles/owned.json",
                        "dependencies":[["id":provider,"index":0,"type":"emitterimage"]]]]]
        try JSONSerialization.data(withJSONObject: fixture).write(to: url)
        let document = try SceneDocumentLoader().load(from: url)
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: SceneProject(rootURL: root,entryPath: url.lastPathComponent,userProperties: .empty),
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(models: [],materials: [],effectDefinitions: [],
                effectDefinitionDiagnostics: [],shaderReferences: [],textureReferences: []),
            resourceReferences: SceneResourceReferenceIndex(missingReferences: [],
                builtInReferenceCount: 0,runtimeProvidedReferenceCount: 0),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: []))
            else { throw Failure.compile }
        return descriptor
    }
}
''')


class SceneParticleLayerImageEmitterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-layer-image-emitter-")
        directory = Path(cls.temporary.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        frozen_sources = []
        for source in SOURCES:
            frozen = directory / source.name
            shutil.copy2(source,frozen);frozen_sources.append(frozen)
        cls.outputs = {}
        for configuration, flags in (("debug", ["-D", "DEBUG"]), ("release", ["-O"])):
            binary = directory / f"layer-image-{configuration}"
            compiled = subprocess.run(
                ["swiftc", *flags, *(str(path) for path in frozen_sources), str(harness),
                 "-module-cache-path",str(directory/"module-cache"),"-o",str(binary)],
                capture_output=True,text=True,timeout=180)
            if compiled.returncode:
                raise AssertionError(f"{configuration}: {compiled.stderr}")
            completed = subprocess.run([str(binary)],capture_output=True,text=True,timeout=60)
            if completed.returncode:
                raise AssertionError(f"{configuration}: {completed.stderr}")
            if not completed.stdout.strip():
                raise unittest.SkipTest("Metal device is unavailable")
            cls.outputs[configuration] = json.loads(completed.stdout)
        cls.result = cls.outputs["debug"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_release_omits_reports_and_preserves_actual_emission_maps(self) -> None:
        debug = json.loads(json.dumps(self.outputs["debug"]))
        release = self.outputs["release"]
        self.assertTrue(debug.pop("compilationHasDiagnosticStorage"))
        self.assertFalse(release["compilationHasDiagnosticStorage"])
        for value in debug["cases"].values():
            self.assertTrue(value.pop("diagnosticsEmpty"))
        self.assertEqual({key: value for key, value in release.items()
                          if key != "compilationHasDiagnosticStorage"}, debug)

    def test_alpha_pixels_map_to_centered_layer_local_positions(self) -> None:
        self.assertEqual(self.result["positions"], [[-15,5,0],[15,-5,0]])
        self.assertTrue(self.result["transparentRejected"])
        self.assertTrue(self.result["transparentBCRejected"])

    def test_uploaded_bc_uses_actual_emitter_compiler_and_same_seed_weighted_map(self) -> None:
        self.assertEqual(set(self.result["cases"]), {"bc1TransparentSelectors","bc2MixedAlpha",
            "bc3InterpolatedAlpha","bc3ZeroAndFullAlpha"})
        for name, value in self.result["cases"].items():
            with self.subTest(codec=name):
                self.assertTrue(value["nativeSource"])
                self.assertTrue(value["diagnosticsEmpty"])
                self.assertGreater(value["positivePixelCount"],0)
                self.assertEqual(value["positionsCount"],value["positivePixelCount"])
                self.assertEqual(value["references"], {"RGBA":True,"BGRA":True,
                    "RGBAsRGB":True,"BGRAsRGB":True})
                self.assertTrue(value["renamedIdentitySamePositions"])
                self.assertTrue(value["animatedSourceRejected"])

    def test_private_over_pixel_budget_and_unsupported_formats_reject_locally(self) -> None:
        self.assertTrue(self.result["rejections"])
        for name, rejected in self.result["rejections"].items():
            with self.subTest(reason=name):
                self.assertTrue(rejected)


if __name__ == "__main__":
    unittest.main()
