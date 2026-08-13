import Foundation

extension SceneGraphRenderTargetPlan {
    nonisolated static func zeroClear(_ clear: SceneJSONValue) -> ClearColor? {
        let components: [Double]
        switch clear {
        case .string(let value):
            let parts = value.split(whereSeparator: { $0.isWhitespace })
            components = parts.compactMap { Double($0) }
            guard components.count == parts.count else { return nil }
        case .array(let values):
            components = values.compactMap(\.numberValue)
            guard components.count == values.count else { return nil }
        default:
            return nil
        }
        guard components.count == 4,
              components.allSatisfy({ $0.isFinite && $0 == 0 }) else {
            return nil
        }
        return ClearColor(
            red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components[3]
        )
    }
}
