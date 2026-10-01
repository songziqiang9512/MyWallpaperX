import Foundation
import Metal

extension SceneDesktopWallpaperSession {
    /// Stops all Scene owners, then submits one empty barrier to each surface's
    /// existing command queue. Completion means every command submitted before
    /// teardown has reached a terminal GPU state.
    func stopAndDrainGPU(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if let drainResult { completion(drainResult); return }
        drainCallbacks.append(completion)
        guard !drainStarted else { return }
        drainStarted = true
        let commandQueues = (Array(surfaces.values) + Array(retiringSurfaces.values))
            .map { $0.metalView.renderer.commandQueue }
        stop()
        guard !commandQueues.isEmpty else {
            finishDrain(true)
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
                self.finishDrain(createdAllBarriers && completedAllBarriers)
            }
        }
    }
    /// Rebuilt surfaces keep their resources until their own queue is terminal.
    /// A later stop includes any outstanding rebuild drains in its barrier.
    func retireSurface(_ surface: Surface) {
        let identity = ObjectIdentifier(surface)
        retiringSurfaces[identity] = surface
        guard let barrier = surface.metalView.renderer.commandQueue.makeCommandBuffer() else { return }
        barrier.label = "Scene replaced surface drain"
        barrier.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async { self?.retiringSurfaces.removeValue(forKey: identity) }
        }
        barrier.commit()
    }

    private func finishDrain(_ succeeded: Bool) {
        drainResult = succeeded
        retiringSurfaces.removeAll()
        let callbacks = drainCallbacks
        drainCallbacks = []
        callbacks.forEach { $0(succeeded) }
    }

}
