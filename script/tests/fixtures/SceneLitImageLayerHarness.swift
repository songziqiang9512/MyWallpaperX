import Foundation
import Metal
import simd

#if !SCENE_AUTHORED_NORMAL
@main
#endif
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

    static func candidate(_ texture: MTLTexture) -> SceneTextureCandidate {
        SceneTextureCandidate(texture: texture, identity: .builtIn(name: "self-authored"),
            generation: .immutable(revision: 1), purpose: .normal, content: .data,
            physicalSize: CGSize(width: texture.width, height: texture.height),
            mappedSize: CGSize(width: texture.width, height: texture.height),
            uvTransform: .identity, sampling: .directImageFallback, authoredFormat: nil)
    }

    static func normalTexture(_ device: MTLDevice, x: Int8) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bc5_rgSnorm,
            width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        let result = device.makeTexture(descriptor: descriptor)!
        let bytes: [UInt8] = [UInt8(bitPattern: x), UInt8(bitPattern: x), 0,0,0,0,0,0,
                             0,0,0,0,0,0,0,0]
        bytes.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0,0,4,4), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: 16) }
        return result
    }

    static func render(
        _ device: MTLDevice, _ queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline, lit: SceneLitImageLayerPipeline,
        payload: SceneLitImageLayerLightPayload?, normal: MTLTexture? = nil,
        normalInput: SceneBaseMaterialLitCapturePayload.NormalInput? = nil
    ) -> [Float] {
        let source = texture(device, fill: albedo)
        let captured = texture(device)
        let terminal = texture(device)
        let command = queue.makeCommandBuffer()!
        let lighting = payload.flatMap { SceneBaseMaterialLitCapturePayload(pipeline: lit, lights: $0, normal: normalInput ?? normal.map { .resolve(candidate($0)) } ?? .disabled) }
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

    // Independent double oracle: explicit correlated masking G from lambda,
    // separate GGX D/F and the original lamp-unit pi conversion.
    static func materialResponse(normal: SIMD3<Float>, light: SIMD3<Float>,
        view: SIMD3<Float> = SIMD3(0,0,1), source: SIMD4<Float> = albedo,
        metallic: Double = 0.5, roughness: Double = 0.5) -> SIMD3<Float> {
        if simd_length(light) == 0 { return .zero }
        let n = simd_normalize(SIMD3<Double>(normal)), l = simd_normalize(SIMD3<Double>(light))
        let v = simd_length(view) > 0 ? simd_normalize(SIMD3<Double>(view)) : .zero
        let nl = max(0,simd_dot(n,l)), nv = simd_dot(n,v)
        var result = SIMD3<Float>.zero
        for c in 0..<3 {
            let base = source.w > 0 ? Double(source[c]/source.w) : 0
            let f0 = 0.04*(1-metallic)+min(1,max(0,base))*metallic
            var f = f0, spec = 0.0
            if nl > 0 && nv > 0 {
                let h = simd_normalize(l+v), nh = max(0,simd_dot(n,h))
                let a = max(0.01,roughness*roughness), a2 = a*a
                let d = a2 / (Double.pi*pow(1+(a2-1)*nh*nh,2))
                func lambda(_ cosine: Double) -> Double {
                    (sqrt(1+a2*(1-cosine*cosine)/(cosine*cosine))-1)/2
                }
                let g = 1/(1+lambda(nl)+lambda(nv))
                f = f0+(1-f0)*pow(1-max(0,min(1,simd_dot(v,h))),5)
                spec = Double.pi*d*g*f/(4*nl*nv)*nl
            }
            result[c] = Float(((1-metallic)*(1-f)*base*nl+spec)*Double(source.w))
        }
        return result
    }

    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = SceneImageLayerPipeline(device: device, pixelFormat: .rgba16Float, library: library)!
        let lit = SceneLitImageLayerPipeline(device: device, pixelFormat: .rgba16Float, library: library)!
        let flat = normalTexture(device, x: 0)
        let tilted = normalTexture(device, x: 127)
        let ambient = SIMD3<Float>(repeating: 0.03)
        typealias Capture = SceneBaseMaterialLitCapturePayload
        var caseCount = 0
        var maxError: Float = 0
        var flatError: Float = 0
        var moveDelta: Float = 0
        var previous: [Float] = []
        for (model, normalModel) in [(matrix(200, 100), matrix(1, 1)),
            (matrix(80, 320), matrix(1, 1)),
            (matrix(200, 100, angle: .pi/2), matrix(1, 1, angle: .pi/2))] {
            for position in [SIMD3<Float>(20, 75, 80), SIMD3<Float>(20, -95, 80)] {
                for useTilted in [false, true] {
                    let point = Capture.PointLight(position: position, color: SIMD3(1, 0.7, 0.4), intensity: 2, radius: 500)
                    let payload = Capture.packLights(pointLights: [point], spotLights: [], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0), layerModelMatrix: model, normalModelMatrix: normalModel)!
                    let pixels = render(device, queue, pipeline: pipeline, lit: lit, payload: payload, normal: useTilted ? tilted : nil)
                    let tangentNormal = useTilted ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
                    let n4 = simd_transpose(simd_inverse(normalModel)) * SIMD4(tangentNormal, 0)
                    let normal = simd_normalize(SIMD3(n4.x,n4.y,n4.z))
                    for y in 0..<height { for x in 0..<width {
                        let local = SIMD4<Float>((Float(x)+0.5)/Float(width)-0.5, 0.5-(Float(y)+0.5)/Float(height), 0, 1)
                        let w = model * local
                        let delta = position - SIMD3(w.x,w.y,w.z)
                        let distance = simd_length(delta)
                        let amount = pow(max(0, 1-distance/point.radius), 2) * point.intensity
                        let response = materialResponse(normal: normal, light: delta/distance)
                        for channel in 0..<3 {
                            maxError = max(maxError, abs(pixels[(y*width+x)*4+channel] - (albedo[channel]*ambient[channel] + point.color[channel]*amount*response[channel])))
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
        let spotPayload = Capture.packLights(pointLights: [], spotLights: [spot], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0), layerModelMatrix: model, normalModelMatrix: matrix(1, 1, angle: 0.4))!
        let spotPixels = render(device, queue, pipeline: pipeline, lit: lit, payload: spotPayload)
        for y in 0..<height { for x in 0..<width {
            let w = model * SIMD4<Float>((Float(x)+0.5)/Float(width)-0.5, 0.5-(Float(y)+0.5)/Float(height), 0, 1)
            let delta = spot.position - SIMD3(w.x,w.y,w.z)
            let distance = simd_length(delta)
            let cone = min(1, max(0, (simd_dot(-delta/distance,spot.direction)-spot.outerConeCosine)/(spot.innerConeCosine-spot.outerConeCosine)))
            let amount = pow(max(0, 1-distance/spot.radius),2) * cone * spot.intensity
            let response = materialResponse(normal: SIMD3(0,0,1), light: delta/distance)
            maxError = max(maxError,abs(spotPixels[(y*width+x)*4]-(albedo.x*ambient.x+response.x*amount)))
        }}
        let zero = Capture.packLights(pointLights: [], spotLights: [], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0), layerModelMatrix: model, normalModelMatrix: matrix(1, 1, angle: 0.4))!
        let zeroPixels = render(device, queue, pipeline: pipeline, lit: lit, payload: zero)
        let restored = render(device, queue, pipeline: pipeline, lit: lit, payload: spotPayload)
        let restorationError = zip(spotPixels,restored).map { abs($0-$1) }.max()!
        let unlit = render(device, queue, pipeline: pipeline, lit: lit, payload: nil)
        let unlitAgain = render(device, queue, pipeline: pipeline, lit: lit, payload: nil)
        precondition(unlit == unlitAgain)
        precondition(maxError < 0.002 && flatError == 0 && moveDelta > 0.03 && restorationError == 0)
        precondition(zeroPixels[0] < restored.max()! && abs(unlit[0]-albedo.x) < 0.001)
        precondition(Capture.packLights(pointLights: [], spotLights: [], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0),
            layerModelMatrix: simd_float4x4(), normalModelMatrix: matrix_identity_float4x4) == nil)
        let result: [String: Any] = ["rectangleRotationNormalCases": caseCount, "maxOracleError": maxError,
            "flatNormalError": flatError, "verticalMoveDelta": moveDelta, "nextFrameRestoreError": restorationError,
            "spotAlongNegativeZ": true, "plainUnlitUnchanged": true,
            "gpuCompletion": true, "terminalSourceOver": true]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
