import Foundation

/// Discovers the bounded time-of-day scalar producer directly from authored
/// `multiply` pass constants. Selection depends on that public semantic key,
/// the exact wrapper/source grammar, and the typed target only; effect names,
/// paths, hashes, and dedicated plans are not part of admission.
nonisolated enum SceneTimeOfDayEffectScriptProgramCompiler {
    /// Launch-time bounds for the complete descriptor-derived producer scan.
    /// They are intentionally separate from the per-source lexer/parser limits.
    nonisolated struct Limits: Equatable, Sendable {
        let maximumLayerCount: Int
        let maximumEffectCount: Int
        let maximumPassCount: Int
        let maximumConstantShaderValueCount: Int
        let maximumMultiplyCandidateCount: Int
        let maximumScriptCandidateCount: Int
        let maximumAggregateSourceUTF8ByteCount: Int

        nonisolated init(
            maximumLayerCount: Int = 512,
            maximumEffectCount: Int = 1_024,
            maximumPassCount: Int = 1_024,
            maximumConstantShaderValueCount: Int = 4_096,
            maximumMultiplyCandidateCount: Int = 128,
            maximumScriptCandidateCount: Int = 64,
            maximumAggregateSourceUTF8ByteCount: Int = 64 * 1_024
        ) {
            self.maximumLayerCount = max(0, maximumLayerCount)
            self.maximumEffectCount = max(0, maximumEffectCount)
            self.maximumPassCount = max(0, maximumPassCount)
            self.maximumConstantShaderValueCount = max(
                0, maximumConstantShaderValueCount
            )
            self.maximumMultiplyCandidateCount = max(
                0, maximumMultiplyCandidateCount
            )
            self.maximumScriptCandidateCount = max(
                0, maximumScriptCandidateCount
            )
            self.maximumAggregateSourceUTF8ByteCount = max(
                0, maximumAggregateSourceUTF8ByteCount
            )
        }
    }

    nonisolated struct Failure: Error, Equatable, Sendable {
        nonisolated enum Code: String, Equatable, Sendable {
            case invalidLayerIdentity = "invalid-layer-identity"
            case invalidPassIdentity = "invalid-pass-identity"
            case layerBudgetExceeded = "layer-budget-exceeded"
            case effectBudgetExceeded = "effect-budget-exceeded"
            case passBudgetExceeded = "pass-budget-exceeded"
            case constantBudgetExceeded = "constant-budget-exceeded"
            case multiplyCandidateBudgetExceeded =
                "multiply-candidate-budget-exceeded"
            case scriptCandidateBudgetExceeded =
                "script-candidate-budget-exceeded"
            case sourceBudgetExceeded = "source-budget-exceeded"
            case aggregateSourceBudgetExceeded =
                "aggregate-source-budget-exceeded"
            case duplicateTarget = "duplicate-target"
        }

        let code: Code
        let observedCount: Int?
        let limit: Int?

        nonisolated init(
            _ code: Code,
            observedCount: Int? = nil,
            limit: Int? = nil
        ) {
            self.code = code
            self.observedCount = observedCount
            self.limit = limit
        }

        nonisolated var isDescriptorIntegrityFailure: Bool {
            switch code {
            case .invalidLayerIdentity, .invalidPassIdentity, .duplicateTarget:
                true
            case .layerBudgetExceeded, .effectBudgetExceeded,
                 .passBudgetExceeded, .constantBudgetExceeded,
                 .multiplyCandidateBudgetExceeded,
                 .scriptCandidateBudgetExceeded,
                 .sourceBudgetExceeded,
                 .aggregateSourceBudgetExceeded:
                false
            }
        }

        nonisolated var diagnostic: String {
            guard let observedCount, let limit else { return code.rawValue }
            return "\(code.rawValue) observed=\(observedCount) limit=\(limit)"
        }
    }

    nonisolated static func compile(
        descriptor: SceneRenderDescriptor,
        limits: Limits = .init()
    ) -> Result<SceneTimeOfDayEffectScriptProgram, Failure> {
        guard descriptor.layers.count <= limits.maximumLayerCount else {
            return .failure(budgetFailure(
                .layerBudgetExceeded,
                used: 0,
                adding: descriptor.layers.count,
                limit: limits.maximumLayerCount
            ))
        }

        var layerIDs: Set<Int> = []
        var effectCount = 0
        var passCount = 0
        var constantCount = 0
        var multiplyCandidateCount = 0
        var scriptCandidateCount = 0
        var aggregateSourceByteCount = 0
        var bindings: [SceneTimeOfDayEffectScriptBinding] = []
        for (layerIndex, layer) in descriptor.layers.enumerated() {
            guard layerIndex == layer.layerIndex,
                  layerIDs.insert(layer.id).inserted else {
                return .failure(.init(.invalidLayerIdentity))
            }
            guard consume(
                layer.effects.count,
                used: &effectCount,
                maximum: limits.maximumEffectCount
            ) else {
                return .failure(budgetFailure(
                    .effectBudgetExceeded,
                    used: effectCount,
                    adding: layer.effects.count,
                    limit: limits.maximumEffectCount
                ))
            }
            for (effectIndex, effect) in layer.effects.enumerated() {
                guard consume(
                    effect.passes.count,
                    used: &passCount,
                    maximum: limits.maximumPassCount
                ) else {
                    return .failure(budgetFailure(
                        .passBudgetExceeded,
                        used: passCount,
                        adding: effect.passes.count,
                        limit: limits.maximumPassCount
                    ))
                }
                for (passIndex, pass) in effect.passes.enumerated() {
                    guard passIndex == pass.passIndex else {
                        return .failure(.init(.invalidPassIdentity))
                    }
                    guard consume(
                        pass.constantShaderValues.count,
                        used: &constantCount,
                        maximum: limits.maximumConstantShaderValueCount
                    ) else {
                        return .failure(budgetFailure(
                            .constantBudgetExceeded,
                            used: constantCount,
                            adding: pass.constantShaderValues.count,
                            limit: limits.maximumConstantShaderValueCount
                        ))
                    }
                    let name = "multiply"
                    guard let value = pass.constantShaderValues[name] else {
                        continue
                    }
                    guard consume(
                        1,
                        used: &multiplyCandidateCount,
                        maximum: limits.maximumMultiplyCandidateCount
                    ) else {
                        return .failure(budgetFailure(
                            .multiplyCandidateBudgetExceeded,
                            used: multiplyCandidateCount,
                            adding: 1,
                            limit: limits.maximumMultiplyCandidateCount
                        ))
                    }
                    if let source = value.scriptSource {
                        guard consume(
                            1,
                            used: &scriptCandidateCount,
                            maximum: limits.maximumScriptCandidateCount
                        ) else {
                            return .failure(budgetFailure(
                                .scriptCandidateBudgetExceeded,
                                used: scriptCandidateCount,
                                adding: 1,
                                limit: limits.maximumScriptCandidateCount
                            ))
                        }
                        guard let sourceByteCount =
                                SceneTimeOfDayEffectScriptCompiler
                                    .boundedSourceUTF8ByteCount(source) else {
                            return .failure(.init(
                                .sourceBudgetExceeded,
                                observedCount:
                                    SceneTimeOfDayEffectScriptCompiler
                                        .maximumSourceUTF8ByteCount + 1,
                                limit: SceneTimeOfDayEffectScriptCompiler
                                    .maximumSourceUTF8ByteCount
                            ))
                        }
                        guard consume(
                            sourceByteCount,
                            used: &aggregateSourceByteCount,
                            maximum: limits.maximumAggregateSourceUTF8ByteCount
                        ) else {
                            return .failure(budgetFailure(
                                .aggregateSourceBudgetExceeded,
                                used: aggregateSourceByteCount,
                                adding: sourceByteCount,
                                limit: limits.maximumAggregateSourceUTF8ByteCount
                            ))
                        }
                    }
                    guard let binding = SceneTimeOfDayEffectScriptCompiler.compile(
                        value: value,
                        target: .effectConstant(
                            layerID: layer.id,
                            effectIndex: effectIndex,
                            passIndex: pass.passIndex,
                            name: name
                        )
                    ) else {
                        continue
                    }
                    bindings.append(binding)
                }
            }
        }

        let targets = bindings.map(\.definition.target)
        guard Set(targets).count == targets.count else {
            return .failure(.init(.duplicateTarget))
        }
        return .success(SceneTimeOfDayEffectScriptProgram(bindings: bindings))
    }

    private nonisolated static func consume(
        _ amount: Int,
        used: inout Int,
        maximum: Int
    ) -> Bool {
        guard amount >= 0, used <= maximum,
              amount <= maximum - used else { return false }
        used += amount
        return true
    }

    private nonisolated static func budgetFailure(
        _ code: Failure.Code,
        used: Int,
        adding amount: Int,
        limit: Int
    ) -> Failure {
        let (sum, overflow) = used.addingReportingOverflow(amount)
        return .init(
            code,
            observedCount: overflow ? Int.max : sum,
            limit: limit
        )
    }
}
