import Foundation

/// Shared user intent. Authored HDR/Bloom and each display's capability remain
/// separate inputs; changing this preference never reloads a Scene.
enum SceneHDRDisplayPreference {
    static let key = "sceneHDRDisplayEnabled"
    static let changed = Notification.Name("com.mywallpaperx.sceneHDRDisplayChanged")

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        UserDefaults.standard.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func refresh() {
        UserDefaults.standard.synchronize()
    }
}
