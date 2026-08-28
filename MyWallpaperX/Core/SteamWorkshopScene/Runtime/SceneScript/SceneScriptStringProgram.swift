import Foundation

nonisolated struct SceneScriptStringFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
}

/// Generic string-valued SceneScript owners. Current admission is the authored
/// text content wrapper with an actual `update` export; event-only layer
/// mutation scripts remain with their existing bounded owner or fail closed.
nonisolated final class SceneScriptStringProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptStringOwner]
    let generation: UInt64
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []
    private var consumedMediaThumbnailGeneration: UInt64 = 0
    private var consumedMediaPlaybackGeneration: UInt64 = 0
    private var consumedMediaPropertiesGeneration: UInt64 = 0

    static func compile(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptStringProgram {
        guard let domain else {
            return SceneScriptStringProgram(
                bindings: [], authoredValues: [:], generation: generation
            )
        }
        let candidates = scriptBindings.compactMap { binding -> (
            SceneScriptBindingIR, SceneDynamicTarget, String, [String?]
        )? in
            guard let projection = projection(binding, descriptor: descriptor),
                  !excludedTargets.contains(projection.target) else { return nil }
            return (binding, projection.target, projection.authored, projection.effects)
        }
        let counts = Dictionary(grouping: candidates, by: { $0.1 }).mapValues(\.count)
        let owners: [SceneScriptStringOwner] = candidates.compactMap { candidate in
            let (binding, target, _, effects) = candidate
            guard counts[target] == 1 else { return nil }
            return try? SceneScriptStringOwner(
                domain: domain,
                source: binding.source,
                target: target,
                effectNames: effects,
                hasCurrentAnimation: timelineTargets.contains(target),
                generation: generation,
                budget: budget
            )
        }
        let authoredValues = candidates.reduce(
            into: [SceneDynamicTarget: String]()
        ) { values, candidate in
            if values[candidate.1] == nil { values[candidate.1] = candidate.2 }
        }
        return SceneScriptStringProgram(
            bindings: owners,
            authoredValues: authoredValues,
            generation: generation
        )
    }

    private init(
        bindings: [SceneScriptStringOwner],
        authoredValues: [SceneDynamicTarget: String],
        generation: UInt64
    ) {
        self.bindings = bindings
        self.generation = generation
        definitions = bindings.compactMap { owner in
            authoredValues[owner.target].map {
                .init(target: owner.target, valueType: .string, authoredValue: .string($0))
            }
        }
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String = "{}",
        mediaThumbnailEvent: SceneScriptMediaThumbnailEventInput? = nil,
        mediaPlaybackEvent: SceneScriptMediaPlaybackEventInput? = nil,
        mediaPropertiesEvent: SceneScriptMediaPropertiesEventInput? = nil,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptStringFrameResult {
        let thumbnail = pending(
            mediaThumbnailEvent,
            consumed: &consumedMediaThumbnailGeneration
        )
        let playback = pending(
            mediaPlaybackEvent,
            consumed: &consumedMediaPlaybackGeneration
        )
        let properties = pending(
            mediaPropertiesEvent,
            consumed: &consumedMediaPropertiesGeneration
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
        var animations: [SceneTimelinePlaybackMutation] = []
        for binding in bindings {
            guard !disabledTargets.contains(binding.target),
                  let input = inputs[binding.target],
                  case let .string(current) = input else { continue }
            var ownerMaterialFunctions: [SceneScriptMaterialFunctionMutation] = []
            var ownerAnimations: [SceneTimelinePlaybackMutation] = []
            if let playback, !dispatch(
                binding.dispatchMediaPlayback(
                    playback, frame: frame, userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                failures: &failures
            ) { continue }
            if let properties, !dispatch(
                binding.dispatchMediaProperties(
                    properties, frame: frame, userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                failures: &failures
            ) { continue }
            switch binding.evaluate(
                input: current,
                frame: frame,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                ownerMaterialFunctions.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                ownerAnimations.append(contentsOf: evaluation.animationMutations)
                if let thumbnail, !dispatch(
                    binding.dispatchMediaThumbnail(
                        thumbnail, frame: frame,
                        userPropertiesJSON: userPropertiesJSON,
                        interruptBudget: interruptBudget
                    ),
                    binding: binding,
                    materialFunctions: &ownerMaterialFunctions,
                    animations: &ownerAnimations,
                    failures: &failures
                ) { continue }
                values[binding.target] = evaluation.value
                materialFunctions.append(contentsOf: ownerMaterialFunctions)
                animations.append(contentsOf: ownerAnimations)
                if let properties {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaPropertiesChanged generation=%llu titleUTF8Bytes=%d artistUTF8Bytes=%d route=generic-only",
                        String(describing: binding.target), properties.generation,
                        properties.title.utf8.count, properties.artist.utf8.count
                    )
                }
                if reportedTargets.insert(binding.target).inserted,
                   case let .string(output) = evaluation.value {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=completed inputUTF8Bytes=%d outputUTF8Bytes=%d route=generic-only",
                        String(describing: binding.target), current.utf8.count,
                        output.utf8.count
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
            materialFunctionMutations: materialFunctions,
            animationMutations: animations
        )
    }

    func invalidate() { bindings.forEach { $0.invalidate() } }

    private func dispatch(
        _ result: Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure>,
        binding: SceneScriptStringOwner,
        materialFunctions: inout [SceneScriptMaterialFunctionMutation],
        animations: inout [SceneTimelinePlaybackMutation],
        failures: inout [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    ) -> Bool {
        switch result {
        case let .success(mutations):
            materialFunctions.append(contentsOf: mutations.materialFunctions)
            animations.append(contentsOf: mutations.animations)
            return true
        case let .failure(failure):
            failures[binding.target] = failure
            disabledTargets.insert(binding.target)
            return false
        }
    }

    private func pending<Event>(
        _ event: Event?,
        consumed: inout UInt64
    ) -> Event? where Event: SceneScriptGeneratedEvent {
        guard let event, event.generation != consumed else { return nil }
        consumed = event.generation
        return event
    }

    private static func projection(
        _ binding: SceneScriptBindingIR,
        descriptor: SceneRenderDescriptor
    ) -> (target: SceneDynamicTarget, authored: String, effects: [String?])? {
        guard binding.owner.kind == .object,
              binding.properties.isEmpty,
              binding.valueType == .string,
              let objectIndex = binding.owner.objectIndex,
              let layerID = binding.owner.objectID,
              descriptor.layers.indices.contains(objectIndex) else { return nil }
        let layer = descriptor.layers[objectIndex]
        guard layer.id == layerID,
              layer.layerIndex == objectIndex,
              layer.contentKind == "text",
              binding.targetKey == "text",
              binding.targetPath == [
                  .key("objects"), .index(objectIndex), .key("text"),
              ],
              (binding.wrapperKeys == ["script", "value"] ||
                binding.wrapperKeys == ["script", "scriptproperties", "value"]),
              layer.textScript?.source == binding.source,
              case let .string(authored)? = binding.authoredValue,
              layer.text == authored else { return nil }
        return (
            .text(layerID: layerID, field: .content),
            authored,
            layer.effects.map(\.name)
        )
    }
}

private protocol SceneScriptGeneratedEvent {
    var generation: UInt64 { get }
}

extension SceneScriptMediaThumbnailEventInput: SceneScriptGeneratedEvent {}
extension SceneScriptMediaPlaybackEventInput: SceneScriptGeneratedEvent {}
extension SceneScriptMediaPropertiesEventInput: SceneScriptGeneratedEvent {}
