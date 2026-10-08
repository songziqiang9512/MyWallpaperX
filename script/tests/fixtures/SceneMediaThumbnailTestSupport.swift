// Shared test doubles and image/state observation helpers for the media fixture.
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

struct SceneBaseMaterialProviderBindingProgram {
    struct BaseMaterialBinding: Hashable {
        enum Source: Hashable { case layerInstance, materialPass }
        enum Provider: Hashable {
            case current, previous
            case userProperty(SceneUserPropertyTextureIdentity)
            var authoredName: String {
                switch self {
                case .current: SceneBaseMaterialProviderBindingProgram.currentIdentity
                case .previous: SceneBaseMaterialProviderBindingProgram.previousIdentity
                case let .userProperty(identity): identity.propertyKey
                }
            }
            var diagnosticPrefix: String {
                switch self {
                case .current: "base-material-current"
                case .previous: "base-material-previous"
                case .userProperty: "base-material-user-property"
                }
            }
            var frameIdentity: SceneFrameTextureIdentity {
                switch self {
                case .current, .previous:
                    .system(.init(
                        name: authoredName,
                        purpose: .premultipliedColor
                    ))
                case let .userProperty(identity):
                    .materialUserProperty(identity)
                }
            }
            var isSystemProvider: Bool {
                switch self {
                case .current, .previous: true
                case .userProperty: false
                }
            }
            var userPropertyIdentity: SceneUserPropertyTextureIdentity? {
                guard case let .userProperty(identity) = self else { return nil }
                return identity
            }
            func accepts(_ candidate: SceneTextureCandidate) -> Bool {
                switch self {
                case .current:
                    return candidate.identity == .provider(.mediaThumbnailCurrent)
                case .previous:
                    return candidate.identity == .provider(.mediaThumbnailPrevious)
                case let .userProperty(identity):
                    guard candidate.purpose == identity.purpose else { return false }
                    if case .file = candidate.identity { return true }
                    return false
                }
            }
        }
        let layerID: Int
        let source: Source
        let slotIndex: Int
        let provider: Provider
        let fallbackAsset: SceneAssetTextureIdentity?
        init(
            layerID: Int,
            source: Source,
            slotIndex: Int,
            provider: Provider = .current,
            fallbackAsset: SceneAssetTextureIdentity? = nil
        ) {
            self.layerID = layerID
            self.source = source
            self.slotIndex = slotIndex
            self.provider = provider
            self.fallbackAsset = fallbackAsset
        }
    }
    static let currentIdentity = "$mediaThumbnail"
    static let previousIdentity = "$mediaPreviousThumbnail"
    let baseMaterialBindings: [Int: BaseMaterialBinding]
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        var isImageRenderable: Bool {
            contentKind == "image" || contentKind == "solid"
        }
    }
}

struct SceneBaseImageTextureSnapshot {
    let textures: [Int: MTLTexture]
    let candidates: [Int: SceneTextureCandidate]

    subscript(layerID: Int) -> MTLTexture? { textures[layerID] }

    func candidate(for layerID: Int, matching texture: MTLTexture) -> SceneTextureCandidate? {
        guard let candidate = candidates[layerID], candidate.texture === texture else {
            return nil
        }
        return candidate
    }
}

struct SceneMetalRenderer {
    let baseMaterialProviderBindings: SceneBaseMaterialProviderBindingProgram
    let textureRegistry: SceneFrameTextureRegistry
}

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

func png(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    alpha: UInt8 = 255,
    width: Int = 1,
    height: Int = 1
) -> Data {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for _ in 0 ..< width * height {
        bytes.append(contentsOf: [red, green, blue, alpha])
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func pixel(_ texture: MTLTexture?) -> [UInt8] {
    guard let texture else { return [] }
    var bytes = [UInt8](repeating: 0, count: 4)
    texture.getBytes(
        &bytes,
        bytesPerRow: 4,
        from: MTLRegionMake2D(0, 0, 1, 1),
        mipmapLevel: 0
    )
    return bytes
}

func waitFor(_ store: SceneMediaThumbnailTextureStore, generation: UInt64) -> SceneMediaThumbnailTextureStore.Snapshot {
    for _ in 0..<200 {
        let snapshot = store.snapshot()
        if snapshot.generation == generation { return snapshot }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return store.snapshot()
}

final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func decode(_ data: Data) -> CGImage? {
        lock.lock()
        count += 1
        lock.unlock()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

func providerStateIsAbsent(
    _ snapshot: SceneMediaThumbnailTextureStore.Snapshot,
    _ identity: SceneSystemProviderTextureIdentity
) -> Bool {
    guard case .absent? = snapshot.providerStates[identity] else { return false }
    return true
}
func providerStateIsPending(
    _ snapshot: SceneMediaThumbnailTextureStore.Snapshot,
    _ identity: SceneSystemProviderTextureIdentity
) -> Bool {
    guard case .pending? = snapshot.providerStates[identity] else { return false }
    return true
}
func providerStateIsUnavailable(
    _ snapshot: SceneMediaThumbnailTextureStore.Snapshot,
    _ identity: SceneSystemProviderTextureIdentity
) -> Bool {
    guard case .unavailable? = snapshot.providerStates[identity] else { return false }
    return true
}
func providerStateIsReady(
    _ snapshot: SceneMediaThumbnailTextureStore.Snapshot,
    _ identity: SceneSystemProviderTextureIdentity,
    matching texture: MTLTexture?
) -> Bool {
    guard
        let texture,
        case let .ready(publication)? = snapshot.providerStates[identity]
    else {
        return false
    }
    return publication.requestIdentity == .system(identity)
        && publication.texture === texture
        && publication.isComplete
}
