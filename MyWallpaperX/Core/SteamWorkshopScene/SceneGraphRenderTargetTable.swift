import Foundation
import Metal

struct SceneGraphRenderTargetTable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Failure: String, Error {
        case invalidPlan
        case invalidByteBudget
        case byteCostOverflow
        case byteBudgetExceeded
        case textureAllocationFailed
        case textureAllocationAliased
    }

    let plan: SceneGraphRenderTargetPlan
    let inputTexture: MTLTexture
    let outputTexture: MTLTexture
    let residentByteCost: Int

    private let texturesByIdentity: [Graph.TextureIdentity: MTLTexture]

    var residentTextureCount: Int {
        texturesByIdentity.count
    }

    func texture(for identity: Graph.TextureIdentity) -> MTLTexture? {
        texturesByIdentity[identity]
    }

    static func make(
        plan: SceneGraphRenderTargetPlan,
        device: MTLDevice,
        byteBudget: Int
    ) -> Result<Self, Failure> {
        guard byteBudget >= 0 else { return .failure(.invalidByteBudget) }
        guard let specifications = specifications(for: plan) else {
            return .failure(.invalidPlan)
        }

        var totalByteCost = 0
        for specification in specifications {
            guard let byteCost = byteCost(for: specification.extent) else {
                return .failure(.byteCostOverflow)
            }
            let (nextTotal, overflow) = totalByteCost.addingReportingOverflow(byteCost)
            guard !overflow else { return .failure(.byteCostOverflow) }
            totalByteCost = nextTotal
        }
        guard totalByteCost <= byteBudget else {
            return .failure(.byteBudgetExceeded)
        }

        var textures: [Graph.TextureIdentity: MTLTexture] = [:]
        textures.reserveCapacity(specifications.count)
        var allocatedObjects = Set<ObjectIdentifier>()
        for specification in specifications {
            guard let texture = makeTexture(
                device: device,
                specification: specification,
                layerID: plan.layerID,
                effect: plan.output.effect
            ) else {
                return .failure(.textureAllocationFailed)
            }
            guard allocatedObjects.insert(ObjectIdentifier(texture)).inserted else {
                return .failure(.textureAllocationAliased)
            }
            textures[specification.identity] = texture
        }

        guard let inputTexture = textures[plan.input],
              let outputTexture = textures[plan.output],
              textures.count == specifications.count else {
            return .failure(.textureAllocationFailed)
        }
        return .success(Self(
            plan: plan,
            inputTexture: inputTexture,
            outputTexture: outputTexture,
            residentByteCost: totalByteCost,
            texturesByIdentity: textures
        ))
    }

    private struct Specification {
        let identity: Graph.TextureIdentity
        let extent: SceneGraphRenderTargetPlan.PixelExtent
        let role: String
    }

    private static func specifications(
        for plan: SceneGraphRenderTargetPlan
    ) -> [Specification]? {
        guard validInput(plan.input, layerID: plan.layerID),
              let effect = plan.output.effect,
              validOutput(plan.output, effect: effect, layerID: plan.layerID),
              validExtent(plan.inputExtent) else {
            return nil
        }

        var specifications = [Specification(
            identity: plan.input,
            extent: plan.inputExtent,
            role: "input"
        )]
        specifications.reserveCapacity(plan.logicalTargets.count + 2)
        for target in plan.logicalTargets {
            guard target.format == .rgbaBackbuffer,
                  validTarget(target.identity, effect: effect, layerID: plan.layerID),
                  validExtent(target.extent) else {
                return nil
            }
            specifications.append(Specification(
                identity: target.identity,
                extent: target.extent,
                role: "framebuffer"
            ))
        }
        specifications.append(Specification(
            identity: plan.output,
            extent: plan.inputExtent,
            role: "output"
        ))

        let identities = Set(specifications.map(\.identity))
        guard identities.count == specifications.count else { return nil }
        return specifications
    }

    private static func byteCost(
        for extent: SceneGraphRenderTargetPlan.PixelExtent
    ) -> Int? {
        let (pixelCount, pixelOverflow) = extent.width.multipliedReportingOverflow(
            by: extent.height
        )
        guard !pixelOverflow else { return nil }
        let (byteCost, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        return byteOverflow ? nil : byteCost
    }

    private static func makeTexture(
        device: MTLDevice,
        specification: Specification,
        layerID: Int,
        effect: Graph.EffectKey?
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: specification.extent.width,
            height: specification.extent.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        let effectIndex = effect?.effectIndex ?? -1
        let name = specification.identity.name ?? specification.role
        texture?.label = "SceneGraphRT layer=\(layerID) effect=\(effectIndex) \(name)"
        return texture
    }

    private static func validExtent(
        _ extent: SceneGraphRenderTargetPlan.PixelExtent
    ) -> Bool {
        extent.width > 0 && extent.height > 0
    }

    private static func validInput(_ identity: Graph.TextureIdentity, layerID: Int) -> Bool {
        identity.kind == .layerSource
            && identity.layerID == layerID
            && identity.effect == nil
            && identity.name == nil
    }

    private static func validOutput(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .effectOutput
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name == nil
    }

    private static func validTarget(
        _ identity: Graph.TextureIdentity,
        effect: Graph.EffectKey,
        layerID: Int
    ) -> Bool {
        identity.kind == .framebuffer
            && identity.layerID == layerID
            && identity.effect == effect
            && identity.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
