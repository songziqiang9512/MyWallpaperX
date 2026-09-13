import Foundation

private let sceneScriptMaximumOwnerLayerMutations = 256

/// Scene JSON and the renderer keep Euler angles in radians, while the public
/// SceneScript layer API exposes degrees. Convert only at the VM boundary so
/// authored storage, dynamic publication and world-frame math stay canonical.
nonisolated enum SceneScriptAngleUnits {
    static func degrees(fromRadians value: Double) -> Double {
        value * 180 / .pi
    }

    static func radians(fromDegrees value: Double) -> Double {
        value * .pi / 180
    }
}

nonisolated struct SceneScriptVideoPlaybackSnapshot: Equatable, Sendable {
    let layerID: Int
    let duration: TimeInterval
    let rate: Double
    let loop: Bool
    let currentTime: TimeInterval
    let isPlaying: Bool
    let endedGeneration: UInt64
}

nonisolated struct SceneScriptVideoCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case play
        case pause
        case stop
        case setCurrentTime(TimeInterval)
        case setRate(Double)
        case setLoop(Bool)
    }

    let layerID: Int
    let action: Action
}

nonisolated struct SceneScriptPuppetBoneMutation: Equatable, Sendable {
    let layerID: Int
    let boneIndex: Int
    let localSpace: Bool
    let matrix: [Double]
}

nonisolated enum SceneScriptPuppetBoneMutationBridge {
    static func mutations(owner: OpaquePointer) -> Result<[SceneScriptPuppetBoneMutation], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_puppet_bone_mutation_count(owner)
        guard count <= 256 else { return .failure(.mutationOverflow("Puppet bone mutation buffer exceeded")) }
        var output: [SceneScriptPuppetBoneMutation] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSPuppetBoneMutation()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_puppet_bone_mutation_at(owner, index, &raw, &diagnostic, diagnostic.count)
            guard result == MWX_SCENE_QUICKJS_OK, raw.layer_id >= -9_007_199_254_740_991,
                  raw.layer_id <= 9_007_199_254_740_991, raw.bone_index >= 0,
                  raw.bone_index < 256, raw.local_space <= 1 else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let matrix = withUnsafeBytes(of: raw.matrix) { bytes in
                Array(bytes.bindMemory(to: Double.self))
            }
            guard matrix.count == 16, matrix.allSatisfy(\.isFinite) else {
                return .failure(.invalidArgument("invalid Puppet bone matrix"))
            }
            output.append(.init(layerID: Int(raw.layer_id), boneIndex: Int(raw.bone_index), localSpace: raw.local_space != 0, matrix: matrix))
        }
        return .success(output)
    }
}

/// Keeps one callback owner's heterogeneous side effects together until the
/// frame transaction has admitted or rejected that owner. Destination layer,
/// effect, animation and video identities are not owner identities and must
/// never be used to reconstruct this relationship after flattening.
nonisolated struct SceneScriptOwnerEffects: Equatable, Sendable {
    let ownerTarget: SceneDynamicTarget
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let videoCommands: [SceneScriptVideoCommand]
    let textureAnimationCommands:
        [SceneTextureAnimationCommand]
    let puppetBoneMutations: [SceneScriptPuppetBoneMutation]

    init(
        ownerTarget: SceneDynamicTarget,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        videoCommands: [SceneScriptVideoCommand],
        textureAnimationCommands:
            [SceneTextureAnimationCommand] = [],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = []
    ) {
        self.ownerTarget = ownerTarget
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.videoCommands = videoCommands
        self.textureAnimationCommands = textureAnimationCommands
        self.puppetBoneMutations = puppetBoneMutations
    }

    var isEmpty: Bool {
        materialFunctionMutations.isEmpty && animationMutations.isEmpty
            && layerMutations.isEmpty && videoCommands.isEmpty
            && textureAnimationCommands.isEmpty
            && puppetBoneMutations.isEmpty
    }
}

nonisolated enum SceneScriptVideoCommandBridge {
    static func commands(
        owner: OpaquePointer
    ) -> Result<[SceneScriptVideoCommand], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_video_command_count(owner)
        guard count <= 64 else {
            return .failure(.mutationOverflow("video command buffer exceeded"))
        }
        var output: [SceneScriptVideoCommand] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSVideoCommand()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_video_command_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.layer_id >= Int64(Int.min),
                  raw.layer_id <= Int64(Int.max),
                  raw.number_value.isFinite,
                  raw.bool_value <= 1 else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let action: SceneScriptVideoCommand.Action
            switch raw.kind {
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_PLAY.rawValue):
                action = .play
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_PAUSE.rawValue):
                action = .pause
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_STOP.rawValue):
                action = .stop
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_SET_CURRENT_TIME.rawValue):
                action = .setCurrentTime(raw.number_value)
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_SET_RATE.rawValue):
                action = .setRate(raw.number_value)
            case UInt32(MWX_SCENE_QUICKJS_VIDEO_SET_LOOP.rawValue):
                action = .setLoop(raw.bool_value != 0)
            default:
                return .failure(.invalidArgument("unknown video command"))
            }
            output.append(.init(layerID: Int(raw.layer_id), action: action))
        }
        return .success(output)
    }
}

nonisolated enum SceneScriptTextureAnimationCommandBridge {
    static func commands(
        owner: OpaquePointer
    ) -> Result<
        [SceneTextureAnimationCommand],
        SceneScriptScalarRuntimeFailure
    > {
        let count = mwx_scene_quickjs_owner_texture_animation_command_count(
            owner
        )
        guard count <= 64 else {
            return .failure(.mutationOverflow(
                "texture animation command buffer exceeded"
            ))
        }
        var output: [SceneTextureAnimationCommand] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSTextureAnimationCommand()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_texture_animation_command_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.layer_id >= Int64(Int.min),
                  raw.layer_id <= Int64(Int.max),
                  raw.number_value.isFinite else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let action: SceneTextureAnimationCommand.Action
            switch raw.kind {
            case UInt32(MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PLAY.rawValue):
                action = .play
            case UInt32(MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_PAUSE.rawValue):
                action = .pause
            case UInt32(MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_STOP.rawValue):
                action = .stop
            case UInt32(
                MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_FRAME.rawValue
            ):
                action = .setFrame(raw.number_value)
            case UInt32(
                MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_SET_RATE.rawValue
            ):
                action = .setRate(raw.number_value)
            case UInt32(MWX_SCENE_QUICKJS_TEXTURE_ANIMATION_JOIN.rawValue):
                action = .join
            default:
                return .failure(.invalidArgument(
                    "unknown texture animation command"
                ))
            }
            output.append(.init(
                layerID: Int(raw.layer_id),
                action: action
            ))
        }
        return .success(output)
    }
}

nonisolated struct SceneScriptLayerMutation: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case upsert, destroy }

    struct Fields: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let origin = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ORIGIN.rawValue
        ))
        static let scale = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_SCALE.rawValue
        ))
        static let angles = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ANGLES.rawValue
        ))
        static let visibility = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_VISIBILITY.rawValue
        ))
        static let text = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_TEXT.rawValue
        ))
        static let font = Self(rawValue: UInt32(
            MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_FONT.rawValue
        ))
        static let authoredFields: Self = [
            .origin, .scale, .angles, .visibility, .text, .font, .alpha, .color,
        ]
        static let alpha = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_ALPHA.rawValue))
        static let color = Self(rawValue: UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_FIELD_COLOR.rawValue))
    }

    let kind: Kind
    let isDynamic: Bool
    let fields: Fields
    let layerID: Int
    let orderIndex: Int
    let visible: Bool
    let alpha: Double
    let origin: SIMD3<Double>
    let scale: SIMD3<Double>
    let angles: SIMD3<Double>
    let color: SIMD3<Double>
    let pointSize: Double
    let text: String
    let font: String
    let assetPath: String?
    let ownerTarget: SceneDynamicTarget?

    init(
        kind: Kind,
        isDynamic: Bool,
        fields: Fields,
        layerID: Int,
        orderIndex: Int,
        visible: Bool,
        alpha: Double,
        origin: SIMD3<Double>,
        scale: SIMD3<Double>,
        angles: SIMD3<Double>,
        color: SIMD3<Double>,
        pointSize: Double,
        text: String,
        font: String,
        assetPath: String?,
        ownerTarget: SceneDynamicTarget? = nil
    ) {
        self.kind = kind
        self.isDynamic = isDynamic
        self.fields = fields
        self.layerID = layerID
        self.orderIndex = orderIndex
        self.visible = visible
        self.alpha = alpha
        self.origin = origin
        self.scale = scale
        self.angles = angles
        self.color = color
        self.pointSize = pointSize
        self.text = text
        self.font = font
        self.assetPath = assetPath
        self.ownerTarget = ownerTarget
    }

    func owned(by target: SceneDynamicTarget) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: fields,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: assetPath, ownerTarget: target
        )
    }

    func resolvingAssetPath(to resolved: String) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: fields,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: resolved, ownerTarget: ownerTarget
        )
    }

    func selectingAuthoredFields(_ selected: Fields) -> Self {
        .init(
            kind: kind, isDynamic: isDynamic, fields: selected,
            layerID: layerID, orderIndex: orderIndex, visible: visible,
            alpha: alpha, origin: origin, scale: scale, angles: angles,
            color: color, pointSize: pointSize, text: text, font: font,
            assetPath: assetPath, ownerTarget: ownerTarget
        )
    }

    /// Coalesces repeated writes emitted by init/events/update for one owner.
    /// Dynamic upserts carry a complete current record, while authored writes
    /// retain untouched fields from the earlier mutation.
    static func coalescing(_ mutations: [Self]) -> [Self] {
        var indices: [Int: Int] = [:]
        var output: [Self] = []
        output.reserveCapacity(mutations.count)
        for mutation in mutations {
            if let index = indices[mutation.layerID] {
                output[index] = output[index].merging(with: mutation)
            } else {
                indices[mutation.layerID] = output.count
                output.append(mutation)
            }
        }
        return output
    }

    private func merging(with newer: Self) -> Self {
        guard kind != .destroy, kind == .upsert, newer.kind == .upsert,
              !isDynamic, !newer.isDynamic else {
            return kind == .destroy ? self : newer
        }
        let mergedFields = fields.union(newer.fields)
        return .init(
            kind: .upsert,
            isDynamic: false,
            fields: mergedFields,
            layerID: newer.layerID,
            orderIndex: newer.orderIndex,
            visible: newer.fields.contains(.visibility) ? newer.visible : visible,
            alpha: newer.fields.contains(.alpha) ? newer.alpha : alpha,
            origin: newer.fields.contains(.origin) ? newer.origin : origin,
            scale: newer.fields.contains(.scale) ? newer.scale : scale,
            angles: newer.fields.contains(.angles) ? newer.angles : angles,
            color: newer.fields.contains(.color) ? newer.color : color,
            pointSize: newer.pointSize,
            text: newer.fields.contains(.text) ? newer.text : text,
            font: newer.fields.contains(.font) ? newer.font : font,
            assetPath: newer.assetPath ?? assetPath,
            ownerTarget: newer.ownerTarget ?? ownerTarget
        )
    }
}

nonisolated enum SceneScriptLayerMutationBridge {
    // These limits mirror the lossless C DTO/QuickJS contracts. Keep the
    // validation at this ABI boundary so malformed native data cannot become
    // a permissive Swift mutation and then reach the shared frame plan.
    private static let maximumLayerIdentity: Int64 = 9_007_199_254_740_991
    private static let maximumTextBytes = 4_096
    private static let maximumFontBytes = 1_024
    private static let maximumAssetPathBytes = 1_024

    static func commit(owner: OpaquePointer) {
        mwx_scene_quickjs_owner_commit_layer_mutations(owner)
    }

    static func discard(owner: OpaquePointer) {
        mwx_scene_quickjs_owner_discard_layer_mutations(owner)
    }

    static func configure(owner: OpaquePointer, target: SceneDynamicTarget) throws {
        guard let layerID = layerID(for: target) else { return }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_owner_configure_layer_identity(
            owner, Int64(layerID), &diagnostic, diagnostic.count
        )
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
    }

    static func layerID(for target: SceneDynamicTarget) -> Int? {
        switch target {
        case let .layer(id, _), let .text(id, _), let .particle(id, _),
             let .effectConstant(id, _, _, _), let .effectVisibility(id, _),
             let .scriptInstanceProperty(id, _):
            id
        default:
            nil
        }
    }

    static func mutations(
        owner: OpaquePointer,
        ownerTarget: SceneDynamicTarget
    ) -> Result<[SceneScriptLayerMutation], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_layer_mutation_count(owner)
        guard count <= sceneScriptMaximumOwnerLayerMutations else {
            return .failure(.mutationOverflow("layer mutation buffer exceeded"))
        }
        // Owners without layer side effects are valid even when their target
        // belongs to a non-layer API family. Validate the identity only when
        // a DTO is actually being attached to the owner effect package.
        if count > 0 {
            guard let ownerLayerID = layerID(for: ownerTarget),
                  Int64(ownerLayerID) >= -maximumLayerIdentity,
                  Int64(ownerLayerID) <= maximumLayerIdentity else {
                return .failure(.invalidArgument(
                    "invalid layer mutation owner identity"
                ))
            }
        }
        var output: [SceneScriptLayerMutation] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSLayerMutation()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_layer_mutation_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.dynamic <= 1,
                  raw.visible <= 1,
                  raw.layer_id >= -maximumLayerIdentity,
                  raw.layer_id <= maximumLayerIdentity,
                  raw.order_index >= 0,
                  raw.alpha.isFinite, raw.point_size.isFinite,
                  raw.origin.0.isFinite, raw.origin.1.isFinite, raw.origin.2.isFinite,
                  raw.scale.0.isFinite, raw.scale.1.isFinite, raw.scale.2.isFinite,
                  raw.angles.0.isFinite, raw.angles.1.isFinite, raw.angles.2.isFinite,
                  raw.color.0.isFinite, raw.color.1.isFinite,
                  raw.color.2.isFinite,
                  let textPointer = raw.text, let fontPointer = raw.font,
                  let assetPathPointer = raw.asset_path else {
                return .failure(.invalidArgument(
                    String(cString: diagnostic).isEmpty
                        ? "invalid layer mutation ABI"
                        : String(cString: diagnostic)
                ))
            }
            let kind: SceneScriptLayerMutation.Kind
            switch raw.kind {
            case UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_UPSERT.rawValue):
                kind = .upsert
            case UInt32(MWX_SCENE_QUICKJS_LAYER_MUTATION_DESTROY.rawValue):
                kind = .destroy
            default:
                // Never silently reinterpret a future/invalid enum value as
                // an upsert.
                return .failure(.invalidArgument("unknown layer mutation kind"))
            }
            let fields = SceneScriptLayerMutation.Fields(rawValue: raw.fields)
            guard raw.fields & ~SceneScriptLayerMutation.Fields.authoredFields.rawValue == 0 else {
                return .failure(.invalidArgument("unknown layer mutation fields"))
            }
            if raw.dynamic == 1 {
                guard (0...1).contains(raw.alpha),
                      (1...1024).contains(raw.point_size),
                      (0...1).contains(raw.color.0),
                      (0...1).contains(raw.color.1),
                      (0...1).contains(raw.color.2) else {
                    return .failure(.invalidArgument(
                        "invalid dynamic layer mutation range"
                    ))
                }
            }
            switch (kind, raw.dynamic, raw.fields) {
            case (.destroy, 0, 0), (.destroy, 1, 0), (.upsert, 1, 0):
                break
            case (.upsert, 0, _)
                where !fields.isEmpty && fields.isSubset(of: .authoredFields):
                break
            default:
                return .failure(.invalidArgument(
                    "layer mutation kind/dynamic/fields ABI mismatch"
                ))
            }
            let text = String(cString: textPointer)
            let font = String(cString: fontPointer)
            let assetPath = String(cString: assetPathPointer)
            guard text.utf8.count <= maximumTextBytes,
                  font.utf8.count <= maximumFontBytes,
                  assetPath.utf8.count <= maximumAssetPathBytes else {
                return .failure(.invalidArgument("layer mutation string exceeds ABI limit"))
            }
            output.append(.init(
                kind: kind,
                isDynamic: raw.dynamic != 0, fields: fields,
                layerID: Int(raw.layer_id), orderIndex: Int(raw.order_index),
                visible: raw.visible != 0, alpha: raw.alpha,
                origin: .init(raw.origin.0, raw.origin.1, raw.origin.2),
                scale: .init(raw.scale.0, raw.scale.1, raw.scale.2),
                angles: .init(
                    SceneScriptAngleUnits.radians(fromDegrees: raw.angles.0),
                    SceneScriptAngleUnits.radians(fromDegrees: raw.angles.1),
                    SceneScriptAngleUnits.radians(fromDegrees: raw.angles.2)
                ),
                color: .init(raw.color.0, raw.color.1, raw.color.2),
                pointSize: raw.point_size,
                text: text, font: font,
                assetPath: assetPath.nilIfEmpty,
                ownerTarget: ownerTarget
            ))
        }
        return .success(output)
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Publishes the existing frame snapshot into the callback-scoped SceneScript
/// handle projection. This is not a second property store: launch-stable
/// identity, parent, authored size and authored origins come from the prepared
/// descriptor; every frame overlays only resolved current values.
nonisolated extension SceneScriptQuickJSDomain {
    /// Launch-stable catalog identity: index, id, parent, name, authored
    /// transforms, size and text mutability of every descriptor layer. This
    /// signature is only built at load/configuration time; the per-frame
    /// snapshot path compares the launch-frozen token instead of rescanning
    /// the catalog.
    nonisolated static func catalogSignature(
        for descriptor: SceneRenderDescriptor
    ) -> String {
        let camera = descriptor.camera.orthoHeight.map { String($0) }
            ?? "perspective"
        let layers = descriptor.layers.enumerated().map { index, layer in
            let origin = layer.originXYZ ?? [0, 0, 0]
            let scale = layer.scaleXYZ ?? [1, 1, 1]
            let angles = layer.anglesXYZ ?? [0, 0, 0]
            let size = layer.sizeWH ?? [0, 0]
            let attachment = layer.parentAttachmentBindFrame ?? []
            let textMutable = layer.contentKind == "text"
                && layer.text != nil && layer.textStyle != nil
            return "\(index):\(layer.id):\(layer.parentID.map(String.init) ?? "root"):\(layer.name ?? ""):\(origin):\(scale):\(angles):size=\(size):attachment=\(attachment):text=\(textMutable)"
        }.joined(separator: "|")
        return "camera=\(camera)|\(layers)"
    }

    func configureLayerCatalog(_ descriptor: SceneRenderDescriptor) throws {
        let layerIDs = Set(descriptor.layers.map(\.id))
        guard descriptor.layers.count <= 4096,
              layerIDs.count == descriptor.layers.count,
              descriptor.layers.allSatisfy({ layer in
                  let layerID = Int64(layer.id)
                  let parentID = layer.parentID.map(Int64.init)
                  let validOrigin = layer.originXYZ.map {
                      $0.count == 3 && $0.allSatisfy(\.isFinite)
                  } ?? true
                  let validSize = layer.sizeWH.map {
                      $0.count == 2
                        && $0.allSatisfy { $0.isFinite && $0 >= 0 }
                  } ?? true
                  return layerID >= -9_007_199_254_740_991
                    && layerID <= 9_007_199_254_740_991
                    && parentID.map {
                        $0 >= -9_007_199_254_740_991
                            && $0 <= 9_007_199_254_740_991
                            && $0 != layerID
                            && layerIDs.contains(Int($0))
                    } ?? true
                    && (layer.name?.utf8.count ?? 0) <= 256
                    && !(layer.name?.contains("\0") ?? false)
                    && validOrigin
                    && validSize
              }) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer catalog exceeds its identity contract"
            )
        }
        let signature = Self.catalogSignature(for: descriptor)
        if let configured = layerCatalogSignature {
            guard configured == signature,
                  layerWorldTransformProjection?.catalogSignature
                    == signature else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer catalog identity changed"
                )
            }
            return
        }

        guard let worldTransformProjection =
                SceneScriptLayerWorldTransformProjection(
                    descriptor: descriptor,
                    catalogSignature: signature
                ) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer world transform preparation failed"
            )
        }

        var diagnostic = [CChar](repeating: 0, count: 512)
        guard mwx_scene_quickjs_domain_configure_layer_catalog(
            handle,
            UInt32(descriptor.layers.count),
            &diagnostic,
            diagnostic.count
        ) == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                Self.layerDiagnostic(diagnostic)
            )
        }
        for (index, layer) in descriptor.layers.enumerated() {
            let name = layer.name ?? ""
            let authored = layer.originXYZ ?? [0, 0, 0]
            let origin = authored.map(Double.init)
            let authoredSize = layer.sizeWH ?? [0, 0]
            let size = authoredSize.map(Double.init)
            let result = name.withCString { namePointer in
                origin.withUnsafeBufferPointer { originPointer in
                    size.withUnsafeBufferPointer { sizePointer in
                        mwx_scene_quickjs_domain_set_layer_descriptor(
                            handle, UInt32(index), Int64(layer.id),
                            layer.parentID == nil ? 0 : 1,
                            Int64(layer.parentID ?? 0),
                            namePointer, name.utf8.count,
                            originPointer.baseAddress,
                            sizePointer.baseAddress,
                            &diagnostic, diagnostic.count
                        )
                    }
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    Self.layerDiagnostic(diagnostic)
                )
            }
            let capabilityResult =
                mwx_scene_quickjs_domain_set_layer_mutation_capabilities(
                    handle,
                    UInt32(index),
                    layer.contentKind == "text" && layer.text != nil
                        && layer.textStyle != nil ? 1 : 0,
                    &diagnostic,
                    diagnostic.count
                )
            guard capabilityResult == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    Self.layerDiagnostic(diagnostic)
                )
            }
        }
        layerCatalogSignature = signature
        layerWorldTransformProjection = worldTransformProjection
    }

    func publishLayerSnapshot(
        _ snapshot: SceneDynamicSnapshot,
        descriptor: SceneRenderDescriptor,
        videoSnapshots: [Int: SceneScriptVideoPlaybackSnapshot] = [:],
        textureAnimationSnapshots: [
            Int: SceneTextureAnimationSnapshot
        ] = [:],
        destroyedAuthoredLayerIDs: Set<Int> = [], catalogToken: String? = nil,
        runtimeFieldLayerIDs: Set<Int>? = nil,
        awaitingHostFrameOutcome: Bool = false
    ) throws {
        if let catalogToken {
            guard let configured = layerCatalogSignature else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer catalog not configured"
                )
            }
            guard configured == catalogToken else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    "SceneScript layer catalog identity changed"
                )
            }
        } else {
            try configureLayerCatalog(descriptor)
        }
        guard layerSnapshotGeneration < UInt64.max else {
            throw SceneScriptScalarRuntimeFailure.staleOwner
        }
        let pendingGeneration = layerSnapshotGeneration + 1
        var diagnostic = [CChar](repeating: 0, count: 512)
        let beginResult = mwx_scene_quickjs_domain_begin_layer_snapshot(
            handle,
            pendingGeneration,
            &diagnostic,
            diagnostic.count
        )
        guard beginResult == MWX_SCENE_QUICKJS_OK else {
            throw layerSnapshotFailure(beginResult, diagnostic: diagnostic)
        }
        var committed = false
        defer {
            if !committed {
                mwx_scene_quickjs_domain_abort_layer_snapshot(handle)
            }
        }
        try publishLayerRuntimeFields(
            snapshot,
            descriptor: descriptor,
            videoSnapshots: videoSnapshots,
            textureAnimationSnapshots: textureAnimationSnapshots, destroyedAuthoredLayerIDs: destroyedAuthoredLayerIDs,
            runtimeFieldLayerIDs: runtimeFieldLayerIDs,
            diagnostic: &diagnostic
        )
        guard let worldTransformProjection = layerWorldTransformProjection,
              worldTransformProjection.catalogSignature
                == layerCatalogSignature else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer world transform projection is stale"
            )
        }
        let dynamicTransformIDs = snapshot.dynamicTransformLayerIDsForFrame
        if layerSnapshotGeneration == 0 || !dynamicTransformIDs.isEmpty
            || !committedDynamicWorldTransformLayerIDs.isEmpty {
            try publishLayerWorldTransforms(
                worldTransformProjection.worldFrames(for: snapshot),
                descriptor: descriptor,
                diagnostic: &diagnostic
            )
        }
        for (index, layer) in descriptor.layers.enumerated() {
            guard let resolved = snapshot[.layer(layerID: layer.id, field: .origin)],
                  case let .vector3(x, y, z) = resolved.value,
                  x.isFinite, y.isFinite, z.isFinite else { continue }
            let origin = [x, y, z]
            let result = origin.withUnsafeBufferPointer { pointer in
                mwx_scene_quickjs_domain_set_layer_origin(
                    handle,
                    UInt32(index),
                    pointer.baseAddress,
                    &diagnostic,
                    diagnostic.count
                )
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw layerSnapshotFailure(result, diagnostic: diagnostic)
            }
        }
        let commitResult = mwx_scene_quickjs_domain_commit_layer_snapshot(
            handle,
            &diagnostic,
            diagnostic.count
        )
        guard commitResult == MWX_SCENE_QUICKJS_OK else {
            throw layerSnapshotFailure(commitResult, diagnostic: diagnostic)
        }
        rollbackDynamicWorldTransformLayerIDs =
            committedDynamicWorldTransformLayerIDs
        committedDynamicWorldTransformLayerIDs = dynamicTransformIDs
        layerSnapshotGeneration = pendingGeneration
        committed = true
        if !awaitingHostFrameOutcome {
            finalizeCommittedLayerSnapshot()
        }
    }

    func layerSnapshotFailure(
        _ result: MWXSceneQuickJSResult,
        diagnostic buffer: [CChar]
    ) -> SceneScriptScalarRuntimeFailure {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let diagnostic = String(decoding: bytes, as: UTF8.self)
        return result == MWX_SCENE_QUICKJS_MEMORY_EXCEEDED
            ? .memoryExceeded(diagnostic)
            : .invalidArgument(diagnostic)
    }

    private static func layerDiagnostic(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
