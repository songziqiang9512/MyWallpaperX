import simd

struct ScenePuppetAnimationSelection {
    enum Composition: String {
        case singleAbsolute = "single-absolute"
        // More than one authored layer is evaluated in scene order; layered
        // clips may be absolute, additive, or both.
        case layered = "layered"
    }

    struct Clip {
        let layer: ScenePuppetAnimationLayer
        let animation: SceneMdlPuppetAnimation
    }

    let clips: [Clip]
    let composition: Composition
}
enum ScenePuppetAnimationSelectionFailure: Error, CustomStringConvertible, Equatable {
    case unresolvedVisibility(Int?)
    case malformedVisibility(Int?)
    case unsupportedLayer(Int?)
    case unknownAnimation(Int)

    nonisolated var description: String {
        switch self {
        case .unresolvedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has property-bound visibility without a stable layer id"
        case .malformedVisibility(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") has no static visibility"
        case .unsupportedLayer(let id):
            return "animation layer \(id.map(String.init) ?? "unknown") is outside the bounded playback profile"
        case .unknownAnimation(let id):
            return "animation id \(id) is absent from the version-matched MDLA block"
        }
    }
}

enum ScenePuppetAnimationSelector {
    static func select(
        layers: [ScenePuppetAnimationLayer],
        animationSet: SceneMdlPuppetAnimationSet
    ) -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        var clips: [ScenePuppetAnimationSelection.Clip] = []
        let requiredAnimationIDs = Set(layers.filter {
            $0.visible != false || $0.visibilityBinding != nil
        }.compactMap(\.animationID))
        for layer in layers {
            guard let visible = layer.visible else {
                return .failure(.malformedVisibility(layer.id))
            }
            guard visible || layer.visibilityBinding != nil || layer.hasVisibilityScript == true else { continue }
            let optionalScriptClip = layer.visible == false
                && layer.visibilityBinding == nil && layer.hasVisibilityScript == true
            guard let animationID = layer.animationID,
                  layer.additive != nil,
                  let blend = layer.blend,
                  blend.isFinite,
                  blend >= 0,
                  Float(blend).isFinite,
                  // Omitted blend edges are the authored false defaults; an
                  // explicit true still stays outside this bounded profile.
                  layer.blendIn != true,
                  layer.blendOut != true,
                  let rate = layer.rate,
                  rate.isFinite,
                  rate > 0 else {
                // An optional, initially hidden script resource cannot revoke
                // a healthy parent. Its script receives unavailable metadata.
                if optionalScriptClip { continue }
                return .failure(.unsupportedLayer(layer.id))
            }
            guard layer.visibilityBinding == nil || layer.id != nil else {
                return .failure(.unresolvedVisibility(layer.id))
            }
            if optionalScriptClip && (requiredAnimationIDs.contains(animationID)
                || clips.contains(where: { $0.animation.id == animationID })) { continue }
            guard let animation = animationSet.animations.first(where: { $0.id == animationID }) else {
                if optionalScriptClip { continue }
                return .failure(.unknownAnimation(animationID))
            }
            clips.append(.init(layer: layer, animation: animation))
        }
        // Consequential multi-clip alpha is outside the established profile.
        // Extra preparation for hidden scripts must not break a previously
        // valid visible selection. Drop only those optional resources first.
        if clips.count > 1, clips.contains(where: {
            $0.animation.alphaByBone?.contains { $0.contains { $0 != 1 } } == true
        }) {
            clips.removeAll { $0.layer.visible == false
                && $0.layer.visibilityBinding == nil && $0.layer.hasVisibilityScript == true }
        }
        guard clips.isEmpty == false else { return .success(nil) }
        if clips.count > 1, let alphaClip = clips.first(where: {
            $0.animation.alphaByBone?.contains { $0.contains { $0 != 1 } } == true
        }) {
            // Multi-clip alpha conflict order is not yet established. Do not
            // silently discard an authored coverage track while animating TRS.
            return .failure(.unsupportedLayer(alphaClip.layer.id))
        }
        if clips.count == 1, clips[0].layer.additive == false {
            return .success(.init(clips: clips, composition: .singleAbsolute))
        }
        // Wallpaper Engine stacks visible puppet layers bottom-to-top.  An
        // additive layer contributes its bind-relative delta; the first
        // opaque layer supplies the weighted base pose.  Keep
        // the complete authored order instead of rejecting mixed or
        // overlapping layers; the evaluator still validates every track and
        // fails closed on malformed data.
        return .success(.init(clips: clips, composition: .layered))
    }
}

enum ScenePuppetAnimationEvaluationFailure: Error, CustomStringConvertible, Equatable {
    case boneCountMismatch
    case singularBindMatrix(Int)
    case invalidBindTransform(Int)
    case invalidFrame(Int)
    case duplicateAdditiveAnimation(Int)
    case invalidBlend
    case invalidDeformedVertex

    nonisolated var description: String {
        switch self {
        case .invalidBlend:
            return "puppet weight or weighted pose is not finite"
        case .invalidDeformedVertex:
            return "puppet skinning produced a non-finite vertex"
        case .boneCountMismatch:
            return "puppet mesh, rig, and animation bone counts do not match"
        case .singularBindMatrix(let index):
            return "puppet bind world matrix \(index) is singular"
        case .invalidBindTransform(let index):
            return "puppet bind local transform \(index) is not decomposable"
        case .invalidFrame(let index):
            return "puppet animation frame \(index) is out of bounds"
        case .duplicateAdditiveAnimation(let animationID):
            return "additive animation \(animationID) is selected more than once"
        }
    }
}
