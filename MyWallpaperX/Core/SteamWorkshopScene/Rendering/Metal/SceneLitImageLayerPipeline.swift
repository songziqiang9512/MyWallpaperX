import Metal
import simd

/// Fragment `buffer(1)` payload for the lit base capture. Fixed four point
/// and four spot slots, zero-padded per type; the layout mirrors the MSL
/// struct `SceneLitImageLayerLightPayload` in SceneLitImageLayer.metal and
/// follows the static-model zero-padding pattern for the same shared launch
/// light snapshot (`SceneLightSnapshot`, authored order, maximum 4 total).
struct SceneLitImageLayerLightPayload {
    /// World xyz position and world radius. Color.w carries intensity.
    var pointPositionRadius0 = SIMD4<Float>.zero
    var pointPositionRadius1 = SIMD4<Float>.zero
    var pointPositionRadius2 = SIMD4<Float>.zero
    var pointPositionRadius3 = SIMD4<Float>.zero
    var pointColor0 = SIMD4<Float>.zero
    var pointColor1 = SIMD4<Float>.zero
    var pointColor2 = SIMD4<Float>.zero
    var pointColor3 = SIMD4<Float>.zero
    var spotPositionRadius0 = SIMD4<Float>.zero
    var spotPositionRadius1 = SIMD4<Float>.zero
    var spotPositionRadius2 = SIMD4<Float>.zero
    var spotPositionRadius3 = SIMD4<Float>.zero
    var spotDirectionCone0 = SIMD4<Float>.zero
    var spotDirectionCone1 = SIMD4<Float>.zero
    var spotDirectionCone2 = SIMD4<Float>.zero
    var spotDirectionCone3 = SIMD4<Float>.zero
    var spotColorIntensity0 = SIMD4<Float>.zero
    var spotColorIntensity1 = SIMD4<Float>.zero
    var spotColorIntensity2 = SIMD4<Float>.zero
    var spotColorIntensity3 = SIMD4<Float>.zero
    var spotOuterConeCosines = SIMD4<Float>.zero
    var ambientHasNormal = SIMD4<Float>.zero
    /// x/y are populated point/spot slots; the snapshot owns admission order.
    var lightCounts = SIMD4<Float>.zero
    var modelMatrix = matrix_identity_float4x4
    var normalBasis = matrix_identity_float4x4
    var normalFrame0 = SIMD4<Float>(0, 0, 1, 0)
    var normalFrame1 = SIMD4<Float>(0, 1, 0, 0)
    /// x = sampler mode; y = RGB UNORM / RG UNORM / RG SNORM.
    var normalSamplingEncoding = SIMD4<UInt32>.zero
    /// x/y = metallic/perceptual roughness; z = explicit builtin admission.
    var material = SIMD4<Float>.zero
    /// xyz = perspective eye (w=1) or orthographic toward-viewer (w=0).
    var view = SIMD4<Float>(0, 0, 1, 0)
    var mapFrame0 = SIMD4<Float>(0, 0, 1, 0)
    var mapFrame1 = SIMD4<Float>(0, 1, 0, 0)
    /// x = sampler; y = enabled component bits (metal/rough/emission).
    var mapSamplingComponents = SIMD4<UInt32>.zero
    var emission = SIMD4<Float>.zero
    var sceneViewProjection = matrix_identity_float4x4
    /// strength, project world distance, environment ready, direct enabled.
    var reflection = SIMD4<Float>(0, 4, 0, 1)
}

/// One claimed layer's lit base-capture request. Built by the frame
/// preflight only when the launch lighting profile enables the layer, the
/// lit pipeline resolved and the light packing succeeded; any failure keeps
/// the request nil so the executor takes the unlit `imagePipeline` capture.
struct SceneBaseMaterialLitCapturePayload {
    struct PointLight {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
    }

    struct SpotLight {
        let position: SIMD3<Float>
        let direction: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let radius: Float
        let innerConeCosine: Float
        let outerConeCosine: Float
    }

    enum TextureInput {
        enum Kind { case normal, materialMap }
        case disabled, unavailable, invalid, unsupported
        case ready(SceneTextureSlotBinding, encoding: UInt32)

        static func resolve(_ lookup: SceneFrameTextureLookupStatus?, kind: Kind = .normal) -> Self {
            switch lookup {
            case let .ready(resource): resolve(resource.publication.candidate, kind: kind)
            case .incomplete: .invalid
            case .absent, .pending, .unavailable, nil: .unavailable
            }
        }

        static func resolve(_ candidate: SceneTextureCandidate, kind: Kind = .normal) -> Self {
            guard let binding = SceneTextureSlotBinding(slotIndex: kind == .normal ? 1 : 2, candidate: candidate)
            else { return .invalid }
            guard candidate.materialProgramUVTransform() != nil,
                  candidate.sampling.isResolvedForMaterialProgram,
                  !candidate.sampling.usesClampBorderFallback else { return .unsupported }
            if kind == .materialMap && candidate.sampling.rawFlags == nil { return .unsupported }
            let encoding: UInt32
            switch binding.pixelFormat {
            case .rgba8Unorm, .bc1_rgba, .bc2_rgba, .bc3_rgba: encoding = 0
            case .rg8Unorm where kind == .normal: encoding = 1
            case .bc5_rgSnorm where kind == .normal: encoding = 2
            default: return .unsupported
            }
            return .ready(binding, encoding: encoding)
        }

        var status: String {
            switch self {
            case .disabled: "disabled"
            case .unavailable: "unavailable"
            case .invalid: "invalid"
            case .unsupported: "unsupported"
            case .ready: "ready"
            }
        }
    }

    private static let diagnosticLock = NSLock()
    private static var reportedTextureStates = Set<String>()
    private static func report(status: String, role: String) {
        guard status != "ready", status != "disabled" else { return }
        diagnosticLock.lock()
        defer { diagnosticLock.unlock() }
        guard reportedTextureStates.insert(role + ":" + status).inserted else { return }
        NSLog("MWX SCENE: schema=base-material-%@ status=%@ fallback=%@", role, status, role == "normal" ? "flat-lit" : "scalar-no-emission")
    }

    let pipeline: SceneLitImageLayerPipeline
    private(set) var lights: SceneLitImageLayerLightPayload
    let normal: TextureInput
    let materialMap: TextureInput
    private var environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)?
    private(set) var environmentTexture: MTLTexture?
    var requiresReflection: Bool { lights.reflection.x > 0 && normalTexture != nil }
    var hasDirectLighting: Bool { lights.reflection.w != 0 }
    var normalTexture: MTLTexture? {
        guard case let .ready(binding, _) = normal else { return nil }
        return binding.texture
    }

    var materialMapTexture: MTLTexture? {
        guard case let .ready(binding, _) = materialMap else { return nil }
        return binding.texture
    }

    init?(
        pipeline: SceneLitImageLayerPipeline,
        lights: SceneLitImageLayerLightPayload,
        normal: TextureInput,
        materialMap: TextureInput = .disabled,
        mapAllowedComponents: UInt32 = 0,
        mapRequiredComponents: UInt32 = 0,
        emission: SIMD4<Float>? = nil,
        environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)? = nil
    ) {
        guard lights.isFinite else { return nil }
        self.pipeline = pipeline
        self.normal = normal
        self.materialMap = materialMap
        self.environmentSource = environmentSource
        self.environmentTexture = nil
        var packed = lights
        packed.ambientHasNormal.w = 0
        if case let .ready(binding, encoding) = normal {
            packed.ambientHasNormal.w = 1
            let uv = binding.uvTransform
            packed.normalFrame0 = SIMD4(uv.origin.x, uv.origin.y, uv.xAxis.x, uv.xAxis.y)
            packed.normalFrame1 = SIMD4(uv.yAxis.x, uv.yAxis.y, 0, 0)
            packed.normalSamplingEncoding = SIMD4(binding.sampling.imageLayerUniformMode, encoding, 0, 0)
        }
        packed.mapSamplingComponents = .zero
        packed.emission = emission ?? .zero
        if case let .ready(binding, _) = materialMap {
            let header = ((binding.sampling.rawFlags ?? 0) >> 20) & 15
            let enabled = header & mapAllowedComponents & (emission == nil ? 7 : 15)
            let uv = binding.uvTransform
            packed.mapFrame0 = SIMD4(uv.origin.x, uv.origin.y, uv.xAxis.x, uv.xAxis.y)
            packed.mapFrame1 = SIMD4(uv.yAxis.x, uv.yAxis.y, 0, 0)
            packed.mapSamplingComponents = SIMD4(binding.sampling.imageLayerUniformMode, enabled, 0, 0)
            if mapRequiredComponents & ~header != 0 {
                Self.report(status: "component-unavailable", role: "map")
            }
        }
        self.lights = packed
        Self.report(status: normal.status, role: "normal")
        Self.report(status: materialMap.status, role: "map")
    }

    /// A bad normal is rejected independently of a legal capture target. The
    /// texture alias/device check belongs here, where the encode target exists.
    func validated(for target: MTLTexture) -> Self? {
        guard target.pixelFormat == pipeline.pixelFormat,
              pipeline.state.device.registryID == target.device.registryID else { return nil }
        func compatible(_ texture: MTLTexture?) -> Bool {
            guard let texture else { return true }
            return texture.device.registryID == target.device.registryID && texture !== target
        }
        let normalValid = compatible(normalTexture)
        let mapValid = compatible(materialMapTexture)
        if normalValid && mapValid { return self }
        var value = Self(pipeline: pipeline, lights: lights,
            normal: normalValid ? normal : .invalid,
            materialMap: mapValid ? materialMap : .invalid,
            mapAllowedComponents: lights.mapSamplingComponents.y,
            emission: lights.emission, environmentSource: environmentSource)
        value?.environmentTexture = environmentTexture
        return value
    }

    /// Called before creating a source render encoder. Prepared payloads keep
    /// immutable intent; this value is local to one actual encode operation.
    func resolvingEnvironment(for target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Self? {
        guard var value = validated(for: target) else { return nil }
        if value.requiresReflection, value.environmentTexture == nil {
            value.environmentTexture = value.environmentSource?(commandBuffer)?.publication.texture
        }
        value.environmentSource = nil
        if let texture = value.environmentTexture,
           value.requiresReflection, texture !== target,
           texture.device.registryID == target.device.registryID {
            value.lights.reflection.z = 1
        } else {
            value.environmentTexture = nil
            value.lights.reflection.z = 0
        }
        return value.hasDirectLighting || value.environmentTexture != nil ? value : nil
    }

    /// Position maps the unit quad into world space. Direction uses the authored
    /// world transform and card orientation, excluding intrinsic pixel extent.
    static func packLights(
        pointLights: [PointLight],
        spotLights: [SpotLight],
        ambient: SIMD3<Float>,
        material: SIMD2<Float>?,
        view: SIMD4<Float>,
        layerModelMatrix: simd_float4x4,
        normalModelMatrix: simd_float4x4
    ) -> SceneLitImageLayerLightPayload? {
        // Four is the physical shader ABI capacity, not another admission budget.
        // SceneLightSnapshot selects lights in authored order before this call.
        guard pointLights.count + spotLights.count <= 4,
              simd_determinant(layerModelMatrix).isFinite,
              abs(simd_determinant(layerModelMatrix)) > 1e-9,
              ambient.x >= 0, ambient.y >= 0, ambient.z >= 0 else { return nil }
        var payload = SceneLitImageLayerLightPayload()
        payload.material = material.map { SIMD4($0.x, $0.y, 1, 0) } ?? .zero
        payload.view = view
        payload.modelMatrix = layerModelMatrix
        payload.normalBasis = simd_transpose(simd_inverse(normalModelMatrix))
        payload.ambientHasNormal = SIMD4(ambient, 0)
        payload.lightCounts = SIMD4(Float(pointLights.count), Float(spotLights.count), 0, 0)
        var positions = [SIMD4<Float>](repeating: .zero, count: 4)
        var colors = positions
        for (index, light) in pointLights.enumerated() {
            guard light.intensity >= 0, light.radius > 0 else { return nil }
            positions[index] = SIMD4(light.position, light.radius)
            colors[index] = SIMD4(simd_max(light.color, .zero), light.intensity)
        }
        (payload.pointPositionRadius0, payload.pointPositionRadius1,
         payload.pointPositionRadius2, payload.pointPositionRadius3) =
            (positions[0], positions[1], positions[2], positions[3])
        (payload.pointColor0, payload.pointColor1,
         payload.pointColor2, payload.pointColor3) =
            (colors[0], colors[1], colors[2], colors[3])
        positions = [SIMD4<Float>](repeating: .zero, count: 4)
        colors = positions
        var directions = positions
        for (index, light) in spotLights.enumerated() {
            let length = simd_length(light.direction)
            guard light.intensity >= 0, light.radius > 0,
                  length.isFinite, length > 1e-6,
                  light.innerConeCosine >= light.outerConeCosine,
                  light.innerConeCosine <= 1, light.outerConeCosine >= -1
            else { return nil }
            positions[index] = SIMD4(light.position, light.radius)
            directions[index] = SIMD4(light.direction / length, light.innerConeCosine)
            colors[index] = SIMD4(simd_max(light.color, .zero), light.intensity)
            payload.spotOuterConeCosines[index] = light.outerConeCosine
        }
        (payload.spotPositionRadius0, payload.spotPositionRadius1,
         payload.spotPositionRadius2, payload.spotPositionRadius3) =
            (positions[0], positions[1], positions[2], positions[3])
        (payload.spotDirectionCone0, payload.spotDirectionCone1,
         payload.spotDirectionCone2, payload.spotDirectionCone3) =
            (directions[0], directions[1], directions[2], directions[3])
        (payload.spotColorIntensity0, payload.spotColorIntensity1,
         payload.spotColorIntensity2, payload.spotColorIntensity3) =
            (colors[0], colors[1], colors[2], colors[3])
        return payload.isFinite ? payload : nil
    }

}

private func sceneLitIsFinite(_ value: SIMD4<Float>) -> Bool {
    value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
}

private extension SceneLitImageLayerLightPayload {
    var isFinite: Bool {
        [
            pointPositionRadius0, pointPositionRadius1,
            pointPositionRadius2, pointPositionRadius3,
            pointColor0, pointColor1, pointColor2, pointColor3,
            spotPositionRadius0, spotPositionRadius1,
            spotPositionRadius2, spotPositionRadius3,
            spotDirectionCone0, spotDirectionCone1,
            spotDirectionCone2, spotDirectionCone3,
            spotColorIntensity0, spotColorIntensity1,
            spotColorIntensity2, spotColorIntensity3,
            spotOuterConeCosines, ambientHasNormal, lightCounts,
            modelMatrix.columns.0, modelMatrix.columns.1,
            modelMatrix.columns.2, modelMatrix.columns.3,
            normalBasis.columns.0, normalBasis.columns.1,
            normalBasis.columns.2, normalBasis.columns.3, material, view,
            mapFrame0, mapFrame1, emission, reflection,
            sceneViewProjection.columns.0, sceneViewProjection.columns.1,
            sceneViewProjection.columns.2, sceneViewProjection.columns.3,
        ].allSatisfy(sceneLitIsFinite)
    }
}

/// Lit-only base-capture pipeline. Single PSO, no blending: the base capture
/// is a clear-target overwrite (SceneGraphResourcePassEncoder). Construction
/// fails soft (nil) when the default library or either function is missing;
/// the layer then keeps the unlit `imagePipeline` capture for that frame.
final class SceneLitImageLayerPipeline {
    let pixelFormat: MTLPixelFormat
    let state: MTLRenderPipelineState

    init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        library injectedLibrary: MTLLibrary? = nil
    ) {
        guard let library = injectedLibrary ?? device.makeDefaultLibrary(),
              let vertFn = library.makeFunction(name: "sceneImageLayerVert"),
              let fragFn = library.makeFunction(
                  name: "sceneLitImageLayerFrag"
              ) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertFn
        descriptor.fragmentFunction = fragFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = false
        guard let state = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else { return nil }
        self.state = state
        self.pixelFormat = pixelFormat
    }

    func bind(encoder: MTLRenderCommandEncoder) {
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        encoder.setRenderPipelineState(state)
        SceneImageLayerPipeline.bindQuad(encoder: encoder)
    }

    func drawLayer(
        texture: MTLTexture,
        normalTexture: MTLTexture?,
        materialMapTexture: MTLTexture? = nil,
        environmentTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        litPayload: SceneLitImageLayerLightPayload,
        encoder: MTLRenderCommandEncoder
    ) {
        var mvpCopy = mvp
        encoder.setVertexBytes(
            &mvpCopy,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        var uniformsCopy = uniforms
        encoder.setFragmentBytes(
            &uniformsCopy,
            length: MemoryLayout<SceneLayerFragmentUniforms>.size,
            index: 0
        )
        var lightsCopy = litPayload
        encoder.setFragmentBytes(
            &lightsCopy,
            length: MemoryLayout<SceneLitImageLayerLightPayload>.size,
            index: 1
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(normalTexture ?? texture, index: 1)
        encoder.setFragmentTexture(materialMapTexture ?? texture, index: 2)
        encoder.setFragmentTexture(environmentTexture ?? texture, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
    }
}
