import Foundation

struct SceneCapabilityProfile {
    let supportsAudioProcessing: Bool
    let usesEffects: Bool
    let usesMaterials: Bool
    let usesShaderReferences: Bool
    let hasShaderBlobs: Bool
    let hasScripts: Bool
    let hasParticles: Bool
    let hasPuppetModels: Bool
    let requiresBuiltInResources: Bool
    let hasMissingResources: Bool

    nonisolated var firstStageRendererGaps: [String] {
        var gaps: [String] = []

        if usesEffects {
            gaps.append("effect runtime")
        }
        if usesMaterials {
            gaps.append("material pipeline")
        }
        if usesShaderReferences || hasShaderBlobs {
            gaps.append("shader translation")
        }
        if hasScripts {
            gaps.append("SceneScript")
        }
        if hasParticles {
            gaps.append("particle runtime")
        }
        if hasPuppetModels {
            gaps.append("puppet warp")
        }
        if supportsAudioProcessing {
            gaps.append("audio processing")
        }
        if requiresBuiltInResources {
            gaps.append("built-in resources")
        }
        if hasMissingResources {
            gaps.append("resource resolution")
        }

        return gaps
    }
}

struct SceneCapabilityProfileBuilder {
    nonisolated func build(
        project: SceneProject?,
        sceneDocument: SceneDocument?,
        assetCatalog: SceneAssetCatalog?,
        resourceReferences: SceneResourceReferenceIndex?,
        resourceIndex: SceneResourceIndex
    ) -> SceneCapabilityProfile {
        SceneCapabilityProfile(
            supportsAudioProcessing: project?.supportsAudioProcessing == true,
            usesEffects: (sceneDocument?.effectCount ?? 0) > 0,
            usesMaterials: (assetCatalog?.materialPassCount ?? 0) > 0,
            usesShaderReferences: assetCatalog?.shaderReferences.isEmpty == false,
            hasShaderBlobs: resourceIndex.count(kind: .shaderBlob) > 0,
            hasScripts: resourceIndex.count(kind: .script) > 0 || sceneDocument?.objects.contains(where: \.hasInlineScript) == true,
            hasParticles: resourceIndex.count(kind: .particle) > 0,
            hasPuppetModels: assetCatalog?.models.contains(where: { $0.puppetPath != nil }) == true,
            requiresBuiltInResources: (resourceReferences?.builtInReferenceCount ?? 0) > 0,
            hasMissingResources: resourceReferences?.missingReferences.isEmpty == false
        )
    }
}
