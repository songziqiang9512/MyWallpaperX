import Foundation

enum SceneAuthoredEffectRenderPlanner {
    typealias Plan = SceneAuthoredEffectRenderPlan

    nonisolated static func plans(
        for descriptor: SceneRenderDescriptor,
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = []
    ) -> [SceneAuthoredEffectRenderPlan] {
        let definitions = Dictionary(
            grouping: descriptor.effectDefinitions,
            by: { normalizedPath($0.relativePath) }
        )
        let materials = Dictionary(
            grouping: descriptor.materialPasses,
            by: { normalizedPath($0.materialPath) }
        )
        return descriptor.layers.compactMap { layer -> Plan? in
            let visibleIndices = Set(layer.effects.enumerated().compactMap {
                $0.element.visible != false ? $0.offset : nil
            })
            let propertyInactiveCandidates = Set(
                layer.effects.enumerated().compactMap { effectIndex, effect in
                    let target = SceneDynamicTarget.effectVisibility(
                        layerID: layer.id,
                        effectIndex: effectIndex
                    )
                    return effect.visible == false
                            && startupInactiveEffectVisibilityTargets.contains(target)
                        ? effectIndex : nil
                }
            )
            let tentativeIndices = visibleIndices.union(
                propertyInactiveCandidates
            )
            guard !tentativeIndices.isEmpty else { return nil }
            let tentative = plan(
                for: layer,
                includedEffectIndices: tentativeIndices,
                definitions: definitions,
                materials: materials
            )
            let safePropertyInactiveIndices: Set<Int> = Set(
                tentative.effects.compactMap { effect -> Int? in
                    guard propertyInactiveCandidates.contains(
                        effect.key.effectIndex
                    ), effectLocalPassthroughIsSafe(
                        effect,
                        in: tentative
                    ) else { return nil }
                    return effect.key.effectIndex
                }
            )
            let selectedIndices = visibleIndices.union(
                safePropertyInactiveIndices
            )
            guard !selectedIndices.isEmpty else { return nil }
            return selectedIndices == tentativeIndices
                ? tentative
                : plan(
                    for: layer,
                    includedEffectIndices: selectedIndices,
                    definitions: definitions,
                    materials: materials
                )
        }
    }

    nonisolated private static func plan(
        for layer: SceneRenderDescriptor.Layer,
        includedEffectIndices: Set<Int>,
        definitions: [String: [SceneEffectDefinition]],
        materials: [String: [SceneRenderDescriptor.MaterialPassDescriptor]]
    ) -> Plan {
        var effects: [Plan.Effect] = []
        var targets: [Plan.RenderTarget] = []
        var nodes: [Plan.Node] = []
        var blockers: [Plan.Blocker] = []
        var chainInput = texture(.layerSource, layerID: layer.id)

        for (effectIndex, instance) in layer.effects.enumerated()
            where includedEffectIndices.contains(effectIndex) {
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
                if let compose = pass.compose, compose.boolValue == nil {
                    blockers.append(blocker(
                        key,
                        passIndex: pass.passIndex,
                        reason: .unsupportedCompose,
                        detail: "Compose must be a boolean before structural admission."
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

            let effectNodes = Array(nodes[effectNodeStart..<nodes.count])
            let layerLocalComposeSupported = definition.framebuffers.isEmpty
                && supportsLayerLocalCompose(
                    effectNodes,
                    input: chainInput,
                    output: texture(.effectOutput, effect: key)
                )
            if !layerLocalComposeSupported {
                for node in effectNodes where node.compose == .bool(true) {
                    blockers.append(blocker(
                        key,
                        passIndex: node.definitionPassIndex,
                        reason: .unsupportedCompose,
                        detail: "Compose requires an ordered layer-local full-frame material chain."
                    ))
                }
            }
            if outputPassCount == 0 {
                blockers.append(blocker(
                    key,
                    reason: .missingEffectOutput,
                    detail: "Effect has no material pass targeting the effect output."
                ))
            } else if outputPassCount > 1 && !layerLocalComposeSupported {
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

    /// Initially inactive stages enter the authored chain only when the exact
    /// stage can be skipped as a previous-current copy. Unsupported stages are
    /// omitted without changing active siblings; a later property change then
    /// follows the existing relaunch path.
    nonisolated private static func effectLocalPassthroughIsSafe(
        _ effect: Plan.Effect,
        in graph: Plan
    ) -> Bool {
        let nodesByIndex = Dictionary(grouping: graph.nodes, by: \.nodeIndex)
        var nodes: [Plan.Node] = []
        for nodeIndex in effect.nodeIndices {
            guard let matches = nodesByIndex[nodeIndex], matches.count == 1,
                  let node = matches.first,
                  node.effect == effect.key else { return false }
            nodes.append(node)
        }
        let stage = Plan(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: graph.renderTargets.filter {
                $0.texture.effect == effect.key
            },
            nodes: nodes,
            finalOutput: effect.output,
            blockers: graph.blockers.filter { $0.effect == effect.key }
        )
        guard stage.renderTargets.isEmpty,
              stage.blockers.isEmpty,
              stage.nodes.count == 1,
              let node = stage.nodes.first,
              node.effect == effect.key,
              node.kind == .material,
              node.target == effect.output,
              node.commandSource == nil,
              node.commandTarget == nil,
              node.conditions == nil,
              node.compose == nil || node.compose == .bool(false),
              node.bindings.allSatisfy({
                  $0.conditions == nil && $0.texture == effect.input
              }) else { return false }
        return true
    }

    nonisolated private static func supportsLayerLocalCompose(
        _ nodes: [Plan.Node],
        input: Plan.TextureIdentity,
        output: Plan.TextureIdentity
    ) -> Bool {
        guard nodes.count >= 2,
              nodes.dropLast().allSatisfy({ $0.compose == .bool(true) }),
              let final = nodes.last,
              final.compose == nil || final.compose == .bool(false) else {
            return false
        }
        return nodes.allSatisfy { node in
            node.kind == .material
                && node.target == output
                && node.commandSource == nil
                && node.commandTarget == nil
                // Condition admission prunes the ordered chain after this
                // raw-shape check; it must not be treated as a compose blocker.
                && node.bindings.allSatisfy {
                    $0.texture == input && $0.conditions == nil
                }
        }
    }

}
