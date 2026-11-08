"""Real QuickJS media transactions reach the existing AVQueuePlayer registry."""
import json
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from .scene_vector_vm_test_support import compile_vector_harness, SCENE

HARNESS = r'''
import AVFoundation
// Prepared-plan fixture only; admission and real media selection have their own gate.
nonisolated final class SceneVideoOwnedFile: Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    func retainForLifetime(of asset: AVAsset) {}
}
struct SceneSoundPlaybackProgram {
    struct Resource {
        let file: SceneVideoOwnedFile?
        let displayPath: String
    }
    enum PlaybackMode: Equatable {
        case loop, single
        case random(minimumTime: Double, maximumTime: Double)
    }
    struct Binding {
        let layerID: Int
        let resources: [Resource]
        let playbackMode: PlaybackMode = .loop
        let startsSilent = true
        var authoredVolume = 0.0
        var volumePropertyKey: String? = nil
        var volumeTarget: SceneDynamicTarget { .layer(layerID: layerID, field: .volume) }
    }
    let bindings: [Binding]
    let layerRejectionCount = 0
    let skippedSourceCount = 0
    let scriptVolumeTargets: Set<SceneDynamicTarget> = []
}
@main enum Harness {
    static func main() throws {
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 1, layerIndex: 0, name: "sound", visible: true,
                  originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil,
                  alpha: 1, effects: [], contentKind: "sound"),
            .init(id: 2, layerIndex: 1, name: "video", visible: true,
                  originXYZ: [0,0,0], scaleXYZ: [1,1,1], scaleHasScript: nil,
                  alpha: 1, effects: [])])
        let registry = SceneSoundPlaybackRegistry(program: .init(bindings: [
            .init(layerID: 1, resources: [.init(file: SceneVideoOwnedFile(url: URL(fileURLWithPath: CommandLine.arguments[1])),
                displayPath: "fixture.wav")])]), epoch: 1)
        registry.start(paused: false, userValues: [:]); defer { registry.stop() }
        let registryHasSourcesAfterStart = registry.hasSources
        let domain = try SceneScriptQuickJSDomain(); try domain.configureLayerCatalog(descriptor)
        let volumeTarget = SceneDynamicTarget.layer(layerID: 1, field: .volume)
        let volumeDefinitions: [SceneDynamicTargetDefinition] = [
            .init(target: volumeTarget, valueType: .scalar, authoredValue: .scalar(0))]
        func volumeSnapshot(_ script: [SceneDynamicTarget: SceneDynamicValue] = [:],
                            user: [SceneDynamicTarget: SceneDynamicValue] = [:]) -> SceneDynamicSnapshot {
            SceneDynamicSnapshotResolver().resolve(frameIndex: 1, generation: 1,
                definitions: volumeDefinitions, userValues: user, sceneScriptValues: script).snapshot
        }
        var currentVolumes = volumeSnapshot()
        func publish(_ sound: [Int: Bool], volumeInput: SceneDynamicSnapshot? = nil, pending: Bool = false) throws {
            try domain.publishLayerSnapshot(volumeInput ?? currentVolumes, descriptor: descriptor,
                videoSnapshots: .init(sources: [SceneScriptVideoPlaybackSnapshot(sourceIncarnation: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, duration: 5, rate: 1, loop: true,
                    currentTime: 0, isPlaying: true, endedGeneration: 0)], layerBindings: [2: 0]),
                soundPlaybackSnapshots: sound, runtimeFieldLayerIDs: [], awaitingHostFrameOutcome: pending)
        }
        func owner(_ source: String, layerID: Int = 1) throws -> SceneScriptValueOwner {
            try SceneScriptValueOwner(domain: domain, source: source, target: .layer(layerID: layerID, field: .alpha),
                valueType: .scalar, effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        }
        func boolOwner(_ source: String, stateful: Bool = false, layerID: Int = 1) throws -> SceneScriptValueOwner {
            try SceneScriptValueOwner(domain: domain, source: source,
                target: .layer(layerID: layerID, field: .visibility), valueType: .bool,
                effectNames: [], allowsStatefulLayerSideEffects: stateful, generation: 1, budget: .default)
        }
        let frame = SceneScriptFrameInput(timing: .init(wallDate: Date(), simulationFrameTime: 0.016, sceneTime: 1))
        func evaluate(_ author: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try author.evaluate(input: .scalar(1), frame: frame, scriptPropertiesJSON: "",
                userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        }
        func evaluateBool(_ author: SceneScriptValueOwner) throws -> SceneScriptValueEvaluation {
            try author.evaluate(input: .bool(true), frame: frame, scriptPropertiesJSON: "",
                userPropertiesJSON: "{}", expectedGeneration: 1, interruptBudget: nil).get()
        }
        func waitPlaying() -> Bool {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if registry.sceneScriptSnapshots()[1] == true { return true }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            return false
        }
        var result: [String: Bool] = [:]
        try publish(registry.sceneScriptSnapshots(), volumeInput: .empty(frameIndex: 0))
        let playbackOnly = try boolOwner("""
            export function update(seed){const sound=thisScene.getLayerByID(1);
                if(!sound||sound.id!==1)throw Error('prepared Sound reference');
                let denied=false;try{sound.volume;}
                catch(error){denied=error instanceof TypeError;}
                return !sound.isPlaying()&&denied
                    &&thisScene.getLayer('video').getVideoTexture().isPlaying()&&seed;}
            """)
        let playbackWithoutVolume = try evaluateBool(playbackOnly)
        result["playback_snapshot_remains_independent_of_volume_input"] = playbackWithoutVolume.value == .bool(true)
            && playbackWithoutVolume.layerMutations.isEmpty && playbackWithoutVolume.mediaPlaybackCommands.isEmpty
        playbackOnly.discardLayerMutations()
        // Cache in init before the consumer's first available snapshot.
        try publish([:])
        let cachedVolume = try owner("""
            let renamed,updates=0;
            export function init(seed){
                renamed=thisScene.enumerateLayers().find(track=>track.id===1);
                if(!renamed||renamed.id!==1)throw Error('cached Sound reference');
                shared.assignGain=value=>{renamed.volume=value;return renamed.volume;};return seed;
            }
            export function update(seed){
                if(++updates===1)return seed;
                if(renamed.volume!==0)throw Error('real authored seed');
                for(const gain of [0,0.5,1]){renamed.volume=gain;if(renamed.volume!==gain)throw Error('immediate getter');}
                return seed;
            }
            """, layerID: 2)
        let unavailableCached = try evaluate(cachedVolume)
        result["init_caches_unavailable_sound_without_journal"] = unavailableCached.value == .scalar(1)
            && unavailableCached.layerMutations.isEmpty && unavailableCached.mediaPlaybackCommands.isEmpty
        cachedVolume.commitLayerMutations()
        try publish(registry.sceneScriptSnapshots())
        let ownVolume = try owner("""
            export function update(seed){for(const gain of [0,0.5,1]){
                thisLayer.volume=gain;if(thisLayer.volume!==gain)throw Error('thisLayer accessor');}return seed;}
            """)
        let ownWrittenVolume = try evaluate(ownVolume)
        result["this_layer_volume_publishes_typed_journal"] = ownWrittenVolume.layerMutations.count == 1
            && ownWrittenVolume.layerMutations[0].fields == [.volume]
            && ownWrittenVolume.layerMutations[0].layerID == 1 && ownWrittenVolume.layerMutations[0].volume == 1
            && ownWrittenVolume.mediaPlaybackCommands.isEmpty
        ownVolume.discardLayerMutations()
        let writtenVolume = try evaluate(cachedVolume)
        result["init_cached_volume_accessor_becomes_available"] = writtenVolume.layerMutations.count == 1
            && writtenVolume.layerMutations[0].fields == [.volume]
            && writtenVolume.layerMutations[0].volume == 1
            && writtenVolume.layerMutations[0].ownerTarget == .layer(layerID: 2, field: .alpha)
            && writtenVolume.mediaPlaybackCommands.isEmpty
        cachedVolume.discardLayerMutations()
        let volumeReader = try owner("export function update(seed){return thisLayer.volume;}")
        result["discarded_volume_keeps_frozen_peer_baseline"] = try evaluate(volumeReader).value == .scalar(0)
        volumeReader.discardLayerMutations()
        let baselineWriter = try owner("""
            export function update(seed){if(thisLayer.volume!==1)throw Error('owner baseline');
                thisLayer.volume=0.5;if(thisLayer.volume!==0.5)throw Error('written baseline');return seed;}
            """)
        result["volume_read_baseline_uses_original_abi"] = baselineWriter.configureAuthoredLayerReadBaselines(
            writtenVolume.layerMutations) == nil
        let baselineWritten = try evaluate(baselineWriter)
        result["volume_write_overlays_owner_baseline"] = baselineWritten.layerMutations.count == 1
            && baselineWritten.layerMutations[0].volume == 0.5
        baselineWriter.discardLayerMutations(); baselineWriter.clearAuthoredLayerReadBaselines()
        currentVolumes = volumeSnapshot([volumeTarget: .scalar(0.5)])
        try publish(registry.sceneScriptSnapshots())
        result["next_volume_getter_uses_typed_snapshot"] = try evaluate(volumeReader).value == .scalar(0.5)
        volumeReader.discardLayerMutations()
        currentVolumes = volumeSnapshot([volumeTarget: .scalar(1)])
        try publish(registry.sceneScriptSnapshots(), pending: true)
        let pendingVolume = try evaluate(volumeReader).value
        volumeReader.discardLayerMutations(); domain.discardCommittedLayerSnapshot()
        let restoredVolume = try evaluate(volumeReader).value
        result["volume_snapshot_discard_restores_previous_value"] = pendingVolume == .scalar(1)
            && restoredVolume == .scalar(0.5)
        volumeReader.discardLayerMutations()
        currentVolumes = volumeSnapshot(); try publish(registry.sceneScriptSnapshots())
        let gainBorrower = try boolOwner("export function update(seed){return shared.assignGain(0.5)===0.5&&seed;}",
            stateful: true, layerID: 2)
        let borrowedGain = try evaluateBool(gainBorrower)
        result["shared_volume_journal_belongs_to_executing_owner"] = borrowedGain.value == .bool(true)
            && borrowedGain.layerMutations.count == 1 && borrowedGain.layerMutations[0].volume == 0.5
            && borrowedGain.layerMutations[0].ownerTarget == .layer(layerID: 2, field: .visibility)
            && mwx_scene_quickjs_owner_layer_mutation_count(cachedVolume.handle) == 0
            && mwx_scene_quickjs_owner_layer_mutation_count(gainBorrower.handle) == 1
        gainBorrower.discardLayerMutations()
        for (key, invalid) in [("nan", "NaN"), ("infinity", "Infinity"), ("string", "'0.5'"),
                               ("missing", "undefined"), ("object", "{}"), ("boolean", "true")] {
            let rejected = try owner("export function update(v){thisLayer.volume=0.5;thisLayer.volume=\(invalid);return v;}")
            do { _ = try evaluate(rejected); result["volume_invalid_\(key)_rolls_back"] = false }
            catch { result["volume_invalid_\(key)_rolls_back"] = mwx_scene_quickjs_owner_layer_mutation_count(rejected.handle) == 0 }
            rejected.discardLayerMutations()
        }
        let nonSound = try owner("export function update(v){thisLayer.volume=0.5;return v;}", layerID: 2)
        do { _ = try evaluate(nonSound); result["non_sound_volume_rejected"] = false }
        catch { result["non_sound_volume_rejected"] = mwx_scene_quickjs_owner_layer_mutation_count(nonSound.handle) == 0 }
        nonSound.discardLayerMutations()
        result["volume_healthy_peer_after_failure"] = try evaluate(volumeReader).value == .scalar(0)
        volumeReader.discardLayerMutations()
        try publish([:], pending: true)
        // An uncaught update exception disables its owner, not the cached target.
        let missingGain = try boolOwner("export function update(seed){return shared.assignGain(0.5)===0.5&&seed;}",
            stateful: true, layerID: 2)
        do { _ = try evaluateBool(missingGain); result["cached_volume_missing_consumer_rejected"] = false }
        catch { result["cached_volume_missing_consumer_rejected"] = mwx_scene_quickjs_owner_layer_mutation_count(missingGain.handle) == 0 }
        missingGain.discardLayerMutations(); domain.discardCommittedLayerSnapshot()
        result["cached_volume_source_rollback_restores_accessor"] = try evaluateBool(gainBorrower).layerMutations.count == 1
        gainBorrower.discardLayerMutations()
        let propertyRegistry = SceneSoundPlaybackRegistry(program: .init(bindings: [
            .init(layerID: 1, resources: [.init(file: SceneVideoOwnedFile(url: URL(fileURLWithPath: CommandLine.arguments[1])),
                displayPath: "renamed.wav")], volumePropertyKey: "gain")]), epoch: 2)
        propertyRegistry.start(paused: true, userValues: [volumeTarget: .scalar(0.25)])
        defer { propertyRegistry.stop() }
        let sources = Mirror(reflecting: propertyRegistry).children.first { $0.label == "sources" }!.value
        let source = Array(Mirror(reflecting: Mirror(reflecting: sources).children.first!.value).children)[1].value
        let player = Mirror(reflecting: source).children.first { $0.value is AVQueuePlayer }!.value as! AVQueuePlayer
        let item = player.currentItem
        propertyRegistry.apply(userValues: [volumeTarget: .scalar(0.75)], committedSnapshot: volumeSnapshot(user: [volumeTarget: .scalar(0.25)]))
        result["direct_property_still_uses_existing_player"] = player.volume == 0.75
        let rawScriptSnapshot = volumeSnapshot([volumeTarget: .scalar(borrowedGain.layerMutations[0].volume)])
        propertyRegistry.apply(snapshot: rawScriptSnapshot)
        result["script_source_without_handle_provenance_keeps_direct_gain"] = player.volume == 0.75
        propertyRegistry.apply(userValues: [volumeTarget: .scalar(0.25)], committedSnapshot: rawScriptSnapshot)
        result["script_source_without_handle_provenance_keeps_property_updates"] = player.volume == 0.25
        let handleRuntime = SceneScriptDynamicLayerRuntime(descriptor: descriptor, authoredMutationLayerIDs: [],
            preparedSoundDefinitions: volumeDefinitions)
        let handlePlan = handleRuntime.preflightOwnerEffects([.init(ownerTarget: gainBorrower.target,
            materialFunctionMutations: borrowedGain.materialFunctionMutations,
            animationMutations: borrowedGain.animationMutations, layerMutations: borrowedGain.layerMutations,
            mediaPlaybackCommands: borrowedGain.mediaPlaybackCommands)])
        result["uncommitted_handle_journal_grants_no_provenance"] = handlePlan.rejectedOwners.isEmpty
            && handleRuntime.committedHandleVolumeLayerIDs.isEmpty
        handleRuntime.commit(handlePlan.layerPlan)
        let handleSnapshot = volumeSnapshot(handleRuntime.snapshot().authoredLayerValues)
        let handleIDs = handleRuntime.committedHandleVolumeLayerIDs
        result["committed_c_journal_grants_real_runtime_handle_provenance"] = handleIDs.count == 1 && handleIDs.contains(1)
        propertyRegistry.apply(snapshot: handleSnapshot, committedHandleVolumeLayerIDs: handleIDs)
        propertyRegistry.apply(userValues: [volumeTarget: .scalar(0.25)], committedSnapshot: handleSnapshot,
            committedHandleVolumeLayerIDs: handleIDs)
        result["handle_source_owns_property_player_gain"] = player.volume == 0.5
        propertyRegistry.apply(userValues: [volumeTarget: .scalar(0.75)],
            committedSnapshot: volumeSnapshot(user: [volumeTarget: .scalar(0.25)]),
            committedHandleVolumeLayerIDs: handleIDs)
        propertyRegistry.apply(snapshot: volumeSnapshot(user: [volumeTarget: .scalar(0.25)]),
            committedHandleVolumeLayerIDs: handleIDs)
        result["handle_provenance_without_script_source_keeps_direct_lane"] = player.volume == 0.75
        propertyRegistry.apply(snapshot: handleSnapshot, committedHandleVolumeLayerIDs: handleIDs)
        propertyRegistry.setMasterVolume(0.5); propertyRegistry.setMuted(true)
        let muted = player.volume == 0
        propertyRegistry.setMuted(false)
        result["handle_gain_preserves_master_mute_and_player"] = muted && player.volume == 0.25 && player.currentItem === item
        propertyRegistry.apply(snapshot: .empty(frameIndex: 2))
        result["missing_snapshot_does_not_reset_gain"] = player.volume == 0.25
        try publish(registry.sceneScriptSnapshots())
        let author = try owner("""
            export function update(v) {
                if(thisLayer.isPlaying()) throw Error('silent');
                thisLayer.play(); if(!thisLayer.isPlaying()) throw Error('play');
                thisLayer.pause(); if(thisLayer.isPlaying()) throw Error('pause');
                thisLayer.stop(); if(thisLayer.isPlaying()) throw Error('stop');
                thisScene.getLayer('video').getVideoTexture().pause();
                thisLayer.play(); return v;
            }
            """)
        let evaluated = try evaluate(author)
        let commands = evaluated.mediaPlaybackCommands
        result["typed_order"] = commands.map(\.destination) == [.soundLayer,.soundLayer,.soundLayer,.videoTexture,.soundLayer]
            && commands.map(\.action) == [.play,.pause,.stop,.pause,.play]
            && commands.map(\.videoSourceIncarnation) == [nil,nil,nil,UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,nil]
        result["evaluation_has_no_player_effect"] = registry.sceneScriptSnapshots()[1] == false
        author.discardLayerMutations()
        _ = try registry.apply(commands.filter { $0.destination == .soundLayer }).get()
        result["committed_commands_reach_real_player"] = waitPlaying()
        _ = try registry.apply([.init(layerID: 1, action: .stop, destination: .soundLayer)]).get()
        try publish(registry.sceneScriptSnapshots())
        let query = try owner("export function update(v){if(thisLayer.isPlaying())throw Error('old intent leaked');return v;}")
        result["next_callback_reads_published_state"] = try evaluate(query).mediaPlaybackCommands.isEmpty
        query.discardLayerMutations()
        let callbackScoped = try owner("""
            export function init(v){thisLayer.play();return v;}
            export function update(v){
                if(thisLayer.isPlaying())throw Error('previous callback command leaked');
                return v;
            }
            """)
        result["same_owner_callback_projection_isolated"] = try evaluate(callbackScoped).mediaPlaybackCommands.count == 1
        callbackScoped.discardLayerMutations()
        for (key, body) in [
            ("throw_rollback", "thisLayer.play();throw Error('failed');"),
            ("mixed_budget", "for(let i=0;i<33;i++)thisLayer.play();for(let i=0;i<32;i++)thisScene.getLayer('video').getVideoTexture().pause();return v;"),
            ("caught_budget", "try{for(let i=0;i<65;i++)thisLayer.play();}catch(e){}return v;"),
            ("argument_rejected", "thisLayer.play(true);return v;"),
            ("emit_remains_particle_only", "thisLayer.emitParticles(1);return v;")
        ] {
            let failed = try owner("export function update(v){" + body + "}")
            do { _ = try evaluate(failed); result[key] = false }
            catch { result[key] = mwx_scene_quickjs_owner_media_playback_command_count(failed.handle) == 0 }
            failed.discardLayerMutations()
        }
        for destination in ["sound", "video"] {
            let target = destination == "sound" ? "thisScene.getLayer('sound')" : "thisScene.getLayer('video').getVideoTexture()"
            for action in ["play", "pause", "stop"] {
                let readOnly = try boolOwner("""
                    export function update(v){
                        let media=\(target);
                        if(typeof media.isPlaying() !== 'boolean')throw Error('prepared query unavailable');
                        try { media.\(action)(); throw Error('control accepted'); }
                        catch(e) { if(!(e instanceof TypeError)) throw e; }
                        return v;
                    }
                    """)
                // A caught permission TypeError must leave no command and no
                // overflow fuse: the read-only owner can still return a value.
                let denied = try evaluateBool(readOnly)
                result["readonly_\(destination)_\(action)"] = denied.value == .bool(true)
                    && denied.mediaPlaybackCommands.isEmpty
                    && mwx_scene_quickjs_owner_media_playback_command_count(readOnly.handle) == 0
                readOnly.discardLayerMutations()
            }
        }
        let readQuery = try boolOwner("""
            export function update(v){
                return !thisScene.getLayer('sound').isPlaying()
                    && thisScene.getLayer('video').getVideoTexture().isPlaying() && v;
            }
            """)
        let queried = try evaluateBool(readQuery)
        result["readonly_queries_available"] = queried.value == .bool(true)
            && queried.mediaPlaybackCommands.isEmpty
        readQuery.discardLayerMutations()
        let stateful = try boolOwner("""
            export function update(v){
                thisLayer.play();thisLayer.pause();thisLayer.stop();
                let video=thisScene.getLayer('video').getVideoTexture();
                video.play();video.pause();video.stop();return v;
            }
            """, stateful: true)
        let controlled = try evaluateBool(stateful)
        result["stateful_bool_controls_media"] = controlled.value == .bool(true)
            && controlled.mediaPlaybackCommands.map(\.destination) == [.soundLayer,.soundLayer,.soundLayer,.videoTexture,.videoTexture,.videoTexture]
            && controlled.mediaPlaybackCommands.map(\.action) == [.play,.pause,.stop,.play,.pause,.stop]
            && controlled.mediaPlaybackCommands.map(\.videoSourceIncarnation) == [nil,nil,nil,UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,UUID(uuidString:"00000000-0000-0000-0000-000000000002")!,UUID(uuidString:"00000000-0000-0000-0000-000000000002")!]
        stateful.discardLayerMutations()
        var creator: SceneScriptValueOwner? = try owner("""
            let cached;
            export function init(v){cached=thisScene.getLayer('sound');
                shared.playTrack=()=>{cached.play();if(cached.isPlaying()!==true)throw Error('play');
                    cached.pause();if(cached.isPlaying()!==false)throw Error('pause');
                    cached.stop();if(cached.isPlaying()!==false)throw Error('stop');
                    cached.play();return cached.isPlaying();};
                shared.trackPlaying=()=>cached.isPlaying();return v;}
            export function update(v){return v;}
            """)
        _ = try evaluate(creator!); creator!.discardLayerMutations()
        let borrowed = try boolOwner("export function update(v){if(shared.playTrack()!==true)throw Error('projection');return v;}",
            stateful: true, layerID: 2)
        let sharedEvaluation = try evaluateBool(borrowed)
        let sharedCommands = sharedEvaluation.mediaPlaybackCommands
        result["shared_sound_order"] = sharedEvaluation.value == .bool(true)
            && sharedCommands.map(\.action) == [.play,.pause,.stop,.play]
            && sharedCommands.allSatisfy { $0.layerID == 1 && $0.destination == .soundLayer }
        result["shared_executing_owner_journal"] = mwx_scene_quickjs_owner_media_playback_command_count(borrowed.handle) == 4
            && mwx_scene_quickjs_owner_media_playback_command_count(creator!.handle) == 0
        result["shared_evaluation_has_no_player_effect"] = registry.sceneScriptSnapshots()[1] == false
        borrowed.discardLayerMutations()
        _ = try registry.apply(sharedCommands).get()
        result["shared_commands_reach_real_player"] = waitPlaying()
        _ = try registry.apply([.init(layerID: 1, action: .stop, destination: .soundLayer)]).get()
        try publish(registry.sceneScriptSnapshots())
        let readonlyBorrower = try boolOwner("""
            export function update(v){const track=thisScene.getLayer('sound');if(track.isPlaying()!==false)throw Error('snapshot');
                let denied=false;try{track.play();}catch(e){denied=e instanceof TypeError;}
                if(!denied)throw Error('readonly control');return v;}
            """, layerID: 2)
        let readonlyShared = try evaluateBool(readonlyBorrower)
        result["readonly_sound_after_shared_commit"] = readonlyShared.value == .bool(true)
            && readonlyShared.mediaPlaybackCommands.isEmpty && registry.sceneScriptSnapshots()[1] == false
        readonlyBorrower.discardLayerMutations()
        let sharedThrow = try boolOwner("export function update(v){shared.playTrack();throw Error('shared failure');}",
            stateful: true, layerID: 2)
        do { _ = try evaluateBool(sharedThrow); result["shared_throw_rollback"] = false }
        catch { result["shared_throw_rollback"] = mwx_scene_quickjs_owner_media_playback_command_count(sharedThrow.handle) == 0
            && registry.sceneScriptSnapshots()[1] == false }
        sharedThrow.discardLayerMutations()
        _ = try evaluateBool(borrowed); borrowed.discardLayerMutations()
        result["shared_discard_rollback"] = mwx_scene_quickjs_owner_media_playback_command_count(borrowed.handle) == 0
            && registry.sceneScriptSnapshots()[1] == false
        let healthy = try boolOwner("export function update(v){return typeof shared.trackPlaying()==='boolean'&&!shared.trackPlaying()&&v;}", stateful: true, layerID: 2)
        let peer = try evaluateBool(healthy)
        result["shared_healthy_peer_after_failure"] = peer.value == .bool(true) && peer.mediaPlaybackCommands.isEmpty
        healthy.discardLayerMutations()
        creator = nil
        let retiredCreator = try evaluateBool(borrowed)
        result["shared_creator_retired_target_live"] = retiredCreator.mediaPlaybackCommands.map(\.action) == [.play,.pause,.stop,.play]
            && retiredCreator.mediaPlaybackCommands.allSatisfy { $0.layerID == 1 && $0.destination == .soundLayer }
        borrowed.discardLayerMutations()
        let held = try owner("""
            let sound;
            export function init(v){sound=thisLayer;return v;}
            export function update(v){
                try { sound.play(); return v; }
                catch(e) { return 0; }
            }
            """)
        _ = try evaluate(held); held.discardLayerMutations()
        try publish([:], pending: true)
        let removed = try evaluate(held)
        result["removed_source_unavailable"] = removed.value == .scalar(0)
            && removed.mediaPlaybackCommands.isEmpty
        held.discardLayerMutations()
        let missingShared = try boolOwner("""
            export function update(v){let refused=false;try{shared.playTrack();}
                catch(e){refused=e instanceof TypeError;}return refused&&v;}
            """, stateful: true, layerID: 2)
        let missing = try evaluateBool(missingShared)
        result["shared_retired_reference_source_unavailable"] = missing.value == .bool(true) && missing.mediaPlaybackCommands.isEmpty
        missingShared.discardLayerMutations()
        domain.discardCommittedLayerSnapshot()
        result["snapshot_rollback_restores_availability"] = try evaluate(held).mediaPlaybackCommands.count == 1
        held.discardLayerMutations()
        result["shared_source_rollback_restores_reference"] = try evaluateBool(borrowed).mediaPlaybackCommands.count == 4
        borrowed.discardLayerMutations()
        let renamedCreator = try owner("""
            export function update(seed){const renamed=thisScene.enumerateLayers().find(item=>item.id===1);
                shared.renamedMusic=()=>{renamed.play();if(!renamed.isPlaying())throw Error('renamed play');
                    renamed.pause();if(renamed.isPlaying())throw Error('renamed pause');renamed.stop();return !renamed.isPlaying();};return seed;}
            """)
        _ = try evaluate(renamedCreator); renamedCreator.discardLayerMutations()
        let renamedCaller = try boolOwner("export function update(seed){return shared.renamedMusic()&&seed;}", stateful: true, layerID: 2)
        let renamed = try evaluateBool(renamedCaller)
        result["shared_renamed_equivalent_lookup"] = renamed.value == .bool(true)
            && renamed.mediaPlaybackCommands.map(\.action) == [.play,.pause,.stop]
            && renamed.mediaPlaybackCommands.allSatisfy { $0.layerID == 1 && $0.destination == .soundLayer }
            && mwx_scene_quickjs_owner_media_playback_command_count(renamedCreator.handle) == 0
        renamedCaller.discardLayerMutations()
        result["live-registry-keeps-source-through-playback-stop"] = registryHasSourcesAfterStart && registry.hasSources
        registry.retire(layerIDs: [1])
        result["last-source-retirement-clears-current-process-demand"] = !registry.hasSources
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneSoundScriptCommandsTests(unittest.TestCase):
    def test_vm_transactions_and_actual_player(self):
        with tempfile.TemporaryDirectory(prefix="mwx-sound-script-") as directory:
            root = Path(directory)
            audio = root / "fixture.wav"
            with wave.open(str(audio), "wb") as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(44100)
                stream.writeframes(b"\0\0" * 44100)
            binary = compile_vector_harness(root, HARNESS, "sound-script", extra_swift_sources=(
                SCENE / "Systems/Media/SceneSoundPlaybackRegistry.swift",),
                whole_module_optimization=True,
            )
            run = subprocess.run([str(binary), str(audio)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            facts = json.loads(run.stdout)
            for key, value in facts.items():
                with self.subTest(key=key):
                    self.assertTrue(value, run.stderr)
