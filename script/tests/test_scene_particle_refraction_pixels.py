#!/usr/bin/env python3

"""GPU pixels for REFRACT normal storage and single-coverage compositing."""

from __future__ import annotations

import json
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    Path(__file__).parent / "fixtures/SceneTextureSamplingReadback.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
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
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTextureSource.swift",
]

HARNESS_SOURCE = Path(__file__).with_name("fixtures") / "SceneParticleRefractionPixelsHarness.swift"
HARNESS = HARNESS_SOURCE.read_text(encoding="utf-8")



class SceneParticleRefractionPixelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._temporary_directory = tempfile.TemporaryDirectory()
        temporary = Path(cls._temporary_directory.name)
        identity = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in [Path(__file__), HARNESS_SOURCE, *SWIFT_SOURCES]}
        harness = temporary / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = temporary / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(
                f"harness compilation failed:\n{compilation.stderr}"
            )
        completed = subprocess.run(
            [str(binary)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)
        assert identity == {str(Path(p)): hashlib.sha256(Path(p).read_bytes()).hexdigest()
                            for p in identity}, "source identity drift"
        if evidence := os.environ.get("MWX_REFRACTION_PIXEL_EVIDENCE"):
            parent = Path(evidence); parent.mkdir(parents=True, exist_ok=True)
            (parent / "result.json").write_text(json.dumps(cls.result, indent=2))
            (parent / "source-identity.json").write_text(json.dumps(identity, indent=2))

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def require_metal(self) -> None:
        if not self.result["available"]:
            self.skipTest("Metal is unavailable")

    def test_normal_storage_preserves_channels_and_source_format_decoding(self) -> None:
        self.require_metal()
        self.assertEqual(self.result["decodedDXT5n"], [255, 130, 0, 64])
        self.assertEqual(self.result["loadedDXT5nNormal"], [255, 130, 0, 64])
        pixels = self.result["normalPixels"]
        self.assertLessEqual(max(abs(a - b) for a, b in zip(
            pixels["dxt5n"], pixels["dxt5nDirect"])), 2)
        self.assertGreater(
            max(abs(left - right) for left, right in zip(
                pixels["rgba"], pixels["swapped"]
            )),
            8,
        )
        self.assertGreater(
            max(abs(left - right) for left, right in zip(
                pixels["rgba"], pixels["neutral"]
            )),
            8,
        )
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["padded"], pixels["neutral"]
            )),
            2,
        )
        self.assertLessEqual(
            max(abs(left - right) for left, right in zip(
                pixels["flatDefault"], pixels["neutral"]
            )),
            2,
        )

    def test_static_normal_candidate_is_atomic_and_legacy_routes_stay_closed(
        self,
    ) -> None:
        self.require_metal()
        routes = self.result["normalRoutes"]
        self.assertTrue(routes["dxt5nStaticCandidate"], routes)
        self.assertTrue(routes["rgbaStaticCandidate"], routes)
        self.assertTrue(routes["paddedStaticCandidate"], routes)
        self.assertEqual(routes["paddedUVScale"], [0.5, 1])
        self.assertTrue(routes["multiImageLegacy"], routes)
        self.assertEqual(routes["sameFilePixels"], routes["separateFilePixels"])
        self.assertTrue(any(routes["sameFilePixels"][:3]))
        self.assertTrue(routes["sixteenColorAccepted"], routes)
        self.assertTrue(routes["sixteenNormalRejected"], routes)
        self.assertTrue(routes["singleImageBC3KeepsNativeStorage"], routes)
        self.assertTrue(routes["directBC3IsNative"], routes)
        self.assertEqual(routes["decodedBC3Format"], 4)
        self.assertEqual(routes["nativeBC3Format"], 4)
        self.assertEqual(routes["sameFileBC3Format"], 4)
        self.assertEqual(routes["rgbaFormat"], 0)
        self.assertTrue(routes["absentFormat"])
        self.assertTrue(routes["unknownFormatRejected"])
        self.assertTrue(routes["unsupportedFormatRejected"])
        self.assertTrue(routes["mismatchedFormatRejected"])
        self.assertTrue(routes["oversizedSameSourceRejected"], routes)
        self.assertTrue(routes["clampBorderLegacy"], routes)
        self.assertTrue(routes["invalidMappedRejected"], routes)
        self.assertTrue(routes["wrongPurposeRejected"], routes)
        self.assertTrue(routes["clampBorderCandidateRejected"], routes)
        self.assertTrue(routes["wrongUsageRejected"], routes)
        self.assertTrue(routes["wrongTypeRejected"], routes)

    def test_bc3_bias_uses_authored_format_with_same_rgba_channel_values(self) -> None:
        self.require_metal()
        values = self.result["sourceFormatPixels"]
        # With A=64/255, RGBA X=2*A-1 while BC3 X=2*A-.965.
        # The 32px background changes by 5 blue units/pixel, amount=.75.
        for key, bias in [("rgba", 1), ("singleImageBC3", .965), ("nativeBC3", .965)]:
            expected_blue = 100 + (2 * 64 / 255 - bias) * .75 * 32 * 5
            self.assertAlmostEqual(values[key][0], expected_blue, delta=1)
        self.assertGreater(values["singleImageBC3"][0], values["rgba"][0] + 2)
        self.assertAlmostEqual(values["singleImageBC3"][1], values["rgba"][1], delta=1)

    def test_absent_normal_has_exact_zero_displacement_for_any_amount(self) -> None:
        self.require_metal()
        self.assertEqual(len(self.result["absentPixels"]), 6)
        for name, pixels in self.result["absentPixels"].items():
            with self.subTest(name=name):
                self.assertEqual(pixels[0], pixels[1])
                self.assertEqual(pixels[2], pixels[1])
                self.assertGreater(pixels[1][3], 0)
        self.assertEqual(self.result["absentStrong"], [100,78,40,255])
        self.assertNotEqual(self.result["explicitNeutral"], self.result["absentStrong"])

    def test_refraction_composite_coverage_is_applied_once(self) -> None:
        self.require_metal()
        self.assertEqual(
            self.result["coveragePixels"]["albedo"],
            [255, 255, 255, 128],
        )
        expected = [50, 25, 13, 64]
        double_applied = [13, 6, 3, 64]
        for mode in ("translucent", "additive"):
            pixel = self.result["coveragePixels"][mode]
            expected_error = sum(abs(left - right) for left, right in zip(
                pixel, expected
            ))
            double_error = sum(abs(left - right) for left, right in zip(
                pixel, double_applied
            ))
            self.assertLessEqual(max(abs(left - right) for left, right in zip(
                pixel, expected
            )), 2)
            self.assertLess(expected_error, double_error)


# The loader double changes source identity exactly between metadata and upload.
# Only I/O is doubled; the production refraction preparation and binding execute.
IDENTITY_HARNESS = r'''
import Foundation
import Metal
import simd

typealias SceneParticleTextureSampling = SceneTextureSampling
enum SceneTextureLoadPurpose { case normal, straightAlbedo }
enum SceneParticleTextureSource { case file(URL), builtIn(String) }
struct SceneParticleRefractionDeclaration {
    let normalTextureSource: SceneParticleTextureSource?
    let amount: Float = 1
    let overbright: Float = 1
}
struct SceneTexContainer {
    struct SpriteFrame {
        let imageIndex: Int; let duration: Float
        let origin: SIMD2<Float>; let xAxis: SIMD2<Float>; let yAxis: SIMD2<Float>
    }
    struct Mip { let width = 4; let height = 4 }
    let format: UInt32
    let flags: UInt32
    let imageCount = 1; let isAnimated = false
    let spriteFrames: [SpriteFrame] = []; let mips = [Mip()]
    let imageWidth = 4; let imageHeight = 4; let textureWidth = 4; let textureHeight = 4
}
struct SceneSpriteAnimation { init(container: SceneTexContainer, sourceURL: URL) {} }
struct SceneTextureCandidate {
    let texture: MTLTexture
    let authoredFormat: SceneShaderTextureFormat?
    let sampling = SceneTextureSampling.linearClamp
    var pixelFormat: MTLPixelFormat { texture.pixelFormat }
    func axisAlignedMappedUVScale(expectedPurpose: SceneTextureLoadPurpose) -> SIMD2<Float>? { SIMD2(1,1) }
}
final class SceneTextureLoader {
    struct SourceKey: Equatable { let revision: Int }
    enum Outcome { case loaded(MTLTexture) }
    enum CandidateOutcome { case loaded(SceneTextureCandidate) }
    let texture: MTLTexture
    let mode: String
    var revision: [String: Int] = [:]
    var changed = false
    init(device: MTLDevice, mode: String) {
        self.mode = mode
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 4, height: 4, mipmapped: false)
        d.usage = .shaderRead
        texture = device.makeTexture(descriptor: d)!
    }
    func sourceKey(for url: URL) -> SourceKey? { .init(revision: revision[url.path, default: 0]) }
    func texContainer(from url: URL) -> SceneTexContainer? {
        .init(format: revision[url.path, default: 0] == 0 ? 0 : 4,
              flags: mode == "normal-base" ? 8 : 0)
    }
    func changeIfNeeded(_ url: URL, candidate: Bool) {
        guard !changed else { return }
        let change = (mode == "color" || mode == "same-file") && url.lastPathComponent == "color.tex"
            || mode == "normal-base" && url.lastPathComponent == "normal.tex"
            || mode == "normal-candidate" && candidate
        if change { revision[url.path, default: 0] += 1; changed = true }
    }
    func load(from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice) -> Outcome {
        changeIfNeeded(url, candidate: false); return .loaded(texture)
    }
    func loadCandidate(from url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice) -> CandidateOutcome {
        changeIfNeeded(url, candidate: true)
        return .loaded(.init(texture: texture,
            authoredFormat: revision[url.path, default: 0] == 0 ? .rgba8888 : .dxt5))
    }
}
@main enum Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        let color = URL(fileURLWithPath: "/fixture/color.tex")
        let normal = URL(fileURLWithPath: "/fixture/normal.tex")
        var result: [String: [Bool]] = [:]
        for mode in ["stable", "color", "same-file", "normal-base", "normal-candidate"] {
            let loader = SceneTextureLoader(device: device, mode: mode)
            let declaration = SceneParticleRefractionDeclaration(
                normalTextureSource: mode == "color" ? nil : .file(mode == "same-file" ? color : normal))
            func prepare() -> Bool {
                SceneParticleRefractionTextureLoader.load(colorSource: .file(color),
                    declaration: declaration, textureLoader: loader, device: device) != nil
            }
            result[mode] = [prepare(), prepare()]
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
        print(String(decoding: data, as: UTF8.self))
    }
}
'''

class SceneParticleRefractionIdentityTests(unittest.TestCase):
    def test_metadata_upload_identity_drift_is_rejected_and_retry_recovers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-refraction-identity-") as directory:
            root = Path(directory)
            harness = root / "harness.swift"
            harness.write_text(IDENTITY_HARNESS)
            binary = root / "harness"
            sources = [
                SCENE_ROOT / "Resources/Textures/SceneTextureSampling.swift",
                SCENE_ROOT / "Systems/Particles/SceneParticleRefractionBinding.swift",
                SCENE_ROOT / "Systems/Particles/SceneParticleRefractionTextureLoader.swift",
            ]
            result = subprocess.run(["swiftc", *map(str, sources), str(harness), "-o", str(binary)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            values = json.loads(result.stdout)
            self.assertEqual(values["stable"], [True, True])
            for key in ["color", "same-file", "normal-base", "normal-candidate"]:
                self.assertEqual(values[key], [False, True], key)


if __name__ == "__main__":
    unittest.main()
