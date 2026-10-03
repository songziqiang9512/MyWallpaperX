import Foundation
import QuartzCore

nonisolated extension SceneResolvedMaterialVariantCache {
    static func analyzeVariantColor(
        cachedAnalysis: SceneResolvedMaterialVariantAnalysisCache.Record?,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        normalBlendModeIdentifiers: Set<String>,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        outputIsRGBA8Unorm: Bool
    ) -> (
        spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?,
        sourceCarriedRGBAFact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact?,
        rgba8UnormAccumulatorSourceSlot: Int?,
        conditionalGeneratedRGBFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?,
        sameAlphaReconstructedRGBFact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?,
        rgbBlendScalarAlphaFact: SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact?,
        sourceColorTransfer: SceneShaderColorTransfer
    ) {
        let spatialWeightedColorBlendFact: SceneAuthoredShaderSpatialWeightedColorBlendFact?
        let analyzedSourceColorTransfer: SceneShaderColorTransfer
        let sourceCarriedRGBAFact: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedFact?
        let rgba8UnormAccumulatorSourceSlot: Int?
        let conditionalGeneratedRGBFact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact?
        let sameAlphaReconstructedRGBFact: SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.Fact?
        if let cachedAnalysis {
            spatialWeightedColorBlendFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.spatialWeightedColorBlend)
            analyzedSourceColorTransfer = cachedAnalysis.sourceColorTransfer
            sourceCarriedRGBAFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.sourceCarriedRGBA)
            rgba8UnormAccumulatorSourceSlot =
                cachedAnalysis.rgba8UnormAccumulatorSourceSlot
            conditionalGeneratedRGBFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.conditionalGeneratedRGB)
            sameAlphaReconstructedRGBFact = SceneResolvedMaterialVariantAnalysisCache
                .rebuild(cachedAnalysis.sameAlphaReconstructedRGB)
        } else {
            spatialWeightedColorBlendFact =
                SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment,
                    normalBlendModeIdentifiers: normalBlendModeIdentifiers
                )
            analyzedSourceColorTransfer =
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment,
                    provenRuntimeLoopBounds: runtimeLoopBounds.fragment
                )
            sourceCarriedRGBAFact =
                SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
                    .analyzeSourceCarried(fragmentSource: compilerSources.fragment)
            rgba8UnormAccumulatorSourceSlot = outputIsRGBA8Unorm
                ? SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
                    .rgba8UnormAttachmentSourceSlot(
                        fragmentSource: compilerSources.fragment
                    )
                : nil
            conditionalGeneratedRGBFact =
                SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                )
            sameAlphaReconstructedRGBFact =
                SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer.analyze(
                    fragmentSource: compilerSources.fragment
                )
        }
        let rgbBlendScalarAlphaFact =
            SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
                fragmentSource: compilerSources.fragment
            )
        let targetAwareSourceColorTransfer: SceneShaderColorTransfer =
            if analyzedSourceColorTransfer == .unresolved,
               let rgba8UnormAccumulatorSourceSlot {
                .independentAlphaSignalPreserving(
                    textureSlot: rgba8UnormAccumulatorSourceSlot
                )
            } else {
                analyzedSourceColorTransfer
            }
        let sourceColorTransfer: SceneShaderColorTransfer =
            spatialWeightedColorBlendFact.map {
                .straightAlphaPreserving(textureSlot: $0.sourceSlot)
            } ?? targetAwareSourceColorTransfer
        return (
            spatialWeightedColorBlendFact,
            sourceCarriedRGBAFact,
            rgba8UnormAccumulatorSourceSlot,
            conditionalGeneratedRGBFact,
            sameAlphaReconstructedRGBFact,
            rgbBlendScalarAlphaFact,
            sourceColorTransfer
        )
    }
}
