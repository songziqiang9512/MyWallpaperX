import Foundation
import Metal

nonisolated struct SceneUserPropertyTextureLoadResult {
    let textures: [String: MTLTexture]
    let textureCandidates: [String: SceneTextureCandidate]
    let providerStates: [SceneUserPropertyTextureIdentity: SceneTextureProviderState]
    let reportLines: [String]

    static let empty = Self(textures: [:], textureCandidates: [:], providerStates: [:], reportLines: [])

    func replacing(propertyKeys: Set<String>, with replacement: Self) -> Self {
        Self(
            textures: textures.filter { !propertyKeys.contains($0.key) }
                .merging(replacement.textures) { _, new in new },
            textureCandidates: textureCandidates.filter { !propertyKeys.contains($0.key) }
                .merging(replacement.textureCandidates) { _, new in new },
            providerStates: providerStates.filter { !propertyKeys.contains($0.key.propertyKey) }
                .merging(replacement.providerStates) { _, new in new },
            reportLines: replacement.reportLines
        )
    }

    func hasCompletePublications(for identities: Set<SceneUserPropertyTextureIdentity>) -> Bool {
        identities.allSatisfy {
            guard case let .ready(publication)? = providerStates[$0] else { return false }
            return publication.requestIdentity == .materialUserProperty($0)
                && publication.isComplete && publication.generationIsCurrent
        }
    }

    func satisfiesRequiredProperties(
        _ keys: Set<String>, selectedKeys: Set<String>,
        demands: Set<SceneUserPropertyTextureIdentity>
    ) -> Bool {
        guard keys.isSubset(of: Set(demands.map(\.propertyKey))) else { return false }
        let identities = Set(demands.filter { keys.contains($0.propertyKey) })
            .union(keys.compactMap {
                SceneUserPropertyTextureIdentity(propertyKey: $0, purpose: .premultipliedColor)
            })
        let selected = Set(identities.filter { selectedKeys.contains($0.propertyKey) })
        return hasCompletePublications(for: selected)
            && identities.subtracting(selected).allSatisfy {
                if case .absent? = providerStates[$0] { return true }
                return false
            }
    }

    var straightAlbedoTextures: [String: MTLTexture] {
        publishedTextures(for: .straightAlbedo)
    }

    var preservedTextures: [String: MTLTexture] {
        publishedTextures(for: .preservedChannels)
    }

    var publications: [
        SceneUserPropertyTextureIdentity: SceneTextureProviderPublication
    ] {
        providerStates.reduce(into: [:]) { result, pair in
            guard case let .ready(publication) = pair.value else { return }
            result[pair.key] = publication
        }
    }

    private func publishedTextures(
        for purpose: SceneTextureLoadPurpose
    ) -> [String: MTLTexture] {
        publications.reduce(into: [:]) { result, pair in
            guard pair.key.purpose == purpose else { return }
            result[pair.key.propertyKey] = pair.value.texture
        }
    }
}

nonisolated struct SceneUserPropertyTextureLoader {
    private static let supportedFileExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func supports(url: URL) -> Bool {
        supportedFileExtensions.contains(url.pathExtension.localizedLowercase)
    }

    func load(
        urlsByPropertyKey: [String: URL],
        requestedIdentities: Set<SceneUserPropertyTextureIdentity> = [],
        textureUploadCommandQueue: SceneTextureUploadCommandQueue = .init(),
        textureDecodeCacheBudget: SceneTextureDecodeCacheBudget = .init(
            maximumBytes: 1_024 * 1_024 * 1_024
        ),
        device: MTLDevice,
        contentGeneration: UInt64 = 1,
        isCancelled: () -> Bool = { false }
    ) -> SceneUserPropertyTextureLoadResult {
        guard !urlsByPropertyKey.isEmpty || !requestedIdentities.isEmpty else {
            return SceneUserPropertyTextureLoadResult(
                textures: [:],
                textureCandidates: [:],
                providerStates: [:],
                reportLines: []
            )
        }
        let loader = SceneTextureLoader(
            uploadCommandQueue: textureUploadCommandQueue,
            decodeCacheBudget: textureDecodeCacheBudget
        )
        var textures: [String: MTLTexture] = [:]
        var textureCandidates: [String: SceneTextureCandidate] = [:]
        var providerStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:]
        for identity in requestedIdentities {
            providerStates[identity] = urlsByPropertyKey[identity.propertyKey] == nil
                ? .absent : .unavailable
        }
        var reportLines = ["sceneUserTextureRequestedCount: \(urlsByPropertyKey.count)"]
        for key in urlsByPropertyKey.keys.sorted() {
            guard !isCancelled(), let url = urlsByPropertyKey[key] else { break }
            let purposes = Set(requestedIdentities.filter { $0.propertyKey == key }.map(\.purpose))
                .union([.premultipliedColor])
            for purpose in purposes {
                if let identity = SceneUserPropertyTextureIdentity(propertyKey: key, purpose: purpose) {
                    providerStates[identity] = .unavailable
                }
            }
            guard Self.supports(url: url) else {
                reportLines.append("scene user texture \(key): unsupported \(url.pathExtension.lowercased())")
                continue
            }
            let outcomes = loader.loadDirectImageCandidates(
                from: url, purposes: purposes, device: device, isCancelled: isCancelled
            )
            for purpose in purposes.sorted(by: { $0.reportToken < $1.reportToken }) {
                guard !isCancelled(), let outcome = outcomes[purpose] else { break }
                switch outcome {
                case let .loaded(candidate):
                    if purpose == .premultipliedColor {
                        textures[key] = candidate.texture
                        textureCandidates[key] = candidate
                    }
                    publish(candidate, propertyKey: key, contentGeneration: contentGeneration,
                            into: &providerStates)
                    reportLines.append("scene user texture \(key) \(purpose.reportToken): OK "
                        + "\(url.lastPathComponent) -> \(candidate.texture.width)x\(candidate.texture.height)")
                case let .failed(outcome):
                    reportLines.append("scene user texture \(key) \(purpose.reportToken): "
                        + failureDescription(outcome))
                }
            }
        }
        reportLines.append("sceneUserTextureLoadedCount: \(textures.count)")
        let readyPurposeCount: (SceneTextureLoadPurpose) -> Int = { purpose in
            providerStates.reduce(into: 0) { count, pair in
                guard pair.key.purpose == purpose,
                      case .ready = pair.value else { return }
                count += 1
            }
        }
        reportLines.append(
            "sceneUserTextureStraightAlbedoLoadedCount: \(readyPurposeCount(.straightAlbedo))"
        )
        reportLines.append(
            "sceneUserTexturePreservedLoadedCount: \(readyPurposeCount(.preservedChannels))"
        )
        return SceneUserPropertyTextureLoadResult(
            textures: textures,
            textureCandidates: textureCandidates,
            providerStates: providerStates,
            reportLines: reportLines
        )
    }

    private func failureDescription(_ outcome: SceneTextureLoadOutcome) -> String {
        switch outcome {
        case let .decodeFailed(message): "decode failed (\(message))"
        case let .textureAllocationFailed(width, height): "allocation failed at \(width)x\(height)"
        case .unsupportedFormat, .unsupportedTexFormat, .texNoEmbeddedImage, .texContainsVideoPayload:
            "unsupported image payload"
        case .loaded: "typed candidate unavailable"
        }
    }

    private func publish(
        _ candidate: SceneTextureCandidate,
        propertyKey: String,
        contentGeneration: UInt64,
        into states: inout [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ]
    ) {
        guard let identity = SceneUserPropertyTextureIdentity(
            propertyKey: propertyKey,
            purpose: candidate.purpose
        ) else { return }
        let publication = SceneTextureProviderPublication(
            requestIdentity: .materialUserProperty(identity),
            candidate: candidate, contentGeneration: contentGeneration
        )
        states[identity] = publication.isComplete ? .ready(publication) : .unavailable
    }
}
