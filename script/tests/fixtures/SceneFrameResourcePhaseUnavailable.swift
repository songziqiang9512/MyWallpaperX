// Nil-only compatibility for fixtures whose existing pool/executor owners are
// explicitly mocked. This is not resource-phase evidence. Real pool/target
// combinations must compile the production Bundle and PreparationAdmission
// sources and must not include this adapter.
final class SceneResolvedMaterialFrameResourceBundle {
    private init() { fatalError("resource phase is outside this fixture") }
    func cancel() { fatalError("non-nil resource bundle is outside this fixture") }
}

// COORDINATOR_RESOURCE_PHASE_UNAVAILABLE
// Leaf compositor/admission fixtures include only the handle prefix above.
// The old one-phase coordinator fixture includes these trap-only signatures
// because the production coordinator now accepts an optional resource bundle.
// Source materials are also outside this coordinator-only fixture: the real
// Runtime preparation job populates them after constructing the bridge. This
// unconstructible leaf permits only the bridge's empty cold-start collection.
extension SceneResolvedMaterialRuntimeBridge {
    struct PreparedSourceMaterial {
        var sharedModelPath: String? { fatalError("source preparation is outside this fixture") }
        private init() { fatalError("source preparation is outside this fixture") }
    }
}

extension SceneResolvedMaterialFrameResourceBundle {
    struct UnavailableAdmission {
        private init() { fatalError("resource phase is outside this fixture") }
        func finalize(
            selectedInputIndices: [Int]? = nil,
            historyTokensByTarget: [[ScenePreparedPersistentGraphTargets.EffectKey:
                Set<ScenePreparedPersistentGraphTargets.Token>]],
            discardedHistoryEffectsByTarget:
                [Set<ScenePreparedPersistentGraphTargets.EffectKey>]? = nil,
            commandBuffer: MTLCommandBuffer? = nil
        ) -> [ScenePreparedPersistentGraphTargets.Commit]? {
            fatalError("resource admission is outside this one-phase fixture")
        }
        func cancel() { fatalError("resource admission is outside this fixture") }
    }
    struct Possession {
        private init() { fatalError("resource phase is outside this fixture") }
        var targets: [ScenePreparedPersistentGraphTargets] {
            fatalError("resource targets are outside this fixture")
        }
        var admission: UnavailableAdmission {
            fatalError("resource admission is outside this fixture")
        }
        func isValidForFramePreparation(
            coordinator: SceneResolvedMaterialSubmissionCoordinator,
            frame: SceneResolvedMaterialFrameSnapshot,
            plans: [SceneResolvedMaterialFrameTargetPlan],
            pool: SceneOffscreenTexturePool?,
            commandBuffer: MTLCommandBuffer
        ) -> Bool { fatalError("resource matching is outside this fixture") }
    }
    func take() -> Possession? {
        fatalError("non-nil resource bundle is outside this one-phase fixture")
    }
}

extension SceneResolvedMaterialSubmissionCoordinator {
    func prepareFrameResourceBundle(
        plans: [SceneResolvedMaterialFrameTargetPlan],
        pool: SceneOffscreenTexturePool,
        commandBuffer: MTLCommandBuffer
    ) -> SceneResolvedMaterialFrameResourceBundle? {
        fatalError("resource phase is outside this one-phase fixture")
    }
    func overlayPreparedSceneEnvironment(
        from snapshot: SceneFrameTextureRegistrySnapshot
    ) -> Bool {
        fatalError("environment overlay is outside this one-phase fixture")
    }
}
