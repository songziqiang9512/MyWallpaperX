import AppKit
import Foundation

/// Owns the detail-only, user-triggered Scene inspection lifecycle.
/// Product playback and Scene runtime state remain outside this controller.
@MainActor
final class SteamWorkshopSceneInspectionController {
    private enum Purpose: Equatable {
        case diagnostics
        case properties
    }

    private struct Identity: Equatable {
        let recordID: String
        let folderURL: URL
        let updatedAt: Date
        let propertyOverrides: [String: SceneUserPropertyValue]
    }

    private struct Snapshot {
        let identity: Identity
        let report: SceneDiagnosticsReport
    }

    private struct Request {
        let id: UUID
        let identity: Identity
        let purpose: Purpose
        let workItem: DispatchWorkItem
    }

    private let service = SteamWorkshopService.shared
    private let queue = DispatchQueue(
        label: "com.mywallpaperx.scene-detail-inspection",
        qos: .userInitiated
    )
    private let onStateChange: @MainActor () -> Void
    private var launchObserver: NSObjectProtocol?
    private var presentedIdentity: Identity?
    private var request: Request?
    private var snapshot: Snapshot?
    private var propertyMessage: String?
    private var diagnosticsExpanded = false
    private var diagnosticsRequested = false
    private var shouldOpenPropertiesAfterPreparation = false

    init(onStateChange: @escaping @MainActor () -> Void) {
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
                self.onStateChange()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            request?.workItem.cancel()
            if let launchObserver {
                NotificationCenter.default.removeObserver(launchObserver)
            }
        }
    }

    func reset() {
        request?.workItem.cancel()
        request = nil
        snapshot = nil
        presentedIdentity = nil
        propertyMessage = nil
        diagnosticsExpanded = false
        diagnosticsRequested = false
        shouldOpenPropertiesAfterPreparation = false
    }

    func makeSection(for record: SteamWorkshopDownloadRecord) -> NSView {
        let identity = inspectionIdentity(for: record)
        presentedIdentity = identity
        let currentSnapshot = snapshot.flatMap { $0.identity == identity ? $0 : nil }
        let launchState = SceneDesktopWallpaperHost.shared.launchState.flatMap {
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
            statusText(identity: identity, hasCurrentSnapshot: currentSnapshot != nil),
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            lines: 0
        ))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer())

        if let launchState, launchState.isInProgress {
            let cancelButton = ActionButton(title: "取消设置") {
                SceneDesktopWallpaperHost.shared.cancelPendingLaunch(recordID: record.id)
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
                hasCurrentSnapshot: currentSnapshot != nil
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
                currentSnapshot: currentSnapshot
            )
        }
        return root
    }

    private func requestDiagnostics(for record: SteamWorkshopDownloadRecord) {
        diagnosticsRequested = true
        diagnosticsExpanded = true
        propertyMessage = nil
        shouldOpenPropertiesAfterPreparation = false
        startInspection(for: record, purpose: .diagnostics)
    }

    private func requestPropertyEditor(for record: SteamWorkshopDownloadRecord) {
        let identity = inspectionIdentity(for: record)
        propertyMessage = nil
        if let snapshot, snapshot.identity == identity {
            presentPropertyEditor(record: record, report: snapshot.report)
            return
        }
        shouldOpenPropertiesAfterPreparation = true
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
        let workItem = DispatchWorkItem { [weak self] in
            let report = SceneDiagnosticsBuilder().build(
                rootURL: rootURL,
                propertyOverrides: propertyOverrides
            )
            DispatchQueue.main.async { [weak self] in
                self?.finishInspection(
                    requestID: requestID,
                    identity: identity,
                    record: record,
                    report: report
                )
            }
        }
        request = Request(
            id: requestID,
            identity: identity,
            purpose: purpose,
            workItem: workItem
        )
        queue.async(execute: workItem)
        onStateChange()
    }

    private func finishInspection(
        requestID: UUID,
        identity: Identity,
        record: SteamWorkshopDownloadRecord,
        report: SceneDiagnosticsReport
    ) {
        guard request?.id == requestID else { return }
        request = nil
        guard presentedIdentity == identity else {
            shouldOpenPropertiesAfterPreparation = false
            onStateChange()
            return
        }

        snapshot = Snapshot(identity: identity, report: report)
        if shouldOpenPropertiesAfterPreparation {
            shouldOpenPropertiesAfterPreparation = false
            presentPropertyEditor(record: record, report: report)
        }
        onStateChange()
    }

    private func presentPropertyEditor(
        record: SteamWorkshopDownloadRecord,
        report: SceneDiagnosticsReport
    ) {
        guard let context = service.scenePropertyContext(for: record, report: report) else {
            propertyMessage = "当前 Scene 没有可调节的受支持属性，或属性模型尚未解析成功。"
            onStateChange()
            return
        }
        ScenePropertyWindowController.shared.show(record: record, context: context)
    }

    private func inspectionIdentity(for record: SteamWorkshopDownloadRecord) -> Identity {
        Identity(
            recordID: record.id,
            folderURL: record.folderURL.standardizedFileURL,
            updatedAt: record.updatedAt,
            propertyOverrides: service.scenePropertyOverrides(for: record)
        )
    }

    private func statusText(identity: Identity, hasCurrentSnapshot: Bool) -> String {
        if let request, request.identity == identity {
            return request.purpose == .diagnostics
                ? "正在后台生成诊断；详情面板仍可继续使用"
                : "正在后台准备属性；不会阻塞详情面板"
        }
        if diagnosticsRequested, hasCurrentSnapshot {
            return diagnosticsExpanded
                ? "已展开当前 Scene 的诊断结果"
                : "诊断已完成，按需展开查看"
        }
        if diagnosticsRequested, snapshot != nil {
            return "Scene 内容或属性已变化，上次诊断结果已过期"
        }
        return hasCurrentSnapshot
            ? "诊断默认关闭；已有可复用的 Scene 解析结果"
            : "诊断默认关闭，只有主动点击后才开始"
    }

    private func diagnosticsButtonTitle(
        identity: Identity,
        hasCurrentSnapshot: Bool
    ) -> String {
        if let request, request.identity == identity {
            return request.purpose == .diagnostics ? "诊断中…" : "准备中…"
        }
        return hasCurrentSnapshot && diagnosticsRequested ? "重新诊断" : "开始诊断"
    }

    private func appendExpandedContent(
        to stack: NSStackView,
        currentSnapshot: Snapshot?
    ) {
        if diagnosticsRequested, let currentSnapshot {
            appendReport(currentSnapshot.report, to: stack)
        } else if diagnosticsRequested, snapshot != nil, currentSnapshot == nil {
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

    private func diagnosticRows(
        _ report: SceneDiagnosticsReport
    ) -> [(label: String, value: String)] {
        let capability = report.capabilityProfile
        let descriptor = report.renderDescriptor
        return [
            ("入口", report.project?.entryPath ?? "未解析"),
            ("资源数", "\(report.resourceIndex.resources.count)"),
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
            ("shader blob", "\(report.resourceIndex.count(kind: .shaderBlob))"),
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

    private func progressRow(for purpose: Purpose) -> NSView {
        progressRow(text: purpose == .diagnostics
            ? "正在后台生成 Scene 诊断…"
            : "正在后台准备 Scene 属性…")
    }

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
