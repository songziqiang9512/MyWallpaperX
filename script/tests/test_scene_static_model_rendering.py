#!/usr/bin/env python3

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RESOURCES = SCENE_ROOT / "Resources/ScenePreparedStaticModelResources.swift"
PREPARATION = SCENE_ROOT / "Runtime/ScenePreparedDeviceResources.swift"
DESCRIPTOR = SCENE_ROOT / "Runtime/SceneRenderDescriptor.swift"
LAYER = SCENE_ROOT / "Runtime/SceneRenderDescriptor+Layer.swift"
RENDERER = SCENE_ROOT / "Rendering/SceneMetalRenderer.swift"
VIEW = SCENE_ROOT / "Rendering/SceneMetalView.swift"
HOST = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
TOPOLOGY = SCENE_ROOT / "Runtime/SceneScript/SceneScriptLayerTopologyProjection.swift"
SOURCE_FACTS = SCENE_ROOT / "Runtime/SceneRuntimeSourceFacts.swift"
MODEL_READER = SCENE_ROOT / "Format/SceneMdlStaticModelReader.swift"


class SceneStaticModelRenderingTests(unittest.TestCase):
    def test_descriptor_preserves_direct_model_as_authored_order_layer(self) -> None:
        descriptor = DESCRIPTOR.read_text(encoding="utf-8")
        layer = LAYER.read_text(encoding="utf-8")
        self.assertIn("staticModelPath: object.staticModelPath", descriptor)
        self.assertIn("usesPerspective: object.usesPerspective", descriptor)
        self.assertIn('return "model"', descriptor)
        self.assertIn("let renderOrderLayerIDs", descriptor)
        self.assertIn("var staticModelPath: String? = nil", layer)
        self.assertNotIn('contentKind == "model"', layer.split(
            "nonisolated var isImageRenderable", 1
        )[1].split("}", 1)[0])

    def test_preparation_reuses_typed_texture_and_device_resource_owners(self) -> None:
        resources = RESOURCES.read_text(encoding="utf-8")
        preparation = PREPARATION.read_text(encoding="utf-8")
        self.assertIn("let albedo: SceneTextureCandidate", resources)
        self.assertIn("let emissiveMask: SceneTextureCandidate?", resources)
        self.assertIn("let material: SceneStaticModelMaterial", resources)
        self.assertIn("let geometryIdentity: String", resources)
        self.assertIn("pass.textureSlots.first.flatMap", resources)
        self.assertNotIn("pass.texturePaths.first", resources)
        self.assertIn("textureLoader.loadCandidate(", resources)
        self.assertIn("purpose: .straightAlbedo", resources)
        self.assertIn("purpose: .mask", resources)
        self.assertIn(
            "candidate.sampling.isResolvedForMaterialProgram", resources
        )
        self.assertIn(
            "!candidate.sampling.usesClampBorderFallback", resources
        )
        self.assertIn('named: "emissivebrightness"', resources)
        self.assertIn('named: "emissivecolor"', resources)
        self.assertIn(")?.first ?? 0", resources)
        self.assertIn('pass.combos["TINTMASKALPHA"] != 1', resources)
        self.assertIn('pass.combos["TINTMASKALPHA"] == 1', resources)
        self.assertIn('named: "tintback"', resources)
        self.assertIn("let viewTint: SceneStaticModelViewTint?", resources)
        self.assertIn("textureLoader: baseImages.textureLoader", preparation)
        self.assertIn("let staticModels: ScenePreparedStaticModelResources", preparation)
        self.assertIn("var preparedLayerIDs: [Int]", resources)

    def test_renderer_uses_existing_main_pass_and_surface_route(self) -> None:
        renderer = RENDERER.read_text(encoding="utf-8")
        view = VIEW.read_text(encoding="utf-8")
        host = HOST.read_text(encoding="utf-8")
        topology = TOPOLOGY.read_text(encoding="utf-8")
        model_case = renderer.split('case "model":', 1)[1].split(
            'case "quad":', 1
        )[0]
        self.assertIn("mainPass.encoder(", model_case)
        self.assertIn("pipeline.draw(", model_case)
        self.assertIn("emissiveMask: prepared.emissiveMask?.texture", model_case)
        self.assertIn("emissiveMaskTextureFrame: prepared.emissiveMask?.uvTransform", model_case)
        self.assertIn("emissiveMaskSampling: prepared.emissiveMask?.sampling", model_case)
        self.assertIn("prepared.material.resolvingDynamicViewTintBack(", model_case)
        self.assertIn("material: material", model_case)
        self.assertIn("cameraPosition: cameraFrame.perspectiveEyePosition", model_case)
        self.assertIn("lighting: frameLightSnapshot", model_case)
        self.assertIn("let frameLightSnapshot = SceneLightSnapshot.make(", renderer)
        self.assertIn("worldFramesByLayerID: frameWorldFrames", renderer)
        self.assertIn("dynamicLayerColors: dynamicLightColors", renderer)
        self.assertIn("entryPath: entryPath, camera: camera, lighting: lighting", topology)
        self.assertIn("staticModelDepthPlan.target(", model_case)
        self.assertIn("case .isolated:", model_case)
        self.assertIn("frameWorldFrames[layer.id]", model_case)
        self.assertIn("cameraFrame.resolvesPerspective(", model_case)
        self.assertIn("layerOverride: layer.usesPerspective", model_case)
        self.assertIn("cameraFrame.reverseDepthViewProjection(", model_case)
        self.assertIn("clearDepth: 0", model_case)
        self.assertNotIn("makeCommandQueue", model_case)
        self.assertNotIn("CAMetalLayer", model_case)
        self.assertIn("staticModelResources: staticModelResources", view)
        self.assertIn("prepared static model layers:", view)
        self.assertIn("launchContext.preparedDeviceResources.staticModels", host)

    def test_mdl_material_dependency_is_published_before_vm_projection(self) -> None:
        source_facts = SOURCE_FACTS.read_text(encoding="utf-8")
        reader = MODEL_READER.read_text(encoding="utf-8")
        descriptor = DESCRIPTOR.read_text(encoding="utf-8")
        self.assertIn("directStaticModelMaterialLinks(", source_facts)
        self.assertIn("readMaterialPathMetadata(data: data)", source_facts)
        self.assertIn("private static func readHeader(", reader)
        self.assertIn("directStaticModelMaterialLinks:", descriptor)
        self.assertIn("+ directStaticModelMaterialLinks", descriptor)


if __name__ == "__main__":
    unittest.main()
