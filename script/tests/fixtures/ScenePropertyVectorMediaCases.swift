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
        defer { fixture.retained += [mediaOrigin, passTimeline, passTimelineWithoutTarget, passTimelineWrongWrapper, passTimelineWithProperties, playbackProgram, stringProgram, orderedDomain, orderedVector, orderedString, orderedScalar, orderedCoordinator] }
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
