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
    static func resolveFallback(
        binding: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding,
        registry: SceneFrameTextureRegistry
    ) -> SceneBaseMaterialTextureResolution {
        guard let asset = binding.fallbackAsset else { return .authoredFallback }
        let identity = SceneFrameTextureIdentity.asset(asset)
        let prefix = binding.provider.diagnosticPrefix + "-fallback"
        guard let status = registry.lookup(identity) else {
            return .rejected(reasonCode: "\(prefix)-registry-missing")
        }
        switch status {
        case let .ready(resource):
            let publication = resource.publication
            let candidate = publication.candidate
            let isAsset: Bool
            switch candidate.identity {
            case .file, .builtIn: isAsset = true
            case .provider: isAsset = false
            }
            guard publication.requestIdentity == identity,
                  publication.isComplete, isAsset,
                  SceneBaseImageTextureCandidateResolver.sample(
                    candidate: candidate, sourceTexture: candidate.texture
                  ) != nil else {
                return .rejected(reasonCode: "\(prefix)-publication-invalid")
            }
            return .ready(candidate)
        case .incomplete:
            return .rejected(reasonCode: "\(prefix)-publication-incomplete")
        case .absent: return .rejected(reasonCode: "\(prefix)-absent")
        case .pending: return .rejected(reasonCode: "\(prefix)-pending")
        case .unavailable: return .rejected(reasonCode: "\(prefix)-unavailable")
        }
    }

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
        guard let binding = baseMaterialProviderBindings
            .baseMaterialBindings[layer.id] else {
            guard let fallbackTexture = imageTextures[layer.id] else { return .missing }
            return .source(
                SceneBaseMaterialTextureSource(
                    texture: fallbackTexture,
                    candidate: imageTextures.candidate(for: layer.id, matching: fallbackTexture),
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
                // A solid's static color belongs to its authored placeholder.
                // Ready file and system providers share the existing dynamic
                // color policy; reset still selects the authored color below.
                usesAuthoredLayerColor:
                    layer.contentKind == "solid" || binding.provider.isSystemProvider
                        ? readyProviderUsesAuthoredLayerColor : true,
                rejectedProviderReason: nil
            ))
        case .authoredFallback:
            return authoredBaseMaterialFallback(
                for: layer, binding: binding, imageTextures: imageTextures
            )
        case let .rejected(reasonCode):
            // Reject only the unsafe provider replacement. The authored
            // placeholder remains the safe previous-current for this slot.
            return authoredBaseMaterialFallback(
                for: layer, binding: binding, imageTextures: imageTextures,
                rejectedProviderReason: reasonCode
            )
        }
    }

    private func authoredBaseMaterialFallback(
        for layer: SceneRenderDescriptor.Layer,
        binding: SceneBaseMaterialProviderBindingProgram.BaseMaterialBinding,
        imageTextures: SceneBaseImageTextureSnapshot,
        rejectedProviderReason: String? = nil
    ) -> SceneBaseMaterialTextureSelection {
        let texture: MTLTexture
        let candidate: SceneTextureCandidate?
        switch SceneBaseMaterialTextureResolver.resolveFallback(
            binding: binding, registry: textureRegistry
        ) {
        case let .ready(asset):
            texture = asset.texture
            candidate = asset
        case .authoredFallback:
            guard let fallback = imageTextures[layer.id] else {
                return rejectedProviderReason.map { .rejected(reasonCode: $0) } ?? .missing
            }
            texture = fallback
            candidate = imageTextures.candidate(for: layer.id, matching: fallback)
        case let .rejected(reasonCode):
            return .rejected(reasonCode: reasonCode)
        }
        return .source(.init(texture: texture, candidate: candidate,
            usesSystemProvider: false, usesUserPropertyProvider: false,
            usesAuthoredLayerColor: true, rejectedProviderReason: rejectedProviderReason))
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
