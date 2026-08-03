import CoreGraphics
import Foundation

nonisolated enum SceneAuthoredShaderExecutionPlanner {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneAuthoredShaderExecutionPlan

    static let compilerBackend: SceneEffectStageCompilerBackend = .authoredShader

    /// Compatibility projection for callers that have not migrated to typed
    /// admission. The compile result below is the single planning authority.
    static func plan(
        graph: Graph,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> Plan? {
        compile(.init(
            stageGraph: graph,
            inputRole: inputRole,
            descriptor: descriptor,
            shaderContracts: shaderContracts
        )).acceptedPlan
    }

    static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<Plan> {
        let graph = input.stageGraph
        guard graph.blockers.isEmpty else {
            return rejected(
                phase: .graph,
                code: .graphBlocked,
                details: graph.blockers.map { String(describing: $0.reason) }
            )
        }

        let materialNodes = graph.nodes.filter { $0.kind == .material }
        guard graph.effects.count == 1,
              graph.nodes.count == 1,
              materialNodes.count == 1,
              graph.renderTargets.isEmpty else {
            return .notApplicable
        }
        guard let layer = input.descriptor.layers.first(where: {
            $0.id == graph.layerID
        }) else {
            return rejected(phase: .topology, code: .layerMissing)
        }
        guard ["image", "solid", "text"].contains(layer.contentKind) else {
            return rejected(
                phase: .topology,
                code: .unsupportedContentKind,
                details: [layer.contentKind]
            )
        }
        guard let mappedSize = mappedSize(layer) else {
            return rejected(phase: .topology, code: .invalidMappedSize)
        }

        let node = materialNodes[0]
        if let failure = topologyFailure(
            graph: graph,
            node: node,
            layer: layer,
            inputRole: input.inputRole
        ) {
            return .rejected(failure)
        }

        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: graph,
            descriptor: input.descriptor
        )
        guard resolution.isResolved, let material = resolution.node else {
            return rejected(
                phase: .material,
                code: .materialResolutionFailed,
                details: resolution.issues.isEmpty
                    ? ["resolved-node-missing"]
                    : resolution.issues
            )
        }
        let hasOnlyEmptyTextureSlots = material.textureSlots.allSatisfy { $0 == nil }
        guard hasOnlyEmptyTextureSlots else {
            return rejected(
                phase: .material,
                code: .materialTextureSlotUnsupported
            )
        }
        guard material.combos.isEmpty else {
            return rejected(phase: .material, code: .materialComboUnsupported)
        }
        guard let renderState = SceneMaterialRenderState.compile(
            blending: material.renderState.blending,
            depthTest: material.renderState.depthTest,
            depthWrite: material.renderState.depthWrite,
            cullMode: material.renderState.cullMode,
            alphaWriting: material.renderState.alphaWriting
        ) else {
            return rejected(phase: .material, code: .renderStateInvalid)
        }
        guard renderState.matchesFullscreenOverwrite(
            alphaWriting: .unspecified
        ) else {
            return rejected(
                phase: .material,
                code: .renderStateNotFullscreenOverwrite
            )
        }
        guard let materialDescriptor = input.descriptor.materialPasses.first(where: {
            $0.id == node.materialPassID
        }) else {
            return rejected(phase: .invariant, code: .materialDescriptorMissing)
        }
        guard materialDescriptor.userShaderValues.isEmpty else {
            return rejected(
                phase: .material,
                code: .dynamicUserShaderValueUnsupported
            )
        }

        let contractResult = matchingContract(
            material.shaderPath,
            shaderContracts: input.shaderContracts
        )
        let contract: SceneShaderContract
        switch contractResult {
        case .accepted(let value):
            contract = value
        case .notApplicable:
            return rejected(phase: .invariant, code: .shaderStageMissing)
        case .rejected(let failure):
            return .rejected(failure)
        }
        guard let vertex = contract.stages.first(where: { $0.kind == .vertex }),
              let fragment = contract.stages.first(where: { $0.kind == .fragment }) else {
            return rejected(phase: .invariant, code: .shaderStageMissing)
        }
        let preparationResult = prepareShaderStages(
            contract: contract,
            combos: material.combos
        )
        if !contract.stages.allSatisfy({ $0.includes.isEmpty }) {
            switch preparationResult {
            case .accepted:
                return rejected(
                    phase: .shaderContract,
                    code: .shaderIncludeUnsupported
                )
            case .notApplicable:
                return rejected(
                    phase: .invariant,
                    code: .shaderPreparationInvariant
                )
            case .rejected(let failure): return .rejected(failure)
            }
        }

        // The prepared program is an R2 diagnostic handoff, not a new execution
        // authority. An R1-compatible raw program remains accepted even when
        // the bounded preprocessor rejects syntax it does not yet model. R3 must
        // resolve texture providers and color representation before prepared
        // source can become executable.
        let frontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex.source,
            fragmentSource: fragment.source
        )
        guard frontend.diagnostics.isEmpty else {
            let prepared: SceneShaderPreparedProgram
            switch preparationResult {
            case .accepted(let value): prepared = value
            case .notApplicable:
                return rejected(
                    phase: .invariant,
                    code: .shaderPreparationInvariant
                )
            case .rejected(let failure): return .rejected(failure)
            }
            let preparedFrontend = SceneAuthoredShaderFrontend.compile(
                vertexSource: prepared.vertex.source,
                fragmentSource: prepared.fragment.source
            )
            let unresolvedColorReasons = unresolvedColorContractReasons(contract)
            if preparedFrontend.diagnostics.isEmpty,
               preparedFrontend.program != nil,
               !unresolvedColorReasons.isEmpty,
               !prepared.colorContract.isResolved {
                return rejected(
                    phase: .compatibility,
                    code: .shaderColorContractUnproven,
                    details: unresolvedColorReasons
                )
            }
            return rejected(
                phase: .shaderFrontend,
                code: .shaderFrontendDiagnostic,
                details: frontend.diagnostics.map { $0.code.rawValue }
            )
        }
        guard let program = frontend.program else {
            return rejected(
                phase: .invariant,
                code: .shaderFrontendInvariant
            )
        }
        let scrollProfile = SceneAuthoredScrollShaderProfile.resolve(
            graph: graph,
            descriptor: input.descriptor,
            contract: contract,
            program: program
        )
        let bindingResult = BindingCompiler.compile(
            program: program,
            contract: contract,
            constants: material.constants,
            inferredFramebufferSlots: scrollProfile?.inferredFramebufferSlots ?? []
        )
        let bindings: BindingCompilation
        switch bindingResult {
        case .accepted(let value):
            bindings = value
        case .notApplicable:
            return rejected(phase: .invariant, code: .uniformBindingInvariant)
        case .rejected(let failure):
            return .rejected(failure)
        }

        return .accepted(Plan(
            cacheKey: contract.canonicalSHA256,
            program: program,
            renderState: renderState,
            mappedSize: mappedSize,
            framebufferTextureSlots: bindings.framebufferSlots,
            uniformBindings: bindings.uniformBindings,
            profile: scrollProfile == nil ? .genericFramebuffer : .scroll
        ))
    }

    static func compilerFailure(
        phase: SceneEffectStageCompilerFailure.Phase,
        code: SceneEffectStageCompilerFailure.Code,
        details: [String] = []
    ) -> SceneEffectStageCompilerFailure {
        .init(
            backend: compilerBackend,
            phase: phase,
            code: code,
            details: details
        )
    }

    private static func rejected<Value>(
        phase: SceneEffectStageCompilerFailure.Phase,
        code: SceneEffectStageCompilerFailure.Code,
        details: [String] = []
    ) -> SceneEffectStageBackendCompileResult<Value> {
        .rejected(compilerFailure(phase: phase, code: code, details: details))
    }

    private static func topologyFailure(
        graph: Graph,
        node: Graph.Node,
        layer: SceneRenderDescriptor.Layer,
        inputRole: SceneAuthoredEffectInputRole
    ) -> SceneEffectStageCompilerFailure? {
        let effect = graph.effects[0]
        guard layer.effects.indices.contains(effect.key.effectIndex) else {
            return compilerFailure(phase: .topology, code: .effectIndexOutOfRange)
        }
        let descriptor = layer.effects[effect.key.effectIndex]
        guard descriptor.id == effect.key.descriptorID else {
            return compilerFailure(phase: .topology, code: .descriptorIDMismatch)
        }
        guard descriptor.visible != false else {
            return compilerFailure(phase: .topology, code: .descriptorDisabled)
        }
        guard effect.nodeIndices == [node.nodeIndex] else {
            return compilerFailure(phase: .topology, code: .nodeCoverageMismatch)
        }
        guard SceneAuthoredEffectInputValidator.accepts(
            effect.input,
            layerID: graph.layerID,
            role: inputRole
        ) else {
            return compilerFailure(phase: .topology, code: .inputRoleMismatch)
        }
        guard effect.output == graph.finalOutput else {
            return compilerFailure(phase: .topology, code: .finalOutputMismatch)
        }
        guard node.effect == effect.key else {
            return compilerFailure(phase: .topology, code: .nodeEffectMismatch)
        }
        guard node.target == effect.output else {
            return compilerFailure(phase: .topology, code: .nodeTargetMismatch)
        }
        guard node.bindings.isEmpty else {
            return compilerFailure(
                phase: .topology,
                code: .explicitNodeBindingUnsupported
            )
        }
        return nil
    }

    private static func matchingContract(
        _ shaderPath: String,
        shaderContracts: [SceneShaderContract]
    ) -> SceneEffectStageBackendCompileResult<SceneShaderContract> {
        let matches = shaderContracts.filter {
            normalized($0.identity) == normalized(shaderPath)
        }
        guard !matches.isEmpty else {
            return rejected(phase: .shaderContract, code: .shaderContractMissing)
        }
        guard matches.count == 1, let contract = matches.first else {
            return rejected(phase: .shaderContract, code: .shaderContractAmbiguous)
        }
        guard contract.sourceKind == .authoredSource else {
            return rejected(
                phase: .shaderContract,
                code: .shaderSourceKindUnsupported
            )
        }
        guard contract.diagnostics.isEmpty else {
            return rejected(
                phase: .shaderContract,
                code: .shaderContractDiagnostic,
                details: contract.diagnostics.map { $0.code.rawValue }
            )
        }
        guard contract.stages.count == 2,
              Set(contract.stages.map(\.kind)) == Set([.vertex, .fragment]) else {
            return rejected(
                phase: .shaderContract,
                code: .shaderStageSetUnsupported
            )
        }
        return .accepted(contract)
    }

    private static func mappedSize(_ layer: SceneRenderDescriptor.Layer) -> CGSize? {
        guard let sizeWH = layer.sizeWH, sizeWH.count >= 2 else { return nil }
        let width = CGFloat(sizeWH[0])
        let height = CGFloat(sizeWH[1])
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func normalized(_ value: String?) -> String {
        value?.replacingOccurrences(of: "\\", with: "/").localizedLowercase ?? ""
    }
}
