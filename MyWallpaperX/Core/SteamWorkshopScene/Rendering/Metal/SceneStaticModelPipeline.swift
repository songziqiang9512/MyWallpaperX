import Metal
import simd

struct SceneStaticModelMesh {
    fileprivate let vertexBuffer: MTLBuffer
    fileprivate let indexBuffer: MTLBuffer
    let boundsMinimum: SIMD3<Float>
    let boundsMaximum: SIMD3<Float>
    let indexCount: Int
    fileprivate let indexType: MTLIndexType
}

private struct SceneStaticModelShadowUniforms {
    var modelToLightClip: simd_float4x4
    var modelMatrix: simd_float4x4
    var worldToLight: simd_float4x4
    var positionRadius: SIMD4<Float>
    var projectionParameters: SIMD4<Float>
    var viewport: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
    var coverage: SIMD4<Float>
}

private struct SceneModelShadowUniforms {
    var transform: simd_float4x4 = matrix_identity_float4x4
    var positionRadius: SIMD4<Float> = .zero
    var parameters: SIMD4<Float> = .zero
    var identity: SIMD4<UInt32> = .zero

    init(_ shadow: SceneStaticModelShadow? = nil, lightIndex: Int = 0) {
        guard let shadow else { return }
        switch shadow.projection {
        case .directional(let value):
            transform = value.worldToClip
            parameters.z = value.depthBias
            identity = SIMD4(0, UInt32(lightIndex), 1, 0)
        case .spot(let value):
            transform = value.worldToLight
            positionRadius = SIMD4(value.position, value.radius)
            parameters = SIMD4(value.tanHalfAngle, value.outerCosine, value.depthBias, 0)
            identity = SIMD4(1, UInt32(lightIndex), 1, 0)
        case .point(let value):
            positionRadius = SIMD4(value.position, value.radius)
            parameters.z = value.depthBias
            identity = SIMD4(2, UInt32(lightIndex), 1, 0)
        }
    }
}

private struct SceneStaticModelUniforms {
    var modelMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
    var componentTextureFrame0: SIMD4<Float>
    var componentTextureFrame1: SIMD4<Float>
    var materialColorAndOpacity: SIMD4<Float>
    var emissiveColorAndBrightness: SIMD4<Float>
    var viewTintFrontAndExponent: SIMD4<Float>
    var viewTintBackAndEnabled: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var materialFlags: SIMD4<UInt32>
    var lightCounts: SIMD4<UInt32>
    var ambientColor: SIMD4<Float>
    var skylightColor: SIMD4<Float>
    var distanceFogColor: SIMD4<Float>
    var distanceFogRange: SIMD4<Float>
    var lightDirectionIntensity0: SIMD4<Float>
    var lightDirectionIntensity1: SIMD4<Float>
    var lightDirectionIntensity2: SIMD4<Float>
    var lightDirectionIntensity3: SIMD4<Float>
    var lightColor0: SIMD4<Float>
    var lightColor1: SIMD4<Float>
    var lightColor2: SIMD4<Float>
    var lightColor3: SIMD4<Float>
    var pointPositionRadius0: SIMD4<Float>
    var pointPositionRadius1: SIMD4<Float>
    var pointPositionRadius2: SIMD4<Float>
    var pointPositionRadius3: SIMD4<Float>
    var pointColorIntensity0: SIMD4<Float>
    var pointColorIntensity1: SIMD4<Float>
    var pointColorIntensity2: SIMD4<Float>
    var pointColorIntensity3: SIMD4<Float>
    var spotPositionRadius0: SIMD4<Float>
    var spotPositionRadius1: SIMD4<Float>
    var spotPositionRadius2: SIMD4<Float>
    var spotPositionRadius3: SIMD4<Float>
    var spotDirectionInnerCosine0: SIMD4<Float>
    var spotDirectionInnerCosine1: SIMD4<Float>
    var spotDirectionInnerCosine2: SIMD4<Float>
    var spotDirectionInnerCosine3: SIMD4<Float>
    var spotColorIntensity0: SIMD4<Float>
    var spotColorIntensity1: SIMD4<Float>
    var spotColorIntensity2: SIMD4<Float>
    var spotColorIntensity3: SIMD4<Float>
    var spotOuterCosines: SIMD4<Float>
    var shadow0: SceneModelShadowUniforms
    var shadow1: SceneModelShadowUniforms
    var shadow2: SceneModelShadowUniforms
    var shadow3: SceneModelShadowUniforms
    var surfaceMaterial: SIMD4<Float>
}

/// Fixed, bounded pipeline for decoded static-model triangles. It consumes the
/// caller's current encoder and projection; target lifetime and publication
/// stay with the renderer that owns that encoder.
struct SceneStaticModelPipeline {
    let state: MTLRenderPipelineState

    private let device: MTLDevice
    private let writingDepthState: MTLDepthStencilState
    private let nonwritingDepthState: MTLDepthStencilState
    private let disabledDepthState: MTLDepthStencilState
    private let samplerStates: SceneTextureSamplerStateSet
    private let shadowState: MTLRenderPipelineState?
    private let spotShadowState: MTLRenderPipelineState?
    private let pointShadowState: MTLRenderPipelineState?
    private let shadowDepthState: MTLDepthStencilState?

    init?(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) {
        guard Self.hasExpectedUniformABI,
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneStaticModelVertex"),
              let fragment = library.makeFunction(name: "sceneStaticModelFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Scene static model"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.depthAttachmentPixelFormat = depthPixelFormat

        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = colorPixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let writingDepthDescriptor = MTLDepthStencilDescriptor()
        writingDepthDescriptor.label = "Scene static model writing depth"
        writingDepthDescriptor.depthCompareFunction = .greaterEqual
        writingDepthDescriptor.isDepthWriteEnabled = true

        let nonwritingDepthDescriptor = MTLDepthStencilDescriptor()
        nonwritingDepthDescriptor.label = "Scene static model nonwriting depth"
        nonwritingDepthDescriptor.depthCompareFunction = .greaterEqual
        nonwritingDepthDescriptor.isDepthWriteEnabled = false

        // Metal validation (Xcode Debug runs) rejects `setDepthStencilState(nil)`
        // with "depthStencilState must not be nil"; a no-test, no-write state is
        // the supported way to leave the encoder without depth configuration.
        let disabledDepthDescriptor = MTLDepthStencilDescriptor()
        disabledDepthDescriptor.label = "Scene static model disabled depth"
        disabledDepthDescriptor.depthCompareFunction = .always
        disabledDepthDescriptor.isDepthWriteEnabled = false

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor),
              let writingDepthState = device.makeDepthStencilState(
                  descriptor: writingDepthDescriptor
              ),
              let nonwritingDepthState = device.makeDepthStencilState(
                  descriptor: nonwritingDepthDescriptor
              ),
              let disabledDepthState = device.makeDepthStencilState(
                  descriptor: disabledDepthDescriptor
              ),
              let samplerStates = SceneTextureSamplerStateSet(device: device) else {
            return nil
        }
        self.device = device
        self.state = state
        self.writingDepthState = writingDepthState
        self.nonwritingDepthState = nonwritingDepthState
        self.disabledDepthState = disabledDepthState
        self.samplerStates = samplerStates
        let shadowDescriptor = MTLRenderPipelineDescriptor()
        shadowDescriptor.label = "Scene directional model shadow"
        shadowDescriptor.vertexFunction = library.makeFunction(name: "sceneStaticModelShadowVertex")
        shadowDescriptor.fragmentFunction = library.makeFunction(name: "sceneStaticModelShadowFragment")
        shadowDescriptor.depthAttachmentPixelFormat = .depth32Float
        // Metal permits a nil fragment for depth-only pipelines. Each model
        // shadow requires its fragment for coverage and the chosen depth domain.
        if shadowDescriptor.vertexFunction != nil, shadowDescriptor.fragmentFunction != nil {
            shadowState = try? device.makeRenderPipelineState(descriptor: shadowDescriptor)
        } else {
            shadowState = nil
        }
        shadowDescriptor.label = "Scene spot model shadow"
        shadowDescriptor.vertexFunction = library.makeFunction(name: "sceneStaticModelSpotShadowVertex")
        shadowDescriptor.fragmentFunction = library.makeFunction(name: "sceneStaticModelSpotShadowFragment")
        if shadowDescriptor.vertexFunction != nil, shadowDescriptor.fragmentFunction != nil {
            spotShadowState = try? device.makeRenderPipelineState(descriptor: shadowDescriptor)
        } else {
            spotShadowState = nil
        }
        shadowDescriptor.label = "Scene point model shadow"
        shadowDescriptor.fragmentFunction = library.makeFunction(name: "sceneStaticModelPointShadowFragment")
        if shadowDescriptor.vertexFunction != nil, shadowDescriptor.fragmentFunction != nil {
            pointShadowState = try? device.makeRenderPipelineState(descriptor: shadowDescriptor)
        } else {
            pointShadowState = nil
        }
        let shadowDepth = MTLDepthStencilDescriptor()
        shadowDepth.depthCompareFunction = .lessEqual
        shadowDepth.isDepthWriteEnabled = true
        shadowDepthState = device.makeDepthStencilState(descriptor: shadowDepth)
    }

    /// Uploads immutable decoded geometry after validating the fixed Swift/MSL
    /// ABI and every index. Invalid geometry never reaches a GPU draw.
    func makeMesh(
        vertices: [SceneMdlStaticModel.Vertex],
        indices: [UInt32]
    ) -> SceneStaticModelMesh? {
        guard Self.hasExpectedVertexABI,
              !vertices.isEmpty,
              indices.count >= 3,
              indices.count.isMultiple(of: 3),
              indices.allSatisfy({ Int($0) < vertices.count }) else {
            return nil
        }

        let vertexLength = vertices.count
            * MemoryLayout<SceneMdlStaticModel.Vertex>.stride
        let usesWideIndices = indices.contains { $0 > UInt16.max }
        let indexData = usesWideIndices
            ? indices.withUnsafeBytes { Data($0) }
            : indices.map(UInt16.init).withUnsafeBytes { Data($0) }
        guard let vertexBuffer = vertices.withUnsafeBytes({ bytes in
                  device.makeSceneBuffer(
                      bytes: bytes.baseAddress!,
                      length: vertexLength,
                      options: []
                  )
              }),
              let indexBuffer = indexData.withUnsafeBytes({ bytes in
                  device.makeSceneBuffer(
                      bytes: bytes.baseAddress!,
                      length: bytes.count,
                      options: []
                  )
              }) else {
            return nil
        }
        vertexBuffer.label = "Scene static model vertices"
        indexBuffer.label = "Scene static model indices"
        return SceneStaticModelMesh(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            boundsMinimum: vertices.reduce(vertices[0].position) { simd_min($0, $1.position) },
            boundsMaximum: vertices.reduce(vertices[0].position) { simd_max($0, $1.position) },
            indexCount: indices.count,
            indexType: usesWideIndices ? .uint32 : .uint16
        )
    }

    /// Encodes into the caller's current render pass. A singular/non-finite
    /// transform is rejected before bindings or render state are mutated.
    @discardableResult
    func draw(
        mesh: SceneStaticModelMesh,
        texture: MTLTexture,
        colorTextureIsPremultiplied: Bool,
        emissiveMask: MTLTexture?,
        emissiveMaskTextureFrame: SceneTextureUVTransform?,
        emissiveMaskSampling: SceneTextureSampling?,
        modelMatrix: simd_float4x4,
        viewProjection: simd_float4x4,
        cameraPosition: SIMD3<Float>,
        textureFrame: SceneTextureUVTransform,
        sampling: SceneTextureSampling,
        layerAlpha: Float,
        material: SceneStaticModelMaterial,
        lighting: SceneLightSnapshot,
        writesDepth: Bool,
        shadows: [SceneStaticModelShadow] = [],
        frameEpoch: UInt64 = 0,
        commandBuffer: MTLCommandBuffer? = nil,
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        guard Self.isFinite(modelMatrix),
              Self.isFinite(viewProjection),
              Self.isValid(textureFrame),
              emissiveMask == nil || (
                  emissiveMaskTextureFrame.map(Self.isValid) == true
                      && emissiveMaskSampling?.isResolvedForMaterialProgram == true
                      && emissiveMaskSampling?.usesClampBorderFallback == false
              ),
              sampling.isResolvedForMaterialProgram,
              !sampling.usesClampBorderFallback,
              layerAlpha.isFinite,
              material.opacity.isFinite,
              material.emissiveBrightness.isFinite,
              material.brightness.isFinite,
              material.color.x.isFinite,
              material.color.y.isFinite,
              material.color.z.isFinite,
              material.emissiveColor.x.isFinite,
              material.emissiveColor.y.isFinite,
              material.emissiveColor.z.isFinite,
              cameraPosition.x.isFinite,
              cameraPosition.y.isFinite,
              cameraPosition.z.isFinite,
              Self.isValid(material.viewTint),
              let normalMatrix = Self.normalMatrix(for: modelMatrix) else {
            return false
        }
        // Official `lpoint` lights static models; `point` lights only 2D lit
        // images (own-fixture black-box, 2026-10-06). Shadow slots and the
        // encoded uniforms must index the same filtered array.
        let staticModelPoints = lighting.point.filter(\.illuminatesStaticModels)
        let acceptedShadows = shadows.compactMap { value -> (SceneStaticModelShadow, Int)? in
            guard value.frameEpoch == frameEpoch, value.commandBuffer === commandBuffer else { return nil }
            let index: Int?
            switch value.projection {
            case .directional:
                index = lighting.directional.firstIndex { $0.layerID == value.lightLayerID && $0.castsShadow }
            case .spot:
                index = lighting.spot.firstIndex { $0.layerID == value.lightLayerID && $0.castsShadow }
            case .point:
                index = staticModelPoints.firstIndex { $0.layerID == value.lightLayerID && $0.castsShadow }
            }
            return index.map { (value, $0) }
        }
        let maps = (0..<SceneLightSnapshot.maximumLightCount).map { index in
            acceptedShadows.indices.contains(index)
                ? SceneModelShadowUniforms(acceptedShadows[index].0, lightIndex: acceptedShadows[index].1)
                : SceneModelShadowUniforms()
        }
        let lightEnergyScale: Float = material.surfaceProfile == nil
            ? Self.staticModelLightEnergyScale : 1
        let lights = Self.encodedLights(lighting.directional, energyScale: lightEnergyScale)
        let points = Self.encodedPoints(staticModelPoints, energyScale: lightEnergyScale)
        let spots = Self.encodedSpots(lighting.spot, energyScale: lightEnergyScale)
        let brightness = material.usesHDRBrightness
            ? max(material.brightness, 0)
            : 1
        var uniforms = SceneStaticModelUniforms(
            modelMatrix: modelMatrix,
            viewProjectionMatrix: viewProjection,
            normalMatrix: normalMatrix,
            textureFrame0: textureFrame.uniform0,
            textureFrame1: textureFrame.uniform1,
            componentTextureFrame0: (
                emissiveMaskTextureFrame ?? textureFrame
            ).uniform0,
            componentTextureFrame1: (
                emissiveMaskTextureFrame ?? textureFrame
            ).uniform1,
            materialColorAndOpacity: SIMD4(
                max(material.color.x * brightness, 0),
                max(material.color.y * brightness, 0),
                max(material.color.z * brightness, 0),
                min(max(material.opacity * layerAlpha, 0), 1)
            ),
            emissiveColorAndBrightness: SIMD4(
                max(material.emissiveColor.x, 0),
                max(material.emissiveColor.y, 0),
                max(material.emissiveColor.z, 0),
                max(material.emissiveBrightness, 0)
            ),
            viewTintFrontAndExponent: SIMD4(
                material.viewTint?.front.x ?? 1,
                material.viewTint?.front.y ?? 1,
                material.viewTint?.front.z ?? 1,
                max(material.viewTint?.exponent ?? 1, 0.01)
            ),
            viewTintBackAndEnabled: SIMD4(
                material.viewTint?.back.x ?? 1,
                material.viewTint?.back.y ?? 1,
                material.viewTint?.back.z ?? 1,
                material.viewTint == nil ? 0 : 1
            ),
            cameraPosition: SIMD4(
                cameraPosition.x, cameraPosition.y, cameraPosition.z, 1
            ),
            materialFlags: SIMD4(
                (material.textureAlphaIsOpacity ? 1 : 0)
                    | (colorTextureIsPremultiplied ? 2 : 0),
                (emissiveMask == nil ? 0 : 1)
                    | (material.receivesLighting ? 0 : 2),
                0,
                material.textureAlphaIsTintMask ? 1 : 0
            ),
            lightCounts: SIMD4(
                UInt32(lighting.directional.count),
                UInt32(staticModelPoints.count),
                UInt32(lighting.spot.count),
                0
            ),
            ambientColor: SIMD4(lighting.ambient, 0),
            skylightColor: SIMD4(lighting.skylight, 0),
            distanceFogColor: lighting.distanceFogColor,
            distanceFogRange: lighting.distanceFogRange,
            lightDirectionIntensity0: lights[0].directionIntensity,
            lightDirectionIntensity1: lights[1].directionIntensity,
            lightDirectionIntensity2: lights[2].directionIntensity,
            lightDirectionIntensity3: lights[3].directionIntensity,
            lightColor0: lights[0].color,
            lightColor1: lights[1].color,
            lightColor2: lights[2].color,
            lightColor3: lights[3].color,
            pointPositionRadius0: points[0].positionRadius,
            pointPositionRadius1: points[1].positionRadius,
            pointPositionRadius2: points[2].positionRadius,
            pointPositionRadius3: points[3].positionRadius,
            pointColorIntensity0: points[0].colorIntensity,
            pointColorIntensity1: points[1].colorIntensity,
            pointColorIntensity2: points[2].colorIntensity,
            pointColorIntensity3: points[3].colorIntensity,
            spotPositionRadius0: spots[0].positionRadius,
            spotPositionRadius1: spots[1].positionRadius,
            spotPositionRadius2: spots[2].positionRadius,
            spotPositionRadius3: spots[3].positionRadius,
            spotDirectionInnerCosine0: spots[0].directionInnerCosine,
            spotDirectionInnerCosine1: spots[1].directionInnerCosine,
            spotDirectionInnerCosine2: spots[2].directionInnerCosine,
            spotDirectionInnerCosine3: spots[3].directionInnerCosine,
            spotColorIntensity0: spots[0].colorIntensity,
            spotColorIntensity1: spots[1].colorIntensity,
            spotColorIntensity2: spots[2].colorIntensity,
            spotColorIntensity3: spots[3].colorIntensity,
            spotOuterCosines: SIMD4(
                spots[0].outerCosine,
                spots[1].outerCosine,
                spots[2].outerCosine,
                spots[3].outerCosine
            ),
            shadow0: maps[0], shadow1: maps[1], shadow2: maps[2], shadow3: maps[3],
            surfaceMaterial: material.surfaceProfile.map {
                SIMD4($0.metallic, $0.roughness, 1, 0)
            } ?? .zero
        )

        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        encoder.setRenderPipelineState(state)
        encoder.setDepthStencilState(
            writesDepth ? writingDepthState : nonwritingDepthState
        )
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(material.cullMode)
        defer {
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(disabledDepthState)
        }
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<SceneStaticModelUniforms>.stride,
            index: 1
        )
        for index in 0..<SceneLightSnapshot.maximumLightCount {
            // Unused slots are never sampled. Reuse an already-pinned depth
            // binding when available; the no-shadow draw needs no allocation.
            let texture = acceptedShadows.indices.contains(index)
                ? acceptedShadows[index].0.texture : acceptedShadows.first?.0.texture
            encoder.setFragmentTexture(texture, index: 2 + index)
        }
        encoder.setFragmentTexture(texture, index: 0)
        // Keep the fixed Metal ABI bound even when this optional channel is
        // absent; the material flag prevents the placeholder from sampling.
        encoder.setFragmentTexture(emissiveMask ?? texture, index: 1)
        encoder.setFragmentSamplerState(
            samplerStates.state(for: sampling),
            index: 0
        )
        encoder.setFragmentSamplerState(
            samplerStates.state(for: emissiveMaskSampling ?? sampling),
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneStaticModelUniforms>.stride,
            index: 1
        )
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: mesh.indexType,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0
        )
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
        return true
    }

    /// Uses the same validated mesh and alpha contract as the color draw.
    /// The frame owner supplies the light target and closes this encoder before reads.
    func drawShadow(
        mesh: SceneStaticModelMesh, texture: MTLTexture,
        textureFrame: SceneTextureUVTransform, sampling: SceneTextureSampling,
        modelMatrix: simd_float4x4, projection: SceneStaticModelShadowProjection,
        face: Int, viewport: MTLViewport,
        layerAlpha: Float, material: SceneStaticModelMaterial,
        encoder: MTLRenderCommandEncoder,
        frontFacing: MTLWinding = .counterClockwise
    ) -> Bool {
        let pipeline: MTLRenderPipelineState?
        var clip = matrix_identity_float4x4, light = matrix_identity_float4x4
        var positionRadius = SIMD4<Float>.zero, parameters = SIMD4<Float>.zero
        switch projection {
        case .directional(let value):
            pipeline = shadowState
            clip = value.worldToClip * modelMatrix
        case .spot(let value):
            pipeline = spotShadowState
            light = value.worldToLight
            positionRadius = SIMD4(value.position, value.radius)
            parameters.x = value.tanHalfAngle
        case .point(let value):
            pipeline = pointShadowState
            light = ScenePointShadowProjection.worldToFaces[face]
            positionRadius = SIMD4(value.position, value.radius)
            parameters.x = 1
        }
        guard let pipeline, let shadowDepthState,
              Self.isFinite(modelMatrix), Self.isFinite(clip),
              Self.isValid(textureFrame), sampling.isResolvedForMaterialProgram,
              !sampling.usesClampBorderFallback, layerAlpha.isFinite,
              material.opacity.isFinite, texture.device === device else { return false }
        var uniforms = SceneStaticModelShadowUniforms(
            modelToLightClip: clip, modelMatrix: modelMatrix, worldToLight: light,
            positionRadius: positionRadius, projectionParameters: parameters,
            viewport: SIMD4(Float(viewport.originX), Float(viewport.originY), Float(viewport.width), Float(viewport.height)),
            textureFrame0: textureFrame.uniform0, textureFrame1: textureFrame.uniform1,
            coverage: SIMD4(min(max(material.opacity * layerAlpha, 0), 1),
                            material.textureAlphaIsOpacity ? 1 : 0, 0, 0))
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(shadowDepthState)
        encoder.setFrontFacing(frontFacing)
        encoder.setCullMode(material.cullMode)
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneStaticModelShadowUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneStaticModelShadowUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerStates.state(for: sampling), index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
            indexType: mesh.indexType, indexBuffer: mesh.indexBuffer, indexBufferOffset: 0)
        ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
        return true
    }

    static func normalMatrix(
        for modelMatrix: simd_float4x4
    ) -> simd_float3x3? {
        guard isFinite(modelMatrix) else { return nil }
        // Absolute determinant thresholds reject small, nonsingular authored
        // models (uniform scale 0.001 has determinant 1e-9). Compute in Double
        // so Float-scale products cannot underflow, then retain direction only:
        // the vertex shader normalizes the transformed normal independently.
        let linear = simd_double3x3(columns: (
            SIMD3<Double>(Double(modelMatrix.columns.0.x), Double(modelMatrix.columns.0.y), Double(modelMatrix.columns.0.z)),
            SIMD3<Double>(Double(modelMatrix.columns.1.x), Double(modelMatrix.columns.1.y), Double(modelMatrix.columns.1.z)),
            SIMD3<Double>(Double(modelMatrix.columns.2.x), Double(modelMatrix.columns.2.y), Double(modelMatrix.columns.2.z))
        ))
        let determinant = simd_determinant(linear)
        guard determinant.isFinite, determinant != 0 else { return nil }
        let inverseTranspose = simd_transpose(simd_inverse(linear))
        let magnitude = max(
            simd_reduce_max(abs(inverseTranspose.columns.0)),
            simd_reduce_max(abs(inverseTranspose.columns.1)),
            simd_reduce_max(abs(inverseTranspose.columns.2))
        )
        guard magnitude.isFinite, magnitude > 0 else { return nil }
        let result = simd_float3x3(columns: (
            SIMD3<Float>(inverseTranspose.columns.0 / magnitude),
            SIMD3<Float>(inverseTranspose.columns.1 / magnitude),
            SIMD3<Float>(inverseTranspose.columns.2 / magnitude)
        ))
        return isFinite(result) ? result : nil
    }

    private static func isValid(_ viewTint: SceneStaticModelViewTint?) -> Bool {
        guard let viewTint else { return true }
        return viewTint.front.x.isFinite && viewTint.front.y.isFinite
            && viewTint.front.z.isFinite && viewTint.back.x.isFinite
            && viewTint.back.y.isFinite && viewTint.back.z.isFinite
            && viewTint.exponent.isFinite && viewTint.exponent > 0
    }

    private static let hasExpectedVertexABI =
        MemoryLayout<SceneMdlStaticModel.Vertex>.stride == 64
        && MemoryLayout<SceneMdlStaticModel.Vertex>.offset(of: \.position) == 0
        && MemoryLayout<SceneMdlStaticModel.Vertex>.offset(of: \.normal) == 16
        && MemoryLayout<SceneMdlStaticModel.Vertex>.offset(of: \.tangent) == 32
        && MemoryLayout<SceneMdlStaticModel.Vertex>.offset(of: \.uv) == 48

    /// Swift/MSL constant-buffer ABI. The paired Metal source compiles in the
    /// same test that executes this gate; host-side drift rejects pipeline
    /// preparation before any draw can be encoded.
    static let hasExpectedUniformABI =
        MemoryLayout<SceneStaticModelUniforms>.stride == 1344
        && MemoryLayout<SceneModelShadowUniforms>.stride == 112
        && MemoryLayout<SceneModelShadowUniforms>.offset(of: \.positionRadius) == 64
        && MemoryLayout<SceneModelShadowUniforms>.offset(of: \.parameters) == 80
        && MemoryLayout<SceneModelShadowUniforms>.offset(of: \.identity) == 96
        && MemoryLayout<SceneStaticModelShadowUniforms>.stride == 288
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.modelMatrix) == 64
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.worldToLight) == 128
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.positionRadius) == 192
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.viewport) == 224
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.textureFrame0) == 240
        && MemoryLayout<SceneStaticModelShadowUniforms>.offset(of: \.coverage) == 272
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.shadow0) == 880
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.shadow3) == 1216
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.surfaceMaterial) == 1328
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.modelMatrix) == 0
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.viewProjectionMatrix) == 64
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.normalMatrix) == 128
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.textureFrame0) == 176
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.materialFlags) == 320
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.lightCounts) == 336
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.ambientColor) == 352
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.skylightColor) == 368
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.lightDirectionIntensity0) == 416
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.lightDirectionIntensity3) == 464
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.lightColor0) == 480
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.lightColor3) == 528
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.pointPositionRadius0) == 544
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.pointPositionRadius3) == 592
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.pointColorIntensity0) == 608
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.pointColorIntensity3) == 656
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotPositionRadius0) == 672
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotPositionRadius3) == 720
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotDirectionInnerCosine0) == 736
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotDirectionInnerCosine3) == 784
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotColorIntensity0) == 800
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotColorIntensity3) == 848
        && MemoryLayout<SceneStaticModelUniforms>.offset(of: \.spotOuterCosines) == 864

    /// Preserve legacy diffuse units for materials without an admitted surface
    /// profile. Admitted generic4 model lights upload raw intensity; the shared
    /// surface response supplies its one normalization factor.
    static let staticModelLightEnergyScale: Float = 0.30

    private static func encodedLights(
        _ lights: [SceneLightSnapshot.Directional], energyScale: Float
    ) -> [(directionIntensity: SIMD4<Float>, color: SIMD4<Float>)] {
        (0..<SceneLightSnapshot.maximumLightCount).map { index in
            guard lights.indices.contains(index) else {
                return (.zero, .zero)
            }
            let light = lights[index]
            return (
                SIMD4(
                    light.directionTowardLight.x,
                    light.directionTowardLight.y,
                    light.directionTowardLight.z,
                    max(light.intensity, 0) * energyScale
                ),
                SIMD4(light.color.x, light.color.y, light.color.z, 0)
            )
        }
    }

    private static func encodedSpots(
        _ lights: [SceneLightSnapshot.Spot], energyScale: Float
    ) -> [(
        positionRadius: SIMD4<Float>,
        directionInnerCosine: SIMD4<Float>,
        colorIntensity: SIMD4<Float>,
        outerCosine: Float
    )] {
        (0..<SceneLightSnapshot.maximumLightCount).map { index in
            guard lights.indices.contains(index) else {
                return (.zero, .zero, .zero, 0)
            }
            let light = lights[index]
            return (
                SIMD4(
                    light.position.x, light.position.y, light.position.z,
                    light.radius
                ),
                SIMD4(
                    light.directionFromLight.x,
                    light.directionFromLight.y,
                    light.directionFromLight.z,
                    light.innerConeCosine
                ),
                SIMD4(
                    light.color.x, light.color.y, light.color.z,
                    light.intensity * energyScale
                ),
                light.outerConeCosine
            )
        }
    }

    private static func encodedPoints(
        _ lights: [SceneLightSnapshot.Point], energyScale: Float
    ) -> [(
        positionRadius: SIMD4<Float>,
        colorIntensity: SIMD4<Float>
    )] {
        (0..<SceneLightSnapshot.maximumLightCount).map { index in
            guard lights.indices.contains(index) else {
                return (.zero, .zero)
            }
            let light = lights[index]
            return (
                SIMD4(
                    light.position.x, light.position.y, light.position.z,
                    light.radius
                ),
                SIMD4(
                    light.color.x, light.color.y, light.color.z,
                    light.intensity * energyScale
                )
            )
        }
    }

    private static func isFinite(_ matrix: simd_float4x4) -> Bool {
        matrix.columns.0.x.isFinite && matrix.columns.0.y.isFinite
            && matrix.columns.0.z.isFinite && matrix.columns.0.w.isFinite
            && matrix.columns.1.x.isFinite && matrix.columns.1.y.isFinite
            && matrix.columns.1.z.isFinite && matrix.columns.1.w.isFinite
            && matrix.columns.2.x.isFinite && matrix.columns.2.y.isFinite
            && matrix.columns.2.z.isFinite && matrix.columns.2.w.isFinite
            && matrix.columns.3.x.isFinite && matrix.columns.3.y.isFinite
            && matrix.columns.3.z.isFinite && matrix.columns.3.w.isFinite
    }

    private static func isFinite(_ matrix: simd_float3x3) -> Bool {
        matrix.columns.0.x.isFinite && matrix.columns.0.y.isFinite
            && matrix.columns.0.z.isFinite && matrix.columns.1.x.isFinite
            && matrix.columns.1.y.isFinite && matrix.columns.1.z.isFinite
            && matrix.columns.2.x.isFinite && matrix.columns.2.y.isFinite
            && matrix.columns.2.z.isFinite
    }

    private nonisolated static func isValid(
        _ transform: SceneTextureUVTransform
    ) -> Bool {
        let determinant = transform.xAxis.x * transform.yAxis.y
            - transform.xAxis.y * transform.yAxis.x
        return transform.origin.x.isFinite && transform.origin.y.isFinite
            && transform.xAxis.x.isFinite && transform.xAxis.y.isFinite
            && transform.yAxis.x.isFinite && transform.yAxis.y.isFinite
            && determinant.isFinite && abs(determinant) > 1e-7
    }
}

/// Chooses depth isolation from authored geometry/transform structure only.
/// Near-coincident copies of one geometry are layered materials: each keeps
/// self-depth but must not z-fight the preceding shell. Other models continue
/// to share one depth target and occlude each other normally.
struct SceneStaticModelDepthPlan {
    enum Target: Equatable {
        case shared
        case isolated
    }

    private struct Draw {
        let geometryIdentity: String
        let translation: SIMD3<Float>
        let axisLengths: SIMD3<Float>
    }

    private var draws: [Draw] = []

    mutating func target(
        geometryIdentity: String,
        modelMatrix: simd_float4x4
    ) -> Target {
        guard let draw = Self.draw(
            geometryIdentity: geometryIdentity,
            modelMatrix: modelMatrix
        ) else {
            return .shared
        }
        defer { draws.append(draw) }
        return draws.contains(where: { Self.isNearCoincident($0, draw) })
            ? .isolated : .shared
    }

    private static func draw(
        geometryIdentity: String,
        modelMatrix: simd_float4x4
    ) -> Draw? {
        let translation = SIMD3(
            modelMatrix.columns.3.x,
            modelMatrix.columns.3.y,
            modelMatrix.columns.3.z
        )
        let axes = SIMD3(
            axisLength(modelMatrix.columns.0),
            axisLength(modelMatrix.columns.1),
            axisLength(modelMatrix.columns.2)
        )
        guard translation.x.isFinite, translation.y.isFinite,
              translation.z.isFinite, axes.x.isFinite, axes.y.isFinite,
              axes.z.isFinite, axes.x > 0, axes.y > 0, axes.z > 0 else {
            return nil
        }
        return Draw(
            geometryIdentity: geometryIdentity,
            translation: translation,
            axisLengths: axes
        )
    }

    private static func isNearCoincident(_ lhs: Draw, _ rhs: Draw) -> Bool {
        guard lhs.geometryIdentity == rhs.geometryIdentity else { return false }
        let maximumAxis = [
            lhs.axisLengths.x, lhs.axisLengths.y, lhs.axisLengths.z,
            rhs.axisLengths.x, rhs.axisLengths.y, rhs.axisLengths.z
        ].max() ?? 0
        guard simd_distance(lhs.translation, rhs.translation)
                <= max(1, maximumAxis * 0.001) else {
            return false
        }
        return zip(
            [lhs.axisLengths.x, lhs.axisLengths.y, lhs.axisLengths.z],
            [rhs.axisLengths.x, rhs.axisLengths.y, rhs.axisLengths.z]
        ).allSatisfy {
            max($0.0, $0.1) / min($0.0, $0.1) <= 1.02
        }
    }

    private static func axisLength(_ column: SIMD4<Float>) -> Float {
        simd_length(SIMD3(column.x, column.y, column.z))
    }
}
