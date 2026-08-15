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
        var ready = 0
        var failures: [WarmupReport.Failure] = []
        for plan in plans.sorted(by: {
            if $0.identity != $1.identity { return $0.identity < $1.identity }
            return $0.preparedKey < $1.preparedKey
        }) where visited.insert(plan.key).inserted {
            switch pipeline(
                for: plan.key,
                frontend: plan.frontend,
                renderState: plan.renderState,
                pixelFormat: plan.pixelFormat,
                sampleCount: plan.sampleCount,
                writeMask: plan.writeMask,
                origin: .launchWarmup
            ) {
            case .success:
                ready += 1
            case let .failure(failure):
                failures.append(.init(
                    identity: plan.identity,
                    preparedKey: plan.preparedKey,
                    reasonCode: failure.code
                ))
            }
        }
        return .init(
            plannedPlanCount: plans.count,
            uniqueKeyCount: visited.count,
            readyKeyCount: ready,
            failedKeyCount: failures.count,
            compilationAttemptCount:
                pipelineCompilationAttemptCount - attemptsBefore,
            failures: failures
        )
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
