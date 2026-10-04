import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

extension Harness {
    static func realEventSpawnSample(
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
        _ = runtime.advance(by: 0.5)
        let batches = runtime.advance(by: 1.0 / 60.0)
        let childPath = "particles/workshop/2562725207/presets/shootingstarglow.json"
        return [
            "activeLayerIDs": runtime.activeLayerIDs,
            "childInstanceCount": batches.first { $0.particlePath == childPath }?.instances.count ?? 0,
            "childTextureWidth": batches.first { $0.particlePath == childPath }?.texture.width ?? 0,
            "layer264ChildUnsupported": runtime.diagnostics.contains {
                $0.layerID == 264 && $0.kind == .childSystemsUnsupported
            },
        ]
    }

    static func realEventDeathSample(
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
        let hitPath = "particles/workshop/2110548715/presets/fireworks1hit.json"
        var firstHitBatches: [SceneParticleDrawBatch] = []
        var firstRootInstances: [SceneParticleGPUInstance] = []
        var firstHitFrame = -1
        for frame in 0..<(8 * 60) {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let hitBatches = batches.filter { $0.particlePath == hitPath }
            if !hitBatches.isEmpty {
                firstHitFrame = frame
                firstHitBatches = hitBatches
                firstRootInstances = batches.filter {
                    $0.layerID == 529 && $0.particlePath != hitPath
                }.flatMap(\.instances)
                break
            }
        }
        let hitBatches = firstHitBatches
        let hitInstances = hitBatches.flatMap(\.instances)
        let pixels = renderEventDeathBatches(hitBatches, device: device)
        return [
            "firstHitFrame": firstHitFrame,
            "hitInstanceCount": hitInstances.count,
            "hitMaximumAlpha": hitInstances.map(\.rotationAndAlpha.w).max() ?? -1,
            "hitMaximumSize": hitInstances.map(\.positionAndSize.w).max() ?? -1,
            "hitMaximumTrailStretch": hitInstances.map(\.velocityAndTrail.w).max() ?? -1,
            "hitMinimumPosition": vector(hitInstances.map(\.positionAndSize).min {
                $0.y < $1.y
            } ?? .zero),
            "hitMaximumPosition": vector(hitInstances.map(\.positionAndSize).max {
                $0.y < $1.y
            } ?? .zero),
            "rootPositions": firstRootInstances.map { vector($0.positionAndSize) },
            "renderedPixelCount": pixels["count"] ?? 0,
            "renderedPixelWidth": pixels["width"] ?? 0,
            "renderedPixelHeight": pixels["height"] ?? 0,
            "hitUsesTrail": hitBatches.contains {
                ($0.instances.first?.velocityAndTrail.w ?? -1) >= 0
            },
            "layer529ChildUnsupported": runtime.diagnostics.contains {
                $0.layerID == 529 && $0.kind == .childSystemsUnsupported
            },
            "layer529SimulationDetails": runtime.diagnostics.compactMap {
                $0.layerID == 529 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
        ]
    }

    static func renderEventDeathBatches(
        _ batches: [SceneParticleDrawBatch],
        device: MTLDevice
    ) -> [String: Int] {
        batches.forEach { _ = $0.instanceBuffer.update(device: device, instances: $0.instances) }
        let width = 1280
        let height = 831
        guard !batches.isEmpty,
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }

        let origin = SIMD2<Float>(1783.794, 2160 - 589.649)
        let halfExtents = SIMD2<Float>(Float(width) / Float(height) * 1080, 1080)
        let model = simd_float4x4(columns: (
            SIMD4(1 / halfExtents.x, 0, 0, 0),
            SIMD4(0, 1 / halfExtents.y, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(
                (origin.x - 1920) / halfExtents.x,
                1 - origin.y / halfExtents.y,
                0,
                1
            )
        ))
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0),
            cameraUp: SIMD3(0, -1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        for batch in batches {
            pipeline.draw(
                texture: batch.texture,
                instances: batch.instanceBuffer,
                uniforms: SceneParticleLayerUniforms(
                    viewProjection: matrix_identity_float4x4,
                    layerModel: model,
                    basis: basis
                ),
                renderState: batch.renderState,
                colorSampling: batch.colorSampling,
                encoder: encoder
            )
        }
        encoder.endEncoding()
        for batch in batches { batch.instanceBuffer.markSubmitted(on: command) }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return [:] }

        var values = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(
            &values,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        var count = 0
        var minimumX = width
        var minimumY = height
        var maximumX = -1
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard values[offset] > 3 || values[offset + 1] > 3 || values[offset + 2] > 3 else {
                    continue
                }
                count += 1
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        return [
            "count": count,
            "width": maximumX >= minimumX ? maximumX - minimumX + 1 : 0,
            "height": maximumY >= minimumY ? maximumY - minimumY + 1 : 0,
        ]
    }

    static func syntheticEventFollow() throws -> [String: Any] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-particle-follow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePNG(directory.appendingPathComponent("materials/shared.png"))
        try writeParticle(
            "particles/follow-root.json", material: "materials/shared.json",
            velocityX: 60, lifetime: 4.0 / 60.0, moves: true, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/follow-child.json", "type": "eventfollow", "maxcount": 1,
                "scale": "2.5 2.5 1",
            ]], under: directory
        )
        try writeParticle(
            "particles/follow-child.json", material: "materials/shared.json",
            flags: 1, rate: 60, under: directory
        )
        try writeParticle(
            "particles/bounded-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/bounded-child.json", "type": "eventspawn",
                "scale": "0.2 0.2 0.2",
            ]], under: directory
        )
        try writeParticle(
            "particles/bounded-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, emitterDuration: 3.0 / 60.0, under: directory
        )
        try writeParticle(
            "particles/budget-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 100,
            children: [[
                "name": "particles/budget-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/budget-child.json", material: "materials/shared.json",
            rate: 60, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/audio-child.json", "type": "eventspawn",
            ], [
                "name": "particles/audio-operator-child.json", "type": "static",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-child.json", material: "materials/shared.json",
            rate: 60, audioProcessingMode: 1, under: directory
        )
        try writeParticle(
            "particles/audio-operator-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/audio-churn-root.json", material: "materials/shared.json",
            lifetime: 1.0 / 60.0, rate: 60,
            children: [[
                "name": "particles/audio-churn-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/audio-churn-child.json", material: "materials/shared.json",
            rate: 0, operatorAudioProcessingMode: 1, instantaneous: 1, under: directory
        )
        try writeParticle(
            "particles/window-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [[
                "name": "particles/window-child.json", "type": "eventspawn",
            ]], under: directory
        )
        try writeParticle(
            "particles/window-child.json", material: "materials/shared.json",
            lifetime: 2.0 / 60.0, rate: 60, under: directory
        )
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "colorrandom", "min": "255 255 255", "max": "255 255 255"],
            ],
            "operator": [[
                "name": "colorchange", "starttime": 0, "endtime": 1,
                "startvalue": "1 1 1", "endvalue": "0 0 1",
            ]],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-follow-child.json", "type": "eventfollow",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [["name": "lifetimerandom", "min": 1, "max": 1]],
            "operator": [["name": "inheritvaluefromevent"]],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-follow-child.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1.0 / 60.0, "max": 1.0 / 60.0],
                ["name": "colorrandom", "min": "51 102 153", "max": "51 102 153"],
            ],
            "renderer": [["name": "sprite"]],
            "children": [[
                "name": "particles/inherit-death-child.json", "type": "eventdeath",
            ]],
        ], to: directory.appendingPathComponent("particles/inherit-death-root.json"))
        try writeJSON([
            "material": "materials/shared.json", "maxcount": 1,
            "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
            "initializer": [
                ["name": "lifetimerandom", "min": 1, "max": 1],
                ["name": "inheritinitialvaluefromevent"],
            ],
            "renderer": [["name": "sprite"]],
        ], to: directory.appendingPathComponent("particles/inherit-death-child.json"))
        for (path, component): (String, [String: Any]) in [
            ("particles/invalid-inherit-static.json", ["name": "inheritinitialvaluefromevent"]),
            ("particles/invalid-inherit-death.json", ["name": "inheritvaluefromevent"]),
            ("particles/invalid-inherit-follow.json", [
                "name": "inheritvaluefromevent", "input": "setsize",
            ]),
        ] {
            var initializers: [[String: Any]] = [
                ["name": "lifetimerandom", "min": 1, "max": 1],
            ]
            var operators: [[String: Any]] = []
            if component["name"] as? String == "inheritinitialvaluefromevent" {
                initializers.append(component)
            } else {
                operators.append(component)
            }
            try writeJSON([
                "material": "materials/shared.json", "maxcount": 1,
                "emitter": [["name": "sphererandom", "rate": 0, "instantaneous": 1]],
                "initializer": initializers,
                "operator": operators,
                "renderer": [["name": "sprite"]],
            ], to: directory.appendingPathComponent(path))
        }
        try writeParticle(
            "particles/invalid-inherit-root.json", material: "materials/shared.json",
            rate: 0, instantaneous: 1,
            children: [
                ["name": "particles/invalid-inherit-static.json", "type": "static"],
                ["name": "particles/invalid-inherit-death.json", "type": "eventdeath"],
                ["name": "particles/invalid-inherit-follow.json", "type": "eventfollow"],
            ], under: directory
        )

        let descriptor = SceneRenderDescriptor(
            layers: [
                layer(10, "particles/follow-root.json"),
                layer(11, "particles/bounded-root.json"),
                layer(12, "particles/budget-root.json"),
                layer(13, "particles/audio-root.json"),
                layer(14, "particles/window-root.json"),
                layer(15, "particles/inherit-follow-root.json"),
                layer(16, "particles/inherit-death-root.json"),
                layer(17, "particles/invalid-inherit-root.json"),
            ],
            renderOrderLayerIDs: [10, 11, 12, 13, 14, 15, 16, 17],
            materialPasses: [
                .init(
                    materialPath: "materials/shared.json",
                    shaderPath: "genericparticle", texturePaths: ["shared.png"], blending: "additive"
                ),
            ]
        )
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let runtime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let activeAudioRuntime = SceneParticleRuntime(
            descriptor: descriptor,
            cacheDirectory: directory,
            device: device
        )
        let activeAudioInput = SceneParticleAudioInput(
            left: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            right: Array(repeating: 1, count: SceneParticleAudioInput.bandCount),
            generation: 7
        )
        for _ in 0..<2 {
            _ = activeAudioRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        }
        let activeChildAudioInput = activeAudioRuntime.frameSnapshot().layers
            .compactMap { $0.child?.systems.first?.simulatorFrame.audioInput.left.first }
            .first ?? 0
        let churnDescriptor = SceneRenderDescriptor(
            layers: [layer(18, "particles/audio-churn-root.json")],
            renderOrderLayerIDs: [18],
            materialPasses: descriptor.materialPasses
        )
        let churnRuntime = SceneParticleRuntime(
            descriptor: churnDescriptor,
            cacheDirectory: directory,
            device: device
        )
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let churnRollbackSnapshot = churnRuntime.frameSnapshot()
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let rejectedChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
        churnRuntime.restoreFrame(churnRollbackSnapshot)
        let churnObservationsAfterRestore = churnRuntime
            .consumeAudioEvaluationObservations()
        _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
        let retryChurnObservations = churnRuntime.consumeAudioEvaluationObservations()
        var laterChurnObservationCount = 0
        for _ in 0..<6 {
            _ = churnRuntime.advance(by: 1.0 / 60.0, audioInput: activeAudioInput)
            laterChurnObservationCount += churnRuntime
                .consumeAudioEvaluationObservations().count
        }
        var childCounts: [Int] = []
        var childPositions: [Float] = []
        var childSizes: [Float] = []
        var boundedCounts: [Int] = []
        var boundedSizes: [Float] = []
        var budgetCounts: [Int] = []
        var windowCounts: [Int] = []
        var inheritedFollowMatches: [Bool] = []
        var inheritedDeathColors: [[Float]] = []
        for _ in 0..<6 {
            let batches = runtime.advance(by: 1.0 / 60.0)
            let instances = batches.first {
                $0.particlePath == "particles/follow-child.json"
            }?.instances ?? []
            childCounts.append(instances.count)
            if let position = instances.first?.positionAndSize.x {
                childPositions.append(position)
            }
            if let size = instances.first?.positionAndSize.w {
                childSizes.append(size)
            }
            let boundedInstances = batches.first {
                $0.particlePath == "particles/bounded-child.json"
            }?.instances ?? []
            boundedCounts.append(boundedInstances.count)
            if let size = boundedInstances.first?.positionAndSize.w {
                boundedSizes.append(size)
            }
            budgetCounts.append(batches.first {
                $0.particlePath == "particles/budget-child.json"
            }?.instances.count ?? 0)
            windowCounts.append(batches.first {
                $0.particlePath == "particles/window-child.json"
            }?.instances.count ?? 0)
            let followRootColor = batches.first {
                $0.particlePath == "particles/inherit-follow-root.json"
            }?.instances.first?.colorAndFrameMix
            let followChildColor = batches.first {
                $0.particlePath == "particles/inherit-follow-child.json"
            }?.instances.first?.colorAndFrameMix
            if let root = followRootColor, let child = followChildColor {
                inheritedFollowMatches.append(
                    abs(root.x - child.x) < 1e-6 && abs(root.y - child.y) < 1e-6
                        && abs(root.z - child.z) < 1e-6
                )
            }
            if let color = batches.first(where: {
                $0.particlePath == "particles/inherit-death-child.json"
            })?.instances.first?.colorAndFrameMix {
                inheritedDeathColors.append([color.x, color.y, color.z])
            }
        }
        return [
            "windowCounts": windowCounts,
            "childCounts": childCounts,
            "childPositions": childPositions,
            "childSizes": childSizes,
            "boundedCounts": boundedCounts,
            "boundedSizes": boundedSizes,
            "budgetCounts": budgetCounts,
            "inheritedFollowMatches": inheritedFollowMatches,
            "inheritedDeathColors": inheritedDeathColors,
            "eventColorMarkers": runtime.diagnostics.compactMap {
                $0.kind == .simulationLimitation && $0.detail?.contains("eventColor") == true
                    ? $0.detail : nil
            },
            "invalidEventColorDetails": runtime.diagnostics.compactMap {
                $0.layerID == 17 && $0.kind == .childSystemsUnsupported
                    && $0.detail?.contains("eventColor") == true ? $0.detail : nil
            },
            "childUnsupportedLayers": runtime.diagnostics.compactMap {
                $0.kind == .childSystemsUnsupported && ![13, 17].contains($0.layerID)
                    ? $0.layerID : nil
            },
            "budgetDetails": runtime.diagnostics.compactMap {
                $0.layerID == 12 && $0.kind == .simulationLimitation ? $0.detail : nil
            },
            "audioChildDetails": runtime.diagnostics.compactMap {
                $0.layerID == 13 && $0.kind == .childSystemsUnsupported ? $0.detail : nil
            },
            "hasAudioConsumer": runtime.hasAudioConsumer,
            "activeChildAudioInput": activeChildAudioInput,
            "rejectedChurnObservationCount": rejectedChurnObservations.count,
            "churnObservationsAfterRestore": churnObservationsAfterRestore.count,
            "retryChurnObservationCount": retryChurnObservations.count,
            "retryChurnObservationPaths": retryChurnObservations.map(\.particlePath),
            "laterChurnObservationCount": laterChurnObservationCount,
            "childScaleDetails": runtime.diagnostics.compactMap {
                $0.kind == .simulationLimitation && $0.detail?.contains("childScaleBounded") == true
                    ? $0.detail : nil
            },
        ]
    }

}
