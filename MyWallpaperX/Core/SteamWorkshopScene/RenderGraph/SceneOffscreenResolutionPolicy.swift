nonisolated struct SceneFullFrameExtentPolicy: Equatable, Hashable, Sendable {
    enum MaximumDimensionClass: String, Equatable, Hashable, Sendable {
        case standard
        case poolLimit = "pool-limit"
    }

    let maximumDimensionClass: MaximumDimensionClass
    let requiresExactInputExtent: Bool

    static let standard = Self(
        maximumDimensionClass: .standard,
        requiresExactInputExtent: false
    )
}

enum SceneOffscreenResolutionPolicy {
    static let standardMaximumDimension = 2048

    static func maximumDimension(hardLimit: Int, includesAuthoredShader: Bool) -> Int {
        maximumDimension(
            hardLimit: hardLimit,
            policy: .init(
                maximumDimensionClass: includesAuthoredShader
                    ? .poolLimit : .standard,
                requiresExactInputExtent: false
            )
        )
    }

    static func maximumDimension(
        hardLimit: Int,
        policy: SceneFullFrameExtentPolicy
    ) -> Int {
        switch policy.maximumDimensionClass {
        case .standard:
            min(hardLimit, standardMaximumDimension)
        case .poolLimit:
            hardLimit
        }
    }

    static func resolvedDimensions(
        width: Int,
        height: Int,
        hardLimit: Int,
        policy: SceneFullFrameExtentPolicy
    ) -> (Int, Int)? {
        guard width > 0, height > 0, hardLimit > 0 else { return nil }
        let result = limitedDimensions(
            width: width,
            height: height,
            maximumDimension: maximumDimension(
                hardLimit: hardLimit,
                policy: policy
            )
        )
        guard !policy.requiresExactInputExtent
            || (result.0 == width && result.1 == height) else { return nil }
        return result
    }

    static func limitedDimensions(
        width: Int,
        height: Int,
        maximumDimension: Int
    ) -> (Int, Int) {
        let sourceWidth = max(1, width)
        let sourceHeight = max(1, height)
        let longestEdge = max(sourceWidth, sourceHeight)
        let scale = min(1, Double(maximumDimension) / Double(longestEdge))
        return (
            max(1, Int((Double(sourceWidth) * scale).rounded())),
            max(1, Int((Double(sourceHeight) * scale).rounded()))
        )
    }
}
