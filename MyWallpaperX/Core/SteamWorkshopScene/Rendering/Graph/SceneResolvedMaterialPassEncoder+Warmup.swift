import Foundation
import Metal

extension SceneResolvedMaterialPassEncoder {
    struct WarmupPlan {
        let identity: String
        let preparedKey: String

        fileprivate let key: SceneResolvedMaterialProgram.MetalCompileStateKey
        fileprivate let frontend: SceneAuthoredShaderProgram
        fileprivate let renderState: SceneMaterialRenderState
        fileprivate let pixelFormat: MTLPixelFormat
        fileprivate let sampleCount: Int
        fileprivate let writeMask: MTLColorWriteMask

        init?(
            identity: String,
            prepared: SceneResolvedMaterialProgram.PreparedAssembly,
            pixelFormat: MTLPixelFormat,
            sampleCount: Int = 1,
            writeMask: MTLColorWriteMask,
            passRole: SceneResolvedMaterialProgram.PassRole = .offscreenOverwrite,
            device: MTLDevice
        ) {
            if passRole.readsCurrentAttachment {
                guard prepared.frontendProgram.attachmentReadVariant != nil,
                      SceneResolvedMaterialProgram.PassRole.supportsAttachmentReadTarget(
                    pixelFormat: pixelFormat, sampleCount: sampleCount, device: device
                ) else { return nil }
            }
            guard !identity.isEmpty, pixelFormat != .invalid,
                  sampleCount > 0, !writeMask.isEmpty,
                  device.registryID != 0 else { return nil }
            self.identity = identity
            preparedKey = prepared.preparedIdentity.cacheKey
            key = .init(
                passRole: passRole,
                shader: prepared.shaderIdentity,
                renderState: prepared.renderStateIdentity,
                attachmentPixelFormatRawValue: pixelFormat.rawValue,
                sampleCount: sampleCount,
                colorWriteMaskRawValue: writeMask.rawValue,
                deviceRegistryID: device.registryID,
                attachmentReadMetalSourceSHA256: passRole.readsCurrentAttachment
                    ? prepared.frontendProgram.attachmentReadVariant?.metalSourceSHA256 : nil
            )
            frontend = prepared.frontendProgram
            renderState = prepared.renderState
            self.pixelFormat = pixelFormat
            self.sampleCount = sampleCount
            self.writeMask = writeMask
        }
    }

    struct WarmupReport {
        struct Failure {
            let identity: String
            let preparedKey: String
            let reasonCode: String
        }

        let plannedPlanCount: Int
        let uniqueKeyCount: Int
        let readyKeyCount: Int
        let failedKeyCount: Int
        let compilationAttemptCount: Int
        let failures: [Failure]

        var reportLines: [String] {
            var lines = [
                "resolved material pipeline warmup: schema=launch-pipeline-warmup-v1"
                    + " phase=launch-preparation"
                    + " planned=\(plannedPlanCount)"
                    + " unique=\(uniqueKeyCount)"
                    + " ready=\(readyKeyCount)"
                    + " failed=\(failedKeyCount)"
                    + " attempts=\(compilationAttemptCount)"
            ]
            lines += failures.map {
                "resolved material pipeline warmup failure:"
                    + " identity=\($0.identity)"
                    + " prepared=\($0.preparedKey)"
                    + " reason=\($0.reasonCode)"
            }
            return lines
        }
    }

    func warmup(_ plans: [WarmupPlan]) -> WarmupReport {
#if DEBUG || SCENE_GRAPH_TESTING
        let attemptsBefore = pipelineCompilationAttemptCount
#endif
        var visited = Set<SceneResolvedMaterialProgram.MetalCompileStateKey>()
        let uniquePlans = plans.sorted(by: {
            if $0.identity != $1.identity { return $0.identity < $1.identity }
            return $0.preparedKey < $1.preparedKey
        }).filter { visited.insert($0.key).inserted }
        let outcomesLock = NSLock()
        var failuresByIndex: [Int: PreparationFailure] = [:]
        let workerCount = min(uniquePlans.count, 4)
        if workerCount > 0 {
            DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
                for index in stride(
                    from: worker,
                    to: uniquePlans.count,
                    by: workerCount
                ) {
                    let plan = uniquePlans[index]
                    if let failure = warmupPipeline(plan) {
                        outcomesLock.lock()
                        failuresByIndex[index] = failure
                        outcomesLock.unlock()
                    }
                }
            }
        }
        let failures = failuresByIndex.keys.sorted().map { index in
            let plan = uniquePlans[index]
            return WarmupReport.Failure(
                identity: plan.identity,
                preparedKey: plan.preparedKey,
                reasonCode: failuresByIndex[index]!.code
            )
        }
#if DEBUG || SCENE_GRAPH_TESTING
        let compilationAttemptCount = pipelineCompilationAttemptCount - attemptsBefore
#else
        let compilationAttemptCount = 0
#endif
        return .init(
            plannedPlanCount: plans.count,
            uniqueKeyCount: visited.count,
            readyKeyCount: uniquePlans.count - failures.count,
            failedKeyCount: failures.count,
            compilationAttemptCount: compilationAttemptCount,
            failures: failures
        )
    }

    /// Graph and source-material preparation finish warmup before publication.
    /// Unique keys may compile concurrently, then publish under the cache lock.
    /// The persistent binary archive is loaded on the warmup workers;
    /// successful PSOs hand optional publication to utility. Frames never touch it.
    private func warmupPipeline(_ plan: WarmupPlan) -> PreparationFailure? {
        lock.lock()
        if let existing = entries[plan.key] {
            lock.unlock()
            switch existing {
            case .ready: return nil
            case let .failed(failure): return failure
            }
        }
#if DEBUG || SCENE_GRAPH_TESTING
        compilationAttempts += 1
#endif
        lock.unlock()

        let binaryArchiveSession = SceneResolvedMaterialPipelineBinaryArchive
            .prepareSession(
                key: plan.key,
                device: device
            )
        let result = compileUncachedPipeline(
            frontend: plan.frontend,
            renderState: plan.renderState,
            pixelFormat: plan.pixelFormat,
            sampleCount: plan.sampleCount,
            writeMask: plan.writeMask,
            passRole: plan.key.passRole,
            binaryArchiveSession: binaryArchiveSession
        )
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case let .success(pipeline):
            entries[plan.key] = .ready(pipeline)
            return nil
        case let .failure(failure):
            entries[plan.key] = .failed(failure)
#if DEBUG || SCENE_GRAPH_TESTING
            failedPipelines += 1
#endif
            return failure
        }
    }

#if DEBUG || SCENE_GRAPH_TESTING
    func recordLaunchWarmupConsumption(
        key: SceneResolvedMaterialProgram.MetalCompileStateKey,
        preparedKey: String
    ) {
        let observation: (attempts: Int, hits: Int)? = withLock {
            guard consumedLaunchWarmupKeys.insert(key).inserted else { return nil }
            launchWarmupHits += 1
            return (compilationAttempts, launchWarmupHits)
        }
        guard let observation else { return }
#if DEBUG
        NSLog(
            "MWX resolved material pipeline consumption phase=frame-preparation source=launch-warmup prepared=%@ attempts=%d hits=%d",
            preparedKey,
            observation.attempts,
            observation.hits
        )
#endif
    }
#endif
}
