import Foundation

extension SILService {
    var personalSettingsSources: [PersonalSettingsLocalSource] {
        wallpapers.map { .init(reference: .init(provider: .staticImageLibrary, sourceID: $0.id), path: $0.path, title: $0.title) }
    }

    func applyPersonalSettingsSources(_ patches: [PersonalSettingsSourcePatch], at date: Date) throws {
        guard allowsLibraryMutation else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        guard patches.contains(where: { $0.target.reference.provider == .staticImageLibrary }) else { return }
        var target = wallpapers
        for patch in patches where patch.target.reference.provider == .staticImageLibrary {
            let reference = patch.target.reference
            let index = target.firstIndex { WallpaperReference(provider: .staticImageLibrary, sourceID: $0.id) == reference }
            let current = index.map { PersonalSettingsLocalSource(reference: reference, path: target[$0].path, title: target[$0].title) }
            guard current == patch.before || current == patch.target else { throw PersonalSettingsError.sourceChanged }
            if let index {
                target[index].title = patch.target.title
            } else {
                let path = URL(fileURLWithPath: patch.target.path).resolvingSymlinksInPath().standardizedFileURL.path
                guard !target.contains(where: { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().standardizedFileURL.path == path }) else {
                    throw PersonalSettingsError.sourceChanged
                }
                target.append(SILWallpaper(personalSettingsSource: patch.target, at: date))
            }
        }
        try persistWallpaperMetadata(target, synchronize: true)
        if wallpapers != target { wallpapers = target }
    }
}

extension SILWallpaper {
    /// Offline recovery creates no stat/ImageIO/thumbnail demand.
    init(personalSettingsSource source: PersonalSettingsLocalSource, at date: Date) {
        id = source.reference.sourceID
        path = source.path
        title = source.title
        fileSize = nil; pixelWidth = nil; pixelHeight = nil
        tags = []; lastUsed = .distantPast; addedAt = date
    }
}
