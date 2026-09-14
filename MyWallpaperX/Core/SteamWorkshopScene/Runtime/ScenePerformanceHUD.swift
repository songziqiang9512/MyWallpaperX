#if DEBUG
import AppKit
import QuartzCore

/// M1.3：debug 性能 HUD（仅 DEBUG 编译）。1Hz 读取常开计数器
/// （ScenePerformanceCounterHub）快照差分并渲染；每 5 秒输出一行
/// 结构化 NSLog（MWX PERF）供脚本/基准做 before/after 解析。
/// 本类型不在帧路径上：唯一与帧路径的交集是 startFrameDriver 里
/// 的一次 showIfNeeded() 调用。
final class ScenePerformanceHUDController {
    static let shared = ScenePerformanceHUDController()

    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: DispatchSourceTimer?
    private var tickCount = 0
    private var lastSnapshot: [ScenePerformanceMetric: UInt64] = [:]

    private var isEnabled: Bool {
        SceneDesktopWallpaperHost.usesDebugEvidenceWindow
            || ProcessInfo.processInfo.environment["MYWALLPAPERX_SCENE_PERF_HUD"] == "1"
    }

    func showIfNeeded() {
        guard isEnabled, panel == nil else { return }
        let label = NSTextField(labelWithString: "…")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .systemGreen
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 8
        label.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 16, y: 16, width: 460, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: panel.contentView!.leadingAnchor, constant: 8),
            label.topAnchor.constraint(
                equalTo: panel.contentView!.topAnchor, constant: 6),
            label.trailingAnchor.constraint(
                equalTo: panel.contentView!.trailingAnchor, constant: -8)
        ])
        panel.orderFrontRegardless()

        self.panel = panel
        self.label = label

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    private func refresh() {
        guard let label, let panel else { return }
        tickCount += 1
        let snapshot = ScenePerformanceCounterHub.shared.snapshot()
        defer { lastSnapshot = snapshot }

        func delta(_ metric: ScenePerformanceMetric) -> UInt64 {
            let now = snapshot[metric] ?? 0
            let before = lastSnapshot[metric] ?? 0
            return now >= before ? now - before : 0
        }
        func total(_ metric: ScenePerformanceMetric) -> UInt64 {
            snapshot[metric] ?? 0
        }
        func ms(_ micros: UInt64, _ frames: UInt64) -> String {
            guard frames > 0 else { return "-" }
            return String(format: "%.2fms", Double(micros) / Double(frames) / 1000.0)
        }
        func mib(_ bytes: UInt64) -> String {
            String(format: "%.1fMiB", Double(bytes) / 1_048_576.0)
        }

        let rendered = delta(.framesRendered)
        let cpu = ms(delta(.cpuFrameMicros), rendered)
        let renderer = ms(delta(.rendererMicros), rendered)
        let drawable = ms(delta(.drawableWaitMicros), rendered)
        let busy = delta(.framesBusy)
        let dropped = delta(.framesDropped)
        let drawCalls = delta(.drawCalls)
        let pipelineStateBinds = delta(.pipelineStateBinds)
        let geometryDrawCalls = delta(.geometryDrawCalls)
        let fallbackBranches = delta(.fallbackBranches)
        let stageSummary = [
            ("res", delta(.worldResolveMicros)),
            ("adm", delta(.frameAdmissionMicros)),
            ("prep", delta(.prepassMicros)),
            ("loop", delta(.layerLoopMicros)),
            ("seal", delta(.compositorSealMicros)),
        ]
        .map { "\($0.0) \(ms($0.1, rendered))" }
        .joined(separator: " ")

        label.stringValue = """
        FPS \(rendered)  busy \(busy)  drop \(dropped)  draw \(drawCalls)
        bind \(pipelineStateBinds)  geometry \(geometryDrawCalls)  fallback \(fallbackBranches)
        GPU \(mib(total(.gpuAllocatedBytes)))  RT pools \(mib(total(.renderTargetPoolBytes)))
        cpu \(cpu)  renderer \(renderer)  drawable \(drawable)
        stages: \(stageSummary)

        """

        if tickCount % 5 == 0 {
            let launch = ScenePerformanceCounterHub.shared.launchPhaseSnapshot()
            let launchSummary = SceneLaunchPhase.allCases.compactMap { phase in
                launch[phase].map { "\(phase.rawValue)=\(String(format: "%.2fs", Double($0) / 1_000_000))" }
            }
            .joined(separator: " ")
            NSLog(
                "MWX PERF: rendered=%llu attempts=%llu busy=%llu dropped=%llu cpu=%@ renderer=%@ drawable=%@ draw=%llu binds=%llu geometry=%llu fallback=%llu gpu=%llu rtPools=%llu stages{%@} launch{%@}",
                total(.framesRendered), total(.frameAttempts),
                total(.framesBusy), total(.framesDropped),
                ms(total(.cpuFrameMicros), total(.framesRendered)),
                ms(total(.rendererMicros), total(.framesRendered)),
                ms(total(.drawableWaitMicros), total(.framesRendered)),
                total(.drawCalls), total(.pipelineStateBinds),
                total(.geometryDrawCalls), total(.fallbackBranches),
                total(.gpuAllocatedBytes), total(.renderTargetPoolBytes),
                stageSummary, launchSummary
            )
        }
        panel.contentView?.needsLayout = true
    }
}
#endif
