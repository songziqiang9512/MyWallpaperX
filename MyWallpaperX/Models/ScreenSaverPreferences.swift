import Foundation

/// Portable user intent only. Published files, component installation and the
/// system's selected screen saver have independent owners and are not exported.
nonisolated struct ScreenSaverPreferences: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case fixed, followDesktop }

    var mode: Mode
    var reference: WallpaperReference?
    var fillMode: String
    var playsOnBattery: Bool

    init(mode: Mode = .fixed, reference: WallpaperReference? = nil,
         fillMode: String = "aspectFill", playsOnBattery: Bool = false) {
        self.mode = mode
        self.reference = reference
        self.fillMode = fillMode
        self.playsOnBattery = playsOnBattery
    }

    private enum CodingKeys: String, CodingKey { case mode, reference, fillMode, playsOnBattery }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .fixed
        reference = try values.decodeIfPresent(WallpaperReference.self, forKey: .reference)
        fillMode = try values.decodeIfPresent(String.self, forKey: .fillMode) ?? "aspectFill"
        playsOnBattery = try values.decodeIfPresent(Bool.self, forKey: .playsOnBattery) ?? false
    }
}
