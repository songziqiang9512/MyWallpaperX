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

nonisolated struct SceneScriptMediaPlaybackCommand: Equatable, Sendable {
    enum Destination: Equatable, Sendable { case videoTexture, soundLayer }
    enum Action: Equatable, Sendable {
        case play
        case pause
        case stop
        case setCurrentTime(TimeInterval)
        case setRate(Double)
        case setLoop(Bool)
    }

    let destination: Destination
    let layerID: Int
    let action: Action

    init(layerID: Int, action: Action, destination: Destination = .videoTexture) {
        self.destination = destination
        self.layerID = layerID
        self.action = action
    }
}

nonisolated struct SceneScriptPuppetBoneMutation: Equatable, Sendable {
    let layerID: Int
    let boneIndex: Int
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
                  raw.bone_index < 256 else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let matrix = withUnsafeBytes(of: raw.matrix) { bytes in
                Array(bytes.bindMemory(to: Double.self))
            }
            guard matrix.count == 16, matrix.allSatisfy(\.isFinite) else {
                return .failure(.invalidArgument("invalid Puppet bone matrix"))
            }
            output.append(.init(layerID: Int(raw.layer_id), boneIndex: Int(raw.bone_index), matrix: matrix))
        }
        return .success(output)
    }
}

/// Keeps one callback owner's heterogeneous side effects together until the
/// frame transaction has admitted or rejected that owner. Destination layer,
/// effect, animation and video identities are not owner identities and must
/// never be used to reconstruct this relationship after flattening.
nonisolated struct SceneScriptParticlePlaybackCommand: Equatable, Sendable {
    let layerID: Int
    let action: SceneParticlePlaybackAction
    let callbackEpoch: UInt64
    let ordinal: UInt32
    var count: Int = 0
}

nonisolated struct SceneScriptOwnerEffects: Equatable, Sendable {
    let ownerTarget: SceneDynamicTarget
    /// Prepared source identity retained when a layer owner publishes camera origin.
    let sourceLayerID: Int?
    var materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    var animationMutations: [SceneTimelinePlaybackMutation]
    var layerMutations: [SceneScriptLayerMutation]
    var mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand]
    var textureAnimationCommands:
        [SceneTextureAnimationCommand]
    var puppetBoneMutations: [SceneScriptPuppetBoneMutation]
    var puppetAnimationCommands: [ScenePuppetAnimationCommand]
    var puppetAnimationCallbackRegistrations: Int
    var particlePlaybackCommands: [SceneScriptParticlePlaybackCommand]
    var layerTopologyOwnerIdentity: UInt64?

    init(
        ownerTarget: SceneDynamicTarget,
        sourceLayerID: Int? = nil,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand],
        textureAnimationCommands:
            [SceneTextureAnimationCommand] = [],
        puppetBoneMutations: [SceneScriptPuppetBoneMutation] = [],
        particlePlaybackCommands: [SceneScriptParticlePlaybackCommand] = [],
        puppetAnimationCommands: [ScenePuppetAnimationCommand] = [],
        puppetAnimationCallbackRegistrations: Int = 0,
        layerTopologyOwnerIdentity: UInt64? = nil
    ) {
        self.layerTopologyOwnerIdentity = layerTopologyOwnerIdentity
        self.puppetAnimationCommands = puppetAnimationCommands
        self.puppetAnimationCallbackRegistrations = puppetAnimationCallbackRegistrations
        self.ownerTarget = ownerTarget
        self.sourceLayerID = sourceLayerID
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.mediaPlaybackCommands = mediaPlaybackCommands
        self.textureAnimationCommands = textureAnimationCommands
        self.particlePlaybackCommands = particlePlaybackCommands
        self.puppetBoneMutations = puppetBoneMutations
    }

    var isEmpty: Bool {
        materialFunctionMutations.isEmpty && animationMutations.isEmpty
            && layerMutations.isEmpty && mediaPlaybackCommands.isEmpty
            && textureAnimationCommands.isEmpty
            && puppetBoneMutations.isEmpty && particlePlaybackCommands.isEmpty
            && puppetAnimationCommands.isEmpty && puppetAnimationCallbackRegistrations == 0
            && layerTopologyOwnerIdentity == nil
    }
}

nonisolated enum SceneScriptParticlePlaybackCommandBridge {
    static func commands(owner: OpaquePointer) -> Result<[SceneScriptParticlePlaybackCommand], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_particle_playback_command_count(owner)
        guard count <= 64 else { return .failure(.mutationOverflow("particle playback command budget exceeded")) }
        var commands: [SceneScriptParticlePlaybackCommand] = []
        for index in 0..<count {
            var raw = MWXSceneQuickJSParticlePlaybackCommand()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_particle_playback_command_at(owner, index, &raw, &diagnostic, diagnostic.count)
            if result == MWX_SCENE_QUICKJS_MUTATION_OVERFLOW {
                return .failure(.mutationOverflow(String(cString: diagnostic)))
            }
            guard result == MWX_SCENE_QUICKJS_OK, let layerID = Int(exactly: raw.layer_id),
                  (raw.action <= 2 || raw.action == 4), let action = SceneParticlePlaybackAction(rawValue: Int32(raw.action)) else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            commands.append(.init(layerID: layerID, action: action, callbackEpoch: raw.callback_epoch, ordinal: raw.ordinal, count: Int(raw.count)))
        }
        return .success(commands)
    }
}

nonisolated enum SceneScriptMediaPlaybackCommandBridge {
    static func commands(
        owner: OpaquePointer
    ) -> Result<[SceneScriptMediaPlaybackCommand], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_media_playback_command_count(owner)
        guard count <= 64 else {
            return .failure(.mutationOverflow("media playback command buffer exceeded"))
        }
        var output: [SceneScriptMediaPlaybackCommand] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            var raw = MWXSceneQuickJSMediaPlaybackCommand()
            var diagnostic = [CChar](repeating: 0, count: 512)
            let result = mwx_scene_quickjs_owner_media_playback_command_at(
                owner, index, &raw, &diagnostic, diagnostic.count
            )
            guard result == MWX_SCENE_QUICKJS_OK,
                  raw.layer_id >= Int64(Int.min),
                  raw.layer_id <= Int64(Int.max),
                  raw.number_value.isFinite,
                  raw.bool_value <= 1 else {
                return .failure(.invalidArgument(String(cString: diagnostic)))
            }
            let destination: SceneScriptMediaPlaybackCommand.Destination
            switch raw.destination {
            case 0: destination = .videoTexture
            case 1: destination = .soundLayer
            default: return .failure(.invalidArgument("unknown media playback destination"))
            }
            let action: SceneScriptMediaPlaybackCommand.Action
            switch raw.kind {
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_PLAY.rawValue):
                action = .play
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_PAUSE.rawValue):
                action = .pause
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_STOP.rawValue):
                action = .stop
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_SET_CURRENT_TIME.rawValue):
                action = .setCurrentTime(raw.number_value)
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_SET_RATE.rawValue):
                action = .setRate(raw.number_value)
            case UInt32(MWX_SCENE_QUICKJS_MEDIA_SET_LOOP.rawValue):
                action = .setLoop(raw.bool_value != 0)
            default:
                return .failure(.invalidArgument("unknown media playback command"))
            }
            output.append(.init(layerID: Int(raw.layer_id), action: action, destination: destination))
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

nonisolated enum SceneScriptLayerMutationBridge {
    static func configureDynamicImageAliases(
        owner: OpaquePointer, paths: [String: String]
    ) throws {
        var diagnostic = [CChar](repeating: 0, count: 512)
        for (authored, model) in paths.sorted(by: { $0.key < $1.key }) {
            let result = authored.withCString { authoredPath in
                model.withCString { modelPath in
                    mwx_scene_quickjs_owner_add_dynamic_image_alias(owner,
                        authoredPath, authored.utf8.count, modelPath, model.utf8.count,
                        &diagnostic, diagnostic.count)
                }
            }
            guard result == MWX_SCENE_QUICKJS_OK else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument(
                    String(cString: diagnostic).isEmpty
                        ? "invalid prepared dynamic image alias" : String(cString: diagnostic))
            }
        }
    }

    // These limits mirror the lossless C DTO/QuickJS contracts. Keep the
    // validation at this ABI boundary so malformed native data cannot become
    // a permissive Swift mutation and then reach the shared frame plan.
    private static let maximumLayerIdentity: Int64 = 9_007_199_254_740_991
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
             let .materialConstant(id, _, _, _),
             let .scriptInstanceProperty(id, _):
            id
        default:
            nil
        }
    }

    /// A layer or text property belongs to the layer itself, so the script's
    /// `thisObject` is that layer's own object. Effect, particle and material
    /// properties belong to their component and keep the property-object
    /// handle that serves `IThisPropertyObject.getAnimation`.
    static func propertyObjectIsLayer(_ target: SceneDynamicTarget) -> Bool {
        switch target {
        case .layer, .text: true
        default: false
        }
    }

    /// Effect-visibility targets stage `thisObject.visible` writes on the
    /// property-object handle; the configure call defines that accessor and
    /// records the (layer, effect) identity the staged value publishes to.
    /// `seedVisible` is the binding's authored `visible` seed - the getter's
    /// read default before any staged write. Distinct from the snapshot seed,
    /// which carries the load-prepared state.
    static func configureEffectVisibilityTarget(
        owner: OpaquePointer, target: SceneDynamicTarget, seedVisible: Bool
    ) throws {
        guard case let .effectVisibility(layerID, effectIndex) = target else {
            return
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = mwx_scene_quickjs_owner_configure_effect_visibility_target(
            owner,
            Int64(layerID),
            Int64(effectIndex),
            seedVisible,
            &diagnostic,
            diagnostic.count
        )
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                String(cString: diagnostic)
            )
        }
    }

    static func mutations(
        owner: OpaquePointer,
        ownerTarget: SceneDynamicTarget,
        sourceLayerID: Int? = nil
    ) -> Result<[SceneScriptLayerMutation], SceneScriptScalarRuntimeFailure> {
        let count = mwx_scene_quickjs_owner_layer_mutation_count(owner)
        guard count <= sceneScriptMaximumOwnerLayerMutations else {
            return .failure(.mutationOverflow("layer mutation buffer exceeded"))
        }
        // Owners without layer side effects are valid even when their target
        // belongs to a non-layer API family. Validate the identity only when
        // a DTO is actually being attached to the owner effect package.
        if count > 0 {
            let ownerLayerID = ownerTarget == .camera(.origin)
                ? sourceLayerID : layerID(for: ownerTarget)
            guard let ownerLayerID,
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
                  raw.visible <= 1, raw.solid <= 1, raw.perspective <= 2,
                  raw.size_available <= 1,
                  raw.size_available == 0 || (raw.dynamic == 1 &&
                    raw.size.0.isFinite && raw.size.1.isFinite &&
                    raw.size.0 > 0 && raw.size.1 > 0 &&
                    raw.size.0 <= Double(Float.greatestFiniteMagnitude) &&
                    raw.size.1 <= Double(Float.greatestFiniteMagnitude)),
                  raw.layer_id >= -maximumLayerIdentity,
                  raw.layer_id <= maximumLayerIdentity,
                  raw.order_index >= 0,
                  raw.alpha.isFinite, raw.particle_alpha.isFinite, raw.point_size.isFinite,
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
            guard !fields.contains(.perspective) || raw.perspective <= 1 else {
                return .failure(.invalidArgument("invalid perspective mutation ABI"))
            }
            guard raw.fields & ~SceneScriptLayerMutation.Fields.authoredFields.rawValue == 0 else {
                return .failure(.invalidArgument("unknown layer mutation fields"))
            }
            if raw.dynamic == 1 {
                guard (0...1).contains(raw.alpha),
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
            case (.upsert, 1, _) where fields.isSubset(of: [.text, .pointSize]):
                break
            case (.upsert, 0, 0):
                // An order-only authored mutation: the script sorted this
                // authored layer and the record carries the new order index.
                break
            case (.upsert, 0, _)
                where !fields.isEmpty && fields.isSubset(of: .authoredFields):
                break
            default:
                return .failure(.invalidArgument(
                    "layer mutation kind/dynamic/fields ABI mismatch"
                ))
            }
            guard raw.effect_count <= 1024,
                  (raw.effect_count > 0) == fields.contains(.effectVisibility),
                  raw.effect_count == 0 || raw.effect_visible != nil else {
                return .failure(.invalidArgument("invalid effect visibility mutation ABI"))
            }
            var effectVisibilities: [Int: Bool] = [:]
            for effectIndex in 0..<Int(raw.effect_count) {
                let value = raw.effect_visible![effectIndex]
                guard value <= 2 else { return .failure(.invalidArgument("invalid effect visibility value")) }
                if value < 2 { effectVisibilities[effectIndex] = value != 0 }
            }
            let text = String(cString: textPointer)
            let font = String(cString: fontPointer)
            let assetPath = String(cString: assetPathPointer)
            guard raw.dynamic == 0 || fields.intersection([.text, .pointSize]).isEmpty || assetPath.isEmpty else {
                return .failure(.invalidArgument("dynamic text field requires a text layer"))
            }
            guard SceneScriptLayerMutation.acceptsDynamicText(text),
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
                ownerTarget: ownerTarget, effectVisibilities: effectVisibilities, solid: raw.solid != 0,
                particleAlpha: raw.particle_alpha,
                perspective: raw.perspective == 2 ? nil : raw.perspective != 0,
                size: raw.size_available == 0 ? nil : .init(raw.size.0, raw.size.1),
                textTemplateIdentity: raw.text_template_identity
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
    ) throws -> String {
        let camera = descriptor.camera.orthoHeight.map { String($0) }
            ?? "perspective"
        let layers = try descriptor.layers.enumerated().map { index, layer in
            let origin = layer.originXYZ ?? [0, 0, 0]
            let scale = layer.scaleXYZ ?? [1, 1, 1]
            let angles = layer.anglesXYZ ?? [0, 0, 0]
            let size = layer.sizeWH ?? [0, 0]
            let attachment = layer.parentAttachmentBindFrame ?? []
            let effectIdentity = layer.effects.map { [$0.id, $0.name ?? ""] }
            let textMutable = layer.contentKind == "text"
                && layer.text != nil && layer.textStyle != nil
            return "\(index):\(layer.id):\(layer.parentID.map(String.init) ?? "root"):\(layer.name ?? ""):\(origin):\(scale):\(angles):size=\(size):perspective=\(layer.usesPerspective.map(String.init) ?? "inherit"):attachment=\(attachment):text=\(textMutable):effects=\(effectIdentity):initial=\(try initialConfigurationJSON(layer) ?? "unavailable")"
        }.joined(separator: "|")
        return "camera=\(camera)|\(layers)"
    }

    private static func initialConfigurationJSON(
        _ layer: SceneRenderDescriptor.Layer
    ) throws -> String? {
        guard let configuration = layer.initialConfiguration else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(configuration), as: UTF8.self)
    }

    func configureDynamicImageCatalog(
        _ templates: [String: SceneScriptDynamicImageLayerTemplate]
    ) throws {
        if let configured = dynamicImageCatalog {
            guard configured == templates else {
                throw SceneScriptScalarRuntimeFailure.invalidArgument("dynamic image catalog identity changed")
            }
            return
        }
        guard templates.count <= 4096,
              templates.allSatisfy({ key, value in
                  key == value.modelPath.lowercased() && value.renderSizeWH.count == 2 &&
                    value.renderSizeWH.allSatisfy { $0.isFinite && $0 > 0 }
              }) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument("invalid dynamic image catalog")
        }
        let entries = templates.sorted { $0.key < $1.key }
        let paths = entries.map { $0.value.modelPath.withCString { strdup($0) } }
        defer { paths.forEach { free($0) } }
        guard paths.allSatisfy({ $0 != nil }) else {
            throw SceneScriptScalarRuntimeFailure.memoryExceeded("dynamic image catalog paths")
        }
        let descriptors = entries.enumerated().map { index, entry in
            MWXSceneQuickJSDynamicImageDescriptor(
                model_path: UnsafePointer(paths[index]!),
                model_path_length: entry.value.modelPath.utf8.count,
                natural_size: (Double(entry.value.renderSizeWH[0]), Double(entry.value.renderSizeWH[1])),
                autosize: entry.value.autosize ? 1 : 0,
                uses_puppet: entry.value.puppetMeshPath != nil ? 1 : 0)
        }
        var diagnostic = [CChar](repeating: 0, count: 512)
        let result = descriptors.withUnsafeBufferPointer { buffer in
            mwx_scene_quickjs_domain_configure_dynamic_image_catalog(
                handle, UInt32(buffer.count), buffer.baseAddress, &diagnostic, diagnostic.count)
        }
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw layerSnapshotFailure(result, diagnostic: diagnostic)
        }
        dynamicImageCatalog = templates
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
                    && layer.effects.count <= 1024
                    && layer.effects.allSatisfy { ($0.name?.utf8.count ?? 0) <= 256 && !($0.name?.contains("\0") ?? false) }
                    && validOrigin
                    && validSize
              }) else {
            throw SceneScriptScalarRuntimeFailure.invalidArgument(
                "SceneScript layer catalog exceeds its identity contract"
            )
        }
        let signature = try Self.catalogSignature(for: descriptor)
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
            worldTransformProjection.defaultsToPerspective(for: .empty(frameIndex: 0)) ? 1 : 0,
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
            if let configuration = try Self.initialConfigurationJSON(layer) {
                let status = configuration.withCString { json in
                    mwx_scene_quickjs_domain_set_layer_initial_configuration(
                        handle, UInt32(index), json, configuration.utf8.count,
                        &diagnostic, diagnostic.count
                    )
                }
                guard status == MWX_SCENE_QUICKJS_OK else {
                    throw layerSnapshotFailure(status, diagnostic: diagnostic)
                }
            }
            let effectNames: [UnsafeMutablePointer<CChar>?] = layer.effects.map { effect in
                effect.name.map { name in name.withCString { strdup($0) } } ?? nil
            }
            defer { effectNames.forEach { free($0) } }
            guard zip(layer.effects, effectNames).allSatisfy({ $0.0.name == nil || $0.1 != nil }) else {
                throw SceneScriptScalarRuntimeFailure.memoryExceeded("effect catalog names")
            }
            let effectPointers: [UnsafePointer<CChar>?] = effectNames.map { pointer in pointer.map { UnsafePointer($0) } }
            let effectValues: [UInt8] = layer.effects.map { ($0.visible ?? true) ? 1 : 0 }
            let effectsResult = effectPointers.withUnsafeBufferPointer { names in
                effectValues.withUnsafeBufferPointer { values in
                    mwx_scene_quickjs_domain_configure_layer_effects(handle, UInt32(index),
                        UInt32(layer.effects.count), names.baseAddress, values.baseAddress)
                }
            }
            guard effectsResult == MWX_SCENE_QUICKJS_OK else {
                throw layerSnapshotFailure(effectsResult, diagnostic: diagnostic)
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
        dynamicImageAvailableModelPaths = descriptor.modelMaterialLinks.map(\.modelPath)
        layerCatalogSignature = signature
        layerWorldTransformProjection = worldTransformProjection
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


private nonisolated func sceneScriptParticleEmissionHost(
    _ opaque: UnsafeMutableRawPointer?, _ owner: OpaquePointer?,
    _ command: UnsafePointer<MWXSceneQuickJSParticlePlaybackCommand>?,
    _ projection: UnsafeMutablePointer<MWXSceneQuickJSParticlePlaybackState>?
) -> MWXSceneQuickJSResult {
    guard let opaque, let owner, let command, let projection else { return MWX_SCENE_QUICKJS_STALE_OWNER }
    let domain = Unmanaged<SceneScriptQuickJSDomain>.fromOpaque(opaque).takeUnretainedValue()
    guard let host = domain.particleEmissionHost else { return MWX_SCENE_QUICKJS_STALE_OWNER }
    do {
        let value = try host(owner, command.pointee)
        projection.pointee = .init(available: 1, live: value.liveAny ? 1 : 0,
            emission_pending: value.emissionPending ? 1 : 0,
            rearm_has_work: value.rearmHasWork ? 1 : 0,
            intent: UInt32(value.intent.rawValue), revision: value.revision)
        return MWX_SCENE_QUICKJS_OK
    } catch let failure as SceneScriptScalarRuntimeFailure {
        switch failure {
        case .budgetExceeded: return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED
        case .staleOwner: return MWX_SCENE_QUICKJS_STALE_OWNER
        default: return MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        }
    } catch let failure as SceneParticleEmissionFailure {
        switch failure {
        case .budgetExceeded: return MWX_SCENE_QUICKJS_BUDGET_EXCEEDED
        case .staleIdentity: return MWX_SCENE_QUICKJS_STALE_OWNER
        case .unavailable: return MWX_SCENE_QUICKJS_INVALID_ARGUMENT
        }
    } catch { return MWX_SCENE_QUICKJS_INVALID_ARGUMENT }
}

private nonisolated func sceneScriptParticleBoundary(
    _ opaque: UnsafeMutableRawPointer?, _ owner: OpaquePointer?, _ discard: UInt32
) {
    guard let opaque, let owner else { return }
    let domain = Unmanaged<SceneScriptQuickJSDomain>.fromOpaque(opaque).takeUnretainedValue()
    domain.particleEmissionBoundary?(owner, discard != 0)
}

extension SceneScriptQuickJSDomain {
    func beginParticlePlaybackFrame(
        onBoundary: @escaping (OpaquePointer, Bool) -> Void,

        host: @escaping (OpaquePointer, MWXSceneQuickJSParticlePlaybackCommand) throws -> SceneParticlePlaybackObservation
    ) {
        precondition(particleEmissionHost == nil)
        particleEmissionHost = host
        particleEmissionBoundary = onBoundary
        mwx_scene_quickjs_domain_begin_particle_frame(handle, sceneScriptParticleEmissionHost, sceneScriptParticleBoundary,
            Unmanaged.passUnretained(self).toOpaque(), budget.interruptBudget, budget.maximumNativeTransientBytes)
    }
    func endParticlePlaybackFrame() {
        particleEmissionHost = nil
        particleEmissionBoundary = nil
        mwx_scene_quickjs_domain_end_particle_frame(handle)
    }
    func chargeParticleWork(_ work: UInt64, bytes: Int) throws {
        guard bytes >= 0 else { throw SceneScriptScalarRuntimeFailure.staleOwner }
        let result = mwx_scene_quickjs_domain_particle_charge(handle, work, bytes)
        guard result == MWX_SCENE_QUICKJS_OK else {
            throw SceneScriptScalarRuntimeFailure.budgetExceeded("particle native cadence budget or cancellation")
        }
    }
    func releaseParticleStorage(_ bytes: Int) {
        mwx_scene_quickjs_domain_particle_release(handle, bytes)
    }
}
