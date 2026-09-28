import Foundation

enum WallpaperRuntimeKind: String {
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
    ImportedVideoAutoplayGate.shared.invalidate()
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
