import Foundation

struct SceneRenderDescriptor: Codable {
    struct LightingDescriptor: Codable {
        let ambientColorRGB: [Float]?
        let skylightColorRGB: [Float]?
        var distanceFog: SceneDocument.GeneralDescriptor.DistanceFog? = nil
    }

    // Scene camera + ortho box derived from scene.json `camera` and
    // `general.orthogonalprojection`. eye/center/up are in world coords.
    // ortho dimensions define the view volume (centered on the camera in
    // view space). clearColor is the scene background (0..1 RGB).
    struct CameraDescriptor: Codable {
        struct ShakeDescriptor: Codable {
            let enabled: Bool?
            let amplitude: Float?
            let roughness: Float?
            let speed: Float?
        }

        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        var bloom: SceneBloomConfiguration = .disabled
        var fovDegrees: Float? = nil
        var perspectiveOverrideFOVDegrees: Float? = nil
        let nearZ: Float
        let farZ: Float
        let clearColor: [Float]   // [r, g, b]
        let clearEnabled: Bool
        let parallaxEnabled: Bool
        let parallaxAmount: Float
        let parallaxDelay: Float
        let parallaxMouseInfluence: Float
        let shake: ShakeDescriptor
    }

    let entryPath: String
    let camera: CameraDescriptor
    var lighting: LightingDescriptor? = nil
    var hdrEnabled: Bool = false

    var colorTargetFormat: SceneGraphRenderTargetPlan.TextureFormat {
        hdrEnabled ? .rgba16f : .rgbaBackbuffer
    }
    var layers: [Layer]
    let rootLayerIDs: [Int]
    let renderOrderLayerIDs: [Int]
    let renderOrderPolicy: String
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
    let shaderReferences: [String]
    let textureReferences: [String]
    let missingResources: [String]
    let builtInReferenceCount: Int
    let runtimeProvidedReferenceCount: Int
    let texturePropertyKeys: [String]
    let firstStageRendererGaps: [String]

    nonisolated var isResourceComplete: Bool {
        missingResources.isEmpty
    }
}

struct SceneRenderDescriptorBuilder {
    nonisolated func build(
        project: SceneProject,
        sceneDocument: SceneDocument,
        assetCatalog: SceneAssetCatalog,
        resourceReferences: SceneResourceReferenceIndex,
        capabilityProfile: SceneCapabilityProfile,
        directStaticModelMaterialLinks: [
            SceneRenderDescriptor.ModelMaterialLink
        ] = []
    ) -> SceneRenderDescriptor? {
        guard Set(sceneDocument.objects.map(\.id)).count == sceneDocument.objects.count else {
            return nil
        }
        let modelCropOffsetsByPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.map { ($0.relativePath, $0.cropOffsetXY) }
        )
        let modelDeclaredSizeWHByPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.compactMap { model in
                model.declaredSizeWH.map { (model.relativePath, $0) }
            }
        )
        let puppetMeshPathsByModelPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.map { ($0.relativePath, $0.puppetPath) }
        )
        let puppetAttachmentsByModelPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.map { model in
                (
                    model.relativePath,
                    Dictionary(
                        uniqueKeysWithValues: model.puppetAttachments.map {
                            ($0.name, $0.sceneBindFrameColumnMajor)
                        }
                    )
                )
            }
        )
        let objectsByID = Dictionary(
            uniqueKeysWithValues: sceneDocument.objects.map { ($0.id, $0) }
        )
        let solidModelPaths = Set(
            assetCatalog.models.filter(\.isSolidLayer).map { $0.relativePath.localizedLowercase }
        )
        let childIDsByParentID = sceneDocument.objects.reduce(into: [Int: [Int]]()) { result, object in
            guard let parentID = object.parentID else { return }
            result[parentID, default: []].append(object.id)
        }.mapValues { ids in
            ids.sorted()
        }

        return SceneRenderDescriptor(
            entryPath: project.entryPath,
            camera: cameraDescriptor(from: sceneDocument),
            lighting: .init(
                ambientColorRGB: sceneDocument.general.ambientColorRGB,
                skylightColorRGB: sceneDocument.general.skylightColorRGB,
                distanceFog: sceneDocument.general.distanceFog
            ),
            hdrEnabled: sceneDocument.general.hdrEnabled,
            layers: sceneDocument.objects.enumerated().map { index, object in
                let contentKind = contentKind(for: object, solidModelPaths: solidModelPaths)
                return SceneRenderDescriptor.Layer(
                    id: object.id,
                    layerIndex: index,
                    name: object.name,
                    cameraPath: object.cameraPath,
                    contentKind: contentKind,
                    imagePath: object.imagePath,
                    staticBaseTexturePath: object.materialInstance.flatMap { instance in
                        guard !instance.isMalformed,
                              instance.userTextureInputs.allSatisfy({ $0 == nil }) else { return nil }
                        return instance.textureSlots.first ?? nil
                    },
                    staticModelPath: object.staticModelPath,
                    modelShadowCastIntent: object.modelShadowCastIntent,
                    usesPerspective: object.usesPerspective,
                    particlePath: object.particlePath,
                    pointLight: object.pointLight,
                    spotLight: object.spotLight,
                    directionalLight: object.directionalLight,
                    particleInstanceOverride: object.particleInstanceOverride,
                    utilityLayer: object.utilityLayer,
                    dependencyLayerIDs: object.dependencyLayerIDs,
                    authoredDependencies: object.authoredDependencies,
                    parentID: object.parentID,
                    childLayerIDs: childIDsByParentID[object.id] ?? [],
                    attachmentName: object.attachmentName,
                    parentAttachmentBindFrame: attachmentBindFrame(
                        for: object,
                        objectsByID: objectsByID,
                        attachmentsByModelPath: puppetAttachmentsByModelPath
                    ),
                    puppetAnimationLayers: object.puppetAnimationLayers,
                    solid: object.solid,
                    visible: object.visible,
                    alpha: object.alpha,
                    displayScriptOwnership: object.displayScriptOwnership,
                    colorRGB: padVector(object.colorRGB, length: 3, fill: 1),
                    colorBlendMode: object.colorBlendMode,
                    clampUVs: object.clampUVs,
                    noInterpolation: object.noInterpolation,
                    brightness: object.brightness,
                    imageAlignment: object.imageAlignment,
                    origin: object.origin,
                    size: object.size,
                    scale: object.scale,
                    scaleHasScript: object.scaleHasScript,
                    angles: object.angles,
                    originHasScript: object.originHasScript,
                    anglesHasScript: object.anglesHasScript,
                    originXYZ: padVector(parseVector(object.origin), length: 3, fill: 0),
                    sizeWH: layerSizeWH(
                        explicit: parseVector(object.size),
                        modelDeclared: object.imagePath.flatMap {
                            modelDeclaredSizeWHByPath[$0]
                        }
                    ),
                    scaleXYZ: padVector(parseVector(object.scale), length: 3, fill: 1),
                    anglesXYZ: padVector(parseVector(object.angles), length: 3, fill: 0),
                    parallaxDepthXY: padVector(parseVector(object.parallaxDepth), length: 2, fill: 0),
                    disablesParallaxPropagation: object.disablesParallaxPropagation,
                    timelines: object.timelines,
                    timelineDiagnostics: object.timelineDiagnostics,
                    particleTimelines: object.particleTimelines,
                    particleTimelineDiagnostics: object.particleTimelineDiagnostics,
                    modelCropOffsetXY: object.imagePath.flatMap { modelCropOffsetsByPath[$0] } ?? nil,
                    puppetMeshPath: object.imagePath.flatMap { puppetMeshPathsByModelPath[$0] } ?? nil,
                    text: object.text,
                    textStyle: object.textStyle,
                    textScript: object.textScript,
                    scriptBindings: object.scriptBindings,
                    textureAnimationScripts: object.textureAnimationScripts,
                    hasInlineScript: object.hasInlineScript,
                    effects: effectDescriptors(from: object),
                    effectFiles: object.effectFiles,
                    texturePaths: object.texturePaths
                )
            },
            rootLayerIDs: sceneDocument.objects.filter { $0.parentID == nil }.map(\.id),
            renderOrderLayerIDs: sceneDocument.objects.map(\.id),
            renderOrderPolicy: "source-order",
            modelMaterialLinks: modelMaterialLinks(
                from: assetCatalog,
                directStaticModelMaterialLinks: directStaticModelMaterialLinks
            ),
            materialPasses: materialPassDescriptors(
                from: assetCatalog,
                directStaticModelMaterialLinks: directStaticModelMaterialLinks
            ),
            effectDefinitions: assetCatalog.effectDefinitions,
            effectDefinitionDiagnostics: effectDefinitionDiagnostics(
                from: sceneDocument,
                catalog: assetCatalog
            ),
            shaderReferences: assetCatalog.shaderReferences,
            textureReferences: assetCatalog.textureReferences,
            missingResources: resourceReferences.missingReferences,
            builtInReferenceCount: resourceReferences.builtInReferenceCount,
            runtimeProvidedReferenceCount: resourceReferences.runtimeProvidedReferenceCount,
            texturePropertyKeys: project.userProperties.definitions.compactMap {
                $0.kind == .sceneTexture ? $0.key : nil
            },
            firstStageRendererGaps: capabilityProfile.firstStageRendererGaps
        )
    }

    nonisolated private func modelMaterialLinks(
        from assetCatalog: SceneAssetCatalog,
        directStaticModelMaterialLinks: [
            SceneRenderDescriptor.ModelMaterialLink
        ]
    ) -> [SceneRenderDescriptor.ModelMaterialLink] {
        var seen: Set<String> = []
        return (assetCatalog.models.map { model in
            SceneRenderDescriptor.ModelMaterialLink(
                modelPath: model.relativePath,
                materialPath: model.materialPath
            )
        } + directStaticModelMaterialLinks).filter { link in
            let identity = link.modelPath.replacingOccurrences(of: "\\", with: "/")
                .localizedLowercase
            let material = link.materialPath?.replacingOccurrences(of: "\\", with: "/")
                .localizedLowercase ?? ""
            return seen.insert(identity + "\u{0}" + material).inserted
        }
    }

    nonisolated private func attachmentBindFrame(
        for object: SceneDocument.SceneObject,
        objectsByID: [Int: SceneDocument.SceneObject],
        attachmentsByModelPath: [String: [String: [Float]]]
    ) -> [Float]? {
        guard let attachmentName = object.attachmentName,
              let parentID = object.parentID,
              let modelPath = objectsByID[parentID]?.imagePath else {
            return nil
        }
        return attachmentsByModelPath[modelPath]?[attachmentName]
    }

    nonisolated private func materialPassDescriptors(
        from catalog: SceneAssetCatalog,
        directStaticModelMaterialLinks: [SceneRenderDescriptor.ModelMaterialLink]
    ) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        let directMaterials = Set(directStaticModelMaterialLinks.compactMap {
            $0.materialPath.map { $0.replacingOccurrences(of: "\\", with: "/").localizedLowercase }
        })
        let materialsByPath = Dictionary(grouping: catalog.materials) {
            $0.relativePath.replacingOccurrences(of: "\\", with: "/").localizedLowercase
        }
        return catalog.materials.flatMap { material in
            material.passes.enumerated().map { index, pass in
                var descriptor = SceneRenderDescriptor.MaterialPassDescriptor(
                    id: "\(material.relativePath)#\(index)",
                    materialPath: material.relativePath,
                    materialRawSHA256: material.rawSHA256,
                    shaderPathIndependentSHA256: material.shaderPathIndependentSHA256,
                    passIndex: index,
                    shaderPath: pass.shader,
                    texturePaths: pass.textures,
                    textureSlots: pass.textureSlots,
                    userTextureInputs: pass.userTextureInputs,
                    combos: pass.combos,
                    constantShaderValues: pass.constantShaderValues,
                    userShaderValues: pass.userShaderValues,
                    blending: pass.blending,
                    depthTest: pass.depthTest,
                    depthWrite: pass.depthWrite,
                    cullMode: pass.cullMode,
                    alphaWriting: pass.alphaWriting
                )
                let path = material.relativePath.replacingOccurrences(of: "\\", with: "/")
                    .localizedLowercase
                if index == 0, directMaterials.contains(path) {
                    if materialsByPath[path]?.count == 1 {
                        descriptor.staticModelDefaultAlbedoAssetPath =
                            SceneStaticModelMaterialBindingCompiler.defaultAlbedoAssetPath(
                                pass: descriptor, shaderContracts: catalog.shaderContracts
                            )
                        descriptor.staticModelMaterialBindings =
                            SceneStaticModelMaterialBindingCompiler.compile(
                                pass: descriptor,
                                shaderContracts: catalog.shaderContracts
                            )
                    } else {
                        descriptor.staticModelMaterialBindings = .init(
                            state: .unavailable, bindings: [],
                            rejectionReason: "material-pass-ambiguous"
                        )
                    }
                }
                return descriptor
            }
        }
    }

    nonisolated private func contentKind(
        for object: SceneDocument.SceneObject,
        solidModelPaths: Set<String>
    ) -> String {
        if let utilityLayer = object.utilityLayer {
            return utilityLayer.kind.rawValue
        }
        let normalizedImagePath = object.imagePath?.localizedLowercase
        if normalizedImagePath == "models/util/solidlayer.json"
            || normalizedImagePath.map(solidModelPaths.contains) == true {
            return "solid"
        }
        if object.imagePath != nil {
            return "image"
        }
        if object.staticModelPath != nil {
            return "model"
        }
        if object.particlePath != nil {
            return "particle"
        }
        if object.pointLight != nil {
            return "pointLight"
        }
        if object.spotLight != nil {
            return "spotLight"
        }
        if object.directionalLight != nil {
            return "directionalLight"
        }
        if object.text != nil {
            return "text"
        }
        if object.shape == "quad" {
            return "quad"
        }
        return "container"
    }

    // Pulls camera + ortho box + clear color out of the parsed scene document.
    // Falls back to sane defaults when scene.json omits these (e.g. nearZ/farZ).
    nonisolated private func cameraDescriptor(from document: SceneDocument) -> SceneRenderDescriptor.CameraDescriptor {
        let cam = document.camera
        let gen = document.general
        let clear: [Float] = gen.clearColor ?? [0.7, 0.7, 0.7]
        return SceneRenderDescriptor.CameraDescriptor(
            eye: cam.eye,
            center: cam.center,
            up: cam.up,
            orthoWidth: gen.orthoWidth,
            orthoHeight: gen.orthoHeight,
            bloom: SceneBloomConfiguration(
                enabled: gen.bloomEnabled,
                strength: gen.bloomStrength,
                threshold: gen.bloomThreshold,
                tint: SIMD3(
                    gen.bloomTint.count == 3 ? gen.bloomTint[0] : 1,
                    gen.bloomTint.count == 3 ? gen.bloomTint[1] : 1,
                    gen.bloomTint.count == 3 ? gen.bloomTint[2] : 1
                ),
                // Missing-field equivalence verified with own inputs against
                // official client 2.8.0.42; this is not display EDR selection.
                hdr: gen.hdrEnabled ? .init(
                    strength: gen.bloomHDRStrength ?? 2,
                    threshold: gen.bloomHDRThreshold ?? 1,
                    scatter: gen.bloomHDRScatter ?? 1.619,
                    feather: gen.bloomHDRFeather ?? 0.1,
                    iterations: gen.bloomHDRIterations ?? 8
                ) : nil
            ),
            fovDegrees: gen.fovDegrees,
            perspectiveOverrideFOVDegrees:
                gen.perspectiveOverrideFOVDegrees,
            nearZ: gen.nearZ ?? 0.01,
            farZ: gen.farZ ?? 10_000,
            clearColor: clear,
            clearEnabled: gen.clearEnabled,
            parallaxEnabled: gen.cameraParallaxEnabled,
            parallaxAmount: gen.cameraParallaxAmount,
            parallaxDelay: gen.cameraParallaxDelay,
            parallaxMouseInfluence: gen.cameraParallaxMouseInfluence,
            shake: .init(
                enabled: gen.cameraShake.enabled,
                amplitude: gen.cameraShake.amplitude,
                roughness: gen.cameraShake.roughness,
                speed: gen.cameraShake.speed
            )
        )
    }

    nonisolated private func parseVector(_ raw: String?) -> [Float]? {
        SceneDocumentLoader.floatVector(raw)
    }

    nonisolated private func padVector(_ vec: [Float]?, length: Int, fill: Float) -> [Float]? {
        guard let vec else { return nil }
        if vec.count >= length { return Array(vec.prefix(length)) }
        return vec + Array(repeating: fill, count: length - vec.count)
    }

    /// Explicit authored `size` wins; a model-referencing layer without one
    /// inherits the model's declared design size; anything else stays [0, 0]
    /// (the historical default for size-less layers).
    nonisolated private func layerSizeWH(
        explicit: [Float]?,
        modelDeclared: [Float]?
    ) -> [Float] {
        if let explicit, !explicit.isEmpty {
            return padVector(explicit, length: 2, fill: 0) ?? [0, 0]
        }
        guard let modelDeclared, modelDeclared.count == 2 else { return [0, 0] }
        return modelDeclared
    }

    nonisolated private func effectDescriptors(from object: SceneDocument.SceneObject) -> [SceneRenderDescriptor.EffectDescriptor] {
        object.effects.enumerated().map { index, effect in
            SceneRenderDescriptor.EffectDescriptor(
                id: "\(object.id)#effect#\(effect.id.map(String.init) ?? String(index))",
                effectID: effect.id,
                name: effect.name,
                file: effect.file,
                visible: effect.visible,
                passes: effect.passes.enumerated().map { passIndex, pass in
                    SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
                        id: pass.id,
                        passIndex: passIndex,
                        texturePaths: pass.textures,
                        textureSlots: pass.textureSlots,
                        userTextureInputs: pass.userTextureInputs,
                        combos: pass.combos,
                        constantShaderValues: pass.constantShaderValues,
                        constantShaderValueKeys: pass.constantShaderValueKeys
                    )
                }
            )
        }
    }

    nonisolated private func effectDefinitionDiagnostics(
        from document: SceneDocument,
        catalog: SceneAssetCatalog
    ) -> [SceneEffectDefinitionDiagnostic] {
        let definitionsByPath = Dictionary(
            uniqueKeysWithValues: catalog.effectDefinitions.map {
                ($0.relativePath.localizedLowercase, $0)
            }
        )
        var diagnostics = catalog.effectDefinitionDiagnostics

        for object in document.objects {
            for (effectIndex, effect) in object.effects.enumerated() {
                let effectPath = effect.file.localizedLowercase
                guard let definition = definitionsByPath[effectPath] else {
                    diagnostics.append(.init(
                        code: .missingDefinition,
                        effectPath: effect.file,
                        layerID: object.id,
                        effectIndex: effectIndex,
                        detail: "Referenced effect definition was not found in the extracted asset graph."
                    ))
                    continue
                }
                guard !effect.passes.isEmpty,
                      effect.passes.count != definition.materialPassCount else { continue }
                diagnostics.append(.init(
                    code: .passCountMismatch,
                    effectPath: effect.file,
                    layerID: object.id,
                    effectIndex: effectIndex,
                    detail: "Instance passes \(effect.passes.count) do not match definition material passes \(definition.materialPassCount)."
                ))
            }
        }
        return diagnostics.sorted {
            ($0.effectPath, $0.layerID ?? -1, $0.effectIndex ?? -1, $0.code.rawValue)
                < ($1.effectPath, $1.layerID ?? -1, $1.effectIndex ?? -1, $1.code.rawValue)
        }
    }
}
