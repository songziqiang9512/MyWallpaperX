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
        func begin(_ owner: Coordinator, _ index: UInt64, _ size: Int = 4, frameEpoch: UInt64? = nil) {
            let snapshot = SceneDynamicSnapshotResolver().resolve(
                frameIndex: index, generation: index, definitions: []).snapshot
            owner.beginFrame(textureSnapshot: .init(frameEpoch: frameEpoch ?? index, frameIndex: index, entries: [:]),
                dynamicSnapshot: snapshot, frameInputs: .init(frameIndex: index,
                    screenSize: CGSize(width: size, height: size), sceneTime: Float(index),
                    dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
        }
        func pool(_ budget: Int = 1_048_576) -> SceneOffscreenTexturePool {
            .init(device: device, pixelFormat: .rgba16Float, maxDimension: 64, residentByteBudget: budget)
        }
        func texture(_ size: Int = 4, pixelFormat: MTLPixelFormat = .rgba16Float) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
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
            let scratch = reservation.display!
            copy(reservation.raw, scratch, cb)
            if bloomEnabled {
                precondition(bloom.encode(configuration: .init(enabled: true, strength: 1,
                    threshold: 0.3, tint: SIMD3(1, 1, 1)), source: scratch, commandBuffer: cb))
            }
            if mappingFault { MWXArmEncoderFault(cb, 1) }
            let mapped = mapping.encode(source: scratch, target: target, commandBuffer: cb)
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
        let alphaRaw = read(owner.completedSceneColor!.persistenceReservation!.raw)
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
        let seededRaw = owner.completedSceneColor!.persistenceReservation!.raw
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
        checks["mainEncoderFailureKeepsCompleted"] = owner.completedSceneColor?.persistenceReservation?.raw === seededRaw
            && !owner.shouldDeferFrame
        let before = owner.completedSceneColor!.persistenceReservation!.raw
        let (_, cancelled, _) = prepare(2)
        owner.cancelUnsubmittedFrame(on: cancelled)
        checks["cancelKeepsCompleted"] = owner.completedSceneColor!.persistenceReservation!.raw === before
            && owner.completedSceneColor!.frameIndex == 1 && !owner.shouldDeferFrame
        let (_, failed, _) = prepare(2)
        complete(failed, status: .failed)
        checks["injectedFailureKeepsCompleted"] = owner.completedSceneColor!.persistenceReservation!.raw === before
            && owner.completedSceneColor!.frameIndex == 1 && !owner.shouldDeferFrame
        let (recovery, recovered, _) = prepare(2)
        complete(recovered)
        checks["nextFrameAfterFailure"] = owner.completedSceneColor!.persistenceReservation!.raw === recovery.raw
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
            && abs(read(resizeDisplay)[0] - 1.0) < 1.0 / 1024.0
        let (export, exportBuffer, _) = prepare(2, size: 8)
        checks["sameEpochPausedExportPins"] = !export.requiresDraw && owner.shouldDeferFrame
        complete(exportBuffer)
        checks["pausedExportCompleted"] = owner.completedSceneColor!.persistenceReservation!.raw === export.raw
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
            let previousCompleted = owner.completedSceneColor!.persistenceReservation!.raw
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
                checks["actualHelperDroppedOutputCannotPromote"] = owner.completedSceneColor?.persistenceReservation?.raw === previousCompleted
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

        // A fixed linear surface may never publish unconverted raw fallback.
        // Use the real terminal helper and cancellation owner for both routes.
        for accumulating in [false, true] {
            for fault in ["blit", "encoder", "pipeline"] {
                begin(owner, 5, 8)
                let cb = queue.makeCommandBuffer()!, display = texture(8)
                let previousCompleted = owner.completedSceneColor!.persistenceReservation!.raw
                let reservation = accumulating ? owner.reserveSceneColor(pool: storage,
                    width: 8, height: 8, frameIndex: 5, commandBuffer: cb) : nil
                if let reservation { copy(reservation.previous!, reservation.raw, cb) }
                MWXArmBlitFault(cb, fault == "blit" ? 1 : 0)
                MWXArmEncoderFault(cb, fault == "encoder" ? 1 : 0)
                let outcome = terminalRenderer(fault == "pipeline" ? nil : mapping).encodeTerminalColor(
                    sceneColor: reservation, target: display, offscreenTexturePool: storage,
                    dynamicValues: nilSnapshot, commandBuffer: cb,
                    output: .extendedLinearSRGB(headroom: 4))
                MWXArmBlitFault(cb, 0); MWXArmEncoderFault(cb, 0)
                checks["linear-\(accumulating)-\(fault)-dropsUnconvertedOutput"] = outcome == .dropped(
                    reasonCode: "scene-linear-display-export-unavailable")
                owner.cancelUnsubmittedFrame(on: cb); _ = owner.endFrame()
                checks["linear-\(accumulating)-\(fault)-keepsCompleted"] =
                    owner.completedSceneColor?.persistenceReservation?.raw === previousCompleted
                    && owner.pendingSubmissions.isEmpty && !owner.shouldDeferFrame
            }
        }
        begin(owner, 6, 8)
        let linearCB = queue.makeCommandBuffer()!, linearTarget = texture(8)
        let linearReservation = owner.reserveSceneColor(pool: storage, width: 8, height: 8,
            frameIndex: 6, commandBuffer: linearCB)!
        copy(linearReservation.previous!, linearReservation.raw, linearCB)
        let linearOutcome = terminalRenderer(mapping).encodeTerminalColor(sceneColor: linearReservation,
            target: linearTarget, offscreenTexturePool: storage, dynamicValues: nilSnapshot,
            commandBuffer: linearCB, output: .extendedLinearSRGB(headroom: 4))
        checks["linearRecoveryEncodes"] = linearOutcome == nil
        complete(linearCB)
        let linearPixels = read(linearTarget)
        checks["linearRecoveryPreservesRawAndDecodesTerminal"] =
            read(linearReservation.raw) == [3, 0.25, 0.5, 1]
            && abs(linearPixels[0] - 4) < 0.002 && abs(linearPixels[1] - 0.050876) < 0.001
            && abs(linearPixels[2] - 0.214041) < 0.001 && linearPixels[3] == 1

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

        func completeOn(_ runtime: Coordinator, _ buffer: MTLCommandBuffer,
                        status: SceneGraphExecutionGPUCompletionStatus = .completed) {
            let identity = ObjectIdentifier(buffer)
            let observation = runtime.commandBufferRecords[identity]!.observationID
            buffer.commit(); buffer.waitUntilCompleted()
            precondition(buffer.status == .completed && buffer.error == nil)
            runtime.completeCommandBuffer(identity: identity, observationID: observation, status: status)
        }
        func bytes(_ source: MTLTexture) -> [UInt8] {
            let destination = texture(source.width, pixelFormat: source.pixelFormat)
            let buffer = queue.makeCommandBuffer()!
            copy(source, destination, buffer); buffer.commit(); buffer.waitUntilCompleted()
            precondition(buffer.status == .completed && buffer.error == nil)
            let stride = source.pixelFormat == .rgba16Float ? 8 : 4
            var result = [UInt8](repeating: 0, count: source.width * source.height * stride)
            result.withUnsafeMutableBytes {
                destination.getBytes($0.baseAddress!, bytesPerRow: source.width * stride,
                    from: MTLRegionMake2D(0, 0, source.width, source.height), mipmapLevel: 0)
            }
            return result
        }
        func snapshot(_ runtime: Coordinator, _ cache: SceneOffscreenTexturePool,
                      index: UInt64, epoch: UInt64, size: Int = 4,
                      color: MTLClearColor, copyFault: Bool = false)
            -> (Coordinator.SceneColorReservation, MTLCommandBuffer) {
            begin(runtime, index, size, frameEpoch: epoch)
            let buffer = queue.makeCommandBuffer()!
            let value = runtime.reserveSceneColor(pool: cache, width: size, height: size,
                frameIndex: index, commandBuffer: buffer, intent: .snapshot)!
            let source = texture(size, pixelFormat: cache.pixelFormat)
            let pass = SceneMainPassEncoder(commandBuffer: buffer, target: source,
                clearColor: color, clearEnabled: true)
            precondition(pass.finishEnsuringClear())
            let renderer = SceneMetalRenderer(renderDescriptor: .init(hdrEnabled: false,
                camera: .init(clearColor: [0, 0, 0], bloom: .disabled)),
                imageCompositor: .init(resolvedMaterialRuntime: runtime),
                bloomPostProcess: nil, displayMappingPostProcess: nil)
            checks["snapshot-\(cache.pixelFormat.rawValue)-\(epoch)-cannotMarkDisplayOutput"] =
                !runtime.markSceneColorOutput(on: buffer, mapped: false)
            if copyFault { MWXArmBlitFault(buffer, 1) }
            let copied = renderer.copySceneColor(source, to: value.raw, commandBuffer: buffer)
            if copyFault { MWXArmBlitFault(buffer, 0) }
            if copied { precondition(runtime.markSceneColorSnapshot(on: buffer)) }
            else { precondition(runtime.detachPreparedSceneColorSnapshot(on: buffer)) }
            precondition(runtime.sealFrame(on: buffer)); _ = runtime.endFrame()
            return (value, buffer)
        }
        let red = MTLClearColorMake(1, 0, 0, 1)
        let green = MTLClearColorMake(0, 1, 0, 1)
        for format: MTLPixelFormat in [.bgra8Unorm, .rgba8Unorm, .rgba16Float] {
            let label = "snapshot-\(format.rawValue)"
            let runtime = coordinator()
            let cache = SceneOffscreenTexturePool(device: device, pixelFormat: format,
                maxDimension: 64, residentByteBudget: 1_048_576)
            let (first, firstBuffer) = snapshot(runtime, cache, index: 7, epoch: 701, color: red)
            checks["\(label)-firstPendingUnavailable"] = first.previous == nil && first.previousReceipt == nil
                && first.display == nil && first.requiresDraw && runtime.completedSceneColor == nil
                && runtime.shouldDeferFrame && !runtime.markSceneColorOutput(on: firstBuffer, mapped: false)
            checks["\(label)-realFormatAndCount"] = first.raw.pixelFormat == format
                && cache.residentTextureCount == 2
                && cache.residentByteCost == 4 * 4 * (format == .rgba16Float ? 8 : 4) * 2
            completeOn(runtime, firstBuffer)
            let firstBytes = bytes(first.raw)
            checks["\(label)-rawCopyPreservesColor"] = format == .rgba16Float
                ? read(first.raw) == [1, 0, 0, 1]
                : Array(firstBytes.prefix(4)) == (format == .bgra8Unorm ? [0, 0, 255, 255] : [255, 0, 0, 255])
            checks["\(label)-completedMetadataOnly"] = runtime.completedSceneColor?.persistenceReservation == nil
                && runtime.completedSceneColor?.producerReceipt == first.producerReceipt
                && cache.allocationCache.locked { cache.allocationCache.residents.values.allSatisfy { !$0.isPinned } }
            let (failedCandidate, failedBuffer) = snapshot(runtime, cache, index: 7, epoch: 702, color: green)
            checks["\(label)-sameFrameUsesOtherMember"] = failedCandidate.requiresDraw
                && failedCandidate.raw !== first.raw && failedCandidate.previous === first.raw
                && failedCandidate.previousReceipt == first.producerReceipt
                && failedCandidate.producerReceipt.frameIndex == first.producerReceipt.frameIndex
                && failedCandidate.producerReceipt.frameEpoch == 702
                && failedCandidate.producerReceipt.commandBufferObservationID
                    != first.producerReceipt.commandBufferObservationID
            completeOn(runtime, failedBuffer, status: .failed)
            checks["\(label)-sameFrameFailurePreservesBytesAndIdentity"] = bytes(first.raw) == firstBytes
                && runtime.completedSceneColor?.producerReceipt == first.producerReceipt
                && runtime.pendingSubmissions.isEmpty && !runtime.shouldDeferFrame
            let (second, secondBuffer) = snapshot(runtime, cache, index: 7, epoch: 703, color: green)
            completeOn(runtime, secondBuffer)
            let secondBytes = bytes(second.raw)
            checks["\(label)-secondSuccessHasActualReceipt"] = secondBytes != firstBytes
                && second.previousReceipt == first.producerReceipt
                && runtime.completedSceneColor?.producerReceipt == second.producerReceipt
                && second.producerReceipt.frameEpoch == 703
            let (_, cancelledBuffer) = snapshot(runtime, cache, index: 8, epoch: 704, color: red)
            runtime.cancelUnsubmittedFrame(on: cancelledBuffer)
            checks["\(label)-cancelPreservesCompleted"] = bytes(second.raw) == secondBytes
                && runtime.completedSceneColor?.producerReceipt == second.producerReceipt
                && !runtime.shouldDeferFrame
            let (_, detachedBuffer) = snapshot(runtime, cache, index: 8, epoch: 705,
                color: red, copyFault: true)
            checks["\(label)-copyFailureRetainsUntilTerminal"] = runtime.shouldDeferFrame
                && runtime.pendingSubmissions[0].sceneColor?.snapshotPublicationDetached == true
                && cache.allocationCache.locked { cache.allocationCache.residents.values.contains { $0.isPinned } }
            completeOn(runtime, detachedBuffer)
            checks["\(label)-copyFailureKeepsPrior"] = runtime.completedSceneColor?.producerReceipt == second.producerReceipt
                && bytes(second.raw) == secondBytes && !runtime.shouldDeferFrame
            let (_, staleBuffer) = snapshot(runtime, cache, index: 9, epoch: 706, color: red)
            runtime.invalidate(reason: .allocationReprepare); cache.reset()
            checks["\(label)-resetRetainsInFlightPair"] = cache.residentTextureCount == 2
            completeOn(runtime, staleBuffer)
            checks["\(label)-staleCompletionReleasesWithoutPromotion"] = runtime.completedSceneColor == nil
                && cache.residentByteCost == 0 && !runtime.shouldDeferFrame
            let (resizedSnapshot, resizedBuffer) = snapshot(runtime, cache, index: 7, epoch: 707,
                size: 8, color: green)
            checks["\(label)-resizeHasNoOldHistory"] = resizedSnapshot.previous == nil
                && resizedSnapshot.previousReceipt == nil && resizedSnapshot.raw.width == 8
            completeOn(runtime, resizedBuffer)
            runtime.invalidate(reason: .surfaceStop); cache.reset()
            checks["\(label)-stopReleasesSnapshotCache"] = cache.residentByteCost == 0

            let rawCost = 4 * 4 * (format == .rgba16Float ? 8 : 4)
            let exactCache = SceneOffscreenTexturePool(device: device, pixelFormat: format,
                maxDimension: 64, residentByteBudget: rawCost * 2)
            let exactLease = exactCache.reserveSceneColor(width: 4, height: 4, intent: .snapshot)
            checks["\(label)-exactTwoTargetBudget"] = exactLease != nil
                && exactCache.residentByteCost == rawCost * 2 && exactCache.residentTextureCount == 2
            exactLease?.release(); exactCache.reset()
            let shortCache = SceneOffscreenTexturePool(device: device, pixelFormat: format,
                maxDimension: 64, residentByteBudget: rawCost * 2 - 1)
            checks["\(label)-shortBudgetPublishesNothing"] = shortCache.reserveSceneColor(
                width: 4, height: 4, intent: .snapshot) == nil && shortCache.residentTextureCount == 0
        }

        // A completed optional pair must yield to the next frame's actual
        // mandatory scratch. No admission retry or fake history is involved.
        let yieldingOwner = coordinator()
        let yieldingPool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba8Unorm,
            maxDimension: 64, residentByteBudget: 4 * 4 * 4 * 2)
        let (yielded, yieldedBuffer) = snapshot(yieldingOwner, yieldingPool, index: 1, epoch: 11, color: red)
        completeOn(yieldingOwner, yieldedBuffer)
        begin(yieldingOwner, 2, frameEpoch: 12)
        let mandatoryBuffer = queue.makeCommandBuffer()!
        let mandatoryScratch = yieldingOwner.reserveDisplayScratch(pool: yieldingPool, width: 4,
            height: 4, commandBuffer: mandatoryBuffer)
        let unavailable = yieldingOwner.reserveSceneColor(pool: yieldingPool, width: 4, height: 4,
            frameIndex: 2, commandBuffer: mandatoryBuffer, intent: .snapshot)
        checks["snapshotYieldsToMandatoryNextFrame"] = mandatoryScratch != nil && unavailable == nil
            && yieldingPool.residentTextureCount == 1
            && yieldingPool.allocationCache.allocation(for: yielded.lease.key) == nil
        let mandatoryPass = SceneMainPassEncoder(commandBuffer: mandatoryBuffer, target: mandatoryScratch!,
            clearColor: green, clearEnabled: true)
        precondition(mandatoryPass.finishEnsuringClear())
        precondition(yieldingOwner.sealFrame(on: mandatoryBuffer)); _ = yieldingOwner.endFrame()
        completeOn(yieldingOwner, mandatoryBuffer)
        checks["mandatoryFrameCompletesWithOptionalUnavailable"] = yieldingOwner.pendingSubmissions.isEmpty
            && !yieldingOwner.shouldDeferFrame && bytes(mandatoryScratch!) != bytes(yielded.raw)
        let (restarted, restartBuffer) = snapshot(yieldingOwner, yieldingPool, index: 3, epoch: 13, color: green)
        checks["evictedSnapshotMetadataCannotBecomeReady"] = restarted.previous == nil
            && restarted.previousReceipt == nil
            && restarted.producerReceipt.allocationGeneration != yielded.producerReceipt.allocationGeneration
        completeOn(yieldingOwner, restartBuffer)
        let (availableAgain, availableBuffer) = snapshot(yieldingOwner, yieldingPool,
            index: 4, epoch: 14, color: red)
        checks["snapshotRestartsAfterMandatoryEviction"] = availableAgain.previous === restarted.raw
            && availableAgain.previousReceipt == restarted.producerReceipt
        yieldingOwner.cancelUnsubmittedFrame(on: availableBuffer)
        yieldingOwner.invalidate(reason: .surfaceStop); yieldingPool.reset()

        // Detaching a copied snapshot keeps both its encoded allocation and an
        // independent mandatory display pin until this exact buffer completes.
        let detachedOwner = coordinator(), detachedPool = pool()
        begin(detachedOwner, 1)
        let detachBuffer = queue.makeCommandBuffer()!
        let displayPin = detachedOwner.reserveDisplayScratch(pool: detachedPool, width: 4,
            height: 4, commandBuffer: detachBuffer)!
        let detached = detachedOwner.reserveSceneColor(pool: detachedPool, width: 4, height: 4,
            frameIndex: 1, commandBuffer: detachBuffer, intent: .snapshot)!
        let detachedPass = SceneMainPassEncoder(commandBuffer: detachBuffer, target: displayPin,
            clearColor: red, clearEnabled: true)
        precondition(detachedPass.finishEnsuringClear())
        copy(displayPin, detached.raw, detachBuffer)
        precondition(detachedOwner.markSceneColorSnapshot(on: detachBuffer))
        precondition(detachedOwner.detachPreparedSceneColorSnapshot(on: detachBuffer))
        checks["detachPreservesMandatoryDisplayScratch"] = detachedOwner.preparedDisplayScratch != nil
            && detachedOwner.preparedSceneColor?.snapshotPublicationDetached == true
        precondition(detachedOwner.sealFrame(on: detachBuffer)); _ = detachedOwner.endFrame()
        detachedPool.reset()
        checks["detachEncodedPinsRetainedThroughTerminal"] = detachedPool.residentTextureCount == 3
        completeOn(detachedOwner, detachBuffer)
        checks["detachCannotPublishAndReleasesAtTerminal"] = detachedOwner.completedSceneColor == nil
            && detachedPool.residentByteCost == 0 && !detachedOwner.shouldDeferFrame

        let exactPersistence = pool(4 * 4 * 8 * 3)
        let exactPersistenceLease = exactPersistence.reserveSceneColor(width: 4, height: 4)
        checks["persistenceStillRequiresThreeTargets"] = exactPersistenceLease?.targets.display != nil
            && exactPersistence.residentTextureCount == 3 && exactPersistence.residentByteCost == 4 * 4 * 8 * 3
        exactPersistenceLease?.release(); exactPersistence.reset()

        let unmarkedOwner = coordinator(), unmarkedPool = pool()
        begin(unmarkedOwner, 1)
        let unmarkedBuffer = queue.makeCommandBuffer()!
        let unmarked = unmarkedOwner.reserveSceneColor(pool: unmarkedPool, width: 4, height: 4,
            frameIndex: 1, commandBuffer: unmarkedBuffer, intent: .snapshot)
        checks["snapshotCannotSealWithoutTerminalCopy"] = unmarked != nil
            && !unmarkedOwner.sealFrame(on: unmarkedBuffer)
            && unmarkedOwner.completedSceneColor == nil
        _ = unmarkedOwner.endFrame(); unmarkedPool.reset()
        begin(unmarkedOwner, 2)
        let persistenceBuffer = queue.makeCommandBuffer()!
        let persistence = unmarkedOwner.reserveSceneColor(pool: unmarkedPool, width: 4, height: 4,
            frameIndex: 2, commandBuffer: persistenceBuffer)
        checks["snapshotAPIsCannotDetachMandatoryPersistence"] = persistence != nil
            && !unmarkedOwner.markSceneColorSnapshot(on: persistenceBuffer)
            && !unmarkedOwner.detachPreparedSceneColorSnapshot(on: persistenceBuffer)
            && unmarkedOwner.preparedSceneColor?.intent == .persistence
        unmarkedOwner.cancelUnsubmittedFrame(on: persistenceBuffer); _ = unmarkedOwner.endFrame()
        unmarkedPool.reset()
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
            && abs(read(largeSource)[0] - 1.0) < 1.0 / 1024.0
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
