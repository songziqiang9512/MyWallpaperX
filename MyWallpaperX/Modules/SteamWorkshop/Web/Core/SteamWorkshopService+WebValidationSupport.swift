#if DEBUG
import Foundation

extension SteamWorkshopService {
    func appendWebExternalDependencyIssues(
        from urls: Set<String>,
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void
    ) {
        let parsedURLs = urls.compactMap { URL(string: $0) }
        let hosts = Set(
            parsedURLs.compactMap { $0.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        guard hosts.isEmpty == false else { return }

        let summary = hosts.sorted().joined(separator: ", ")
        appendIssue(.info, .info, "检测到外部资源/服务依赖：\(summary)")
        appendIssue(.warning, .warning, "若网络或第三方服务不可用，页面可能出现部分功能失效，但这不一定是宿主兼容失败")

        let localhostHosts = hosts.filter {
            $0 == "localhost" || $0 == "127.0.0.1" || $0 == "::1"
        }
        if localhostHosts.isEmpty == false {
            let localhostSummary = localhostHosts.sorted().joined(separator: ", ")
            appendIssue(.warning, .preconditionUnmet, "检测到样本依赖本地附加服务：\(localhostSummary)；若对应服务未在系统中运行，相关性能/监控模块会失效")
            appendIssue(.info, .info, "这类 localhost 依赖通常属于样本自带扩展链路，不应误判为 Web 宿主桥接缺失")
        }

        let remoteScriptHosts = Set(
            parsedURLs.compactMap { url -> String? in
                guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                    return nil
                }
                let path = url.path.lowercased()
                if path.hasSuffix(".js") || path.hasSuffix(".mjs") || path.hasSuffix(".css") {
                    return host
                }
                return nil
            }
        )
        if remoteScriptHosts.isEmpty == false {
            appendIssue(.warning, .preconditionUnmet, "检测到样本直接依赖外网脚本/样式 CDN：\(remoteScriptHosts.sorted().joined(separator: ", "))；离线、本地 scheme 或第三方源失效时会直接影响启动稳定性")
            appendIssue(.info, .info, "这类断点优先归因于样本资源组织不够自包含，而不是宿主 HTML 入口承载失败")
        }
    }

    func webValidationLevelForMissingResource(
        relativePath: String,
        sampleStructure: SteamWorkshopWebSampleStructure,
        referencingFileExtension: String,
        record: SteamWorkshopDownloadRecord
    ) -> SteamWorkshopWebValidationLevel {
        let loweredPath = relativePath.lowercased()
        let resourceExtension = loweredPath.components(separatedBy: ".").last ?? ""
        if ["html", "js", "css"].contains(resourceExtension) {
            return .runtimeBlocking
        }
        if record.isDependencyBackedWeb,
           isDependencyShellPreconditionResourcePath(loweredPath) {
            return .preconditionUnmet
        }
        if referencingFileExtension.lowercased() == "html"
            && (loweredPath.hasSuffix(".png") || loweredPath.hasSuffix(".jpg") || loweredPath.hasSuffix(".jpeg") || loweredPath.hasSuffix(".webp")) {
            return sampleStructure == .basicHTMLWeb ? .warning : .runtimeBlocking
        }
        return .warning
    }

    func webValidationMessageForMissingResource(
        relativePath: String,
        sampleStructure: SteamWorkshopWebSampleStructure,
        referencingFileExtension: String,
        level: SteamWorkshopWebValidationLevel,
        record: SteamWorkshopDownloadRecord
    ) -> String {
        if level == .preconditionUnmet {
            if record.isDependencyBackedWeb {
                return "依赖型 WEB 预设壳引用的宿主/预设资源当前不可用：\(relativePath)"
            }
            return "运行当前 Web 项目前还缺少前置资源：\(relativePath)"
        }
        if sampleStructure == .shaderOrCanvasWeb && referencingFileExtension.lowercased() == "js" {
            return "脚本依赖资源缺失，可能导致 Web 壁纸启动后空白：\(relativePath)"
        }
        if record.isDependencyBackedWeb {
            return "补丁壳或依赖宿主中的本地资源缺失：\(relativePath)"
        }
        return "本地资源缺失：\(relativePath)"
    }

    func webPlaybackFailureIssue(for message: String) -> SteamWorkshopWebValidationIssue {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredMessage = trimmedMessage.lowercased()

        if isWebPlaybackFailurePreconditionRelated(loweredMessage) {
            return SteamWorkshopWebValidationIssue(
                severity: .warning,
                level: .preconditionUnmet,
                message: "最近一次播放失败更像前置条件/本地访问问题：\(trimmedMessage)"
            )
        }

        if isWebPlaybackFailureEnvironmentRelated(loweredMessage) {
            return SteamWorkshopWebValidationIssue(
                severity: .warning,
                level: .warning,
                message: "最近一次播放失败更像外部环境/网络问题：\(trimmedMessage)"
            )
        }

        return SteamWorkshopWebValidationIssue(
            severity: .warning,
            level: .runtimeBlocking,
            message: "最近一次播放失败：\(trimmedMessage)"
        )
    }

    func appendWebPropertyPreconditionIssues(
        preconditions: [ResolvedWebRuntimePrecondition],
        sampleStructure _: SteamWorkshopWebSampleStructure,
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void
    ) {
        guard !preconditions.isEmpty else { return }
        for precondition in preconditions where precondition.status == .unmet {
            let level: SteamWorkshopWebValidationLevel = switch precondition.kind {
            case .directory:
                .preconditionUnmet
            case .file:
                .warning
            }
            appendIssue(level.severity, level, precondition.message)
        }
    }

    func appendHighLoadWebSampleIssue(
        riskFlags: [ResolvedWebRuntimeRiskFlag],
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void
    ) {
        guard riskFlags.contains(.highLoadStructure) else { return }
        appendIssue(
            .warning,
            .warning,
            "该 Web 样本命中高负载结构特征，运行时可能出现高内存占用、明显卡顿或宿主压力过高"
        )
        appendIssue(
            .info,
            .info,
            "当前已启用宿主止损策略（输入节流、较低刷新频率等），但这不保证复杂样本一定流畅"
        )
    }

    func appendScannedWebRuntimeRiskIssues(
        riskFlags: [ResolvedWebRuntimeRiskFlag],
        appendIssue: (SteamWorkshopWebValidationSeverity, SteamWorkshopWebValidationLevel, String) -> Void
    ) {
        let flags = Set(riskFlags)
        if flags.contains(.unsupportedDisplayConditionFallback) {
            appendIssue(.warning, .warning, "检测到复杂 display condition；当前属性面板仅覆盖受支持表达式，未识别条件会回退为显示")
        }
        if flags.contains(.incompleteLocalizationTokens) {
            appendIssue(.warning, .warning, "检测到未翻译的 ui_ 本地化 token；说明该样本的 localization 表可能不完整，当前界面会按原始 token 回退显示")
        }
        if flags.contains(.implicitFractionalSliderPrecision) {
            appendIssue(.info, .info, "检测到 fractional slider 未显式声明 precision；当前按 precision=2 的默认语义注入和显示")
        }
        if flags.contains(.knownSafariBaselineIncompatibility) {
            appendIssue(.warning, .warning, "该 Web 样本曾被标记为 Safari 基线可疑，但这不再作为直接封锁依据；当前应优先检查入口定位、根目录与相对路径解析是否正确")
            appendIssue(.info, .info, "如果样本在 Safari 可以运行而软件内失败，优先怀疑本地 scheme 根路径、依赖宿主入口或资源相对路径识别问题")
        }
        if flags.contains(.externalServiceDependency) {
            appendIssue(.warning, .warning, "检测到样本依赖外部资源/服务；网络或第三方服务不可用时，页面可能出现部分功能失效，但这不一定是宿主兼容失败")
            appendIssue(.info, .info, "当前样本更像自带外网/CDN 增强依赖的页面；若功能局部失效，应先排查这些依赖是否可用，再判断宿主兼容性")
        }
        if flags.contains(.localhostDependency) {
            appendIssue(.warning, .preconditionUnmet, "检测到样本依赖本地附加服务；若对应 localhost 服务未运行，相关模块会失效")
            appendIssue(.info, .info, "这类 localhost 依赖通常属于样本自带扩展链路，不应误判为 Web 宿主桥接缺失")
        }
        if flags.contains(.webMHeavyMedia) {
            appendIssue(.warning, .warning, "检测到样本依赖 .webm 媒体资源；若页面内视频无法播放，优先怀疑 WebKit/Safari 对该编码组合的解码能力")
            appendIssue(.info, .info, "这类样本建议结合运行时媒体事件（loadedmetadata/canplay/error/stalled）继续核对，不宜直接判成入口或本地 scheme 故障")
        }
        if flags.contains(.hoverOnlyInteraction) {
            appendIssue(.warning, .warning, "检测到样本存在纯 CSS :hover 交互；当前 click-through Web 宿主主要转发 JS 指针事件，不保证原生 hover 命中状态完全成立")
            appendIssue(.info, .info, "若页面主要依赖 :hover 切换显示层或滤镜效果，应优先按宿主输入命中边界评估")
        }
        if flags.contains(.pluginBridgeApproximation) {
            appendIssue(.warning, .warning, "检测到样本使用 Wallpaper Engine plugin / RGB 接口；当前宿主仅提供不会崩的占位兼容，不代表真实 LED/RGB 能力已实现")
        }
        if flags.contains(.persistentBrowserStorageUsage) {
            appendIssue(.info, .info, "检测到样本依赖浏览器持久化存储（localStorage/IndexedDB）；这类页面会把用户事件、布局或运行态保存在页面私有存储中")
            appendIssue(.warning, .warning, "若页面数据丢失、重置或与 Wallpaper Engine 的 wpcache 行为不一致，应优先按持久化环境差异评估，而不应直接判为宿主桥接失败")
        }
        if flags.contains(.serviceWorkerRegistration) {
            appendIssue(.warning, .warning, "检测到 Service Worker 注册；自定义 scheme 无法提供该能力，当前会建议使用本地 HTTP loopback 兼容模式")
        }
        if flags.contains(.esModuleDependency) {
            appendIssue(.info, .info, "检测到 ES module 依赖；当前会建议使用本地 HTTP loopback 兼容模式降低 custom scheme 差异")
        }
        if flags.contains(.dynamicImportUsage) {
            appendIssue(.info, .info, "检测到动态 import()；当前会建议使用本地 HTTP loopback 兼容模式")
        }
        if flags.contains(.wasmUsage) {
            appendIssue(.info, .info, "检测到 WASM 资源或 WebAssembly API；当前会按 WASM MIME 与 streaming 行为记录兼容诊断")
        }
        if flags.contains(.wasmStreamingUsage) {
            appendIssue(.warning, .warning, "检测到 WebAssembly streaming 编译；custom scheme 兼容性较弱，当前会建议使用本地 HTTP loopback")
        }
        if flags.contains(.iframeCrossFrameAccess) {
            appendIssue(.warning, .warning, "检测到 iframe 跨 frame DOM 访问；custom scheme 更容易触发同源限制，当前会建议使用本地 HTTP loopback")
        }
    }

    func webValidationLevelForEmptyPropertyValue(
        definition: SteamWorkshopWebPropertyDefinition,
        sampleStructure: SteamWorkshopWebSampleStructure
    ) -> SteamWorkshopWebValidationLevel {
        if definition.kind == .directory {
            return .preconditionUnmet
        }
        switch sampleStructure {
        case .multimediaDashboardWeb, .megaConfigDashboardWeb, .dependencyBackedShell:
            return .preconditionUnmet
        case .shaderOrCanvasWeb, .spineWebCharacter, .propertyDrivenHTMLWeb, .basicHTMLWeb:
            return .warning
        }
    }

    func webValidationMessageForEmptyPropertyValue(definition: SteamWorkshopWebPropertyDefinition) -> String {
        switch definition.kind {
        case .directory:
            if let mode = definition.directoryMode, mode.isEmpty == false {
                return "属性 `\(definition.title)` 需要先选择并授权目录后才能完整运行（mode: \(mode)）"
            }
            return "属性 `\(definition.title)` 需要先选择并授权目录后才能完整运行"
        case .file:
            if let fileType = definition.fileType, fileType.isEmpty == false {
                return "属性 `\(definition.title)` 需要先选择\(fileType)文件后才能完整运行"
            }
            return "属性 `\(definition.title)` 需要先选择文件后才能完整运行"
        case .slider, .color, .toggle, .combo, .label, .group, .text, .unknown:
            return "属性 `\(definition.title)` 缺少运行前置值"
        }
    }

}
#endif
