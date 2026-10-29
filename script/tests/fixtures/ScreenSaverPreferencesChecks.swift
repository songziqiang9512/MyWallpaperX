import Foundation

@MainActor
func screenSaverPreferenceChecks(state: UserCollectionsSnapshot) throws -> [String: Bool] {
    var checks: [String: Bool] = [:]
    let local = WallpaperReference(provider: .videoLibrary, sourceID: "screen-saver-local")
    let imported = WallpaperReference(provider: .videoLibrary, sourceID: "screen-saver-imported")
    let missing = WallpaperReference(provider: .steamWorkshop, sourceID: "scene:unavailable")
    var settings = WallpaperSettings()
    settings.screenSaver = .init(mode: .followDesktop, reference: local, fillMode: "aspectFit", playsOnBattery: true)
    let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(settings))
    checks["ScreenSaverIntentRoundTripsThroughOriginalSettings"] = decoded == settings
    let oldSettings = try JSONDecoder().decode(WallpaperSettings.self, from: Data("{}".utf8))
    checks["OldLocalSettingsAndResetDefaultsRemainUnconfigured"] = oldSettings.screenSaver == ScreenSaverPreferences()
        && WallpaperSettings.defaults.screenSaver == ScreenSaverPreferences()
    let oldProfile = try JSONDecoder().decode(PersonalSettingsPreferences.self, from: Data("{}".utf8))
    checks["AbsentProfileScreenSaverPreservesLocalIntent"] = oldProfile.screenSaver == nil
        && oldProfile.applying(to: settings).screenSaver == settings.screenSaver
    var explicit = PersonalSettingsPreferences(from: settings)
    explicit.screenSaver = ScreenSaverPreferences()
    checks["ExplicitProfileUnconfiguredIntentClearsOnlyThePreference"] = explicit.applying(to: settings).screenSaver == ScreenSaverPreferences()
    let profileRoundTrip = try JSONDecoder().decode(PersonalSettingsPreferences.self,
        from: JSONEncoder().encode(PersonalSettingsPreferences(from: settings)))
    checks["ProfileContainsIntentWithoutInstallationOrMediaPaths"] = profileRoundTrip.screenSaver == settings.screenSaver
    var previous = PersonalSettingsPreferences(from: settings)
    previous.screenSaver = nil
    var changed = settings
    changed.screenSaver.reference = missing
    checks["OldRecoveryDoesNotClaimNewScreenSaverField"] = previous.matchesForRecovery(.init(from: changed))
        && !profileRoundTrip.matchesForRecovery(.init(from: changed))
    let localSource = PersonalSettingsLocalSource(reference: local, path: "/offline/screen-saver.mp4", title: "Same title")
    let importedSource = PersonalSettingsLocalSource(reference: imported, path: localSource.path, title: localSource.title)
    var preferences = PersonalSettingsPreferences(from: settings)
    preferences.screenSaver = .init(reference: imported, fillMode: "aspectFit", playsOnBattery: true)
    let payload = PersonalSettingsPayload(exportedAt: .distantPast, preferences: preferences,
        sources: [importedSource], collections: .init())
    let plan = try LibraryPersonalSettings.plan(payload, sources: [localSource],
        beforePreferences: .init(from: settings), targetPreferences: preferences,
        state: state, normalizedPaths: [:], missingPathCount: 1)
    checks["ScreenSaverReferenceUsesTheExistingSourceRemapping"] = plan.targetPreferences.screenSaver?.reference == local
        && plan.targetPreferences.screenSaver?.fillMode == "aspectFit"
        && plan.targetPreferences.screenSaver?.playsOnBattery == true
    preferences.screenSaver?.reference = missing
    let unavailable = PersonalSettingsPayload(exportedAt: .distantPast, preferences: preferences,
        sources: [], collections: .init())
    let unavailablePlan = try LibraryPersonalSettings.plan(unavailable, sources: [localSource],
        beforePreferences: .init(from: settings), targetPreferences: preferences,
        state: state, normalizedPaths: [:], missingPathCount: 0)
    checks["UnmappedReferenceRemainsUnavailableWithoutBorrowingSameTitle"] = unavailablePlan.targetPreferences.screenSaver?.reference == missing
        && unavailablePlan.sourcePatches.isEmpty
    let oldPayload = PersonalSettingsPayload(exportedAt: .distantPast, preferences: oldProfile,
        sources: [importedSource], collections: .init())
    let oldPlan = try LibraryPersonalSettings.plan(oldPayload, sources: [localSource],
        beforePreferences: .init(from: settings), targetPreferences: .init(from: oldProfile.applying(to: settings)),
        state: state, normalizedPaths: [:], missingPathCount: 1)
    checks["OldProfileSourceRemapDoesNotClaimLocalScreenSaverIntent"] = oldPlan.targetPreferences.screenSaver == settings.screenSaver
    return checks
}
