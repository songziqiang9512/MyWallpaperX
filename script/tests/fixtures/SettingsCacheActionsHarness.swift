import AppKit
import Foundation
import UniformTypeIdentifiers

struct WallpaperSettings {}
struct PersonalSettingsExportSummary { var wallpaperCount = 3, tagCount = 2 }
struct PersonalSettingsImportSummary { var mergedWallpaperCount = 1, createdWallpaperCount = 2, tagCount = 3, missingPathCount = 4 }
enum PersonalSettingsError: Error { case recoveryRequired(String) }
@MainActor final class PersonalSettingsImportCoordinator {
    func exportPersonalSettings(to: URL) async throws -> PersonalSettingsExportSummary { .init() }
    func importPersonalSettings(from: URL) async throws -> PersonalSettingsImportSummary { .init() }
}

@MainActor enum Trace {
    static var events: [String] = []
    static var alerts: [String] = []
    static var alertHosts: [ObjectIdentifier?] = []
    static var response = NSApplication.ModalResponse.alertFirstButtonReturn
    static func reset() { events = []; alerts = []; alertHosts = [] }
}
@MainActor final class CacheLeaf {
    let name: String
    init(_ name: String) { self.name = name }
    func clearAll() { Trace.events.append(name + ".clear") }
}
@MainActor enum VideoLibraryThumbnailStore { static let sharedCache = CacheLeaf("video") }
@MainActor enum SILThumbnailStore { static let sharedCache = CacheLeaf("image") }
@MainActor enum OLDownloadedThumbnailStore { static let sharedCache = CacheLeaf("downloaded") }
@MainActor enum SteamWorkshopPreviewImageCache { static let shared = CacheLeaf("steam") }
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    func clearAllCachedState() {
        Trace.events.append("steam.state")
        SteamWorkshopPreviewImageCache.shared.clearAll()
    }
}
@MainActor final class OLThumbnailCache {
    static let shared = OLThumbnailCache()
    var continuation: CheckedContinuation<Void, Never>?
    func clearAll() async {
        Trace.events.append("online.begin")
        await withCheckedContinuation { continuation = $0 }
        Trace.events.append("online.end")
    }
    func finish() { let pending = continuation; continuation = nil; pending?.resume() }
}
@MainActor final class WallpaperManager {
    static let shared = WallpaperManager()
    func clearAllCaches() { Trace.events.append("manager") }
    func applyEngineSettings(reloadWallpaper: Bool) {}
    func refreshAutoSwitchTimerIfNeeded() {}
    func setLoopPlaybackEnabled(_: Bool) {}
    func setRandomPlaybackEnabled(_: Bool) {}
    func setSequentialPlaybackEnabled(_: Bool) {}
    func setSyncSystemWallpaperEnabled(_: Bool) {}
    func startAutoSwitchTimer() {}
    func stopAutoSwitchTimer() {}
    func updateLoginItemStatus() {}
    func updateVolume(_: Double) {}
}

@MainActor final class SettingsContentViewController {
    var personalSettings: PersonalSettingsImportCoordinator?
    var resetAction: (() -> Void)?
    // ACTUAL_ACTION_FACTORY
    var actions: AppSettingsActions { settingsActions }
}

@MainActor final class HostWindow: NSWindow {
    var shown = true
    override var isVisible: Bool { shown }
}
@MainActor func makeAppAlert(title: String, message: String = "", buttons: [String] = ["确定"]) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    buttons.forEach { alert.addButton(withTitle: $0) }
    return alert
}
@MainActor func presentAppAlert(_ alert: NSAlert, in window: NSWindow?,
                               completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
    Trace.alerts.append(alert.messageText)
    Trace.alertHosts.append(window.map(ObjectIdentifier.init))
    completion?(Trace.response)
}
@MainActor final class AppKitSettingsContainerView: NSObject {
    let dependency: AppSettingsPanelDependency
    let clearCacheButton = NSButton(title: "清除缓存", target: nil, action: nil)
    let exportProfileButton = NSButton(title: "导出", target: nil, action: nil)
    let importProfileButton = NSButton(title: "导入", target: nil, action: nil)
    let host = HostWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    var fallbackHost: HostWindow?
    var selectedSaveURL: URL? = URL(fileURLWithPath: "/unused/export.json")
    var selectedOpenURL: URL? = URL(fileURLWithPath: "/unused/import.json")
    init(actions: AppSettingsActions) {
        dependency = .init(settings: .init(), actions: actions)
        super.init()
        clearCacheButton.target = self
        clearCacheButton.action = #selector(handleClearCache)
        exportProfileButton.target = self; exportProfileButton.action = #selector(handleExportProfile)
        importProfileButton.target = self; importProfileButton.action = #selector(handleImportProfile)
    }
    func preferredHostWindow() -> NSWindow? {
        return host.isVisible ? host : fallbackHost
    }
    func presentSavePanel(_ panel: NSSavePanel, completion: @escaping (URL?) -> Void) { completion(selectedSaveURL) }
    func presentOpenPanel(_ panel: NSOpenPanel, completion: @escaping (URL?) -> Void) { completion(selectedOpenURL) }
    // ACTUAL_CLEAR_HANDLER
    // ACTUAL_EXPORT_HANDLER
    // ACTUAL_IMPORT_HANDLER
}

@MainActor final class ProfileGate {
    enum Failure: Error { case fixture }
    var exportURLs: [URL] = [], importURLs: [URL] = []
    var completedExports = 0, completedImports = 0
    var exportContinuation: CheckedContinuation<PersonalSettingsExportSummary, Error>?
    var importContinuation: CheckedContinuation<PersonalSettingsImportSummary, Error>?
    func export(_ url: URL) async throws -> PersonalSettingsExportSummary {
        exportURLs.append(url)
        return try await withCheckedThrowingContinuation { exportContinuation = $0 }
    }
    func importProfile(_ url: URL) async throws -> PersonalSettingsImportSummary {
        importURLs.append(url)
        return try await withCheckedThrowingContinuation { importContinuation = $0 }
    }
    func finish(export: Bool, failing: Bool) {
        if export {
            let pending = exportContinuation; exportContinuation = nil; completedExports += 1
            if failing { pending?.resume(throwing: Failure.fixture) } else { pending?.resume(returning: .init()) }
        } else {
            let pending = importContinuation; importContinuation = nil; completedImports += 1
            if failing { pending?.resume(throwing: Failure.fixture) } else { pending?.resume(returning: .init()) }
        }
    }
    var actions: AppSettingsActions {
        .init(exportPersonalSettings: { try await self.export($0) },
              importPersonalSettings: { try await self.importProfile($0) })
    }
}

@main enum Checks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let controller = SettingsContentViewController()
        let view = AppKitSettingsContainerView(actions: controller.actions)
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            precondition(condition(), name); checks[name] = true
        }
        func settle(_ predicate: () -> Bool) async {
            for _ in 0..<200 where !predicate() { await Task.yield() }
            precondition(predicate(), "settings async action did not settle")
        }
        Trace.response = .alertSecondButtonReturn
        view.clearCacheButton.performClick(nil)
        check("cancel-has-zero-provider-effects", Trace.events.isEmpty)
        check("cancel-keeps-button-and-has-no-success", view.clearCacheButton.isEnabled
              && view.clearCacheButton.title == "清除缓存" && Trace.alerts == ["清空缓存"])

        Trace.reset(); Trace.response = .alertFirstButtonReturn
        view.clearCacheButton.performClick(nil)
        await settle { OLThumbnailCache.shared.continuation != nil }
        check("pending-has-no-success-feedback", Trace.alerts == ["清空缓存"])
        check("pending-button-disabled-with-progress-label", !view.clearCacheButton.isEnabled
              && view.clearCacheButton.title == "清理中…")
        let expected = ["manager", "video.clear", "image.clear", "downloaded.clear", "steam.state", "steam.clear", "online.begin"]
        check("every-provider-and-steam-namespace-clears-once", Trace.events == expected)
        OLThumbnailCache.shared.finish()
        await settle { view.clearCacheButton.isEnabled }
        check("success-follows-online-completion", Trace.events == expected + ["online.end"]
              && Trace.alerts == ["清空缓存", "缓存已清空"])
        check("completed-button-restores-original-label", view.clearCacheButton.title == "清除缓存")

        Trace.reset(); view.clearCacheButton.performClick(nil)
        await settle { OLThumbnailCache.shared.continuation != nil }
        view.host.shown = false
        OLThumbnailCache.shared.finish()
        await settle { view.clearCacheButton.isEnabled }
        check("closed-host-finishes-clear-without-orphan-success-sheet", Trace.events == expected + ["online.end"]
              && Trace.alerts == ["清空缓存"])
        view.host.shown = true
        Trace.reset(); view.clearCacheButton.performClick(nil)
        await settle { OLThumbnailCache.shared.continuation != nil }
        OLThumbnailCache.shared.finish()
        await settle { view.clearCacheButton.isEnabled }
        check("next-operation-remains-usable-and-clears-once", Trace.events == expected + ["online.end"]
              && Trace.alerts == ["清空缓存", "缓存已清空"])

        for exporting in [true, false] {
            let operation = exporting ? "export" : "import"
            let cancelledGate = ProfileGate()
            let chooserCancelled = AppKitSettingsContainerView(actions: cancelledGate.actions)
            chooserCancelled.selectedSaveURL = nil; chooserCancelled.selectedOpenURL = nil
            Trace.reset(); Trace.response = .alertFirstButtonReturn
            (exporting ? chooserCancelled.exportProfileButton : chooserCancelled.importProfileButton).performClick(nil)
            check(operation + "-cancelled-chooser-has-no-transaction-or-terminal-alert", cancelledGate.exportURLs.isEmpty
                  && cancelledGate.importURLs.isEmpty && Trace.alerts.isEmpty
                  && chooserCancelled.exportProfileButton.isEnabled && chooserCancelled.importProfileButton.isEnabled)
            if !exporting {
                let confirmationGate = ProfileGate()
                let confirmationCancelled = AppKitSettingsContainerView(actions: confirmationGate.actions)
                Trace.reset(); Trace.response = .alertSecondButtonReturn
                confirmationCancelled.importProfileButton.performClick(nil)
                check("import-cancelled-confirmation-has-no-transaction", confirmationGate.importURLs.isEmpty
                      && Trace.alerts == ["导入个人设置"] && confirmationCancelled.exportProfileButton.isEnabled
                      && confirmationCancelled.importProfileButton.isEnabled)
            }
            for failing in [false, true] {
                for closing in [false, true] {
                    let gate = ProfileGate()
                    let actual = AppKitSettingsContainerView(actions: gate.actions)
                    let second = HostWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
                    let state = operation + (failing ? "-failure" : "-success") + (closing ? "-closed" : "-visible")
                    Trace.reset(); Trace.response = .alertFirstButtonReturn
                    (exporting ? actual.exportProfileButton : actual.importProfileButton).performClick(nil)
                    await settle { exporting ? gate.exportContinuation != nil : gate.importContinuation != nil }
                    check(state + "-pending-disables-both-buttons", !actual.exportProfileButton.isEnabled && !actual.importProfileButton.isEnabled)
                    let before = Trace.alerts.count
                    actual.fallbackHost = second
                    actual.host.shown = !closing
                    gate.finish(export: exporting, failing: failing)
                    await settle { actual.exportProfileButton.isEnabled && actual.importProfileButton.isEnabled }
                    let completed = exporting ? gate.completedExports : gate.completedImports
                    let urls = exporting ? gate.exportURLs : gate.importURLs
                    let expectedURL = exporting ? actual.selectedSaveURL! : actual.selectedOpenURL!
                    check(state + "-original-transaction-finishes-once", completed == 1 && urls == [expectedURL])
                    let resultTitle = exporting ? (failing ? "导出失败" : "导出完成") : (failing ? "导入未完成" : "导入完成")
                    check(state + "-terminal-feedback-stays-with-the-original-host", closing ? Trace.alerts.count == before :
                            Trace.alerts.count == before + 1 && Trace.alerts.last == resultTitle
                            && Trace.alertHosts.last! == ObjectIdentifier(actual.host))
                    check(state + "-second-host-never-receives-terminal-feedback", !Trace.alertHosts.contains(ObjectIdentifier(second)))
                    actual.host.shown = true
                    Trace.reset()
                    (exporting ? actual.exportProfileButton : actual.importProfileButton).performClick(nil)
                    await settle { exporting ? gate.exportContinuation != nil : gate.importContinuation != nil }
                    gate.finish(export: exporting, failing: false)
                    await settle { actual.exportProfileButton.isEnabled && actual.importProfileButton.isEnabled }
                    check(state + "-next-operation-remains-usable", (exporting ? gate.completedExports : gate.completedImports) == 2
                          && (exporting ? gate.exportURLs : gate.importURLs) == [expectedURL, expectedURL]
                          && Trace.alerts.last == (exporting ? "导出完成" : "导入完成")
                          && Trace.alertHosts.last! == ObjectIdentifier(actual.host))
                }
            }
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
