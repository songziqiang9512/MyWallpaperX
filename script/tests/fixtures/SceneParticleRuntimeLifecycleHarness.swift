import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func playbackDeltaBounds() -> [String: Double] {
        [
            "sixtyFPS": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(1.0 / 60.0),
            "thirtyFPS": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(1.0 / 30.0),
            "slowFrame": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(0.25),
            "negative": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(-1),
            "nonFinite": SceneParticlePlaybackState.boundedRealtimeSimulationDelta(.infinity),
        ]
    }

    static func frameTransactionBounds() -> [String: Any] {
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 30,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 2, "max": 2],
                ["name": "velocityrandom", "min": "-1 2 0", "max": "1 3 0"],
            ],
            "renderer": [["name": "sprite"]],
        ])
        var retry = SceneParticleSimulator(definition: definition, seed: 17)
        retry.advance(by: 1.0 / 60.0)
        let snapshot = retry.frameSnapshot()
        retry.advance(by: 1.0 / 60.0)
        retry.restoreFrame(snapshot)
        retry.advance(by: 1.0 / 60.0)
        var expected = SceneParticleSimulator(definition: definition, seed: 17)
        expected.advance(by: 1.0 / 60.0)
        expected.advance(by: 1.0 / 60.0)
        let subframeDefinition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [[
                "name": "lifetimerandom", "min": 0.0004, "max": 0.0004,
            ]],
            "renderer": [["name": "sprite"]],
        ])
        let subframe = SceneParticleSimulator(definition: subframeDefinition, seed: 19)
        subframe.advance(by: 1.0 / 60.0)
        let subframeSnapshot = subframe.frameSnapshot()
        let transientBeforeConsume = subframe.renderParticlesForCurrentAdvance().count
        _ = subframe.consumeBirthEvents()
        _ = subframe.consumeDeathEvents()
        let transientAfterConsume = subframe.renderParticlesForCurrentAdvance().count
        subframe.advance(by: 0)
        let transientAfterNextAdvance = subframe.renderParticlesForCurrentAdvance().count
        subframe.restoreFrame(subframeSnapshot)
        let steadyDefinition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/unused.json",
            "maxcount": 8,
            "emitter": [[
                "name": "sphererandom", "rate": 60,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [[
                "name": "lifetimerandom", "min": 0.025, "max": 0.025,
            ]],
            "renderer": [["name": "sprite"]],
        ])
        let steady = SceneParticleSimulator(definition: steadyDefinition, seed: 23)
        steady.advance(by: 1.0 / 60.0)
        _ = steady.consumeBirthEvents()
        _ = steady.consumeDeathEvents()
        steady.advance(by: 1.0 / 60.0)
        return [
            "sameParticles": retry.particles == expected.particles,
            "sameTime": retry.simulationTime == expected.simulationTime,
            "sameRandom": retry.random.state == expected.random.state,
            "transientPersistentCount": subframe.particles.count,
            "transientBeforeConsume": transientBeforeConsume,
            "transientAfterConsume": transientAfterConsume,
            "transientAfterNextAdvance": transientAfterNextAdvance,
            "transientRestored": subframe.renderParticlesForCurrentAdvance().count,
            "steadyPersistentCount": steady.particles.count,
            "steadyTransientCount": steady.transientRenderSampleCount,
        ]
    }

    static func syntheticSubframeLifetime() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-subframe-lifetime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [[
                "name": "sphererandom", "rate": 50, "controlpoint": 1,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.02, "max": 0.02],
                ["name": "sizerandom", "min": 8, "max": 8],
            ],
            "renderer": [["name": "sprite"]],
            "children": [["name": "particles/child.json", "type": "static"]],
        ], to: directory.appendingPathComponent("particles/root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 100,
            "emitter": [[
                "name": "sphererandom", "rate": 120,
                "distancemin": 0, "distancemax": 0,
            ]],
            "initializer": [
                ["name": "lifetimerandom", "min": 0.0004, "max": 0.0004],
                ["name": "sizerandom", "min": 4, "max": 4],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/child.json"))
        let descriptor = SceneRenderDescriptor(
            layers: [layer(
                984, "particles/root.json",
                particleLifetime: 0.02, particleRate: 3.95
            )],
            renderOrderLayerIDs: [984],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let pointer = SIMD3<Double>(32, 48, 0)
        let first = runtime.advance(
            by: 1.0 / 20.0,
            pointerLocalPositions: [984: pointer]
        )
        let lifecycle = runtime.lifecycleSnapshot
        let rootBatch = first.first { $0.particlePath == "particles/root.json" }
        let childBatch = first.first { $0.particlePath == "particles/child.json" }
        let second = runtime.advance(by: 1.0 / 120.0)
        return [
            "rootInstanceCount": rootBatch?.instances.count ?? 0,
            "childInstanceCount": childBatch?.instances.count ?? 0,
            "rootPositions": rootBatch?.instances.map {
                [$0.positionAndSize.x, $0.positionAndSize.y, $0.positionAndSize.z]
            } ?? [],
            "rootPersistentCount": lifecycle.rootParticleCount,
            "childPersistentCount": lifecycle.childParticleCount,
            "secondAdvanceInstanceCount": second.reduce(0) { $0 + $1.instances.count },
        ]
    }

    static func playbackControl() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-playback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/root.json", material: "materials/shared.json", flags: 5,
            renderer: "ropetrail", rendererLength: 0.5, velocityX: 100, startTime: 0.5,
            moves: true, rate: 0, instantaneous: 1, under: directory)
        try writeParticle("particles/children.json", material: "materials/shared.json", rate: 0,
            instantaneous: 1, children: [["name": "missing.json"]], under: directory)
        let descriptor = SceneRenderDescriptor(layers: [layer(42, "particles/root.json"),
            layer(43, "particles/children.json"), layer(44, "particles/root.json", visible: false),
            layer(45, "particles/root.json", particleAlpha: 0), layer(46, "particles/missing.json")],
            renderOrderLayerIDs: [42,43,44,45,46], materialPasses: [.init(
                materialPath: "materials/shared.json", shaderPath: "genericparticle",
                texturePaths: ["shared.png"], blending: "additive")])
        guard let device = MTLCreateSystemDefaultDevice(), let playback = SceneParticlePlaybackState(
            descriptor: descriptor, cacheDirectory: directory, device: device) else { throw HarnessError.noMetal }
        var result: [String: Bool] = [:]
        result["preparedLive"] = playback.playbackObservation(layerID: 42)?.liveAny == true
            && !playback.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
        result["unavailableIsNotFalse"] = [43, 44, 46].allSatisfy { playback.playbackObservation(layerID: $0) == nil }
        let transparent = playback.batches.filter { $0.layerID == 45 }.flatMap(\.instances)
        result["zeroInstanceAlphaKeepsPreparedTransparentOwner"] = playback.playbackObservation(layerID: 45) != nil
            && !transparent.isEmpty && transparent.allSatisfy { $0.rotationAndAlpha.w == 0 }
        let stop = SceneParticlePlaybackTransition(layerID: 42, action: .stop, revision: 1)
        result["validatesStop"] = playback.validatePlaybackTransitions([stop])
        result["rejectsRevisionGap"] = !playback.validatePlaybackTransitions([.init(layerID: 42, action: .play, revision: 2)])
        result["rejectsMissingBeforeAnyApply"] = !playback.validatePlaybackTransitions([stop, .init(layerID: 46, action: .stop, revision: 1)])
            && playback.playbackObservation(layerID: 42)?.liveAny == true
        playback.applyPlaybackTransitions([stop])
        result["stopClearsPublishedBatch"] = playback.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
            && playback.playbackObservation(layerID: 42)?.liveAny == false
        result["stopClearsRopeGhostNextFrame"] = playback.advance(by: 1.0 / 60).filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
        result["emptyRuntimeRemainsAvailable"] = playback.playbackObservation(layerID: 42)?.intent == .stopped
        let play = SceneParticlePlaybackTransition(layerID: 42, action: .play, revision: 2)
        result["resumeValidated"] = playback.validatePlaybackTransitions([play])
        playback.applyPlaybackTransitions([play])
        _ = playback.advance(by: 1.0 / 60)
        let resumed = playback.advance(by: 1.0 / 60).filter { $0.layerID == 42 }.flatMap(\.instances)
        result["stopPlayProducesFreshTrail"] = !resumed.isEmpty && playback.playbackObservation(layerID: 42)?.liveAny == true
        result["retryValidated"] = playback.validatePlaybackTransitions([stop, play])
        playback.applyPlaybackTransitions([stop, play])
        result["retryDoesNotClearPublishedBatch"] = playback.batches.filter { $0.layerID == 42 }.flatMap(\.instances).count == resumed.count
            && playback.playbackObservation(layerID: 42)?.revision == 2
        for intent in [SceneParticlePlaybackIntent.paused, .stopped] {
            guard let rebuilt = SceneParticlePlaybackState(descriptor: descriptor,
                cacheDirectory: directory, device: device, initialPlayback: [42: .init(intent: intent, revision: 2)])
            else { throw HarnessError.noParticlePipeline }
            result["rebuild-\(intent)-noWarmupOrOldCommands"] = rebuilt.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
                && rebuilt.playbackObservation(layerID: 42)?.liveAny == false
            rebuilt.applyPlaybackTransitions([stop, play])
            result["rebuild-\(intent)-revisionConsumed"] = rebuilt.playbackObservation(layerID: 42)?.intent == intent
        }
        return result
    }

    static func syntheticLifecycle() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "mwx-particle-lifecycle-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/root.json",
            material: "materials/shared.json",
            rate: 60,
            children: [[
                "name": "particles/child.json",
                "type": "eventspawn",
                "maxcount": 4,
            ]],
            under: directory
        )
        try writeParticle(
            "particles/child.json",
            material: "materials/shared.json",
            rate: 30,
            emitterDuration: 0.5,
            under: directory
        )
        let descriptor = SceneRenderDescriptor(
            layers: [layer(200, "particles/root.json")],
            renderOrderLayerIDs: [200],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle",
                    texturePaths: ["shared.png"],
                    blending: "additive"
                )
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.noMetal
        }
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        ) else {
            throw HarnessError.noParticlePipeline
        }
        _ = playback.advance(by: 0.25)
        _ = playback.advance(by: 0.25)
        let identity = playback.lifecycleIdentity
        let active = playback.lifecycleSnapshot
        let observation = playback.teardown(reason: "scene-switch")
        let terminated = playback.lifecycleSnapshot
        let postTeardownBatches = playback.advance(by: 1)
        let repeatedObservation = playback.teardown(reason: "surface-stop")
        return [
            "identity": identity.uuidString,
            "observationIdentity": observation?.lifecycleIdentity.uuidString ?? "",
            "reason": observation?.reason ?? "",
            "active": lifecycleJSON(active),
            "observed": lifecycleJSON(
                observation?.snapshotBeforeTeardown ?? .empty
            ),
            "batchCountBeforeTeardown": observation?.batchCountBeforeTeardown ?? -1,
            "terminated": lifecycleJSON(terminated),
            "postTeardownBatchCount": postTeardownBatches.count,
            "repeatedObservation": repeatedObservation != nil,
        ]
    }

    static func lifecycleJSON(
        _ value: SceneParticleRuntimeLifecycleSnapshot
    ) -> [String: Int] {
        [
            "layers": value.activeLayerCount,
            "rootSystems": value.rootSystemCount,
            "childSystems": value.childSystemCount,
            "rootParticles": value.rootParticleCount,
            "childParticles": value.childParticleCount,
        ]
    }

}
