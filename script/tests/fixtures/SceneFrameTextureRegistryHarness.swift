@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "SceneFrameTextureRegistryTests", code: 1)
        }
        let registry = SceneFrameTextureRegistry()
        let fallbackTexture = texture(device)
        let replacementFallbackTexture = texture(device)
        let propertyTexture = texture(device)
        let replacementPropertyTexture = texture(device)
        let systemTexture = texture(device)
        let replacementSystemTexture = texture(device)
        let namedTexture = texture(device)
        let dynamicTexture = texture(device)
        let replacementDynamicTexture = texture(device)
        let staleDynamicTexture = texture(device)
        let (graphLayerSource, currentResult) = currentAndPersistentCases(
            device: device,
            registry: registry,
            fallbackTexture: fallbackTexture,
            replacementFallbackTexture: replacementFallbackTexture,
            propertyTexture: propertyTexture,
            replacementPropertyTexture: replacementPropertyTexture,
            systemTexture: systemTexture,
            replacementSystemTexture: replacementSystemTexture,
            namedTexture: namedTexture,
            dynamicTexture: dynamicTexture,
            replacementDynamicTexture: replacementDynamicTexture,
            staleDynamicTexture: staleDynamicTexture
        )
        let publicationResult = typedPublicationCases(
            registry: registry,
            dynamicTexture: dynamicTexture,
            replacementDynamicTexture: replacementDynamicTexture,
            graphLayerSource: graphLayerSource
        )
        let lifecycleResult = videoAndRollbackCases(
            dynamicTexture: dynamicTexture,
            replacementDynamicTexture: replacementDynamicTexture,
            staleDynamicTexture: staleDynamicTexture
        )
        let directSampling = SceneTextureSampling.linearClamp
        let programSamplerAdmissionIsBounded =
            directSampling.rawFlags == nil
            && directSampling.isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 0).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 1).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 2).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 3).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 2) == .linearClamp
            && SceneTextureSampling(texFlags: 4).isResolvedForMaterialProgram
            // Authored component selectors occupy bits 20...23 and are
            // metadata consumed by the material path, not unknown sampler
            // behavior. Keep this admission contract explicit.
            && SceneTextureSampling(texFlags: 0x00A00002).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 0x00F00000).isResolvedForMaterialProgram
            && !SceneTextureSampling(texFlags: 0x00100008).isResolvedForMaterialProgram
            && !SceneTextureSampling(texFlags: 8).isResolvedForMaterialProgram
            && !SceneTextureSampling(texFlags: 16).isResolvedForMaterialProgram
            && SceneTextureSampling(texFlags: 8).rawFlags == 8
        var result: [String: Any] = [
            "propertyResetRetirement": propertyResetRetirementChecks(device),
            "environmentPublication": environmentPublication(device),
            "programSamplerAdmissionIsBounded": programSamplerAdmissionIsBounded,
        ]
        result.merge(currentResult) { _, new in new }
        result.merge(publicationResult) { _, new in new }
        result.merge(lifecycleResult) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func texture(
        _ device: MTLDevice,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }
    static func publication(
        _ texture: MTLTexture,
        generation: UInt64,
        requestIdentity: SceneFrameTextureIdentity = .layerSource(8),
        identity: SceneTextureResourceIdentity =
            .provider(.dynamicText(layerID: 8)),
        candidateGeneration: SceneTextureResourceGeneration? = nil,
        purpose: SceneTextureLoadPurpose = .premultipliedColor,
        content: SceneTextureContent =
            .color(.resolved(.premultipliedAlpha))
    ) -> SceneTextureProviderPublication {
        let size = CGSize(width: texture.width, height: texture.height)
        return SceneTextureProviderPublication(
            requestIdentity: requestIdentity,
            candidate: SceneTextureCandidate(
                texture: texture,
                identity: identity,
                generation: candidateGeneration
                    ?? .provider(contentGeneration: generation),
                purpose: purpose,
                content: content,
                physicalSize: size,
                mappedSize: size,
                uvTransform: .identity,
                sampling: .linearClamp
            ),
            contentGeneration: generation
        )
    }
    static func bareResolution(
        _ registry: SceneFrameTextureRegistry,
        _ identity: SceneFrameTextureIdentity
    ) -> (texture: MTLTexture, generation: UInt64)? {
        guard let texture = registry.texture(for: identity),
              case let .incomplete(.bare(_, generation))? = registry.lookup(identity)
        else { return nil }
        return (texture, generation)
    }
    static func typedResolution(
        _ registry: SceneFrameTextureRegistry,
        _ identity: SceneFrameTextureIdentity
    ) -> (texture: MTLTexture, generation: UInt64)? {
        guard let resource = registry.resource(for: identity) else { return nil }
        return (resource.publication.texture, resource.resourceGeneration)
    }

}
