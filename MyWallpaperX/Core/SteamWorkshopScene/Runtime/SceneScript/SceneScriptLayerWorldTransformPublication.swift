import Foundation

nonisolated extension SceneScriptQuickJSDomain {
    func publishLayerWorldTransformsIfNeeded(
        snapshot: SceneDynamicSnapshot,
        descriptor: SceneRenderDescriptor,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot,
        dynamicTransformIDs: Set<Int>,
        diagnostic: inout [CChar]
    ) throws {
        guard let projection = layerWorldTransformProjection,
              projection.catalogSignature == layerCatalogSignature else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer world transform projection is stale"
            )
        }
        guard layerSnapshotGeneration == 0
                || !dynamicTransformIDs.isEmpty
                || !committedDynamicWorldTransformLayerIDs.isEmpty
                || !puppetAttachmentFrames.framesByParentLayerID.isEmpty else {
            return
        }
        try publishLayerWorldTransforms(
            projection.worldFrames(
                for: snapshot,
                puppetAttachmentFrames: puppetAttachmentFrames
            ),
            descriptor: descriptor,
            diagnostic: &diagnostic
        )
    }
}
