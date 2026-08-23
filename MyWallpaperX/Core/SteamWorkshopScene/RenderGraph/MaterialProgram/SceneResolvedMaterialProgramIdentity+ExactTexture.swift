import Foundation
import Metal

nonisolated extension SceneResolvedMaterialProgramIdentity {
    static func exactTexture(
        _ slot: Program.TextureSlot
    ) -> Program.ExactTextureIdentity {
        let resource = slot.resource
        let publication = resource.publication
        let candidate = publication.candidate
        let transform = candidate.uvTransform
        return .init(
            reference: slot.reference,
            registryIdentity: slot.registryIdentity,
            graphInputSource: slot.graphInputSourceFact,
            resourceIdentity: candidate.identity,
            resourceGeneration: candidate.generation,
            contentGeneration: publication.contentGeneration,
            registryResourceGeneration: resource.resourceGeneration,
            purpose: candidate.purpose,
            content: candidate.content,
            physicalExtent: [
                Int(candidate.physicalSize.width),
                Int(candidate.physicalSize.height),
            ],
            mappedExtent: [
                Int(candidate.mappedSize.width),
                Int(candidate.mappedSize.height),
            ],
            uvBitPatterns: [
                transform.origin.x.bitPattern,
                transform.origin.y.bitPattern,
                transform.xAxis.x.bitPattern,
                transform.xAxis.y.bitPattern,
                transform.yAxis.x.bitPattern,
                transform.yAxis.y.bitPattern,
            ],
            sampling: candidate.sampling,
            samplingRawFlags: candidate.sampling.rawFlags,
            authoredFormat: candidate.authoredFormat,
            pixelFormatRawValue: candidate.texture.pixelFormat.rawValue,
            mipLevelCount: candidate.texture.mipmapLevelCount,
            deviceRegistryID: candidate.texture.device.registryID,
            textureObjectIdentifier: ObjectIdentifier(candidate.texture)
        )
    }
}
