import Foundation

extension SceneGenericShaderArtifactBuilder {
    static func prepareStraightAlphaPreservingColorTransfer(
        msl source: String,
        authoredSource: String,
        expectedSlot: Int
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        let preserving: (
            msl: String,
            transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
        )?
        if let fact = SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer
            .analyze(fragmentSource: authoredSource) {
            guard fact.blurredSlot == expectedSlot,
                  let lowered =
                    SceneGenericShaderUnitPreviousBlurredCompositeLowering.lower(
                        source,
                        expectedBlurredSlot: expectedSlot,
                        expectedPreviousSlot: fact.previousSlot,
                        expectedMaskSlot: fact.maskSlot
                    ) else { throw Failure.colorTransfer }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else if let fact = SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer
            .analyzeAny(fragmentSource: authoredSource) {
            guard fact.sourceSlot == expectedSlot,
                  let lowered = SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreservedAlphaRGBFilter(
                        source,
                        sourceSlot: fact.sourceSlot,
                        fullColorSampleCallCounts:
                            fact.fullColorSampleCallCounts,
                        rgbColorSampleCallCounts:
                            fact.rgbColorSampleCallCounts,
                        dataSampleCallCounts: fact.dataSampleCallCounts
                    ) else { throw Failure.colorTransfer }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else if let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer
            .analyze(fragmentSource: authoredSource) {
            guard fact.sourceSlot == expectedSlot,
                  let lowered = SceneGenericShaderTypedDataRGBFilterLowering
                    .lower(source, fact: fact) else {
                throw Failure.colorTransfer
            }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else if let fact =
            SceneAuthoredShaderSameAlphaReconstructedRGBFilterAnalyzer
                .analyze(fragmentSource: authoredSource) {
            guard fact.sourceSlot == expectedSlot,
                  let lowered =
                    SceneGenericShaderSameAlphaReconstructedRGBFilterLowering
                        .lower(source, fact: fact) else {
                throw Failure.colorTransfer
            }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else if let fact = SceneAuthoredShaderConditionalGeneratedRGBAnalyzer
            .analyze(fragmentSource: authoredSource) {
            guard fact.alphaCarrierSlot == expectedSlot,
                  let lowered = SceneGenericShaderConditionalGeneratedRGBLowering
                    .lower(source, fact: fact) else {
                throw Failure.colorTransfer
            }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else if let fact = SceneAuthoredShaderStraightBlendOutputAnalyzer
            .analyzeAlphaPreservingGeneratedRGB(fragmentSource: authoredSource) {
            guard fact.sourceSlot == expectedSlot,
                  let lowered = SceneGenericShaderGeneratedRGBPreservedAlphaLowering
                    .lower(source, fact: fact) else {
                throw Failure.colorTransfer
            }
            preserving = preservingTransfer(lowered, slot: expectedSlot)
        } else {
            preserving = straightAlphaPreserving(
                source,
                expectedSlot: expectedSlot
            )
        }
        guard let preserving else { throw Failure.colorTransfer }
        return preserving
    }

    private static func preservingTransfer(
        _ msl: String,
        slot: Int
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    ) {
        (
            msl: msl,
            transfer: artifactTransfer(
                kind: "straight-alpha-preserving",
                slot: slot
            )
        )
    }
}
