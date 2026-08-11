import Foundation

enum SceneAuthoredEffectRenderPlanner {
    typealias Plan = SceneAuthoredEffectRenderPlan

    nonisolated static func plans(
        for descriptor: SceneRenderDescriptor
    ) -> [SceneAuthoredEffectRenderPlan] {
        let definitions = Dictionary(
            grouping: descriptor.effectDefinitions,
            by: { normalizedPath($0.relativePath) }
        )
        let materials = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalizedPath($0.materialPath) }
        )
        return descriptor.layers.compactMap { layer in
            guard layer.effects.contains(where: { $0.visible != false }) else { return nil }
            return plan(for: layer, definitions: definitions, materials: materials)
        }
    }

    nonisolated private static func plan(
        for layer: SceneRenderDescriptor.Layer,
        definitions: [String: [SceneEffectDefinition]],
        materials: [String: [SceneRenderDescriptor.MaterialPassDescriptor]]
    ) -> Plan {
        var effects: [Plan.Effect] = []
        var targets: [Plan.RenderTarget] = []
        var nodes: [Plan.Node] = []
        var blockers: [Plan.Blocker] = []
        var chainInput = texture(.layerSource, layerID: layer.id)

        for (effectIndex, instance) in layer.effects.enumerated() where instance.visible != false {
            let key = Plan.EffectKey(
                layerID: layer.id,
                effectIndex: effectIndex,
                descriptorID: instance.id
            )
            let effectNodeStart = nodes.count
            let matches = definitions[normalizedPath(instance.file)] ?? []
            guard matches.count == 1, let definition = matches.first else {
                blockers.append(blocker(
                    key,
                    reason: matches.isEmpty ? .missingDefinition : .ambiguousDefinition,
                    detail: "Expected one effect definition for \(instance.file), found \(matches.count)."
                ))
                effects.append(.init(
                    key: key,
                    definitionPath: instance.file,
                    input: chainInput,
                    output: chainInput,
                    nodeIndices: []
                ))
                continue
            }
            if !instance.passes.isEmpty, instance.passes.count != definition.materialPassCount {
                blockers.append(blocker(
                    key,
                    reason: .instancePassCountMismatch,
                    detail: "Instance has \(instance.passes.count) material overrides; definition has \(definition.materialPassCount) material passes."
                ))
            }
            if definition.functions != nil {
                blockers.append(blocker(
                    key,
                    reason: .unsupportedFunctions,
                    detail: "Effect functions require a live function executor."
                ))
            }
            if !definition.unknownFieldPaths.isEmpty {
                blockers.append(blocker(
                    key,
                    reason: .unknownDefinitionFields,
                    detail: definition.unknownFieldPaths.joined(separator: ", ")
                ))
            }

            let framebufferGroups = Dictionary(
                grouping: definition.framebuffers,
                by: \.name
            )
            let framebufferDefinitions = framebufferGroups.compactMapValues { group in
                group.count == 1 ? group[0] : nil
            }
            for (name, group) in framebufferGroups where group.count != 1 {
                blockers.append(blocker(
                    key,
                    reason: .duplicateFramebuffer,
                    detail: "Framebuffer \(name) is declared \(group.count) times."
                ))
            }
            for framebuffer in definition.framebuffers {
                let extent = targetExtent(framebuffer)
                if extent.kind == .unsupported {
                    blockers.append(blocker(
                        key,
                        reason: .unsupportedFramebufferExtent,
                        detail: "Framebuffer \(framebuffer.name) has an unsupported extent."
                    ))
                }
                if !supportedFramebufferFormats.contains(
                    framebuffer.format?.lowercased() ?? ""
                ) {
                    blockers.append(blocker(
                        key,
                        reason: .unsupportedFramebufferFormat,
                        detail: "Framebuffer \(framebuffer.name) uses format \(framebuffer.format ?? "<missing>")."
                    ))
                }
                if framebuffer.unique != nil, framebuffer.unique?.boolValue == nil {
                    blockers.append(blocker(
                        key,
                        reason: .invalidFramebufferUnique,
                        detail: "Framebuffer \(framebuffer.name) has a non-boolean unique field."
                    ))
                }
                if !validClear(framebuffer.clear) {
                    blockers.append(blocker(
                        key,
                        reason: .invalidFramebufferClear,
                        detail: "Framebuffer \(framebuffer.name) has an invalid clear value."
                    ))
                }
                if let uvs = framebuffer.uvs, uvs.stringValue != "repeat" {
                    blockers.append(blocker(
                        key,
                        reason: .unsupportedFramebufferUVs,
                        detail: "Framebuffer \(framebuffer.name) has unsupported UV semantics."
                    ))
                }
                if framebuffer.conditions != nil {
                    blockers.append(blocker(
                        key,
                        reason: .unsupportedCondition,
                        detail: "Framebuffer \(framebuffer.name) has a runtime condition."
                    ))
                }
                targets.append(.init(
                    texture: framebufferTexture(key, name: framebuffer.name),
                    extent: extent,
                    format: framebuffer.format,
                    declaredUnique: framebuffer.unique?.boolValue == true,
                    clear: framebuffer.clear,
                    uvs: framebuffer.uvs,
                    conditions: framebuffer.conditions
                ))
            }

            var materialOrdinal = 0
            var outputPassCount = 0
            for pass in definition.passes {
                if pass.conditions != nil {
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .unsupportedCondition,
                        detail: "Pass has a runtime condition."
                    ))
                }
                if let compose = pass.compose, compose.boolValue != false {
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .unsupportedCompose,
                        detail: "Compose is preserved raw until its input identity is verified."
                    ))
                }

                let hasMaterial = pass.materialPath != nil
                let hasCommand = pass.command != nil
                guard hasMaterial != hasCommand else {
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .invalidPassShape,
                        detail: "A definition pass must contain exactly one material or command."
                    ))
                    continue
                }

                if let materialPath = pass.materialPath {
                    let materialMatches = materials[normalizedPath(materialPath)] ?? []
                    let material = materialMatches.count == 1 ? materialMatches[0] : nil
                    if materialMatches.count != 1 {
                        blockers.append(blocker(
                            key,
                            passIndex: pass.passIndex,
                            reason: materialMatches.isEmpty ? .missingMaterial : .ambiguousMaterial,
                            detail: "Expected one material pass for \(materialPath), found \(materialMatches.count)."
                        ))
                    }
                    let target: Plan.TextureIdentity
                    if let name = pass.target {
                        target = resolveFramebuffer(
                            name,
                            key: key,
                            definitions: framebufferDefinitions,
                            passIndex: pass.passIndex,
                            blockers: &blockers
                        )
                    } else {
                        target = texture(.effectOutput, effect: key)
                        outputPassCount += 1
                    }
                    let bindings = resolvedBindings(
                        pass.bindings,
                        chainInput: chainInput,
                        key: key,
                        definitions: framebufferDefinitions,
                        passIndex: pass.passIndex,
                        blockers: &blockers
                    )
                    nodes.append(.init(
                        nodeIndex: nodes.count,
                        effect: key,
                        definitionPassIndex: pass.passIndex,
                        materialOrdinal: materialOrdinal,
                        instancePassIndex: instance.passes.isEmpty
                            ? nil
                            : instance.passes.indices.contains(materialOrdinal)
                                ? instance.passes[materialOrdinal].passIndex
                                : nil,
                        kind: .material,
                        materialPath: materialPath,
                        materialPassID: material?.id,
                        target: target,
                        bindings: bindings,
                        commandSource: nil,
                        commandTarget: nil,
                        compose: pass.compose,
                        conditions: pass.conditions
                    ))
                    materialOrdinal += 1
                    continue
                }

                let source = pass.source.map {
                    resolveFramebuffer(
                        $0,
                        key: key,
                        definitions: framebufferDefinitions,
                        passIndex: pass.passIndex,
                        blockers: &blockers
                    )
                }
                let target = pass.target.map {
                    resolveFramebuffer(
                        $0,
                        key: key,
                        definitions: framebufferDefinitions,
                        passIndex: pass.passIndex,
                        blockers: &blockers
                    )
                }
                let kind: Plan.NodeKind
                switch pass.command {
                case "copy": kind = .copy
                case "swap": kind = .swap
                default:
                    kind = .unknownCommand
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .unknownCommand,
                        detail: "Unsupported command \(pass.command ?? "<missing>")."
                    ))
                }
                if source == nil || target == nil || source == target {
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .incompatibleCommand,
                        detail: "Copy/swap requires distinct declared source and target framebuffers."
                    ))
                }
                nodes.append(.init(
                    nodeIndex: nodes.count,
                    effect: key,
                    definitionPassIndex: pass.passIndex,
                    materialOrdinal: nil,
                    instancePassIndex: nil,
                    kind: kind,
                    materialPath: nil,
                    materialPassID: nil,
                    target: nil,
                    bindings: [],
                    commandSource: source,
                    commandTarget: target,
                    compose: pass.compose,
                    conditions: pass.conditions
                ))
            }

            if outputPassCount == 0 {
                blockers.append(blocker(
                    key,
                    reason: .missingEffectOutput,
                    detail: "Effect has no material pass targeting the effect output."
                ))
            } else if outputPassCount > 1 {
                blockers.append(blocker(
                    key,
                    reason: .multipleEffectOutputs,
                    detail: "Effect has \(outputPassCount) material passes targeting the effect output."
                ))
            }
            let output = outputPassCount == 0 ? chainInput : texture(.effectOutput, effect: key)
            effects.append(.init(
                key: key,
                definitionPath: definition.relativePath,
                input: chainInput,
                output: output,
                nodeIndices: Array(effectNodeStart..<nodes.count)
            ))
            chainInput = output
        }

        return Plan(
            layerID: layer.id,
            effects: effects,
            renderTargets: targets,
            nodes: nodes,
            finalOutput: chainInput,
            blockers: blockers
        )
    }

}
