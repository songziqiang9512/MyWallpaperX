"""Production dependency value declarations for isolated material harnesses."""

from pathlib import Path

from script.tests.support.scene_framebuffer_source_test_support import _declaration


_MODEL_SOURCE = (Path(__file__).resolve().parents[3] /
    "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan.swift").read_text(encoding="utf-8")

SCENE_DEPENDENCY_AGGREGATE_SUPPORT = "extension SceneDependencyRenderPlan {\n" + _declaration(
    _MODEL_SOURCE, "MultiProviderAggregate",
    marker="    nonisolated struct MultiProviderAggregate: Hashable {",
) + "\n}\n"

SCENE_DEPENDENCY_BINDING_SUPPORT = r'''
enum SceneImageLayerBlendDependencyContract {
    static func supports(blendMode: Int) -> Bool {
        (0...32).contains(blendMode)
    }
}
''' + "extension SceneDependencyRenderPlan {\n" + _declaration(
    _MODEL_SOURCE, "Binding", marker="    nonisolated struct Binding: Hashable {",
) + "\n}\n"
