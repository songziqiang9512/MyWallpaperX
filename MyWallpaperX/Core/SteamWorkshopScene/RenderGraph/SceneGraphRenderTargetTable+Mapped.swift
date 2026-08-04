import Metal

extension SceneGraphRenderTargetTable {
    /// Checked legacy entry: semantic input and output own both pair members and
    /// therefore must remain physically distinct.
    static func makeMapped(
        plan: SceneGraphRenderTargetPlan,
        device: MTLDevice,
        texturesByIdentity: [Graph.TextureIdentity: MTLTexture]
    ) -> Result<Self, Failure> {
        guard let input = texturesByIdentity[plan.input],
              let output = texturesByIdentity[plan.output] else {
            return .failure(.mappedTextureInvalid)
        }
        return makeMapped(
            plan: plan,
            device: device,
            texturesByIdentity: texturesByIdentity,
            fullFramePair: .init(first: input, second: output),
            expectsInputOutputAlias: false
        )
    }

    /// Checked whole-chain entry. Only the two semantic endpoints may share one
    /// full-frame member, and only when the admitted transition parity requires
    /// it. Authored FBOs remain disjoint from the pair and from one another.
    static func makeMapped(
        plan: SceneGraphRenderTargetPlan,
        device: MTLDevice,
        texturesByIdentity: [Graph.TextureIdentity: MTLTexture],
        fullFramePair: FullFramePair,
        expectsInputOutputAlias: Bool
    ) -> Result<Self, Failure> {
        guard let specifications = specifications(for: plan),
              specifications.count == texturesByIdentity.count,
              Set(specifications.map(\.identity)) == Set(texturesByIdentity.keys),
              let input = texturesByIdentity[plan.input],
              let output = texturesByIdentity[plan.output],
              let endpointSpecification = specifications.first(where: {
                  $0.identity == plan.input
              }) else { return .failure(.mappedTextureInvalid) }

        let firstObject = ObjectIdentifier(fullFramePair.first)
        let secondObject = ObjectIdentifier(fullFramePair.second)
        let pairObjects = Set([firstObject, secondObject])
        guard pairObjects.count == 2 else { return .failure(.mappedTextureAliased) }
        guard [fullFramePair.first, fullFramePair.second].allSatisfy({ texture in
            texture.device.registryID == device.registryID
                && validMappedTexture(texture, specification: endpointSpecification)
        }) else { return .failure(.mappedTextureInvalid) }

        let inputObject = ObjectIdentifier(input)
        let outputObject = ObjectIdentifier(output)
        guard pairObjects.contains(inputObject), pairObjects.contains(outputObject) else {
            return .failure(.mappedTextureInvalid)
        }
        if expectsInputOutputAlias {
            guard inputObject == outputObject else {
                return .failure(.mappedTextureAliased)
            }
        } else {
            guard Set([inputObject, outputObject]) == pairObjects else {
                return .failure(.mappedTextureAliased)
            }
        }

        var framebufferObjects = Set<ObjectIdentifier>()
        for specification in specifications {
            guard let texture = texturesByIdentity[specification.identity],
                  texture.device.registryID == device.registryID,
                  validMappedTexture(texture, specification: specification) else {
                return .failure(.mappedTextureInvalid)
            }
            guard specification.identity != plan.input,
                  specification.identity != plan.output else { continue }
            let object = ObjectIdentifier(texture)
            guard !pairObjects.contains(object),
                  framebufferObjects.insert(object).inserted else {
                return .failure(.mappedTextureAliased)
            }
        }

        guard let pairMemberBytes = byteCost(for: endpointSpecification) else {
            return .failure(.byteCostOverflow)
        }
        let (pairBytes, pairOverflow) = pairMemberBytes.multipliedReportingOverflow(by: 2)
        guard !pairOverflow else { return .failure(.byteCostOverflow) }
        var totalByteCost = pairBytes
        for specification in specifications where
            specification.identity != plan.input && specification.identity != plan.output {
            guard let bytes = byteCost(for: specification) else {
                return .failure(.byteCostOverflow)
            }
            let (next, overflow) = totalByteCost.addingReportingOverflow(bytes)
            guard !overflow else { return .failure(.byteCostOverflow) }
            totalByteCost = next
        }
        return .success(Self(
            plan: plan,
            inputTexture: input,
            outputTexture: output,
            fullFramePair: fullFramePair,
            inputOutputAliased: expectsInputOutputAlias,
            residentByteCost: totalByteCost,
            texturesByIdentity: texturesByIdentity
        ))
    }
}
