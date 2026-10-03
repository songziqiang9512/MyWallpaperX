//
//  DebugPlaybackFailureCapture.swift
//  MyWallpaperX
//

#if DEBUG
import Foundation

final class DebugPlaybackFailureCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [[AnyHashable: Any]] = []

    func reset() {
        lock.lock()
        payloads.removeAll()
        lock.unlock()
    }

    func append(_ payload: [AnyHashable: Any]) {
        lock.lock()
        payloads.append(payload)
        lock.unlock()
    }

    func snapshot() -> [[AnyHashable: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return payloads
    }
}
#endif
