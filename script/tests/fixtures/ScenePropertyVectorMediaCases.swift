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
        let eventPipeline = valuePipeline(cachedSource, generation: 162)
        _ = eventPipeline.evaluate(inputs: [passTimelineTarget: .scalar(1)], frame: frame)
        eventPipeline.finalizeLayerMutations(committing: true)
        let eventAnimation = SceneTimelineAnimation(
            lanes: [[
                .init(frame: 0, value: 1, back: nil, front: nil, locksAngle: nil, locksLength: nil),
                .init(frame: 1, value: 0, back: nil, front: nil, locksAngle: nil, locksLength: nil)
            ]],
            options: .init(fps: 1, length: 1, mode: .single, startsPaused: true,
                wrapsLoop: false, smoothing: nil, stiffness: nil, parent: nil, children: []),
            isRelative: false, previewValue: nil
        )
        let peerTimelineTarget = SceneDynamicTarget.layer(layerID: 42, field: .alpha)
        let eventRuntime = SceneTimelinePlaybackRuntime(program: .init(bindings: [
            .init(definition: eventPipeline.definitions[0], animation: eventAnimation, composition: .absolute),
            .init(definition: .init(target: peerTimelineTarget, valueType: .scalar, authoredValue: .scalar(1)),
                animation: eventAnimation, composition: .absolute)
        ], diagnostics: []))
        _ = try eventRuntime.apply([.init(target: passTimelineTarget, command: .play)], sceneTime: 0).get()
        let oldEventInput = eventRuntime.values(sceneTime: 2)
        let eventResult = eventPipeline.evaluate(inputs: oldEventInput, frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
        let eventPreview = try eventRuntime.preview(eventResult.animationMutations, sceneTime: 2).get()
        let eventResolution = SceneDynamicSnapshotResolver().resolve(
            frameIndex: 1, generation: 1, definitions: eventPipeline.definitions,
            timelineValues: eventPreview, sceneScriptValues: eventResult.valuesForAdmission(
                timelineValues: eventPreview, excluding: [])
        )
        let foreignPreview = try eventRuntime.preview([
            .init(target: peerTimelineTarget, command: .stop),
            .init(target: peerTimelineTarget, command: .play)
        ], sceneTime: 2).get()
        let foreignProjection = eventResult.valuesForAdmission(timelineValues: foreignPreview, excluding: [])
        let rejectedProjection = eventResult.valuesForAdmission(timelineValues: eventPreview, excluding: [passTimelineTarget])
        let noCommandProjection = eventResult.valuesForAdmission(
            timelineValues: try eventRuntime.preview([], sceneTime: 2).get(), excluding: [])
        let eventBeforeCommit = eventRuntime.values(sceneTime: 2)
        eventPipeline.finalizeLayerMutations(committing: true)
        _ = try eventRuntime.apply(eventResult.animationMutations, sceneTime: 2).get()
        let eventNextFrame = eventRuntime.values(sceneTime: 2.25)
        let eventIdle = eventPipeline.evaluate(inputs: eventNextFrame, frame: frame)
        eventPipeline.finalizeLayerMutations(committing: true)
        let emptyVector = SceneScriptVectorProgram.compile(domain: domain,
            descriptor: descriptor, scriptBindings: [], userPropertyDefinitions: [], generation: 162)
        let emptyString = SceneScriptStringProgram.compile(domain: domain,
            descriptor: descriptor, scriptBindings: [], generation: 162)
        let eventCoordinator = SceneScriptMediaFrameCoordinator(vectorProgram: emptyVector,
            stringProgram: emptyString, scalarProgram: eventPipeline)
        let coordinatedEvent = eventCoordinator.evaluate(vectorInputs: [:], stringInputs: [:],
            scalarInputs: [passTimelineTarget: .scalar(0)], effectivePropertyValues: [:], frame: frame,
            userPropertiesJSON: "{}", events: .init(playback: nil, properties: nil,
                thumbnail: .init(hasThumbnail: true, generation: 2), timeline: nil), audioSpectrum: .silent)
        let coordinatedPreview = try eventRuntime.preview(coordinatedEvent.animationMutations, sceneTime: 3).get()
        let coordinatedValue = coordinatedEvent.scalar.valuesForAdmission(timelineValues: coordinatedPreview, excluding: [])
        eventPipeline.finalizeLayerMutations(committing: false)
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
        let equalInit = valuePipeline(cachedSource, generation: 167)
        let equalInitEvent = equalInit.evaluate(inputs: [passTimelineTarget: .scalar(0)], frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
        equalInit.finalizeLayerMutations(committing: true)
        let equalUpdate = valuePipeline(cachedSource + "\nexport function update(value){return value;}", generation: 168)
        _ = equalUpdate.evaluate(inputs: [passTimelineTarget: .scalar(1)], frame: frame)
        equalUpdate.finalizeLayerMutations(committing: true)
        let equalUpdateEvent = equalUpdate.evaluate(inputs: [passTimelineTarget: .scalar(0)], frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
        equalUpdate.finalizeLayerMutations(committing: true)
        let overlay = valuePipeline(cachedSource.replacingOccurrences(
            of: "return value;", with: "thisObject.unseenTimelineScalar=0.7;return value;"
        ), generation: 159)
        _ = overlay.evaluate(inputs: [passTimelineTarget: .scalar(0.4)], frame: frame)
        overlay.finalizeLayerMutations(committing: true)
        let overlayIdle = overlay.evaluate(inputs: [passTimelineTarget: .scalar(0.6)], frame: frame)
        overlay.finalizeLayerMutations(committing: true)
        let equalOverlay = valuePipeline(cachedSource.replacingOccurrences(
            of: "return value;", with: "thisObject.unseenTimelineScalar=0;return value;"
        ), generation: 163)
        _ = equalOverlay.evaluate(inputs: [passTimelineTarget: .scalar(1)], frame: frame)
        equalOverlay.finalizeLayerMutations(committing: true)
        let equalOverlayEvent = equalOverlay.evaluate(inputs: [passTimelineTarget: .scalar(0)], frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
        equalOverlay.finalizeLayerMutations(committing: true)
        let pendingInit = valuePipeline(cachedSource.replacingOccurrences(
            of: "return value;", with: "return value * 0.5;"
        ), generation: 164)
        _ = try pendingInit.bindings[0].initializeIfNeeded(input: .scalar(0.6), frame: frame,
            scriptPropertiesJSON: "", userPropertiesJSON: "{}", expectedGeneration: 164,
            interruptBudget: nil, retainsValueForNextUpdate: true).get()
        pendingInit.finalizeLayerMutations(committing: true)
        let pendingEvent = pendingInit.evaluate(inputs: [passTimelineTarget: .scalar(0)], frame: frame,
            mediaThumbnailEvent: .init(hasThumbnail: true, generation: 1))
        pendingInit.finalizeLayerMutations(committing: false)
        let pendingRetry = pendingInit.evaluate(inputs: [passTimelineTarget: .scalar(0)], frame: frame)
        pendingInit.finalizeLayerMutations(committing: true)
        func boundedProjection(_ target: SceneDynamicTarget, firstValue: Double,
                               generation: UInt64) throws -> [Double] {
            let owner = try SceneScriptValueOwner(domain: domain,
                source: "export function init(value){return value;}", target: target,
                valueType: .scalar, effectNames: [], hasCurrentAnimation: true,
                generation: generation, budget: .default)
            _ = try owner.evaluate(input: .scalar(1), frame: frame,
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: generation, interruptBudget: nil).get()
            owner.commitLayerMutations()
            let output = try owner.evaluate(input: .scalar(1), frame: frame,
                scriptPropertiesJSON: "", userPropertiesJSON: "{}",
                expectedGeneration: generation, interruptBudget: nil).get()
            let value = SceneScriptScalarFrameResult(values: [target: output.value], failures: [:],
                materialFunctionMutations: [], animationMutations: [], layerMutations: [],
                timelineInputTargets: output.scalarValueFollowsInput ? [target] : [])
            let animation = SceneTimelineAnimation(lanes: [[
                .init(frame: 0, value: firstValue, back: nil, front: nil, locksAngle: nil, locksLength: nil),
                .init(frame: 1, value: 1, back: nil, front: nil, locksAngle: nil, locksLength: nil)
            ]], options: eventAnimation.options, isRelative: false, previewValue: nil)
            let runtime = SceneTimelinePlaybackRuntime(program: .init(bindings: [.init(
                definition: .init(target: target, valueType: .scalar, authoredValue: .scalar(1)),
                animation: animation, composition: .absolute
            )], diagnostics: []))
            let preview = try runtime.preview([.init(target: target, command: .stop)], sceneTime: 2).get()
            let rejected = value.valuesForAdmission(timelineValues: preview, excluding: [])
            let accepted = value.valuesForAdmission(timelineValues: [target: .scalar(2)], excluding: [])
            owner.commitLayerMutations()
            fixture.retained += [owner, runtime]
            return [scalar(preview[target]), scalar(rejected[target]), scalar(accepted[target])]
        }
        let intensityProjection = try boundedProjection(.layer(layerID: 10, field: .intensity),
            firstValue: -1, generation: 165)
        let materialProjection = try boundedProjection(.materialConstant(layerID: 10,
            passIndex: 0, name: "Alpha", materialPath: "materials/fixture.json"),
            firstValue: Double(Float.greatestFiniteMagnitude) * 2, generation: 166)
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
        defer { fixture.retained += [mediaOrigin, passTimeline, cachedTimeline, eventPipeline, eventRuntime, eventCoordinator, changedInit, transforming, equalInit, equalUpdate, overlay, equalOverlay, pendingInit, retiring, invalidating, throwingTimeline, passTimelineWithoutTarget, passTimelineWrongWrapper, passTimelineWithProperties, playbackProgram, stringProgram, orderedDomain, orderedVector, orderedString, orderedScalar, orderedCoordinator] }
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
                 "eventFrame": ["oldInput": scalar(oldEventInput[passTimelineTarget]),
                     "preview": scalar(eventPreview[passTimelineTarget]),
                     "settled": scalar(eventResolution.snapshot[passTimelineTarget]?.value),
                     "source": eventResolution.snapshot[passTimelineTarget]?.source.rawValue ?? "missing",
                     "followsInput": eventResult.timelineInputTargets.contains(passTimelineTarget),
                     "foreignUnchanged": scalar(foreignProjection[passTimelineTarget]) == 0 && foreignProjection[peerTimelineTarget] == nil,
                     "rejectedEmpty": rejectedProjection.isEmpty,
                     "noCommandUnchanged": scalar(noCommandProjection[passTimelineTarget]) == 0,
                     "previewDidNotCommit": scalar(eventBeforeCommit[passTimelineTarget]) == 0,
                     "nextFrame": scalar(eventIdle.values[passTimelineTarget]),
                     "coordinatorSettled": scalar(coordinatedValue[passTimelineTarget]),
                     "activeInit": scalar(changedInitFirst.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "activeUpdate": scalar(transformed.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "equalInit": scalar(equalInitEvent.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "equalUpdate": scalar(equalUpdateEvent.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "overlay": scalar(overlayIdle.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "equalOverlay": scalar(equalOverlayEvent.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "pendingInit": scalar(pendingEvent.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "pendingInitAfterRejection": scalar(pendingRetry.valuesForAdmission(timelineValues: eventPreview, excluding: [])[passTimelineTarget]),
                     "rejectedCommandsNotReplayed": pendingRetry.animationMutations.isEmpty,
                     "intensityProjection": intensityProjection,
                     "materialProjection": materialProjection,
                     "throwUnpublished": throwingTimelineResult.valuesForAdmission(timelineValues: eventPreview, excluding: []).isEmpty] as [String: Any],
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
