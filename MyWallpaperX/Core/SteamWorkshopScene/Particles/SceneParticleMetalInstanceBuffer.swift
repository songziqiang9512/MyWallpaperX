import Foundation
import Metal

final class SceneParticleMetalInstanceBuffer: @unchecked Sendable {
    private struct Slot {
        var buffer: MTLBuffer
        var capacity: Int
        var isInFlight: Bool
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
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
    func markSubmitted(on commandBuffer: MTLCommandBuffer) -> Bool {
        let submittedSlot: Int? = withLock {
            guard let currentSlotIndex else { return nil }
            slots[currentSlotIndex].isInFlight = true
            self.currentSlotIndex = nil
            return currentSlotIndex
        }
        guard let submittedSlot else { return false }
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.releaseSlot(at: submittedSlot)
        }
        return true
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
            slots[slotIndex] = Slot(buffer: buffer, capacity: capacity, isInFlight: false)
            return slotIndex
        }

        let capacity = max(requiredCount, max(slots.map(\.capacity).max() ?? 0, 64))
        let newIndex = slots.count
        guard let buffer = makeBuffer(
            device: device,
            capacity: capacity,
            slotIndex: newIndex
        ) else { return nil }
        slots.append(Slot(buffer: buffer, capacity: capacity, isInFlight: false))
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

    private func releaseSlot(at index: Int) {
        withLock {
            guard slots.indices.contains(index) else { return }
            slots[index].isInFlight = false
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
