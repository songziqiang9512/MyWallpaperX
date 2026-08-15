# MyWallpaperX AppKit 全量迁移计划

> 状态：现役迁移目标与剩余工作入口
>
> 最近核对：2026-08-11。下文各阶段的“当前进展”保留 2026-05-17 批次记录；当前残留以本节清单和代码扫描为准。
>
> 长期权威：本计划与[技术栈与架构路线边界](technology-stack-boundaries.md)共同确定最终 UI 为 Swift + AppKit。迁移完成前只维护下列 SwiftUI 残留，不新增 SwiftUI 产品面、设置页、桌面宿主或 hosting bridge；若要改变 0 SwiftUI 目标，必须先修改长期技术路线，而不是在功能批次中隐式扩张。

目标：最终交付一个 0 SwiftUI 的 macOS 原生 AppKit 应用。应用结构以邮件类客户端为参照：左侧原生 source list，右侧模块内容区，顶部统一 NSToolbar，详情/信息面板由 AppKit inspector overlay 或 panel 承载。

## 当前判断

截至 2026-07-31，App 生命周期、主窗口 Shell、主菜单和主要网格均已由 AppKit 承担，但 SwiftUI 尚未清零。当前 `import SwiftUI` 只剩 7 个文件：

- `App/ScenePropertyWindowController.swift`
- `Shared/UI/InspectorHostBridge.swift`
- `Modules/SteamWorkshop/Scene/SteamWorkshopSceneDetailSection.swift`
- `Modules/SteamWorkshop/Scene/SteamWorkshopScenePropertyEditorView.swift`
- `Modules/SteamWorkshop/UI/SteamWorkshopItemDetailPreviewSupport.swift`
- `Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet.swift`
- `Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSupportViews.swift`

剩余工作已经集中在 Scene 属性窗口、共享 inspector bridge 和 Steam Workshop 详情/属性 UI；迁移仍应按这些边界逐项替换并验证，不需要重写已完成的 AppKit Shell 或网格。

## 最终结构

### App 层

- `main.swift` 创建 `NSApplication`，设置 `AppDelegate`，调用 `NSApp.run()`。
- `AppDelegate` 只负责应用生命周期、Help Book、状态栏、主菜单安装、启动阶段调度。
- 主菜单由 `NSMenu` / `NSMenuItem` 构建，动态可用性继续通过 `NSMenuItemValidation` 实现。
- 设置窗口使用 `NSWindowController + NSViewController + AppKitSettingsContainerView`，不再经过 `NSHostingController`。

### Shell 层

- 主窗口内容控制器为 AppKit `NSSplitViewController`。
- 左侧为 `AppKitSidebarContainerView`，使用 `NSOutlineView` source list 样式。
- 右侧为 `AppKitDetailHostViewController`，按 `SelectedItem` 切换各模块 `NSViewController` / `NSView`。
- Shell 维护当前 `SelectedItem`、模块切换通知、Quick Look 同步、空白点击清选、模块焦点转移。
- Shell 不持有 SwiftUI `Binding`、`@State`、`@EnvironmentObject`。

### 模块层

- 每个模块对 Shell 暴露 AppKit 入口：
  - 视频库：`VideoLibraryViewController` 或 `VideoLibraryContainerView`
  - 图片库：`StaticImageLibraryViewController`
  - 在线库：`OnlineLibraryBrowserViewController` / `OnlineLibraryDownloadsViewController`
  - Steam：`SteamWorkshopBrowserViewController` / `SteamWorkshopDownloadsViewController`
- 模块内部继续尊重现有服务边界。跨模块仍然只通过 Notification 或既有 Coordinator 中转。
- 现有 AppKit 网格容器优先复用，不重新造一套渲染系统。

### Inspector

- `InspectorHostStore`、`InspectorHostRequest`、mount notification 机制保留。
- SwiftUI `InspectorHost` 替换为 AppKit panel view。
- SwiftUI `InspectorHostBridge` 替换为模块侧显式监听/请求：
  - 选中项出现：发起 inspector open。
  - inspector present：mount 模块提供的 `NSView`。
  - 选中项清空：发起 inspector close。
- 各模块 inspector 内容改为 AppKit `NSView`。

## 分阶段执行

### 阶段 1：切断 SwiftUI App 生命周期

目标：

- 删除 `@main struct MyWallpaperApp: App` 的启动角色。
- 用 AppKit `main.swift`、`NSApplicationMain` 等价流程启动应用。
- 将 SwiftUI Commands 改成 AppKit 主菜单。
- 设置窗口改为直接承载 `AppKitSettingsContainerView`。

验收：

- `rg -n "@main|struct .*: App|Commands|WindowGroup|Settings \\{" MyWallpaperX` 无应用生命周期残留。
- `xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug build` 通过。
- 偏好设置、文件/编辑/显示/壁纸/帮助菜单仍能触发原有 Coordinator 动作。

当前进展：

- 2026-05-17：App 生命周期已从 SwiftUI `App` 改为 AppKit `@main`。
- 2026-05-17：`MainMenuBuilder` 接管主菜单构建，菜单可用性继续走 `NSMenuItemValidation`。
- 2026-05-17：设置窗口改为 `SettingsWindowController` 直接承载 AppKit 设置容器。
- 2026-05-17：`MyWallpaperApp.swift` 已删除。

### 阶段 2：Shell 全 AppKit 化

目标：

- 移除 `ContentView`、`DetailView`、`AppKitMainSplitView: NSViewControllerRepresentable`、`AppKitSidebarView: NSViewRepresentable`。
- `MainWindowController` 直接创建 AppKit `AppKitMainSplitViewController`。
- `AppKitMainSplitViewController` 直接持有 sidebar/detail 控制器，不再创建 `NSHostingController`。
- 把 `ContentView.syncManagerSelection`、初始焦点、Quick Look 同步、空白点击清选迁移到 AppKit Shell 控制器。

验收：

- `MyWallpaperX/Shell` 内不再 `import SwiftUI`。
- 主窗口左侧 source list 与右侧详情切换行为保持一致。
- 模块切换仍正确更新工具栏、菜单可用性和焦点。

当前进展：

- 2026-05-17：`MainWindowController` 已直接创建 `AppKitMainSplitViewController`，主窗口根不再由 `ContentView`/`NSHostingController` 承载。
- 2026-05-17：Shell 选择同步、模块切换通知、Quick Look 同步、重置处理已迁入 `AppKitMainSplitViewController`。
- 2026-05-17：左侧 sidebar 已由 `AppKitSidebarViewController` 直接承载 `AppKitSidebarContainerView`。
- 2026-05-17：`ContentView.swift` 已删除。
- 2026-05-17：`DetailView` 已删除；右侧路由已迁入 `AppKitDetailHostViewController`。
- 待完成：`AppKitMainSplitView` 仍通过 `NSHostingController` 承载共享 `InspectorHost`；`AppKitDetailHostViewController` 仍临时由 `NSHostingController` 承载 Steam 浏览 / 下载入口。

### 阶段 3：模块入口去 SwiftUI 包装

目标：

- 视频库入口从 `VideoLibraryEntryView` 改为 AppKit view/controller。
- 图片库入口从 `StaticImageLibraryEntryView + SILBridgeView` 改为直接使用 `SILGridContainerView`。
- 在线库和 Steam 已有 AppKit 网格的页面，先替换入口包装，再处理登录/API key/空态/错误态。
- 设置页保留 `AppKitSettingsContainerView`，删除 `AppKitSettingsView: NSViewRepresentable`。

验收：

- `NSViewRepresentable` 在模块入口层清零。
- 各模块列表、选择、多选、搜索、缩放、预览、删除、导入/下载入口保持可用。

当前进展：

- 2026-05-17：视频库列表已由 `AppKitDetailHostViewController` 直接创建 `AppKitLibraryGridContainerView`，不再经过 `VideoLibraryEntryView` / `AppKitLibraryGridView: NSViewRepresentable`。
- 2026-05-17：`VideoLibraryEntryView.swift` 已删除，`AppKitLibraryGridView.swift` 已去掉 SwiftUI wrapper。
- 2026-05-17：视频库 inspector 触发已由 `AppKitDetailHostViewController` 接管；内容已在阶段 4 改为 AppKit `VideoLibraryInspectorView`。
- 2026-05-17：图片库列表已由 `AppKitDetailHostViewController` 直接创建 `SILGridContainerView`，不再经过 `StaticImageLibraryEntryView` / `SILBridgeView: NSViewRepresentable`。
- 2026-05-17：`SILEntryView.swift` 已删除；图片库 inspector 触发已由 `AppKitDetailHostViewController` 接管，内容已在阶段 4 改为 AppKit `SILInspectorView`。
- 2026-05-17：在线库浏览入口已改为 AppKit `OnlineLibraryBrowserView`，API key、loading、空态、错误态和下载完成提示均由 AppKit support view 承载。
- 2026-05-17：在线库下载入口已由 `AppKitDetailHostViewController` 直接承载 `AppKitOLDownloadsContainerView`，`OnlineLibraryDownloadsView.swift` 已删除。
- 待完成：Steam 浏览 / 下载入口仍为 SwiftUI，需要按登录 sheet、空态、错误态、详情面板等边界分步迁移。

### 阶段 4：Inspector 与弹层全 AppKit 化

目标：

- 替换 `InspectorHost.swift` 和 `InspectorHostBridge.swift`。
- 视频库、图片库、在线下载、Steam 详情面板全部提供 AppKit inspector view。
- Steam 登录 sheet、在线库 API key sheet、alert/empty/loading/toast 全部换为 AppKit view、sheet 或 panel。

验收：

- `NSHostingView`、`NSHostingController` 在 app target 清零。
- Inspector 打开/关闭动画、焦点恢复、点击外部关闭和滚动关闭行为保持一致。

当前进展：

- 2026-05-17：视频库、图片库、在线库下载的 inspector 内容已改为 AppKit `NSView`，分别落在：
  - `VideoLibraryInspectorView.swift` / `VideoLibraryInspectorSupport.swift`
  - `SILInspectorView.swift` / `SILInspectorSupport.swift`
  - `OnlineLibraryDownloadsInspectorView.swift` / `OnlineLibraryDownloadsInspectorSupport.swift`
- 2026-05-17：`AppKitDetailHostViewController` 负责视频库、图片库、在线库下载 inspector 的 open / mount / close，同步仍通过 `InspectorHostActions` 与通知边界。
- 2026-05-17：共享 `InspectorHost` 外壳仍是 SwiftUI，但已按 AppKit 内容面板需要修正浅色 / 深色玻璃质感、缩略图宽度、内容垂直居中、分隔线、底部按钮宽度 / 高度 / 图文间距。
- 待完成：将共享 `InspectorHost` / `InspectorHostBridge` / `InspectorHostActions` 替换为 AppKit 宿主后，移除 `NSHostingController` / `NSHostingView`。
- 待完成：Steam 详情、Steam Web inspector、登录 sheet，以及在线库剩余 toast / alert / sheet 继续按单一边界迁移。

UI 保真要求：

- AppKit 化不是重画一套新视觉；视频库、图片库、在线库下载详情面板必须保持与既有 Steam 详情面板同一视觉语言。
- 缩略图应占满内容区宽度，不能只显示半边或被错误裁切。
- 非 Steam 面板内容应在可滚动内容区内自然居中；顶部内容间距为 0，不允许大羽化遮挡标题。
- 底部按钮总宽度（含间距）必须与内容区 / 缩略图宽度一致，按钮高度一致，图标与文字间距紧凑。
- 浅色模式使用更接近原生白玻璃的层次；灰色按钮使用 label/黑色方向文字，蓝色主按钮使用白字，并且必须随深浅色切换自适应。

本阶段 2026-05-17 验证：

- 2026-05-17：`xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug build` 通过。
- 2026-05-17：残留扫描显示 SwiftUI 主要集中在共享 `InspectorHost`、`InspectorHostBridge` / `InspectorHostActions`、Steam 入口与 Steam Web inspector；视频库、图片库、在线库下载 inspector 内容文件已不再 `import SwiftUI`。

### 阶段 5：SwiftUI 依赖清零与文档同步

目标：

- 删除所有 `import SwiftUI`。
- 删除 SwiftUI-only helper、modifier、bridge。
- 更新 README、Help Book、架构文档中“AppKit / SwiftUI 混合”的表述。

验收：

- `rg -n "SwiftUI|NSHosting|NSViewRepresentable|ViewModifier|@State|@ObservedObject|@EnvironmentObject|@Binding|some View" MyWallpaperX README.md MyWallpaperXHelp docs/history/architecture/framework-architecture-memo.md` 仅允许历史迁移文档中出现。
- Debug 构建通过。
- 手工走查：启动、主窗口、菜单、设置、四个模块入口、Inspector、Quick Look、状态栏、关闭/重开主窗口。

## 执行原则

- 每阶段只解决一个边界，不顺手重写模块内部。
- 优先复用现有 AppKit 容器和服务对象。
- 任何跨模块调用保持现有 Coordinator / Notification 方式。
- 每阶段结束必须跑构建，并记录残留 SwiftUI 清单。
- 若某个 SwiftUI 视图同时包含业务状态与 UI，先把业务状态迁回服务或 AppKit controller，再替换 UI。
