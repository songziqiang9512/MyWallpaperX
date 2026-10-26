//
//  ModuleFocusable.swift
//  MyWallpaperX
//
//  模块焦点管理协议。
//  各模块的根容器视图遵从此协议，Shell 层在模块切换时统一调用，
//  让目标模块把键盘焦点转给正确的内部子视图（CollectionView 等）。
//
//  使用方式：
//  1. 模块容器视图遵从 ModuleFocusable，实现 requestFocus()
//  2. 在 requestFocus() 内调用 window?.makeFirstResponder(内部CollectionView)
//  3. Shell 层通过 moduleDidBecomeActive 通知触发，无需知晓模块内部类型
//

import AppKit

// MARK: - 协议

/// 模块根容器视图遵从此协议，表示该模块可以接管键盘焦点。
protocol ModuleFocusable: NSView {
    /// 模块激活时由框架层调用，实现者负责把焦点给到正确的内部子视图。
    func requestFocus()
}

// MARK: - 通知名

extension Notification.Name {
    /// Shell 层在模块切换完成后发出，object 为目标 SelectedItem 的描述字符串。
    /// userInfo: ["module": String] 标识目标模块
    static let moduleDidBecomeActive = Notification.Name("com.mywallpaper.moduleDidBecomeActive")
    /// 请求 Shell 打开统一 Inspector 宿主。
    /// userInfo:
    /// - "module": String，来源模块标识（必填）
    /// - "cardID": String，详情卡片稳定 token（必填）
    /// - "title": String，宿主标题（必填）
    /// - "subtitle": String，副标题（可选）
    /// - "preferredWidth": CGFloat/Double，宿主建议宽度（可选）
    /// - "focusPolicy": String，见 InspectorHostFocusPolicy.rawValue（可选）
    /// - "chromeStyle": String，见 InspectorHostChromeStyle.rawValue（可选，默认 standard）
    static let inspectorHostOpenRequested = Notification.Name("com.mywallpaper.inspectorHostOpenRequested")
    /// 请求 Shell 关闭统一 Inspector 宿主。
    /// userInfo 可为空；若提供 "module" / "cardID"，则只关闭匹配中的卡片。
    static let inspectorHostCloseRequested = Notification.Name("com.mywallpaper.inspectorHostCloseRequested")
    /// Shell 宿主完成展示后发出，模块可据此桥接详情内容或接管 inspector 内部焦点。
    static let inspectorHostDidPresent = Notification.Name("com.mywallpaper.inspectorHostDidPresent")
    /// Shell 宿主关闭后发出，userInfo 回传最近一次已关闭卡片的 token 信息。
    static let inspectorHostDidClose = Notification.Name("com.mywallpaper.inspectorHostDidClose")
    /// 模块请求把详情内容挂入 Shell 已持有的 InspectorHost 插槽。
    /// userInfo:
    /// - "module": String，来源模块标识（必填）
    /// - "cardID": String，详情卡片稳定 token（必填）
    /// - "hostedView": NSView，模块详情承载视图（必填）
    static let inspectorHostMountContentRequested = Notification.Name("com.mywallpaper.inspectorHostMountContentRequested")
}

// MARK: - 模块标识常量

enum ModuleIdentifier: String {
    case videoLibrary       = "videoLibrary"
    case staticImageLibrary = "staticImageLibrary"
    case onlineLibrary      = "onlineLibrary"
    case steamWorkshop      = "steamWorkshop"
    case wallhaven          = "wallhaven"
    case pixiv              = "pixiv"
}
