import CoreGraphics
import Foundation
import Metal
import simd

// Invalid inputs, local negative cache, reset, warmup and original archive tier.
struct SceneResolvedMaterialPassPipelineResult {
    let facts: [String: Bool]
    let crossDeviceExercised: Bool
}

private func waitForArchivePublication(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.01)
    } while Date() < deadline
    return condition()
}

func runSceneResolvedMaterialPassPipelineCases(
    device: MTLDevice,
    queue: MTLCommandQueue,
    encoder: SceneResolvedMaterialPassEncoder,
    baseline: Program,
    rgbaTarget: MTLTexture,
    second: SceneResolvedMaterialPassEncoder.PreparedPass?
) -> SceneResolvedMaterialPassPipelineResult {
    let readOnlyTarget = target(device: device, usage: .shaderRead)
    let missingRenderTargetRejected = encoder.prepare(
        program: baseline,
        target: readOnlyTarget
    ) == nil
    let writeOnlyTarget = target(device: device, usage: .renderTarget)
    let missingShaderReadRejected = encoder.prepare(
        program: baseline,
        target: writeOnlyTarget
    ) == nil

    let noReadTexture = texture(device: device, usage: .renderTarget)
    let inputUsageRejectedUpstream = program(
        device: device,
        marker: 7,
        outputSlot: 0,
        slot0Texture: noReadTexture
    ) == nil
    let malformedUniformRejectedUpstream = program(
        device: device,
        marker: 8,
        outputSlot: 0,
        malformedUniform: true
    ) == nil

    let invalidMetal = program(
        device: device,
        marker: 9,
        outputSlot: 0,
        uniformName: "operator"
    )!
    let attemptsBeforeFailure = encoder.pipelineCompilationAttemptCount
    prepareMaterialPipeline(invalidMetal, encoder: encoder, target: rgbaTarget)
    let firstFailure = encoder.prepare(
        program: invalidMetal,
        target: rgbaTarget
    ) == nil
    let attemptsAfterFailure = encoder.pipelineCompilationAttemptCount
    let secondFailure = encoder.prepare(
        program: invalidMetal,
        target: rgbaTarget
    ) == nil
    let failureNegativeCached = firstFailure
        && secondFailure
        && attemptsAfterFailure == attemptsBeforeFailure + 1
        && encoder.pipelineCompilationAttemptCount == attemptsAfterFailure
        && encoder.failedPipelineCount == 1

    let preparedBeforeReset = second
    let cachedPipelinesBeforeReset = encoder.cachedPipelineCount
    let attemptsBeforeReset = encoder.pipelineCompilationAttemptCount
    let failuresBeforeReset = encoder.failedPipelineCount
    encoder.reset()
    let resetPreservedHotCache =
        encoder.cachedPipelineCount == cachedPipelinesBeforeReset
        && encoder.pipelineCompilationAttemptCount == attemptsBeforeReset
        && encoder.failedPipelineCount == failuresBeforeReset
    var stalePreparedRejected = false
    if let preparedBeforeReset, let staleCommand = queue.makeCommandBuffer() {
        stalePreparedRejected = !encoder.encode(
            preparedBeforeReset,
            commandBuffer: staleCommand
        )
    }
    let attemptsBeforePrepareAfterReset =
        encoder.pipelineCompilationAttemptCount
    let preparedAfterReset = encoder.prepare(
        program: baseline,
        target: rgbaTarget
    )
    let prepareAfterResetReusesPipeline = preparedAfterReset != nil
        && encoder.pipelineCompilationAttemptCount
            == attemptsBeforePrepareAfterReset

    let warmupEncoder = SceneResolvedMaterialPassEncoder(device: device)!
    let coldMiss = warmupEncoder.prepareResult(program: baseline, target: rgbaTarget)
    let coldMissDoesNotCompile: Bool
    if case .failure(.pipelineNotPrepared) = coldMiss {
        coldMissDoesNotCompile = warmupEncoder.pipelineCompilationAttemptCount == 0
            && warmupEncoder.metalLibraryCompilationAttemptCount == 0
            && warmupEncoder.cachedPipelineCount == 0
    } else { coldMissDoesNotCompile = false }
    let warmupPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
        identity: "fixture:baseline",
        prepared: baseline.preparedAssembly,
        pixelFormat: .rgba8Unorm,
        writeMask: .all,
        device: device
    )!
    let warmupReport = warmupEncoder.warmup([warmupPlan, warmupPlan])
    let attemptsAfterWarmup = warmupEncoder.pipelineCompilationAttemptCount
    let warmupPrepared = warmupEncoder.prepare(
        program: baseline,
        target: rgbaTarget
    )
    let launchWarmupConsumedWithoutCompile = warmupPrepared != nil
        && warmupEncoder.pipelineCompilationAttemptCount == attemptsAfterWarmup
        && warmupEncoder.launchWarmupHitCount == 1

    let sharedLibraryWarmupEncoder =
        SceneResolvedMaterialPassEncoder(device: device)!
    let sharedLibraryBGRAPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
        identity: "fixture:baseline-bgra",
        prepared: baseline.preparedAssembly,
        pixelFormat: .bgra8Unorm,
        writeMask: .all,
        device: device
    )!
    let sharedLibraryWarmupReport = sharedLibraryWarmupEncoder.warmup([
        warmupPlan, sharedLibraryBGRAPlan,
    ])
    let concurrentWarmupSharesMetalLibrary =
        sharedLibraryWarmupReport.uniqueKeyCount == 2
        && sharedLibraryWarmupReport.readyKeyCount == 2
        && sharedLibraryWarmupReport.compilationAttemptCount == 2
        && sharedLibraryWarmupEncoder.metalLibraryCompilationAttemptCount == 1

    let invalidWarmupEncoder = SceneResolvedMaterialPassEncoder(device: device)!
    let invalidWarmupPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
        identity: "fixture:invalid",
        prepared: invalidMetal.preparedAssembly,
        pixelFormat: .rgba8Unorm,
        writeMask: .all,
        device: device
    )!
    let invalidWarmupReport = invalidWarmupEncoder.warmup([invalidWarmupPlan])
    let invalidAttemptsAfterWarmup =
        invalidWarmupEncoder.pipelineCompilationAttemptCount
    let invalidWarmupNegativeCached = invalidWarmupEncoder.prepare(
        program: invalidMetal,
        target: rgbaTarget
    ) == nil
        && invalidWarmupEncoder.pipelineCompilationAttemptCount
            == invalidAttemptsAfterWarmup
        && invalidWarmupEncoder.failedPipelineCount == 1
        && invalidWarmupEncoder.launchWarmupFailureHitCount == 1

    // Binary archive warm start. The tier root is isolated through
    // MWX_SCENE_PIPELINE_BINARY_ARCHIVE; the probe reuses the baseline
    // admission path with a dedicated fragment source so no earlier
    // fixture shares its identity.
    var binaryArchivePublishedOnFirstLaunch = false
    var binaryArchiveHitOnSecondLaunch = false
    var binaryArchiveSafeMissOnCorruptEntry = false
    var binaryArchiveIdentitySeparatesFormats = false
    var framePreparationSkipsArchiveTier = false
    var binaryArchiveReadyBeforePublication = false
    var binaryArchiveEncodesBeforePublication = false
    var binaryArchiveDeniedRootKeepsReadyOutput = false
    let archiveColor: [UInt8] = [80, 160, 240, 255, 80, 160, 240, 255,
                                80, 160, 240, 255, 80, 160, 240, 255]
    if let archiveProbe = program(
        device: device,
        marker: 901,
        outputSlot: 3,
        slot0Texture: texture(device: device, fill: archiveColor),
        slot3Texture: texture(device: device, fill: [UInt8](repeating: 255, count: 16)),
        uniformName: "g_ArchiveProbe"
    ), let archiveRoot = ProcessInfo.processInfo
        .environment["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"],
        let rgbaPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
            identity: "fixture:archive-probe",
            prepared: archiveProbe.preparedAssembly,
            pixelFormat: .rgba8Unorm,
            writeMask: .all,
            device: device
        ), let bgraPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
            identity: "fixture:archive-probe-bgra",
            prepared: archiveProbe.preparedAssembly,
            pixelFormat: .bgra8Unorm,
            writeMask: .all,
            device: device
        ), let rgbaKey = archiveProbe.metalCompileStateKey(
            attachmentPixelFormat: .rgba8Unorm, sampleCount: 1, device: device
        ), let rgbaDigest = SceneResolvedMaterialPipelineBinaryArchive
            .keyDigest(key: rgbaKey) {
        let tierDirectory = URL(
            fileURLWithPath: archiveRoot, isDirectory: true
        ).appendingPathComponent(
            SceneResolvedMaterialPipelineBinaryArchive.cacheDirectoryName,
            isDirectory: true
        )
        let rgbaArchiveName = "\(rgbaDigest).metalarchive"
        let rgbaArchiveURL = tierDirectory.appendingPathComponent(
            rgbaArchiveName
        )
        func tierEntries() -> Set<String> {
            Set(
                ((try? FileManager.default.contentsOfDirectory(
                    atPath: tierDirectory.path
                )) ?? []).filter { $0.hasSuffix(".metalarchive") }
            )
        }
        let entriesBefore = tierEntries()
        let countersBefore =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let barrierArmed = MWXArmArchivePublicationBarrier(
            device, ".\(rgbaDigest).metalarchive.tmp-")

        // First launch: identity miss compiles from source and publishes.
        let firstLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let firstLaunchReport = firstLaunchEncoder.warmup([rgbaPlan])
        let publicationStarted = barrierArmed && MWXWaitArchivePublicationStarted(5)
        binaryArchiveReadyBeforePublication = publicationStarted && MWXArchivePublicationIsHeld()
            && firstLaunchReport.readyKeyCount == 1 && firstLaunchReport.failedKeyCount == 0
            && firstLaunchEncoder.cachedPipelineCount == 1
            && !FileManager.default.fileExists(atPath: rgbaArchiveURL.path)
        let firstPixels = render(archiveProbe, encoder: firstLaunchEncoder, queue: queue, target: rgbaTarget)
        binaryArchiveEncodesBeforePublication = binaryArchiveReadyBeforePublication
            && firstPixels.prepared && firstPixels.encoded && firstPixels.completed
            && closePixels(firstPixels.pixels, archiveColor) && MWXArchivePublicationIsHeld()
        if barrierArmed { MWXReleaseArchivePublication() }
        let serializationFinished = barrierArmed && MWXWaitArchivePublicationFinished(5)
        let firstFilePublished = waitForArchivePublication {
            FileManager.default.fileExists(atPath: rgbaArchiveURL.path)
        }
        let countersAfterFirst =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        binaryArchivePublishedOnFirstLaunch =
            firstLaunchReport.readyKeyCount == 1
            && serializationFinished && firstFilePublished
            && MWXArchiveSerializationAttempts() == 1
            && countersAfterFirst.hits == countersBefore.hits
            && !entriesBefore.contains(rgbaArchiveName)
            && tierEntries().contains(rgbaArchiveName)

        // Second launch: the persisted entry warms the same identity.
        let secondLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let secondLaunchReport = secondLaunchEncoder.warmup([rgbaPlan])
        let secondLaunchAttempts =
            secondLaunchEncoder.pipelineCompilationAttemptCount
        let countersAfterSecond =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let serializationsAfterSecond = MWXArchiveSerializationAttempts()
        let consumedFromWarmup = secondLaunchEncoder.prepare(
            program: archiveProbe,
            target: rgbaTarget
        ) != nil
        binaryArchiveHitOnSecondLaunch =
            secondLaunchReport.readyKeyCount == 1
            && countersAfterSecond.hits == countersAfterFirst.hits + 1
            && serializationsAfterSecond == 1
            && secondLaunchEncoder.pipelineCompilationAttemptCount
                == secondLaunchAttempts
            && consumedFromWarmup

        // A corrupted entry is a safe miss: the state still compiles and
        // the freshly compiled entry heals the file for later launches.
        let corruptedBytes = Data(repeating: 0xFF, count: 64)
        let corrupted = ((try? corruptedBytes.write(
            to: rgbaArchiveURL
        )) != nil)
        let thirdLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let thirdLaunchReport = thirdLaunchEncoder.warmup([rgbaPlan])
        let healed = waitForArchivePublication {
            guard let data = try? Data(contentsOf: rgbaArchiveURL) else { return false }
            return !data.isEmpty && data != corruptedBytes
        }
        let countersAfterThird =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let healedBytes = (try? Data(contentsOf: rgbaArchiveURL)) ?? Data()
        binaryArchiveSafeMissOnCorruptEntry =
            corrupted
            && thirdLaunchReport.readyKeyCount == 1
            && countersAfterThird.invalidLoads
                == countersAfterSecond.invalidLoads + 1
            && healed && MWXArchiveSerializationAttempts() == serializationsAfterSecond + 1
            && healedBytes != corruptedBytes

        // Attachment format participates in the identity: a separate
        // variant publishes its own entry and never hits the other one.
        let entriesBeforeBgra = tierEntries()
        let countersBeforeBgra =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let bgraKey = archiveProbe.metalCompileStateKey(
            attachmentPixelFormat: .bgra8Unorm, sampleCount: 1, device: device)!
        let bgraDigest = SceneResolvedMaterialPipelineBinaryArchive.keyDigest(key: bgraKey)!
        let bgraName = "\(bgraDigest).metalarchive"
        let rgbaBeforeBgra = (try? Data(contentsOf: rgbaArchiveURL)) ?? Data()
        let bgraLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let bgraLaunchReport = bgraLaunchEncoder.warmup([bgraPlan])
        let bgraPublished = waitForArchivePublication { tierEntries().contains(bgraName) }
        let countersAfterBgra =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        binaryArchiveIdentitySeparatesFormats =
            bgraLaunchReport.readyKeyCount == 1
            && bgraDigest != rgbaDigest && bgraPublished && !entriesBeforeBgra.contains(bgraName)
            && countersAfterBgra.hits == countersBeforeBgra.hits
            && ((try? Data(contentsOf: rgbaArchiveURL)) ?? Data()) == rgbaBeforeBgra

        // A new valid Program needs preparation before its frame can draw.
        let countersBeforeFrame =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let frameOnlyProgram = program(
            device: device,
            marker: 902,
            outputSlot: 3,
            uniformName: "g_FrameProbe"
        )
        let attemptsBeforeFrame = firstLaunchEncoder.pipelineCompilationAttemptCount
        let librariesBeforeFrame = firstLaunchEncoder.metalLibraryCompilationAttemptCount
        let frameOnlyRejected = frameOnlyProgram.map {
            if case .failure(.pipelineNotPrepared) = firstLaunchEncoder.prepareResult(
                program: $0, target: rgbaTarget) { return true }
            return false
        } ?? false
        let countersAfterFrame = SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        framePreparationSkipsArchiveTier =
            frameOnlyRejected
            && firstLaunchEncoder.pipelineCompilationAttemptCount == attemptsBeforeFrame
            && firstLaunchEncoder.metalLibraryCompilationAttemptCount == librariesBeforeFrame
            && countersAfterFrame.absentLoads == countersBeforeFrame.absentLoads
            && countersAfterFrame.invalidLoads == countersBeforeFrame.invalidLoads
            && countersAfterFrame.hits == countersBeforeFrame.hits
            && countersAfterFrame.archiveRetries == countersBeforeFrame.archiveRetries

        // The process-private root stays blocked through exit; publication may
        // continue after ready, so restoring a global environment early is invalid.
        let blockedRoot = URL(fileURLWithPath: archiveRoot, isDirectory: true)
            .appendingPathComponent("not-a-directory")
        let deniedRootInstalled = ((try? Data([1]).write(to: blockedRoot)) != nil)
            && setenv("MWX_SCENE_PIPELINE_BINARY_ARCHIVE", blockedRoot.path, 1) == 0
        let deniedBefore = SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let deniedEncoder = SceneResolvedMaterialPassEncoder(device: device)!
        let deniedReport = deniedEncoder.warmup([rgbaPlan])
        let deniedAfterWarmup = SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let deniedPixels = render(archiveProbe, encoder: deniedEncoder, queue: queue, target: rgbaTarget)
        let deniedPublication = waitForArchivePublication {
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot().publicationFailures > deniedBefore.publicationFailures
        }
        binaryArchiveDeniedRootKeepsReadyOutput = deniedRootInstalled
            && deniedReport.readyKeyCount == 1 && deniedReport.failedKeyCount == 0
            && deniedAfterWarmup.absentLoads == deniedBefore.absentLoads + 1
            && deniedAfterWarmup.hits == deniedBefore.hits
            && deniedPixels.prepared && deniedPixels.encoded && deniedPixels.completed
            && closePixels(deniedPixels.pixels, archiveColor) && deniedPublication
    }

    var crossDeviceExercised = false
    var crossDeviceRejected = true
    if let other = MTLCopyAllDevices().first(where: {
        $0.registryID != device.registryID
    }) {
        crossDeviceExercised = true
        let otherTarget = target(device: other)
        crossDeviceRejected = encoder.prepare(
            program: baseline,
            target: otherTarget
        ) == nil
    }

    let facts: [String: Bool] = [
        "missingRenderTargetRejected": missingRenderTargetRejected,
        "missingShaderReadRejected": missingShaderReadRejected,
        "inputUsageRejectedUpstream": inputUsageRejectedUpstream,
        "uniformMismatchRejectedUpstream": malformedUniformRejectedUpstream,
        "pipelineFailureNegativeCached": failureNegativeCached,
        "effectLocalPreEncodeFailureAllowlistIsNarrow": [
            SceneResolvedMaterialPassEncoder.PreparationFailure
                .libraryCompilationRejected(diagnostic: "fixture"),
            .vertexFunctionRejected,
            .fragmentFunctionRejected,
            .pipelineCompilationRejected(diagnostic: "fixture"),
            .pipelineNotPrepared,
        ].allSatisfy { $0.effectLocalPreEncodeReasonCode != nil }
            && [
                SceneResolvedMaterialPassEncoder.PreparationFailure
                    .fragmentOutputRejected,
                .targetRejected,
                .uniformsRejected,
                .bindingsRejected,
                .compileStateKeyRejected,
                .renderStateRejected,
            ].allSatisfy { $0.effectLocalPreEncodeReasonCode == nil },
        "resetPreservesHotCache": resetPreservedHotCache,
        "resetInvalidatesPreparedPass": stalePreparedRejected,
        "prepareAfterResetReusesPipeline": prepareAfterResetReusesPipeline,
        "launchWarmupDeduplicatesPhysicalKey":
            warmupReport.plannedPlanCount == 2
            && warmupReport.uniqueKeyCount == 1
            && warmupReport.readyKeyCount == 1
            && warmupReport.failedKeyCount == 0
            && warmupReport.compilationAttemptCount == 1,
        "launchWarmupConsumedWithoutFrameCompile":
            launchWarmupConsumedWithoutCompile,
        "coldMissRejectsWithoutCompiling": coldMissDoesNotCompile,
        "concurrentWarmupSharesMetalLibrary":
            concurrentWarmupSharesMetalLibrary,
        "launchWarmupFailureNegativeCached":
            invalidWarmupReport.uniqueKeyCount == 1
            && invalidWarmupReport.readyKeyCount == 0
            && invalidWarmupReport.failedKeyCount == 1
            && invalidWarmupReport.failures.first?.reasonCode
                == "library-compilation"
            && invalidWarmupNegativeCached,
        "crossDeviceRejectedWhenAvailable": crossDeviceRejected,
        "binaryArchivePublishedOnFirstLaunch": binaryArchivePublishedOnFirstLaunch,
        "binaryArchiveHitOnSecondLaunch": binaryArchiveHitOnSecondLaunch,
        "binaryArchiveSafeMissOnCorruptEntry": binaryArchiveSafeMissOnCorruptEntry,
        "binaryArchiveIdentitySeparatesFormats": binaryArchiveIdentitySeparatesFormats,
        "framePreparationSkipsArchiveTier": framePreparationSkipsArchiveTier,
        "binaryArchiveReadyBeforePublication": binaryArchiveReadyBeforePublication,
        "binaryArchiveEncodesBeforePublication": binaryArchiveEncodesBeforePublication,
        "binaryArchiveDeniedRootKeepsReadyOutput": binaryArchiveDeniedRootKeepsReadyOutput,
    ]
    return .init(facts: facts, crossDeviceExercised: crossDeviceExercised)
}
