import Foundation
import Metal

extension SceneResolvedMaterialProgram {
    struct RenderStateIdentity: Hashable {
        let blending: SceneMaterialRenderState.Blending
        let depthTest: SceneMaterialRenderState.Depth
        let depthWrite: SceneMaterialRenderState.Depth
        let cullMode: SceneMaterialRenderState.Cull
        let alphaWriting: SceneMaterialRenderState.AlphaWriting
    }

    struct ShaderSemanticIdentity: Hashable {
        struct UniformField: Hashable {
            let name: String
            let valueType: String
            let arrayCount: Int?
            let offset: Int
        }

        enum ColorTransfer: Hashable {
            case passthrough(Int)
            case interpolatedColor([Int])
            case straightAlphaPreserving(Int)
            case straightAlpha(Int)
            case straightAlphaUNorm(Int)
            case independentAlphaSignal(Int)
            case independentAlphaSignalPreserving(Int)
            case independentAlphaSignalCompositing(signalSlot: Int, colorSlot: Int)
            case premultipliedAlpha
            case opaque
            case unresolved
        }

        let frontendSchemaVersion: Int
        let backend: SceneAuthoredShaderProgram.Backend
        let metalSource: String
        let vertexFunctionName: String
        let fragmentFunctionName: String
        let uniformBufferIndex: Int
        let uniformFields: [UniformField]
        let textureSlots: [Int]
        let textureChannelUses: [SceneAuthoredShaderProgram.TextureBinding.ChannelUse]
        let colorTransfer: ColorTransfer
        let fragmentOutputChannelUse:
            SceneAuthoredShaderProgram.FragmentOutputChannelUse
    }

    enum TextureContentIdentity: Hashable {
        case data
        case scalarRedUnorm
        case redGreenUnorm
        case scalarRedFloat16
        case redGreenFloat16
        case opaque
        case straightAlpha
        case premultipliedAlpha
        case independentAlphaSignal
    }

    enum TextureReferenceKind: Hashable {
        case asset
        case userProperty
        case provider
        case graph(SceneResolvedMaterialTemplate.GraphTextureRole)
    }

    struct TextureSemanticIdentity: Hashable {
        let slot: Int
        let referenceKind: TextureReferenceKind
        let graphInputSource:
            SceneResolvedMaterialGraphInputSourceSlotFact?
        let purpose: SceneTextureLoadPurpose
        let content: TextureContentIdentity
        let sampling: SceneTextureSampling
    }

    enum ColorRepresentationIdentity: Hashable {
        case opaque
        case straightAlpha
        case premultipliedAlpha
        case independentAlphaSignal
    }

    struct ColorContractIdentity: Hashable {
        let framebufferInput: ColorRepresentationIdentity
        let fragmentOutput: ColorRepresentationIdentity
    }

    enum OutputContractIdentity: Hashable {
        case color(ColorContractIdentity)
        case scalarRedUnorm
        case redGreenUnorm
        case scalarRedFloat16
        case redGreenFloat16
        case preservedRGBAUnorm
    }

    struct ActiveUniformIdentity: Hashable {
        let fieldName: String
        let fieldType: String
        let arrayCount: Int?
        let fieldOffset: Int
        let source: UniformSourceSchema
    }

    struct SemanticIdentity: Hashable {
        let shader: ShaderSemanticIdentity
        let textureSlots: [TextureSemanticIdentity?]
        let activeUniforms: [ActiveUniformIdentity]
        let renderState: RenderStateIdentity
        let outputContract: OutputContractIdentity
        let graphRole: SceneResolvedMaterialTemplate.GraphRole
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    }

    struct ExactPreparedIdentity: Hashable {
        let cacheKey: String
        let vertexDependency: String
        let vertexModuleDependency: String
        let vertexVariant: String
        let vertexPrepared: String
        let fragmentDependency: String
        let fragmentModuleDependency: String
        let fragmentVariant: String
        let fragmentPrepared: String
    }

    struct ExactTextureIdentity: Hashable {
        let reference: SceneResolvedMaterialTemplate.TextureReference
        let registryIdentity: SceneFrameTextureIdentity
        let graphInputSource:
            SceneResolvedMaterialGraphInputSourceSlotFact?
        let resourceIdentity: SceneTextureResourceIdentity
        let resourceGeneration: SceneTextureResourceGeneration
        let contentGeneration: UInt64
        let registryResourceGeneration: UInt64
        let purpose: SceneTextureLoadPurpose
        let content: SceneTextureContent
        let physicalExtent: [Int]
        let mappedExtent: [Int]
        let uvBitPatterns: [UInt32]
        let sampling: SceneTextureSampling
        let samplingRawFlags: UInt32?
        let authoredFormat: SceneShaderTextureFormat?
        let pixelFormatRawValue: UInt
        let mipLevelCount: Int
        let deviceRegistryID: UInt64
        let textureObjectIdentifier: ObjectIdentifier
    }

    struct ExactDynamicUniformIdentity: Hashable {
        let target: SceneDynamicTarget
        let declaredSource: SceneResolvedMaterialTemplate.DynamicUniformSource
        let resolvedSource: SceneDynamicSource
        let scriptAttachments: [
            SceneResolvedMaterialTemplate.DynamicUniformScriptAttachment
        ]
    }

    struct ExactIdentity: Hashable {
        let semanticIdentity: SemanticIdentity
        let prepared: ExactPreparedIdentity
        let textureSlots: [ExactTextureIdentity?]
        let uniformBytes: Data
        let dynamicUniforms: [ExactDynamicUniformIdentity]
    }

    struct MetalCompileStateKey: Hashable {
        let shader: ShaderSemanticIdentity
        let renderState: RenderStateIdentity
        let attachmentPixelFormatRawValue: UInt
        let sampleCount: Int
        let colorWriteMaskRawValue: UInt
        let deviceRegistryID: UInt64
    }
}

/// Canonical cache identities projected from facts already admitted by the
/// material Program derivation boundary.
nonisolated enum SceneResolvedMaterialProgramIdentity {
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    static func renderState(
        _ state: SceneMaterialRenderState
    ) -> Program.RenderStateIdentity {
        .init(
            blending: state.blending,
            depthTest: state.depthTest,
            depthWrite: state.depthWrite,
            cullMode: state.cullMode,
            alphaWriting: state.alphaWriting
        )
    }

    static func shader(
        _ frontend: SceneAuthoredShaderProgram,
        schemaVersion: Int
    ) -> Program.ShaderSemanticIdentity {
        let transfer: Program.ShaderSemanticIdentity.ColorTransfer
        switch frontend.colorTransfer {
        case let .passthrough(slot): transfer = .passthrough(slot)
        case let .interpolatedColor(slots):
            transfer = .interpolatedColor(slots)
        case let .straightAlphaPreserving(slot):
            transfer = .straightAlphaPreserving(slot)
        case let .straightAlpha(slot): transfer = .straightAlpha(slot)
        case let .straightAlphaUNorm(slot): transfer = .straightAlphaUNorm(slot)
        case let .independentAlphaSignal(slot):
            transfer = .independentAlphaSignal(slot)
        case let .independentAlphaSignalPreserving(slot):
            transfer = .independentAlphaSignalPreserving(slot)
        case let .independentAlphaSignalCompositing(signalSlot, colorSlot):
            transfer = .independentAlphaSignalCompositing(
                signalSlot: signalSlot,
                colorSlot: colorSlot
            )
        case .premultipliedAlpha: transfer = .premultipliedAlpha
        case .opaque: transfer = .opaque
        case .unresolved: transfer = .unresolved
        }
        return .init(
            frontendSchemaVersion: schemaVersion,
            backend: frontend.backend,
            metalSource: frontend.metalSource,
            vertexFunctionName: frontend.vertexFunctionName,
            fragmentFunctionName: frontend.fragmentFunctionName,
            uniformBufferIndex: frontend.uniformBufferIndex,
            uniformFields: frontend.uniformLayout.fields.map {
                .init(
                    name: $0.name,
                    valueType: $0.type.rawValue,
                    arrayCount: $0.arrayCount,
                    offset: $0.offset
                )
            },
            textureSlots: frontend.textureBindings.map(\.slot),
            textureChannelUses: frontend.textureBindings.map(\.channelUse),
            colorTransfer: transfer,
            fragmentOutputChannelUse: frontend.fragmentOutputChannelUse
        )
    }

    static func textureReferenceKind(
        _ reference: Template.TextureReference
    ) -> Program.TextureReferenceKind? {
        switch reference {
        case .asset: return .asset
        case .userProperty: return .userProperty
        case .provider: return .provider
        case let .graph(identity):
            switch identity.kind {
            case .layerSource: return .graph(.layerSource)
            case .effectOutput: return .graph(.effectOutput)
            case .framebuffer: return .graph(.framebuffer)
            case .unresolved: return nil
            }
        }
    }

    static func registryIdentity(
        _ identity: SceneFrameTextureIdentity,
        matches reference: Template.TextureReference,
        purpose: SceneTextureLoadPurpose
    ) -> Bool {
        switch (reference, identity) {
        case let (.asset(path), .asset(asset)):
            return asset.path == path && asset.purpose == purpose
        case let (.userProperty(request), .materialUserProperty(property)):
            return property.propertyKey == request.key && property.purpose == purpose
        case let (.provider(.system(expected)), .system(actual)):
            return actual == expected
        case let (
            .provider(.namedLayerTarget(expected)),
            .namedLayerTarget(actual)
        ):
            return actual == expected
        case let (
            .provider(.sceneBackground(expected)),
            .sceneBackground(actual)
        ):
            return actual == expected
        case let (.graph(expected), .graph(actual)):
            return actual == expected
        default:
            return false
        }
    }

    static func textureContent(
        _ content: SceneTextureContent
    ) -> Program.TextureContentIdentity? {
        switch content {
        case .data: return .data
        case .scalarRedUnorm: return .scalarRedUnorm
        case .redGreenUnorm: return .redGreenUnorm
        case .scalarRedFloat16: return .scalarRedFloat16
        case .redGreenFloat16: return .redGreenFloat16
        case .color(.unresolved): return nil
        case .color(.resolved(.opaque)): return .opaque
        case .color(.resolved(.straightAlpha)): return .straightAlpha
        case .color(.resolved(.premultipliedAlpha)): return .premultipliedAlpha
        case .color(.resolved(.independentAlphaSignal)):
            return .independentAlphaSignal
        }
    }

    static func color(
        _ value: SceneShaderColorRepresentation
    ) -> Program.ColorRepresentationIdentity {
        switch value {
        case .opaque: return .opaque
        case .straightAlpha: return .straightAlpha
        case .premultipliedAlpha: return .premultipliedAlpha
        case .independentAlphaSignal: return .independentAlphaSignal
        }
    }

    static func graphRole(
        _ role: Template.GraphRole,
        textureSlots: [Program.TextureSlot?],
        activeTextureSlots: Set<Int>
    ) -> Template.GraphRole? {
        guard textureSlots.count == 8 else { return nil }
        var allBindings: [Int: Template.GraphBindingRole] = [:]
        for binding in role.bindings {
            guard (0 ..< 8).contains(binding.slot),
                  allBindings.updateValue(binding, forKey: binding.slot) == nil else {
                return nil
            }
        }
        let bindingsBySlot = allBindings.filter {
            activeTextureSlots.contains($0.key)
        }
        for slot in activeTextureSlots {
            guard let texture = textureSlots[slot] else { return nil }
            switch texture.reference {
            case let .graph(identity):
                guard let expected = graphTextureRole(identity),
                      bindingsBySlot[slot]?.texture == expected else {
                    return nil
                }
            case .asset, .userProperty, .provider:
                guard bindingsBySlot[slot] == nil else { return nil }
            }
        }
        let bindings = bindingsBySlot.values.sorted {
            $0.slot < $1.slot
        }
        return .init(
            effectInput: role.effectInput,
            effectOutput: role.effectOutput,
            nodeTarget: role.nodeTarget,
            bindings: bindings
        )
    }

    private static func graphTextureRole(
        _ identity: SceneAuthoredEffectRenderPlan.TextureIdentity
    ) -> Template.GraphTextureRole? {
        switch identity.kind {
        case .layerSource: return .layerSource
        case .effectOutput: return .effectOutput
        case .framebuffer: return .framebuffer
        case .unresolved: return nil
        }
    }

    static func prepared(
        _ prepared: SceneShaderPreparedProgram
    ) -> Program.ExactPreparedIdentity {
        .init(
            cacheKey: prepared.cacheKey,
            vertexDependency: prepared.vertex.dependencySHA256,
            vertexModuleDependency: prepared.vertex.moduleDependencySHA256,
            vertexVariant: prepared.vertex.variantSHA256,
            vertexPrepared: prepared.vertex.preparedSHA256,
            fragmentDependency: prepared.fragment.dependencySHA256,
            fragmentModuleDependency: prepared.fragment.moduleDependencySHA256,
            fragmentVariant: prepared.fragment.variantSHA256,
            fragmentPrepared: prepared.fragment.preparedSHA256
        )
    }
}

extension SceneResolvedMaterialProgram {
    /// Pipeline state depends on the already-derived shader/state/color facts
    /// plus the concrete render attachment and Metal device selected by R4.
    func metalCompileStateKey(
        attachmentPixelFormat: MTLPixelFormat,
        sampleCount: Int,
        colorWriteMask: MTLColorWriteMask = .all,
        device: MTLDevice
    ) -> MetalCompileStateKey? {
        guard attachmentPixelFormat != .invalid,
              sampleCount > 0,
              !colorWriteMask.isEmpty,
              exactIdentity.textureSlots.compactMap({ $0 }).allSatisfy({
                  $0.deviceRegistryID == device.registryID
              }) else {
            return nil
        }
        return SceneResolvedMaterialProgramIdentity.metalCompileStateKey(
            frontend: frontendProgram,
            renderState: renderState,
            frontendSchemaVersion: semanticIdentity.shader.frontendSchemaVersion,
            attachmentPixelFormatRawValue: attachmentPixelFormat.rawValue,
            sampleCount: sampleCount,
            colorWriteMaskRawValue: colorWriteMask.rawValue,
            deviceRegistryID: device.registryID
        )
    }
}

extension SceneResolvedMaterialProgramIdentity {
    static func metalCompileStateKey(
        frontend: SceneAuthoredShaderProgram,
        renderState: SceneMaterialRenderState,
        frontendSchemaVersion: Int,
        attachmentPixelFormatRawValue: UInt,
        sampleCount: Int,
        colorWriteMaskRawValue: UInt,
        deviceRegistryID: UInt64
    ) -> Program.MetalCompileStateKey? {
        guard frontendSchemaVersion == SceneShaderVariantEnvironment.frontendSchemaVersion,
              attachmentPixelFormatRawValue != MTLPixelFormat.invalid.rawValue,
              sampleCount > 0,
              colorWriteMaskRawValue != MTLColorWriteMask().rawValue,
              deviceRegistryID != 0,
              renderState.supportsResolvedMaterialFullscreenOverwrite,
              SceneResolvedMaterialProgramDerivation.uniqueAndValid(
                  frontend.uniformLayout
              ) else { return nil }
        return .init(
            shader: shader(frontend, schemaVersion: frontendSchemaVersion),
            renderState: self.renderState(renderState),
            attachmentPixelFormatRawValue: attachmentPixelFormatRawValue,
            sampleCount: sampleCount,
            colorWriteMaskRawValue: colorWriteMaskRawValue,
            deviceRegistryID: deviceRegistryID
        )
    }
}
