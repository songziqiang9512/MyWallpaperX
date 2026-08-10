import Foundation

nonisolated enum SceneResolvedMaterialExecutionCapabilityEnvelopeDiagnostics {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Failure = SceneResolvedMaterialVariantCache.LaunchEnvelopeFailure

    static func launchEnvelopeFailure(
        template: SceneResolvedMaterialTemplate,
        failure: Failure
    ) {
#if DEBUG
        let reason: String
        switch failure {
        case .capacity:
            reason = "capacity"
        case let .material(material):
            reason = "\(material.phase.rawValue)/\(material.code.rawValue)"
                + " slot=\(material.slot.map(String.init) ?? "none")"
                + " details=\(material.boundedDetails.joined(separator: ","))"
        }
        print(
            "MWX resolved material envelope rejection:"
                + " shader=\(template.diagnosticProvenance.authoredShaderPath)"
                + " node=\(template.diagnosticProvenance.nodeIndex)"
                + " kind=\(failure.kind.rawValue) reason=\(reason)"
        )
#endif
    }

    static func materialTemplateFailure(
        node: Graph.Node,
        reason: String,
        failure: SceneResolvedMaterialFailure? = nil
    ) {
#if DEBUG
        let failureText = failure.map {
            " phase=\($0.phase.rawValue) code=\($0.code.rawValue)"
                + " details=\($0.boundedDetails.joined(separator: ","))"
        } ?? ""
        print(
            "MWX resolved material template rejection:"
                + " material=\(node.materialPath ?? "none")"
                + " node=\(node.nodeIndex) reason=\(reason)"
                + failureText
        )
#endif
    }

    static func variantSchemaFailure(template: SceneResolvedMaterialTemplate) {
#if DEBUG
        let samplerResult = Result {
            try SceneResolvedMaterialShaderSchema.unconditionalSamplers(template)
        }
        let formatResult = Result {
            try SceneResolvedMaterialTextureResolver.launchTextureFormatSlots(
                template: template
            )
        }
        print(
            "MWX resolved material variant schema rejection:"
                + " shader=\(template.diagnosticProvenance.authoredShaderPath)"
                + " node=\(template.diagnosticProvenance.nodeIndex)"
                + " sampler=\(failureDescription(samplerResult))"
                + " format=\(failureDescription(formatResult))"
        )
#endif
    }

#if DEBUG
    private static func failureDescription<Success, Failure: Error>(
        _ result: Result<Success, Failure>
    ) -> String {
        switch result {
        case .success: "accepted"
        case .failure(let error): String(describing: error)
        }
    }
#endif
}
