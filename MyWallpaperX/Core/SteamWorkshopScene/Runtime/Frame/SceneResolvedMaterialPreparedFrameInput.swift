import Foundation

/// Prepared numeric consumer schema; source/schema discovery remains in compilation.
nonisolated struct SceneResolvedMaterialPreparedUniformSchema: Hashable {
    let name: String
    let materialKeys: [String]
    let defaultValue: SceneResolvedMaterialTemplate.StaticUniformValue?
    /// Author-declared numeric domain, including the normalized domain of
    /// a typed color editor. It is not a general clamp policy; owner
    /// transfers may require it to preserve an incumbent's runtime contract.
    let authoredRange: ClosedRange<Double>?
}

/// Immutable identity of one admitted material node.
nonisolated struct SceneResolvedMaterialKey: Hashable {
    let effect: SceneAuthoredEffectRenderPlan.EffectKey
    let nodeIndex: Int

    var reportToken: String {
        "\(effect.layerID):\(effect.effectIndex):"
            + "\(effect.descriptorID.utf8.count)#\(effect.descriptorID):\(nodeIndex)"
    }
}

/// Immutable execution route for one active authored uniform. Preparation
/// resolves ownership and structural projection once; a frame only supplies
/// the value carried by that route and revalidates live resource identity.
nonisolated struct SceneResolvedMaterialPreparedUniformBinding: Hashable {
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate
    typealias Uniform = SceneResolvedMaterialPreparedUniformSchema

    struct Dynamic: Hashable {
        let declaration: Template.DynamicUniform
        let contributor: Template.DynamicUniformSource
        let fallback: Template.StaticUniformValue?
        let schema: Uniform
    }

    enum Source: Hashable {
        case host(Program.HostUniform)
        case staticValue(Data)
        case dynamic(Dynamic)
        case neutralMissingTextureResolution(
            SceneAuthoredShaderNeutralTextureResolutionFact
        )
        case selfCompositeTextureResolution(
            slot: Int,
            providerLayerID: Int
        )
    }

    let field: SceneAuthoredShaderUniformLayout.Field
    let source: Source
}

/// Immutable layer-level sources for host values shared by every effect
/// stage. Each Program variant separately owns its exact per-uniform route;
/// this contract fixes how renderer geometry becomes those host values.
nonisolated struct SceneResolvedMaterialFrameInputContract: Equatable {
    enum DirectDrawGeometryFallback: String, Equatable {
        case roleInvalid = "role-invalid"
        case sourceAmbiguous = "source-ambiguous"
        case vertexInputUnqualified = "vertex-input-unqualified"
        case pointBindingsUnproven = "point-bindings-unproven"
    }

    struct DirectDrawGeometryBinding: Equatable {
        let sourceMaterialKey: SceneResolvedMaterialKey
        /// Prepared p0...p3 numeric ownership, independent of source names.
        let pointBindings: [SceneResolvedMaterialPreparedUniformBinding]
    }
    enum EmittedOutputGeometrySource: Equatable {
        case layerCard
        case captureGeometry
        case authoredCanvasDirectDraw
    }

    enum EffectTextureProjectionSource: Equatable {
        /// The geometry used to emit the layer's effect card into its
        /// working target. This is canonical fullscreen geometry for a
        /// fullscreen capture and live world geometry for image, Puppet,
        /// composition, and direct-draw products.
        case emittedOutputGeometry
    }

    let effectTextureProjectionSource: EffectTextureProjectionSource
    let emittedOutputGeometrySource: EmittedOutputGeometrySource
    let requiresInvertibleEffectTextureProjection: Bool
    let directDrawGeometry: DirectDrawGeometryBinding?
    let directDrawGeometryFallback: DirectDrawGeometryFallback?

    init(
        effectTextureProjectionSource: EffectTextureProjectionSource,
        emittedOutputGeometrySource: EmittedOutputGeometrySource,
        requiresInvertibleEffectTextureProjection: Bool,
        directDrawGeometry: DirectDrawGeometryBinding? = nil,
        directDrawGeometryFallback: DirectDrawGeometryFallback? = nil
    ) {
        self.effectTextureProjectionSource = effectTextureProjectionSource
        self.emittedOutputGeometrySource = emittedOutputGeometrySource
        self.requiresInvertibleEffectTextureProjection = requiresInvertibleEffectTextureProjection
        self.directDrawGeometry = directDrawGeometry
        self.directDrawGeometryFallback = directDrawGeometryFallback
    }
}
