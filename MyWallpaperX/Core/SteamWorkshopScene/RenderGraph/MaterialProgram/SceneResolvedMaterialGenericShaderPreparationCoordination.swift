import Foundation

/// Process-lifetime single-flight for immutable accepted generic Programs.
/// Failures are deliberately not cached so a repairable compiler/cache failure
/// can retry without requiring a new process.
nonisolated final class SceneResolvedMaterialGenericShaderResolutionCache:
    @unchecked Sendable
{
    struct Input: Hashable {
        let vertexSource: String
        let fragmentSource: String
        let alphaAttenuationSourceSlot: Int?
        let colorBlendSourceSlot: Int?
        let unitCompositeBlurredSlot: Int?
        let unitCompositePreviousSlot: Int?
        let unitCompositeMaskSlot: Int?
        let hasExternalProviderTexture: Bool
        let producesScalarRedOutput: Bool
        let producesRedGreenUnormOutput: Bool
        let hasOnlyScalarDataInputs: Bool
        let isSourceIndependentPremultipliedOutput: Bool
        let graphTextureSlots: Set<Int>
        let graphInputTextureSlots: Set<Int>
        let activeTextureSlots: Set<Int>
        let activeOpacityMaskSlots: Set<Int>
        let typedStaticDataAuxiliarySlots: Set<Int>
        let preservedChannelsExternalProviderTextureSlots: Set<Int>
        let premultipliedColorAuxiliarySlots: Set<Int>
        let spatialWeightedColorBlendSourceSlot: Int?
        let spatialWeightedColorBlendActiveSlots: Set<Int>
        let spatialWeightedColorBlendTypedAuxiliarySlots: Set<Int>
        let spatialWeightedColorBlendExternalColorSlot: Int?
        let r8TextureSlots: Set<Int>
        let hasDefaultedOpacityMaskSampler: Bool
        let hasOnlyTypedOpacityMaskAuxiliary: Bool
        let hasOnlyGraphInputSampler: Bool
        let outputIsRGBA8Unorm: Bool
        let sourceColorTransfer: SceneShaderColorTransfer?
        let outputSemantics: SceneGenericShaderOutputSemantics
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    }

    struct Outcome {
        let resolution: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
        let cacheHit: Bool
    }

    private let condition = NSCondition()
    private var accepted: [
        Input: SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ] = [:]
    private var inFlight: Set<Input> = []

    func perform(
        key: Input,
        operation: () -> SceneResolvedMaterialGenericShaderArtifactCache.Resolution
    ) -> Outcome {
        condition.lock()
        while true {
            if let resolution = accepted[key] {
                condition.unlock()
                return .init(resolution: resolution, cacheHit: true)
            }
            if inFlight.insert(key).inserted { break }
            condition.wait()
        }
        condition.unlock()

        let resolution = operation()

        condition.lock()
        if case .accepted = resolution {
            accepted[key] = resolution
        }
        inFlight.remove(key)
        condition.broadcast()
        condition.unlock()
        return .init(resolution: resolution, cacheHit: false)
    }
}

/// Shares compiler outcomes across equivalent launch-time requests after the
/// outer Program-resolution cache has admitted the exact authored inputs.
nonisolated final class SceneResolvedMaterialGenericShaderCompilationCoordinator:
    @unchecked Sendable
{
    enum Source: String {
        case spawn
        case launchResultCache = "launch-result-cache"
    }

    struct Outcome {
        let result: Result<URL, SceneGenericShaderCompiler.Failure>
        let source: Source
    }

    private let condition = NSCondition()
    private var active = Set<String>()
    private var completed: [
        String: Result<URL, SceneGenericShaderCompiler.Failure>
    ] = [:]

    func perform(
        key: String,
        operation: () -> Result<URL, SceneGenericShaderCompiler.Failure>
    ) -> Outcome {
        condition.lock()
        while active.contains(key) {
            condition.wait()
        }
        if let result = completed[key] {
            condition.unlock()
            return .init(result: result, source: .launchResultCache)
        }
        active.insert(key)
        condition.unlock()

        let result = operation()

        condition.lock()
        completed[key] = result
        active.remove(key)
        condition.broadcast()
        condition.unlock()
        return .init(result: result, source: .spawn)
    }
}
