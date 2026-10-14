from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_detail_diagnostics_on_demand import CONTROLLER_PATH, function_body

ROOT = CONTROLLER_PATH.parents[4]
PROPERTY_MODEL = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserProperty.swift'


def controller_fixture_source() -> str:
    """Compile the real request/cache/version owner; replace UI and builder leaves."""
    source = CONTROLLER_PATH.read_text()
    for signature in ['    func makeSection(', '    private func requestDiagnostics(']:
        start = source.index(signature)
        body = function_body(source, signature)
        opening = source.index('{', start)
        source = source[:start] + source[opening + len(body):]
    start = source.index('    private func statusText(')
    version = source.index('/// Conservative version')
    source = source[:start] + '}\n\n' + source[version:]
    models = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperLaunchModels.swift'
    reachability = models.read_text().split('nonisolated struct SceneWallpaperLaunchState:', 1)[0]
    return reachability + source.replace('private ', '')


PROBE = r'''
import AppKit
import Foundation
import Darwin

extension Notification.Name {
    static let sceneWallpaperLaunchStateDidChange = Self("fixture-launch")
    static let sceneDaemonActiveSessionFactsDidChange = Self("fixture-active-facts")
}
struct SceneDaemonActiveSessionFactsChange { let recordIDs: Set<String> }
@MainActor final class SceneDaemonClient {
    static let shared = SceneDaemonClient()
    struct ActiveCallbackPropertyFacts: Equatable {
        let transportGeneration: UInt64; let requestID: UUID; let recordID: String?
        let reachability: ScenePreparedCallbackPropertyReachability
    }
    var activeCallbackPropertyFacts: ActiveCallbackPropertyFacts?
}
struct SceneWallpaperLaunchState { let recordID: String }
struct SteamWorkshopDownloadRecord {
    enum ContentType { case scene, web }
    enum Status { case ready, removed }
    var id: String; var folderURL: URL; var updatedAt = Date(timeIntervalSince1970: 0)
    var title = "fixture"; var status = Status.ready; var contentType = ContentType.scene
}
struct SceneDiagnosticsReport {}
struct SceneDiagnosticsBuilder {
    func build(rootURL: URL, propertyOverrides: [String: SceneUserPropertyValue]) -> SceneDiagnosticsReport { .init() }
}
struct SceneResourceView {
    struct Root { let url: URL }
    let roots: [Root]
    static func defaultStockAssetsRootURL() -> URL? { BuilderSpy.shared.stockRoot }
}
struct SceneProject { let packageURL: URL? }
struct ScenePkgExtractionReport { let blockingMessage: String? }
struct SceneRuntimeSourceFacts {
    let project: SceneProject?; let sceneDocument: Bool?; let assetCatalog: Bool?
    let resourceReferences: Bool?; let renderDescriptor: Bool?
    let sceneDocumentLoadErrorDescription: String?; let packageReport: ScenePkgExtractionReport?
    let resourceView: SceneResourceView; let key: String
}
final class BuilderSpy: @unchecked Sendable {
    static let shared = BuilderSpy()
    let lock = NSLock()
    var calls = 0
    var beforeRead: (() -> Void)?
    var afterRead: (() -> Void)?
    var afterBoundary: (() -> Void)?
    var stockRoot: URL?
    var additionalRoots: [URL] = []
    var packageFailure = false
    var documentFailure = false
    func increment() { lock.lock(); calls += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}
final class FixtureBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func finish() { lock.lock(); finished = true; lock.unlock() }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
}
struct SceneRuntimeSourceFactsBuilder {
    func build(rootURL: URL, propertyOverrides: [String: SceneUserPropertyValue] = [:],
               willReadResourceRoots: (([URL]) -> Void)? = nil) -> SceneRuntimeSourceFacts {
        let spy = BuilderSpy.shared
        spy.increment(); spy.beforeRead?()
        let key = (try? String(contentsOf: rootURL.appendingPathComponent("definition"), encoding: .utf8)) ?? "none"
        spy.afterRead?()
        willReadResourceRoots?([rootURL] + spy.additionalRoots); spy.afterBoundary?()
        return .init(project: .init(packageURL: spy.packageFailure ? rootURL.appendingPathComponent("broken.pkg") : nil),
            sceneDocument: spy.documentFailure ? nil : true, assetCatalog: true, resourceReferences: true,
            renderDescriptor: true, sceneDocumentLoadErrorDescription: spy.documentFailure ? "broken" : nil,
            packageReport: spy.packageFailure ? .init(blockingMessage: "failed") : nil,
            resourceView: .init(roots: ([rootURL] + spy.additionalRoots).map { .init(url: $0) }), key: key)
    }
}
struct SteamWorkshopScenePropertyContext {
    let catalog: SceneUserPropertyCatalog
    let actionableKeys: Set<String>
    let effectiveValues: [String: SceneUserPropertyValue]
    var staticActionableKeys: Set<String> { actionableKeys.subtracting(["callback"]) }
    var sourceIdentity: ScenePreparedCallbackPropertyReachability.Source? { nil }
}
@MainActor final class SteamWorkshopService {
    static let shared = SteamWorkshopService()
    var records: [String: SteamWorkshopDownloadRecord] = [:]
    var overrides: [String: [String: SceneUserPropertyValue]] = [:]
    func latestDownloadRecord(for id: String) -> SteamWorkshopDownloadRecord? { records[id] }
    func scenePropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SceneUserPropertyValue] { overrides[record.id] ?? [:] }
    func scenePropertyContext(for record: SteamWorkshopDownloadRecord, sourceFacts: SceneRuntimeSourceFacts) -> SteamWorkshopScenePropertyContext? {
        guard sourceFacts.key != "none" else { return nil }
        let definition = SceneUserPropertyDefinition(key: sourceFacts.key, title: sourceFacts.key, kind: .bool,
            runtimeType: "bool", order: 0, index: nil, minimumValue: nil, maximumValue: nil, stepValue: nil,
            allowsFractionalValues: false, fractionalPrecision: nil, displayCondition: nil, defaultValue: .bool(false), options: [])
        let catalog = SceneUserPropertyCatalog(definitions: [definition])
        return projectedScenePropertyContext(.init(catalog: catalog, actionableKeys: [definition.key],
                     effectiveValues: catalog.effectiveValues(overrides: scenePropertyOverrides(for: record))), for: record)
    }
    func projectedScenePropertyContext(_ context: SteamWorkshopScenePropertyContext,
        for record: SteamWorkshopDownloadRecord) -> SteamWorkshopScenePropertyContext? {
        let keys = SceneDaemonClient.shared.activeCallbackPropertyFacts?.reachability.propertyKeys ?? []
        return .init(catalog: context.catalog, actionableKeys: context.staticActionableKeys.union(keys),
            effectiveValues: context.catalog.effectiveValues(overrides: scenePropertyOverrides(for: record)))
    }
}
@MainActor final class SteamWorkshopPropertyPanelController {
    static let shared = SteamWorkshopPropertyPanelController()
    let window = NSObject()
    var presentationID: UUID?
    var loadingShows = 0
    @discardableResult func show(title: String, subtitle: String, content: Any, retaining: AnyObject? = nil) -> UUID {
        loadingShows += 1
        let id = UUID(); presentationID = id; return id
    }
}
@MainActor final class ScenePropertyWindowController {
    static let shared = ScenePropertyWindowController()
    var contexts: [SteamWorkshopScenePropertyContext] = []
    func show(record: SteamWorkshopDownloadRecord, context: SteamWorkshopScenePropertyContext) {
        contexts.append(context)
        SteamWorkshopPropertyPanelController.shared.presentationID = UUID()
    }
}
@main enum Probe {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let manager = FileManager.default
        let input = root.appendingPathComponent("definition")
        func write(_ text: String) throws { try Data(text.utf8).write(to: input) }
        try write("enabled")
        let service = SteamWorkshopService.shared, spy = BuilderSpy.shared
        let panel = SteamWorkshopPropertyPanelController.shared, output = ScenePropertyWindowController.shared
        var record = SteamWorkshopDownloadRecord(id: "own", folderURL: root)
        service.records[record.id] = record
        let owner = SteamWorkshopSceneInspectionController(onStateChange: {}, ownsPropertyPreparation: true)
        var results: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError("FAIL: " + label) }; results.append(label)
        }
        func drain(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            precondition(condition(), "completion timeout")
        }
        func open() { owner.preparePropertyEditor(for: record); drain { owner.request == nil } }
        func reset() { owner.reset(); spy.beforeRead = nil; spy.afterRead = nil; spy.afterBoundary = nil }
        open(); let first = spy.count
        open(); check(spy.count == first, "unchanged namespace reuses projected context")
        service.overrides[record.id] = ["enabled": .bool(true)]
        open(); check(spy.count == first + 1 && output.contexts.last?.effectiveValues["enabled"] == .bool(true), "full override identity refreshes values")
        let old = ScenePropertySourceVersion.capture(roots: [root])!
        let date = try input.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try write("renamed"); try manager.setAttributes([.modificationDate: date], ofItemAtPath: input.path)
        check(ScenePropertySourceVersion.capture(roots: [root]) != old, "same size restored mtime rejected by ctime")
        open(); check(output.contexts.last?.actionableKeys == ["renamed"], "changed definition reaches projection")
        let stable = ScenePropertySourceVersion.capture(roots: [root])!
        let addition = root.appendingPathComponent("resource-renamed")
        try Data([1]).write(to: addition)
        check(ScenePropertySourceVersion.capture(roots: [root]) != stable, "namespace addition invalidates")
        try manager.removeItem(at: addition)
        let link = root.appendingPathComponent("alias")
        try manager.createSymbolicLink(at: link, withDestinationURL: input)
        check(ScenePropertySourceVersion.capture(roots: [root]) == nil, "symlink disables reuse")
        try manager.removeItem(at: link)
        let renamed = root.appendingPathComponent("other-name")
        try manager.moveItem(at: input, to: renamed)
        check(ScenePropertySourceVersion.capture(roots: [root]) != stable, "resource rename invalidates")
        try manager.moveItem(at: renamed, to: input)
        let permission = ScenePropertySourceVersion.capture(roots: [root])!
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        check(ScenePropertySourceVersion.capture(roots: [root]) != permission, "permission change invalidates")
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: input.path)
        check(ScenePropertySourceVersion.capture(roots: [root.appendingPathComponent("missing")]) == nil, "missing namespace disables reuse")
        let parentA = root.deletingLastPathComponent().appendingPathComponent("A")
        let parentB = root.deletingLastPathComponent().appendingPathComponent("B")
        for parent in [parentA, parentB] {
            try manager.createDirectory(at: parent.appendingPathComponent("child"), withIntermediateDirectories: true)
            try Data([7]).write(to: parent.appendingPathComponent("child/resource"))
        }
        let ancestor = root.deletingLastPathComponent().appendingPathComponent("ancestor")
        try manager.createSymbolicLink(at: ancestor, withDestinationURL: parentA)
        let aliasedRoot = ancestor.appendingPathComponent("child")
        let originalAlias = ScenePropertySourceVersion.capture(roots: [aliasedRoot])!
        try manager.removeItem(at: ancestor)
        try manager.createSymbolicLink(at: ancestor, withDestinationURL: parentB)
        check(ScenePropertySourceVersion.capture(roots: [aliasedRoot]) != originalAlias, "retargeted ancestor alias invalidates")
        try Data("variantA".utf8).write(to: parentA.appendingPathComponent("child/definition"))
        try Data("variantB".utf8).write(to: parentB.appendingPathComponent("child/definition"))
        func retarget(_ parent: URL) {
            try! manager.removeItem(at: ancestor)
            try! manager.createSymbolicLink(at: ancestor, withDestinationURL: parent)
        }
        retarget(parentA); owner.reset()
        let previousRecord = record
        record.folderURL = aliasedRoot; service.records[record.id] = record
        spy.beforeRead = { retarget(parentB) }; spy.afterRead = { retarget(parentA) }
        open()
        check(output.contexts.last?.actionableKeys == ["variantA"], "alias ABA cannot stamp facts from another namespace")
        spy.beforeRead = nil; spy.afterRead = nil; retarget(parentB); open()
        check(output.contexts.last?.actionableKeys == ["variantB"], "alias retarget refreshes actual property definitions")
        record = previousRecord; service.records[record.id] = record
        reset()
        let packageRoot = root.deletingLastPathComponent().appendingPathComponent("package")
        let stockRoot = root.deletingLastPathComponent().appendingPathComponent("stock")
        for extra in [packageRoot, stockRoot] { try manager.createDirectory(at: extra, withIntermediateDirectories: true) }
        let marker = packageRoot.appendingPathComponent(".completion")
        try Data([1]).write(to: marker)
        spy.additionalRoots = [packageRoot, stockRoot]; spy.stockRoot = stockRoot
        open(); let multiRoot = spy.count
        try Data([2]).write(to: marker); open()
        check(spy.count == multiRoot + 1, "hidden package marker mutation invalidates")
        try Data([3]).write(to: stockRoot.appendingPathComponent("added.json")); open()
        check(spy.count == multiRoot + 2, "stock namespace addition invalidates")
        spy.additionalRoots = []; spy.stockRoot = nil
        let wide = root.deletingLastPathComponent().appendingPathComponent("wide")
        try manager.createDirectory(at: wide, withIntermediateDirectories: true)
        for index in 0..<10000 { try Data([0]).write(to: wide.appendingPathComponent(String(repeating: "x", count: 150) + String(index))) }
        check(ScenePropertySourceVersion.capture(roots: [wide]) == nil, "wide namespace cannot admit partial over-budget version")



        reset(); spy.afterRead = { try! Data("changed".utf8).write(to: input) }
        open(); check(owner.snapshot == nil, "project read before boundary cannot acquire new version")
        reset(); spy.afterBoundary = { try! Data("afterXX".utf8).write(to: input) }
        open(); check(owner.snapshot == nil, "resource change during preparation not cached")
        reset(); spy.packageFailure = true; open(); let failed = spy.count; open()
        check(owner.snapshot == nil && spy.count == failed + 1, "failed package validation never cached")
        spy.packageFailure = false; spy.documentFailure = true; reset(); open()
        check(owner.snapshot == nil, "document failure never cached")
        spy.documentFailure = false; reset(); try write("none"); open(); let unavailable = spy.count; open()
        check(owner.snapshot == nil && spy.count == unavailable + 1, "no controls result never cached")
        try write("enabled"); reset(); open(); owner.discardSnapshot(); let pressure = spy.count; open()
        check(spy.count == pressure + 1, "pressure clears warm reuse")
        func blocked(_ action: () -> Void) {
            reset(); let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            spy.beforeRead = { entered.signal(); release.wait() }
            owner.preparePropertyEditor(for: record)
            precondition(entered.wait(timeout: .now() + 2) == .success)
            action(); spy.beforeRead = nil; release.signal()
            let barrier = FixtureBarrier()
            owner.queue.async { DispatchQueue.main.async { barrier.finish() } }
            drain { owner.request == nil && barrier.isFinished }
        }
        let closed = output.contexts.count
        blocked { NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel.window) }
        check(output.contexts.count == closed && owner.snapshot == nil, "close rejects late delivery and admission")
        let replaced = output.contexts.count
        blocked { panel.presentationID = UUID(); service.overrides[record.id] = ["enabled": .bool(false)] }
        check(output.contexts.count == replaced && owner.snapshot == nil, "replacement rejects retry and admission")
        blocked { owner.discardSnapshot() }
        check(owner.snapshot == nil && output.contexts.count == replaced + 1, "pressure in flight permits current delivery without backfill")
        blocked { service.overrides[record.id] = ["enabled": .bool(true)] }
        check(output.contexts.last?.effectiveValues["enabled"] == .bool(true), "override change in flight restarts current identity")
        blocked { record.updatedAt = Date(timeIntervalSince1970: 1); service.records[record.id] = record }
        check(owner.snapshot?.identity.updatedAt == record.updatedAt, "reimport uses latest record identity")
        let removed = output.contexts.count
        blocked { service.records.removeValue(forKey: record.id) }
        check(output.contexts.count == removed && owner.snapshot == nil, "deleted record cannot deliver or cache")
        service.records[record.id] = record
        reset(); try write("enabled"); open()
        let beforeProjection = spy.count
        let callbackFacts = SceneDaemonClient.ActiveCallbackPropertyFacts(transportGeneration: 1,
            requestID: UUID(), recordID: record.id, reachability: .init(source: .init(rootPath: root.path,
                projectWitness: "project", sceneWitness: "scene"), scriptGeneration: 1, propertyKeys: ["callback"]))
        func publishFacts(_ facts: SceneDaemonClient.ActiveCallbackPropertyFacts?, recordID: String? = nil) {
            SceneDaemonClient.shared.activeCallbackPropertyFacts = facts
            NotificationCenter.default.post(name: .sceneDaemonActiveSessionFactsDidChange,
                object: SceneDaemonActiveSessionFactsChange(recordIDs: [recordID ?? record.id]))
        }
        publishFacts(callbackFacts); drain { owner.request == nil }
        check(output.contexts.last?.actionableKeys.contains("callback") == true && spy.count == beforeProjection,
            "active callback facts reproject open catalog without builder")
        check(owner.propertyPanelToken == panel.presentationID, "replacement tracks actual presentation token")
        publishFacts(nil); drain { owner.request == nil }
        check(output.contexts.last?.actionableKeys.contains("callback") == false && spy.count == beforeProjection,
            "silent active retirement retracts callback rows without rebuilding facts")
        let unrelated = output.contexts.count
        publishFacts(callbackFacts, recordID: "other")
        check(output.contexts.count == unrelated && owner.request == nil, "other record cannot replace open panel")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel.window)
        let closedProjection = output.contexts.count
        publishFacts(nil)
        check(output.contexts.count == closedProjection && owner.request == nil, "closed panel ignores late active facts")
        blocked { publishFacts(callbackFacts) }
        check(output.contexts.last?.actionableKeys.contains("callback") == true,
            "callback launch during inspection delivers only latest projection")
        SceneDaemonClient.shared.activeCallbackPropertyFacts = nil
        reset(); try write("enabled"); open()
        let retained = owner.snapshot!
        let huge = SteamWorkshopScenePropertyContext(catalog: retained.contentContext!.catalog, actionableKeys: ["enabled"],
            effectiveValues: ["enabled": .string(String(repeating: "x", count: 1100000))])
        check(SteamWorkshopSceneInspectionController.retentionCost(context: huge,
            version: ScenePropertySourceVersion.capture(roots: [root])!, identity: retained.identity) > 4 * 1024 * 1024,
            "conservative admission accounts for large values")
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
extension SteamWorkshopSceneInspectionController.Snapshot {
    var contentContext: SteamWorkshopScenePropertyContext? {
        if case let .preparedProperties(context, _) = content { return context }; return nil
    }
}
'''


@unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
class ScenePropertyPreparationReuseTests(unittest.TestCase):
    def test_source_versions_delivery_and_failure_boundaries(self) -> None:
        with tempfile.TemporaryDirectory(prefix='mwx-property-reuse-') as temporary:
            work = Path(temporary)
            (work / 'input').mkdir()
            source = work / 'Controller.swift'
            source.write_text(controller_fixture_source())
            probe = work / 'Probe.swift'
            probe.write_text(PROBE)
            binary = work / 'probe'
            build = subprocess.run(['swiftc', '-O', str(PROPERTY_MODEL), str(source), str(probe),
                '-module-cache-path', str(work / 'cache'), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary), str((work / 'input').resolve())], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            cases = json.loads(run.stdout)
            self.assertEqual(len(cases), 34)


if __name__ == '__main__':
    unittest.main()
