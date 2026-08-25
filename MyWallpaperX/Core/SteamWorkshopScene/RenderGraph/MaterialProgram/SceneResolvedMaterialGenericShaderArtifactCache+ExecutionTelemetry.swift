import Foundation

extension SceneResolvedMaterialGenericShaderArtifactCache {
    static func recordExecution(
        routeDecision: RouteDecision?,
        backend: SceneAuthoredShaderProgram.Backend,
        graphInputDiagnostics: [String],
        layerID: Int,
        effectIndex: Int,
        descriptorID: String,
        nodeIndex: Int,
        preparedKey: String
    ) {
        guard let routeDecision else { return }
        routeTelemetry.recordExecution(
            routeDecision: routeDecision,
            backend: backend,
            graphInputDiagnostics: graphInputDiagnostics,
            layerID: layerID,
            effectIndex: effectIndex,
            descriptorID: descriptorID,
            nodeIndex: nodeIndex,
            preparedKey: preparedKey
        )
    }
}
