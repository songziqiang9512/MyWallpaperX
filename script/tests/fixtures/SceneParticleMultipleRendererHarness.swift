import Foundation
import Metal

private struct MultipleRendererDrawState: Equatable {
    let layers: [Int]
    let templates: [Int?]
    let renderers: [Int]
    let instances: [[[Float]]]

    init(_ batches: [SceneParticleDrawBatch]) {
        layers = batches.map(\.layerID)
        templates = batches.map(\.childTemplateIndex)
        renderers = batches.map(\.rendererIndex)
        instances = batches.map { Harness.multipleRendererInstances($0.instances) }
    }
}

extension Harness {
    // Compare every stored GPU field, without depending on struct padding or
    // recomputing any renderer's geometry in the fixture.
    fileprivate static func multipleRendererInstances(_ instances: [SceneParticleGPUInstance]) -> [[Float]] {
        instances.map { value in
            [value.positionAndSize, value.rotationAndAlpha, value.colorAndFrameMix,
             value.frame0A, value.frame0B, value.frame1A, value.frame1B,
             value.velocityAndTrail, value.trailHeadJoin, value.trailTailJoin]
                .flatMap { [$0.x, $0.y, $0.z, $0.w] }
        }
    }

    private static func multipleRendererFramesMatch(
        _ left: SceneParticleSimulator.FrameSnapshot,
        _ right: SceneParticleSimulator.FrameSnapshot
    ) -> Bool {
        // Recorder policies and DEBUG component observations intentionally
        // differ between full and single-renderer systems. Compare simulation
        // values, events and emitter progress rather than their storage shape.
        left.playback == right.playback && left.particles == right.particles
            && left.transientRenderBirths == right.transientRenderBirths
            && left.birthEvents == right.birthEvents && left.deathEvents == right.deathEvents
            && left.simulationTime == right.simulationTime && left.accumulator == right.accumulator
            && left.random.state == right.random.state && left.nextParticleID == right.nextParticleID
            && left.activeInstanceOverride == right.activeInstanceOverride
            && left.explicitBirthEventStart == right.explicitBirthEventStart
            && left.normalizedLives == right.normalizedLives
            && left.dynamicControlPoints == right.dynamicControlPoints
            && left.dynamicControlPointAngles == right.dynamicControlPointAngles
            && left.audioInput == right.audioInput && left.eventValueContext == right.eventValueContext
            && left.controlPointConstraintHistory == right.controlPointConstraintHistory
            && left.emitters.count == right.emitters.count
            && zip(left.emitters, right.emitters).allSatisfy { pair in
                pair.0.elapsed == pair.1.elapsed && pair.0.remainder == pair.1.remainder
                    && pair.0.emittedInstantaneous == pair.1.emittedInstantaneous
            }
    }

    private static func multipleRendererChildrenMatch(
        _ left: SceneParticleChildRuntime.FrameSnapshot,
        _ right: SceneParticleChildRuntime.FrameSnapshot
    ) -> Bool {
        left.nextSeed == right.nextSeed && left.nextSystemID == right.nextSystemID
            && left.systems.count == right.systems.count
            && zip(left.systems, right.systems).allSatisfy { pair in
                pair.0.id == pair.1.id && pair.0.templateIndex == pair.1.templateIndex && pair.0.depth == pair.1.depth
                    && pair.0.spawnScopeID == pair.1.spawnScopeID && pair.0.parentParticleID == pair.1.parentParticleID
                    && pair.0.isWorldSpace == pair.1.isWorldSpace && pair.0.origin == pair.1.origin
                    && pair.0.particleOrigins == pair.1.particleOrigins
                    && multipleRendererFramesMatch(pair.0.simulatorFrame, pair.1.simulatorFrame)
            }
    }

    static func syntheticMultipleRenderers() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-multiple-renderers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let material = "materials/shared.json", renamedMaterial = "materials/other-palette.json"
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writePNG(directory.appendingPathComponent("materials/other-palette.png"))
        let passes: [SceneRenderDescriptor.MaterialPassDescriptor] = [
            .init(materialPath: material, shaderPath: "genericparticle",
                  texturePaths: ["shared.png"], blending: "additive"),
            .init(materialPath: renamedMaterial, shaderPath: "genericparticle",
                  texturePaths: ["other-palette.png"], blending: "additive"),
        ]
        let rootRenderers: [[String: Any]] = [
            ["name": "sprite", "id": 7],
            ["name": "ropetrail", "id": 7, "length": 0.25, "segments": 4, "subdivision": 0],
            ["name": "spritetrail", "id": 7, "length": 0.4, "minlength": 0, "maxlength": 80],
            ["name": "sprite", "id": 7],
            ["name": "sprite"],
            ["name": "ropetrail", "length": 0.8, "segments": 4, "subdivision": 2],
            ["name": "ropetrail", "length": 0],
            ["name": "unimplemented-fixture-renderer"],
        ]
        func renamed(_ renderers: [[String: Any]]) -> [[String: Any]] {
            renderers.enumerated().map { index, raw in
                var value = raw
                if value["id"] != nil { value["id"] = 900 + index }
                return value
            }
        }
        func writeDefinition(
            _ path: String, renderers: [[String: Any]]?, variant: Bool = false,
            lifetime: Double = 0.6, burst: Int = 3, rate: Double = 0,
            maximum: Int = 8, children: [[String: Any]] = []
        ) throws {
            try writeParticle(path, material: variant ? renamedMaterial : material,
                velocityX: 48, lifetime: lifetime, moves: true, rate: rate,
                instantaneous: burst, children: children, under: directory)
            let url = directory.appendingPathComponent(path)
            var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            raw["maxcount"] = maximum
            raw["id"] = variant ? 9901 : 1
            raw["name"] = variant ? "renamed author label" : "author label"
            var emitters = raw["emitter"] as! [[String: Any]]
            emitters[0]["distancemin"] = 1
            emitters[0]["distancemax"] = 3
            raw["emitter"] = emitters
            var writers = raw["initializer"] as! [[String: Any]]
            writers[0]["min"] = lifetime * 0.75
            writers[1]["min"] = 6
            writers[1]["max"] = 10
            writers[2]["min"] = [20, -12, 0]
            writers[2]["max"] = [72, 16, 0]
            if variant {
                writers[2]["min"] = "20 -12 0"
                writers[2]["max"] = "72 16 0"
            }
            raw["initializer"] = writers
            if let renderers { raw["renderer"] = variant ? renamed(renderers) : renderers }
            else { raw.removeValue(forKey: "renderer") }
            try writeJSON(raw, to: url)
        }
        func runtime(_ path: String, id: Int = 110, peer: Bool = true) -> SceneParticleRuntime {
            let layers = [layer(id, path)] + (peer ? [layer(111, "particles/peer.json")] : [])
            return SceneParticleRuntime(descriptor: .init(
                layers: layers, renderOrderLayerIDs: layers.map(\.id), materialPasses: passes
            ), cacheDirectory: directory, device: device)
        }
        func rootFrame(_ value: SceneParticleRuntime) -> SceneParticleSimulator.FrameSnapshot {
            value.frameSnapshot().layers[0].root!.simulatorFrame
        }
        func rootBatches(_ batches: [SceneParticleDrawBatch]) -> [SceneParticleDrawBatch] {
            // Runtime retains empty prepared batches; these indices describe drawable output.
            batches.filter { $0.layerID == 110 && $0.childTemplateIndex == nil && !$0.instances.isEmpty }
        }
        func geometryMatches(_ actual: SceneParticleDrawBatch?, _ control: SceneParticleDrawBatch?) -> Bool {
            if let actual, let control {
                return multipleRendererInstances(actual.instances) == multipleRendererInstances(control.instances)
                    && actual.orientation == control.orientation && actual.orientationAxis == control.orientationAxis
                    && actual.usesPerspective == control.usesPerspective
                    && actual.usesSceneCamera == control.usesSceneCamera
                    && actual.sizeIsWorldSpace == control.sizeIsWorldSpace
            }
            return actual == nil && control == nil
        }
        try writeDefinition("particles/peer.json", renderers: [["name": "sprite"]], lifetime: 4, burst: 1)
        try writeDefinition("particles/full.json", renderers: rootRenderers)
        try writeDefinition("particles/renamed-system.json", renderers: rootRenderers, variant: true)
        for index in 0..<6 {
            try writeDefinition("particles/control-\(index).json", renderers: [rootRenderers[index]])
        }
        let full = runtime("particles/full.json")
        let variant = runtime("particles/renamed-system.json")
        let singles = (0..<6).map { runtime("particles/control-\($0).json") }
        let peer = runtime("particles/peer.json", id: 111, peer: false)
        let rootRuntimes = [full, variant] + singles + [peer]
        defer { rootRuntimes.forEach { $0.teardown() } }
        let prepared = full.layers.first { $0.layerID == 110 }?.rootRender?.outputs ?? []
        let textureShared = prepared.count == 6 && prepared.dropFirst().allSatisfy {
            $0.renderer.texture === prepared[0].renderer.texture
        }
        var rootRows: [[String: Any]] = []
        var replayStates: [MultipleRendererDrawState] = []
        var replayFrames: [SceneParticleSimulator.FrameSnapshot] = []
        func sampleRoot(_ delta: Double, record: Bool) -> [MultipleRendererDrawState] {
            let draws = rootRuntimes.map { $0.advance(by: delta) }
            let actual = rootBatches(draws[0]), alternative = rootBatches(draws[1])
            let state = rootFrame(full)
            if record {
                rootRows.append([
                    "time": state.simulationTime, "population": state.particles.count,
                    "rootSystems": full.lifecycleSnapshot.rootSystemCount,
                    "indices": actual.map(\.rendererIndex),
                    "counts": (0..<6).map { index in actual.first { $0.rendererIndex == index }?.instances.count ?? 0 },
                    "singleGeometry": (0..<6).map { index in geometryMatches(
                        actual.first { $0.rendererIndex == index }, rootBatches(draws[index + 2]).first) },
                    "singleState": singles.map { multipleRendererFramesMatch(state, rootFrame($0)) },
                    "variantGeometry": MultipleRendererDrawState(actual) == MultipleRendererDrawState(alternative),
                    "variantState": multipleRendererFramesMatch(state, rootFrame(variant)),
                    "peerGeometry": geometryMatches(draws[0].first { $0.layerID == 111 }, draws.last!.first),
                    "peerState": multipleRendererFramesMatch(full.frameSnapshot().layers[1].root!.simulatorFrame,
                                                               rootFrame(peer)),
                ])
            }
            return draws.map(MultipleRendererDrawState.init)
        }
        _ = sampleRoot(0.125, record: true)
        let firstParticles = rootFrame(full).particles
        let randomizedPopulation = firstParticles.count == 3
            && firstParticles[0].size != firstParticles[1].size
            && firstParticles[0].velocity != firstParticles[1].velocity
        _ = sampleRoot(0.125, record: true)
        let checkpoints = rootRuntimes.map { $0.frameSnapshot() }
        for delta in [0.25, 0.25, 0.25, 0.5] {
            replayStates += sampleRoot(delta, record: true)
            replayFrames += rootRuntimes.map(rootFrame)
        }
        for (value, checkpoint) in zip(rootRuntimes, checkpoints) { value.restoreFrame(checkpoint) }
        var secondStates: [MultipleRendererDrawState] = []
        var secondFrames: [SceneParticleSimulator.FrameSnapshot] = []
        for delta in [0.25, 0.25, 0.25, 0.5] {
            secondStates += sampleRoot(delta, record: false)
            secondFrames += rootRuntimes.map(rootFrame)
        }
        let replayMatches = replayStates == secondStates
            && zip(replayFrames, secondFrames).allSatisfy { multipleRendererFramesMatch($0.0, $0.1) }

        try writeDefinition("particles/playback-full.json", renderers: rootRenderers,
                            lifetime: 2, rate: 12, maximum: 24)
        for index in 0..<6 {
            try writeDefinition("particles/playback-\(index).json", renderers: [rootRenderers[index]],
                                lifetime: 2, rate: 12, maximum: 24)
        }
        let playback = runtime("particles/playback-full.json")
        let playbackSingles = (0..<6).map { runtime("particles/playback-\($0).json") }
        let playing = runtime("particles/playback-full.json")
        let playbackRuntimes = [playback] + playbackSingles
        defer { (playbackRuntimes + [playing]).forEach { $0.teardown() } }
        for value in playbackRuntimes + [playing] { _ = value.advance(by: 0.125) }
        let beforePause = rootFrame(playback)
        for value in playbackRuntimes {
            value.applyPlaybackTransitions([.init(layerID: 110, action: .pause, revision: 1)])
        }
        let pauseDraws = playbackRuntimes.map { rootBatches($0.advance(by: 0.25)) }
        _ = playing.advance(by: 0.25)
        let paused = rootFrame(playback)
        let pauseMatches = (0..<6).allSatisfy { index in
            geometryMatches(pauseDraws[0].first { $0.rendererIndex == index }, pauseDraws[index + 1].first)
                && multipleRendererFramesMatch(paused, rootFrame(playbackSingles[index]))
        }
        for value in playbackRuntimes {
            value.applyPlaybackTransitions([.init(layerID: 110, action: .stop, revision: 2)])
        }
        let stoppedDraws = playbackRuntimes.map { $0.advance(by: 0.125) }
        let stopped = playback.layers.first { $0.layerID == 110 }!.rootRender!
        let stopClearsEveryOutput = stopped.outputs.count == 6 && stopped.simulator.particles.isEmpty
            && stopped.outputs.allSatisfy {
                $0.instances.isEmpty && ($0.ropeTrailHistory?.totalTrackCount ?? 0) == 0
            } && stoppedDraws.allSatisfy { rootBatches($0).isEmpty }
        let stopMatches = playbackSingles.allSatisfy {
            multipleRendererFramesMatch(rootFrame(playback), rootFrame($0))
        }

        let childRenderers: [[String: Any]] = [
            ["name": "sprite", "id": 4],
            ["name": "spritetrail", "id": 4, "length": 0.4, "minlength": 0, "maxlength": 80],
            ["name": "rope", "id": 4, "subdivision": 1],
            ["name": "sprite"],
            ["name": "ropetrail", "length": 0.5],
            ["name": "spritetrail", "length": -1],
            // These Rope plans are valid; event aggregation exceeds its original segment budget.
            ["name": "rope", "subdivision": 99],
            ["name": "rope", "subdivision": 32],
        ]
        var childResults: [String: Any] = [:]
        for trigger in ["static", "eventspawn"] {
            let expected = trigger == "static" ? [0, 1, 2, 3, 6, 7] : [0, 1, 2, 3]
            func childRuntime(_ label: String, renderers: [[String: Any]]?, variant: Bool = false) throws -> SceneParticleRuntime {
                let leafPath = "particles/\(trigger)-\(label)-leaf.json"
                let parentPath = "particles/\(trigger)-\(label)-parent.json"
                try writeDefinition(leafPath, renderers: renderers, variant: variant, lifetime: 2)
                try writeDefinition(parentPath, renderers: [["name": "sprite"]], variant: variant,
                    lifetime: 3, burst: trigger == "static" ? 0 : 1,
                    children: [["name": leafPath, "type": trigger]])
                return runtime(parentPath, id: 210, peer: false)
            }
            let mixed = try childRuntime("mixed", renderers: childRenderers)
            let renamedChild = try childRuntime("renamed", renderers: childRenderers, variant: true)
            let controls = try expected.map { try childRuntime("control-\($0)", renderers: [childRenderers[$0]]) }
            let implicit = try childRuntime("implicit", renderers: nil)
            let explicit = try childRuntime("explicit", renderers: [["name": "sprite"]])
            let values = [mixed, renamedChild] + controls
            defer { (values + [implicit, explicit]).forEach { $0.teardown() } }
            func childBatches(_ draws: [SceneParticleDrawBatch]) -> [SceneParticleDrawBatch] {
                draws.filter { $0.childTemplateIndex != nil }
            }
            var geometryEqual = true, stateEqual = true
            var latestDraws: [[SceneParticleDrawBatch]] = []
            for _ in 0..<2 { latestDraws = values.map { $0.advance(by: 0.125) } }
            let childCheckpoint = values.map { $0.frameSnapshot() }
            latestDraws = values.map { $0.advance(by: 0.125) }
            let mixedDraws = childBatches(latestDraws[0])
            let mixedState = mixed.frameSnapshot().layers[0]
            for (offset, index) in expected.enumerated() {
                geometryEqual = geometryEqual && geometryMatches(
                    mixedDraws.first { $0.rendererIndex == index }, childBatches(latestDraws[offset + 2]).first)
                let controlState = controls[offset].frameSnapshot().layers[0]
                stateEqual = stateEqual && multipleRendererChildrenMatch(mixedState.child!, controlState.child!)
                    && multipleRendererFramesMatch(mixedState.root!.simulatorFrame, controlState.root!.simulatorFrame)
            }
            let renamedState = renamedChild.frameSnapshot().layers[0]
            let variantEqual = MultipleRendererDrawState(mixedDraws)
                == MultipleRendererDrawState(childBatches(latestDraws[1]))
                && multipleRendererChildrenMatch(mixedState.child!, renamedState.child!)
                && multipleRendererFramesMatch(mixedState.root!.simulatorFrame, renamedState.root!.simulatorFrame)
            let forwardChildDraws = latestDraws.map(MultipleRendererDrawState.init)
            let forwardChildStates = values.map { $0.frameSnapshot().layers[0] }
            for (value, checkpoint) in zip(values, childCheckpoint) { value.restoreFrame(checkpoint) }
            let retriedDraws = values.map { $0.advance(by: 0.125) }
            let childReplay = forwardChildDraws == retriedDraws.map(MultipleRendererDrawState.init)
                && zip(forwardChildStates, values.map { $0.frameSnapshot().layers[0] }).allSatisfy { pair in
                    multipleRendererChildrenMatch(pair.0.child!, pair.1.child!)
                        && multipleRendererFramesMatch(pair.0.root!.simulatorFrame, pair.1.root!.simulatorFrame)
                }
            var implicitDraws: [SceneParticleDrawBatch] = [], explicitDraws: [SceneParticleDrawBatch] = []
            for _ in 0..<3 {
                implicitDraws = childBatches(implicit.advance(by: 0.125))
                explicitDraws = childBatches(explicit.advance(by: 0.125))
            }
            let child = mixedState.child!, childSystem = child.systems.first
            let childFrame = childSystem?.simulatorFrame
            let spriteDraws = mixedDraws.filter { [0, 1, 3].contains($0.rendererIndex) }
            let ropeDraws = mixedDraws.filter { [2, 6, 7].contains($0.rendererIndex) }
            let textureViewsShared = spriteDraws.count == 3 && spriteDraws.dropFirst().allSatisfy {
                $0.texture === spriteDraws[0].texture
            } && ropeDraws.dropFirst().allSatisfy { $0.texture === ropeDraws[0].texture }
            childResults[trigger] = [
                "indices": mixedDraws.map(\.rendererIndex), "counts": mixedDraws.map { $0.instances.count },
                "geometryMatches": geometryEqual, "simulationMatches": stateEqual,
                "variantMatches": variantEqual, "replayMatches": childReplay,
                "rootSystems": mixed.lifecycleSnapshot.rootSystemCount,
                "childSystems": child.systems.count, "childPopulation": mixed.lifecycleSnapshot.childParticleCount,
                "templateIndices": child.systems.map(\.templateIndex),
                "nextSystemID": child.nextSystemID, "nextSeed": child.nextSeed,
                "rootNextID": mixedState.root!.simulatorFrame.nextParticleID,
                "childNextID": childFrame?.nextParticleID ?? UInt64.max,
                "spriteAndTrailDiffer": multipleRendererInstances(mixedDraws.first { $0.rendererIndex == 0 }?.instances ?? [])
                    != multipleRendererInstances(mixedDraws.first { $0.rendererIndex == 1 }?.instances ?? []),
                "duplicateSpriteMatches": geometryMatches(mixedDraws.first { $0.rendererIndex == 0 },
                                                          mixedDraws.first { $0.rendererIndex == 3 }),
                "textureViewsShared": textureViewsShared,
                "implicitIndices": implicitDraws.map(\.rendererIndex),
                "implicitMatchesExplicit": geometryMatches(implicitDraws.first, explicitDraws.first)
                    && multipleRendererChildrenMatch(implicit.frameSnapshot().layers[0].child!,
                                                     explicit.frameSnapshot().layers[0].child!),
            ]
        }
        let containerLeaf = "particles/container-leaf.json"
        try writeDefinition(containerLeaf,
            renderers: [childRenderers[0], childRenderers[1], childRenderers[4]], lifetime: 2)
        try writeDefinition("particles/container.json", renderers: [], burst: 0,
            children: [["name": containerLeaf, "type": "static"]])
        try writeDefinition("particles/unsupported-leaf.json", renderers: [childRenderers[4]], lifetime: 2)
        try writeDefinition("particles/empty-container.json", renderers: [], burst: 0,
            children: [["name": "particles/unsupported-leaf.json", "type": "static"]])
        try writeDefinition("particles/bad-declaration.json", renderers: [], burst: 0,
            children: [["name": containerLeaf, "type": "not-an-event"]])
        let container = runtime("particles/container.json", id: 310, peer: false)
        let emptyContainer = runtime("particles/empty-container.json", id: 310, peer: false)
        let badDeclaration = runtime("particles/bad-declaration.json", id: 310, peer: false)
        defer { [container, emptyContainer, badDeclaration].forEach { $0.teardown() } }
        _ = container.advance(by: 0.125)
        let containerDraws = container.advance(by: 0.125)
        let containerState = container.frameSnapshot().layers.first
        let containerFacts: [String: Any] = [
            "activeLayers": container.activeLayerIDs,
            "rootSystems": container.lifecycleSnapshot.rootSystemCount,
            "childSystems": container.lifecycleSnapshot.childSystemCount,
            "childPopulation": container.lifecycleSnapshot.childParticleCount,
            "noRootSimulator": containerState != nil && containerState?.root == nil,
            "indices": containerDraws.map(\.rendererIndex),
            "counts": containerDraws.map { $0.instances.count },
            "allChildOutputs": !containerDraws.isEmpty && containerDraws.allSatisfy { $0.childTemplateIndex == 0 },
            "noExecutableTemplateRejected": emptyContainer.activeLayerIDs.isEmpty,
            "badDeclarationRejected": badDeclaration.activeLayerIDs.isEmpty,
        ]
        return [
            "root": rootRows, "rootPreparedIndices": prepared.map { $0.renderer.index },
            "rootTextureShared": textureShared, "randomizedPopulation": randomizedPopulation,
            "replayMatches": replayMatches, "pauseMatchesSingles": pauseMatches,
            "pauseStopsBirths": paused.nextParticleID == beforePause.nextParticleID
                && rootFrame(playing).nextParticleID > beforePause.nextParticleID,
            "pauseKeepsExistingMotion": paused.simulationTime > beforePause.simulationTime
                && !paused.particles.isEmpty && paused.particles.map(\.position) != beforePause.particles.map(\.position),
            "stopClearsEveryOutput": stopClearsEveryOutput, "stopMatchesSingles": stopMatches,
            "stopKeepsPeer": stoppedDraws[0].contains { $0.layerID == 111 && !$0.instances.isEmpty },
            "children": childResults, "container": containerFacts,
        ]
    }
}
