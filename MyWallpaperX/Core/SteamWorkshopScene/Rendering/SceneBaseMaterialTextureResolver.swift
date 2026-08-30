import Metal

/// One frame-local base source selected from an authored material slot. A
/// provider resource remains its own atom; it is not republished as layerSource.
struct SceneBaseMaterialTextureSource {
    let texture: MTLTexture
    let candidate: SceneTextureCandidate?
    let usesSystemProvider: Bool
    let usesUserPropertyProvider: Bool
    let usesAuthoredLayerColor: Bool
    let rejectedProviderReason: String?
}

enum SceneBaseMaterialTextureResolution {
    case ready(SceneTextureCandidate)
    case authoredFallback
    case rejected(reasonCode: String)
}

enum SceneBaseMaterialTextureSelection {
    case source(SceneBaseMaterialTextureSource)
    case missing
    case rejected(reasonCode: String)

    var source: SceneBaseMaterialTextureSource? {
        guard case let .source(value) = self else { return nil }
        return value
    }

    var rejectedProviderReason: String? {
        switch self {
        case let .source(value): value.rejectedProviderReason
        case .missing: nil
        case let .rejected(reasonCode): reasonCode
        }
    }
}

enum SceneBaseMaterialTextureResolver {
    static func resolve(
        binding: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding,
        registry: SceneFrameTextureRegistry
    ) -> SceneBaseMaterialTextureResolution {
        let identity = binding.provider.frameIdentity
        let prefix = binding.provider.diagnosticPrefix
        guard let status = registry.lookup(identity) else {
            return .rejected(reasonCode: "\(prefix)-registry-missing")
        }
        switch status {
        case let .ready(resource):
            let publication = resource.publication
            let candidate = publication.candidate
            guard publication.requestIdentity == identity,
                  publication.isComplete,
                  binding.provider.accepts(candidate),
                  SceneBaseImageTextureCandidateResolver.sample(
                    candidate: candidate,
                    sourceTexture: candidate.texture
                  ) != nil else {
                return .rejected(
                    reasonCode: "\(prefix)-publication-invalid"
                )
            }
            return .ready(candidate)
        case .incomplete:
            return .rejected(reasonCode: "\(prefix)-publication-incomplete")
        case .absent, .pending:
            return .authoredFallback
        case .unavailable:
            return binding.provider.isSystemProvider
                ? .authoredFallback
                : .rejected(reasonCode: "\(prefix)-unavailable")
        }
    }
}

extension SceneMetalRenderer {
    func baseMaterialTextureSelection(
        for layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        readyProviderUsesAuthoredLayerColor: Bool = false
    ) -> SceneBaseMaterialTextureSelection {
        let fallbackTexture = imageTextures[layer.id]
        let fallbackCandidate = fallbackTexture.flatMap {
            imageTextures.candidate(for: layer.id, matching: $0)
        }
        guard let binding = baseMaterialProviderBindings
            .baseMaterialBindings[layer.id] else {
            guard let fallbackTexture else { return .missing }
            return .source(
                SceneBaseMaterialTextureSource(
                    texture: fallbackTexture,
                    candidate: fallbackCandidate,
                    usesSystemProvider: false,
                    usesUserPropertyProvider: false,
                    usesAuthoredLayerColor: true,
                    rejectedProviderReason: nil
                )
            )
        }
        switch SceneBaseMaterialTextureResolver.resolve(
            binding: binding,
            registry: textureRegistry
        ) {
        case let .ready(candidate):
            return .source(SceneBaseMaterialTextureSource(
                texture: candidate.texture,
                candidate: candidate,
                usesSystemProvider: binding.provider.isSystemProvider,
                usesUserPropertyProvider:
                    binding.provider.userPropertyIdentity != nil,
                usesAuthoredLayerColor:
                    binding.provider.isSystemProvider
                        ? readyProviderUsesAuthoredLayerColor : true,
                rejectedProviderReason: nil
            ))
        case .authoredFallback:
            guard let fallbackTexture else { return .missing }
            return .source(SceneBaseMaterialTextureSource(
                texture: fallbackTexture,
                candidate: fallbackCandidate,
                usesSystemProvider: false,
                usesUserPropertyProvider: false,
                usesAuthoredLayerColor: true,
                rejectedProviderReason: nil
            ))
        case let .rejected(reasonCode):
            // Reject only the unsafe provider replacement. The authored
            // placeholder remains the safe previous-current for this slot.
            guard let fallbackTexture else {
                return .rejected(reasonCode: reasonCode)
            }
            return .source(SceneBaseMaterialTextureSource(
                texture: fallbackTexture,
                candidate: fallbackCandidate,
                usesSystemProvider: false,
                usesUserPropertyProvider: false,
                usesAuthoredLayerColor: true,
                rejectedProviderReason: reasonCode
            ))
        }
    }

    func baseMaterialTextureSource(
        for layer: SceneRenderDescriptor.Layer,
        imageTextures: SceneBaseImageTextureSnapshot,
        readyProviderUsesAuthoredLayerColor: Bool = false
    ) -> SceneBaseMaterialTextureSource? {
        baseMaterialTextureSelection(
            for: layer,
            imageTextures: imageTextures,
            readyProviderUsesAuthoredLayerColor: readyProviderUsesAuthoredLayerColor
        ).source
    }
}
