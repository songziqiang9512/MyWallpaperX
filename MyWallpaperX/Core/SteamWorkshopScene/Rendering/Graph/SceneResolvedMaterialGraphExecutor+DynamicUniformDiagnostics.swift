#if DEBUG
import Foundation

extension SceneResolvedMaterialGraphExecutor {
    func recordPreparedMaterialDiagnostics(
        _ program: SceneResolvedMaterialProgram, node: Graph.Node, nodeIndex: Int,
        frame: SceneResolvedMaterialFrameSnapshot, frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs
    ) {
        recordTypedUserPropertyUniformPublications(
            program: program,
            effect: node.effect,
            nodeIndex: nodeIndex,
            frameInputs: frameInputs
        )
        recordTypedFrameDrivenUniformConsumptions(
            program: program,
            effect: node.effect,
            nodeIndex: nodeIndex,
            frameInputs: frameInputs
        )
        recordTypedAudioSpectrumUniformConsumptions(
            program: program,
            effect: node.effect,
            nodeIndex: nodeIndex,
            frameIndex: frame.frameIndex,
            audioSpectrum: frame.audioSpectrum
        )
        if capturesExecutionDiagnostics, let routeDecision = program.routeDecision {
            SceneGraphExecutionTelemetry.recordGenericShaderExecution(
                state: routeDecision.state,
                profile: routeDecision.profile,
                backend: program.frontendProgram.backend.rawValue,
                graphInputDiagnostics: program.textureSlots.compactMap {
                    $0?.graphInputSourceFact?.diagnosticIdentity
                },
                layerID: node.effect.layerID,
                effectIndex: node.effect.effectIndex,
                descriptorID: node.effect.descriptorID,
                nodeIndex: nodeIndex,
                preparedKey: program.preparedShader.cacheKey
            )
        }
    }

    func recordTypedUserPropertyUniformPublications(
        program: SceneResolvedMaterialProgram,
        effect: Graph.EffectKey,
        nodeIndex: Int,
        frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs
    ) {
        guard capturesExecutionDiagnostics else { return }
        for (binding, uniform) in zip(
            program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms
        ) {
            guard binding.field.arrayCount == nil,
                  case let .dynamic(dynamic) = binding.source,
                  case let .userProperty(propertyKey) = dynamic.contributor,
                  uniform.resolvedSource == .userProperty,
                  dynamic.declaration.scriptAttachments.isEmpty,
                  case let .effectConstant(
                      layerID, effectIndex, passIndex, constant
                  ) = dynamic.declaration.target,
                  layerID == effect.layerID,
                  effectIndex == effect.effectIndex else { continue }
            let target = dynamic.declaration.target
            let values: [Float]
            let type: String
            switch binding.field.type {
            case .float where uniform.encodedValue.count == MemoryLayout<Float>.size:
                values = [uniform.encodedValue.withUnsafeBytes {
                    $0.loadUnaligned(as: Float.self)
                }]
                type = "float"
            case .float2 where uniform.encodedValue.count == 2 * MemoryLayout<Float>.size:
                guard let resolved = frameInputs.dynamicValues[target],
                      resolved.source == .userProperty,
                      case let .scalar(sourceValue) = resolved.value else { continue }
                values = uniform.encodedValue.withUnsafeBytes { bytes in
                    [
                        bytes.loadUnaligned(fromByteOffset: 0, as: Float.self),
                        bytes.loadUnaligned(
                            fromByteOffset: MemoryLayout<Float>.size,
                            as: Float.self
                        ),
                    ]
                }
                guard values[0].bitPattern == values[1].bitPattern,
                      values[0].bitPattern == Float(sourceValue).bitPattern else { continue }
                type = "float2-scalar-splat"
            default:
                continue
            }
            guard values.allSatisfy(\.isFinite) else { continue }
            let stage = binding.field.stage?.rawValue ?? "shared"
            let identity = [
                String(layerID), String(effectIndex), String(passIndex),
                constant, propertyKey, binding.field.name, stage,
                type,
                values.map { String($0.bitPattern) }.joined(separator: ","),
            ].joined(separator: "\u{1f}")
            typedUniformPublicationLock.lock()
            let inserted = typedUniformPublicationIdentities.insert(identity).inserted
            typedUniformPublicationLock.unlock()
            guard inserted else { continue }
            let valueToken = values.map { String(format: "%.9g", $0) }
                .joined(separator: ",")
                NSLog(
                "MWX typed input publication: channel=user-property consumer=material-uniform layer=%d effect=%d descriptor=%@ node=%d property=%@ pass=%d constant=%@ uniform=%@ stage=%@ type=%@ frame=%llu generation=%llu value=%@",
                layerID,
                effectIndex,
                effect.descriptorID,
                nodeIndex,
                propertyKey,
                passIndex,
                constant,
                binding.field.name,
                stage,
                type,
                frameInputs.dynamicValues.frameIndex,
                frameInputs.dynamicValues.generation,
                valueToken
            )
        }
    }

    /// Records a bounded evidence-window join for frame-driven uniforms. The
    /// prepared Program already owns the reflected field and encoded bytes;
    /// this only proves that a typed snapshot value reached that consumer.
    /// Ordinary playback never enters this loop.
    func recordTypedAudioSpectrumUniformConsumptions(
        program: SceneResolvedMaterialProgram,
        effect: Graph.EffectKey,
        nodeIndex: Int,
        frameIndex: UInt64,
        audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs
    ) {
        guard capturesExecutionDiagnostics else { return }
        for (binding, uniform) in zip(
            program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms
        ) {
            let side: String
            let expected: [Float]
            let count: Int
            switch binding.source {
            case let .host(.audioSpectrumLeft(value)):
                side = "left"
                count = value
                expected = switch count {
                case 16: audioSpectrum.left16
                case 32: audioSpectrum.left32
                case 64: audioSpectrum.left64
                default: []
                }
            case let .host(.audioSpectrumRight(value)):
                side = "right"
                count = value
                expected = switch count {
                case 16: audioSpectrum.right16
                case 32: audioSpectrum.right32
                case 64: audioSpectrum.right64
                default: []
                }
            default:
                continue
            }
            guard binding.field.type == .float,
                  binding.field.arrayCount == count,
                  expected.count == count,
                  uniform.encodedValue.count
                    == count * MemoryLayout<Float>.stride else {
                continue
            }
            let encoded: [Float] = uniform.encodedValue.withUnsafeBytes { bytes in
                (0 ..< count).map {
                    bytes.loadUnaligned(
                        fromByteOffset: $0 * MemoryLayout<Float>.stride,
                        as: Float.self
                    )
                }
            }
            guard encoded.count == expected.count,
                  zip(encoded, expected).allSatisfy({
                      $0.bitPattern == $1.bitPattern
                  }),
                  encoded.allSatisfy(\.isFinite) else {
                continue
            }
            let nonZeroCount = encoded.filter { $0 > 0 }.count
            let state = nonZeroCount > 0 ? "nonzero" : "silent"
            let identity = [
                "audio-spectrum", String(effect.layerID),
                String(effect.effectIndex), effect.descriptorID,
                String(nodeIndex), binding.field.name, side,
                String(count), state,
            ].joined(separator: "\u{1f}")
            typedUniformPublicationLock.lock()
            let inserted = typedUniformPublicationIdentities.insert(identity).inserted
            typedUniformPublicationLock.unlock()
            guard inserted else { continue }
            NSLog(
                "MWX typed input consumption: channel=audio-spectrum "
                    + "consumer=material-uniform layer=%d effect=%d "
                    + "descriptor=%@ node=%d uniform=%@ side=%@ count=%d "
                    + "frame=%llu generation=%llu state=%@ nonZero=%d "
                    + "first=%.9g peak=%.9g",
                effect.layerID,
                effect.effectIndex,
                effect.descriptorID,
                nodeIndex,
                binding.field.name,
                side,
                count,
                frameIndex,
                audioSpectrum.generation,
                state,
                nonZeroCount,
                encoded.first ?? 0,
                encoded.max() ?? 0
            )
        }
    }

    func recordTypedFrameDrivenUniformConsumptions(
        program: SceneResolvedMaterialProgram,
        effect: Graph.EffectKey,
        nodeIndex: Int,
        frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs
    ) {
        guard capturesExecutionDiagnostics else { return }
        for (binding, uniform) in zip(
            program.preparedAssembly.preparedUniformBindings, program.resolvedUniforms
        ) {
            guard binding.field.arrayCount == nil,
                  case let .dynamic(dynamic) = binding.source,
                  let resolvedSource = uniform.resolvedSource,
                  dynamic.declaration.scriptAttachments.isEmpty,
                  case let .effectConstant(
                      layerID, effectIndex, passIndex, constant
                  ) = dynamic.declaration.target,
                  layerID == effect.layerID,
                  effectIndex == effect.effectIndex else { continue }

            let target = dynamic.declaration.target
            guard let resolved = frameInputs.dynamicValues[target],
                  resolved.source == resolvedSource else { continue }
            let channel: String
            switch resolvedSource {
            case .timeline:
                channel = "timeline"
            case .sceneScript:
                channel = "scene-script"
            case .authored:
                channel = "authored-fallback"
            case .userProperty:
                // Scalar and scalar-splat publications have their existing reader.
                if case .scalar = resolved.value { continue }
                channel = "user-property"
            }
            guard let expected = SceneResolvedMaterialUniformEncoder.encode(
                      resolved.value,
                      as: binding.field.type
                  ),
                  expected == uniform.encodedValue else {
                continue
            }
            let stage = binding.field.stage?.rawValue ?? "shared"
            let identity = [
                channel, String(layerID), String(effectIndex),
                String(passIndex), constant, binding.field.name, stage,
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
                binding.field.name,
                stage,
                frameInputs.dynamicValues.frameIndex,
                frameInputs.dynamicValues.generation,
                String(describing: resolved.value)
            )
        }
    }
}
#endif
