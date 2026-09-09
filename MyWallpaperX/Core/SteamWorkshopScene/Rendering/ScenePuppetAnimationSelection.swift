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
        for layer in layers {
            guard let visible = layer.visible else {
                return .failure(.malformedVisibility(layer.id))
            }
            guard visible || layer.visibilityBinding != nil else { continue }
            guard let animationID = layer.animationID,
                  layer.additive != nil,
                  let blend = layer.blend,
                  blend.isFinite,
                  blend > 0,
                  blend <= 1,
                  // Omitted blend edges are the authored false defaults; an
                  // explicit true still stays outside this bounded profile.
                  layer.blendIn != true,
                  layer.blendOut != true,
                  let rate = layer.rate,
                  rate.isFinite,
                  rate > 0 else {
                return .failure(.unsupportedLayer(layer.id))
            }
            guard layer.visibilityBinding == nil || layer.id != nil else {
                return .failure(.unresolvedVisibility(layer.id))
            }
            guard let animation = animationSet.animations.first(where: { $0.id == animationID }) else {
                return .failure(.unknownAnimation(animationID))
            }
            clips.append(.init(layer: layer, animation: animation))
        }
        guard clips.isEmpty == false else { return .success(nil) }
        if clips.count == 1, clips[0].layer.additive == false {
            return .success(.init(clips: clips, composition: .singleAbsolute))
        }
        // Wallpaper Engine stacks visible puppet layers bottom-to-top.  An
        // additive layer contributes its frame-relative delta while an
        // opaque layer blends its absolute pose over the running pose.  Keep
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

    nonisolated var description: String {
        switch self {
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
