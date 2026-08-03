import Foundation
import Metal

struct SceneUserPropertyTextureLoadResult {
    let textures: [String: MTLTexture]
    let textureCandidates: [String: SceneTextureCandidate]
    let straightAlbedoTextures: [String: MTLTexture]
    let preservedTextures: [String: MTLTexture]
    let providerStates: [SceneUserPropertyTextureIdentity: SceneTextureProviderState]
    let reportLines: [String]

    var publications: [
        SceneUserPropertyTextureIdentity: SceneTextureProviderPublication
    ] {
        providerStates.reduce(into: [:]) { result, pair in
            guard case let .ready(publication) = pair.value else { return }
            result[pair.key] = publication
        }
    }
}

struct SceneUserPropertyTextureLoader {
    private static let supportedFileExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func supports(url: URL) -> Bool {
        supportedFileExtensions.contains(url.pathExtension.localizedLowercase)
    }

    func load(
        urlsByPropertyKey: [String: URL],
        requestedIdentities: Set<SceneUserPropertyTextureIdentity> = [],
        straightAlbedoPropertyKeys: Set<String> = [],
        preservedPropertyKeys: Set<String> = [],
        device: MTLDevice
    ) -> SceneUserPropertyTextureLoadResult {
        guard !urlsByPropertyKey.isEmpty || !requestedIdentities.isEmpty else {
            return SceneUserPropertyTextureLoadResult(
                textures: [:],
                textureCandidates: [:],
                straightAlbedoTextures: [:],
                preservedTextures: [:],
                providerStates: [:],
                reportLines: []
            )
        }
        let loader = SceneTextureLoader()
        var textures: [String: MTLTexture] = [:]
        var textureCandidates: [String: SceneTextureCandidate] = [:]
        var straightAlbedoTextures: [String: MTLTexture] = [:]
        var preservedTextures: [String: MTLTexture] = [:]
        var providerStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:]
        let requestedStraightAlbedoKeys = straightAlbedoPropertyKeys.union(
            requestedIdentities.compactMap {
                $0.purpose == .straightAlbedo ? $0.propertyKey : nil
            }
        )
        let requestedPreservedKeys = preservedPropertyKeys.union(
            requestedIdentities.compactMap {
                $0.purpose == .preservedChannels ? $0.propertyKey : nil
            }
        )
        for identity in requestedIdentities {
            providerStates[identity] = urlsByPropertyKey[identity.propertyKey] == nil
                ? .absent
                : .unavailable
        }
        var reportLines = ["sceneUserTextureRequestedCount: \(urlsByPropertyKey.count)"]

        for key in urlsByPropertyKey.keys.sorted() {
            guard let url = urlsByPropertyKey[key] else { continue }
            var requestedPurposes: [SceneTextureLoadPurpose] = [.premultipliedColor]
            if requestedStraightAlbedoKeys.contains(key) {
                requestedPurposes.append(.straightAlbedo)
            }
            if requestedPreservedKeys.contains(key) {
                requestedPurposes.append(.preservedChannels)
            }
            for purpose in requestedPurposes {
                guard let identity = SceneUserPropertyTextureIdentity(
                    propertyKey: key,
                    purpose: purpose
                ) else { continue }
                providerStates[identity] = .unavailable
            }
            guard Self.supports(url: url) else {
                reportLines.append("scene user texture \(key): unsupported \(url.pathExtension.lowercased())")
                continue
            }
            switch loader.loadCandidate(
                from: url,
                purpose: .premultipliedColor,
                device: device
            ) {
            case let .loaded(candidate):
                textures[key] = candidate.texture
                textureCandidates[key] = candidate
                publish(candidate, propertyKey: key, into: &providerStates)
                reportLines.append(
                    "scene user texture \(key): OK \(url.lastPathComponent) -> "
                        + "\(candidate.texture.width)x\(candidate.texture.height)"
                )
            case let .failed(outcome):
                switch outcome {
                case let .decodeFailed(message):
                    reportLines.append(
                        "scene user texture \(key): decode failed (\(message))"
                    )
                case let .textureAllocationFailed(width, height):
                    reportLines.append(
                        "scene user texture \(key): allocation failed at \(width)x\(height)"
                    )
                case .unsupportedFormat, .unsupportedTexFormat,
                     .texNoEmbeddedImage, .texContainsVideoPayload:
                    reportLines.append(
                        "scene user texture \(key): unsupported image payload"
                    )
                case .loaded:
                    reportLines.append(
                        "scene user texture \(key): typed candidate unavailable"
                    )
                }
            }
            if requestedStraightAlbedoKeys.contains(key) {
                switch loader.loadCandidate(
                    from: url,
                    purpose: .straightAlbedo,
                    device: device
                ) {
                case let .loaded(candidate):
                    straightAlbedoTextures[key] = candidate.texture
                    publish(candidate, propertyKey: key, into: &providerStates)
                    reportLines.append(
                        "scene user texture \(key) straight albedo: OK "
                            + "\(url.lastPathComponent) -> \(candidate.texture.width)x"
                            + "\(candidate.texture.height)"
                    )
                case let .failed(.decodeFailed(message)):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: decode failed (\(message))"
                    )
                case let .failed(.textureAllocationFailed(width, height)):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: allocation failed at "
                            + "\(width)x\(height)"
                    )
                case .failed(.unsupportedFormat), .failed(.unsupportedTexFormat),
                     .failed(.texNoEmbeddedImage), .failed(.texContainsVideoPayload):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: unsupported image payload"
                    )
                case .failed(.loaded):
                    reportLines.append(
                        "scene user texture \(key) straight albedo: typed candidate unavailable"
                    )
                }
            }
            if requestedPreservedKeys.contains(key) {
                switch loader.loadCandidate(
                    from: url,
                    purpose: .preservedChannels,
                    device: device
                ) {
                case let .loaded(candidate):
                    preservedTextures[key] = candidate.texture
                    publish(candidate, propertyKey: key, into: &providerStates)
                    reportLines.append(
                        "scene user texture \(key) preserved: OK "
                            + "\(url.lastPathComponent) -> \(candidate.texture.width)x"
                            + "\(candidate.texture.height)"
                    )
                case let .failed(.decodeFailed(message)):
                    reportLines.append(
                        "scene user texture \(key) preserved: decode failed (\(message))"
                    )
                case let .failed(.textureAllocationFailed(width, height)):
                    reportLines.append(
                        "scene user texture \(key) preserved: allocation failed at "
                            + "\(width)x\(height)"
                    )
                case .failed(.unsupportedFormat), .failed(.unsupportedTexFormat),
                     .failed(.texNoEmbeddedImage), .failed(.texContainsVideoPayload):
                    reportLines.append(
                        "scene user texture \(key) preserved: unsupported image payload"
                    )
                case .failed(.loaded):
                    reportLines.append(
                        "scene user texture \(key) preserved: typed candidate unavailable"
                    )
                }
            }
        }
        let legacyPurposes: Set<SceneTextureLoadPurpose> = [
            .premultipliedColor, .straightAlbedo, .preservedChannels,
        ]
        for identity in requestedIdentities.sorted(by: {
            $0.reportToken < $1.reportToken
        }) where !legacyPurposes.contains(identity.purpose) {
            guard let url = urlsByPropertyKey[identity.propertyKey],
                  Self.supports(url: url) else { continue }
            switch loader.loadCandidate(
                from: url,
                purpose: identity.purpose,
                device: device
            ) {
            case let .loaded(candidate):
                publish(candidate, propertyKey: identity.propertyKey, into: &providerStates)
            case let .failed(outcome):
                reportLines.append(
                    "scene user texture \(identity.reportToken): unavailable \(outcome)"
                )
            }
        }
        reportLines.append("sceneUserTextureLoadedCount: \(textures.count)")
        reportLines.append(
            "sceneUserTextureStraightAlbedoLoadedCount: \(straightAlbedoTextures.count)"
        )
        reportLines.append(
            "sceneUserTexturePreservedLoadedCount: \(preservedTextures.count)"
        )
        return SceneUserPropertyTextureLoadResult(
            textures: textures,
            textureCandidates: textureCandidates,
            straightAlbedoTextures: straightAlbedoTextures,
            preservedTextures: preservedTextures,
            providerStates: providerStates,
            reportLines: reportLines
        )
    }

    private func publish(
        _ candidate: SceneTextureCandidate,
        propertyKey: String,
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
            candidate: candidate, contentGeneration: 1
        )
        states[identity] = publication.isComplete ? .ready(publication) : .unavailable
    }
}
