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

        nonisolated var supportsDirectModelChannels: Bool {
            !animation.hasAlphaContribution && !animation.hasAuxiliaryScalarTrack
        }
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
        animationSet: SceneMdlPuppetAnimationSet,
        includeStaticHidden: Bool = false
    ) -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        var clips: [ScenePuppetAnimationSelection.Clip] = []
        let requiredAnimationIDs: Set<Int> = includeStaticHidden ? [] : Set(layers.filter {
            $0.visible != false || $0.visibilityBinding != nil
        }.compactMap(\.animationID))
        for layer in layers {
            guard let visible = layer.visible else {
                return .failure(.malformedVisibility(layer.id))
            }
            guard visible || layer.visibilityBinding != nil || layer.hasVisibilityScript == true
                || includeStaticHidden else { continue }
            let optionalClip = layer.visible == false && layer.visibilityBinding == nil
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
                // An optional hidden resource cannot revoke a healthy parent.
                // A caller receives unavailable metadata for that slot.
                if optionalClip { continue }
                return .failure(.unsupportedLayer(layer.id))
            }
            guard layer.visibilityBinding == nil || layer.id != nil else {
                return .failure(.unresolvedVisibility(layer.id))
            }
            if optionalClip && !includeStaticHidden && (requiredAnimationIDs.contains(animationID)
                || clips.contains(where: { $0.animation.id == animationID })) { continue }
            guard let animation = animationSet.animations.first(where: { $0.id == animationID }) else {
                if optionalClip { continue }
                return .failure(.unknownAnimation(animationID))
            }
            // New static slots need a consumer for every authored channel.
            if optionalClip && layer.hasVisibilityScript != true
                && animation.hasAuxiliaryScalarTrack { continue }
            clips.append(.init(layer: layer, animation: animation))
        }
        // Newly addressable static resources cannot evict previously prepared
        // visible, bound or scripted clips when the existing union is unsupported.
        if includeStaticHidden,
           clips.filter({ $0.animation.hasAlphaContribution }).count > 1
            || (clips.contains { $0.animation.transformTrackStates.contains(.referenceCandidate) }
                && clips.filter({ $0.layer.additive == false }).count > 1) {
            clips.removeAll { $0.layer.visible == false && $0.layer.visibilityBinding == nil
                && $0.layer.hasVisibilityScript != true }
        }
        // More than one alpha contributor is outside the bounded profile.
        // Extra preparation for hidden scripts must not break a previously
        // valid visible selection. Drop only those optional resources first.
        if clips.reduce(0, { $0 + ($1.animation.hasAlphaContribution ? 1 : 0) }) > 1 {
            clips.removeAll { $0.layer.visible == false
                && $0.layer.visibilityBinding == nil && $0.layer.hasVisibilityScript == true }
        }
        guard clips.isEmpty == false else { return .success(nil) }
        let alphaClips = clips.filter { $0.animation.hasAlphaContribution }
        if alphaClips.count > 1, let alphaClip = alphaClips.first {
            // Neutral peers preserve the single contributor's coverage. Two
            // contributors still require an independently established rule.
            return .failure(.unsupportedLayer(alphaClip.layer.id))
        }
        if clips.contains(where: { $0.animation.transformTrackStates.contains(.referenceCandidate) }),
           clips.filter({ $0.layer.additive == false }).count > 1 {
            return .failure(.unsupportedLayer(clips.first?.layer.id))
        }
        if clips.count == 1, clips[0].layer.additive == false {
            return .success(.init(clips: clips, composition: .singleAbsolute))
        }
        // Wallpaper Engine stacks visible puppet layers bottom-to-top.  An
        // additive layer contributes its rig-reference delta (bind by default); the first
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
    case invalidReferenceTransform(Int)
    case invalidReferenceTrack(Int)
    case unsupportedReferenceComposition
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
        case .invalidReferenceTransform(let index):
            return "puppet reference local transform \(index) is not decomposable"
        case .invalidReferenceTrack(let index):
            return "puppet animation reference track \(index) is outside the bounded bind-equivalent profile"
        case .unsupportedReferenceComposition:
            return "puppet reference tracks require at most one opaque clip"
        case .invalidFrame(let index):
            return "puppet animation frame \(index) is out of bounds"
        case .duplicateAdditiveAnimation(let animationID):
            return "additive animation \(animationID) is selected more than once"
        }
    }
}
