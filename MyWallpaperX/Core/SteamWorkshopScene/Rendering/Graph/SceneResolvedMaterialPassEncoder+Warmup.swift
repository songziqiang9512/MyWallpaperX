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
            preparedKey: String,
            frontend: SceneAuthoredShaderProgram,
            renderState: SceneMaterialRenderState,
            frontendSchemaVersion: Int,
            pixelFormat: MTLPixelFormat,
            sampleCount: Int = 1,
            writeMask: MTLColorWriteMask,
            device: MTLDevice
        ) {
            guard !identity.isEmpty, !preparedKey.isEmpty,
                  let key = SceneResolvedMaterialProgramIdentity.metalCompileStateKey(
                      frontend: frontend,
                      renderState: renderState,
                      frontendSchemaVersion: frontendSchemaVersion,
                      attachmentPixelFormatRawValue: pixelFormat.rawValue,
                      sampleCount: sampleCount,
                      colorWriteMaskRawValue: writeMask.rawValue,
                      deviceRegistryID: device.registryID
                  ) else { return nil }
            self.identity = identity
            self.preparedKey = preparedKey
            self.key = key
            self.frontend = frontend
            self.renderState = renderState
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
        let attemptsBefore = pipelineCompilationAttemptCount
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
        return .init(
            plannedPlanCount: plans.count,
            uniqueKeyCount: visited.count,
            readyKeyCount: uniquePlans.count - failures.count,
            failedKeyCount: failures.count,
            compilationAttemptCount:
                pipelineCompilationAttemptCount - attemptsBefore,
            failures: failures
        )
    }

    /// Warmup runs only from `SceneResolvedMaterialGraphExecutor.init`, before
    /// the encoder can escape to a frame. Unique compile keys therefore may be
    /// compiled concurrently, then published under the ordinary cache lock.
    private func warmupPipeline(_ plan: WarmupPlan) -> PreparationFailure? {
        lock.lock()
        if let existing = entries[plan.key] {
            lock.unlock()
            switch existing {
            case .ready: return nil
            case let .failed(failure, _): return failure
            }
        }
        compilationAttempts += 1
        lock.unlock()

        let result = compileUncachedPipeline(
            frontend: plan.frontend,
            renderState: plan.renderState,
            pixelFormat: plan.pixelFormat,
            sampleCount: plan.sampleCount,
            writeMask: plan.writeMask
        )
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case let .success(pipeline):
            entries[plan.key] = .ready(pipeline, origin: .launchWarmup)
            return nil
        case let .failure(failure):
            entries[plan.key] = .failed(failure, origin: .launchWarmup)
            failedPipelines += 1
            return failure
        }
    }

    func recordLaunchWarmupConsumption(
        key: SceneResolvedMaterialProgram.MetalCompileStateKey,
        origin: PipelineOrigin,
        preparedKey: String
    ) {
        guard origin == .launchWarmup else { return }
        let observation: (attempts: Int, hits: Int)? = withLock {
            guard consumedLaunchWarmupKeys.insert(key).inserted else { return nil }
            launchWarmupHits += 1
            return (compilationAttempts, launchWarmupHits)
        }
        guard let observation else { return }
        NSLog(
            "MWX resolved material pipeline consumption phase=frame-preparation source=launch-warmup prepared=%@ attempts=%d hits=%d",
            preparedKey,
            observation.attempts,
            observation.hits
        )
    }
}
