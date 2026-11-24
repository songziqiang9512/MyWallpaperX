"""Production projected-quad and main color blend test support.

The standalone renderer fixtures supply peripheral scene types. Projection and
pixel bounds remain the exact production declarations, never fixture algorithms.
"""
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PROJECTION_SOURCE = REPO / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLayerSourcePassthroughPlan.swift"
UNIFORMS_SOURCE = PROJECTION_SOURCE.with_name("SceneImageLayerCompositor+Uniforms.swift")


def projection_support():
    source = PROJECTION_SOURCE.read_text(encoding="utf-8")
    quad = source[source.index("    struct ProjectedClippedQuad {"):source.index("    let layerID: Int")]
    projection = source[source.index("    static func projectedGeometry("):]
    return "import Metal\nimport simd\nstruct SceneLayerSourcePassthroughPlan {\n" + quad + projection


def completed_source_uniforms_support():
    return UNIFORMS_SOURCE.read_text(encoding="utf-8").split("extension SceneImageLayerCompositor {", 1)[0]


def assert_main_background_reader(test, rows, layer_id, main_target):
    blend, = (r for r in rows if r["kind"] == "color-blend-background"
              and r.get("layerID") == layer_id and r["outcome"] == "draw-encoded")
    copies = [r for r in rows if r["kind"] == "background-copy"
              and r.get("layerID") == layer_id and r["outcome"] == "encoded"]
    test.assertEqual(blend["target"]["textureToken"], main_target["textureToken"])
    if blend["access"] == "color-attachment-read":
        test.assertFalse(copies)
        test.assertEqual(blend["source"]["textureToken"], main_target["textureToken"])
        return (blend,)
    test.assertEqual(blend["access"], "texture-bind")
    copy, = copies
    test.assertEqual(copy["source"]["textureToken"], main_target["textureToken"])
    test.assertEqual(copy["target"]["textureToken"], blend["source"]["textureToken"])
    test.assertNotEqual(blend["source"]["textureToken"], main_target["textureToken"])
    test.assertLess(rows.index(copy), rows.index(blend))
    return copy, blend
