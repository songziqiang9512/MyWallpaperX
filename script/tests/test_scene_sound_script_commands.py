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
struct SceneSoundPlaybackProgram {
    struct Resource {
        let url: URL
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
        let authoredVolume = 0.0
        let volumePropertyKey: String? = nil
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
            .init(layerID: 1, resources: [.init(url: URL(fileURLWithPath: CommandLine.arguments[1]),
                displayPath: "fixture.wav")])]), epoch: 1)
        registry.start(paused: false, userValues: [:]); defer { registry.stop() }
        let domain = try SceneScriptQuickJSDomain(); try domain.configureLayerCatalog(descriptor)
        func publish(_ sound: [Int: Bool], pending: Bool = false) throws {
            try domain.publishLayerSnapshot(.empty(frameIndex: 0), descriptor: descriptor,
                videoSnapshots: [2: .init(layerID: 2, duration: 5, rate: 1, loop: true,
                    currentTime: 0, isPlaying: true, endedGeneration: 0)],
                soundPlaybackSnapshots: sound, runtimeFieldLayerIDs: [], awaitingHostFrameOutcome: pending)
        }
        func owner(_ source: String) throws -> SceneScriptValueOwner {
            try SceneScriptValueOwner(domain: domain, source: source, target: .layer(layerID: 1, field: .alpha),
                valueType: .scalar, effectNames: [], allowsStatefulLayerSideEffects: true, generation: 1, budget: .default)
        }
        func boolOwner(_ source: String, stateful: Bool = false) throws -> SceneScriptValueOwner {
            try SceneScriptValueOwner(domain: domain, source: source,
                target: .layer(layerID: 1, field: .visibility), valueType: .bool,
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
        stateful.discardLayerMutations()
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
        domain.discardCommittedLayerSnapshot()
        result["snapshot_rollback_restores_availability"] = try evaluate(held).mediaPlaybackCommands.count == 1
        held.discardLayerMutations()
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
                SCENE / "Systems/Media/SceneSoundPlaybackRegistry.swift",))
            run = subprocess.run([str(binary), str(audio)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            facts = json.loads(run.stdout)
            self.assertEqual(len(facts), 20)
            for key, value in facts.items():
                with self.subTest(key=key):
                    self.assertTrue(value, run.stderr)
