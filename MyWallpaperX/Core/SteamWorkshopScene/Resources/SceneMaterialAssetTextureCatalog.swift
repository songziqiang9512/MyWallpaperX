import Foundation
import Metal

/// Immutable scene/device asset publications prepared before the first frame.
/// Accessing `states` never performs VFS lookup, decoding or GPU upload.
struct SceneMaterialAssetTextureCatalog {
    let states: [SceneAssetTextureIdentity: SceneTextureProviderState]

    init(
        demands: Set<SceneAssetTextureIdentity>,
        resourceView: SceneResourceView,
        descriptor: SceneRenderDescriptor,
        device: MTLDevice
    ) {
        let resolver = SceneTexturePathResolver(
            resourceView: resourceView,
            descriptor: descriptor
        )
        let loader = SceneTextureLoader()
        var loaded: [SceneAssetTextureIdentity: SceneTextureProviderState] = [:]
        for identity in demands.sorted(by: Self.less) {
            guard let url = resolver.resolveTextureFile(named: identity.path.value) else {
                loaded[identity] = .absent
                continue
            }
            switch loader.loadCandidate(
                from: url,
                purpose: identity.purpose,
                device: device
            ) {
            case .failed:
                loaded[identity] = .unavailable
            case let .loaded(candidate):
                let request = SceneFrameTextureIdentity.asset(identity)
                let publication = SceneTextureProviderPublication(
                    requestIdentity: request,
                    candidate: candidate,
                    contentGeneration: 1
                )
                guard candidate.purpose == identity.purpose,
                      publication.isComplete else {
                    loaded[identity] = .unavailable
                    continue
                }
                loaded[identity] = .ready(publication)
            }
        }
        states = loaded
    }

    var reportLines: [String] {
        var ready = 0
        var absent = 0
        var pending = 0
        var unavailable = 0
        for state in states.values {
            switch state {
            case .ready: ready += 1
            case .absent: absent += 1
            case .pending: pending += 1
            case .unavailable: unavailable += 1
            }
        }
        return [
            "resolved material asset catalog: schema=r3-vfs-assets-v1"
                + " demands=\(states.count) ready=\(ready) absent=\(absent)"
                + " pending=\(pending) unavailable=\(unavailable)"
        ]
    }

    private static func less(
        _ lhs: SceneAssetTextureIdentity,
        _ rhs: SceneAssetTextureIdentity
    ) -> Bool {
        lhs.reportToken < rhs.reportToken
    }
}
