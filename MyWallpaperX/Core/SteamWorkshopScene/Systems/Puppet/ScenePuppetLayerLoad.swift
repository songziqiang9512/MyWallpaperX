import Foundation
import simd

/// Prepares immutable MDL, animation selections and pose evaluation data.
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
        enum PlaybackKind {
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

        enum Geometry {
            case unavailable(allowsMissingMeshTextureProduct: Bool, message: String)
            case bind(PreparedAsset, fallbackMessage: String?)
            case evaluated(PreparedAsset, ScenePuppetAnimationSelection,
                           ScenePuppetAnimationEvaluator, PlaybackKind, fallbackMessage: String?)
        }

        let geometry: Geometry
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
                        layers: animationLayers, animationSet: animationSet, includeStaticHidden: true
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
            var selection = selection
            let evaluator: ScenePuppetAnimationEvaluator
            if selection.clips.isEmpty, let referenceEvaluator = asset.referenceEvaluator {
                evaluator = try referenceEvaluator.get()
            } else {
                let requiredIDs = Set(selection.clips.filter {
                    $0.layer.additive == false
                        && ($0.layer.visible != false || $0.layer.visibilityBinding != nil)
                }.map { $0.animation.id })
                var resourceIDs: Set<Int> = []
                let animations = selection.clips.compactMap { clip in
                    resourceIDs.insert(clip.animation.id).inserted ? clip.animation : nil
                }
                evaluator = try ScenePuppetAnimationEvaluator(mesh: asset.mesh,
                    rig: asset.rig.get(), additiveAnimations: animations,
                    optionalAnimationIDs: resourceIDs.subtracting(requiredIDs))
                let clips = selection.clips.filter {
                    evaluator.hasPreparedAnimation(animationID: $0.animation.id)
                }
                let unavailable = selection.clips.filter {
                    !evaluator.hasPreparedAnimation(animationID: $0.animation.id)
                }
                let unavailableMessage = unavailable.isEmpty ? fallbackMessage :
                    (fallbackMessage.map { $0 + "; " } ?? "") + "additive/optional animation unavailable: "
                    + unavailable.map { "slot=\($0.layer.id.map(String.init) ?? "unknown") clip=\($0.animation.id)" }
                        .joined(separator: ", ")
                if !selection.clips.isEmpty && clips.isEmpty {
                    let message = "animation unavailable: no prepared layer"
                    if case let .success(referenceEvaluator)? = asset.referenceEvaluator {
                        return .init(geometry: .evaluated(asset,
                            .init(clips: [], composition: .layered), referenceEvaluator,
                            .reference, fallbackMessage: message))
                    }
                    return .init(geometry: .bind(asset, fallbackMessage: message))
                }
                selection = .init(clips: clips, composition: clips.count == 1
                    && clips[0].layer.additive == false ? .singleAbsolute : .layered)
                return .init(geometry: .evaluated(asset, selection, evaluator, kind,
                    fallbackMessage: unavailableMessage))
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
                    + "\(kind.failurePrefix): \(error)"))
        }
    }

}
