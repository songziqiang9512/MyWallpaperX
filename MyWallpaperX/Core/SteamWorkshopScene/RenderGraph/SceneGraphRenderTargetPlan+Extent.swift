import Foundation

nonisolated extension SceneGraphRenderTargetPlan {
    struct TargetDescriptor: Equatable {
        let extent: PixelExtent
        let format: TextureFormat
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
              target.uvs == nil,
              target.conditions == nil else {
            return nil
        }
        let initialClear: ClearColor?
        if let authoredClear = target.clear {
            guard let zeroClear = zeroClear(authoredClear) else { return nil }
            initialClear = zeroClear
        } else {
            initialClear = nil
        }
        return TargetDescriptor(
            extent: extent,
            format: format,
            isUnique: target.declaredUnique,
            initialClear: initialClear
        )
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
        stageExecutionPlan: SceneEffectStageExecutionPlan?,
        declarations: [Graph.TextureIdentity: Graph.RenderTarget]
    ) -> Bool {
        if declarations[identity]?.declaredUnique == true { return true }
        // The typed Cursor Ripple contract uses its second ping-pong target as
        // the frame-to-frame history seed. The planner validates that exact
        // topology before this target planner is allowed to preserve it.
        guard let cursorRipple = stageExecutionPlan?.cursorRipple,
              identity.effect == cursorRipple.effectKey else {
            return false
        }
        return identity.name?.lowercased() == "_rt_eightbuffer2"
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
        case "rgba_backbuffer": return .rgbaBackbuffer
        case "rgba8888": return .rgba8888
        default: return nil
        }
    }
}
