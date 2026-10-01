#!/usr/bin/env python3
"""RF03 behavior against the real Swift simulator and authored JSON parser."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from test_scene_particle_simulator import SWIFT_SOURCES

HARNESS = r'''
import Foundation
@main enum Harness {
    static func main() throws {
        func make(start: Double = 0, lifetime: Double = 10, historyMotion: Bool = false,
                  initial: SceneParticlePlaybackSnapshot = .init(),
                  emitter: [String: Any]? = nil, multiple: Bool = false, children: [[String: Any]] = []) throws -> SceneParticleSimulator {
            let root: [String: Any] = ["material": "p.json", "maxcount": 100, "starttime": start,
                "emitter": Array(repeating: emitter ?? ["name": "boxrandom", "rate": 4, "duration": 1, "distancemax": 2], count: multiple ? 2 : 1),
                "initializer": [["name": "lifetimerandom", "min": lifetime, "max": lifetime]],
                "operator": historyMotion ? [["name": "oscillateposition", "frequencymin": 2, "frequencymax": 2,
                    "scalemin": "8 4 0", "scalemax": "8 4 0", "phasemin": 0, "phasemax": 0, "mask": "1 0.5 0"]] : [],
                "children": children, "renderer": [["name": "sprite"]]]
            return SceneParticleSimulator(definition: try SceneParticleDefinitionParser().parse(root: root),
                initialPlayback: initial, seed: 81, fixedTimeStep: 0.25,
                stepSnapshotPolicy: .init(interval: 0.25, maximumSnapshots: 8), trailHistoryCapacity: 4)
        }
        func command(_ sim: SceneParticleSimulator, _ action: SceneParticlePlaybackAction, _ revision: UInt64) {
            sim.applyPlaybackTransition(.init(layerID: 42, action: action, revision: revision))
        }
        var result: [String: Bool] = [:]
        let paused = try make(start: 0.5)
        let prepared = paused.particles
        command(paused, .pause, 1)
        paused.advance(by: 0.25)
        result["pauseRetainsPreparedLiveWithoutBirth"] = !prepared.isEmpty
            && paused.particles.map(\.id) == prepared.map(\.id)
            && paused.particles[0].age > prepared[0].age
        paused.advance(by: 12)
        result["pausedParticlesDieAndTimeContinues"] = paused.particles.isEmpty && paused.simulationTime > 12
        let stop = try make(start: 0.5, historyMotion: true)
        let before = stop.frameSnapshot()
        result["stopStartsWithRealCachesAndHistory"] = !before.positionOscillationCache.isEmpty
            && !before.normalizedLives.isEmpty && !stop.trailDirectionSamples().isEmpty
        var recorded = before.stepSnapshotRecorder
        result["stopStartsWithRealStepSnapshots"] = recorded?.consume(particles: before.particles).isEmpty == false
        command(stop, .stop, 1)
        let after = stop.frameSnapshot()
        result["stopClearsLiveEventsAndHistory"] = stop.particles.isEmpty
            && stop.renderParticlesForCurrentAdvance().isEmpty && stop.birthEvents.isEmpty && stop.deathEvents.isEmpty
            && stop.trailDirectionSamples().isEmpty && stop.consumeStepSnapshots().isEmpty
            && after.normalizedLives.isEmpty && after.positionOscillationCache.isEmpty
        result["stopPreservesTimeIDRandomAccumulator"] = before.simulationTime == after.simulationTime
            && before.nextParticleID == after.nextParticleID && before.random.state == after.random.state
            && before.accumulator == after.accumulator
        command(stop, .play, 2)
        stop.advance(by: 0.25)
        result["stopPlayRearmsWithoutIDReset"] = stop.particles.count == 1 && stop.particles[0].id == before.nextParticleID
        let transient = try make(lifetime: 0.1)
        transient.advance(by: 0.5)
        result["stopStartsWithRealTransientEvents"] = !transient.renderParticlesForCurrentAdvance().isEmpty
            && !transient.birthEvents.isEmpty && !transient.deathEvents.isEmpty
        command(transient, .stop, 1)
        result["stopClearsRealTransientEvents"] = transient.renderParticlesForCurrentAdvance().isEmpty
            && transient.birthEvents.isEmpty && transient.deathEvents.isEmpty
        let finished = try make()
        finished.advance(by: 1.125)
        let old = finished.frameSnapshot()
        command(finished, .play, 1)
        let rearmed = finished.frameSnapshot()
        result["finishedPlayPreservesLiveAndClocks"] = old.particles == rearmed.particles
            && old.random.state == rearmed.random.state && old.nextParticleID == rearmed.nextParticleID
            && old.accumulator == rearmed.accumulator && old.simulationTime == rearmed.simulationTime
            && finished.playbackObservation?.emissionPending == true
        finished.advance(by: 0.125)
        result["finishedPlayActuallyBirths"] = finished.particles.count == old.particles.count + 1
            && finished.particles.last?.id == old.nextParticleID
        let randomReference = try make(emitter: ["name": "boxrandom", "rate": 4, "duration": 2, "distancemax": 2])
        randomReference.advance(by: 1.25)
        result["finishedPlayPreservesFutureRandomSequence"] = finished.particles == randomReference.particles
        let interrupted = try make()
        interrupted.advance(by: 0.75)
        command(interrupted, .stop, 1); command(interrupted, .pause, 2); command(interrupted, .play, 3)
        interrupted.advance(by: 0.75)
        result["stopPausePlayRestartsFullSchedule"] = interrupted.particles.count == 3
        let frozen = finished.frameSnapshot()
        command(finished, .stop, 1)
        result["consumedRevisionNotReplayed"] = finished.particles == frozen.particles
        for intent in [SceneParticlePlaybackIntent.paused, .stopped] {
            let rebuilt = try make(start: 0.5, initial: .init(intent: intent, revision: 9))
            result["rebuild-\(intent)-noWarmupBirth"] = rebuilt.particles.isEmpty
                && rebuilt.frameSnapshot().nextParticleID == 0 && rebuilt.playback.revision == 9
            rebuilt.advance(by: 0.5)
            result["rebuild-\(intent)-remainsEmpty"] = rebuilt.particles.isEmpty
        }
        let periodic: [String: Any] = ["name": "boxrandom", "flags": 4, "rate": 4,
            "minperiodicduration": 0.5, "maxperiodicduration": 0.5,
            "minperiodicdelay": 0.5, "maxperiodicdelay": 0.5]
        let period = try make(emitter: periodic), reference = try make(emitter: periodic)
        period.advance(by: 0.25); reference.advance(by: 0.25)
        command(period, .pause, 1); period.advance(by: 0.75); command(period, .play, 2)
        period.advance(by: 0.25); reference.advance(by: 0.25)
        result["periodicResumesSchedule"] = period.particles.map(\.id) == reference.particles.map(\.id)
            && period.frameSnapshot().random.state == reference.frameSnapshot().random.state
        let zero = try make(emitter: ["name": "boxrandom", "rate": 0])
        result["zeroWork"] = zero.playbackObservation?.rearmHasWork == false
            && zero.playbackObservation?.emissionPending == false
        var random = periodic; random["maxperiodicduration"] = 1
        result["randomScheduleUnavailable"] = try make(emitter: random).playbackObservation == nil
        result["authoredChildrenUnavailable"] = try make(children: [["name": "missing-child.json"]]).playbackObservation == nil
        result["multipleEmittersUnavailable"] = try make(multiple: true).playbackObservation == nil
        result["unknownEmitterUnavailable"] = try make(emitter: ["name": "futureemitter", "rate": 0]).playbackObservation == nil
        let burst = try make(emitter: ["name": "boxrandom", "rate": 0, "instantaneous": 2, "delay": 0.5])
        burst.advance(by: 0.25)
        result["delayedBurstPending"] = burst.particles.isEmpty && burst.playbackObservation?.emissionPending == true
        command(burst, .pause, 1); burst.advance(by: 1); command(burst, .play, 2)
        burst.advance(by: 0.5)
        result["delayedBurstResumes"] = burst.particles.count == 2 && burst.playbackObservation?.emissionPending == false
        let burstIDs = burst.particles.map(\.id)
        command(burst, .play, 3); burst.advance(by: 0.5)
        result["rearmReplaysInitialDelay"] = burst.particles.map(\.id) == burstIDs
        burst.advance(by: 0.25)
        result["burstRearmsOnceWithLiveRetained"] = burst.particles.count == 4 && Array(burst.particles.prefix(2).map(\.id)) == burstIDs
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

class SceneParticlePlaybackSimulatorTests(unittest.TestCase):
    def test_authored_playback_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="mwx-rf03-simulator-") as temporary:
            directory = Path(temporary)
            harness = directory / "Harness.swift"
            harness.write_text(HARNESS)
            binary = directory / "fixture"
            compile_result = subprocess.run([shutil.which("swiftc"), *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            results = json.loads(run.stdout)
            for name, passed in results.items():
                with self.subTest(name=name):
                    self.assertTrue(passed, name)

if __name__ == "__main__":
    unittest.main()
