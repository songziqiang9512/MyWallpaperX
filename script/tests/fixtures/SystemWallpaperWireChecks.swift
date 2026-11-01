import Foundation
import ObjectiveC

@main
enum SystemWallpaperWireChecks {
    static func main() {
        do { try check() }
        catch { print("FAIL:", error); exit(1) }
    }

    static func check() throws {
        let remote = try SystemWallpaperWire.remoteContext(0x1234)
        guard SystemWallpaperWire.field("rawValue", in: remote) as? UInt32 == 0x1234 else {
            throw CocoaError(.coderReadCorrupt)
        }
        let remoteArchive = try NSKeyedArchiver.archivedData(withRootObject: remote, requiringSecureCoding: true)
        let roundTrip = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [type(of: remote)], from: remoteArchive)
        guard let roundTrip, SystemWallpaperWire.field("rawValue", in: roundTrip) as? UInt32 == 0x1234 else {
            throw CocoaError(.coderReadCorrupt)
        }

        let media = SystemWallpaperMedia(configuration: ScreenSaverConfiguration(content: .init(
            kind: .video, mediaGeneration: UUID().uuidString, title: "Motion fixture",
            entryRelativePath: "video.mp4", posterRelativePath: "poster.png")),
            root: URL(fileURLWithPath: "/fixture"), video: URL(fileURLWithPath: "/fixture/video.mp4"),
            poster: URL(fileURLWithPath: "/fixture/poster.png"))
        let settings = try SystemWallpaperWire.settings(SystemWallpaperCatalog(media: media))
        let settingsArchive = try NSKeyedArchiver.archivedData(withRootObject: settings, requiringSecureCoding: true)
        let restored = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [type(of: settings)], from: settingsArchive)
        guard let restored,
              let desktop = SystemWallpaperWire.field("desktop", in: restored),
              (SystemWallpaperWire.field("groups", in: desktop) as? [Any])?.isEmpty == true,
              let screenSaver = SystemWallpaperWire.field("screenSaver", in: restored),
              SystemWallpaperWire.field("isModificationDisabled", in: screenSaver) as? Bool == false,
              let groups = SystemWallpaperWire.field("groups", in: screenSaver) as? [Any], groups.count == 1,
              let items = SystemWallpaperWire.field("items", in: groups[0]) as? [Any], items.count == 1,
              SystemWallpaperWire.field("localizedName", in: items[0]) as? String == "Motion fixture" else {
            throw CocoaError(.coderReadCorrupt)
        }
        let empty = try SystemWallpaperWire.settings(SystemWallpaperCatalog(media: nil))
        guard let desktop = SystemWallpaperWire.field("desktop", in: empty),
              (SystemWallpaperWire.field("groups", in: desktop) as? [Any])?.isEmpty == true,
              let screenSaver = SystemWallpaperWire.field("screenSaver", in: empty),
              let groups = SystemWallpaperWire.field("groups", in: screenSaver) as? [Any], groups.isEmpty else {
            throw CocoaError(.coderReadCorrupt)
        }
        _ = try SystemWallpaperWire.allowedClasses()
        struct Request {
            let directDisplayID: UInt32 = 1
            let size = CGSize(width: 800, height: 600)
            let scaleFactor = 2
            let presentationMode: String
            let activityState: String
        }
        let active = try SystemWallpaperWire.geometry(in: Request(presentationMode: "active", activityState: "active"))
        let suspended = try SystemWallpaperWire.geometry(in: Request(presentationMode: "locked", activityState: "suspended"))
        guard active.presentation == .screenSaver, active.isActive, active.size.width == 800, active.scale == 2,
              suspended.presentation == .locked, !suspended.isActive else { throw CocoaError(.coderReadCorrupt) }
        print("PASS: real system settings and remote-context values round-trip")
    }
}
