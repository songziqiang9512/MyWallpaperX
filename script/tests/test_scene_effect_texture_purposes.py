#!/usr/bin/env python3

from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources"
LAYER_LOADER = RESOURCE_ROOT / "SceneLayerEffectTextureLoader.swift"
TEXTURE_LOADING = (
    RESOURCE_ROOT / "SceneLayerEffectTextureLoader+TextureLoading.swift"
)
EFFECT_TEXTURE_LOAD_RESULT = RESOURCE_ROOT / "SceneEffectTextureLoadResult.swift"
XRAY_LOADER = RESOURCE_ROOT / "SceneXRayEffectTextureLoader.swift"
BLEND_LOADER = RESOURCE_ROOT / "SceneBlendEffectTextureLoader.swift"
TEXTURE_CANDIDATE = RESOURCE_ROOT / "SceneTextureCandidate.swift"
SLOT_BINDING = RESOURCE_ROOT / "SceneTextureSlotBinding.swift"
STANDARD_BLUR_LOADER = RESOURCE_ROOT / "SceneStandardBlurEffectTextureLoader.swift"
EFFECT_ROOT = (
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Effects"
)
OFFSCREEN_RENDERER = EFFECT_ROOT / "SceneOffscreenEffectRenderer.swift"
RESOLVED_TEMPLATE_COMPILER = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/RenderGraph/MaterialProgram"
    / "SceneResolvedMaterialTemplateCompiler.swift"
)
METAL_VIEW = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift"
)
LOADER_SOURCES = sorted(RESOURCE_ROOT.glob("*EffectTextureLoader*.swift"))
EXPECTED_PURPOSES = {
    "blend effect texture": "premultipliedColor",
    "pulse noise": "noise",
    "pulse effect mask": "mask",
    "standard blur mask": "mask",
    "xray blend": "straightAlbedo",
    "xray halo": "preservedChannels",
    "xray opacity": "mask",
}
CALL_PATTERN = re.compile(
    r"(?:SceneLayerEffectTextureLoader\.)?loadTexture(?:Candidate)?\("
    r"\s*url:.*?"
    r"\s*label:\s*\"([^\"]+)\".*?"
    r"\s*purpose:\s*\.(\w+),",
    re.DOTALL,
)


class SceneEffectTexturePurposeTests(unittest.TestCase):
    def test_every_effect_auxiliary_declares_its_channel_purpose(self) -> None:
        calls: list[tuple[str, str]] = []
        for path in LOADER_SOURCES:
            calls.extend(CALL_PATTERN.findall(path.read_text(encoding="utf-8")))
        self.assertEqual(len(calls), len(EXPECTED_PURPOSES))
        self.assertEqual(dict(calls), EXPECTED_PURPOSES)

    def test_effect_helper_has_no_default_purpose(self) -> None:
        source = TEXTURE_LOADING.read_text(encoding="utf-8")
        for function in ("loadTexture", "loadTextureCandidate"):
            signature = source.split(f"static func {function}(", maxsplit=1)[1]
            signature = signature.split(") ->", maxsplit=1)[0]
            self.assertIn("purpose: SceneTextureLoadPurpose", signature)
            self.assertNotIn("purpose: SceneTextureLoadPurpose =", signature)

    def test_candidate_admission_is_limited_to_proven_consumers(self) -> None:
        candidate_callers = {
            path.name: path.read_text(encoding="utf-8").count(
                "loadTextureCandidate("
            )
            for path in LOADER_SOURCES
            if path != TEXTURE_LOADING
            if "loadTextureCandidate(" in path.read_text(encoding="utf-8")
        }
        self.assertEqual(
            candidate_callers,
            {
                "SceneBlendEffectTextureLoader.swift": 1,
                "SceneStandardBlurEffectTextureLoader.swift": 1,
            },
        )
        helper = TEXTURE_LOADING.read_text(encoding="utf-8")
        legacy_body = helper.split("static func loadTexture(", maxsplit=1)[1]
        legacy_body = legacy_body.split(
            "static func loadTextureCandidate(", maxsplit=1
        )[0]
        self.assertNotIn("loadCandidate(", legacy_body)

    def test_xray_property_inputs_use_role_typed_texture_maps(self) -> None:
        xray = XRAY_LOADER.read_text(encoding="utf-8")
        view = METAL_VIEW.read_text(encoding="utf-8")
        self.assertEqual(xray.count("straightAlbedoUserPropertyTextures[$0]"), 1)
        self.assertEqual(xray.count("preservedUserPropertyTextures[$0]"), 1)
        self.assertNotIn("userPropertyTextures[$0]", xray)
        self.assertIn(r"\.blendPropertyKey", view)
        self.assertIn(r"\.haloPropertyKey", view)
        self.assertIn(
            "straightAlbedoUserPropertyTextures: userPropertyTextureLoad.straightAlbedoTextures",
            view,
        )
        self.assertIn(
            "preservedUserPropertyTextures: userPropertyTextureLoad.preservedTextures",
            view,
        )

    def test_blend_property_override_uses_explicit_provider_state(self) -> None:
        blend = BLEND_LOADER.read_text(encoding="utf-8")
        view = METAL_VIEW.read_text(encoding="utf-8")
        self.assertIn("userPropertyTextureStates", blend)
        self.assertIn("case .absent", blend)
        self.assertIn("case .pending", blend)
        self.assertIn("case .unavailable", blend)
        self.assertIn("publication.requestIdentity == .materialUserProperty(identity)", blend)
        self.assertNotIn("userPropertyTextureCandidates", blend)
        self.assertIn("renderDescriptor.texturePropertyKeys", view)
        self.assertIn("userPropertyTextureLoad.providerStates", view)

    def test_typed_candidate_and_slot_binding_reach_bounded_consumers(self) -> None:
        candidate = TEXTURE_CANDIDATE.read_text(encoding="utf-8")
        effect_binding = EFFECT_TEXTURE_LOAD_RESULT.read_text(encoding="utf-8")
        slot_binding = SLOT_BINDING.read_text(encoding="utf-8")
        helper = TEXTURE_LOADING.read_text(encoding="utf-8")
        blur_loader = STANDARD_BLUR_LOADER.read_text(encoding="utf-8")
        offscreen = OFFSCREEN_RENDERER.read_text(encoding="utf-8")
        resolved_template = RESOLVED_TEMPLATE_COMPILER.read_text(encoding="utf-8")

        for field in (
            "let texture: MTLTexture",
            "let identity: SceneTextureResourceIdentity",
            "let generation: SceneTextureResourceGeneration",
            "let purpose: SceneTextureLoadPurpose",
            "let content: SceneTextureContent",
            "let physicalSize: CGSize",
            "let mappedSize: CGSize",
            "let uvTransform: SceneTextureUVTransform",
            "let sampling: SceneTextureSampling",
        ):
            self.assertIn(field, candidate)
        for field in (
            "static let authoredSlotRange = 0..<8",
            "let slotIndex: Int",
            "let candidate: SceneTextureCandidate",
            "var physicalMappedResolution: SIMD4<Float>",
            "var physicalTexelSize: SIMD2<Float>",
            "var mappedTexelSize: SIMD2<Float>",
            "!sampling.usesClampBorderFallback",
        ):
            self.assertIn(field, slot_binding)
        self.assertIn("loader.loadCandidate(", helper)
        for field in (
            "let candidate: SceneTextureCandidate?",
            "var texture: MTLTexture? { candidate?.texture }",
            "var generation: SceneTextureResourceGeneration? { candidate?.generation }",
            "var physicalSize: CGSize? { candidate?.physicalSize }",
            "var mappedSize: CGSize? { candidate?.mappedSize }",
        ):
            self.assertIn(field, effect_binding)
        self.assertIn("let maskCandidate: SceneTextureCandidate?", blur_loader)
        self.assertIn("expectedPurpose: .mask", offscreen)
        self.assertIn(
            "guard authored.count == 8",
            resolved_template,
        )
        self.assertIn(
            "guard slot.index == index, !slot.candidates.isEmpty",
            resolved_template,
        )


if __name__ == "__main__":
    unittest.main()
