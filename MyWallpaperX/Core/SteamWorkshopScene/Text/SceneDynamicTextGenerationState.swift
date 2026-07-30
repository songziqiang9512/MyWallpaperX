import Foundation

nonisolated struct SceneDynamicTextSignature: Equatable, Sendable {
    let content: String
    let pointSize: Float
    let colorRGB: [Float]
}

nonisolated struct SceneDynamicTextGenerationState {
    private var requested: [Int: SceneDynamicTextSignature] = [:]
    private var ready: [Int: SceneDynamicTextSignature] = [:]
    private var generations: [Int: UInt64] = [:]
    private var readyGenerations: [Int: UInt64] = [:]

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
    }
}
