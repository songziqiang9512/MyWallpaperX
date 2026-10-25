import CoreGraphics
import Foundation
import Metal
import simd

// Invalid inputs, local negative cache, reset, warmup and original archive tier.
struct SceneResolvedMaterialPassPipelineResult {
    let facts: [String: Bool]
    let crossDeviceExercised: Bool
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
    let warmupPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
        identity: "fixture:baseline",
        preparedKey: baseline.preparedShader.cacheKey,
        frontend: baseline.frontendProgram,
        renderState: baseline.renderState,
        frontendSchemaVersion:
            baseline.semanticIdentity.shader.frontendSchemaVersion,
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
        preparedKey: baseline.preparedShader.cacheKey,
        frontend: baseline.frontendProgram,
        renderState: baseline.renderState,
        frontendSchemaVersion:
            baseline.semanticIdentity.shader.frontendSchemaVersion,
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
        preparedKey: invalidMetal.preparedShader.cacheKey,
        frontend: invalidMetal.frontendProgram,
        renderState: invalidMetal.renderState,
        frontendSchemaVersion:
            invalidMetal.semanticIdentity.shader.frontendSchemaVersion,
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
    if let archiveProbe = program(
        device: device,
        marker: 901,
        outputSlot: 3,
        uniformName: "g_ArchiveProbe"
    ), let archiveRoot = ProcessInfo.processInfo
        .environment["MWX_SCENE_PIPELINE_BINARY_ARCHIVE"],
        let rgbaPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
            identity: "fixture:archive-probe",
            preparedKey: archiveProbe.preparedShader.cacheKey,
            frontend: archiveProbe.frontendProgram,
            renderState: archiveProbe.renderState,
            frontendSchemaVersion: archiveProbe.semanticIdentity
                .shader.frontendSchemaVersion,
            pixelFormat: .rgba8Unorm,
            writeMask: .all,
            device: device
        ), let bgraPlan = SceneResolvedMaterialPassEncoder.WarmupPlan(
            identity: "fixture:archive-probe-bgra",
            preparedKey: archiveProbe.preparedShader.cacheKey,
            frontend: archiveProbe.frontendProgram,
            renderState: archiveProbe.renderState,
            frontendSchemaVersion: archiveProbe.semanticIdentity
                .shader.frontendSchemaVersion,
            pixelFormat: .bgra8Unorm,
            writeMask: .all,
            device: device
        ), let rgbaDigest = SceneResolvedMaterialPipelineBinaryArchive
            .keyDigest(
                frontend: archiveProbe.frontendProgram,
                renderState: archiveProbe.renderState,
                pixelFormat: .rgba8Unorm,
                sampleCount: 1,
                writeMask: .all,
                device: device
            ) {
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

        // First launch: identity miss compiles from source and publishes.
        let firstLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let firstLaunchReport = firstLaunchEncoder.warmup([rgbaPlan])
        let countersAfterFirst =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        binaryArchivePublishedOnFirstLaunch =
            firstLaunchReport.readyKeyCount == 1
            && countersAfterFirst.publications
                == countersBefore.publications + 1
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
        let consumedFromWarmup = secondLaunchEncoder.prepare(
            program: archiveProbe,
            target: rgbaTarget
        ) != nil
        binaryArchiveHitOnSecondLaunch =
            secondLaunchReport.readyKeyCount == 1
            && countersAfterSecond.hits == countersAfterFirst.hits + 1
            && countersAfterSecond.publications
                == countersAfterFirst.publications
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
        let countersAfterThird =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let healedBytes = (try? Data(contentsOf: rgbaArchiveURL)) ?? Data()
        binaryArchiveSafeMissOnCorruptEntry =
            corrupted
            && thirdLaunchReport.readyKeyCount == 1
            && countersAfterThird.invalidLoads
                == countersAfterSecond.invalidLoads + 1
            && countersAfterThird.publications
                == countersAfterSecond.publications + 1
            && healedBytes != corruptedBytes

        // Attachment format participates in the identity: a separate
        // variant publishes its own entry and never hits the other one.
        let entriesBeforeBgra = tierEntries()
        let countersBeforeBgra =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let bgraLaunchEncoder =
            SceneResolvedMaterialPassEncoder(device: device)!
        let bgraLaunchReport = bgraLaunchEncoder.warmup([bgraPlan])
        let countersAfterBgra =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        binaryArchiveIdentitySeparatesFormats =
            bgraLaunchReport.readyKeyCount == 1
            && countersAfterBgra.publications
                == countersBeforeBgra.publications + 1
            && countersAfterBgra.hits == countersBeforeBgra.hits
            && tierEntries().count == entriesBeforeBgra.count + 1

        // Ordinary frame preparation compiles without the archive tier.
        let countersBeforeFrame =
            SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
        let frameOnlyProgram = program(
            device: device,
            marker: 902,
            outputSlot: 3,
            uniformName: "g_FrameProbe"
        )
        let frameOnlyPrepared = frameOnlyProgram.map {
            firstLaunchEncoder.prepare(
                program: $0,
                target: rgbaTarget
            ) != nil
        } ?? false
        framePreparationSkipsArchiveTier =
            frameOnlyPrepared
            && SceneResolvedMaterialPipelineBinaryArchive.counterSnapshot()
                == countersBeforeFrame
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
    ]
    return .init(facts: facts, crossDeviceExercised: crossDeviceExercised)
}
