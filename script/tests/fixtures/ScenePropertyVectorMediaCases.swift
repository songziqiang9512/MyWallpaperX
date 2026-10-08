import Foundation

extension Harness {
    static func mediaCases(_ fixture: PropertyVectorFixture) throws -> PropertyVectorObservations {
        let descriptor = fixture.descriptor
        let domain = fixture.domain
        let frame = fixture.frame
        let animatedAlphaTarget = SceneDynamicTarget.layer(layerID: 10, field: .alpha)
        let animatedOriginTarget = SceneDynamicTarget.layer(layerID: 10, field: .origin)
        let mediaOrigin = SceneScriptVectorProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [binding(
                key: "origin", source: mediaAnimationSource, value: "20 2250 0",
                properties: [:],
                wrapperKeys: ["animation", "script", "value"]
            )],
            userPropertyDefinitions: [],
            timelineTargets: [animatedOriginTarget],
            generation: 15
        )
        let mediaEvent = SceneScriptMediaThumbnailEventInput(
            hasThumbnail: true,
            generation: 8
        )
        let mediaOriginResult = mediaOrigin.evaluate(
            inputs: [animatedOriginTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: [:], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let duplicateMediaOriginResult = mediaOrigin.evaluate(
            inputs: [animatedOriginTarget: .vector3(20, 2250, 0)],
            effectivePropertyValues: [:], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let passTimelineTarget = SceneDynamicTarget.effectConstant(
            layerID: 10,
            effectIndex: 0,
            passIndex: 0,
            name: "unseenTimelineScalar"
        )
        let passTimeline = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 151
        )
        let passTimelineResult = passTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.4)],
            frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let passTimelineDuplicate = passTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)],
            frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        let cachedSource = """
        let animation;
        export function init(value){animation=thisObject.getAnimation();return value;}
        export function mediaThumbnailChanged(event){animation.stop();animation.play();}
        """
        func timelineDescriptor(_ source: String) -> SceneRenderDescriptor {
            .init(layers: [.init(id: 10, layerIndex: 0, name: "anchor", visible: true,
                originXYZ: [20, 2250, 0], scaleXYZ: [1.5, 1.5, 1.5],
                scaleHasScript: nil, alpha: 0.75,
                effects: [.init(name: "history", effectID: 100, passes: [.init(
                    passIndex: 0, id: 200, constantShaderValues: [
                        "unseenTimelineScalar": .init(scriptSource: source, components: [1])
                    ])])])])
        }
        let cachedTimeline = SceneScriptScalarProgram.compile(
            domain: domain, descriptor: timelineDescriptor(cachedSource),
            scriptBindings: [passBinding(key: "unseenTimelineScalar",
                source: cachedSource, value: 1, wrapperKeys: ["animation", "script", "value"])],
            timelineTargets: [passTimelineTarget], generation: 156
        )
        let cachedFirst = cachedTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.4)], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        // Reject the real Swift bundle; consumed media input is not replayed,
        // while the property capability survives the next event generation.
        cachedTimeline.finalizeLayerMutations(committing: false)
        let cachedDuplicate = cachedTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        cachedTimeline.finalizeLayerMutations(committing: true)
        let passTimelineNext = cachedTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)], frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 9)
        )
        cachedTimeline.finalizeLayerMutations(committing: true)
        let cachedIdle = [0.55, 0.25].map { input in
            let result = cachedTimeline.evaluate(
                inputs: [passTimelineTarget: .scalar(input)], frame: frame
            )
            cachedTimeline.finalizeLayerMutations(committing: true)
            return result
        }
        func valuePipeline(_ source: String, generation: UInt64) -> SceneScriptScalarProgram {
            SceneScriptScalarProgram.compile(
                domain: domain, descriptor: timelineDescriptor(source),
                scriptBindings: [passBinding(key: "unseenTimelineScalar", source: source,
                    value: 1, wrapperKeys: ["animation", "script", "value"])],
                timelineTargets: [passTimelineTarget], generation: generation
            )
        }
        let changedInit = valuePipeline(cachedSource.replacingOccurrences(
            of: "return value;", with: "return value * 0.5;"
        ), generation: 157)
        let changedInitFirst = changedInit.evaluate(
            inputs: [passTimelineTarget: .scalar(0.4)], frame: frame
        )
        changedInit.finalizeLayerMutations(committing: true)
        let changedInitIdle = changedInit.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)], frame: frame
        )
        changedInit.finalizeLayerMutations(committing: true)
        let transforming = valuePipeline(cachedSource + "\nexport function update(value){return value*0.5;}",
            generation: 158)
        let transformed = transforming.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)], frame: frame
        )
        transforming.finalizeLayerMutations(committing: true)
        let overlay = valuePipeline(cachedSource.replacingOccurrences(
            of: "return value;", with: "thisObject.unseenTimelineScalar=0.7;return value;"
        ), generation: 159)
        _ = overlay.evaluate(inputs: [passTimelineTarget: .scalar(0.4)], frame: frame)
        overlay.finalizeLayerMutations(committing: true)
        let overlayIdle = overlay.evaluate(inputs: [passTimelineTarget: .scalar(0.6)], frame: frame)
        overlay.finalizeLayerMutations(committing: true)
        let staleIdle = overlay.bindings.first?.scalarValueWithoutUpdate(input: 0.6, expectedGeneration: 160)
        let retiringDomain = try SceneScriptQuickJSDomain()
        try retiringDomain.configureLayerCatalog(timelineDescriptor(cachedSource))
        let retiring = SceneScriptScalarProgram.compile(
            domain: retiringDomain,
            descriptor: timelineDescriptor(cachedSource),
            scriptBindings: [passBinding(key: "unseenTimelineScalar", source: cachedSource,
                value: 1, wrapperKeys: ["animation", "script", "value"])],
            timelineTargets: [passTimelineTarget], generation: 160
        )
        _ = retiring.evaluate(inputs: [passTimelineTarget: .scalar(0.4)], frame: frame)
        retiring.finalizeLayerMutations(committing: true)
        let retirement = retiring.retire(layerIDs: [10], frame: frame, userPropertiesJSON: "{}")
        let retiredIdle = retiring.evaluate(inputs: [passTimelineTarget: .scalar(0.6)], frame: frame)
        let repeatedRetirement = retiring.retire(layerIDs: [10], frame: frame, userPropertiesJSON: "{}")
        let invalidatingDomain = try SceneScriptQuickJSDomain()
        try invalidatingDomain.configureLayerCatalog(timelineDescriptor(cachedSource))
        let invalidating = SceneScriptScalarProgram.compile(
            domain: invalidatingDomain, descriptor: timelineDescriptor(cachedSource),
            scriptBindings: [alphaBinding(source: cachedSource, value: 0.75)],
            timelineTargets: [animatedAlphaTarget], generation: 161
        )
        let beforeInvalidation = invalidating.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.4)], frame: frame
        )
        invalidating.finalizeLayerMutations(committing: true)
        let oldTimerState = invalidating.timerFrameStateSnapshot()
        invalidating.invalidate()
        let invalidatedIdle = invalidating.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.6)], frame: frame
        )
        invalidating.restoreTimerFrameState(oldTimerState)
        invalidating.discardTimerFrameState(oldTimerState)
        let restoredInvalidatedIdle = invalidating.evaluate(
            inputs: [animatedAlphaTarget: .scalar(0.7)], frame: frame
        )
        let throwingSource = cachedSource.replacingOccurrences(
            of: "animation.play();", with: "animation.play(); throw new Error('late');"
        )
        let throwingTimeline = SceneScriptScalarProgram.compile(
            domain: domain, descriptor: timelineDescriptor(throwingSource),
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: throwingSource, value: 1, wrapperKeys: ["animation", "script", "value"]
            )], timelineTargets: [passTimelineTarget], generation: 155
        )
        let throwingTimelineResult = throwingTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.4)], frame: frame,
            mediaThumbnailEvent: mediaEvent
        )
        throwingTimeline.finalizeLayerMutations(committing: false)
        let throwingIdle = throwingTimeline.evaluate(
            inputs: [passTimelineTarget: .scalar(0.6)], frame: frame
        )
        let passTimelineWithoutTarget = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"]
            )],
            generation: 152
        )
        let passTimelineWrongWrapper = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "extra", "script", "value"]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 153
        )
        let passTimelineWithProperties = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "unseenTimelineScalar",
                source: mediaAnimationSource,
                value: 1,
                wrapperKeys: ["animation", "script", "value"],
                properties: ["unexpected": .number(1)]
            )],
            timelineTargets: [passTimelineTarget],
            generation: 154
        )
        let playbackTarget = SceneDynamicTarget.effectConstant(
            layerID: 10, effectIndex: 0, passIndex: 0, name: "alpha"
        )
        let playbackProgram = SceneScriptScalarProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [passBinding(
                key: "alpha", source: mediaPlaybackSource, value: 1
            )],
            generation: 16
        )
        let playbackFrame = SceneScriptFrameInput(timing: .init(
            wallDate: Date(timeIntervalSince1970: 0),
            simulationFrameTime: 0.25,
            sceneTime: 2
        ), timeZone: TimeZone(secondsFromGMT: 0)!)
        let playing = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let playingNextFrame = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 1, generation: 1)
        )
        let stopped = playbackProgram.evaluate(
            inputs: [playbackTarget: .scalar(1)], frame: playbackFrame,
            mediaPlaybackEvent: .init(state: 0, generation: 2)
        )
        let stringTarget = SceneDynamicTarget.text(
            layerID: 77, field: .content
        )
        let stringProgram = SceneScriptStringProgram.compile(
            domain: domain,
            descriptor: descriptor,
            scriptBindings: [textBinding(
                source: mediaPropertiesSource,
                value: "Placeholder"
            )],
            generation: 17
        )
        let stringEvent = SceneScriptMediaPropertiesEventInput(
            title: "春日歌", artist: "Artist", subTitle: "Live",
            albumTitle: "Album", albumArtist: "Album Artist",
            genres: "Rock,Pop", contentType: "music", generation: 1
        )
        let stringResult = stringProgram.evaluate(
            inputs: [stringTarget: .string("Placeholder")],
            frame: frame,
            mediaPropertiesEvent: stringEvent
        )
        let duplicateStringResult = stringProgram.evaluate(
            inputs: [stringTarget: .string("Placeholder")],
            frame: frame,
            mediaPropertiesEvent: stringEvent
        )
        let orderedDomain = try SceneScriptQuickJSDomain()
        var orderedDescriptor = descriptor
        orderedDescriptor.layers[2].textScript = .init(
            source: orderedStringMediaSource
        )
        let orderedBindings = [
            alphaBinding(
                source: orderedScalarMediaSource, value: 0.75,
                wrapperKeys: ["script", "value"]
            ),
            binding(
                key: "origin", source: orderedVectorMediaSource,
                value: "10 20 30", properties: [:],
                objectIndex: 1, objectID: 42,
                wrapperKeys: ["script", "value"]
            ),
            textBinding(source: orderedStringMediaSource, value: "Placeholder"),
        ]
        let orderedVector = SceneScriptVectorProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings,
            userPropertyDefinitions: [], generation: 18
        )
        let orderedString = SceneScriptStringProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings, generation: 18
        )
        let orderedScalar = SceneScriptScalarProgram.compile(
            domain: orderedDomain, descriptor: orderedDescriptor,
            scriptBindings: orderedBindings, generation: 18
        )
        let orderedEvents = SceneScriptMediaFrameEvents(
            playback: .init(state: 1, generation: 1),
            properties: stringEvent,
            thumbnail: .init(hasThumbnail: true, generation: 1),
            timeline: .init(position: 12.5, duration: 90, generation: 1)
        )
        let orderedCoordinator = SceneScriptMediaFrameCoordinator(
            vectorProgram: orderedVector,
            stringProgram: orderedString,
            scalarProgram: orderedScalar
        )
        let orderedResult = orderedCoordinator.evaluate(
            vectorInputs: [
                .layer(layerID: 42, field: .origin): .vector3(10, 20, 30)
            ],
            stringInputs: [stringTarget: .string("Placeholder")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.75)],
            effectivePropertyValues: [:], frame: frame,
            userPropertiesJSON: "{}", events: orderedEvents,
            audioSpectrum: .silent
        )
        let orderedDuplicate = orderedCoordinator.evaluate(
            vectorInputs: [
                .layer(layerID: 42, field: .origin): .vector3(10, 20, 30)
            ],
            stringInputs: [stringTarget: .string("Placeholder")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.75)],
            effectivePropertyValues: [:], frame: frame,
            userPropertiesJSON: "{}", events: orderedEvents,
            audioSpectrum: .silent
        )
        let orderedNextGeneration = orderedCoordinator.evaluate(
            vectorInputs: [.layer(layerID: 42, field: .origin): .vector3(40, 50, 60)],
            stringInputs: [stringTarget: .string("Changed input")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.3)],
            effectivePropertyValues: [:], frame: playbackFrame,
            userPropertiesJSON: "{}",
            events: .init(
                playback: .init(state: 0, generation: 2),
                properties: stringEvent,
                thumbnail: .init(hasThumbnail: false, generation: 2),
                timeline: .init(position: 20, duration: 100, generation: 2)
            ),
            audioSpectrum: .silent
        )
        orderedVector.invalidate()
        orderedString.invalidate()
        orderedScalar.invalidate()
        let orderedInvalidated = orderedCoordinator.evaluate(
            vectorInputs: [.layer(layerID: 42, field: .origin): .vector3(70, 80, 90)],
            stringInputs: [stringTarget: .string("Stale owner")],
            scalarInputs: [animatedAlphaTarget: .scalar(0.9)],
            effectivePropertyValues: [:], frame: playbackFrame,
            userPropertiesJSON: "{}", events: orderedEvents,
            audioSpectrum: .silent
        )
        defer { fixture.retained += [mediaOrigin, passTimeline, cachedTimeline, changedInit, transforming, overlay, retiring, invalidating, throwingTimeline, passTimelineWithoutTarget, passTimelineWrongWrapper, passTimelineWithProperties, playbackProgram, stringProgram, orderedDomain, orderedVector, orderedString, orderedScalar, orderedCoordinator] }
        return [
            "mediaAnimationCommands": { mediaOriginResult.animationMutations.map {
                $0.command.rawValue
            } },
            "mediaGenerationDeduplicated": {
                duplicateMediaOriginResult.animationMutations.isEmpty },
            "passTimelineBindings": { passTimeline.bindings.count },
            "passTimelineKeepsTimelineValueOwner": {
                passTimelineResult.values[passTimelineTarget] == nil },
            "passTimelineCommands": { passTimelineResult.animationMutations.map {
                $0.command.rawValue
            } },
            "passTimelineGenerationDeduplicated": {
                passTimelineDuplicate.animationMutations.isEmpty },
            "passTimelineAfterRejection": {
                ["firstFailures": cachedFirst.failures.count,
                 "firstCommands": cachedFirst.animationMutations.map { $0.command.rawValue },
                 "firstValue": String(describing: cachedFirst.values[passTimelineTarget]),
                 "duplicateCommands": cachedDuplicate.animationMutations.map { $0.command.rawValue },
                 "idleValues": cachedIdle.map { scalar($0.values[passTimelineTarget]) },
                 "idleEffectsEmpty": cachedIdle.allSatisfy { $0.ownerEffects.isEmpty && $0.animationMutations.isEmpty },
                 "idleSource": SceneDynamicSnapshotResolver().resolve(
                    frameIndex: 1, generation: 1, definitions: cachedTimeline.definitions,
                    timelineValues: [passTimelineTarget: .scalar(0.55)],
                    sceneScriptValues: cachedIdle[0].values).snapshot[passTimelineTarget]?.source.rawValue ?? "missing",
                 "changedInitFirst": scalar(changedInitFirst.values[passTimelineTarget]),
                 "changedInitIdle": scalar(changedInitIdle.values[passTimelineTarget]),
                 "updateTransform": scalar(transformed.values[passTimelineTarget]),
                 "boundOverlayIdle": scalar(overlayIdle.values[passTimelineTarget]),
                 "staleIdleRejected": { if case .failure(.staleOwner)? = staleIdle { return true }; return false }(),
                 "retiredIdleUnpublished": retirement.count == 1 && repeatedRetirement.isEmpty && retiredIdle.values.isEmpty,
                 "retirementCounts": [retiring.bindings.count, retirement.count, repeatedRetirement.count, retiredIdle.values.count],
                 "invalidatingBindings": invalidating.bindings.count,
                 "beforeInvalidation": scalar(beforeInvalidation.values[animatedAlphaTarget]),
                 "invalidatedIdleUnpublished": invalidatedIdle.values.isEmpty && restoredInvalidatedIdle.values.isEmpty,
                 "invalidatedIdleValues": [scalar(invalidatedIdle.values[animatedAlphaTarget]), scalar(restoredInvalidatedIdle.values[animatedAlphaTarget])],
                 "nextFailures": passTimelineNext.failures.count,
                 "nextCommands": passTimelineNext.animationMutations.map { $0.command.rawValue }] as [String: Any] },
            "passTimelineThrowUnpublished": {
                !throwingTimelineResult.failures.isEmpty && throwingTimelineResult.animationMutations.isEmpty
                    && throwingTimelineResult.ownerEffects.isEmpty && throwingIdle.values.isEmpty },
            "passTimelineWithoutTargetRejected": {
                passTimelineWithoutTarget.bindings.isEmpty },
            "passTimelineWrongWrapperRejected": {
                passTimelineWrongWrapper.bindings.isEmpty },
            "passTimelinePropertiesRejected": {
                passTimelineWithProperties.bindings.isEmpty },
            "playbackBindings": { playbackProgram.bindings.count },
            "playbackPlaying": { scalar(playing.values[playbackTarget]) },
            "playbackNextFrame": { scalar(playingNextFrame.values[playbackTarget]) },
            "playbackStopped": { scalar(stopped.values[playbackTarget]) },
            "playbackFailures": { playing.failures.count
                + playingNextFrame.failures.count + stopped.failures.count },
            "stringBindings": { stringProgram.bindings.count },
            "stringValue": { string(stringResult.values[stringTarget]) },
            "stringFailures": { stringResult.failures.count },
            "stringGenerationDeduplicated": {
                string(duplicateStringResult.values[stringTarget]) ==
                    "春日歌 / Artist / Live / Album / Album Artist / Rock,Pop / music" },
            "orderedMediaTrace": { string(orderedResult.string.values[stringTarget]) },
            "orderedMediaDuplicateTrace": {
                string(orderedDuplicate.string.values[stringTarget]) },
            "orderedMediaFailures": { orderedResult.vector.failures.count
                + orderedResult.string.failures.count
                + orderedResult.scalar.failures.count },
            "orderedLayerMutationOrder": { orderedResult.layerMutations.map(\.layerID) },
            "orderedLayerMutationFields": { orderedResult.layerMutations.map {
                $0.fields == [.visibility] && !$0.visible
            } },
            "orderedDuplicateLayerMutations": { orderedDuplicate.layerMutations.count },
            "orderedNextGenerationTrace": {
                string(orderedNextGeneration.string.values[stringTarget]) },
            "orderedNextGenerationVector": { vector(orderedNextGeneration.vector.values[
                .layer(layerID: 42, field: .origin)
            ]) },
            "orderedNextGenerationScalar": { scalar(orderedNextGeneration.scalar.values[
                animatedAlphaTarget
            ]) },
            "orderedNextGenerationLayerMutations": { orderedNextGeneration.layerMutations.count },
            "orderedInvalidatedValues": { orderedInvalidated.vector.values.count
                + orderedInvalidated.string.values.count
                + orderedInvalidated.scalar.values.count },
            "orderedInvalidatedFailures": { orderedInvalidated.vector.failures.count
                + orderedInvalidated.string.failures.count
                + orderedInvalidated.scalar.failures.count },
            "orderedInvalidatedLayerMutations": { orderedInvalidated.layerMutations.count },
        ]
    }
}
