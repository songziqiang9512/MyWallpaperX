import Foundation

/// 粗粒度壁纸引擎命令：UI 与控制面只发命令，不直触引擎内部。
/// 该枚举是 Scene daemon IPC 合同（engine-refactor-program.md M5.4）
/// 的应用层草案；新增命令时必须同时补齐两个引擎处理端的语义映射。
enum WallpaperEngineCommand: Equatable, Sendable {
    /// 加载 Scene 壁纸。属性覆盖为通用字符串键值，由引擎端解析。
    case loadScene(rootURL: URL, propertyOverrides: [String: String])
    /// 属性热更新：不重启当前壁纸，由运行时 value-only 路径消费。
    case setProperty([String: String], revision: UInt64)
    /// 性能预算档：60 = standard，30 = efficient。
    case setPerformanceProfile(maxFPS: Int)
    case setMuted(Bool)
    case pause
    case resume
    /// 选中层"下一张壁纸"；由当前选中权威消费，非引擎内部语义。
    case switchNext
    /// 停止当前引擎播放（不退出 App）。
    case stop
}
