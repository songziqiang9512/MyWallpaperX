#if DEBUG
import Foundation

/// Debug-evidence-only fault state for proving dependency-subgraph containment.
///
/// The request selects a provider by its stable ordinal in the current plan,
/// never by sample, layer, path, asset, or screenshot identity. Each runtime
/// instance drops at most one capture and then permits the next frame to prove
/// recovery through the unchanged product dependency path.
struct SceneDependencyCaptureFault {
    static let environmentKey =
        "MWX_SCENE_DEBUG_DROP_NAMED_PROVIDER_CAPTURE_ONCE"

    private let requestedProviderOrdinal: Int?
    private var droppedProviderLayerID: Int?
    private var recoveredProviderLayerID: Int?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        requestedProviderOrdinal = Self.requestedOrdinal(in: environment)
    }

    static func containsRequest(in environment: [String: String]) -> Bool {
        environment[environmentKey] != nil
    }

    static func requestedOrdinal(in environment: [String: String]) -> Int? {
        guard let rawValue = environment[environmentKey],
              let ordinal = Int(rawValue),
              ordinal > 0 else {
            return nil
        }
        return ordinal
    }

    mutating func shouldDropCapture(
        for providerLayerID: Int,
        orderedProviderLayerIDs: [Int]
    ) -> Bool {
        guard droppedProviderLayerID == nil,
              let requestedProviderOrdinal,
              orderedProviderLayerIDs.indices.contains(
                  requestedProviderOrdinal - 1
              ),
              orderedProviderLayerIDs[requestedProviderOrdinal - 1]
                  == providerLayerID else {
            return false
        }
        droppedProviderLayerID = providerLayerID
        return true
    }

    mutating func observeSuccessfulCapture(for providerLayerID: Int) -> Bool {
        guard droppedProviderLayerID == providerLayerID,
              recoveredProviderLayerID == nil else {
            return false
        }
        recoveredProviderLayerID = providerLayerID
        return true
    }
}
#endif
