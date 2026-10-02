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
    /// Resolves one claimed layer's lit capture payload from the frame light
    /// snapshot and the same layer model matrix the base capture uses. A
    /// unavailable or rejected normal keeps valid flat lighting. Only a whole
    /// producer miss keeps the layer unlit for this frame.
    func makeLitCapturePayload(
        profile: SceneBaseMaterialLightingProfile?,
        snapshot: SceneLightSnapshot?,
        layerModelMatrix: simd_float4x4,
        layerWorldFrame: simd_float4x4,
        usesPerspective: Bool,
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
        let normal: SceneBaseMaterialLitCapturePayload.NormalInput
        switch profile.normalSource {
        case let .asset(asset):
            let identity = SceneFrameTextureIdentity.asset(asset)
            normal = .resolve(textureRegistry.lookup(identity))
        case .disabled: normal = .disabled
        case .unsupported: normal = .unsupported
        case .invalid: normal = .invalid
        }
        let lights = SceneBaseMaterialLitCapturePayload.packLights(
            pointLights: snapshot.point.map { light in
                SceneBaseMaterialLitCapturePayload.PointLight(
                    position: light.position,
                    color: light.color,
                    intensity: light.intensity,
                    radius: light.radius
                )
            },
            spotLights: snapshot.spot.map { light in
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
            ambient: snapshot.ambient,
            layerModelMatrix: layerModelMatrix,
            normalModelMatrix: layerWorldFrame * SceneMatrix.scale(SIMD3(
                1, SceneCameraProjection.imageCardYDirection(
                    usesPerspective: usesPerspective,
                    sceneOrthoHeight: renderDescriptor.camera.orthoHeight
                ), 1
            ))
        )
        guard let lights else { return .miss(.lightPackingRejected) }
        guard let payload = SceneBaseMaterialLitCapturePayload(
            pipeline: litPipeline,
            lights: lights,
            normal: normal
        ) else { return .miss(.payloadInvalid) }
        return .payload(payload)
    }
}
