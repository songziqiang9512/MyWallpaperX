import Foundation
import Metal

final class SceneParticleMetalInstanceBuffer: @unchecked Sendable {
    private struct Slot {
        var buffer: MTLBuffer
        var capacity: Int
        var isInFlight: Bool
        /// The command buffer that currently owns this slot, including the
        /// short interval after encoding and before `commit()`.  Keeping this
        /// identity lets the renderer cancel a not-enqueued command safely
        /// without allowing a late completion callback to release a reused
        /// slot.
        var submissionCommandBuffer: ObjectIdentifier?
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
    /// Completion handlers are armed before particle encoding starts.  Metal
    /// command-buffer ownership is therefore established before a command can
    /// cross the enqueue/commit boundary; marking a slot later only records
    /// which candidate the already-armed command actually captured.
    private var armedSubmissionCommandBuffers: Set<ObjectIdentifier> = []
    private var currentSlotIndex: Int?
    private var currentCount = 0

    var buffer: MTLBuffer? {
        withLock { currentSlotIndex.map { slots[$0].buffer } }
    }

    var count: Int {
        withLock { currentCount }
    }

    func update(device: MTLDevice, instances: [SceneParticleGPUInstance]) -> Bool {
        withLock {
            currentCount = instances.count
            guard !instances.isEmpty else {
                currentSlotIndex = nil
                return true
            }
            guard let slotIndex = prepareSlot(
                device: device,
                requiredCount: instances.count
            ) else {
                currentCount = 0
                currentSlotIndex = nil
                return false
            }
            currentSlotIndex = slotIndex
            let length = instances.count * MemoryLayout<SceneParticleGPUInstance>.stride
            instances.withUnsafeBufferPointer { values in
                guard let source = values.baseAddress else { return }
                slots[slotIndex].buffer.contents().copyMemory(
                    from: source,
                    byteCount: length
                )
            }
            return true
        }
    }

    @discardableResult
    func armSubmission(on commandBuffer: MTLCommandBuffer) -> Bool {
        // Completion handlers are installed only while the command is still
        // not enqueued.  The renderer calls this before its first particle
        // draw; `markSubmitted` also calls it for isolated/unit callers.
        let identity = ObjectIdentifier(commandBuffer)
        return withLock {
            if armedSubmissionCommandBuffers.contains(identity) { return true }
            guard commandBuffer.status == .notEnqueued else { return false }
            armedSubmissionCommandBuffers.insert(identity)
            commandBuffer.addCompletedHandler { [weak self] buffer in
                self?.releaseSlots(
                    for: ObjectIdentifier(buffer)
                )
            }
            return true
        }
    }

    @discardableResult
    func markSubmitted(on commandBuffer: MTLCommandBuffer) -> Bool {
        // Arm before reserving the slot.  This keeps completion-handler
        // registration out of the post-encoding path and makes the slot
        // reservation safe even if the command is enqueued immediately after
        // the renderer returns from this method.
        guard commandBuffer.status != .completed,
              commandBuffer.status != .error else { return false }
        let submissionCommandBuffer = ObjectIdentifier(commandBuffer)
        guard armSubmission(on: commandBuffer) else { return false }
        let didReserve = withLock {
            guard let currentSlotIndex,
                  slots.indices.contains(currentSlotIndex),
                  !slots[currentSlotIndex].isInFlight,
                  armedSubmissionCommandBuffers.contains(submissionCommandBuffer)
            else { return false }
            slots[currentSlotIndex].isInFlight = true
            slots[currentSlotIndex].submissionCommandBuffer = submissionCommandBuffer
            self.currentSlotIndex = nil
            return true
        }
        return didReserve
    }

    /// Discards the current CPU-written candidate when no draw was encoded.
    ///
    /// A candidate slot is not GPU-owned until `markSubmitted` moves it to the
    /// in-flight set, so cancellation only clears the current reference and
    /// makes that slot available for the next update.  In-flight slots are
    /// never released here; their completion handler remains the sole owner of
    /// that lifecycle transition.
    @discardableResult
    func cancelPending() -> Bool {
        withLock {
            guard let currentSlotIndex,
                  slots.indices.contains(currentSlotIndex) else { return false }
            guard !slots[currentSlotIndex].isInFlight else {
                // This should be unreachable because markSubmitted clears the
                // current index before setting the slot in flight.  Keep the
                // guard explicit so a corrupted state cannot release a slot
                // still referenced by a command buffer.
                self.currentSlotIndex = nil
                currentCount = 0
                return false
            }
            self.currentSlotIndex = nil
            currentCount = 0
            return true
        }
    }

    /// Releases slots reserved by a command buffer that has not been enqueued.
    ///
    /// `markSubmitted` reserves a slot before the renderer's final graph seal
    /// because the draw has already captured that buffer.  If the seal (or any
    /// later synchronous validation) rejects the frame, the command is still
    /// `.notEnqueued` and the reservation can be safely undone.  Once Metal has
    /// accepted the command, completion is the only release path.
    @discardableResult
    func cancelUncommittedSubmission(on commandBuffer: MTLCommandBuffer) -> Bool {
        guard commandBuffer.status == .notEnqueued else { return false }
        let submissionCommandBuffer = ObjectIdentifier(commandBuffer)
        return withLock {
            var cancelled = false
            for index in slots.indices where
                slots[index].submissionCommandBuffer == submissionCommandBuffer
            {
                // A matching command identity is sufficient here: a slot is
                // marked in-flight at the same time the identity is stored,
                // and only this method can clear it before command enqueue.
                slots[index].isInFlight = false
                slots[index].submissionCommandBuffer = nil
                cancelled = true
            }
            armedSubmissionCommandBuffers.remove(submissionCommandBuffer)
            if cancelled, currentSlotIndex == nil {
                currentCount = 0
            }
            return cancelled
        }
    }

    func currentDrawState() -> (buffer: MTLBuffer, count: Int)? {
        withLock {
            guard currentCount > 0, let currentSlotIndex else { return nil }
            return (slots[currentSlotIndex].buffer, currentCount)
        }
    }

    private func prepareSlot(device: MTLDevice, requiredCount: Int) -> Int? {
        let slotIndex = currentSlotIndex
            ?? slots.indices.first(where: {
                !slots[$0].isInFlight && slots[$0].capacity >= requiredCount
            })
            ?? slots.indices.first(where: { !slots[$0].isInFlight })

        if let slotIndex {
            guard slots[slotIndex].capacity < requiredCount else { return slotIndex }
            let capacity = max(requiredCount, max(slots[slotIndex].capacity * 2, 64))
            guard let buffer = makeBuffer(
                device: device,
                capacity: capacity,
                slotIndex: slotIndex
            ) else { return nil }
            slots[slotIndex] = Slot(
                buffer: buffer,
                capacity: capacity,
                isInFlight: false,
                submissionCommandBuffer: nil
            )
            return slotIndex
        }

        let capacity = max(requiredCount, max(slots.map(\.capacity).max() ?? 0, 64))
        let newIndex = slots.count
        guard let buffer = makeBuffer(
            device: device,
            capacity: capacity,
            slotIndex: newIndex
        ) else { return nil }
        slots.append(Slot(
            buffer: buffer,
            capacity: capacity,
            isInFlight: false,
            submissionCommandBuffer: nil
        ))
        return newIndex
    }

    private func makeBuffer(
        device: MTLDevice,
        capacity: Int,
        slotIndex: Int
    ) -> MTLBuffer? {
        let length = capacity * MemoryLayout<SceneParticleGPUInstance>.stride
        let buffer = device.makeBuffer(length: length, options: .storageModeShared)
        buffer?.label = "Scene particle instances slot \(slotIndex)"
        return buffer
    }

    private func releaseSlots(for commandBuffer: ObjectIdentifier) {
        withLock {
            for index in slots.indices where
                slots[index].submissionCommandBuffer == commandBuffer
            {
                slots[index].isInFlight = false
                slots[index].submissionCommandBuffer = nil
            }
            armedSubmissionCommandBuffers.remove(commandBuffer)
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
