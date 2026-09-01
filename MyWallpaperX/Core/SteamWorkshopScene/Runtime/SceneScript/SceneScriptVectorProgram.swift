import Foundation

/// Generic typed vector VM route. Admission is based only on the
/// loss-preserving binding owner/path/type and descriptor identity. JavaScript
/// semantics remain owned by QuickJS; there is no source-shape interpreter.
nonisolated final class SceneScriptVectorProgram: @unchecked Sendable {
    private(set) var definitions: [SceneDynamicTargetDefinition]
    private(set) var bindings: [SceneScriptVectorBinding]
    let domain: SceneScriptQuickJSDomain?
    let generation: UInt64
    private let descriptor: SceneRenderDescriptor
    private let userPropertyKinds: [String: SceneUserPropertyKind]
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
        bindings.contains(where: { $0.owner.hasAudioRegistration })
    }

    var livePropertyInputTargets: Set<SceneDynamicTarget> {
        bindings.reduce(into: Set<SceneDynamicTarget>()) {
            $0.formUnion($1.livePropertyInputTargets)
        }
    }

    var activeLivePropertyInputTargets: Set<SceneDynamicTarget> {
        bindings.reduce(into: Set<SceneDynamicTarget>()) {
            if !disabledTargets.contains($1.definition.target) {
                $0.formUnion($1.livePropertyInputTargets)
            }
        }
    }

    private init(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        bindings: [SceneScriptVectorBinding],
        generation: UInt64,
        userPropertyDefinitions: [SceneUserPropertyDefinition]
    ) {
        self.domain = domain
        self.descriptor = descriptor
        self.bindings = bindings
        self.generation = generation
        definitions = bindings.map(\.definition)
        userPropertyKinds = Dictionary(
            uniqueKeysWithValues: userPropertyDefinitions.map { ($0.key, $0.kind) }
        )
    }

    var admittedScaleLayerIDs: Set<Int> {
        Set(bindings.compactMap { binding in
            guard case let .layer(layerID, .scale) = binding.definition.target else {
                return nil
            }
            return layerID
        })
    }

    var animationTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.hasCurrentAnimation ? binding.definition.target : nil
        })
    }

    var mediaThumbnailTargets: Set<SceneDynamicTarget> {
        Set(bindings.compactMap { binding in
            binding.handlesMediaThumbnail ? binding.definition.target : nil
        })
    }

    var mediaOwnerTargets: Set<SceneDynamicTarget> {
        Set(mediaOwnerRegistrations.map(\.target))
    }

    var mediaOwnerRegistrations: [SceneScriptMediaOwnerRegistration] {
        bindings.compactMap { binding in
            guard binding.handlesMediaPlayback
                    || binding.handlesMediaProperties
                    || binding.handlesMediaThumbnail
                    || binding.handlesMediaTimeline else { return nil }
            return .init(
                authoredOrdinal: binding.authoredOrdinal,
                target: binding.definition.target,
                family: .vector
            )
        }
    }

    var cursorOwnerRegistrations: [SceneScriptCursorOwnerRegistration] {
        bindings.compactMap { binding in
            let layerID: Int
            switch binding.definition.target {
            case let .layer(value, _), let .text(value, _):
                layerID = value
            default:
                return nil
            }
            guard let authoredOrder = descriptor.layers.firstIndex(where: {
                      $0.id == layerID
                  }) else { return nil }
            return .init(
                layerID: layerID,
                authoredOrder: authoredOrder,
                owner: binding.owner
            )
        }
    }

    static func compile(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        scriptBindings: [SceneScriptBindingIR],
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        timelineTargets: Set<SceneDynamicTarget> = [],
        admittedLayerColorConsumerIDs: Set<Int> = [],
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorProgram {
        let projection = project(
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets,
            admittedLayerColorConsumerIDs: admittedLayerColorConsumerIDs,
            excludedTargets: excludedTargets
        )
        let program = compileNonPass(
            domain: domain,
            descriptor: descriptor,
            projection: projection,
            userPropertyDefinitions: userPropertyDefinitions,
            generation: generation,
            budget: budget
        )
        _ = program.instantiatePassOwners(
            projection: projection,
            admittedTargets: projection.passTargets,
            budget: budget
        )
        return program
    }

    static func compileNonPass(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        projection: SceneScriptVectorCandidateCatalog,
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorProgram {
        compileNonPassCandidate(
            domain: domain,
            descriptor: descriptor,
            projection: projection,
            userPropertyDefinitions: userPropertyDefinitions,
            rejectedTargets: [],
            generation: generation,
            budget: budget
        ).program
    }

    static func compileNonPassCandidate(
        domain: SceneScriptQuickJSDomain?,
        descriptor: SceneRenderDescriptor,
        projection: SceneScriptVectorCandidateCatalog,
        userPropertyDefinitions: [SceneUserPropertyDefinition],
        rejectedTargets: Set<SceneDynamicTarget>,
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorProgramConstruction {
        let requestedTargets = projection.nonPassTargets.subtracting(
            rejectedTargets
        )
        guard let domain else {
            let program = SceneScriptVectorProgram(
                domain: nil, descriptor: descriptor,
                bindings: [], generation: generation,
                userPropertyDefinitions: userPropertyDefinitions
            )
            let failure = SceneScriptScalarRuntimeFailure.invalidArgument(
                "QuickJS domain unavailable"
            )
            return .init(
                program: program,
                requestedTargets: requestedTargets,
                instantiatedTargets: [],
                failures: Dictionary(uniqueKeysWithValues:
                    requestedTargets.map { ($0, failure) }
                )
            )
        }
        do {
            try domain.configureLayerCatalog(descriptor)
        } catch {
            let failure = (error as? SceneScriptScalarRuntimeFailure)
                ?? .invalidArgument(String(describing: error))
            let program = SceneScriptVectorProgram(
                domain: nil, descriptor: descriptor,
                bindings: [], generation: generation,
                userPropertyDefinitions: userPropertyDefinitions
            )
            return .init(
                program: program,
                requestedTargets: requestedTargets,
                instantiatedTargets: [],
                failures: Dictionary(uniqueKeysWithValues:
                    requestedTargets.map { ($0, failure) }
                )
            )
        }
        let program = SceneScriptVectorProgram(
            domain: domain, descriptor: descriptor,
            bindings: [],
            generation: generation,
            userPropertyDefinitions: userPropertyDefinitions
        )
        let failures = program.instantiateCandidates(
            projection.uniqueCandidates.filter {
                requestedTargets.contains($0.definition.target)
            },
            budget: budget
        )
        let instantiatedTargets = Set(program.definitions.map(\.target))
            .intersection(requestedTargets)
        return .init(
            program: program,
            requestedTargets: requestedTargets,
            instantiatedTargets: instantiatedTargets,
            failures: failures
        )
    }

    @discardableResult
    func instantiatePassOwners(
        projection: SceneScriptVectorCandidateCatalog,
        admittedTargets: Set<SceneDynamicTarget>,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorPassCompilation {
        let requestedTargets = admittedTargets.intersection(projection.passTargets)
        let candidates = projection.uniqueCandidates.filter {
            requestedTargets.contains($0.definition.target)
        }
        let failures = instantiateCandidates(candidates, budget: budget)
        let failedTargets = Set(failures.keys)
        let instantiatedTargets = requestedTargets.subtracting(failedTargets)
            .intersection(Set(definitions.map(\.target)))
        return .init(
            requestedTargets: requestedTargets,
            instantiatedTargets: instantiatedTargets,
            failures: failures
        )
    }

    private func instantiateCandidates(
        _ candidates: [SceneScriptVectorCandidate],
        budget: SceneScriptScalarBudget
    ) -> [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] {
        let existingTargets = Set(definitions.map(\.target))
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        guard let domain else {
            return Dictionary(uniqueKeysWithValues: candidates.map {
                ($0.definition.target, .invalidArgument("QuickJS domain unavailable"))
            })
        }
        for candidate in candidates
        where !existingTargets.contains(candidate.definition.target) {
            let target = candidate.definition.target
            guard let layerID = SceneScriptLayerMutationBridge.layerID(for: target),
                  let layer = descriptor.layers.first(where: { $0.id == layerID }) else {
                failures[target] = .invalidArgument(
                    "SceneScript owner layer identity unavailable"
                )
                break
            }
            let owner: SceneScriptVectorOwner
            do {
                owner = try SceneScriptVectorOwner(
                      domain: domain,
                      source: candidate.source,
                      target: target,
                      valueType: candidate.definition.valueType,
                      effectNames: layer.effects.map(\.name),
                      hasCurrentAnimation: candidate.hasCurrentAnimation,
                      dynamicImagePathsByAuthoredIdentity: Dictionary(
                        uniqueKeysWithValues: candidate.dynamicImageReferences.map {
                            ($0.authoredPath.lowercased(), $0.modelPath)
                        }
                      ),
                      generation: generation,
                      budget: budget
                )
            } catch let failure as SceneScriptScalarRuntimeFailure {
                failures[target] = failure
                break
            } catch {
                failures[target] = .invalidArgument(String(describing: error))
                break
            }
            bindings.append(.init(
                authoredOrdinal: candidate.authoredOrdinal,
                definition: candidate.definition,
                properties: candidate.properties,
                livePropertyInputTargets: candidate.livePropertyInputTargets,
                hasCurrentAnimation: candidate.hasCurrentAnimation,
                handlesMediaThumbnail: owner.handlesMediaThumbnail,
                handlesMediaPlayback: owner.handlesMediaPlayback,
                handlesMediaProperties: owner.handlesMediaProperties,
                handlesMediaTimeline: owner.handlesMediaTimeline,
                dynamicImageReferences: candidate.dynamicImageReferences,
                owner: owner
            ))
        }
        definitions = bindings.map(\.definition)
        return failures
    }

    func evaluate(
        inputs: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frame: SceneScriptFrameInput,
        mediaThumbnailEvent: SceneScriptMediaThumbnailEventInput? = nil,
        mediaPlaybackEvent: SceneScriptMediaPlaybackEventInput? = nil,
        mediaPropertiesEvent: SceneScriptMediaPropertiesEventInput? = nil,
        mediaTimelineEvent: SceneScriptMediaTimelineEventInput? = nil,
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptVectorFrameResult {
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
        let userJSON = userPropertiesJSON(
            effectiveValues: effectivePropertyValues
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        var videoCommands: [SceneScriptVideoCommand] = []
        var videoCommandTargets: Set<SceneDynamicTarget> = []
        for binding in bindings {
            let target = binding.definition.target
            if disabledTargets.contains(target) { continue }
            guard let input = inputs[target],
                  input.valueType == binding.definition.valueType,
                  let propertiesJSON = SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                      binding.properties,
                      effectiveValues: effectivePropertyValues
                  ) else { continue }
            let changedUserPropertiesJSON =
                SceneScriptPropertyInputCodec.changedUserPropertiesJSON(
                previous: appliedUserPropertiesByTarget[target],
                current: effectivePropertyValues,
                kinds: userPropertyKinds
            )
            let pendingPlaybackEvent = observedPlaybackEvent.flatMap { event in
                binding.handlesMediaPlayback && event.generation
                    > consumedMediaPlaybackGenerations[target, default: 0]
                    ? event : nil
            }
            let pendingMediaEvent = observedMediaEvent.flatMap { event in
                binding.handlesMediaThumbnail && event.generation
                    > consumedMediaThumbnailGenerations[target, default: 0]
                    ? event : nil
            }
            let pendingPropertiesEvent = observedPropertiesEvent.flatMap { event in
                binding.handlesMediaProperties && event.generation
                    > consumedMediaPropertiesGenerations[target, default: 0]
                    ? event : nil
            }
            let pendingTimelineEvent = observedTimelineEvent.flatMap { event in
                binding.handlesMediaTimeline && event.generation
                    > consumedMediaTimelineGenerations[target, default: 0]
                    ? event : nil
            }
            var callbackMaterialMutations: [SceneScriptMaterialFunctionMutation] = []
            var callbackAnimationMutations: [SceneTimelinePlaybackMutation] = []
            var callbackLayerMutations: [SceneScriptLayerMutation] = []
            var initializationLayerMutations: [SceneScriptLayerMutation] = []
            var callbackVideoCommands: [SceneScriptVideoCommand] = []
            var playbackMutationCount = 0
            var propertiesLayerMutationCount = 0
            var thumbnailMutationCount = 0
            var evaluationInput = input
            if changedUserPropertiesJSON != nil || pendingPlaybackEvent != nil
                || pendingMediaEvent != nil || pendingPropertiesEvent != nil
                || pendingTimelineEvent != nil {
                switch binding.owner.initializeIfNeeded(
                    input: input,
                    frame: frame,
                    scriptPropertiesJSON: propertiesJSON,
                    userPropertiesJSON: userJSON,
                    expectedGeneration: generation,
                    interruptBudget: interruptBudget
                ) {
                case let .success(initialization):
                    if let initialization {
                        evaluationInput = initialization.value
                        callbackMaterialMutations.append(
                            contentsOf: initialization.materialFunctionMutations
                        )
                        callbackAnimationMutations.append(
                            contentsOf: initialization.animationMutations
                        )
                        initializationLayerMutations.append(
                            contentsOf: initialization.layerMutations
                        )
                        callbackVideoCommands.append(
                            contentsOf: initialization.videoCommands
                        )
                    }
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if let changedUserPropertiesJSON {
                switch binding.owner.dispatchUserProperties(
                    changedPropertiesJSON: changedUserPropertiesJSON,
                    scriptPropertiesJSON: propertiesJSON,
                    frame: frame,
                    userPropertiesJSON: userJSON,
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
                    callbackVideoCommands.append(
                        contentsOf: eventMutations.videoCommands
                    )
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if binding.definition.valueType == .bool,
               !callbackMaterialMutations.isEmpty
                    || !callbackAnimationMutations.isEmpty {
                failures[target] = .invalidArgument(
                    "Boolean value owner produced out-of-cohort callback mutations"
                )
                disabledTargets.insert(target)
                continue
            }
            if binding.owner.hasAudioRegistration {
                switch binding.owner.refreshAudio(audioSpectrum) {
                case .success:
                    if audioSpectrum.generation > 0, !audioSpectrum.isSilent,
                       reportedAudioTargets.insert(target).inserted {
                        let peak = [
                            audioSpectrum.left.max() ?? 0,
                            audioSpectrum.right.max() ?? 0,
                            audioSpectrum.left32.max() ?? 0,
                            audioSpectrum.right32.max() ?? 0,
                            audioSpectrum.left64.max() ?? 0,
                            audioSpectrum.right64.max() ?? 0,
                        ].max() ?? 0
                        NSLog(
                            "MWX SceneScript VM: target=%@ event=audioBuffersUpdated generation=%llu silent=%@ peak=%.9g route=generic-only",
                            String(describing: target),
                            audioSpectrum.generation,
                            audioSpectrum.isSilent ? "true" : "false",
                            peak
                        )
                    }
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if let pendingPlaybackEvent {
                switch binding.owner.dispatchMediaPlayback(
                    pendingPlaybackEvent,
                    frame: frame,
                    userPropertiesJSON: userJSON,
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
                    callbackVideoCommands.append(
                        contentsOf: eventMutations.videoCommands
                    )
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if let pendingPropertiesEvent {
                switch binding.owner.dispatchMediaProperties(
                    pendingPropertiesEvent,
                    frame: frame,
                    userPropertiesJSON: userJSON,
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
                    callbackVideoCommands.append(
                        contentsOf: eventMutations.videoCommands
                    )
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if let pendingMediaEvent {
                switch binding.owner.dispatchMediaThumbnail(
                    pendingMediaEvent,
                    frame: frame,
                    userPropertiesJSON: userJSON,
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
                    callbackVideoCommands.append(
                        contentsOf: eventMutations.videoCommands
                    )
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            if let pendingTimelineEvent {
                switch binding.owner.dispatchMediaTimeline(
                    pendingTimelineEvent,
                    frame: frame,
                    userPropertiesJSON: userJSON,
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
                    callbackVideoCommands.append(
                        contentsOf: eventMutations.videoCommands
                    )
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            switch binding.owner.evaluate(
                input: evaluationInput,
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                let value = evaluation.value
                if binding.definition.valueType == .bool {
                    guard case let .layer(layerID, .visibility) = target,
                          case let .bool(visible) = value,
                          callbackLayerMutations.allSatisfy({ mutation in
                              mutation.kind == .upsert && !mutation.isDynamic
                                  && mutation.layerID == layerID
                                  && mutation.fields == .visibility
                                  && mutation.visible == visible
                          }) else {
                        failures[target] = .invalidArgument(
                            "Boolean value owner produced conflicting target visibility"
                        )
                        disabledTargets.insert(target)
                        continue
                    }
                    callbackLayerMutations.removeAll(keepingCapacity: true)
                }
                callbackLayerMutations.insert(
                    contentsOf: initializationLayerMutations,
                    at: callbackLayerMutations.startIndex
                )
                if let pendingPlaybackEvent {
                    consumedMediaPlaybackGenerations[target] =
                        pendingPlaybackEvent.generation
                }
                if let pendingMediaEvent {
                    consumedMediaThumbnailGenerations[target] =
                        pendingMediaEvent.generation
                }
                if let pendingPropertiesEvent {
                    consumedMediaPropertiesGenerations[target] =
                        pendingPropertiesEvent.generation
                }
                if let pendingTimelineEvent {
                    consumedMediaTimelineGenerations[target] =
                        pendingTimelineEvent.generation
                }
                appliedUserPropertiesByTarget[target] = effectivePropertyValues
                callbackMaterialMutations.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                callbackAnimationMutations.append(
                    contentsOf: evaluation.animationMutations
                )
                callbackLayerMutations.append(contentsOf: evaluation.layerMutations)
                callbackVideoCommands.append(contentsOf: evaluation.videoCommands)
                values[target] = value
                materialFunctionMutations.append(
                    contentsOf: callbackMaterialMutations
                )
                animationMutations.append(contentsOf: callbackAnimationMutations)
                layerMutations.append(contentsOf: callbackLayerMutations)
                videoCommands.append(contentsOf: callbackVideoCommands)
                if !callbackVideoCommands.isEmpty {
                    videoCommandTargets.insert(target)
                }
                if pendingMediaEvent != nil {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaThumbnailChanged generation=%llu hasThumbnail=%@ primary=%.9g,%.9g,%.9g secondary=%.9g,%.9g,%.9g tertiary=%.9g,%.9g,%.9g text=%.9g,%.9g,%.9g highContrast=%.9g,%.9g,%.9g output=%@ mutations=%d route=generic-only fallback=none",
                        String(describing: target),
                        pendingMediaEvent?.generation ?? 0,
                        pendingMediaEvent?.hasThumbnail == true ? "true" : "false",
                        pendingMediaEvent?.primaryColor.x ?? 0,
                        pendingMediaEvent?.primaryColor.y ?? 0,
                        pendingMediaEvent?.primaryColor.z ?? 0,
                        pendingMediaEvent?.secondaryColor.x ?? 0,
                        pendingMediaEvent?.secondaryColor.y ?? 0,
                        pendingMediaEvent?.secondaryColor.z ?? 0,
                        pendingMediaEvent?.tertiaryColor.x ?? 0,
                        pendingMediaEvent?.tertiaryColor.y ?? 0,
                        pendingMediaEvent?.tertiaryColor.z ?? 0,
                        pendingMediaEvent?.textColor.x ?? 0,
                        pendingMediaEvent?.textColor.y ?? 0,
                        pendingMediaEvent?.textColor.z ?? 0,
                        pendingMediaEvent?.highContrastColor.x ?? 0,
                        pendingMediaEvent?.highContrastColor.y ?? 0,
                        pendingMediaEvent?.highContrastColor.z ?? 0,
                        String(describing: value),
                        thumbnailMutationCount
                    )
                }
                if pendingPlaybackEvent != nil {
                    NSLog(
                        "MWX SceneScript VM: target=%@ event=mediaPlaybackChanged generation=%llu state=%d mutations=%d route=generic-only",
                        String(describing: target),
                        pendingPlaybackEvent?.generation ?? 0,
                        pendingPlaybackEvent?.state ?? -1,
                        playbackMutationCount
                    )
                }
                if let pendingPropertiesEvent {
                    SceneScriptMediaRuntimeDiagnostics.logProperties(
                        target: target,
                        event: pendingPropertiesEvent,
                        layerMutationCount: propertiesLayerMutationCount
                    )
                }
                if let pendingTimelineEvent {
                    SceneScriptMediaRuntimeDiagnostics.logTimeline(
                        target: target, event: pendingTimelineEvent
                    )
                }
                if reportedTargets.insert(target).inserted {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=completed type=%@ input=%@ output=%@ audio=%@ audioGeneration=%llu route=generic-only",
                        String(describing: target),
                        binding.definition.valueType.rawValue,
                        String(describing: input),
                        String(describing: value),
                        binding.owner.hasAudioRegistration ? "true" : "false",
                        audioSpectrum.generation
                    )
                }
                if binding.owner.hasAudioRegistration,
                   audioSpectrum.generation > 0, !audioSpectrum.isSilent,
                   reportedAudioValueTargets.insert(target).inserted {
                    NSLog(
                        "MWX SceneScript VM: target=%@ callback=audioValuePublished type=%@ generation=%llu input=%@ output=%@ route=generic-only",
                        String(describing: target),
                        binding.definition.valueType.rawValue,
                        audioSpectrum.generation,
                        String(describing: input),
                        String(describing: value)
                    )
                }
            case let .failure(failure):
                failures[target] = failure
                disabledTargets.insert(target)
            }
        }
        return .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctionMutations,
            animationMutations: animationMutations,
            layerMutations: layerMutations,
            videoCommands: videoCommands,
            videoCommandTargets: videoCommandTargets
        )
    }

    func rejectVideoCommandTargets(_ targets: Set<SceneDynamicTarget>) {
        disabledTargets.formUnion(targets)
    }

    func userPropertiesJSON(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String {
        SceneScriptPropertyInputCodec.userPropertiesJSON(
            values: effectiveValues,
            kinds: userPropertyKinds
        )
    }

    func invalidate() {
        bindings.forEach { $0.owner.invalidate() }
    }

    func teardown(
        frame: SceneScriptFrameInput,
        effectivePropertyValues: [String: SceneUserPropertyValue],
        userPropertiesJSON: String
    ) -> [SceneScriptOwnerTeardownOutcome] {
        bindings.map { binding in
            let propertiesJSON =
                SceneScriptPropertyInputCodec.scriptPropertiesJSON(
                binding.properties,
                effectiveValues: effectivePropertyValues
            ) ?? ""
            return binding.owner.teardown(
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userPropertiesJSON
            )
        }
    }
}
