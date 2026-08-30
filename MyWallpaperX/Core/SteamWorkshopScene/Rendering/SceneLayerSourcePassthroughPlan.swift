import Metal
import simd

/// One fail-closed source-stage plan for an image whose authored effect chain
/// has no runtime owner. The plan proves only that the exact layer source can
/// enter the final layer composite; it does not claim or publish effect output.
struct SceneLayerSourcePassthroughPlan {
    enum RejectionReason: String, Error {
        case routeUnavailable = "route-unavailable"
        case publicationUnavailable = "publication-unavailable"
        case imageSourceRequired = "image-source-required"
        case displayAuthorityUnavailable = "display-authority-unavailable"
        case visibleEffectUnavailable = "visible-effect-unavailable"
        case frameTargetPresent = "frame-target-present"
        case sourceCopyRequired = "source-copy-required"
        case finalAlphaPresent = "final-alpha-present"
        case dependencyPresent = "dependency-present"
        case sourceCoverageUnproven = "source-coverage-unproven"
        case layerBlendNonneutral = "layer-blend-nonneutral"
        case layerStyleNonneutral = "layer-style-nonneutral"
        case textureFrameNonidentity = "texture-frame-nonidentity"
        case publicationRequestMismatch = "publication-request-mismatch"
        case publicationTextureMismatch = "publication-texture-mismatch"
        case publicationGenerationInvalid = "publication-generation-invalid"
        case publicationIncomplete = "publication-incomplete"
        case publicationPurposeInvalid = "publication-purpose-invalid"
        case publicationContentInvalid = "publication-content-invalid"
        case publicationSampleInvalid = "publication-sample-invalid"
        case staticSourceAtomInvalid = "static-source-atom-invalid"
        case currentMediaAtomInvalid = "current-media-atom-invalid"
        case sourceIdentityUnsupported = "source-identity-unsupported"
        case staticSourceGraphRolePresent = "static-source-graph-role-present"
        case projectedGeometryInvalid = "projected-geometry-invalid"
    }

    enum SourceKind: Equatable {
        case staticFile
        case currentMedia
    }

    struct SourceAtom {
        let kind: SourceKind
        let requestIdentity: SceneFrameTextureIdentity
        let resourceIdentity: SceneTextureResourceIdentity
        let resourceGeneration: SceneTextureResourceGeneration
        let contentGeneration: UInt64
        let purpose: SceneTextureLoadPurpose
        let content: SceneTextureContent
        let physicalSize: CGSize
        let mappedSize: CGSize
        let texture: MTLTexture
        let uvTransform: SceneTextureUVTransform
        let sampling: SceneTextureSampling
        let authoredFormat: SceneShaderTextureFormat?
    }

    struct ProjectedClippedQuad {
        /// Perimeter order in Metal NDC: bottom-left, bottom-right,
        /// top-right, top-left.
        let ndcVertices: [SIMD2<Float>]
        /// The same quad after clipping to the canonical NDC viewport.
        let clippedNDCVertices: [SIMD2<Float>]
        let clippedArea: Float
    }

    let layerID: Int
    let visibleEffectIDs: [String]
    let source: SourceAtom
    let modelViewProjection: simd_float4x4
    let projectedGeometry: ProjectedClippedQuad

    private init(
        layerID: Int,
        visibleEffectIDs: [String],
        source: SourceAtom,
        modelViewProjection: simd_float4x4,
        projectedGeometry: ProjectedClippedQuad
    ) {
        self.layerID = layerID
        self.visibleEffectIDs = visibleEffectIDs
        self.source = source
        self.modelViewProjection = modelViewProjection
        self.projectedGeometry = projectedGeometry
    }

    static func resolve(
        request: SceneImageLayerDrawRequest,
        publication: SceneTextureProviderPublication?,
        route: SceneResolvedMaterialClaimRoute
    ) -> Result<Self, RejectionReason> {
        guard route.allowsLayerSourcePassthrough else {
            return .failure(.routeUnavailable)
        }
        guard let publication else { return .failure(.publicationUnavailable) }
        guard request.layer.contentKind == "image" else {
            return .failure(.imageSourceRequired)
        }
        guard SceneLayerVisibility.hasCurrentSourceDisplayAuthority(
            for: request.layer,
            snapshot: request.dynamicValues
        ) else { return .failure(.displayAuthorityUnavailable) }
        guard request.layer.effects.contains(where: { $0.visible != false }) else {
            return .failure(.visibleEffectUnavailable)
        }
        guard request.resolvedMaterialFrameTargetPlan == nil else {
            return .failure(.frameTargetPresent)
        }
        guard !request.requiresSourceCopy else { return .failure(.sourceCopyRequired) }
        guard request.finalCompositeAlpha == nil else {
            return .failure(.finalAlphaPresent)
        }
        guard request.dependencyEffect == nil,
              !request.requiresDependencyEffect else {
            return .failure(.dependencyPresent)
        }
        guard !request.masks.blocksLayerSourcePassthrough(
            forVisibleEffects: request.layer.effects
        ) else { return .failure(.sourceCoverageUnproven) }
        guard (request.layer.colorBlendMode ?? 0) == 0 else {
            return .failure(.layerBlendNonneutral)
        }
        guard neutral(request.uniforms.alpha),
              neutral(request.uniforms.tint.x),
              neutral(request.uniforms.tint.y),
              neutral(request.uniforms.tint.z),
              neutralColor(request.layer.colorRGB),
              neutral(Float(request.layer.brightness ?? 1)) else {
            return .failure(.layerStyleNonneutral)
        }
        guard request.textureFrame == .identity else {
            return .failure(.textureFrameNonidentity)
        }
        guard publication.requestIdentity == .layerSource(request.layer.id) else {
            return .failure(.publicationRequestMismatch)
        }
        guard publication.texture === request.texture else {
            return .failure(.publicationTextureMismatch)
        }
        guard publication.contentGeneration > 0 else {
            return .failure(.publicationGenerationInvalid)
        }
        guard publication.isComplete else { return .failure(.publicationIncomplete) }
        guard publication.candidate.purpose == .premultipliedColor else {
            return .failure(.publicationPurposeInvalid)
        }
        guard publication.candidate.content
                == .color(.resolved(.premultipliedAlpha))
                || publication.candidate.content
                == .color(.resolved(.opaque)) else {
            return .failure(.publicationContentInvalid)
        }
        guard let sourceSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: publication.candidate,
            sourceTexture: publication.texture
        ) else { return .failure(.publicationSampleInvalid) }
        let resolvedSourceKind: SourceKind
        switch Self.sourceKind(request: request, publication: publication) {
        case let .success(value): resolvedSourceKind = value
        case let .failure(reason): return .failure(reason)
        }
        // The media provider is already an explicit degraded display authority.
        // Authored cross-layer roles only block static-file source fallback here.
        guard resolvedSourceKind == .currentMedia
            || !request.blocksStaticLayerSourcePassthrough else {
            return .failure(.staticSourceGraphRolePresent)
        }
        guard let geometry = projectedGeometry(for: request.mvp) else {
            return .failure(.projectedGeometryInvalid)
        }
        return .success(Self(
            layerID: request.layer.id,
            visibleEffectIDs: request.layer.effects.compactMap {
                $0.visible != false ? $0.id : nil
            },
            source: SourceAtom(
                kind: resolvedSourceKind,
                requestIdentity: publication.requestIdentity,
                resourceIdentity: publication.candidate.identity,
                resourceGeneration: publication.candidate.generation,
                contentGeneration: publication.contentGeneration,
                purpose: publication.candidate.purpose,
                content: publication.candidate.content,
                physicalSize: publication.candidate.physicalSize,
                mappedSize: publication.candidate.mappedSize,
                texture: publication.texture,
                uvTransform: sourceSample.textureFrame,
                sampling: sourceSample.sampling,
                authoredFormat: publication.candidate.authoredFormat
            ),
            modelViewProjection: request.mvp,
            projectedGeometry: geometry
        ))
    }

    private static func sourceKind(
        request: SceneImageLayerDrawRequest,
        publication: SceneTextureProviderPublication
    ) -> Result<SourceKind, RejectionReason> {
        switch (
            publication.candidate.identity,
            publication.candidate.generation
        ) {
        case (.file, .file):
            guard let requestCandidate = request.baseTextureCandidate,
                  sameAtom(requestCandidate, publication.candidate),
                  SceneBaseImageTextureCandidateResolver.sample(
                      candidate: requestCandidate,
                      sourceTexture: request.texture
                  ) != nil else {
                return .failure(.staticSourceAtomInvalid)
            }
            return .success(.staticFile)
        case let (
            .provider(.mediaThumbnailCurrent),
            .provider(contentGeneration)
        ):
            guard contentGeneration == publication.contentGeneration,
                  request.baseTextureCandidate.map({
                      sameAtom($0, publication.candidate)
                  }) ?? true,
                  publication.candidate.sampling.rawFlags == nil,
                  publication.candidate.authoredFormat == nil,
                  validCurrentMediaTexture(publication.texture) else {
                return .failure(.currentMediaAtomInvalid)
            }
            return .success(.currentMedia)
        case (.builtIn, _), (.provider, _), (.file, _):
            return .failure(.sourceIdentityUnsupported)
        }
    }

    private static func sameAtom(
        _ lhs: SceneTextureCandidate,
        _ rhs: SceneTextureCandidate
    ) -> Bool {
        lhs.texture === rhs.texture
            && lhs.identity == rhs.identity
            && lhs.generation == rhs.generation
            && lhs.purpose == rhs.purpose
            && lhs.content == rhs.content
            && lhs.physicalSize == rhs.physicalSize
            && lhs.mappedSize == rhs.mappedSize
            && lhs.uvTransform == rhs.uvTransform
            && lhs.sampling == rhs.sampling
            && lhs.sampling.rawFlags == rhs.sampling.rawFlags
            && lhs.authoredFormat == rhs.authoredFormat
    }

    private static func validCurrentMediaTexture(_ texture: MTLTexture) -> Bool {
        (texture.pixelFormat == .rgba8Unorm
            || texture.pixelFormat == .bgra8Unorm)
            && texture.textureType == .type2D
            && texture.sampleCount == 1
            && texture.mipmapLevelCount == 1
            && texture.usage.contains(.shaderRead)
    }

    private static func projectedGeometry(
        for mvp: simd_float4x4
    ) -> ProjectedClippedQuad? {
        guard mvp.columns.0.allFinite,
              mvp.columns.1.allFinite,
              mvp.columns.2.allFinite,
              mvp.columns.3.allFinite else {
            return nil
        }
        let localVertices: [SIMD4<Float>] = [
            SIMD4(-0.5, -0.5, 0, 1),
            SIMD4(0.5, -0.5, 0, 1),
            SIMD4(0.5, 0.5, 0, 1),
            SIMD4(-0.5, 0.5, 0, 1),
        ]
        var ndcVertices: [SIMD2<Float>] = []
        ndcVertices.reserveCapacity(localVertices.count)
        for localVertex in localVertices {
            let clip = mvp * localVertex
            guard clip.allFinite, clip.w > 0.000_001 else { return nil }
            let ndc = clip / clip.w
            guard ndc.allFinite,
                  ndc.z >= 0,
                  ndc.z <= 1 else {
                return nil
            }
            ndcVertices.append(SIMD2(ndc.x, ndc.y))
        }
        let clipped = ViewportEdge.allCases.reduce(ndcVertices) { polygon, edge in
            clip(polygon, to: edge)
        }
        let area = polygonArea(clipped)
        guard clipped.count >= 3,
              area.isFinite,
              area > 0.000_000_01 else {
            return nil
        }
        return ProjectedClippedQuad(
            ndcVertices: ndcVertices,
            clippedNDCVertices: clipped,
            clippedArea: area
        )
    }

    private enum ViewportEdge: CaseIterable {
        case left
        case right
        case bottom
        case top

        func contains(_ point: SIMD2<Float>) -> Bool {
            switch self {
            case .left: return point.x >= -1
            case .right: return point.x <= 1
            case .bottom: return point.y >= -1
            case .top: return point.y <= 1
            }
        }

        func intersection(
            from start: SIMD2<Float>,
            to end: SIMD2<Float>
        ) -> SIMD2<Float>? {
            let values: (boundary: Float, startAxis: Float, deltaAxis: Float)
            switch self {
            case .left:
                values = (-1, start.x, end.x - start.x)
            case .right:
                values = (1, start.x, end.x - start.x)
            case .bottom:
                values = (-1, start.y, end.y - start.y)
            case .top:
                values = (1, start.y, end.y - start.y)
            }
            guard values.deltaAxis.isFinite,
                  abs(values.deltaAxis) > 0.000_001 else {
                return nil
            }
            let progress = (values.boundary - values.startAxis)
                / values.deltaAxis
            guard progress.isFinite,
                  progress >= 0,
                  progress <= 1 else {
                return nil
            }
            let result = start + (end - start) * progress
            return result.allFinite ? result : nil
        }
    }

    private static func clip(
        _ polygon: [SIMD2<Float>],
        to edge: ViewportEdge
    ) -> [SIMD2<Float>] {
        guard var previous = polygon.last else { return [] }
        var previousInside = edge.contains(previous)
        var result: [SIMD2<Float>] = []
        for current in polygon {
            let currentInside = edge.contains(current)
            if currentInside != previousInside,
               let intersection = edge.intersection(from: previous, to: current) {
                result.append(intersection)
            }
            if currentInside { result.append(current) }
            previous = current
            previousInside = currentInside
        }
        return result
    }

    private static func polygonArea(_ polygon: [SIMD2<Float>]) -> Float {
        guard polygon.count >= 3 else { return 0 }
        var twiceSignedArea: Float = 0
        for index in polygon.indices {
            let next = polygon[(index + 1) % polygon.count]
            twiceSignedArea += polygon[index].x * next.y
                - next.x * polygon[index].y
        }
        return abs(twiceSignedArea) * 0.5
    }

    private static func neutral(_ value: Float) -> Bool {
        value.isFinite && abs(value - 1) <= 0.000_001
    }

    private static func neutralColor(_ values: [Float]?) -> Bool {
        guard let values else { return true }
        return values.count == 3 && values.allSatisfy {
            $0.isFinite && abs($0 - 1) <= 0.000_001
        }
    }
}

private extension SIMD2 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite && w.isFinite
    }
}
