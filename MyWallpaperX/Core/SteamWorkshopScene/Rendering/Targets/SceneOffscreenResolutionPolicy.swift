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

    static let exactSamplingTexture = Self(
        maximumDimensionClass: .poolLimit,
        requiresExactInputExtent: true
    )
}

/// Prepared source-product contract for the texture extent consumed by an
/// effect graph. The renderer selects one immutable contract from the prepared
/// source product before target planning; individual effects cannot replace it.
nonisolated enum SceneEffectSourceExtentContract: Equatable, Hashable, Sendable {
    /// Ordinary captured products may be proportionally bounded by the normal
    /// working-target limit.
    case scalableStandard
    /// Geometry samples the graph output as its authored texture atlas, so the
    /// graph must preserve that atlas exactly or reject the local graph unit.
    case exactSamplingTexture

    var targetPolicy: SceneFullFrameExtentPolicy {
        switch self {
        case .scalableStandard: .standard
        case .exactSamplingTexture: .exactSamplingTexture
        }
    }
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

    /// 缺口 5b 候选 A：持久效果链工作 extent 的拓扑档规则（纯拓扑级，
    /// 零样本/效果类知识）。链规划入口只承认两档：`.exactSamplingTexture`
    /// 合同层逐字保留原 policy（poolLimit + requiresExactInputExtent 硬拒，
    /// atlas 保真不变）；其余合同层一律落 `.standard`（2048 上限）——裸
    /// poolLimit/hardLimit 不再进入链工作尺寸解析。
    static func chainPlanningPolicy(
        _ policy: SceneFullFrameExtentPolicy
    ) -> SceneFullFrameExtentPolicy {
        policy.requiresExactInputExtent ? policy : .standard
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
