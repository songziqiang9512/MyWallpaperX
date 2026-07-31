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
        case borrowedTextureInvalid
    }

    let plan: SceneGraphRenderTargetPlan
    let inputTexture: MTLTexture
    let outputTexture: MTLTexture
    let residentByteCost: Int

    private let texturesByIdentity: [Graph.TextureIdentity: MTLTexture]
    private let initializationState: InitializationState

    private final class InitializationState {
        var needsInitialInitialization = true
        var clearInFlight = false
    }

    var residentTextureCount: Int {
        texturesByIdentity.count
    }

    func texture(for identity: Graph.TextureIdentity) -> MTLTexture? {
        texturesByIdentity[identity]
    }

    func makeCommandRuntime() -> SceneGraphCommandRuntime? {
        SceneGraphCommandRuntime(plan: plan, texturesByIdentity: texturesByIdentity)
    }

    func encodeInitialTargetClear(commandBuffer: MTLCommandBuffer) -> Bool {
        let targets = plan.logicalTargets.filter {
            $0.lifetime.requiresHistorySeed || $0.initialClear != nil
        }
        guard !targets.isEmpty else { return true }
        guard initializationState.needsInitialInitialization,
              !initializationState.clearInFlight else {
            return true
        }

        for target in targets {
            guard let texture = texturesByIdentity[target.identity] else { return false }
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            let clear = target.initialClear ?? .init(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(
                clear.red,
                clear.green,
                clear.blue,
                clear.alpha
            )
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return false
            }
            encoder.endEncoding()
        }
        initializationState.clearInFlight = true
        commandBuffer.addCompletedHandler { [initializationState] buffer in
            initializationState.clearInFlight = false
            if buffer.status == .completed {
                initializationState.needsInitialInitialization = false
            }
        }
        return true
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
            guard let byteCost = byteCost(for: specification) else {
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
            texturesByIdentity: textures,
            initializationState: InitializationState()
        ))
    }

    static func makeBorrowed(
        plan: SceneGraphRenderTargetPlan,
        inputTexture: MTLTexture,
        outputTexture: MTLTexture
    ) -> Result<Self, Failure> {
        guard plan.logicalTargets.isEmpty,
              let specifications = specifications(for: plan),
              specifications.count == 2,
              plan.input != plan.output,
              inputTexture !== outputTexture,
              validBorrowedTexture(inputTexture, extent: plan.inputExtent),
              validBorrowedTexture(outputTexture, extent: plan.inputExtent),
              inputTexture.device.registryID == outputTexture.device.registryID else {
            return .failure(.borrowedTextureInvalid)
        }
        return .success(Self(
            plan: plan,
            inputTexture: inputTexture,
            outputTexture: outputTexture,
            residentByteCost: 0,
            texturesByIdentity: [
                plan.input: inputTexture,
                plan.output: outputTexture,
            ],
            initializationState: InitializationState()
        ))
    }

    private struct Specification {
        let identity: Graph.TextureIdentity
        let extent: SceneGraphRenderTargetPlan.PixelExtent
        let format: SceneGraphRenderTargetPlan.TextureFormat
        let role: String
    }

    private static func specifications(
        for plan: SceneGraphRenderTargetPlan
    ) -> [Specification]? {
        guard let effect = plan.output.effect,
              SceneAuthoredEffectInputValidator.accepts(
                plan.input,
                layerID: plan.layerID,
                role: plan.inputRole
              ),
              validOutput(plan.output, effect: effect, layerID: plan.layerID),
              validExtent(plan.inputExtent) else {
            return nil
        }

        var specifications = [Specification(
            identity: plan.input,
            extent: plan.inputExtent,
            format: .rgbaBackbuffer,
            role: "input"
        )]
        specifications.reserveCapacity(plan.logicalTargets.count + 2)
        for target in plan.logicalTargets {
            guard validTarget(target.identity, effect: effect, layerID: plan.layerID),
                  validExtent(target.extent) else {
                return nil
            }
            specifications.append(Specification(
                identity: target.identity,
                extent: target.extent,
                format: target.format,
                role: "framebuffer"
            ))
        }
        specifications.append(Specification(
            identity: plan.output,
            extent: plan.inputExtent,
            format: .rgbaBackbuffer,
            role: "output"
        ))

        let identities = Set(specifications.map(\.identity))
        guard identities.count == specifications.count else { return nil }
        return specifications
    }

    private static func byteCost(for specification: Specification) -> Int? {
        let (pixelCount, pixelOverflow) = specification.extent.width.multipliedReportingOverflow(
            by: specification.extent.height
        )
        guard !pixelOverflow else { return nil }
        let (byteCost, byteOverflow) = pixelCount.multipliedReportingOverflow(
            by: bytesPerPixel(for: specification.format)
        )
        return byteOverflow ? nil : byteCost
    }

    private static func bytesPerPixel(
        for format: SceneGraphRenderTargetPlan.TextureFormat
    ) -> Int {
        switch format {
        case .rgbaBackbuffer, .rgba8888:
            return 4
        }
    }

    private static func makeTexture(
        device: MTLDevice,
        specification: Specification,
        layerID: Int,
        effect: Graph.EffectKey?
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat(for: specification.format),
            width: specification.extent.width,
            height: specification.extent.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        let effectIndex = effect?.effectIndex ?? -1
        let name = specification.identity.name ?? specification.role
        texture?.label = "SceneGraphRT layer=\(layerID) effect=\(effectIndex) \(name) \(specification.format.rawValue)"
        return texture
    }

    private static func pixelFormat(
        for format: SceneGraphRenderTargetPlan.TextureFormat
    ) -> MTLPixelFormat {
        switch format {
        case .rgbaBackbuffer:
            return .bgra8Unorm
        case .rgba8888:
            return .rgba8Unorm
        }
    }

    private static func validExtent(
        _ extent: SceneGraphRenderTargetPlan.PixelExtent
    ) -> Bool {
        extent.width > 0 && extent.height > 0
    }

    private static func validBorrowedTexture(
        _ texture: MTLTexture,
        extent: SceneGraphRenderTargetPlan.PixelExtent
    ) -> Bool {
        texture.textureType == .type2D
            && texture.pixelFormat == .bgra8Unorm
            && texture.width == extent.width
            && texture.height == extent.height
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(.renderTarget)
            && texture.usage.contains(.shaderRead)
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
