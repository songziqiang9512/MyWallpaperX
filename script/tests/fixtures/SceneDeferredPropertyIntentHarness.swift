import Foundation

@main enum Harness {
    static let a = SceneDynamicTarget.layer(layerID: 11, field: .visibility)
    static let b = SceneDynamicTarget.layer(layerID: 22, field: .visibility)
    static let level = SceneDynamicTarget.layer(layerID: 33, field: .alpha)
    static let optional = SceneDynamicTarget.scriptInstanceProperty(
        layerID: 44, path: ["optional"])
    static let particle = SceneDynamicTarget.layer(layerID: 42, field: .visibility)
    static let particleParent = SceneDynamicTarget.layer(layerID: 77, field: .visibility)

    static func make(particleCohort: Bool = false, parentParticleCohort: Bool = false)
        -> (SceneDesktopWallpaperSession, FixtureResources, FixtureAdoption) {
        let visibilityOwner = parentParticleCohort ? particleParent : particle
        let hasParticles = particleCohort || parentParticleCohort
        let preparedParticleIDs: Set<Int> = parentParticleCohort ? [42, 43] : (particleCohort ? [42] : [])
        let requirements: [Int: Set<Int>] = parentParticleCohort ? [77: [42, 43]] : (particleCohort ? [42: [42]] : [:])
        let particleDefinitions: [SceneDynamicTargetDefinition] = hasParticles
            ? [.init(target: visibilityOwner, valueType: .bool, authoredValue: .bool(false))] : []
        let particleInstructions: [ScenePropertyBindingInstruction] = hasParticles
            ? [.init(propertyKey: "A", path: .init(components: [.key("A")]),
                     target: visibilityOwner, valueType: .bool, condition: .string("on"))] : []
        let program = ScenePropertyBindingProgram(
            definitions: [
                .init(target: a, valueType: .bool, authoredValue: .bool(false)),
                .init(target: b, valueType: .bool, authoredValue: .bool(false)),
                .init(target: level, valueType: .scalar, authoredValue: .scalar(0.2)),
            ] + particleDefinitions,
            instructions: [
                .init(propertyKey: "A", path: .init(components: [.key("A")]),
                    target: a, valueType: .bool, condition: .string("on")),
                .init(propertyKey: "B", path: .init(components: [.key("B")]),
                    target: b, valueType: .bool, condition: .string("on")),
                .init(propertyKey: "level", path: .init(components: [.key("level")]),
                    target: level, valueType: .scalar),
            ] + particleInstructions,
            conditionalValueDomainsByPropertyKey: ["A": ["off", "on"], "B": ["off", "on"]]
        )
        let state = ScenePropertyLiveUpdateState(
            program: program,
            effectiveValues: ["A": .string("off"), "B": .string("off"),
                "level": .number(0.2), "optional": .string("seed")],
            activeConsumerTargets: Set([a, b, level, optional]).union(hasParticles ? [visibilityOwner] : []),
            scriptUserPropertyConsumerTargetsByKey: ["optional": [optional]]
        )
        let resources = FixtureResources()
        let adoption = FixtureAdoption()
        let session = SceneDesktopWallpaperSession(.init(recordID: "own-input",
            liveState: state, runtimeInput: .init(propertyBindingProgram: program),
            preparedDeviceResources: .init(baseImages: resources),
            particleLayerIDs: preparedParticleIDs, particleVisibilityRequirements: requirements))
        installSurfaces(session, adoption)
        session.surfaces.values.forEach { $0.metalView.preparedParticleLayerIDs = preparedParticleIDs }
        return (session, resources, adoption)
    }

    static func installSurfaces(_ session: SceneDesktopWallpaperSession,
                                _ adoption: FixtureAdoption) {
        session.surfaces = [1: .init(metalView: FixtureView(adoption)),
                           2: .init(metalView: FixtureView(adoption))]
        session.preparedSurfaceIDs = [1, 2]
    }

    static func apply(_ session: SceneDesktopWallpaperSession,
                      _ values: [String: SceneUserPropertyValue],
                      keys: Set<String>? = nil) -> Bool {
        session.applyUserPropertyValues(values,
            changedPropertyKeys: keys ?? Set(values.keys), recordID: "own-input")
    }

    static func snapshot(_ session: SceneDesktopWallpaperSession,
                         _ resources: FixtureResources) -> [String: Any] {
        let state = session.launchContext!.liveState
        func boolean(_ target: SceneDynamicTarget) -> Bool {
            guard case let .bool(value)? = state.userValues[target] else { return false }
            return value
        }
        let levelValue: Double
        if case let .scalar(value)? = state.userValues[level] { levelValue = value }
        else { levelValue = -1 }
        let optionalValue: Any
        if case let .string(value)? = state.effectiveValues["optional"] { optionalValue = value }
        else { optionalValue = NSNull() }
        let pending: Any
        if let value = session.pendingDeferredLayerVisibilityUpdate {
            pending = ["generation": value.generation,
                "keys": value.changedPropertyKeys.sorted(),
                "layers": value.layerIDs.sorted()] as [String: Any]
        } else { pending = NSNull() }
        let views = session.surfaces.keys.sorted().map { id -> [String: Any] in
            let view = session.surfaces[id]!.metalView
            return ["id": id, "staged": view.staged.sorted(),
                "committed": view.committed.sorted(), "attempts": view.attempts,
                "discards": view.discards, "commits": view.commits,
                "preparedParticleIDs": view.preparedParticleLayerIDs.sorted(),
                "scriptGeneration": session.surfaces[id]!.scriptGeneration]
        }
        return ["visible": [boolean(a), boolean(b)], "particleVisible": boolean(particle),
            "particleParentVisible": boolean(particleParent),
            "revision": state.revision, "level": levelValue,
            "optional": optionalValue, "pending": pending, "views": views,
            "requests": resources.requests.map { [Int($0.layerID), Int($0.generation)] },
            "soundApplies": session.soundPlaybackRegistry?.applies ?? 0]
    }

    static func candidateValueCases() -> [String: Any] {
        var output: [String: Any] = [:]
        do {
            let (session, resources, _) = make()
            let changed = apply(session, ["level": .number(0.7)])
            let repeated = apply(session, ["level": .number(0.7)])
            output["scalarWithoutVisibility"] = ["accepted": [changed, repeated],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            session.soundPlaybackRegistry!.accepts = false
            let before = snapshot(session, resources)
            let accepted = apply(session, ["A": .string("on")])
            output["soundAdmission"] = ["accepted": accepted,
                "before": before, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            session.soundPlaybackRegistry!.accepts = false
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["soundPromotion"] = ["accepted": show,
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let before = snapshot(session, resources)
            let wrongRecord = session.applyUserPropertyValues(["A": .string("off")],
                changedPropertyKeys: ["A"], recordID: "other-record")
            let after = snapshot(session, resources)
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["wrongRecord"] = ["accepted": [show, wrongRecord],
                "before": before, "after": after, "final": snapshot(session, resources)]
        }
        for (name, ids, selected) in [("choice", [101, 102, 103], "selected"),
                                     ("renamed_mode", [711, 722, 733], "equivalent_option")] {
            let key = "\(name)_layout"
            let scalarKey = "\(name)_opacity"
            let visibleTargets = ids.prefix(2).map { SceneDynamicTarget.layer(layerID: $0, field: .visibility) }
            let effect = SceneDynamicTarget.effectVisibility(layerID: ids[2], effectIndex: 0)
            let scalar = SceneDynamicTarget.layer(layerID: ids[2], field: .alpha)
            let booleanTargets = visibleTargets + [effect]
            let program = ScenePropertyBindingProgram(
                definitions: booleanTargets.map { .init(target: $0, valueType: .bool, authoredValue: .bool(false)) }
                    + [.init(target: scalar, valueType: .scalar, authoredValue: .scalar(0.2))],
                instructions: booleanTargets.map { .init(propertyKey: key, path: .init(components: [.key(key)]),
                    target: $0, valueType: .bool, condition: .string(selected)) }
                    + [.init(propertyKey: scalarKey, path: .init(components: [.key(scalarKey)]),
                        target: scalar, valueType: .scalar)],
                conditionalValueDomainsByPropertyKey: [key: ["disabled", selected]])
            let state = ScenePropertyLiveUpdateState(program: program,
                effectiveValues: [key: .string("disabled"), scalarKey: .number(0.2)],
                activeConsumerTargets: Set(booleanTargets + [scalar]))
            // Rename the resource identities too; the effect's ID is a nearby
            // deferred resource but must never be selected by a layer guard.
            let resources = FixtureResources(deferredLayerIDs: Set(ids))
            let session = SceneDesktopWallpaperSession(.init(recordID: "own-input", liveState: state,
                runtimeInput: .init(propertyBindingProgram: program),
                preparedDeviceResources: .init(baseImages: resources)))
            installSurfaces(session, FixtureAdoption())
            let neighbor = apply(session, [scalarKey: .number(0.8)])
            let neighborRequested = resources.requests.count
            let wrongType = apply(session, [key: .bool(true)])
            let wrongOption = apply(session, [key: .string("not-in-domain")])
            let invalidRequested = resources.requests.count
            let show = apply(session, [key: .string(selected)])
            let pendingLayers = session.pendingDeferredLayerVisibilityUpdate!.layerIDs.sorted()
            let unchangedNeighbor = apply(session, [scalarKey: .number(0.8)])
            resources.statuses[ids[0]] = .ready
            resources.statuses[ids[1]] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            let current = session.launchContext!.liveState
            let visible = booleanTargets.map { current.userValues[$0] == .bool(true) }
            let committedRevision = current.revision
            session.launchContext!.unavailable = [effect]
            let unavailable = apply(session, [key: .string("disabled")])
            let retained = session.launchContext!.liveState
            output["variant-\(name)"] = ["accepted": [neighbor, wrongType, wrongOption, show, unchangedNeighbor, unavailable],
                "neighborRequests": neighborRequested, "invalidRequests": invalidRequested,
                "pendingLayers": pendingLayers, "expectedLayers": Array(ids.prefix(2)), "visible": visible,
                "revision": committedRevision, "retainedRevision": retained.revision,
                "retainedVisible": booleanTargets.map { retained.userValues[$0] == .bool(true) },
                "scalar": current.userValues[scalar] == .scalar(0.8),
                "pendingCleared": session.pendingDeferredLayerVisibilityUpdate == nil,
                "requestedLayers": Set(resources.requests.map(\.layerID)).sorted(),
                "views": session.surfaces.values.map { ["staged": $0.metalView.staged.sorted(),
                                                        "committed": $0.metalView.committed.sorted()] }]
        }
        return output
    }

    static func main() throws {
        var output = candidateValueCases()
        do {
            let (session, resources, _) = make()
            let first = apply(session, ["A": .string("on")])
            let second = apply(session, ["B": .string("on")])
            let waiting = snapshot(session, resources)
            resources.statuses[11] = .ready
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["independent"] = ["accepted": [first, second],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let bulk = apply(session, ["A": .string("on"), "B": .string("on")])
            let cancel = apply(session, ["A": .string("off")])
            let waiting = snapshot(session, resources)
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["partialCancellation"] = ["accepted": [bulk, cancel],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let waiting = snapshot(session, resources)
            let hide = apply(session, ["A": .string("off")])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["sameKeyCancellation"] = ["accepted": [show, hide],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let before = snapshot(session, resources)
            let invalid = apply(session, ["B": .bool(true)])
            let after = snapshot(session, resources)
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["invalidUpdate"] = ["accepted": [show, invalid],
                "before": before, "after": after, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on"), "optional": .string("pending")])
            let remove = apply(session, [:], keys: ["optional"])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["removal"] = ["accepted": [show, remove],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, adoption) = make()
            let accepted = apply(session, ["A": .string("on"), "B": .string("on")])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            let oneReady = snapshot(session, resources)
            session.surfaces = [:]
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            let noSurface = snapshot(session, resources)
            installSurfaces(session, adoption)
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["readiness"] = ["accepted": accepted, "oneReady": oneReady,
                "noSurface": noSurface, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, adoption) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .ready
            adoption.failAfterSuccessfulCalls = 1
            session.promotePendingDeferredLayerVisibilityIfReady()
            let rolledBack = snapshot(session, resources)
            adoption.failAfterSuccessfulCalls = nil
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["adoptionRollback"] = ["accepted": accepted,
                "rolledBack": rolledBack, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .ready
            session.launchContext!.unavailable = [a]
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["validationRollback"] = ["accepted": accepted,
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .failed("own-controlled-load-failure")
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["resourceFailure"] = ["accepted": accepted,
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let level = apply(session, ["level": .number(0.7)])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["disjointValue"] = ["accepted": [show, level],
                "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make()
            let show = apply(session, ["A": .string("on")])
            let level = apply(session, ["level": .number(0.7)])
            let waiting = snapshot(session, resources)
            resources.statuses[11] = .failed("own-controlled-load-failure")
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["disjointFailure"] = ["accepted": [show, level],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make(particleCohort: true)
            let accepted = apply(session, ["A": .string("on")])
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["preparedParticleCohort"] = ["accepted": accepted,
                "final": snapshot(session, resources)]
        }
        for fault in ["missing-surface-resource", "generation", "surface-set"] {
            let (session, resources, _) = make(particleCohort: true)
            switch fault {
            case "missing-surface-resource": session.surfaces[2]!.metalView.preparedParticleLayerIDs = []
            case "generation": session.surfaces[2]!.scriptGeneration = 2
            default: session.preparedSurfaceIDs = [1, 2, 3]
            }
            let before = snapshot(session, resources)
            let accepted = apply(session, ["A": .string("on")])
            output["particleAdmission-\(fault)"] = ["accepted": accepted,
                "before": before, "final": snapshot(session, resources)]
        }
        for fault in ["missing-surface-resource", "generation"] {
            let (session, resources, _) = make(particleCohort: true)
            let accepted = apply(session, ["A": .string("on")])
            let waiting = snapshot(session, resources)
            if fault == "generation" { session.surfaces[2]!.scriptGeneration = 2 }
            else { session.surfaces[2]!.metalView.preparedParticleLayerIDs = [] }
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["particlePromotion-\(fault)"] = ["accepted": accepted,
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        do {
            let (session, resources, _) = make(parentParticleCohort: true)
            let first = apply(session, ["A": .string("on")])
            let second = apply(session, ["B": .string("on")])
            let waiting = snapshot(session, resources)
            resources.statuses[11] = .ready
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["preparedParentParticleCohort"] = ["accepted": [first, second],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        for fault in ["missing-first-leaf", "missing-second-leaf", "generation", "surface-set", "no-surfaces"] {
            for incoming in ["off", "on"] {
                let (session, resources, _) = make(parentParticleCohort: true)
                switch fault {
                case "missing-first-leaf": session.surfaces[1]!.metalView.preparedParticleLayerIDs = [43]
                case "missing-second-leaf": session.surfaces[2]!.metalView.preparedParticleLayerIDs = [42]
                case "generation": session.surfaces[2]!.scriptGeneration = 2
                case "surface-set": session.preparedSurfaceIDs = [1, 2, 3]
                default: session.surfaces = [:]
                }
                let before = snapshot(session, resources)
                let accepted = apply(session, ["A": .string(incoming)])
                output["parentAdmission-\(fault)-\(incoming)"] = ["accepted": accepted,
                    "before": before, "final": snapshot(session, resources)]
            }
        }
        for fault in ["missing-second-leaf", "generation"] {
            let (session, resources, _) = make(parentParticleCohort: true)
            let accepted = apply(session, ["A": .string("on")])
            if fault == "generation" { session.surfaces[2]!.scriptGeneration = 2 }
            else { session.surfaces[2]!.metalView.preparedParticleLayerIDs = [42] }
            let before = snapshot(session, resources)
            let merged = apply(session, ["B": .string("on")])
            let after = snapshot(session, resources)
            resources.statuses[11] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["parentMerge-\(fault)"] = ["accepted": [accepted, merged],
                "before": before, "after": after, "final": snapshot(session, resources)]
        }
        for fault in ["missing-second-leaf", "generation"] {
            let (session, resources, _) = make(parentParticleCohort: true)
            let first = apply(session, ["A": .string("on")])
            let second = apply(session, ["B": .string("on")])
            let waiting = snapshot(session, resources)
            if fault == "generation" { session.surfaces[2]!.scriptGeneration = 2 }
            else { session.surfaces[2]!.metalView.preparedParticleLayerIDs = [42] }
            resources.statuses[11] = .ready
            resources.statuses[22] = .ready
            session.promotePendingDeferredLayerVisibilityIfReady()
            output["parentPromotion-\(fault)"] = ["accepted": [first, second],
                "waiting": waiting, "final": snapshot(session, resources)]
        }
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
