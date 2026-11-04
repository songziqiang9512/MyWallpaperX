import Foundation
import Metal
import simd

// Independent flat-fragment hardware oracle: no copied alpha threshold, tint,
// or sampling logic. Runtime cases replay the production mesh captured below;
// frozen node interiors and endpoint continuity qualify its geometry separately.
private let particleCoverageReferenceSource = """
#include <metal_stdlib>
using namespace metal;
vertex float4 coverageReferenceVertex(uint index [[vertex_id]]) {
    const float2 corners[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    return float4(corners[index],0.5,1);
}
vertex float4 coverageReferenceMeshVertex(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    device const float4 *positions [[buffer(0)]]) {
    return positions[instanceID * 4 + vertexID];
}
fragment float4 coverageReferenceFragment(constant float4 &color [[buffer(0)]]) {
    return color;
}
"""

enum SceneParticleCoverageRenderingHarness {
    private static let side = 16
    private static let textureRGB = SIMD3<Float>(240, 80, 32) / 255
    private static let particleRGB = SIMD3<Float>(0.5, 0.75, 1.25)
    private static let overbright: Float = 1.2
    private static let pairs: [(UInt8, Float)] = [
        (0, 1), (255, 0), (64, 1), (128, 1),
        (192, 1), (255, 1), (255, 0.52), (128, 0.5)
    ]

    static func run() throws -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let coveragePipeline = SceneParticleMetalPipeline(
                device: device, requiredVariants: SceneParticlePipelineVariant.standaloneDefaults.union([
                    .init(blendMode: .alphaToCoverage),
                    .init(blendMode: .alphaToCoverage, usesDepthAttachment: true)
                ])),
              let ordinaryPipeline = SceneParticleMetalPipeline(device: device)
        else { throw failure("device-or-pipeline") }
        let library = try device.makeLibrary(source: particleCoverageReferenceSource, options: nil)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let disabledDepth = device.makeDepthStencilState(descriptor: depthDescriptor)
        else { throw failure("disabled-depth-state") }
        var coverage: [[String: Any]] = []
        var ordinary: [[String: Any]] = []
        var missing: [[String: Any]] = []
        for depth in [false, true] {
            let coverageReference = try referenceState(
                device: device, library: library, mode: .alphaToCoverage, depth: depth)
            for (textureAlpha, particleAlpha) in pairs {
                coverage.append(try draw(
                    device: device, queue: queue, pipeline: coveragePipeline,
                    reference: coverageReference, disabledDepth: disabledDepth,
                    textureAlpha: textureAlpha, particleAlpha: particleAlpha,
                    mode: .alphaToCoverage, depth: depth))
            }
            for mode in [SceneParticlePipelineBlendMode.translucent, .additive] {
                let reference = try referenceState(
                    device: device, library: library, mode: mode, depth: depth)
                ordinary.append(try draw(
                    device: device, queue: queue, pipeline: coveragePipeline,
                    reference: reference, disabledDepth: disabledDepth,
                    textureAlpha: 192, particleAlpha: 0.52, mode: mode, depth: depth))
                if mode == .translucent {
                    missing.append(try draw(
                        device: device, queue: queue, pipeline: ordinaryPipeline,
                        reference: reference, disabledDepth: disabledDepth,
                        textureAlpha: 192, particleAlpha: 0.52, mode: mode,
                        depth: depth, attemptsUnpreparedCoverage: true))
                }
            }
        }
        let runtime = try runtimeCases(device: device, queue: queue,
            pipeline: coveragePipeline, ordinaryPipeline: ordinaryPipeline, library: library)
        return ["device": device.name, "sampleCount": 1,
                "coverage": coverage, "ordinary": ordinary, "missing": missing,
                "runtime": runtime.0, "runtimeDepth": runtime.1, "signedBirth": runtime.2]
    }

    private static func referenceState(
        device: MTLDevice, library: MTLLibrary,
        mode: SceneParticlePipelineBlendMode, depth: Bool, mesh: Bool = false
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(
            name: mesh ? "coverageReferenceMeshVertex" : "coverageReferenceVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "coverageReferenceFragment")
        descriptor.rasterSampleCount = 1
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        if depth { descriptor.depthAttachmentPixelFormat = .depth32Float }
        let color = descriptor.colorAttachments[0]!
        switch mode {
        case .alphaToCoverage:
            descriptor.isAlphaToCoverageEnabled = true
            descriptor.isAlphaToOneEnabled = true
        case .translucent, .additive:
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = mode == .additive ? .one : .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func sourceTexture(device: MTLDevice, alpha: UInt8) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor)
        else { throw failure("source-texture") }
        let bytes: [UInt8] = [240, 80, 32, alpha]
        bytes.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        return texture
    }

    private static func target(device: MTLDevice, width: Int = side, height: Int = side) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: descriptor)
        else { throw failure("color-target") }
        return texture
    }

    private static func readPixels(_ texture: MTLTexture) -> [Int] {
        let width = texture.width, height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var pixels: [Int] = []
        pixels.reserveCapacity(bytes.count)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            pixels.append(Int(bytes[index + 2]))
            pixels.append(Int(bytes[index + 1]))
            pixels.append(Int(bytes[index]))
            pixels.append(Int(bytes[index + 3]))
        }
        return pixels
    }

    private static func readInterior(_ texture: MTLTexture) -> [Int] {
        let pixels = readPixels(texture)
        // The oversized Sprite and oracle triangle both cover this frozen
        // interior. Direct getBytes uses the actual tightly packed row stride.
        return (4..<12).flatMap { y in (4..<12).flatMap { x -> [Int] in
            let index = (y * side + x) * 4
            return Array(pixels[index..<index + 4])
        } }
    }

    private static func draw(
        device: MTLDevice, queue: MTLCommandQueue,
        pipeline: SceneParticleMetalPipeline, reference: MTLRenderPipelineState,
        disabledDepth: MTLDepthStencilState, textureAlpha: UInt8, particleAlpha: Float,
        mode: SceneParticlePipelineBlendMode, depth: Bool,
        attemptsUnpreparedCoverage: Bool = false
    ) throws -> [String: Any] {
        let actual = try target(device: device)
        let expected = try target(device: device)
        var depthTexture: MTLTexture?
        if depth {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: side, height: side, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            guard let texture = device.makeTexture(descriptor: descriptor)
            else { throw failure("depth-target") }
            depthTexture = texture
        }
        guard let command = queue.makeCommandBuffer() else { throw failure("command-buffer") }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [.init(
            position: SIMD3(0, 0, 0.5), size: 8, rotation: .zero,
            color: particleRGB, alpha: particleAlpha)])
        else { throw failure("instance-buffer") }
        let texture = try sourceTexture(device: device, alpha: textureAlpha)
        var encoded = false
        var unpreparedCoverageEncoded = false
        for (output, isReference) in [(actual, false), (expected, true)] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(
                16.0 / 255, 24.0 / 255, 40.0 / 255, 102.0 / 255)
            if depth {
                pass.depthAttachment.texture = depthTexture
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.storeAction = .dontCare
                pass.depthAttachment.clearDepth = 1
            }
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { throw failure("render-encoder") }
            if isReference {
                let alpha = Float(textureAlpha) / 255 * particleAlpha
                let rgb = textureRGB * particleRGB * overbright
                var color = mode == .alphaToCoverage
                    ? SIMD4<Float>(rgb, alpha) : SIMD4<Float>(rgb * alpha, alpha)
                encoder.setRenderPipelineState(reference)
                if depth { encoder.setDepthStencilState(disabledDepth) }
                encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            } else {
                let uniforms = SceneParticleLayerUniforms(
                    viewProjection: SceneMatrix.identity(), layerModel: SceneMatrix.identity(),
                    basis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0)),
                    viewportSize: SIMD2(repeating: Float(side)))
                if attemptsUnpreparedCoverage {
                    unpreparedCoverageEncoded = pipeline.draw(
                        texture: texture, instances: instances, uniforms: uniforms,
                        renderState: .init(blendMode: .alphaToCoverage, cullMode: .none,
                                           overbright: overbright),
                        colorSampling: .directImageFallback, usesDepthAttachment: depth,
                        encoder: encoder)
                }
                encoded = pipeline.draw(
                    texture: texture, instances: instances, uniforms: uniforms,
                    renderState: .init(blendMode: mode, cullMode: .none, overbright: overbright),
                    colorSampling: .directImageFallback, usesDepthAttachment: depth,
                    encoder: encoder)
            }
            encoder.endEncoding()
        }
        guard instances.markSubmitted(on: command),
              SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        else { throw command.error ?? failure("gpu-completion") }
        let pixels = readInterior(actual)
        let oracle = readInterior(expected)
        return ["mode": mode.rawValue, "textureAlpha": Int(textureAlpha),
                "particleAlpha": particleAlpha, "depth": depth,
                "encoded": encoded, "completed": command.status == .completed,
                "unpreparedCoverageAttempted": attemptsUnpreparedCoverage,
                "unpreparedCoverageEncoded": unpreparedCoverageEncoded,
                "actual": pixels, "reference": oracle,
                "maximumByteError": zip(pixels, oracle).map { abs($0 - $1) }.max() ?? 255]
    }

    private struct RuntimeInput {
        var name: String
        var renderer = "rope"
        var shape = "acute"
        var particleAlpha: Double = 1
        var rgba: [UInt8] = [96, 160, 224, 255]
        var overbright: Double = 1
        var blend: SceneParticlePipelineBlendMode = .alphaToCoverage
        var cull: SceneParticlePipelineCullMode = .none
        var depthTest = false
        var depthWrite = false
        var birthSpeed: Double? = nil
    }

    private struct RuntimeProduct {
        let batch: SceneParticleDrawBatch
        let input: RuntimeInput
        let facts: [String: Any]
    }

    private struct RuntimeDraw {
        let product: RuntimeProduct
        let uniforms: SceneParticleLayerUniforms
        var omitsReference = false
    }

    private static let runtimeWidth = 128
    private static let runtimeHeight = 96

    private static func runtimeProduct(
        _ input: RuntimeInput, layerID: Int, root: URL, device: MTLDevice
    ) throws -> RuntimeProduct {
        let path = "particles/\(input.name).json"
        let material = "materials/\(input.name).json"
        let textureName = "\(input.name).tex"
        let textureURL = root.appendingPathComponent("materials/\(textureName)")
        try FileManager.default.createDirectory(
            at: textureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Exact, self-authored RGBA8 bytes avoid an image encoder's PMA/color
        // conversion becoming part of the independent fragment-color oracle.
        var tex = Data("TEXV0005\0TEXI0001\0".utf8)
        for value: UInt32 in [0, 2, 4, 16, 4, 16, 0] { Harness.appendUInt32(value, to: &tex) }
        tex.append(Data("TEXB0002\0".utf8))
        for value: UInt32 in [1, 1, 4, 16, 0, 0, 256] { Harness.appendUInt32(value, to: &tex) }
        for _ in 0..<64 { tex.append(contentsOf: input.rgba) }
        try tex.write(to: textureURL)
        let origins: [[Double]]
        switch input.shape {
        case "acute": origins = [[-42, -14, 0], [8, -14, 0], [-6, 12, 0], [38, 18, 0]]
        case "zero": origins = Array(repeating: [0, 0, 0], count: 4)
        case "peer", "signedBirth": origins = [[0, 0, 0]]
        default: origins = [[-32, -12, 0]]
        }
        var initializers: [[String: Any]] = [
            ["name": "lifetimerandom", "min": 10, "max": 10],
            ["name": "sizerandom", "min": input.shape == "peer" ? 8 : 16,
             "max": input.shape == "peer" ? 8 : 16],
            ["name": "colorrandom", "min": [255, 255, 255], "max": [255, 255, 255]],
        ]
        if input.shape == "moving" {
            initializers.append(["name": "velocityrandom", "min": [80, 40, 0], "max": [80, 40, 0]])
        }
        var renderer: [String: Any] = ["name": input.renderer]
        if input.renderer == "rope" { renderer["subdivision"] = 6 }
        if input.renderer == "ropetrail" {
            renderer["length"] = 0.5
            renderer["segments"] = 8
            renderer["subdivision"] = 1
        }
        if input.renderer == "spritetrail" { renderer["length"] = 0.2 }
        let emitters: [[String: Any]] = origins.map { origin in
            var emitter: [String: Any] = ["name": "sphererandom", "rate": 0,
                "instantaneous": 1, "distancemin": 0, "distancemax": 0,
                "speedmin": 0, "speedmax": 0, "origin": origin]
            if let speed = input.birthSpeed {
                emitter["directions"] = [1, 0, 0]
                emitter["sign"] = [1, 0, 0]
                emitter["distancemin"] = 32
                emitter["distancemax"] = 32
                emitter["speedmin"] = speed
                emitter["speedmax"] = speed
            }
            return emitter
        }
        let moves = input.shape == "moving" || input.birthSpeed != nil
        try Harness.writeJSON([
            "material": material, "maxcount": 16, "starttime": 0,
            "emitter": emitters,
            "initializer": initializers,
            "operator": moves ? [["name": "movement", "drag": 0]] : [],
            "renderer": [renderer],
        ], to: root.appendingPathComponent(path))
        let constant = SceneDocument.ShaderValue(rawValue: String(input.overbright), valueKind: "number",
            components: [input.overbright], userBinding: nil, timeline: nil, timelineDiagnostics: [])
        let pass = SceneRenderDescriptor.MaterialPassDescriptor(
            materialPath: material, shaderPath: "genericparticle", texturePaths: [textureName],
            constantShaderValues: ["ui_editor_properties_overbright": constant],
            blending: input.blend.rawValue, depthTest: input.depthTest ? "enabled" : "disabled",
            depthWrite: input.depthWrite ? "enabled" : "disabled",
            cullMode: input.cull == .back ? "normal" : "nocull")
        let runtime = SceneParticleRuntime(descriptor: .init(
            layers: [Harness.layer(layerID, path, particleAlpha: input.particleAlpha)],
            renderOrderLayerIDs: [layerID], materialPasses: [pass]),
            cacheDirectory: root, device: device, stockTextureBundleURL: nil)
        var batches = runtime.advance(by: 0)
        for _ in 0..<(moves ? 30 : 2) { batches = runtime.advance(by: 1.0 / 60) }
        guard let batch = batches.first else {
            throw failure("runtime-\(input.name)-\(runtime.diagnostics)")
        }
        let birthFacts = input.birthSpeed == nil ? [] : runtime.consumeComponentObservations().filter {
            $0.layerID == layerID && $0.childTemplateIndex == nil
                && $0.particlePath.lowercased() == path.lowercased() && $0.evaluation.origin == "live"
        }
        return RuntimeProduct(batch: batch, input: input, facts: [
            "name": input.name, "layerID": layerID, "particlePath": path, "renderer": input.renderer,
            "actualRenderer": batch.debugRendererKind ?? "unknown", "shape": input.shape,
            "liveParticles": runtime.lifecycleSnapshot.rootParticleCount,
            "instances": batch.instances.count,
            "history": runtime.frameSnapshot().layers.first?.root?.ropeTrailHistory != nil,
            "requiredCoverage": runtime.requiredPipelineVariants.contains { $0.blendMode == .alphaToCoverage },
            "blend": batch.renderState.blendMode.rawValue, "cull": batch.renderState.cullMode.rawValue,
            "depthTest": batch.renderState.depthTestEnabled, "depthWrite": batch.renderState.depthWriteEnabled,
            "usesSceneCamera": batch.renderState.usesSceneCamera,
            "inheritsNativeSceneCamera": batch.inheritsNativeSceneCamera,
            "overbright": batch.renderState.overbright, "particleAlpha": input.particleAlpha,
            "textureRGBA": input.rgba.map(Int.init), "textureExtent": [batch.texture.width, batch.texture.height],
            "liveBirthAccepted": birthFacts.contains { $0.evaluation.stage == "accepted-birth" },
            "liveBirthRejected": birthFacts.contains { $0.evaluation.reason == "birth-construction-rejected" },
            "diagnostics": runtime.diagnostics.map { $0.kind.rawValue },
        ])
    }

    private static func runtimeDraw(
        _ product: RuntimeProduct, camera: SceneParticleCameraFrame,
        affine: simd_float4x4 = SceneMatrix.identity(), origin: SIMD3<Float> = SIMD3(64, 48, 0),
        omitsReference: Bool = false
    ) -> RuntimeDraw {
        let batch = product.batch
        let model = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.translation(origin) * affine, parallaxOffset: .zero)
        return RuntimeDraw(product: product, uniforms: camera.particleUniforms(
            layerModel: model, orientation: batch.orientation, orientationAxis: batch.orientationAxis,
            usesPerspective: batch.usesPerspective, usesSceneCamera: batch.renderState.usesSceneCamera,
            inheritsNativeSceneCamera: batch.inheritsNativeSceneCamera,
            viewportSize: SIMD2(Float(runtimeWidth), Float(runtimeHeight)),
            sizeIsWorldSpace: batch.sizeIsWorldSpace), omitsReference: omitsReference)
    }

    private static func runtimeCases(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: SceneParticleMetalPipeline,
        ordinaryPipeline: SceneParticleMetalPipeline, library: MTLLibrary
    ) throws -> ([[String: Any]], [[String: Any]], [[String: Any]]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-particle-coverage-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var cameraDescriptor = SceneRenderDescriptor.CameraDescriptor()
        cameraDescriptor.orthoWidth = Float(runtimeWidth)
        cameraDescriptor.orthoHeight = Float(runtimeHeight)
        cameraDescriptor.nearZ = 0.01
        cameraDescriptor.farZ = 2.01
        let camera = SceneParticleCameraFrame(camera: cameraDescriptor,
            viewportSize: CGSize(width: CGFloat(runtimeWidth), height: CGFloat(runtimeHeight)))
        let probe = try vertexProbe(device: device)
        var references: [String: MTLRenderPipelineState] = [:]
        for depth in [false, true] {
            for mode in [SceneParticlePipelineBlendMode.alphaToCoverage, .translucent] {
                references["\(mode.rawValue)-\(depth)"] = try referenceState(
                    device: device, library: library, mode: mode, depth: depth, mesh: true)
            }
        }
        var depthStates: [Int: MTLDepthStencilState] = [:]
        for key in 0..<4 {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = key & 1 != 0 ? .lessEqual : .always
            descriptor.isDepthWriteEnabled = key & 2 != 0
            guard let state = device.makeDepthStencilState(descriptor: descriptor)
            else { throw failure("reference-depth") }
            depthStates[key] = state
        }
        var layerID = 100
        func make(_ input: RuntimeInput) throws -> RuntimeProduct {
            layerID += 1
            return try runtimeProduct(input, layerID: layerID, root: root, device: device)
        }
        func render(_ name: String, _ draws: [RuntimeDraw], depth: Bool = false,
                    missingPSO: Bool = false, frozenPoints: [SIMD2<Int>] = []) throws -> [String: Any] {
            try renderRuntime(name, draws: draws, device: device, queue: queue,
                pipeline: missingPSO ? ordinaryPipeline : pipeline,
                probe: probe, references: references, depthStates: depthStates, depth: depth,
                frozenPoints: frozenPoints)
        }
        var rows: [[String: Any]] = []
        let inputs = [
            RuntimeInput(name: "acuteOpaque"),
            RuntimeInput(name: "acutePartial", particleAlpha: 0.52, rgba: [96, 160, 224, 192]),
            RuntimeInput(name: "acuteParticleZero", particleAlpha: 0),
            RuntimeInput(name: "acuteTextureZero", rgba: [96, 160, 224, 0]),
            RuntimeInput(name: "zeroSpan", shape: "zero"),
            RuntimeInput(name: "singleRope", shape: "moving"),
            RuntimeInput(name: "movingRopeTrail", renderer: "ropetrail", shape: "moving"),
            RuntimeInput(name: "movingSpriteTrail", renderer: "spritetrail", shape: "moving"),
            RuntimeInput(name: "movingSprite", renderer: "sprite", shape: "moving"),
            RuntimeInput(name: "renamedRibbon"),
            RuntimeInput(name: "overbright65", rgba: [1, 2, 3, 255], overbright: 65),
        ]
        for input in inputs {
            rows.append(try render(input.name, [runtimeDraw(try make(input), camera: camera)]))
        }
        for renderer in ["rope", "ropetrail", "spritetrail", "sprite"] {
            for (suffix, cull, mirrored) in [
                ("back", SceneParticlePipelineCullMode.back, false),
                ("backMirror", .back, true), ("noCullMirror", .none, true),
            ] {
                let name = "\(renderer)-\(suffix)"
                let product = try make(.init(name: name, renderer: renderer,
                    shape: renderer == "rope" ? "acute" : "moving", cull: cull))
                let sign: Float = mirrored ? -1 : 1
                let affine = simd_float4x4(columns: (
                    SIMD4(sign * 0.85, sign * 0.15, 0, 0), SIMD4(0.2, 0.65, 0, 0),
                    SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
                var row = try render(name, [runtimeDraw(product, camera: camera, affine: affine)])
                row["mirrored"] = mirrored
                rows.append(row)
            }
        }
        let missing = try make(.init(name: "missingRope"))
        let peer = try make(.init(name: "healthyPeer", renderer: "sprite", shape: "peer",
            rgba: [192, 96, 48, 255], blend: .translucent))
        rows.append(try render("missingPSO", [runtimeDraw(missing, camera: camera, omitsReference: true),
            runtimeDraw(peer, camera: camera, origin: SIMD3(116, 14, 0))], missingPSO: true))

        var depthRows: [[String: Any]] = []
        for renderer in ["rope", "ropetrail", "spritetrail", "sprite"] {
            let shape = renderer == "rope" ? "acute" : "moving"
            let writer = try make(.init(name: "\(renderer)-writer", renderer: renderer, shape: shape,
                rgba: [224, 32, 16, 255], depthTest: true, depthWrite: true))
            let readOnly = try make(.init(name: "\(renderer)-reader", renderer: renderer, shape: shape,
                rgba: [16, 192, 32, 255], depthTest: true))
            let ordinary = try make(.init(name: "\(renderer)-ordinaryReader", renderer: renderer,
                shape: shape, particleAlpha: 0.52, rgba: [16, 192, 32, 255],
                blend: .translucent, depthTest: true))
            let disabled = try make(.init(name: "\(renderer)-disabled", renderer: renderer,
                shape: shape, rgba: [16, 192, 32, 255]))
            let writeOnly = try make(.init(name: "\(renderer)-writeOnly", renderer: renderer,
                shape: shape, rgba: [224, 32, 16, 255], depthWrite: true))
            let nearWriter = runtimeDraw(writer, camera: camera, origin: SIMD3(64, 48, 0.5))
            let farReader = runtimeDraw(readOnly, camera: camera, origin: SIMD3(64, 48, -0.5))
            let cases: [(String, [RuntimeDraw])] = [
                ("writer", [nearWriter]), ("reader", [farReader]),
                ("writerFirst", [nearWriter, farReader]), ("writerLast", [farReader, nearWriter]),
                ("mixedReadonly", [nearWriter,
                    runtimeDraw(ordinary, camera: camera, origin: SIMD3(64, 48, -0.5))]),
                ("ordinaryReader", [runtimeDraw(ordinary, camera: camera, origin: SIMD3(64, 48, -0.5))]),
                ("readonlyDoesNotWrite", [runtimeDraw(readOnly, camera: camera, origin: SIMD3(64, 48, 0.5)),
                    runtimeDraw(writer, camera: camera, origin: SIMD3(64, 48, -0.5))]),
                ("ordinaryReadonlyDoesNotWrite", [runtimeDraw(ordinary, camera: camera, origin: SIMD3(64, 48, 0.5)),
                    runtimeDraw(writer, camera: camera, origin: SIMD3(64, 48, -0.5))]),
                ("depthDisabled", [nearWriter,
                    runtimeDraw(disabled, camera: camera, origin: SIMD3(64, 48, -0.5))]),
                ("writeWithoutTest", [runtimeDraw(writeOnly, camera: camera, origin: SIMD3(64, 48, 0.5)), farReader]),
            ]
            for (name, draws) in cases {
                var row = try render("\(renderer)-\(name)", draws, depth: true)
                row["renderer"] = renderer
                row["scenario"] = name
                depthRows.append(row)
            }
        }
        // Preregistered independently of Runtime output: one +X sphere axis,
        // sign+1 and fixed radius32 put birth atx32. Thirty1/60 movement steps
        // with speed-32/0/+32 end at localx16/32/48, or screenx80/96/112.
        // The Runtime, mesh probe and production draw supply all measured data.
        let frozenPoints = [SIMD2(80, 48), SIMD2(96, 48), SIMD2(112, 48),
                            SIMD2(116, 14), SIMD2(4, 4)]
        var signedBirth: [[String: Any]] = []
        for (name, speed) in [("inwardBirth", -32.0), ("stationaryBirth", 0.0),
                              ("outwardBirth", 32.0), ("renamedInwardBirth", -32.0)] {
            let product = try make(.init(name: name, renderer: "sprite", shape: "signedBirth",
                blend: .translucent, birthSpeed: speed))
            var row = try render(name, [runtimeDraw(product, camera: camera),
                runtimeDraw(peer, camera: camera, origin: SIMD3(116, 14, 0))], frozenPoints: frozenPoints)
            row["authoredSpeed"] = speed
            signedBirth.append(row)
        }
        return (rows, depthRows, signedBirth)
    }

    private static func vertexProbe(device: MTLDevice) throws -> MTLRenderPipelineState {
        let source = sceneParticleShaderSource + """
        vertex void coverageProductionProbe(
            uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
            constant QuadVertex *quad [[buffer(0)]],
            device const ParticleInstance *instances [[buffer(1)]],
            constant LayerUniforms &uniforms [[buffer(2)]], device float4 *positions [[buffer(3)]]) {
            positions[instanceID * 4 + vertexID] =
                particleVertex(vertexID, instanceID, quad, instances, uniforms, true).position;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "coverageProductionProbe")
        descriptor.isRasterizationEnabled = false
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func renderRuntime(
        _ name: String, draws: [RuntimeDraw], device: MTLDevice, queue: MTLCommandQueue,
        pipeline: SceneParticleMetalPipeline, probe: MTLRenderPipelineState,
        references: [String: MTLRenderPipelineState], depthStates: [Int: MTLDepthStencilState], depth: Bool,
        frozenPoints: [SIMD2<Int>] = []
    ) throws -> [String: Any] {
        let actual = try target(device: device, width: runtimeWidth, height: runtimeHeight)
        let expected = try target(device: device, width: runtimeWidth, height: runtimeHeight)
        guard let command = queue.makeCommandBuffer() else { throw failure("runtime-command") }
        var prepared: [(draw: RuntimeDraw, batch: SceneParticleMetalPipeline.PreparedBatch?, positions: MTLBuffer?)] = []
        for draw in draws {
            guard let batch = pipeline.prepare([draw.product.batch]).first else {
                if !draw.product.batch.instances.isEmpty { throw failure("runtime-prepare-\(name)") }
                prepared.append((draw, nil, nil))
                continue
            }
            guard let state = batch.instanceBuffer.currentDrawState(),
                  batch.instanceBuffer.armSubmission(on: command),
                  let positions = device.makeBuffer(length: state.count * 4 * 16, options: .storageModeShared)
            else { throw failure("runtime-probe-buffer") }
            let pass = MTLRenderPassDescriptor()
            pass.renderTargetWidth = 1
            pass.renderTargetHeight = 1
            pass.defaultRasterSampleCount = 1
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { throw failure("runtime-probe-encoder") }
            var quad: [SIMD4<Float>] = [
                SIMD4(-0.5, -0.5, 0, 1), SIMD4(0.5, -0.5, 1, 1),
                SIMD4(-0.5, 0.5, 0, 0), SIMD4(0.5, 0.5, 1, 0),
            ]
            var uniforms = draw.uniforms
            encoder.setRenderPipelineState(probe)
            encoder.setVertexBytes(&quad, length: quad.count * 16, index: 0)
            encoder.setVertexBuffer(state.buffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
            encoder.setVertexBuffer(positions, offset: 0, index: 3)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 4, instanceCount: state.count)
            encoder.endEncoding()
            prepared.append((draw, batch, positions))
        }
        var depthTexture: MTLTexture?
        if depth {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                width: runtimeWidth, height: runtimeHeight, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            depthTexture = device.makeTexture(descriptor: descriptor)
            if depthTexture == nil { throw failure("runtime-depth-target") }
        }
        var encoded: [Bool] = []
        for (output, isReference) in [(actual, false), (expected, true)] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(16.0 / 255, 24.0 / 255, 40.0 / 255, 102.0 / 255)
            if depth {
                pass.depthAttachment.texture = depthTexture
                pass.depthAttachment.loadAction = .clear
                pass.depthAttachment.storeAction = .dontCare
                pass.depthAttachment.clearDepth = 1
            }
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { throw failure("runtime-render-encoder") }
            for record in prepared {
                guard let batch = record.batch, let positions = record.positions else {
                    if !isReference { encoded.append(false) }
                    continue
                }
                let input = record.draw.product.input
                if isReference {
                    if record.draw.omitsReference { continue }
                    guard let state = references["\(input.blend.rawValue)-\(depth)"]
                    else { throw failure("runtime-reference-pso") }
                    let alpha = Float(input.rgba[3]) / 255 * Float(input.particleAlpha)
                    var rgb = SIMD3<Float>(Float(input.rgba[0]), Float(input.rgba[1]), Float(input.rgba[2]))
                        / 255 * Float(input.overbright)
                    if input.blend != .alphaToCoverage { rgb *= alpha }
                    var color = SIMD4(rgb, alpha)
                    encoder.setRenderPipelineState(state)
                    encoder.setFrontFacing(.counterClockwise)
                    encoder.setCullMode(input.cull == .back ? .back : .none)
                    if depth { encoder.setDepthStencilState(depthStates[(input.depthTest ? 1 : 0) | (input.depthWrite ? 2 : 0)]) }
                    encoder.setVertexBuffer(positions, offset: 0, index: 0)
                    encoder.setFragmentBytes(&color, length: 16, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                        instanceCount: batch.draw.instances.count)
                } else {
                    encoded.append(pipeline.draw(texture: batch.draw.texture, instances: batch.instanceBuffer,
                        uniforms: record.draw.uniforms, renderState: batch.draw.renderState,
                        colorUVScale: batch.draw.colorUVScale, colorSampling: batch.draw.colorSampling,
                        usesDepthAttachment: depth, encoder: encoder))
                }
            }
            encoder.endEncoding()
        }
        for record in prepared {
            if let batch = record.batch, !batch.instanceBuffer.markSubmitted(on: command) {
                throw failure("runtime-submission")
            }
        }
        guard SceneParticleOffscreenReadbackHarness.commitAndWait(command)
        else { throw command.error ?? failure("runtime-completion") }
        let pixels = readPixels(actual), oracle = readPixels(expected)
        var histogram: [String: Int] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            histogram[pixels[index..<index + 4].map(String.init).joined(separator: ","), default: 0] += 1
        }
        func pixel(_ x: Int, _ y: Int) -> [Int] {
            let index = (y * runtimeWidth + x) * 4
            return Array(pixels[index..<index + 4])
        }
        // Frozen before any GPU result: the two inner live nodes of the acute
        // fixture, outside corners, and the separately placed healthy peer.
        let nodePixels = [(72, 62), (58, 36)].flatMap { x, y in
            (-1...1).flatMap { dy in (-1...1).map { dx in pixel(x + dx, y + dy) } }
        }
        var vertices: [SIMD4<Float>] = []
        if let first = prepared.first, let positions = first.positions {
            let count = first.draw.product.batch.instances.count * 4
            vertices = Array(UnsafeBufferPointer(
                start: positions.contents().assumingMemoryBound(to: SIMD4<Float>.self), count: count))
        }
        let vertexPixels = vertices.map { SIMD2(($0.x / $0.w + 1) * Float(runtimeWidth) / 2,
                                                (1 - $0.y / $0.w) * Float(runtimeHeight) / 2) }
        var joinGap: Float = 0
        if draws.first?.product.input.renderer == "rope" || draws.first?.product.input.renderer == "ropetrail" {
            for index in stride(from: 0, to: max(0, vertexPixels.count - 4), by: 4) {
                // Live Rope and history RopeTrail serialize opposite ends
                // first; adjacent quads must share one complete edge in either order.
                let forward = max(simd_distance(vertexPixels[index + 1], vertexPixels[index + 4]),
                                  simd_distance(vertexPixels[index + 3], vertexPixels[index + 6]))
                let backward = max(simd_distance(vertexPixels[index], vertexPixels[index + 5]),
                                   simd_distance(vertexPixels[index + 2], vertexPixels[index + 7]))
                joinGap = max(joinGap, min(forward, backward))
            }
        }
        let bounds: [Float] = vertexPixels.isEmpty ? [] : [
            vertexPixels.map(\.x).min()!, vertexPixels.map(\.y).min()!,
            vertexPixels.map(\.x).max()!, vertexPixels.map(\.y).max()!,
        ]
        return ["name": name, "facts": draws.map { $0.product.facts }, "encoded": encoded,
            "completed": command.status == .completed, "usesDepthAttachment": depth,
            "maximumByteError": zip(pixels, oracle).map { abs($0 - $1) }.max() ?? 255,
            "changedPixels": runtimeWidth * runtimeHeight - (histogram["16,24,40,102"] ?? 0),
            "histogram": histogram, "nodePixels": nodePixels,
            "outsidePixels": [pixel(4, 4), pixel(123, 90)], "peerPixel": pixel(116, 14),
            "frozenPoints": frozenPoints.map { [$0.x, $0.y] },
            "frozenPixels": frozenPoints.map { pixel($0.x, $0.y) },
            "vertexCount": vertices.count, "vertexBounds": bounds,
            "verticesFinite": vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite },
            "maximumJoinGapPixels": joinGap]
    }

    private static func failure(_ stage: String) -> NSError {
        NSError(domain: "SceneParticleCoverageRenderingHarness.\(stage)", code: 1)
    }
}
