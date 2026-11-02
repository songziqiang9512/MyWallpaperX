import Foundation
import Metal

extension ScenePreparedBaseImageResources {
    struct PuppetClippingPreparation {
        let paintTextures: [Int: MTLTexture]
        let readFailed: Bool
    }

    static func preparePuppetClipping(
        resources: ScenePreparedPuppetResources,
        dynamicResources: [String: ScenePreparedDynamicImageResource],
        resolver: SceneTexturePathResolver,
        textureLoader: SceneTextureLoader,
        device: MTLDevice,
        cancellationCheck: () throws -> Void
    ) throws -> [String: PuppetClippingPreparation] {
        var assets: [String: ScenePuppetLayerLoad.PreparedAsset] = resources.assetsByMeshPath.compactMapValues { preparation in
            if case let .ready(asset) = preparation { return asset }
            return nil
        }
        for resource in dynamicResources.values {
            guard let pose = resource.puppetPose else { continue }
            switch pose.geometry {
            case let .bind(asset, _), let .evaluated(asset, _, _, _, _):
                assets[asset.meshPath.lowercased()] = asset
            case .unavailable: break
            }
        }
        var prepared: [String: PuppetClippingPreparation] = [:]
        for (path, asset) in assets where !asset.mesh.clipRecords.isEmpty {
            var paints: [Int: MTLTexture] = [:]
            var readFailed = false
            for (index, record) in asset.mesh.clipRecords.enumerated() {
                try cancellationCheck()
                do {
                    guard let input = resolver.resolveTextureFile(named: record.maskTexturePath),
                          case let .loaded(texture) = try textureLoader.loadDataTexture(
                            from: input, device: device),
                          texture.pixelFormat == .r8Unorm else { continue }
                    paints[index] = texture
                } catch {
                    readFailed = true
                }
            }
            prepared[path] = .init(paintTextures: paints, readFailed: readFailed)
        }
        return prepared
    }
}
