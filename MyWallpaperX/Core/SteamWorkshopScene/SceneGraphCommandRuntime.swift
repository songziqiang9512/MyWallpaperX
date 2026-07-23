import Metal

struct SceneGraphCommandRuntime {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneGraphRenderTargetPlan

    enum Failure: String, Error {
        case commandOrderMismatch
        case missingTexture
        case incompatibleTextures
        case commandBufferDeviceMismatch
        case encoderUnavailable
    }

    private let commands: [Plan.Command]
    private var texturesByIdentity: [Graph.TextureIdentity: MTLTexture]
    private var nextCommandIndex = 0

    init?(
        plan: Plan,
        texturesByIdentity: [Graph.TextureIdentity: MTLTexture]
    ) {
        let requiredIdentities = Set(
            [plan.input, plan.output] + plan.logicalTargets.map(\.identity)
        )
        guard Set(texturesByIdentity.keys) == requiredIdentities,
              requiredIdentities.count == texturesByIdentity.count,
              zip(plan.commands, plan.commands.dropFirst()).allSatisfy({
                  $0.nodeIndex < $1.nodeIndex
              }),
              plan.commands.allSatisfy({
                  requiredIdentities.contains($0.source)
                      && requiredIdentities.contains($0.target)
                      && $0.source != $0.target
              }) else {
            return nil
        }
        commands = plan.commands
        self.texturesByIdentity = texturesByIdentity
    }

    var remainingCommandCount: Int {
        commands.count - nextCommandIndex
    }

    var isComplete: Bool {
        remainingCommandCount == 0
    }

    func texture(for identity: Graph.TextureIdentity) -> MTLTexture? {
        texturesByIdentity[identity]
    }

    mutating func encodeCommand(
        at nodeIndex: Int,
        commandBuffer: MTLCommandBuffer
    ) -> Result<Void, Failure> {
        guard commands.indices.contains(nextCommandIndex),
              commands[nextCommandIndex].nodeIndex == nodeIndex else {
            return .failure(.commandOrderMismatch)
        }
        let command = commands[nextCommandIndex]
        guard let source = texturesByIdentity[command.source],
              let target = texturesByIdentity[command.target] else {
            return .failure(.missingTexture)
        }
        guard source !== target, Self.compatible(source, target) else {
            return .failure(.incompatibleTextures)
        }
        let commandDevice = commandBuffer.commandQueue.device.registryID
        guard source.device.registryID == commandDevice,
              target.device.registryID == commandDevice else {
            return .failure(.commandBufferDeviceMismatch)
        }

        switch command.kind {
        case .copy:
            guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
                return .failure(.encoderUnavailable)
            }
            encoder.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(
                    width: source.width,
                    height: source.height,
                    depth: 1
                ),
                to: target,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: .init(x: 0, y: 0, z: 0)
            )
            encoder.endEncoding()
        case .swap:
            texturesByIdentity[command.source] = target
            texturesByIdentity[command.target] = source
        }
        nextCommandIndex += 1
        return .success(())
    }

    private static func compatible(_ source: MTLTexture, _ target: MTLTexture) -> Bool {
        source.textureType == target.textureType
            && source.pixelFormat == target.pixelFormat
            && source.width == target.width
            && source.height == target.height
            && source.depth == target.depth
            && source.arrayLength == target.arrayLength
            && source.mipmapLevelCount == target.mipmapLevelCount
            && source.sampleCount == target.sampleCount
    }
}
