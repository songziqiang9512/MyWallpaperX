import Foundation

nonisolated struct SceneScriptLayerMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case upsert, destroy }

    struct Fields: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let origin = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN.rawValue
        ))
        static let scale = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE.rawValue
        ))
        static let angles = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES.rawValue
        ))
        static let visibility = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY.rawValue
        ))
        static let solid = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SOLID.rawValue))
        static let text = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT.rawValue
        ))
        static let font = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT.rawValue
        ))
        static let effectVisibility = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_EFFECT_VISIBILITY.rawValue))

        static let particleAlpha = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_PARTICLE_ALPHA.rawValue))

        static let authoredFields: Self = [
            .origin, .scale, .angles, .visibility, .solid, .text, .font, .alpha, .color, .effectVisibility, .particleAlpha,
        ]
        static let alpha = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA.rawValue))
        static let color = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR.rawValue))
    }

    let kind: Kind
    let isDynamic: Bool
    let fields: Fields
    let layerID: Int
    let orderIndex: Int
    let visible: Bool
    let solid: Bool
    let alpha: Double
    let particleAlpha: Double
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let angles: SIMD3<Double>
    let color: SIMD3<Double>
    let pointSize: Double
    let text: String
    let font: String
    let assetPath: String?
    let ownerTarget: SceneDynamicTarget?
    let effectVisibilities: [Int: Bool]

    init(
        kind: Kind,
        isDynamic: Bool,
        fields: Fields,
        layerID: Int,
        orderIndex: Int,
        visible: Bool,
        alpha: Double,
        origin: SIMD3<Double>,
        scale: SIMD3<Double>,
        angles: SIMD3<Double>,
        color: SIMD3<Double>,
        pointSize: Double,
        text: String,
        font: String,
        assetPath: String?,
        ownerTarget: SceneDynamicTarget? = nil,
        effectVisibilities: [Int: Bool] = [:],
        solid: Bool = true,
        particleAlpha: Double = 1
    ) {
        self.kind = kind
        self.isDynamic = isDynamic
        self.fields = fields
        self.layerID = layerID
        self.orderIndex = orderIndex
        self.solid = solid
        self.visible = visible
        self.alpha = alpha
        self.particleAlpha = particleAlpha
        self.origin = origin
        self.scale = scale
        self.angles = angles
        self.color = color
        self.pointSize = pointSize
        self.text = text
        self.font = font
        self.assetPath = assetPath
        self.ownerTarget = ownerTarget
        self.effectVisibilities = effectVisibilities
    }

    func owned(by target: SceneDynamicTarget) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: fields,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: assetPath, ownerTarget: target, effectVisibilities: effectVisibilities, solid: solid, particleAlpha: particleAlpha
        )
    }

    func resolvingAssetPath(to resolved: String) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: fields,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: resolved, ownerTarget: ownerTarget, effectVisibilities: effectVisibilities, solid: solid, particleAlpha: particleAlpha
        )
    }

    func selectingAuthoredFields(_ selected: Fields) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: selected,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: assetPath, ownerTarget: ownerTarget,
            effectVisibilities: selected.contains(.effectVisibility) ? effectVisibilities : [:], solid: solid, particleAlpha: particleAlpha
        )
    }

    /// Coalesces repeated writes emitted by init/events/update for one owner.
    /// Dynamic upserts carry a complete current record, while authored writes
    /// retain untouched fields from the earlier mutation.
    static func coalescing(_ mutations: [Self]) -> [Self] {
        var indices: [Int: Int] = [:]
        var output: [Self] = []
        output.reserveCapacity(mutations.count)
        for mutation in mutations {
            if let index = indices[mutation.layerID] {
                output[index] = output[index].merging(with: mutation)
            } else {
                indices[mutation.layerID] = output.count
                output.append(mutation)
            }
        }
        return output
    }

    func merging(with newer: Self) -> Self {
        guard kind != .destroy, kind == .upsert, newer.kind == .upsert,
              !isDynamic, !newer.isDynamic else {
            return kind == .destroy ? self : newer
        }
        let mergedFields = fields.union(newer.fields)
        return .init(
            kind: .upsert,
            isDynamic: false,
            fields: mergedFields,
            layerID: newer.layerID,
            orderIndex: newer.orderIndex,
            visible: newer.fields.contains(.visibility) ? newer.visible : visible,
            alpha: newer.fields.contains(.alpha) ? newer.alpha : alpha,
            origin: newer.fields.contains(.origin) ? newer.origin : origin,
            scale: newer.fields.contains(.scale) ? newer.scale : scale,
            angles: newer.fields.contains(.angles) ? newer.angles : angles,
            color: newer.fields.contains(.color) ? newer.color : color,
            pointSize: newer.pointSize,
            text: newer.fields.contains(.text) ? newer.text : text,
            font: newer.fields.contains(.font) ? newer.font : font,
            assetPath: newer.assetPath ?? assetPath,
            ownerTarget: newer.ownerTarget ?? ownerTarget,
            effectVisibilities: effectVisibilities.merging(newer.effectVisibilities) { _, new in new },
            solid: newer.fields.contains(.solid) ? newer.solid : solid,
            particleAlpha: newer.fields.contains(.particleAlpha) ? newer.particleAlpha : particleAlpha
        )
    }
}
