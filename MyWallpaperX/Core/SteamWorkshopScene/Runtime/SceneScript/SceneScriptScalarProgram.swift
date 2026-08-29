import Foundation

nonisolated struct SceneScriptScalarFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

/// Generic pass-constant SceneScript owners. The program is deliberately
/// source/identity based rather than effect-name based; runtime failure keeps
/// the lower-priority authored/property/Timeline value for the affected owner.
nonisolated final class SceneScriptScalarProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptScalarOwner]
    let domain: SceneScriptQuickJSDomain?
    let generation: UInt64
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []
    private var reportedAudioTargets: Set<SceneDynamicTarget> = []
    private var consumedMediaThumbnailGeneration: UInt64 = 0
    private var consumedMediaPlaybackGeneration: UInt64 = 0

    var hasAudioConsumers: Bool {
        bindings.contains(where: \.hasAudioRegistration)
    }

    private init(
        domain: SceneScriptQuickJSDomain?,
        bindings: [SceneScriptScalarOwner],
        generation: UInt64
    ) {
        self.domain = domain
        self.bindings = bindings
        self.generation = generation
        definitions = bindings.map {
            .init(
                target: $0.target,
                valueType: .scalar,
                authoredValue: .scalar($0.authoredValue)
            )
        }
    }

    static func compile(
        domain sharedDomain: SceneScriptQuickJSDomain? = nil,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64 = 1,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptScalarProgram {
        let domain: SceneScriptQuickJSDomain
        if let sharedDomain {
            domain = sharedDomain
        } else if let created = try? SceneScriptQuickJSDomain(budget: budget) {
            domain = created
        } else {
            return empty(budget: budget, generation: generation)
        }
        let candidates: [(SceneScriptBindingIR, SceneDynamicTarget, Double, String)] =
            scriptBindings.compactMap { binding in
                guard let target = projection(
                          binding,
                          descriptor: descriptor,
                          timelineTargets: timelineTargets
                      ),
                      !excludedTargets.contains(target),
                      let authored = binding.authoredValue?.numberValue,
                      let propertiesJSON = staticPropertiesJSON(binding.properties),
                      authored.isFinite else { return nil }
                return (binding, target, authored, propertiesJSON)
            }
        let counts = Dictionary(grouping: candidates, by: { $0.1 })
            .mapValues(\.count)
        var owners: [SceneScriptScalarOwner] = []
        for (binding, target, authored, propertiesJSON) in candidates {
            let layerID: Int
            switch target {
            case let .effectConstant(value, _, _, _), let .layer(value, _),
                 let .particle(value, _):
                layerID = value
            default:
                continue
            }
            guard counts[target] == 1,
                  let layer = descriptor.layers.first(where: { $0.id == layerID }),
                  let owner = try? SceneScriptScalarOwner(
                      domain: domain,
                      source: binding.source,
                      target: target,
                      authoredValue: authored,
                      scriptPropertiesJSON: propertiesJSON,
                      effectNames: layer.effects.map(\.name),
                      hasCurrentAnimation: timelineTargets.contains(target),
                      generation: generation,
                      budget: budget
                  ) else { continue }
            owners.append(owner)
        }
        return SceneScriptScalarProgram(
            domain: domain,
            bindings: owners,
            generation: generation
        )
    }

    static func projectedTargets(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        let targets = scriptBindings.compactMap { binding -> SceneDynamicTarget? in
            guard staticPropertiesJSON(binding.properties) != nil else { return nil }
            return projection(
                binding,
                descriptor: descriptor,
                timelineTargets: timelineTargets
            )
        }
        let counts = Dictionary(grouping: targets, by: { $0 }).mapValues(\.count)
        return Set(targets.filter { counts[$0] == 1 })
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String = "{}",
        mediaThumbnailEvent: SceneScriptMediaThumbnailEventInput? = nil,
        mediaPlaybackEvent: SceneScriptMediaPlaybackEventInput? = nil,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptScalarFrameResult {
        var pendingMediaEvent: SceneScriptMediaThumbnailEventInput?
        if let event = mediaThumbnailEvent,
           event.generation != consumedMediaThumbnailGeneration {
            consumedMediaThumbnailGeneration = event.generation
            pendingMediaEvent = event
        } else {
            pendingMediaEvent = nil
        }
        var pendingPlaybackEvent: SceneScriptMediaPlaybackEventInput?
        if let event = mediaPlaybackEvent,
           event.generation != consumedMediaPlaybackGeneration {
            consumedMediaPlaybackGeneration = event.generation
            pendingPlaybackEvent = event
        } else {
            pendingPlaybackEvent = nil
        }
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        for binding in bindings {
            guard !disabledTargets.contains(binding.target) else { continue }
            guard let input = inputs[binding.target],
                  case let .scalar(value) = input else { continue }
            if binding.hasAudioRegistration {
                switch binding.refreshAudio(audioSpectrum) {
                case .success:
                    if audioSpectrum.generation > 0, !audioSpectrum.isSilent,
                       reportedAudioTargets.insert(binding.target).inserted {
                        let peak = [
                            audioSpectrum.left.max() ?? 0,
                            audioSpectrum.right.max() ?? 0,
                            audioSpectrum.left32.max() ?? 0,
                            audioSpectrum.right32.max() ?? 0,
                            audioSpectrum.left64.max() ?? 0,
                            audioSpectrum.right64.max() ?? 0,
                        ].max() ?? 0
                        NSLog(
                            "MWX SceneScript VM: target=%@ callback=audioBuffersUpdated generation=%llu peak=%.9g route=generic-only",
                            String(describing: binding.target),
                            audioSpectrum.generation,
                            peak
                        )
                    }
                case let .failure(failure):
                    failures[binding.target] = failure
                    disabledTargets.insert(binding.target)
                    continue
                }
            }
            var callbackMaterialMutations: [SceneScriptMaterialFunctionMutation] = []
            var callbackAnimationMutations: [SceneTimelinePlaybackMutation] = []
            var callbackLayerMutations: [SceneScriptLayerMutation] = []
            var playbackMutationCount = 0
            if let pendingPlaybackEvent {
                switch binding.dispatchMediaPlayback(
                    pendingPlaybackEvent,
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ) {
                case let .success(eventMutations):
                    playbackMutationCount = eventMutations.materialFunctions.count
                        + eventMutations.animations.count
                    callbackMaterialMutations.append(
                        contentsOf: eventMutations.materialFunctions
                    )
                    callbackAnimationMutations.append(
                        contentsOf: eventMutations.animations
                    )
                    callbackLayerMutations.append(contentsOf: eventMutations.layers)
                case let .failure(failure):
                    failures[binding.target] = failure
                    disabledTargets.insert(binding.target)
                    continue
                }
            }
            switch binding.evaluate(
                input: value,
                frame: frame,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                callbackMaterialMutations.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                callbackAnimationMutations.append(
                    contentsOf: evaluation.animationMutations
                )
                callbackLayerMutations.append(contentsOf: evaluation.layerMutations)
                var thumbnailMutationCount = 0
                if let pendingMediaEvent {
                    switch binding.dispatchMediaThumbnail(
                        pendingMediaEvent,
                        frame: frame,
                        userPropertiesJSON: userPropertiesJSON,
                        interruptBudget: interruptBudget
                    ) {
                    case let .success(eventMutations):
                        thumbnailMutationCount = eventMutations.materialFunctions.count
                            + eventMutations.animations.count
                        callbackMaterialMutations.append(
                            contentsOf: eventMutations.materialFunctions
                        )
                        callbackAnimationMutations.append(
                            contentsOf: eventMutations.animations
                        )
                        callbackLayerMutations.append(contentsOf: eventMutations.layers)
                    case let .failure(failure):
                        failures[binding.target] = failure
                        disabledTargets.insert(binding.target)
                        continue
                    }
                }
                values[binding.target] = evaluation.value
                materialFunctionMutations.append(contentsOf: callbackMaterialMutations)
                animationMutations.append(contentsOf: callbackAnimationMutations)
                layerMutations.append(contentsOf: callbackLayerMutations)
                if pendingMediaEvent != nil {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaThumbnailChanged generation=%llu hasThumbnail=%@ mutations=%d route=generic-only",
                        String(describing: binding.target),
                        pendingMediaEvent?.generation ?? 0,
                        pendingMediaEvent?.hasThumbnail == true ? "true" : "false",
                        thumbnailMutationCount
                    )
                }
                if pendingPlaybackEvent != nil {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaPlaybackChanged generation=%llu state=%d mutations=%d route=generic-only",
                        String(describing: binding.target),
                        pendingPlaybackEvent?.generation ?? 0,
                        pendingPlaybackEvent?.state ?? -1,
                        playbackMutationCount
                    )
                }
                if reportedTargets.insert(binding.target).inserted,
                   case let .scalar(inputValue) = input,
                   case let .scalar(outputValue) = evaluation.value {
                    let mutationSummary = evaluation.materialFunctionMutations.map {
                        "\($0.effectIndex):\($0.functionName)"
                    }.joined(separator: ",")
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=completed input=%.9g output=%.9g mutations=%d mutationTargets=%@ route=generic-only",
                        String(describing: binding.target),
                        inputValue,
                        outputValue,
                        evaluation.materialFunctionMutations.count,
                        mutationSummary
                    )
                }
            case let .failure(failure):
                failures[binding.target] = failure
                disabledTargets.insert(binding.target)
            }
        }
        return .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctionMutations,
            animationMutations: animationMutations,
            layerMutations: layerMutations
        )
    }

    func invalidate() {
        bindings.forEach { $0.invalidate() }
    }

    private static func empty(
        budget: SceneScriptScalarBudget,
        generation: UInt64
    ) -> SceneScriptScalarProgram {
        // A domain should only fail construction for a machine-level resource
        // error. Keep the failure local and preserve bounded fallbacks.
        return .init(domain: nil, bindings: [], generation: generation)
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor,
        timelineTargets: Set<SceneDynamicTarget>
    ) -> SceneDynamicTarget? {
        guard binding.valueType == .number,
              let authored = binding.authoredValue?.numberValue,
              authored.isFinite,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex),
              descriptor.layers[objectIndex].id == layerID,
              descriptor.layers[objectIndex].layerIndex == objectIndex else {
            return nil
        }
        if binding.owner.kind == .object {
            if binding.targetPath == [
                .key("objects"), .index(objectIndex),
                .key("instanceoverride"), .key("rate"),
            ] {
                let layer = descriptor.layers[objectIndex]
                guard binding.targetKey == "rate",
                      binding.wrapperKeys == ["script", "scriptproperties", "value"],
                      layer.contentKind == "particle",
                      let override = layer.particleInstanceOverride,
                      override.hasOnlyGenericRateScript,
                      let rate = override.rate,
                      rate.userPropertyKey == nil,
                      !rate.hasAnimation,
                      rate.value?.scalarValue?.bitPattern == authored.bitPattern else {
                    return nil
                }
                return .particle(layerID: layerID, field: .rate)
            }
            let target = SceneDynamicTarget.layer(layerID: layerID, field: .alpha)
            guard binding.properties.isEmpty,
                  binding.targetKey == "alpha",
                  binding.wrapperKeys == ["animation", "script", "value"],
                  binding.targetPath == [
                      .key("objects"), .index(objectIndex), .key("alpha"),
                  ],
                  descriptor.layers[objectIndex].alpha?.bitPattern == authored.bitPattern,
                  timelineTargets.contains(target)
            else { return nil }
            return target
        }
        guard binding.properties.isEmpty,
              binding.owner.kind == .pass,
              let effectIndex = binding.owner.effectIndex,
              let passIndex = binding.owner.passIndex,
              descriptor.layers[objectIndex].effects.indices.contains(effectIndex) else {
            return nil
        }
        let effect = descriptor.layers[objectIndex].effects[effectIndex]
        guard effect.effectID == binding.owner.effectID,
              effect.passes.indices.contains(passIndex) else { return nil }
        let pass = effect.passes[passIndex]
        let name = binding.targetKey
        guard pass.passIndex == passIndex,
              pass.id == binding.owner.passID,
              !name.isEmpty,
              binding.targetPath == expectedPath(
                  objectIndex: objectIndex,
                  effectIndex: effectIndex,
                  passIndex: passIndex,
                  name: name
              ),
              let value = pass.constantShaderValues[name],
              value.scriptSource == binding.source,
              value.components?.count == 1,
              value.components?.first?.bitPattern == authored.bitPattern else {
            return nil
        }
        return .effectConstant(
            layerID: layerID,
            effectIndex: effectIndex,
            passIndex: passIndex,
            name: name
        )
    }

    private static func expectedPath(
        objectIndex: Int,
        effectIndex: Int,
        passIndex: Int,
        name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }

    private static func staticPropertiesJSON(
        _ properties: [String: SceneJSONValue]
    ) -> String? {
        if properties.isEmpty { return "" }
        var object: [String: Any] = [:]
        for (key, value) in properties {
            switch value {
            case let .bool(item): object[key] = item
            case let .number(item) where item.isFinite: object[key] = item
            case let .string(item): object[key] = item
            default: return nil
            }
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private nonisolated extension SceneParticleInstanceOverride {
    var hasOnlyGenericRateScript: Bool {
        guard rate?.hasScript == true else { return false }
        let otherValues = [
            alpha, size, lifetime, speed, count, brightness,
            color, normalizedColor,
        ]
        return !otherValues.compactMap { $0 }.contains(where: \.hasScript)
            && !controlPoints.values.contains(where: \.hasScript)
            && !controlPointAngles.values.contains(where: \.hasScript)
    }
}
