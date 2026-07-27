enum SceneOffscreenResolutionPolicy {
    static func maximumDimension(hardLimit: Int, includesAuthoredShader: Bool) -> Int {
        includesAuthoredShader ? hardLimit : min(hardLimit, 2048)
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
