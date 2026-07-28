import Foundation

extension SceneGraphRenderTargetPlan {
    nonisolated static func pixelExtent(
        _ authored: Graph.TargetExtent,
        inputWidth: Int,
        inputHeight: Int
    ) -> PixelExtent? {
        switch authored.kind {
        case .input:
            guard authored.first == nil, authored.second == nil else { return nil }
            return PixelExtent(width: inputWidth, height: inputHeight)
        case .scale:
            guard let scale = authored.first,
                  scale.isFinite,
                  scale >= 1,
                  authored.second == nil else {
                return nil
            }
            return PixelExtent(
                width: max(1, Int((Double(inputWidth) / scale).rounded(.down))),
                height: max(1, Int((Double(inputHeight) / scale).rounded(.down)))
            )
        case .fit:
            guard let maximumSide = authored.first,
                  maximumSide.isFinite,
                  maximumSide >= 1,
                  authored.second == nil else {
                return nil
            }
            let scale = max(
                Double(inputWidth) / maximumSide,
                Double(inputHeight) / maximumSide,
                1
            )
            return PixelExtent(
                width: max(1, Int((Double(inputWidth) / scale).rounded(.down))),
                height: max(1, Int((Double(inputHeight) / scale).rounded(.down)))
            )
        case .absolute, .unsupported:
            return nil
        }
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
