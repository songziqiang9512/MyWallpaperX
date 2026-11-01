import Foundation
import ObjectiveC
import CoreGraphics

struct SystemWallpaperGeometry: Sendable {
    enum Presentation: String, Sendable { case desktop = "default", locked, screenSaver = "active", idle }
    let displayID: CGDirectDisplayID
    let size: CGSize
    let scale: CGFloat
    var isPreview: Bool
    var presentation: Presentation = .desktop
    var isActive = true
}

/// The private host boundary ends here; media and playback use public APIs.
enum SystemWallpaperWire {
    private static let frameworkAvailable = dlopen(
        "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit",
        RTLD_NOW | RTLD_LOCAL
    ) != nil

    static func geometry(in request: Any) throws -> SystemWallpaperGeometry {
        let display = field("directDisplayID", in: request) as? UInt32 ?? CGMainDisplayID()
        let size = field("size", in: request) as? CGSize ?? CGDisplayBounds(display).size
        let scale = (field("scaleFactor", in: request) as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              scale.isFinite, scale > 0 else { throw CocoaError(.coderReadCorrupt) }
        let mode = field("presentationMode", in: request).map { String(describing: $0) } ?? "default"
        let activity = field("activityState", in: request).map { String(describing: $0) } ?? "active"
        return SystemWallpaperGeometry(displayID: display, size: size, scale: scale,
                                       isPreview: field("isPreview", in: request) as? Bool ?? false,
                                       presentation: .init(rawValue: mode) ?? .desktop,
                                       isActive: activity == "active")
    }

    static func allowedClasses() throws -> Set<AnyHashable> {
        guard frameworkAvailable else { throw CocoaError(.featureUnsupported) }
        let classes = NSMutableSet(array: [NSString.self, NSNumber.self, NSData.self, NSArray.self,
                                          NSDictionary.self, NSURL.self, NSError.self])
        for name in ["WallpaperIDXPC", "WallpaperCreationRequestXPC", "WallpaperUpdateRequestXPC",
                     "WallpaperRemoteContextXPC", "WallpaperSnapshotXPC", "WallpaperContentTypeSetXPC",
                     "WallpaperChoiceIDXPC", "WallpaperChoiceIDsXPC", "WallpaperSettingsViewModelsXPC"] {
            guard let type = NSClassFromString(name) else { throw CocoaError(.featureUnsupported) }
            classes.add(type)
        }
        return classes as! Set<AnyHashable>
    }

    private static func object<Value: Encodable>(className: String, key: String, payload: Value) throws -> NSObject {
        guard frameworkAvailable,
              let type = NSClassFromString(className) as? (NSObject & NSSecureCoding).Type else {
            throw NSError(domain: "MyWallpaperX.SystemWallpaper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "系统动态锁屏接口不可用。"])
        }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(className, for: ValueArchive.self)
        let envelope = ValueArchive { try $0.encodeEncodable(payload, forKey: key) }
        archiver.encode(envelope, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        if let error = envelope.error { throw error }
        guard let value = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [type], from: archiver.encodedData) as? NSObject else {
            throw CocoaError(.coderReadCorrupt)
        }
        return value
    }

    static func settings<Value: Encodable>(_ payload: Value) throws -> NSObject {
        try object(className: "WallpaperSettingsViewModelsXPC", key: "WallpaperSettingsViewModels", payload: payload)
    }

    static func remoteContext(_ identifier: UInt32) throws -> NSObject {
        try object(className: "WallpaperRemoteContextXPC", key: "UInt32", payload: identifier)
    }

    static func field(_ name: String, in value: Any) -> Any? {
        search(name, in: value, depth: 0)
    }

    static func identifier(_ value: Any?) -> UUID? {
        guard let value else { return nil }
        return value as? UUID ?? field("id", in: value) as? UUID
    }

    private static func search(_ name: String, in value: Any, depth: Int) -> Any? {
        let mirror = Mirror(reflecting: value)
        if let child = mirror.children.first(where: { $0.label == name }) {
            var result = child.value
            while Mirror(reflecting: result).displayStyle == .optional {
                guard let wrapped = Mirror(reflecting: result).children.first else { return nil }
                result = wrapped.value
            }
            return result
        }
        guard depth < 8 else { return nil }
        for child in mirror.children {
            if let found = search(name, in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    @objc(MWXSystemWallpaperArchiveValue)
    private final class ValueArchive: NSObject, NSSecureCoding {
        static var supportsSecureCoding: Bool { true }
        private let write: (NSKeyedArchiver) throws -> Void
        private(set) var error: Error?

        init(write: @escaping (NSKeyedArchiver) throws -> Void) { self.write = write; super.init() }
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {
            do { try write(coder as! NSKeyedArchiver) }
            catch { self.error = error }
        }
    }
}
