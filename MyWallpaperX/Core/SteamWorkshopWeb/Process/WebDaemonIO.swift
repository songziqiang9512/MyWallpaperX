import Foundation
import Darwin

/// A pipe read completes on available bytes, not when a requested 64 KiB has
/// accumulated. Launch controls must be consumed while the parent keeps stdin open.
nonisolated enum WebDaemonPipeReader {
    static func read(from handle: FileHandle, receive: (Data) -> Bool) {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0, receive(Data(bytes.prefix(count))) else { return }
        }
    }
}

/// One bounded mailbox on each pipe direction. Critical controls are barriers;
/// high-rate values coalesce without blocking either AppKit main run loop.
nonisolated final class WebDaemonMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = DaemonCommandBuffer<Data, Data>()
    private var scheduled = false
    private var closed = false

    func submit(_ data: Data, latest: Bool, schedule: () -> Void) -> Bool {
        lock.lock()
        guard !closed, data.count <= WebDaemonProtocol.maximumFrameBytes else {
            lock.unlock(); return false
        }
        if latest { pending.enqueueDroppable(data) }
        else if !pending.enqueueControl(data, byteCount: data.count,
                    maximumCount: DaemonCommandBufferLimits.maximumPendingControlCount,
                    maximumBytes: DaemonCommandBufferLimits.maximumPendingControlBytes) {
            lock.unlock(); return false
        }
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if shouldSchedule { schedule() }
        return true
    }

    func take() -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, let entry = pending.takeFirst() else { scheduled = false; return nil }
        switch entry {
        case let .control(data, _), let .droppable(data): return data
        }
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true; pending.removeAll()
    }
}
