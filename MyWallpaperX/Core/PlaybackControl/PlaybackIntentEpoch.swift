import Foundation

/// Product-level playback intent epoch (E2a-1). The selection authority
/// (WallpaperManager) owns the counter and increments it at every switch
/// entry; runtime adapters adopt the published value as their execution
/// epoch mirror. Internal adapter restarts (e.g. web host failover) keep
/// their own increment and never move the epoch backwards, so a daemon
/// recovery guard that compares epochs still detects any newer intent.
nonisolated struct PlaybackIntentEpoch: Sendable {
    private(set) var value: UInt64 = 0

    /// Called once per switch entry by the selection authority; returns the
    /// new epoch so callers can hand it to adapters.
    mutating func begin() -> UInt64 {
        value &+= 1
        return value
    }

    /// Monotonic adoption for an adapter-side mirror: a newer product epoch
    /// wins, a stale one (the adapter restarted locally since) is ignored.
    static func adopted(mirror: UInt64, product: UInt64) -> UInt64 {
        max(mirror, product)
    }
}
