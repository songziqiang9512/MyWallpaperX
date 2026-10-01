import Foundation
import Metal
import simd

@main
enum Harness {
    static let width = 32
    static let height = 16
    static let albedo = SIMD4<Float>(0.2, 0.15, 0.1, 0.5)
    static let uniforms = SceneLayerFragmentUniforms(
        time: 0, alpha: 1, dependencyBlendMode: 0, usesDependencyBlend: 0,
        cursorUV: .zero, sourceSampling: .zero, tint: SIMD4(repeating: 1),
        textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0)
    )

    static func texture(_ device: MTLDevice, fill: SIMD4<Float>? = nil) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false
        )
        d.storageMode = .shared
        d.usage = [.shaderRead, .renderTarget]
        let t = device.makeTexture(descriptor: d)!
        if let fill {
            let pixel = [Float16(fill.x), Float16(fill.y), Float16(fill.z), Float16(fill.w)]
            let data = (0..<(width * height)).flatMap { _ in pixel }
            data.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 8) }
        }
        return t
    }

    static func render(
        _ device: MTLDevice, _ queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline, lit: SceneLitImageLayerPipeline,
        payload: SceneLitImageLayerLightPayload?, normal: MTLTexture? = nil
    ) -> [Float] {
        let source = texture(device, fill: albedo)
        let captured = texture(device)
        let terminal = texture(device)
        let command = queue.makeCommandBuffer()!
        let lighting = payload.flatMap { SceneBaseMaterialLitCapturePayload(pipeline: lit, lights: $0, normalTexture: normal) }
        precondition(SceneOffscreenEffectRenderer.captureSource(
            sourceTexture: source, target: captured, sourceUniforms: uniforms,
            pipeline: pipeline, commandBuffer: command, sourceLighting: lighting
        ))
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = terminal
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        d.colorAttachments[0].storeAction = .store
        let encoder = command.makeRenderCommandEncoder(descriptor: d)!
        pipeline.bind(encoder: encoder)
        pipeline.drawLayer(texture: captured, mvp: SceneOffscreenEffectRenderer.fullTargetMVP,
            uniforms: uniforms, encoder: encoder)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed && command.error == nil)
        var pixels = [Float16](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { terminal.getBytes($0.baseAddress!, bytesPerRow: width * 8,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return pixels.map(Float.init)
    }

    static func matrix(_ x: Float, _ y: Float, angle: Float = 0) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(SIMD4(c*x, s*x, 0, 0), SIMD4(-s*y, c*y, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(20, -10, 0, 1))
    }

    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float, library: library)!
        let lit = SceneLitImageLayerPipeline(device: device, pixelFormat: .rgba16Float, library: library)!
        let flat = texture(device, fill: SIMD4(0.5, 0.5, 1, 1))
        let tilted = texture(device, fill: SIMD4(1, 0.5, 0.5, 1))
        let ambient = SIMD3<Float>(repeating: 0.03)
        typealias Capture = SceneBaseMaterialLitCapturePayload
        var caseCount = 0
        var maxError: Float = 0
        var flatError: Float = 0
        var moveDelta: Float = 0
        var previous: [Float] = []
        for model in [matrix(200, 100), matrix(80, 320), matrix(200, 100, angle: .pi/2)] {
            for position in [SIMD3<Float>(20, 75, 80), SIMD3<Float>(20, -95, 80)] {
                for useTilted in [false, true] {
                    let point = Capture.PointLight(position: position, color: SIMD3(1, 0.7, 0.4), intensity: 2, radius: 500)
                    let payload = Capture.packLights(pointLights: [point], spotLights: [], ambient: ambient, layerModelMatrix: model)!
                    let pixels = render(device, queue, pipeline: pipeline, lit: lit, payload: payload, normal: useTilted ? tilted : nil)
                    let tangentNormal = useTilted ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
                    let n4 = simd_transpose(simd_inverse(model)) * SIMD4(tangentNormal, 0)
                    let normal = simd_normalize(SIMD3(n4.x,n4.y,n4.z))
                    for y in 0..<height { for x in 0..<width {
                        let local = SIMD4<Float>((Float(x)+0.5)/Float(width)-0.5, 0.5-(Float(y)+0.5)/Float(height), 0, 1)
                        let w = model * local
                        let delta = position - SIMD3(w.x,w.y,w.z)
                        let distance = simd_length(delta)
                        let amount = pow(max(0, 1-distance/point.radius), 2) * max(0, simd_dot(normal, delta/distance)) * point.intensity
                        let lighting = ambient + point.color * amount
                        for channel in 0..<3 {
                            maxError = max(maxError, abs(pixels[(y*width+x)*4+channel] - albedo[channel]*lighting[channel]))
                        }
                        precondition(abs(pixels[(y*width+x)*4+3]-0.5) < 0.001)
                    }}
                    if !useTilted {
                        let flatPixels = render(device, queue, pipeline: pipeline, lit: lit, payload: payload, normal: flat)
                        flatError = max(flatError, zip(pixels, flatPixels).map { abs($0-$1) }.max()!)
                        if !previous.isEmpty { moveDelta = max(moveDelta, zip(pixels, previous).map { abs($0-$1) }.max()!) }
                        previous = pixels
                    }
                    caseCount += 1
                }
            }
        }
        // A spot facing the plane along -Z must work; projection onto XY would
        // discard this valid direction. A rectangular basis cannot warp cones.
        let model = matrix(300, 90, angle: 0.4)
        let spot = Capture.SpotLight(position: SIMD3(20, 30, 100), direction: SIMD3(0, 0, -1),
            color: SIMD3(repeating: 1), intensity: 3, radius: 500, innerConeCosine: 0.95, outerConeCosine: 0.7)
        let spotPayload = Capture.packLights(pointLights: [], spotLights: [spot], ambient: ambient, layerModelMatrix: model)!
        let spotPixels = render(device, queue, pipeline: pipeline, lit: lit, payload: spotPayload)
        for y in 0..<height { for x in 0..<width {
            let w = model * SIMD4<Float>((Float(x)+0.5)/Float(width)-0.5, 0.5-(Float(y)+0.5)/Float(height), 0, 1)
            let delta = spot.position - SIMD3(w.x,w.y,w.z)
            let distance = simd_length(delta)
            let cone = min(1, max(0, (simd_dot(-delta/distance,spot.direction)-spot.outerConeCosine)/(spot.innerConeCosine-spot.outerConeCosine)))
            let amount = pow(max(0, 1-distance/spot.radius),2) * max(0,delta.z/distance) * cone * spot.intensity
            maxError = max(maxError,abs(spotPixels[(y*width+x)*4]-albedo.x*(ambient.x+amount)))
        }}
        let zero = Capture.packLights(pointLights: [], spotLights: [], ambient: ambient, layerModelMatrix: model)!
        let zeroPixels = render(device, queue, pipeline: pipeline, lit: lit, payload: zero)
        let restored = render(device, queue, pipeline: pipeline, lit: lit, payload: spotPayload)
        let restorationError = zip(spotPixels,restored).map { abs($0-$1) }.max()!
        let unlit = render(device, queue, pipeline: pipeline, lit: lit, payload: nil)
        let unlitAgain = render(device, queue, pipeline: pipeline, lit: lit, payload: nil)
        precondition(unlit == unlitAgain)
        precondition(maxError < 0.002 && flatError == 0 && moveDelta > 0.03 && restorationError == 0)
        precondition(zeroPixels[0] < restored.max()! && abs(unlit[0]-albedo.x) < 0.001)
        precondition(Capture.packLights(pointLights: [], spotLights: [], ambient: ambient,
            layerModelMatrix: simd_float4x4()) == nil)
        let result: [String: Any] = ["rectangleRotationNormalCases": caseCount, "maxOracleError": maxError,
            "flatNormalError": flatError, "verticalMoveDelta": moveDelta, "nextFrameRestoreError": restorationError,
            "spotAlongNegativeZ": true, "plainUnlitUnchanged": true,
            "gpuCompletion": true, "terminalSourceOver": true]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
