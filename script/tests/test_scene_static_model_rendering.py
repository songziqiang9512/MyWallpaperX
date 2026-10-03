#!/usr/bin/env python3

from __future__ import annotations

from script.tests.source_family import read_source_family
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RESOURCES = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift"
PREPARATION = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift"
DESCRIPTOR = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor.swift"
LAYER = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor+Layer.swift"
RENDERER = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer.swift"
VIEW = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalView.swift"
HOST = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost.swift"
TOPOLOGY = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerTopologyProjection.swift"
SOURCE_FACTS = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeSourceFacts.swift"
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
        self.assertIn('receivesLighting: pass.combos["LIGHTING"] != 0', resources)
        self.assertLess(
            resources.index('named: "color"'),
            resources.index('named: "Color"'),
        )
        self.assertLess(
            resources.index('named: "alpha"'),
            resources.index('named: "Alpha"'),
        )
        self.assertIn("pass.constantShaderValues[name]", resources)
        self.assertNotIn("localizedCaseInsensitiveCompare", resources)
        self.assertIn('named: "tintback"', resources)
        self.assertIn("let viewTint: SceneStaticModelViewTint?", resources)
        self.assertIn("textureLoader: baseImages.textureLoader", preparation)
        self.assertIn("let staticModels: ScenePreparedStaticModelResources", preparation)
        self.assertIn("var preparedLayerIDs: [Int]", resources)

    def test_renderer_uses_existing_main_pass_and_surface_route(self) -> None:
        renderer = read_source_family(RENDERER)
        view = VIEW.read_text(encoding="utf-8")
        host = HOST.with_name("SceneDesktopWallpaperSession.swift").read_text(encoding="utf-8")
        topology = TOPOLOGY.read_text(encoding="utf-8")
        model_case = renderer.split('case "model":', 1)[1].split(
            'case "quad":', 1
        )[0]
        self.assertIn("drawStaticModel(layer: layer, state: modelFrame", model_case)
        self.assertIn("worldFrames: frameWorldFrames", model_case)
        self.assertIn("lighting: frameLightSnapshot", model_case)
        model_stage = RENDERER.with_name("SceneMetalRenderer+StaticModels.swift").read_text(encoding="utf-8")
        self.assertIn("pass.encoder(", model_stage)
        self.assertIn("pipeline.draw(", model_stage)
        self.assertIn("emissiveMask: draw.entry.emissiveMask?.texture", model_stage)
        self.assertIn("emissiveMaskTextureFrame: draw.entry.emissiveMask?.uvTransform", model_stage)
        self.assertIn("emissiveMaskSampling: draw.entry.emissiveMask?.sampling", model_stage)
        self.assertIn("entry.material.resolvingDynamicValues(", model_stage)
        self.assertIn(").resolvingDynamicViewTintBack(", model_stage)
        self.assertIn("material: draw.material", model_stage)
        self.assertIn("cameraPosition: cameraFrame.perspectiveEyePosition", model_stage)
        self.assertIn("let frameLightSnapshot = SceneLightSnapshot.make(", renderer)
        self.assertIn("layersByID: frameLayersByID", renderer)
        self.assertIn("worldFramesByLayerID: frameWorldFrames", renderer)
        self.assertIn("dynamicLayerColors: dynamicLightColors", renderer)
        self.assertIn("entryPath: entryPath, camera: camera, lighting: lighting", topology)
        self.assertIn("plan.target(geometryIdentity:", model_stage)
        self.assertIn("case .isolated:", model_stage)
        self.assertIn("worldFrames[layer.id]", model_stage)
        self.assertIn("cameraFrame.resolvesPerspective(", model_stage)
        self.assertIn("usesPerspective: cameraFrame.resolvesPerspective(for: layer)", model_stage)
        self.assertIn("cameraFrame.reverseDepthViewProjection(", model_stage)
        self.assertIn("clearDepth: 0", model_stage)
        self.assertNotIn("makeCommandQueue", model_case + model_stage)
        self.assertNotIn("CAMetalLayer", model_case + model_stage)
        self.assertIn("staticModelResources: staticModelResources", view)
        self.assertIn("prepared static model layers:", view)
        self.assertIn("launchContext.preparedDeviceResources.staticModels", host)

    def test_mdl_material_dependency_is_published_before_vm_projection(self) -> None:
        source_facts = SOURCE_FACTS.read_text(encoding="utf-8")
        reader = MODEL_READER.read_text(encoding="utf-8")
        descriptor = DESCRIPTOR.read_text(encoding="utf-8")
        self.assertIn("directStaticModelMaterialLinks(", source_facts)
        self.assertIn("readMaterialPathsMetadata(data: data)", source_facts)
        self.assertIn("private static func readHeader(", reader)
        self.assertIn("directStaticModelMaterialLinks:", descriptor)
        self.assertIn("+ directStaticModelMaterialLinks", descriptor)


if __name__ == "__main__":
    unittest.main()
