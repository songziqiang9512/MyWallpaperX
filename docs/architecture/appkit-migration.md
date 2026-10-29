# MyWallpaperX AppKit 全量迁移计划

<!-- document-role: active-plan -->

> 状态：现役迁移目标与剩余工作入口
>
> 最近核对：2026-10-25（统一主窗口装配与旧源 UI 退出，整体验收仍待专项）。下文保留 2026-05-17 批次记录；当前源码状态以下节为准，静态扫描不代替 UI 验收。
>
> 长期权威：本计划与[技术栈与架构路线边界](technology-stack-boundaries.md)共同确定最终 UI 为 Swift + AppKit。迁移完成前只维护下列 SwiftUI 残留，不新增 SwiftUI 产品面、设置页、桌面宿主或 hosting bridge；若要改变 0 SwiftUI 目标，必须先修改长期技术路线，而不是在功能批次中隐式扩张。

目标：最终交付一个 0 SwiftUI 的 macOS 原生 AppKit 应用。应用结构以邮件类客户端为参照：左侧原生 source list，右侧模块内容区，顶部统一 NSToolbar，详情/信息面板由 AppKit inspector overlay 或 panel 承载。

## 当前判断

2026-10-22 源码核查：App 生命周期、Shell、菜单、网格、Inspector、Scene 属性窗口与 Steam 详情均已走 AppKit。最后两个 SwiftUI 文件中的 bridge 与详情辅助组件没有产品消费者，现已退役；`InspectorHostPresentation` 仍供 AppKit 使用并保留。产品源码的 `import SwiftUI`、`NSHostingView` 与 `NSHostingController` 已清零。此结论只说明源码依赖；构建与实际操作验收归[代码精简专项](../development/code-slimming-program.md)，主窗口后续统一改造的实施与验收归[播放列表专项](../development/main-window-playlists-redesign.md)，下述历史批次不定义当前 owner。

## 最终结构

### App 层

- `main.swift` 创建 `NSApplication`，设置 `AppDelegate`，调用 `NSApp.run()`。
- `AppDelegate` 只负责应用生命周期、Help Book、状态栏、主菜单安装、启动阶段调度。
- 主菜单用`NSMenu`/`NSMenuItem`与`NSMenuItemValidation`；浏览取来源选择，文本/sheet优先，普通action无check AX值。关闭从first responder沿`tryToPerform`派发`performClose:`，交NSPopover/无边框sheet。
- 设置窗口使用 `NSWindowController + NSViewController + AppKitSettingsContainerView`；无关状态回填保留当前原生field editor草稿，模式禁用则撤销，失焦沿原提交；背景只消费主窗已投影色与动画决策，共用原0.75 s原生过渡；隐藏只记呈现值、可见消费点一次准入，首show/原生模式即时，不串层读取或重复采样。

### Shell 层

- 主窗口内容控制器为 AppKit `NSSplitViewController`。
- 左侧为 `WallpaperLibrarySidebarController`，使用 `NSOutlineView` source list 样式。
- `WallpaperLibraryWindowComposition` 装配统一 Grid、列表目录与原远端浏览；`AppKitDetailHostViewController` 仅挂载子控制器。
- `WallpaperLibraryPresentation` 持有页面/query/selection；App Commands、InspectorCoordinator 分别处理固定引用命令、QL/详情；旧 `SelectedItem` 及源选择槽已退役。
- Shell 不持有 SwiftUI `Binding`、`@State`、`@EnvironmentObject`。

### 模块层

- 本地/下载/关系内容共用 `WallpaperLibraryGridController`，`WallpaperLibraryCellAdapter` 复用各来源卡片和唯一缓存；原浏览页继续由各远端服务分页；仅在线浏览装配原生下拉刷新，本地无刷新任务。图片/视频“打开方式”由共享NSWorkspace菜单查询系统handlers并持固定文件目标，无应用目录扫描。
- 模块保留导入、元数据、下载、文件与引擎职责；源旧 Grid/Toolbar/QL 与 tag/favorite/recent 写侧退出，历史输入解码仍供迁移使用。
- App Workspace 连接唯一 Catalog、Store 与 Manager 原播放票据；共享值跨层，不在 Shell 重建服务或媒体索引。

### Inspector

- `InspectorHostStore`、`InspectorHostRequest`、mount notification 机制保留。
- SwiftUI `InspectorHost` 替换为 AppKit panel view。
- SwiftUI `InspectorHostBridge` 替换为模块侧显式监听/请求：
  - 选中项出现：发起 inspector open。
  - inspector present：mount 模块提供的 `NSView`。
  - 选中项清空：发起 inspector close。
- 各模块 inspector 内容改为 AppKit `NSView`。

### Steam 缩略图状态与资源寿命

网格默认静态、悬停播放，详情打开播放；两者复用每视图一个 `SteamWorkshopPreviewState`，只投影预览状态，资源、缓存与网络仍由原 owner 管理。

- 数据流：已下载记录的本地 preview 优先于远程元数据 URL → 原 `ThumbnailCache` / request coordinator → 静态就绪 → 可选临时 GIF → 原 `NSImageView`。本地图片按可解码尺寸接纳，近黑启发式只用于静态帧挑选和视频候选，不把合法黑图判成丢图。
- 订阅／在线浏览卡片与邻近预取共用本地来源选择；缺失或损坏的本地预览回退远程。Steam 按显示像素档生成静态 PNG，原动画字节另键保留；暖盘只读派生图，不重复扫描 GIF。方形 aspect-fill 按方向后的双轴选像素，保原最长边 800 上限；超过该上限的原有清晰度限制不作新增放大解码。
- 各现有缩略图 owner 的解码图层共用有界 LRU 容器，预算不增加，压力事件释放；不常驻轮询，不承诺全库图常驻。内存就绪同步回显，淘汰后后台读取派生磁盘图；Video 派生资产存在性／失效校验保留。在线库请求从联网前携带发布代次，清理后的旧可见／预取回包不得重写缓存；Steam 双文件发布仍受同一请求代次、取消与失效门约束。
- 下载队列封面只消费同一静态解码缓存，不通过默认 NSImage 解码将原始 GIF 写回静态内存预算。共享 cache 持有异步 producer 和消费者租约：退出只撤销本消费者，最后消费者退出才取消 producer；不把单卡 token 传入合并网络 loader。无取消语义的既有消费者固定保活，旧任务完成不得提交到同 key 的新一代；落盘先写私有临时文件，再在短锁内复核 producer 并原子发布。显式失效同时撤销 image/raw/raw-prefetch 的缓存发布权，仍允许既有消费者接收结果，编码／暂存与 trim 在请求锁外，显式清缓存仅在原锁内摘除旧namespace并重建，后台维护队列删除退役目录，避免递归I/O阻塞主线程或误删新写入；与原子发布仍串行。既有 coordinator 继续拥有网络并发/超时，取消需及时释放活跃槽。
- 每视图保留当前静态图，GIF 仅在激活期间持有；退出、隐藏立即恢复静态图，缓存淘汰不影响已显示内容。失败或非动画源保留静态图；动画解码在后台串行执行，交付回主线程。
- 图片候选按本地 → 远程 → 视频尝试；已下载显示投影中的本地 URL 不遮蔽原始 record.browserItem 的远端候选，动画使用实际成功来源；请求身份含各候选的内容键与刷新版本，本地键含设备/inode、mtime 和 size，覆盖稳定路径的原子版本替换。同身份配置无副作用，切换/复用推进代数；仅后备变化时保留仍属于当前候选的成功图，主图已就绪时不重启加载。迟到回调只可提交给原代数。
- loading/失败占位只在没有当前可用图时显示；自动重试有时间边界。资源不变的元数据、订阅和 Scene 启动通知不得重新触发解码；不同资源不能借用旧图。
- 旧网格和详情的独立加载/动画状态同时退出；无调用者的 SwiftUI preview wrapper 删除。验收使用真实 GIF/静态图片、缓存移除、重复配置、快速进出、A→B→A 迟到、刷新失败与跨消费者场景，另做 Debug 构建和隔离 AppKit 运行；不把通知模拟等同于真实 Scene 负载或线上 Steam 验收。

### 网格缩略图需求调度（D17，2026-10-21）

- 六类网格共享需求与AppKit响应式滚动；滚轮观察转交`super`，保持scroll／clip／document兼容及GIF退让，不接管惯性或另造时钟。cache 不增预算、不改作者图像／动画、不建平台。阶段与结果见[Apple silicon执行方案D17](../development/apple-silicon-optimization-plan.md#d17全模块网格缩略图调度审查与下一批顺序)。
- 网格把视口变化合并为一次短时调度，按可见与滚动方向选择有界近邻；返回／反向／缩放重算来源和用途，不按列表头截断邻域。每类网格只持有一份预取consumer集合，切分类、隐藏、删除、源变化或离屏时撤销旧集合；原生prefetch回调只是同一集合的输入，旧第二预取owner退出。
- `ThumbnailCache`持有本地／Steam预览的共享请求与原子落盘；显式全清一次清 image、负结论及本 namespace 磁盘，旧任务保回调但不能回填，成功覆盖旧失败。UI源身份 memo 不拥有失败裁决；普通图片consumer可取消，沿同键producer合并，visible需求可提升尚未开始的prefetch。取消一个不影响其他consumer，最后一个撤销后排队工作不执行，已进入不可抢占解码的结果不得发布；既有无取消调用保持保活兼容。短磁盘读取／解码2槽、媒体生成1槽、异步来源4槽（其中prefetch最多2槽），各槽包含其结果交接／落盘；入场类别固定，不因途中升降级错误退还配额。已运行任务不强行抢占，可见请求仍可能短暂等待。
- 在线原pipeline独占网络和解码：网络与按来源／像素档的解码分别合并、有界；消费者退出逐个结算，最后退出撤销下载／排队解码，预取被可见消费时可提升。取消不是坏图或失败负缓存；clear代次从请求开始贯穿读取、解码和落盘。不存在“actor内await所以天然串行解码”的假设。
- raw／still仍先在原请求代次内原子发布；将可见完成从非关键磁盘trim中解耦，trim合并低优先执行。不提前让GIF消费者看到尚未可复用的原始数据。不同来源版本不得借旧图；本批不增加跨档旧图捷径。Pixabay下载项取图依据后台取得的当前来源键，扫描提示不授权旧图；暖命中不重复解码。换源沿原 producer 读前后边界结算，活跃消费者仍收到不可缓存终态，不借其取消吞掉完成。
- 选择／播放bar／元数据只改必要UI，同需求不清有效图；无图才显加载／失败，暖盘可延迟但绑定请求、复用撤销、失败可见，不借其他卡旧图。保取帧质量、清缓存／重试。Video可见源与缩略图检查共用后台单flight；主线程按当前可见ID／路径接纳，补建校验缩略图路径，保变化检测。
- 每阶段先执行真实owner的取消／共享、优先级、clear迟到、反向／换档／源替换、坏图回退和GIF／播放bar反例，再做相称Debug构建、独立审查与签名Release实际操作；不加Release常驻探针、不以占位文字消失代替FPS证据。若某候选需要扩大长期状态或无法闭合失效，保留已证局部收益并单独记录STOP。

### 网格卡片减负试用版（2026-10-23）

- 目标：减少进入视口时的隐藏控件构建与滚动中的鼠标跟踪工作，保持原生集合复用、现有样式和点击／右键／键盘／辅助功能；不迁移SwiftUI、不加缓存预算或Release探针。
- 沿原`WallpaperGridScrollView`滚动态统一撤下卡片的hover tracking area，结束后按当前可见区域恢复；新进入／复用卡片在布局时同步当前滚动态。实际同步右键菜单期间保源卡缩放，调用返回后恢复当前真实指针；纯菜单工厂不改变网格状态，不增通知代理冻结链。不移除集合选择/拖动，不禁命中测试，不另设滚动时钟。
- Video与在线下载的播放徽章按第一次实际显示创建，随后随原item复用；尺寸即使徽章尚未创建也保留计算，播放／多选／复用仍由原状态决定。不可用隐藏控件作为辅助功能唯一入口。
- Steam仅在预览像素档实际改变时因布局重新配置图片；模型配置、显式重载和源版本校验保持原链。不同来源或清缓存不得借旧图；本版不重开D17 B3的路径代替版本捷径。
- Steam近邻预取的文件版本检查移到串行utility队列，每个网格只允许一批检查在途，后续视口合并为最新快照；返回主线程只接纳仍在当前需求中、来源和像素档一致的条目。隐藏／退出递增生命周期代次并取消租约，迟到检查不能重建需求。保留完整文件指纹，实际loader继续独占取数、解码和发布，不新增路径缓存或版本owner。
- Steam不显示的玻璃bar移出窗口视图树，显示前挂回；保留原玻璃、按钮和布局，收起动画结束才移除，旧动画完成不能移除已重新显示的bar。播放／启动／下载常驻、多选、辅助操作仍由原卡片状态决定。
- 失败／退出：滚动结束、换窗与复用恢复原跟踪语义；懒建徽章取当下播放状态和最新几何。原图片loader、取消与失效owner不变；若局部改法无收益或破坏交互，撤回对应片段，不扩张为第二资源管理层。
- 验收：真实AppKit窗口覆盖惯性衔接、新卡进入、复用、首次hover／播放、多选、缩放和点击；保图片迟到／清理反例，Debug与Release构建、独立审查及新版实际操作。只认结构工作量减少与已测行为，不预认120Hz或整App性能提升。

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
- 2026-10-22 核查：共享 Inspector 由 `InspectorHostViewController` 承载，Steam 浏览／下载由 AppKit 视图直接承载，无 hosting controller。

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
- 2026-05-17：在线库浏览入口已改为 AppKit `PixabayBrowserView`，API key、loading、空态、错误态和下载完成提示均由 AppKit support view 承载。
- 2026-05-17：在线库下载入口已由 `AppKitDetailHostViewController` 直接承载 `AppKitOLDownloadsContainerView`，`OnlineLibraryDownloadsView.swift` 已删除。
- 2026-10-22 核查：Steam 浏览／下载、登录与详情均有 AppKit 入口；未接入的 SwiftUI 详情 helper 已删除。

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
  - `PixabayDownloadsInspectorView.swift` / `PixabayDownloadsInspectorSupport.swift`
- 2026-05-17：`AppKitDetailHostViewController` 负责视频库、图片库、在线库下载 inspector 的 open / mount / close，同步仍通过 `InspectorHostActions` 与通知边界。
- 2026-10-22 核查：共享 `InspectorHostStore` 与通知请求继续由 AppKit 宿主消费；无消费者的 SwiftUI bridge 及其私有 hosting/观察状态已删除。
- Steam 详情、Web 属性、登录与在线库 toast／alert／sheet 已采用 AppKit；完整操作验收仍按阶段 5 执行。

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
