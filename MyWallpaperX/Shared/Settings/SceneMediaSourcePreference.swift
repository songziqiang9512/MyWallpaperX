import Foundation

/// Explicit source intent, shared by the settings UI and the Scene process.
/// A supported player's metadata must not masquerade as a global system session.
enum SceneMediaSourcePreference: String, CaseIterable, Sendable {
    case disabled
    case appleMusic
    case systemNowPlaying

    static let key = "sceneMediaPlayerSource"
    static let changed = Notification.Name("com.mywallpaperx.sceneMediaPlayerSourceChanged")

    static var current: Self {
        let source = UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .disabled
        #if !DEBUG
        if source == .systemNowPlaying { return .disabled }
        #endif
        return source
    }

    static func set(_ source: Self) {
        UserDefaults.standard.set(source.rawValue, forKey: key)
        UserDefaults.standard.synchronize()
        notifyChange()
    }

    static func notifyChange() {
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    /// Called only on process startup or a source/authorization notification.
    static func refresh() {
        UserDefaults.standard.synchronize()
    }
}
