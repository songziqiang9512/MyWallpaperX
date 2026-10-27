import AppKit
import Darwin
import Foundation

/// Owns user-triggered Scene property preparation for the independent window.
/// Product playback and Scene runtime state remain outside this controller.
@MainActor
final class SteamWorkshopSceneInspectionController {
    private static let propertyPreparation = SteamWorkshopSceneInspectionController()

    private nonisolated struct Identity: Equatable {
        let recordID: String
        let folderURL: URL
        let updatedAt: Date
        let propertyOverrides: [String: SceneUserPropertyValue]
        let callbackPropertyVersion: SceneDaemonClient.ActiveCallbackPropertyFacts?
        let displayLanguageVersion: [String]

        func hasSameAuthoredInput(as other: Identity) -> Bool {
            recordID == other.recordID && folderURL == other.folderURL
                && updatedAt == other.updatedAt && propertyOverrides == other.propertyOverrides
        }
    }

    private nonisolated struct Snapshot {
        let identity: Identity
        let source: ScenePlaybackSource
        let content: InspectionResult
    }

    private nonisolated enum InspectionResult {
        case properties(SceneRuntimeSourceFacts, ScenePropertySourceVersion?)
        case sourceFailure(Error)
        case preparedProperties(SteamWorkshopScenePropertyContext, ScenePropertySourceVersion)
    }

    private final class Request {
        let id = UUID()
        let identity: Identity
        var admission: SteamWorkshopService.SceneSourceAdmission?
        let cancellation = SceneWallpaperLaunchCancellation()
        let cacheEpoch: UInt64
        var task: Task<Void, Never>?

        init(identity: Identity, cacheEpoch: UInt64) {
            self.identity = identity
            self.cacheEpoch = cacheEpoch
        }

        func cancel() {
            cancellation.cancel()
            task?.cancel()
        }
    }

    private let service = SteamWorkshopService.shared
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-detail-inspection",
        qos: .userInitiated
    )
    private var launchObserver: NSObjectProtocol?
    private var activeSessionObserver: NSObjectProtocol?
    private var localeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var cacheEpoch: UInt64 = 0
    private var presentedIdentity: Identity?
    private var request: Request?
    private var snapshot: Snapshot?
    private var propertyMessage: String?
    private var propertyPanelToken: UUID?

    private init() {
        launchObserver = NotificationCenter.default.addObserver(
            forName: .sceneWallpaperLaunchStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let state = notification.object as? SceneWallpaperLaunchState,
                      state.recordID == self.presentedIdentity?.recordID else {
                    return
                }
                self.refreshPropertyProjection()
            }
        }

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPropertyProjection() }
        }
        activeSessionObserver = NotificationCenter.default.addObserver(
            forName: .sceneDaemonActiveSessionFactsDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let recordID = self.presentedIdentity?.recordID,
                      let change = notification.object as? SceneDaemonActiveSessionFactsChange,
                      change.recordIDs.contains(recordID) else { return }
                self.refreshPropertyProjection()
            }
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: SteamWorkshopPropertyPanelController.shared.window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPropertyPresentation() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main
        )
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.discardSnapshot() }
        }
        pressure.resume()
        memoryPressure = pressure
    }

    deinit {
        MainActor.assumeIsolated {
            request?.cancel()
            if let launchObserver {
                NotificationCenter.default.removeObserver(launchObserver)
            }
            for observer in [activeSessionObserver, localeObserver, closeObserver, terminationObserver].compactMap({ $0 }) {
                NotificationCenter.default.removeObserver(observer)
            }
            memoryPressure?.cancel()
        }
    }

    func reset() {
        request?.cancel()
        request = nil
        discardSnapshot()
        presentedIdentity = nil
        propertyMessage = nil
    }

    static func requestPropertyEditor(for record: SteamWorkshopDownloadRecord) {
        // Property preparation belongs to the independent window, not to the
        // detail view whose selection and lifetime can change while loading.
        guard let current = SteamWorkshopService.shared.latestDownloadRecord(for: record.id),
              current.status == .ready, current.contentType == .scene else { return }
        propertyPreparation.preparePropertyEditor(for: current)
    }

    private func preparePropertyEditor(for record: SteamWorkshopDownloadRecord) {
        propertyPanelToken = SteamWorkshopPropertyPanelController.shared.showMessage(title: "Scene 属性调节", subtitle: record.title,
            message: "正在准备 Scene 属性…", retaining: self)
        let identity = inspectionIdentity(for: record)
        presentedIdentity = identity
        propertyMessage = nil
        if request?.identity == identity {
            return
        }
        startInspection(for: record)
    }

    private func startInspection(for record: SteamWorkshopDownloadRecord) {
        let identity = inspectionIdentity(for: record)
        request?.cancel()
        let pending = Request(identity: identity, cacheEpoch: cacheEpoch)
        request = pending
        let requestID = pending.id
        let propertyOverrides = identity.propertyOverrides
        let queue = self.queue
        let cancellation = pending.cancellation
        pending.task = Task { @MainActor [weak self] in
            defer { pending.admission = nil; pending.task = nil }
            guard let self else { return }
            do {
                pending.admission = try self.service.sceneSourceAdmission(for: record)
                try Task.checkCancellation()
                try cancellation.check()
            } catch {
                self.finishInspection(requestID: requestID, identity: identity, record: record,
                    result: .sourceFailure(error))
                return
            }
            let source = pending.admission!.source
            // Managed source facts still never reuse the directory memo.
            let reusable = source.managed == nil ? self.snapshot.flatMap {
                $0.source == source && $0.identity.hasSameAuthoredInput(as: identity) ? $0 : nil
            } : nil
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    // Do not cancel a DispatchWorkItem: its closure must run even
                    // when cancelled before dequeue, to resume and join this task.
                    queue.async {
                        var result: InspectionResult
                        do {
                            try cancellation.check()
                            if let reusable,
                               case let .preparedProperties(context, version) = reusable.content,
                               version.stockRootURL == SceneResourceView.defaultStockAssetsRootURL(),
                               ScenePropertySourceVersion.capture(roots: version.rootURLs,
                                    checkCancellation: { try cancellation.check() }) == version {
                                result = .preparedProperties(context, version)
                            } else {
                                result = try SteamWorkshopSceneInspectionController.buildPropertyInspection(source: source,
                                    propertyOverrides: propertyOverrides,
                                    checkCancellation: { try cancellation.check() })
                            }
                            try cancellation.check()
                        } catch { result = .sourceFailure(error) }
                        DispatchQueue.main.async {
                            self.finishInspection(requestID: requestID, identity: identity,
                                record: record, result: result)
                            continuation.resume()
                        }
                    }
                }
            } onCancel: { cancellation.cancel() }
            // The MainActor-only admission (and opaque lease) remains live until
            // the actual queued read and its delivery have both completed.
            withExtendedLifetime(pending.admission) {}
        }
    }

    private func finishInspection(
        requestID: UUID,
        identity: Identity,
        record: SteamWorkshopDownloadRecord,
        result: InspectionResult
    ) {
        guard let request, request.id == requestID else { return }
        let requestEpoch = request.cacheEpoch
        self.request = nil
        guard presentedIdentity == identity else {
            return
        }

        var currentRecord = record
        guard let propertyPanelToken,
              SteamWorkshopPropertyPanelController.shared.presentationID == propertyPanelToken else {
            cancelPropertyPresentation()
            return
        }
        guard let current = service.latestDownloadRecord(for: record.id),
              current.status == .ready, current.contentType == .scene else {
            discardSnapshot()
            presentPropertyUnavailable(record: record)
            cancelPropertyPresentation()
            return
        }
        currentRecord = current
        let currentIdentity = inspectionIdentity(for: current)
        if currentIdentity != identity {
            presentedIdentity = currentIdentity
            startInspection(for: current)
            return
        }

        switch result {
        case let .sourceFailure(error):
            snapshot = nil
            NSLog("MWX Scene property source failed: %@", String(describing: error))
            presentPropertyUnavailable(record: currentRecord)
        case let .properties(facts, version):
            if let context = service.scenePropertyContext(for: currentRecord, sourceFacts: facts) {
                if let source = request.admission?.source, let version, requestEpoch == cacheEpoch,
                   Self.retentionCost(context: context, version: version, identity: identity) <= 4 * 1024 * 1024 {
                    snapshot = Snapshot(identity: identity, source: source, content: .preparedProperties(context, version))
                } else {
                    snapshot = nil
                }
                presentPropertyEditor(record: currentRecord, context: context)
            } else {
                snapshot = nil
                presentPropertyUnavailable(record: currentRecord)
            }
        case let .preparedProperties(context, version):
            let projected = service.projectedScenePropertyContext(context, for: currentRecord)
            let retained = projected ?? context
            if let source = request.admission?.source, requestEpoch == cacheEpoch,
               Self.retentionCost(context: retained, version: version, identity: identity) <= 4 * 1024 * 1024 {
                snapshot = Snapshot(identity: identity, source: source, content: .preparedProperties(retained, version))
            } else { snapshot = nil }
            if let projected {
                presentPropertyEditor(record: currentRecord, context: projected)
            } else {
                presentPropertyUnavailable(record: currentRecord)
            }
        }
    }

    private func presentPropertyEditor(
        record: SteamWorkshopDownloadRecord,
        context: SteamWorkshopScenePropertyContext
    ) {
        guard let propertyPanelToken,
              SteamWorkshopPropertyPanelController.shared.presentationID == propertyPanelToken else { return }
        ScenePropertyWindowController.shared.show(record: record, context: context)
        self.propertyPanelToken = SteamWorkshopPropertyPanelController.shared.presentationID
    }

    private func presentPropertyUnavailable(record: SteamWorkshopDownloadRecord) {
        guard let propertyPanelToken,
              SteamWorkshopPropertyPanelController.shared.presentationID == propertyPanelToken else { return }
        propertyMessage = "当前 Scene 没有可调节的受支持属性，\n或属性模型尚未解析成功。"
        self.propertyPanelToken = SteamWorkshopPropertyPanelController.shared.showMessage(title: "Scene 属性调节", subtitle: record.title,
            message: propertyMessage!, retaining: self)
    }

    private func refreshPropertyProjection() {
        guard let propertyPanelToken, let presentedIdentity else { return }
        guard SteamWorkshopPropertyPanelController.shared.presentationID == propertyPanelToken else {
            cancelPropertyPresentation()
            return
        }
        guard let current = service.latestDownloadRecord(for: presentedIdentity.recordID),
              current.status == .ready, current.contentType == .scene else { return }
        let identity = inspectionIdentity(for: current)
        guard identity != presentedIdentity else { return }
        self.presentedIdentity = identity
        startInspection(for: current)
    }

    private func cancelPropertyPresentation() {
        request?.cancel()
        request = nil
        propertyPanelToken = nil
        presentedIdentity = nil
    }

    private func discardSnapshot() {
        snapshot = nil
        cacheEpoch &+= 1
    }

    private nonisolated static func buildPropertyInspection(
        source: ScenePlaybackSource,
        propertyOverrides: [String: SceneUserPropertyValue],
        checkCancellation: @escaping () throws -> Void
    ) throws -> InspectionResult {
        try checkCancellation()
        let rootURL = source.rootURL
        // Managed facts use the selected storage identity and shared source
        // lifetime. A physical directory stamp does not describe package data.
        let original = source.managed == nil
            ? ScenePropertySourceVersion.capture(roots: [rootURL], checkCancellation: checkCancellation) : nil
        let preparedRoot = original?.resolvedRootURLs.first ?? rootURL
        var before: ScenePropertySourceVersion?
        let builderSource = source.managed == nil ? ScenePlaybackSource(rootURL: preparedRoot) : source
        let facts = try SceneRuntimeSourceFactsBuilder().build(
            rootURL: preparedRoot, source: builderSource,
            propertyOverrides: propertyOverrides,
            checkCancellation: checkCancellation,
            willReadResourceRoots: { roots in
                if source.managed == nil {
                    before = ScenePropertySourceVersion.capture(roots: [rootURL] + roots,
                        checkCancellation: checkCancellation)
                }
            }
        )
        try checkCancellation()
        // Package backing has no directory URL. Do not invent one or memoize
        // package currentness with FTS. Keep the original pure-context boundary.
        guard source.managed == nil, facts.project?.packageURL == nil else {
            return .properties(facts, nil)
        }
        let after = ScenePropertySourceVersion.capture(roots: [rootURL] + facts.resourceView.roots.compactMap(\.directoryURL),
            checkCancellation: checkCancellation)
        let successful = facts.project != nil && facts.sceneDocument != nil
            && facts.assetCatalog != nil && facts.renderDescriptor != nil
            && facts.sceneDocumentLoadErrorDescription == nil
        let stable = original != nil && before?.entries(in: preparedRoot) == original?.entries
            && before?.resolvedRootURLs.first == preparedRoot && after?.resolvedRootURLs.first == preparedRoot
            && before != nil && before == after
        return .properties(facts, successful && stable ? after : nil)
    }

    private static func retentionCost(
        context: SteamWorkshopScenePropertyContext,
        version: ScenePropertySourceVersion,
        identity: Identity
    ) -> Int {
        // Admission estimate, not a physical-footprint measurement. Include
        // complete catalog/overrides, projected controls, token programs and stamps.
        var cost = version.estimatedCost + 4096
        // Strings reserve UTF-16 storage plus growth/copies. Only authored
        // conditions need the additional per-byte token/container allowance.
        func text(_ value: String?) { cost += (value?.utf8.count ?? 0) * 4 + 128 }
        func condition(_ value: String?) {
            text(value)
            cost += (value?.utf8.count ?? 0) * 64
        }
        func value(_ value: SceneUserPropertyValue?) {
            if case let .string(string) = value { text(string) } else { cost += 128 }
        }
        text(identity.recordID); text(identity.folderURL.path)
        cost += context.propertyDisplayLocalization.estimatedCost
        for language in identity.displayLanguageVersion { text(language) }
        if let source = context.sourceIdentity {
            text(source.rootPath); text(source.projectWitness); text(source.sceneWitness)
        }
        for key in context.staticActionableKeys { text(key) }
        for key in identity.callbackPropertyVersion?.reachability.propertyKeys ?? [] { text(key) }
        for definition in context.catalog.definitions {
            cost += 2048
            text(definition.key); text(definition.title); text(definition.runtimeType)
            condition(definition.displayCondition); value(definition.defaultValue)
            for option in definition.options {
                cost += 512
                text(option.label); condition(option.displayCondition); value(option.value)
            }
        }
        for values in [identity.propertyOverrides, context.effectiveValues] {
            for (key, entry) in values { text(key); value(entry) }
        }
        for key in context.actionableKeys { text(key) }
        return cost
    }

    private func inspectionIdentity(for record: SteamWorkshopDownloadRecord) -> Identity {
        Identity(
            recordID: record.id,
            folderURL: record.folderURL.standardizedFileURL,
            updatedAt: record.updatedAt,
            propertyOverrides: service.scenePropertyOverrides(for: record),
            callbackPropertyVersion: SceneDaemonClient.shared.activeCallbackPropertyFacts.flatMap {
                $0.recordID == record.id ? $0 : nil
            },
            displayLanguageVersion: WorkshopPropertyDisplayResolver.languageVersion
        )
    }
}

/// Conservative version of all namespaces consumed by one property inspection.
/// Metadata uncertainty only disables reuse; the normal builder still decides
/// whether authored content is supported and performs package integrity checks.
private nonisolated struct ScenePropertySourceVersion: Equatable {
    struct Entry: Equatable {
        let rootPath: String
        let relativePath: String
        let device: Int32
        let inode: UInt64
        let mode: UInt16
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
    }

    let rootURLs: [URL]
    let resolvedRootURLs: [URL]
    let stockRootURL: URL?
    let entries: [Entry]

    var estimatedCost: Int {
        1024 + rootURLs.reduce(0) { $0 + $1.path.utf8.count * 2 + 128 }
            + resolvedRootURLs.reduce(0) { $0 + $1.path.utf8.count * 2 + 128 }
            + entries.reduce(0) { $0 + $1.relativePath.utf8.count * 2 + 288 }
    }

    func entries(in rootURL: URL) -> [Entry] {
        let path = rootURL.resolvingSymlinksInPath().path
        return entries.filter { $0.rootPath == path }
    }

    static func capture(roots: [URL], checkCancellation: (() throws -> Void)? = nil) -> Self? {
        var seenRoots: Set<String> = [], seenResolvedRoots: Set<String> = []
        let roots = roots.map(\.standardizedFileURL).filter { seenRoots.insert($0.path).inserted }
        guard !roots.isEmpty else { return nil }
        var entries: [Entry] = []
        var resolvedRoots: [URL] = []
        var cost = 1024
        func append(_ path: UnsafePointer<CChar>, rootPath: String, relativePath: String, info: stat) -> Bool {
            guard (info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR),
                  access(path, info.st_mode & S_IFMT == S_IFDIR ? R_OK | X_OK : R_OK) == 0 else {
                return false
            }
            cost += relativePath.utf8.count * 2 + 288
            guard cost <= 4 * 1024 * 1024 else { return false }
            entries.append(Entry(rootPath: rootPath, relativePath: relativePath,
                device: info.st_dev, inode: info.st_ino,
                mode: info.st_mode, size: info.st_size,
                modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                changedSeconds: info.st_ctimespec.tv_sec, changedNanoseconds: info.st_ctimespec.tv_nsec))
            return true
        }
        for root in roots {
            if (try? checkCancellation?()) == nil && checkCancellation != nil { return nil }
            var info = stat()
            guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
            // Resolve ancestor aliases once. Retain the original roots so a
            // retargeted alias is re-resolved on every hit. FTS supplies each
            // entry's stat without URL normalization or a second metadata read.
            let resolvedRoot = root.resolvingSymlinksInPath()
            resolvedRoots.append(resolvedRoot)
            let rootPath = resolvedRoot.path
            guard seenResolvedRoots.insert(rootPath).inserted else { continue }
            guard let path = strdup(resolvedRoot.path) else { return nil }
            defer { free(path) }
            let prefixLength = strlen(path)
            var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
            guard let tree = paths.withUnsafeMutableBufferPointer({
                fts_open($0.baseAddress!, FTS_PHYSICAL | FTS_NOCHDIR, nil)
            }) else { return nil }
            defer { fts_close(tree) }
            while true {
                if (try? checkCancellation?()) == nil && checkCancellation != nil { return nil }
                errno = 0
                guard let node = fts_read(tree) else {
                    guard errno == 0 else { return nil }
                    break
                }
                switch Int32(node.pointee.fts_info) {
                case FTS_DP:
                    continue
                case FTS_D, FTS_F:
                    guard let metadata = node.pointee.fts_statp else { return nil }
                    let length = Int(node.pointee.fts_pathlen)
                    guard length >= prefixLength else { return nil }
                    let relative = length == prefixLength ? "" : String(
                        validatingCString: node.pointee.fts_path.advanced(by: prefixLength + 1)
                    )
                    guard let relative,
                          append(node.pointee.fts_path, rootPath: rootPath,
                                 relativePath: relative, info: metadata.pointee) else { return nil }
                default:
                    // Includes unreadable directories, stat/I/O errors, cycles,
                    // symlinks and special files; never cache a partial walk.
                    return nil
                }
            }
        }
        return Self(rootURLs: roots,
            resolvedRootURLs: resolvedRoots,
            stockRootURL: SceneResourceView.defaultStockAssetsRootURL(),
            entries: entries.sorted {
                $0.rootPath == $1.rootPath ? $0.relativePath < $1.relativePath : $0.rootPath < $1.rootPath
            })
    }
}
