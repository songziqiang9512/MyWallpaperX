import simd

/// Current attachment frames emitted by prepared Puppet pose owners. The
/// parent layer identity stays outside the MDL payload, so aggregation happens
/// only after each playback state has evaluated its own skeleton.
nonisolated struct ScenePuppetAttachmentFrameSnapshot: Sendable {
    static let empty = ScenePuppetAttachmentFrameSnapshot(
        framesByParentLayerID: [:]
    )

    let framesByParentLayerID: [Int: [String: simd_float4x4]]

    nonisolated func frame(
        parentLayerID: Int,
        attachmentName: String
    ) -> simd_float4x4? {
        framesByParentLayerID[parentLayerID]?[attachmentName]
    }
}
