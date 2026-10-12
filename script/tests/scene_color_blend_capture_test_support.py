"""Compile the production projected-quad section without unrelated source admission.

The standalone renderer fixtures supply peripheral scene types. Projection and
pixel bounds remain the exact production declarations, never fixture algorithms.
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJECTION_SOURCE = REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerSourcePassthroughPlan.swift"
UNIFORMS_SOURCE = PROJECTION_SOURCE.with_name("SceneImageLayerCompositor+Uniforms.swift")


def projection_support():
    source = PROJECTION_SOURCE.read_text(encoding="utf-8")
    quad = source[source.index("    struct ProjectedClippedQuad {"):source.index("    let layerID: Int")]
    projection = source[source.index("    static func projectedGeometry("):]
    return "import Metal\nimport simd\nstruct SceneLayerSourcePassthroughPlan {\n" + quad + projection


def completed_source_uniforms_support():
    return UNIFORMS_SOURCE.read_text(encoding="utf-8").split("extension SceneImageLayerCompositor {", 1)[0]
