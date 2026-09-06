import Foundation

extension SceneResolvedMaterialGraphExecutor {
    /// Records a bounded evidence-window join for frame-driven uniforms. The
    /// prepared Program already owns the reflected field and encoded bytes;
    /// this only proves that a Timeline or SceneScript snapshot value reached
    /// that existing consumer. Ordinary playback never enters this loop.
    func recordTypedFrameDrivenUniformConsumptions(
        program: SceneResolvedMaterialProgram,
        effect: Graph.EffectKey,
        nodeIndex: Int,
        frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs
    ) {
        guard capturesExecutionDiagnostics else { return }
        for uniform in program.resolvedUniforms {
            guard uniform.field.arrayCount == nil,
                  case let .dynamic(
                      declared: declared,
                      target: target,
                      resolvedSource: resolvedSource,
                      scriptAttachments: attachments
                  ) = uniform.source,
                  attachments.isEmpty,
                  case let .effectConstant(
                      layerID, effectIndex, passIndex, constant
                  ) = target,
                  layerID == effect.layerID,
                  effectIndex == effect.effectIndex else { continue }

            let channel: String
            switch (declared, resolvedSource) {
            case (.timeline, .timeline):
                channel = "timeline"
            case (.sceneScript, .sceneScript):
                channel = "scene-script"
            default:
                continue
            }
            guard let resolved = frameInputs.dynamicValues[target],
                  resolved.source == resolvedSource,
                  let expected = SceneResolvedMaterialUniformEncoder.encode(
                      resolved.value,
                      as: uniform.field.type
                  ),
                  expected == uniform.encodedValue else {
                continue
            }
            let stage = uniform.field.stage?.rawValue ?? "shared"
            let identity = [
                channel, String(layerID), String(effectIndex),
                String(passIndex), constant, uniform.field.name, stage,
                String(frameInputs.dynamicValues.generation),
            ].joined(separator: "\u{1f}")
            typedUniformPublicationLock.lock()
            let inserted = typedUniformPublicationIdentities.insert(identity).inserted
            typedUniformPublicationLock.unlock()
            guard inserted else { continue }
            NSLog(
                "MWX typed input consumption: channel=%@ "
                    + "consumer=material-uniform layer=%d effect=%d "
                    + "descriptor=%@ node=%d source=%@ pass=%d constant=%@ "
                    + "uniform=%@ stage=%@ frame=%llu generation=%llu value=%@",
                channel,
                layerID,
                effectIndex,
                effect.descriptorID,
                nodeIndex,
                channel,
                passIndex,
                constant,
                uniform.field.name,
                stage,
                frameInputs.dynamicValues.frameIndex,
                frameInputs.dynamicValues.generation,
                String(describing: resolved.value)
            )
        }
    }
}
