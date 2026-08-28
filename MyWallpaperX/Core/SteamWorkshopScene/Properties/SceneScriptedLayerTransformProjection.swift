import Foundation

/// Central fail-closed admission for scripted layer scale. Independent bounded
/// producers contribute typed ownership; an unowned script never falls back to
/// the serialized Vec3 as if it were static author intent.
nonisolated enum SceneScriptedLayerTransformProjection {
    nonisolated static func apply(
        admittedSceneScriptScaleLayerIDs: Set<Int>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var result = descriptor
        result.layers = descriptor.layers.map { source in
            var layer = source
            if layer.scaleHasScript == true,
               !admittedSceneScriptScaleLayerIDs.contains(layer.id) {
                layer.visible = false
            }
            return layer
        }
        return result
    }
}
