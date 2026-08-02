import Foundation

struct SceneRenderDescriptor: Codable {
    // Scene camera + ortho box derived from scene.json `camera` and
    // `general.orthogonalprojection`. eye/center/up are in world coords.
    // ortho dimensions define the view volume (centered on the camera in
    // view space). clearColor is the scene background (0..1 RGB).
    struct CameraDescriptor: Codable {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let nearZ: Float
        let farZ: Float
        let clearColor: [Float]   // [r, g, b]
        let clearEnabled: Bool
        let parallaxEnabled: Bool
        let parallaxAmount: Float
        let parallaxDelay: Float
        let parallaxMouseInfluence: Float
    }

    let entryPath: String
    let camera: CameraDescriptor
    let layers: [Layer]
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
        capabilityProfile: SceneCapabilityProfile
    ) -> SceneRenderDescriptor? {
        guard Set(sceneDocument.objects.map(\.id)).count == sceneDocument.objects.count else {
            return nil
        }
        let modelCropOffsetsByPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.map { ($0.relativePath, $0.cropOffsetXY) }
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
            layers: sceneDocument.objects.enumerated().map { index, object in
                let contentKind = contentKind(for: object, solidModelPaths: solidModelPaths)
                return SceneRenderDescriptor.Layer(
                    id: object.id,
                    layerIndex: index,
                    name: object.name,
                    cameraPath: object.cameraPath,
                    contentKind: contentKind,
                    imagePath: object.imagePath,
                    particlePath: object.particlePath,
                    spotLight: object.spotLight,
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
                    visible: object.visible,
                    alpha: object.alpha,
                    colorRGB: padVector(object.colorRGB, length: 3, fill: 1),
                    colorBlendMode: object.colorBlendMode,
                    brightness: object.brightness,
                    imageAlignment: object.imageAlignment,
                    origin: object.origin,
                    size: object.size,
                    scale: object.scale,
                    angles: object.angles,
                    originXYZ: padVector(parseVector(object.origin), length: 3, fill: 0),
                    sizeWH: padVector(parseVector(object.size), length: 2, fill: 0),
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
            modelMaterialLinks: assetCatalog.models.map { model in
                SceneRenderDescriptor.ModelMaterialLink(
                    modelPath: model.relativePath,
                    materialPath: model.materialPath
                )
            },
            materialPasses: materialPassDescriptors(from: assetCatalog),
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

    nonisolated func build(report: SceneDiagnosticsReport) -> SceneRenderDescriptor? {
        guard let project = report.project,
              let sceneDocument = report.sceneDocument,
              let assetCatalog = report.assetCatalog,
              let resourceReferences = report.resourceReferences,
              let capabilityProfile = report.capabilityProfile else {
            return nil
        }

        return build(
            project: project,
            sceneDocument: sceneDocument,
            assetCatalog: assetCatalog,
            resourceReferences: resourceReferences,
            capabilityProfile: capabilityProfile
        )
    }

    nonisolated private func materialPassDescriptors(from catalog: SceneAssetCatalog) -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        catalog.materials.flatMap { material in
            material.passes.enumerated().map { index, pass in
                SceneRenderDescriptor.MaterialPassDescriptor(
                    id: "\(material.relativePath)#\(index)",
                    materialPath: material.relativePath,
                    materialRawSHA256: material.rawSHA256,
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
        if object.particlePath != nil {
            return "particle"
        }
        if object.spotLight != nil {
            return "spotLight"
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
            nearZ: gen.nearZ ?? 0.01,
            farZ: gen.farZ ?? 10_000,
            clearColor: clear,
            clearEnabled: gen.clearEnabled,
            parallaxEnabled: gen.cameraParallaxEnabled,
            parallaxAmount: gen.cameraParallaxAmount,
            parallaxDelay: gen.cameraParallaxDelay,
            parallaxMouseInfluence: gen.cameraParallaxMouseInfluence
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
