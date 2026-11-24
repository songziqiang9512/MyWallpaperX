import Foundation
import Metal
import simd

/// Immutable launch-prepared resources for direct `objects[].model` layers.
/// Geometry production joins the existing renderer/main pass; this type owns
/// no command queue, frame target, compositor, or mutable playback state.
struct ScenePreparedStaticModelResources {
    enum AlbedoSource: Equatable {
        case asset(SceneAssetTextureIdentity)
        case named(SceneNamedTextureReference)
    }

    struct MaterialPlan {
        struct Item {
            let pass: SceneRenderDescriptor.MaterialPassDescriptor
            let material: SceneStaticModelMaterial
            let albedoSource: AlbedoSource?
            let userAlbedoProperty: SceneUserPropertyTextureIdentity?
            let writesDepth: Bool
            let testsDepth: Bool
            let materialBlending: SceneMaterialRenderState.Blending?
        }

        let materialsByPath: [SceneVFSAssetPath: Item]
        let assetDemands: Set<SceneAssetTextureIdentity>

        static let empty = MaterialPlan(materialsByPath: [:], assetDemands: [])
    }

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
        let albedoSource: AlbedoSource?
        let userAlbedoProperty: SceneUserPropertyTextureIdentity?
        let materialMap: SceneStaticModelMaterialMap?
        let normalMap: SceneStaticModelNormalMap?
        let gradient: SceneStaticModelGradient?
        let pigment: SceneStaticModelPigment?
        let material: SceneStaticModelMaterial
        let writesDepth: Bool
        let testsDepth: Bool
        let materialBlending: SceneMaterialRenderState.Blending?
        let geometryState: SceneMdlStaticModel.GeometryState

        init(
            modelPath: String, materialPath: String, dynamicMaterialPath: String,
            mesh: SceneStaticModelMesh, albedoSource: AlbedoSource?,
            materialMap: SceneStaticModelMaterialMap?,
            material: SceneStaticModelMaterial, writesDepth: Bool,
            materialBlending: SceneMaterialRenderState.Blending?,
            geometryState: SceneMdlStaticModel.GeometryState = .authoredStatic,
            normalMap: SceneStaticModelNormalMap? = nil,
            testsDepth: Bool = true,
            gradient: SceneStaticModelGradient? = nil,
            pigment: SceneStaticModelPigment? = nil,
            userAlbedoProperty: SceneUserPropertyTextureIdentity? = nil
        ) {
            self.modelPath = modelPath
            self.materialPath = materialPath
            self.dynamicMaterialPath = dynamicMaterialPath
            self.mesh = mesh
            self.albedoSource = albedoSource
            self.userAlbedoProperty = userAlbedoProperty
            self.materialMap = materialMap
            self.normalMap = normalMap
            self.gradient = gradient
            self.pigment = pigment
            self.material = material
            self.writesDepth = writesDepth
            self.testsDepth = testsDepth
            self.materialBlending = materialBlending
            self.geometryState = geometryState
        }
    }

    let pipeline: SceneStaticModelPipeline?
    let directionalShadowDimensionLimit: Int?
    private let entriesByLayerID: [Int: [Entry]]
    private let animationsByLayerID: [Int: Animation]
    let namedAlbedoLayerIDs: Set<Int>
    let reflectiveLayerIDs: Set<Int>
    let videoAlbedoAssetsByLayerID: [Int: Set<SceneAssetTextureIdentity>]

    private init(pipeline: SceneStaticModelPipeline?, directionalShadowDimensionLimit: Int?, entriesByLayerID: [Int: [Entry]],
                 animationsByLayerID: [Int: Animation] = [:], reflectiveLayerIDs: Set<Int> = [],
                 videoAlbedoAssetsByLayerID: [Int: Set<SceneAssetTextureIdentity>] = [:]) {
        self.pipeline = pipeline
        self.directionalShadowDimensionLimit = directionalShadowDimensionLimit
        self.entriesByLayerID = entriesByLayerID
        self.animationsByLayerID = animationsByLayerID
        namedAlbedoLayerIDs = Set(entriesByLayerID.compactMap {
            $0.value.contains { if case .named = $0.albedoSource { true } else { false } }
                ? $0.key : nil
        })
        self.reflectiveLayerIDs = reflectiveLayerIDs
        self.videoAlbedoAssetsByLayerID = videoAlbedoAssetsByLayerID
    }

    static let empty = ScenePreparedStaticModelResources(
        pipeline: nil,
        directionalShadowDimensionLimit: nil,
        entriesByLayerID: [:]
    )

    var isEmpty: Bool { entriesByLayerID.isEmpty }
    var preparedLayerIDs: [Int] { entriesByLayerID.keys.sorted() }
    var albedoAssetDemands: Set<SceneAssetTextureIdentity> {
        Set(entriesByLayerID.values.joined().compactMap {
            if case let .asset(identity) = $0.albedoSource { identity } else { nil }
        })
    }
    var userPropertyDemands: Set<SceneUserPropertyTextureIdentity> {
        Set(entriesByLayerID.values.joined().compactMap(\.userAlbedoProperty))
    }
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

    static func compileMaterialPlan(
        descriptor: SceneRenderDescriptor,
        resourceView: SceneResourceView,
        cancellationCheck: () throws -> Void
    ) throws -> MaterialPlan {
        var seen: Set<SceneVFSAssetPath> = []
        var materials: [SceneVFSAssetPath: MaterialPlan.Item] = [:]
        var demands: Set<SceneAssetTextureIdentity> = []
        for pass in descriptor.materialPasses where pass.passIndex == 0 {
            try cancellationCheck()
            guard let path = SceneVFSAssetPath(pass.materialPath),
                  seen.insert(path).inserted,
                  let bindings = pass.staticModelMaterialBindings,
                  bindings.state != .rejected,
                  let material = material(pass, hdrEnabled: descriptor.hdrEnabled, resourceView: resourceView)
            else { continue }
            let userProperty = pass.userTextureInputs.first.flatMap { input in
                input.flatMap { $0.kind == .property ? SceneUserPropertyTextureIdentity(
                    propertyKey: $0.value, purpose: .straightAlbedo) : nil }
            }
            var source: AlbedoSource?
            if let texturePath = pass.textureSlots.first.flatMap({ $0 })
                ?? pass.staticModelDefaultAlbedoAssetPath {
                if let reference = SceneNamedTextureReference.parse(texturePath) {
                    source = .named(reference)
                } else if let identity = SceneAssetTextureIdentity(virtualPath: texturePath, purpose: .straightAlbedo) {
                    source = .asset(identity)
                    demands.insert(identity)
                }
            }
            guard source != nil || userProperty != nil else { continue }
            let blending = SceneMaterialRenderState.compileBlending(pass.blending)
            materials[path] = .init(pass: pass, material: material, albedoSource: source,
                userAlbedoProperty: userProperty,
                writesDepth: blending != .translucent && depthEnabled(pass.depthWrite),
                testsDepth: depthEnabled(pass.depthTest), materialBlending: blending)
        }
        return .init(materialsByPath: materials, assetDemands: demands)
    }

    static func prepare(
        descriptor: SceneRenderDescriptor,
        directionalShadowDimensionLimit: Int? = 4096,
        pointVolumeEnabled: Bool = true,
        modelReflectionsEnabled: Bool = true,
        resourceView: SceneResourceView,
        device: MTLDevice,
        textureLoader: SceneTextureLoader,
        materialPlan: MaterialPlan,
        albedoStates: [SceneAssetTextureIdentity: SceneAssetTextureLaunchState],
        preparedSources: inout [String: SceneMdlStaticModel.PreparedSource],
        cancellationCheck: () throws -> Void
    ) throws -> ScenePreparedStaticModelResources {
        try withoutActuallyEscaping(cancellationCheck) { cancellationCheck in
            let layers = descriptor.layers.filter { $0.staticModelPath != nil }
            guard !layers.isEmpty else { return .empty }

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
            var videoAlbedos: [Int: Set<SceneAssetTextureIdentity>] = [:]
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
                        guard let mesh = SceneStaticModelPipeline.makeMesh(model: part, device: device)
                        else { return nil }
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
                    ), let planned = materialPlan.materialsByPath[materialIdentity] else { continue }
                    if planned.userAlbedoProperty == nil, case let .asset(identity) = planned.albedoSource {
                        guard let state = albedoStates[identity] else { continue }
                        switch state {
                        case .ready, .preparedVideo: break
                        default: continue
                        }
                    }
                    let pass = planned.pass
                    let modelMaterial = planned.material
#if DEBUG
                    if SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
                       let bindings = pass.staticModelMaterialBindings {
                        NSLog("MWX Scene model-material layer=%d state=%@ reason=%@",
                            layer.id, bindings.state.rawValue, bindings.rejectionReason ?? "none")
                    }
#endif
                    let materialMap = try Self.materialMap(pass, material: modelMaterial,
                        resolver: textureResolver, textureLoader: textureLoader,
                        device: device, checkCancellation: cancellationCheck)
                    let needsSurfaceNormal = modelMaterial.receivesLighting
                        || (modelMaterial.surfaceProfile?.reflectivity ?? 0) > 0
                        || (modelMaterial.surfaceProfile?.kind == .chroma4 && modelMaterial.viewTint.map {
                            $0.front != $0.back || $0.usesDynamicBackColor
                        } == true)
                    let normal = modelMaterial.surfaceProfile != nil && needsSurfaceNormal
                        && pass.combos["NORMALMAP"] != 0
                        ? try optionalTexture(at: 1, in: pass, purpose: .normal,
                            resolver: textureResolver, textureLoader: textureLoader,
                            device: device, checkCancellation: cancellationCheck)
                        : nil
                    entries[layer.id, default: []].append(Entry(
                        modelPath: modelPath,
                        materialPath: preparedGeometry.materialPath,
                        dynamicMaterialPath: identity(preparedGeometry.materialPath),
                        mesh: preparedGeometry.mesh,
                        albedoSource: planned.albedoSource,
                        materialMap: materialMap,
                        material: modelMaterial,
                        writesDepth: planned.writesDepth,
                        materialBlending: planned.materialBlending,
                        geometryState: preparedGeometry.geometryState,
                        normalMap: normal.map { .init(texture: $0.texture,
                            textureFrame: $0.uvTransform, sampling: $0.sampling,
                            encoding: .init(authoredFormat: $0.authoredFormat, pixelFormat: $0.pixelFormat)) },
                        testsDepth: planned.testsDepth,
                        gradient: try Self.gradient(pass, material: modelMaterial,
                            resolver: textureResolver, textureLoader: textureLoader,
                            device: device, checkCancellation: cancellationCheck),
                        pigment: try Self.pigment(pass, material: modelMaterial,
                            resolver: textureResolver, textureLoader: textureLoader,
                            device: device, checkCancellation: cancellationCheck),
                        userAlbedoProperty: planned.userAlbedoProperty
                    ))
                    if case let .asset(identity) = planned.albedoSource,
                       case .preparedVideo = albedoStates[identity] {
                        videoAlbedos[layer.id, default: []].insert(identity)
                    }
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

            guard !entries.isEmpty else { return .empty }
            let reflectiveLayerIDs: Set<Int> = modelReflectionsEnabled ? Set(entries.compactMap { id, parts in
                parts.contains { ($0.material.surfaceProfile?.reflectivity ?? 0) > 0 } ? id : nil
            }) : []
            guard let pipeline = SceneStaticModelPipeline(
                device: device, colorPixelFormat: descriptor.colorTargetFormat.metalPixelFormat,
                preparesReflection: !reflectiveLayerIDs.isEmpty,
                preparesAdditive: entries.values.contains { $0.contains { $0.materialBlending == .additive } },
                preparesCameraDepth: pointVolumeEnabled && descriptor.camera.clearEnabled && descriptor.layers.contains {
                    $0.pointLight?.unshadowedVolume != nil
                }, preparesShadows: directionalShadowDimensionLimit != nil) else { return .empty }
            return ScenePreparedStaticModelResources(
                pipeline: pipeline,
                directionalShadowDimensionLimit: directionalShadowDimensionLimit,
                entriesByLayerID: entries,
                animationsByLayerID: animations.filter { entries[$0.key]?.count == 1 },
                reflectiveLayerIDs: pipeline.supportsReflection ? reflectiveLayerIDs : [],
                videoAlbedoAssetsByLayerID: videoAlbedos
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

    private static func depthEnabled(_ value: String?) -> Bool {
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
            let rawOpacity = components(named: "alpha", in: pass)?.first
                ?? components(named: "Alpha", in: pass)?.first ?? 1
            opacity = rawOpacity.isFinite ? rawOpacity : 1
            brightness = components(named: "brightness", in: pass)?.first ?? 1
        }
        let emissiveColor = components(named: "emissivecolor", in: pass)
            ?? [1, 1, 1]
        let surface = surfaceProfile(pass, resourceView: resourceView)
        let emissiveBrightness = components(
            named: "emissivebrightness",
            in: pass
        )?.first ?? (surface == nil ? 0 : 1)
        let tintFrontValue = shaderValue(named: "tintfront", in: pass)
        let tintBackValue = shaderValue(named: "tintback", in: pass)
        let defaultTint: [Double]? = surface?.kind == .chroma4
            && (tintFrontValue != nil || tintBackValue != nil) ? [1, 1, 1] : nil
        let tintExponent = components(named: "tintwexponent", in: pass)?
            .first ?? 1.5
        let viewTint: SceneStaticModelViewTint? = if let tintFront = tintFrontValue?.components ?? defaultTint,
                                                    let tintBack = tintBackValue?.components ?? defaultTint {
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
                    tintBackValue?.scriptSource != nil
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
            // Clamp before narrowing: finite authored alpha can exceed Float.
            opacity: Float(min(max(opacity, 0), 1)),
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
            surfaceProfile: surface,
            // Missing or unrecognized state retains the existing back-face
            // policy; only the authored no-cull state opens both mesh sides.
            cullMode: SceneMaterialRenderState.Cull(rawValue:
                pass.cullMode?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedLowercase ?? ""
            ) == .noCull ? .none : .back
        )
    }

    /// The resource namespace owns source precedence. An author override of
    /// either stock root stage never gains the fixed model surface policy.
    static func surfaceProfile(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        resourceView: SceneResourceView
    ) -> SceneStaticModelSurfaceProfile? {
        let authoredReflection = pass.combos["REFLECTION"].map { $0 != 0 } ?? false
        guard let shader = pass.shaderPath?.localizedLowercase,
              let kind = SceneStaticModelSurfaceProfile.Kind(rawValue: shader),
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
            if let stage = resourceView.resolvedResource(relativePath: "shaders/" + shader + suffix),
               stage.source != .stock {
                return nil
            }
        }
        let reflectivity: Double
        if authoredReflection,
           pass.textureSlots.count < 4 || pass.textureSlots[3] == nil
                || pass.textureSlots[3] == "_rt_MipMappedFrameBuffer",
           pass.userShaderValues["reflectivity"] == nil {
            reflectivity = SceneMaterialPropertyBindingCompiler.staticComponents(
                "reflectivity", instance: nil, pass: pass, count: 1, fallback: [1],
                requiresCompleteScalar: true)?.first ?? 0
        } else { reflectivity = 0 }
        let maximum = Double(Float.greatestFiniteMagnitude)
        var rimAmount: Float = 0
        var rimExponent: Float = 4
        if pass.combos["RIMLIGHTING"].map({ $0 != 0 }) == true,
           pass.combos["LIGHTING"] != 0,
           pass.userShaderValues["rimamount"] == nil,
           pass.userShaderValues["rimexponent"] == nil,
           let amount = SceneMaterialPropertyBindingCompiler.staticComponents(
               "rimamount", instance: nil, pass: pass, count: 1, fallback: [2],
               requiresCompleteScalar: true)?.first,
           let exponent = SceneMaterialPropertyBindingCompiler.staticComponents(
               "rimexponent", instance: nil, pass: pass, count: 1, fallback: [4],
               requiresCompleteScalar: true)?.first {
            rimAmount = Float(min(maximum, max(0, amount)))
            rimExponent = Float(min(maximum, max(0, exponent)))
        }
        var specularTint = SIMD3<Float>(repeating: 1)
        var pigmentAmount: Float = 0
        if kind == .chroma4, pass.userShaderValues["speculartint"] == nil,
           let values = SceneMaterialPropertyBindingCompiler.staticComponents(
               "speculartint", instance: nil, pass: pass, count: 3, fallback: [1, 1, 1]) {
            specularTint = SIMD3(Float(min(maximum, max(0, values[0]))),
                Float(min(maximum, max(0, values[1]))), Float(min(maximum, max(0, values[2]))))
        }
        if kind == .chroma4, pass.combos["LIGHTING"] != 0,
           pass.userShaderValues["tintpigmentation"] == nil,
           let amount = SceneMaterialPropertyBindingCompiler.staticComponents(
               "tintpigmentation", instance: nil, pass: pass, count: 1, fallback: [0],
               requiresCompleteScalar: true)?.first {
            pigmentAmount = Float(min(1, max(0, amount)))
        }
        return .init(
            metallic: Float(min(1, max(0, metallic))),
            roughness: Float(min(1, max(0, roughness))),
            reflectivity: Float(min(1, max(0, reflectivity))),
            reflectionEnabled: authoredReflection,
            rimAmount: rimAmount, rimExponent: rimExponent, kind: kind,
            specularTint: specularTint, pigmentAmount: pigmentAmount
        )
    }

    private static func materialMap(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        material: SceneStaticModelMaterial,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneStaticModelMaterialMap? {
        let emission = shaderValue(named: "emissivebrightness", in: pass)
        let needsEmission = material.emissiveBrightness > 0
            || emission?.userBinding != nil || emission?.scriptSource != nil
        let surface = material.surfaceProfile
        var requested: UInt32 = 0
        var automatic: UInt32 = 0
        if let surface {
            guard pass.combos["PBRMASKS"] != 0 else { return nil }
            for (name, bit) in [("METALLIC_MAP", UInt32(1)), ("ROUGHNESS_MAP", 2),
                                ("REFLECTION_MAP", 4), ("EMISSIVE_MAP", 8)] {
                if let value = pass.combos[name] {
                    if value != 0 { requested |= bit }
                } else {
                    automatic |= bit
                }
            }
            let needsResponse = material.receivesLighting || surface.reflectivity > 0
            let demand: UInt32 = (needsResponse ? 3 : 0) | (surface.reflectivity > 0 ? 4 : 0)
                | (needsEmission ? 8 : 0)
            requested &= demand
            automatic &= demand
        } else if needsEmission {
            requested = 8
        }
        guard (requested | automatic) != 0,
              let candidate = try optionalTexture(at: 2, in: pass, purpose: .mask,
                  resolver: resolver, textureLoader: textureLoader, device: device,
                  checkCancellation: checkCancellation) else { return nil }
        let components = requested | (((candidate.sampling.rawFlags ?? 0) >> 20) & automatic)
        guard components != 0 else { return nil }
        return .init(texture: candidate.texture, textureFrame: candidate.uvTransform,
            sampling: candidate.sampling, components: components)
    }

    private static func gradient(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        material: SceneStaticModelMaterial,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneStaticModelGradient? {
        guard material.surfaceProfile != nil, material.receivesLighting,
              pass.combos["SHADINGGRADIENT"].map({ $0 != 0 }) == true,
              let candidate = try optionalTexture(at: 4, in: pass, purpose: .mask,
                  defaultPath: "gradient/gradient_toon_smooth",
                  resolver: resolver, textureLoader: textureLoader, device: device,
                  checkCancellation: checkCancellation) else { return nil }
        let frame = candidate.uvTransform
        let origin = frame.origin + 0.5 * frame.yAxis
        let replicatesRed = candidate.authoredFormat == .r8 || candidate.authoredFormat == .rg88
            || candidate.pixelFormat == .r8Unorm || candidate.pixelFormat == .rg8Unorm
        return .init(texture: candidate.texture,
            sampleLine: SIMD4(origin.x, origin.y, frame.xAxis.x, frame.xAxis.y),
            sampling: candidate.sampling, replicatesRed: replicatesRed)
    }

    private static func pigment(
        _ pass: SceneRenderDescriptor.MaterialPassDescriptor,
        material: SceneStaticModelMaterial,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneStaticModelPigment? {
        guard (material.surfaceProfile?.pigmentAmount ?? 0) > 0,
              let candidate = try optionalTexture(at: 8, in: pass, purpose: .noise,
                  defaultPath: "util/noise", resolver: resolver,
                  textureLoader: textureLoader, device: device,
                  checkCancellation: checkCancellation) else { return nil }
        let frame = candidate.uvTransform
        let replicatesRed = candidate.authoredFormat == .r8 || candidate.authoredFormat == .rg88
            || candidate.pixelFormat == .r8Unorm || candidate.pixelFormat == .rg8Unorm
        let pixelFrame: SceneTextureUVTransform
        let framePixels: SIMD4<Float>
        if candidate.isSpriteSheet {
            let physical = SIMD2(Float(candidate.physicalSize.width), Float(candidate.physicalSize.height))
            // Subpixel frames occupy one target-pixel sampling cell.
            let width = max(1, simd_length(frame.xAxis * physical))
            let height = max(1, simd_length(frame.yAxis * physical))
            pixelFrame = .init(origin: frame.origin,
                xAxis: frame.xAxis / width, yAxis: frame.yAxis / height)
            framePixels = SIMD4(width, height, 1 / width, 1 / height)
        } else {
            pixelFrame = .init(origin: frame.origin,
                xAxis: frame.xAxis / Float(candidate.mappedSize.width),
                yAxis: frame.yAxis / Float(candidate.mappedSize.height))
            framePixels = .zero
        }
        return .init(texture: candidate.texture,
            pixelFrame: pixelFrame, framePixels: framePixels,
            sampling: candidate.sampling, replicatesRed: replicatesRed)
    }

    /// Optional packed material data fails soft, leaving the ordinary lit
    /// albedo intact. It is loaded as a typed mask rather than color.
    private static func optionalTexture(
        at slotIndex: Int,
        in pass: SceneRenderDescriptor.MaterialPassDescriptor,
        purpose: SceneTextureLoadPurpose,
        defaultPath: String? = nil,
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        checkCancellation: (() throws -> Void)?
    ) throws -> SceneTextureCandidate? {
        let authoredPath = pass.textureSlots.indices.contains(slotIndex) ? pass.textureSlots[slotIndex] : nil
        let hasUserInput = pass.userTextureInputs.indices.contains(slotIndex)
            && pass.userTextureInputs[slotIndex] != nil
        guard let path = authoredPath ?? (hasUserInput ? nil : defaultPath),
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
