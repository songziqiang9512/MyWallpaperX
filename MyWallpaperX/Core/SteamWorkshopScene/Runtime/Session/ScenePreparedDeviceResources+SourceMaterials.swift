import Foundation
import Metal

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
            guard case let .template(template) = entry.entry else {
                if case let .failure(failure) = entry.entry { reject(String(describing: failure)) }
                continue
            }
            guard case let .success(variants) = SceneResolvedMaterialVariantCache.launchValidated(
                template: template, maximumVariantCount: 32, assetFormatFacts: assets.launchFormatFacts
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
            if envelope.variants.allSatisfy({ $0.activeSamplers[0] == nil }) {
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
                let purposes = envelope.variants.compactMap {
                    $0.activeSamplers[0]?.purpose(for: reference)
                }
                guard purposes.count == envelope.variants.count,
                      Set(purposes).count == 1, let purpose = purposes.first else {
                    reject("source-domain-variant-dependent"); continue
                }
                outputDomain = .sampledAsset(.init(path: path, purpose: purpose))
            }
            let plans = envelope.variants.compactMap { variant in
                SceneResolvedMaterialPassEncoder.WarmupPlan(
                    identity: entry.key.reportToken, preparedKey: variant.preparedShader.cacheKey,
                    frontend: variant.frontendProgram, renderState: template.renderState,
                    frontendSchemaVersion: variant.preparedShader.vertex.frontendSchemaVersion,
                    pixelFormat: format, writeMask: .all, device: device)
            }
            guard plans.count == envelope.variants.count else {
                reject("pipeline-plan-incomplete"); continue
            }
            let report = encoder.warmup(plans)
            guard report.failedKeyCount == 0, report.readyKeyCount > 0 else {
                reject("pipeline-warmup"); continue
            }
            prepared[layerID] = .init(template: template, bindFrame: { input in
                SceneResolvedMaterialProgramFinalizer.finalize(input, variantCache: variants)
            }, pixelFormat: format, outputDomain: outputDomain,
                sharedModelPath: entry.sharedModelPath)
            logSink("source material prepared: owner=\(entry.key.reportToken) variants=\(envelope.variants.count)")
        }
        return prepared
    }
}
