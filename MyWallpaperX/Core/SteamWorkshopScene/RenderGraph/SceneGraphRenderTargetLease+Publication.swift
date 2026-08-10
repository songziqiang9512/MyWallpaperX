import Foundation
import Metal

struct SceneOffscreenTexturePhysicalIdentity {
    typealias Token = SceneGraphExecutionState.PhysicalToken

    let generation: UInt64
    let tokensByTexture: [ObjectIdentifier: Token]

    func token(for texture: MTLTexture) -> Token? {
        tokensByTexture[ObjectIdentifier(texture)]
    }
}

/// Issues monotonic allocation generations and fresh physical tokens. History
/// copy-on-write never reuses a committed token in a new writable generation.
final class SceneOffscreenTextureIdentityIssuer {
    typealias Token = SceneGraphExecutionState.PhysicalToken

    private let namespace = UUID().uuidString.lowercased()
    private let lock = NSLock()
    private var lastGeneration: UInt64 = 0

    func issueGeneration() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return issueGenerationLocked()
    }

    func issue(textures: [MTLTexture]) -> SceneOffscreenTexturePhysicalIdentity? {
        lock.lock()
        defer { lock.unlock() }
        let objects = textures.map(ObjectIdentifier.init)
        guard !textures.isEmpty,
              Set(objects).count == textures.count,
              let generation = issueGenerationLocked() else { return nil }
        var tokens: [ObjectIdentifier: Token] = [:]
        for (index, object) in objects.enumerated() {
            tokens[object] = Token(
                rawValue: "scene-rt:\(namespace):\(generation):\(index)"
            )
        }
        guard Set(tokens.values).count == textures.count else { return nil }
        return .init(generation: generation, tokensByTexture: tokens)
    }

    private func issueGenerationLocked() -> UInt64? {
        guard lastGeneration < UInt64.max else { return nil }
        lastGeneration += 1
        return lastGeneration
    }
}

extension SceneGraphRenderTargetLease {
    enum PublicationFailure: String, Error {
        case invalidLogicalIdentity
        case invalidGeneration
        case unknownPhysicalToken
        case descriptorMismatch
        case textureMismatch
        case physicalAlias
        case pairMemberMismatch
        case colorRepresentationUnresolved
        case publicationIncomplete
    }

    /// Publishes a versioned physical graph allocation for one logical request.
    /// Storage format is never used to infer alpha representation.
    func graphResource(
        for logicalIdentity: Graph.TextureIdentity,
        versionedResource: State.VersionedResource,
        fragmentColorRepresentation: SceneShaderColorRepresentationResolution
    ) -> Result<SceneFrameTextureResource, PublicationFailure> {
        let framebuffers = framebufferAllocation
        guard logicalIdentity.kind == .framebuffer,
              framebuffers.resources[logicalIdentity] != nil else {
            return .failure(.invalidLogicalIdentity)
        }
        guard generation > 0,
              versionedResource.contentGeneration > 0,
              Self.valid(versionedResource.token) else {
            return .failure(.invalidGeneration)
        }
        let framebufferTokens = framebuffers.resources.values.map(\.token)
        guard Set(framebufferTokens).count == framebufferTokens.count else {
            return .failure(.physicalAlias)
        }
        guard versionedResource.token != fullFramePair.first,
              versionedResource.token != fullFramePair.second,
              let physical = framebuffers.resources.values.first(where: {
                  $0.token == versionedResource.token
              }) else {
            return .failure(.unknownPhysicalToken)
        }
        guard let logical = framebuffers.resources[logicalIdentity],
              logical.descriptor == versionedResource.descriptor,
              physical.descriptor == versionedResource.descriptor else {
            return .failure(.descriptorMismatch)
        }
        guard let texture = texturesByToken[versionedResource.token],
              Self.textureMatches(texture, descriptor: versionedResource.descriptor) else {
            return .failure(.textureMismatch)
        }
        return publishedResource(
            logicalIdentity: logicalIdentity,
            token: versionedResource.token,
            allocationGeneration: generation,
            descriptor: versionedResource.descriptor,
            contentGeneration: versionedResource.contentGeneration,
            fragmentColorRepresentation: fragmentColorRepresentation,
            texture: texture
        )
    }

    /// Publishes the dynamic full-frame member currently referenced by an
    /// endpoint identity. Compose rotation may select either pair member; the
    /// lease's static endpoint mapping is deliberately not consulted.
    func fullFrameResource(
        for logicalIdentity: Graph.TextureIdentity,
        member: SceneLayerFullFramePairPlan.Member,
        contentGeneration: UInt64,
        fragmentColorRepresentation: SceneShaderColorRepresentationResolution
    ) -> Result<SceneFrameTextureResource, PublicationFailure> {
        guard logicalIdentity == table.plan.input
                || logicalIdentity == table.plan.output else {
            return .failure(.invalidLogicalIdentity)
        }
        guard generation > 0, contentGeneration > 0 else {
            return .failure(.invalidGeneration)
        }
        guard fullFramePair.first != fullFramePair.second,
              let zeroTexture = texturesByToken[fullFramePair.first],
              let oneTexture = texturesByToken[fullFramePair.second],
              zeroTexture === table.fullFramePair.first,
              oneTexture === table.fullFramePair.second else {
            return .failure(.pairMemberMismatch)
        }
        let token = member == .zero ? fullFramePair.first : fullFramePair.second
        let texture = member == .zero ? zeroTexture : oneTexture
        let descriptor = State.ResourceDescriptor(
            extent: table.plan.inputExtent,
            format: .rgbaBackbuffer,
            isUnique: false,
            initialClear: nil
        )
        guard Self.valid(token),
              Self.textureMatches(texture, descriptor: descriptor) else {
            return .failure(.textureMismatch)
        }
        return publishedResource(
            logicalIdentity: logicalIdentity,
            token: token,
            allocationGeneration: generation,
            descriptor: descriptor,
            contentGeneration: contentGeneration,
            fragmentColorRepresentation: fragmentColorRepresentation,
            texture: texture
        )
    }

    private func publishedResource(
        logicalIdentity: Graph.TextureIdentity,
        token: State.PhysicalToken,
        allocationGeneration: UInt64,
        descriptor: State.ResourceDescriptor,
        contentGeneration: UInt64,
        fragmentColorRepresentation: SceneShaderColorRepresentationResolution,
        texture: MTLTexture
    ) -> Result<SceneFrameTextureResource, PublicationFailure> {
        guard allocationGeneration > 0,
              case .resolved(let representation) = fragmentColorRepresentation,
              representation != .straightAlpha else {
            return .failure(.colorRepresentationUnresolved)
        }
        let extent = descriptor.extent
        let size = CGSize(width: CGFloat(extent.width), height: CGFloat(extent.height))
        let candidate = SceneTextureCandidate(
            texture: texture,
            identity: .provider(.graph(
                allocationGeneration: allocationGeneration,
                physicalToken: token.rawValue
            )),
            generation: .provider(contentGeneration: contentGeneration),
            purpose: .premultipliedColor,
            content: .color(.resolved(representation)),
            physicalSize: size,
            mappedSize: size,
            uvTransform: .identity,
            sampling: .directImageFallback
        )
        let result = SceneFrameTextureResource(
            publication: .init(
                requestIdentity: .graph(logicalIdentity),
                candidate: candidate,
                contentGeneration: contentGeneration
            ),
            resourceGeneration: contentGeneration
        )
        guard result.isCompleteGraphResource else {
            return .failure(.publicationIncomplete)
        }
        return .success(result)
    }
}
