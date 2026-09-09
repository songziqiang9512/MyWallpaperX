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
        /// The exact image provider appears after its consumer in authored
        /// compositor order and must publish in the offscreen prepass. A
        /// static provider captures its source; an effectful provider executes
        /// its already-admitted graph. Neither changes final composition order.
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
    /// Reachable childless composition consumers whose visible effects name
    /// more than one external primary image provider. This is a deferred
    /// candidate only: until the runtime aggregate owner exists it must stay
    /// out of `bindingsByConsumerLayerID` and all provider requirements.
    let multiProviderCandidateLayerIDs: Set<Int>
    /// Strictly admitted aggregate descriptions.  Runtime owners may consume
    /// this value when their reservation/input/publication atom is available;
    /// until then it remains out of the legacy binding and provider sets.
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
