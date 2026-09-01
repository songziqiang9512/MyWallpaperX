import Foundation

nonisolated struct SceneScriptScalarFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

nonisolated struct SceneScriptScalarProgramConstruction: @unchecked Sendable {
    let program: SceneScriptScalarProgram
    let requestedTargets: Set<SceneDynamicTarget>
    let instantiatedTargets: Set<SceneDynamicTarget>
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]

    var deferredTargets: Set<SceneDynamicTarget> {
        requestedTargets.subtracting(instantiatedTargets).subtracting(failures.keys)
    }
}

/// Generic scalar SceneScript owners. The program is deliberately
/// source/identity based rather than effect-name based; runtime failure keeps
/// the lower-priority authored/property/Timeline value for the affected owner.
nonisolated final class SceneScriptScalarProgram: @unchecked Sendable {
    let definitions: [SceneDynamicTargetDefinition]
    let bindings: [SceneScriptScalarOwner]
    let domain: SceneScriptQuickJSDomain?
    let generation: UInt64
    private let authoredOrdinals: [SceneDynamicTarget: Int]
    private let propertyInputsByTarget:
        [SceneDynamicTarget: [String: SceneScriptPropertyInput]]
    private let livePropertyInputTargetsByTarget:
        [SceneDynamicTarget: Set<SceneDynamicTarget>]
    private let userPropertyKinds: [String: SceneUserPropertyKind]
    let livePropertyInputTargets: Set<SceneDynamicTarget>
    private var disabledTargets: Set<SceneDynamicTarget> = []
    private var reportedTargets: Set<SceneDynamicTarget> = []
    private var reportedAudioTargets: Set<SceneDynamicTarget> = []
    private var reportedAudioValueTargets: Set<SceneDynamicTarget> = []
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
    private var appliedUserPropertiesByTarget:
        [SceneDynamicTarget: [String: SceneUserPropertyValue]] = [:]

    var hasAudioConsumers: Bool {
        bindings.contains(where: \.hasAudioRegistration)
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
                family: .scalar
            )
        }
    }

    var activeLivePropertyInputTargets: Set<SceneDynamicTarget> {
        livePropertyInputTargetsByTarget.reduce(into: Set<SceneDynamicTarget>()) {
            if !disabledTargets.contains($1.key) { $0.formUnion($1.value) }
        }
    }

    private init(
        domain: SceneScriptQuickJSDomain?,
        bindings: [SceneScriptScalarOwner],
        generation: UInt64,
        propertyInputsByTarget:
            [SceneDynamicTarget: [String: SceneScriptPropertyInput]] = [:],
        livePropertyInputTargetsByTarget:
            [SceneDynamicTarget: Set<SceneDynamicTarget>] = [:],
        livePropertyInputTargets: Set<SceneDynamicTarget> = [],
        userPropertyDefinitions: [SceneUserPropertyDefinition] = [],
        authoredOrdinals: [SceneDynamicTarget: Int] = [:]
    ) {
        self.domain = domain
        self.bindings = bindings
        self.generation = generation
        self.propertyInputsByTarget = propertyInputsByTarget
        self.livePropertyInputTargetsByTarget = livePropertyInputTargetsByTarget
        self.livePropertyInputTargets = livePropertyInputTargets
        self.authoredOrdinals = authoredOrdinals
        userPropertyKinds = Dictionary(
            uniqueKeysWithValues: userPropertyDefinitions.map { ($0.key, $0.kind) }
        )
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
        userPropertyDefinitions: [SceneUserPropertyDefinition] = [],
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
            return unavailable(generation: generation)
        }
        return compileCandidate(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            userPropertyDefinitions: userPropertyDefinitions,
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
        userPropertyDefinitions: [SceneUserPropertyDefinition] = [],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        rejectedTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptScalarProgramConstruction {
        let candidates: [(
            SceneScriptBindingIR, SceneDynamicTarget, Double,
            [String: SceneScriptPropertyInput]
        )] =
            scriptBindings.compactMap { binding in
                guard let target = projection(
                          binding,
                          descriptor: descriptor,
                          timelineTargets: timelineTargets
                      ),
                      !excludedTargets.contains(target),
                      let authored = binding.authoredValue?.numberValue,
                      let properties = SceneScriptPropertyInputCodec.inputs(
                          binding.properties
                      ),
                      authored.isFinite else { return nil }
                return (binding, target, authored, properties)
            }
        let counts = Dictionary(grouping: candidates, by: { $0.1 })
            .mapValues(\.count)
        let requestedTargets = Set(candidates.compactMap { candidate in
            counts[candidate.1] == 1 ? candidate.1 : nil
        }).subtracting(rejectedTargets)
        var owners: [SceneScriptScalarOwner] = []
        var propertyInputsByTarget:
            [SceneDynamicTarget: [String: SceneScriptPropertyInput]] = [:]
        var livePropertyInputTargetsByTarget:
            [SceneDynamicTarget: Set<SceneDynamicTarget>] = [:]
        var livePropertyInputTargets: Set<SceneDynamicTarget> = []
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        for (binding, target, authored, properties) in candidates {
            let layerID: Int
            switch target {
            case let .effectConstant(value, _, _, _), let .layer(value, _),
                 let .text(value, .pointSize), let .particle(value, _):
                layerID = value
            default:
                continue
            }
            guard requestedTargets.contains(target),
                  let layer = descriptor.layers.first(where: { $0.id == layerID }) else {
                continue
            }
            do {
                guard let propertiesJSON =
                        SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                            properties,
                            effectiveValues: [:]
                        ) else {
                    failures[target] = .invalidArgument(
                        "SceneScript properties unavailable"
                    )
                    break
                }
                let owner = try SceneScriptScalarOwner(
                      domain: domain,
                      source: binding.source,
                      target: target,
                      authoredValue: authored,
                      scriptPropertiesJSON: propertiesJSON,
                      effectNames: layer.effects.map(\.name),
                      hasCurrentAnimation: timelineTargets.contains(target),
                      generation: generation,
                      budget: budget
                )
                owners.append(owner)
                propertyInputsByTarget[target] = properties
                let inputTargets =
                    SceneScriptPropertyInputCodec.liveConsumerTargets(
                        binding: binding, inputs: properties
                    )
                livePropertyInputTargetsByTarget[target] = inputTargets
                livePropertyInputTargets.formUnion(
                    inputTargets
                )
            } catch let failure as SceneScriptScalarRuntimeFailure {
                failures[target] = failure
                break
            } catch {
                failures[target] = .invalidArgument(String(describing: error))
                break
            }
        }
        var authoredOrdinals: [SceneDynamicTarget: Int] = [:]
        for (ordinal, binding) in scriptBindings.enumerated() {
            guard let target = projection(
                binding,
                descriptor: descriptor,
                timelineTargets: timelineTargets
            ), requestedTargets.contains(target) else { continue }
            authoredOrdinals[target] = ordinal
        }
        let program = SceneScriptScalarProgram(
            domain: domain,
            bindings: owners,
            generation: generation,
            propertyInputsByTarget: propertyInputsByTarget,
            livePropertyInputTargetsByTarget:
                livePropertyInputTargetsByTarget,
            livePropertyInputTargets: livePropertyInputTargets,
            userPropertyDefinitions: userPropertyDefinitions,
            authoredOrdinals: authoredOrdinals
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
        timelineTargets: Set<SceneDynamicTarget> = []
    ) -> Set<SceneDynamicTarget> {
        Set(projectedDefinitions(
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets
        ).map(\.target))
    }

    static func projectedDefinitions(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [SceneDynamicTargetDefinition] {
        let candidates = scriptBindings.compactMap { binding ->
            (target: SceneDynamicTarget, authored: Double)? in
            guard SceneScriptPropertyInputCodec.inputs(binding.properties) != nil,
                  let authored = binding.authoredValue?.numberValue,
                  authored.isFinite,
                  let target = projection(
                      binding,
                      descriptor: descriptor,
                      timelineTargets: timelineTargets
                  ), !excludedTargets.contains(target) else { return nil }
            return (target, authored)
        }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            guard counts[candidate.target] == 1 else { return nil }
            return .init(
                target: candidate.target,
                valueType: .scalar,
                authoredValue: .scalar(candidate.authored)
            )
        }
    }

    static func projectedOwnerSources(
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        timelineTargets: Set<SceneDynamicTarget> = [],
        excludedTargets: Set<SceneDynamicTarget> = []
    ) -> [String] {
        let candidates = scriptBindings.compactMap { binding ->
            (source: String, target: SceneDynamicTarget)? in
            guard SceneScriptPropertyInputCodec.inputs(binding.properties) != nil,
                  let target = projection(
                      binding,
                      descriptor: descriptor,
                      timelineTargets: timelineTargets
                  ),
                  !excludedTargets.contains(target) else { return nil }
            return (binding.source, target)
        }
        let counts = Dictionary(grouping: candidates, by: \.target)
            .mapValues(\.count)
        return candidates.compactMap { candidate in
            counts[candidate.target] == 1 ? candidate.source : nil
        }
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        frame: SceneScriptFrameInput,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        userPropertiesJSON: String = "{}",
        mediaThumbnailEvent: SceneScriptMediaThumbnailEventInput? = nil,
        mediaPlaybackEvent: SceneScriptMediaPlaybackEventInput? = nil,
        mediaPropertiesEvent: SceneScriptMediaPropertiesEventInput? = nil,
        mediaTimelineEvent: SceneScriptMediaTimelineEventInput? = nil,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptScalarFrameResult {
        let observedMediaEvent = observedMediaThumbnailEvent.observe(
            mediaThumbnailEvent
        )
        let observedPlaybackEvent = observedMediaPlaybackEvent.observe(
            mediaPlaybackEvent
        )
        let observedPropertiesEvent = observedMediaPropertiesEvent.observe(
            mediaPropertiesEvent
        )
        let observedTimelineEvent = observedMediaTimelineEvent.observe(
            mediaTimelineEvent
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        for binding in bindings {
            if disabledTargets.contains(binding.target) { continue }
            guard let input = inputs[binding.target],
                  case let .scalar(value) = input else { continue }
            guard let propertyInputs = propertyInputsByTarget[binding.target],
                  let propertiesJSON =
                    SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                        propertyInputs,
                        effectiveValues: effectivePropertyValues
                    ) else {
                failures[binding.target] = .invalidArgument(
                    "SceneScript properties unavailable"
                )
                continue
            }
            let hasUserPropertyInput = propertyInputs.values.contains {
                $0.userPropertyKey != nil
            }
            let changedUserPropertiesJSON = hasUserPropertyInput
                ? SceneScriptPropertyInputCodec.changedUserPropertiesJSON(
                    previous: appliedUserPropertiesByTarget[binding.target],
                    current: effectivePropertyValues,
                    kinds: userPropertyKinds
                ) : nil
            let pendingPlaybackEvent = observedPlaybackEvent.flatMap { event in
                binding.handlesMediaPlayback && event.generation
                    > consumedMediaPlaybackGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let pendingMediaEvent = observedMediaEvent.flatMap { event in
                binding.handlesMediaThumbnail && event.generation
                    > consumedMediaThumbnailGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let pendingPropertiesEvent = observedPropertiesEvent.flatMap { event in
                binding.handlesMediaProperties && event.generation
                    > consumedMediaPropertiesGenerations[binding.target, default: 0]
                    ? event : nil
            }
            let pendingTimelineEvent = observedTimelineEvent.flatMap { event in
                binding.handlesMediaTimeline && event.generation
                    > consumedMediaTimelineGenerations[binding.target, default: 0]
                    ? event : nil
            }
            var callbackMaterialMutations: [SceneScriptMaterialFunctionMutation] = []
            var callbackAnimationMutations: [SceneTimelinePlaybackMutation] = []
            var callbackLayerMutations: [SceneScriptLayerMutation] = []
            var playbackMutationCount = 0
            var propertiesLayerMutationCount = 0
            var thumbnailMutationCount = 0
            var evaluationInput = value
            if changedUserPropertiesJSON != nil || pendingPlaybackEvent != nil
                || pendingMediaEvent != nil || pendingPropertiesEvent != nil
                || pendingTimelineEvent != nil {
                switch binding.initializeIfNeeded(
                    input: value,
                    frame: frame,
                    scriptPropertiesJSON: propertiesJSON,
                    userPropertiesJSON: userPropertiesJSON,
                    expectedGeneration: generation,
                    interruptBudget: interruptBudget
                ) {
                case let .success(initialization):
                    if let initialization {
                        guard case let .scalar(initializedValue) = initialization.value else {
                            failures[binding.target] = .badReturn(
                                "scalar initialization returned a non-scalar value"
                            )
                            disabledTargets.insert(binding.target)
                            continue
                        }
                        evaluationInput = initializedValue
                        callbackMaterialMutations.append(
                            contentsOf: initialization.materialFunctionMutations
                        )
                        callbackAnimationMutations.append(
                            contentsOf: initialization.animationMutations
                        )
                        callbackLayerMutations.append(
                            contentsOf: initialization.layerMutations
                        )
                    }
                case let .failure(failure):
                    failures[binding.target] = failure
                    disabledTargets.insert(binding.target)
                    continue
                }
            }
            if let changedUserPropertiesJSON {
                switch binding.dispatchUserProperties(
                    changedPropertiesJSON: changedUserPropertiesJSON,
                    scriptPropertiesJSON: propertiesJSON,
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ) {
                case let .success(eventMutations):
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
            if let pendingPropertiesEvent {
                switch binding.dispatchMediaProperties(
                    pendingPropertiesEvent,
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ) {
                case let .success(eventMutations):
                    propertiesLayerMutationCount = eventMutations.layers.count
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
            if let pendingTimelineEvent {
                switch binding.dispatchMediaTimeline(
                    pendingTimelineEvent,
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    interruptBudget: interruptBudget
                ) {
                case let .success(eventMutations):
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
                input: evaluationInput,
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                if hasUserPropertyInput {
                    appliedUserPropertiesByTarget[binding.target] =
                        effectivePropertyValues
                }
                if let pendingPlaybackEvent {
                    consumedMediaPlaybackGenerations[binding.target] =
                        pendingPlaybackEvent.generation
                }
                if let pendingMediaEvent {
                    consumedMediaThumbnailGenerations[binding.target] =
                        pendingMediaEvent.generation
                }
                if let pendingPropertiesEvent {
                    consumedMediaPropertiesGenerations[binding.target] =
                        pendingPropertiesEvent.generation
                }
                if let pendingTimelineEvent {
                    consumedMediaTimelineGenerations[binding.target] =
                        pendingTimelineEvent.generation
                }
                callbackMaterialMutations.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                callbackAnimationMutations.append(
                    contentsOf: evaluation.animationMutations
                )
                callbackLayerMutations.append(contentsOf: evaluation.layerMutations)
                values[binding.target] = evaluation.value
                materialFunctionMutations.append(contentsOf: callbackMaterialMutations)
                animationMutations.append(contentsOf: callbackAnimationMutations)
                layerMutations.append(contentsOf: callbackLayerMutations)
                if changedUserPropertiesJSON != nil,
                   case let .scalar(outputValue) = evaluation.value {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=propertyInputApplied output=%.9g route=generic-only",
                        String(describing: binding.target),
                        outputValue
                    )
                }
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
                if let pendingPropertiesEvent {
                    SceneScriptMediaRuntimeDiagnostics.logProperties(
                        target: binding.target,
                        event: pendingPropertiesEvent,
                        layerMutationCount: propertiesLayerMutationCount
                    )
                }
                if let pendingTimelineEvent {
                    SceneScriptMediaRuntimeDiagnostics.logTimeline(
                        target: binding.target, event: pendingTimelineEvent
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
                if binding.hasAudioRegistration,
                   audioSpectrum.generation > 0, !audioSpectrum.isSilent,
                   reportedAudioValueTargets.insert(binding.target).inserted,
                   case let .scalar(inputValue) = input,
                   case let .scalar(outputValue) = evaluation.value {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=audioValuePublished type=scalar generation=%llu input=%.9g output=%.9g route=generic-only",
                        String(describing: binding.target),
                        audioSpectrum.generation,
                        inputValue,
                        outputValue
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

    func teardown(
        frame: SceneScriptFrameInput,
        effectivePropertyValues: [String: SceneUserPropertyValue] = [:],
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        bindings.map { binding in
            let propertiesJSON = propertyInputsByTarget[binding.target].flatMap {
                SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                    $0,
                    effectiveValues: effectivePropertyValues
                )
            }
            return binding.teardown(
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON
            )
        }
    }

    static func unavailable(generation: UInt64) -> SceneScriptScalarProgram {
        // A domain should only fail construction for a machine-level resource
        // error. Keep the failure local and preserve bounded fallbacks.
        return .init(domain: nil, bindings: [], generation: generation)
    }

}
