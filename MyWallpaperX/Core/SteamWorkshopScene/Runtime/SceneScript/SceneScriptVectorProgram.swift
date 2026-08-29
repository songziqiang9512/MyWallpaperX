import Foundation

nonisolated struct SceneScriptVectorFrameResult: Equatable, Sendable {
    let values: [SceneDynamicTarget: SceneDynamicValue]
    let failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure]
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
}

nonisolated enum SceneScriptHostValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case vector3(Double, Double, Double)

    var jsonObject: Any {
        switch self {
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .vector3(x, y, z): ["x": x, "y": y, "z": z]
        }
    }
}

nonisolated struct SceneScriptPropertyInput: Equatable, Sendable {
    let fallback: SceneScriptHostValue
    let userPropertyKey: String?

    func resolve(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> SceneScriptHostValue? {
        guard let userPropertyKey,
              let live = effectiveValues[userPropertyKey] else { return fallback }
        switch (fallback, live) {
        case (_, .number(let value)) where !value.isFinite:
            return nil
        case (.number, .number(let value)):
            return .number(value)
        case (.bool, .bool(let value)):
            return .bool(value)
        case (.string, .string(let value)):
            return .string(value)
        default:
            return nil
        }
    }
}

nonisolated struct SceneScriptVectorBinding: @unchecked Sendable {
    let definition: SceneDynamicTargetDefinition
    let properties: [String: SceneScriptPropertyInput]
    let hasCurrentAnimation: Bool
    let handlesMediaThumbnail: Bool
    let handlesMediaPlayback: Bool
    let owner: SceneScriptVectorOwner
}

nonisolated struct SceneScriptCursorOwnerRegistration: @unchecked Sendable {
    let layerID: Int
    let authoredOrder: Int
    let owner: SceneScriptVectorOwner
}

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
    private var consumedMediaThumbnailGenerations: [SceneDynamicTarget: UInt64] = [:]
    private var consumedMediaPlaybackGenerations: [SceneDynamicTarget: UInt64] = [:]
    private var appliedUserPropertiesByTarget:
        [SceneDynamicTarget: [String: SceneUserPropertyValue]] = [:]

    var hasAudioConsumers: Bool {
        bindings.contains(where: { $0.owner.hasAudioRegistration })
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

    var cursorOwnerRegistrations: [SceneScriptCursorOwnerRegistration] {
        bindings.compactMap { binding in
            guard case let .layer(layerID, _) = binding.definition.target,
                  let authoredOrder = descriptor.layers.firstIndex(where: {
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
        excludedTargets: Set<SceneDynamicTarget> = [],
        generation: UInt64,
        budget: SceneScriptScalarBudget = .default
    ) -> SceneScriptVectorProgram {
        let projection = project(
            descriptor: descriptor,
            scriptBindings: scriptBindings,
            timelineTargets: timelineTargets,
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
                definition: candidate.definition,
                properties: candidate.properties,
                hasCurrentAnimation: candidate.hasCurrentAnimation,
                handlesMediaThumbnail: owner.handlesMediaThumbnail,
                handlesMediaPlayback: owner.handlesMediaPlayback,
                owner: owner
            ))
        }
        bindings.sort {
            String(describing: $0.definition.target)
                < String(describing: $1.definition.target)
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
        audioSpectrum: SceneAudioSpectrumSnapshot = .silent,
        interruptBudget: UInt64? = nil
    ) -> SceneScriptVectorFrameResult {
        let observedMediaEvent = observedMediaThumbnailEvent.observe(
            mediaThumbnailEvent
        )
        let observedPlaybackEvent = observedMediaPlaybackEvent.observe(
            mediaPlaybackEvent
        )
        let userJSON = userPropertiesJSON(
            effectiveValues: effectivePropertyValues
        )
        var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        for binding in bindings {
            let target = binding.definition.target
            if disabledTargets.contains(target) { continue }
            guard let input = inputs[target],
                  input.valueType == binding.definition.valueType,
                  let propertiesJSON = Self.scriptPropertiesJSON(
                      binding.properties,
                      effectiveValues: effectivePropertyValues
                  ) else { continue }
            let changedUserPropertiesJSON = Self.changedUserPropertiesJSON(
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
            var callbackMaterialMutations: [SceneScriptMaterialFunctionMutation] = []
            var callbackAnimationMutations: [SceneTimelinePlaybackMutation] = []
            var callbackLayerMutations: [SceneScriptLayerMutation] = []
            var playbackMutationCount = 0
            var thumbnailMutationCount = 0
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
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
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
                case let .failure(failure):
                    failures[target] = failure
                    disabledTargets.insert(target)
                    continue
                }
            }
            switch binding.owner.evaluate(
                input: input,
                frame: frame,
                scriptPropertiesJSON: propertiesJSON,
                userPropertiesJSON: userJSON,
                expectedGeneration: generation,
                interruptBudget: interruptBudget
            ) {
            case let .success(evaluation):
                let value = evaluation.value
                if let pendingPlaybackEvent {
                    consumedMediaPlaybackGenerations[target] =
                        pendingPlaybackEvent.generation
                }
                if let pendingMediaEvent {
                    consumedMediaThumbnailGenerations[target] =
                        pendingMediaEvent.generation
                }
                appliedUserPropertiesByTarget[target] = effectivePropertyValues
                callbackMaterialMutations.append(
                    contentsOf: evaluation.materialFunctionMutations
                )
                callbackAnimationMutations.append(
                    contentsOf: evaluation.animationMutations
                )
                callbackLayerMutations.append(contentsOf: evaluation.layerMutations)
                values[target] = value
                materialFunctionMutations.append(
                    contentsOf: callbackMaterialMutations
                )
                animationMutations.append(contentsOf: callbackAnimationMutations)
                layerMutations.append(contentsOf: callbackLayerMutations)
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
            layerMutations: layerMutations
        )
    }

    func userPropertiesJSON(
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String {
        Self.userPropertiesJSON(
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
            let propertiesJSON = Self.scriptPropertiesJSON(
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

    static func passConstantPath(
        objectIndex: Int, effectIndex: Int, passIndex: Int, name: String
    ) -> [SceneScriptBindingPathComponent] {
        [
            .key("objects"), .index(objectIndex),
            .key("effects"), .index(effectIndex),
            .key("passes"), .index(passIndex),
            .key("constantshadervalues"), .key(name),
        ]
    }

    static func propertyInput(
        _ value: SceneJSONValue
    ) -> SceneScriptPropertyInput? {
        if let fallback = hostValue(value) {
            return .init(fallback: fallback, userPropertyKey: nil)
        }
        guard case let .object(wrapper) = value,
              wrapper.keys.sorted() == ["user", "value"],
              case let .string(key)? = wrapper["user"], validName(key),
              let fallbackValue = wrapper["value"],
              let fallback = hostValue(fallbackValue) else { return nil }
        return .init(fallback: fallback, userPropertyKey: key)
    }

    private static func hostValue(_ value: SceneJSONValue) -> SceneScriptHostValue? {
        switch value {
        case let .number(number) where number.isFinite: .number(number)
        case let .bool(value): .bool(value)
        case let .string(value): .string(value)
        default: nil
        }
    }

    static func vector3(_ value: String) -> SIMD3<Double>? {
        let parts = value.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 3, numbers.allSatisfy(\.isFinite) else { return nil }
        return .init(numbers[0], numbers[1], numbers[2])
    }

    static func vector2(_ value: String) -> SIMD2<Double>? {
        let parts = value.split { $0.isWhitespace || $0 == "," }
        guard parts.count == 2 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 2, numbers.allSatisfy(\.isFinite) else { return nil }
        return .init(numbers[0], numbers[1])
    }

    static func validName(_ value: String) -> Bool {
        !value.isEmpty && value != "__proto__" && value.utf8.count <= 256
    }

    static func scriptPropertiesJSON(
        _ inputs: [String: SceneScriptPropertyInput],
        effectiveValues: [String: SceneUserPropertyValue]
    ) -> String? {
        if inputs.isEmpty { return "" }
        var object: [String: Any] = [:]
        for (key, input) in inputs {
            guard let value = input.resolve(effectiveValues: effectiveValues) else {
                return nil
            }
            object[key] = value.jsonObject
        }
        return json(object)
    }

    private static func userPropertiesJSON(
        values: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind]
    ) -> String {
        let object = values.reduce(into: [String: Any]()) { result, entry in
            guard validName(entry.key) else { return }
            switch (kinds[entry.key], entry.value) {
            case (.color, .string(let value)):
                if let color = vector3(value) {
                    result[entry.key] = SceneScriptHostValue.vector3(
                        color.x, color.y, color.z
                    ).jsonObject
                }
            case (_, .number(let value)) where value.isFinite:
                result[entry.key] = value
            case (_, .bool(let value)):
                result[entry.key] = value
            case (_, .string(let value)):
                result[entry.key] = value
            default:
                break
            }
        }
        return json(object) ?? "{}"
    }

    private static func changedUserPropertiesJSON(
        previous: [String: SceneUserPropertyValue]?,
        current: [String: SceneUserPropertyValue],
        kinds: [String: SceneUserPropertyKind]
    ) -> String? {
        guard let previous else {
            return userPropertiesJSON(values: current, kinds: kinds)
        }
        let changedKeys = Set(previous.keys).union(current.keys).filter {
            previous[$0] != current[$0]
        }
        guard !changedKeys.isEmpty else { return nil }
        var object: [String: Any] = [:]
        for key in changedKeys where validName(key) {
            guard let value = current[key] else {
                object[key] = NSNull()
                continue
            }
            let encoded = userPropertiesJSON(
                values: [key: value],
                kinds: kinds
            )
            guard let data = encoded.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = item as? [String: Any],
                  let encodedValue = dictionary[key] else { continue }
            object[key] = encodedValue
        }
        return object.isEmpty ? nil : json(object)
    }

    private static func json(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.sortedKeys]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
