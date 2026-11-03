import Foundation

nonisolated enum SceneParticleComponentObservationChecks {
    static func run() throws -> [String: Bool] {
        let root: [String: Any] = [
            "material": "particle.json", "maxcount": 16,
            "emitter": [false,
                ["id": 7, "name": "boxrandom", "instantaneous": 1, "rate": 0],
                ["id": 7, "name": "boxrandom", "rate": 0]] as [Any],
            "initializer": [false,
                ["id": 7, "name": "lifetimerandom", "min": 2, "max": 2],
                ["id": 7, "name": "colorrandom", "min": "255 0 0", "max": "255 0 0"]] as [Any],
            "operator": [false, ["id": 7, "name": "movement", "gravity": "0 0 0"],
                ["id": 7, "name": "capvelocity", "maxspeed": 100],
                ["id": 7, "name": "futureoperator"]] as [Any],
            "renderer": [false, ["id": 7, "name": "sprite"],
                ["id": 7, "name": "sprite"]] as [Any],
            "children": [false, ["name": "child.json", "type": "static"]] as [Any],
            "controlpoint": [false, ["id": 0, "offset": "0 0 0"]] as [Any]
        ]
        let parser = SceneParticleDefinitionParser()
        let definition = parser.parse(root: root)
        func make(_ source: [String: Any]? = nil,
                  playback: SceneParticlePlaybackSnapshot = .init()) -> SceneParticleSimulator {
            SceneParticleSimulator(definition: parser.parse(root: source ?? root), initialPlayback: playback,
                                   fixedTimeStep: 0.25)
        }
        let simulation = make()
        simulation.observeSelectedRenderer(typedIndex: 0)
        simulation.advance(by: 0.25)
        if !SceneParticleDefinitionParser.componentObservationEnabled {
            return ["disabled-source-map-absent": definition.componentObservationSources == nil,
                    "disabled-state-absent": simulation.componentObservation == nil,
                    "disabled-no-facts": simulation.consumeComponentObservations().isEmpty,
                    "disabled-keeps-real-birth": simulation.particles.count == 1]
        }
        let facts = simulation.consumeComponentObservations()
        func has(_ category: String, _ index: Int, _ stage: String,
                 in values: [SceneParticleComponentObservation]? = nil) -> Bool {
            (values ?? facts).contains { $0.category == category && $0.componentIndex == index && $0.stage == stage }
        }
        var result: [String: Bool] = [:]
        result["raw-ordinals-survive-malformed-and-duplicate-identities"] =
            definition.componentObservationSources?["emitter"]?.map(\.componentIndex) == [1, 2]
            && definition.componentObservationSources?["initializer"]?.map(\.componentIndex) == [1, 2]
            && definition.componentObservationSources?["children"]?.map(\.componentIndex) == [1]
            && definition.componentObservationSources?["controlpoint"]?.map(\.componentIndex) == [1]
        result["actual-birth-keeps-emitter-ordinal"] = has("emitter", 1, "accepted-birth")
            && !has("emitter", 2, "accepted-birth") && has("emitter", 2, "not-triggered")
        result["actual-initializer-and-neutral-operator-evaluations"] = has("initializer", 2, "evaluated")
            && has("operator", 1, "evaluated") && simulation.particles.first?.color == SIMD3(1, 0, 0)
        result["helper-dispatch-is-unknown"] = has("operator", 2, "unknown")
            && !has("operator", 2, "evaluated")
        result["unknown-kind-is-reported-at-real-dispatch"] = has("operator", 3, "unsupported")
        result["only-selected-renderer-qualified"] = has("renderer", 1, "prepared-executable")
            && has("renderer", 2, "not-selected") && !has("renderer", 2, "prepared-executable")

        var zeroRoot = root
        zeroRoot["emitter"] = [["name": "boxrandom", "rate": 0]]
        let zero = make(zeroRoot)
        zero.advance(by: 0.25)
        let zeroFacts = zero.consumeComponentObservations()
        result["zero-particles-never-count-as-operator-evaluation"] = has("operator", 1, "not-triggered", in: zeroFacts)
            && !has("operator", 1, "evaluated", in: zeroFacts)
        let paused = make(playback: .init(intent: .paused))
        paused.advance(by: 0.25)
        result["paused-emitter-is-untriggered"] = !paused.consumeComponentObservations().contains {
            $0.category == "emitter" && ($0.stage == "attempted" || $0.stage == "accepted-birth")
        }

        var implicitRoot = root
        implicitRoot.removeValue(forKey: "renderer")
        let implicit = make(implicitRoot)
        implicit.observeSelectedRenderer(typedIndex: 0)
        let implicitFacts = implicit.consumeComponentObservations()
        result["implicit-renderer-has-no-authored-ordinal"] = has("renderer", -1, "prepared-executable", in: implicitFacts)
            && !implicitFacts.contains { $0.category == "renderer" && $0.componentIndex >= 0 }

        let restored = make()
        _ = restored.consumeComponentObservations()
        let checkpoint = restored.frameSnapshot()
        restored.advance(by: 0.25)
        let accepted = restored.consumeComponentObservations()
        restored.restoreFrame(checkpoint)
        let rollbackEmpty = restored.consumeComponentObservations().isEmpty
        restored.advance(by: 0.25)
        result["rollback-restores-first-facts"] = rollbackEmpty
            && accepted == restored.consumeComponentObservations()

        var explicitRoot = root
        explicitRoot["children"] = [] as [Any]
        explicitRoot["emitter"] = [false,
            ["name": "boxrandom", "instantaneous": 1, "rate": 0]] as [Any]
        let explicit = make(explicitRoot)
        _ = explicit.consumeComponentObservations()
        var charges = 0
        var sawCandidateBirthBeforeRejection = false
        do {
            _ = try explicit.preparePlaybackCandidate(
                commands: [(.init(layerID: 1, action: .emit, revision: 1, count: 2), SceneParticleSimulator.EmissionContext())],
                charge: { _, _ in
                    charges += 1
                    if charges == 4 {
                        sawCandidateBirthBeforeRejection = explicit.particles.count == 1
                        throw SceneParticleEmissionFailure.budgetExceeded
                    }
                }, release: { _ in })
            result["rejected-explicit-candidate-leaves-no-success"] = false
        } catch {
            result["rejected-explicit-candidate-leaves-no-success"] = charges == 4
                && sawCandidateBirthBeforeRejection && explicit.particles.isEmpty
                && explicit.consumeComponentObservations().isEmpty
        }
        let candidate = try explicit.preparePlaybackCandidate(
            commands: [(.init(layerID: 1, action: .emit, revision: 1, count: 1), SceneParticleSimulator.EmissionContext())],
            charge: { _, _ in }, release: { _ in })
        let pendingOutsideCandidate = explicit.consumeComponentObservations().isEmpty
        explicit.restoreFrame(candidate.state)
        result["installed-explicit-candidate-keeps-origin"] = pendingOutsideCandidate
            && explicit.consumeComponentObservations().contains {
                $0.category == "emitter" && $0.componentIndex == 1
                    && $0.stage == "accepted-birth" && $0.origin == "explicit"
            }
        return result
    }
}
