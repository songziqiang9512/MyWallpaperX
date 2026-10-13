// Complete attenuation and color blend eligibility counterexample families.
import Foundation
import Metal
import simd

func attenuationEligibilityTokens() -> [String: Bool] {
    let maskMetadata = #"{"mode":"opacitymask","combo":"MASK"}"#
    let maskPath = SceneVFSAssetPath("textures/eligibility-mask.tex")!
    let shader = contract(
        revision: "eligibility-mask",
        secondSamplerMetadata: maskMetadata,
        maskedAlpha: true,
        optionalMask: true,
        semanticProbes: false
    )
    let fixtureTemplate = template(
        shader,
        includePrimaryCandidate: false,
        secondReference: .asset(maskPath)
    )

    func prepared(
        _ readiness: [Int: Bool]
    ) -> (SceneShaderPreparedProgram, [Int: SceneResolvedMaterialShaderSchema.Sampler])? {
        guard case let .accepted(value) =
                SceneAuthoredShaderPreparation.prepareShaderStages(
                    contract: shader,
                    combos: [:],
                    textureReadiness: readiness
                ),
              let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: value.vertex.source,
                    fragmentSource: value.fragment.source
                ),
              let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
                  value,
                  activeNames: activeNames
              ) else { return nil }
        return (value, samplers)
    }

    func proven(
        _ preparedValue: SceneShaderPreparedProgram,
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler],
        _ materialTemplate: Template = fixtureTemplate,
        inputIdentity: Graph.TextureIdentity = graphTexture()
    ) -> Bool {
        guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
            fragmentSource: preparedValue.fragment.source
        ) else { return false }
        return SceneResolvedMaterialAlphaAttenuationEligibility.validated(
            fact: fact,
            samplers: samplers,
            template: materialTemplate,
            implicitFramebufferIdentity: inputIdentity
        )
    }

    let maskOff = prepared([0: true, 1: false]).map {
        proven($0.0, $0.1)
    } ?? false
    let maskOn = prepared([0: true, 1: true]).map {
        proven($0.0, $0.1)
    } ?? false

    let wrongSamplerMode: Bool = {
        let wrongShader = contract(
            revision: "eligibility-wrong-mode",
            secondSamplerMetadata: #"{"mode":"rgbmask"}"#,
            maskedAlpha: true,
            semanticProbes: false
        )
        let wrongTemplate = template(
            wrongShader,
            includePrimaryCandidate: false,
            secondReference: .asset(maskPath)
        )
        guard case let .accepted(value) =
                SceneAuthoredShaderPreparation.prepareShaderStages(
                    contract: wrongShader,
                    combos: [:],
                    textureReadiness: [0: true, 1: true]
                ),
              let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: value.vertex.source,
                    fragmentSource: value.fragment.source
                ),
              let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
                  value,
                  activeNames: activeNames
              ),
              let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
                  fragmentSource: value.fragment.source
              ) else { return true }
        return !SceneResolvedMaterialAlphaAttenuationEligibility.validated(
            fact: fact,
            samplers: samplers,
            template: wrongTemplate,
            implicitFramebufferIdentity: graphTexture()
        )
    }()

    let auxiliaryGraphInputRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let graphAuxiliaryTemplate = template(
            shader,
            includePrimaryCandidate: false,
            graphBindingsOverride: [.init(slot: 1, texture: .layerSource)],
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, graphAuxiliaryTemplate)
    }()

    let extraActiveSamplerRejected: Bool = {
        guard let value = prepared([0: true, 1: true]),
              let auxiliary = value.1[1] else { return false }
        var samplers = value.1
        samplers[2] = .init(
            name: "g_Texture2",
            slot: 2,
            mode: auxiliary.mode,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value.0, samplers)
    }()

    let priorEffectOutputAccepted: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let priorTemplate = template(
            shader,
            includePrimaryCandidate: true,
            primaryReference: .graph(prior),
            effectInputGraphTextureRole: .effectOutput,
            primaryGraphTextureRole: .effectOutput,
            secondReference: .asset(maskPath)
        )
        return proven(
            value.0,
            value.1,
            priorTemplate,
            inputIdentity: prior
        )
    }()

    let internalFramebufferRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let internalTemplate = template(
            shader,
            primaryReference: .graph(namedFramebufferTexture()),
            primaryGraphTextureRole: .framebuffer,
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, internalTemplate)
    }()

    let differentEffectOutputRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let different = effectOutputTexture("fixture-other")
        let differentTemplate = template(
            shader,
            primaryReference: .graph(different),
            effectInputGraphTextureRole: .effectOutput,
            primaryGraphTextureRole: .effectOutput,
            secondReference: .asset(maskPath)
        )
        return !proven(
            value.0,
            value.1,
            differentTemplate,
            inputIdentity: prior
        )
    }()

    let fallbackCandidateRejected: Bool = {
        guard let value = prepared([0: true, 1: true]) else { return false }
        let fallbackTemplate = template(
            shader,
            candidateCount: 2,
            secondReference: .asset(maskPath)
        )
        return !proven(value.0, value.1, fallbackTemplate)
    }()

    return [
        "maskOffPreparedVariant": maskOff,
        "maskOnPreparedVariant": maskOn,
        "wrongSamplerModeRejected": wrongSamplerMode,
        "auxiliaryGraphInputRejected": auxiliaryGraphInputRejected,
        "extraActiveSamplerRejected": extraActiveSamplerRejected,
        "priorEffectOutputAccepted": priorEffectOutputAccepted,
        "internalFramebufferRejected": internalFramebufferRejected,
        "differentEffectOutputRejected": differentEffectOutputRejected,
        "fallbackCandidateRejected": fallbackCandidateRejected,
    ]
}

func colorBlendEligibilityTokens() -> [String: Bool] {
    let maskPath = SceneVFSAssetPath("textures/color-blend-mask.tex")!

    struct Prepared {
        let program: SceneShaderPreparedProgram
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        let shader: SceneShaderContract
        let combos: [String: Int]
    }

    func prepared(
        blendMode: Int,
        mask: Bool,
        legacyMaskOverride: Bool = false
    ) -> Prepared? {
        let shader = contract(
            revision: "color-blend-\(blendMode)-\(mask)-\(legacyMaskOverride)",
            semanticProbes: false,
            colorBlend: true,
            legacyMaskOverride: legacyMaskOverride
        )
        // MASK is a readiness-derived combo; passing it explicitly would
        // conflict with the active sampler schema when the mask is absent.
        let combos = ["BLENDMODE": blendMode]
        let program: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: shader,
            combos: combos,
            textureReadiness: [0: true, 1: mask]
        ) {
        case let .accepted(value):
            program = value
        case let .rejected(failure):
            fatalError(
                "COLOR-BLEND-PREPARATION=\(blendMode)/\(mask)/"
                    + "\(failure.phase.rawValue)/\(failure.code.rawValue)/"
                    + "\(failure.details)"
            )
        case .notApplicable:
            fatalError("COLOR-BLEND-PREPARATION-NOT-APPLICABLE=\(blendMode)/\(mask)")
        }
        guard let activeNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNames(
                    vertexSource: program.vertex.source,
                    fragmentSource: program.fragment.source
                ) else {
            fatalError("COLOR-BLEND-ACTIVE-NAMES=\(blendMode)/\(mask)")
        }
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(
                program,
                activeNames: activeNames
            )
        } catch {
            fatalError(
                "COLOR-BLEND-SAMPLERS=\(blendMode)/\(mask)/\(activeNames)/\(error)"
            )
        }
        return .init(
            program: program,
            samplers: samplers,
            shader: shader,
            combos: combos
        )
    }

    func materialTemplate(
        _ value: Prepared,
        input: Graph.TextureIdentity = graphTexture(),
        inputRole: Template.GraphTextureRole = .layerSource,
        auxiliaryReference: Template.TextureReference? = nil,
        auxiliaryGraphBinding: Bool = false,
        candidateCount: Int = 1
    ) -> Template {
        template(
            value.shader,
            candidateCount: candidateCount,
            includePrimaryCandidate: true,
            primaryReference: .graph(input),
            effectInputGraphTextureRole: inputRole,
            primaryGraphTextureRole: inputRole,
            graphBindingsOverride: auxiliaryGraphBinding
                ? [
                    .init(slot: 0, texture: inputRole),
                    .init(slot: 1, texture: inputRole),
                ]
                : [.init(slot: 0, texture: inputRole)],
            secondReference: auxiliaryReference,
            comboValues: value.combos
        )
    }

    func proven(
        _ value: Prepared,
        samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]? = nil,
        templateValue: Template? = nil,
        input: Graph.TextureIdentity = graphTexture()
    ) -> Bool {
        SceneResolvedMaterialColorBlendEligibility.sourceSlot(
            fragmentSource: value.program.fragment.source,
            colorTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: value.program.fragment.source
            ),
            samplers: samplers ?? value.samplers,
            template: templateValue ?? materialTemplate(
                value,
                auxiliaryReference: value.samplers[1].map { _ in .asset(maskPath) }
            ),
            implicitFramebufferIdentity: input
        ) == 0
    }

    let unmasked = prepared(blendMode: 30, mask: false)
    let stockMasked = prepared(blendMode: 12, mask: true)
    let legacyMasked = prepared(
        blendMode: 18,
        mask: true,
        legacyMaskOverride: true
    )
    let opaque = prepared(blendMode: 0, mask: false)

    let wrongSamplerModeRejected: Bool = {
        guard let value = stockMasked, let auxiliary = value.samplers[1] else {
            return false
        }
        var samplers = value.samplers
        samplers[1] = .init(
            name: auxiliary.name,
            slot: auxiliary.slot,
            mode: .regular,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value, samplers: samplers)
    }()

    let auxiliaryGraphInputRejected: Bool = {
        guard let value = stockMasked else { return false }
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                auxiliaryReference: .asset(maskPath),
                auxiliaryGraphBinding: true
            )
        )
    }()

    let extraActiveSamplerRejected: Bool = {
        guard let value = stockMasked, let auxiliary = value.samplers[1] else {
            return false
        }
        var samplers = value.samplers
        samplers[2] = .init(
            name: "g_Texture2",
            slot: 2,
            mode: auxiliary.mode,
            materialKey: auxiliary.materialKey,
            isHidden: auxiliary.isHidden,
            defaultTexture: auxiliary.defaultTexture,
            readinessCombo: auxiliary.readinessCombo
        )
        return !proven(value, samplers: samplers)
    }()

    let priorEffectOutputAccepted: Bool = {
        guard let value = stockMasked else { return false }
        let prior = effectOutputTexture("fixture-prior")
        return proven(
            value,
            templateValue: materialTemplate(
                value,
                input: prior,
                inputRole: .effectOutput,
                auxiliaryReference: .asset(maskPath)
            ),
            input: prior
        )
    }()

    let internalFramebufferRejected: Bool = {
        guard let value = stockMasked else { return false }
        let internalTarget = namedFramebufferTexture()
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                input: internalTarget,
                inputRole: .framebuffer,
                auxiliaryReference: .asset(maskPath)
            ),
            input: internalTarget
        )
    }()

    let differentEffectOutputRejected: Bool = {
        guard let value = stockMasked else { return false }
        let prior = effectOutputTexture("fixture-prior")
        let different = effectOutputTexture("fixture-other")
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                input: different,
                inputRole: .effectOutput,
                auxiliaryReference: .asset(maskPath)
            ),
            input: prior
        )
    }()

    let fallbackCandidateRejected: Bool = {
        guard let value = stockMasked else { return false }
        return !proven(
            value,
            templateValue: materialTemplate(
                value,
                auxiliaryReference: .asset(maskPath),
                candidateCount: 2
            )
        )
    }()

    return [
        "unmaskedSourceFact": unmasked.map {
            SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) != nil
        } ?? false,
        "unmaskedTransferProven": unmasked.map {
            if case .straightAlphaPreserving(textureSlot: 0) =
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: $0.program.fragment.source
                ) { return true }
            return false
        } ?? false,
        "unmaskedSamplerSetExact": unmasked.map {
            Set($0.samplers.keys) == [0]
        } ?? false,
        "modeZeroSourceFact": opaque.map {
            SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) != nil
        } ?? false,
        "modeZeroTransferProven": opaque.map {
            SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: $0.program.fragment.source
            ) == .opaque
        } ?? false,
        "modeZeroSamplerSetExact": opaque.map {
            Set($0.samplers.keys) == [0]
        } ?? false,
        "unmaskedPreparedVariant": unmasked.map { proven($0) } ?? false,
        "stockMaskMultiplyPreparedVariant": stockMasked.map { proven($0) } ?? false,
        "legacyMaskOverridePreparedVariant": legacyMasked.map { proven($0) } ?? false,
        "modeZeroOpaquePreparedVariant": opaque.map { proven($0) } ?? false,
        "wrongSamplerModeRejected": wrongSamplerModeRejected,
        "auxiliaryGraphInputRejected": auxiliaryGraphInputRejected,
        "extraActiveSamplerRejected": extraActiveSamplerRejected,
        "priorEffectOutputAccepted": priorEffectOutputAccepted,
        "internalFramebufferRejected": internalFramebufferRejected,
        "differentEffectOutputRejected": differentEffectOutputRejected,
        "fallbackCandidateRejected": fallbackCandidateRejected,
    ]
}
