import AppKit
import Darwin
import Foundation

/// Owns the detail-only, user-triggered Scene inspection lifecycle.
/// Product playback and Scene runtime state remain outside this controller.
@MainActor
final class SteamWorkshopSceneInspectionController {
    private static let propertyPreparation = SteamWorkshopSceneInspectionController(
        onStateChange: {}, ownsPropertyPreparation: true
    )

    private enum Purpose: Equatable {
#if DEBUG
        case diagnostics
#endif
        case properties
    }

    private struct Identity: Equatable {
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

    private struct Snapshot {
        let identity: Identity
        let content: InspectionResult

#if DEBUG
        var diagnosticsReport: SceneDiagnosticsReport? {
            guard case let .diagnostics(report) = content else { return nil }
            return report
        }
#endif
    }

    private enum InspectionResult {
#if DEBUG
        case diagnostics(SceneDiagnosticsReport)
#endif
        case properties(SceneRuntimeSourceFacts, ScenePropertySourceVersion?)
        case preparedProperties(SteamWorkshopScenePropertyContext, ScenePropertySourceVersion)
    }

    private struct Request {
        let id: UUID
        let identity: Identity
        let purpose: Purpose
        let workItem: DispatchWorkItem
        let cacheEpoch: UInt64
    }

    private let service = SteamWorkshopService.shared
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-detail-inspection",
        qos: .userInitiated
    )
    private let onStateChange: @MainActor () -> Void
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
#if DEBUG
    private var diagnosticsExpanded = false
    private var diagnosticsRequested = false
#endif

    init(
        onStateChange: @escaping @MainActor () -> Void,
        ownsPropertyPreparation: Bool = false
    ) {
        self.onStateChange = onStateChange
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
                self.onStateChange()
            }
        }
        if ownsPropertyPreparation {
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
    }

    deinit {
        MainActor.assumeIsolated {
            request?.workItem.cancel()
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
        request?.workItem.cancel()
        request = nil
        discardSnapshot()
        presentedIdentity = nil
        propertyMessage = nil
#if DEBUG
        diagnosticsExpanded = false
        diagnosticsRequested = false
#endif
    }

#if DEBUG
    func makeSection(for record: SteamWorkshopDownloadRecord) -> NSView {
        let identity = inspectionIdentity(for: record)
        presentedIdentity = identity
        let currentSnapshot = snapshot.flatMap { $0.identity == identity ? $0 : nil }
        let currentDiagnosticsReport = currentSnapshot?.diagnosticsReport
        let launchState = SceneDaemonClient.shared.launchState.flatMap {
            $0.recordID == record.id ? $0 : nil
        }

        let root = verticalStack(spacing: 10)
        root.addArrangedSubview(divider())

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = verticalStack(spacing: 4)
        titleStack.addArrangedSubview(sectionTitle("Scene"))
        titleStack.addArrangedSubview(label(
            statusText(
                identity: identity,
                hasCurrentDiagnostics: currentDiagnosticsReport != nil
            ),
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            lines: 0
        ))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer())

        if let launchState, launchState.isInProgress {
            let cancelButton = ActionButton(title: "取消设置") {
                PlaybackCommandMultiplexer.shared.dispatch(
                    .cancelSceneLaunch(recordID: record.id),
                    to: .scene
                )
            }
            configureSmallButton(cancelButton)
            header.addArrangedSubview(cancelButton)
        }

        let propertiesButton = ActionButton(title: "属性调节") { [weak self] in
            self?.requestPropertyEditor(for: record)
        }
        configureSmallButton(propertiesButton)
        propertiesButton.isEnabled = request == nil || request?.identity == identity
        header.addArrangedSubview(propertiesButton)

        let diagnosticsButton = ActionButton(
            title: diagnosticsButtonTitle(
                identity: identity,
                hasCurrentDiagnostics: currentDiagnosticsReport != nil
            )
        ) { [weak self] in
            self?.requestDiagnostics(for: record)
        }
        configureSmallButton(diagnosticsButton)
        diagnosticsButton.isEnabled = request == nil
        header.addArrangedSubview(diagnosticsButton)

        let toggleButton = ActionButton(
            title: diagnosticsExpanded ? "收起" : "展开"
        ) { [weak self] in
            guard let self else { return }
            diagnosticsExpanded.toggle()
            onStateChange()
        }
        configureSmallButton(toggleButton)
        header.addArrangedSubview(toggleButton)
        root.addArrangedSubview(header)

        if let launchState, launchState.isInProgress {
            root.addArrangedSubview(progressRow(text: launchState.message))
            root.addArrangedSubview(notice(
                icon: "rectangle.stack.badge.play",
                text: "当前壁纸会继续播放；候选 Scene 尚未提交。"
            ))
        } else if let launchState, launchState.phase == .failed {
            root.addArrangedSubview(notice(
                icon: "exclamationmark.triangle.fill",
                text: "Scene 壁纸准备失败。当前壁纸未被切换，可重试或主动查看诊断。"
            ))
        }

        if let request, request.identity == identity {
            root.addArrangedSubview(progressRow(for: request.purpose))
        }
        if let propertyMessage {
            root.addArrangedSubview(notice(
                icon: "slider.horizontal.3",
                text: propertyMessage
            ))
        }
        if diagnosticsExpanded {
            appendExpandedContent(
                to: root,
                currentReport: currentDiagnosticsReport
            )
        }
        return root
    }
#endif

#if DEBUG
    private func requestDiagnostics(for record: SteamWorkshopDownloadRecord) {
        diagnosticsRequested = true
        diagnosticsExpanded = true
        propertyMessage = nil
        startInspection(for: record, purpose: .diagnostics)
    }
#endif

    func requestPropertyEditor(for record: SteamWorkshopDownloadRecord) {
        // Property preparation belongs to the independent window, not to the
        // detail view whose selection and lifetime can change while loading.
        guard let current = service.latestDownloadRecord(for: record.id),
              current.status == .ready, current.contentType == .scene else { return }
        Self.propertyPreparation.preparePropertyEditor(for: current)
    }

    private func preparePropertyEditor(for record: SteamWorkshopDownloadRecord) {
        propertyPanelToken = SteamWorkshopPropertyPanelController.shared.showMessage(title: "Scene 属性调节", subtitle: record.title,
            message: "正在准备 Scene 属性…", retaining: self)
        let identity = inspectionIdentity(for: record)
        presentedIdentity = identity
        propertyMessage = nil
        if request?.identity == identity {
            onStateChange()
            return
        }
        startInspection(for: record, purpose: .properties)
    }

    private func startInspection(
        for record: SteamWorkshopDownloadRecord,
        purpose: Purpose
    ) {
        let identity = inspectionIdentity(for: record)
        request?.workItem.cancel()
        let requestID = UUID()
        let rootURL = identity.folderURL
        let propertyOverrides = identity.propertyOverrides
        let reusable = snapshot.flatMap { $0.identity.hasSameAuthoredInput(as: identity) ? $0 : nil }
        let workItem = DispatchWorkItem { [weak self] in
            let result: InspectionResult
            switch purpose {
#if DEBUG
            case .diagnostics:
                result = .diagnostics(SceneDiagnosticsBuilder().build(
                    rootURL: rootURL,
                    propertyOverrides: propertyOverrides
                ))
#endif
            case .properties:
                if let reusable,
                   case let .preparedProperties(context, version) = reusable.content,
                   version.stockRootURL == SceneResourceView.defaultStockAssetsRootURL(),
                   ScenePropertySourceVersion.capture(roots: version.rootURLs) == version {
                    result = .preparedProperties(context, version)
                } else {
                    result = Self.buildPropertyInspection(
                        rootURL: rootURL, propertyOverrides: propertyOverrides
                    )
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishInspection(
                    requestID: requestID,
                    identity: identity,
                    record: record,
                    result: result
                )
            }
        }
        request = Request(
            id: requestID,
            identity: identity,
            purpose: purpose,
            workItem: workItem,
            cacheEpoch: cacheEpoch
        )
        queue.async(execute: workItem)
        onStateChange()
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
            onStateChange()
            return
        }

        var currentRecord = record
        if request.purpose == .properties {
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
                startInspection(for: current, purpose: .properties)
                return
            }
        }
        switch result {
#if DEBUG
        case let .diagnostics(report):
            snapshot = Snapshot(identity: identity, content: .diagnostics(report))
#endif
        case let .properties(facts, version):
            if let context = service.scenePropertyContext(for: currentRecord, sourceFacts: facts) {
                if let version, requestEpoch == cacheEpoch,
                   Self.retentionCost(context: context, version: version, identity: identity) <= 4 * 1024 * 1024 {
                    snapshot = Snapshot(identity: identity, content: .preparedProperties(context, version))
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
            if requestEpoch == cacheEpoch,
               Self.retentionCost(context: retained, version: version, identity: identity) <= 4 * 1024 * 1024 {
                snapshot = Snapshot(identity: identity, content: .preparedProperties(retained, version))
            } else { snapshot = nil }
            if let projected {
                presentPropertyEditor(record: currentRecord, context: projected)
            } else {
                presentPropertyUnavailable(record: currentRecord)
            }
        }
        onStateChange()
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
        startInspection(for: current, purpose: .properties)
    }

    private func cancelPropertyPresentation() {
        request?.workItem.cancel()
        request = nil
        propertyPanelToken = nil
        presentedIdentity = nil
    }

    private func discardSnapshot() {
        snapshot = nil
        cacheEpoch &+= 1
    }

    private static func buildPropertyInspection(
        rootURL: URL,
        propertyOverrides: [String: SceneUserPropertyValue]
    ) -> InspectionResult {
        // Project loading, the loose index and package validation precede the
        // resource-root callback, so cover their input before starting them.
        let original = ScenePropertySourceVersion.capture(roots: [rootURL])
        // Pin the complete read chain to the namespace observed initially.
        // An ancestor alias moving A→B→A cannot make facts from B acquire A's
        // version. Keep the authored root in subsequent versions for hit checks.
        let preparedRoot = original?.resolvedRootURLs.first ?? rootURL.resolvingSymlinksInPath()
        var before: ScenePropertySourceVersion?
        let facts = SceneRuntimeSourceFactsBuilder().build(
            rootURL: preparedRoot,
            propertyOverrides: propertyOverrides,
            willReadResourceRoots: {
                before = ScenePropertySourceVersion.capture(roots: [rootURL] + $0)
            }
        )
        let after = ScenePropertySourceVersion.capture(roots: [rootURL] + facts.resourceView.roots.map(\.url))
        let successful = facts.project != nil && facts.sceneDocument != nil
            && facts.assetCatalog != nil
            && facts.renderDescriptor != nil && facts.sceneDocumentLoadErrorDescription == nil
            && (facts.project?.packageURL == nil
                || (facts.packageReport != nil && facts.packageReport?.blockingMessage == nil))
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

#if DEBUG
    private func statusText(
        identity: Identity,
        hasCurrentDiagnostics: Bool
    ) -> String {
        if let request, request.identity == identity {
            return request.purpose == .diagnostics
                ? "正在后台生成诊断；详情面板仍可继续使用"
                : "正在后台准备属性；不会阻塞详情面板"
        }
        if diagnosticsRequested, hasCurrentDiagnostics {
            return diagnosticsExpanded
                ? "已展开当前 Scene 的诊断结果"
                : "诊断已完成，按需展开查看"
        }
        if diagnosticsRequested, snapshot?.diagnosticsReport != nil {
            return "Scene 内容或属性已变化，上次诊断结果已过期"
        }
        return "诊断默认关闭，只有主动点击后才开始"
    }
#endif

#if DEBUG
    private func diagnosticsButtonTitle(
        identity: Identity,
        hasCurrentDiagnostics: Bool
    ) -> String {
        if let request, request.identity == identity {
            return request.purpose == .diagnostics ? "诊断中…" : "准备中…"
        }
        return hasCurrentDiagnostics && diagnosticsRequested
            ? "重新诊断" : "开始诊断"
    }
#endif

#if DEBUG
    private func appendExpandedContent(
        to stack: NSStackView,
        currentReport: SceneDiagnosticsReport?
    ) {
        if diagnosticsRequested, let currentReport {
            appendReport(currentReport, to: stack)
        } else if diagnosticsRequested,
                  snapshot?.diagnosticsReport != nil,
                  currentReport == nil {
            stack.addArrangedSubview(notice(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                text: "Scene 内容或属性已经变化，上次诊断结果已过期。"
                    + "点击“重新诊断”生成当前结果。"
            ))
        } else if request == nil {
            stack.addArrangedSubview(notice(
                icon: "stethoscope",
                text: "诊断默认关闭。展开不会扫描文件；"
                    + "只有点击“开始诊断”才会读取并分析 Scene 内容。"
            ))
        }
    }
#endif

#if DEBUG
    private func appendReport(
        _ report: SceneDiagnosticsReport,
        to stack: NSStackView
    ) {
        stack.addArrangedSubview(sectionTitle("Scene 诊断"))
        diagnosticRows(report).forEach { row in
            stack.addArrangedSubview(notice(
                icon: "square.stack.3d.up",
                text: "\(row.label)：\(row.value)"
            ))
        }
        report.issues.forEach { issue in
            stack.addArrangedSubview(notice(
                icon: issue.severity == .blocking
                    ? "exclamationmark.triangle.fill"
                    : "info.circle",
                text: issue.message
            ))
        }
    }
#endif

#if DEBUG
    private func diagnosticRows(
        _ report: SceneDiagnosticsReport
    ) -> [(label: String, value: String)] {
        let capability = report.capabilityProfile
        let descriptor = report.renderDescriptor
        return [
            ("入口", report.project?.entryPath ?? "未解析"),
            ("资源数", "\(report.resourceIndex?.resources.count ?? 0)"),
            ("对象数", "\(report.sceneDocument?.objectCount ?? 0)"),
            ("effect", "\(report.sceneDocument?.effectCount ?? 0)"),
            ("模型", "\(report.assetCatalog?.models.count ?? 0)"),
            ("材质", "\(report.assetCatalog?.materials.count ?? 0)"),
            ("材质 pass", "\(report.assetCatalog?.materialPassCount ?? 0)"),
            ("shader 引用", "\(report.assetCatalog?.shaderReferences.count ?? 0)"),
            ("资源引用", "\(report.sceneDocument?.referencedResourcePaths.count ?? 0)"),
            ("引用命中", "\(report.resourceReferences?.resolvedCount ?? 0)"),
            ("内置引用", "\(report.resourceReferences?.builtInReferenceCount ?? 0)"),
            ("引用缺失", "\(report.resourceReferences?.missingReferences.count ?? 0)"),
            (
                report.project?.packageURL?.lastPathComponent ?? "Scene 资源包",
                report.project?.packageURL == nil ? "缺失" : "已找到"
            ),
            ("PKGV 索引", "\(report.packageReport?.packageIndex?.entries.count ?? 0)"),
            ("缓存解包", "\(report.packageReport?.discoveredPaths.count ?? 0)"),
            ("shader blob", "\(report.resourceIndex?.count(kind: .shaderBlob) ?? 0)"),
            ("脚本", capability?.hasScripts == true ? "有" : "无"),
            ("粒子", capability?.hasParticles == true ? "有" : "无"),
            ("音频处理", capability?.supportsAudioProcessing == true ? "声明支持" : "未声明"),
            ("阻塞能力", capability?.firstStageRendererGaps.joined(separator: "、") ?? "未解析"),
            ("render layer", "\(descriptor?.layers.count ?? 0)"),
            ("root layer", "\(descriptor?.rootLayerIDs.count ?? 0)"),
            ("render order", descriptor?.renderOrderPolicy ?? "未解析"),
            ("render pass", "\(descriptor?.materialPasses.count ?? 0)"),
            (
                "effect pass",
                "\(report.sceneDocument?.objects.flatMap { $0.effects }.reduce(0) { $0 + $1.passes.count } ?? 0)"
            ),
            (
                "内联脚本",
                "\(report.sceneDocument?.objects.filter(\.hasInlineScript).count ?? 0)"
            ),
        ]
    }
#endif

#if DEBUG
    private func progressRow(for purpose: Purpose) -> NSView {
        progressRow(text: purpose == .diagnostics
            ? "正在后台生成 Scene 诊断…"
            : "正在后台准备 Scene 属性…")
    }
#endif

    private func progressRow(text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        row.addArrangedSubview(progress)
        row.addArrangedSubview(label(
            text,
            font: .systemFont(ofSize: 12, weight: .medium),
            color: .secondaryLabelColor,
            lines: 0
        ))
        return row
    }

    private func configureSmallButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    private func verticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        label(
            text,
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .secondaryLabelColor,
            lines: 1
        )
    }

    private func label(
        _ text: String,
        font: NSFont,
        color: NSColor,
        lines: Int
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.maximumNumberOfLines = lines
        label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func divider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func notice(icon: String, text: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) ?? NSImage()
        let imageView = NSImageView(image: image)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: .semibold
        )
        imageView.contentTintColor = .secondaryLabelColor
        row.addArrangedSubview(imageView)
        row.addArrangedSubview(label(
            text,
            font: .systemFont(ofSize: 12, weight: .semibold),
            color: .secondaryLabelColor,
            lines: 0
        ))
        return row
    }

    private final class ActionButton: NSButton {
        private let actionHandler: () -> Void

        init(title: String, actionHandler: @escaping () -> Void) {
            self.actionHandler = actionHandler
            super.init(frame: .zero)
            self.title = title
            target = self
            action = #selector(runAction)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        @objc private func runAction() {
            actionHandler()
        }
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

    static func capture(roots: [URL]) -> Self? {
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
