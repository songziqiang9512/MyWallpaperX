import Foundation
import Metal

enum SceneSubmissionRuntimeBridgeChecks {
    static func claimsProvidersAndEvidence(
        device: MTLDevice, queue: MTLCommandQueue,
        results: inout [String: Bool]
    ) throws {
        do {
            let coordinator = makeCoordinator(device)
            let exact: Bool
            switch coordinator.preflightClaim(layerID: 7) {
            case let .claimed(claim):
                exact = claim.admittedGraphs.flatMap {
                    $0.effects.map(\.key)
                } == [effect]
                    && claim.frameInputContract
                        .effectTextureProjectionSource
                        == .emittedOutputGeometry
                    && !claim.frameInputContract
                        .requiresInvertibleEffectTextureProjection
            case .rejected, .notMigrated:
                exact = false
            }
            results["claimCarriesGraphIdentityOnly"] = exact
        }

        do {
            let name = "$mediaThumbnail"
            let colorIdentity = SceneSystemProviderTextureIdentity(
                name: name,
                purpose: .premultipliedColor
            )
            let preservedIdentity = SceneSystemProviderTextureIdentity(
                name: name,
                purpose: .preservedChannels
            )
            let texture = makeTexture(device, "system-provider")
            let otherTexture = makeTexture(device, "other-system-provider")
            let publication = SceneTextureProviderPublication(
                requestIdentity: .system(colorIdentity),
                candidate: .init(
                    texture: texture,
                    identity: .file("system-provider"),
                    purpose: .premultipliedColor
                ),
                contentGeneration: 1
            )
            let preservedPublication = SceneTextureProviderPublication(
                requestIdentity: .system(preservedIdentity),
                candidate: .init(
                    texture: otherTexture,
                    identity: .file("system-provider-preserved"),
                    purpose: .preservedChannels
                ),
                contentGeneration: 1
            )
            let bridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(
                    userPropertyDemands: [],
                    systemProviderDemands: [
                        .init(name: name, purpose: .premultipliedColor),
                        .init(name: name, purpose: .preservedChannels),
                    ]
                ),
                capabilities: makeCapabilities(layerIDs: []),
                assets: .init(states: [:]),
                device: device
            )
            let missing = bridge.systemProviderBlocks(for: [
                    colorIdentity: .absent,
                    preservedIdentity: .absent,
                ]
            )
            let initialPending = bridge.systemProviderBlocks(for: [
                    colorIdentity: .pending,
                    preservedIdentity: .pending,
                ]
            )
            let unrelatedPending = bridge.systemProviderBlocks(for: [.init(
                    name: "$other",
                    purpose: .preservedChannels
                ): .pending]
            )
            let fullyReady = bridge.systemProviderBlocks(for: [
                    colorIdentity: .ready(publication),
                    preservedIdentity: .ready(preservedPublication),
                ]
            )
            let onlyColorReady = bridge.systemProviderBlocks(for: [
                    colorIdentity: .ready(publication),
                    preservedIdentity: .unavailable,
                ]
            )
            let missingIsAbsent: Bool
            if case .absent? = missing[colorIdentity],
               case .absent? = missing[preservedIdentity] {
                missingIsAbsent = true
            } else { missingIsAbsent = false }
            let initialIsPurposeQualifiedPending: Bool
            if case .pending? = initialPending[colorIdentity],
               case .pending? = initialPending[preservedIdentity] {
                initialIsPurposeQualifiedPending = true
            } else { initialIsPurposeQualifiedPending = false }
            let unknownIsUnavailable: Bool
            if case .unavailable? = unrelatedPending[colorIdentity],
               case .unavailable? = unrelatedPending[preservedIdentity] {
                unknownIsUnavailable = true
            } else { unknownIsUnavailable = false }
            results["systemProviderExplicitAbsenceSoftBlocks"] =
                missingIsAbsent && missing.count == 2
                    && fullyReady.isEmpty
            results["systemProviderInitialPreparationIsPurposeQualifiedPending"] =
                initialIsPurposeQualifiedPending
            results["systemProviderUnknownIdentityRemainsUnavailable"] =
                unknownIsUnavailable
            results["systemProviderPurposesRemainPerConsumer"] =
                Set(onlyColorReady.keys) == [preservedIdentity]
                    && Set(missing.keys) == [colorIdentity, preservedIdentity]
            let noiseIdentity = SceneSystemProviderTextureIdentity(name: "util/noise", purpose: .noise)
            let mixedBridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(userPropertyDemands: [], systemProviderDemands: [colorIdentity, noiseIdentity]),
                capabilities: makeCapabilities(layerIDs: []), assets: .init(states: [:]), device: device)
            let noisePublication = SceneTextureProviderPublication(
                requestIdentity: .system(noiseIdentity),
                candidate: .init(texture: otherTexture, identity: .file("stock-noise"), purpose: .noise),
                contentGeneration: 1)
            let combined: [SceneSystemProviderTextureIdentity: SceneTextureProviderState] = [
                colorIdentity: .pending, noiseIdentity: .ready(noisePublication)]
            results["systemProviderPreparedNoiseNotOverwrittenByMissingMedia"] =
                Set(mixedBridge.systemProviderBlocks(for: combined).keys) == [colorIdentity]

        }

        do {
            let bridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(
                    userPropertyDemands: [],
                    systemProviderDemands: []
                ),
                capabilities: makeCapabilities(layerIDs: [7, 8]),
                assets: .init(states: [:]),
                device: device
            )
            let key7 = effect(for: 7)
            let key8 = effect(for: 8)
            guard case let .claimed(claim7) = bridge.preflightClaim(layerID: 7),
                  case let .claimed(claim8) = bridge.preflightClaim(layerID: 8) else {
                fatalError("fixture capability claims unavailable")
            }
            results["uninstalledDispositionEvidenceIsNotInvoked"] =
                bridge.executionEvidenceSubjects(for: claim7).isEmpty
                && bridge.executionEvidenceSubjects(for: claim8).isEmpty
            bridge.installExecutionEvidence([
                .init(key: key7, family: "generic-framebuffer"),
            ])
            guard let fallback7 = bridge.executionEvidenceSubjects(
                for: claim7
            ).first else {
                fatalError("installed fixture disposition unavailable")
            }
            results["bridgeProjectsOnlyInstalledDispositionEvidence"] =
                fallback7.key == key7
                && fallback7.family == "generic-framebuffer"
                && bridge.executionEvidenceSubjects(for: claim8).isEmpty
            results["executionEvidenceOverridesFallbackFamily"] =
                bridge.executionEvidenceFamily(for: fallback7.key)
                    == "generic-framebuffer"
            results["missingExecutionEvidenceKeepsFallbackIsolated"] =
                bridge.executionEvidenceFamily(for: key8) == nil

            let passthroughBridge = SceneResolvedMaterialRuntimeBridge(
                catalog: .init(
                    userPropertyDemands: [],
                    systemProviderDemands: []
                ),
                capabilities: makeCapabilities(
                    layerIDs: [9],
                    visualFailureReasonByLayerID: [
                        9: "material-variant-envelope-frontend",
                    ]
                ),
                assets: .init(states: [:]),
                device: device
            )
            passthroughBridge.installExecutionEvidence([
                .init(
                    key: effect(for: 9),
                    family: "visual-failure-passthrough"
                ),
            ])
            if case let .claimed(passthroughClaim) = passthroughBridge
                .preflightClaim(layerID: 9),
               let passthroughSubject = passthroughBridge
                .executionEvidenceSubjects(for: passthroughClaim).first,
               case let .failed(reasonCode) = passthroughBridge
                .executionEvidenceOutcome(
                    for: passthroughSubject,
                    claim: passthroughClaim,
                    ticket: .init(
                        identity: 0,
                        epoch: 0,
                        finalTextureIdentity: ObjectIdentifier(device),
                        finalContent: .color(.resolved(.premultipliedAlpha)),
                        consumesExternalPrimaryDependency: false,
                        effectFailures: []
                    )
                ) {
                results["visualFailurePassthroughKeepsFailedTelemetry"] =
                    passthroughSubject.family == "visual-failure-passthrough"
                    && reasonCode == "effect-local-passthrough-"
                        + "material-variant-envelope-frontend"
            } else {
                results["visualFailurePassthroughKeepsFailedTelemetry"] = false
            }

            if case let .failed(reasonCode) = bridge.executionEvidenceOutcome(
                for: fallback7,
                claim: claim7,
                ticket: .init(
                    identity: 1,
                    epoch: 1,
                    finalTextureIdentity: ObjectIdentifier(device),
                    finalContent: .color(.resolved(.premultipliedAlpha)),
                    consumesExternalPrimaryDependency: false,
                    effectFailures: [.init(
                        layerID: key7.layerID,
                        effectIndex: key7.effectIndex,
                        descriptorID: key7.descriptorID,
                        reasonCode: "material-pass-preparation-library-compilation"
                    )]
                )
            ) {
                results["dynamicRendererPassthroughKeepsFailedTelemetry"] =
                    reasonCode == "effect-local-passthrough-"
                        + "material-pass-preparation-library-compilation"
            } else {
                results["dynamicRendererPassthroughKeepsFailedTelemetry"] = false
            }

            bridge.installExecutionEvidence([
                .init(key: key7, family: "generic-framebuffer"),
                .init(key: key7, family: "generic-framebuffer"),
                .init(key: key8, family: "second-family"),
            ])
            results["malformedExecutionEvidenceDropsOnlyInvalidKey"] =
                bridge.executionEvidenceFamily(for: key7) == nil
                && bridge.executionEvidenceFamily(for: key8) == "second-family"
                && bridge.executionEvidenceReportLines.contains {
                    $0.contains("issue: duplicate-key count=1")
                }

            bridge.installExecutionEvidence([
                .init(key: key7, family: "  "),
                .init(key: key8, family: "second-family"),
            ])
            results["emptyExecutionFamilyDropsOnlyInvalidKey"] =
                bridge.executionEvidenceFamily(for: key7) == nil
                && bridge.executionEvidenceFamily(for: key8) == "second-family"
                && bridge.executionEvidenceReportLines.contains {
                    $0.contains("issue: empty-family count=1")
                }
        }

    }

}
