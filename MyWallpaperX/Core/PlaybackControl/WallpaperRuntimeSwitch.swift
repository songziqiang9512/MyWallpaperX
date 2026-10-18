import Foundation

nonisolated enum WallpaperRuntimeKind: String, Hashable, Sendable {
    case video
    case web
    case scene
    case systemStill
}

extension Notification.Name {
    static let wallpaperRuntimeWillSwitch = Notification.Name("WallpaperRuntimeWillSwitch")
}

@inline(__always)
func postWallpaperRuntimeWillSwitch(
    to kind: WallpaperRuntimeKind,
    recordID: String? = nil
) {
    var userInfo = ["kind": kind.rawValue]
    if let recordID {
        userInfo["recordID"] = recordID
    }
    NotificationCenter.default.post(
        name: .wallpaperRuntimeWillSwitch,
        object: nil,
        userInfo: userInfo
    )
}
