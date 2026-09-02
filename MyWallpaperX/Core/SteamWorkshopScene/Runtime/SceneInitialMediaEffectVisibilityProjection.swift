import Foundation

/// Exact initial-state projection for the two stock album-cover visibility
/// scripts observed in legal Workshop assets. The system starts without a
/// published thumbnail, so these effects are inactive until a future unified
/// dynamic-topology owner supports their event lifecycle.
nonisolated enum SceneInitialMediaEffectVisibilityProjection {
    struct EffectOwner: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    static func initiallyInactiveOwners(
        scriptBindings: [SceneScriptBindingIR],
        sourceEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> Set<EffectOwner> {
        var owners = Set<EffectOwner>(scriptBindings.compactMap { binding -> EffectOwner? in
            guard binding.owner.kind == .effect,
                  binding.targetKey == "visible",
                  binding.valueType == .boolean,
                  isSupportedVisibilitySource(binding.source),
                  let layerID = binding.owner.objectID,
                  let effectIndex = binding.owner.effectIndex else {
                return nil
            }
            return EffectOwner(layerID: layerID, effectIndex: effectIndex)
        })
        owners.formUnion(sourceEvidence.compactMap { evidence -> EffectOwner? in
            guard evidence.owner.kind == .effect,
                  evidence.targetKey == "visible",
                  evidence.wrapperKeys == ["script", "user", "value"],
                  isSupportedVisibilitySource(evidence.source),
                  let layerID = evidence.owner.objectID,
                  let effectIndex = evidence.owner.effectIndex else {
                return nil
            }
            return EffectOwner(layerID: layerID, effectIndex: effectIndex)
        })
        return owners
    }

    static func apply(
        to descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        sourceEvidence: [SceneScriptSourceEvidenceIR] = []
    ) -> SceneRenderDescriptor {
        let owners = initiallyInactiveOwners(
            scriptBindings: scriptBindings,
            sourceEvidence: sourceEvidence
        )
        guard !owners.isEmpty else { return descriptor }
        var projected = descriptor
        for layerIndex in projected.layers.indices {
            let layerID = projected.layers[layerIndex].id
            for effectIndex in projected.layers[layerIndex].effects.indices
                where owners.contains(.init(layerID: layerID, effectIndex: effectIndex)) {
                projected.layers[layerIndex].effects[effectIndex].visible = false
            }
        }
        return projected
    }

    private static func isSupportedVisibilitySource(_ source: String) -> Bool {
        let compact = source.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"//[^\n\r]*"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        let body = compact.replacingOccurrences(
            of: #"^['\"]usestrict['\"];?"#,
            with: "",
            options: .regularExpression
        ).replacingOccurrences(
            of: #"^exportlet__workshopId=['\"][^'\"]+['\"];?"#,
            with: "",
            options: .regularExpression
        )
        let direct = #"^exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{thisObject\.visible=\1\.hasThumbnail;?\}$"#
        let timed = #"^varlastHideEvent;?exportfunctionmediaThumbnailChanged\(([A-Za-z_$][A-Za-z0-9_$]*)\)\{if\(lastHideEvent\)\{lastHideEvent\(\);lastHideEvent=undefined;?\}thisObject\.visible=\1\.hasThumbnail;if\(\1\.hasThumbnail\)\{lastHideEvent=engine\.setTimeout\(\(\)=>\{thisObject\.visible=false;?\},1000\);?\}\}$"#
        return body.range(of: direct, options: .regularExpression) != nil
            || body.range(of: timed, options: .regularExpression) != nil
    }
}
