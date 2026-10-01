import Metal

extension SceneMetalRenderer {
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

    func encodeTerminalColor(sceneColor: SceneResolvedMaterialSubmissionCoordinator.SceneColorReservation?,
                             target: MTLTexture, offscreenTexturePool: SceneOffscreenTexturePool?,
                             dynamicValues: SceneDynamicSnapshot, commandBuffer: MTLCommandBuffer) -> FrameOutcome? {
        if let sceneColor {
            // Only display scratch sees Bloom or the nonlinear output curve.
            // A paused export reuses raw without traversing authored layers.
            let copied = copySceneColor(sceneColor.raw, to: sceneColor.display, commandBuffer: commandBuffer)
            if copied {
                bloomPostProcess?.encode(configuration: renderDescriptor.camera.bloom.resolving(
                    dynamicValues), source: sceneColor.display,
                    commandBuffer: commandBuffer)
            }
            let mapped = copied && displayMappingPostProcess?.encode(
                source: sceneColor.display, target: target,
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
}
