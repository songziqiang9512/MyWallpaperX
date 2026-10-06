import Metal
import simd

enum SceneLitCaptureMissReason: String, Hashable {
    case geometryUnsupported = "receiver-geometry-unsupported"
    case profileMissing = "profile-missing"
    case snapshotUnavailable = "frame-light-snapshot-unavailable"
    case pipelineUnavailable = "lit-pipeline-unavailable"
    case lightPackingRejected = "light-packing-rejected"
    case payloadInvalid = "payload-invalid"
}

/// At most one entry per fixed reason for the process lifetime. Layer IDs are
/// diagnostic context only, so changing scenes cannot grow a global ID set.
enum SceneBaseMaterialLitCaptureMissLog {
    private static let lock = NSLock()
    private static var reported = Set<SceneLitCaptureMissReason>()

    static func record(reason: SceneLitCaptureMissReason, layerID: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard reported.insert(reason).inserted else { return }
        NSLog(
            "MWX SCENE: schema=base-material-lit-capture-miss layer=%d reason=%@",
            layerID,
            reason.rawValue
        )
    }
}

enum SceneLitCapturePayloadResolution {
    case payload(SceneBaseMaterialLitCapturePayload)
    case miss(SceneLitCaptureMissReason)
}

extension SceneMetalRenderer {
    /// Plain receivers use the same typed source producer as prepared graphs;
    /// optional reflection absence leaves the original direct route available.
    func preparePlainSourceLighting(request: inout SceneImageLayerDrawRequest,
        snapshot: SceneLightSnapshot, model: simd_float4x4, worldFrame: simd_float4x4,
        cameraFrame: SceneParticleCameraFrame, usesPerspective: Bool,
        environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)?,
        preparedResolution: SceneLitCapturePayloadResolution? = nil) {
        let layer = request.layer
        guard request.resolvedMaterialFrameTargetPlan == nil,
              let profile = baseMaterialProviderBindings.lightingProfileByLayerID[layer.id],
              profile.surfaceEnabled else { return }
        switch preparedResolution ?? makeLitCapturePayload(profile: profile, snapshot: snapshot,
            dynamicValues: request.dynamicValues, layerModelMatrix: model, layerWorldFrame: worldFrame,
            usesPerspective: usesPerspective, cameraFrame: cameraFrame,
            sceneViewProjection: cameraFrame.viewProjection(for: layer),
            environmentSource: environmentSource, geometryProduct: request.geometryProduct) {
        case let .payload(payload): request.sourceLighting = payload
        case let .miss(reason): SceneBaseMaterialLitCaptureMissLog.record(reason: reason, layerID: layer.id)
        }
    }

    /// Resolves one claimed layer's lit capture payload from the frame light
    /// snapshot and the same layer model matrix the base capture uses. A
    /// unavailable or rejected normal keeps valid flat lighting. Only a whole
    /// producer miss keeps the layer unlit for this frame.
    func makeLitCapturePayload(
        profile: SceneBaseMaterialLightingProfile?,
        snapshot: SceneLightSnapshot?,
        dynamicValues: SceneDynamicSnapshot,
        layerModelMatrix: simd_float4x4,
        layerWorldFrame: simd_float4x4,
        usesPerspective: Bool,
        cameraFrame: SceneParticleCameraFrame,
        sceneViewProjection: simd_float4x4,
        environmentSource: ((MTLCommandBuffer) -> SceneFrameTextureResource?)?,
        geometryProduct: SceneGeometryProduct? = nil
    ) -> SceneLitCapturePayloadResolution {
        // Mesh/puppet source atlases do not identify a unique world receiver
        // position after deformation. Preserve unlit current until that mapping
        // is prepared by the geometry owner, rather than shading a unit quad.
        guard geometryProduct == nil else { return .miss(.geometryUnsupported) }
        guard let profile else { return .miss(.profileMissing) }
        guard let snapshot else {
            return .miss(.snapshotUnavailable)
        }
        guard let litPipeline = pipelineRepository.litImageLayer else {
            return .miss(.pipelineUnavailable)
        }
        let normal: SceneBaseMaterialLitCapturePayload.TextureInput
        switch profile.normalSource {
        case let .asset(asset):
            let identity = SceneFrameTextureIdentity.asset(asset)
            normal = .resolve(textureRegistry.lookup(identity))
        case .disabled: normal = .disabled
        case .unsupported: normal = .unsupported
        case .invalid: normal = .invalid
        }
        let materialMap: SceneBaseMaterialLitCapturePayload.TextureInput
        switch profile.mapSource {
        case let .asset(asset):
            materialMap = .resolve(textureRegistry.lookup(.asset(asset)), kind: .materialMap)
        case .disabled: materialMap = .disabled
        case .unsupported: materialMap = .unsupported
        case .invalid: materialMap = .invalid
        }
        let lights = SceneBaseMaterialLitCapturePayload.packLights(
            pointLights: (profile.lightingEnabled ? snapshot.point : []).filter { light in
                // Official `point` lights 2D lit images; `lpoint` is a static-
                // model light (own-fixture black-box, 2026-10-06).
                !light.illuminatesStaticModels
            }.map { light in
                SceneBaseMaterialLitCapturePayload.PointLight(
                    position: light.position,
                    color: light.color,
                    intensity: light.intensity,
                    radius: light.radius
                )
            },
            spotLights: (profile.lightingEnabled ? snapshot.spot : []).map { light in
                SceneBaseMaterialLitCapturePayload.SpotLight(
                    position: light.position,
                    direction: light.directionFromLight,
                    color: light.color,
                    intensity: light.intensity,
                    radius: light.radius,
                    innerConeCosine: light.innerConeCosine,
                    outerConeCosine: light.outerConeCosine
                )
            },
            ambient: profile.lightingEnabled ? snapshot.ambient : .zero,
            material: profile.scalarMaterial,
            view: cameraFrame.materialView(usesPerspective: usesPerspective),
            layerModelMatrix: layerModelMatrix,
            normalModelMatrix: layerWorldFrame * SceneMatrix.scale(SIMD3(
                1, SceneCameraProjection.imageCardYDirection(
                    usesPerspective: usesPerspective,
                    sceneOrthoHeight: renderDescriptor.camera.orthoHeight
                ), 1
            ))
        )
        guard var lights else { return .miss(.lightPackingRejected) }
        lights.sceneViewProjection = sceneViewProjection
        lights.reflection = SIMD4(profile.reflection?.x ?? 0,
            profile.reflection?.y ?? 4, 0, profile.lightingEnabled ? 1 : 0)
        if !profile.lightingEnabled {
            guard profile.reflection != nil, environmentSource != nil, case .ready = normal else { return .miss(.profileMissing) }
        }
        let emission: SIMD4<Float>?
        switch profile.emission {
        case let .constant(value): emission = value
        case let .propertyBrightness(color, target):
            if case let .scalar(brightness) = dynamicValues[target]?.value,
               brightness >= 0, brightness.isFinite, Float(brightness).isFinite {
                emission = SIMD4(color, Float(brightness))
            } else { emission = nil }
        case nil: emission = nil
        }
        guard let payload = SceneBaseMaterialLitCapturePayload(
            pipeline: litPipeline,
            lights: lights,
            normal: normal,
            materialMap: materialMap,
            mapAllowedComponents: profile.mapAllowedComponents,
            mapRequiredComponents: profile.mapRequiredComponents,
            emission: emission, environmentSource: environmentSource
        ) else { return .miss(.payloadInvalid) }
        return .payload(payload)
    }
}
