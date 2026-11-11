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

    static func make(_ root: [String: Any], budget: Int? = nil, step: Double = 1.0 / 32,
                     rate: Double = 1, history: Int = 0,
                     shouldCancel: (() -> Bool)? = nil,
                     eventValueContext: SceneParticleEventValueContext = .unavailable) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: parser.parse(root: root),
            instanceOverride: parser.parseInstanceOverride(["rate": rate]), seed: 73,
            fixedTimeStep: step, prewarmStepBudget: budget, shouldCancelPrewarm: shouldCancel,
            stepSnapshotPolicies: history > 1
                ? [SceneParticleStepSnapshotPolicy(interval: step * 4, maximumSnapshots: history)!] : [],
            eventValueContext: eventValueContext)
    }

    static func history(_ frame: SceneParticleSimulator.FrameSnapshot) -> [SceneParticleStepSnapshot] {
        var recorder = frame.stepSnapshotRecorder
        return (recorder?.consume(particles: frame.particles) ?? [:]).values.flatMap { $0 }
    }

    static func sameObservableState(_ a: SceneParticleSimulator, _ b: SceneParticleSimulator) -> Bool {
        let x = a.frameSnapshot(), y = b.frameSnapshot()
        let cachesMatch = x.positionOscillationCache.count == y.positionOscillationCache.count
            && x.positionOscillationCache.allSatisfy { key, left in
                guard let right = y.positionOscillationCache[key] else { return false }
                return left.frequency == right.frequency && left.scale == right.scale && left.phase == right.phase
            }
        guard x.particles == y.particles, x.random.state == y.random.state,
              x.nextParticleID == y.nextParticleID, x.simulationTime == y.simulationTime,
              x.accumulator == y.accumulator, x.normalizedLives == y.normalizedLives,
              x.controlPointConstraintHistory == y.controlPointConstraintHistory, cachesMatch,
              x.emitters.count == y.emitters.count else { return false }
        return zip(x.emitters, y.emitters).allSatisfy { left, right in
            left.elapsed == right.elapsed && left.remainder == right.remainder
                && left.emittedInstantaneous == right.emittedInstantaneous
        }
    }

    /// Replay witnessed completed wall steps, not a duplicate budget estimator.
    static func replay(_ warm: SceneParticleSimulator, source: [String: Any],
                       completedSteps: Int, rate: Double = 1, history: Int = 0,
                       handoffSteps: Int = 1,
                       eventValueContext: SceneParticleEventValueContext = .unavailable) -> [String: Any] {
        var cold = source; cold.removeValue(forKey: "starttime")
        let plain = make(cold, rate: rate, history: history, eventValueContext: eventValueContext)
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
        let preparedFirst = prepared.particles.first
        warm.advance(by: step); plain.advance(by: step)
        let nextStepRetainedSnapshot = prepared.particles.count == liveCount
            && prepared.particles.first == preparedFirst
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
            "retainedSnapshotUnchanged": nextStepRetainedSnapshot && prepared.particles.count == liveCount
                && prepared.particles.first == preparedFirst,
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
        for name in ["failed-initializer", "short-lived"] {
            var root = source(rate: name == "short-lived" ? 32_000 : 64_000,
                              lifetime: name == "failed-initializer" ? 0 : (name == "short-lived" ? 0.001 : 100))
            root["initializer"] = [["name": "lifetimerandom",
                "min": name == "failed-initializer" ? 0 : 0.001,
                "max": name == "failed-initializer" ? 0 : 0.001]]
            let warm = make(root)
            let completed = Int((warm.simulationTime / step).rounded())
            output[name] = replay(warm, source: root, completedSteps: completed)
        }
        return output
    }

    static func emptySystems() -> [String: Any] {
        let movement: [String: Any] = ["name": "movement", "gravity": "0 0 0"]
        let boids: [String: Any] = ["name": "boids", "neighborthreshold": 100,
            "alignmentfactor": 1, "cohesionfactor": 1, "separationfactor": 0]
        var result: [String: Any] = [:]
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
        let child = SceneParticleSimulator(definition: parser.parse(root: source(start: 60)),
            instanceOverride: parser.parseInstanceOverride(["rate": 1]), seed: 73,
            fixedTimeStep: step)
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
            "partialAge": particle?.age ?? -1, "partialHistoryCount": tail.consumeStepSnapshots().values.flatMap { $0 }.count,
            "partialLimited": tail.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "partialDrained": tail.birthEvents.isEmpty && tail.deathEvents.isEmpty]
    }

    static func complete() -> [String: Any] {
        let movement: [String: Any] = ["name": "movement", "gravity": "0 0 0"]
        let boids: [String: Any] = ["name": "boids", "neighborthreshold": 100,
            "separationfactor": 0, "cohesionfactor": 1, "alignmentfactor": 1]
        let inputs: [(String, [String: Any], Int, Int)] = [
            ("dense", source(rate: 64_000), 1920, 0),
            ("boids", source(capacity: 64, rate: 0, burst: 64, lifetime: 3600,
                operators: [boids, movement]), 1920, 8),
            ("beyond3600", source(capacity: 2, start: 128, rate: 0, burst: 2,
                lifetime: 3600), 4096, 8)]
        var rows: [String: Any] = [:]
        for (name, input, steps, history) in inputs {
            rows[name] = replay(make(input, budget: nil, history: history), source: input,
                completedSteps: steps, history: history, handoffSteps: 8)
        }
        var partial = source(capacity: 1, start: 128 + 1.0 / 128, rate: 0, burst: 1,
            lifetime: 3600)
        partial["emitter"] = [["id": 11, "name": "boxrandom", "rate": 0, "instantaneous": 1,
            "distancemin": "0 0 0", "distancemax": "0 0 0"]]
        partial["initializer"] = [["name": "lifetimerandom", "min": 3600, "max": 3600],
            ["name": "velocityrandom", "min": "64 0 0", "max": "64 0 0"]]
        let tail = make(partial, budget: nil, history: 8)
        var cold = partial; cold.removeValue(forKey: "starttime")
        let plain = SceneParticleSimulator(definition: parser.parse(root: cold),
            instanceOverride: parser.parseInstanceOverride(["rate": 1]), seed: 73,
            fixedTimeStep: 1.0 / 128,
            stepSnapshotPolicies: [SceneParticleStepSnapshotPolicy(interval: step * 4, maximumSnapshots: 8)!])
        // The finer live step reaches the fractional endpoint while retaining
        // the same history interval as this constant-velocity prewarm control.
        for _ in 0..<16_385 {
            plain.advance(by: 1.0 / 128)
            _ = plain.consumeBirthEvents(); _ = plain.consumeDeathEvents()
        }
        plain.advance(by: 0)
        let samePlainState = sameObservableState(tail, plain)
        let retainedHistory = tail.consumeStepSnapshots().values.flatMap { $0 }
        rows["partial"] = ["time": tail.simulationTime,
            "age": tail.particles.first?.age ?? -1, "x": tail.particles.first?.position.x ?? -1,
            "samePlainLinearState": samePlainState,
            "samePlainHistory": retainedHistory == plain.consumeStepSnapshots().values.flatMap { $0 },
            "historyCount": retainedHistory.count,
            "limited": tail.diagnostics.contains { $0.kind == .prewarmBudgetExceeded },
            "drained": tail.birthEvents.isEmpty && tail.deathEvents.isEmpty]
        return rows
    }

    static func cancellation() -> [String: Any] {
        let operators: [[String: Any]] = [
            ["name": "oscillateposition", "frequencymin": 1, "frequencymax": 2,
                "scalemin": "1 0 0", "scalemax": "3 1 0"],
            ["name": "movement", "gravity": "0 0 0", "drag": 0]]
        let input = source(capacity: 64, start: 20, rate: 32, lifetime: 0.125, operators: operators)
        let cases: [(String, Int?, Int)] = [
            ("beforeStart", nil, 0), ("threeSteps", nil, 3),
            ("step240", nil, 240), ("step241", nil, 241), ("childCancelled", 240, 3)]
        var rows: [String: Any] = [:]
        for (name, budget, stop) in cases {
            var checks = 0
            let warm = make(input, budget: budget, history: 8, shouldCancel: {
                let cancelled = checks >= stop
                checks += 1
                return cancelled
            })
            let checksAtReturn = checks
            var row = replay(warm, source: input, completedSteps: stop, history: 8, handoffSteps: 8)
            row["cancellationChecks"] = checks
            row["checksOnlyDuringWarmup"] = checks == checksAtReturn
            row["cancelled"] = warm.diagnostics.contains {
                $0.kind == .prewarmBudgetExceeded && $0.componentName?.contains(",cancelled=true") == true
            }
            rows[name] = row
        }
        var checks = 0
        let warm = make(input, budget: nil, history: 8, shouldCancel: { checks += 1; return false })
        let checksAtReturn = checks
        var row = replay(warm, source: input, completedSteps: 640, history: 8, handoffSteps: 8)
        row["cancellationChecks"] = checks
        row["checksOnlyDuringWarmup"] = checks == checksAtReturn
        row["cancelled"] = warm.diagnostics.contains { $0.componentName?.contains(",cancelled=true") == true }
        rows["continues"] = row
        return rows
    }

    static func appearance(_ particle: SceneParticleState) -> [String: Any] {
        ["size": particle.size, "initialSize": particle.initialSize,
         "color": [particle.color.x, particle.color.y, particle.color.z],
         "initialColor": [particle.initialColor.x, particle.initialColor.y, particle.initialColor.z],
         "alpha": particle.alpha, "initialAlpha": particle.initialAlpha, "age": particle.age]
    }

    static func fieldWriterBaselines() -> [String: Any] {
        let size: [String: Any] = ["name": "sizechange", "starttime": 0, "endtime": 1,
            "startvalue": 2, "endvalue": 2]
        let oscillate: [String: Any] = ["name": "oscillatesize", "frequencymin": 0,
            "frequencymax": 0, "scalemin": 3, "scalemax": 3, "phasemin": 0, "phasemax": 0]
        let color: [String: Any] = ["name": "colorchange", "starttime": 0, "endtime": 1,
            "startvalue": "0.5 0.25 0.75", "endvalue": "0.5 0.25 0.75"]
        let alpha: [String: Any] = ["name": "alphachange", "starttime": 0, "endtime": 1,
            "startvalue": 0.5, "endvalue": 0.5]
        let movement: [String: Any] = ["name": "movement", "gravity": "0 0 0"]
        var root = source(capacity: 1, start: 1, rate: 0, burst: 1, lifetime: 64)
        root["initializer"] = [["id": 21, "name": "lifetimerandom", "min": 64, "max": 64],
            ["id": 22, "name": "sizerandom", "min": 7, "max": 7],
            ["id": 23, "name": "colorrandom", "min": "255 0 255", "max": "255 0 255"],
            ["id": 24, "name": "alpharandom", "min": 0.375, "max": 0.375]]
        let cases: [(String, [[String: Any]])] = [("none", []), ("size", [size]),
            ("oscillate", [oscillate]), ("twoSizeWriters", [size, oscillate]),
            ("color", [color]), ("combined", [size, oscillate, color]),
            ("renamed", [size, oscillate, color]), ("movementOnly", [movement])]
        var rows: [String: Any] = [:]
        for (name, operators) in cases {
            var input = root
            // The hot-path case has no alpha/size/color writer at all, so all
            // three per-step resets can be skipped; other cases keep the alpha
            // writer to observe baseline rebasing.
            input["operator"] = name == "movementOnly" ? operators : operators + [alpha]
            if name == "renamed" {
                input["material"] = "materials/another-birth-spectrum.json"
                input["operator"] = (operators + [alpha]).enumerated().map { index, value in
                    var renamed = value; renamed["id"] = 700 + index; return renamed
                }
            }
            let warm = make(input, history: 4)
            let prepared = appearance(warm.particles[0])
            var row = replay(warm, source: input, completedSteps: 32, history: 4, handoffSteps: 8)
            row["prewarm"] = prepared
            row["live"] = appearance(warm.particles[0])
            rows[name] = row
        }
        var eventInput = root
        eventInput["operator"] = [["name": "inheritvaluefromevent", "input": "setcolor"], alpha]
        let context = SceneParticleEventValueContext.follow(.init(color: SIMD3(0.25, 0.5, 0.75),
            size: 19, alpha: 0.9))
        let warm = make(eventInput, history: 4, eventValueContext: context)
        let prepared = appearance(warm.particles[0])
        let identity = warm.particles[0].id
        var event = replay(warm, source: eventInput, completedSteps: 32, history: 4,
            eventValueContext: context)
        event["prewarm"] = prepared
        event["validLive"] = appearance(warm.particles[0])
        warm.updateFollowEventValues(.init(color: SIMD3(.infinity, 0.5, 0.75), size: 19, alpha: 0.9))
        var unavailable: [[String: Any]] = []
        for _ in 0..<3 {
            warm.advance(by: step)
            unavailable.append(appearance(warm.particles[0]))
        }
        event["unavailableLive"] = unavailable
        warm.updateFollowEventValues(.init(color: SIMD3(0, 0.25, 1), size: 19, alpha: 0.9))
        warm.advance(by: step)
        event["recoveredLive"] = appearance(warm.particles[0])
        event["sameParticle"] = warm.particles.count == 1 && warm.particles[0].id == identity
        return ["rows": rows, "event": event]
    }

    static func orderedDeaths() -> [String: Any] {
        let operatorValue: [String: Any] = ["name": "oscillateposition", "frequencymin": 1,
            "frequencymax": 2, "scalemin": "1 0 0", "scalemax": "3 1 0"]
        // Death payloads are observed after the step's operator pass; a
        // constant alpha writer makes the post-operator value visible in every
        // death event.
        let alphaWriter: [String: Any] = ["name": "alphachange", "starttime": 0,
            "endtime": 1, "startvalue": 0.5, "endvalue": 0.5]
        let input = source(capacity: 8, start: 0, rate: 0, burst: 8,
                           lifetime: step * 8, operators: [operatorValue, alphaWriter])
        let patterns: [(String, [Int])] = [("none", []), ("prefix", [0, 1]),
            ("interior", [2, 5]), ("mixed", [0, 1, 4, 6]), ("all", Array(0..<8))]
        var rows: [String: Any] = [:]
        for (name, expired) in patterns {
            let simulator = make(input, history: 4)
            simulator.advance(by: step * 3)
            _ = simulator.consumeBirthEvents()
            // Death payloads are observed after the step's operator pass. No
            // operator writes size in this fixture, so the particle keeps its
            // birth size; set the value and its baseline together the way a
            // real birth leaves them.
            for index in simulator.particles.indices {
                simulator.particles[index].initialSize = Double(index + 1)
                simulator.particles[index].size = Double(index + 1)
            }
            for index in expired {
                simulator.particles[index].lifetime = step * 4
            }

            let retained = simulator.frameSnapshot()
            simulator.advance(by: step, allowsEmission: false)
            let current = simulator.frameSnapshot()
            rows[name] = [
                "retainedIDs": retained.particles.map(\.id),
                "retainedAges": retained.particles.map(\.age),
                "survivors": current.particles.map(\.id),
                "deaths": current.deathEvents.map(\.id),
                "deathSizes": current.deathEvents.map(\.size),
                "deathAges": current.deathEvents.map(\.age),
                "deathAlphas": current.deathEvents.map(\.alpha),
                "survivorAlphas": current.particles.map(\.alpha),
                "cachedIDs": current.positionOscillationCache.keys.map(\.particleID).sorted(),
                "historyIDs": history(current).map { $0.particles.map(\.id) }
            ]
        }
        return rows
    }

    /// Leading deaths past the storage compaction threshold must keep the live
    /// order, snapshots and the next step identical to a compact array. The
    /// mixed case first leaves a dead prefix below the threshold and then kills
    /// one leading and one interior particle, exercising the in-place split.
    static func leadingDeathCompaction() -> [String: Any] {
        func run(expired: [Int], second: ((SceneParticleSimulator) -> Void)? = nil) -> [String: Any] {
            let input = source(capacity: 96, start: 0, rate: 0, burst: 96,
                               lifetime: step * 8)
            let simulator = make(input, history: 4)
            simulator.advance(by: step * 3)
            _ = simulator.consumeBirthEvents()
            for index in expired {
                simulator.particles[index].lifetime = step * 4
            }
            simulator.advance(by: step, allowsEmission: false)
            let first = simulator.frameSnapshot()
            let firstDeaths = simulator.consumeDeathEvents().map(\.id)
            let firstHistory = history(first).map { $0.particles.map(\.id) }
            second?(simulator)
            simulator.advance(by: step, allowsEmission: false)
            let current = simulator.frameSnapshot()
            let retainedHistory = history(current).map { $0.particles.map(\.id) }
            simulator.advance(by: step, allowsEmission: false)
            let next = simulator.frameSnapshot()
            return ["firstDeaths": firstDeaths,
                    "firstSurvivors": first.particles.map(\.id),
                    "firstHistory": firstHistory,
                    "deaths": current.deathEvents.map(\.id),
                    "survivors": current.particles.map(\.id),
                    "ages": current.particles.map(\.age),
                    "history": retainedHistory,
                    "nextSurvivors": next.particles.map(\.id),
                    "nextAges": next.particles.map(\.age)]
        }
        return ["partial": run(expired: Array(0..<70)),
                "all": run(expired: Array(0..<96)),
                "mixed": run(expired: Array(0..<3)) { simulator in
                    // The first step already removed three leading particles;
                    // indices below are relative to the remaining live range.
                    simulator.particles[0].lifetime = step * 4
                    simulator.particles[37].lifetime = step * 4
                }]
    }

    static func main() throws {
        let result: [String: Any] = ["sparse": sparse(), "workload": workload(),
            "emptySystems": emptySystems(), "bounds": boundaries(),
            "complete": complete(), "cancellation": cancellation(), "fieldWriters": fieldWriterBaselines(),
            "orderedDeaths": orderedDeaths(), "compaction": leadingDeathCompaction()]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
