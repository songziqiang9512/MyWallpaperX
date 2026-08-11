# MyWallpaperX 框架架构备忘

> 最后更新：2026-05-05
> 基准 Git 分支：`dev`

本备忘录保留 2026-05-05 的框架结构与协作约定，停止作为现役架构清单更新。当前实现应以代码和可复现门禁为准；AppKit 迁移现状见[迁移计划顶部残留清单](appkit-migration-plan-2026-05-17.md)，Scene 现役事实见[覆盖台账](../scene/semantics/coverage-ledger.md)与[运行证据索引](../scene/semantics/runtime-evidence-index.md)，Web 按[专题入口](../web/README.md)复核当前代码和最新报告。

---

## 一、目录结构

```
MyWallpaperX/
├── MyWallpaperX/               ← 主 App Target
│   ├── App/                    ← 窗口生命周期、菜单、状态栏
│   ├── Core/
│   │   ├── Playback/           ← 视频播放引擎 + DaemonProtocol（双 Target 共享）
│   │   └── System/             ← GlobalHotkeyManager、SystemMonitor
│   ├── Models/                 ← 共享数据模型，零依赖
│   ├── Modules/
│   │   ├── VideoLibrary/       ← 已完成，其他模块的实现标准
│   │   ├── StaticImageLibrary/ ← 已完成
│   │   ├── OnlineLibrary/      ← 已完成（Pixabay 在线库，以下可简称“在线库”）
│   │   └── SteamWorkshop/      ← 已接入（创意工坊浏览/下载模块，内嵌 Workshop + steamcmd）
│   ├── Resources/Videos.zip     ← 内置示例视频，首次使用时解压到 Application Support
│   ├── Shared/
│   │   ├── UI/                 ← 见下表
│   │   └── Components/         ← SidebarComponents、AppKitSettingsComponents
│   └── Shell/                  ← 路由、侧边栏、窗口框架
├── WallpaperDaemonSources/main.swift  ← 独立进程，不动
├── MyWallpaperXHelp/
└── docs/
```

### Shared/UI/ 文件清单

| 文件 | 内容 |
|------|------|
| `ModalPresentation.swift` | 统一弹窗工厂（`makeAppAlert`/`presentAppAlert`） |
| `UIInteractionAnimation.swift` | 卡片动画常量（hover/press/timing） |
| `GridLayoutHelper.swift` | 网格列数计算，支持 `minCols`/`maxCols` 参数化 |
| `WallpaperGridIdentifiable.swift` | 网格 CollectionView 的 hit-test 标识协议 |
| `GridCollectionViewProtocol.swift` | CollectionView 标准 handler 接口（各模块子类遵从） |
| `BoxSelectionState.swift` | 框选状态机（mode + initialIDs + resolve） |
| `ThumbnailCache.swift` | 异步缩略图缓存（in-flight 合并 + NSCache，后台解码，主线程回调） |
| `AppearanceAwareContainerView.swift` | 监听深色/浅色模式切换的容器基类 |
| `NSViewExtensions.swift` | `isDarkAppearance`、`ensureLayerAnchorCentered` |
| `ModuleFocusable.swift` | 模块焦点协议、`moduleDidBecomeActive` 通知名、`ModuleIdentifier` 枚举 |
| `InspectorHost.swift` | 统一 Inspector token、开关通知、焦点恢复规则与 Shell 宿主卡片 |
| `InspectorHostBridge.swift` | 统一 inspector bridge adapter，负责模块选中态与公共宿主通知链的接线 |
| `InspectorHostActions.swift` | 统一 open/close/mount helper、presentation preset 与页面退出自动关闭 modifier |

---

## 二、依赖层级（严格单向，禁止反向）

```
Daemon → DaemonProtocol（双 Target 共享，新增 IPC 字段只改此文件）
Core   → Models
Shared → Models
Modules/VideoLibrary       → Core、Models、Shared
Modules/StaticImageLibrary → Models、Shared
Modules/OnlineLibrary      → Models、Shared
Modules/SteamWorkshop      → Shared
Shell  → VideoLibrary(WallpaperManager)、Shared、Models
App    → Shell、Core/System、Shared（不直接引用模块内部类型）
```

**2026-05-05 的历史目标（当前不成立）：删除任意一个模块文件夹，其余代码正常编译运行。** 当前 App/Shell 仍直接引用部分模块类型，仓库没有“任意模块可物理删除”的构建门；现役架构只承诺按职责分区。若未来需要可选装模块，必须由独立 target/package、协议注册和删除模块后的构建验证重新建立该合同。

---

## 三、新模块接入规范

四个模块均已完成接入，以下为规范说明，供后续新模块参考。

### 3.1 路由（Shell/ContentViewSupport.swift）

在 `SelectedItem` 枚举追加 case，在 `DetailView.body` 的 `else if selection.isSettings` 之前追加路由分支。`SidebarNode.selectedItem` 属性负责节点 kind → `SelectedItem` 的映射，新增 kind 时必须同步更新。

**子页面归并规范：** 若新节点属于某模块的子页面（而非独立模块），不需要新增 `ActiveModule` case。在 `syncManagerSelection` 中将该节点的 `newModule` 归并到父模块，并在 `isXxx` 条件里同时包含父节点和子节点，确保工具栏/菜单/快捷键路由与父模块一致。

示例（Pixabay 在线库已下载项）：
```swift
let isOnline = item == .onlineLibrary || item == .onlineDownloads
case .onlineDownloads: newModule = .onlineLibrary  // 子页面归并到父模块
```

Steam 创意工坊同理：
```swift
let isSteam = item == .steamWorkshop || item == .steamDownloads
case .steamDownloads: newModule = .steamWorkshop
```

### 3.2 侧边栏（Shell/SidebarViews.swift）

在 `SidebarSectionID` 追加新分区 case，在 `rebuildNodes` 中追加分区节点构建。

**当前侧边栏分区顺序（`sections.append` 顺序决定）：**
1. **库**（`.library`）：我的视频 → 特别喜爱 → 最近使用
2. **标签**（`.tags`）：视频库标签，支持拖拽排序
3. **图片壁纸**（`.images`）：我的图片（总库）+ 图片库标签，支持拖拽排序
4. **Steam**（`.steam`）：Steam 创意工坊、Steam 下载页
   - `steamWorkshop`：Steam 创意工坊浏览页
   - `steamDownloads`：Steam 下载页（Steam 子页面，`activeModule` 归并为 `.steamWorkshop`）
5. **在线**（`.online`）：Pixabay 在线库、已下载项
   - `onlineLibrary`：Pixabay 在线库浏览页
   - `onlineDownloads`：已下载项管理页（Pixabay 在线库子页面，`activeModule` 归并为 `.onlineLibrary`）
6. **其他**（`.others`）：设置（始终最底部）

**侧边栏节点计数规范：**
- 有内容计数的入口节点必须在 `SidebarSnapshotSignature` 里包含对应计数字段，否则内容变化时侧边栏不会刷新
- 当前已追踪字段：`wallpaperCount`、`favoriteCount`、`recentCount`、`silTagCounts`、`silWallpapersCount`、`onlineDownloadsCount`、`steamDownloadsCount`
- 新增有计数的节点时，必须同步在 `SidebarSnapshotSignature` 结构体和 `makeSidebarSnapshotSignature` 方法中追加字段，并在所有构造 `SidebarSnapshotSignature` 的地方补全

**侧边栏标签拖拽排序：**
- 视频库标签：拖拽结束后调用 `wallpaperManager.tags = liveTagOrder; wallpaperManager.saveTags()`
- 图片库标签：拖拽结束后调用 `SILService.shared.reorderSILTags(liveSILTagOrder)`
- Pasteboard 写入格式区分：视频库用 `"tag:<tagName>"`，图片库用 `"silTag:<tagName>"`，避免跨分区误拖
- 图片库分区（`.images`）子节点第 0 项始终是「我的图片」主入口，拖拽排序只操作第 1 项起的 silTag 节点，`moveItem` 时行索引需 +1 偏移

**侧边栏选中行样式规范：**
- `SidebarRowView` 覆写 `isEmphasized` 始终返回 `true`，确保焦点转移到内容区后选中行仍保持蓝色
- 不依赖 `NSOutlineView` 的默认失焦变灰行为

### 3.3 工具栏（Modules/VideoLibrary/Toolbar/VideoLibraryToolbarController.swift）

**工具栏中心化协调协议（重要）：**
1. **主控权归属**：`VideoLibraryToolbarController` 是工具栏的唯一 `NSToolbarDelegate` 和布局管理者。**禁止**任何子模块控制器直接调用 `toolbar.removeItem` 或 `toolbar.insertItem`。
2. **布局切换触发**：由主控器监听模块切换通知，统一执行 `applyIdentifiers`。子模块仅提供 `identifiers` 列表、`makeItem` 实现，以及自身的轻量模式状态同步。
3. **幂等保护**：布局切换前必须比对当前 `items`，若一致则跳过重绘，避免闪烁。
4. **回退逻辑**：当所有非视频库模块均未激活时，主控器负责恢复默认（视频库）布局。

### 3.4 菜单命令路由与验证（App/MainWindowCoordinator.swift + App/AppDelegate.swift）

**菜单命令分发：** 所有菜单命令经 `MainWindowCoordinator` 分发，不直接调用模块 Service。新模块操作在对应分发方法中追加 `case`。搜索聚焦需在模块 `ToolbarController` 实现 `focusSearch()`，并在 `VideoLibraryToolbarController.focusSearch()` 末端追加分支。

**菜单项可用状态验证（重要）：**

SwiftUI `CommandMenu`/`CommandGroup` 的 `@CommandsBuilder` 闭包**不支持**状态追踪，`.disabled()` 只在 App 启动时求值一次，之后永不更新。**禁止**在 Commands 闭包里用 `.disabled()` 做动态模块判断。

正确做法：由 `AppDelegate` 实现 `NSMenuItemValidation` 协议，在 `validateMenuItem(_:)` 里按 `menuItem.title` 匹配，读取 `MainWindowCoordinator.activeModule` 和各模块 Service 的即时状态返回 `Bool`。AppKit 每次菜单打开时自动调用此方法。

```swift
// AppDelegate 正确示例
func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let module = MainWindowCoordinator.activeModule
    switch menuItem.title {
    case "视频库专属菜单项": return module == .videoLibrary
    case "图片库专属菜单项": return module == .staticImageLibrary
    default: return true
    }
}
```

`MyWallpaperApp.swift` 里的 Commands 闭包只负责定义快捷键绑定和调用动作，**不加任何 `.disabled()`**。

**当前菜单接入原则（新模块接入时参考）：**
- 视频库与图片库接入完整菜单集。
- Pixabay 在线库浏览页只接入搜索与刷新；已下载项页面通过 Bridge 接入信息、多选、全选、删除、查看文件、预览、设为壁纸。
- Steam 浏览页当前接入搜索与缩放；Steam 下载页已接入搜索、缩放、进入/退出多选、全选、删除、信息、查看文件。
- Steam 下载页的“查看文件”统一为“对当前单选项在访达中显示”；无选中项或处于多选模式时，菜单与工具栏统一禁用，不再退回“打开下载目录”。
- Steam 下载页的“信息”统一为 toggle 语义：当前单选项 Inspector 已打开时，再次触发同一入口会关闭。

**`validateMenuItem` 中导入菜单项处理规范：**
```swift
if menuItem.title == "导入" || menuItem.title == "导入视频" || menuItem.title == "导入图片" {
    if module == .staticImageLibrary { menuItem.title = "导入图片"; return true }
    if module == .onlineLibrary || module == .steamWorkshop {
        menuItem.title = "导入"; return false
    }
    menuItem.title = "导入视频"; return true
}
```
新增模块时，按此模式在 `validateMenuItem` 中处理标题和可用性。

`MainWindowCoordinator.activeModule` 由 `MainWindowController.observeModuleModeChanges` 在模块切换时同步更新，两处（`MainWindowController.activeModule` 和 `MainWindowCoordinator.activeModule`）必须保持一致。

### 3.5 CollectionView 接入 Shared 标准

```swift
final class XxxCollectionView: NSCollectionView, GridCollectionViewProtocol {
    var onBackgroundLeftClick: (() -> Void)?
    var contextMenuProvider: ((IndexPath?) -> NSMenu?)?
    var cardInteractionHandler: (() -> Void)?
    var cardPressStateHandler: ((IndexPath, Bool) -> Void)?
    var isBoxSelectionEnabled = false
    var boxSelectionBeginHandler: ((IndexPath?) -> Bool)?
    var boxSelectionUpdateHandler: ((NSRect) -> Void)?
    var boxSelectionEndHandler: (() -> Void)?
    private(set) var lastPrimaryClickIndexPath: IndexPath?
}
```

框选用 `BoxSelectionState`，缩略图用 `ThumbnailCache(label:)`，外观容器用 `AppearanceAwareContainerView`。

⚠️ **特例**（已更新）：OnlineLibrary（Pixabay 在线库）已于 2026-03-31 从纯 SwiftUI `LazyVGrid` 迁移到 AppKit `NSCollectionView`（`AppKitOLBrowserGridView` / `AppKitOLBrowserContainerView`），并已接入 `ModuleFocusable`。当前 Pixabay 在线库浏览页与已下载项页面均通过容器视图监听 `moduleDidBecomeActive` 自动接管焦点。`BoxSelectionState` 和框选功能在线库暂不需要，不视为违规。

⚠️ **Steam 模块当前状态**（2026-05-05）：`SteamWorkshop` 已完成路由、侧边栏、工具栏、菜单、Inspector 与焦点协议接入。浏览页为原生 AppKit 网格，详情通过统一 `InspectorHost` 展示；登录与下载仍围绕 App 内置 `SteamCMDRuntime.bundle` 中的 `steamcmd.sh`。下载成品统一落地到 `~/Movies/MyWallpaperX/创意工坊`，下载页扫描该目录并保留关键元数据。当前 Steam 浏览页的公共能力以搜索、缩放和浏览上下文工具栏控件为主；Steam 下载页的真实公共能力包括：搜索、缩放、进入/退出多选、全选、删除、信息 toggle、查看文件（在访达中显示当前单选项）、QuickLook。Steam 当前同时维护两条真实播放主链：本地视频通过 `.steamWorkshopVideoReadyToPlay` 中转到视频库，HTML 网页壁纸通过 `.steamWorkshopWebWallpaperReadyToPlay` 中转到当前 Web 壁纸宿主。更细的 Steam 工具栏形态与数据源说明见后文 §六、§十。

### 3.6 模块焦点管理（AppKit 模块必须实现）

```swift
final class XxxGridContainerView: NSView, ModuleFocusable {
    func requestFocus() { window?.makeFirstResponder(collectionView) }
    // 在 init 中注册：
    // NotificationCenter.default.addObserver(forName: .moduleDidBecomeActive, ...) { [weak self] n in
    //     guard module == ModuleIdentifier.xxx.rawValue else { return }
    //     self?.requestFocus()
    // }
}
```

`moduleDidBecomeActive` 由 Shell 层在模块切换后 **120ms** 延迟发出（给工具栏重建留时间）。Pixabay 在线库已迁移到 AppKit 容器并实现该协议：浏览页与已下载项均可接管焦点。Steam 当前的真实实现仅由两个 AppKit 容器（浏览页与下载页）直接监听该通知并把 first responder 交给内部 `NSCollectionView`，`SteamWorkshopFocusHost` 已经被移除，避免悬置的焦点桥接。纯 SwiftUI 页面若未桥接 AppKit 容器，暂无法接入该协议。

### 3.7 QuickLook

- 视频库：`QuickLookPreviewController.shared`，Space/ESC 由 `MainWindowController.handleQuickLookKeyDown` 处理
- 图片库：`SILQuickLookController.shared` + `SILKeyboardHandler.shared`，`activeModule == .staticImageLibrary` 时接管
- Pixabay 在线库：浏览页**不接入 QuickLook**；已下载项页面通过 `OLDownloadsQuickLookController` 接入本地预览
- Steam：浏览页**不接入 QuickLook**；下载页通过 `SteamWorkshopDownloadsQuickLookController` 接入本地预览

`beginPreviewPanelControl` / `endPreviewPanelControl` 根据 `activeModule` 挂载对应控制器。

**Inspector / Preview / Feedback 三层语义边界：**
- `Inspector`：承载“当前选中项的上下文详情”，展示方式统一走 `InspectorHost`
- `Preview`：承载“内容预览/临时查看”，当前主要指 QuickLook 或模块自有预览链路，不进入 `InspectorHost`
- `Feedback`：承载“操作结果、错误、确认或阻断提示”，继续走 `Alert`、toast、badge 或模块内反馈 UI，不并入详情宿主
- 三者必须分离：不得把 QuickLook 预览或操作反馈伪装成 inspector 内容，也不得为了复用外壳把反馈弹窗挂入 `InspectorHost`

### 3.8 InspectorHost（统一浏览详情宿主）

为替代模块各自散落的 `.sheet(item:)` / 自定义详情入口，框架层新增统一 `InspectorHost`。该宿主只负责承载卡片外壳、开关时序与焦点恢复，不持有任何模块业务状态。

**宿主位置：**
- 宿主由 `AppKitMainSplitViewController` 挂在 detail 区根视图上层
- 呈现形态为 detail 区右侧的上下文内浮层卡片，不新增独立窗口，不接管工具栏主控
- 宿主必须是 **pure overlay**：只覆盖在 detail 内容上方，**不能**通过右侧留白、缩窄主内容区或常驻分隔线模拟“详情栏”
- hidden 状态下宿主必须零残留：不留下背景、描边、命中区域、safe-area 占位或未卸载的 hosted content

**公共通知协议：**

| 通知名 | 定义位置 | 发出方 | 用途 |
|--------|----------|--------|------|
| `inspectorHostOpenRequested` | `Shared/UI/ModuleFocusable.swift` | 模块浏览桥接层 | 请求 Shell 打开统一详情宿主 |
| `inspectorHostCloseRequested` | `Shared/UI/ModuleFocusable.swift` | 模块桥接层 / Shell | 请求关闭当前详情宿主 |
| `inspectorHostDidPresent` | `Shared/UI/ModuleFocusable.swift` | Shell | 宿主展示完成，供模块桥接内容与内部焦点 |
| `inspectorHostDidClose` | `Shared/UI/ModuleFocusable.swift` | Shell | 宿主关闭完成，供模块清理瞬时态 |
| `inspectorHostMountContentRequested` | `Shared/UI/ModuleFocusable.swift` | 模块浏览桥接层 | 请求把模块详情视图挂入 Shell 已持有的宿主插槽 |

**`inspectorHostOpenRequested` userInfo 最小字段规范：**
- `module: String`，必填，值必须来自 `ModuleIdentifier.rawValue`
- `cardID: String`，必填，模块内稳定详情 token；关闭匹配与状态回填都依赖它
- `title: String`，必填，宿主头部标题
- `subtitle: String`，可选，摘要或作者信息
- `preferredWidth: CGFloat/Double`，可选，建议宽度；Shell 会夹在 `300...460`
- `focusPolicy: String`，可选，当前支持：
  - `preserveCurrentResponder`：默认值，打开时不主动抢焦点
  - `moduleManaged`：模块在收到 `inspectorHostDidPresent` 后自行把焦点切到 inspector 内部控件
- `chromeStyle: String`，可选，当前支持：
  - `standard`：默认值，显示请求标题与副标题，使用系统圆形关闭按钮
  - `infoPanel`：显示左侧信息图标 + 固定“详情”标题，隐藏副标题，使用方形圆角关闭按钮

**`inspectorHostCloseRequested` userInfo 规范：**
- 可为空；为空时关闭当前展示中的卡片
- 若提供 `module` 或 `cardID`，则只关闭与之匹配的当前卡片

**`inspectorHostMountContentRequested` userInfo 最小字段规范：**
- `module: String`，必填，值必须来自 `ModuleIdentifier.rawValue`
- `cardID: String`，必填，必须与当前已打开卡片 token 一致
- `hostedView: NSView`，必填，模块详情承载视图；Shell 负责把它装入统一宿主插槽

**焦点规则：**
1. Shell 在首次打开 Inspector 时缓存当前窗口 `firstResponder`
2. `focusPolicy = preserveCurrentResponder` 时，打开详情不改变浏览网格当前焦点，避免破坏方向键与上下文选择
3. `focusPolicy = moduleManaged` 时，Shell 只负责发出 `inspectorHostDidPresent`，由模块桥接层在内容挂入宿主后自行把焦点交给 inspector 内部搜索框、按钮组或可滚动内容
4. 关闭详情时，Shell 优先恢复打开前缓存的 `firstResponder`
5. 若缓存 responder 已失效或已脱离当前窗口，Shell 退回到 `moduleDidBecomeActive`，由来源模块按既有 `ModuleFocusable` 规则重新接管焦点

**真实承载机制：**
- `InspectorHost` 自身持有右侧卡片壳与内容插槽
- Shell 只接受 `inspectorHostMountContentRequested`，并把模块传入的 `NSView` 装入该插槽
- 宿主透明区域必须允许事件穿透到底层 detail/grid；只有卡片真实命中区域可以截获交互
- 模块桥接层不得再直接往 `window.contentView` 或其他窗口级容器挂私有 overlay
- 宿主公共层只负责通用壳体、动画与样式预设；模块若需要特殊头部外观，必须通过 `chromeStyle` 这类公共配置传入，不能在 Shared 内写死模块分支

**模块接入方式：**
1. 浏览列表项点击、回车或信息按钮不再直接弹自有 sheet，而是 post `inspectorHostOpenRequested`
2. 模块内部详情 View / AppKit 容器仍保留在各自目录，由桥接适配器在 `inspectorHostDidPresent` 后通过 `inspectorHostMountContentRequested` 挂入宿主
3. 关闭动作统一 post `inspectorHostCloseRequested`
4. 禁止模块之间共享详情 Service；跨模块仍然只能走既有通知中转

**推荐接入实现：**
- 新模块优先复用 `Shared/UI/InspectorHostBridge.swift` 中的通用 bridge adapter
- 优先直接使用 `View.inspectorHostBridge(...)` 修饰器接入，不再单独创建模块专属 bridge 包装文件，除非模块确实需要额外适配层
- 模块只提供：
  - 当前选中项
  - `cardID/title/subtitle/preferredWidth/focusPolicy/chromeStyle`
  - 详情内容 View
  - 关闭后如何清理本模块选中态
- 不再在模块内重复实现 `DidPresent/DidClose/CloseRequested` 监听、hosting view 挂载与本地可见态同步
- 通知发送优先复用 `Shared/UI/InspectorHostActions.swift`：
  - `InspectorHostActions.postOpen`
  - `InspectorHostActions.postClose`
  - `InspectorHostActions.postMount`
  - `inspectorHostAutoClose(module:onDisappear:)`
- 头部样式优先复用 `InspectorHostPresentation.standard(...)` 与 `InspectorHostPresentation.infoPanel(...)` preset，避免模块各自重复拼配置

**AppKit 迁移期注记（2026-05-17）：**
- 当前项目正在迁向 0 SwiftUI；上述 `InspectorHostBridge` / `View.inspectorHostBridge(...)` 是迁移前的统一接入基线，不应在新 AppKit 化模块里继续扩散。
- 视频库、图片库、在线库下载的详情内容已经改为 AppKit `NSView`，由 `AppKitDetailHostViewController` 通过 `InspectorHostActions` 与通知进行 open / mount / close。
- 共享 `InspectorHost` 外壳仍是 SwiftUI 临时宿主；后续应优先把 `InspectorHost` / `InspectorHostBridge` / `InspectorHostActions` 收敛为 AppKit 宿主与显式通知接入，而不是新增 SwiftUI wrapper。
- 详情 UI 保真要求优先级高于“快速改成 AppKit”：迁移后的视频库、图片库、在线库下载面板必须保持与既有 Steam 详情面板一致的缩略图宽度、内容位置、玻璃质感、分隔线和底部按钮尺寸。

**迁移前的新模块默认详情接入基线：**
- `InspectorHost` + `InspectorHostBridge` + `InspectorHostActions` 现在是新模块详情入口的默认公共基线
- 新接入模块应优先使用：
  - `View.inspectorHostBridge(...)`
  - `View.inspectorHostAutoClose(...)`
  - `InspectorHostPresentation.standard(...)` / `.infoPanel(...)`
- 若模块需要详情能力，默认先复用这套基线；只有真实场景证明无法覆盖时，才允许回转公共层补最小协议缺口

**已完成接入样板（2026-04-04）：**
- `SteamWorkshop`：已接入统一 `InspectorHost`
- `VideoLibrary`：已接入统一 `InspectorHost`
- `StaticImageLibrary`：已接入统一 `InspectorHost`
- `OnlineLibrary Downloads`（Pixabay 在线库已下载项）：已接入统一 `InspectorHost`
- `OnlineLibrary Browser`（Pixabay 在线库浏览页）：**尚未纳入本轮**，当前不作为已完成样板统计

---

## 四、Shared 层维护规范

**可以放入：** 无业务状态的纯函数/常量、只接受基本类型的 UI 原语、通用弹窗工厂、`AppearanceAwareContainerView`、零依赖 NSView 扩展、三模块共用的协议/状态机/缓存。

**禁止放入：** 引用任何模块 Service 的代码、模块特定业务逻辑、需要 `@EnvironmentObject`/`@ObservedObject` 注入的视图。

**修改原则：**
- 修改必须对所有模块无破坏
- 只对一个模块有意义的修改放模块内部
- 调整动画常量 → 模块内用局部常量覆盖，不改 `UIInteractionAnimation`
- 调整列数范围 → 通过 `minCols`/`maxCols` 参数传入，不在 `GridLayoutHelper` 加模块分支
- `ThumbnailCache` 不支持取消单条预取，如需此功能在模块内自行扩展

---

## 五、模块边界关键设计点

**各模块 setAsWallpaper 边界**
- VideoLibrary：经过 `WallpaperEngine`，支持视频循环播放，是唯一有权发出播放指令的模块
- StaticImageLibrary：**纯浏览，不提供设置壁纸功能**，不触发任何壁纸设置调用
- OnlineLibrary（Pixabay 在线库）：**纯浏览平台资源，自身不调用任何壁纸设置接口，不直接依赖视频库模块**。"设为壁纸"的正确流程：
  1. `OnlineLibraryService` 下载视频到本地
  2. 发送 `Notification.Name.onlineVideoReadyToPlay` 通知（`userInfo["localURL": URL]`），定义在 `Shell/ContentViewSupport.swift`
  3. `MainWindowCoordinator.observeOnlineVideoReadyToPlay()` 接收并中转，调用 `WallpaperManager.processImportedVideos(context: .onlinePlayback)`
  4. 视频库静默导入后通过 `setAsWallpaper(_:userInitiated:true)` 直接触发播放（绕过防抖，确保每次点击立即响应）

  **模块间依赖：** OnlineLibrary（Pixabay 在线库）只依赖 Foundation（发通知），对 VideoLibrary 零耦合。

  ⚠️ **注意**：播放触发使用 `setAsWallpaper(_:userInitiated:true)` 而非 `requestSetAsWallpaper`，绕过防抖和重复路径跳过逻辑，确保每次点击都立即响应。

**`ImportContext` 使用规范（`WallpaperLibrarySupport.swift`）**

| case | 用途 | 弹窗 | 播放触发 |
|------|------|------|----------|
| `.library` | 用户手动导入到视频库 | ✅ 显示导入结果 | ✗ |
| `.favorites` | 导入并自动收藏 | ✅ 显示导入结果 | ✗ |
| `.tag(String)` | 导入并自动打标签 | ✅ 显示导入结果 | ✗ |
| `.onlinePlayback` | Pixabay 在线库静默下载后导入 | ✗ 跳过弹窗 | ✅ 立即播放 |
| `.steamPlayback` | Steam 下载页本地视频静默导入 | ✗ 跳过弹窗 | ✅ 立即播放 |

新增 context case 时，必须同步在 `applyContextMetadataIfNeeded` 和 `applyPreparedImportResult` 两处处理。

**UIActionHelper**（`Shell/UIActionHelper.swift`）仅服务视频库。图片库和 Pixabay 在线库各自在模块内实现 ActionHelper，不复用此文件。

**通知名定义位置**
- `staticImageLibraryModeDidChange`、`onlineLibraryModeDidChange`：`Shell/ContentViewSupport.swift`
- `steamWorkshopModeDidChange`：`Shell/ContentViewSupport.swift`
- `moduleDidBecomeActive`：`Shared/UI/ModuleFocusable.swift`
- 模块内部通知：定义在各自模块目录内，不外漏到 Shell/Shared

**跨模块操作请求协议（零耦合中转规范）**

模块间禁止直接调用对方 Service。若某模块需要触发另一模块的操作，必须通过通知中转：

1. 通知名定义在 `Shell/ContentViewSupport.swift`（Notification.Name 扩展）
2. 发出方只负责 post 通知 + userInfo 携带必要参数，不 import 目标模块
3. `MainWindowCoordinator` 在 `configure(with:)` 中注册监听，调用目标模块 Service

**当前已注册的跨模块通知：**

| 通知名 | 发出方 | 接收方 | userInfo | 用途 |
|--------|--------|--------|----------|------|
| `onlineVideoReadyToPlay` | OnlineLibraryService | MainWindowCoordinator | `["localURL": URL]` | Pixabay 在线库视频下载完成后，由视频库静默导入并播放 |
| `steamWorkshopVideoReadyToPlay` | SteamWorkshopService | MainWindowCoordinator | `["localURL": URL]` | Steam 下载页选中本地视频后，由视频库静默导入并播放 |
| `steamWorkshopWebWallpaperReadyToPlay` | SteamWorkshopService | MainWindowCoordinator | `["recordID": String, "entryURL": URL, "rootURL": URL, "propertiesJSON": String?]` | Steam 下载页选中 HTML 网页壁纸后，由当前 Web 壁纸宿主接管播放 |

**模块内部通知（OnlineLibrary，不外漏到 Shell/Shared）：**

| 通知名 | 用途 |
|--------|------|
| `olDownloadsDeleteSelected` | Bridge → Container 删除选中 |
| `olDownloadsSelectAll` | Bridge → Container 全选 |
| `olDownloadsToggleMultiSelect` | Bridge → Container 切换多选 |
| `olDownloadsPreviewSelected` | Bridge → Container QuickLook 预览 |
| `olDownloadsSetAsWallpaper` | Bridge → Container 设为壁纸 |

**`OnlineDownloadsBridge.isActive` 规范：**
- `AppKitOLDownloadsContainerView` 在 `viewDidMoveToWindow()` 中管理此标志
- 接入窗口时设为 `true`，移出时设为 `false`
- `MainWindowCoordinator` 在 `onlineLibrary` 分支调用 Bridge 方法前，先检查 `isActive`，防止误触浏览页

**新模块若需触发其他模块操作，必须遵循此协议，不得直接引用目标模块类型。**

## 六、工具栏控制器协作机制

```
VideoLibraryToolbarController（主控，NSToolbarDelegate）
    ├── toolbar(_:itemForItemIdentifier:) default 分支依次代理给：
    │       OnlineLibraryToolbarController.makeItem(for:)
    │       SteamWorkshopToolbarController.makeItem(for:)
    │       SILToolbarController.makeItem(for:)
    ├── lazy var onlineLibraryToolbarController
    ├── lazy var steamWorkshopToolbarController
    └── lazy var staticImageLibraryToolbarController
```

各子控制器可以监听模式切换通知更新自身状态与按钮内容，但**不得直接修改 `NSToolbar` 布局**；布局切换只能由 `VideoLibraryToolbarController.applyIdentifiers` 执行。

`performZoom(delta:)` 路由链：`MainWindowCoordinator` → `MainWindowController` → `VideoLibraryToolbarController` → 各子控制器。  
`focusSearch()` 路由链：`MainWindowCoordinator` → `VideoLibraryToolbarController` → 各子控制器。

**Steam 工具栏当前上下文形态：**
- 浏览发现页：账号、刷新、排序、时间窗、筛选、缩放、搜索
- 作者工坊页：返回总榜、账号、刷新、缩放、搜索
- 下载页：标题、打开目录、刷新、缩放、搜索

以上变化由 `SteamWorkshopToolbarController.browserIdentifiers` / `downloadsIdentifiers` 提供，由主控工具栏统一切换。

---

## 七、缩放控件语义（重要，新模块必须遵守）

本项目缩放采用**故意的反直觉映射**，这是产品设计要求，不是 bug，**不要修正**：

| 菜单项 | 快捷键 | delta | 实际效果 |
|--------|--------|-------|----------|
| 放大缩略图 | Cmd+- | `+1` | 列数增加，卡片变小 |
| 缩小缩略图 | Cmd++ | `-1` | 列数减少，卡片变大 |

新模块缩放按钮的 segment 图标顺序可自由选择，但 handler 传入 `performZoom(delta:)` 的参数必须遵守以上语义。

`GridLayoutHelper.zoomAvailability` 用于计算按钮可用性，各模块传入自己的 `zoomOffset`，互相独立。

---

## 八、框架层巡检与模块接入验收清单

### 8.1 框架层日常巡检（统筹层执行）

1. **路由一致性巡检**
   - `SelectedItem` case 与 `DetailView` 路由分支一一对应
   - `ContentView.syncManagerSelection` 的 `newModule` 归并与子页面归属一致（如 `onlineDownloads -> .onlineLibrary`、`steamDownloads -> .steamWorkshop`）
   - `SidebarNode.selectedItem` 与侧边栏节点 kind 映射一致

2. **菜单一致性巡检**
   - `MyWallpaperApp` Commands 仅定义动作与快捷键，不使用动态 `.disabled()`
   - `MainWindowCoordinator` 负责全部菜单命令分发
   - `AppDelegate.validateMenuItem(_:)` 负责动态可用性与标题切换

3. **焦点一致性巡检**
   - 模块容器遵循 `ModuleFocusable`
   - 模块激活后响应 `moduleDidBecomeActive` 并执行 `requestFocus()`
   - 焦点通知时序与工具栏重建时序保持兼容（当前延迟 120ms）
   - Inspector 关闭后 first responder 能恢复；恢复失败时必须回退到 `moduleDidBecomeActive`

4. **跨模块协作巡检**
   - 跨模块请求仅走通知中转：通知定义在 Shell，执行在 Coordinator
   - 模块间不得直接 import 目标模块 Service

### 8.2 新模块/子页面接入验收（模块负责人 + 统筹层）

- [ ] Shell 路由已接入（`SelectedItem`、`DetailView`、`syncManagerSelection`）
- [ ] Sidebar 节点与计数已接入（含 `SidebarSnapshotSignature`）
- [ ] 工具栏模式通知已接入（含子页面 `isDownloads` 等上下文）
- [ ] 菜单分发与可用性验证已接入（Coordinator + AppDelegate）
- [ ] 焦点协议已接入（`ModuleFocusable` + 激活通知）
- [ ] InspectorHost 开关通知与 `cardID` token 已接入
- [ ] 跨模块调用遵循“通知 + 中转”零耦合规范

### 8.3 文档维护制度

以下变更发生时，必须同步维护本备忘录：
- 新增/删除模块或子页面
- 路由映射与 activeModule 归并规则变化
- 通知协议（名称、payload、中转路径）变化
- 菜单命令分发或 `validateMenuItem` 规则变化
- 焦点接管机制变化
- InspectorHost 通知、token 或焦点恢复规则变化

若发生真实框架缺陷修复（非纯文档改写），同时在 `docs/framework-fix-archive.md` 追加 FIX 记录。

---

## 九、待处理技术债

| 编号 | 问题 | 影响 |
|------|------|------|
| TD-1 | `VideoLibraryToolbarController.configureZoomItem()` 内联了 `GridLayoutHelper` 等价计算，未复用共享方法 | 仅代码重复，行为正确 |
| TD-3 | `ContentView.syncManagerSelection` 中 `silTag` 判断用了立即执行尾随闭包，可读性差 | 仅可读性问题，逻辑正确 |
| TD-5 | `OnlineLibraryBrowserView.swift` 中 `OLDownloadedView`、`OLVideoCard` 为废弃遗留代码，已被侧边栏「已下载项」子页面替代 | 纯死代码，增加维护负担，待模块负责人确认后删除 |

---

## 十、Steam 数据源现状

- 浏览页基础列表目前仍以 Steam 页面抓取为主。
- 详情补水已不是纯 HTML 路线；当前代码已接入 Steam 官方 `ISteamRemoteStorage/GetPublishedFileDetails/v1/`，用于补充项目详情字段。
- 因此，旧文档里“尚未确认到可直接替代 HTML 的官方 JSON 接口”不再适合作为当前框架现状。
- 预览资源仍主要依赖 `images.steamusercontent.com/ugc/...`，动态图预览目前仍未整理出稳定独立接口协议。
