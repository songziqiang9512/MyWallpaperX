import Foundation
import Metal
import simd

// The probe does not reserve composition targets.
final class SceneGraphRenderTargetResidencyPin { func release() {} }

@main enum ScenePointVolumeChecks {
    static let side = 65
    static let background = MTLClearColorMake(0.0625, 0.125, 0.1875, 0.375)

    static func point(
        _ position: SIMD3<Float>, radius: Float, color: SIMD3<Float> = SIMD3(1, 0, 0),
        intensity: Float = 3, volume: ScenePointLightDefinition.Volume? = .init(density: 1, exponent: 2)
    ) -> SceneLightSnapshot.Point {
        .init(position: position, color: color, intensity: intensity, radius: radius, volume: volume)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: "default.metallib"))
        let modelPipeline = SceneStaticModelPipeline(device: device, preparesCameraDepth: true, preparesShadows: false)!
        // A scaled copy at each distance keeps the same projected upper-half footprint.
        let vertices = [SIMD3<Float>(-0.5, 0.04, -1), SIMD3(0.5, 0.04, -1),
                        SIMD3(-0.5, 0.5, -1), SIMD3(0.5, 0.5, -1)].map { position in
            SceneMdlStaticModel.Vertex(position: position, normal: SIMD3(0, 0, 1),
                tangent: SIMD4(1, 0, 0, 1), uv: .zero)
        }
        let mesh = modelPipeline.makeMesh(model: SceneStaticModelFixture.model(
            vertices: vertices, indices: [0, 1, 2, 1, 3, 2]))!

        func render(
            _ lights: [SceneLightSnapshot.Point], planes: [Float] = [],
            planeDepthTests: [Bool] = [],
            frontFacing: MTLWinding = .counterClockwise, cullMode: MTLCullMode = .none,
            near: Float = 0.25, far: Float = 20,
            format: MTLPixelFormat = .bgra8Unorm, pipeline: ScenePointVolumePipeline,
            clipsScreenCoverage: Bool = false, wholeFrame: Bool = false,
            width: Int = side, cameraOverride: ScenePointVolumePipeline.Camera? = nil
        ) -> [String: Any] {
            let command = queue.makeCommandBuffer()!
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: width, height: side, mipmapped: false)
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = [.shaderRead, .renderTarget]
            let depth = device.makeTexture(descriptor: depthDescriptor)!
            let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: width, height: side, mipmapped: false)
            outputDescriptor.storageMode = .shared
            outputDescriptor.usage = .renderTarget
            let target = device.makeTexture(descriptor: outputDescriptor)!
            let depthPass = MTLRenderPassDescriptor()
            depthPass.depthAttachment.texture = depth
            depthPass.depthAttachment.loadAction = .clear
            depthPass.depthAttachment.clearDepth = 0
            depthPass.depthAttachment.storeAction = .store
            let writer = command.makeRenderCommandEncoder(descriptor: depthPass)!
            let projection = SceneMatrix.reversingDepth(SceneMatrix.perspectiveRHMetal(
                fovYRadians: .pi / 2, aspect: Float(width) / Float(side), near: near, far: far))
            for (index, distance) in planes.enumerated() {
                precondition(modelPipeline.drawCameraDepth(mesh: mesh,
                    modelToClip: projection * SceneMatrix.scale(SIMD3(repeating: distance)),
                    frontFacing: frontFacing, cullMode: cullMode,
                    testsDepth: planeDepthTests.indices.contains(index) ? planeDepthTests[index] : true,
                    encoder: writer))
            }
            writer.endEncoding()

            let pass = SceneMainPassEncoder(commandBuffer: command, target: target,
                clearColor: background, clearEnabled: true)
            let camera = cameraOverride ?? ScenePointVolumePipeline.Camera(origin: .zero, near: near,
                forward: SIMD3(0, 0, -1), far: far, horizontal: SIMD3(1, 0, 0), vertical: SIMD3(0, 1, 0))
            let prepared = pipeline.prepare(lights: lights, camera: camera,
                viewport: pass.targetExtent, clipsScreenCoverage: clipsScreenCoverage)
            if let prepared { pipeline.draw(prepared, depth: depth, encoder: pass.encoder()!) }
            precondition(pass.finishEnsuringClear())
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed && command.error == nil,
                "point volume Metal command failed: \(String(describing: command.error))")
            var result: [String: Any] = ["encoded": prepared != nil,
                    "center": pixel(target, x: 32, y: 32),
                    "covered": pixel(target, x: 32, y: 28),
                    "uncovered": pixel(target, x: 32, y: 36),
                    "shoulder": pixel(target, x: 40, y: 32),
                    "outside": pixel(target, x: 49, y: 32)]
            if wholeFrame {
                let bytesPerRow = width * (format == .rgba16Float ? 8 : 4)
                var pixels = Data(count: bytesPerRow * side)
                pixels.withUnsafeMutableBytes {
                    target.getBytes($0.baseAddress!, bytesPerRow: bytesPerRow,
                        from: MTLRegionMake2D(0, 0, width, side), mipmapLevel: 0)
                }
                result["pixels"] = pixels
                result["rect"] = prepared.map { draw -> [Int] in
                    guard let scissor = draw.scissor else { return [0, 0, width, side] }
                    return [scissor.x, scissor.y, scissor.width, scissor.height]
                } ?? []
            }
            return result
        }

        let ldr = ScenePointVolumePipeline(device: device, library: library, pixelFormat: .bgra8Unorm)!
        let hdr = ScenePointVolumePipeline(device: device, library: library, pixelFormat: .rgba16Float)!
        let position = SIMD3<Float>(0, 0, -5)
        let red = point(position, radius: 1.75)
        let green = point(position, radius: 1.75, color: SIMD3(0, 1, 0))
        var result = [
            "background": render([], pipeline: ldr),
            "red": render([red], pipeline: ldr),
            "highFarNearRatio": render([red], near: 0.01, far: 1_000_000, pipeline: ldr),
            "nearPlane": render([red], planes: [2], pipeline: ldr),
            "throughVolume": render([red], planes: [5], pipeline: ldr),
            "farPlane": render([red], planes: [8], pipeline: ldr),
            "nearThenFar": render([red], planes: [2, 8], pipeline: ldr),
            "farThenNear": render([red], planes: [8, 2], pipeline: ldr),
            "nearThenFarNoTest": render([red], planes: [2, 8], planeDepthTests: [true, false], pipeline: ldr),
            "farThenNearNoTest": render([red], planes: [8, 2], planeDepthTests: [true, false], pipeline: ldr),
            "counterClockwise": render([red], planes: [2], cullMode: .back, pipeline: ldr),
            "clockwise": render([red], planes: [2], frontFacing: .clockwise, cullMode: .back, pipeline: ldr),
            "cameraInside": render([point(SIMD3(0, 0, -0.7), radius: 2)], pipeline: ldr),
            "pastFarPlane": render([point(SIMD3(0, 0, -24), radius: 1.75)], pipeline: ldr),
            "surfaceOnly": render([point(position, radius: 1.75, volume: nil)], pipeline: ldr),
            "zeroIntensity": render([point(position, radius: 1.75, intensity: 0)], pipeline: ldr),
            "zeroDensity": render([point(position, radius: 1.75, volume: .init(density: 0, exponent: 2))], pipeline: ldr),
            "lowerExponent": render([point(position, radius: 1.75, volume: .init(density: 1, exponent: 0))], pipeline: ldr),
            "twoLights": render([red, green], pipeline: ldr),
            "hdrUniformDensity": render([point(position, radius: 1.75, intensity: 8,
                volume: .init(density: 1, exponent: 0))], format: .rgba16Float, pipeline: hdr),
            "hdrHighExponent": render([point(position, radius: 1.75, intensity: 8,
                volume: .init(density: 1, exponent: 10))], format: .rgba16Float, pipeline: hdr),
        ]
        let probes: [(String, [SceneLightSnapshot.Point], [Float], Bool)] = [
            ("occluded", [red], [2], false),
            ("through", [red], [5], false),
            ("partial-far", [point(SIMD3(1, 0, -20), radius: 1.75)], [], false),
            ("off-axis", [point(SIMD3(2.4, 1.2, -5), radius: 0.8)], [], false),
            ("viewport-edge", [point(SIMD3(4.8, 0.7, -5), radius: 0.9)], [], false),
            ("inside", [point(SIMD3(0, 0, -0.7), radius: 2)], [], false),
            ("cross-near", [point(SIMD3(0.15, 0.04, -0.35), radius: 0.2)], [], false),
            ("before-near", [point(SIMD3(0, 0, -0.12), radius: 0.03)], [], false),
            ("behind-far", [point(SIMD3(0, 0, -24), radius: 1.75)], [], false),
            ("axis-miss", [point(SIMD3(8, 0.1, -5), radius: 0.2)], [], false),
            ("overlap", [red, point(SIMD3(0.45, 0.1, -5), radius: 1.75, color: SIMD3(0, 1, 0))], [], true),
            ("disjoint", [point(SIMD3(-2, 0.8, -5), radius: 0.6),
                          point(SIMD3(2, -0.7, -5), radius: 0.6, color: SIMD3(0, 1, 0))], [], false),
        ]
        let emptySDR = render([], pipeline: ldr, wholeFrame: true)["pixels"] as! Data
        let emptyHDR = render([], format: .rgba16Float, pipeline: hdr, wholeFrame: true)["pixels"] as! Data
        for (name, lights, planes, useHDR) in probes {
            let format: MTLPixelFormat = useHDR ? .rgba16Float : .bgra8Unorm
            let pipeline = useHDR ? hdr : ldr
            let full = render(lights, planes: planes, format: format, pipeline: pipeline, wholeFrame: true)
            let scissored = render(lights, planes: planes, format: format, pipeline: pipeline,
                clipsScreenCoverage: true, wholeFrame: true)
            let original = full["pixels"] as! Data
            let narrowed = scissored["pixels"] as! Data
            result["bounds-\(name)"] = ["sameRGBA": original == narrowed,
                "visible": original != (useHDR ? emptyHDR : emptySDR),
                "fullEncoded": full["encoded"]!, "encoded": scissored["encoded"]!, "rect": scissored["rect"]!]
        }
        let shifted = SIMD3<Float>(21, -12, 5)
        let rotated = ScenePointVolumePipeline.Camera(origin: shifted, near: 0.25,
            forward: SIMD3(1, 0, 0), far: 20, horizontal: SIMD3(0, 0, 1.4), vertical: SIMD3(0, 1, 0))
        let lamp = point(shifted + SIMD3(5, -0.3, 2), radius: 0.67)
        let rotatedFull = render([lamp], pipeline: ldr, wholeFrame: true, width: 91, cameraOverride: rotated)
        let rotatedScissor = render([lamp], pipeline: ldr, clipsScreenCoverage: true,
            wholeFrame: true, width: 91, cameraOverride: rotated)
        let normalBytes = rotatedFull["pixels"] as! Data
        result["bounds-rotated-nonsquare"] = [
            "sameRGBA": normalBytes == (rotatedScissor["pixels"] as! Data),
            "visible": normalBytes != (render([], pipeline: ldr, wholeFrame: true, width: 91)["pixels"] as! Data),
            "fullEncoded": rotatedFull["encoded"]!,
            "encoded": rotatedScissor["encoded"]!,
            "rect": rotatedScissor["rect"]!,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }

    static func pixel(_ target: MTLTexture, x: Int, y: Int) -> [Float] {
        let region = MTLRegionMake2D(x, y, 1, 1)
        if target.pixelFormat == .rgba16Float {
            var values = [UInt16](repeating: 0, count: 4)
            target.getBytes(&values, bytesPerRow: 8, from: region, mipmapLevel: 0)
            return values.map { Float(Float16(bitPattern: $0)) }
        }
        var bgra = [UInt8](repeating: 0, count: 4)
        target.getBytes(&bgra, bytesPerRow: 4, from: region, mipmapLevel: 0)
        return [bgra[2], bgra[1], bgra[0], bgra[3]].map { Float($0) / 255 }
    }
}
