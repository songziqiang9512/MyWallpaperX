"""Shared Swift dependency-binding stub for resolved-material harnesses."""

from pathlib import Path

from script.tests.scene_framebuffer_source_test_support import _declaration


# Coordinator-derived harnesses retain this before their @main split. Keep it
# separate from Binding: graph fixtures already provide their own aggregate.
SCENE_DEPENDENCY_AGGREGATE_SUPPORT = "extension SceneDependencyRenderPlan {\n" + _declaration(
    (Path(__file__).resolve().parents[2] / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift").read_text(encoding="utf-8"),
    "MultiProviderAggregate", marker="    nonisolated struct MultiProviderAggregate: Hashable {",
) + "\n}\n"


SCENE_DEPENDENCY_BINDING_SUPPORT = r'''
enum SceneImageLayerBlendDependencyContract {
    static func supports(blendMode: Int) -> Bool {
        (0...32).contains(blendMode)
    }
}

extension SceneDependencyRenderPlan {
    struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
            case geometryLayer
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind
        let requiresForwardCapture: Bool
        let requiresResolvedMaterialProgram: Bool

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind,
            requiresForwardCapture: Bool = false,
            requiresResolvedMaterialProgram: Bool = false
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
            self.requiresForwardCapture = requiresForwardCapture
            self.requiresResolvedMaterialProgram =
                requiresResolvedMaterialProgram
        }
    }
}
'''
