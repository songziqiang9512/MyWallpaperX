import CryptoKit
import Foundation

/// Lossless verification snapshot used by the strict compiler and its clean-room fixtures.
nonisolated struct SceneScriptAudioBarsVerificationInput: Equatable, Sendable {
    nonisolated struct ShaderValueSnapshot: Equatable, Sendable {
        let rawValue: String
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
        let hasTimeline: Bool
        let timelineDiagnostics: [String]
    }

    nonisolated struct LayerSnapshot: Equatable, Sendable {
        let contentKind: String
        let imagePath: String?
        let imageAlignment: String?
        let visible: Bool?
        let alpha: Double?
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        let brightness: Double?
        let hasInlineScript: Bool
        let particlePath: String?
        let hasUtilityLayer: Bool
        let dependencyCount: Int
        let reverseDependencyConsumerCount: Int
        let parentID: Int?
        let childCount: Int
        let attachmentName: String?
        let hasParentAttachmentBindFrame: Bool
        let puppetAnimationCount: Int
        let puppetMeshPath: String?
        let text: String?
        let hasTextStyle: Bool
        let hasTextScript: Bool
        let effectCount: Int
        let effectFileCount: Int
        let texturePathCount: Int
        let timelineCount: Int
        let timelineDiagnosticCount: Int
        let hasModelCropOffset: Bool
        let parallaxDepthXY: [Float]?
        let disablesParallaxPropagation: Bool
        let cameraParallaxEnabled: Bool
        let cameraOrthoHeight: Float?
        let hasFiniteOrigin: Bool
        let hasPositiveFiniteSize: Bool
    }

    nonisolated struct AssetSnapshot: Equatable, Sendable {
        let missingResourceCount: Int
        let modelLinkCount: Int
        let linkedMaterialPath: String?
        let materialPassCount: Int
        let materialPath: String?
        let materialRawSHA256: String?
        let materialPassIndex: Int?
        let shaderPath: String?
        let texturePaths: [String]
        let textureSlots: [String?]
        let userTextureInputCount: Int
        let combos: [String: Int]
        let constants: [String: ShaderValueSnapshot]
        let userShaderValues: [String: String]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
        let alphaWriting: String?
        let shaderContractCount: Int
        let shaderIdentity: String?
        let shaderSourceKind: String?
        let shaderDiagnosticCount: Int
        let shaderStageCount: Int
        let shaderDeclaredStageSHA256: [String: String]
        let shaderSourceStageSHA256: [String: String]
        let shaderCanonicalSHA256: String?
        let shaderCanonicalMatchesPayload: Bool
    }

    let layerID: Int
    let bindingCount: Int
    let host: String
    let sourceSHA256: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let layer: LayerSnapshot
    let assets: AssetSnapshot
}

extension SceneScriptAudioBarsVerificationInput.LayerSnapshot {
    nonisolated init(
        layer: SceneRenderDescriptor.Layer,
        cameraParallaxEnabled: Bool,
        cameraOrthoHeight: Float?,
        reverseDependencyConsumerCount: Int
    ) {
        self.init(
            contentKind: layer.contentKind,
            imagePath: layer.imagePath,
            imageAlignment: layer.imageAlignment,
            visible: layer.visible,
            alpha: layer.alpha,
            colorRGB: layer.colorRGB,
            colorBlendMode: layer.colorBlendMode,
            brightness: layer.brightness,
            hasInlineScript: layer.hasInlineScript,
            particlePath: layer.particlePath,
            hasUtilityLayer: layer.utilityLayer != nil,
            dependencyCount: layer.dependencyLayerIDs.count,
            reverseDependencyConsumerCount: reverseDependencyConsumerCount,
            parentID: layer.parentID,
            childCount: layer.childLayerIDs.count,
            attachmentName: layer.attachmentName,
            hasParentAttachmentBindFrame: layer.parentAttachmentBindFrame != nil,
            puppetAnimationCount: layer.puppetAnimationLayers.count,
            puppetMeshPath: layer.puppetMeshPath,
            text: layer.text,
            hasTextStyle: layer.textStyle != nil,
            hasTextScript: layer.textScript != nil,
            effectCount: layer.effects.count,
            effectFileCount: layer.effectFiles.count,
            texturePathCount: layer.texturePaths.count,
            timelineCount: layer.timelines.count,
            timelineDiagnosticCount: layer.timelineDiagnostics.count,
            hasModelCropOffset: layer.modelCropOffsetXY != nil,
            parallaxDepthXY: layer.parallaxDepthXY,
            disablesParallaxPropagation: layer.disablesParallaxPropagation,
            cameraParallaxEnabled: cameraParallaxEnabled,
            cameraOrthoHeight: cameraOrthoHeight,
            hasFiniteOrigin: Self.finite(layer.originXYZ, count: 3, positive: false),
            hasPositiveFiniteSize: Self.finite(layer.sizeWH, count: 2, positive: true)
        )
    }

    private nonisolated static func finite(
        _ values: [Float]?,
        count: Int,
        positive: Bool
    ) -> Bool {
        guard let values, values.count == count, values.allSatisfy(\.isFinite) else {
            return false
        }
        return !positive || values.allSatisfy { $0 > 0 }
    }
}

extension SceneScriptAudioBarsVerificationInput.AssetSnapshot {
    private nonisolated struct CanonicalShaderPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated init(
        layer: SceneRenderDescriptor.Layer,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) {
        let links = descriptor.modelMaterialLinks.filter {
            $0.modelPath == layer.imagePath
        }
        let linkedMaterial = links.count == 1 ? links[0].materialPath : nil
        let passes = descriptor.materialPasses.filter {
            $0.materialPath == linkedMaterial
        }
        let pass = passes.count == 1 ? passes[0] : nil
        let contracts = shaderContracts.filter { $0.identity == pass?.shaderPath }
        let contract = contracts.count == 1 ? contracts[0] : nil
        let stageHashes = Self.stageHashes(contract)
        self.init(
            missingResourceCount: descriptor.missingResources.count,
            modelLinkCount: links.count,
            linkedMaterialPath: linkedMaterial,
            materialPassCount: passes.count,
            materialPath: pass?.materialPath,
            materialRawSHA256: pass?.materialRawSHA256,
            materialPassIndex: pass?.passIndex,
            shaderPath: pass?.shaderPath,
            texturePaths: pass?.texturePaths ?? [],
            textureSlots: pass?.textureSlots ?? [],
            userTextureInputCount: pass?.userTextureInputs.count ?? 0,
            combos: pass?.combos ?? [:],
            constants: pass?.constantShaderValues.mapValues {
                .init(
                    rawValue: $0.rawValue,
                    valueKind: $0.valueKind,
                    userBinding: $0.userBinding,
                    components: $0.components,
                    hasTimeline: $0.timeline != nil,
                    timelineDiagnostics: $0.timelineDiagnostics
                )
            } ?? [:],
            userShaderValues: pass?.userShaderValues ?? [:],
            blending: pass?.blending,
            depthTest: pass?.depthTest,
            depthWrite: pass?.depthWrite,
            cullMode: pass?.cullMode,
            alphaWriting: pass?.alphaWriting,
            shaderContractCount: contracts.count,
            shaderIdentity: contract?.identity,
            shaderSourceKind: contract?.sourceKind.rawValue,
            shaderDiagnosticCount: contract?.diagnostics.count ?? 0,
            shaderStageCount: contract?.stages.count ?? 0,
            shaderDeclaredStageSHA256: stageHashes.declared,
            shaderSourceStageSHA256: stageHashes.source,
            shaderCanonicalSHA256: contract?.canonicalSHA256,
            shaderCanonicalMatchesPayload: contract.map(Self.canonicalMatches) ?? false
        )
    }

    private nonisolated static func stageHashes(
        _ contract: SceneShaderContract?
    ) -> (declared: [String: String], source: [String: String]) {
        var declared: [String: String] = [:]
        var source: [String: String] = [:]
        for stage in contract?.stages ?? [] {
            let key = "\(stage.kind.rawValue):\(stage.relativePath)"
            declared[key] = declared[key] == nil ? stage.rawSHA256 : "<duplicate>"
            source[key] = source[key] == nil ? Self.sha256(stage.source) : "<duplicate>"
        }
        return (declared, source)
    }

    private nonisolated static func canonicalMatches(
        _ contract: SceneShaderContract
    ) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalShaderPayload(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
        guard let data = try? encoder.encode(payload) else { return false }
        return Self.sha256(data) == contract.canonicalSHA256
    }

    private nonisolated static func sha256(_ source: String) -> String {
        Self.sha256(Data(source.utf8))
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
