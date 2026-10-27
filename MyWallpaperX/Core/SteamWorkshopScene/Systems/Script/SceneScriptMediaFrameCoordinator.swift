import Foundation

nonisolated struct SceneScriptMediaFrameCoordinatorResult: Sendable {
    let vector: SceneScriptVectorFrameResult
    let string: SceneScriptStringFrameResult
    let scalar: SceneScriptScalarFrameResult
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand]
    let ownerEffects: [SceneScriptOwnerEffects]

    init(
        vector: SceneScriptVectorFrameResult,
        string: SceneScriptStringFrameResult,
        scalar: SceneScriptScalarFrameResult,
        materialFunctionMutations: [SceneScriptMaterialFunctionMutation],
        animationMutations: [SceneTimelinePlaybackMutation],
        layerMutations: [SceneScriptLayerMutation],
        mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand],
        ownerEffects: [SceneScriptOwnerEffects] = []
    ) {
        self.vector = vector
        self.string = string
        self.scalar = scalar
        self.materialFunctionMutations = materialFunctionMutations
        self.animationMutations = animationMutations
        self.layerMutations = layerMutations
        self.mediaPlaybackCommands = mediaPlaybackCommands
        self.ownerEffects = ownerEffects
    }
}

/// Initializes typed owners before cursor/update, then dispatches media in
/// authored order. Programs retain their VM handles and publication/lifecycle;
/// only unfinished initialization work survives the launch-prepared index.
nonisolated final class SceneScriptMediaFrameCoordinator: @unchecked Sendable {
    private let vectorProgram: SceneScriptVectorProgram
    private let stringProgram: SceneScriptStringProgram
    private let scalarProgram: SceneScriptScalarProgram
    private let registrations: [SceneScriptMediaOwnerRegistration]
    private let vectorMediaTargets: Set<SceneDynamicTarget>
    private let stringMediaTargets: Set<SceneDynamicTarget>
    private let scalarMediaTargets: Set<SceneDynamicTarget>
    private var pendingInitializations: [(registration: SceneScriptMediaOwnerRegistration,
        owner: SceneScriptValueOwner, properties: [String: SceneScriptPropertyInput])]

    init(
        vectorProgram: SceneScriptVectorProgram,
        stringProgram: SceneScriptStringProgram,
        scalarProgram: SceneScriptScalarProgram
    ) {
        self.vectorProgram = vectorProgram
        self.stringProgram = stringProgram
        self.scalarProgram = scalarProgram
        pendingInitializations = (vectorProgram.initializationOwners
            + stringProgram.initializationOwners + scalarProgram.initializationOwners).sorted {
            if $0.registration.authoredOrdinal != $1.registration.authoredOrdinal {
                return $0.registration.authoredOrdinal < $1.registration.authoredOrdinal
            }
            return $0.registration.family.rawValue < $1.registration.family.rawValue
        }
        registrations = (
            vectorProgram.mediaOwnerRegistrations
                + stringProgram.mediaOwnerRegistrations
                + scalarProgram.mediaOwnerRegistrations
        ).sorted {
            if $0.authoredOrdinal != $1.authoredOrdinal {
                return $0.authoredOrdinal < $1.authoredOrdinal
            }
            return $0.family.rawValue < $1.family.rawValue
        }
        vectorMediaTargets = Set(registrations.compactMap {
            $0.family == .vector ? $0.target : nil
        })
        stringMediaTargets = Set(registrations.compactMap {
            $0.family == .string ? $0.target : nil
        })
        scalarMediaTargets = Set(registrations.compactMap {
            $0.family == .scalar ? $0.target : nil
        })
    }

    /// The work index is prepared once; C owns provisional/committed init state.
    /// Keep successful entries until the existing owner transaction finalizes.
    func initialize(
        vectorInputs: [SceneDynamicTarget: SceneDynamicValue],
        stringInputs: [SceneDynamicTarget: SceneDynamicValue],
        scalarInputs: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frame: SceneScriptFrameInput, userPropertiesJSON: String,
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> (failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure], effects: [SceneScriptOwnerEffects]) {
        var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
        var effects: [SceneScriptOwnerEffects] = []
        for entry in pendingInitializations where entry.owner.needsInitialization {
            let target = entry.registration.target
            let inputs: [SceneDynamicTarget: SceneDynamicValue]
            switch entry.registration.family {
            case .vector: inputs = vectorInputs
            case .string: inputs = stringInputs
            case .scalar: inputs = scalarInputs
            }
            guard let input = inputs[target], let properties = SceneScriptPropertyInputCodec
                .scriptPropertiesJSON(entry.properties, effectiveValues: effectivePropertyValues) else { continue }
            let audio = entry.owner.hasAudioRegistration ? entry.owner.refreshAudio(audioSpectrum) : .success(())
            let result = audio.flatMap { _ in
                entry.owner.initializeIfNeeded(input: input, frame: frame,
                    scriptPropertiesJSON: properties, userPropertiesJSON: userPropertiesJSON,
                    expectedGeneration: entry.owner.generation, interruptBudget: nil,
                    retainsValueForNextUpdate: true)
            }
            switch result {
            case let .success(value):
                if let value {
                    var effect = SceneScriptOwnerEffects(ownerTarget: target, sourceLayerID: target == .camera(.origin) ? entry.owner.layerID : nil,
                        materialFunctionMutations: [], animationMutations: [], layerMutations: [], mediaPlaybackCommands: [])
                    effect.append(value)
                    if !effect.isEmpty { effects.append(effect) }
                }
            case let .failure(failure):
                failures[target] = failure
                if failure.permanentlyDisablesOwner {
                    switch entry.registration.family {
                    case .vector: vectorProgram.disableFailedInitialization(target)
                    case .string: stringProgram.disableFailedInitialization(target)
                    case .scalar: scalarProgram.disableFailedInitialization(target)
                    }
                }
            }
        }
        if !failures.isEmpty {
            pendingInitializations.removeAll { failures[$0.registration.target]?.permanentlyDisablesOwner == true }
        }
        return (failures, effects)
    }

    func finalizeInitializations() {
        pendingInitializations.removeAll { entry in
            if !entry.owner.needsInitialization { return true }
            switch entry.registration.family {
            case .vector: return vectorProgram.disabledTargets.contains(entry.registration.target)
            case .string: return stringProgram.disabledTargets.contains(entry.registration.target)
            case .scalar: return scalarProgram.disabledTargets.contains(entry.registration.target)
            }
        }
    }

    func evaluate(
        vectorInputs: [SceneDynamicTarget: SceneDynamicValue],
        stringInputs: [SceneDynamicTarget: SceneDynamicValue],
        scalarInputs: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        propertyRevision: UInt64? = nil,
        events: SceneScriptMediaFrameEvents,
        audioSpectrum: SceneAudioSpectrumSnapshot,
        initializationFailures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    ) -> SceneScriptMediaFrameCoordinatorResult {
        var vector = VectorAccumulator()
        var string = StringAccumulator()
        var scalar = ScalarAccumulator()
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        var mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand] = []
        var ownerEffects: [SceneScriptOwnerEffects] = []
        let failedInitializations = Set(initializationFailures.keys)
        for (target, failure) in initializationFailures {
            if vectorProgram.inputTargets.contains(target) { vector.failures[target] = failure }
            if stringProgram.inputTargets.contains(target) { string.failures[target] = failure }
            if scalarProgram.inputTargets.contains(target) { scalar.failures[target] = failure }
        }
        let observedVectorEvents = vectorProgram.observeMediaEvents(events)
        let observedStringEvents = stringProgram.observeMediaEvents(events)
        let observedScalarEvents = scalarProgram.observeMediaEvents(events)
        func appendSideEffects(
            materialFunctions: [SceneScriptMaterialFunctionMutation],
            animations: [SceneTimelinePlaybackMutation],
            layers: [SceneScriptLayerMutation],
            ownedBy effects: [SceneScriptOwnerEffects]
        ) {
            materialFunctionMutations.append(contentsOf: materialFunctions)
            animationMutations.append(contentsOf: animations)
            layerMutations.append(contentsOf: layers)
            ownerEffects.append(contentsOf: effects)
        }
        for registration in registrations where !failedInitializations.contains(registration.target) {
            switch registration.family {
            case .vector:
                let frameResult = vectorProgram.evaluate(
                    inputs: vectorInputs,
                    effectivePropertyValues: effectivePropertyValues,
                    frame: frame,
                    propertyRevision: propertyRevision,
                    targetFilter: registration.target,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    observedMediaEvents: observedVectorEvents,
                    audioSpectrum: audioSpectrum,
                    userPropertiesJSON: userPropertiesJSON
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations,
                    ownedBy: frameResult.ownerEffects
                )
                mediaPlaybackCommands.append(contentsOf: frameResult.mediaPlaybackCommands)
                vector.merge(frameResult)
            case .string:
                let frameResult = stringProgram.evaluate(
                    inputs: stringInputs,
                    effectivePropertyValues: effectivePropertyValues,
                    propertyRevision: propertyRevision,
                    targetFilter: registration.target,
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    preparedCurrentJSON: userPropertiesJSON,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    observedMediaEvents: observedStringEvents,
                    audioSpectrum: audioSpectrum
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations,
                    ownedBy: frameResult.ownerEffects
                )
                string.merge(frameResult)
            case .scalar:
                let frameResult = scalarProgram.evaluate(
                    inputs: scalarInputs,
                    frame: frame,
                    effectivePropertyValues: effectivePropertyValues,
                    propertyRevision: propertyRevision,
                    targetFilter: registration.target,
                    userPropertiesJSON: userPropertiesJSON,
                    preparedCurrentJSON: userPropertiesJSON,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    observedMediaEvents: observedScalarEvents,
                    audioSpectrum: audioSpectrum
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations,
                    ownedBy: frameResult.ownerEffects
                )
                scalar.merge(frameResult)
            }
        }

        let remainingVector = vectorProgram.evaluate(
            inputs: vectorInputs,
            effectivePropertyValues: effectivePropertyValues,
            frame: frame,
            propertyRevision: propertyRevision,
            excludedTargets: failedInitializations.isEmpty ? vectorMediaTargets : vectorMediaTargets.union(failedInitializations),
            observedMediaEvents: observedVectorEvents,
            audioSpectrum: audioSpectrum,
            userPropertiesJSON: userPropertiesJSON
        )
        appendSideEffects(
            materialFunctions: remainingVector.materialFunctionMutations,
            animations: remainingVector.animationMutations,
            layers: remainingVector.layerMutations,
            ownedBy: remainingVector.ownerEffects
        )
        mediaPlaybackCommands.append(contentsOf: remainingVector.mediaPlaybackCommands)
        vector.merge(remainingVector)
        let remainingString = stringProgram.evaluate(
            inputs: stringInputs,
            effectivePropertyValues: effectivePropertyValues,
            propertyRevision: propertyRevision,
            excludedTargets: failedInitializations.isEmpty ? stringMediaTargets : stringMediaTargets.union(failedInitializations),
            frame: frame,
            userPropertiesJSON: userPropertiesJSON,
            preparedCurrentJSON: userPropertiesJSON,
            observedMediaEvents: observedStringEvents,
            audioSpectrum: audioSpectrum
        )
        appendSideEffects(
            materialFunctions: remainingString.materialFunctionMutations,
            animations: remainingString.animationMutations,
            layers: remainingString.layerMutations,
            ownedBy: remainingString.ownerEffects
        )
        string.merge(remainingString)
        let remainingScalar = scalarProgram.evaluate(
            inputs: scalarInputs,
            frame: frame,
            effectivePropertyValues: effectivePropertyValues,
            propertyRevision: propertyRevision,
            excludedTargets: failedInitializations.isEmpty ? scalarMediaTargets : scalarMediaTargets.union(failedInitializations),
            userPropertiesJSON: userPropertiesJSON,
            preparedCurrentJSON: userPropertiesJSON,
            observedMediaEvents: observedScalarEvents,
            audioSpectrum: audioSpectrum
        )
        appendSideEffects(
            materialFunctions: remainingScalar.materialFunctionMutations,
            animations: remainingScalar.animationMutations,
            layers: remainingScalar.layerMutations,
            ownedBy: remainingScalar.ownerEffects
        )
        scalar.merge(remainingScalar)
        return .init(
            vector: vector.result,
            string: string.result,
            scalar: scalar.result,
            materialFunctionMutations: materialFunctionMutations,
            animationMutations: animationMutations,
            layerMutations: layerMutations,
            mediaPlaybackCommands: mediaPlaybackCommands,
            ownerEffects: ownerEffects
        )
    }

}

private nonisolated struct VectorAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []
    var mediaPlaybackCommands: [SceneScriptMediaPlaybackCommand] = []
    var videoCommandTargets: Set<SceneDynamicTarget> = []
    var ownerEffects: [SceneScriptOwnerEffects] = []

    mutating func merge(_ frame: SceneScriptVectorFrameResult) {
        values.merge(frame.values) { _, new in new }
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
        mediaPlaybackCommands.append(contentsOf: frame.mediaPlaybackCommands)
        videoCommandTargets.formUnion(frame.videoCommandTargets)
        ownerEffects.append(contentsOf: frame.ownerEffects)
    }

    var result: SceneScriptVectorFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers,
            mediaPlaybackCommands: mediaPlaybackCommands,
            videoCommandTargets: videoCommandTargets,
            ownerEffects: ownerEffects
        )
    }
}

private nonisolated struct StringAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []
    var ownerEffects: [SceneScriptOwnerEffects] = []

    mutating func merge(_ frame: SceneScriptStringFrameResult) {
        values.merge(frame.values) { _, new in new }
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
        ownerEffects.append(contentsOf: frame.ownerEffects)
    }

    var result: SceneScriptStringFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers,
            ownerEffects: ownerEffects
        )
    }
}

private nonisolated struct ScalarAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var timelineInputTargets: Set<SceneDynamicTarget> = []
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []
    var ownerEffects: [SceneScriptOwnerEffects] = []

    mutating func merge(_ frame: SceneScriptScalarFrameResult) {
        values.merge(frame.values) { _, new in new }
        timelineInputTargets.formUnion(frame.timelineInputTargets)
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
        ownerEffects.append(contentsOf: frame.ownerEffects)
    }

    var result: SceneScriptScalarFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers,
            ownerEffects: ownerEffects,
            timelineInputTargets: timelineInputTargets
        )
    }
}
