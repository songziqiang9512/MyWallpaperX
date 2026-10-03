import Foundation
import Metal

struct SceneVFSAssetPath: Hashable { let value: String }
enum SceneTextureLoadPurpose: String, Hashable {
    case mask, flow
    var reportToken: String { rawValue }
}
struct SceneAssetTextureIdentity: Hashable {
    let path: SceneVFSAssetPath
    let purpose: SceneTextureLoadPurpose
    var reportToken: String { "\(path.value):\(purpose.rawValue)" }
}
enum SceneFrameTextureIdentity: Equatable { case asset(SceneAssetTextureIdentity) }
enum SceneShaderTextureFormat: UInt32 {
    case rgba8888 = 0
    var macroValue: Int { Int(rawValue) }
}
enum SceneTextureContent: Hashable { case data }
struct SceneTextureCandidate {
    let purpose: SceneTextureLoadPurpose
    let complete: Bool
    let authoredFormat: SceneShaderTextureFormat?
    let content: SceneTextureContent = .data
}
struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let contentGeneration: UInt64
    var isComplete: Bool { candidate.complete }
}
enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication), absent, pending, unavailable
}
enum SceneAssetTextureLaunchState: Hashable {
    case ready(SceneTextureContent), absent, pending, unavailable
}
struct SceneRenderDescriptor {}
struct SceneResourceView { let urls: [String: URL] }
struct SceneTexturePathResolver {
    let resourceView: SceneResourceView
    init(resourceView: SceneResourceView, descriptor: SceneRenderDescriptor) {
        self.resourceView = resourceView
    }
    func resolveTextureFile(named name: String) -> URL? { resourceView.urls[name] }
}
enum SceneTextureCandidateLoadOutcome {
    case loaded(SceneTextureCandidate), failed(Int)
}
final class SceneTextureLoader {
    func loadCandidate(
        from url: URL,
        purpose: SceneTextureLoadPurpose,
        device: MTLDevice
    ) -> SceneTextureCandidateLoadOutcome {
        if url.lastPathComponent == "bad" { return .failed(1) }
        return .loaded(.init(
            purpose: purpose,
            complete: url.lastPathComponent != "incomplete",
            authoredFormat: .rgba8888
        ))
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        func identity(_ path: String, _ purpose: SceneTextureLoadPurpose) -> SceneAssetTextureIdentity {
            .init(path: .init(value: path), purpose: purpose)
        }
        let goodMask = identity("good", .mask)
        let goodFlow = identity("good", .flow)
        let missing = identity("missing", .mask)
        let bad = identity("bad", .mask)
        let incomplete = identity("incomplete", .mask)
        let catalog = SceneMaterialAssetTextureCatalog(
            demands: [goodMask, goodFlow, missing, bad, incomplete],
            resourceView: .init(urls: [
                "good": URL(fileURLWithPath: "/tmp/good"),
                "bad": URL(fileURLWithPath: "/tmp/bad"),
                "incomplete": URL(fileURLWithPath: "/tmp/incomplete"),
            ]),
            descriptor: .init(),
            device: device
        )
        func disposition(_ identity: SceneAssetTextureIdentity) -> String {
            switch catalog.states[identity] {
            case let .ready(publication):
                return publication.requestIdentity == .asset(identity)
                    && publication.candidate.purpose == identity.purpose
                    && publication.contentGeneration == 1 ? "ready" : "invalid"
            case .absent: return "absent"
            case .pending: return "pending"
            case .unavailable: return "unavailable"
            case nil: return "missing-state"
            }
        }
        let output: [String: Any] = [
            "available": true,
            "goodMask": disposition(goodMask),
            "goodFlow": disposition(goodFlow),
            "missing": disposition(missing),
            "bad": disposition(bad),
            "incomplete": disposition(incomplete),
            "stateCount": catalog.states.count,
            "report": catalog.reportLines.joined(separator: "\n"),
            "goodMaskFormat": catalog.launchFormatFacts[goodMask.reportToken] ?? -999,
            "missingFormat": catalog.launchFormatFacts[missing.reportToken] ?? -999,
            "badFormat": catalog.launchFormatFacts[bad.reportToken] ?? -999,
            "goodMaskLaunch": launchDisposition(catalog.launchStates[goodMask]),
            "missingLaunch": launchDisposition(catalog.launchStates[missing]),
            "badLaunch": launchDisposition(catalog.launchStates[bad]),
            "incompleteLaunch": launchDisposition(catalog.launchStates[incomplete]),
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func launchDisposition(
        _ state: SceneAssetTextureLaunchState?
    ) -> String {
        switch state {
        case .ready(.data): return "ready-data"
        case .absent: return "absent"
        case .pending: return "pending"
        case .unavailable: return "unavailable"
        case nil: return "missing-state"
        }
    }
}
