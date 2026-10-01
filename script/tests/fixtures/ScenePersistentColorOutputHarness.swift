import Foundation
import Metal

@main enum ScenePersistentColorOutputHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { fatalError("RF07 requires Metal") }
        typealias Coordinator = SceneResolvedMaterialSubmissionCoordinator
        func coordinator() -> Coordinator {
            Coordinator(device: device, capabilities: .init(admissionCandidates: [],
                materialCatalog: .init(entries: [:], resourceDemandIssues: [])),
                capturesExecutionObservations: false, logSink: { _ in })
        }
        func begin(_ owner: Coordinator, _ index: UInt64, _ size: Int = 4) {
            let snapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: index, generation: index, definitions: []).snapshot
            owner.beginFrame(textureSnapshot: .init(frameEpoch: index, frameIndex: index, entries: [:]),
                dynamicSnapshot: snapshot, frameInputs: .init(frameIndex: index,
                    screenSize: CGSize(width: size, height: size), sceneTime: Float(index),
                    dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
        }
        func pool(_ budget: Int = 1_048_576) -> SceneOffscreenTexturePool {
            .init(device: device, pixelFormat: .rgba16Float, maxDimension: 64, residentByteBudget: budget)
        }
        func texture(_ size: Int = 4) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: size, height: size, mipmapped: false)
            d.storageMode = .shared; d.usage = [.shaderRead, .renderTarget]
            return device.makeSceneTexture(descriptor: d)!
        }
        func copy(_ source: MTLTexture, _ target: MTLTexture, _ cb: MTLCommandBuffer) {
            let e = cb.makeBlitCommandEncoder()!
            e.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: source.width, height: source.height, depth: 1),
                to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
            e.endEncoding()
        }
        func read(_ source: MTLTexture) -> [Float] {
            let result = texture(source.width), cb = queue.makeCommandBuffer()!
            copy(source, result, cb); cb.commit(); cb.waitUntilCompleted()
            precondition(cb.status == .completed && cb.error == nil)
            var values = [Float16](repeating: 0, count: source.width * source.height * 4)
            values.withUnsafeMutableBytes {
                result.getBytes($0.baseAddress!, bytesPerRow: source.width * 8,
                    from: MTLRegionMake2D(0, 0, source.width, source.height), mipmapLevel: 0)
            }
            return values.prefix(4).map(Float.init)
        }
        let mapping = SceneDisplayMappingPostProcess(device: device, pixelFormat: .rgba16Float,
                                                     hdrEnabled: true)!
        let bloom = SceneBloomPostProcess(device: device, pixelFormat: .rgba16Float)!
        let fragmentLibrary = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            fragment float4 authoredHalfAlpha() { return float4(0, 1, 0, 0.5); }
            """, options: nil)
        let blendDescriptor = MTLRenderPipelineDescriptor()
        blendDescriptor.vertexFunction = device.makeDefaultLibrary()!.makeFunction(name: "sceneDisplayMappingVertex")
        blendDescriptor.fragmentFunction = fragmentLibrary.makeFunction(name: "authoredHalfAlpha")
        let attachment = blendDescriptor.colorAttachments[0]!
        attachment.pixelFormat = .rgba16Float
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let authoredPipeline = try device.makeRenderPipelineState(descriptor: blendDescriptor)
        let storage = pool(), owner = coordinator()
        var checks: [String: Bool] = [:]
        var frames: [[String: Any]] = []
        // Product owner, not the fixture, chooses candidate/current and draw/export.
        func prepare(_ index: UInt64, size: Int = 4, append: Bool = false, bloomEnabled: Bool = false, mappingFault: Bool = false)
            -> (Coordinator.SceneColorReservation, MTLCommandBuffer, MTLTexture) {
            begin(owner, index, size)
            let cb = queue.makeCommandBuffer()!
            let reservation = owner.reserveSceneColor(pool: storage, width: size, height: size,
                                                       frameIndex: index, commandBuffer: cb)!
            if reservation.requiresDraw {
                if let previous = reservation.previous { copy(previous, reservation.raw, cb) }
                let pass = SceneMainPassEncoder(commandBuffer: cb, target: reservation.raw,
                    clearColor: MTLClearColorMake(3, 0.25, 0.5, 1), clearEnabled: reservation.previous == nil)
                if append {
                    let encoder = pass.encoder()!
                    encoder.setRenderPipelineState(authoredPipeline)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                }
                precondition(pass.finishEnsuringClear())
            }
            let target = texture(size)
            copy(reservation.raw, reservation.display, cb)
            if bloomEnabled {
                precondition(bloom.encode(configuration: .init(enabled: true, strength: 1,
                    threshold: 0.3, tint: SIMD3(1, 1, 1)), source: reservation.display, commandBuffer: cb))
            }
            if mappingFault { MWXArmEncoderFault(cb, 1) }
            let mapped = mapping.encode(source: reservation.display, target: target, commandBuffer: cb)
            if mappingFault { MWXArmEncoderFault(cb, 0) }
            if !mapped { copy(reservation.raw, target, cb) }
            precondition(owner.markSceneColorOutput(on: cb, mapped: mapped))
            precondition(owner.sealFrame(on: cb)); _ = owner.endFrame()
            return (reservation, cb, target)
        }
        func complete(_ cb: MTLCommandBuffer, status: SceneGraphExecutionGPUCompletionStatus = .completed) {
            let id = ObjectIdentifier(cb), observation = owner.commandBufferRecords[id]!.observationID
            cb.commit(); cb.waitUntilCompleted()
            precondition(cb.status == .completed && cb.error == nil)
            // The failed status below is an injected existing completion seam;
            // GPU commands themselves complete. This is not a device fault claim.
            owner.completeCommandBuffer(identity: id, observationID: observation, status: status)
        }
        for i in 0..<8 {
            let (r, cb, display) = prepare(1)
            checks["drawOnlyInitial-\(i)"] = r.requiresDraw == (i == 0)
            checks["emptyGraphHasPendingTerminal-\(i)"] = owner.pendingSubmissions.count == 1
                && owner.pendingSubmissions[0].ledgerIDs.isEmpty && owner.shouldDeferFrame
            complete(cb)
            let raw = read(r.raw), shown = read(display)
            checks["rawStable-\(i)"] = raw == [3, 0.25, 0.5, 1]
            checks["completedAndReleased-\(i)"] = owner.pendingSubmissions.isEmpty && !owner.shouldDeferFrame
                && owner.completedSceneColor?.frameIndex == 1
            frames.append(["gpuCompleted": true, "rgb": Array(shown.prefix(3)), "alpha": shown[3]])
        }
        var alphaFrames: [[Float]] = []
        for index: UInt64 in [2, 3] {
            let (r, cb, display) = prepare(index, append: true)
            complete(cb)
            alphaFrames.append(read(r.raw) + read(display))
        }
        let alphaRaw = read(owner.completedSceneColor!.raw)
        let (bloomR, bloomCB, bloomDisplay) = prepare(3, bloomEnabled: true)
        complete(bloomCB)
        let brightDisplay = read(bloomDisplay)
        let (plainR, plainCB, plainDisplay) = prepare(3)
        complete(plainCB)
        checks["bloomDoesNotMutateRaw"] = read(bloomR.raw) == alphaRaw && read(plainR.raw) == alphaRaw
        checks["bloomOnOffExportsDoNotAccumulate"] = brightDisplay[0] > read(plainDisplay)[0]
            && !bloomR.requiresDraw && !plainR.requiresDraw
        let (faultR, faultCB, faultDisplay) = prepare(4, mappingFault: true)
        complete(faultCB)
        checks["mappingEncoderFailureExportsRaw"] = read(faultDisplay) == alphaRaw
            && read(faultR.raw) == alphaRaw && owner.completedSceneColor?.displayMapped == false
        // Reset restores the independent lifecycle scenarios below to their seed.
        owner.invalidate(reason: .allocationReprepare); storage.reset()
        let (_, seedCB, _) = prepare(1); complete(seedCB)
        let seededRaw = owner.completedSceneColor!.raw
        begin(owner, 2)
        let bootstrapFaultCB = queue.makeCommandBuffer()!
        let bootstrapR = owner.reserveSceneColor(pool: storage, width: 4, height: 4,
            frameIndex: 2, commandBuffer: bootstrapFaultCB)!
        MWXArmEncoderFault(bootstrapFaultCB, 1)
        let bootstrapPass = SceneMainPassEncoder(commandBuffer: bootstrapFaultCB, target: bootstrapR.raw,
            clearColor: MTLClearColorMake(3, 0.25, 0.5, 1), clearEnabled: true)
        checks["mainEncoderFailureDetected"] = !bootstrapPass.finishEnsuringClear()
        MWXArmEncoderFault(bootstrapFaultCB, 0)
        owner.cancelUnsubmittedFrame(on: bootstrapFaultCB); _ = owner.endFrame()
        checks["mainEncoderFailureKeepsCompleted"] = owner.completedSceneColor?.raw === seededRaw
            && !owner.shouldDeferFrame
        let before = owner.completedSceneColor!.raw
        let (_, cancelled, _) = prepare(2)
        owner.cancelUnsubmittedFrame(on: cancelled)
        checks["cancelKeepsCompleted"] = owner.completedSceneColor!.raw === before
            && owner.completedSceneColor!.frameIndex == 1 && !owner.shouldDeferFrame
        let (_, failed, _) = prepare(2)
        complete(failed, status: .failed)
        checks["injectedFailureKeepsCompleted"] = owner.completedSceneColor!.raw === before
            && owner.completedSceneColor!.frameIndex == 1 && !owner.shouldDeferFrame
        let (recovery, recovered, _) = prepare(2)
        complete(recovered)
        checks["nextFrameAfterFailure"] = owner.completedSceneColor!.raw === recovery.raw
            && owner.completedSceneColor!.frameIndex == 2

        let (_, staleBuffer, _) = prepare(3)
        let oldID = owner.commandBufferRecords[ObjectIdentifier(staleBuffer)]!.observationID
        owner.invalidate(reason: .allocationReprepare); storage.reset()
        staleBuffer.commit(); staleBuffer.waitUntilCompleted()
        owner.completeCommandBuffer(identity: ObjectIdentifier(staleBuffer), observationID: oldID, status: .completed)
        checks["oldEpochCannotPromote"] = owner.completedSceneColor == nil
            && owner.pendingSubmissions.isEmpty && storage.residentByteCost == 0
        let (resized, resizeBuffer, resizeDisplay) = prepare(2, size: 8)
        checks["sameSimulationFrameNewEpochDraws"] = resized.requiresDraw && resized.previous == nil
            && resized.raw.width == 8
        complete(resizeBuffer)
        checks["resizeSeedOpaque"] = read(resized.raw) == [3, 0.25, 0.5, 1]
            && abs(read(resizeDisplay)[0] - 11.0 / 12.0) < 1.0 / 1024.0
        let (export, exportBuffer, _) = prepare(2, size: 8)
        checks["sameEpochPausedExportPins"] = !export.requiresDraw && owner.shouldDeferFrame
        complete(exportBuffer)
        checks["pausedExportCompleted"] = owner.completedSceneColor!.raw === export.raw
            && !owner.shouldDeferFrame

        // Exercise the actual renderer terminal helper, not a reconstruction
        // of its fallback branches. The carrier contains only dependencies.
        func terminalRenderer(_ mapping: SceneDisplayMappingPostProcess?) -> SceneMetalRenderer {
            .init(renderDescriptor: .init(hdrEnabled: true,
                camera: .init(clearColor: [3, 0.25, 0.5], bloom: .disabled)),
                imageCompositor: .init(resolvedMaterialRuntime: owner),
                bloomPostProcess: nil, displayMappingPostProcess: mapping)
        }
        for mask in [1, 3] {
            let frameIndex = UInt64(mask + 2)
            begin(owner, frameIndex, 8)
            let cb = queue.makeCommandBuffer()!, display = texture(8)
            let r = owner.reserveSceneColor(pool: storage, width: 8, height: 8,
                frameIndex: frameIndex, commandBuffer: cb)!
            copy(r.previous!, r.raw, cb)
            let previousCompleted = owner.completedSceneColor!.raw
            let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 3,
                generation: 3, definitions: []).snapshot
            MWXArmBlitFault(cb, UInt(mask))
            let outcome = terminalRenderer(mapping).encodeTerminalColor(sceneColor: r,
                target: display, offscreenTexturePool: storage, dynamicValues: snapshot, commandBuffer: cb)
            MWXArmBlitFault(cb, 0)
            if mask == 1 {
                checks["actualHelperFirstBlitFallsBack"] = outcome == nil
                complete(cb)
                checks["actualHelperFallbackRawOutput"] = read(display) == [3, 0.25, 0.5, 1]
                    && owner.completedSceneColor?.displayMapped == false
            } else {
                checks["actualHelperBothBlitsDrop"] = outcome == .dropped(
                    reasonCode: "scene-color-display-export-unavailable")
                owner.cancelUnsubmittedFrame(on: cb); _ = owner.endFrame()
                checks["actualHelperDroppedOutputCannotPromote"] = owner.completedSceneColor?.raw === previousCompleted
                    && owner.pendingSubmissions.isEmpty && !owner.shouldDeferFrame
            }
        }
        MWXArmPipelineFault(device, 1)
        let unavailableMapping = SceneDisplayMappingPostProcess(device: device,
            pixelFormat: .rgba16Float, hdrEnabled: true)
        MWXArmPipelineFault(device, 0)
        checks["mappingPreparationFaultIsReal"] = unavailableMapping == nil
        begin(owner, 4, 8)
        let nilMappingCB = queue.makeCommandBuffer()!, nilMappingTarget = texture(8)
        let nilMappingRenderer = terminalRenderer(unavailableMapping)
        let nilStart = nilMappingRenderer.encodeSceneColorStart(pool: storage, target: nilMappingTarget,
            frameIndex: 4, clearEnabled: false, commandBuffer: nilMappingCB)
        let nilSnapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: 4, generation: 4, definitions: []).snapshot
        checks["actualHelperPreparesRaw"] = nilStart.failure == nil && nilStart.reservation != nil
        let nilOutcome = nilMappingRenderer.encodeTerminalColor(sceneColor: nilStart.reservation,
            target: nilMappingTarget, offscreenTexturePool: storage, dynamicValues: nilSnapshot,
            commandBuffer: nilMappingCB)
        checks["actualHelperNilMappingExports"] = nilOutcome == nil
        complete(nilMappingCB)
        checks["actualHelperNilMappingRawOutput"] = read(nilMappingTarget) == [3, 0.25, 0.5, 1]
            && owner.completedSceneColor?.displayMapped == false

        for index in 1...3 {
            let failurePool = pool(); var allocations = 0
            let rejected = failurePool.reserveSceneColor(width: 4, height: 4) { descriptor in
                allocations += 1
                return allocations == index ? nil : device.makeSceneTexture(descriptor: descriptor)
            }
            checks["allocationFailure-\(index)"] = rejected == nil
                && failurePool.residentByteCost == 0 && allocations == index
            let retried = failurePool.reserveSceneColor(width: 4, height: 4)
            checks["allocationRecovery-\(index)"] = retried != nil
            retried?.release(); failurePool.reset()
        }
        let tooSmall = pool(4 * 4 * 8 * 3 - 1)
        checks["budgetRefusedBeforePublication"] = tooSmall.reserveSceneColor(width: 4, height: 4) == nil
            && tooSmall.residentByteCost == 0
        checks["exactExtentRefused"] = storage.reserveSceneColor(width: 65, height: 4) == nil

        // Distinct real surface owners must not share busy/completed history.
        let other = coordinator(), otherPool = pool()
        let (_, pending, _) = prepare(3, size: 8)
        begin(other, 1)
        let peerCB = queue.makeCommandBuffer()!
        let peer = other.reserveSceneColor(pool: otherPool, width: 4, height: 4,
                                          frameIndex: 1, commandBuffer: peerCB)
        checks["independentSurfaceAdmission"] = owner.shouldDeferFrame && peer != nil
            && peer?.previous == nil
        other.cancelUnsubmittedFrame(on: peerCB); _ = other.endFrame()
        owner.cancelUnsubmittedFrame(on: pending)
        owner.invalidate(reason: .surfaceStop); storage.reset()
        other.invalidate(reason: .surfaceStop); otherPool.reset()
        checks["stopReleasesTerminalResidency"] = storage.residentByteCost == 0 && otherPool.residentByteCost == 0
        let largePool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
            maxDimension: 8192, residentByteBudget: 128 * 1024 * 1024)
        let largeSource = texture(2056), largeCB = queue.makeCommandBuffer()!
        let largePass = SceneMainPassEncoder(commandBuffer: largeCB, target: largeSource,
            clearColor: MTLClearColorMake(3, 0.25, 0.5, 1), clearEnabled: true)
        precondition(largePass.finishEnsuringClear())
        let largeOwner = coordinator()
        begin(largeOwner, 1, 2056)
        let scratch = largeOwner.reserveDisplayScratch(pool: largePool, width: 2056, height: 2056,
                                                       commandBuffer: largeCB)!
        precondition(largeOwner.sealFrame(on: largeCB)); _ = largeOwner.endFrame()
        checks["clearedEmptyGraphHasTerminalPin"] = largeOwner.pendingSubmissions.count == 1
        largePool.reset()
        checks["clearedScratchRetiredUntilGPU"] = largePool.residentTextureCount == 1
        let exact = scratch.width == largeSource.width && scratch.height == largeSource.height
        if exact {
            copy(largeSource, scratch, largeCB)
            precondition(mapping.encode(source: scratch, target: largeSource, commandBuffer: largeCB))
        }
        let largeObservation = largeOwner.commandBufferRecords[ObjectIdentifier(largeCB)]!.observationID
        largeCB.commit(); largeCB.waitUntilCompleted()
        largeOwner.completeCommandBuffer(identity: ObjectIdentifier(largeCB), observationID: largeObservation,
                                         status: .completed)
        checks["clearedScratchCompletionReleasesResetResidency"] = largePool.residentByteCost == 0
        checks["clearTrueLargeExtentConservation"] = exact && largeCB.status == .completed
            && abs(read(largeSource)[0] - 11.0 / 12.0) < 1.0 / 1024.0
        let source = texture(), target = texture(), cb = queue.makeCommandBuffer()!
        let pass = SceneMainPassEncoder(commandBuffer: cb, target: source,
            clearColor: MTLClearColorMake(3, 0.25, 0.5, 1), clearEnabled: true)
        precondition(pass.finishEnsuringClear())
        precondition(mapping.encode(source: source, target: target, commandBuffer: cb))
        cb.commit(); cb.waitUntilCompleted()
        let shown = read(target), raw = read(source)
        let result: [String: Any] = ["accumulatingFrames": frames, "ownerChecks": checks, "alphaFrames": alphaFrames,
            "clearedHDR": ["gpuCompleted": cb.status == .completed, "rgb": Array(shown.prefix(3)), "alpha": shown[3]],
            "nonHDR": ["rgb": Array(raw.prefix(3)), "alpha": raw[3]]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
