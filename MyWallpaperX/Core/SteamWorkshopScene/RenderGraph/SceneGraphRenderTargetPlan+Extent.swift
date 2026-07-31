import Foundation

extension SceneGraphRenderTargetPlan {
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
        executionPlan: SceneAuthoredEffectExecutionPlan,
        declarations: [Graph.TextureIdentity: Graph.RenderTarget]
    ) -> Bool {
        if declarations[identity]?.declaredUnique == true { return true }
        guard let cursorRipple = executionPlan.cursorRipple,
              identity.effect == cursorRipple.effectKey else {
            return false
        }
        return identity.name?.lowercased() == "_rt_eightbuffer2"
    }
}
