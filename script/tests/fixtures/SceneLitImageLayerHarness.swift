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
        normalInput: SceneBaseMaterialLitCapturePayload.TextureInput? = nil
    ) -> [Float] {
        let command = queue.makeCommandBuffer()!
        let terminal = encode(device, command, pipeline: pipeline, lit: lit,
            payload: payload, normal: normal, normalInput: normalInput)
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed && command.error == nil)
        return pixels(terminal)
    }

    static func encode(
        _ device: MTLDevice, _ command: MTLCommandBuffer,
        pipeline: SceneImageLayerPipeline, lit: SceneLitImageLayerPipeline,
        payload: SceneLitImageLayerLightPayload?, normal: MTLTexture? = nil,
        normalInput: SceneBaseMaterialLitCapturePayload.TextureInput? = nil
    ) -> MTLTexture {
        let source = texture(device, fill: albedo)
        let captured = texture(device)
        let terminal = texture(device)
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
        return terminal
    }

    static func pixels(_ terminal: MTLTexture) -> [Float] {
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
                f = f0+(1-f0)*pow(1-max(0,min(1,simd_dot(v,h))),5)
                // Exact zero has no finite raster specular sample. Its
                // independently defined Fresnel/diffuse split still applies.
                if roughness > 0 {
                    let a = max(0.01,roughness*roughness), a2 = a*a
                    let d = a2 / (Double.pi*pow(1+(a2-1)*nh*nh,2))
                    func lambda(_ cosine: Double) -> Double {
                        (sqrt(1+a2*(1-cosine*cosine)/(cosine*cosine))-1)/2
                    }
                    let g = 1/(1+lambda(nl)+lambda(nv))
                    spec = Double.pi*d*g*f/(4*nl*nv)*nl
                }
            }
            result[c] = Float(((1-metallic)*(1-f)*base*nl+spec)*Double(source.w))
        }
        return result
    }

    // Pure CPU entry below calls the actual packer without creating a Metal
    // device. Chosen axis and 3-4-5 inputs have independent normalized answers.
    static func packingChecks() -> [String: Any] {
        typealias Capture = SceneBaseMaterialLitCapturePayload
        typealias Directional = Capture.DirectionalLight
        func directional(_ vector: SIMD3<Float>, _ intensity: Float = 2,
                         color: SIMD3<Float> = SIMD3(1, 0.5, -1)) -> Directional {
            .init(directionTowardLight: vector, color: color, intensity: intensity)
        }
        let valid = directional(SIMD3(3, 4, 0))
        let point = Capture.PointLight(position: SIMD3(1, 2, 3),
            color: SIMD3(repeating: 1), intensity: 1, radius: 100)
        let spot = Capture.SpotLight(position: SIMD3(1, 2, 3), direction: SIMD3(0, 0, -1),
            color: SIMD3(repeating: 1), intensity: 1, radius: 100,
            innerConeCosine: 0.9, outerConeCosine: 0.7)
        func pack(_ directions: [Directional], v1: Bool = true,
                  points: [Capture.PointLight] = [], spots: [Capture.SpotLight] = [])
            -> SceneLitImageLayerLightPayload? {
            Capture.packLights(pointLights: points, spotLights: spots, ambient: .zero,
                material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0),
                layerModelMatrix: matrix_identity_float4x4,
                normalModelMatrix: matrix_identity_float4x4,
                directionalLights: directions, usesLightingV1: v1)
        }
        let omitted = Capture.packLights(pointLights: [point], spotLights: [], ambient: .zero,
            material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0),
            layerModelMatrix: matrix_identity_float4x4, normalModelMatrix: matrix_identity_float4x4)!
        let legacy = pack([directional(.zero)], v1: false, points: [point])!
        let one = pack([valid])!
        let tiny = pack([directional(SIMD3(0, 0, Float.leastNonzeroMagnitude))])!
        let huge = pack([directional(SIMD3(0, Float.greatestFiniteMagnitude, 0))])!
        let zeroEnergy = pack([directional(SIMD3(0, 0, 1), 0)])!
        let mixed = pack([valid, valid], points: [point, point], spots: [spot])!
        let full = pack((1...5).map { directional(SIMD3(0, 0, 1), Float($0)) })!
        let exponents: [Float] = [0, 0.54, 1, 5]
        let spots = exponents.map { exponent -> Capture.SpotLight in
            var value = spot; value.falloffExponent = exponent; return value
        }
        let fourSpots = pack([], spots: spots)!
        let truncatedSpots = pack([], points: [point, point], spots: spots)!
        let legacySpot = pack([], v1: false, spots: [spots[1]])!
        let invalid = [directional(.zero), directional(SIMD3(.nan, 0, 1)),
            directional(SIMD3(0, .infinity, 1)), directional(SIMD3(0, 0, 1), -1),
            directional(SIMD3(0, 0, 1), .nan),
            directional(SIMD3(0, 0, 1), color: SIMD3(.infinity, 1, 1))]
        let checks: [String: Bool] = [
            "legacyDefaultRetained": omitted.lightCounts == SIMD4(1, 0, 0, 0)
                && legacy.lightCounts == omitted.lightCounts
                && legacy.pointPositionRadius0 == omitted.pointPositionRadius0
                && legacy.pointColor0 == omitted.pointColor0,
            "legacyIgnoresDirectionalRequest": legacy.directionalDirectionIntensity0 == .zero
                && legacy.directionalColor0 == .zero,
            "directionAndColorHaveIndependentUnits": one.lightCounts == SIMD4(0, 0, 1, 1)
                && abs(one.directionalDirectionIntensity0.x - 0.6) < 1e-6
                && abs(one.directionalDirectionIntensity0.y - 0.8) < 1e-6
                && one.directionalDirectionIntensity0.z == 0
                && one.directionalDirectionIntensity0.w == 2
                && one.directionalColor0 == SIMD4(1, 0.5, 0, 0),
            "finiteTinyDirectionIsNotDiscarded": tiny.directionalDirectionIntensity0 == SIMD4(0, 0, 1, 2),
            "finiteHugeDirectionDoesNotOverflow": huge.directionalDirectionIntensity0 == SIMD4(0, 1, 0, 2),
            "zeroEnergyPreservesSlot": zeroEnergy.lightCounts.z == 1
                && zeroEnergy.directionalDirectionIntensity0.w == 0,
            "invalidAdmittedDirectionRejected": invalid.allSatisfy { pack([$0]) == nil },
            "combinedCapacityPreservesExistingPriority": mixed.lightCounts == SIMD4(2, 1, 1, 1)
                && mixed.directionalDirectionIntensity1 == .zero,
            "directionalCapacityPreservesInputOrder": full.lightCounts == SIMD4(0, 0, 4, 1)
                && [full.directionalDirectionIntensity0.w, full.directionalDirectionIntensity1.w,
                    full.directionalDirectionIntensity2.w, full.directionalDirectionIntensity3.w] == [1, 2, 3, 4],
            "unusedDirectionalSlotsAreClear": one.directionalDirectionIntensity1 == .zero
                && one.directionalDirectionIntensity2 == .zero && one.directionalDirectionIntensity3 == .zero
                && one.directionalColor1 == .zero && one.directionalColor2 == .zero && one.directionalColor3 == .zero,
            "spotExponentDefaultsAndUnusedWordsStayTwo": mixed.spotFalloffExponents == SIMD4(repeating: 2)
                && one.spotFalloffExponents == SIMD4(repeating: 2),
            "fourSpotExponentsPreserveZeroAndOrder": fourSpots.spotFalloffExponents == SIMD4(0, 0.54, 1, 5),
            "combinedCapacityTruncatesSpotExponentWords": truncatedSpots.lightCounts == SIMD4(2, 2, 0, 1)
                && truncatedSpots.spotFalloffExponents == SIMD4(0, 0.54, 2, 2),
            "legacySpotCarriesItsAuthoredExponent": legacySpot.spotFalloffExponents == SIMD4(0.54, 2, 2, 2),
        ]
        typealias Payload = SceneLitImageLayerLightPayload
        return ["checks": checks, "layout": [
            MemoryLayout<Payload>.offset(of: \.lightCounts)!,
            MemoryLayout<Payload>.offset(of: \.sceneViewProjection)!,
            MemoryLayout<Payload>.offset(of: \.reflection)!,
            MemoryLayout<Payload>.offset(of: \.directionalDirectionIntensity0)!,
            MemoryLayout<Payload>.offset(of: \.directionalColor0)!,
            MemoryLayout<Payload>.offset(of: \.pointFalloffExponents)!,
            MemoryLayout<Payload>.offset(of: \.spotFalloffExponents)!, MemoryLayout<Payload>.stride]]
    }

    static func main() throws {
#if SCENE_LIT_PACK_ONLY
        print(String(data: try JSONSerialization.data(withJSONObject: packingChecks(),
            options: [.sortedKeys]), encoding: .utf8)!)
#else
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
                        // Official 2D lit images: planar falloff (Z excluded)
                        // and point energy scale 1.85 (own-fixture, 2026-10-06).
                        let distance = simd_length(SIMD2(delta.x, delta.y))
                        let amount = pow(max(0, 1-distance/point.radius), 2) * point.intensity * 1.85
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
        // Mixed-count overflow truncates in authored order (points first),
        // keeping the layer lit instead of the previous whole-payload reject.
        func overflowPoint(_ index: Int) -> Capture.PointLight {
            .init(position: SIMD3(Float(index), 0, 50), color: SIMD3(repeating: 1),
                  intensity: 1, radius: Float(100 + index))
        }
        let mixed = Capture.packLights(pointLights: (0..<3).map(overflowPoint),
            spotLights: [spot, spot, spot], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0),
            layerModelMatrix: model, normalModelMatrix: matrix_identity_float4x4)!
        let pointsOnly = Capture.packLights(pointLights: (0..<5).map(overflowPoint),
            spotLights: [], ambient: ambient, material: SIMD2(0.5,0.5), view: SIMD4(0,0,1,0),
            layerModelMatrix: model, normalModelMatrix: matrix_identity_float4x4)!
        var mixedTruncates = mixed.lightCounts.x == 3 && mixed.lightCounts.y == 1
        mixedTruncates = mixedTruncates && mixed.spotColorIntensity1.w == 0
        var pointsTruncate = pointsOnly.lightCounts == SIMD4<Float>(4, 0, 0, 0)
        // Authored order survives: radii 100..103 occupy the four slots.
        pointsTruncate = pointsTruncate && pointsOnly.pointPositionRadius0.w == 100
            && pointsOnly.pointPositionRadius1.w == 101
            && pointsOnly.pointPositionRadius2.w == 102
            && pointsOnly.pointPositionRadius3.w == 103
        precondition(mixedTruncates && pointsTruncate)
        // One command buffer alternates families on the same actual pipeline.
        // A tiny world card makes the axis-aligned head-on answer constant to
        // far below half-storage tolerance without copying a general BRDF.
        let tinyCard = simd_float4x4(diagonal: SIMD4<Float>(0.001, 0.001, 1, 1))
        func familyPayload(z: Float? = nil, direction: SIMD3<Float>? = nil,
                           modern: Bool = true, falloffExponent: Float = 2) -> SceneLitImageLayerLightPayload {
            Capture.packLights(pointLights: z.map { [Capture.PointLight(
                position: SIMD3(0, 0, $0), color: SIMD3(repeating: 1), intensity: 1, radius: 100,
                falloffExponent: falloffExponent)] } ?? [],
                spotLights: [], ambient: .zero, material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0),
                layerModelMatrix: tinyCard, normalModelMatrix: matrix_identity_float4x4,
                directionalLights: direction.map { [Capture.DirectionalLight(
                    directionTowardLight: $0, color: SIMD3(repeating: 1), intensity: 1)] } ?? [],
                usesLightingV1: modern)!
        }
        let familyCases: [(String, SceneLitImageLayerLightPayload, MTLTexture?)] = [
            ("legacy-near", familyPayload(z: 25, modern: false), nil),
            ("modern-near", familyPayload(z: 25), nil),
            ("direction-forward", familyPayload(direction: SIMD3(0, 0, 1)), nil),
            ("legacy-far", familyPayload(z: 50, modern: false), nil),
            ("modern-far", familyPayload(z: 50), nil),
            ("direction-backward", familyPayload(direction: SIMD3(0, 0, -1)), nil),
            ("direction-flat-normal", familyPayload(direction: SIMD3(0, 0, 1)), flat),
            ("direction-tilted-normal", familyPayload(direction: SIMD3(0, 0, 1)), tilted),
            ("legacy-repeat", familyPayload(z: 25, modern: false, falloffExponent: 0.1), nil),
            ("modern-gentle", familyPayload(z: 50, falloffExponent: 0.1), nil),
            ("modern-steep", familyPayload(z: 50, falloffExponent: 5), nil),
            ("modern-zero", familyPayload(z: 50, falloffExponent: 0), nil),
            ("modern-zero-outside", familyPayload(z: 101, falloffExponent: 0), nil),
        ]
        func makeSpotPayload(z: Float, position: SIMD3<Float>? = nil, exponent: Float? = nil, intensity: Float = 1,
                         direction: SIMD3<Float> = SIMD3(0, 0, -1), modern: Bool = true)
            -> SceneLitImageLayerLightPayload {
            var light = Capture.SpotLight(position: position ?? SIMD3(0, 0, z), direction: direction,
                color: SIMD3(repeating: 1), intensity: intensity, radius: 100,
                innerConeCosine: 0.9, outerConeCosine: 0.7)
            if let exponent { light.falloffExponent = exponent }
            return Capture.packLights(pointLights: [], spotLights: [light], ambient: .zero,
                material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0), layerModelMatrix: tinyCard,
                normalModelMatrix: matrix_identity_float4x4, usesLightingV1: modern)!
        }
        var spotCases: [(String, SceneLitImageLayerLightPayload, MTLTexture?)] = [
            ("spot-default", makeSpotPayload(z: 50), nil),
            ("spot-two", makeSpotPayload(z: 50, exponent: 2), nil),
            ("legacy-spot-default", makeSpotPayload(z: 50, modern: false), nil),
            ("legacy-spot-two", makeSpotPayload(z: 50, exponent: 2, modern: false), nil),
        ]
        // Each independent intensity is remaining^(authoredExponent-2).
        // Controls keep the already qualified squared radial path and BRDF.
        let radialInputs: [(String, Float, Float, Float)] = [
            ("25-gentle", 25, 0.54, 1.521985642037), ("25-zero", 25, 0, 1.777777777778),
            ("25-one", 25, 1, 1.333333333333),
            ("50-gentle", 50, 0.54, 2.751083636279), ("50-zero", 50, 0, 4), ("50-one", 50, 1, 2),
            ("75-gentle", 75, 0.54, 7.568461173805), ("75-zero", 75, 0, 16), ("75-one", 75, 1, 4),
        ]
        for (name, z, exponent, referenceIntensity) in radialInputs {
            spotCases.append(("spot-" + name, makeSpotPayload(z: z, exponent: exponent), nil))
            spotCases.append(("spot-" + name + "-reference",
                makeSpotPayload(z: z, exponent: 2, intensity: referenceIntensity), nil))
        }
        spotCases += [
            ("spot-cone-transition", makeSpotPayload(z: 50, exponent: 0.54, direction: SIMD3(0.6, 0, -0.8)), nil),
            ("spot-cone-transition-reference", makeSpotPayload(z: 50, exponent: 2,
                intensity: 2.751083636279, direction: SIMD3(0.6, 0, -0.8)), nil),
            ("spot-cone-outside-zero", makeSpotPayload(z: 50, exponent: 0, direction: SIMD3(0.8, 0, -0.6)), nil),
            ("spot-zero-edge", makeSpotPayload(z: 100, exponent: 0), nil),
            ("spot-zero-near-inside", makeSpotPayload(z: Float(100).nextDown, exponent: 0), nil),
            ("spot-zero-near-outside", makeSpotPayload(z: Float(100).nextUp, exponent: 0), nil),
            ("spot-zero-outside", makeSpotPayload(z: 125, exponent: 0), nil),
            ("spot-gentle-outside", makeSpotPayload(z: 125, exponent: 0.54), nil),
        ]
        let centerLocal = SIMD4<Float>((Float(width / 2) + 0.5) / Float(width) - 0.5,
            0.5 - (Float(height / 2) + 0.5) / Float(height), 0, 1)
        let centerWorld = tinyCard * centerLocal
        let receiver = SIMD3(centerWorld.x, centerWorld.y, centerWorld.z)
        // The light offset is an exact 3-4-5 vector at the sampled pixel.
        // Adjacent Float Z values fall strictly inside/outside radius 100.
        for (name, delta) in [("edge", SIMD3<Float>(60, 0, 80)),
                              ("inside", SIMD3<Float>(60, 0, Float(80).nextDown)),
                              ("outside", SIMD3<Float>(60, 0, Float(80).nextUp)),
                              ("control", SIMD3<Float>(30, 0, 40))] {
            spotCases.append(("spot-oblique-zero-" + name,
                makeSpotPayload(z: delta.z, position: receiver + delta, exponent: 0,
                    direction: -simd_normalize(delta)), nil))
        }
        func fourSpotPayload(reference: Bool) -> SceneLitImageLayerLightPayload {
            let slots: [(Float, Float, Float, SIMD3<Float>)] = [
                (25, 0, 1.777777777778, SIMD3(1, 0, 0)), (50, 1, 2, SIMD3(0, 1, 0)),
                (75, 0.54, 7.568461173805, SIMD3(0, 0, 1)), (50, 5, 0.125, SIMD3(repeating: 1)),
            ]
            return Capture.packLights(pointLights: [], spotLights: slots.map { z, exponent, intensity, color in
                Capture.SpotLight(position: SIMD3(0, 0, z), direction: SIMD3(0, 0, -1),
                    color: color, intensity: reference ? intensity : 1, radius: 100,
                    innerConeCosine: 0.9, outerConeCosine: 0.7, falloffExponent: reference ? 2 : exponent)
            }, ambient: .zero, material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0), layerModelMatrix: tinyCard,
                normalModelMatrix: matrix_identity_float4x4, usesLightingV1: true)!
        }
        spotCases += [("spot-four-slots", fourSpotPayload(reference: false), nil),
                      ("spot-four-slots-reference", fourSpotPayload(reference: true), nil)]
        let invalidPoint = Capture.packLights(pointLights: [.init(position: SIMD3(0, 0, 50),
            color: SIMD3(repeating: 1), intensity: 1, radius: 100, falloffExponent: .nan)],
            spotLights: [], ambient: .zero, material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0),
            layerModelMatrix: tinyCard, normalModelMatrix: matrix_identity_float4x4)!
        let invalidSpot = makeSpotPayload(z: 50, exponent: .infinity)
        let invalidInverse = Capture.packLights(pointLights: [], spotLights: [], ambient: .zero,
            material: SIMD2(0, 1), view: SIMD4(0, 0, 1, 0), layerModelMatrix: tinyCard,
            normalModelMatrix: simd_float4x4(diagonal: SIMD4(1, 1, 0, 1)))!
        var invalidProjection = spotCases[0].1, invalidReflection = spotCases[0].1
        invalidProjection.sceneViewProjection.columns.0.x = .infinity
        invalidReflection.reflection.x = .nan
        let rejectsInvalidFinalPayload = [invalidPoint, invalidSpot, invalidInverse, invalidProjection, invalidReflection]
            .allSatisfy { Capture(pipeline: lit, lights: $0, normal: .disabled) == nil }
        precondition(rejectsInvalidFinalPayload
            && Capture(pipeline: lit, lights: spotCases[0].1, normal: .disabled) != nil)
        let lightingCases = familyCases + spotCases
        let familyCommand = queue.makeCommandBuffer()!
        let familyTargets = lightingCases.map { row in
            encode(device, familyCommand, pipeline: pipeline, lit: lit, payload: row.1, normal: row.2)
        }
        familyCommand.commit()
        familyCommand.waitUntilCompleted()
        precondition(familyCommand.status == .completed && familyCommand.error == nil)
        let center = (height / 2 * width + width / 2) * 4
        let lightingPixels = zip(lightingCases, familyTargets).map { row, target -> [String: Any] in
            let rgba = pixels(target)
            return ["name": row.0, "rgba": Array(rgba[center..<(center + 4)])]
        }
        let result: [String: Any] = ["rectangleRotationNormalCases": caseCount, "maxOracleError": maxError,
            "flatNormalError": flatError, "verticalMoveDelta": moveDelta, "nextFrameRestoreError": restorationError,
            "spotAlongNegativeZ": true, "plainUnlitUnchanged": true,
            "gpuCompletion": true, "terminalSourceOver": true,
            "mixedOverflowTruncates": mixedTruncates, "pointsOverflowKeepsAuthoredOrder": pointsTruncate,
            "mixedFamilySingleCommandCompleted": true,
            "finalCaptureRejectsNonfinitePayload": rejectsInvalidFinalPayload,
            "lightingFamilyPixels": Array(lightingPixels.prefix(familyCases.count)),
            "spotRadialPixels": Array(lightingPixels.dropFirst(familyCases.count))]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
#endif
    }
}
