import Foundation

nonisolated extension SceneGraphRenderTargetPlan {
    struct TargetDescriptor: Equatable {
        let extent: PixelExtent
        let format: TextureFormat
        let addressMode: UVAddressMode
        let isUnique: Bool
        let initialClear: ClearColor?

        func storageCompatible(with other: Self) -> Bool {
            extent == other.extent && format == other.format
        }
    }

    nonisolated static func targetDescriptor(
        _ target: Graph.RenderTarget,
        inputWidth: Int,
        inputHeight: Int
    ) -> TargetDescriptor? {
        guard let extent = pixelExtent(
            target.extent,
            inputWidth: inputWidth,
            inputHeight: inputHeight
        ), let format = textureFormat(target.format),
              let addressMode = uvAddressMode(target.uvs),
              target.conditions == nil else {
            return nil
        }
        let initialClear: ClearColor?
        if let rawClear = target.clear {
            guard let clear = authoredClear(rawClear) else { return nil }
            initialClear = clear
        } else {
            initialClear = nil
        }
        return TargetDescriptor(
            extent: extent,
            format: format,
            addressMode: addressMode,
            isUnique: target.declaredUnique,
            initialClear: initialClear
        )
    }

    /// Command compatibility must not depend on a probe extent. In particular,
    /// a 1x1 launch probe cannot collapse distinct scale declarations to the
    /// same clamped pixel extent and grant a later-invalid swap capability.
    nonisolated static func authoredSwapDescriptorsAreCompatible(
        in graph: Graph
    ) -> Bool {
        authoredCommandDescriptorsAreCompatible(
            in: graph,
            includeCopy: false
        )
    }

    /// A startup capability probe must not admit a copy merely because two
    /// different authored extent expressions collapse to 1x1. Runtime copy
    /// storage requires the same extent and format at every real size.
    nonisolated static func authoredCommandStorageDescriptorsAreCompatible(
        in graph: Graph
    ) -> Bool {
        authoredCommandDescriptorsAreCompatible(
            in: graph,
            includeCopy: true
        )
    }

    private nonisolated static func authoredCommandDescriptorsAreCompatible(
        in graph: Graph,
        includeCopy: Bool
    ) -> Bool {
        let declarations = Dictionary(grouping: graph.renderTargets, by: \.texture)
        for node in graph.nodes where node.kind == .swap
                || (includeCopy && node.kind == .copy) {
            guard let source = node.commandSource,
                  let target = node.commandTarget,
                  source != target,
                  let sourceDeclarations = declarations[source],
                  sourceDeclarations.count == 1,
                  let sourceDeclaration = sourceDeclarations.first,
                  let targetDeclarations = declarations[target],
                  targetDeclarations.count == 1,
                  let targetDeclaration = targetDeclarations.first,
                  normalizedExtent(sourceDeclaration.extent)
                    == normalizedExtent(targetDeclaration.extent),
                  let sourceDescriptor = targetDescriptor(
                      sourceDeclaration,
                      inputWidth: 1,
                      inputHeight: 1
                  ),
                  let targetDescriptor = targetDescriptor(
                      targetDeclaration,
                      inputWidth: 1,
                      inputHeight: 1
                  ),
                  sourceDescriptor.format == targetDescriptor.format else {
                return false
            }
            if node.kind == .swap,
               (sourceDescriptor.addressMode != targetDescriptor.addressMode
                || sourceDescriptor.isUnique != targetDescriptor.isUnique
                || sourceDescriptor.initialClear != targetDescriptor.initialClear) {
                return false
            }
        }
        return true
    }

    /// Capability probes must compare authored descriptor expressions, not a
    /// 1x1 resolved extent where different fit/scale values can both clamp to
    /// one pixel and appear equivalent.
    nonisolated static func authoredTargetDescriptorsAreEquivalent(
        _ targets: [Graph.RenderTarget]
    ) -> Bool {
        guard let first = targets.first,
              let firstDescriptor = targetDescriptor(
                  first,
                  inputWidth: 1,
                  inputHeight: 1
              ) else { return false }
        return targets.dropFirst().allSatisfy { target in
            guard authoredExtentsAreEquivalent(first.extent, target.extent),
                  let descriptor = targetDescriptor(
                      target,
                      inputWidth: 1,
                      inputHeight: 1
                  ) else { return false }
            return descriptor.format == firstDescriptor.format
                && descriptor.addressMode == firstDescriptor.addressMode
                && descriptor.isUnique == firstDescriptor.isUnique
                && descriptor.initialClear == firstDescriptor.initialClear
        }
    }

    private nonisolated static func normalizedExtent(
        _ authored: Graph.TargetExtent
    ) -> Graph.TargetExtent {
        Graph.TargetExtent(
            width: authored.width,
            height: authored.height,
            fit: authored.fit,
            scale: authored.scale == 1 ? nil : authored.scale
        )
    }

    private nonisolated static func authoredExtentsAreEquivalent(
        _ lhs: Graph.TargetExtent,
        _ rhs: Graph.TargetExtent
    ) -> Bool {
        let left = normalizedExtent(lhs)
        let right = normalizedExtent(rhs)
        return left.kind == right.kind
            && left.width == right.width
            && left.height == right.height
            && left.fit == right.fit
            && left.scale == right.scale
    }

    /// Confirms that this typed Plan is the canonical interpretation of the
    /// supplied Graph declarations. Callers consume Plan descriptors only;
    /// raw spelling differences are accepted when they resolve identically.
    nonisolated func matchesSourceDeclarations(in graph: Graph) -> Bool {
        let identities = logicalTargets.map(\.identity)
        guard Set(identities).count == identities.count,
              graph.renderTargets.count == identities.count else {
            return false
        }
        var declarations: [Graph.TextureIdentity: Graph.RenderTarget] = [:]
        for target in graph.renderTargets {
            guard declarations.updateValue(target, forKey: target.texture) == nil else {
                return false
            }
        }
        guard Set(declarations.keys) == Set(identities) else {
            return false
        }
        return logicalTargets.allSatisfy { logical in
            guard let declaration = declarations[logical.identity],
                  let descriptor = Self.targetDescriptor(
                      declaration,
                      inputWidth: inputExtent.width,
                      inputHeight: inputExtent.height
                  ) else {
                return false
            }
            return descriptor == .init(
                extent: logical.extent,
                format: logical.format,
                addressMode: logical.addressMode,
                isUnique: logical.isUnique,
                initialClear: logical.initialClear
            )
        }
    }

    nonisolated static func pixelExtent(
        _ authored: Graph.TargetExtent,
        inputWidth: Int,
        inputHeight: Int
    ) -> PixelExtent? {
        guard inputWidth > 0, inputHeight > 0 else { return nil }
        let normalized = Graph.TargetExtent(
            width: authored.width,
            height: authored.height,
            fit: authored.fit,
            scale: authored.scale
        )
        guard authored.kind == normalized.kind,
              authored.first == normalized.first,
              authored.second == normalized.second,
              normalized.kind != .unsupported else {
            return nil
        }

        var width = authored.width ?? Double(inputWidth)
        var height = authored.height ?? Double(inputHeight)
        if let fit = authored.fit {
            let fitDivisor = max(width / fit, height / fit, 1)
            width /= fitDivisor
            height /= fitDivisor
        }
        if let scale = authored.scale {
            width /= scale
            height /= scale
        }

        let maximumInteger = Double(Int.max)
        guard width.isFinite, height.isFinite,
              width > 0, height > 0,
              width < maximumInteger, height < maximumInteger else {
            return nil
        }
        return PixelExtent(
            width: max(1, Int(width.rounded(.down))),
            height: max(1, Int(height.rounded(.down)))
        )
    }

    nonisolated static func permitsHistorySeed(
        _ identity: Graph.TextureIdentity,
        feedbackHistory: FeedbackHistoryProfile?,
        declarations: [Graph.TextureIdentity: Graph.RenderTarget]
    ) -> Bool {
        if declarations[identity]?.declaredUnique == true { return true }
        return feedbackHistory?.seedTargets.contains(identity) == true
    }

    nonisolated static func validEffectKey(
        _ key: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        key.layerID == layerID && key.effectIndex >= 0
            && !key.descriptorID.isEmpty
    }

    nonisolated static func validOutput(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .effectOutput
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name == nil
    }

    nonisolated static func validTargetIdentity(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .framebuffer
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false
    }

    private nonisolated static func textureFormat(
        _ authored: String?
    ) -> TextureFormat? {
        switch authored?.lowercased() {
        case "r8": return .r8
        case "rg88": return .rg88
        case "r16f": return .r16f
        case "rg1616f": return .rg1616f
        case "rgba_backbuffer": return .rgbaBackbuffer
        case "rgba8888": return .rgba8888
        default: return nil
        }
    }

    private nonisolated static func uvAddressMode(
        _ authored: SceneJSONValue?
    ) -> UVAddressMode? {
        switch authored {
        case nil: return .clampToEdge
        case .string("repeat"): return .repeatWrap
        default: return nil
        }
    }
}

/// Shared target-topology predicate for an effect-local previous-current
/// fallback. It accepts only non-persistent framebuffer work whose reads are
/// dominated by authored writes and whose terminal output consumes that work.
nonisolated enum SceneEffectLocalPreviousCurrentTopology {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static func acceptsFramebufferGraph(
        _ graph: Graph,
        effect: Graph.Effect
    ) -> Bool {
        let targetIdentities = Set(graph.renderTargets.map(\.texture))
        guard graph.effects.count == 1,
              graph.effects.first?.key == effect.key,
              graph.finalOutput == effect.output,
              graph.blockers.isEmpty,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              !targetIdentities.isEmpty,
              targetIdentities.count == graph.renderTargets.count,
              graph.renderTargets.allSatisfy({ target in
                  target.texture.kind == .framebuffer
                    && target.texture.layerID == graph.layerID
                    && target.texture.effect == effect.key
                    && target.texture.name?.isEmpty == false
                    && !target.declaredUnique
                    && target.clear == nil
                    && target.conditions == nil
              }),
              graph.nodes.count >= 2,
              SceneGraphRenderTargetPlan
                .authoredCommandStorageDescriptorsAreCompatible(in: graph),
              let inputRole = SceneAuthoredEffectInputValidator.role(
                  for: effect.input,
                  layerID: graph.layerID
              ),
              case let .success(targetPlan) = SceneGraphRenderTargetPlan.make(
                  graph: graph,
                  inputRole: inputRole,
                  inputWidth: 1,
                  inputHeight: 1
              ),
              targetPlan.logicalTargets.allSatisfy({
                  !$0.lifetime.requiresHistorySeed
              }) else { return false }

        var initializedTargets = Set<Graph.TextureIdentity>()
        var consumedTargets = Set<Graph.TextureIdentity>()
        var materialOrdinals: [Int] = []
        var terminalReadsFramebuffer = false
        for (offset, node) in graph.nodes.enumerated() {
            guard node.effect == effect.key,
                  node.conditions == nil,
                  node.compose == nil || node.compose == .bool(false)
            else { return false }

            switch node.kind {
            case .material:
                guard let ordinal = node.materialOrdinal,
                      node.commandSource == nil,
                      node.commandTarget == nil,
                      node.bindings.allSatisfy({ binding in
                          binding.conditions == nil
                            && (binding.texture == effect.input
                                || (targetIdentities.contains(binding.texture)
                                    && initializedTargets.contains(
                                        binding.texture
                                    )))
                      }) else { return false }
                materialOrdinals.append(ordinal)
                consumedTargets.formUnion(node.bindings.compactMap { binding in
                    targetIdentities.contains(binding.texture)
                        ? binding.texture : nil
                })
                if node.target == effect.output {
                    guard offset == graph.nodes.indices.last,
                          node.bindings.contains(where: {
                              targetIdentities.contains($0.texture)
                          }) else { return false }
                    terminalReadsFramebuffer = true
                } else {
                    guard let target = node.target,
                          targetIdentities.contains(target) else { return false }
                    initializedTargets.insert(target)
                }

            case .copy:
                guard node.materialOrdinal == nil,
                      node.target == nil,
                      node.bindings.isEmpty,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      targetIdentities.contains(source),
                      initializedTargets.contains(source),
                      targetIdentities.contains(target) else { return false }
                consumedTargets.insert(source)
                initializedTargets.insert(target)

            case .swap:
                guard node.materialOrdinal == nil,
                      node.target == nil,
                      node.bindings.isEmpty,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      targetIdentities.contains(source),
                      initializedTargets.contains(source),
                      targetIdentities.contains(target),
                      initializedTargets.contains(target) else { return false }
                consumedTargets.insert(source)
                consumedTargets.insert(target)

            case .unknownCommand:
                return false
            }
        }
        return terminalReadsFramebuffer
            && materialOrdinals.count >= 2
            && zip(materialOrdinals, materialOrdinals.dropFirst())
                .allSatisfy({ $0 < $1 })
            && initializedTargets == targetIdentities
            && consumedTargets == targetIdentities
    }
}
