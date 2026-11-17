import Metal

nonisolated enum SceneCommandBufferOrdering {
    // Callers keep their successor unqueued while reserving its resources.
    static func isEnqueued(_ previous: MTLCommandBuffer, on queue: MTLCommandQueue) -> Bool {
        previous.status != .notEnqueued
            && ObjectIdentifier(previous.commandQueue) == ObjectIdentifier(queue)
    }
}
