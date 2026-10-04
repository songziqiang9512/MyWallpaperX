import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func realSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        let initial = runtime.advance(by: 0)
        let initialInstances = initial.first?.instances ?? []
        let firstPositions = initialInstances.map(\.positionAndSize)
        initial.forEach { _ = $0.instanceBuffer.update(device: device, instances: $0.instances) }
        let initialBufferMatchesData = initial.first?.instanceBuffer.count == initialInstances.count
        let advanced = runtime.advance(by: 1)
        let advancedInstances = advanced.first?.instances ?? []
        let secondPositions = advancedInstances.map(\.positionAndSize)
        let override = descriptor.layers
            .first(where: { $0.id == 196 })?.particleInstanceOverride
        guard let playback = SceneParticlePlaybackState(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        ) else { throw HarnessError.noParticlePipeline }
        let playbackReport = playback.loadReportLines(descriptor: descriptor)

        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "batchLayerIDs": initial.map(\.layerID),
            "initialCount": initialInstances.count,
            "advancedCount": advancedInstances.count,
            "stateChanged": firstPositions != secondPositions,
            "bufferMatchesData": initialBufferMatchesData,
            "blend": initial.first?.renderState.blendMode.rawValue ?? "",
            "usesPerspective": initial.first?.usesPerspective ?? false,
            "orientationScreen": initial.first?.orientation == .screen,
            "maximumLocalSize": initialInstances.map { $0.positionAndSize.w }.max() ?? 0,
            "meanLocalY": initialInstances.isEmpty ? 0 : initialInstances.reduce(0) {
                $0 + $1.positionAndSize.y
            } / Float(initialInstances.count),
            "overrideCount": scalar(override?.count),
            "overrideLifetime": scalar(override?.lifetime),
            "overrideSize": scalar(override?.size),
            "diagnosticKinds": runtime.diagnostics.map { $0.kind.rawValue },
            "playbackLoadedLine": playbackReport.first { $0.hasPrefix("particle loaded:") } ?? "",
            "missingBatchLoadedLine": SceneParticlePlaybackState.loadedSummaryLine(
                batchLayerIDs: [], visibleLayerCount: 1
            ),
        ]
    }

    static func realRefractionSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        let batches = runtime.advance(by: 0)
        return [
            "batchLayerIDs": batches.map(\.layerID),
            "refractionLayerIDs": batches.filter { $0.refraction != nil }.map(\.layerID),
            "sameTextureIdentity": batches.filter { $0.refraction != nil }.allSatisfy {
                $0.texture === $0.refraction?
                    .resolvedNormalArguments()?.texture
            },
            "staticCandidateLayerIDs": batches.filter {
                $0.refraction?.usesStaticNormalCandidate == true
            }.map(\.layerID),
            "amounts": batches.compactMap { $0.refraction?.amount },
            "diagnostics": runtime.diagnostics.map(\.kind.rawValue),
            "diagnosticDetails": runtime.diagnostics.map { $0.detail ?? "" },
        ]
    }

    static func realRefractionChildSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        var paths = Set<String>()
        var candidatePaths = Set<String>()
        var legacyPaths = Set<String>()
        var firstFrame = -1
        for frame in 0..<(7 * 60) {
            let refractive = runtime.advance(by: 1.0 / 60.0).filter {
                $0.refraction != nil && !$0.instances.isEmpty
            }
            if !refractive.isEmpty && firstFrame < 0 { firstFrame = frame }
            paths.formUnion(refractive.map(\.particlePath))
            candidatePaths.formUnion(refractive.filter {
                $0.refraction?.usesStaticNormalCandidate == true
            }.map(\.particlePath))
            legacyPaths.formUnion(refractive.filter {
                $0.refraction?.usesStaticNormalCandidate == false
            }.map(\.particlePath))
        }
        return [
            "firstFrame": firstFrame,
            "paths": paths.sorted(),
            "candidatePaths": candidatePaths.sorted(),
            "legacyPaths": legacyPaths.sorted(),
            "refractionUnsupported": runtime.diagnostics.filter {
                $0.kind == .refractionUnsupported
            }.map { $0.detail ?? "" },
        ]
    }

    static func realWaterImpactSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: URL(fileURLWithPath: cachePath, isDirectory: true),
            device: device,
            stockTextureBundleURL: URL(fileURLWithPath:
                "\(FileManager.default.currentDirectoryPath)/MyWallpaperX/Resources/SceneStockAssets.bundle",
                isDirectory: true
            )
        )
        let targetLayers = Set([239, 245, 248])
        let ropePaths = Set([
            "particles/presets/dripping_water_refract.json",
            "particles/presets/dripping_water_splash.json",
        ])
        let trailChildPath = "particles/presets/water_impact_droplets.json"
        var activeFrames: [Int: Int] = [:]
        var maximumInstances: [Int: Int] = [:]
        var candidateLayers = Set<Int>()
        var legacyLayers = Set<Int>()
        var activeRopePaths = Set<String>()
        var maximumRopeInstances: [String: Int] = [:]
        var refractiveRopePaths = Set<String>()
        var activeTrailChildLayers = Set<Int>()
        var maximumTrailChildInstances: [Int: Int] = [:]
        var minimumTrailStretch = Float.greatestFiniteMagnitude
        var maximumTrailStretch: Float = 0
        for _ in 0..<(8 * 60) {
            for batch in runtime.advance(by: 1.0 / 60.0) {
                if batch.refraction?.usesStaticNormalCandidate == true {
                    candidateLayers.insert(batch.layerID)
                } else if batch.refraction != nil {
                    legacyLayers.insert(batch.layerID)
                }
                if targetLayers.contains(batch.layerID)
                    && batch.refraction != nil
                    && !batch.instances.isEmpty {
                    activeFrames[batch.layerID, default: 0] += 1
                    maximumInstances[batch.layerID] = max(
                        maximumInstances[batch.layerID, default: 0],
                        batch.instances.count
                    )
                }
                if ropePaths.contains(batch.particlePath), !batch.instances.isEmpty {
                    activeRopePaths.insert(batch.particlePath)
                    maximumRopeInstances[batch.particlePath] = max(
                        maximumRopeInstances[batch.particlePath, default: 0],
                        batch.instances.count
                    )
                    if batch.refraction != nil { refractiveRopePaths.insert(batch.particlePath) }
                }
                if batch.particlePath == trailChildPath, !batch.instances.isEmpty {
                    activeTrailChildLayers.insert(batch.layerID)
                    maximumTrailChildInstances[batch.layerID] = max(
                        maximumTrailChildInstances[batch.layerID, default: 0],
                        batch.instances.count
                    )
                    for instance in batch.instances {
                        minimumTrailStretch = min(minimumTrailStretch, instance.velocityAndTrail.w)
                        maximumTrailStretch = max(maximumTrailStretch, instance.velocityAndTrail.w)
                    }
                }
            }
        }
        return [
            "activeFrames": Dictionary(uniqueKeysWithValues: targetLayers.sorted().map {
                (String($0), activeFrames[$0, default: 0])
            }),
            "maximumInstances": Dictionary(uniqueKeysWithValues: targetLayers.sorted().map {
                (String($0), maximumInstances[$0, default: 0])
            }),
            "candidateLayers": candidateLayers.sorted(),
            "legacyLayers": legacyLayers.sorted(),
            "activeRopePaths": activeRopePaths.sorted(),
            "maximumRopeInstances": maximumRopeInstances,
            "refractiveRopePaths": refractiveRopePaths.sorted(),
            "activeTrailChildLayers": activeTrailChildLayers.sorted(),
            "maximumTrailChildInstances": Dictionary(uniqueKeysWithValues:
                targetLayers.sorted().map {
                    (String($0), maximumTrailChildInstances[$0, default: 0])
                }
            ),
            "minimumTrailStretch": minimumTrailStretch.isFinite ? minimumTrailStretch : -1,
            "maximumTrailStretch": maximumTrailStretch,
            "trailChildUnsupported": runtime.diagnostics.compactMap { diagnostic in
                diagnostic.kind == .childSystemsUnsupported
                    && (diagnostic.detail ?? "").contains(trailChildPath)
                    ? (diagnostic.detail ?? "") : nil
            },
            "ropeUnsupported": runtime.diagnostics.compactMap { diagnostic in
                diagnostic.kind == .childSystemsUnsupported
                    && ropePaths.contains(where: {
                        (diagnostic.detail ?? "").contains($0)
                    })
                    ? (diagnostic.detail ?? "") : nil
            },
            "refractionUnsupported": runtime.diagnostics.filter {
                $0.kind == .refractionUnsupported
            }.map { $0.detail ?? "" },
        ]
    }

    static func realContinuousProfiles(cachePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: cachePath, isDirectory: true)
        let parser = SceneParticleDefinitionParser()
        var supported: [String: Bool] = [:]
        var completed: [String: Bool] = [:]
        var rates: [String: Double] = [:]
        var instantaneous: [String: Int] = [:]
        for name in ["Flare_Flame", "Flare_Smoke", "Flare_Sparks"] {
            let definition = try parser.parse(
                data: Data(contentsOf: root.appendingPathComponent("\(name).json"))
            )
            supported[name] = SceneParticleChildLifecycle.supportsEmitterProfile(definition)
            let simulator = SceneParticleSimulator(definition: definition, seed: 17)
            simulator.advance(by: 3)
            completed[name] = simulator.hasFinishedEmission
            rates[name] = definition.emitters.first?.rate ?? -1
            instantaneous[name] = definition.emitters.first?.instantaneousCount ?? 0
        }
        return [
            "supported": supported,
            "completed": completed,
            "rates": rates,
            "instantaneous": instantaneous,
        ]
    }

    static func realStaticOriginSample(
        evidencePath: String,
        cachePath: String
    ) throws -> [String: Any] {
        let cache = URL(fileURLWithPath: cachePath, isDirectory: true)
        let descriptor = try renderDescriptor(evidencePath: evidencePath)
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: cache,
            device: device
        )
        let childPath = "particles/presets/snowstormfog.json"
        let childBatches = runtime.advance(by: 0.5).filter {
            [513, 534].contains($0.layerID) && $0.particlePath == childPath
        }
        return [
            "childLayerIDs": childBatches.map(\.layerID).sorted(),
            "childInstanceCounts": childBatches.map(\.instances.count).sorted(),
            "childTextureWidths": childBatches.map(\.texture.width).sorted(),
            "unsupportedLayerIDs": runtime.diagnostics.compactMap {
                [513, 534].contains($0.layerID) && $0.kind == .childSystemsUnsupported
                    ? $0.layerID : nil
            }.sorted(),
        ]
    }

}
