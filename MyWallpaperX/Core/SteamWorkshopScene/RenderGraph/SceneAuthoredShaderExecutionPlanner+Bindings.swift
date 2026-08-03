import Foundation

extension SceneAuthoredShaderExecutionPlanner {
    nonisolated struct BindingCompilation {
        let framebufferSlots: [Int]
        let uniformBindings: [Plan.UniformBinding]
    }

    nonisolated enum BindingCompiler {
        static func compile(
            program: SceneAuthoredShaderProgram,
            contract: SceneShaderContract,
            constants: [String: SceneDocument.ShaderValue],
            inferredFramebufferSlots: Set<Int>
        ) -> SceneEffectStageBackendCompileResult<BindingCompilation> {
            let slotResult = framebufferSlots(
                program: program,
                contract: contract,
                inferredSlots: inferredFramebufferSlots
            )
            let slots: [Int]
            switch slotResult {
            case .accepted(let value):
                slots = value
            case .notApplicable:
                return .rejected(failure(
                    phase: .invariant,
                    code: .uniformBindingInvariant
                ))
            case .rejected(let failure):
                return .rejected(failure)
            }

            let keyResult = materialConstantKeys(program: program, contract: contract)
            let materialKeys: [String: String]
            switch keyResult {
            case .accepted(let value):
                materialKeys = value
            case .notApplicable:
                return .rejected(failure(
                    phase: .invariant,
                    code: .uniformBindingInvariant
                ))
            case .rejected(let failure):
                return .rejected(failure)
            }

            var bindings: [Plan.UniformBinding] = []
            for field in program.uniformLayout.fields {
                if let source = builtinSource(field, framebufferSlots: Set(slots)) {
                    bindings.append(.init(field: field, source: source))
                    continue
                }
                let sourceResult = constantSource(
                    field,
                    authored: constants,
                    materialKey: materialKeys[field.name]
                )
                switch sourceResult {
                case .accepted(let source):
                    bindings.append(.init(field: field, source: source))
                case .notApplicable:
                    return .rejected(failure(
                        phase: .invariant,
                        code: .uniformBindingInvariant,
                        details: [field.name]
                    ))
                case .rejected(let failure):
                    return .rejected(failure)
                }
            }
            return .accepted(.init(
                framebufferSlots: slots,
                uniformBindings: bindings
            ))
        }

        private static func framebufferSlots(
            program: SceneAuthoredShaderProgram,
            contract: SceneShaderContract,
            inferredSlots: Set<Int>
        ) -> SceneEffectStageBackendCompileResult<[Int]> {
            var slots: [Int] = []
            for texture in program.textureBindings {
                let annotated = contract.stages.contains { stage in
                    stage.declarations.contains { declaration in
                        declaration.kind == .uniform
                            && declaration.type == "sampler2D"
                            && declaration.name == texture.name
                            && stage.annotations.contains {
                                $0.line == declaration.line && isFramebuffer($0.value)
                            }
                    }
                }
                guard annotated || inferredSlots.contains(texture.slot) else {
                    return .rejected(failure(
                        phase: .textureBinding,
                        code: .framebufferSlotUnproven,
                        details: [texture.name, "slot=\(texture.slot)"]
                    ))
                }
                slots.append(texture.slot)
            }
            return .accepted(slots.sorted())
        }

        private static func materialConstantKeys(
            program: SceneAuthoredShaderProgram,
            contract: SceneShaderContract
        ) -> SceneEffectStageBackendCompileResult<[String: String]> {
            let uniformNames = Set(program.uniformLayout.fields.map(\.name))
            var keysByUniform: [String: String] = [:]
            var uniformByKey: [String: String] = [:]
            for stage in contract.stages {
                for declaration in stage.declarations
                where declaration.kind == .uniform
                    && declaration.type.caseInsensitiveCompare("sampler2D") != .orderedSame
                    && uniformNames.contains(declaration.name) {
                    let annotations = stage.annotations.filter {
                        $0.line == declaration.line
                    }
                    for annotation in annotations {
                        guard case .object(let object) = annotation.value,
                              let rawKey = object["material"] else {
                            continue
                        }
                        guard let key = rawKey.stringValue,
                              !key.isEmpty,
                              key == key.trimmingCharacters(
                                  in: .whitespacesAndNewlines
                              ) else {
                            return .rejected(failure(
                                phase: .uniformBinding,
                                code: .materialAnnotationInvalid,
                                details: [declaration.name]
                            ))
                        }
                        if let existing = keysByUniform[declaration.name],
                           existing != key {
                            return .rejected(failure(
                                phase: .uniformBinding,
                                code: .materialAliasConflict,
                                details: [declaration.name]
                            ))
                        }
                        if let owner = uniformByKey[key], owner != declaration.name {
                            return .rejected(failure(
                                phase: .uniformBinding,
                                code: .materialKeyCollision,
                                details: [key, owner, declaration.name]
                            ))
                        }
                        keysByUniform[declaration.name] = key
                        uniformByKey[key] = declaration.name
                    }
                }
            }
            return .accepted(keysByUniform)
        }

        private static func builtinSource(
            _ field: SceneAuthoredShaderUniformLayout.Field,
            framebufferSlots: Set<Int>
        ) -> Plan.UniformBinding.Source? {
            switch (field.name, field.type) {
            case ("mwxRenderSize", .float2): .renderSize
            case ("g_ModelViewProjectionMatrix", .float4x4): .modelViewProjection
            case ("g_Time", .float): .time
            case ("g_Daytime", .float): .dayTime
            case ("g_Frametime", .float): .frameTime
            case ("g_PointerPosition", .float2): .pointerPosition
            case ("g_PointerPositionLast", .float2): .pointerPositionLast
            case ("g_Screen", .float3): .screen
            case ("g_TexelSize", .float2): .texelSize(scale: 1)
            case ("g_TexelSizeHalf", .float2): .texelSize(scale: 0.5)
            default: textureBuiltin(field, framebufferSlots: framebufferSlots)
            }
        }

        private static func textureBuiltin(
            _ field: SceneAuthoredShaderUniformLayout.Field,
            framebufferSlots: Set<Int>
        ) -> Plan.UniformBinding.Source? {
            for slot in framebufferSlots {
                if field.name == "g_Texture\(slot)Resolution", field.type == .float4 {
                    return .textureResolution(slot: slot)
                }
            }
            return nil
        }

        private static func constantSource(
            _ field: SceneAuthoredShaderUniformLayout.Field,
            authored: [String: SceneDocument.ShaderValue],
            materialKey: String?
        ) -> SceneEffectStageBackendCompileResult<Plan.UniformBinding.Source> {
            var matches: [SceneDocument.ShaderValue] = []
            if let value = authored[field.name] { matches.append(value) }
            if let materialKey,
               materialKey != field.name,
               let value = authored[materialKey] {
                matches.append(value)
            }
            guard !matches.isEmpty else {
                return .rejected(failure(
                    phase: .uniformBinding,
                    code: .uniformSourceMissing,
                    details: [field.name]
                ))
            }
            guard matches.count == 1, let value = matches.first else {
                return .rejected(failure(
                    phase: .uniformBinding,
                    code: .uniformSourceAmbiguous,
                    details: [field.name]
                ))
            }
            guard value.userBinding == nil else {
                return .rejected(failure(
                    phase: .uniformBinding,
                    code: .dynamicUniformUnsupported,
                    details: [field.name]
                ))
            }
            guard value.timeline == nil, value.timelineDiagnostics.isEmpty else {
                return .rejected(failure(
                    phase: .uniformBinding,
                    code: .timelineUniformUnsupported,
                    details: [field.name]
                ))
            }
            guard let components = value.components,
                  components.count == componentCount(field.type),
                  SceneAuthoredShaderUniformBinder.canEncodeConstant(
                      components,
                      as: field.type
                  ) else {
                return .rejected(failure(
                    phase: .uniformBinding,
                    code: .uniformConstantInvalid,
                    details: [field.name]
                ))
            }
            return .accepted(.constant(components))
        }

        private static func componentCount(
            _ type: SceneAuthoredShaderValueType
        ) -> Int {
            switch type {
            case .bool, .int, .uint, .float: 1
            case .int2, .uint2, .float2: 2
            case .int3, .uint3, .float3: 3
            case .int4, .uint4, .float4, .float2x2: 4
            case .float3x3: 9
            case .float4x4: 16
            }
        }

        private static func isFramebuffer(_ value: SceneJSONValue) -> Bool {
            guard case .object(let object) = value,
                  object["material"]?.stringValue?.localizedLowercase == "framebuffer" else {
                return false
            }
            return true
        }

        private static func failure(
            phase: SceneEffectStageCompilerFailure.Phase,
            code: SceneEffectStageCompilerFailure.Code,
            details: [String] = []
        ) -> SceneEffectStageCompilerFailure {
            SceneAuthoredShaderExecutionPlanner.compilerFailure(
                phase: phase,
                code: code,
                details: details
            )
        }
    }
}
