import Foundation
import simd

enum SceneLayerPlacementSummary {
    static func make(
        layer: SceneRenderDescriptor.Layer,
        worldFrame: simd_float4x4
    ) -> String {
        let origin = SIMD3<Float>(layer.originXYZ ?? [], fill: 0)
        let size = SIMD2<Float>(layer.renderSizeWH ?? [], fill: 0)
        let scale = SIMD3<Float>(layer.scaleXYZ ?? [], fill: 1)
        let angles = SIMD3<Float>(layer.anglesXYZ ?? [], fill: 0)
        let cropOffset = SIMD2<Float>(layer.modelCropOffsetXY ?? [], fill: 0)
        let worldCenter = worldFrame.columns.3
        let attachment = layer.attachmentName.map {
            " attachment=\($0):\(layer.parentAttachmentBindFrame == nil ? "unavailable" : "bind")"
        } ?? ""
        return String(
            format: "parent=%@ localOrigin=(%.2f, %.2f, %.2f) worldCenter=(%.2f, %.2f, %.2f) size=(%.2f, %.2f) scale=(%.3f, %.3f, %.3f) angles=(%.3f, %.3f, %.3f) cropOffset=(%.2f, %.2f)",
            layer.parentID.map(String.init) ?? "nil",
            origin.x, origin.y, origin.z,
            worldCenter.x, worldCenter.y, worldCenter.z,
            size.x, size.y,
            scale.x, scale.y, scale.z,
            angles.x, angles.y, angles.z,
            cropOffset.x, cropOffset.y
        ) + attachment
    }
}
