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
        let cameraPosition: SIMD2<Float>
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
        layerPosition: SIMD2<Float>,
        mouseNormalized: SIMD2<Float>
    ) -> SIMD2<Float> {
        guard configuration.enabled, let resolution,
              configuration.orthoSize.x > 0, configuration.orthoSize.y > 0,
              resolution.depth != .zero else { return .zero }
        let halfSize = configuration.orthoSize * 0.5
        let mouseOffset = -mouseNormalized * halfSize * configuration.mouseInfluence
        let shift = (layerPosition - configuration.cameraPosition + mouseOffset)
            * resolution.depth * configuration.amount
        guard shift.x.isFinite, shift.y.isFinite else { return .zero }
        return shift
    }
}

nonisolated struct SceneParallaxPointerSmoother: Sendable {
    private let delay: Double
    private var current = SIMD2<Float>.zero
    private var target = SIMD2<Float>.zero
    private var delayedTime = 0.0
    private var lastInputTimestamp: Double?

    nonisolated init(delay: Float) {
        self.delay = max(0, Double(delay))
    }

    nonisolated mutating func setTarget(_ value: SIMD2<Float>, timestamp: Double) {
        if let lastInputTimestamp, timestamp.isFinite {
            delayedTime = max(0, delayedTime - max(0, timestamp - lastInputTimestamp))
        }
        target = value
        lastInputTimestamp = timestamp.isFinite ? timestamp : lastInputTimestamp
    }

    nonisolated mutating func advance(delta: Double) -> SIMD2<Float> {
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
