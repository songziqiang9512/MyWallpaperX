import Foundation

nonisolated struct SceneScriptStringFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

nonisolated struct SceneScriptStringProgramConstruction: @unchecked Sendable {
    let program: SceneScriptStringProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}

/// Generic string-valued SceneScript owners. Current admission is the authored
/// text content wrapper with an actual `update` export; event-only layer
/// mutation scripts remain with their existing bounded owner or fail closed.
nonisolated final class SceneScriptStringProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptStringOwner]
    let generation: UInt64
    private let authoredOrdinals: [SceneDynamicTarget: Int]
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []
    private var observedMediaThumbnailEvent =
        SceneScriptObservedEvent<SceneScriptMediaThumbnailEventInput>()
    private var observedMediaPlaybackEvent =
        SceneScriptObservedEvent<SceneScriptMediaPlaybackEventInput>()
    private var observedMediaPropertiesEvent =
        SceneScriptObservedEvent<SceneScriptMediaPropertiesEventInput>()
    private var observedMediaTimelineEvent =
        SceneScriptObservedEvent<SceneScriptMediaTimelineEventInput>()
    private var consumedMediaThumbnailGenerations: [SceneDynamicTarget: UInt64] = [:]
    private var consumedMediaPlaybackGenerations: [SceneDynamicTarget: UInt64] = [:]
    private var consumedMediaPropertiesGenerations: [SceneDynamicTarget: UInt64] = [:]
    private var consumedMediaTimelineGenerations: [SceneDynamicTarget: UInt64] = [:]

    var hasAudioConsumers: Bool {
        bindings.contains(where: \.hasAudioRegistration)
    }

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
        return compileCandidate(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets,
            excludedTargets: excludedTargets,
            rejectedTargets: [],
            generation: generation,
            budget: budget
        ).program
    }

    static func compileCandidate(
        domain: SceneScriptQuickJSDomain,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        rejectedTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptStringProgramConstruction {
        let candidates = scriptBindings.enumerated().compactMap {
            authoredOrdinal, binding -> (
            Int, SceneScriptBindingIR, SceneDynamicTarget, String, [String?]
        )? in
            guard let projection = projection(binding, descriptor: descriptor),
                  !excludedTargets.contains(projection.target) else { return nil }
            return (
                authoredOrdinal, binding, projection.target,
                projection.authored, projection.effects
            )
        }
        let counts = Dictionary(grouping: candidates, by: { $0.2 }).mapValues(\.count)
        let requestedTargets = Set(candidates.compactMap { candidate in
            counts[candidate.2] == 1 ? candidate.2 : nil
        }).subtracting(rejectedTargets)
        var owners: [SceneScriptStringOwner] = []
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        for candidate in candidates {
            let (_, binding, target, _, effects) = candidate
            guard requestedTargets.contains(target) else { continue }
            do {
                owners.append(try SceneScriptStringOwner(
                    domain: domain,
                    source: binding.source,
                    target: target,
                    effectNames: effects,
                    hasCurrentAnimation: timelineTargets.contains(target),
                    generation: generation,
                    budget: budget
                ))
            } catch let failure as SceneScriptScalarRuntimeFailure {
                failures[target] = failure
                break
            } catch {
                failures[target] = .invalidArgument(String(describing: error))
                break
            }
        }
        let authoredValues = candidates.reduce(
            into: [SceneDynamicTarget: String]()
        ) { values, candidate in
            if values[candidate.2] == nil { values[candidate.2] = candidate.3 }
        }
        let authoredOrdinals = candidates.reduce(
            into: [SceneDynamicTarget: Int]()
        ) { values, candidate in
            if requestedTargets.contains(candidate.2) {
                values[candidate.2] = candidate.0
            }
        }
        let program = SceneScriptStringProgram(
            bindings: owners,
            authoredValues: authoredValues,
            authoredOrdinals: authoredOrdinals,
            generation: generation
        )
        return .init(
            program: program,
            requestedTargets: requestedTargets,
            instantiatedTargets: Set(program.definitions.map(\.target)),
            failures: failures
        )
    }

    static func projectedTargets(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        Set(projectedDefinitions(
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            excludedTargets: excludedTargets
        ).map(\.target))
    }

    static func projectedDefinitions(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [SceneDynamicTargetDefinition] {
        let candidates = scriptBindings.compactMap {
            projection($0, descriptor: descriptor)
        }.filter { !excludedTargets.contains($0.target) }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            guard counts[candidate.target] == 1 else { return nil }
            return .init(
                target: candidate.target,
                valueType: .string,
                authoredValue: .string(candidate.authored)
            )
        }
    }

    static func projectedOwnerSources(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [String] {
        let candidates = scriptBindings.compactMap { binding ->
            (source: String, target: SceneDynamicTarget)? in
            guard let projection = projection(binding, descriptor: descriptor),
                  !excludedTargets.contains(projection.target) else { return nil }
            return (binding.source, projection.target)
        }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            counts[candidate.target] == 1 ? candidate.source : nil
        }
    }

    private init(
        bindings: [SceneScriptStringOwner],
        authoredValues: [SceneDynamicTarget: String],
        authoredOrdinals: [SceneDynamicTarget: Int] = [:],
        generation: UInt64
    ) {
        self.bindings = bindings
        self.authoredOrdinals = authoredOrdinals
        self.generation = generation
        definitions = bindings.compactMap { owner in
            authoredValues[owner.target].map {
                .init(target: owner.target, valueType: .string, authoredValue: .string($0))
            }
        }
    }

    var mediaOwnerRegistrations: [SceneScriptMediaOwnerRegistration] {
        bindings.compactMap { binding in
            guard binding.handlesMediaPlayback
                    || binding.handlesMediaProperties
                    || binding.handlesMediaThumbnail
                    || binding.handlesMediaTimeline,
                  let authoredOrdinal = authoredOrdinals[binding.target] else {
                return nil
            }
            return .init(
                authoredOrdinal: authoredOrdinal,
                target: binding.target,
                family: .string
            )
        }
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String = "{}",
        mediaThumbnailEvent: SceneScriptMediaThumbnailEventInput? = nil,
        mediaPlaybackEvent: SceneScriptMediaPlaybackEventInput? = nil,
        mediaPropertiesEvent: SceneScriptMediaPropertiesEventInput? = nil,
        mediaTimelineEvent: SceneScriptMediaTimelineEventInput? = nil,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptStringFrameResult {
        let observedThumbnail = observedMediaThumbnailEvent.observe(
            mediaThumbnailEvent
        )
        let observedPlayback = observedMediaPlaybackEvent.observe(
            mediaPlaybackEvent
        )
        let observedProperties = observedMediaPropertiesEvent.observe(
            mediaPropertiesEvent
        )
        let observedTimeline = observedMediaTimelineEvent.observe(
            mediaTimelineEvent
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
        var animations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        for binding in bindings {
            if disabledTargets.contains(binding.target) { continue }
            guard let input = inputs[binding.target],
                  case let .string(current) = input else { continue }
            let playback = observedPlayback.flatMap { event in
                binding.handlesMediaPlayback && event.generation
                    > consumedMediaPlaybackGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let properties = observedProperties.flatMap { event in
                binding.handlesMediaProperties && event.generation
                    > consumedMediaPropertiesGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let thumbnail = observedThumbnail.flatMap { event in
                binding.handlesMediaThumbnail && event.generation
                    > consumedMediaThumbnailGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let timeline = observedTimeline.flatMap { event in
                binding.handlesMediaTimeline && event.generation
                    > consumedMediaTimelineGenerations[binding.target, default: 0]
                    ? event : nil
            }
            if binding.hasAudioRegistration {
                switch binding.refreshAudio(audioSpectrum) {
                case .success: break
                case let .failure(failure):
                    failures[binding.target] = failure
                    disabledTargets.insert(binding.target)
                    continue
                }
            }
            var ownerMaterialFunctions: [SceneScriptMaterialFunctionMutation] = []
            var ownerAnimations: [SceneTimelinePlaybackMutation] = []
            var ownerLayerMutations: [SceneScriptLayerMutation] = []
            if let playback, !dispatch(
                binding.dispatchMediaPlayback(
                    playback, frame: frame, userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                layers: &ownerLayerMutations,
                failures: &failures
            ) {
                continue
            }
            if let properties, !dispatch(
                binding.dispatchMediaProperties(
                    properties, frame: frame, userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                layers: &ownerLayerMutations,
                failures: &failures
            ) {
                continue
            }
            if let thumbnail, !dispatch(
                binding.dispatchMediaThumbnail(
                    thumbnail, frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                layers: &ownerLayerMutations,
                failures: &failures
            ) {
                continue
            }
            if let timeline, !dispatch(
                binding.dispatchMediaTimeline(
                    timeline, frame: frame, userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ),
                binding: binding,
                materialFunctions: &ownerMaterialFunctions,
                animations: &ownerAnimations,
                layers: &ownerLayerMutations,
                failures: &failures
            ) {
                continue
            }
            switch binding.evaluate(
                input: current,
                frame: frame,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                if let playback {
                    consumedMediaPlaybackGenerations[binding.target] =
                        playback.generation
                }
                if let properties {
                    consumedMediaPropertiesGenerations[binding.target] =
                        properties.generation
                }
                if let timeline {
                    consumedMediaTimelineGenerations[binding.target] =
                        timeline.generation
                }
                if let thumbnail {
                    consumedMediaThumbnailGenerations[binding.target] =
                        thumbnail.generation
                }
                ownerMaterialFunctions.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                ownerAnimations.append(contentsOf: evaluation.animationMutations)
                ownerLayerMutations.append(contentsOf: evaluation.layerMutations)
                values[binding.target] = evaluation.value
                materialFunctions.append(contentsOf: ownerMaterialFunctions)
                animations.append(contentsOf: ownerAnimations)
                layerMutations.append(contentsOf: ownerLayerMutations)
                if let properties,
                   case let .string(output) = evaluation.value {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaPropertiesChanged generation=%llu titleUTF8Bytes=%d artistUTF8Bytes=%d subTitleUTF8Bytes=%d albumTitleUTF8Bytes=%d albumArtistUTF8Bytes=%d genresUTF8Bytes=%d contentTypeUTF8Bytes=%d outputUTF8Bytes=%d route=generic-only",
                        String(describing: binding.target), properties.generation,
                        properties.title.utf8.count, properties.artist.utf8.count,
                        properties.subTitle.utf8.count,
                        properties.albumTitle.utf8.count,
                        properties.albumArtist.utf8.count,
                        properties.genres.utf8.count,
                        properties.contentType.utf8.count,
                        output.utf8.count
                    )
                }
                if let timeline {
                    SceneScriptMediaRuntimeDiagnostics.logTimeline(
                        target: binding.target, event: timeline
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
            animationMutations: animations,
            layerMutations: layerMutations
        )
    }

    func invalidate() { bindings.forEach { $0.invalidate() } }

    func teardown(
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        bindings.map {
            $0.teardown(frame: frame, userPropertiesJSON: userPropertiesJSON)
        }
    }

    private func dispatch(
        _ result: Result<SceneScriptMediaEventMutations, SceneScriptScalarRuntimeFailure>,
        binding: SceneScriptStringOwner,
        materialFunctions: inout [SceneScriptMaterialFunctionMutation],
        animations: inout [SceneTimelinePlaybackMutation],
        layers: inout [SceneScriptLayerMutation],
        failures: inout [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    ) -> Bool {
        switch result {
        case let .success(mutations):
            materialFunctions.append(contentsOf: mutations.materialFunctions)
            animations.append(contentsOf: mutations.animations)
            layers.append(contentsOf: mutations.layers)
            return true
        case let .failure(failure):
            failures[binding.target] = failure
            disabledTargets.insert(binding.target)
            return false
        }
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
