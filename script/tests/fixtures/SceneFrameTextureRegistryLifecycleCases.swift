extension Harness {
    static func environmentPublication(_ device: MTLDevice) -> [String: Bool] {
        func texture(_ levels: Int, format: MTLPixelFormat = .rgba16Float, usage: MTLTextureUsage = [.shaderRead, .renderTarget]) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 13, height: 7, mipmapped: true)
            d.mipmapLevelCount = levels; d.usage = usage
            return device.makeTexture(descriptor: d)!
        }
        let full = texture(4)
        // This is a publication-unit fixture identity, not a claim that a
        // submission owner produced this texture. Owner receipts are exercised
        // by test_scene_persistent_color_output's actual completion chain.
        let source = SceneCompletedColorSourceIdentity(frameIndex: 41, frameEpoch: 5,
            executionEpoch: 2,
            commandBufferObservationID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            allocationGeneration: 9,
            resetEpoch: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let otherProducer = SceneCompletedColorSourceIdentity(frameIndex: source.frameIndex,
            frameEpoch: source.frameEpoch, executionEpoch: source.executionEpoch,
            commandBufferObservationID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            allocationGeneration: source.allocationGeneration, resetEpoch: source.resetEpoch)
        let first = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 3, texture: full, source: source)!
        let second = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 8, allocationGeneration: 3, texture: full, source: source)!
        let replacement = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 4, texture: full, source: source)!
        let changedProducer = SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 3, texture: full, source: otherProducer)!
        let candidate = first.publication.candidate
        return [
            "environmentExactAtom": first.publication.isComplete && first.resourceGeneration == 3
                && first.publication.requestIdentity == .sceneEnvironment && first.publication.contentGeneration == 7
                && candidate.texture === full && candidate.identity == .provider(.sceneEnvironment(frameEpoch: 7, allocationGeneration: 3, source: source))
                && candidate.generation == .provider(contentGeneration: 7)
                && candidate.purpose == .premultipliedColor && candidate.uvTransform == .identity,
            "environmentEpochChangesAtom": !first.publication.isSameAtom(as: second.publication),
            "environmentAllocationChangesAtom": !first.publication.isSameAtom(as: replacement.publication),
            "environmentProducerSubmissionChangesAtom": first.publication.contentGeneration == changedProducer.publication.contentGeneration
                && first.resourceGeneration == changedProducer.resourceGeneration
                && candidate.texture === changedProducer.publication.texture
                && !first.publication.isSameAtom(as: changedProducer.publication),
            "environmentPartialMipRejected": SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 3, texture: texture(3), source: source) == nil,
            "environmentUnsupportedFormatRejected": SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 3, texture: texture(4, format: .rgba32Float), source: source) == nil,
            "environmentNoRenderTargetRejected": SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 7, allocationGeneration: 3, texture: texture(4, usage: .shaderRead), source: source) == nil,
            "environmentZeroEpochRejected": SceneFrameTextureResource.sameFrameEnvironment(frameEpoch: 0, allocationGeneration: 3, texture: full, source: source) == nil
        ]
    }

    static func videoAndRollbackCases(
        dynamicTexture: MTLTexture,
        replacementDynamicTexture: MTLTexture,
        staleDynamicTexture: MTLTexture
    ) -> [String: Any] {
        let videoRegistry = SceneFrameTextureRegistry()
        let videoRequest = SceneFrameTextureIdentity.layerSource(13)
        func videoPublication(
            _ texture: MTLTexture,
            generation: UInt64,
            epoch: UInt64
        ) -> SceneTextureProviderPublication {
            publication(
                texture,
                generation: generation,
                requestIdentity: videoRequest,
                identity: .provider(.video(
                    layerID: 13,
                    lifecycleEpoch: epoch
                ))
            )
        }
        videoRegistry.beginFrame(
            layerSources: [13: dynamicTexture],
            explicitLayerSources: [
                13: videoPublication(dynamicTexture, generation: 10, epoch: 100)
            ]
        )
        let initialVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: replacementDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(
                    replacementDynamicTexture,
                    generation: 10,
                    epoch: 100
                )
            ]
        )
        let sameGenerationVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: staleDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(staleDynamicTexture, generation: 9, epoch: 100)
            ]
        )
        let staleVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: replacementDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(
                    replacementDynamicTexture,
                    generation: 1,
                    epoch: 101
                )
            ]
        )
        let rebuiltVideo = videoRegistry.resource(for: videoRequest)!
        videoRegistry.beginFrame(
            layerSources: [13: staleDynamicTexture],
            explicitLayerSources: [
                13: videoPublication(staleDynamicTexture, generation: 11, epoch: 100)
            ]
        )
        let oldLifecycleVideo = videoRegistry.resource(for: videoRequest)!
        let videoLifecycleGenerationIsAtomic =
            sameGenerationVideo.resourceGeneration == initialVideo.resourceGeneration
            && sameGenerationVideo.publication.texture === dynamicTexture
            && staleVideo.resourceGeneration == initialVideo.resourceGeneration
            && staleVideo.publication.texture === dynamicTexture
            && rebuiltVideo.resourceGeneration > initialVideo.resourceGeneration
            && rebuiltVideo.publication.contentGeneration == 1
            && rebuiltVideo.publication.texture === replacementDynamicTexture
            && oldLifecycleVideo.resourceGeneration == rebuiltVideo.resourceGeneration
            && oldLifecycleVideo.publication.texture === replacementDynamicTexture

        let rollbackRegistry = SceneFrameTextureRegistry()
        let rollbackRequest = SceneFrameTextureIdentity.layerSource(21)
        let rollbackInitial = publication(
            dynamicTexture,
            generation: 50,
            requestIdentity: rollbackRequest
        )
        rollbackRegistry.beginFrame(
            layerSources: [21: dynamicTexture],
            explicitLayerSources: [21: rollbackInitial]
        )
        let rollbackInitialResource = rollbackRegistry.resource(
            for: rollbackRequest
        )!
        rollbackRegistry.commitFramePublication()
        rollbackRegistry.beginFrame(
            layerSources: [21: replacementDynamicTexture],
            explicitLayerSources: [
                21: publication(
                    replacementDynamicTexture,
                    generation: 51,
                    requestIdentity: rollbackRequest
                )
            ]
        )
        rollbackRegistry.discardFramePublication()
        rollbackRegistry.beginFrame(
            layerSources: [21: dynamicTexture],
            explicitLayerSources: [21: rollbackInitial]
        )
        let rollbackRestoredResource = rollbackRegistry.resource(
            for: rollbackRequest
        )!
        let framePublicationDiscardRestoresPrevious =
            rollbackRestoredResource.publication.texture === dynamicTexture
            && rollbackRestoredResource.publication.contentGeneration == 50
            && rollbackRestoredResource.resourceGeneration
                == rollbackInitialResource.resourceGeneration
        return [
            "videoLifecycleGenerationIsAtomic": videoLifecycleGenerationIsAtomic,
            "framePublicationDiscardRestoresPrevious":
                framePublicationDiscardRestoresPrevious,
        ]
    }

    static func propertyResetRetirementChecks(_ device: MTLDevice) -> [String: Bool] {
        let resetRegistry = SceneFrameTextureRegistry()
        let property = SceneUserPropertyTextureIdentity(
            propertyKey: "retired-cover", purpose: .premultipliedColor
        )!
        let request = SceneFrameTextureIdentity.materialUserProperty(property)
        weak var oldTexture: MTLTexture?
        var oldResourceGeneration: UInt64 = 0
        autoreleasepool {
            let initial = texture(device)
            oldTexture = initial
            resetRegistry.beginFrame(layerSources: [:],
                userPropertyTextures: [property.propertyKey: initial],
                userPropertyStates: [property: .ready(publication(initial,
                    generation: 30, requestIdentity: request))])
            oldResourceGeneration = resetRegistry.resource(for: request)!.resourceGeneration
            resetRegistry.commitFramePublication()
        }
        resetRegistry.beginFrame(layerSources: [:], userPropertyStates: [property: .pending])
        resetRegistry.commitFramePublication()
        let pendingKeepsCommitted = oldTexture != nil
        resetRegistry.beginFrame(layerSources: [:], userPropertyStates: [property: .absent])
        let baselineKeepsOldUntilDecision = oldTexture != nil
        resetRegistry.discardFramePublication()
        var discardedResetRestoresOld = false
        autoreleasepool {
            let initial = oldTexture!
            resetRegistry.beginFrame(layerSources: [:],
                userPropertyTextures: [property.propertyKey: initial],
                userPropertyStates: [property: .ready(publication(initial,
                    generation: 30, requestIdentity: request))])
            let restored = resetRegistry.resource(for: request)!
            discardedResetRestoresOld = restored.publication.texture === initial
                && restored.resourceGeneration == oldResourceGeneration
            resetRegistry.commitFramePublication()
        }
        autoreleasepool {
            resetRegistry.beginFrame(layerSources: [:], userPropertyStates: [property: .absent])
            resetRegistry.commitFramePublication()
        }
        let acceptedResetReleasesOld = oldTexture == nil
        let replacement = texture(device)
        resetRegistry.beginFrame(layerSources: [:],
            userPropertyTextures: [property.propertyKey: replacement],
            userPropertyStates: [property: .ready(publication(replacement,
                generation: 31, requestIdentity: request))])
        let newResource = resetRegistry.resource(for: request)!
        return [
            "pendingKeepsCommitted": pendingKeepsCommitted,
            "baselineKeepsOldUntilDecision": baselineKeepsOldUntilDecision,
            "discardedResetRestoresOld": discardedResetRestoresOld,
            "acceptedResetReleasesOld": acceptedResetReleasesOld,
            "sameKeyNewGenerationPublishes": newResource.publication.texture === replacement
                && newResource.publication.contentGeneration == 31
                && newResource.resourceGeneration > oldResourceGeneration,
        ]
    }
}
