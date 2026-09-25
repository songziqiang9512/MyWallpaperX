import simd

nonisolated enum SceneLayerParallax {
    nonisolated struct Node: Equatable, Sendable {
        let id: Int
        let parentID: Int?
        let depth: SIMD2<Float>
        let propagatesToChildren: Bool
    }

    nonisolated struct Resolution: Equatable, Sendable {
        let sourceLayerID: Int
        let depth: SIMD2<Float>
    }

    nonisolated struct Configuration: Equatable, Sendable {
        let enabled: Bool
        let amount: Float
        let mouseInfluence: Float
        let orthoSize: SIMD2<Float>
        let worldYDown: Bool
    }

    nonisolated static func resolveAll(
        layersByID: [Int: SceneRenderDescriptor.Layer]
    ) -> [Int: Resolution] {
        let nodesByID = layersByID.mapValues { layer in
            Node(
                id: layer.id, parentID: layer.parentID,
                depth: SIMD2(layer.parallaxDepthXY ?? [], fill: 0),
                propagatesToChildren: !layer.disablesParallaxPropagation
            )
        }
        return Dictionary(uniqueKeysWithValues: layersByID.keys.compactMap { id in
            resolve(layerID: id, nodesByID: nodesByID).map { (id, $0) }
        })
    }

    nonisolated static func resolve(
        layerID: Int,
        nodesByID: [Int: Node]
    ) -> Resolution? {
        guard let layer = nodesByID[layerID] else { return nil }
        var resolved = layer
        var parentID = layer.parentID
        var visited = Set([layer.id])

        while let candidateID = parentID, visited.insert(candidateID).inserted,
              let candidate = nodesByID[candidateID] {
            guard candidate.propagatesToChildren else { break }
            resolved = candidate
            parentID = candidate.parentID
        }
        return Resolution(sourceLayerID: resolved.id, depth: resolved.depth)
    }

    nonisolated static func offset(
        resolution: Resolution?,
        configuration: Configuration,
        mouseNormalized: SIMD2<Float>
    ) -> SIMD2<Float> {
        guard configuration.enabled, let resolution,
              configuration.orthoSize.x > 0, configuration.orthoSize.y > 0,
              resolution.depth != .zero else { return .zero }
        let halfSize = configuration.orthoSize * 0.5
        // Camera parallax is a rest-centered effect: the authored layout is
        // unchanged while the pointer sits at the center, and each layer
        // drifts opposite the pointer scaled by depth and the scene amounts.
        // The previous `(layerPosition - cameraPosition)` term displaced
        // off-center layers even at rest and, through the script-driven
        // dynamic camera origin, amplified pointer input into a ~120px sway
        // on 3750813609 (measured 2026-09-25). Surface/NDC Y points up; the
        // 2D world-frame translations below point down. Convert at this
        // consumer, not in the shared pointer.
        let mouseInWorldAxes = SIMD2(
            mouseNormalized.x,
            configuration.worldYDown ? -mouseNormalized.y : mouseNormalized.y
        )
        let shift = -mouseInWorldAxes
            * halfSize * configuration.mouseInfluence
            * resolution.depth * configuration.amount
        guard shift.x.isFinite, shift.y.isFinite else { return .zero }
        return shift
    }
}

nonisolated struct SceneParallaxPointerSmoother: Sendable {
    nonisolated struct State: Equatable, Sendable {
        fileprivate let current: SIMD2<Float>
        fileprivate let target: SIMD2<Float>
        fileprivate let delayedTime: Double
        fileprivate let lastInputTimestamp: Double?

        fileprivate init(
            current: SIMD2<Float>, target: SIMD2<Float>, delayedTime: Double,
            lastInputTimestamp: Double?
        ) {
            self.current = current
            self.target = target
            self.delayedTime = delayedTime
            self.lastInputTimestamp = lastInputTimestamp
        }
    }

    private var current = SIMD2<Float>.zero
    private var target = SIMD2<Float>.zero
    private var delayedTime = 0.0
    private var lastInputTimestamp: Double?

    nonisolated func snapshot() -> State {
        State(
            current: current,
            target: target,
            delayedTime: delayedTime,
            lastInputTimestamp: lastInputTimestamp
        )
    }

    nonisolated mutating func restore(_ state: State) {
        current = state.current
        target = state.target
        delayedTime = state.delayedTime
        lastInputTimestamp = state.lastInputTimestamp
    }

    nonisolated mutating func setTarget(_ value: SIMD2<Float>, timestamp: Double) {
        if let lastInputTimestamp, timestamp.isFinite {
            delayedTime = max(0, delayedTime - max(0, timestamp - lastInputTimestamp))
        }
        target = value
        lastInputTimestamp = timestamp.isFinite ? timestamp : lastInputTimestamp
    }

    nonisolated mutating func advance(
        delta: Double,
        delay authoredDelay: Float
    ) -> SIMD2<Float> {
        let delay = max(0, Double(
            authoredDelay.isFinite ? authoredDelay : 0
        ))
        guard delay > 0 else {
            current = target
            return current
        }
        delayedTime = min(delay, delayedTime + max(0, delta.isFinite ? delta : 0))
        let amount = Float(delayedTime / delay)
        current += (target - current) * amount
        return current
    }
}
