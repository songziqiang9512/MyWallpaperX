# MyWallpaperX AppKit 全量迁移计划

<!-- document-role: active-plan -->

> 状态：现役迁移目标与剩余工作入口
>
> 最近核对：2026-10-17（SwiftUI 残留与 Steam 预览职责）。下文各阶段的“当前进展”保留 2026-05-17 批次记录；当前残留以本节清单和代码扫描为准。
>
> 长期权威：本计划与[技术栈与架构路线边界](technology-stack-boundaries.md)共同确定最终 UI 为 Swift + AppKit。迁移完成前只维护下列 SwiftUI 残留，不新增 SwiftUI 产品面、设置页、桌面宿主或 hosting bridge；若要改变 0 SwiftUI 目标，必须先修改长期技术路线，而不是在功能批次中隐式扩张。

目标：最终交付一个 0 SwiftUI 的 macOS 原生 AppKit 应用。应用结构以邮件类客户端为参照：左侧原生 source list，右侧模块内容区，顶部统一 NSToolbar，详情/信息面板由 AppKit inspector overlay 或 panel 承载。

## 当前判断

截至 2026-10-17，App 生命周期、主窗口 Shell、主菜单和主要网格均已由 AppKit 承担，但 SwiftUI 尚未清零。当前 `import SwiftUI` 只剩 2 个文件：

- `Shared/UI/InspectorHostBridge.swift`
- `Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSupportViews.swift`

Scene 属性窗口与诊断详情已迁为 AppKit；剩余工作集中在共享 inspector bridge 和 Steam Workshop 详情辅助 UI。迁移仍应按这些边界逐项替换并验证，不需要重写已完成的 AppKit Shell 或网格。

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

### Steam 缩略图状态与资源寿命

2026-10-17 设计：网格默认静态、悬停播放，详情打开播放；两者共用每视图一个 `SteamWorkshopPreviewState`，只投影预览状态，不取得壁纸 runtime 或共享缓存的权威。当前两份加载分支会在 GIF 退出且缓存未命中时清空图片，详情重建也会重启加载；以共同状态替换它们，不增加另一份缓存或网络调度器。

- 数据流：已下载记录的本地 preview 优先于远程元数据 URL → 原 `ThumbnailCache` / request coordinator → 静态就绪 → 可选临时 GIF → 原 `NSImageView`。本地图片按可解码尺寸接纳，近黑启发式只用于静态帧挑选和视频候选，不把合法黑图判成丢图。
- 订阅／在线浏览卡片与邻近预取共用本地来源选择；缺失或损坏的本地预览回退远程。Steam 按显示像素档生成静态 PNG，原动画字节另键保留；暖盘只读派生图，不重复扫描 GIF。方形 aspect-fill 按方向后的双轴选像素，保原最长边 800 上限；超过该上限的原有清晰度限制不作新增放大解码。
- 各现有缩略图 owner 的解码图层共用有界 LRU 容器，预算不增加，压力事件释放；不常驻轮询，不承诺全库图常驻。内存就绪同步回显，淘汰后后台读取派生磁盘图；Video 派生资产存在性／失效校验保留。在线库请求从联网前携带发布代次，清理后的旧可见／预取回包不得重写缓存；Steam 双文件发布仍受同一请求代次、取消与失效门约束。
- 下载队列封面只消费同一静态解码缓存，不通过默认 NSImage 解码将原始 GIF 写回静态内存预算。共享 cache 持有异步 producer 和消费者租约：退出只撤销本消费者，最后消费者退出才取消 producer；不把单卡 token 传入合并网络 loader。无取消语义的既有消费者固定保活，旧任务完成不得提交到同 key 的新一代；落盘先写私有临时文件，再在短锁内复核 producer 并原子发布。显式失效同时撤销 image/raw/raw-prefetch 的缓存发布权，仍允许既有消费者接收结果，编码／暂存与 trim 在请求锁外，显式失效删除与原子发布在锁内串行。既有 coordinator 继续拥有网络并发/超时，取消需及时释放活跃槽。
- 每视图保留当前静态图，GIF 仅在激活期间持有；退出、隐藏立即恢复静态图，缓存淘汰不影响已显示内容。失败或非动画源保留静态图；动画解码在后台串行执行，交付回主线程。
- 图片候选按本地 → 远程 → 视频尝试；已下载显示投影中的本地 URL 不遮蔽原始 record.browserItem 的远端候选，动画使用实际成功来源；请求身份含各候选的内容键与刷新版本，本地键含设备/inode、mtime 和 size，覆盖稳定路径的原子版本替换。同身份配置无副作用，切换/复用推进代数；仅后备变化时保留仍属于当前候选的成功图，主图已就绪时不重启加载。迟到回调只可提交给原代数。
- loading/失败占位只在没有当前可用图时显示；自动重试有时间边界。资源不变的元数据、订阅和 Scene 启动通知不得重新触发解码；不同资源不能借用旧图。
- 旧网格和详情的独立加载/动画状态同时退出；无调用者的 SwiftUI preview wrapper 删除。验收使用真实 GIF/静态图片、缓存移除、重复配置、快速进出、A→B→A 迟到、刷新失败与跨消费者场景，另做 Debug 构建和隔离 AppKit 运行；不把通知模拟等同于真实 Scene 负载或线上 Steam 验收。

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
