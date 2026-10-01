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

    let pipeline: SceneLitImageLayerPipeline
    let lights: SceneLitImageLayerLightPayload
    let normalTexture: MTLTexture?

    init?(
        pipeline: SceneLitImageLayerPipeline,
        lights: SceneLitImageLayerLightPayload,
        normalTexture: MTLTexture?
    ) {
        guard lights.isFinite else { return nil }
        self.pipeline = pipeline
        var packed = lights
        packed.ambientHasNormal.w = normalTexture == nil ? 0 : 1
        self.lights = packed
        self.normalTexture = normalTexture
    }

    /// Graph allocation and composition-pool targets can differ in format;
    /// registry resources can belong to an obsolete device. Never bind either.
    func isCompatible(with target: MTLTexture) -> Bool {
        guard target.pixelFormat == pipeline.pixelFormat,
              pipeline.state.device.registryID == target.device.registryID else { return false }
        guard let normal = normalTexture else { return true }
        return normal.device.registryID == target.device.registryID
            && normal.textureType == .type2D && normal.sampleCount == 1
            && normal.usage.contains(.shaderRead) && normal !== target
    }

    /// Preserve world distances and cone angles under rectangular, rotated,
    /// reflected or nonuniformly scaled layer geometry. The fragment transforms
    /// the unit quad into the same world space as the shared frame snapshot.
    static func packLights(
        pointLights: [PointLight],
        spotLights: [SpotLight],
        ambient: SIMD3<Float>,
        layerModelMatrix: simd_float4x4
    ) -> SceneLitImageLayerLightPayload? {
        // Four is the physical shader ABI capacity, not another admission budget.
        // SceneLightSnapshot selects lights in authored order before this call.
        guard pointLights.count + spotLights.count <= 4,
              simd_determinant(layerModelMatrix).isFinite,
              abs(simd_determinant(layerModelMatrix)) > 1e-9,
              ambient.x >= 0, ambient.y >= 0, ambient.z >= 0 else { return nil }
        var payload = SceneLitImageLayerLightPayload()
        payload.modelMatrix = layerModelMatrix
        payload.normalBasis = simd_transpose(simd_inverse(layerModelMatrix))
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
            normalBasis.columns.2, normalBasis.columns.3,
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
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
    }
}
