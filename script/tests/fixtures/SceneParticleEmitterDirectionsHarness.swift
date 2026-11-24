import Foundation
import simd

@main
enum SceneParticleEmitterDirectionsHarness {
    static func definition(_ fields: [String: Any], peer: Bool = false,
                           renamed: Bool = false) -> SceneParticleDefinition {
        var emitter: [String: Any] = [
            "id": renamed ? 907 : 17, "name": "sphererandom", "instantaneous": 8,
            "rate": 0, "origin": "0 0 0", "sign": "0 0 0",
            "distancemin": 1, "distancemax": 4, "speedmin": 0, "speedmax": 0,
        ]
        emitter.merge(fields) { _, value in value }
        var emitters = [emitter]
        if peer {
            emitters.append(["name": "sphererandom", "instantaneous": 1, "rate": 0,
                             "origin": "7 8 9", "directions": "0 0 0",
                             "distancemin": 0, "distancemax": 0])
        }
        return SceneParticleDefinitionParser().parse(root: [
            "material": renamed ? "renamed/compass.json" : "particle.json", "maxcount": 64,
            "emitter": emitters,
            "initializer": [["name": "lifetimerandom", "min": 10, "max": 10]],
            "renderer": [["name": "sprite"]],
        ])
    }

    static func simulator(_ fields: [String: Any], peer: Bool = false,
                          renamed: Bool = false, paused: Bool = false) -> SceneParticleSimulator {
        SceneParticleSimulator(definition: definition(fields, peer: peer, renamed: renamed),
                               initialPlayback: .init(intent: paused ? .paused : .playing), seed: 52)
    }

    static func coordinates<C: Collection>(_ particles: C) -> [[Double]] where C.Element == SceneParticleState {
        particles.map { [Double(Float($0.position.x)), Double(Float($0.position.y)),
                         Double(Float($0.position.z))] }
    }

    static func facts(_ state: SceneParticleSimulator.FrameSnapshot) -> [String: Any] {
        ["ids": state.particles.map { String($0.id) },
         "positions": coordinates(state.particles), "ages": state.particles.map(\.age),
         "birthIDs": state.birthEvents.map { String($0.id) },
         "birthPositions": coordinates(state.birthEvents),
         "birthVelocities": state.birthEvents.map { [$0.velocity.x, $0.velocity.y, $0.velocity.z] },
         "random": String(state.random.state), "nextID": String(state.nextParticleID),
         "time": state.simulationTime, "revision": String(state.playback.revision),
         "intent": state.playback.intent.rawValue]
    }

    static func run(_ fields: [String: Any], peer: Bool = false,
                    renamed: Bool = false, randomState: UInt64? = nil) -> [String: Any] {
        let value = simulator(fields, peer: peer, renamed: renamed)
        if let randomState { value.random = .init(state: randomState) }
        let initial = value.frameSnapshot()
        value.advance(by: value.fixedTimeStep)
        let first = value.frameSnapshot()
        value.advance(by: value.fixedTimeStep)
        let second = value.frameSnapshot()
        value.restoreFrame(initial)
        value.advance(by: value.fixedTimeStep)
        return ["first": facts(first), "second": facts(second), "replayed": facts(value.frameSnapshot())]
    }

    static func candidate(_ value: SceneParticleSimulator, count: Int = 2,
                          revision: UInt64 = 1) throws -> SceneParticleSimulator.PlaybackCandidate {
        try value.preparePlaybackCandidate(
            commands: [(.init(layerID: 61, action: .emit, revision: revision, count: count),
                        SceneParticleSimulator.EmissionContext())],
            charge: { _, _ in }, release: { _ in })
    }

    static func transaction(_ fields: [String: Any]) -> [String: Any] {
        let value = simulator(fields, paused: true)
        let before = value.frameSnapshot()
        do {
            let prepared = try candidate(value)
            let afterPrepare = value.frameSnapshot()
            value.restoreFrame(prepared.state)
            let committed = value.frameSnapshot()
            value.restoreFrame(before)
            let rolledBack = value.frameSnapshot()
            let retry = try candidate(value)
            var partialRejected = false
            do {
                _ = try value.preparePlaybackCandidate(commands: [
                    (.init(layerID: 61, action: .emit, revision: 1, count: 1),
                     SceneParticleSimulator.EmissionContext()),
                    (.init(layerID: 61, action: .emit, revision: 2, count: 1025),
                     SceneParticleSimulator.EmissionContext()),
                ], charge: { _, _ in }, release: { _ in })
            } catch { partialRejected = true }
            return ["accepted": true, "before": facts(before), "afterPrepare": facts(afterPrepare),
                    "candidate": facts(prepared.state), "committed": facts(committed),
                    "rolledBack": facts(rolledBack), "retry": facts(retry.state),
                    "partialRejected": partialRejected, "afterRejected": facts(value.frameSnapshot())]
        } catch {
            return ["accepted": false, "before": facts(before), "afterRejected": facts(value.frameSnapshot())]
        }
    }

    static func speedBirth(
        _ fields: [String: Any] = [:], world: Bool = true, scaleX: Float = 3,
        initializerY: Bool = false, worldMovement: Bool = false, explicit: Bool = false
    ) throws -> [[Double]] {
        var emitter: [String: Any] = ["name": "sphererandom", "instantaneous": 1, "rate": 0,
                                      "directions": "1 0 0", "sign": "1 0 0", "distancemin": 2,
                                      "distancemax": 2, "speedmin": 12, "speedmax": 12]
        emitter.merge(fields) { _, value in value }
        let initializers: [[String: Any]] = initializerY
            ? [["name": "velocityrandom", "min": "0 8 0", "max": "0 8 0"]] : []
        let operators: [[String: Any]] = worldMovement ? [["name": "movement", "flags": 1]] : []
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "p.json", "flags": world ? 1 : 0, "emitter": [emitter],
            "initializer": initializers, "operator": operators, "renderer": [["name": "sprite"]],
        ])
        let transform = simd_float4x4(diagonal: SIMD4(scaleX, 0.5, 1, 1))
        let value = SceneParticleSimulator(definition: definition,
            initialPlayback: .init(intent: explicit ? .paused : .playing), seed: 52,
            worldSpaceFrame: SceneParticleWorldSpaceFrame(worldFrame: transform))
        if explicit {
            value.restoreFrame(try candidate(value, count: 1).state)
        } else {
            value.advance(by: value.fixedTimeStep)
        }
        let birth = value.frameSnapshot().birthEvents[0]
        return [birth.position, birth.velocity].map { [$0.x, $0.y, $0.z] }
    }

    static func main() throws {
        let scale = 1_099_511_627_776.0
        let inverse = 1 / scale
        var equivalents: [[String: Any]] = []
        for mask in 0...7 {
            let axes = (0..<3).map { mask & (1 << $0) == 0 ? 0.0 : 1.0 }
            let large = axes.map { $0 * scale }
            let actual: [String: Any] = ["directions": large, "distancemin": inverse,
                                         "distancemax": 4 * inverse]
            equivalents.append(["name": "sphere-\(mask)", "mask": mask,
                                "actual": run(actual), "reference": run(["directions": axes])])
        }
        equivalents.append(["name": "box", "actual": run([
            "name": "boxrandom", "directions": [scale, -2 * scale, 0],
            "distancemin": "0 0 0", "distancemax": [inverse, inverse, 0]]),
            "reference": run(["name": "boxrandom", "directions": "1 -2 0",
                              "distancemin": "0 0 0", "distancemax": "1 1 0"])])
        equivalents.append(["name": "renamed-wrapper", "actual": run([
            "directions": ["user": "otherCompass", "value": "1 1 0"],
            "distancemin": ["user": "otherInner", "value": 1],
            "distancemax": ["user": "otherOuter", "value": 4]], renamed: true),
            "reference": run([:])])
        equivalents.append(["name": "tiny-fixed", "actual": run([
            "directions": "1e200 1e200 1e200", "distancemin": 1e-200, "distancemax": 1e-200]),
            "reference": run(["directions": "1 1 1", "distancemin": 1, "distancemax": 1])])
        equivalents.append(["name": "canonical-clamp", "actual": run([
            "distancemin": -8, "distancemax": -2]),
            "reference": run(["distancemin": 0, "distancemax": 0])])
        equivalents.append(["name": "canonical-maximum", "actual": run([
            "distancemin": 8, "distancemax": 2]),
            "reference": run(["distancemin": 8, "distancemax": 8])])

        // Literal states select the second real RNG draw; the harness contains no RNG implementation.
        let zeroState: UInt64 = 0xc3910c8d016b07d6
        let eighthState: UInt64 = 0xf80a4e4f0006f273
        var probes: [String: Any] = [:]
        for (name, state) in [("zero", zeroState), ("eighth", eighthState)] {
            var random = SceneParticleRandomGenerator(state: state)
            _ = random.unit()
            probes[name] = random.unit()
        }
        let subnormal = run(["directions": "1e308 0 0", "sign": "1 0 0", "instantaneous": 1,
                             "distancemin": 0, "distancemax": Double.leastNonzeroMagnitude],
                            randomState: eighthState)
        let zeroDraw = run(["directions": "1e200 0 0", "sign": "1 0 0", "instantaneous": 1,
                            "distancemin": 1e-200, "distancemax": 1e200], randomState: zeroState)
        let zeroRadius = run(["directions": "1e308 -1e308 1e308", "origin": "7 8 9",
                              "distancemin": 0, "distancemax": 0])
        let launch: [String: Any] = ["origin": "7 8 9", "distancemin": 0, "distancemax": 0,
                                    "speedmin": 12, "speedmax": 12]
        let variableLaunch = launch.merging(["directions": "1 0 0", "speedmin": 5]) { _, v in v }
        let weightedLaunch = launch.merging(["directions": "4 .25 0"]) { _, v in v }
        let zeroLaunch = [
            "plane": run(launch),
            "positive": run(launch.merging(["directions": "1 0 0", "sign": "1 0 0"]) { _, v in v }),
            "renamed": run(launch.merging(["directions": ["user": "travelAxes", "value": [1, 0, 0]],
                                            "sign": "-1 0 0"]) { _, v in v }, renamed: true),
            "negative": run(launch.merging(["directions": "1 0 0", "speedmin": -12,
                                             "speedmax": -12]) { _, v in v }),
            "zeroSpeed": run(launch.merging(["speedmin": 0, "speedmax": 0]) { _, v in v }),
            "noAxis": run(launch.merging(["directions": "0 0 0"]) { _, v in v }),
            "zAxis": run(launch.merging(["directions": "0 0 1"]) { _, v in v }),
            "positiveRadius": run(launch.merging(["distancemin": 1, "distancemax": 1,
                                                   "directions": "1 0 0", "sign": "1 0 0"]) { _, v in v }),
            "variableZero": run(variableLaunch),
            "variablePositive": run(variableLaunch.merging(["distancemin": 1, "distancemax": 1]) { _, v in v }),
            "weightedZero": run(weightedLaunch),
            "weightedPositive": run(weightedLaunch.merging(["distancemin": 1, "distancemax": 1]) { _, v in v }),
            "scaledWeights": run(launch.merging(["directions": "1e308 -6.25e306 0"]) { _, v in v }),
        ]
        let threshold = 1e-6
        let thresholds = [("below", threshold.nextDown), ("at", threshold),
                          ("above", threshold.nextUp), ("negative-below", -threshold.nextDown),
                          ("negative-at", -threshold), ("negative-above", -threshold.nextUp)].map { name, axis in
            ["name": name, "actual": run(["directions": [axis, 1, 0]])] as [String: Any]
        }

        let peerFields: [String: Any] = ["instantaneous": 1, "origin": "7 8 9",
                                        "directions": "0 0 0", "distancemin": 0, "distancemax": 0]
        let peerReference = run(peerFields)
        var invalid: [[String: Any]] = []
        for (name, raw) in [("short", "1 0" as Any), ("malformed", "not-a-vector" as Any),
                            ("nan", "nan 1 0" as Any), ("infinity", "inf 1 0" as Any),
                            ("bool", true as Any)] {
            invalid.append(["name": name, "actual": run(["directions": raw, "instantaneous": 1], peer: true)])
        }
        for (name, fields) in [
            ("infinite-maximum", ["distancemin": 2, "distancemax": Double.infinity]),
            ("infinite-minimum", ["distancemin": Double.infinity, "distancemax": 4]),
        ] {
            invalid.append(["name": name, "actual": run(fields.merging(["instantaneous": 1]) { _, v in v }, peer: true)])
        }

        let finiteOverflow: [String: Any] = ["directions": "1 1 1", "instantaneous": 2,
                                             "distancemin": 1e200, "distancemax": 2e200]
        let floatOverflow: [String: Any] = ["name": "boxrandom", "directions": "1e39 0 0",
                                            "instantaneous": 2, "distancemin": "1 0 0", "distancemax": "1 0 0"]
        let speedBirths = try [
            "world": speedBirth(initializerY: true),
            "local": speedBirth(world: false, initializerY: true),
            "diagonalInward": speedBirth(["directions": "1 1 0", "sign": "1 1 0",
                                           "speedmin": -12, "speedmax": -12]),
            "controlPoint": speedBirth(["controlpoint": 1]),
            "worldMovement": speedBirth(worldMovement: true),
            "explicit": speedBirth(explicit: true),
            "tinyWorld": speedBirth(["distancemin": 1e-5, "distancemax": 1e-5], scaleX: 1e-8),
            "tinyLocal": speedBirth(["distancemin": 5e-13, "distancemax": 5e-13], scaleX: 1e9),
            "zeroWorld": speedBirth(["distancemin": 0, "distancemax": 0]),
            "zeroLocal": speedBirth(["distancemin": 0, "distancemax": 0], world: false),
            "zeroExplicit": speedBirth(["distancemin": 0, "distancemax": 0], explicit: true),
        ]
        let payload: [String: Any] = [
            "equivalents": equivalents, "rngProbes": probes, "subnormal": subnormal,
            "zeroDraw": zeroDraw, "zeroRadius": zeroRadius, "thresholds": thresholds, "invalid": invalid,
            "speedBirths": speedBirths, "zeroLaunch": zeroLaunch,
            "peerReference": peerReference,
            "finiteOverflow": run(finiteOverflow, peer: true),
            "finiteOverflowReference": run(["directions": "1 1 1", "instantaneous": 2], peer: true),
            "floatOverflow": run(floatOverflow, peer: true),
            "floatOverflowReference": run(["name": "boxrandom", "directions": "1 0 0",
                                            "instantaneous": 2, "distancemin": "1 0 0", "distancemax": "1 0 0"], peer: true),
            "transaction": transaction(["directions": [scale, scale, 0],
                                         "distancemin": inverse, "distancemax": 4 * inverse]),
            "overflowTransaction": transaction(finiteOverflow),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
