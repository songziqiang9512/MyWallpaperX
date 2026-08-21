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
        let declarations = Dictionary(grouping: graph.renderTargets, by: \.texture)
        for node in graph.nodes where node.kind == .swap {
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
            if sourceDescriptor.addressMode != targetDescriptor.addressMode
                || sourceDescriptor.isUnique != targetDescriptor.isUnique
                || sourceDescriptor.initialClear != targetDescriptor.initialClear {
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
