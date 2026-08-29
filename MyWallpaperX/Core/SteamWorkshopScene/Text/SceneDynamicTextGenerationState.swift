import Foundation

nonisolated struct SceneDynamicTextSignature: Equatable, Sendable {
    let content: String
    let pointSize: Float
    let colorRGB: [Float]
    let maxWidth: Float
}

nonisolated struct SceneDynamicTextGenerationState {
    nonisolated struct RenderRequest: Equatable, Sendable {
        let layerID: Int
        let signature: SceneDynamicTextSignature
        let generation: UInt64
    }

    nonisolated struct RenderCompletion: Equatable, Sendable {
        let accepted: Bool
        let next: RenderRequest?
    }

    private var requested: [Int: SceneDynamicTextSignature] = [:]
    private var ready: [Int: SceneDynamicTextSignature] = [:]
    private var generations: [Int: UInt64] = [:]
    private var readyGenerations: [Int: UInt64] = [:]
    private var renderingGenerations: [Int: UInt64] = [:]

    nonisolated mutating func registerInitial(
        layerID: Int,
        signature: SceneDynamicTextSignature,
        isReady: Bool
    ) {
        requested[layerID] = signature
        if isReady {
            ready[layerID] = signature
            readyGenerations[layerID] = generations[layerID] ?? 0
        }
    }

    nonisolated mutating func registerDynamic(
        layerID: Int,
        signature: SceneDynamicTextSignature
    ) -> RenderRequest? {
        guard requested[layerID] == nil else { return nil }
        requested[layerID] = signature
        generations[layerID] = 1
        renderingGenerations[layerID] = 1
        return .init(layerID: layerID, signature: signature, generation: 1)
    }

    nonisolated mutating func unregister(layerID: Int) {
        requested.removeValue(forKey: layerID)
        ready.removeValue(forKey: layerID)
        generations.removeValue(forKey: layerID)
        readyGenerations.removeValue(forKey: layerID)
        renderingGenerations.removeValue(forKey: layerID)
    }

    nonisolated mutating func request(
        layerID: Int,
        signature: SceneDynamicTextSignature
    ) -> UInt64? {
        guard requested[layerID] != signature else { return nil }
        let generation = (generations[layerID] ?? 0) &+ 1
        generations[layerID] = generation
        requested[layerID] = signature
        return generation
    }

    /// 连续 Timeline 可能每帧都改变签名。每层只允许一个栅格任务在途；在途期间仍更新
    /// 最新 generation，完成后只调度最新的一份，避免把每个中间帧都堆进串行队列。
    nonisolated mutating func schedule(
        layerID: Int,
        signature: SceneDynamicTextSignature
    ) -> RenderRequest? {
        guard let generation = request(layerID: layerID, signature: signature),
              renderingGenerations[layerID] == nil else { return nil }
        renderingGenerations[layerID] = generation
        return RenderRequest(layerID: layerID, signature: signature, generation: generation)
    }

    nonisolated mutating func complete(
        layerID: Int,
        generation: UInt64,
        succeeded: Bool
    ) -> Bool {
        guard succeeded,
              generations[layerID] == generation,
              let signature = requested[layerID] else { return false }
        ready[layerID] = signature
        readyGenerations[layerID] = generation
        return true
    }

    nonisolated mutating func finish(
        _ request: RenderRequest,
        succeeded: Bool
    ) -> RenderCompletion {
        guard renderingGenerations[request.layerID] == request.generation else {
            return RenderCompletion(accepted: false, next: nil)
        }
        // schedule 保证同一 layer 的完成顺序严格单调；即使期间已有更新请求，这个完成值
        // 也比当前 ready 新，可以先发布再追最新。若仍套用并发 complete 的 exact-latest
        // 规则，栅格耗时超过一帧时连续 Timeline 会永远饿死、始终停在 authored 纹理。
        let accepted = succeeded
            && request.generation > (readyGenerations[request.layerID] ?? 0)
        if accepted {
            ready[request.layerID] = request.signature
            readyGenerations[request.layerID] = request.generation
        }
        guard let latestGeneration = generations[request.layerID],
              latestGeneration != request.generation,
              let latestSignature = requested[request.layerID] else {
            renderingGenerations[request.layerID] = nil
            return RenderCompletion(accepted: accepted, next: nil)
        }
        renderingGenerations[request.layerID] = latestGeneration
        return RenderCompletion(
            accepted: accepted,
            next: RenderRequest(
                layerID: request.layerID,
                signature: latestSignature,
                generation: latestGeneration
            )
        )
    }

    nonisolated func readySignature(layerID: Int) -> SceneDynamicTextSignature? {
        ready[layerID]
    }

    nonisolated func readyGeneration(layerID: Int) -> UInt64? {
        readyGenerations[layerID]
    }

    nonisolated mutating func reset() {
        requested.removeAll()
        ready.removeAll()
        generations.removeAll()
        readyGenerations.removeAll()
        renderingGenerations.removeAll()
    }
}
