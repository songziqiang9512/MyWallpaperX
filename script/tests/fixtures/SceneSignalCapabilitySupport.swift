enum SceneShaderColorRepresentation {
    case independentAlphaSignal
}

extension SceneResolvedMaterialVariantCache {
    func provesIndependentAlphaSignalPreserving(slot: Int) -> Bool {
        _ = slot
        return false
    }

    func provesIndependentAlphaSignalCompositing(
        signalSlot: Int,
        colorSlot: Int
    ) -> Bool {
        _ = (signalSlot, colorSlot)
        return false
    }
}
