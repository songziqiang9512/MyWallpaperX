import Foundation
import simd

@main enum PrewarmWorkHarness {
    static let step = 1.0 / 32
    static let parser = SceneParticleDefinitionParser()

    static func source(name: String = "owned-prewarm", capacity: Int = 20_000,
                       start: Double = 60, rate: Double = 0.3, burst: Int = 0,
                       lifetime: Double = 100, operators: [[String: Any]]? = nil) -> [String: Any] {
        ["material": "materials/\(name).json", "maxcount": capacity, "starttime": start,
         "emitter": [["id": 11, "name": "boxrandom", "rate": rate, "instantaneous": burst,
                      "distancemin": "0 0 0", "distancemax": "2 3 0"]],
         "initializer": [["id": 21, "name": "lifetimerandom", "min": lifetime, "max": lifetime],
                         ["id": 22, "name": "velocityrandom", "min": "-2 0 0", "max": "1 3 0"]],
         "operator": operators ?? [["name": "movement", "gravity": "0 0 0"]],
         "renderer": [["name": "sprite"]]]
    }

    static func make(_ root: [String: Any], budget: Int = 3_600, step: Double = 1.0 / 32,
                     rate: Double = 1, history: Int = 0) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: parser.parse(root: root),
            instanceOverride: parser.parseInstanceOverride(["rate": rate]), seed: 73,
            fixedTimeStep: step, prewarmStepBudget: budget,
            stepSnapshotPolicy: history > 1 ? .init(interval: step * 4, maximumSnapshots: history) : nil)
    }

    static func history(_ frame: SceneParticleSimulator.FrameSnapshot) -> [SceneParticleStepSnapshot] {
        var recorder = frame.stepSnapshotRecorder
        return recorder?.consume(particles: frame.particles) ?? []
    }

    static func sameObservableState(_ a: SceneParticleSimulator, _ b: SceneParticleSimulator) -> Bool {
        let x = a.frameSnapshot(), y = b.frameSnapshot()
        guard x.particles == y.particles, x.random.state == y.random.state,
              x.nextParticleID == y.nextParticleID, x.simulationTime == y.simulationTime,
              x.accumulator == y.accumulator, x.normalizedLives == y.normalizedLives,
              x.controlPointConstraintHistory == y.controlPointConstraintHistory,
              x.emitters.count == y.emitters.count else { return false }
        return zip(x.emitters, y.emitters).allSatisfy { left, right in
            left.elapsed == right.elapsed && left.remainder == right.remainder
                && left.emittedInstantaneous == right.emittedInstantaneous
        }
    }

    /// Replay witnessed completed wall steps, not a duplicate budget estimator.
    static func replay(_ warm: SceneParticleSimulator, source: [String: Any],
                       completedSteps: Int, rate: Double = 1, history: Int = 0,
                       handoffSteps: Int = 1) -> [String: Any] {
        var cold = source; cold.removeValue(forKey: "starttime")
        let plain = make(cold, rate: rate, history: history)
        var births = 0, deaths = 0
        for _ in 0..<completedSteps {
            plain.advance(by: step)
            births += plain.consumeBirthEvents().count
            deaths += plain.consumeDeathEvents().count
        }
        // Live advance can expose a transient render sample; warmup intentionally
        // drains events and does not publish that callback-only render suffix.
        plain.advance(by: 0)
        let prepared = warm.frameSnapshot()
        let equal = sameObservableState(warm, plain)
        let historiesEqual = self.history(prepared) == self.history(plain.frameSnapshot())
        let retainedHistory = self.history(prepared)
        let drained = warm.birthEvents.isEmpty && warm.deathEvents.isEmpty
        let nextID = prepared.nextParticleID, time = prepared.simulationTime
        let liveCount = prepared.particles.count, processedCount = prepared.normalizedLives.count
        warm.advance(by: step); plain.advance(by: step)
        let nextState = sameObservableState(warm, plain)
        let nextEvents = warm.birthEvents == plain.birthEvents && warm.deathEvents == plain.deathEvents
        let nextHistory = self.history(warm.frameSnapshot()) == self.history(plain.frameSnapshot())
        var handoffEqual = nextState && nextEvents && nextHistory
        for _ in 1..<handoffSteps {
            _ = warm.consumeBirthEvents(); _ = warm.consumeDeathEvents()
            _ = plain.consumeBirthEvents(); _ = plain.consumeDeathEvents()
            warm.advance(by: step); plain.advance(by: step)
            handoffEqual = handoffEqual && sameObservableState(warm, plain)
                && warm.birthEvents == plain.birthEvents && warm.deathEvents == plain.deathEvents
                && self.history(warm.frameSnapshot()) == self.history(plain.frameSnapshot())
        }
        return ["sameObservableState": equal, "sameHistory": historiesEqual,
            "nextStepObservableState": nextState, "nextStepEvents": nextEvents,
            "nextStepHistory": nextHistory, "continuedHandoff": handoffEqual,
            "handoffCadences": handoffSteps,
            "drained": drained, "historyCount": retainedHistory.count,
            "historyHasPopulation": retainedHistory.contains { !$0.particles.isEmpty },
            "time": time, "completedSteps": completedSteps, "nextID": nextID,
            "population": liveCount, "processedPopulation": processedCount,
            "acceptedBirths": births, "deaths": deaths,
            "limited": warm.diagnostics.contains { $0.kind == .prewarmBudgetExceeded }]
    }

    static func sparse() -> [String: Any] {
        var rows: [[String: Any]] = []
        var standard = source()
        var emitter = (standard["emitter"] as! [[String: Any]])[0]
        emitter["flags"] = 4; emitter["maxtoemitperperiod"] = 2
        emitter["minperiodicduration"] = 2.0; emitter["maxperiodicduration"] = 3.0
        emitter["minperiodicdelay"] = 0.5; emitter["maxperiodicdelay"] = 1.0
        standard["emitter"] = [emitter]
        for renamed in [false, true] {
            var input = standard
            if renamed {
                input["material"] = "materials/other-spectrum.json"
                var emitter = (input["emitter"] as! [[String: Any]])[0]; emitter["id"] = 911
                input["emitter"] = [emitter]
                var initializers = input["initializer"] as! [[String: Any]]
                initializers[0]["id"] = 921; initializers[1]["id"] = 922
                input["initializer"] = initializers
            }
            let warm = make(input, history: 36)
            let baseline = make(standard, history: 36)
            var row = replay(warm, source: input, completedSteps: 1920, history: 36, handoffSteps: 2048)
            // The independent renamed comparison uses the same live handoff.
            for _ in 0..<2048 { baseline.advance(by: step) }
            row["name"] = renamed ? "renamed" : "ordinary"
            row["renamedEquivalent"] = sameObservableState(warm, baseline)
                && history(warm.frameSnapshot()) == history(baseline.frameSnapshot())
            rows.append(row)
        }
        var fast = source(start: 9, rate: 0.8)
        fast["initializer"] = [["name": "lifetimerandom", "min": 4, "max": 4],
                               ["name": "velocityrandom", "min": "60 0 0", "max": "60 0 0"]]
        let fastWarm = make(fast, rate: 1.2, history: 36)
        return ["rows": rows, "scaledClock": replay(fastWarm, source: fast,
            completedSteps: 288, rate: 1.2, history: 36)]
    }

    static func workload() -> [String: Any] {
        var output: [String: Any] = [:]
        for name in ["dense", "failed-initializer", "short-lived"] {
            var root = source(rate: name == "short-lived" ? 32_000 : 64_000,
                              lifetime: name == "failed-initializer" ? 0 : (name == "short-lived" ? 0.001 : 100))
            if name != "dense" {
                root["initializer"] = [["name": "lifetimerandom",
                    "min": name == "failed-initializer" ? 0 : 0.001,
                    "max": name == "failed-initializer" ? 0 : 0.001]]
            }
            let warm = make(root)
            let completed = Int((warm.simulationTime / step).rounded())
            output[name] = replay(warm, source: root, completedSteps: completed)
        }
        return output
    }

    static func boidsAndEmpty() -> [String: Any] {
        let movement: [String: Any] = ["name": "movement", "gravity": "0 0 0"]
        let boids: [String: Any] = ["name": "boids", "neighborthreshold": 100,
            "alignmentfactor": 1, "cohesionfactor": 1, "separationfactor": 0]
        var result: [String: Any] = [:]
        for flock in [false, true] {
            let root = source(capacity: 64, rate: 0, burst: 64, lifetime: 3600,
                              operators: flock ? [boids, movement] : [movement])
            let warm = make(root)
            let completed = Int((warm.simulationTime / step).rounded())
            var row = replay(warm, source: root, completedSteps: completed)
            row["boidsPlanPrepared"] = flock
                ? warm.definition.boidsPlan(for: warm.definition.operators[0]) != nil : false
            row["velocities"] = warm.particles.prefix(2).map { [$0.velocity.x, $0.velocity.y, $0.velocity.z] }
            result[flock ? "boids" : "linear"] = row
        }
        for name in ["capacity", "boids", "dispatch", "rate-zero"] {
            var root = source(capacity: name == "boids" ? 64 : 20_000, rate: 0,
                operators: name == "boids" ? [boids, movement]
                    : (name == "dispatch" ? Array(repeating: movement, count: 1000) : [movement]))
            if name == "rate-zero" { root["emitter"] = [["name": "boxrandom", "rate": 64_000]] }
            let warm = make(root, rate: name == "rate-zero" ? 0 : 1)
            result["empty-" + name] = ["time": warm.simulationTime,
                "population": warm.particles.count, "nextID": warm.frameSnapshot().nextParticleID,
                "limited": warm.diagnostics.contains { $0.kind == .prewarmBudgetExceeded }]
        }
        return result
    }

    static func boundaries() -> [String: Any] {
        let child = make(source(start: 60), budget: 240)
        var empty = source(capacity: 0, start: 112.5, rate: 0)
        let exact = make(empty, budget: Int.max)
        empty["starttime"] = 112.5 + step
        let over = make(empty, budget: Int.max)
        var partial = source(capacity: 1, start: 8 + 1.0 / 128, rate: 0, burst: 1)
        partial["emitter"] = [["name": "boxrandom", "rate": 0, "instantaneous": 1,
                              "distancemin": 0, "distancemax": 0]]
        partial["initializer"] = [["name": "lifetimerandom", "min": 100, "max": 100],
                                  ["name": "velocityrandom", "min": "64 0 0", "max": "64 0 0"]]
        let tail = make(partial, history: 8)
        let particle = tail.particles.first
        return ["childTime": child.simulationTime,
            "childLimited": child.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "exactTime": exact.simulationTime, "exactLimited": exact.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "overTime": over.simulationTime, "overLimited": over.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "partialTime": tail.simulationTime, "partialX": particle?.position.x ?? -1,
            "partialAge": particle?.age ?? -1, "partialHistoryCount": tail.consumeStepSnapshots().count,
            "partialLimited": tail.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "partialDrained": tail.birthEvents.isEmpty && tail.deathEvents.isEmpty]
    }

    static func main() throws {
        let result: [String: Any] = ["sparse": sparse(), "workload": workload(),
            "populationWork": boidsAndEmpty(), "bounds": boundaries()]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
