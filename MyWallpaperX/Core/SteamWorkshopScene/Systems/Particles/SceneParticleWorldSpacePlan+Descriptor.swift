import simd

extension SceneRenderDescriptor {
    var staticParticleWorldSpaceFrames: [Int: SceneParticleWorldSpaceFrame] {
        let layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        let parallaxNodes = layersByID.mapValues { layer in
            SceneLayerParallax.Node(
                id: layer.id,
                parentID: layer.parentID,
                depth: SIMD2(layer.parallaxDepthXY ?? [], fill: 0),
                propagatesToChildren: !layer.disablesParallaxPropagation
            )
        }
        let nodes = layers.map { layer in
            let parallax = SceneLayerParallax.resolve(
                layerID: layer.id,
                nodesByID: parallaxNodes
            )
            return SceneParticleStaticWorldSpacePlan.Node(
                id: layer.id,
                parentID: layer.parentID,
                hasAuthoredTransformMotion: layer.hasAuthoredTransformMotion,
                hasEffectiveParallaxMotion: camera.parallaxEnabled
                    && parallax?.depth != .zero
            )
        }
        let eligible = SceneParticleStaticWorldSpacePlan.eligibleLayerIDs(nodes: nodes)
        let worldFrames = SceneLayerWorldFrameResolver.compute(
            layers: layers,
            byID: layersByID,
            sceneOrthoHeight: camera.orthoHeight
        )
        return Dictionary(uniqueKeysWithValues: eligible.compactMap { layerID in
            guard let worldFrame = worldFrames[layerID],
                  let frame = SceneParticleWorldSpaceFrame(worldFrame: worldFrame) else {
                return nil
            }
            return (layerID, frame)
        })
    }
}

private extension SceneRenderDescriptor.Layer {
    var hasAuthoredTransformMotion: Bool {
        if hasInlineScript { return true }
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
