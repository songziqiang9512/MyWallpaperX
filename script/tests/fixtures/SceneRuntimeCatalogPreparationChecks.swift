import Foundation
import Synchronization

__CATALOG_PREPARATION_TRANSPORT__

private final class CatalogPreparationGate: Sendable {
    struct State: Sendable { var calls = 0; var materialAdmissions = 0 }
    let token = SceneWallpaperLaunchCancellation()
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let state = Mutex(State())
    let prefix: Int
    let stopAt: Int?
    let pauseAt: Int?

    init(prefix: Int, stopAt: Int? = nil, pauseAt: Int? = nil) {
        self.prefix = prefix; self.stopAt = stopAt; self.pauseAt = pauseAt
    }

    func check() throws {
        let number = state.withLock { value in value.calls += 1; return value.calls }
        if number == stopAt { token.cancel() }
        try token.check()
        if number > prefix { state.withLock { $0.materialAdmissions += 1 } }
        if number == pauseAt {
            entered.signal()
            precondition(release.wait(timeout: .now() + 5) == .success, "entered Catalog worker deadline")
        }
    }
}

private final class CatalogPreparationCompletion: Sendable {
    let result = Mutex<String?>(nil)
    func finish(_ value: String) { result.withLock { $0 = value } }
}

extension CancellationProbe {
    static func catalogCases(_ root: URL) throws -> [String: Bool] {
        let model = try SceneRuntimeModelBuilder().build(rootURL: root.appendingPathComponent("catalog"))
        let descriptor = model.renderDescriptor
        let contracts = model.assetCatalog.shaderContracts
        let candidates = try model.authoredEffectRenderPlans.map { graph in
            let definition = descriptor.effectDefinitions.first { $0.relativePath == graph.effects[0].definitionPath }
            let product = try SceneGraphAdmissionCompiler.compile(graph: graph, descriptor: descriptor,
                functions: definition?.functions).get()
            let pair = try SceneLayerFullFramePairPlan.make(conditionPrunedGraphs: [product.graph]).get()
            let admitted = SceneResolvedMaterialAdmittedLayer(layerID: graph.layerID,
                products: [product], pairPlan: pair, dependencyOwnership: .none,
                sourceRoute: .capturedLayerTexture, isVisibleExecutionRoot: true,
                isGraphOutputProvider: false, requiresGraphOutputProvider: false)
            return SceneResolvedMaterialExecutionCapabilityAdmission.Candidate(
                layerID: graph.layerID, result: .success(admitted))
        }
        let materialCount = model.authoredEffectRenderPlans.reduce(0) {
            $0 + $1.nodes.filter { $0.kind == .material }.count
        }
        precondition(candidates.count == 2 && materialCount == 6
            && descriptor.layers.allSatisfy { $0.dependencyLayerIDs.isEmpty && $0.authoredDependencies.isEmpty },
            "fixture must reach two real independent admitted stages")
        func sameTemplates(_ lhs: SceneResolvedMaterialRuntimeCatalog, _ rhs: SceneResolvedMaterialRuntimeCatalog,
                           layerID: Int? = nil) -> Bool {
            guard Set(lhs.entries.keys) == Set(rhs.entries.keys) else { return false }
            return lhs.entries.allSatisfy { key, entry in
                if let layerID, key.effect.layerID != layerID { return true }
                switch (entry, rhs.entries[key]) {
                case let (.template(a, formatsA), .some(.template(b, formatsB))):
                    return a.textureSlots == b.textureSlots && a.combos == b.combos
                        && a.inheritedInactiveCombos == b.inheritedInactiveCombos
                        && a.uniformDeclarations == b.uniformDeclarations && a.renderState == b.renderState
                        && a.graphRole == b.graphRole && a.effectContext == b.effectContext
                        && a.previousBlurredCompositeGenericOwnerEligible == b.previousBlurredCompositeGenericOwnerEligible
                        && a.compatibilityTarget == b.compatibilityTarget
                        && a.shaderContract == b.shaderContract && a.diagnosticProvenance == b.diagnosticProvenance
                        && formatsA == formatsB
                case let (.failure(a), .some(.failure(b))): return a == b
                default: return false
                }
            }
        }
        let plain = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
            admissionCandidates: candidates, shaderContracts: contracts, userPropertyProducers: [])
        let observed = CatalogPreparationGate(prefix: 1 + candidates.count + materialCount)
        let noop = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
            admissionCandidates: candidates, shaderContracts: contracts, userPropertyProducers: [],
            cancellationCheck: observed.check)
        var checks = ["catalogPlainHasSixSuccessfulTemplates": plain.entries.count == materialCount
            && plain.entries.values.allSatisfy { if case .template(_, .success(_)) = $0 { return true }; return false },
            "catalogNoopPreservesPreparedTemplatesAndDemands": sameTemplates(noop, plain)
            && noop.entries.count == materialCount && noop.resourceDemandIssues.isEmpty
            && noop.assetDemands == plain.assetDemands && noop.userPropertyDemands == plain.userPropertyDemands
            && noop.systemProviderDemands == plain.systemProviderDemands
            && noop.systemProviderDemandsByMaterial == plain.systemProviderDemandsByMaterial]
        let prefix = observed.prefix
        // The callback contract checks batch start, candidates and resolved
        // material records before workers enter. This fixture counts entry
        // grants; it does not reproduce shader or graph preparation policy.
        for (name, stopAt) in [("batch", 1), ("resolve", 2 + candidates.count), ("queuedMaterial", prefix + 1)] {
            let gate = CatalogPreparationGate(prefix: prefix, stopAt: stopAt)
            var returnedCatalog = false, cancelled = false
            do {
                _ = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
                    admissionCandidates: candidates, shaderContracts: contracts, userPropertyProducers: [],
                    cancellationCheck: gate.check)
                returnedCatalog = true
            } catch SceneDesktopWallpaperHostLaunchError.cancelled { cancelled = true }
            checks["catalog-\(name)-typedCancellationWithoutHalfProduct"] = cancelled && !returnedCatalog
            checks["catalog-\(name)-noUnenteredMaterialStarts"] = gate.state.withLock { $0.materialAdmissions == 0 }
        }

        let held = CatalogPreparationGate(prefix: prefix, pauseAt: prefix + 1)
        let completion = CatalogPreparationCompletion(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            do {
                _ = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
                    admissionCandidates: candidates, shaderContracts: contracts, userPropertyProducers: [],
                    cancellationCheck: held.check)
                completion.finish("unexpected-success")
            } catch SceneDesktopWallpaperHostLaunchError.cancelled { completion.finish("cancelled") }
            catch { completion.finish("wrong-error:\(error)") }
            done.signal()
        }
        precondition(held.entered.wait(timeout: .now() + 5) == .success)
        held.token.cancel()
        checks["catalogJoinsEnteredWorkBeforeCancellationReturns"] = done.wait(timeout: .now() + 0.05) == .timedOut
        held.release.signal()
        precondition(done.wait(timeout: .now() + 5) == .success)
        checks["catalogCancelledWorkerDoesNotAdmitQueuedPeers"] = completion.result.withLock { $0 == "cancelled" }
            && held.state.withLock { $0.materialAdmissions == 1 }

        let recovered = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
            admissionCandidates: candidates, shaderContracts: contracts, userPropertyProducers: [])
        checks["catalogCancellationDoesNotPoisonNextConstruction"] = sameTemplates(recovered, plain)
        let missingContract = try SceneResolvedMaterialRuntimeCatalog(descriptor: descriptor,
            admissionCandidates: candidates, shaderContracts: contracts.filter { $0.identity != "catalog/left" },
            userPropertyProducers: [])
        let failures = missingContract.entries.values.filter { if case .failure = $0 { return true }; return false }
        let leftEntries = missingContract.entries.filter { $0.key.effect.layerID == 401 }
        let rightEntries = missingContract.entries.filter { $0.key.effect.layerID == 402 }
        checks["catalogOrdinaryMaterialFailureKeepsHealthyStage"] = failures.count == 3
            && missingContract.entries.count == materialCount
            && leftEntries.count == 3 && leftEntries.values.allSatisfy {
                guard case let .failure(failure) = $0 else { return false }
                return failure.phase == .shaderContract && failure.code == .shaderIdentityMismatch
                    && failure.boundedDetails == ["matching-contract-count=0"]
            }
            && rightEntries.count == 3 && rightEntries.values.allSatisfy {
                if case .template(_, .success(_)) = $0 { return true }; return false
            }
            && sameTemplates(missingContract, plain, layerID: 402)
        return checks
    }
}
