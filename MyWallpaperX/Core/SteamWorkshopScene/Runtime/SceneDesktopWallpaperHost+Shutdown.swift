import Foundation
import Metal

extension SceneDesktopWallpaperHost {
    /// Stops all Scene owners, then submits one empty barrier to each surface's
    /// existing command queue. Completion means every command submitted before
    /// teardown has reached a terminal GPU state.
    func stopAndDrainGPU(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        let commandQueues = surfaces.values.map { $0.metalView.renderer.commandQueue }
        stop()
        guard !commandQueues.isEmpty else {
            completion(true)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let barriers = commandQueues.compactMap { queue -> MTLCommandBuffer? in
                guard let buffer = queue.makeCommandBuffer() else { return nil }
                buffer.label = "Scene daemon shutdown drain barrier"
                buffer.commit()
                return buffer
            }
            let createdAllBarriers = barriers.count == commandQueues.count
            barriers.forEach { $0.waitUntilCompleted() }
            let completedAllBarriers = barriers.allSatisfy {
                $0.status == .completed && $0.error == nil
            }
            DispatchQueue.main.async {
                completion(createdAllBarriers && completedAllBarriers)
            }
        }
    }
}
