import Foundation

nonisolated enum SceneEffectDedicatedStageResolution {
    case accepted(
        backend: SceneEffectStageCompilerBackend,
        executionPlan: SceneEffectStageExecutionPlan,
        precedingProbes: [SceneEffectStageCompilerProbe]
    )
    case exhausted(probes: [SceneEffectStageCompilerProbe])
}

extension SceneEffectProgramCompiler {
    /// Compiles typed stage programs without granting execution ownership.
    /// The resolved capability catalog must still admit every active stage in
    /// the layer before GraphExecutor may claim the ordered graph.
    nonisolated static func compileDedicatedLeaves(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract]
    ) -> [SceneEffectStageProgram] {
        graph.effects.enumerated().compactMap { ordinal, effect in
            guard let stageGraph = stageGraph(effect: effect, in: graph) else {
                return nil
            }
            let input = SceneEffectStageCompileInput(
                stageGraph: stageGraph,
                authoredOrdinal: ordinal,
                effectKey: effect.key,
                definitionPath: effect.definitionPath,
                inputRole: ordinal == 0 ? .layerSource : .priorEffectOutput,
                descriptor: descriptor,
                shaderContracts: shaderContracts
            )
            guard case let .accepted(backend, plan, probes) =
                    resolveDedicatedStage(input) else { return nil }
            return SceneEffectStageProgram(
                input: input,
                compilerBackend: backend,
                executionPlan: plan,
                precedingProbes: probes
            )
        }
    }

    /// Ordered typed compilers distinguish stages outside a compiler family
    /// from same-family stages rejected by an exact fail-closed profile.
    nonisolated static func resolveDedicatedStage(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectDedicatedStageResolution {
        let stageGraph = input.stageGraph
        let inputRole = input.inputRole
        typealias Probe = (
            backend: SceneEffectStageCompilerBackend,
            compile: () -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan>
        )
        let probes: [Probe] = [
            (.preciseGaussian, {
                SceneEffectStageExecutionPlanner.compile(input)
            }),
            (.standardBlur, {
                SceneAuthoredStandardBlurPlanner.compile(input)
            }),
            (.localContrast, {
                SceneAuthoredLocalContrastPlanner.compile(input).mapAccepted {
                    stage(
                        .localContrast($0),
                        stageGraph: stageGraph,
                        inputRole: inputRole,
                        materialNodeCount: 4,
                        logicalRenderTargetCount: 2
                    )
                }
            }),
            (.colorGrading, {
                SceneAuthoredColorGradingPlanner.compile(input).mapAccepted {
                    stage(.colorGrading($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.workshopShiftHue, {
                SceneAuthoredWorkshopShiftHuePlanner.compile(input).mapAccepted {
                    stage(.workshopShiftHue($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.workshopAudioBars, {
                SceneAuthoredWorkshopAudioBarsPlanner.compile(input).mapAccepted {
                    stage(.workshopAudioBars($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.workshopGradient, {
                SceneAuthoredWorkshopGradientPlanner.compile(input).mapAccepted {
                    stage(.workshopGradient($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.workshopShadow, {
                SceneAuthoredWorkshopShadowPlanner.compile(input).mapAccepted {
                    stage(.workshopShadow($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.proceduralNoise, {
                SceneAuthoredProceduralNoisePlanner.compile(input).mapAccepted {
                    stage(.proceduralNoise($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.lightShafts, {
                SceneAuthoredLightShaftsPlanner.compile(input).mapAccepted {
                    stage(.lightShafts($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.shake, {
                SceneAuthoredShakePlanner.compile(input).mapAccepted {
                    stage(.shake($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.waterFlow, {
                SceneAuthoredWaterFlowPlanner.compile(input).mapAccepted {
                    stage(.waterFlow($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.waterWaves, {
                SceneAuthoredWaterWavesPlanner.compile(input).mapAccepted {
                    stage(.waterWaves($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.waterCaustics, {
                SceneAuthoredWaterCausticsPlanner.compile(input).mapAccepted {
                    stage(.waterCaustics($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.cursorRipple, {
                SceneAuthoredCursorRipplePlanner.compile(input).mapAccepted {
                    stage(
                        .cursorRipple($0),
                        stageGraph: stageGraph,
                        inputRole: inputRole,
                        materialNodeCount: 3,
                        logicalRenderTargetCount: 2
                    )
                }
            }),
            (.waterRipple, {
                SceneAuthoredWaterRipplePlanner.compile(input).mapAccepted {
                    stage(.waterRipple($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.depthParallax, {
                SceneAuthoredDepthParallaxPlanner.compile(input).mapAccepted {
                    stage(.depthParallax($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.xRay, {
                SceneAuthoredXRayPlanner.compile(input).mapAccepted {
                    stage(.xRay($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.blend, {
                SceneAuthoredBlendPlanner.compile(input).mapAccepted {
                    stage(.blend($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.transform, {
                SceneAuthoredTransformPlanner.compile(input).mapAccepted {
                    stage(.transform($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.pulse, {
                SceneAuthoredPulsePlanner.compile(input).mapAccepted {
                    stage(.pulse($0), stageGraph: stageGraph, inputRole: inputRole)
                }
            }),
            (.godrays, {
                SceneAuthoredGodraysPlanner.compile(input).mapAccepted {
                    stage(
                        .godrays($0),
                        stageGraph: stageGraph,
                        inputRole: inputRole,
                        materialNodeCount: 5,
                        logicalRenderTargetCount: 2
                    )
                }
            }),
            (.shine, {
                SceneAuthoredShinePlanner.compile(input).mapAccepted {
                    stage(
                        .shine($0),
                        stageGraph: stageGraph,
                        inputRole: inputRole,
                        materialNodeCount: 5,
                        logicalRenderTargetCount: 2
                    )
                }
            }),
        ]

        var precedingProbes: [SceneEffectStageCompilerProbe] = []
        precedingProbes.reserveCapacity(probes.count)
        for probe in probes {
            switch probe.compile() {
            case .accepted(let executionPlan):
                return .accepted(
                    backend: probe.backend,
                    executionPlan: executionPlan,
                    precedingProbes: precedingProbes
                )
            case .notApplicable:
                precedingProbes.append(.init(
                    backend: probe.backend,
                    outcome: .notApplicable
                ))
            case .rejected(let failure):
                precedingProbes.append(.init(
                    backend: probe.backend,
                    outcome: .rejected(failure)
                ))
            }
        }
        return .exhausted(probes: precedingProbes)
    }
}
