import Foundation
import Darwin

// DaemonCommand / DaemonEvent 定义在 DaemonProtocol.swift，
// 通过 Xcode Target Membership 共享到此 target，此处不再重复定义。

@inline(__always)
func daemonLog(_ message: @autoclosure () -> String) {
#if DEBUG
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date())
    fputs("daemon[\(timestamp)]: \(message())\n", stderr)
#endif
}
