import Foundation
import Metal

/// Immutable launch-prepared resources for direct `objects[].model` layers.
/// Geometry production joins the existing renderer/main pass; this type owns
/// no command queue, frame target, compositor, or mutable playback state.
struct ScenePreparedStaticModelResources {
    enum FutureVisibilityFailure: Equatable {
        case selection(ScenePuppetAnimationSelectionFailure)
        case evaluation(ScenePuppetAnimationEvaluationFailure)
    }

    /// Immutable preparation shared by instances. Playback and vertex storage
    /// are allocated by the existing surface-owned Puppet state.
    struct Animation {
        let vertices: [SceneMdlStaticModel.Vertex]
        let selection: ScenePuppetAnimationSelection
        let evaluator: ScenePuppetAnimationEvaluator
        let attachments: [SceneMdlPuppetAttachment]
        let initialBones: ScenePuppetLayerLoad.BoneConfiguration?
        let futureVisibilityFailure: FutureVisibilityFailure?
    }

    private struct AnimationAsset {
        let model: SceneMdlStaticModel
        let animations: Result<SceneMdlPuppetAnimationSet?, Error>
        let attachments: Result<[SceneMdlPuppetAttachment], Error>
    }

    struct Entry {
        let modelPath: String
        let materialPath: String
        let dynamicMaterialPath: String
        let mesh: SceneStaticModelMesh
        let albedo: SceneTextureCandidate?
        let namedAlbedo: SceneNamedTextureReference?
        let emissiveMask: SceneTextureCandidate?
        let material: SceneStaticModelMaterial
        let writesDepth: Bool
        let materialBlending: SceneMaterialRenderState.Blending?
        let geometryState: SceneMdlStaticModel.GeometryState

        init(
            modelPath: String, materialPath: String, dynamicMaterialPath: String,
            mesh: SceneStaticModelMesh, albedo: SceneTextureCandidate?,
            namedAlbedo: SceneNamedTextureReference?, emissiveMask: SceneTextureCandidate?,
            material: SceneStaticModelMaterial, writesDepth: Bool,
            materialBlending: SceneMaterialRenderState.Blending?,
            geometryState: SceneMdlStaticModel.GeometryState = .authoredStatic
        ) {
            self.modelPath = modelPath
            self.materialPath = materialPath
            self.dynamicMaterialPath = dynamicMaterialPath
            self.mesh = mesh
            self.albedo = albedo
            self.namedAlbedo = namedAlbedo
            self.emissiveMask = emissiveMask
            self.material = material
            self.writesDepth = writesDepth
            self.materialBlending = materialBlending
            self.geometryState = geometryState
        }
    }

    let pipeline: SceneStaticModelPipeline?
    private let entriesByLayerID: [Int: [Entry]]
    private let animationsByLayerID: [Int: Animation]
    let namedAlbedoLayerIDs: Set<Int>

    private init(pipeline: SceneStaticModelPipeline?, entriesByLayerID: [Int: [Entry]],
                 animationsByLayerID: [Int: Animation] = [:]) {
        self.pipeline = pipeline
        self.entriesByLayerID = entriesByLayerID
        self.animationsByLayerID = animationsByLayerID
        namedAlbedoLayerIDs = Set(entriesByLayerID.compactMap {
            $0.value.contains(where: { $0.namedAlbedo != nil }) ? $0.key : nil
        })
    }

    static let empty = ScenePreparedStaticModelResources(
        pipeline: nil,
        entriesByLayerID: [:]
    )

    var isEmpty: Bool { entriesByLayerID.isEmpty }
    var preparedLayerIDs: [Int] { entriesByLayerID.keys.sorted() }
    var preparedDirectModelAnimationVisibilityTargets: Set<SceneDynamicTarget> {
        guard pipeline != nil else { return [] }
        return animationsByLayerID.reduce(into: []) { targets, entry in
            guard entriesByLayerID[entry.key]?.count == 1,
                  entry.value.attachments.isEmpty else { return }
            targets.formUnion(ScenePuppetAnimationPropertyPreparation.visibilityTargets(
                layerID: entry.key, selection: entry.value.selection))
        }
    }
    subscript(layerID: Int) -> [Entry]? {
        entriesByLayerID[layerID]
    }

    func animation(for layerID: Int) -> Animation? { animationsByLayerID[layerID] }

    static func prepare(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        device: MTLDevice,
        textureLoader: SceneTextureLoader,
        preparedSources: inout [String: SceneMdlStaticModel.PreparedSource],
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedStaticModelResources {
        try withoutActuallyEscaping(cancellationCheck) { cancellationCheck in
            let layers = descriptor.layers.filter { $0.staticModelPath != nil }
            guard !layers.isEmpty,
                  let pipeline = SceneStaticModelPipeline(
                      device: device, colorPixelFormat: descriptor.colorTargetFormat.metalPixelFormat
                  ) else {
                return .empty
            }

            struct PreparedGeometry {
                let materialPath: String
                let mesh: SceneStaticModelMesh
                let geometryState: SceneMdlStaticModel.GeometryState
                let animationAsset: AnimationAsset?
            }

            let textureResolver = SceneTexturePathResolver(
                resourceView: resourceView,
                descriptor: descriptor
            )
            var geometryByPath: [String: [PreparedGeometry]] = [:]
            var rejectedModelPaths: Set<String> = []
            var entries: [Int: [Entry]] = [:]
            var animations: [Int: Animation] = [:]
            for layer in layers {
                try cancellationCheck()
                guard let modelPath = layer.staticModelPath else { continue }
                let modelIdentity = identity(modelPath)
                if rejectedModelPaths.contains(modelIdentity) { continue }

                let preparedGeometries: [PreparedGeometry]
                if let cached = geometryByPath[modelIdentity] {
                    preparedGeometries = cached
                } else {
                    guard let source = preparedSources.removeValue(forKey: modelIdentity) else {
                        rejectedModelPaths.insert(modelIdentity)
                        continue
                    }
                    // Material links and geometry use the one completed CPU
                    // snapshot. This owner only uploads it; it never rereads.
                    preparedGeometries = source.parts.compactMap { part in
                        guard let mesh = pipeline.makeMesh(
                            vertices: part.vertices, indices: part.indices
                        ) else { return nil }
                        return PreparedGeometry(
                            materialPath: part.materialPath,
                            mesh: mesh,
                            geometryState: part.geometryState,
                            animationAsset: source.animations.map {
                                AnimationAsset(model: part, animations: $0, attachments: source.attachments)
                            }
                        )
                    }
                    geometryByPath[modelIdentity] = preparedGeometries
                }
                if preparedGeometries.count == 1,
                   let asset = preparedGeometries[0].animationAsset,
                   !layer.puppetAnimationLayers.isEmpty {
                    do {
                        if let animation = try prepareAnimation(
                            asset: asset, layers: layer.puppetAnimationLayers) {
                            animations[layer.id] = animation
#if DEBUG
                            if let failure = animation.futureVisibilityFailure {
                                NSLog("MWX Scene model-animation layer=%d state=default-selection-preserved futureVisibility=unavailable reason=%@",
                                    layer.id, String(describing: failure))
                            }
#endif
                        }
                    } catch {
#if DEBUG
                        NSLog("MWX Scene model-animation layer=%d state=bind-only reason=%@",
                              layer.id, String(describing: error))
#endif
                    }
                }
                try cancellationCheck()

                for preparedGeometry in preparedGeometries {
                    guard let materialIdentity = SceneVFSAssetPath(
                        preparedGeometry.materialPath
                    ),
                          let pass = descriptor.materialPasses.first(where: {
                        SceneVFSAssetPath($0.materialPath) == materialIdentity
                            && $0.passIndex == 0
                    }) else { continue }
#if DEBUG
                    if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
                       let bindings = pass.staticModelMaterialBindings {
                        NSLog("MWX Scene model-material layer=%d state=%@ reason=%@",
                            layer.id, bindings.state.rawValue, bindings.rejectionReason ?? "none")
                    }
#endif
                    guard pass.staticModelMaterialBindings?.state != .rejected,
                          let modelMaterial = material(
                              pass, hdrEnabled: descriptor.hdrEnabled, resourceView: resourceView
                          ),
                          let texturePath = pass.textureSlots.first.flatMap({ $0 })
                            ?? pass.staticModelDefaultAlbedoAssetPath else {
                        continue
                    }
                    let namedAlbedo = SceneNamedTextureReference.parse(texturePath)
                    let albedo: SceneTextureCandidate?
                    if namedAlbedo == nil {
                        guard let textureURL = textureResolver.resolveTextureFile(
                            named: texturePath
                        ), case let .loaded(candidate) = try textureLoader.loadCandidate(
                            from: textureURL,
                            purpose: .straightAlbedo,
                            device: device, checkCancellation: cancellationCheck
                        ) else { continue }
                        albedo = candidate
                    } else {
                        albedo = nil
                    }
                    let emission = shaderValue(named: "emissivebrightness", in: pass)
                    // Dynamic declarations need the mask even with a zero seed.
                    // Resource reservation does not grant a live script consumer.
                    let hasDynamicEmissiveBrightness = emission?.userBinding != nil || emission?.scriptSource != nil
                    let emissiveMask = modelMaterial.emissiveBrightness > 0
                        || hasDynamicEmissiveBrightness
                        ? try optionalTexture(
                            at: 2,
                            in: pass,
                            purpose: .mask,
                            resolver: textureResolver,
                            textureLoader: textureLoader,
                            device: device, checkCancellation: cancellationCheck
                        )
                        : nil
                    entries[layer.id, default: []].append(Entry(
                        modelPath: modelPath,
                        materialPath: preparedGeometry.materialPath,
                        dynamicMaterialPath: identity(preparedGeometry.materialPath),
                        mesh: preparedGeometry.mesh,
                        albedo: albedo,
                        namedAlbedo: namedAlbedo,
                        emissiveMask: emissiveMask,
                        material: modelMaterial,
                        writesDepth: writesDepth(pass.depthWrite),
                        materialBlending: SceneMaterialRenderState.compileBlending(pass.blending),
                        geometryState: preparedGeometry.geometryState
                    ))
#if DEBUG
                    if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
                       preparedGeometry.geometryState == .bindOnlyAnimationUnqualified {
                        NSLog("MWX Scene model-geometry layer=%d state=%@ preparation=ready animation=unqualified",
                            layer.id, preparedGeometry.geometryState.rawValue)
                    }
#endif
                    try cancellationCheck()
                }
            }

            return ScenePreparedStaticModelResources(
                pipeline: entries.isEmpty ? nil : pipeline,
                entriesByLayerID: entries,
                animationsByLayerID: animations.filter { entries[$0.key]?.count == 1 }
            )
        }
    }

    private static func prepareAnimation(
        asset: AnimationAsset,
        layers: [ScenePuppetAnimationLayer]
    ) throws -> Animation? {
        guard let set = try asset.animations.get(), let rig = asset.model.rig else { return nil }
        let attachments = try asset.attachments.get()
        let bindPositions = asset.model.vertices.map(\.position)
        func make(_ requested: [ScenePuppetAnimationLayer],
                  failure: FutureVisibilityFailure? = nil) throws -> Animation? {
            guard let selection = try ScenePuppetAnimationSelector.select(
                layers: requested, animationSet: set).get() else { return nil }
            let evaluator = try ScenePuppetAnimationEvaluator(
                bindPositions: bindPositions, rig: rig,
                additiveAnimations: selection.clips.map(\.animation))
            return Animation(vertices: asset.model.vertices, selection: selection,
                evaluator: evaluator, attachments: attachments,
                initialBones: ScenePuppetLayerLoad.initialBoneConfiguration(
                    rig: rig, referenceEvaluator: .success(evaluator)),
                futureVisibilityFailure: failure)
        }
        do {
            return try make(layers)
        } catch {
            let failure: FutureVisibilityFailure
            switch error {
            case let reason as ScenePuppetAnimationSelectionFailure:
                failure = .selection(reason)
            case let reason as ScenePuppetAnimationEvaluationFailure:
                switch reason {
                case .invalidReferenceTrack, .unsupportedReferenceComposition,
                     .duplicateAdditiveAnimation:
                    failure = .evaluation(reason)
                default:
                    throw error
                }
            default:
                throw error
            }
            let current = layers.filter {
                !($0.hasPreparedVisibilityProperty == true && $0.visible == false)
            }
            guard current.count < layers.count else { throw error }
            return try make(current, failure: failure)
        }
    }

    private nonisolated static func identity(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
    }

    private static func writesDepth(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).localizedLowercase else {
            return true
        }
        return !["disabled", "false", "off", "0"].contains(normalized)
    }

    private static func material(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        hdrEnabled: Bool,
        resourceView: SceneResourceView
    ) -> SceneStaticModelMaterial? {
        let color: [Double]
        let opacity: Double
        let brightness: Double
        if let bindings = pass.staticModelMaterialBindings, bindings.state == .authored {
            guard let tint = bindings.binding(for: .color), tint.components.count == 3,
                  let alpha = bindings.binding(for: .alpha), alpha.components.count == 1,
                  let intensity = bindings.binding(for: .brightness), intensity.components.count == 1 else {
                return nil
            }
            color = tint.components
            opacity = alpha.components[0]
            brightness = intensity.components[0]
        } else {
            color = components(named: "color", in: pass)
                ?? components(named: "Color", in: pass) ?? [1, 1, 1]
            opacity = components(named: "alpha", in: pass)?.first
                ?? components(named: "Alpha", in: pass)?.first ?? 1
            brightness = components(named: "brightness", in: pass)?.first ?? 1
        }
        let emissiveColor = components(named: "emissivecolor", in: pass)
            ?? [1, 1, 1]
        let emissiveBrightness = components(
            named: "emissivebrightness",
            in: pass
        )?.first ?? 0
        let tintFront = components(named: "tintfront", in: pass)
        let tintBack = components(named: "tintback", in: pass)
        let tintExponent = components(named: "tintwexponent", in: pass)?
            .first ?? 1.5
        let viewTint: SceneStaticModelViewTint? = if let tintFront, let tintBack {
            .init(
                front: SIMD3(
                    component(tintFront, at: 0, default: 1),
                    component(tintFront, at: 1, default: 1),
                    component(tintFront, at: 2, default: 1)
                ),
                back: SIMD3(
                    component(tintBack, at: 0, default: 1),
                    component(tintBack, at: 1, default: 1),
                    component(tintBack, at: 2, default: 1)
                ),
                exponent: Float(tintExponent),
                usesDynamicBackColor:
                    shaderValue(named: "tintback", in: pass)?.scriptSource != nil
            )
        } else {
            nil
        }
        return SceneStaticModelMaterial(
            color: SIMD3(
                component(color, at: 0, default: 1),
                component(color, at: 1, default: 1),
                component(color, at: 2, default: 1)
            ),
            opacity: Float(opacity),
            receivesLighting: pass.combos["LIGHTING"] != 0,
            textureAlphaIsOpacity: pass.combos["TINTMASKALPHA"] != 1,
            textureAlphaIsTintMask: pass.combos["TINTMASKALPHA"] == 1,
            emissiveColor: SIMD3(
                component(emissiveColor, at: 0, default: 1),
                component(emissiveColor, at: 1, default: 1),
                component(emissiveColor, at: 2, default: 1)
            ),
            emissiveBrightness: Float(emissiveBrightness),
            brightness: Float(brightness),
            usesHDRBrightness: hdrEnabled,
            viewTint: viewTint,
            channelBindings: pass.staticModelMaterialBindings,
            surfaceProfile: surfaceProfile(pass, resourceView: resourceView),
            // Missing or unrecognized state retains the existing back-face
            // policy; only the authored no-cull state opens both mesh sides.
            cullMode: SceneMaterialRenderState.Cull(rawValue:
                pass.cullMode?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedLowercase ?? ""
            ) == .noCull ? .none : .back
        )
    }

    /// The resource namespace owns source precedence. An author override of
    /// either generic4 root stage never gains the fixed model surface policy.
    static func surfaceProfile(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        resourceView: SceneResourceView
    ) -> SceneStaticModelSurfaceProfile? {
        guard pass.shaderPath?.localizedLowercase == "generic4",
              pass.combos["LIGHTING"] != 0,
              pass.userShaderValues["metallic"] == nil,
              pass.userShaderValues["roughness"] == nil,
              let metallic = SceneMaterialPropertyBindingCompiler.staticComponents(
                  "metallic", instance: nil, pass: pass, count: 1, fallback: [0],
                  requiresCompleteScalar: true
              )?.first,
              let roughness = SceneMaterialPropertyBindingCompiler.staticComponents(
                  "roughness", instance: nil, pass: pass, count: 1, fallback: [0.7],
                  requiresCompleteScalar: true
              )?.first else { return nil }
        for suffix in [".vert", ".frag"] {
            if let stage = resourceView.resolvedResource(relativePath: "shaders/generic4" + suffix),
               stage.source != .stock {
                return nil
            }
        }
        return .init(
            metallic: Float(min(1, max(0, metallic))),
            roughness: Float(min(1, max(0, roughness)))
        )
    }

    /// Optional packed material data fails soft, leaving the ordinary lit
    /// albedo intact. It is loaded as a typed mask rather than color.
    private static func optionalTexture(
        at slotIndex: Int,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor,
        purpose: SceneTextureLoadPurpose,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureCandidate? {
        guard pass.textureSlots.indices.contains(slotIndex),
              let path = pass.textureSlots[slotIndex],
              let url = resolver.resolveTextureFile(named: path),
              case let .loaded(candidate) = try textureLoader.loadCandidate(
                  from: url,
                  purpose: purpose,
                  device: device, checkCancellation: checkCancellation
              ),
              candidate.sampling.isResolvedForMaterialProgram,
              !candidate.sampling.usesClampBorderFallback else {
            return nil
        }
        return candidate
    }

    private static func components(
        named name: String,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> [Double]? {
        shaderValue(named: name, in: pass)?.components
    }

    private static func shaderValue(
        named name: String,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor
    ) -> SceneDocument.ShaderValue? {
        pass.constantShaderValues[name]
    }

    private static func component(
        _ values: [Double],
        at index: Int,
        default defaultValue: Float
    ) -> Float {
        values.indices.contains(index) ? Float(values[index]) : defaultValue
    }
}
