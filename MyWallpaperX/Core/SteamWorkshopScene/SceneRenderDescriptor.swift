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

    struct EffectDescriptor: Identifiable, Codable {
        struct PassDescriptor: Identifiable, Codable {
            let id: Int?
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let constantShaderValueKeys: [String]
        }

        let id: String
        let effectID: Int?
        let name: String?
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer: Identifiable, Codable {
        let id: Int
        let layerIndex: Int
        let name: String?
        let contentKind: String
        let imagePath: String?
        let particlePath: String?
        let parentID: Int?
        let childLayerIDs: [Int]
        let visible: Bool?
        let alpha: Double?
        let colorBlendMode: Int?
        let origin: String?
        let size: String?
        let scale: String?
        let angles: String?
        // Numeric transform fields parsed from the corresponding string fields.
        // originXYZ: world-space center (3 floats, defaults to [0,0,0]).
        // sizeWH: world-space size in pixels (2 floats, defaults to [0,0]).
        // scaleXYZ: per-axis scale factor (3 floats, defaults to [1,1,1]).
        // anglesXYZ: rotation in radians around X/Y/Z (3 floats, defaults to [0,0,0]).
        let originXYZ: [Float]?
        let sizeWH: [Float]?
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
        let parallaxDepthXY: [Float]?
        let disablesParallaxPropagation: Bool
        let modelCropOffsetXY: [Float]?
        let text: String?
        let textStyle: SceneTextDescriptor?
        let hasInlineScript: Bool
        let effects: [EffectDescriptor]
        let effectFiles: [String]
        let texturePaths: [String]
    }

    struct ModelMaterialLink: Identifiable, Codable {
        let modelPath: String
        let materialPath: String?

        var id: String { modelPath }
    }

    struct MaterialPassDescriptor: Identifiable, Codable {
        let id: String
        let materialPath: String
        let passIndex: Int
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }

    let entryPath: String
    let camera: CameraDescriptor
    let layers: [Layer]
    let rootLayerIDs: [Int]
    let renderOrderLayerIDs: [Int]
    let renderOrderPolicy: String
    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
    let shaderReferences: [String]
    let textureReferences: [String]
    let missingResources: [String]
    let builtInReferenceCount: Int
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
    ) -> SceneRenderDescriptor {
        let modelCropOffsetsByPath = Dictionary(
            uniqueKeysWithValues: assetCatalog.models.map { ($0.relativePath, $0.cropOffsetXY) }
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
                SceneRenderDescriptor.Layer(
                    id: object.id,
                    layerIndex: index,
                    name: object.name,
                    contentKind: contentKind(for: object),
                    imagePath: object.imagePath,
                    particlePath: object.particlePath,
                    parentID: object.parentID,
                    childLayerIDs: childIDsByParentID[object.id] ?? [],
                    visible: object.visible,
                    alpha: object.alpha,
                    colorBlendMode: object.colorBlendMode,
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
                    modelCropOffsetXY: object.imagePath.flatMap { modelCropOffsetsByPath[$0] } ?? nil,
                    text: object.text,
                    textStyle: object.textStyle,
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
            shaderReferences: assetCatalog.shaderReferences,
            textureReferences: assetCatalog.textureReferences,
            missingResources: resourceReferences.missingReferences,
            builtInReferenceCount: resourceReferences.builtInReferenceCount,
            firstStageRendererGaps: capabilityProfile.firstStageRendererGaps
        )
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
                    passIndex: index,
                    shaderPath: pass.shader,
                    texturePaths: pass.textures,
                    textureSlots: pass.textureSlots,
                    combos: pass.combos,
                    constantShaderValues: pass.constantShaderValues,
                    blending: pass.blending,
                    depthTest: pass.depthTest,
                    depthWrite: pass.depthWrite,
                    cullMode: pass.cullMode
                )
            }
        }
    }

    nonisolated private func contentKind(for object: SceneDocument.SceneObject) -> String {
        if object.imagePath != nil {
            return "image"
        }
        if object.particlePath != nil {
            return "particle"
        }
        if object.text != nil {
            return "text"
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
                        combos: pass.combos,
                        constantShaderValues: pass.constantShaderValues,
                        constantShaderValueKeys: pass.constantShaderValueKeys
                    )
                }
            )
        }
    }
}
