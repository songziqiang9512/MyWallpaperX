import Metal
import simd

/// Static generic4 point/spot surface parameters, prepared once per material.
/// The caller retains the existing directional and other material policies.
struct SceneStaticModelSurfaceProfile: Equatable, Sendable {
    let metallic: Float
    let roughness: Float
}

struct SceneStaticModelViewTint {
    let front: SIMD3<Float>
    let back: SIMD3<Float>
    let exponent: Float
    let usesDynamicBackColor: Bool

    func resolvingBackColor(_ color: SIMD3<Float>) -> Self {
        guard usesDynamicBackColor else { return self }
        return .init(
            front: front,
            back: color,
            exponent: exponent,
            usesDynamicBackColor: true
        )
    }
}

/// Small material contract shared by direct static-model shader families.
/// Authored alpha meaning is kept separate from storage alpha so tint masks
/// cannot accidentally punch holes through otherwise opaque geometry.
struct SceneStaticModelMaterial {
    let color: SIMD3<Float>
    let opacity: Float
    let receivesLighting: Bool
    let textureAlphaIsOpacity: Bool
    let textureAlphaIsTintMask: Bool
    let emissiveColor: SIMD3<Float>
    let emissiveBrightness: Float
    let brightness: Float
    let usesHDRBrightness: Bool
    let viewTint: SceneStaticModelViewTint?
    var channelBindings: SceneStaticModelMaterialBindings? = nil
    var surfaceProfile: SceneStaticModelSurfaceProfile? = nil
    var cullMode: MTLCullMode = .back

    func resolvingDynamicViewTintBack(_ color: SIMD3<Float>) -> Self {
        .init(
            color: self.color,
            opacity: opacity,
            receivesLighting: receivesLighting,
            textureAlphaIsOpacity: textureAlphaIsOpacity,
            textureAlphaIsTintMask: textureAlphaIsTintMask,
            emissiveColor: emissiveColor,
            emissiveBrightness: emissiveBrightness,
            brightness: brightness,
            usesHDRBrightness: usesHDRBrightness,
            viewTint: viewTint?.resolvingBackColor(color),
            channelBindings: channelBindings,
            surfaceProfile: surfaceProfile,
            cullMode: cullMode
        )
    }

    func resolvingDynamicValues(
        layerID: Int,
        materialPath: String = "",
        snapshot: SceneDynamicSnapshot
    ) -> Self {
        let color = vector3(dynamicKey(for: .color, legacy: "color"), layerID: layerID, materialPath: materialPath, snapshot: snapshot)
            ?? self.color
        let emissiveColor = vector3(
            "emissivecolor", layerID: layerID, materialPath: materialPath, snapshot: snapshot
        ) ?? self.emissiveColor
        return .init(
            color: color,
            opacity: scalar(dynamicKey(for: .alpha, legacy: "alpha"), layerID: layerID, materialPath: materialPath, snapshot: snapshot)
                .map { min(max($0, 0), 1) } ?? opacity,
            receivesLighting: receivesLighting,
            textureAlphaIsOpacity: textureAlphaIsOpacity,
            textureAlphaIsTintMask: textureAlphaIsTintMask,
            emissiveColor: emissiveColor,
            emissiveBrightness: scalar(
                "emissivebrightness", layerID: layerID, materialPath: materialPath, snapshot: snapshot
            ).map { max($0, 0) } ?? emissiveBrightness,
            brightness: scalar(
                dynamicKey(for: .brightness, legacy: "brightness"), layerID: layerID, materialPath: materialPath, snapshot: snapshot
            ).map { max($0, 0) } ?? brightness,
            usesHDRBrightness: usesHDRBrightness,
            viewTint: viewTint,
            channelBindings: channelBindings,
            surfaceProfile: surfaceProfile,
            cullMode: cullMode
        )
    }

    private func dynamicKey(
        for channel: SceneStaticModelMaterialBindings.Channel,
        legacy: String
    ) -> String? {
        switch channelBindings?.state {
        case .some(.authored):
            return channelBindings?.binding(for: channel)?.materialKey
        case .some(.rejected):
            return nil
        default:
            return legacy
        }
    }

    private func scalar(
        _ name: String?,
        layerID: Int,
        materialPath: String,
        snapshot: SceneDynamicSnapshot
    ) -> Float? {
        guard let name, let resolved = snapshot[.materialConstant(
            layerID: layerID, passIndex: 0, name: name, materialPath: materialPath
        )], case let .scalar(value) = resolved.value, value.isFinite else {
            return nil
        }
        let result = Float(value)
        return result.isFinite ? result : nil
    }

    private func vector3(
        _ name: String?,
        layerID: Int,
        materialPath: String,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Float>? {
        guard let name, let resolved = snapshot[.materialConstant(
            layerID: layerID, passIndex: 0, name: name, materialPath: materialPath
        )], case let .vector3(x, y, z) = resolved.value,
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        return SIMD3(
            Float(min(max(x, 0), 1)),
            Float(min(max(y, 0), 1)),
            Float(min(max(z, 0), 1))
        )
    }
}

