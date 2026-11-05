import Foundation

nonisolated struct SceneDependencyRenderPlan {
    nonisolated struct Reference: Hashable {
        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let variant: SceneNamedTextureReference.Variant
    }

    nonisolated struct Binding: Hashable {
        enum Kind: Hashable {
            case resolvedMaterial
            case solidLayer
            case imageLayerBlend
            /// A GeometryProduct provider is rasterized into its authored-
            /// local target before the aggregate MaterialProgram samples it.
            /// The sampling atlas itself is never a named layer publication.
            case geometryLayer
            /// A visible image layer publishes its unified graph-final color
            /// into the same-frame named target consumed by a later
            /// MaterialProgram stage. It remains a normal compositor layer.
            case visibleImageGraphOutput
        }

        let consumerLayerID: Int
        let providerLayerID: Int
        let slot: SceneEffectPassSlot
        let referenceSlots: [SceneEffectPassSlot]
        let blendMode: Int
        let kind: Kind
        /// The exact provider follows its consumer in authored order. The
        /// preparation schedule chooses a legal supply point from its actual
        /// source; this declaration never changes final composition order.
        let requiresForwardCapture: Bool
        /// The binding is resource ownership only. UV transform or additional
        /// graph-internal provenance must be consumed by an admitted
        /// MaterialProgram, never by the legacy direct dependency composite.
        let requiresResolvedMaterialProgram: Bool

        init(
            consumerLayerID: Int,
            providerLayerID: Int,
            slot: SceneEffectPassSlot,
            referenceSlots: [SceneEffectPassSlot]? = nil,
            blendMode: Int,
            kind: Kind,
            requiresForwardCapture: Bool = false,
            requiresResolvedMaterialProgram: Bool = false
        ) {
            self.consumerLayerID = consumerLayerID
            self.providerLayerID = providerLayerID
            self.slot = slot
            self.referenceSlots = referenceSlots ?? [slot]
            self.blendMode = blendMode
            self.kind = kind
            self.requiresForwardCapture = requiresForwardCapture
            self.requiresResolvedMaterialProgram = requiresResolvedMaterialProgram
        }
    }


    /// Prepared external inputs in authored effect/pass/slot order.
    nonisolated struct MultiProviderAggregate: Hashable {
        let consumerLayerID: Int
        let bindings: [Binding]

        var providerLayerIDs: Set<Int> {
            Set(bindings.map(\.providerLayerID))
        }

    }

    nonisolated struct PreparationSchedule: Equatable {
        let preparationLayerIDs: [Int]
        let prepassProviderLayerIDs: [Int]
        let providersBeforeLayerID: [Int: [Int]]
        let scheduledGraphProviderLayerIDs: Set<Int>
    }

    nonisolated enum IssueKind: String {
        case dependencyMismatch
        case missingProvider
        case cyclicDependency
        case unsupportedConsumer
        case unsupportedVariant
        case forwardUtilityProvider
        case namedProviderRouteDisabled
    }

    nonisolated struct Issue: Hashable {
        let kind: IssueKind
        let layerID: Int
        let providerLayerID: Int?
    }

    let references: [Reference]
    let namedReferenceConsumerLayerIDs: Set<Int>
    let executableUtilityConsumerLayerIDs: Set<Int>
    /// Reachable consumers with multiple external input slots. Cold candidates
    /// alone do not grant provider ownership.
    let multiProviderCandidateLayerIDs: Set<Int>
    /// Prepared input vectors consumed by the existing reservation and
    /// publication owners, separate from the legacy single-input route.
    let multiProviderAggregatesByConsumerLayerID: [Int: MultiProviderAggregate]
    let requiredEffectConsumerLayerIDs: Set<Int>
    let bindingsByConsumerLayerID: [Int: Binding]
    let staticModelBindingsByConsumerLayerID: [Int: SceneStaticModelNamedTextureBinding]
    let requiredProviderLayerIDs: Set<Int>
    let requiredGraphOutputProviderLayerIDs: Set<Int>
    let staticLayerSourcePassthroughBlockedLayerIDs: Set<Int>
    let cyclicLayerIDs: Set<Int>
    let issues: [Issue]

}
