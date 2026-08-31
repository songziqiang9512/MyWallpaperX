import Foundation

nonisolated struct SceneScriptMediaFrameCoordinatorResult: Sendable {
    let vector: SceneScriptVectorFrameResult
    let string: SceneScriptStringFrameResult
    let scalar: SceneScriptScalarFrameResult
    let materialFunctionMutations: [SceneScriptMaterialFunctionMutation]
    let animationMutations: [SceneTimelinePlaybackMutation]
    let layerMutations: [SceneScriptLayerMutation]
    let videoCommands: [SceneScriptVideoCommand]
}

/// Executes media-bearing owners through one authored-order view of the
/// existing scalar, String and vector programs. Each program still owns its VM
/// handle, generation watermark and typed publication; this coordinator only
/// removes the old family-order dispatch split.
nonisolated enum SceneScriptMediaFrameCoordinator {
    static func evaluate(
        vectorProgram: SceneScriptVectorProgram,
        stringProgram: SceneScriptStringProgram,
        scalarProgram: SceneScriptScalarProgram,
        vectorInputs: [SceneDynamicTarget: SceneDynamicValue],
        stringInputs: [SceneDynamicTarget: SceneDynamicValue],
        scalarInputs: [SceneDynamicTarget: SceneDynamicValue],
        effectivePropertyValues: [String: SceneUserPropertyValue],
        frame: SceneScriptFrameInput,
        userPropertiesJSON: String,
        events: SceneScriptMediaFrameEvents,
        audioSpectrum: SceneAudioSpectrumSnapshot
    ) -> SceneScriptMediaFrameCoordinatorResult {
        let registrations = (
            vectorProgram.mediaOwnerRegistrations
                + stringProgram.mediaOwnerRegistrations
                + scalarProgram.mediaOwnerRegistrations
        ).sorted {
            if $0.authoredOrdinal != $1.authoredOrdinal {
                return $0.authoredOrdinal < $1.authoredOrdinal
            }
            return $0.family.rawValue < $1.family.rawValue
        }
        let vectorMediaTargets = Set(registrations.compactMap {
            $0.family == .vector ? $0.target : nil
        })
        let stringMediaTargets = Set(registrations.compactMap {
            $0.family == .string ? $0.target : nil
        })
        let scalarMediaTargets = Set(registrations.compactMap {
            $0.family == .scalar ? $0.target : nil
        })

        var vector = VectorAccumulator()
        var string = StringAccumulator()
        var scalar = ScalarAccumulator()
        var materialFunctionMutations: [SceneScriptMaterialFunctionMutation] = []
        var animationMutations: [SceneTimelinePlaybackMutation] = []
        var layerMutations: [SceneScriptLayerMutation] = []
        var videoCommands: [SceneScriptVideoCommand] = []
        func appendSideEffects(
            materialFunctions: [SceneScriptMaterialFunctionMutation],
            animations: [SceneTimelinePlaybackMutation],
            layers: [SceneScriptLayerMutation]
        ) {
            materialFunctionMutations.append(contentsOf: materialFunctions)
            animationMutations.append(contentsOf: animations)
            layerMutations.append(contentsOf: layers)
        }
        for registration in registrations {
            switch registration.family {
            case .vector:
                let frameResult = vectorProgram.evaluate(
                    inputs: input(registration.target, from: vectorInputs),
                    effectivePropertyValues: effectivePropertyValues,
                    frame: frame,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    audioSpectrum: audioSpectrum
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations
                )
                videoCommands.append(contentsOf: frameResult.videoCommands)
                vector.merge(frameResult)
            case .string:
                let frameResult = stringProgram.evaluate(
                    inputs: input(registration.target, from: stringInputs),
                    frame: frame,
                    userPropertiesJSON: userPropertiesJSON,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    audioSpectrum: audioSpectrum
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations
                )
                string.merge(frameResult)
            case .scalar:
                let frameResult = scalarProgram.evaluate(
                    inputs: input(registration.target, from: scalarInputs),
                    frame: frame,
                    effectivePropertyValues: effectivePropertyValues,
                    userPropertiesJSON: userPropertiesJSON,
                    mediaThumbnailEvent: events.thumbnail,
                    mediaPlaybackEvent: events.playback,
                    mediaPropertiesEvent: events.properties,
                    mediaTimelineEvent: events.timeline,
                    audioSpectrum: audioSpectrum
                )
                appendSideEffects(
                    materialFunctions: frameResult.materialFunctionMutations,
                    animations: frameResult.animationMutations,
                    layers: frameResult.layerMutations
                )
                scalar.merge(frameResult)
            }
        }

        let remainingVector = vectorProgram.evaluate(
            inputs: vectorInputs.filter { !vectorMediaTargets.contains($0.key) },
            effectivePropertyValues: effectivePropertyValues,
            frame: frame,
            audioSpectrum: audioSpectrum
        )
        appendSideEffects(
            materialFunctions: remainingVector.materialFunctionMutations,
            animations: remainingVector.animationMutations,
            layers: remainingVector.layerMutations
        )
        videoCommands.append(contentsOf: remainingVector.videoCommands)
        vector.merge(remainingVector)
        let remainingString = stringProgram.evaluate(
            inputs: stringInputs.filter { !stringMediaTargets.contains($0.key) },
            frame: frame,
            userPropertiesJSON: userPropertiesJSON,
            audioSpectrum: audioSpectrum
        )
        appendSideEffects(
            materialFunctions: remainingString.materialFunctionMutations,
            animations: remainingString.animationMutations,
            layers: remainingString.layerMutations
        )
        string.merge(remainingString)
        let remainingScalar = scalarProgram.evaluate(
            inputs: scalarInputs.filter { !scalarMediaTargets.contains($0.key) },
            frame: frame,
            effectivePropertyValues: effectivePropertyValues,
            userPropertiesJSON: userPropertiesJSON,
            audioSpectrum: audioSpectrum
        )
        appendSideEffects(
            materialFunctions: remainingScalar.materialFunctionMutations,
            animations: remainingScalar.animationMutations,
            layers: remainingScalar.layerMutations
        )
        scalar.merge(remainingScalar)
        return .init(
            vector: vector.result,
            string: string.result,
            scalar: scalar.result,
            materialFunctionMutations: materialFunctionMutations,
            animationMutations: animationMutations,
            layerMutations: layerMutations,
            videoCommands: videoCommands
        )
    }

    private static func input(
        _ target: SceneDynamicTarget,
        from inputs: [SceneDynamicTarget: SceneDynamicValue]
    ) -> [SceneDynamicTarget: SceneDynamicValue] {
        inputs[target].map { [target: $0] } ?? [:]
    }
}

private nonisolated struct VectorAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []
    var videoCommands: [SceneScriptVideoCommand] = []
    var videoCommandTargets: Set<SceneDynamicTarget> = []

    mutating func merge(_ frame: SceneScriptVectorFrameResult) {
        values.merge(frame.values) { _, new in new }
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
        videoCommands.append(contentsOf: frame.videoCommands)
        videoCommandTargets.formUnion(frame.videoCommandTargets)
    }

    var result: SceneScriptVectorFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers,
            videoCommands: videoCommands,
            videoCommandTargets: videoCommandTargets
        )
    }
}

private nonisolated struct StringAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []

    mutating func merge(_ frame: SceneScriptStringFrameResult) {
        values.merge(frame.values) { _, new in new }
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
    }

    var result: SceneScriptStringFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers
        )
    }
}

private nonisolated struct ScalarAccumulator {
    var values: [SceneDynamicTarget: SceneDynamicValue] = [:]
    var failures: [SceneDynamicTarget: SceneScriptScalarRuntimeFailure] = [:]
    var materialFunctions: [SceneScriptMaterialFunctionMutation] = []
    var animations: [SceneTimelinePlaybackMutation] = []
    var layers: [SceneScriptLayerMutation] = []

    mutating func merge(_ frame: SceneScriptScalarFrameResult) {
        values.merge(frame.values) { _, new in new }
        failures.merge(frame.failures) { _, new in new }
        materialFunctions.append(contentsOf: frame.materialFunctionMutations)
        animations.append(contentsOf: frame.animationMutations)
        layers.append(contentsOf: frame.layerMutations)
    }

    var result: SceneScriptScalarFrameResult {
        .init(
            values: values,
            failures: failures,
            materialFunctionMutations: materialFunctions,
            animationMutations: animations,
            layerMutations: layers
        )
    }
}
