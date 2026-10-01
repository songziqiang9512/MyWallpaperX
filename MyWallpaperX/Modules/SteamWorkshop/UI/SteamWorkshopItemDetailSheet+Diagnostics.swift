//
//  SteamWorkshopItemDetailSheet+Diagnostics.swift
//  MyWallpaperX
//

import AppKit

/// 播放诊断面板与属性入口：Scene/Web 诊断区块、诊断面板的打开与刷新、
/// 属性编辑器路由。从主面板文件拆出（主文件长期贴行数额度）。
extension AppKitSteamWorkshopItemDetailView {
    func buildWebDiagnosticsSection(in destination: NSStackView) {
        guard let webDownloadRecord else { return }

        let stack = verticalStack(spacing: 10)
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = verticalStack(spacing: 4)
        titleStack.addArrangedSubview(sectionTitle("WEB 诊断"))
        titleStack.addArrangedSubview(label(
            webDiagnosticsExpanded ? "已展开详细诊断与兼容提示" : "默认不立即执行重扫描，按需展开以避免打开详情时卡顿",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor,
            lines: 0
        ))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(spacer())

        let toggle = NSButton(title: webDiagnosticsExpanded ? "收起" : "展开", target: self, action: #selector(toggleWebDiagnostics))
        toggle.bezelStyle = .rounded
        toggle.controlSize = .small
        header.addArrangedSubview(toggle)
        stack.addArrangedSubview(header)

        if webDiagnosticsExpanded,
           let report = service.webValidationReport(for: webDownloadRecord) {
            buildWebDiagnosticsReport(report, record: webDownloadRecord, descriptor: webProjectDescriptor, in: stack)
        }

        destination.addArrangedSubview(stack)
    }

    private func buildWebDiagnosticsReport(
        _ report: SteamWorkshopWebValidationReport,
        record: SteamWorkshopDownloadRecord?,
        descriptor: ResolvedWebProjectDescriptor?,
        in stack: NSStackView
    ) {
        let resolvedEntryPath = descriptor?.resolvedEntryRelativePath ?? report.entryRelativePath
        let entrySummary = resolvedEntryPath.isEmpty ? "未解析到入口" : resolvedEntryPath
        let runtimeEvents = WebRuntimeDiagnosticsStore.shared.recentEvents(recordID: record?.id, limit: 12)

        stack.addArrangedSubview(sectionTitle("WEB 诊断"))
        stack.addArrangedSubview(notice(
            icon: "square.stack.3d.up",
            text: "属性来源：\(descriptor?.propertySource.displayName ?? report.propertySource.displayName)"
                + ((descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) > 0
                   ? "  ·  壳 preset 覆盖 \(descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) 条"
                   : "")
        ))
        stack.addArrangedSubview(notice(
            icon: "doc.text.magnifyingglass",
            text: "样本结构：\(descriptor?.sampleStructure.displayName ?? report.sampleStructure.displayName)  ·  入口：\(entrySummary)  ·  扫描文件：\(report.scannedFileCount)"
        ))

        if report.issues.isEmpty {
            stack.addArrangedSubview(validationPill(severity: .info, levelTitle: SteamWorkshopWebValidationLevel.info.displayName, message: "未发现明显的本地资源缺失或外部依赖风险"))
        } else {
            report.issues.forEach {
                stack.addArrangedSubview(validationPill(severity: $0.severity, levelTitle: $0.level.displayName, message: $0.message))
            }
        }

        if let record, case let .missing(itemID) = record.dependencyStatus {
            stack.addArrangedSubview(validationPill(
                severity: .warning,
                levelTitle: SteamWorkshopWebValidationLevel.preconditionUnmet.displayName,
                message: record.isDependencyBackedWeb
                    ? "当前样本属于依赖型 WEB 预设壳，需先下载依赖宿主 \(itemID) 才能运行"
                    : "当前项目声明依赖包 \(itemID)，但本地未找到该依赖的可启动 WEB 入口"
            ))
        }

        if !runtimeEvents.isEmpty {
            stack.addArrangedSubview(sectionTitle("最近运行事件"))
            runtimeEvents.forEach {
                stack.addArrangedSubview(validationPill(severity: $0.validationSeverity, levelTitle: $0.type, message: $0.displayMessage))
            }
        }
    }

    func buildSceneDiagnosticsSection(in destination: NSStackView) {
        guard let record = sceneDownloadRecord else { return }
        destination.addArrangedSubview(
            sceneInspectionController.makeSection(for: record)
        )
    }

    func openDiagnostics() {
        guard let record = latestDownloadRecord, record.contentType == .scene || record.contentType == .web else { return }
        let stack = verticalStack(spacing: 12)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        diagnosticsPanelStack = stack
        diagnosticsPanelToken = SteamWorkshopPropertyPanelController.shared.show(title: "播放诊断", subtitle: record.title, content: scroll)
        refreshDiagnosticsPanel()
    }

    func refreshDiagnosticsPanel() {
        guard let token = diagnosticsPanelToken,
              SteamWorkshopPropertyPanelController.shared.presentationID == token,
              let stack = diagnosticsPanelStack, let record = latestDownloadRecord else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if record.contentType == .scene {
            buildSceneDiagnosticsSection(in: stack)
        } else if record.contentType == .web {
            buildWebDiagnosticsSection(in: stack)
        }
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    @objc func openProperties() {
        guard let record = latestDownloadRecord, record.status == .ready else { return }
        switch record.contentType {
        case .unknown: return
        case .scene:
            sceneInspectionController.requestPropertyEditor(for: record)
        case .web:
            SteamWorkshopPropertyPanelController.shared.show(title: "Web 属性调节", subtitle: record.title,
                content: SteamWorkshopWebPropertyEditorView(record: record))
        case .video:
            let text = label("视频壁纸没有作者可调属性。音量、播放速度及播放方式使用应用的播放设置。", font: .systemFont(ofSize: 13), color: .secondaryLabelColor, lines: 0)
            SteamWorkshopPropertyPanelController.shared.show(title: "Video 属性", subtitle: record.title, content: text)
        }
    }

    @objc func toggleWebDiagnostics() {
        webDiagnosticsExpanded.toggle()
        refreshDiagnosticsPanel()
    }
}

private extension WebRuntimeDiagnosticEvent {
    var validationSeverity: SteamWorkshopWebValidationSeverity {
        switch severity {
        case .error:
            return .error
        case .warning:
            return .warning
        case .info:
            return .info
        }
    }

    var displayMessage: String {
        let urlText = url.map { "  ·  \($0)" } ?? ""
        return "\(message)\(urlText)"
    }
}
