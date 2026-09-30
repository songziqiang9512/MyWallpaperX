# UI 代码全面审查报告（2026-09-30）

- 截止日期：2026-09-30
- 类型：cross-topic 静态审查记录（App / Shell / Shared / Modules UI / Web 壁纸宿主）
- 独有价值：全仓 UI 代码 163 个 Swift 文件、12 个区域并行评审后，经逐条独立复核的 41 条问题清单与完整证据（1 high / 20 medium / 19 low / 1 存疑）
- 当前权威：当前代码；各条修复进展以工作树与提交历史为准，本文件不决定后续任务顺序

## 审查方法与范围

- 范围：`MyWallpaperX/` 下 163 个 UI 相关 Swift 文件，分 12 个区域：App 窗口与生命周期（13）、App 调试窗口（20）、主窗口 Shell（8）、共享 UI 组件（19）、设置面板与共享模型（6）、视频库 UI（8）、静态图库 UI（8）、在线库 UI（12）、Steam 工坊 UI（13+18）、Web 壁纸宿主视图（19+19）。
- 方法：每个区域由独立评审员只读评审（主线程违规、引用循环与 observer/timer 泄漏、窗口生命周期与异步回调、AppKit 陷阱、状态一致性、数据竞争、错误吞没、内存增长八个重点），每条发现再由未参与原审查的复核员重读代码独立核实：确认、给出反证驳回、或标注静态无法判定。
- 性质：静态只读审查。未运行应用、未构建、未跑测试；运行时行为、视觉效果与交互手感无法由此发现。非 UI 代码（Scene 渲染引擎、Core/Playback 播放核心、Steam 网络与下载层、守护进程）不在范围。
- 修复执行：2026-09-30 起由「UI 代码全量修复」工作流按本文 F01–F41 编号逐条修复并复核；修复结果以工作树与提交历史为准。

## 总体结论

共审查 163 个 UI 相关 Swift 文件（12 个区域）。原始发现 41 条，其中 40 条经独立复核确认；去重合并后 41 条，已确认的高严重度问题 1 条。41 条发现全部经独立复核（40 条 verified、1 条 unconfirmed），无崩溃或数据丢失级问题；唯一的 high 是 Web 宿主注入脚本的 attachShadow 包装器作用域错误，令使用 Shadow DOM 的壁纸整页脚本中断，属功能明显破坏。整体健康度：功能链路基本完整、多数缺陷有自愈或替代路径，但工程细节粗糙——medium 集中在主线程同步 IO、列表/面板缺重用缺缓存缺节流、状态只靠一次性事件不回放三大反模式，影响随数据量与使用时长线性放大。最该先修 F01（一处作用域修复即消除整页破坏），随后按主题批量处理吞错组（F17、F18、F24、F25）与主线程 IO 组（F03、F04、F37），同模式问题可用统一模式一次消除。

## 系统性主题

1. **主线程同步 IO**：导入、随机文件枚举、loopback 启动等路径在主线程做目录枚举、磁盘 stat、图片解码，本地 SSD 无感、慢速卷或大目录上卡顿冻结，影响随数据量放大（F03、F04、F36、F37 等）。
2. **列表/面板缺重用、缺缓存、缺节流**：视频库网格零重用、缩略图无内存缓存、在线库进度回调无节流、Steam 预览缓存无字节上限，滚动/下载/长会话场景性能退化（F11–F14、F33 等）。
3. **状态只靠一次性事件、不回放**：播放角标、activeModule、媒体节点音量等状态靠一次性事件恢复，切模块/切壁纸/动态创建节点后失真，直到下次交互才自愈（F10、F15、F29 等）。
4. **吞错**：下载失败弹窗吞并发错误、SMAppService 失败只 NSLog、缩略图失败静默、空标签选择器静默返回（F16、F18、F24、F25）。

---

## 已确认的问题

### High

#### F01 · attachShadow 兼容包装器作用域错误，Shadow DOM 壁纸整页脚本中断

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeMedia.swift:185`
- 问题：attachShadow 兼容包装器引用了其作用域外的 installWallpaperShadowObserver，任何主帧使用 Shadow DOM/Web Components 的壁纸页面每次调用 attachShadow 都抛未捕获 ReferenceError：shadow root 已被创建但页面拿到 undefined，初始化语句失败、整页脚本中断、壁纸无法渲染。
- 证据（含复核结论）：复核用 node vm 按真实装配顺序拼接全部 15 个脚本段（167,364 字符，语法解析通过）在 stub 环境求值后调用 Element.prototype.attachShadow，稳定复现 "ReferenceError: installWallpaperShadowObserver is not defined"，且 DOMContentLoaded 手动触发后仍复现、typeof 全局该名为 undefined，排除 TDZ/时序解释。作用域事实：该标识符唯一声明于 +DOMLifecycleMutation.swift:2，位于 MediaObservers 打开的 DOMContentLoaded 回调作用域内（+DOMLifecycle.swift:6-10 拼接、Pointer 段 :28 才闭合），包装器在回调外（WebWallpaperHostTypes.swift:330-336 拼接顺序）；脚本注入为 atDocumentStart 单 WKUserScript（+Surface.swift:50-62）先于页面脚本；安装处 try/catch（:179-190）不覆盖调用时错误。high 恰当：受影响壁纸整页功能性破坏。
- 状态：verified / high

### Medium

#### F02 · Web 宿主未实现导航策略，外链点击可替换桌面甚至拆除壁纸

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift:181`
- 问题：Web 壁纸宿主未实现 decidePolicyFor 导航策略，页面内任意导航被放行：点击可交互壁纸中的外链后桌面被外部网页替换，目标加载失败则 failCurrentLaunch 拆除全部 surface、整张壁纸退出。
- 证据（含复核结论）：grep Core/SteamWorkshopWeb 无 decidePolicyFor，WebKit 默认放行；瞬态鼠标捕获（InputForwarding.swift:277-280、Surface.swift:238-241、WebWallpaperHostTypes.swift:175-178）使 a[href] 受信点击可达 WKWebView；失败错误码不在 ignoredNavigationFailureCodes（NavigationDelegate.swift:5-7），:181 走 failCurrentLaunch→teardownHostSurfaces，引擎侧清空 currentWallpaper。复核修正：失败后回到系统桌面或被保留的 video runtime，非字面「黑屏」；页面 JS 自行 location.href 外跳同被放行。需壁纸含外链+用户点击故 medium；该适配器为生产 Web host（WallpaperEngine.swift:73 装配）。
- 状态：verified / medium

#### F03 · 图片库导入在主线程同步枚举与读元数据，大文件夹导入冻结数秒

- 位置：`MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift:498`
- 问题：图片库导入在主线程同步递归枚举目录、逐文件读 CGImageSource 元数据并做 O(新×已有) 全库去重比较，大文件夹导入时主窗口冻结（beachball）数秒且无进度反馈。
- 证据（含复核结论）：beginSheetModal 回调（:531-534，AppKit 保证主线程）同步调 importImages；:469-472 主线程枚举、:484 逐文件 fileExists、:498 每个新文件走 SILWallpaper init:46-53 的 CGImageSource 属性读取。复核补充加重项：:486 重复检查对每个新文件全库扫描且每次做两次 resolvingSymlinksInPath（含文件系统调用），:509 save() 也在主线程；同类读取在 :578/:151 有意放后台队列，唯独导入在主线程，属遗漏非设计。只读复核未实测冻结时长。
- 状态：verified / medium

#### F04 · randomFileURL 主线程同步枚举整棵目录树，随机请求阻塞主线程

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift:270`
- 问题：randomFileURL(in:) 在主线程同步递归枚举整个目录树并物化全部文件 URL 后才取随机值，声明 directory 属性的壁纸（图片墙/音乐墙）每次随机请求都阻塞主线程，大目录或慢速卷上达数百毫秒到秒级，鼠标转发、音频频谱与整个 App UI 全部停顿。
- 证据（含复核结论）：:270-287 enumerator 无提前终止、:279-284 compactMap 全量收集；Lifecycle.swift:317-330 在 WKScriptMessageHandler 主线程回调内同步调用；window.wallpaperRequestRandomFileForProperty（BootstrapResourceRewriting.swift:364-409）为页面公开 API，无节流无缓存；仓库已有后台枚举+快照缓存机制（DirectorySync.swift:32-52）完全未复用，证明是可修复的偏离而非必要设计。
- 状态：verified / medium

#### F05 · Cmd+←/→ 菜单键等价无文本编辑防护，编辑时劫持光标键切换壁纸

- 位置：`MyWallpaperX/App/AppDelegate.swift:54`；`MyWallpaperX/App/MainMenuBuilder.swift:164-173`
- 问题：「切换下一张/上一张」的 Cmd+→/Cmd+← 菜单键等价在菜单验证中对文本编辑状态无防护，在任何可编辑文本框（搜索框、新建/重命名标签对话框）按 Cmd+方向键会劫持标准光标移动键并意外切换壁纸。
- 证据（含复核结论）：MainMenuBuilder.swift:164-173 设键等价（默认 [.command]），AppDelegate.swift:53-57 对这两项无条件 return true；同文件 65-75 对「全选/删除选中」有 textViewFirstResponder/editableTextViewFirstResponder 防护，唯独漏这两项；切换链（AppDelegate.swift:320-322→MainWindowCoordinator.swift:88-90→CrossRuntimeWallpaperNavigator.swift:18-64）不感知文本编辑状态，真实 requestSetAsWallpaper；QuickLook 面板打开时（ContentViewSupport.swift:128-131 对带修饰键事件返回 false 交回菜单链）同样命中。复核逐点确认全链属实，静态证据闭环（未运行 GUI 复现按键分发）。
- 状态：verified / medium

#### F06 · inspector 隐藏动画过期 completion 无 generation 检查，快速重开面板被隐藏

- 位置：`MyWallpaperX/Shell/AppKitMainSplitView.swift:575`
- 问题：inspector 隐藏动画的 finishHide 完成块无 generation 检查且不可取消（pendingOverlayHideWorkItem 从未被调度，:534 的 cancel 是死代码），0.24s 隐藏窗口内重新打开 inspector 会被过期 completion 隐藏并清零宽度，面板不可见不可交互且与 store 状态不一致，直到下次打开才恢复。
- 证据（含复核结论）：hide 实际用 NSAnimationContext completionHandler（:585-593）调 finishHide（:575-583，无条件 isHidden=true+宽度清 0）；同文件 handleInspectorClose（:389-401）对 store 侧 completion 专门有 inspectorTransitionGeneration 防护，视图侧漏加——该防护的存在本身佐证过期 completion 会触发。复核逐环核实触发链（点暗区关闭→0.24s 内点卡片 B→open 链全无防护无恢复路径），且触发面比原述更宽（scrollWheel 也触发关闭 :655，SIL/在线下载模块的 sync 同走此 open 路径）。实验依据为 probe 设计+AppKit 事务 completion 语义，复核未亲跑 probe。
- 状态：verified / medium

#### F07 · SIL 方向键导航不感知标签上下文，选择跳到网格外壁纸

- 位置：`MyWallpaperX/Modules/StaticImageLibrary/Core/SILService.swift:403`
- 问题：SIL 方向键导航始终在全库 sortedWallpapers 上移动 selectedID，不感知 currentContextTag——标签视图中按方向键会把选择静默移到网格不存在的壁纸：网格失去全部高亮，inspector（副标题仍显示当前标签名）与 QuickLook 切到标签外壁纸。
- 证据（含复核结论）：:403 `let list = sortedWallpapers` 仅 guard isMultiSelectMode；currentContextTag（:103）全库 4 处使用均不参与导航过滤；调用点 SILGridItemView.swift:96、SILQuickLookController.swift:68（QL 路径确定可达）。复核确认 $selectedID 订阅不重建网格数据（AppKitDetailHostViewController.swift:87-98），updateSelectionVisualsIfNeeded 对新 ID 直接 continue（SILGridContainerView.swift:321）致网格零高亮；删除作用域仍正确用 currentContextTag（MainWindowCoordinator.swift:295-298），无数据风险。
- 状态：verified / medium

#### F08 · 下载页 QuickLook 方向键只移网格选择，预览画面不跟随

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsSupport.swift:103`
- 问题：在线库下载页 QuickLook 打开后接管方向键只移动网格选择，预览面板画面不跟随——网格高亮移动了，预览停在原视频，QuickLook 内方向键浏览这一核心交互失效且行为反直觉。
- 证据（含复核结论）：previewPanel(_:handle:)（:103-107）接管 123-126 键码只调 moveSelection+panel.reloadData() 后 return true；OLDownloadsQuickLookController 的 previewIDs/activeIndex 仅 open 时写入（:46-58），currentPreviewItemIndex 不变则 didChange 不触发；复核 grep 全仓确认不存在网格选择→面板索引的任何同步写入。复核修正措辞：selectionSync 实际是 QuickLook→网格方向，被绕过后没有任何反向同步让画面跟随。
- 状态：verified / medium

#### F09 · 全新安装重置绕过选中通知，activeModule 残留旧模块路由错乱

- 位置：`MyWallpaperX/Shell/AppKitMainSplitView.swift:280`
- 问题：handleFreshInstallReset 切回视频库时不发三个模块的 ModeDidChange(enabled:false) 也不发 moduleDidBecomeActive，activeModule 残留旧模块——Space/Esc 走错分支、performZoom 路由到旧工具栏、Steam 弹层不关、菜单路由残留，直到点侧边栏其他节点才恢复。
- 证据（含复核结论）：:280-286 直接赋值绕过 setSelectedItem（:90-96），连 syncManagerSelection 的通知路径都不经过；三个 Mode 通知全仓唯一发布者是 syncManagerSelection（:193-242），MainWindowController.activeModule 仅由其更新且不监听 reset 通知（MainWindowController.swift:95-176）；reset 链（AppKitSettingsView.swift:826-837→WallpaperManager+Persistence.swift:500-586）全程不发 Mode 通知。复核补充更糟点：已把 selectedItem 设为 .category(.myWallpapers)，点回当前已选节点被 :91 guard 短路，修复应复用 syncManagerSelection 通知序列（含 enabled:false 广播）。
- 状态：verified / medium

#### F10 · 下载页播放角标靠一次性事件恢复，切模块后丢失

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsGridView.swift:25`
- 问题：下载页容器每次切换模块都被重建，currentPlayingNormalizedPath 初始 nil 且只靠 setAsWallpaper 时发出的一次性事件恢复（事件不重放），设壁纸→切走→切回后正在播放视频的播放角标丢失。
- 证据（含复核结论）：:25 初始 nil，唯一外部更新源 .onlineDownloadsPlaybackPathDidChange（:221-231）仅由 WallpaperManager+WallpaperApplication.swift:35-39 发布；AppKitDetailHostViewController.swift:39-48/:163 每次切换新建容器；setup() 无任何从可查询状态 WallpaperManager.effectiveCurrentWallpaper（WallpaperManager.swift:87-89）初始化的代码。复核闭合全链：角标丢失（AppKitOLDownloadsItem.swift:193/:655-658 为真实可见 UI）直到下次壁纸切换自愈，常见序列必现。
- 状态：verified / medium

#### F11 · Steam 预览共享缓存无字节上限且存 1600px 解码位图，内存可达 GB 级

- 位置：`MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopPreviewImageSupport.swift:6`
- 问题：工坊预览共享缓存按 320 张封顶、无字节上限，且解码为最高 1600px 的 RGBA 已解码位图（单张最高约 10MB），网格条目、详情大图与下载面板行封面共用，长会话浏览后内存驻留可达数百 MB 至 GB 级。
- 证据（含复核结论）：ThumbnailCache 只设 countLimit、全文件无 totalCostLimit（grep 零匹配）；steamWorkshopRGBAImage 输出 makeImage() 已解码位图（SteamWorkshopPreviewImageSupport.swift:138-176）；消费方 AppKitSteamWorkshopBrowserItem+Presentation.swift:495、SteamWorkshopItemDetailPreviewSupport.swift:97-102/:214-219、SteamWorkshopDownloadTasksPopover.swift:572/:578 共用同一缓存同一解码器；removeAll 仅设置页手动触发。复核修正量级：NSCache 超 countLimit 也会逐出；典型 1600×900 满载≈1.8GB、800×450 满载≈0.46GB，GB 级为近满载 worst case——有张数上限与系统压力逐出兜底故 medium 不升。
- 状态：verified / medium

#### F12 · 视频库主网格零重用，滚动/搜索每张新卡片整棵重建视图树

- 位置：`MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView.swift:125`
- 问题：视频库主网格 diffable cellProvider 直接 new AppKitWallpaperItem，未 register 也未走 makeItem 重用队列：零重用，滚动/搜索/收藏/缩略图就绪每条路径都对每个新进入视口的卡片整棵重建视图树（13 子视图+38 约束+tracking area），prepareForReuse 清理逻辑永不执行。
- 证据（含复核结论）：全模块 grep 无任何 register/makeItem 调用；局部 reload 走 reloadItems（:552/:560/:579 等）重新走 cellProvider；占位符「生成中...」1-2 个 runloop 闪烁。复核修正一处夸大：diffable apply 按 identifier diff，id 不变的幸存卡片不因 apply 本身重建，重建发生在换血后新进入视口的卡片——零重用核心主张完全成立；同仓库 SILGridContainerView.swift:368/:80 标准重用模式反证这是写法偏差而非平台限制。无正确性缺陷（configure 全量覆盖），但这是主网格高频界面。
- 状态：verified / medium

#### F13 · 视频库缩略图无内存缓存，prefetch 无效且与可见加载抢队列

- 位置：`MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridSupport.swift:194`
- 问题：视频库 AppKitThumbnailProvider 无内存缓存，prefetchThumbnail 读完即弃（{ _ in }），预取只做一次无效读盘；所有显示路径重复「串行队列读盘→主线程回调→绘制解码」，且预取与真实加载共享同一串行 decodeQueue，预取任务还会排在可见加载请求前进一步延长占位符。
- 证据（含复核结论）：loadThumbnail 每次磁盘 NSImage(contentsOfFile:)（:181-185）；prefetch :193-195 丢结果、cancelPrefetch :197-199 空实现；两条真实预取入口（+Interaction.swift:242-250、GridView.swift:892-928）与所有局部 reload（:552/:560/:579/:601/:639/:703/:766/:789/:842）都重复读盘；仓库现成 ThumbnailCache（含 NSCache+in-flight 去重+真 prefetch）仅 SIL/Steam/在线库在用，视频库未接入，修复路径清晰。复核微调：读盘有预热 page cache 的边际收益，「预取完全无效」在应用层成立。
- 状态：verified / medium

#### F14 · 在线库下载进度回调无节流，每 tick 全量重配置可见卡片并做磁盘 stat

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLBrowserGridView.swift:174`
- 问题：在线库下载进度回调无节流，每个 didWriteData tick 直写 @Published downloadProgressByID，浏览网格对每个值全量重配置所有可见卡片并触发整卡手动重布局，多文件并发下载时滚动明显掉帧、CPU 占用高。
- 证据（含复核结论）：OnlineLibraryService.swift:29-42 每块数据回调无节流、:357-359 直写 @Published 无相等性去重；容器 :172-175 无 debounce/removeDuplicates 地 reloadVisibleItems（:231-250）；卡片 configure 无条件 needsLayout=true（AppKitOLBrowserItem.swift:265），viewDidLayout :572-693 每次全量跑、:721 溢出时每次新建 CAGradientLayer。复核补充加重项：reloadVisibleItems 每次对每张未下载可见卡做主线程磁盘 stat（:252-258），即每 tick×每可见卡一次磁盘 I/O。
- 状态：verified / medium

#### F15 · 下载失败弹窗吞掉并发第二个失败，用户永远看不到

- 位置：`MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopBrowserView.swift:404`；`MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopDownloadsView.swift:213`
- 问题：下载失败弹窗展示期间到达的后续下载错误被 guard 拦下，弹窗关闭时又被无条件 downloadError = nil 一并清空——并发下载（上限 2）接连失败时第二个失败永远不会经模态弹窗呈现给用户。
- 证据（含复核结论）：浏览页 :403-404 guard + :415 无条件清空；下载页同构 :213/:224；downloadError 写入点众多（SteamWorkshopService+Downloads.swift:15/:431/:440/:488/:524 等），队列接连失败是常态。复核确认两种 sink/completion 交错顺序均丢失、两视图互斥 tab 无兜底、nil 触发的 sink 也被 guard 拦下。限定：失败原因仍可经下载任务 popover（SteamWorkshopDownloadTasksPopover.swift:471-473）与失败记录重试按钮看到，需用户主动打开，故 medium 不升。
- 状态：verified / medium

#### F16 · 属性面板键盘/VoiceOver 调滑块触发全量 rebuild，操作被打断

- 位置：`MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopWebPropertyEditorView.swift:406`
- 问题：属性面板滑块经键盘/VoiceOver 调节时（isTrackingMouse 恒 false，仅 mouseDown 置位）每次调整都提交并异步全量 rebuild 整个面板，正在操作的滑块被销毁、第一响应者丢失，键盘连续调节第一下后即被打断，构成可访问性交互缺陷。
- 证据（含复核结论）：:348-357 isTrackingMouse 仅 mouseDown 置位；:405-408 键盘路径每次 commitSliderValue→updateWebProperty（:265-268）→DispatchQueue.main.async rebuild；rebuild（:45）removeFromSuperview 全量重建且全文无 makeFirstResponder/keyViewLoop 恢复；对照鼠标路径有 isTrackingMouse+preview 保护至松手才 commit，键盘系非对称遗漏；service 层 updateWebPropertyValue（SteamWorkshopService+WebProperties.swift:72-115）无去重防重入。有鼠标变通故 medium；未构建运行，依据 AppKit 标准语义，静态链路完整无反证。
- 状态：verified / medium

#### F17 · 设置面板无差分全量回填，拖滑块掉帧

- 位置：`MyWallpaperX/Shared/Settings/AppKitSettingsView.swift:246`
- 问题：设置面板 refreshFromState 无差分全量回填，滑块拖动高频触发时每次重建 4 个热键下拉菜单（4×13 项）、同步查询 SMAppService.mainApp.status 并对整棵内容树做 fittingSize 探查，面板内拖动滑块可感知掉帧。
- 证据（含复核结论）：sink :422-427 对每次 settings 写入调 refreshFromState；:246 无条件 refreshHotkeyRows→:900-913 重建 52 项/次；:207 同步系统查询；:248→+Layout.swift:33-59→contentStack.fittingSize.height（:314）整树求解；偏移滑块每次连写 X/Y 产生两次 objectWillChange。复核实测（swift -e，darwin 27）NSSlider(value:minValue:maxValue:target:action:) 三组参数均返回 isContinuous=true，拖动按事件率连发 action 的触发前提实证；掉帧幅度未实测（静态推断），链路与触发频率已全部实证。
- 状态：verified / medium

#### F18 · SMAppService 失败只 NSLog，开机自启开关静默失效且持久化漂移

- 位置：`MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift:288`
- 问题：SMAppService register/unregister 失败只走 NSLog 吞掉，不回滚不提示：开发构建/非 /Applications 位置运行时「开机自启动」开关每次点击弹回 off 且无任何错误提示，持久化 startOnBoot=true 与系统未注册状态永久漂移。
- 证据（含复核结论）：:281-296 抛错仅 NSLog，全仓 SMAppService 仅此一处、无提示机制；面板按 status 回填（AppKitSettingsView.swift:204-210）开关弹回；$settings sink 防抖整份落盘（WallpaperManager+Persistence.swift:338-341）造成持久化漂移，用户每次点击重复该循环。复核修正措辞：UI 开关回填的正是系统真值（有意对账设计），真正漂移的是持久化值与系统状态，非字面「三方漂移」；register 失败在开发构建常见系 SMAppService 公开语义判断，未实机验证；生产签名+/Applications 通常不触发故 medium。
- 状态：verified / medium

#### F19 · 网络代理对非 UTF-8 响应体 base64 回填无编码标志，跨域媒体静默损坏

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift:508`；`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeLogging.swift:229`
- 问题：网络代理把非 UTF-8 二进制响应体转成 base64 文本回填且不带编码标志，fetch 代理的 Response 与 XHR 代理的 responseText/response 直接当文本用——壁纸跨域获取图片/字体/音频时渲染静默损坏，且 headers 原样透传（Content-Type 仍 image/png）使页面完全无从察觉。
- 证据（含复核结论）：宿主 :508 `String(data:encoding:.utf8) ?? base64EncodedString()`，成功 payload 只含 ok/status/headers/body 四键无编码标志；JS fetch 代理 :229-232 new Response(payload.body)、XHR 代理 :312-322 defineProperty 无条件覆写 response getter（设 responseType='arraybuffer' 也拿到字符串）；canProxyNetworkRequest 仅在原生 CORS 失败后放行跨域 GET/HEAD（:160-171，排除同源/localhost），宿主白名单来自壁纸元数据 externalDependencyHosts。复核修正：String(data:encoding:) 失败直接走 base64，不产生替换字符；文本/JSON 响应不受影响。
- 状态：verified / medium

#### F20 · 目录访问错误通知按 propertyName 全局去重，多屏只有第一屏收到

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+DirectoryWatchers.swift:72`；`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift:164-180`
- 问题：fetchall 目录访问错误通知在逐 webView 循环内读写共享去重字典（键仅 propertyName、无屏幕维度），多显示器时目录访问状态变化只送达迭代序第一个屏幕，其余屏对错误发生与恢复永远无知且不可自愈。
- 证据（含复核结论）：:68-72 读-比-写共享字典（WebWallpaperHostTypes.swift:277，实例级）后仅向传入的单一 webView evaluateJavaScript；DirectorySync.swift:164-180 经 forEachWebView（Surface.swift:222-226）逐屏传同一批通知（每 propertyName 一条），主线程同步循环内第一屏写入后其余屏必被去重 return；10s 轮询（DirectoryWatchers.swift:228-237）同路径同被挡；JS 侧无主动查询通道，页面目录状态完全靠 host 推送。复核修正措辞：其余屏不是「停留在错误显示」而是对该属性访问状态永远无知；文件变更通知（:44-61）无去重不受影响。
- 状态：verified / medium

#### F21 · 系统音频频谱子选项区欠约束，子行与分隔线宽度不齐

- 位置：`MyWallpaperX/Shared/Settings/AppKitSettingsView+Layout.swift:218`
- 问题：系统音频频谱子选项区 7 个子行与 6 条内嵌分隔线未加宽度约束，与同文件 hotkeyRowsStack 显式 pin 宽的处理不一致——垂直 stack 的 leading 对齐不拉伸子视图，形成欠约束布局：子行右侧控件不与主行右缘对齐、内嵌分隔线远短于面板其他分隔线。
- 证据（含复核结论）：:218-232 直接放入 spectrumOptionsStack；makeSettingRow 返回的 container（:374-427）无宽度约束；仓库内三处同构场景均显式 pin 宽（AppKitSettingsComponents.swift:129/:134、Layout.swift:265/:271、SteamWorkshopItemDetailSheet.swift:612）反证 .leading 不会自动拉伸；grep 无别处补约束；开启「系统音频频谱」即显示（AppKitSettingsView.swift:214）。复核保留意见：行宽可能由 intrinsic 求出唯一解，严格术语下不一定触发 hasAmbiguousLayout，「歧义」措辞略宽，不影响欠约束与视觉后果实质；未运行视觉验证。核心面板一次 13 个元素成片视觉退化故 medium。
- 状态：verified / medium

### Low

#### F22 · 缩略图磁盘缓存无淘汰机制，长期浏览磁盘占用无限增长

- 位置：`MyWallpaperX/Shared/UI/ThumbnailCache.swift:27`
- 问题：缩略图磁盘缓存层（Application Support/<bundleID>/thumbnails，非系统托管目录）无任何淘汰/上限/自动清理机制，六个成功路径无条件落盘，Steam 工坊原始预览字节（单键可达数 MB）经此持续累积，长期浏览磁盘占用无限增长，仅手动「清空缓存」能清。
- 证据（含复核结论）：:27-34 静态共享目录；:84/:129/:175/:202/:237/:275/:309 无条件 write；countLimit 只作用于内存 NSCache（:43）；按键 remove 仅失效重试路径调用。复核修正原审查员两处依据错误（不影响核心结论）：clearDiskCache 另有 SteamWorkshopService+BrowseStateRecovery.swift:29 调用；设置窗口有统一「清空缓存」（AppKitSettingsView.swift:686→SettingsWindowController.swift:72-74）同时清两服务——清理入口比所述更可达，但均为显式手动全清，仍非淘汰机制。仅磁盘增长、有手动清理入口，low 恰当。
- 状态：verified / low

#### F23 · 空库开启自动切换 timer 静默不启动，导入后不恢复

- 位置：`MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+PlaybackSettings.swift:78`
- 问题：库为空或无当前壁纸时开启自动切换，timer 静默不启动且手动导入壁纸后无恢复调用，开关 on、行为静默失效，直到手动播放一次或（恢复链能落地 currentWallpaper 的）重启。
- 证据（含复核结论）：startAutoSwitchTimer（:76-89）在 shouldRunAutoSwitchTimer（:184-187）不满足时 stopAutoSwitchTimer 后静默 return 无回执；refreshAutoSwitchTimerIfNeeded 全部调用点不含导入路径；$wallpapers sink 仅自动持久化（WallpaperManager.swift:248-254）。复核修正：带 autoplayToken 的在线/Steam 静默导入经 applyPreparedImportResult→setAsWallpaper 会恢复 timer，手动导入（context=.library）支线成立；「重启可恢复」仅在 Persistence.swift:313 guard 通过时成立。代码库已有两处同类「timer 静默死亡」修复注释（Persistence.swift:321-323、PlaybackEvents.swift:41-43），此为同一已知模式的未覆盖入口。
- 状态：verified / low

#### F24 · 下载页缩略图生成失败静默折叠，占位符永远停留「加载中...」

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsItem.swift:313`
- 问题：下载页缩略图生成失败被 try? 静默折叠为 nil 且无 else 分支，损坏/不支持编码的 mp4 卡片占位符永远停留「加载中...」，用户误以为仍在加载，无任何失败呈现。
- 证据（含复核结论）：:311-318 仅 if let image 分支，:328 try? await generator.image(at:) 折叠所有失败；隐藏占位符仅缓存命中（:301）与成功（:316）两处；数据源 :846-853 仅按文件名过滤，坏文件照常进网格；失败不缓存，重进页面重试仍败。对比浏览网格失败路径至少 stopAnimation（AppKitOLBrowserItem.swift:357-363）。复核措辞保留：重新 configure 会重试而非字面永不结束，但对必然失败的文件每次结果相同。
- 状态：verified / low

#### F25 · 空标签库的标签选择器静默无操作

- 位置：`MyWallpaperX/Shell/UIActionHelper.swift:121`
- 问题：标签库被删空后，从 Inspector 标签按钮或主菜单「添加标签」⌘T 触发的 presentTagPicker 弹出无条目 NSPopUpButton，点「确定」因 titleOfSelectedItem 为 nil 直接 return——静默无操作、无任何提示。
- 证据（含复核结论）：:120-122 空数组不加条目、:130-133 guard return 无 else；删空可达（removeTagFromLibrary 无下限，WallpaperManager+Selection.swift:392-400；Persistence.swift:65-69 空数组持久化跨会话）。复核修正可达入口：右键（AppKitLibraryGridView+Interaction.swift:67 isEnabled:!tags.isEmpty）与工具栏（VideoLibraryToolbarController.swift:549 hasTags）均有守卫，实际可达的是 Inspector（makeIconButton 默认启用、refreshFooterActions 从不禁用 tagButton）与主菜单 ⌘T（MainWindowCoordinator.swift:190-193 videoLibrary 分支只查 selection，对比图片库分支 :196 查了）；「全新安装」不成立（defaultTags 4 个种子）。
- 状态：verified / low

#### F26 · Steam 下载页多选模式 Esc/Return 退出是死代码

- 位置：`MyWallpaperX/Modules/SteamWorkshop/UI/AppKitSteamWorkshopDownloadsGridView.swift:562`
- 问题：下载页多选模式下键盘 Esc 无法退出：handleKey 多选分支对所有按键提前 return，含 exitDownloadsMultiSelectMode 的 handleEscapeKey 成不可达死代码；Return 同被吞。
- 证据（含复核结论）：:561-563 提前 return handleArrowKey（:553-558 只特判 Cmd+A）；SteamWorkshopGridKeyboardNavigation.swift:22-23 对 Esc(53)/Return(36/:76) 返回 nil；handleEscapeKey（:373-381）唯一调用点在多选分支之后的 case 53，不可达；全 app 无其他 Esc 出口。复核修正：主菜单「进入/退出多选」绑 Cmd+E（MainMenuBuilder.swift:120-124→MainWindowCoordinator.swift:248-251）纯键盘可退出，非「只能鼠标」——但 Esc 专用退出为死代码、做了 Cmd+A 特判却遗漏 Esc/Return，属真实可用性缺陷，有替代路径故 low。
- 状态：verified / low

#### F27 · Steam Guard 验证码被拒后重进不清空输入框

- 位置：`MyWallpaperX/Modules/SteamWorkshop/UI/SteamLoginPanelController.swift:230`
- 问题：Steam Guard 验证码被拒或邮箱重发后重新进入验证码页时不清空 codeField，输入框残留已失效旧码且为第一响应者，文案提示重新输入却诱导一键重提再次失败。
- 证据（含复核结论）：.awaitingDeviceCode/.awaitingEmailCode 分支（:226-237）只 makeFirstResponder 不清空；全仓 codeField.stringValue 唯一写入是 clearSecrets（SteamLoginPanelView.swift:271），仅 windowWillClose 触发；被拒后 SteamKit2 以 previousCodeWasIncorrect=true 重回调→authState→新 phase 绕过 observe guard（:194-196）。复核勘误：submitGuardCode 实在 Controller:372-386 非 View 文件，实质不变。一次性短时效码+关闭有 clearSecrets 兜底，非安全问题。
- 状态：verified / low

#### F28 · 右键未选中卡片意外弹出详情面板

- 位置：`MyWallpaperX/Modules/VideoLibrary/UI/AppKitLibraryGridView+Interaction.swift:24`
- 问题：右键未选中卡片时 selectForContextMenuIfNeeded 裸写 collectionView.selectionIndexPaths 未包 isApplyingSelectionSnapshot，触发 didSelectItemsAt 意外弹出详情面板——单选模式下右键菜单与详情面板同时出现，而菜单内本有独立的「详细信息」项说明自动弹面板并非预期。
- 证据（含复核结论）：:24 裸写、:206-215 delegate 单选分支 :215 presentInspectorForSelectedWallpaper；程序化写 selection 触发 delegate 有仓库内三模块一致的自证（:876 注释、:851-854/:887-889 包裹、SIL/Steam 同模式 flag+guard）；决定性对照：SIL 的 makeContextMenu 不写 collection selection（SILGridContainerView.swift:461-467），VideoLibrary 系偏离非设计。复核确认边界准确：右键已选中卡为 no-op、多选模式不写，仅「单选+右键未选中卡」受影响；未做运行时验证，AppKit delegate 语义依据为仓库内模式证据。
- 状态：verified / low

#### F29 · 音量/倍速只对快照节点生效，动态新建媒体节点照常有声

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift:558`
- 问题：宿主音量/倍速只对快照时刻已存在的 audio/video 节点生效，之后壁纸动态新建的媒体节点以默认音量播放——用户静音（音量 0）后壁纸进入下一张或动态创建节点会照常有声，直到下次音量命令或页面重载才纠正。
- 证据（含复核结论）：__myWallpaperSetGlobalVolume（:556-569）与 __myWallpaperSetPlaybackRate（:570-580）均一次性快照；attachWallpaperMediaNode（MediaObservers.swift:73-154）对新增节点只挂监听不回填属性，volumechange（:148）只上报。复核排除全部潜在守卫：MutationObserver、shadow observer、volumeListeners、8s setInterval 均无回填，亦无 WKWebView.isMuted 视图级兜底（静音折叠为 volume=0 下发，WallpaperEngine.swift:288-303）。触发需「音量变更后壁纸又动态创建媒体节点」前置条件，下次交互自愈，low（至多 low~medium）。
- 状态：verified / low

#### F30 · Inspector 收藏点击双重全量 rebuild 且主线程读盘

- 位置：`MyWallpaperX/Modules/VideoLibrary/UI/VideoLibraryInspectorView.swift:418`
- 问题：收藏点击触发两次全量 rebuildContent（toggleFavorite 手动一次 + $wallpapers 订阅下一 tick 一次），每次重建在主线程读盘构造 previewImage——实际每次 rebuild 至少读盘 2 次、两次共至少 4 次，且 path label 选中态丢失；任何 wallpapers 数组变化同样全量重建。
- 证据（含复核结论）：:413-420 手动 rebuild+refreshFooterActions；UIActionHelper.swift:109 同步写 @Published wallpapers→:145-157 订阅经 receive(on: main) 下一 tick 再 rebuild（分支必中）；makePreviewSection :192→:57/:62 主线程 NSImage(contentsOfFile:)，noticeItems :90 再求值一次；applyAssetPaths 就地修改数组元素（WallpaperManager+CacheAssets.swift:54-60）同样触发。复核修正：「闪烁」不可直接观察（两 tick 各自完整 remove+add）；重复 IO/解码与选中态丢失真实，主线程毫秒级量级，low。
- 状态：verified / low

#### F31 · 删除防重入标志被异步投递绕过，删 N 个文件启动 N+1 轮扫描

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsGridView.swift:484`
- 问题：deleteSelected 的 suppressDownloadedIDsReload 防重入标志被 Combine receive(on: DispatchQueue.main) 异步投递绕过——标志复位后 @Published 变更才抵达，guard 放行再次 reloadEntries，单次删除 N 个文件共启动 N+1 轮目录扫描+逐文件 AVAsset 元数据加载。
- 证据（含复核结论）：:484-491 同步置位/复位+显式 reload；sink :213-219 receive(on:) 总是异步投递（即使发射方已在主线程），N 次 @Published 发射在返回后到达时标志已复位；reloadEntries（:314-331）generation 计数互相取消但已完成 IO 不回滚，:847 取消检查仅文件间生效。所有删除入口均主线程同步可达。功能结果正确、浪费有界，low；未运行验证 Combine 时序，依据 Apple 文档化 receive(on:) 调度语义。
- 状态：verified / low

#### F32 · reloadEntries detached task 强捕获 self 且不可取消，切走模块后台跑完

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLDownloadsGridView.swift:322`
- 问题：reloadEntries 的 Task.detached 闭包强捕获 self 且容器无外部取消路径，deinit 的 cancel 对运行中 task 不可达——大目录扫描中切走模块，后台 CPU/IO 必然完整跑完且容器延迟释放。
- 证据（含复核结论）：:322-330 嵌套 await MainActor.run 内显式 self.；cancel 仅 deinit:161 与 reloadEntries 开头:319（需先有强引用才可达）；数百文件串行 await、每文件 4 项 AVAsset 异步加载，秒级以上，且为 userInitiated detached task。复核修正：审查员举例的 .olDownloadsReload 通知全仓无发布者（死通知），续命实际经 $downloadedIDs sink（浏览页下载完成 insert）可达，结论不变。generation guard 保证无逻辑错乱，写入目标为已离窗视图，无用户可见影响。
- 状态：verified / low

#### F33 · 在线库浏览网格缩略图无解码缓存，主线程重复解码

- 位置：`MyWallpaperX/Modules/OnlineLibrary/UI/AppKitOLBrowserItem.swift:346`
- 问题：在线库浏览网格缩略图无解码结果缓存（OLThumbnailCache 只缓存压缩 Data），卡片每次进入视口都对同一份 JPEG 做主线程 NSImage(data:) 解码，集中解码时滚动有明显尖刺；同函数未命中分支却用 Task.detached 后台解码，两路径策略不一致。
- 证据（含复核结论）：缓存命中 :344-346 在 MainActor 解码（Task 继承 NSResponder→NSCollectionViewItem 的 @MainActor，SDK 注解链证实），未命中 :358 detached 后台；OLThumbnailCache 为 NSCache<NSString,NSData>（OnlineLibraryThumbnailPipeline.swift:175-207）；对照 OLDownloadedThumbnailCache（NSCache<NSNumber,NSImage>）仅下载页在用。复核机制修正（结论更强）：浏览网格 provider 直接 init 新实例不走 makeItem 复用池（AppKitOLBrowserGridView.swift:99 注释），prepareForReuse 实际不被调用，新实例 image 恒 nil、:205 守卫必放行——每视口重入重复解码完全成立。「1-3ms/张」为经验估算。
- 状态：verified / low

#### F34 · Steam 下载缩略图主线程同步读盘解码，失败时重复 IO 与重试

- 位置：`MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopDownloadThumbnailPipeline.swift:21`
- 问题：cachedThumbnail 在调用线程同步做磁盘读+JPEG 解码+8×8 像素采样且无内存缓存，唯一调用方在主线程卡片配置链路；图像为 nil（视频损坏）时每次刷新重复同步 IO 并重排队 3 帧 AVAsset 重试。
- 证据（含复核结论）：:19-26 同步 NSImage(contentsOf:)+steamWorkshopPreviewImageLooksSuspicious（SteamWorkshopPreviewImageSupport.swift:61-81 强制整图解码+采样）；generateThumbnail 缓存命中路径同线程（:36-41）；调用方 AppKitSteamWorkshopBrowserItem+Presentation.swift:454 处于 configure 主链路，各 sink 均 receive(on: main)。复核限定：nil 场景缓存文件通常不存在，「整图解码」退化为快速失败，真正重复解码仅限缓存文件存在但损坏/可疑的边缘情况；健康卡首次后的刷新被 :370-374 守卫拦下。缩略图上限 960×960 毫秒级，low。
- 状态：verified / low

#### F35 · 下载任务面板已显示行随状态迁移整体重配置，缩略图反复重走加载

- 位置：`MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopDownloadTasksPopover.swift:558`
- 问题：下载任务面板已显示的行在每次 jobs 状态迁移时被整体重配置：unbind 先清 currentPreviewURL 使 loadPreviewIfNeeded 防重入 guard 恒通过，缩略图被重置回占位符重走加载；缓存被逐出的行伴随主线程同步读盘解码。
- 证据（含复核结论）：:214-216 对已存在行无条件 configure；:363 unbind→:426 清 currentPreviewURL→:558 guard 恒通过→:562 占位符重走加载；一次下载生命周期（enqueue→started→staged→committing→completed）至少 4 次 jobs 迁移+终态 history upsert 各触发一轮（SteamWorkshopJobStore.swift:379/:396-410）。复核精确化：预览 URL 为 nil 的行 guard 直接 return 不重置；内存/磁盘命中时占位与真图同栈完成无可见闪烁，仅双未命中跨 runloop 可见；附带副作用：unbind 重置速度采样使读数每次丢一拍、取消进行中加载后重启。
- 状态：verified / low

#### F36 · SIL 网格配置路径与 2 秒轮询主线程磁盘 stat，慢速卷卡顿

- 位置：`MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridContainerView.swift:415`
- 问题：SIL 网格 cell 配置路径（每 cell 主线程 fileExists+attributesOfItem）与 2 秒轮询定时器（对全部可见 item 主线程 stat）在慢速卷（外置盘/NAS/网络卷）上造成逐 cell 卡顿与周期性掉帧；本地 SSD 用户无感。
- 证据（含复核结论）：provider :83→item.configure 同步调 thumbnailLoader→:91 fileExists+:95 thumbnailFailureSignature（:421 attributesOfItem），发生在 :100 ThumbnailCache.load（后台 decode queue）之前不受其保护；轮询 :405 makeTimerSource(queue:.main) 每 2s，唯一守卫 :411 vips.isEmpty，init 启动仅 deinit 取消；refreshVisibleItems/:327 的 reloadItems 也重走 provider。路径原样持久化无本地卷限制（SILService.swift:523-539 可从任意位置导入），场景可达。
- 状态：verified / low

#### F37 · loopback server 启动主线程信号量等待，每屏首次阻塞最长 1 秒

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLoopbackServer.swift:58`
- 问题：loopback server.start() 用信号量在调用线程同步等待最多 1 秒，调用方在主线程的 surface 装载路径上——httpLoopback profile 下每屏首次分配端口最长阻塞主线程 1 秒，多屏顺序创建叠加，表现为启动时 App 明显冻结。
- 证据（含复核结论）：:26/:58 同步 wait；主线程链完整（MainWindowCoordinator.swift:430-434 queue:.main→launch→createAndLoadSurface 逐屏→Lifecycle.swift:347-363→NavigationIdentity.swift:75 load）；highCompatibility profile（serviceWorker/ESM/wasmStreaming 风险 flag）即 httpLoopback（WebWallpaperHostTypes.swift:48-54、SteamWorkshopService+WebPlayback.swift:155-170）。复核修正：恢复重载走 reloadTrackedNavigation→webView.reload() 不经过此链；start() 有端口短路（:21-24）仅每屏首次阻塞；超时有回退 localEntryURL 兜底（Lifecycle.swift:368-371）。触发面窄上限明确，low。
- 状态：verified / low

#### F38 · 侧栏 cell 复用不重置 alphaValue，拖拽后整行不可见

- 位置：`MyWallpaperX/Shared/Components/SidebarComponents.swift:197`
- 问题：SidebarRowCellView.configure 复用时不重置 alphaValue，被拖拽置 0 的 cell 滚出可视区后漏恢复、经复用池挂到普通叶子行导致整行不可见（热区仍在、数据无损），直到该 cell 再挂回标签行被拖拽或窗口重建才自愈。
- 证据（含复核结论）：configure（:197-215）只重置标题/图标/计数，:219 是全仓 alphaValue 唯一写点（无 prepareForReuse 等重置钩子）；恢复循环（SidebarViews.swift:1210-1225/:1327-1340）用 view(atColumn:row:makeIfNecessary:false) 只遍历可见行且 guard 跳过非标签行；拖标签+autoscroll 滚出可视区场景可达，顺序变化或任一 @Published 订阅即可触发 reloadData 把坏 cell 分发到可见叶子行。复核修正治愈路径表述（reloadData 恰是分发坏 cell 的操作）；唯一未实证项是 AppKit 回收 offscreen cell 的确切时机（文档化标准行为+同仓多个复用视图显式重置 alpha 佐证）。
- 状态：verified / low

#### F39 · SIL 快速连点取消上一次按压释放，按压态滞留

- 位置：`MyWallpaperX/Modules/StaticImageLibrary/UI/SILGridItemView.swift:27`
- 问题：SILCollectionView.mouseDown 无条件取消上一次按压释放的 DispatchWorkItem，快速连点（按住 <50ms 松开 A 后立即按下 B）时 A 的释放闭包被取消且永不补偿，isPressingCard 滞留——再 hover A 显示按下态（0.96 缩放），需再点一次 A 复位。
- 证据（含复核结论）：:27-28 先 cancel 再设新按压；按住时长 <minimumPressVisualDuration（0.05s，UIInteractionAnimation.swift:18）时释放经 asyncAfter 排队（SILCollectionInteractionSupport.swift:16-20）；grep 证实 applyPressedState 唯一外部调用方是容器 :436，prepareForReuse（:230）仅回收时复位而 A 仍可见不回收，无事件 monitor 等其他复位点。复核完成边界核实：双击同卡/按住 ≥50ms 不滞留；纯视觉、可自愈、触发窗口 <50ms 偶发，low。
- 状态：verified / low

#### F40 · DOMContentLoaded 包装器破坏 removeEventListener 函数同一性

- 位置：`MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+DOMLifecycleScaffold.swift:257`
- 问题：DOMContentLoaded 包装器每次注册生成新闭包交给原生 addEventListener，页面对同一监听器的 removeEventListener 按函数同一性匹配不到而静默失效，重复注册也不再被原生去重——fire 前 remove 或双注册的页面初始化逻辑会多跑一遍。
- 证据（含复核结论）：:257-268 每次新建 wrappedListener（:267 只改 Function.name 不影响同一性），removeEventListener 无补偿包装（grep prototype.removeEventListener 零匹配）；脚本经 WKUserScript atDocumentStart 注入先于页面脚本，页面 DCL 注册必经 wrapped 路径。复核限定：DCL 为一次性事件，remove 失效仅在 fire 前 remove 的窗口期有可观察差异；守卫 __mwxDOMReadyGuardPatched（:272）只防 patch 重复安装不去重页面注册；宿主自身 DCL 监听器多注册于 patch 之前，受害面限第三方页面。命中较少见写法、后果轻，low。
- 状态：verified / low

## 存疑的问题（复核未通过，保留供人工判断）

#### F41 · QuickLook 面板在 selectedWallpaperId 变 nil 时不关闭（存疑）

- 位置：`MyWallpaperX/Shell/ContentViewSupport.swift:74`
- 问题：syncVisiblePreview 在 selectedWallpaperId 变为 nil 时提前 return，previewURL 残留、numberOfPreviewItems 仍返回 1 且面板不关闭——QuickLook 面板继续展示一个已从列表移除但文件仍在磁盘的壁纸（UI 与列表不同步）。
- 证据（含复核结论）：复核反证原触发场景后按弱化结论保留：应用内删除（四个 scope）均不删源视频文件（WallpaperManager+Removal.swift:136 注释明言只删缩略图/静帧），原主张的「残留已删除条目、渲染失效内容」不可达；库删除通常跳相邻项（resolveNextSelectionID，Removal.swift:213-221）正常刷新面板。弱化残留机制存在：:77 guard return、closePreview 仅空格/ESC 三处调用，selectedWallpaperId 变 nil（删库中最后一项或引用型删除）时面板展示磁盘上完好的源文件，性质为 UI 不同步而非数据缺失。未确认项，按存疑处理排在 low 末位。
- 状态：unconfirmed / low

## 复核方式与未覆盖范围

- 12 个区域逐个只读评审，共 163 个 Swift 文件，清单式列出并逐一阅读。
- 每条发现由独立复核员重读代码核实：确认、给出反证驳回、或标注静态无法判定；F01 由复核员用 node vm 实际拼接并执行 15 个注入脚本段复现。
- 静态只读审查：未运行应用、未构建、未跑测试，运行时行为、视觉效果与交互手感无法由此发现。
- 非 UI 代码不在范围：Scene 渲染引擎、播放核心（Core/Playback）、Steam 网络与下载层、守护进程等。
