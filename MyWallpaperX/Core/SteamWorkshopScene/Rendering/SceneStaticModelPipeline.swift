import Metal
import simd

struct SceneStaticModelMesh {
    fileprivate let vertexBuffer: MTLBuffer
    fileprivate let indexBuffer: MTLBuffer
    let indexCount: Int
}

struct SceneStaticModelViewTint {
    let front: SIMD3<Float>
    let back: SIMD3<Float>
    let exponent: Float
    let usesDynamicBackColor: Bool

    func resolvingBackColor(_ color: SIMD3<Float>) -> Self {
        guard usesDynamicBackColor else { return self }
        return .init(
            front: front,
            back: color,
            exponent: exponent,
            usesDynamicBackColor: true
        )
    }
}

/// Small material contract shared by direct static-model shader families.
/// Authored alpha meaning is kept separate from storage alpha so tint masks
/// cannot accidentally punch holes through otherwise opaque geometry.
struct SceneStaticModelMaterial {
    let color: SIMD3<Float>
    let opacity: Float
    let textureAlphaIsOpacity: Bool
    let textureAlphaIsTintMask: Bool
    let emissiveColor: SIMD3<Float>
    let emissiveBrightness: Float
    let viewTint: SceneStaticModelViewTint?

    func resolvingDynamicViewTintBack(_ color: SIMD3<Float>) -> Self {
        .init(
            color: self.color,
            opacity: opacity,
            textureAlphaIsOpacity: textureAlphaIsOpacity,
            textureAlphaIsTintMask: textureAlphaIsTintMask,
            emissiveColor: emissiveColor,
            emissiveBrightness: emissiveBrightness,
            viewTint: viewTint?.resolvingBackColor(color)
        )
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
    var ambientAndCount: SIMD4<Float>
    var lightDirectionIntensity0: SIMD4<Float>
    var lightDirectionIntensity1: SIMD4<Float>
    var lightDirectionIntensity2: SIMD4<Float>
    var lightDirectionIntensity3: SIMD4<Float>
    var lightColor0: SIMD4<Float>
    var lightColor1: SIMD4<Float>
    var lightColor2: SIMD4<Float>
    var lightColor3: SIMD4<Float>
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
}

/// Fixed, bounded pipeline for decoded static-model triangles. It consumes the
/// caller's current encoder and projection; target lifetime and publication
/// stay with the renderer that owns that encoder.
struct SceneStaticModelPipeline {
    let state: MTLRenderPipelineState

    private let device: MTLDevice
    private let writingDepthState: MTLDepthStencilState
    private let nonwritingDepthState: MTLDepthStencilState
    private let samplerStates: SceneTextureSamplerStateSet

    init?(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthPixelFormat: MTLPixelFormat = .depth32Float
    ) {
        guard let library = device.makeDefaultLibrary(),
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

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor),
              let writingDepthState = device.makeDepthStencilState(
                  descriptor: writingDepthDescriptor
              ),
              let nonwritingDepthState = device.makeDepthStencilState(
                  descriptor: nonwritingDepthDescriptor
              ),
              let samplerStates = SceneTextureSamplerStateSet(device: device) else {
            return nil
        }
        self.device = device
        self.state = state
        self.writingDepthState = writingDepthState
        self.nonwritingDepthState = nonwritingDepthState
        self.samplerStates = samplerStates
    }

    /// Uploads immutable decoded geometry after validating the fixed Swift/MSL
    /// ABI and every UInt16 index. Invalid geometry never reaches a GPU draw.
    func makeMesh(
        vertices: [SceneMdlStaticModel.Vertex],
        indices: [UInt16]
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
        let indexLength = indices.count * MemoryLayout<UInt16>.stride
        guard let vertexBuffer = vertices.withUnsafeBytes({ bytes in
                  device.makeBuffer(
                      bytes: bytes.baseAddress!,
                      length: vertexLength,
                      options: []
                  )
              }),
              let indexBuffer = indices.withUnsafeBytes({ bytes in
                  device.makeBuffer(
                      bytes: bytes.baseAddress!,
                      length: indexLength,
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
            indexCount: indices.count
        )
    }

    /// Encodes into the caller's current render pass. A singular/non-finite
    /// transform is rejected before bindings or render state are mutated.
    @discardableResult
    func draw(
        mesh: SceneStaticModelMesh,
        texture: MTLTexture,
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
        let lights = Self.encodedLights(lighting.directional)
        let spots = Self.encodedSpots(lighting.spot)
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
                max(material.color.x, 0),
                max(material.color.y, 0),
                max(material.color.z, 0),
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
                material.textureAlphaIsOpacity ? 1 : 0,
                emissiveMask == nil ? 0 : 1,
                UInt32(lighting.spot.count),
                material.textureAlphaIsTintMask ? 1 : 0
            ),
            ambientAndCount: SIMD4(
                lighting.ambient.x,
                lighting.ambient.y,
                lighting.ambient.z,
                Float(lighting.directional.count)
            ),
            lightDirectionIntensity0: lights[0].directionIntensity,
            lightDirectionIntensity1: lights[1].directionIntensity,
            lightDirectionIntensity2: lights[2].directionIntensity,
            lightDirectionIntensity3: lights[3].directionIntensity,
            lightColor0: lights[0].color,
            lightColor1: lights[1].color,
            lightColor2: lights[2].color,
            lightColor3: lights[3].color,
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
            )
        )

        encoder.setRenderPipelineState(state)
        encoder.setDepthStencilState(
            writesDepth ? writingDepthState : nonwritingDepthState
        )
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        defer {
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(nil)
        }
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<SceneStaticModelUniforms>.stride,
            index: 1
        )
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
            indexType: .uint16,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0
        )
        return true
    }

    static func normalMatrix(
        for modelMatrix: simd_float4x4
    ) -> simd_float3x3? {
        guard isFinite(modelMatrix) else { return nil }
        let linear = simd_float3x3(columns: (
            SIMD3(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
            SIMD3(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
            SIMD3(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
        ))
        let determinant = simd_determinant(linear)
        guard determinant.isFinite, abs(determinant) > 1e-8 else { return nil }
        let result = simd_transpose(simd_inverse(linear))
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

    private static func encodedLights(
        _ lights: [SceneLightSnapshot.Directional]
    ) -> [(directionIntensity: SIMD4<Float>, color: SIMD4<Float>)] {
        (0..<4).map { index in
            guard lights.indices.contains(index) else {
                return (.zero, .zero)
            }
            let light = lights[index]
            return (
                SIMD4(
                    light.directionTowardLight.x,
                    light.directionTowardLight.y,
                    light.directionTowardLight.z,
                    max(light.intensity, 0)
                ),
                SIMD4(light.color.x, light.color.y, light.color.z, 0)
            )
        }
    }

    private static func encodedSpots(
        _ lights: [SceneLightSnapshot.Spot]
    ) -> [(
        positionRadius: SIMD4<Float>,
        directionInnerCosine: SIMD4<Float>,
        colorIntensity: SIMD4<Float>,
        outerCosine: Float
    )] {
        (0..<4).map { index in
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
                    light.intensity
                ),
                light.outerConeCosine
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
