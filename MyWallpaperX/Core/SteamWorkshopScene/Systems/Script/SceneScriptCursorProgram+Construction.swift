import Foundation

/// Launch/load-time construction half of the cursor program: which authored
/// bindings become cursor owners, and how a failed attempt is reported. It
/// evaluates no frames and holds no per-frame state; `dispatch` in
/// SceneScriptCursorProgram.swift owns the runtime half.
extension SceneScriptCursorProgram {
    static func compile(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        borrowedOwners: [SceneScriptCursorOwnerRegistration] = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptCursorProgram {
        compileCandidate(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            borrowedOwners: borrowedOwners,
            rejectedTargets: [],
            generation: generation,
            budget: budget
        ).program
    }

    static func compileCandidate(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        borrowedOwners: [SceneScriptCursorOwnerRegistration] = [],
        claimedTargets: Set<SceneDynamicTarget> = [],
        rejectedTargets: Set<SceneDynamicTarget>,
        excludedStandaloneLayerIDs: Set<Int> = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default,
        constructionWork: SceneScriptConstructionWorkBudget? = nil
    ) -> SceneScriptCursorProgramConstruction {
        let standaloneCandidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        ).filter { !excludedStandaloneLayerIDs.contains($0.identity.layerID)
            && !claimedTargets.contains($0.identity.target)
            && !rejectedTargets.contains($0.identity.target) }
        let borrowedBindings = projectedBorrowedBindings(
            descriptor: descriptor,
            borrowedOwners: borrowedOwners
        ).filter { !rejectedTargets.contains($0.ownerTarget) }
        // A vector owner may have real cursor exports but no safe layer hit
        // geometry. Preserve its other callbacks; report the cursor route as
        // a local failure instead of silently publishing an event-only owner
        // that will never receive an event.
        let unhitBorrowedTargets = Set(borrowedOwners.compactMap {
            registration -> SceneDynamicTarget? in
            guard !rejectedTargets.contains(registration.target) else {
                return nil
            }
            guard let layer = descriptor.layers.first(where: {
                $0.id == registration.layerID
            }), SceneScriptCursorHitAdmission.accepts(layer) else {
                return registration.target
            }
            return nil
        })
        var candidateCounts = Dictionary(
            grouping: standaloneCandidates,
            by: { $0.identity.target }
        ).mapValues(\.count)
        for binding in borrowedBindings {
            candidateCounts[binding.ownerTarget, default: 0] += 1
        }
        let collisionTargets: Set<SceneDynamicTarget> = Set(candidateCounts.compactMap {
            target, count -> SceneDynamicTarget? in
            count > 1 ? target : nil
        })
        let requestedCandidates = standaloneCandidates.filter {
            candidateCounts[$0.identity.target] == 1
        }.sorted { $0.identity.authoredOrdinal < $1.identity.authoredOrdinal }
        let requestedTargets = Set(
            requestedCandidates.map { $0.identity.target }
        ).union(borrowedBindings.map(\.ownerTarget))
            .union(collisionTargets).union(unhitBorrowedTargets)
        guard let domain else {
            return failedConstruction(
                requestedTargets: requestedTargets,
                generation: generation,
                failure: .invalidArgument("QuickJS domain unavailable")
            )
        }
        do {
            try domain.configureLayerCatalog(descriptor)
        } catch {
            return failedConstruction(
                requestedTargets: requestedTargets,
                generation: generation,
                failure: (error as? SceneScriptScalarRuntimeFailure)
                    ?? .invalidArgument(String(describing: error))
            )
        }

        var bindings = borrowedBindings.filter {
            candidateCounts[$0.ownerTarget] == 1
        }
        var instantiatedTargets = Set(bindings.map(\.ownerTarget))
        var requiresDomainReconstruction = false
        let collisionFailure = SceneScriptScalarRuntimeFailure.invalidArgument(
            "SceneScript cursor owner collision"
        )
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = Dictionary(
            uniqueKeysWithValues:
            collisionTargets.map { ($0, collisionFailure) }
        )
        for target in unhitBorrowedTargets {
            failures[target] = .invalidArgument(
                "SceneScript cursor layer hit geometry unavailable"
            )
        }
        for candidate in requestedCandidates {
            let layerID = candidate.identity.layerID
            let target = candidate.identity.target
            let owner: SceneScriptVectorOwner
            do {
                guard !candidate.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    failures[target] = .invalidSource
                    continue
                }
                owner = try SceneScriptVectorOwner(
                    domain: domain,
                    source: candidate.source,
                    target: target,
                    effectNames: [],
                    generation: generation,
                    budget: budget,
                    constructionWork: constructionWork
                )
            } catch let failure as SceneScriptScalarRuntimeFailure {
                failures[target] = failure
                requiresDomainReconstruction = true
                break
            } catch {
                failures[target] = .invalidArgument(String(describing: error))
                requiresDomainReconstruction = true
                break
            }
            let events = exportedEvents(owner)
            // This path never evaluates frames or timers. A constructed
            // owner that needs them would silently lose authored execution.
            guard !events.isEmpty, !owner.requiresFrameEvaluation else {
                failures[target] = .invalidSource
                requiresDomainReconstruction = true
                break
            }
            bindings.append(.init(
                layerID: layerID,
                authoredOrdinal: candidate.identity.authoredOrdinal,
                owner: owner,
                events: events,
                ownsOwner: true,
                scriptProperties: [:],
                ownerSeedValue: nil
            ))
            instantiatedTargets.insert(target)
        }
        bindings.sort { $0.authoredOrdinal < $1.authoredOrdinal }
        return .init(
            program: .init(bindings: bindings, generation: generation),
            requestedTargets: requestedTargets,
            instantiatedTargets: instantiatedTargets,
            failures: failures,
            requiresDomainReconstruction: requiresDomainReconstruction
        )
    }

    static func projectedStandaloneTargets(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        excludedLayerIDs: Set<Int> = []
    ) -> Set<SceneDynamicTarget> {
        let candidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        )
        let counts = Dictionary(
            grouping: candidates,
            by: { $0.identity.target }
        ).mapValues(\.count)
        return Set(candidates.compactMap { candidate in
            counts[candidate.identity.target] == 1
                && !excludedLayerIDs.contains(candidate.identity.layerID)
                ? candidate.identity.target : nil
        })
    }

    static func projectedStandaloneOwnerSources(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        claimedTargets: Set<SceneDynamicTarget> = [],
        excludedLayerIDs: Set<Int> = []
    ) -> [String] {
        let candidates = projectedStandaloneCandidates(
            descriptor: descriptor,
            scriptBindings: scriptBindings
        )
        let counts = Dictionary(
            grouping: candidates,
            by: { $0.identity.target }
        ).mapValues(\.count)
        return candidates.compactMap { candidate in
            guard counts[candidate.identity.target] == 1,
                  !excludedLayerIDs.contains(candidate.identity.layerID),
                  !claimedTargets.contains(candidate.identity.target) else { return nil }
            return candidate.source
        }
    }


    private struct OwnerIdentity {
        let layerID: Int
        let authoredOrdinal: Int
        let target: SceneDynamicTarget
    }

    private struct StandaloneCandidate {
        let source: String
        let identity: OwnerIdentity
    }

    private static func projectedStandaloneCandidates(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR]
    ) -> [StandaloneCandidate] {
        scriptBindings.enumerated().compactMap { authoredOrdinal, binding in
            ownerIdentity(
                binding,
                authoredOrdinal: authoredOrdinal,
                descriptor: descriptor
            ).map {
                .init(source: binding.source, identity: $0)
            }
        }
    }

    private static func projectedBorrowedBindings(
        descriptor: SceneRenderDescriptor,
        borrowedOwners: [SceneScriptCursorOwnerRegistration]
    ) -> [SceneScriptCursorBinding] {
        borrowedOwners.compactMap { registration in
            guard let layer = descriptor.layers.first(where: {
                $0.id == registration.layerID
            }), SceneScriptCursorHitAdmission.accepts(layer) else { return nil }
            let events = exportedEvents(registration.owner)
            guard !events.isEmpty else { return nil }
            return .init(
                layerID: registration.layerID,
                authoredOrdinal: registration.authoredOrdinal,
                owner: registration.owner,
                events: events,
                ownsOwner: false,
                scriptProperties: registration.scriptProperties,
                ownerSeedValue: registration.seedValue
            )
        }
    }


    private static func failedConstruction(
        requestedTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        failure: SceneScriptScalarRuntimeFailure
    ) -> SceneScriptCursorProgramConstruction {
        .init(
            program: .init(bindings: [], generation: generation),
            requestedTargets: requestedTargets,
            instantiatedTargets: [],
            failures: Dictionary(uniqueKeysWithValues:
                requestedTargets.map { ($0, failure) }
            )
        )
    }

    private static func ownerIdentity(
        _ binding: SceneScriptBindingIR,
        authoredOrdinal: Int,
        descriptor: SceneRenderDescriptor
    ) -> OwnerIdentity? {
        guard binding.owner.kind == .object,
              binding.targetKey == "visible",
              binding.wrapperKeys == ["script", "value"]
                || binding.wrapperKeys == ["script", "user", "value"],
              binding.valueType == .boolean,
              binding.properties.isEmpty,
              let authored = binding.authoredValue?.boolValue,
              let index = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(index) else { return nil }
        let layer = descriptor.layers[index]
        guard layer.id == layerID,
              layer.layerIndex == index,
              layer.visible == authored,
              binding.targetPath == [
                  .key("objects"), .index(index), .key("visible"),
              ],
              ["image", "text", "composition"].contains(layer.contentKind),
              SceneScriptCursorHitAdmission.accepts(layer) else { return nil }
        return .init(
            layerID: layerID,
            authoredOrdinal: authoredOrdinal,
            target: .layer(layerID: layerID, field: .visibility)
        )
    }

}
