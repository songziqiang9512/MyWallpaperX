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

    /// Ready values are the official 0...12 format enum. -1 is proven absent;
    /// -2 is present but not safely attributable to an authored TEX format.
    var launchFormatFacts: [String: Int] {
        Dictionary(uniqueKeysWithValues: states.map { identity, state in
            let value: Int
            switch state {
            case let .ready(publication):
                guard let format = publication.candidate.authoredFormat else {
                    return (identity.reportToken, -2)
                }
                value = format.macroValue
            case .absent:
                value = -1
            case .pending, .unavailable:
                value = -2
            }
            return (identity.reportToken, value)
        })
    }

    private nonisolated static func less(
        _ lhs: SceneAssetTextureIdentity,
        _ rhs: SceneAssetTextureIdentity
    ) -> Bool {
        lhs.reportToken < rhs.reportToken
    }
}
