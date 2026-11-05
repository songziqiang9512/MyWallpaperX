import Foundation
import simd

extension SceneRenderDescriptor {
    func particleControlPointForceEnvironment(
        for layer: Layer, definition: SceneParticleDefinition
    ) -> SceneParticleControlPointForceEnvironment {
        let distance = camera.authoredOrthographicProjectionActive.map { $0 ? 512.0 : 5.0 }
        let worldSource = camera.authoredOrthographicProjectionActive == true
            && camera.orthoWidth.map({ $0.isFinite && $0 > 0 }) == true
            && camera.orthoHeight.map({ $0.isFinite && $0 > 0 }) == true
            && layer.parentID == nil && layer.attachmentName == nil
            && layer.parentAttachmentBindFrame == nil && layer.childLayerIDs.isEmpty
            && !layers.contains(where: { $0.parentID == layer.id })
            && layer.usesPerspective != true && !definition.flags.isWorldSpace
            && !definition.flags.usesPerspective && definition.children.isEmpty
        return .init(defaultMaximumDistance: distance, allowsWorldSource: worldSource)
    }

    /// Prepared reference and initial typed source, before simulator prewarm.
    func particleRootWorldTranslations(initialDynamicValues: SceneDynamicSnapshot)
        -> [Int: (plan: SceneParticleRootWorldTranslationPlan, frame: SceneParticleWorldSpaceFrame)] {
        guard let width = camera.orthoWidth, let height = camera.orthoHeight,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return [:] }
        let byID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        let candidates = layers.filter { layer in
            guard layer.contentKind == "particle" else { return false }
            var current: Layer? = layer
            var visited: Set<Int> = []
            var hasOriginWriter = false
            while let member = current {
                guard visited.insert(member.id).inserted,
                      member.attachmentName == nil, member.parentAttachmentBindFrame == nil,
                      member.usesPerspective != true,
                      !member.hasTransformWriter(.angles), !member.hasTransformWriter(.scale),
                      !member.timelineDiagnostics.contains(where: { $0.hasPrefix("origin:") })
                else { return false }
                hasOriginWriter = hasOriginWriter || member.hasTransformWriter(.origin)
                guard let parentID = member.parentID else { return hasOriginWriter }
                guard let parent = byID[parentID] else { return false }
                current = parent
            }
            return false
        }
        guard !candidates.isEmpty else { return [:] }
        let reference = SceneLayerWorldFrameResolver.compute(
            layers: layers, byID: byID, sceneOrthoHeight: camera.orthoHeight)
        let current = SceneLayerDynamicWorldFrameResolver.resolve(descriptor: self,
            byID: byID, snapshot: initialDynamicValues, staticFrames: reference)
        return Dictionary(uniqueKeysWithValues: candidates.compactMap { layer
            -> (Int, (plan: SceneParticleRootWorldTranslationPlan, frame: SceneParticleWorldSpaceFrame))? in
            guard let source = reference[layer.id], let live = current[layer.id],
                  let plan = SceneParticleRootWorldTranslationPlan(referenceWorldFrame: source),
                  let frame = plan.frame(currentWorldFrame: live) else { return nil }
            return (layer.id, (plan: plan, frame: frame))
        })
    }

    /// Eligible world-space layer -> its full ancestor-chain member set.
    /// Derived with the same node facts as `staticParticleWorldSpaceFrames`.
    var staticParticleWorldSpaceChains: [Int: Set<Int>] {
        let nodes = worldSpacePlanNodes
        return SceneParticleStaticWorldSpacePlan.chainMembership(nodes: nodes)
    }

    var staticParticleWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame] {
        let layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        // Chain eligibility: a static node under a transform-writing ancestor
        // still has a dynamic world frame.
        let eligibleChains = SceneParticleStaticWorldSpacePlan.chainMembership(
            nodes: worldSpacePlanNodes
        )
        let worldFrames = SceneLayerWorldFrameResolver.compute(
            layers: layers,
            byID: layersByID,
            sceneOrthoHeight: camera.orthoHeight
        )
        return Dictionary(uniqueKeysWithValues: eligibleChains.keys.compactMap { layerID in
            guard let worldFrame = worldFrames[layerID],
                  let frame = SceneParticleWorldSpaceFrame(worldFrame: worldFrame) else {
                return nil
            }
            return (layerID, frame)
        })
    }

    private var worldSpacePlanNodes: [SceneParticleStaticWorldSpacePlan.Node] {
        // Camera parallax is the renderer's view translation. It moves already
        // born particles with their layer without changing this direction basis.
        layers.map { layer in
            SceneParticleStaticWorldSpacePlan.Node(
                id: layer.id,
                parentID: layer.parentID,
                hasAuthoredTransformMotion: layer.hasAuthoredTransformMotion
            )
        }
    }
}

private extension SceneRenderDescriptor.Layer {
    func hasTransformWriter(_ host: SceneDocument.SceneObjectTimeline.Host) -> Bool {
        let script: Bool
        switch host {
        case .origin: script = originHasScript == true
        case .angles: script = anglesHasScript == true
        case .scale: script = scaleHasScript == true
        default: script = false
        }
        return script || timelines.contains { $0.host == host }
            || timelineDiagnostics.contains { $0.hasPrefix("\(host.rawValue):") }
    }

    var hasAuthoredTransformMotion: Bool {
        // Only declared transform writers make the chain dynamic: scripted
        // transform field wrappers plus transform-host timelines. Value
        // scripts (color/alpha/visibility pumps) do not move the layer.
        hasTransformWriter(.origin) || hasTransformWriter(.angles) || hasTransformWriter(.scale)
    }
}
