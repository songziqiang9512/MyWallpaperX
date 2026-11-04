#!/usr/bin/env python3
"""RF03 behavior against the real Swift simulator and authored JSON parser."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from script.tests.test_scene_particle_simulator import SWIFT_SOURCES

HARNESS = r'''
import Foundation
@main enum Harness {
    static func main() throws {
        func make(start: Double = 0, lifetime: Double = 10, cacheMotion: Bool = false,
                  initial: SceneParticlePlaybackSnapshot = .init(),
                  maximum: Int = 100, emitter: [String: Any]? = nil, multiple: Bool = false, children: [[String: Any]] = []) throws -> SceneParticleSimulator {
            let root: [String: Any] = ["material": "p.json", "maxcount": maximum, "starttime": start,
                "emitter": Array(repeating: emitter ?? ["name": "boxrandom", "rate": 4, "duration": 1, "distancemax": 2], count: multiple ? 2 : 1),
                "initializer": [["name": "lifetimerandom", "min": lifetime, "max": lifetime]],
                "operator": cacheMotion ? [["name": "oscillateposition", "frequencymin": 2, "frequencymax": 2,
                    "scalemin": "8 4 0", "scalemax": "8 4 0", "phasemin": 0, "phasemax": 0, "mask": "1 0.5 0"]] : [],
                "children": children, "renderer": [["name": "sprite"]]]
            return SceneParticleSimulator(definition: try SceneParticleDefinitionParser().parse(root: root),
                initialPlayback: initial, seed: 81, fixedTimeStep: 0.25,
                stepSnapshotPolicy: .init(interval: 0.25, maximumSnapshots: 8))
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
        let stop = try make(start: 0.5, cacheMotion: true)
        let before = stop.frameSnapshot()
        result["stopStartsWithRealCaches"] = !before.positionOscillationCache.isEmpty
            && !before.normalizedLives.isEmpty
        var recorded = before.stepSnapshotRecorder
        result["stopStartsWithRealStepSnapshots"] = recorded?.consume(particles: before.particles).isEmpty == false
        command(stop, .stop, 1)
        let after = stop.frameSnapshot()
        result["stopClearsLiveEventsAndHistory"] = stop.particles.isEmpty
            && stop.renderParticlesForCurrentAdvance().isEmpty && stop.birthEvents.isEmpty && stop.deathEvents.isEmpty
            && stop.consumeStepSnapshots().isEmpty
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
        for duration in [Optional<Double>.none, 0] {
            var emitter: [String: Any] = ["name": "boxrandom", "rate": 2, "delay": 0.5, "distancemax": 2]
            if let duration { emitter["duration"] = duration }
            let continuous = try make(emitter: emitter)
            let label = duration == nil ? "absent" : "zero"
            result["continuous-availability-\(label)"] = continuous.playbackObservation?.rearmHasWork == true
            continuous.advance(by: 0.75)
            let pending = continuous.frameSnapshot()
            command(continuous, .pause, 1)
            continuous.advance(by: 1)
            command(continuous, .play, 2)
            continuous.advance(by: 0.25)
            result["continuous-remainder-\(label)"] = pending.particles.isEmpty
                && continuous.particles.count == 1 && continuous.playbackObservation?.emissionPending == true
            command(continuous, .play, 3)
            continuous.advance(by: 0.5)
            result["continuous-repeat-play-\(label)"] = continuous.particles.count == 2
            command(continuous, .stop, 4)
            result["continuous-stop-\(label)"] = continuous.particles.isEmpty
                && continuous.playbackObservation?.intent == .stopped
            command(continuous, .play, 5)
            continuous.advance(by: 0.5)
            result["continuous-stop-rearms-delay-\(label)"] = continuous.particles.isEmpty
            continuous.advance(by: 0.5)
            result["continuous-restart-birth-\(label)"] = continuous.particles.count == 1
                && continuous.particles[0].id == 2
        }
        for duration in [-1.0, Double.infinity, Double.nan] {
            result["invalid-duration-\(duration)"] = try make(emitter: ["name": "boxrandom", "rate": 2, "duration": duration]).playbackObservation == nil
        }
        for (index, duration) in [true, "garbage", [1, 2], ["wrong": 1]].enumerated() {
            result["malformed-duration-\(index)"] = try make(emitter: ["name": "boxrandom", "rate": 2, "duration": duration]).playbackObservation == nil
        }
        let noCapacity = try make(maximum: 0, emitter: ["name": "boxrandom", "rate": 2])
        command(noCapacity, .stop, 1); command(noCapacity, .play, 2); noCapacity.advance(by: 1)
        result["continuous-zero-capacity"] = noCapacity.particles.isEmpty
            && noCapacity.playbackObservation?.rearmHasWork == false
        let nullDuration = try make(emitter: ["name": "boxrandom", "rate": 2, "duration": NSNull()])
        result["null-duration-absent"] = nullDuration.playbackObservation?.rearmHasWork == true
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

        let continuousEmitter: [String: Any] = ["name": "boxrandom", "rate": 4, "distancemax": 2]
        let visibility = try make(start: 2, cacheMotion: true,
            initial: .init(revision: 7), emitter: continuousEmitter)
        let visibilityReference = try make(start: 2, cacheMotion: true,
            initial: .init(revision: 7), emitter: continuousEmitter)
        visibility.advance(by: 0.125); visibilityReference.advance(by: 0.125)
        let visibleBefore = visibility.frameSnapshot()
        var visibilityRecorded = visibleBefore.stepSnapshotRecorder
        result["visibilityStartsWithRealWarmupAndResidual"] = visibleBefore.particles.count == 8
            && visibleBefore.simulationTime == 2 && visibleBefore.accumulator == 0.125
            && !visibleBefore.positionOscillationCache.isEmpty
            && visibilityRecorded?.consume(particles: visibleBefore.particles).isEmpty == false
        visibility.restartPopulationForVisibility()
        let visibleReset = visibility.frameSnapshot()
        result["visibilityClearsPopulationAndRetainedRenderHistory"] = visibility.particles.isEmpty
            && visibility.renderParticlesForCurrentAdvance().isEmpty
            && visibility.birthEvents.isEmpty && visibility.deathEvents.isEmpty
            && visibility.consumeStepSnapshots().isEmpty
            && visibleReset.normalizedLives.isEmpty && visibleReset.positionOscillationCache.isEmpty
        result["visibilityPreservesClockRNGMonotonicIDAndRevision"] = visibleReset.simulationTime == visibleBefore.simulationTime
            && visibleReset.accumulator == visibleBefore.accumulator
            && visibleReset.random.state == visibleBefore.random.state
            && visibleReset.nextParticleID == visibleBefore.nextParticleID
            && visibleReset.playback == visibleBefore.playback
        visibility.advance(by: 0.125); visibilityReference.advance(by: 0.125)
        result["visibilityShowDoesNotRepeatStarttimeWarmup"] = visibility.particles.count == 1
            && visibility.particles[0].id == visibleBefore.nextParticleID
            && visibility.particles[0].age == 0.25 && visibility.simulationTime == 2.25
            && visibility.frameSnapshot().nextParticleID == visibleBefore.nextParticleID + 1
        result["visibilityFutureBirthKeepsTheRandomSequence"] = visibility.particles.first == visibilityReference.particles.last
            && visibility.frameSnapshot().random.state == visibilityReference.frameSnapshot().random.state
        for action in [SceneParticlePlaybackAction.pause, .stop] {
            let held = try make(start: 0.5, emitter: continuousEmitter)
            command(held, action, 9)
            let before = held.frameSnapshot()
            held.restartPopulationForVisibility()
            let restarted = held.frameSnapshot()
            held.advance(by: 0.5)
            result["visibilityRetains-\(action)-IntentAndRevision"] = held.particles.isEmpty
                && held.playback == before.playback && held.playback.revision == 9
                && restarted.random.state == before.random.state
                && restarted.nextParticleID == before.nextParticleID
                && restarted.simulationTime == before.simulationTime
                && held.simulationTime == before.simulationTime + 0.5
        }
        let exhausted = try make(start: 2, initial: .init(revision: 13))
        let exhaustedBefore = exhausted.frameSnapshot()
        result["visibilityFiniteEmitterReallyFinished"] = !exhaustedBefore.particles.isEmpty
            && exhausted.hasFinishedEmission && exhausted.playback.intent == .playing
        exhausted.restartPopulationForVisibility()
        let exhaustedReset = exhausted.frameSnapshot()
        exhausted.advance(by: 0.5)
        result["visibilityFinishedDurationDoesNotRestartEmission"] = exhausted.particles.isEmpty
            && exhausted.birthEvents.isEmpty && exhausted.hasFinishedEmission
            && exhausted.playbackObservation?.emissionPending == false
            && exhaustedReset.emitters.map(\.elapsed) == exhaustedBefore.emitters.map(\.elapsed)
            && exhaustedReset.emitters.map(\.emittedInstantaneous) == exhaustedBefore.emitters.map(\.emittedInstantaneous)
            && exhausted.frameSnapshot().nextParticleID == exhaustedBefore.nextParticleID
            && exhausted.frameSnapshot().random.state == exhaustedBefore.random.state
            && exhausted.playback == exhaustedBefore.playback

        // This is the real simulator gate used for retained child systems.
        // It verifies advancement without pretending to exercise Runtime topology.
        let childRoot: [String: Any] = ["material": "p.json", "maxcount": 32,
            "emitter": [["name": "sphererandom", "rate": 4, "instantaneous": 1,
                         "distancemin": 0, "distancemax": 0]],
            "initializer": [["name": "lifetimerandom", "min": 6, "max": 6],
                            ["name": "velocityrandom", "min": "20 0 0", "max": "20 0 0"]],
            "operator": [["name": "movement", "flags": 1, "gravity": "0 0 0"]],
            "renderer": [["name": "sprite"]]]
        let retained = SceneParticleSimulator(definition: try SceneParticleDefinitionParser().parse(root: childRoot),
            initialPlayback: .init(revision: 5), seed: 81, fixedTimeStep: 0.25)
        retained.advance(by: 0.5)
        _ = retained.consumeBirthEvents(); _ = retained.consumeDeathEvents()
        let retainedBefore = retained.frameSnapshot()
        retained.advance(by: 1, allowsEmission: false)
        let hidden = retained.frameSnapshot()
        result["hiddenEmissionGateKeepsIDsIntentAndRNG"] = !retainedBefore.particles.isEmpty
            && hidden.particles.map(\.id) == retainedBefore.particles.map(\.id)
            && hidden.nextParticleID == retainedBefore.nextParticleID
            && hidden.random.state == retainedBefore.random.state
            && hidden.playback == retainedBefore.playback && retained.birthEvents.isEmpty
        result["hiddenEmissionGateAdvancesExistingPositionAndAge"] = zip(hidden.particles, retainedBefore.particles).allSatisfy { current, previous in
            abs(current.age - previous.age - 1) < 1e-12
                && abs(current.position.x - previous.position.x - 20) < 1e-12
        } && hidden.simulationTime == retainedBefore.simulationTime + 1
        retained.advance(by: 0.25)
        result["hiddenEmissionGateResumesBirthsWithoutClearingSurvivors"] = retained.particles.count == retainedBefore.particles.count + 1
            && retained.particles.last?.id == retainedBefore.nextParticleID
            && Array(retained.particles.prefix(retainedBefore.particles.count).map(\.id)) == retainedBefore.particles.map(\.id)
        _ = retained.consumeBirthEvents(); _ = retained.consumeDeathEvents()
        let dyingIDs = retained.particles.map(\.id)
        retained.advance(by: 10, allowsEmission: false)
        result["hiddenEmissionGateAllowsNaturalDeathWithoutNewBirths"] = retained.particles.isEmpty
            && retained.birthEvents.isEmpty && retained.deathEvents.map(\.id).sorted() == dyingIDs.sorted()
            && retained.frameSnapshot().nextParticleID == retainedBefore.nextParticleID + 1
            && retained.playback == retainedBefore.playback

        func explicit(_ sim: SceneParticleSimulator, count: Int,
                      context: SceneParticleSimulator.EmissionContext = .init()) throws -> SceneParticleSimulator.PlaybackCandidate {
            try sim.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,
                revision:sim.playback.revision+1,count:count),context)],charge:{_,_ in},release:{_ in})
        }
        func radial(_ bounds: [String: Any], renamed: Bool = false, peer: Bool = false,
                    streaming: Bool = false, omitsSign: Bool = false,
                    initial: SceneParticlePlaybackSnapshot = .init()) throws -> SceneParticleSimulator {
            var emitter: [String: Any] = ["id": renamed ? 823 : 17, "name": "sphererandom",
                "origin": "4 2 0", "directions": "1 0 0", "sign": "1 0 0",
                "distancemin": 8, "distancemax": 8, "rate": streaming ? 4 : 0,
                "instantaneous": streaming ? 0 : 4]
            emitter.merge(bounds) { _, authored in authored }
            if omitsSign { emitter.removeValue(forKey: "sign") }
            var emitters = [emitter]
            if peer { emitters.append(["name": "boxrandom", "rate": 4,
                "origin": "40 2 0", "distancemin": 0, "distancemax": 0]) }
            let root: [String: Any] = ["material": renamed ? "other/snow.json" : "p.json",
                "maxcount": 32, "emitter": emitters,
                "initializer": [["id": renamed ? 104 : 5, "name": "lifetimerandom", "min": 10, "max": 10]],
                "operator": [["name": "movement", "gravity": "0 0 0", "drag": 0]],
                "renderer": [["name": "sprite"]]]
            let definition = try SceneParticleDefinitionParser().parse(
                data: JSONSerialization.data(withJSONObject: root))
            return SceneParticleSimulator(definition: definition, initialPlayback: initial,
                                          seed: 81, fixedTimeStep: 0.25)
        }
        let fixedSpeeds: [(String, Double, Double)] = [
            ("inward", -4, 11), ("above-old-cap", 1_000_001, 250_012.25),
            ("negative-above-old-cap", -1_000_001, -249_988.25)]
        for (label, speed, expectedX) in fixedSpeeds {
            let sim = try radial(["speedmin": speed, "speedmax": speed])
            sim.advance(by: 0.25)
            result["signed-speed-\(label)-real-birth-and-motion"] = sim.particles.count == 4
                && sim.birthEvents.count == 4 && sim.birthEvents.allSatisfy {
                    $0.position == SIMD3(12, 2, 0) && $0.velocity == SIMD3(speed, 0, 0)
                } && sim.particles.allSatisfy {
                    $0.position == SIMD3(expectedX, 2, 0) && $0.age == 0.25
                        && Float($0.velocity.x).isFinite && Float($0.position.x).isFinite
                }
        }
        let equivalentSpeeds: [(String, [String: Any], [String: Any], Bool)] = [
            ("negative-reversed", ["speedmin": 0, "speedmax": -1], ["speedmin": -1, "speedmax": 0], false),
            ("mixed-reversed", ["speedmin": 1, "speedmax": -1], ["speedmin": -1, "speedmax": 1], false),
            ("min-only-positive", ["speedmin": 1], ["speedmin": 0, "speedmax": 1], false),
            ("min-only-negative", ["speedmin": -1], ["speedmin": -1, "speedmax": 0], false),
            ("max-only-negative", ["speedmax": -1], ["speedmin": -1, "speedmax": 0], false),
            ("max-only-positive", ["speedmax": 4], ["speedmin": 0, "speedmax": 4], false),
            ("both-omitted", [:], ["speedmin": 0, "speedmax": 0], false),
            // Only the cold numeric wrapper is compared; this does not claim a live property writer.
            ("renamed-wrapper", ["speedmin": ["user": "winterDrift", "value": -1], "speedmax": "0"],
             ["speedmin": -1, "speedmax": 0], true)]
        for (label, bounds, ordered, renamed) in equivalentSpeeds {
            let actual = try radial(bounds, renamed: renamed), reference = try radial(ordered)
            actual.advance(by: 0.25); reference.advance(by: 0.25)
            result["signed-speed-\(label)-same-state-events-and-rng"] = actual.particles.count == 4
                && actual.particles == reference.particles && actual.birthEvents == reference.birthEvents
                && actual.frameSnapshot().random.state == reference.frameSnapshot().random.state
                && (!renamed || (actual.definition.materialPath != reference.definition.materialPath
                    && actual.definition.emitters[0].id != reference.definition.emitters[0].id))
        }
        let unsafeSpeeds: [(String, [String: Any])] = [
            ("nan-min", ["speedmin": "nan", "speedmax": 0]),
            ("nan-max", ["speedmin": 0, "speedmax": "nan"]),
            ("infinity-min", ["speedmin": "inf", "speedmax": 0]),
            ("infinity-max", ["speedmin": 0, "speedmax": "inf"]),
            ("negative-infinity-min", ["speedmin": "-inf", "speedmax": 0]),
            ("negative-infinity-max", ["speedmin": 0, "speedmax": "-inf"]),
            ("final-float-overflow", ["speedmin": "1e39", "speedmax": "1e39"])]
        for (label, bounds) in unsafeSpeeds {
            let sim = try radial(bounds, peer: true, streaming: true)
            sim.advance(by: 0.25)
            let first = sim.frameSnapshot()
            _ = sim.consumeBirthEvents()
            sim.advance(by: 0.25)
            result["signed-speed-\(label)-rejects-only-birth-keeps-peer-and-survivor"] =
                first.particles.count == 1 && sim.particles.count == 2
                && sim.particles[0].id == first.particles[0].id
                && sim.particles[0].age == first.particles[0].age + 0.25
                && sim.particles.allSatisfy { $0.position == SIMD3(40, 2, 0) && $0.velocity == .zero }
                && sim.birthEvents.count == 1 && sim.birthEvents[0].position == SIMD3(40, 2, 0)
            result["signed-speed-\(label)-rejects-at-actual-numeric-boundary"] =
                (sim.definition.emitters[0].boundedSpeedRange != nil) == (label == "final-float-overflow")
        }
        let neutralSign = try radial(["sign": 0, "instantaneous": 32])
        neutralSign.advance(by: 0.25)
        result["sign-unit-axis-neutral-control-has-both-sides"] = neutralSign.particles.count == 32
            && Set(neutralSign.birthEvents.map { $0.position.x }) == Set([-4.0, 12.0])
        let equivalentSigns: [(String, Any?, Any, String, Bool)] = [
            ("positive-ten", "10 0 0", "1 0 0", "1 0 0", false),
            ("negative-ten", "-10 0 0", "-1 0 0", "1 0 0", false),
            ("positive-fraction-over-one", "1.25 0 0", "1 0 0", "1 0 0", false),
            ("negative-fraction-over-one", "-1.25 0 0", "-1 0 0", "1 0 0", false),
            ("three-quarters", "0.75 0 0", "0 0 0", "1 0 0", false),
            ("positive-half", 0.5, 0, "1 0 0", false),
            ("negative-half", -0.5, 0, "1 0 0", false),
            ("positive-tiny", "0.0000001 0 0", "0 0 0", "1 0 0", false),
            ("negative-tiny", "-0.0000001 0 0", "0 0 0", "1 0 0", false),
            ("omitted", nil, 0, "1 0 0", false),
            ("scalar-number", 10, 1, "1 1 1", false),
            ("scalar-text", "-10", "-1", "1 1 1", false),
            ("finite-beyond-int", "1e300", 1, "1 0 0", false),
            ("mixed-axes", "10 -1.25 0.75", "1 -1 0", "1 1 1", false),
            ("fraction-before-active-y", "0.5 1 0", "0 1 0", "0 1 0", false),
            // Resource/IDs and the cold wrapper key change independently of the numeric value.
            ("renamed-wrapper", ["user": "otherCompass", "value": "10 -1.25 0.75"],
             "1 -1 0", "1 1 1", true)]
        for (label, rawSign, referenceSign, axes, renamed) in equivalentSigns {
            var fields: [String: Any] = ["directions": axes, "instantaneous": 32]
            if let rawSign { fields["sign"] = rawSign }
            let actual = try radial(fields, renamed: renamed, omitsSign: rawSign == nil)
            let reference = try radial(["directions": axes, "sign": referenceSign, "instantaneous": 32])
            actual.advance(by: 0.25); reference.advance(by: 0.25)
            result["sign-\(label)-same-real-state-events-rng-and-id"] = actual.particles.count == 32
                && actual.particles == reference.particles && actual.birthEvents == reference.birthEvents
                && actual.frameSnapshot().random.state == reference.frameSnapshot().random.state
                && actual.frameSnapshot().nextParticleID == reference.frameSnapshot().nextParticleID
                && (!renamed || (actual.definition.materialPath != reference.definition.materialPath
                    && actual.definition.emitters[0].id != reference.definition.emitters[0].id))
        }
        let unsafeSigns: [(String, Any)] = [("nan", "nan"), ("infinity", "0 inf 0"),
            ("negative-infinity", "0 0 -inf"), ("short-vector", "1 0"),
            ("long-vector", "1 0 0 0"), ("garbage", "otherAxis"), ("bool", true)]
        for (label, rawSign) in unsafeSigns {
            let sim = try radial(["sign": rawSign], peer: true, streaming: true)
            sim.advance(by: 0.25)
            let first = sim.frameSnapshot()
            _ = sim.consumeBirthEvents()
            sim.advance(by: 0.25)
            result["sign-\(label)-rejects-only-birth-keeps-peer-and-survivor"] =
                !sim.definition.emitters[0].hasBoundedDirectionsAndSign
                && first.particles.count == 1 && sim.particles.count == 2
                && sim.particles[0].id == first.particles[0].id
                && sim.particles[0].age == first.particles[0].age + 0.25
                && sim.particles.allSatisfy { $0.position == SIMD3(40, 2, 0) && $0.velocity == .zero }
                && sim.birthEvents.count == 1 && sim.birthEvents[0].position == SIMD3(40, 2, 0)
            let before = sim.frameSnapshot()
            do {
                _ = try explicit(sim, count: 2)
                result["sign-\(label)-exact-n-rejects-without-state-rng-id-commit"] = false
            } catch {
                let restored = sim.frameSnapshot()
                result["sign-\(label)-exact-n-rejects-without-state-rng-id-commit"] =
                    restored.particles == before.particles && restored.birthEvents == before.birthEvents
                    && restored.playback == before.playback && restored.random.state == before.random.state
                    && restored.nextParticleID == before.nextParticleID
            }
        }
        let signedManual = try radial(["sign": "10 0 0", "speedmin": -4, "speedmax": -4],
                                      initial: .init(intent: .paused))
        let signedCandidate = try explicit(signedManual, count: 2)
        let unitManual = try radial(["sign": "1 0 0", "speedmin": -4, "speedmax": -4],
                                    initial: .init(intent: .paused))
        let unitCandidate = try explicit(unitManual, count: 2)
        result["sign-exact-n-keeps-unit-state-events-rng-and-id"] =
            signedCandidate.state.particles == unitCandidate.state.particles
            && signedCandidate.state.birthEvents == unitCandidate.state.birthEvents
            && signedCandidate.state.random.state == unitCandidate.state.random.state
            && signedCandidate.state.nextParticleID == unitCandidate.state.nextParticleID
            && signedManual.particles.isEmpty && unitManual.particles.isEmpty
        result["signed-speed-exact-n-uses-real-constructor"] = signedCandidate.state.particles.count == 2
            && signedCandidate.state.birthEvents.count == 2 && signedCandidate.state.particles.allSatisfy {
                $0.position == SIMD3(12, 2, 0) && $0.velocity == SIMD3(-4, 0, 0)
            } && signedManual.particles.isEmpty
        signedManual.restoreFrame(signedCandidate.state)
        let signedBefore = signedManual.frameSnapshot()
        let overflowingSpeed = SceneParticleDefinitionParser().parseInstanceOverride(["speed": "1e39"])
        do {
            _ = try signedManual.preparePlaybackCandidate(commands: [
                (.init(layerID: 42, action: .emit, revision: signedBefore.playback.revision + 1, count: 1), .init()),
                (.init(layerID: 42, action: .emit, revision: signedBefore.playback.revision + 2, count: 3),
                 .init(instanceOverride: overflowingSpeed))], charge: { _, _ in }, release: { _ in })
            result["signed-speed-exact-n-multiplied-overflow-restores-state-rng-id"] = false
        } catch {
            let restored = signedManual.frameSnapshot()
            result["signed-speed-exact-n-multiplied-overflow-restores-state-rng-id"] =
                restored.particles == signedBefore.particles && restored.birthEvents == signedBefore.birthEvents
                && restored.random.state == signedBefore.random.state && restored.nextParticleID == signedBefore.nextParticleID
                && restored.playback == signedBefore.playback && restored.activeInstanceOverride == signedBefore.activeInstanceOverride
        }
        let signedRetry = try explicit(signedManual, count: 1)
        result["signed-speed-exact-n-retries-with-original-next-id"] = signedRetry.state.particles.count == 3
            && signedRetry.state.particles.last?.id == signedBefore.nextParticleID
            && signedRetry.state.particles.last?.velocity == SIMD3(-4, 0, 0)
        let manual=try make(initial:.init(intent:.stopped),maximum:1024,emitter:["name":"boxrandom","rate":0])
        let manualBefore=manual.frameSnapshot()
        let manualCandidate=try explicit(manual,count:1024)
        result["explicit-preview-restores-committed"] = manual.particles.isEmpty
            && manual.frameSnapshot().random.state==manualBefore.random.state
            && manual.frameSnapshot().nextParticleID==manualBefore.nextParticleID
        manual.restoreFrame(manualCandidate.state)
        result["explicit-1024-stopped-no-automatic-work"] = manual.particles.count==1024
            && manual.playback.intent == .stopped && manual.playbackObservation?.liveAny == true
            && manual.playbackObservation?.rearmHasWork == false
            && manual.frameSnapshot().nextParticleID==1024
            && manual.frameSnapshot().simulationTime==manualBefore.simulationTime
        let full=manual.frameSnapshot()
        do { _=try explicit(manual,count:1);result["explicit-capacity-atomic"]=false }
        catch { result["explicit-capacity-atomic"] = manual.particles==full.particles
            && manual.frameSnapshot().random.state==full.random.state && manual.frameSnapshot().nextParticleID==full.nextParticleID }
        let zeroCandidate=try explicit(manual,count:0)
        result["explicit-zero-no-random-id-live-change"] = zeroCandidate.state.particles==full.particles
            && zeroCandidate.state.random.state==full.random.state && zeroCandidate.state.nextParticleID==full.nextParticleID
            && zeroCandidate.state.playback.intent==full.playback.intent
        let short=try make(lifetime:0.1,initial:.init(intent:.paused),emitter:["name":"boxrandom","rate":0])
        short.restoreFrame(try explicit(short,count:3).state)
        short.advance(by:0.25)
        result["explicit-short-life-events-and-transient"] = short.particles.isEmpty
            && short.birthEvents.map(\.id)==[0,1,2] && short.deathEvents.map(\.id)==[0,1,2]
            && short.renderParticlesForCurrentAdvance().map(\.id)==[0,1,2]
        _=short.consumeBirthEvents();_=short.consumeDeathEvents();short.advance(by:0.25)
        result["explicit-transient-only-once"] = short.renderParticlesForCurrentAdvance().isEmpty
            && short.birthEvents.isEmpty && short.deathEvents.isEmpty
        let invalidBirth=try make(lifetime:0,initial:.init(intent:.stopped))
        let invalidBefore=invalidBirth.frameSnapshot()
        do { _=try explicit(invalidBirth,count:3);result["explicit-lifetime-zero-restores"]=false }
        catch { result["explicit-lifetime-zero-restores"] = invalidBirth.particles.isEmpty
            && invalidBirth.frameSnapshot().random.state==invalidBefore.random.state
            && invalidBirth.frameSnapshot().nextParticleID==invalidBefore.nextParticleID
            && invalidBirth.birthEvents.isEmpty
#if DEBUG
            result["explicit-lifetime-zero-restores"] = result["explicit-lifetime-zero-restores"]!
                && invalidBirth.diagnostics==invalidBefore.diagnostics
#endif
        }
        let overrideSim=try make(initial:.init(intent:.stopped))
        let zeroLifetime=SceneParticleDefinitionParser().parseInstanceOverride(["lifetime":0])
        do {_=try explicit(overrideSim,count:1,context:.init(instanceOverride:zeroLifetime));result["explicit-call-time-zero-rejects"]=false}
        catch {result["explicit-call-time-zero-rejects"]=overrideSim.particles.isEmpty && overrideSim.frameSnapshot().nextParticleID==0}
        overrideSim.restoreFrame(try explicit(overrideSim,count:1).state)
        overrideSim.advance(by:0.25,dynamicInstanceOverride:zeroLifetime)
        result["explicit-return-zero-does-not-rewrite-birth"] = overrideSim.particles.count==1 && overrideSim.particles[0].lifetime==10
        var lateFailureSeed:UInt64?
        for seed:UInt64 in 0..<64 {
            let root:[String:Any] = ["material":"p.json","maxcount":8,
                "emitter":[["name":"boxrandom","rate":0]],
                "initializer":[["name":"lifetimerandom","min":-1,"max":1]],"renderer":[["name":"sprite"]]]
            let randomSim=SceneParticleSimulator(definition:try SceneParticleDefinitionParser().parse(root:root),seed:seed)
            guard (try? explicit(randomSim,count:1)) != nil else {continue}
            let before=randomSim.frameSnapshot()
            do { _=try explicit(randomSim,count:2) } catch {
                lateFailureSeed=seed
                result["explicit-random-late-failure-restores-all"] = randomSim.particles.isEmpty
                    && randomSim.frameSnapshot().nextParticleID==before.nextParticleID
                    && randomSim.frameSnapshot().random.state==before.random.state
                    && randomSim.birthEvents.isEmpty
#if DEBUG
                result["explicit-random-late-failure-restores-all"] = result["explicit-random-late-failure-restores-all"]!
                    && randomSim.diagnostics==before.diagnostics
#endif
                break
            }
        }
        result["explicit-random-late-failure-real-producer"] = lateFailureSeed != nil

        do {
            let root:[String:Any] = ["material":"p.json","maxcount":8,
                "controlpoint":[["id":1,"flags":1,"offset":"0 0 0"]],
                "emitter":[["name":"sphererandom","instantaneous":4,"directions":"1 0 0","distancemin":2,"distancemax":2]],
                "initializer":[["name":"mapsequencearoundcontrolpoint","controlpoint":1,"bounds":"0 1","count":4,"limitbehavior":"repeat","speedmin":"0 2 0","speedmax":"0 2 0"]],
                "renderer":[["name":"sprite"]]]
            let sim=SceneParticleSimulator(definition:SceneParticleDefinitionParser().parse(root:root),initialPlayback:.init(intent:.stopped),seed:71)
            let before=sim.frameSnapshot()
            do {_=try sim.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,revision:1,count:1),.init())],charge:{_,_ in},release:{_ in});result["explicitMissingPointerInitializerRejects"]=false}
            catch {result["explicitMissingPointerInitializerRejects"] = sim.particles.isEmpty && sim.frameSnapshot().random.state==before.random.state && sim.frameSnapshot().nextParticleID==before.nextParticleID}
            let valid=try sim.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,revision:1,count:1),.init(controlPoints:[1:SIMD3(5,6,0)]))],charge:{_,_ in},release:{_ in})
            result["explicitValidPointerInitializerBirths"] = valid.state.particles.count==1 && valid.state.particles[0].position != SIMD3(2,0,0)
        }
        do {
            let turbulent:[String:Any] = ["name":"turbulentvelocityrandom","forward":"0 1 0","right":"1 0 0","phasemin":0.7,"phasemax":0.7,"scale":0.2,"speedmin":25,"speedmax":25,"audioprocessingmode":3]
            let root:[String:Any] = ["material":"p.json","maxcount":2048,
                "emitter":[["name":"boxrandom","instantaneous":1024,"rate":0]],
                "initializer":[["name":"lifetimerandom","min":10,"max":10]]+Array(repeating:turbulent,count:20),"renderer":[["name":"sprite"]]]
            let sim=SceneParticleSimulator(definition:SceneParticleDefinitionParser().parse(root:root))
            sim.advance(by:0.02);sim.applyPlaybackTransition(.init(layerID:42,action:.pause,revision:1))
            let committed=sim.frameSnapshot()
            let audio=SceneParticleAudioInput(left:Array(repeating:1,count:16),right:Array(repeating:1,count:16),generation:3)
            var active=0,peak=0,limit=16*1024*1024
            var chargedWork:UInt64=0
            func charge(_ work:UInt64,_ bytes:Int)throws {
                guard bytes<=limit-active else {throw SceneParticleEmissionFailure.budgetExceeded}
                active+=bytes;peak=max(peak,active);chargedWork+=work
            }
            func release(_ bytes:Int){active-=bytes}
            func actualArrayStorage(_ snapshot:SceneParticleSimulator.FrameSnapshot)->Int {
                var bytes=[snapshot.particles,snapshot.birthEvents,snapshot.deathEvents,snapshot.transientRenderBirths]
                    .reduce(0){$0+$1.capacity*MemoryLayout<SceneParticleState>.stride}
#if DEBUG
                bytes += snapshot.pendingAudioEvaluationObservations.capacity*MemoryLayout<SceneParticleAudioEvaluationObservation>.stride
#endif
                return bytes
            }
            let one=try sim.preparePlaybackCandidate(commands:[(.init(layerID:42,action:.emit,revision:2,count:1),.init(audio:audio))],charge:charge,release:release)
            let firstActive=active
            let two=try sim.preparePlaybackCandidate(starting:one.state,commands:[(.init(layerID:42,action:.emit,revision:3,count:1),.init(audio:audio))],charge:charge,release:release)
            result["real-capacity-audio-reservation"] = committed.particles.count==1024 && one.state.particles.count==1025 && two.state.particles.count==1026
                && one.reservedBytes>=actualArrayStorage(one.state) && two.reservedBytes>=actualArrayStorage(two.state)
                && peak==one.reservedBytes+two.reservedBytes && firstActive==one.reservedBytes && chargedWork>0 && chargedWork<=100_000
#if DEBUG
            result["real-capacity-audio-reservation"] = result["real-capacity-audio-reservation"]!
                && one.state.pendingAudioEvaluationObservations.count==20
#endif
            limit=active
            do {_=try sim.preparePlaybackCandidate(starting:two.state,commands:[(.init(layerID:42,action:.emit,revision:4,count:1),.init(audio:audio))],charge:charge,release:release);result["real-capacity-refused-before-cow"]=false}
            catch {result["real-capacity-refused-before-cow"] = active==one.reservedBytes+two.reservedBytes
                && sim.particles==committed.particles && sim.frameSnapshot().random.state==committed.random.state && sim.frameSnapshot().nextParticleID==committed.nextParticleID}
            release(one.reservedBytes);release(two.reservedBytes)
            result["real-capacity-all-reservations-released"] = active==0
            FileHandle.standardError.write(Data("capacity peak=\(peak) actual1=\(actualArrayStorage(one.state)) actual2=\(actualArrayStorage(two.state)) work=\(chargedWork)\n".utf8))
        }
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
            payloads = {}
            for mode, flags in [("debug", ["-D", "DEBUG"]), ("release", [])]:
                binary = directory / ("fixture-" + mode)
                compile_result = subprocess.run([shutil.which("swiftc"), "-O", *flags,
                    *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)], capture_output=True, text=True)
                self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
                run = subprocess.run([str(binary)], capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stderr)
                print(mode + ": " + run.stdout + run.stderr)
                payloads[mode] = json.loads(run.stdout)
                for name, passed in payloads[mode].items():
                    with self.subTest(mode=mode, name=name):
                        self.assertTrue(passed, name)
            self.assertEqual(payloads["release"], payloads["debug"])

if __name__ == "__main__":
    unittest.main()
