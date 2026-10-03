import Metal

extension SceneMetalRenderer {
    /// One submission's optional environment and the mandatory scratch it may
    /// not evict. Prepared source payloads reference only this frame's resolver.
    final class ReflectionFrame {
        private let pool: SceneOffscreenTexturePool?
        private let mainPass: SceneMainPassEncoder
        private let groupRuntime: SceneCompositionGroupFrameRuntime?
        private let commandBuffer: MTLCommandBuffer
        private let frameEpoch: UInt64
        private var pins: [SceneGraphRenderTargetResidencyPin] = []
        private var attempted = false
        private var resource: SceneFrameTextureResource?
        private var history: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?
        private(set) var scratchReady = false
        var mainSourceCompleted = false

        var snapshot: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation? {
            history?.intent == .snapshot ? history : nil
        }

        init(pool: SceneOffscreenTexturePool?, mainPass: SceneMainPassEncoder,
             groupRuntime: SceneCompositionGroupFrameRuntime?, commandBuffer: MTLCommandBuffer,
             frameEpoch: UInt64) {
            self.pool = pool; self.mainPass = mainPass; self.groupRuntime = groupRuntime
            self.commandBuffer = commandBuffer; self.frameEpoch = frameEpoch
        }

        func admit(_ targets: [SceneOffscreenTexturePool.PinnedTexture],
                   sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?) {
            pins.append(contentsOf: targets.map(\.pin))
            history = sceneColor
            scratchReady = true
        }

        func resolve(_ actual: MTLCommandBuffer) -> SceneFrameTextureResource? {
            guard actual === commandBuffer, scratchReady else { return nil }
            if attempted { return resource }
            attempted = true
            guard let source = history?.previous, let sourceIdentity = history?.previousReceipt else {
                return nil
            }
            let extent = mainPass.targetExtent
            guard let reserved = pool?.reserveEnvironment(width: extent.width, height: extent.height,
                commandBuffer: commandBuffer) else { return nil }
            // Encoding a copy already creates an in-flight writer, even if
            // publication or the eventual receiver subsequently fails.
            pins.append(reserved.pin)
            groupRuntime?.closeAllGroupEncoders()
            let copied = mainPass.encodeOffscreen { buffer in
                guard let blit = buffer.makeBlitCommandEncoder() else { return false }
                blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOriginMake(0, 0, 0),
                    sourceSize: MTLSizeMake(source.width, source.height, 1),
                    to: reserved.texture, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOriginMake(0, 0, 0))
                if reserved.texture.mipmapLevelCount > 1 { blit.generateMipmaps(for: reserved.texture) }
                blit.endEncoding()
                return true
            }
            guard copied == true else { return nil }
            resource = .sameFrameEnvironment(frameEpoch: frameEpoch,
                allocationGeneration: reserved.pin.generation, texture: reserved.texture,
                source: sourceIdentity)
            return resource
        }

        func arm() {
            let submittedPins = pins
            commandBuffer.addCompletedHandler { _ in submittedPins.forEach { $0.release() } }
            pins.removeAll(); resource = nil; history = nil; scratchReady = false
        }

        func cancel() {
            pins.forEach { $0.release() }
            pins.removeAll(); resource = nil; history = nil; scratchReady = false
        }
    }

    /// Establish the current raw main pass and group encoders before preparing
    /// source payloads; optional reflection resolves completed history separately.
    func makeScenePass(target: MTLTexture, clearEnabled: Bool,
                       pool: SceneOffscreenTexturePool?, visibleLayerIDs: Set<Int>,
                       viewportSize: CGSize, commandBuffer: MTLCommandBuffer)
        -> (SceneMainPassEncoder, SceneCompositionGroupFrameRuntime?) {
        let mainPass = SceneMainPassEncoder(commandBuffer: commandBuffer,
            target: target, clearColor: sceneClearColor, clearEnabled: clearEnabled)
        var groups: SceneCompositionGroupFrameRuntime?
        if let pool, !compositionGroupMemberRootsByLayerID.isEmpty {
            groups = SceneCompositionGroupFrameRuntime(parentPass: mainPass,
                commandBuffer: commandBuffer, offscreenTexturePool: pool,
                memberRootsByLayerID: compositionGroupMemberRootsByLayerID,
                membersByRootID: compositionGroupMembersByRootID, viewportSize: viewportSize)
        }
        groups?.reserveSources(orderedRootIDs: compositionGroupRootIDs, visibleLayerIDs: visibleLayerIDs)
        return (mainPass, groups)
    }

    var sceneClearColor: MTLClearColor {
        let color = renderDescriptor.camera.clearColor
        let red = Double(color.count > 0 ? color[0] : 0.7)
        let green = Double(color.count > 1 ? color[1] : 0.7)
        let blue = Double(color.count > 2 ? color[2] : 0.7)
        return MTLClearColorMake(red, green, blue, 1)
    }

    func copySceneColor(_ source: MTLTexture, to target: MTLTexture,
                    commandBuffer: MTLCommandBuffer) -> Bool {
        guard source !== target, source.width == target.width,
              source.height == target.height, source.pixelFormat == target.pixelFormat,
              let encoder = commandBuffer.makeBlitCommandEncoder() else { return false }
        encoder.copy(from: source, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOriginMake(0, 0, 0),
            sourceSize: MTLSizeMake(source.width, source.height, 1),
            to: target, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOriginMake(0, 0, 0))
        encoder.endEncoding()
        return true
        }

    /// Reserve and seed raw color before any authored draw. The caller keeps
    /// the frame's existing cancellation/submit barrier for both outcomes.
    func encodeSceneColorStart(pool: SceneOffscreenTexturePool?, target: MTLTexture,
                               frameIndex: UInt64, clearEnabled: Bool,
                               commandBuffer: MTLCommandBuffer)
        -> (reservation: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?, failure: FrameOutcome?) {
        guard renderDescriptor.hdrEnabled && !clearEnabled else { return (nil, nil) }
        guard let pool,
              let value = imageCompositor.resolvedMaterialRuntime?.reserveSceneColor(
                pool: pool, width: target.width, height: target.height,
                frameIndex: frameIndex, commandBuffer: commandBuffer) else {
            return (nil, .deferred(reasonCode: "scene-color-target-unavailable"))
        }
        if value.requiresDraw, let previous = value.previous,
           !copySceneColor(previous, to: value.raw, commandBuffer: commandBuffer) {
            return (nil, .dropped(reasonCode: "scene-color-seed-encoder-unavailable"))
        }
        return (value, nil)
    }

    func prepareTerminalCapacity(
        sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
        target: MTLTexture, dynamicValues: SceneDynamicSnapshot
    ) -> Bool {
        bloomPostProcess?.prepareCapacity(
            configuration: renderDescriptor.camera.bloom.resolving(dynamicValues),
            source: sceneColor?.display ?? target) ?? true
    }

    func encodeTerminalColor(sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
                             target: MTLTexture, offscreenTexturePool: SceneOffscreenTexturePool?,
                             dynamicValues: SceneDynamicSnapshot, commandBuffer: MTLCommandBuffer) -> FrameOutcome? {
        if let sceneColor {
            guard let display = sceneColor.display else {
                return .dropped(reasonCode: "scene-color-display-reservation-invalid")
            }
            // Only display scratch sees Bloom or the nonlinear output curve.
            // A paused export reuses raw without traversing authored layers.
            let copied = copySceneColor(sceneColor.raw, to: display, commandBuffer: commandBuffer)
            if copied {
                bloomPostProcess?.encode(configuration: renderDescriptor.camera.bloom.resolving(
                    dynamicValues), source: display,
                    commandBuffer: commandBuffer)
            }
            let mapped = copied && displayMappingPostProcess?.encode(
                source: display, target: target,
                commandBuffer: commandBuffer) == true
            if !mapped && !copySceneColor(sceneColor.raw, to: target, commandBuffer: commandBuffer) {
                return .dropped(reasonCode: "scene-color-display-export-unavailable")
            }
            guard imageCompositor.resolvedMaterialRuntime?.markSceneColorOutput(
                on: commandBuffer, mapped: mapped) == true else {
                return .dropped(reasonCode: "scene-color-output-identity-rejected")
            }
        } else {
            bloomPostProcess?.encode(configuration: renderDescriptor.camera.bloom.resolving(
                dynamicValues), source: target,
                commandBuffer: commandBuffer)
            if let displayMappingPostProcess,
               let offscreenTexturePool,
               let scratch = imageCompositor.resolvedMaterialRuntime?.reserveDisplayScratch(
                pool: offscreenTexturePool, width: target.width,
                height: target.height, commandBuffer: commandBuffer),
               copySceneColor(target, to: scratch, commandBuffer: commandBuffer) {
                displayMappingPostProcess.encode(source: scratch, target: target,
                                                 commandBuffer: commandBuffer)
            }
        }
        guard imageCompositor.endResolvedMaterialFrame(on: commandBuffer) else {
            return .dropped(reasonCode: "resolved-material-frame-seal-rejected")
        }
        return nil
    }

    /// Optional capture shares the original completion owner. A failed copy
    /// keeps the ordinary terminal output and cannot promote this candidate.
    func encodeReflectionSnapshot(_ reflection: ReflectionFrame?, source: MTLTexture,
                                  commandBuffer: MTLCommandBuffer) -> FrameOutcome? {
        guard let reflection, let snapshot = reflection.snapshot else { return nil }
        let copied = reflection.mainSourceCompleted
            && copySceneColor(source, to: snapshot.raw, commandBuffer: commandBuffer)
        if copied, imageCompositor.resolvedMaterialRuntime?.markSceneColorSnapshot(on: commandBuffer) == true {
            return nil
        }
        guard imageCompositor.resolvedMaterialRuntime?.detachPreparedSceneColorSnapshot(on: commandBuffer) == true else {
            return .dropped(reasonCode: "scene-color-snapshot-identity-rejected")
        }
        return nil
    }
}
