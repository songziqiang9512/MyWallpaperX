import Foundation
import simd

@main
enum SceneParticleControlPointComponentsHarness {
    static var results: [String: Bool] = [:]
    static var observed: [String: Any] = [:]

    static func definition(_ root: [String: Any]) throws -> SceneParticleDefinition {
        try SceneParticleDefinitionParser().parse(data: JSONSerialization.data(withJSONObject: root))
    }

    static func root(
        between: [String: Any]? = nil, instantaneous: Int = 3, rate: Double = 0,
        origin: String = "0 0 0", velocity: String? = nil, size: Double = 24,
        controlPoints: [[String: Any]]? = nil, operators: [[String: Any]] = [], flags: Int = 0
    ) -> [String: Any] {
        var writers: [[String: Any]] = [
            ["id": 2, "name": "lifetimerandom", "min": 3600, "max": 3600],
            ["id": 3, "name": "sizerandom", "min": size, "max": size],
            ["id": 4, "name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
            ["id": 5, "name": "alpharandom", "min": 1, "max": 1],
        ]
        if let velocity { writers.append(["id": 8, "name": "velocityrandom", "min": velocity, "max": velocity]) }
        if let between { writers.append(between) }
        return ["material": "owned/component.json", "maxcount": 64, "flags": flags,
                "controlpoint": controlPoints ?? [
                    ["id": 0, "flags": 0, "offset": "0 0 0"],
                    ["id": 1, "flags": 0, "offset": "192 0 0"]],
                "emitter": [["id": 1, "name": "sphererandom", "flags": 0,
                    "origin": origin, "directions": "1 0 0", "sign": "1 1 1",
                    "distancemin": 0, "distancemax": 0, "speedmin": 0, "speedmax": 0,
                    "instantaneous": instantaneous, "rate": rate]],
                "initializer": writers, "operator": operators,
                "renderer": [["id": 7, "name": "sprite"]], "children": []]
    }

    static func simulator(
        _ raw: [String: Any], instance: [String: Any]? = nil,
        frame: SceneParticleControlPointFrame? = nil,
        initialParticleSpace: SceneParticleControlPointParticleSpace? = nil,
        initialPoints: [Int: SIMD3<Double>] = [:], initialAngles: [Int: SIMD3<Double>] = [:],
        stopped: Bool = false,
        step: Double = 0.25
    ) throws -> SceneParticleSimulator {
        SceneParticleSimulator(
            definition: try definition(raw),
            instanceOverride: SceneParticleDefinitionParser().parseInstanceOverride(instance),
            initialDynamicControlPoints: initialPoints,
            initialDynamicControlPointAngles: initialAngles,
            initialPlayback: .init(intent: stopped ? .stopped : .playing),
            seed: 71, fixedTimeStep: step, controlPointFrame: frame,
            initialControlPointParticleSpace: initialParticleSpace
        )
    }

    static func points(_ particles: [SceneParticleState]) -> [[Double]] {
        particles.map { [$0.position.x, $0.position.y, $0.position.z] }
    }

    static func matches(_ actual: [[Double]], _ expected: [[Double]], tolerance: Double = 1e-8) -> Bool {
        guard actual.count == expected.count else { return false }
        for (row, wanted) in zip(actual, expected) {
            guard row.count == wanted.count else { return false }
            for (value, target) in zip(row, wanted) where !value.isFinite || abs(value - target) > tolerance {
                return false
            }
        }
        return true
    }

    static func sizes(_ sim: SceneParticleSimulator, _ expected: [Double]) -> Bool {
        matches([sim.particles.map(\.size)], [expected])
    }

    static func velocities(_ sim: SceneParticleSimulator, _ expected: [[Double]]) -> Bool {
        matches(sim.particles.map { [$0.velocity.x, $0.velocity.y, $0.velocity.z] }, expected)
    }

    static func record(_ name: String, _ sim: SceneParticleSimulator) {
        observed[name] = ["positions": points(sim.particles), "sizes": sim.particles.map(\.size),
                          "velocities": sim.particles.map { [$0.velocity.x, $0.velocity.y, $0.velocity.z] },
                          "ids": sim.particles.map(\.id)]
    }

    static func between(_ fields: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["id": 10, "name": "mapsequencebetweencontrolpoints"]
        value.merge(fields) { _, replacement in replacement }
        return value
    }

    static func parseCases() throws {
        let implicit = try simulator(root(between: between(), instantaneous: 3))
        let explicit = try simulator(root(between: between(["count": 32, "bounds": "0 1",
            "controlpointstart": 0, "controlpointend": 1, "limitbehavior": "repeat", "flags": 0]), instantaneous: 3))
        implicit.advance(by: 0.25); explicit.advance(by: 0.25)
        results["parse/missing-defaults-equal-explicit-state-and-rng"] =
            implicit.particles == explicit.particles && implicit.particles.count == 3
            && implicit.frameSnapshot().random.state == explicit.frameSnapshot().random.state
        results["parse/default-count32-has-literal-first-spacing"] = matches(points(implicit.particles),
            [[0, 0, 0], [6.193548387096774, 0, 0], [12.387096774193548, 0, 0]])
        var renamedRoot = root(between: between(["count": 4]), instantaneous: 4)
        renamedRoot["material"] = "renamed/deeper/pigment.json"
        var writers = renamedRoot["initializer"] as! [[String: Any]]
        writers[writers.count - 1]["id"] = 931
        writers[writers.count - 1]["authorLabel"] = ["not-a-runtime-permit": "different"]
        renamedRoot["initializer"] = writers
        let renamed = try simulator(renamedRoot)
        let ordinary = try simulator(root(between: between(["count": 4]), instantaneous: 4))
        renamed.advance(by: 0.25); ordinary.advance(by: 0.25)
        results["parse/renamed-resource-id-and-unrelated-field-keep-real-state"] =
            renamed.particles == ordinary.particles && renamed.particles.count == 4
        var sourceRoot = root(between: between(["count": 1]), instantaneous: 1,
            controlPoints: [["id": 0, "flags": 0, "offset": "10 0 0"],
                ["id": 1, "flags": 0, "offset": "202 0 0"],
                ["id": 2, "flags": 0, "offset": "100 50 0"],
                ["id": 3, "flags": 0, "offset": "300 70 0"]])
        var sources = sourceRoot["emitter"] as! [[String: Any]]
        sources[0]["controlpoint"] = 2; sources[0]["origin"] = "3 5 0"
        var another = sources[0]
        another["id"] = 41; another["controlpoint"] = 3; another["origin"] = "7 9 0"
        sources.append(another); sourceRoot["emitter"] = sources
        let actualSource = try simulator(sourceRoot); actualSource.advance(by: 0.25)
        results["parse/each-birth-removes-its-own-emitter-cp-translation-only"] =
            matches(points(actualSource.particles), [[13, 5, 0], [17, 9, 0]])
        record("defaults", implicit); record("renamed", renamed)
        record("per-birth-source", actualSource)
    }

    static func sequenceCases() throws {
        let repeat4 = try simulator(root(between: between(["count": 4]), instantaneous: 5))
        let mirror4 = try simulator(root(between: between(["count": 4, "limitbehavior": "mirror"]), instantaneous: 7))
        let repeat5 = try simulator(root(between: between(["count": 5]), instantaneous: 6))
        let mirror5 = try simulator(root(between: between(["count": 5, "limitbehavior": "mirror"]), instantaneous: 9))
        let single = try simulator(root(between: between(["count": 1, "limitbehavior": "mirror"]), instantaneous: 3))
        for sim in [repeat4, mirror4, repeat5, mirror5, single] { sim.advance(by: 0.25) }
        results["sequence/repeat4-includes-endpoint"] = matches(points(repeat4.particles),
            [[0, 0, 0], [64, 0, 0], [128, 0, 0], [192, 0, 0], [0, 0, 0]])
        results["sequence/mirror4-does-not-repeat-turning-endpoint"] = matches(points(mirror4.particles),
            [[0, 0, 0], [64, 0, 0], [128, 0, 0], [192, 0, 0], [128, 0, 0], [64, 0, 0], [0, 0, 0]])
        results["sequence/repeat5-includes-endpoint"] = matches(points(repeat5.particles),
            [[0, 0, 0], [48, 0, 0], [96, 0, 0], [144, 0, 0], [192, 0, 0], [0, 0, 0]])
        results["sequence/mirror5-literal-return-sequence"] = matches(points(mirror5.particles),
            [[0, 0, 0], [48, 0, 0], [96, 0, 0], [144, 0, 0], [192, 0, 0],
             [144, 0, 0], [96, 0, 0], [48, 0, 0], [0, 0, 0]])
        results["sequence/single-count-mirror-stays-finite-at-start"] = matches(points(single.particles),
            [[0, 0, 0], [0, 0, 0], [0, 0, 0]])
        let scaled = try simulator(root(between: between(["count": 4, "flags": 16]), instantaneous: 2),
                                   instance: ["count": 1.15])
        let disabled = try simulator(root(between: between(["count": 4, "flags": 16]), instantaneous: 2, flags: 32),
                                     instance: ["count": 1.15])
        let noBit = try simulator(root(between: between(["count": 4, "flags": 0]), instantaneous: 2),
                                  instance: ["count": 1.15])
        let twice = try simulator(root(between: between(["count": 4, "flags": 16]), instantaneous: 2),
                                  instance: ["count": 2])
        for sim in [scaled, disabled, noBit, twice] { sim.advance(by: 0.25) }
        results["sequence/count-float-is-not-rounded-before-mapping"] = matches(points(scaled.particles),
            [[0, 0, 0], [53.333333333333336, 0, 0]])
        results["sequence/general32-keeps-original-count-override-owner"] = matches(points(disabled.particles),
            [[0, 0, 0], [64, 0, 0]])
        results["sequence/count-bit-off-does-not-scale-the-path"] = matches(points(noBit.particles),
            [[0, 0, 0], [64, 0, 0]])
        results["sequence/count-bit-on-uses-current-instance-count"] = matches(points(twice.particles),
            [[0, 0, 0], [27.428571428571427, 0, 0]])
        let liveCount = try simulator(root(between: between(["count": 4, "flags": 16]),
            instantaneous: 0, rate: 1), instance: ["count": 1], step: 1)
        liveCount.advance(by: 1)
        liveCount.advance(by: 1, dynamicInstanceOverride: SceneParticleDefinitionParser().parseInstanceOverride(["count": 2]))
        results["sequence/later-births-use-the-live-count-value"] = matches(points(liveCount.particles),
            [[0, 0, 0], [27.428571428571427, 0, 0], [54.857142857142854, 0, 0]])
        record("repeat4", repeat4); record("mirror5", mirror5); record("scaled-count", scaled)
        record("twice-count", twice)
    }

    static func flagCases() throws {
        var simulations: [Int: SceneParticleSimulator] = [:]
        for flags in [0, 1, 2, 4, 16, 23] {
            let sim = try simulator(root(between: between(["count": 5, "flags": flags]),
                                         origin: "0 96 0", velocity: "0 16 0"))
            sim.advance(by: 0.25); simulations[flags] = sim
        }
        let unchanged = [[0.0, 96, 0], [48, 96, 0], [96, 96, 0]]
        let enveloped = [[0.0, 0, 0], [48, 72, 0], [96, 96, 0]]
        let unchangedVelocity = [[0.0, 16, 0], [0, 16, 0], [0, 16, 0]]
        let envelopedVelocity = [[0.0, 0, 0], [0, 12, 0], [0, 16, 0]]
        results["flags/zero-preserves-position-velocity-and-size"] =
            matches(points(simulations[0]!.particles), unchanged)
            && velocities(simulations[0]!, unchangedVelocity) && sizes(simulations[0]!, [24, 24, 24])
        results["flags/one-only-envelopes-existing-position"] =
            matches(points(simulations[1]!.particles), enveloped)
            && velocities(simulations[1]!, unchangedVelocity) && sizes(simulations[1]!, [24, 24, 24])
        results["flags/two-only-envelopes-existing-velocity"] =
            matches(points(simulations[2]!.particles), unchanged)
            && velocities(simulations[2]!, envelopedVelocity) && sizes(simulations[2]!, [24, 24, 24])
        // Numeric size values are the project contract; the official oracle only measured ordering.
        results["flags/four-only-reduces-size"] = matches(points(simulations[4]!.particles), unchanged)
            && velocities(simulations[4]!, unchangedVelocity) && sizes(simulations[4]!, [2.4, 18.6, 24])
        results["flags/sixteen-count1-does-not-change-other-writers"] =
            simulations[16]!.particles == simulations[0]!.particles
        results["flags/combination23-consumes-independent-options"] =
            matches(points(simulations[23]!.particles), enveloped)
            && velocities(simulations[23]!, envelopedVelocity) && sizes(simulations[23]!, [2.4, 18.6, 24])
        let half = try simulator(root(between: between(["count": 5, "flags": 4, "sizereductionamount": 0.5])))
        let full = try simulator(root(between: between(["count": 5, "flags": 4, "sizereductionamount": 1])))
        half.advance(by: 0.25); full.advance(by: 0.25)
        results["flags/explicit-size-amount-half"] = sizes(half, [12, 21, 24])
        results["flags/explicit-size-amount-one-keeps-zero-size-birth"] = sizes(full, [0, 18, 24])
        var lateRoot = root(between: between(["count": 5, "flags": 6]), velocity: "0 16 0")
        var writers = lateRoot["initializer"] as! [[String: Any]]
        writers.append(["name": "velocityrandom", "min": "0 7 0", "max": "0 7 0"])
        writers.append(["name": "sizerandom", "min": 9, "max": 9])
        lateRoot["initializer"] = writers
        let late = try simulator(lateRoot); late.advance(by: 0.25)
        results["flags/author-ordered-following-writers-execute-after-enveloping"] =
            velocities(late, [[0, 7, 0], [0, 19, 0], [0, 23, 0]]) && sizes(late, [9, 9, 9])
        record("flags23", simulations[23]!); record("size-half", half); record("following-writers", late)
    }

    static func failureCases() throws {
        for bit in [8, 32] {
            let sim = try simulator(root(between: between(["count": 5, "flags": bit]), origin: "0 96 0"))
            sim.advance(by: 0.25)
            var partial = sim.definition.initializers.last?.positionBetweenControlPointsPlan?.hasUnconsumedOptions == true
#if DEBUG
            partial = partial && sim.diagnostics.contains { $0.kind == .positionBetweenControlPointsPartial }
#endif
            results["failure/unconsumed-bit\(bit)-keeps-core-and-reports-partial"] = partial
                && matches(points(sim.particles), [[0, 96, 0], [48, 96, 0], [96, 96, 0]])
        }
        let badAmount = try simulator(root(between: between(["count": 5, "flags": 5,
            "sizereductionamount": "not-a-number"]), origin: "0 96 0"))
        badAmount.advance(by: 0.25)
        var partialAmount = badAmount.definition.initializers.last?.positionBetweenControlPointsPlan?.hasUnconsumedOptions == true
#if DEBUG
        partialAmount = partialAmount && badAmount.diagnostics.contains { $0.kind == .positionBetweenControlPointsPartial }
#endif
        results["failure/bad-size-option-does-not-disable-valid-position-option"] = partialAmount
            && matches(points(badAmount.particles), [[0, 0, 0], [48, 72, 0], [96, 96, 0]])
            && sizes(badAmount, [24, 24, 24])
        let worldPoints: [[String: Any]] = [["id": 0, "flags": 2, "offset": "100 80 0"],
                                           ["id": 1, "flags": 2, "offset": "164 32 0"]]
        var missingRoot = root(between: between(["count": 3]), instantaneous: 1,
                               origin: "12 7 0", controlPoints: worldPoints)
        var emitters = missingRoot["emitter"] as! [[String: Any]]
        var peer = emitters[0]; peer["id"] = 23; peer["origin"] = "40 20 0"; emitters.append(peer)
        missingRoot["emitter"] = emitters
        var writers = missingRoot["initializer"] as! [[String: Any]]
        writers.append(["name": "alpharandom", "min": 0.25, "max": 0.25])
        missingRoot["initializer"] = writers
        let missing = try simulator(missingRoot); missing.advance(by: 0.25)
        results["failure/missing-world-frame-skips-only-between-writer"] =
            matches(points(missing.particles), [[12, 7, 0], [40, 20, 0]])
            && missing.particles.map(\.alpha) == [0.25, 0.25]
            && missing.particles.map(\.id) == [0, 1]
        let badIndex = try simulator(root(between: between(["controlpointend": 9]),
                                         instantaneous: 1, origin: "12 7 0"))
        badIndex.advance(by: 0.25)
        results["failure/bad-endpoint-identity-does-not-reject-the-birth"] =
            matches(points(badIndex.particles), [[12, 7, 0]]) && sizes(badIndex, [24])
        record("missing-world-frame", missing); record("bad-size-option", badAmount)
    }

    static let maintain: [String: Any] = ["id": 10, "name": "maintaindistancebetweencontrolpoints",
                                        "controlpointstart": 0, "controlpointend": 1]
    static let movement: [String: Any] = ["id": 9, "name": "movement", "gravity": "0 0 0", "drag": 0]
    static let localEndpoints: [[String: Any]] = [["id": 0, "flags": 0, "offset": "0 0 0"],
                                                 ["id": 1, "flags": 0, "offset": "64 0 0"]]

    static func maintainCases() throws {
        let still = try simulator(root(instantaneous: 1, origin: "16 24 0",
            controlPoints: localEndpoints, operators: [maintain]))
        let normal = try simulator(root(instantaneous: 1, origin: "16 24 0", velocity: "0 8 0",
            controlPoints: localEndpoints, operators: [movement, maintain]), step: 1.0 / 60)
        for sim in [still, normal] { sim.advance(by: 2) }
        results["maintain/t2-keeps-off-axis-current-position"] = matches(points(still.particles), [[16, 24, 0]])
            && matches(points(normal.particles), [[16, 40, 0]])
        var warmRoot = root(instantaneous: 1, origin: "16 24 0",
            controlPoints: localEndpoints, operators: [maintain])
        warmRoot["starttime"] = 0.5
        let initial = try simulator(warmRoot, initialPoints: [1: SIMD3(128, 0, 0)])
        results["maintain/prewarm-uses-initial-typed-endpoints"] = matches(points(initial.particles), [[16, 24, 0]])
            && initial.simulationTime > 0
        initial.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        results["maintain/first-live-same-endpoints-do-not-apply-a-false-delta"] =
            matches(points(initial.particles), [[16, 24, 0]])
        var angledRoot = root(instantaneous: 1, origin: "2 0 0", controlPoints: localEndpoints)
        angledRoot["starttime"] = 0.5
        var angledEmitters = angledRoot["emitter"] as! [[String: Any]]
        angledEmitters[0]["controlpoint"] = 1; angledRoot["emitter"] = angledEmitters
        let angled = try simulator(angledRoot, initialPoints: [1: SIMD3(128, 0, 0)],
                                  initialAngles: [1: SIMD3(0, 0, Double.pi / 2)])
        results["maintain/prewarm-birth-consumes-initial-position-and-angle"] =
            matches(points(angled.particles), [[128, 2, 0]])
        for sim in [still, normal] {
            sim.advance(by: 2)
            sim.advance(by: 2, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        }
        results["maintain/t6-stretch-preserves-normal-motion"] = matches(points(still.particles), [[32, 24, 0]])
            && matches(points(normal.particles), [[32, 72, 0]]) && velocities(normal, [[0, 8, 0]])
        let saved = still.frameSnapshot()
        still.advance(by: 1, dynamicControlPoints: [1: SIMD3(192, 0, 0)])
        let replayed = still.frameSnapshot()
        still.restoreFrame(saved)
        still.advance(by: 1, dynamicControlPoints: [1: SIMD3(192, 0, 0)])
        results["maintain/snapshot-restores-endpoint-history-for-the-next-delta"] =
            matches(points(still.particles), [[48, 24, 0]]) && still.particles == replayed.particles
            && still.frameSnapshot().random.state == replayed.random.state
        still.restoreFrame(saved)
        for sim in [still, normal] {
            sim.advance(by: 2, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
            sim.advance(by: 4, dynamicControlPoints: [1: SIMD3(128, 32, 0)])
        }
        results["maintain/t12-bend-keeps-normal-offset-and-motion"] = matches(points(still.particles), [[32, 32, 0]])
            && matches(points(normal.particles), [[32, 128, 0]]) && velocities(normal, [[0, 8, 0]])
        let axial = try simulator(root(instantaneous: 1, origin: "16 24 0", velocity: "8 0 0",
            controlPoints: localEndpoints, operators: [movement, maintain]), step: 1.0 / 60)
        axial.advance(by: 4)
        axial.advance(by: 2, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        // Manual oracle center112.8 had ±0.8world localization, plus fixed-step event phase.
        results["maintain/axial-current-position-excludes-fixed-birth-and-no-delta"] =
            matches(points(axial.particles), [[112, 24, 0]], tolerance: 1)
            && velocities(axial, [[8, 0, 0]])
        var newbornRoot = root(instantaneous: 0, rate: 1, controlPoints: localEndpoints, operators: [maintain])
        var emitters = newbornRoot["emitter"] as! [[String: Any]]
        emitters[0]["controlpoint"] = 1; newbornRoot["emitter"] = emitters
        let newborn = try simulator(newbornRoot, step: 1)
        newborn.advance(by: 1)
        newborn.advance(by: 1, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        results["maintain/current-frame-newborn-does-not-receive-the-old-delta-twice"] =
            matches(points(newborn.particles), [[128, 0, 0], [128, 0, 0]])
            && newborn.particles.map(\.id) == [0, 1]
        var pointerPoints = localEndpoints; pointerPoints[1] = ["id": 1, "flags": 1, "offset": "0 0 0"]
        let missing = try simulator(root(instantaneous: 1, origin: "16 24 0",
            controlPoints: pointerPoints, operators: [maintain]))
        missing.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(64, 0, 0)])
        missing.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        missing.advance(by: 0.25)
        missing.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(256, 0, 0)])
        results["maintain/missing-supply-clears-history-and-rebuilds-baseline"] =
            matches(points(missing.particles), [[32, 24, 0]])
        missing.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(512, 0, 0)])
        results["maintain/recovered-baseline-supports-later-delta"] = matches(points(missing.particles), [[64, 24, 0]])
        var duplicatePoints = localEndpoints
        duplicatePoints.append(["id": 2, "flags": 0, "offset": "0 64 0"])
        var second = maintain; second["id"] = 11; second["controlpointend"] = 2
        let multiple = try simulator(root(instantaneous: 1, origin: "16 24 0",
            controlPoints: duplicatePoints, operators: [maintain, second]))
        multiple.advance(by: 0.25)
        multiple.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(128, 0, 0), 2: SIMD3(0, 128, 0)])
        results["maintain/authored-operators-own-separate-endpoint-history"] =
            matches(points(multiple.particles), [[32, 48, 0]])
        let collapsed = try simulator(root(instantaneous: 1, origin: "16 24 0",
            controlPoints: localEndpoints, operators: [maintain]))
        collapsed.advance(by: 0.25)
        collapsed.advance(by: 0.25, dynamicControlPoints: [1: .zero])
        results["maintain/current-endpoints-may-collapse-without-rejecting-the-particle"] =
            matches(points(collapsed.particles), [[0, 24, 0]])
        collapsed.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(64, 0, 0)])
        collapsed.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(128, 0, 0)])
        results["maintain/previous-degenerate-axis-does-not-poison-future-state"] =
            matches(points(collapsed.particles), [[0, 24, 0]])
        record("maintain-t12", normal); record("maintain-axial", axial); record("maintain-newborn", newborn)
    }

    static func frame(_ translation: SIMD3<Float>) -> SceneParticleControlPointFrame? {
        SceneParticleControlPointFrame(worldFrame: .init(columns: (
            SIMD4(-2, 0, 0, 0), SIMD4(0, 3, 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(translation.x, translation.y, translation.z, 1)
        )), sceneOrthoHeight: 256)
    }

    static let worldEndpoints: [[String: Any]] = [["id": 0, "flags": 2, "offset": "100 80 0"],
                                                 ["id": 1, "flags": 2, "offset": "164 32 0"]]

    static func worldCases() throws {
        guard let first = frame(SIMD3(100, 176, 0)), let second = frame(SIMD3(164, 128, 0)) else {
            results["world/finite-mirrored-frame-is-constructible"] = false; return
        }
        results["world/finite-mirrored-frame-is-constructible"] = true
        let raw = root(between: between(["count": 3]), controlPoints: worldEndpoints)
        let mirrored = try simulator(raw, frame: first)
        mirrored.advance(by: 0.25, controlPointFrame: first)
        results["world/nonzero-translation-mirror-and-nonuniform-scale-map-points"] =
            matches(points(mirrored.particles), [[0, 0, 0], [-16, -8, 0], [-32, -16, 0]])
        let translated = try simulator(raw, frame: second)
        translated.advance(by: 0.25, controlPointFrame: second)
        results["world/current-frame-replaces-the-previous-conversion"] =
            matches(points(translated.particles), [[32, -16, 0], [16, -24, 0], [0, -32, 0]])
        let absent = try simulator(raw, frame: second)
        absent.advance(by: 0.25, controlPointFrame: nil)
        results["world/nil-ordinary-frame-does-not-borrow-the-init-frame"] =
            matches(points(absent.particles), [[0, 0, 0], [0, 0, 0], [0, 0, 0]])
        var warmRoot = raw; warmRoot["starttime"] = 0.5
        let prewarmed = try simulator(warmRoot, frame: first)
        results["world/prewarm-uses-its-own-initial-frame"] = matches(points(prewarmed.particles),
            [[0, 0, 0], [-16, -8, 0], [-32, -16, 0]])
        let childFrame = first.childFrame(origin: SIMD3(8, -4, 0), scale: SIMD3(-2, 4, 1))
        let child = try simulator(raw, frame: childFrame)
        child.advance(by: 0.25, controlPointFrame: childFrame)
        results["world/child-origin-and-signed-nonuniform-scale-map-the-same-world-points"] =
            matches(points(child.particles), [[4, 1, 0], [12, -1, 0], [20, -3, 0]])
        record("world-child-frame", child)
        let smallFrame = first.childFrame(origin: SIMD3(8, -4, 0),
                                         scale: SIMD3(repeating: 1.0 / 1024))
        let smallChild = try simulator(raw, frame: smallFrame)
        smallChild.advance(by: 0.25, controlPointFrame: smallFrame)
        results["world/child-valid-small-scale-keeps-finite-authored-positions"] = matches(
            points(smallChild.particles), [[-8192, 4096, 0], [-24576, -4096, 0], [-40960, -12288, 0]])
        record("world-first", mirrored); record("world-second", translated)
    }

    static func explicitCases() throws {
        guard let first = frame(SIMD3(100, 176, 0)), let second = frame(SIMD3(164, 128, 0)) else {
            results["explicit/frame-construction"] = false; return
        }
        let sim = try simulator(root(between: between(["count": 3]), controlPoints: worldEndpoints),
                                frame: first, stopped: true)
        let original = sim.frameSnapshot()
        let commands: [(SceneParticlePlaybackTransition, SceneParticleSimulator.EmissionContext?)] = [
            (.init(layerID: 42, action: .emit, revision: 1, count: 1), .init(controlPointFrame: second)),
            (.init(layerID: 42, action: .emit, revision: 2, count: 1), .init(controlPointFrame: first)),
        ]
        let candidate = try sim.preparePlaybackCandidate(commands: commands, charge: { _, _ in }, release: { _ in })
        results["explicit/each-command-uses-its-own-transform-prefix"] = matches(points(candidate.state.particles),
            [[32, -16, 0], [-16, -8, 0]]) && candidate.state.particles.map(\.id) == [0, 1]
        results["explicit/candidate-restores-original-population-rng-and-frame"] =
            sim.particles == original.particles && sim.frameSnapshot().nextParticleID == original.nextParticleID
            && sim.frameSnapshot().random.state == original.random.state
            && sim.frameSnapshot().controlPointFrame == original.controlPointFrame
        var rejected = false
        do {
            var invalidPrefix = commands
            invalidPrefix.append((.init(layerID: 42, action: .emit, revision: 3, count: 1),
                                  .init(controlPointFrame: nil)))
            _ = try sim.preparePlaybackCandidate(commands: invalidPrefix, charge: { _, _ in }, release: { _ in })
        } catch { rejected = true }
        results["explicit/nil-prefix-cannot-borrow-an-earlier-frame"] = rejected
            && sim.particles.isEmpty && sim.frameSnapshot().random.state == original.random.state
            && sim.frameSnapshot().nextParticleID == original.nextParticleID
        observed["explicit-prefix"] = points(candidate.state.particles)
    }

    static func worldFollowCases() throws {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(0, 256, 0, 1)
        guard let rootFrame = SceneParticleControlPointFrame(worldFrame: matrix, sceneOrthoHeight: 256) else {
            results["maintain/world-follow-frame-construction"] = false; return
        }
        let child10 = rootFrame.childFrame(origin: SIMD3(10, 0, 0), scale: SIMD3(repeating: 1))
        let child20 = rootFrame.childFrame(origin: SIMD3(20, 0, 0), scale: SIMD3(repeating: 1))
        let endpoints: [[String: Any]] = [["id": 0, "flags": 2, "offset": "50 0 0"],
                                          ["id": 1, "flags": 2, "offset": "100 0 0"]]
        let raw = root(between: between(["count": 1, "bounds": "0.5 0.5"]), instantaneous: 1,
                       controlPoints: endpoints, operators: [maintain], flags: 1)
        let firstSpace = SceneParticleControlPointParticleSpace(
            currentOrigin: .zero, scale: SIMD3(repeating: 1), birthOrigins: [:])
        let sim = try simulator(raw, frame: rootFrame, initialParticleSpace: firstSpace)
        sim.advance(by: 0.25, controlPointFrame: rootFrame, controlPointParticleSpace: firstSpace)
        let birthOrigins: [UInt64: SIMD3<Double>] = [0: .zero]
        let movedSpace = SceneParticleControlPointParticleSpace(
            currentOrigin: SIMD3(10, 0, 0), scale: SIMD3(repeating: 1), birthOrigins: birthOrigins)
        sim.advance(by: 0.25, controlPointFrame: child10, controlPointParticleSpace: movedSpace)
        results["maintain/world-follow-stationary-endpoints-keep-old-particle75"] =
            matches(points(sim.particles), [[75, 0, 0]]) && sim.particles.map(\.id) == [0]
        record("world-follow-stationary", sim)
        sim.advance(by: 0.25, dynamicControlPoints: [1: SIMD3(120, 0, 0)],
                    controlPointFrame: child10, controlPointParticleSpace: movedSpace)
        results["maintain/world-follow-moved-endpoint-updates-old-particle85"] =
            matches(points(sim.particles), [[85, 0, 0]]) && velocities(sim, [[0, 0, 0]])
        var warmRoot = raw; warmRoot["starttime"] = 0.5
        let warmSpace = SceneParticleControlPointParticleSpace(
            currentOrigin: SIMD3(10, 0, 0), scale: SIMD3(repeating: 1), birthOrigins: [:])
        let warm = try simulator(warmRoot, frame: child10, initialParticleSpace: warmSpace)
        let beganAt65 = matches(points(warm.particles), [[65, 0, 0]])
        warm.advance(by: 0.25, controlPointFrame: child20,
                     controlPointParticleSpace: .init(currentOrigin: SIMD3(20, 0, 0),
                        scale: SIMD3(repeating: 1), birthOrigins: [0: SIMD3(10, 0, 0)]))
        results["maintain/world-follow-prewarm-baseline-shares-the-birth-origin-space"] =
            beganAt65 && matches(points(warm.particles), [[65, 0, 0]])
        record("world-follow-moved-endpoint", sim); record("world-follow-prewarm", warm)
    }

    static func main() throws {
        try parseCases()
        try sequenceCases()
        try flagCases()
        try failureCases()
        try maintainCases()
        try worldCases()
        try worldFollowCases()
        try explicitCases()
        let data = try JSONSerialization.data(withJSONObject: ["results": results, "observed": observed], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
