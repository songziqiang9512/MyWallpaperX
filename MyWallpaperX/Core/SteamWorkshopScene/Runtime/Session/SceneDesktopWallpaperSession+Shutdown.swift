import AppKit
import Metal

extension SceneDesktopWallpaperSession {
    /// Stops all Scene owners, then submits one empty barrier to each surface's
    /// existing command queue. Completion means every command submitted before
    /// teardown has reached a terminal GPU state and admitted font work ended.
    func stopAndDrainGPU(
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if let drainResult { completion(drainResult); return }
        drainCallbacks.append(completion)
        guard !drainStarted else { return }
        drainStarted = true
        let drainingSurfaces = Array(surfaces.values) + Array(retiringSurfaces.values)
        let commandQueues = drainingSurfaces.map { $0.metalView.renderer.commandQueue }
#if DEBUG
        let captures = drainingSurfaces.map { $0.metalView.debugFrameCapture }
        let exportDrain = DispatchGroup()
        for capture in captures {
            exportDrain.enter()
            capture.closeAndDrain { exportDrain.leave() }
        }
#endif
        stop()
        let retirementDrain = retiringSurfaceDrain
        DispatchQueue.global(qos: .userInitiated).async {
            // Includes text and deferred loaders registered before context
            // disposal, even after stop-before-drain or a failed rebuild.
            // They can submit uploads before their CPU tails return.
            retirementDrain.wait()
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
#if DEBUG
            // GPU terminal does not imply the derived asynchronous export ended.
            exportDrain.wait()
            withExtendedLifetime(captures) {}
#endif
            let deliver: @MainActor @Sendable () -> Void = {
                self.finishDrain(createdAllBarriers && completedAllBarriers && !self.surfaceDrainFailed)
            }
#if DEBUG
            // Isolated AppKit termination can nest inside a main dispatch block.
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated { deliver() }
            }
#else
            DispatchQueue.main.async { deliver() }
#endif
        }
    }
    /// Rebuilt surfaces retain resources until their queue and exports end.
    /// A later stop includes any outstanding rebuild drains in its barrier.
    func retireSurface(_ surface: Surface) {
        let identity = ObjectIdentifier(surface)
        retiringSurfaces[identity] = surface
        retiringSurfaceDrain.enter()
        let resourceDrain = DispatchGroup()
        // Keep an admission open until the GPU barrier is terminal or rejected.
        resourceDrain.enter()
#if DEBUG
        let capture = surface.metalView.debugFrameCapture
        resourceDrain.enter()
        capture.closeAndDrain { resourceDrain.leave() }
#endif
        resourceDrain.notify(queue: .global(qos: .userInitiated)) { [self] in
            let deliver: @MainActor @Sendable () -> Void = {
                self.retiringSurfaces.removeValue(forKey: identity)
                self.retiringSurfaceDrain.leave()
            }
#if DEBUG
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated { deliver() }
            }
#else
            DispatchQueue.main.async { deliver() }
#endif
        }
        let barrier = surface.metalView.renderer.commandQueue.makeCommandBuffer()
        barrier?.label = "Scene replaced surface drain"
        if barrier == nil { surfaceDrainFailed = true }
        barrier?.addCompletedHandler { [self] completed in
            let succeeded = completed.status == .completed && completed.error == nil
            let deliver: @MainActor @Sendable () -> Void = {
                if !succeeded { self.surfaceDrainFailed = true }
                resourceDrain.leave()
            }
#if DEBUG
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                MainActor.assumeIsolated { deliver() }
            }
#else
            DispatchQueue.main.async { deliver() }
#endif
        }
        if let barrier { barrier.commit() }
        else { resourceDrain.leave() }
    }

    private func finishDrain(_ succeeded: Bool) {
        drainResult = succeeded
        retiringSurfaces.removeAll()
        let callbacks = drainCallbacks
        drainCallbacks = []
        callbacks.forEach { $0(succeeded) }
    }

}
