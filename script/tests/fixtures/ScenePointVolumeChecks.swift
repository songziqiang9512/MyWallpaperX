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
        let modelPipeline = SceneStaticModelPipeline(device: device, preparesCameraDepth: true)!
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
            frontFacing: MTLWinding = .counterClockwise, cullMode: MTLCullMode = .none,
            near: Float = 0.25, far: Float = 20,
            format: MTLPixelFormat = .bgra8Unorm, pipeline: ScenePointVolumePipeline
        ) -> [String: Any] {
            let command = queue.makeCommandBuffer()!
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: side, height: side, mipmapped: false)
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = [.shaderRead, .renderTarget]
            let depth = device.makeTexture(descriptor: depthDescriptor)!
            let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: side, height: side, mipmapped: false)
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
                fovYRadians: .pi / 2, aspect: 1, near: near, far: far))
            for distance in planes {
                precondition(modelPipeline.drawCameraDepth(mesh: mesh,
                    modelToClip: projection * SceneMatrix.scale(SIMD3(repeating: distance)),
                    frontFacing: frontFacing, cullMode: cullMode, encoder: writer))
            }
            writer.endEncoding()

            let pass = SceneMainPassEncoder(commandBuffer: command, target: target,
                clearColor: background, clearEnabled: true)
            let camera = ScenePointVolumePipeline.Camera(origin: .zero, near: near,
                forward: SIMD3(0, 0, -1), far: far, horizontal: SIMD3(1, 0, 0), vertical: SIMD3(0, 1, 0))
            let encoded = pipeline.draw(lights: lights, camera: camera,
                depth: depth, encoder: pass.encoder()!)
            precondition(pass.finishEnsuringClear())
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed && command.error == nil,
                "point volume Metal command failed: \(String(describing: command.error))")
            return ["encoded": encoded,
                    "center": pixel(target, x: 32, y: 32),
                    "covered": pixel(target, x: 32, y: 28),
                    "uncovered": pixel(target, x: 32, y: 36),
                    "shoulder": pixel(target, x: 40, y: 32),
                    "outside": pixel(target, x: 49, y: 32)]
        }

        let ldr = ScenePointVolumePipeline(device: device, library: library, pixelFormat: .bgra8Unorm)!
        let hdr = ScenePointVolumePipeline(device: device, library: library, pixelFormat: .rgba16Float)!
        let position = SIMD3<Float>(0, 0, -5)
        let red = point(position, radius: 1.75)
        let green = point(position, radius: 1.75, color: SIMD3(0, 1, 0))
        let result = [
            "background": render([], pipeline: ldr),
            "red": render([red], pipeline: ldr),
            "highFarNearRatio": render([red], near: 0.01, far: 1_000_000, pipeline: ldr),
            "nearPlane": render([red], planes: [2], pipeline: ldr),
            "throughVolume": render([red], planes: [5], pipeline: ldr),
            "farPlane": render([red], planes: [8], pipeline: ldr),
            "nearThenFar": render([red], planes: [2, 8], pipeline: ldr),
            "farThenNear": render([red], planes: [8, 2], pipeline: ldr),
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
