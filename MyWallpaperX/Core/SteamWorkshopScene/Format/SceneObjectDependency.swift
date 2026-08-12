import Foundation

nonisolated struct SceneObjectDependency: Codable, Equatable, Sendable {
    let layerID: Int
    let index: Int?
    let type: String?
}

nonisolated struct SceneObjectDependencies: Equatable, Sendable {
    let flatLayerIDs: [Int]
    let authored: [SceneObjectDependency]

    nonisolated init(rawValue: Any?) {
        let values = rawValue as? [Any] ?? []
        flatLayerIDs = values.compactMap { $0 as? Int }
        authored = values.compactMap { value in
            guard let root = value as? [String: Any],
                  let layerID = root["id"] as? Int else { return nil }
            let type = (root["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return SceneObjectDependency(
                layerID: layerID,
                index: root["index"] as? Int,
                type: type.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}
