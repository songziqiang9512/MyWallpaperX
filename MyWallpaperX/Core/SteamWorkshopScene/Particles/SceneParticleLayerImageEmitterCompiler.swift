import Foundation
import Metal

nonisolated enum SceneParticleLayerImageEmitterCompiler {
    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        texturesByLayerID: [Int: MTLTexture],
        animatedSourceLayerIDs: Set<Int> = []
    ) -> SceneParticleLayerImageEmitterCompilation {
        let layersByID = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        var maps: [Int: SceneParticleLayerImageEmissionMap] = [:]
        var diagnostics: [SceneParticleRuntimeDiagnostic] = []
        for layer in descriptor.layers where layer.contentKind == "particle" {
            let imageDependencies = layer.authoredDependencies.filter { $0.type == "emitterimage" }
            guard !imageDependencies.isEmpty else { continue }
            let path = layer.particlePath ?? ""
            func reject(_ detail: String) {
                diagnostics.append(.init(
                    kind: .layerImageEmitterUnsupported,
                    layerID: layer.id,
                    particlePath: path,
                    detail: detail
                ))
            }
            guard imageDependencies.count == 1,
                  layer.authoredDependencies.count == 1,
                  layer.dependencyLayerIDs.isEmpty,
                  imageDependencies[0].index == 0 else {
                reject("unsupportedDependencyProfile")
                continue
            }
            guard supportsStaticConsumer(layer) else {
                reject("dynamicConsumer")
                continue
            }
            let providerID = imageDependencies[0].layerID
            guard let provider = layersByID[providerID] else {
                reject("missingSourceLayer:\(providerID)")
                continue
            }
            guard supportsStaticSource(provider),
                  !animatedSourceLayerIDs.contains(providerID) else {
                reject("dynamicOrEffectfulSource:\(providerID)")
                continue
            }
            guard staticTransformMatches(layer, provider) else {
                reject("transformMismatch:\(providerID)")
                continue
            }
            guard let size = vector2(provider.sizeWH),
                  let texture = texturesByLayerID[providerID] else {
                reject("missingSourceTextureOrSize:\(providerID)")
                continue
            }
            guard let map = SceneParticleLayerImageEmissionMap(
                texture: texture,
                sourceSize: size
            ) else {
                reject("unsupportedOrEmptyEmissionBitmap:\(providerID)")
                continue
            }
            maps[layer.id] = map
        }
        return SceneParticleLayerImageEmitterCompilation(
            mapsByLayerID: maps,
            diagnostics: diagnostics
        )
    }

    private nonisolated static func supportsStaticSource(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.contentKind == "image"
            && layer.imagePath != nil
            && (layer.imageAlignment?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? "center") == "center"
            && layer.effects.isEmpty
            && layer.timelines.isEmpty && layer.timelineDiagnostics.isEmpty
            && layer.particleTimelines.isEmpty && layer.particleTimelineDiagnostics.isEmpty
            && (layer.scriptBindings?.isEmpty ?? true)
            && (layer.textureAnimationScripts?.isEmpty ?? true)
            && !layer.hasInlineScript
            && layer.puppetMeshPath == nil && layer.text == nil && layer.textScript == nil
    }

    private nonisolated static func supportsStaticConsumer(
        _ layer: SceneRenderDescriptor.Layer
    ) -> Bool {
        layer.timelines.isEmpty && layer.timelineDiagnostics.isEmpty
            && (layer.scriptBindings?.isEmpty ?? true) && !layer.hasInlineScript
    }

    private nonisolated static func staticTransformMatches(
        _ consumer: SceneRenderDescriptor.Layer,
        _ provider: SceneRenderDescriptor.Layer
    ) -> Bool {
        consumer.parentID == provider.parentID
            && vector3(consumer.originXYZ, fallback: .zero)
                == vector3(provider.originXYZ, fallback: .zero)
            && vector3(consumer.scaleXYZ, fallback: SIMD3(repeating: 1))
                == vector3(provider.scaleXYZ, fallback: SIMD3(repeating: 1))
            && vector3(consumer.anglesXYZ, fallback: .zero)
                == vector3(provider.anglesXYZ, fallback: .zero)
            && vector2(consumer.parallaxDepthXY, fallback: .zero)
                == vector2(provider.parallaxDepthXY, fallback: .zero)
    }

    private nonisolated static func vector2(_ values: [Float]?) -> SIMD2<Double>? {
        guard let values, values.count >= 2 else { return nil }
        let value = SIMD2(Double(values[0]), Double(values[1]))
        return value.x.isFinite && value.y.isFinite ? value : nil
    }

    private nonisolated static func vector2(
        _ values: [Float]?, fallback: SIMD2<Double>
    ) -> SIMD2<Double> {
        vector2(values) ?? fallback
    }

    private nonisolated static func vector3(
        _ values: [Float]?, fallback: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard let values, values.count >= 3 else { return fallback }
        let value = SIMD3(Double(values[0]), Double(values[1]), Double(values[2]))
        return value.x.isFinite && value.y.isFinite && value.z.isFinite ? value : fallback
    }
}
