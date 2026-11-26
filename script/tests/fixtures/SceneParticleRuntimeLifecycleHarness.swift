import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func continuousFrameBirths() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-continuous-births-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        func definition(rate: Int) -> [String: Any] {
            ["material": "materials/shared.json", "maxcount": 40,
             "emitter": [["name": "boxrandom", "rate": rate, "distancemin": 0, "distancemax": 0]],
             "initializer": [
                ["name": "lifetimerandom", "min": 0.05, "max": 0.05],
                ["name": "sizerandom", "min": 8, "max": 8],
                ["name": "velocityrandom", "min": "60 0 0", "max": "60 0 0"],
             ],
             "operator": [["name": "movement", "gravity": "900 0 0", "drag": 5]],
             "renderer": [["name": "sprite"]]]
        }
        let path = "particles/continuous.json"
        try writeJSON(definition(rate: 600), to: directory.appendingPathComponent(path))
        let descriptor = SceneRenderDescriptor(layers: [layer(921, path)], renderOrderLayerIDs: [921], materialPasses: [
            .init(materialPath: "materials/shared.json", shaderPath: "genericparticle",
                  texturePaths: ["shared.png"], blending: "additive"),
        ])
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        let split = SceneParticleRuntime(descriptor: descriptor, cacheDirectory: directory, device: device)
        let first = runtime.advance(by: 1.0 / 30.0).flatMap(\.instances)
        _ = runtime.advance(by: 1.0 / 30.0)
        let replaced = runtime.advance(by: 1.0 / 30.0).flatMap(\.instances)
        _ = split.advance(by: 1.0 / 60.0)
        let splitPositions = split.advance(by: 1.0 / 60.0).flatMap(\.instances).map { $0.positionAndSize.x }
        let explicit = SceneParticleSimulator(
            definition: SceneParticleDefinitionParser().parse(root: definition(rate: 0)),
            seed: 19, allowsContinuousFrameUpdate: true)
        try explicit.emitExplicitly(count: 1, context: .init()) { _ in }
        explicit.advance(by: 1.0 / 120.0)
        return ["firstPositions": first.map { $0.positionAndSize.x },
                "replacementPositions": replaced.map { $0.positionAndSize.x },
                "splitPositions": splitPositions,
                "explicitTime": explicit.simulationTime, "explicitCount": explicit.particles.count]
    }

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
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let playback = SceneParticlePlaybackState(descriptor: descriptor, cacheDirectory: directory, device: device)
        var result: [String: Bool] = [:]
        result["preparedVariantDemandRemainsAvailable"] = playback.pipelineVariants.required.contains(.init(blendMode: .additive))
        let empty = SceneParticlePlaybackState(descriptor: .init(layers: [], renderOrderLayerIDs: [], materialPasses: []),
            cacheDirectory: directory, device: device)
        result["emptyCPUStateNeedsNoPipeline"] = empty.batches.isEmpty && empty.preparedLayerIDs.isEmpty
            && empty.pipelineVariants.required.isEmpty && empty.lifecycleSnapshot == .empty
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
            let rebuilt = SceneParticlePlaybackState(descriptor: descriptor,
                cacheDirectory: directory, device: device, initialPlayback: [42: .init(intent: intent, revision: 2)])
            result["rebuild-\(intent)-noWarmupOrOldCommands"] = rebuilt.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
                && rebuilt.playbackObservation(layerID: 42)?.liveAny == false
            rebuilt.applyPlaybackTransitions([stop, play])
            result["rebuild-\(intent)-revisionConsumed"] = rebuilt.playbackObservation(layerID: 42)?.intent == intent
        }
        return result
    }

    static func preparedSurfaceHandoff() throws -> [String: Bool] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mwx-prepared-handoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle("particles/audio-child.json", material: "materials/shared.json",
            startTime: 0.5, rate: 0, instantaneous: 1, under: directory)
        let childURL = directory.appendingPathComponent("particles/audio-child.json")
        var childDefinition = try JSONSerialization.jsonObject(with: Data(contentsOf: childURL)) as! [String: Any]
        var emitters = childDefinition["emitter"] as! [[String: Any]]
        emitters[0]["origin"] = "128 42 -19"
        childDefinition["emitter"] = emitters
        childDefinition["operator"] = [["name": "turbulence", "mask": "1 1 0", "scale": 0.02,
            "speedmin": 25, "speedmax": 25, "phasemin": 1, "phasemax": 1,
            "timescale": 0, "audioprocessingmode": 3]]
        try writeJSON(childDefinition, to: childURL)
        try writeParticle("particles/audio-root.json", material: "materials/shared.json",
            startTime: 0.5, rate: 60, audioProcessingMode: 1,
            children: [["name": "particles/audio-child.json", "type": "static"]], under: directory)
        try writeParticle("particles/finished.json", material: "materials/shared.json", flags: 5,
            renderer: "ropetrail", rendererLength: 0.5, velocityX: 100, startTime: 0.5,
            moves: true, rate: 0, instantaneous: 1, under: directory)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let audioDescriptor = SceneRenderDescriptor(layers: [layer(42, "particles/audio-root.json")],
            renderOrderLayerIDs: [42], materialPasses: [.init(materialPath: "materials/shared.json",
                shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive")])
        let audio = SceneParticleAudioInput(left: Array(repeating: 1, count: 16),
            right: Array(repeating: 1, count: 16), generation: 37)
        let audible = SceneParticlePlaybackState(descriptor: audioDescriptor,
            cacheDirectory: directory, device: device, initialAudioInput: audio)
        let silent = SceneParticlePlaybackState(descriptor: audioDescriptor,
            cacheDirectory: directory, device: device)
        let audibleRuntime = SceneParticleRuntime(descriptor: audioDescriptor,
            cacheDirectory: directory, device: device, initialAudioInput: audio)
        let silentRuntime = SceneParticleRuntime(descriptor: audioDescriptor,
            cacheDirectory: directory, device: device)
        let audioRoot = audible.playbackSimulators.first!.1
        guard let child = audibleRuntime.frameSnapshot().layers.first?.child?.systems.first,
              let silentChild = silentRuntime.frameSnapshot().layers.first?.child?.systems.first else {
            fatalError("prepared handoff fixture did not admit its static audio-operator child")
        }
        var result: [String: Bool] = [
            "rootPrewarmConsumesInitialAudio": !audioRoot.particles.isEmpty
                && silent.lifecycleSnapshot.rootParticleCount == 0,
            "staticChildPrewarmConsumesInitialAudio": child.simulatorFrame.particles.count == 1
                && silentChild.simulatorFrame.particles.count == 1
                && child.simulatorFrame.particles.map(\.velocity) != silentChild.simulatorFrame.particles.map(\.velocity),
            "zeroStepKeepsInitialAudio": audioRoot.frameSnapshot().audioInput == audio
                && child.simulatorFrame.audioInput == audio,
        ]
        let descriptor = SceneRenderDescriptor(layers: [layer(42, "particles/finished.json"),
            layer(43, "particles/finished.json")], renderOrderLayerIDs: [42, 43],
            materialPasses: audioDescriptor.materialPasses)
        let assets = try SceneParticleRuntime.prepareAssets(descriptor: descriptor,
            resourceView: SceneResourceView(projectRootURL: directory, packageRootURL: nil))
        let cancelled = SceneParticleRuntime(descriptor: descriptor,
            preparedAssets: assets, device: device, shouldCancelPrewarm: { true })
        let cancelledRoots = cancelled.frameSnapshot().layers.compactMap(\.root?.simulatorFrame)
        result["cancelledMultiRootPrewarmJoinsWithoutAdvancing"] = cancelledRoots.count == 2
            && cancelledRoots.allSatisfy { $0.simulationTime == 0 && $0.particles.isEmpty }
        let retained = SceneParticlePlaybackState(descriptor: descriptor,
            cacheDirectory: directory, device: device)
        let added = SceneParticlePlaybackState(descriptor: descriptor,
            cacheDirectory: directory, device: device)
        let root = added.playbackSimulators.first { $0.0 == 42 }!.1
        let retainedRoot = retained.playbackSimulators.first { $0.0 == 42 }!.1
        let retainedFrame = retainedRoot.frameSnapshot(), prepared = root.frameSnapshot()
        let retainedCount = retained.batches.flatMap(\.instances).count
        let hasPreparedTrail = !added.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
        result["fixtureHasFinishedLiveRoot"] = root.hasFinishedEmission && !prepared.particles.isEmpty
        added.adoptPlayback([42: .init(intent: .playing, revision: 9)])
        let adopted = root.frameSnapshot()
        result["emitRevisionDoesNotReplayOrRearm"] = adopted.playback == .init(intent: .playing, revision: 9)
            && adopted.particles == prepared.particles && adopted.random.state == prepared.random.state
            && adopted.nextParticleID == prepared.nextParticleID && root.hasFinishedEmission
            && adopted.emitters.map(\.elapsed) == prepared.emitters.map(\.elapsed)
            && adopted.emitters.map(\.remainder) == prepared.emitters.map(\.remainder)
            && adopted.emitters.map(\.emittedInstantaneous) == prepared.emitters.map(\.emittedInstantaneous)
        _ = added.advance(by: 1.0 / 60)
        result["finishedRootKeepsNextIDAfterHandoff"] = root.frameSnapshot().nextParticleID == prepared.nextParticleID
            && root.birthEvents.isEmpty && root.particles.count == prepared.particles.count
        let beforePause = root.frameSnapshot()
        added.adoptPlayback([42: .init(intent: .paused, revision: 12)])
        result["pauseAdoptionPreservesPopulation"] = root.particles == beforePause.particles
            && root.random.state == beforePause.random.state && root.playback == .init(intent: .paused, revision: 12)
        added.adoptPlayback([42: .init(intent: .stopped, revision: 17)])
        result["stopAdoptionClearsPopulationAndPublishedCaches"] = root.particles.isEmpty
            && root.frameSnapshot().nextParticleID == prepared.nextParticleID
            && hasPreparedTrail && root.consumeStepSnapshots().isEmpty
            && added.batches.filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
        result["stopAdoptionClearsRopeGhostOnZeroStep"] = added.advance(by: 0)
            .filter { $0.layerID == 42 }.flatMap(\.instances).isEmpty
        result["nextRealCommandUsesCurrentRevision"] = added.validatePlaybackTransitions([
            .init(layerID: 42, action: .play, revision: 18)])
            && !added.validatePlaybackTransitions([.init(layerID: 42, action: .play, revision: 19)])
        added.applyPlaybackTransitions([.init(layerID: 42, action: .play, revision: 18)])
        _ = added.advance(by: 1.0 / 60)
        result["realPlayStillRearmsAfterStop"] = !root.particles.isEmpty
            && root.frameSnapshot().nextParticleID > prepared.nextParticleID
        let stopped = SceneParticlePlaybackState(descriptor: descriptor,
            cacheDirectory: directory, device: device,
            initialPlayback: [42: .init(intent: .stopped, revision: 3)])
        stopped.adoptPlayback([42: .init(intent: .playing, revision: 20)])
        _ = stopped.advance(by: 1.0 / 60)
        result["stoppedPreparedRootCanAdoptPlaying"] = stopped.playbackObservation(layerID: 42)?.liveAny == true
            && stopped.playbackObservation(layerID: 42)?.revision == 20
        added.retire(layerIDs: [43])
        added.adoptPlayback([42: .init(intent: .playing, revision: 21),
            43: .init(intent: .stopped, revision: 21)])
        result["destroyedLayerCannotReturnThroughAdoption"] = !added.preparedLayerIDs.contains(43)
            && added.playbackObservation(layerID: 43) == nil
        let afterRetained = retainedRoot.frameSnapshot()
        result["retainedRootAndAddedIdentityStayOwned"] = added.playbackSimulators.first { $0.0 == 42 }!.1 === root
            && retainedRoot !== root && afterRetained.playback == retainedFrame.playback
            && afterRetained.particles == retainedFrame.particles && afterRetained.random.state == retainedFrame.random.state
            && afterRetained.nextParticleID == retainedFrame.nextParticleID
            && retained.batches.flatMap(\.instances).count == retainedCount
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
        let playback = SceneParticlePlaybackState(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
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

    static func authoredRetirement() throws -> [String: Bool] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-retirement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        let common: [String: Any] = [
            "material": "materials/shared.json", "maxcount": 64, "starttime": 0.1,
            "controlpoint": [["id": 1, "flags": 1, "offset": "0 0 0"]],
            "emitter": [["name": "sphererandom", "rate": 60, "controlpoint": 1,
                         "distancemin": 0, "distancemax": 2]],
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10],
                            ["name": "sizerandom", "min": 4, "max": 8],
                            ["name": "velocityrandom", "min": "-1 -2 0", "max": "1 2 0"]],
            "renderer": [["name": "sprite"]],
        ]
        try writeParticle("particles/child.json", material: "materials/shared.json",
            startTime: 0.1, rate: 30, under: directory)
        try writeJSON(common, to: directory.appendingPathComponent("particles/peer.json"))
        var facts: [String: Bool] = [:]
        for trigger in ["eventspawn", "eventdeath"] {
            var victim = common
            victim["children"] = [["name": "particles/child.json", "type": trigger, "maxcount": 4]]
            try writeJSON(victim, to: directory.appendingPathComponent("particles/victim.json"))
            let descriptor = SceneRenderDescriptor(layers: [layer(42, "particles/victim.json"),
                layer(43, "particles/peer.json")], renderOrderLayerIDs: [42, 43],
                materialPasses: [.init(materialPath: "materials/shared.json", shaderPath: "genericparticle",
                    texturePaths: ["shared.png"], blending: "additive")])
            let view = SceneResourceView(projectRootURL: directory, packageRootURL: nil)
            let assets = try SceneParticleRuntime.prepareAssets(descriptor: descriptor, resourceView: view)
            let playback = SceneParticlePlaybackState(descriptor: descriptor, preparedAssets: assets, device: device)
            var peerDescriptor = descriptor
            peerDescriptor.layers = [descriptor.layers[1]]
            let control = SceneParticlePlaybackState(descriptor: peerDescriptor, preparedAssets: assets, device: device)
            let pointers: [Int: SIMD3<Double>] = [42: SIMD3(2, 3, 0), 43: SIMD3(2, 3, 0)]
            _ = playback.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
            _ = control.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
            let frozen = playback.batches
            let frozenPositions = frozen.flatMap(\.instances).map(\.positionAndSize)
            let victimIdentity = ObjectIdentifier(playback.playbackSimulators.first { $0.0 == 42 }!.1)
            let peer = playback.playbackSimulators.first { $0.0 == 43 }!.1
            let reference = control.playbackSimulators.first { $0.0 == 43 }!.1
            facts[trigger + "-real-two-root-qualification"] = playback.preparedLayerIDs == [42, 43]
                && playback.pointerControlPointDemands.contains(42) && playback.pointerControlPointDemands.contains(43)
                && frozen.contains { $0.layerID == 42 && $0.childTemplateIndex == nil && !$0.instances.isEmpty }
            facts[trigger + "-child-qualified"] = trigger == "eventspawn"
                ? playback.lifecycleSnapshot.childSystemCount > 0
                    && frozen.contains { $0.layerID == 42 && $0.childTemplateIndex != nil }
                : playback.lifecycleSnapshot.childSystemCount == 0
            facts[trigger + "-authored-child-playback-query-is-unavailable"] = playback.playbackObservation(layerID: 42) == nil
            let visible = SceneDynamicTarget.layer(layerID: 42, field: .visibility)
            let hidden = SceneDynamicSnapshotResolver().resolve(frameIndex: 2, generation: 1,
                definitions: [.init(target: visible, valueType: .bool, authoredValue: .bool(true))],
                userValues: [visible: .bool(false)]).snapshot
            _ = playback.advance(by: 1.0 / 30, dynamicValues: hidden, pointerLocalPositions: pointers)
            _ = control.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
            facts[trigger + "-hidden-keeps-instance-and-demand"] = playback.preparedLayerIDs == [42, 43]
                && playback.playbackSimulators.count == 2
                && playback.playbackSimulators.first(where: { $0.0 == 42 }).map { ObjectIdentifier($0.1) } == victimIdentity
                && playback.pointerControlPointDemands.contains(42)
            _ = playback.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
            _ = control.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
            playback.retire(layerIDs: [42])
            let retired = lifecycleJSON(playback.lifecycleSnapshot)
            playback.retire(layerIDs: [42])
            facts[trigger + "-root-child-and-demands-retired"] = playback.preparedLayerIDs == [43]
                && playback.playbackSimulators.count == 1 && playback.playbackObservation(layerID: 42) == nil
                && Set(playback.pointerControlPointDemands) == [43]
                && playback.lifecycleSnapshot.childSystemCount == 0
                && playback.batches.allSatisfy { $0.layerID == 43 }
            facts[trigger + "-repeated-retirement-is-idempotent"] = lifecycleJSON(playback.lifecycleSnapshot) == retired
            var peerUnchanged = playback.playbackSimulators.first { $0.0 == 43 }!.1 === peer
            for _ in 0..<4 {
                let batches = playback.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
                _ = control.advance(by: 1.0 / 30, pointerLocalPositions: pointers)
                peerUnchanged = peerUnchanged && batches.allSatisfy { $0.layerID == 43 }
                    && peer.particles == reference.particles
                    && peer.frameSnapshot().random.state == reference.frameSnapshot().random.state
                    && peer.simulationTime == reference.simulationTime
            }
            facts[trigger + "-peer-rng-clock-and-values-unchanged"] = peerUnchanged
            facts[trigger + "-frozen-batch-is-independent"] = !frozenPositions.isEmpty
                && frozen.flatMap(\.instances).map(\.positionAndSize) == frozenPositions
                && frozen.contains { $0.layerID == 42 }
            let rebuilt = SceneParticlePlaybackState(descriptor: descriptor, preparedAssets: assets,
                device: device, destroyedAuthoredLayerIDs: [42])
            facts[trigger + "-rebuild-instantiates-only-live-root"] = rebuilt.preparedLayerIDs == [43]
                && rebuilt.lifecycleSnapshot.rootSystemCount == 1 && rebuilt.lifecycleSnapshot.childSystemCount == 0
                && Set(rebuilt.pointerControlPointDemands) == [43]
                && rebuilt.batches.allSatisfy { $0.layerID == 43 }
            _ = playback.teardown(reason: "retirement-test")
            _ = control.teardown(reason: "retirement-test")
            _ = rebuilt.teardown(reason: "retirement-test")
        }
        return facts
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
