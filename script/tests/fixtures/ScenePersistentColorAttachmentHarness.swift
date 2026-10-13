import Foundation
import Metal
import CoreGraphics

@main enum ScenePersistentColorAttachmentHarness {
    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
        typealias Mapping = SceneDisplayMappingPostProcess
        MWXArmPipelineFault(device, 0)
        let mapping = Mapping(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)!
        let preparedPipelines = MWXPipelineAttempts()
        func texture(_ w: Int, _ h: Int, format: MTLPixelFormat = .rgba16Float,
                     usage: MTLTextureUsage = [.shaderRead, .renderTarget]) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: w, height: h, mipmapped: false)
            d.storageMode = .shared; d.usage = usage
            return device.makeTexture(descriptor: d)!
        }
        func fill(_ target: MTLTexture, _ values: [Float16]) {
            values.withUnsafeBytes { target.replace(region: MTLRegionMake2D(
                0, 0, target.width, target.height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: target.width * 8) }
        }
        func read(_ target: MTLTexture) -> [Float16] {
            var values = [Float16](repeating: 0, count: target.width * target.height * 4)
            values.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,
                bytesPerRow: target.width * 8, from: MTLRegionMake2D(
                    0, 0, target.width, target.height), mipmapLevel: 0) }
            return values
        }
        func sameBits(_ a: [Float16], _ b: [Float16]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { pair in pair.0.bitPattern == pair.1.bitPattern }
        }
        func mode(_ pass: Mapping, _ target: MTLTexture, clear: Bool = true,
                  persistence: Bool = false, shadow: Bool = false, source: Bool = false,
                  reflection: () -> Bool = { false }) -> Mapping.Input {
            pass.input(for: target, clearEnabled: clear, hasPersistentSceneColor: persistence,
                hasShadowReceiver: shadow, hasSourceMaterials: source, requiresReflection: reflection)
        }
        let probe = texture(5, 8)
        let supported = mode(mapping, probe) == .colorAttachment
        var admission: [String: Bool] = [:], pixels: [String: Bool] = [:], faults: [String: Bool] = [:]
        for axis in ["clear", "persistence", "shadow", "source"] {
            var scans = 0
            let input = mode(mapping, probe, clear: axis != "clear",
                persistence: axis == "persistence", shadow: axis == "shadow", source: axis == "source",
                reflection: { scans += 1; return false })
            admission["\(axis)-keepsLegacyWithoutReflectionScan"] = input == .textureSource && scans == 0
        }
        var scans = 0
        admission["reflectionDemandKeepsLegacy"] = mode(mapping, probe,
            reflection: { scans += 1; return true }) == .textureSource
            && scans == (supported ? 1 : 0)
        admission["nonRenderTargetKeepsLegacy"] = mode(mapping,
            texture(5, 8, usage: .shaderRead)) == .textureSource
        for format: MTLPixelFormat in [.bgra8Unorm, .rgba8Unorm_srgb] {
            let pass = Mapping(device: device, pixelFormat: format, hdrEnabled: true)!
            admission["format-\(format.rawValue)-keepsLegacy"] = mode(pass,
                texture(5, 8, format: format)) == .textureSource
        }
        MWXArmPipelineFault(device, 0)
        admission["nonHDRPreparesNoPipeline"] = Mapping(device: device,
            pixelFormat: .rgba16Float, hdrEnabled: false) == nil && MWXPipelineAttempts() == 0

        // Actual pool counterexample, in eight-byte units: G40/T40/Z50/source20.
        // Coupling keeps legacy. Pinned G/T reject Z, then the original source fits.
        let budgetPool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
            maxDimension: 64, residentByteBudget: 800)
        let budgetBuffer = queue.makeCommandBuffer()!
        let coupledMode = mode(mapping, probe, shadow: true, source: true)
        let protected = budgetPool.reserveCompositionTargets(
            dimensions: [(8, 5), (5, 8)], commandBuffer: budgetBuffer)!
        let declinedShadow = budgetPool.reserveModelShadow(slot: 0,
            width: 10, height: 10, commandBuffer: budgetBuffer)
        let admittedSource = budgetPool.reserveSourceMaterial(layerID: 91,
            width: 4, height: 5, commandBuffer: budgetBuffer)
        admission["realBudgetKeepsOldSourceAndShadowQualification"] = coupledMode == .textureSource
            && declinedShadow == nil && admittedSource != nil && budgetPool.residentByteCost == 800
        protected.forEach { $0.pin.release() }; admittedSource?.pin.release(); budgetPool.reset()
        admission["budgetCancellationReleasesAllResidency"] = budgetPool.residentByteCost == 0

        var comparedPixels = 0
        if supported {
            let encodedSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)!
            let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
            let channels: [Float16] = [0, 0.01, 0.25, 0.5, 0.75, 1, 1.25, 2, 4,
                -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude]
            var exact = true, oracle = true, sourceKept = true, alphaKept = true
            for (w, h) in [(1, 1), (3, 7), (31, 17), (45, 23)] {
                var input: [Float16] = []
                for y in 0..<h { for x in 0..<w {
                    let i = x * 7 + y * 13
                    input += [channels[i % channels.count], channels[(i + 3) % channels.count],
                        channels[(i + 7) % channels.count], [Float16(0), 0.25, 0.5, 1][i % 4]]
                } }
                let outputs: [Mapping.Output] = [.sRGB, .extendedLinearSRGB(headroom: 1),
                    .extendedLinearSRGB(headroom: 1.2), .extendedLinearSRGB(headroom: 4),
                    .extendedLinearSRGB(headroom: 16), .extendedLinearSRGB(headroom: 0),
                    .extendedLinearSRGB(headroom: .nan), .extendedLinearSRGB(headroom: .infinity)]
                for output in outputs {
                    let source = texture(w, h), native = texture(w, h, usage: .renderTarget), reference = texture(w, h)
                    fill(source, input); fill(native, input)
                    let cb = queue.makeCommandBuffer()!
                    precondition(mapping.encode(source: source, target: reference,
                        commandBuffer: cb, output: output))
                    precondition(mapping.encodeAttachment(target: native, commandBuffer: cb, output: output))
                    cb.commit(); cb.waitUntilCompleted()
                    precondition(cb.status == .completed && cb.error == nil)
                    let actual = read(native), original = read(source)
                    exact = exact && sameBits(actual, read(reference))
                    sourceKept = sourceKept && sameBits(original, input)
                    for i in actual.indices {
                        if i % 4 == 3 {
                            alphaKept = alphaKept && actual[i].bitPattern == input[i].bitPattern
                        } else {
                            let v = Float(input[i]), expected: Float
                            if !v.isFinite || v <= 0 { expected = 0 }
                            else if !output.isLinear { expected = min(v, 1) }
                            else {
                                let color = CGColor(colorSpace: encodedSpace,
                                    components: [CGFloat(v), CGFloat(v), CGFloat(v), 1])!
                                expected = min(output.uniform, Float(color.converted(to: linearSpace,
                                    intent: .relativeColorimetric, options: nil)!.components![0]))
                            }
                            oracle = oracle && actual[i].isFinite
                                && abs(Float(actual[i]) - expected) <= 0.002 * max(1, expected)
                        }
                    }
                    comparedPixels += w * h
                }
            }
            pixels["allPixelsEdgesAndStripDiagonalBitExactWithDistinctRoute"] = exact
            pixels["SDRAndPublicColorSyncOracle"] = oracle
            pixels["distinctSourceUnchanged"] = sourceKept
            pixels["allAlphaBitsPreserved"] = alphaKept
            pixels["noPipelineCompilationDuringPixelEncoding"] = MWXPipelineAttempts() == 0

            // Exercise the real HDR Bloom producer before either display input.
            // Nonzero neighboring pixels prove Bloom ran, rather than only
            // checking authored metadata or a successful owner construction.
            let bloom = SceneBloomPostProcess(device: device,
                pixelFormat: .rgba16Float, hdrEnabled: true)!
            let configuration = SceneBloomConfiguration(enabled: true, strength: 1,
                threshold: 0.65, tint: SIMD3(1, 1, 1), hdr: .init(strength: 1,
                    threshold: 1, scatter: 0.7, feather: 1, iterations: 2))
            let bloomPrepared = MWXPipelineAttempts()
            var bloomExact = true, bloomChangedPixels = true
            for output in [Mapping.Output.sRGB, .extendedLinearSRGB(headroom: 4)] {
                let w = 41, h = 29
                var input = [Float16](repeating: 0, count: w * h * 4)
                for i in 0..<(w * h) { input[i * 4 + 3] = 0.5 }
                // A bright region survives the producer's downsample/threshold.
                // A single texel can legitimately fall below that threshold.
                for y in (h / 2 - 3)...(h / 2 + 3) {
                    for x in (w / 2 - 3)...(w / 2 + 3) {
                        let i = (y * w + x) * 4
                        input[i] = 4; input[i + 1] = 2; input[i + 2] = 1.5
                    }
                }
                let native = texture(w, h), original = texture(w, h), reference = texture(w, h)
                fill(native, input); fill(original, input)
                let producer = queue.makeCommandBuffer()!
                precondition(bloom.encode(configuration: configuration, source: native, commandBuffer: producer))
                precondition(bloom.encode(configuration: configuration, source: original, commandBuffer: producer))
                producer.commit(); producer.waitUntilCompleted()
                precondition(producer.status == .completed && producer.error == nil)
                let prepared = read(native)
                bloomChangedPixels = bloomChangedPixels && prepared.indices.contains {
                    $0 % 4 != 3 && input[$0] == 0 && prepared[$0] > 0
                }
                let terminal = queue.makeCommandBuffer()!
                precondition(mapping.encodeAttachment(target: native, commandBuffer: terminal, output: output))
                precondition(mapping.encode(source: original, target: reference, commandBuffer: terminal, output: output))
                terminal.commit(); terminal.waitUntilCompleted()
                precondition(terminal.status == .completed && terminal.error == nil)
                bloomExact = bloomExact && sameBits(read(native), read(reference))
                comparedPixels += w * h
            }
            pixels["actualBloomChangesNeighborsBeforeBitExactDisplayInputs"] = bloomExact && bloomChangedPixels
            pixels["postBloomDisplayInputsBitExact"] = bloomExact
            pixels["HDRBloomWritesPreviouslyBlackNeighbors"] = bloomChangedPixels
            pixels["preparedBloomAndDisplayEncodingDoNotCompile"] = MWXPipelineAttempts() == bloomPrepared

            // Optional PSO/function failures keep the mandatory owner and transfer.
            MWXArmPipelineFault(device, 2)
            let noOptionalPipeline = Mapping(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)
            let attempts = MWXPipelineAttempts(); MWXArmPipelineFault(device, 0)
            faults["optionalPipelineFailureKeepsRequiredOwner"] = noOptionalPipeline != nil
                && attempts == 2 && mode(noOptionalPipeline!, probe) == .textureSource
            MWXArmMissingAttachmentFunction(device.makeDefaultLibrary()!, true)
            let noOptionalFunction = Mapping(device: device, pixelFormat: .rgba16Float, hdrEnabled: true)
            let missing = MWXMissingFunctionAttempts()
            MWXArmMissingAttachmentFunction(device.makeDefaultLibrary()!, false)
            faults["missingOptionalFunctionKeepsRequiredOwner"] = noOptionalFunction != nil
                && missing == 1 && mode(noOptionalFunction!, probe) == .textureSource
            for (index, pass) in [noOptionalPipeline!, noOptionalFunction!].enumerated() {
                let cb = queue.makeCommandBuffer()!, src = texture(5, 8), dst = texture(5, 8)
                fill(src, Array(repeating: [Float16(0.5), 1, 4, 1], count: 40).flatMap { $0 })
                precondition(pass.encode(source: src, target: dst, commandBuffer: cb,
                    output: .extendedLinearSRGB(headroom: 4)))
                cb.commit(); cb.waitUntilCompleted()
                let values = read(dst)
                faults["preparationFailure-\(index)-stillDecodesTransfer"] = cb.status == .completed
                    && abs(Float(values[0]) - 0.214041) < 0.001 && values[2] == 4 && values[3] == 1
            }

            // Real terminal, pool and submission owners. No graph/history is invented.
            typealias Coordinator = SceneResolvedMaterialSubmissionCoordinator
            let owner = Coordinator(device: device, capabilities: .init(admissionCandidates: [],
                materialCatalog: .init(entries: [:], resourceDemandIssues: [])),
                capturesExecutionObservations: false, logSink: { _ in })
            let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
                maxDimension: 64, residentByteBudget: 320)
            let renderer = SceneMetalRenderer(renderDescriptor: .init(hdrEnabled: true,
                camera: .init(clearColor: [0, 0, 0], bloom: .disabled)),
                imageCompositor: .init(resolvedMaterialRuntime: owner),
                bloomPostProcess: nil, displayMappingPostProcess: mapping)
            for (index, output) in [Mapping.Output.sRGB, .extendedLinearSRGB(headroom: 4),
                                    .extendedLinearSRGB(headroom: 4)].enumerated() {
                let snapshot = SceneDynamicSnapshotResolver().resolve(frameIndex: UInt64(index),
                    generation: UInt64(index), definitions: []).snapshot
                owner.beginFrame(textureSnapshot: .init(frameEpoch: UInt64(index),
                    frameIndex: UInt64(index), entries: [:]), dynamicSnapshot: snapshot,
                    frameInputs: .init(frameIndex: UInt64(index), screenSize: CGSize(width: 5, height: 8),
                        sceneTime: Float(index), dayTime: 0, frameTime: 1 / 60,
                        pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
                let cb = queue.makeCommandBuffer()!, target = texture(5, 8)
                let input: [Float16] = Array(repeating: [0.5, 1, 4, 1], count: 40).flatMap { $0 }
                fill(target, input)
                let capacity = pool.reserveCompositionTargets(dimensions: [(8, 5)], commandBuffer: cb)!
                let before = ScenePerformanceCounterHub.shared.snapshot()
                MWXArmEncoderFault(cb, index < 2 ? 1 : 0)
                let outcome = renderer.encodeTerminalColor(sourceCompleted: true, sceneColor: nil, target: target,
                    offscreenTexturePool: pool, dynamicValues: snapshot, commandBuffer: cb,
                    output: output, input: mode(mapping, target))
                let encoderAttempts = MWXEncoderAttempts(); MWXArmEncoderFault(cb, 0)
                let after = ScenePerformanceCounterHub.shared.snapshot()
                faults["terminal-\(index)-usesNoCopyOrExtraCapacity"] =
                    before[.textureCopyPasses, default: 0] == after[.textureCopyPasses, default: 0]
                    && before[.textureCopyBytes, default: 0] == after[.textureCopyBytes, default: 0]
                    && pool.residentByteCost == 320 && encoderAttempts == 1
                if index == 1 {
                    faults["linearEncoderFailureRejectsSubmission"] = outcome == .dropped(
                        reasonCode: "scene-linear-display-export-unavailable")
                    owner.cancelUnsubmittedFrame(on: cb); _ = owner.endFrame()
                    faults["linearFailureDoesNotEnqueueUnconvertedColor"] = cb.status == .notEnqueued
                        && owner.pendingSubmissions.isEmpty && sameBits(read(target), input)
                } else {
                    cb.commit(); cb.waitUntilCompleted()
                    faults["terminal-\(index)-completes"] = outcome == nil && cb.status == .completed
                    if index == 0 { faults["SDREncoderFailureKeepsSafeOriginal"] = sameBits(read(target), input) }
                    else { faults["nextFrameRecoversLinearMapping"] =
                        abs(Float(read(target)[0]) - 0.214041) < 0.001 && read(target)[2] == 4 }
                }
                capacity.forEach { $0.pin.release() }; pool.reset()
                faults["terminal-\(index)-releasesResidency"] = pool.residentByteCost == 0
            }
            faults["terminalNeverRetainsHistory"] = owner.completedSceneColor == nil
            // A real main-clear failure supplies the existing completion fact
            // to the real terminal. Test both display inputs without prefilling.
            for (i, inputMode) in [Mapping.Input.colorAttachment, .textureSource].enumerated() {
                let storage = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
                    maxDimension: 64, residentByteBudget: 1_048_576)
                for fails in [true, false] {
                    let frame = UInt64(10 + i * 2 + (fails ? 0 : 1))
                    let snapshot = SceneDynamicSnapshotResolver().resolve(
                        frameIndex: frame, generation: frame, definitions: []).snapshot
                    owner.beginFrame(textureSnapshot: .init(frameEpoch: frame, frameIndex: frame, entries: [:]),
                        dynamicSnapshot: snapshot, frameInputs: .init(frameIndex: frame,
                            screenSize: CGSize(width: 5, height: 8), sceneTime: Float(frame),
                            dayTime: 0, frameTime: 1 / 60,
                            pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
                    let cb = queue.makeCommandBuffer()!, target = texture(5, 8)
                    let main = SceneMainPassEncoder(commandBuffer: cb, target: target,
                        clearColor: MTLClearColorMake(0.5, 1, 4, 1), clearEnabled: true)
                    MWXArmEncoderFault(cb, fails ? 1 : 0)
                    let ready = main.finishEnsuringClear(), attempts = MWXEncoderAttempts()
                    let outcome = renderer.encodeTerminalColor(sourceCompleted: ready,
                        sceneColor: nil, target: target, offscreenTexturePool: storage,
                        dynamicValues: snapshot, commandBuffer: cb,
                        output: .extendedLinearSRGB(headroom: 4), input: inputMode)
                    let finalAttempts = MWXEncoderAttempts(); MWXArmEncoderFault(cb, 0)
                    if fails {
                        faults["main-\(i)-failureRejectsBothInputsBeforeReading"] = !ready
                            && attempts == 1 && finalAttempts == 1 && storage.residentByteCost == 0
                            && outcome == .dropped(reasonCode: "scene-color-main-encoder-unavailable")
                            && cb.status == .notEnqueued
                        owner.cancelUnsubmittedFrame(on: cb); _ = owner.endFrame()
                    } else {
                        let observation = owner.commandBufferRecords[ObjectIdentifier(cb)]?.observationID
                        cb.commit(); cb.waitUntilCompleted()
                        if let observation {
                            owner.completeCommandBuffer(identity: ObjectIdentifier(cb),
                                observationID: observation, status: .completed)
                        }
                        faults["main-\(i)-nextFrameRecovers"] = ready && outcome == nil
                            && cb.status == .completed && abs(Float(read(target)[0]) - 0.214041) < 0.001
                            && read(target)[2] == 4
                    }
                    main.cancelCompositionPins(); storage.reset()
                    faults["main-\(i)-\(fails)-doesNotLeak"] = storage.residentByteCost == 0
                        && owner.pendingSubmissions.isEmpty
                }
            }
        }
        let result: [String: Any] = ["nativeSupported": supported, "preparedPipelines": preparedPipelines,
            "comparedPixels": comparedPixels, "admissionChecks": admission,
            "pixelChecks": pixels, "failureChecks": faults]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                     encoding: .utf8)!)
    }
}
