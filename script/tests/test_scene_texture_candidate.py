#!/usr/bin/env python3

"""Typed texture candidate metadata, generation, and fail-closed UV gates."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.scene_source_color_fixture import HARNESS_EXTENSION, assert_source_color_upload
from script.scene_swift_source_sets import scene_swift_sources


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
IMAGE_LAYER_METAL_SOURCE = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayer.metal"
FOG_HEADER = IMAGE_LAYER_METAL_SOURCE.with_name("SceneDistanceFog.metalh")
SWIFT_SOURCES = [
    *scene_swift_sources("scene_resource_input"),
    Path(__file__).parent / "fixtures/SceneTextureSamplingReadback.swift",
    Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSlotBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneFrameTextureRegistry.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureProviderPublication.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLoader+Candidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneMultiImageSpriteResidentBudget.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneMultiImageSpritePlayback.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    SCENE_ROOT / "Runtime/Frame/SceneMaterialRenderState.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Metal/SceneMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneImageLayerCompositor+Uniforms.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Animation/SceneSpriteAnimation.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureCandidateSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneGeometryProduct.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneBaseImageTextureLoad+Ordinary.swift",
]


FIXTURE_ROOT = Path(__file__).with_name("fixtures")
HARNESS_SUPPORT_SOURCE = (FIXTURE_ROOT / "SceneTextureCandidateTransport.swift").read_text(encoding="utf-8")
HARNESS = HARNESS_SUPPORT_SOURCE + "".join(
    (FIXTURE_ROOT / name).read_text(encoding="utf-8")
    for name in (
        "SceneTextureCandidateHarness.swift",
        "SceneTextureCandidateSupport.swift",
        "SceneTextureCandidateMetadataCases.swift",
        "SceneTextureCandidateUploadCases.swift",
        "SceneTextureCandidateBaseAndSpriteCases.swift",
    )
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneTextureCandidateTests(unittest.TestCase):
    def test_candidate_keeps_texture_and_slot_metadata_atomic(self) -> None:
        self.maxDiff = None
        with tempfile.TemporaryDirectory(prefix="mwx-texture-candidate-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "texture-candidate-test"
            harness.write_text(HARNESS + HARNESS_EXTENSION, encoding="utf-8")
            # Parallel renderer work may update shared source files during
            # swiftc. Compile and execute one frozen set of input bytes.
            frozen_sources = []
            for source in SWIFT_SOURCES:
                frozen = root / source.name
                shutil.copy2(source, frozen)
                frozen_sources.append(frozen)
            frozen_metal = root / IMAGE_LAYER_METAL_SOURCE.name
            shutil.copy2(IMAGE_LAYER_METAL_SOURCE, frozen_metal)
            frozen_header = root / FOG_HEADER.name
            shutil.copy2(FOG_HEADER, frozen_header)
            frozen_metal.write_text(frozen_metal.read_text().replace(
                '#include "SceneDistanceFog.metalh"', frozen_header.read_text()), encoding="utf-8")
            identity_paths = [*frozen_sources, frozen_metal, frozen_header, harness]
            identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths}
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in frozen_sources),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "MetalPerformanceShaders",
                    "-framework",
                    "ImageIO",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(frozen_metal)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(identity, {
                str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in identity_paths
            }, "frozen candidate GPU inputs changed during gate")
        result = json.loads(completed.stdout)
        self.assertTrue(result.pop("overflowingRawRejected"))
        if not result["available"]:
            self.skipTest("Metal is unavailable")
        assert_source_color_upload(self, result.pop("sourceContinuity"))
        self.assertEqual(
            result,
            {
                "available": True,
                "baseBudgetLimitedCrossImageSpriteFailsClosed": True,
                "baseCandidateFailureTerminal": True,
                "baseCrossImageFrame0Pixel": [128, 0, 0, 128],
                "baseCrossImageFrame1Pixel": [0, 64, 0, 64],
                "baseCrossImageSpritePlayback": True,
                "baseCroppedCandidate": True,
                "baseDirectCandidate": True,
                "baseDirectGeneratesMipChain": True,
                "baseNearestRepeatCandidate": True,
                "basePaddedR8Specialized": True,
                "basePuppetCandidate": True,
                "baseRotatedCrossImageSpriteFailsClosed": True,
                "baseSpritePlayback": True,
                "baseSnapshotDropsMismatchedCandidate": True,
                "baseSnapshotRejectsMismatchedPublication": True,
                "baseStoreReplacementClearsCandidate": True,
                "staticCandidatePublicationPreservesRevision": True,
                "baseUnparsedRejected": True,
                "boundaryPixelsMatch": True,
                "croppedColorMapped": [4, 4],
                "croppedColorPhysical": [4, 4],
                "croppedColorScale": [1, 1],
                "decodedMismatchTexb3Rejected": True,
                "diagnosticCarriesContract": True,
                "emptySpriteRejected": True,
                "firstMapped": [4, 4],
                "firstPhysical": [8, 4],
                "firstPixelFormat": 10,
                "firstAuthoredFormat": 9,
                "firstSampling": ["nearest", "clampToEdge"],
                "firstScale": [0.5, 1],
                "generationChangedAfterRewrite": True,
                "generationChangedWithRestoredSizeAndMTime": True,
                "generationChangedAfterAtomicReplace": True,
                "generationIsFile": True,
                "identityIsCanonicalFile": True,
                "imageShaderUsesAuthoredNearestFilter": True,
                "imageShaderUsesAuthoredRepeatSampler": True,
                "layerSamplerOverrideClampNearest": True,
                "layerSamplerOverrideRepeatLinear": True,
                "layerSamplerOmissionPreservesSource": True,
                "inPlaceStableMetadata": True,
                "inPlaceStatusChangeDetected": True,
                "invalidMappedRejected": True,
                "invalidPhysicalRejected": True,
                "mismatchedPhysicalRejected": True,
                "missingSourceCandidateRejected": True,
                "missingSourceKeyUnavailable": True,
                "mappedEmbeddedColorIdentity": True,
                "mappedEmbeddedNormalRejected": True,
                "mappedNearestCandidateSample": True,
                "freeFormatMismatchTexb3Rejected": True,
                "lowerMipMismatchTexb3Rejected": True,
                "malformedTexb3EmbeddedRejected": True,
                "mappedTexb2MipRejected": True,
                "mappedTexb3EmbeddedColorIdentity": True,
                "mappedTexb3EmbeddedColorPreservesMipChain": True,
                "oversizedTexb3MipChainPreservesAuthoredBase": True,
                "mappedTexb3EmbeddedNormalIdentity": True,
                "mappedTexb3JPEGIdentity": True,
                "mappedTexb3JPEGOpaque": True,
                "mappedTexb3PNGPreservesAlphaContract": True,
                "normalizedStraightAlbedoJPEGIdentity": True,
                "normalizedStraightAlbedoPNGIdentity": True,
                "paddedStraightAlbedoJPEGRejected": True,
                "mislabeledTexb4StraightAlbedoPNGRejected": True,
                "authoredStraightAlbedoMipsPNG": True,
                "authoredStraightAlbedoMipsPixel": [127, 127, 127, 127],
                "normalizedColorMapped": [4096, 1],
                "normalizedColorPhysical": [4096, 1],
                "normalizedColorPreservesCompiledBaseLevel": True,
                "normalizedColorScale": [1, 1],
                "oversizedMappedRejected": True,
                "purposeCacheSeparated": True,
                "refreshedGenerationMatchesFileSize": True,
                "refreshedPhysical": [8, 8],
                "rotatedRejected": True,
                "sameCandidateGeneration": True,
                "sameCandidateTexture": True,
                "sameGenerationAcrossPurpose": True,
                "sameResourceIdentityAcrossPurpose": True,
                "spriteRejected": True,
                "slotBindingClampBorderRejected": True,
                "slotBindingIdentityRequirementRejected": True,
                "slotBindingInvalidCandidateRejected": True,
                "slotBindingMetadataAtomic": True,
                "slotBindingOverflowingTransformRejected": True,
                "slotBindingOversizedPhysicalRejected": True,
                "slotBindingPreservesRotatedUV": True,
                "slotBindingRangeAccepted": True,
                "slotBindingRangeRejected": True,
                "slotBindingScale": [0.5, 1],
                "slotBindingWrongFormatRejected": True,
                "slotBindingWrongPurposeRejected": True,
                "slotBindingWrongSlotRejected": True,
                "sourceFragmentUniformCarriesCandidateAtom": True,
                "sourceFragmentUniformCarriesAuthoredStyle": True,
                "textureChangedAfterRewrite": True,
                "textureChangedAfterAtomicReplace": True,
                "textureChangedWithRestoredSizeAndMTime": True,
                "transparentStraightAlbedoPNG": True,
                "transparentStraightAlbedoPixel": [127, 127, 127, 127],
                "directTransparentPNG": True,
                "directTransparentPixel": [127, 127, 127, 127],
                "normalizedLegacyStraight": True,
                "paddedStraightMips": True,
                "legacyMappedStraight": True,
                # 直通 alpha 降采样走预乘域面积加权盒式滤波再还原：RGB 按
                # 覆盖面积×携带 alpha 的能量加权，零累计 alpha 窗口保留首源
                # 像素 authored RGB（zeroAlpha 键）。
                "straightResize": {
                    "stridedFirst": [255,0,0,0, 0,0,255,255, 0,255,0,128, 255,255,255,64],
                    "stridedResize": [37,110,182,112],
                    "truncatedRejected": True,
                    "decodeRejected": True,
                    "bitmapRejected": True,
                    "gray8": [64,64,64,128] * 2,
                    "gray16": [64,64,64,128] * 2,
                    "rgba16Big": [0,0,171,64] * 2,
                    "rgba16Little": [0,0,171,64] * 2,
                    "horizontal": [0, 0, 255, 128],
                    "vertical": [0, 0, 255, 128],
                    "nonInteger": [0, 0, 255, 85, 0, 0, 255, 85],
                    "zeroAlpha": [17, 91, 203, 0],
                    "premultipliedRejected": True,
                    "dataResizeRejected": True,
                    "largeSourcePreserved": True,
                    "directPNG": [0, 0, 255, 128],
                },
                "atomicReplaceMetadataPreconditions": True,
                "clampBorderBaseSampleRejected": True,
                "clampBorderBaseLoadRejected": True,
                "translatedRejected": True,
                "unparsedFallbackRejected": True,
                "unknownFlagsBaseSampleRejected": True,
                "unknownSamplerBaseLoadRejected": True,
                "zeroAlphaPixel": [0, 0, 0, 255],
                "samplerFailureDoesNotPoisonSiblingLoad": True,
                "wrongPurposeRejected": True,
                "wrongOutputRejected": True,
                "zeroMappedRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
