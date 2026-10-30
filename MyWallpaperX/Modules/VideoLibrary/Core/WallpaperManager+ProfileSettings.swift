import Foundation

extension WallpaperManager {
    /// App sets this before constructing the source owner when a durable
    /// personal-settings recovery exists. Loading remains writable for resume.
    static var defersMissingFileCleanupForPersonalSettingsRecovery = false

    func resumeMissingFileCleanupAfterSettingsRecovery() {
        guard Self.defersMissingFileCleanupForPersonalSettingsRecovery else { return }
        Self.defersMissingFileCleanupForPersonalSettingsRecovery = false
        if didFinishInitialIndexLoad { scheduleMissingIndexedSourceFilesScan() }
        // An unsettled source schedules its original scan after publication.
    }

    var personalSettingsSources: [PersonalSettingsLocalSource] {
        wallpapers.map { .init(reference: .init(provider: .videoLibrary, sourceID: $0.id), path: $0.path, title: $0.title, firstIndexedAt: $0.firstIndexedAt) }
    }

    /// Source metadata only. Relationships, history and playback remain with
    /// their existing owners; profiles never write retired tag/favorite fields.
    func applyPersonalSettingsSources(_ patches: [PersonalSettingsSourcePatch]) throws {
        guard allowsLibraryMutation else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        guard didFinishInitialIndexLoad else { throw PersonalSettingsError.indexLoading }
        guard patches.contains(where: { $0.target.reference.provider == .videoLibrary }) else { return }
        var target = wallpapers
        for patch in patches where patch.target.reference.provider == .videoLibrary {
            let ref = patch.target.reference
            let index = target.firstIndex { WallpaperReference(provider: .videoLibrary, sourceID: $0.id) == ref }
            let current = index.map { PersonalSettingsLocalSource(reference: ref, path: target[$0].path, title: target[$0].title, firstIndexedAt: target[$0].firstIndexedAt) }
            guard current == patch.before || current == patch.target else { throw PersonalSettingsError.sourceChanged }
            if let index {
                let old = target[index]
                target[index] = VideoWallpaper(id: old.id, title: patch.target.title, path: old.path,
                    thumbnailPath: old.thumbnailPath, staticFramePath: old.staticFramePath, isFavorite: old.isFavorite,
                    lastUsed: old.lastUsed, tags: old.tags, fileSize: old.fileSize, duration: old.duration, resolution: old.resolution,
                    firstIndexedAt: old.firstIndexedAt ?? patch.target.firstIndexedAt)
            } else {
                guard !target.contains(where: { normalizedPath($0.path) == normalizedPath(patch.target.path) }) else {
                    throw PersonalSettingsError.sourceChanged
                }
                target.append(VideoWallpaper(id: ref.sourceID, title: patch.target.title, path: patch.target.path, lastUsed: .distantPast,
                                             firstIndexedAt: patch.target.firstIndexedAt))
            }
        }
        // Already-applied patches still retry a previous failed durable save.
        try persistWallpaperIndexNow(target)
        let wasPublishing = initialIndexInternalPublication
        initialIndexInternalPublication = true
        defer { initialIndexInternalPublication = wasPublishing }
        if wallpapers != target { wallpapers = target }
    }

    func applyPersonalSettingsPreferences(expected: PersonalSettingsPreferences, target: PersonalSettingsPreferences) throws {
        guard allowsLibraryMutation else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: migrationRecoveryMessage ?? "资料库需要恢复"])
        }
        let current = PersonalSettingsPreferences(from: settings)
        guard expected.matchesForRecovery(current) || target.matchesForRecovery(current) else { throw PersonalSettingsError.preferencesChanged }
        let updated = target.applying(to: settings)
        try persistSettingsNow(updated)
        settings = updated
        PlaybackPolicyController.shared.updateSettings(updated)
        // The settings sink handles engine field diffs; no timer, playback
        // source or recent event is created by importing preferences.
        updateLoginItemStatus()
    }
}
