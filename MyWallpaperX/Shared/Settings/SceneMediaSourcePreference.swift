import Foundation

/// User intent for wallpaper song info, shared by the settings UI and the
/// Scene process. One switch covers every supported source; the media
/// producer owns which concrete source actually serves a session, so this
/// preference never names a source.
enum SceneMediaSourcePreference {
    static let key = "sceneMediaInfoEnabled"
    static let changed = Notification.Name("com.mywallpaperx.sceneMediaPlayerSourceChanged")

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
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
