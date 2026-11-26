#!/usr/bin/env python3

from __future__ import annotations

from script.tests.support.source_family import read_source_family
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
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

    def test_renderer_uses_existing_main_pass_and_surface_route(self) -> None:
        renderer = read_source_family(RENDERER)
        view = VIEW.read_text(encoding="utf-8")
        surface_preparation = HOST.with_name(
            "SceneDesktopWallpaperSession+SurfacePreparation.swift"
        ).read_text(encoding="utf-8")
        topology = TOPOLOGY.read_text(encoding="utf-8")
        model_case = renderer.split('case "model":', 1)[1].split(
            'case "quad":', 1
        )[0]
        self.assertIn("drawStaticModel(layer: layer, state: modelFrame", model_case)
        self.assertIn("worldFrames: frameWorldFrames", model_case)
        self.assertIn("lighting: frameLightSnapshot", model_case)
        model_stage = RENDERER.with_name("SceneMetalRenderer+StaticModels.swift").read_text(encoding="utf-8")
        self.assertIn("state.sceneDepthEncoder(pass: pass, commandBuffer: commandBuffer)", model_stage)
        self.assertIn("pipeline.draw(", model_stage)
        self.assertIn("materialMap: draw.entry.materialMap", model_stage)
        self.assertIn("entry.material.resolvingDynamicValues(", model_stage)
        self.assertIn(").resolvingDynamicViewTintBack(", model_stage)
        self.assertIn("material: draw.material", model_stage)
        self.assertRegex(
            model_stage,
            r"cameraPosition: draw\.material\.legacyLighting == nil\s*"
            r"\? cameraFrame\.perspectiveEyePosition : cameraFrame\.legacyModelEyePosition,",
        )
        self.assertIn("let frameLightSnapshot = SceneLightSnapshot.make(", renderer)
        self.assertIn("layersByID: frameLayersByID", renderer)
        self.assertIn("worldFramesByLayerID: frameWorldFrames", renderer)
        self.assertIn("dynamicLayerColors: dynamicLightColors", renderer)
        self.assertIn("entryPath: entryPath, camera: camera, lighting: lighting", topology)
        self.assertIn("worldFrames[layer.id]", model_stage)
        self.assertIn("cameraFrame.resolvesPerspective(", model_stage)
        self.assertIn("usesPerspective: cameraFrame.resolvesPerspective(for: layer)", model_stage)
        self.assertIn("camera.reverseDepthViewProjection(", model_stage)
        self.assertIn("clearDepth: 0", model_stage)
        self.assertNotIn("makeCommandQueue", model_case + model_stage)
        self.assertNotIn("CAMetalLayer", model_case + model_stage)
        self.assertIn("staticModelResources: staticModelResources", view)
        self.assertIn("prepared static model layers:", view)
        self.assertIn("launchContext.preparedDeviceResources.staticModels", surface_preparation)

    def test_mdl_material_dependency_is_published_before_vm_projection(self) -> None:
        source_facts = SOURCE_FACTS.read_text(encoding="utf-8")
        reader = MODEL_READER.read_text(encoding="utf-8")
        descriptor = DESCRIPTOR.read_text(encoding="utf-8")
        self.assertIn("directStaticModelMaterialLinks(", source_facts)
        self.assertIn("private static func readHeader(", reader)
        self.assertIn("directStaticModelMaterialLinks:", descriptor)
        self.assertIn("+ directStaticModelMaterialLinks", descriptor)


if __name__ == "__main__":
    unittest.main()
