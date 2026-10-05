import simd

extension SceneRenderDescriptor {
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
    var hasAuthoredTransformMotion: Bool {
        // Only declared transform writers make the chain dynamic: scripted
        // transform field wrappers plus transform-host timelines. Value
        // scripts (color/alpha/visibility pumps) do not move the layer.
        if originHasScript == true || scaleHasScript == true
            || anglesHasScript == true {
            return true
        }
        let transformHosts: Set<SceneDocument.SceneObjectTimeline.Host> = [
            .origin, .angles, .scale,
        ]
        if timelines.contains(where: { transformHosts.contains($0.host) }) {
            return true
        }
        return timelineDiagnostics.contains { diagnostic in
            transformHosts.contains { diagnostic.hasPrefix("\($0.rawValue):") }
        }
    }
}
