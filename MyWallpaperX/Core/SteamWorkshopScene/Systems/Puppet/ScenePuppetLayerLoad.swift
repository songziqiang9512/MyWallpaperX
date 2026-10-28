import Foundation
import Metal
import simd

/// Prepares immutable MDL and pose data, then creates layer/surface-owned
/// GeometryProducts. The atlas remains a sampling resource of each product.
enum ScenePuppetLayerLoad {
    /// Launch-time payload installed into any existing SceneScript owner for
    /// the same authored layer.  The rig reader remains the sole source of
    /// names, parent order, and bind-local matrices; no sample-specific
    /// routing is involved.
    struct BoneConfiguration {
        let names: [String]
        let parentIndices: [Int]
        let worldMatrices: [Double]
        let localMatrices: [Double]
        var impulseUnavailable: [UInt8] = []
    }

    /// A launch may retain this result by its existing mesh resource identity.
    /// No source layer's selected clips, mutable playback or raw Data live here.
    struct PreparedAsset {
        let meshPath: String
        let mesh: SceneMdlPuppetMesh
        let attachments: [SceneMdlPuppetAttachment]
        fileprivate let rig: Result<SceneMdlPuppetRig, Error>
        fileprivate let animationSet: Result<SceneMdlPuppetAnimationSet?, Error>?
        fileprivate let referenceEvaluator: Result<ScenePuppetAnimationEvaluator, Error>?
        fileprivate let initialBones: BoneConfiguration?
    }

    enum AssetPreparation {
        case ready(PreparedAsset)
        case unavailable(allowsMissingMeshTextureProduct: Bool, message: String)
    }

    /// Opaque immutable configuration, prepared separately for an authored
    /// source and for each admitted creation template. An empty configuration
    /// never acquires the source layer's animation selection or script state.
    struct PreparedPose {
        fileprivate enum PlaybackKind {
            case animation
            case reference
            case script

            var failurePrefix: String {
                switch self {
                case .animation: return "animation geometry rejected"
                case .reference, .script: return "script pose rejected"
                }
            }
        }

        fileprivate enum Geometry {
            case unavailable(allowsMissingMeshTextureProduct: Bool, message: String)
            case bind(PreparedAsset, fallbackMessage: String?)
            case evaluated(PreparedAsset, ScenePuppetAnimationSelection,
                           ScenePuppetAnimationEvaluator, PlaybackKind, fallbackMessage: String?)
        }

        fileprivate let geometry: Geometry
    }

    static func prepareAsset(
        meshPath: String,
        resourceView: SceneResourceView,
        needsAnimations: Bool,
        cancellationCheck: () throws -> Void = {}
    ) throws -> AssetPreparation {
        try cancellationCheck()
        // Select one authored VFS entry, including hidden literal paths. An
        // absent package member may use loose content; a selected bad member
        // remains authoritative and never falls through after its read.
        guard !meshPath.hasPrefix("/") else {
            return .unavailable(allowsMissingMeshTextureProduct: false,
                message: "puppet mesh path rejected (\(meshPath))")
        }
        let relativePath = meshPath.replacingOccurrences(of: "\\", with: "/")
        let data: Data
        do {
            guard let handle = try resourceView.literalEntry(relativePath: relativePath) else {
                return .unavailable(allowsMissingMeshTextureProduct: true,
                    message: "puppet mesh unavailable (\(meshPath))")
            }
            data = try withoutActuallyEscaping(cancellationCheck) { check in
                try handle.readBytes(checkCancellation: check)
            }
        } catch let error as SceneResourceView.ReadError {
            switch error {
            case .sourceChanged, .invalidHandle: throw error
            case .missing:
                return .unavailable(allowsMissingMeshTextureProduct: true,
                    message: "puppet mesh unavailable (\(meshPath))")
            case .invalidPath, .symlinkEscape:
                return .unavailable(allowsMissingMeshTextureProduct: false,
                    message: "puppet mesh path rejected (\(meshPath))")
            case .unreadable, .fileTooLarge:
                return .unavailable(allowsMissingMeshTextureProduct: false,
                    message: "puppet mesh read failed (\(meshPath))")
            }
        }
        let mesh: SceneMdlPuppetMesh
        do {
            mesh = try SceneMdlPuppetMeshReader.read(data: data)
        } catch let error as SceneMdlPuppetMeshReadError {
            return .unavailable(allowsMissingMeshTextureProduct: false,
                message: "puppet mesh rejected: \(error.description) (\(meshPath))")
        } catch {
            return .unavailable(allowsMissingMeshTextureProduct: false,
                message: "puppet mesh rejected: unknown parse failure (\(meshPath))")
        }
        let attachments = (try? SceneMdlPuppetAttachmentReader.read(data: data)) ?? []
        let rig: Result<SceneMdlPuppetRig, Error> = Result {
            try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
        }
        let animationSet: Result<SceneMdlPuppetAnimationSet?, Error>? = needsAnimations
            ? Result { try SceneMdlPuppetAnimationReader.read(data: data) } : nil
        let referenceEvaluator: Result<ScenePuppetAnimationEvaluator, Error>?
        if case let .success(value) = rig, value.referenceLocalMatricesColumnMajor != nil {
            referenceEvaluator = Result { try ScenePuppetAnimationEvaluator(mesh: mesh, rig: value) }
        } else {
            referenceEvaluator = nil
        }
        let initialBones: BoneConfiguration?
        if case let .success(value) = rig {
            initialBones = initialBoneConfiguration(rig: value, referenceEvaluator: referenceEvaluator)
        } else {
            initialBones = nil
        }
        return .ready(.init(meshPath: meshPath, mesh: mesh, attachments: attachments,
            rig: rig, animationSet: animationSet, referenceEvaluator: referenceEvaluator,
            initialBones: initialBones))
    }

    static func boneConfiguration(
        for asset: PreparedAsset,
        layerID: Int? = nil
    ) -> BoneConfiguration? {
        if let layerID, case let .success(rig) = asset.rig {
            logPhysicsDiagnostics(rig: rig, layerID: layerID)
        }
        return asset.initialBones
    }

    private static func logPhysicsDiagnostics(rig: SceneMdlPuppetRig, layerID: Int) {
        for (index, bone) in rig.bones.enumerated() {
            if let diagnostic = bone.physicsDiagnostic {
#if DEBUG
                NSLog("MWX Puppet: layer=%d bone=%d fallback=authored-pose reason=%@",
                      layerID, index, diagnostic)
#endif
            }
        }
    }

    static func initialBoneConfiguration(
        rig: SceneMdlPuppetRig,
        referenceEvaluator: Result<ScenePuppetAnimationEvaluator, Error>?
    ) -> BoneConfiguration? {
        let localMatrices: [simd_float4x4]
        if rig.referenceLocalMatricesColumnMajor != nil {
            guard case let .success(evaluator)? = referenceEvaluator,
                  let neutralPose = try? evaluator.boneTransforms(
                      selection: .init(clips: [], composition: .layered), frameSamples: []
                  ) else { return nil }
            localMatrices = neutralPose.local
        } else {
            // Initial getters preserve the exact historical bind, including affine
            // shear and small determinants that are outside animation evaluation.
            localMatrices = rig.bones.map {
                ScenePuppetAnimationEvaluator.matrix(fromColumnMajor: $0.bindLocalMatrixColumnMajor)
            }
        }
        guard let frame = try? ScenePuppetBoneTransformFrame(
            rig: rig, animatedLocalMatrices: localMatrices
        ) else { return nil }
        func flatten(_ matrix: simd_float4x4) -> [Double] {
            [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
                .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
        }
        return BoneConfiguration(
            names: rig.bones.map(\.name),
            parentIndices: rig.bones.map(\.parentIndex),
            worldMatrices: frame.worldMatrices.flatMap(flatten),
            localMatrices: frame.localMatrices.flatMap(flatten),
            impulseUnavailable: rig.bones.map { $0.physicsDiagnostic == nil ? 0 : 1 }
        )
    }

    struct Outcome {
        let geometryProduct: SceneGeometryProduct?
        let playback: ScenePuppetPlaybackState?
        /// True only when the authored package omits the referenced mesh. In
        /// that case the image payload is the sole available authored product.
        let allowsMissingMeshTextureProduct: Bool
        let message: String
    }

    static func preparePose(
        for layer: SceneRenderDescriptor.Layer,
        asset preparation: AssetPreparation,
        usesDefaultConfiguration: Bool = false
    ) -> PreparedPose? {
        guard layer.puppetMeshPath != nil else { return nil }
        let animationLayers = usesDefaultConfiguration ? [] : layer.puppetAnimationLayers
        let hasInlineScript = !usesDefaultConfiguration && layer.hasInlineScript
        let asset: PreparedAsset
        switch preparation {
        case let .ready(value):
            asset = value
        case let .unavailable(allowsMissing, message):
            return .init(geometry: .unavailable(
                allowsMissingMeshTextureProduct: allowsMissing, message: message))
        }
        if case let .success(rig) = asset.rig, let diagnostic = rig.referencePoseDiagnostic {
#if DEBUG
            NSLog("MWX Puppet: layer=%d fallback=bind-pose reason=%@", layer.id, diagnostic)
#endif
        }
        var fallbackMessage: String?
        var needsReferenceOnlyPlayback = false
        let hasPreparedReference: Bool
        if case let .success(rig) = asset.rig,
           rig.referenceLocalMatricesColumnMajor != nil,
           case .success? = asset.referenceEvaluator {
            hasPreparedReference = true
        } else {
            hasPreparedReference = false
        }
        if !animationLayers.isEmpty {
            do {
                _ = try asset.rig.get()
                switch asset.animationSet {
                case .none:
                    fallbackMessage = "animation unavailable: data was not prepared"
                    needsReferenceOnlyPlayback = hasPreparedReference
                case .some(.success(nil)):
                    fallbackMessage = "animation rejected: version-matched MDLA is absent"
                    needsReferenceOnlyPlayback = hasPreparedReference
                case let .some(.failure(failure)):
                    throw failure
                case let .some(.success(animationSet?)):
                    switch ScenePuppetAnimationSelector.select(
                        layers: animationLayers, animationSet: animationSet
                    ) {
                    case let .success(selection?):
                        return evaluatedPose(asset: asset, selection: selection, kind: .animation)
                    case .success(nil):
                        fallbackMessage = "animation inactive: no visible layer"
                        if case let .success(rig) = asset.rig {
                            needsReferenceOnlyPlayback = rig.referenceLocalMatricesColumnMajor != nil
                        }
                    case let .failure(failure):
                        fallbackMessage = "animation rejected: \(failure.description)"
                        needsReferenceOnlyPlayback = hasPreparedReference
                    }
                }
            } catch let failure as SceneMdlPuppetRigReadError {
                fallbackMessage = "animation rig rejected: \(failure.description)"
            } catch let failure as SceneMdlPuppetAnimationReadError {
                fallbackMessage = "animation data rejected: \(failure.description)"
                needsReferenceOnlyPlayback = hasPreparedReference
            } catch {
                fallbackMessage = "animation rejected: unknown parse failure"
            }
        }
        // Empty requests retain the original reference/bind decision. They do
        // not inherit clips or inline script merely because a source had them.
        if animationLayers.isEmpty || needsReferenceOnlyPlayback,
           case let .success(rig) = asset.rig,
           hasInlineScript || rig.referenceLocalMatricesColumnMajor != nil {
            return evaluatedPose(asset: asset,
                selection: .init(clips: [], composition: .layered),
                kind: rig.referenceLocalMatricesColumnMajor != nil ? .reference : .script,
                fallbackMessage: fallbackMessage)
        }
        return .init(geometry: .bind(asset, fallbackMessage: fallbackMessage))
    }

    private static func evaluatedPose(
        asset: PreparedAsset,
        selection: ScenePuppetAnimationSelection,
        kind: PreparedPose.PlaybackKind,
        fallbackMessage: String? = nil
    ) -> PreparedPose {
        do {
            let evaluator: ScenePuppetAnimationEvaluator
            if selection.clips.isEmpty, let referenceEvaluator = asset.referenceEvaluator {
                evaluator = try referenceEvaluator.get()
            } else {
                evaluator = try ScenePuppetAnimationEvaluator(mesh: asset.mesh,
                    rig: asset.rig.get(), additiveAnimations: selection.clips.map(\.animation))
            }
            return .init(geometry: .evaluated(asset, selection, evaluator, kind,
                fallbackMessage: fallbackMessage))
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            return .init(geometry: .bind(asset,
                fallbackMessage: (fallbackMessage.map { $0 + "; " } ?? "")
                    + "\(kind.failurePrefix): \(failure.description)"))
        } catch {
            return .init(geometry: .bind(asset, fallbackMessage:
                (fallbackMessage.map { $0 + "; " } ?? "")
                    + "\(kind.failurePrefix): \(ScenePuppetPlaybackState.Failure.resourceAllocationFailed.description)"))
        }
    }

    static func preparedGeometry(
        for layer: SceneRenderDescriptor.Layer,
        preparedPose: PreparedPose,
        atlasTexture: MTLTexture,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline,
        clippingPipeline: () -> MTLRenderPipelineState? = { nil },
        loadClippingMask: (String) -> MTLTexture? = { _ in nil },
        allocateClippingMask: @escaping ScenePuppetClipping.Allocator = { _, _, _, _ in nil }
    ) -> Outcome? {
        guard layer.puppetMeshPath != nil else { return nil }
        let asset: PreparedAsset
        let evaluated: (ScenePuppetAnimationSelection, ScenePuppetAnimationEvaluator,
                        PreparedPose.PlaybackKind)?
        var animationFallbackMessage: String?
        switch preparedPose.geometry {
        case let .unavailable(allowsMissing, message):
            return Outcome(geometryProduct: nil, playback: nil,
                allowsMissingMeshTextureProduct: allowsMissing, message: message)
        case let .bind(value, fallbackMessage):
            asset = value
            evaluated = nil
            animationFallbackMessage = fallbackMessage
        case let .evaluated(value, selection, evaluator, kind, fallbackMessage):
            asset = value
            evaluated = (selection, evaluator, kind)
            animationFallbackMessage = fallbackMessage
        }
        let mesh = asset.mesh
        let clipping: ScenePuppetClipping?
        if mesh.clipRecords.isEmpty {
            clipping = nil
        } else {
            var paintTextures: [Int: MTLTexture] = [:]
            for (index, record) in mesh.clipRecords.enumerated() {
                if let texture = loadClippingMask(record.maskTexturePath),
                   texture.pixelFormat == .r8Unorm {
                    paintTextures[index] = texture
                } else {
#if DEBUG
                    NSLog("MWX Puppet: layer=%d clip=%d mask unavailable; target part hidden", layer.id, index)
#endif
                }
            }
            clipping = ScenePuppetClipping(mesh: mesh, pipeline: clippingPipeline(),
                paintTextures: paintTextures, allocate: allocateClippingMask)
        }
        let renderSize = layer.renderSizeWH ?? []
        let layerWidth = renderSize.count > 0 ? renderSize[0] : 0
        let layerHeight = renderSize.count > 1 ? renderSize[1] : 0
        if let (selection, evaluator, kind) = evaluated {
            switch ScenePuppetPlaybackState.make(
                layerID: layer.id, mesh: mesh, evaluator: evaluator,
                selection: selection, attachments: asset.attachments,
                atlasTexture: atlasTexture, layerWidth: layerWidth,
                layerHeight: layerHeight,
                device: device, pipeline: pipeline, clipping: clipping
            ) {
            case let .success(output):
                let message: String
                switch kind {
                case .animation:
                    message = String(
                        format: "puppet world geometry OK %@ mode=%@ ids=%@ clips=%d verts=%d tris=%d",
                        mesh.version, selection.composition.rawValue,
                        selection.clips.map { String($0.animation.id) }.joined(separator: ","),
                        selection.clips.count, mesh.vertices.count, mesh.triangleCount)
                case .reference:
                    message = "puppet reference world geometry prepared"
                case .script:
                    message = "puppet script world geometry prepared"
                }
                return Outcome(geometryProduct: output.product, playback: output.state,
                    allowsMissingMeshTextureProduct: false,
                    message: message + (animationFallbackMessage.map { "; " + $0 } ?? ""))
            case let .failure(failure):
                animationFallbackMessage = (animationFallbackMessage.map { $0 + "; " } ?? "")
                    + "\(kind.failurePrefix): \(failure.description)"
            }
        }
        return staticOutcome(
            layer: layer,
            mesh: mesh,
            atlasTexture: atlasTexture,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            device: device,
            pipeline: pipeline,
            clipping: clipping,
            animationFallbackMessage: animationFallbackMessage
        )
    }

    private static func staticOutcome(
        layer: SceneRenderDescriptor.Layer,
        mesh: SceneMdlPuppetMesh,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline,
        clipping: ScenePuppetClipping?,
        animationFallbackMessage: String?
    ) -> Outcome {
        switch ScenePuppetMeshGeometry.prepare(
            layerID: layer.id,
            mesh: mesh,
            atlasTexture: atlasTexture,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            device: device,
            pipeline: pipeline,
            clipping: clipping
        ) {
        case let .success(output):
            return Outcome(
                geometryProduct: output.product,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: String(
                    format: "puppet bind-pose world geometry OK %@ stride=%d verts=%d tris=%d",
                    mesh.version,
                    mesh.vertexStride,
                    output.vertexCount,
                    output.triangleCount
                ) + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        case let .failure(failure):
            return Outcome(
                geometryProduct: nil,
                playback: nil,
                allowsMissingMeshTextureProduct: false,
                message: "puppet geometry preparation failed: \(failure.description) (\(layer.puppetMeshPath ?? "unknown"))"
                    + (animationFallbackMessage.map { "; \($0)" } ?? "")
            )
        }
    }

}
