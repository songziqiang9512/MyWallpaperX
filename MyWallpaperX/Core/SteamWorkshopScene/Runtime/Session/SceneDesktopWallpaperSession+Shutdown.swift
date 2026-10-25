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
        let textStores = drainingSurfaces.compactMap { $0.metalView.dynamicTextTextures }
        let textDrain = DispatchGroup()
        for store in textStores {
            textDrain.enter()
            store.closeAndDrain { textDrain.leave() }
        }
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
            // CPU loaders can submit uploads while unwinding. Close and join
            // them before placing the final barriers on the surface queues.
            textDrain.wait()
            // Includes shared deferred work registered before context disposal,
            // including stop-before-drain and earlier surface rebuild failures.
            retirementDrain.wait()
            withExtendedLifetime(textStores) {}
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
    /// Rebuilt surfaces retain resources until font work and their queue end.
    /// A later stop includes any outstanding rebuild drains in its barrier.
    func retireSurface(_ surface: Surface) {
        let identity = ObjectIdentifier(surface)
        retiringSurfaces[identity] = surface
        retiringSurfaceDrain.enter()
        let resourceDrain = DispatchGroup()
        // Keep an admission open until the GPU barrier is terminal or rejected.
        resourceDrain.enter()
        let textStore = surface.metalView.dynamicTextTextures
        textStore?.close()
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
        let submitBarrier: @Sendable () -> Void = {
            if let barrier { barrier.commit() }
            else { resourceDrain.leave() }
        }
        if let textStore {
            resourceDrain.enter()
            textStore.closeAndDrain {
                submitBarrier()
                resourceDrain.leave()
            }
        } else {
            submitBarrier()
        }
    }

    private func finishDrain(_ succeeded: Bool) {
        drainResult = succeeded
        retiringSurfaces.removeAll()
        let callbacks = drainCallbacks
        drainCallbacks = []
        callbacks.forEach { $0(succeeded) }
    }

}
