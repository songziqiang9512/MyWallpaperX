import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func webValidationReport(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebValidationReport? {
        let signature = webValidationSignature(for: record)
        if let cached = webValidationReportCache[record.id], cached.signature == signature {
            return cached.report
        }
        guard record.contentType == .web else {
            return nil
        }

        let descriptor = resolvedWebProjectDescriptor(for: record)
        let sampleStructure = descriptor?.sampleStructure ?? webSampleStructure(for: record)
        let sourceRecord = webPropertyDefinitionSourceRecord(for: record)
        let propertyDefinitions = descriptor?.propertyDefinitions ?? webPropertyDefinitions(for: record)
        let propertySource = descriptor?.propertySource ?? {
            if let sourceRecord, sourceRecord.id != record.id {
                return SteamWorkshopWebPropertySource.dependencyHost(itemID: sourceRecord.id)
            }
            return .ownProject
        }()
        let presetOverrideCount = descriptor?.presetOverrideMap.count ?? webPresetValues(for: record).count
        let staticContentSummary = descriptor?.staticContentSummary

        if case let .missing(itemID) = record.dependencyStatus,
           record.isDependencyBackedWeb,
           record.hasPlayableDependencyWebHost == false {
            let issue = SteamWorkshopWebValidationIssue(
                severity: .warning,
                level: .preconditionUnmet,
                message: "当前样本属于依赖型 WEB 预设壳，需先下载依赖宿主 \(itemID) 后才能运行"
            )
            return SteamWorkshopWebValidationReport(
                sampleStructure: sampleStructure,
                entryRelativePath: "",
                scannedFileCount: 0,
                issueCount: 1,
                issues: [issue],
                propertySource: propertySource,
                presetOverrideCount: presetOverrideCount
            )
        }

        guard let entryURL = descriptor?.resolvedEntryURL ?? record.webEntryURL else {
            return SteamWorkshopWebValidationReport(
                sampleStructure: sampleStructure,
                entryRelativePath: "",
                scannedFileCount: 0,
                issueCount: 1,
                issues: [.init(severity: .error, level: .fatal, message: "没有找到可播放的 HTML 入口文件")],
                propertySource: propertySource,
                presetOverrideCount: presetOverrideCount
            )
        }

        let resolvedEntryURL = entryURL.resolvingSymlinksInPath().standardizedFileURL
        let rootURL = descriptor?.effectiveRootURL ?? effectiveWebRootURL(for: record, entryURL: resolvedEntryURL)
        let entryRelativePath = descriptor?.resolvedEntryRelativePath ?? webRelativePath(for: resolvedEntryURL, under: rootURL)
        var issues: [SteamWorkshopWebValidationIssue] = []
        var emittedIssueKeys = Set<String>()
        var scannedFiles = Set<URL>()
        var pendingFiles = [resolvedEntryURL]
        var externalDependencyURLs = Set<String>()
        var usesGeneralProperties = staticContentSummary?.usesApplyGeneralProperties ?? false
        var usesGeneralFPS = staticContentSummary?.usesGeneralFPS ?? false
        var usesServiceWorkerRegistration = staticContentSummary?.usesServiceWorkerRegistration ?? false
        var usesESModuleDependency = staticContentSummary?.usesESModuleDependency ?? false
        var usesDynamicImport = staticContentSummary?.usesDynamicImport ?? false
        var usesWASMResource = staticContentSummary?.usesWASMResource ?? false
        var usesWASMStreaming = staticContentSummary?.usesWASMStreaming ?? false
        var usesCustomSchemeSensitiveWebGL = staticContentSummary?.usesCustomSchemeSensitiveWebGL ?? false
        var usesIframeCrossFrameAccess = staticContentSummary?.usesIframeCrossFrameAccess ?? false
        var truncatedScanFileCount = 0
        let needsServiceWorkerFallbackScan = staticContentSummary == nil

        func appendIssue(_ severity: SteamWorkshopWebValidationSeverity, _ level: SteamWorkshopWebValidationLevel, _ message: String) {
            let issue = SteamWorkshopWebValidationIssue(severity: severity, level: level, message: message)
            let key = "\(issue.level.rawValue)|\(issue.severity.rawValue)|\(issue.message)"
            guard emittedIssueKeys.insert(key).inserted else { return }
            issues.append(issue)
        }

        if record.isDependencyBackedWeb,
           let dependencyItemID = record.dependencyItemID {
            switch record.dependencyStatus {
            case .available:
                appendIssue(.info, .info, "当前样本属于依赖型 WEB 预设壳，已接入依赖宿主 \(dependencyItemID)")
            case .missing:
                appendIssue(.warning, .preconditionUnmet, "当前样本属于依赖型 WEB 预设壳，但依赖宿主 \(dependencyItemID) 尚不可用")
            case .none:
                break
            }
        }

        if record.isDependencyBackedWeb,
           let shellEntryURL = record.webOwnEntryURL,
           let shellRootURL = record.folderURL.resolvingSymlinksInPath().standardizedFileURL as URL? {
            let shellEntryRelativePath = webRelativePath(for: shellEntryURL, under: shellRootURL)
            appendIssue(.info, .info, "当前样本作为补丁壳运行：壳入口 \(shellEntryRelativePath)；实际宿主入口 \(entryRelativePath)")
        } else if record.isDependencyBackedWeb,
                  let dependencyItemID = record.dependencyItemID {
            appendIssue(.info, .info, "当前样本没有独立 HTML 壳入口，当前播放入口完全来自依赖宿主 \(dependencyItemID)")
        }

        if let sourceRecord, sourceRecord.id != record.id {
            appendIssue(.info, .info, "当前属性定义来源于依赖宿主 \(sourceRecord.id)，预设覆盖项 \(presetOverrideCount) 个")
        } else if presetOverrideCount > 0 {
            appendIssue(.info, .info, "当前样本包含 \(presetOverrideCount) 个预设覆盖项")
        }

        if let normalizedDeclaredEntry = declaredWebEntryRelativePath(for: record) {
            let declaredEntryURL = record.folderURL.appendingPathComponent(normalizedDeclaredEntry).resolvingSymlinksInPath().standardizedFileURL
            if !FileManager.default.fileExists(atPath: declaredEntryURL.path) {
                let issueLevel: SteamWorkshopWebValidationLevel = record.isDependencyBackedWeb ? .info : .fatal
                let issueSeverity: SteamWorkshopWebValidationSeverity = record.isDependencyBackedWeb ? .info : .error
                let message = record.isDependencyBackedWeb
                    ? "补丁壳自身声明入口不存在：\(normalizedDeclaredEntry)（已回退到依赖宿主入口）"
                    : "project.json 声明的入口文件不存在：\(normalizedDeclaredEntry)"
                appendIssue(issueSeverity, issueLevel, message)
            } else {
                let declaredRelativePath = webRelativePath(for: declaredEntryURL, under: rootURL)
                if declaredRelativePath != entryRelativePath {
                    appendIssue(.info, .info, "当前入口回退为：\(entryRelativePath)（project.json 声明：\(normalizedDeclaredEntry)）")
                }
            }
        }

        if !FileManager.default.fileExists(atPath: resolvedEntryURL.path) {
            appendIssue(.error, .fatal, "入口文件不存在：\(entryRelativePath)")
        }

        let maxScanFiles = 200
        while let fileURL = pendingFiles.first, scannedFiles.count < maxScanFiles {
            pendingFiles.removeFirst()
            guard scannedFiles.insert(fileURL).inserted else { continue }
            guard let scan = Self.webStaticAnalysisContent(from: fileURL) else {
                appendIssue(.warning, .warning, "无法读取文件：\(webRelativePath(for: fileURL, under: rootURL))")
                continue
            }
            let content = scan.content
            if scan.isTruncated {
                truncatedScanFileCount += 1
            }

            // WebM / 悬停 / 插件桥 / 持久化存储四类信号只驱动 summary 侧旗标：
            // 校验报告不再本地重扫一份（见下方 scannedRiskFlags 装配）。
            if Self.webContentUsesApplyGeneralProperties(content) {
                usesGeneralProperties = true
            }
            if Self.webContentUsesGeneralFPS(content) {
                usesGeneralFPS = true
            }
            if !usesServiceWorkerRegistration,
               Self.webContentUsesServiceWorkerRegistration(content)
                || (scan.isTruncated
                    && needsServiceWorkerFallbackScan
                    && Self.webFileContainsServiceWorkerRegistration(fileURL)) {
                usesServiceWorkerRegistration = true
            }
            if Self.webContentUsesESModuleDependency(content) {
                usesESModuleDependency = true
            }
            if Self.webContentUsesDynamicImport(content) {
                usesDynamicImport = true
            }
            if Self.webContentUsesWASMResource(content) {
                usesWASMResource = true
            }
            if Self.webContentUsesWASMStreaming(content) {
                usesWASMStreaming = true
            }
            if Self.webContentUsesCustomSchemeSensitiveWebGL(content) {
                usesCustomSchemeSensitiveWebGL = true
            }
            if Self.webContentUsesIframeCrossFrameAccess(content) {
                usesIframeCrossFrameAccess = true
            }

            for reference in Self.extractLocalWebResourceReferences(from: content, fileExtension: fileURL.pathExtension) {
                switch reference {
                case let .local(path):
                    guard let resolvedURL = Self.resolveWebResourceURL(path, relativeTo: fileURL, rootURL: rootURL) else {
                        appendIssue(.warning, .warning, "发现越界或无法解析的资源路径：\(path)")
                        continue
                    }
                    let exists = FileManager.default.fileExists(atPath: resolvedURL.path)
                    if exists == false {
                        let missingPath = webRelativePath(for: resolvedURL, under: rootURL)
                        let missingLevel = webValidationLevelForMissingResource(
                            relativePath: missingPath,
                            sampleStructure: sampleStructure,
                            referencingFileExtension: fileURL.pathExtension,
                            record: record
                        )
                        let missingMessage = webValidationMessageForMissingResource(
                            relativePath: missingPath,
                            sampleStructure: sampleStructure,
                            referencingFileExtension: fileURL.pathExtension,
                            level: missingLevel,
                            record: record
                        )
                        appendIssue(missingLevel.severity, missingLevel, missingMessage)
                        continue
                    }

                    let ext = resolvedURL.pathExtension.localizedLowercase
                    if ext == "wasm" {
                        usesWASMResource = true
                    }
                    if ["html", "htm", "css", "js", "json"].contains(ext),
                       Self.shouldScanWebDependencyFile(named: resolvedURL.lastPathComponent) {
                        pendingFiles.append(resolvedURL)
                    }
                case let .external(urlString):
                    externalDependencyURLs.insert(urlString)
                    appendIssue(.warning, .warning, "依赖外部资源：\(urlString)")
                }
            }
        }

        if !scannedFiles.isEmpty {
            appendIssue(.info, .info, "已扫描 \(scannedFiles.count) 个入口/依赖文件")
        }
        if truncatedScanFileCount > 0 {
            appendIssue(
                .info,
                .info,
                "为避免大型数据脚本阻塞启动，\(truncatedScanFileCount) 个文件仅扫描了首尾片段；运行时将使用 HTTP loopback 兼容模式"
            )
        }
        let cachedExternalURLs = staticContentSummary.map {
            Set($0.externalDependencyHosts.map { "https://\($0)" })
        } ?? []
        let effectiveExternalDependencyURLs = externalDependencyURLs.union(cachedExternalURLs)
        appendWebExternalDependencyIssues(from: effectiveExternalDependencyURLs, appendIssue: appendIssue)

        if usesGeneralProperties {
            appendIssue(.info, .info, "检测到样本使用 applyGeneralProperties；当前宿主已提供基础 general properties 注入")
        }
        if usesGeneralFPS {
            appendIssue(.info, .info, "检测到样本读取 properties.fps；当前宿主会按显示器刷新率注入数值型 fps")
        }
        if usesServiceWorkerRegistration {
            appendIssue(.warning, .warning, "检测到 Service Worker 注册；自定义 scheme 不支持该能力，运行时将优先使用本地 HTTP loopback 兼容模式")
        }
        if usesESModuleDependency {
            appendIssue(.info, .info, "检测到 ES module 依赖；运行时会优先选择更接近 http(s) origin 的兼容模式")
        }
        if usesDynamicImport {
            appendIssue(.info, .info, "检测到动态 import()；运行时会优先选择本地 HTTP loopback 兼容模式")
        }
        if usesWASMResource {
            appendIssue(.info, .info, "检测到 WASM 资源或 WebAssembly API；运行时会记录 MIME/streaming 兼容诊断")
        }
        if usesWASMStreaming {
            appendIssue(.warning, .warning, "检测到 WebAssembly streaming 编译；自定义 scheme 兼容性较弱，运行时将优先使用本地 HTTP loopback")
        }
        if usesCustomSchemeSensitiveWebGL {
            appendIssue(.warning, .warning, "检测到 Pixi/Live2D/视频纹理等 WebGL 资源路径；自定义 scheme 容易触发 origin 安全限制，运行时将优先使用本地 HTTP loopback")
        }
        if usesIframeCrossFrameAccess {
            appendIssue(.warning, .warning, "检测到 iframe 跨 frame DOM 访问；自定义 scheme 容易触发同源限制，运行时将优先使用本地 HTTP loopback")
        }
        if staticContentSummary?.hasOnDemandDirectoryProperty == true {
            appendIssue(.info, .info, "检测到目录属性使用 ondemand 模式；当前宿主更偏按需随机文件解析语义，尚未完全覆盖更复杂旧生态样本对目录枚举/刷新节奏的预期")
        }
        if staticContentSummary?.hasFetchAllDirectoryProperty == true {
            appendIssue(.info, .info, "检测到目录属性使用 fetchall 模式；当前宿主已提供基础文件变化通知与目录同步，但这仍属于 fetchall 定向兼容，不代表通用目录能力已完整对齐")
        }
        appendWebPropertyPreconditionIssues(
            preconditions: resolvedWebRuntimePreconditions(
                for: record,
                definitions: propertyDefinitions,
                effectiveValues: effectiveWebPropertyValues(for: record, definitions: propertyDefinitions)
            ),
            sampleStructure: sampleStructure,
            appendIssue: appendIssue
        )
        appendHighLoadWebSampleIssue(
            riskFlags: resolvedWebStructuralRiskFlags(for: record, sampleStructure: sampleStructure),
            appendIssue: appendIssue
        )
        // 运行风险旗标只由结构化摘要装配（`resolvedWebStaticContentRiskFlags`，与
        // 运行档位同源）：校验报告不再手抄一份旗标映射表，两处只共享同一个入口。
        // 摘要缺失（无 descriptor）时按空集合处理——运行侧同样读不到摘要。上面的
        // 本地扫描信号只用于生成 issue 文案，不再驱动旗标。
        let scannedRiskFlags = staticContentSummary.map(resolvedWebStaticContentRiskFlags(from:)) ?? []
        appendScannedWebRuntimeRiskIssues(
            riskFlags: resolvedWebStructuralRiskFlags(for: record, sampleStructure: sampleStructure) + scannedRiskFlags,
            appendIssue: appendIssue
        )

        if let failureMessage = webPlaybackFailureMessage(for: record) {
            let playbackFailureIssue = webPlaybackFailureIssue(for: failureMessage)
            appendIssue(playbackFailureIssue.severity, playbackFailureIssue.level, playbackFailureIssue.message)
        }

        let report = SteamWorkshopWebValidationReport(
            sampleStructure: sampleStructure,
            entryRelativePath: entryRelativePath,
            scannedFileCount: scannedFiles.count,
            issueCount: issues.count,
            issues: issues,
            propertySource: propertySource,
            presetOverrideCount: presetOverrideCount
        )
        webValidationReportCache[record.id] = CachedWebValidationReport(signature: signature, report: report)
        return report
    }

    func webPlaybackFailureMessage(for record: SteamWorkshopDownloadRecord) -> String? {
        if let failureRecordID = lastWebPlaybackFailureRecordID {
            guard failureRecordID == record.id else { return nil }
            return lastWebPlaybackFailureMessage
        }

        guard let entryURL = record.webEntryURL,
              let failurePath = lastWebPlaybackFailurePath else {
            return nil
        }
        let entryPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard failurePath == entryPath else { return nil }
        return lastWebPlaybackFailureMessage
    }
}
