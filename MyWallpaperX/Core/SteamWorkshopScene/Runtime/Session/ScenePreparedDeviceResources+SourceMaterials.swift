import Foundation
import Metal

struct ScenePreparedDeviceResources {
    let pipelineRepository: SceneImageEffectPipelineRepository
    let imageLayerPipeline: SceneImageLayerPipeline
    let spriteTextureLoader: SceneMultiImageSpriteTextureLoader
    let baseImages: ScenePreparedBaseImageResources
    let staticModels: ScenePreparedStaticModelResources

    var device: MTLDevice { pipelineRepository.device }
}

extension ScenePreparedDeviceResources {
    /// Both the first-surface worker and later surfaces use this launch-only
    /// preparation boundary. Rendering receives typed frame binding only.
    static func makeMaterialRuntime(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        capabilities: SceneResolvedMaterialExecutionCapabilityCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        visibleExecutionRootLayerIDs: Set<Int> = [],
        capturesExecutionObservations: Bool
    ) -> SceneResolvedMaterialRuntimeBridge {
        let runtime = SceneResolvedMaterialRuntimeBridge(
            userPropertyDemands: catalog.userPropertyDemands,
            systemProviderDemands: catalog.systemProviderDemands,
            capabilities: capabilities, assets: assets, device: device,
            visibleExecutionRootLayerIDs: visibleExecutionRootLayerIDs,
            capturesExecutionObservations: capturesExecutionObservations)
        runtime.sourceMaterials = prepareSourceMaterialPrograms(catalog: catalog,
            assets: assets, device: device,
            encoder: runtime.submissions.executor?.materialEncoder,
            logSink: runtime.submissions.logSink)
        return runtime
    }
}

extension ScenePreparedDeviceResources {
    static func prepareSourceMaterialPrograms(
        catalog: SceneResolvedMaterialRuntimeCatalog,
        assets: SceneMaterialAssetTextureCatalog,
        device: MTLDevice,
        encoder: SceneResolvedMaterialPassEncoder?,
        logSink: SceneResolvedMaterialRuntimeBridge.LogSink
    ) -> [Int: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial] {
        guard let encoder else { return [:] }
        let format = catalog.sourceMaterialTargetFormat.metalPixelFormat
        var prepared: [Int: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial] = [:]
        for (layerID, entry) in catalog.sourceMaterialEntries.sorted(by: { $0.key < $1.key }) {
            func reject(_ reason: String) {
                logSink("source material unavailable: owner=\(entry.key.reportToken) reason=\(reason)")
            }
            guard case let .template(template, textureFormatSlots) = entry.entry else {
                if case let .failure(failure) = entry.entry { reject(String(describing: failure)) }
                continue
            }
            guard case let .success(variants) = SceneResolvedMaterialVariantCache.launchValidated(
                template: template, textureFormatSlots: textureFormatSlots,
                maximumVariantCount: 32, assetFormatFacts: assets.launchFormatFacts
            ) else { reject("variant-schema"); continue }
            switch variants.precompileLaunchEnvelope(
                implicitFramebufferIdentity: nil,
                outputIsRGBA8Unorm: format != .rgba16Float,
                assetStates: assets.launchStates
            ) {
            case let .failure(failure): reject(String(describing: failure)); continue
            case .success: break
            }
            let envelope = variants.launchEnvelopeCapabilitySnapshot()
            guard envelope.allEntriesReady, !envelope.variants.isEmpty else {
                reject("variant-envelope-incomplete"); continue
            }
            let outputDomain: SceneResolvedMaterialRuntimeBridge.PreparedSourceMaterial.OutputDomain
            if entry.capturesMainTarget {
                guard let sourceSlot = template.textureSlots.first ?? nil,
                      sourceSlot.candidates.count == 1,
                      let reference = sourceSlot.candidates.first?.reference,
                      case let .provider(.sceneBackground(consumerLayerID)) = reference,
                      consumerLayerID == layerID,
                      template.textureSlots.dropFirst().allSatisfy({ $0 == nil }),
                      envelope.variants.allSatisfy({ variant in
                          variant.activeSamplers.count == 1
                              && variant.textureSelectionFacts.candidatePurposes[0] == [.premultipliedColor]
                      }) else {
                    reject("framebuffer-source-domain-unproven"); continue
                }
                outputDomain = .capturedMain
            } else if envelope.variants.allSatisfy({ $0.activeSamplers[0] == nil }) {
                // A complete base-image atom supplies geometry only. It is
                // never manufactured as a sampler binding or color-purpose fact.
                outputDomain = .baseImage
            } else {
                // Actual slot-zero sampling retains the original asset's
                // physical/padding domain, rather than the cropped base upload.
                guard let reference = template.textureSlots.first??.candidates.last?.reference,
                      case let .asset(path) = reference else {
                    reject("source-domain-unavailable"); continue
                }
                let purposes = envelope.variants.compactMap { variant in
                    variant.activeSamplers[0].flatMap {
                        SceneResolvedMaterialShaderSchema.purpose(for: reference, sampler: $0)
                    }
                }
                guard purposes.count == envelope.variants.count,
                      Set(purposes).count == 1, let purpose = purposes.first else {
                    reject("source-domain-variant-dependent"); continue
                }
                outputDomain = .sampledAsset(.init(path: path, purpose: purpose))
            }
            let plans = envelope.variants.compactMap { variant in
                SceneResolvedMaterialPassEncoder.WarmupPlan(
                    identity: entry.key.reportToken, prepared: variant.preparedAssembly,
                    pixelFormat: format, writeMask: .all, device: device)
            }
            guard plans.count == envelope.variants.count else {
                reject("pipeline-plan-incomplete"); continue
            }
            let report = encoder.warmup(plans)
            guard report.failedKeyCount == 0, report.readyKeyCount > 0 else {
                reject("pipeline-warmup"); continue
            }
            prepared[layerID] = .init(declaredDynamicTargets: Set(envelope.dynamicUniforms.map(\.target)),
                hasAudioSpectrumConsumer: variants.hasAudioSpectrumConsumer,
                requiresSceneEnvironment: variants.hasSceneEnvironmentConsumer, bindFrame: { input in
                SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: variants)
            }, pixelFormat: format, outputDomain: outputDomain,
                sharedModelPath: entry.sharedModelPath)
            logSink("source material prepared: owner=\(entry.key.reportToken) variants=\(envelope.variants.count)")
        }
        return prepared
    }
}

extension SceneTexContainer.Condition {
    nonisolated func matches(_ values: [String: SceneUserPropertyValue]) -> Bool {
        guard let value = values[propertyKey] else { return false }
        switch self {
        case .boolean: return value.boolValue == true
        case let .equals(_, condition): return value.matches(.string(condition))
        }
    }
}

extension ScenePreparedBaseImageResources {
    static func prepareConditionalAtlas(
        _ prepared: SceneTextureLoader.PreparedTexSource,
        selection: Set<UInt32>, loader: SceneTextureLoader, device: MTLDevice,
        checkCancellation: () throws -> Void
    ) throws -> SceneBaseImageTextureLoad.Loaded? {
        try withoutActuallyEscaping(checkCancellation) { checkCancellation in
            let outcome = try SceneBaseImageTextureLoad.loadOrdinaryCandidate(from: prepared.input,
                loader: loader, device: device, preparedTexSource: prepared,
                conditionalVariantIDs: selection, checkCancellation: checkCancellation)
            switch outcome {
            case let .loaded(loaded):
                return loaded
            case let .failed(failure):
                try failure.rethrowResourceReadFailure()
                return nil
            }
        }
    }
}
