import Foundation

enum SceneParticleStepSnapshotPolicyHarness {
    static func facts() -> [String: Bool] {
        let fast = SceneParticleStepSnapshotPolicy(interval: 0.125, maximumSnapshots: 3)!
        let slow = SceneParticleStepSnapshotPolicy(interval: 0.5, maximumSnapshots: 8)!
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/owned-history.json", "maxcount": 64,
            "emitter": [["name": "boxrandom", "rate": 8, "duration": 4,
                         "distancemin": "0 0 0", "distancemax": "2 3 0"]],
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10],
                            ["name": "velocityrandom", "min": "1 0 0", "max": "2 1 0"]],
            "operator": [["name": "movement", "gravity": "0 0 0"]],
            "renderer": [["name": "sprite"]],
        ])
        func make(_ policies: [SceneParticleStepSnapshotPolicy]) -> SceneParticleSimulator {
            SceneParticleSimulator(definition: definition, seed: 83, fixedTimeStep: 0.125,
                                   stepSnapshotPolicies: policies)
        }
        let multiple = make([fast, slow]), repeated = make([fast, slow, fast])
        let fastOnly = make([fast]), slowOnly = make([slow]), noHistory = make([])
        let systems = [multiple, repeated, fastOnly, slowOnly, noHistory]
        for _ in 0..<16 {
            for simulator in systems { simulator.advance(by: 0.125) }
        }
        var facts: [String: Bool] = [:]
        facts["step-policies-do-not-advance-simulation-or-rng"] = systems.allSatisfy {
            sameSimulation(multiple, $0)
        }
        facts["step-policies-duplicates-do-not-reserve-another-stream"] =
            multiple.frameSnapshot().stepSnapshotRecorder?.emissionStorageBytes
                == repeated.frameSnapshot().stepSnapshotRecorder?.emissionStorageBytes
        let samples = multiple.consumeStepSnapshots()
        facts["step-policies-match-independent-single-policy-streams"] =
            samples[fast] == fastOnly.consumeStepSnapshots()[fast]
                && samples[slow] == slowOnly.consumeStepSnapshots()[slow]
        facts["step-policies-preserve-each-interval-and-capacity"] =
            samples[fast]?.count == 3 && samples[slow]?.count == 4
                && samples[fast]?.allSatisfy { $0.duration == 0.125 } == true
                && samples[slow]?.allSatisfy { $0.duration == 0.5 } == true
        facts["step-policies-duplicate-policies-produce-one-result"] =
            samples.count == 2 && repeated.consumeStepSnapshots() == samples
        facts["step-policies-share-due-particle-payload"] = {
            guard let a = samples[fast]?.last?.particles,
                  let b = samples[slow]?.last?.particles, !a.isEmpty else { return false }
            return a.withUnsafeBufferPointer { left in
                b.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
            }
        }()
        facts["step-policies-consume-drains-all-streams"] =
            multiple.consumeStepSnapshots().isEmpty && noHistory.consumeStepSnapshots().isEmpty

        let pending = make([fast, slow, fast])
        let partialFast = make([fast]), partialSlow = make([slow])
        for simulator in [pending, partialFast, partialSlow] { simulator.advance(by: 0.375) }
        let checkpoint = pending.frameSnapshot()
        let partial = pending.consumeStepSnapshots()
        facts["step-policies-partial-samples-match-single-policy-consumers"] =
            partial[fast] == partialFast.consumeStepSnapshots()[fast]
                && partial[slow] == partialSlow.consumeStepSnapshots()[slow]
                && partial[slow]?.map(\.duration) == [0.375]
        pending.restoreFrame(checkpoint)
        facts["step-policies-snapshot-restores-consumed-and-pending-samples"] =
            pending.consumeStepSnapshots() == partial
        pending.restoreFrame(checkpoint)
        pending.advance(by: 0.625)
        let futureState = pending.frameSnapshot()
        let future = pending.consumeStepSnapshots()
        pending.restoreFrame(checkpoint)
        pending.advance(by: 0.625)
        facts["step-policies-rollback-replays-each-stream-and-simulation"] =
            pending.consumeStepSnapshots() == future
                && pending.particles == futureState.particles
                && pending.frameSnapshot().random.state == futureState.random.state
                && pending.frameSnapshot().nextParticleID == futureState.nextParticleID
        pending.restoreFrame(checkpoint)
        pending.applyPlaybackTransition(.init(layerID: 42, action: .stop, revision: 1))
        facts["step-policies-stop-clears-all-policies"] = pending.particles.isEmpty
            && pending.consumeStepSnapshots().isEmpty
        pending.restoreFrame(checkpoint)
        facts["step-policies-rollback-restores-stopped-streams"] =
            pending.consumeStepSnapshots() == partial
        return facts
    }

    private static func sameSimulation(_ a: SceneParticleSimulator, _ b: SceneParticleSimulator) -> Bool {
        let left = a.frameSnapshot(), right = b.frameSnapshot()
        return left.particles == right.particles && left.random.state == right.random.state
            && left.nextParticleID == right.nextParticleID && left.simulationTime == right.simulationTime
            && left.accumulator == right.accumulator && left.birthEvents == right.birthEvents
            && left.deathEvents == right.deathEvents
    }
}
