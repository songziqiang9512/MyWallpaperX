import Foundation
import Metal

/// Binds one immutable physical allocation to the logical graph identities that
/// may reference it. Metal objects stay in the lease and never enter the pure
/// `SceneGraphExecutionState` value.
struct SceneGraphRenderTargetLease {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneGraphRenderTargetPlan
    typealias State = SceneGraphExecutionState

    enum Failure: String, Error {
        case invalidGeneration
        case invalidPlan
        case missingTexture
        case descriptorMismatch
        case missingPhysicalToken
        case physicalAlias
    }

    struct FullFramePair {
        let first: State.PhysicalToken
        let second: State.PhysicalToken
    }

    let table: SceneGraphRenderTargetTable
    let allocation: State.Allocation
    let texturesByToken: [State.PhysicalToken: MTLTexture]
    let fullFramePair: FullFramePair
    let fullFramePairGeneration: UInt64

    var generation: UInt64 { allocation.generation }
    /// State reduction owns authored FBOs only. Pair endpoints remain on the
    /// lease for full-frame publication and never enter persistent graph state.
    var framebufferAllocation: State.Allocation {
        .init(
            generation: allocation.generation,
            resources: allocation.resources.filter {
                $0.key.kind == .framebuffer
            }
        )
    }

    init(
        table: SceneGraphRenderTargetTable,
        allocation: State.Allocation,
        texturesByToken: [State.PhysicalToken: MTLTexture],
        fullFramePair: FullFramePair? = nil,
        fullFramePairGeneration: UInt64? = nil
    ) {
        self.table = table
        self.allocation = allocation
        self.texturesByToken = texturesByToken
        self.fullFramePairGeneration = fullFramePairGeneration ?? allocation.generation
        let fallback = State.PhysicalToken(rawValue: "")
        self.fullFramePair = fullFramePair ?? .init(
            first: allocation.resources[table.plan.input]?.token ?? fallback,
            second: allocation.resources[table.plan.output]?.token ?? fallback
        )
    }

    func texture(for identity: Graph.TextureIdentity) -> MTLTexture? {
        guard let token = allocation.resources[identity]?.token else { return nil }
        return texturesByToken[token]
    }

    static func make(
        table: SceneGraphRenderTargetTable,
        generation: UInt64,
        tokenForTexture: (MTLTexture) -> State.PhysicalToken?,
        fullFramePairGeneration: UInt64? = nil,
        tokenForPairTexture: ((MTLTexture) -> State.PhysicalToken?)? = nil
    ) -> Result<Self, Failure> {
        guard generation > 0 else { return .failure(.invalidGeneration) }
        guard let identities = orderedIdentities(for: table.plan) else {
            return .failure(.invalidPlan)
        }

        var resources: [Graph.TextureIdentity: State.Resource] = [:]
        var textures: [State.PhysicalToken: MTLTexture] = [:]
        var tokenByObject: [ObjectIdentifier: State.PhysicalToken] = [:]
        var logicalOwnerByObject: [ObjectIdentifier: Graph.TextureIdentity] = [:]
        resources.reserveCapacity(identities.count)
        textures.reserveCapacity(table.residentTextureCount)

        let pairTextures = [table.fullFramePair.first, table.fullFramePair.second]
        let pairObjects = Set(pairTextures.map(ObjectIdentifier.init))
        guard pairObjects.count == 2,
              table.inputOutputAliased == (table.inputTexture === table.outputTexture) else {
            return .failure(.physicalAlias)
        }
        let pairDescriptor = State.ResourceDescriptor(
            extent: table.plan.inputExtent,
            format: .rgbaBackbuffer,
            isUnique: false,
            initialClear: nil
        )
        guard pairTextures.allSatisfy({
            textureMatches($0, descriptor: pairDescriptor)
        }) else { return .failure(.descriptorMismatch) }
        for texture in table.orderedPhysicalTextures {
            let object = ObjectIdentifier(texture)
            let token: State.PhysicalToken?
            if pairObjects.contains(object), let tokenForPairTexture {
                token = tokenForPairTexture(texture)
            } else {
                token = tokenForTexture(texture)
            }
            guard let token, valid(token) else {
                return .failure(.missingPhysicalToken)
            }
            guard textures.updateValue(texture, forKey: token) == nil else {
                return .failure(.physicalAlias)
            }
            tokenByObject[object] = token
        }
        guard tokenByObject.count == table.residentTextureCount,
              let firstPairToken = tokenByObject[ObjectIdentifier(pairTextures[0])],
              let secondPairToken = tokenByObject[ObjectIdentifier(pairTextures[1])] else {
            return .failure(.missingPhysicalToken)
        }

        for identity in identities {
            guard let descriptor = descriptor(for: identity, plan: table.plan) else {
                return .failure(.invalidPlan)
            }
            guard let texture = table.texture(for: identity) else {
                return .failure(.missingTexture)
            }
            guard textureMatches(texture, descriptor: descriptor) else {
                return .failure(.descriptorMismatch)
            }
            let object = ObjectIdentifier(texture)
            guard let token = tokenByObject[object] else {
                return .failure(.missingPhysicalToken)
            }
            if let prior = logicalOwnerByObject[object] {
                let endpointAlias = table.inputOutputAliased
                    && Set([prior, identity]) == Set([table.plan.input, table.plan.output])
                guard endpointAlias else { return .failure(.physicalAlias) }
            } else {
                logicalOwnerByObject[object] = identity
            }
            guard identity == table.plan.input || identity == table.plan.output
                    || !pairObjects.contains(object) else {
                return .failure(.physicalAlias)
            }
            guard resources.updateValue(
                .init(token: token, descriptor: descriptor),
                forKey: identity
            ) == nil else { return .failure(.invalidPlan) }
        }
        return .success(Self(
            table: table,
            allocation: .init(generation: generation, resources: resources),
            texturesByToken: textures,
            fullFramePair: .init(first: firstPairToken, second: secondPairToken),
            fullFramePairGeneration: fullFramePairGeneration
        ))
    }

    static func orderedTextures(for table: SceneGraphRenderTargetTable) -> [MTLTexture]? {
        guard orderedIdentities(for: table.plan) != nil else { return nil }
        let textures = table.orderedPhysicalTextures
        return textures.count == table.residentTextureCount ? textures : nil
    }

    private static func orderedIdentities(for plan: Plan) -> [Graph.TextureIdentity]? {
        let identities = [plan.input]
            + plan.logicalTargets.map(\.identity)
            + [plan.output]
        return Set(identities).count == identities.count ? identities : nil
    }

    private static func descriptor(
        for identity: Graph.TextureIdentity,
        plan: Plan
    ) -> State.ResourceDescriptor? {
        if identity == plan.input || identity == plan.output {
            return .init(
                extent: plan.inputExtent,
                format: .rgbaBackbuffer,
                isUnique: false,
                initialClear: nil
            )
        }
        guard let target = plan.logicalTargets.first(where: {
            $0.identity == identity
        }) else { return nil }
        return .init(
            extent: target.extent,
            format: target.format,
            isUnique: target.isUnique,
            initialClear: target.initialClear
        )
    }

    static func textureMatches(
        _ texture: MTLTexture,
        descriptor: State.ResourceDescriptor
    ) -> Bool {
        let pixelFormat: MTLPixelFormat = switch descriptor.format {
        case .rgbaBackbuffer: .bgra8Unorm
        case .rgba8888: .rgba8Unorm
        }
        return texture.textureType == .type2D
            && texture.pixelFormat == pixelFormat
            && texture.width == descriptor.extent.width
            && texture.height == descriptor.extent.height
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(.renderTarget)
            && texture.usage.contains(.shaderRead)
    }

    static func valid(_ token: State.PhysicalToken) -> Bool {
        !token.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Shared bound for logical in-flight submissions and their physical chain
/// generations. Residency admission and the runtime coordinator use one value.
enum SceneResolvedMaterialInFlightCapacity {
    static let maximumSubmissions = 2

    static func admitsNewSubmission(_ pinCounts: [Int]) -> Bool {
        pinCounts.reduce(0) {
            min(maximumSubmissions, $0 + min(maximumSubmissions, $1))
        } < maximumSubmissions
    }

}
