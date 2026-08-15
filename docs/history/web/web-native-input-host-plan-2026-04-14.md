# Web 单宿主瞬时接管方案（2026-04-14）

> **历史证据 — 非现役入口**
>
> 本文仅保存 2026-04-14 的输入/宿主设计快照；其中“当前真实状态”、目标、路径和实施建议均不得作为现役宿主合同或任务入口。
>
> 现役能力、所有权、证据和剩余风险只查 [Web 现役状态](../../web/current-state.md)；全部历史材料见[历史索引](../README.md)。

> 状态：历史输入/宿主设计快照，不是当前生产宿主或 macOS 能力结论入口。文中的“当前真实状态”只代表 2026-04-14；现役所有权与剩余风险只查 [Web 现役状态](../../web/current-state.md)。
>
> 目标：
> 为 `MyWallpaperX` 的 Web 壁纸收敛出一条**单宿主 + 默认透传 + 命中时瞬时接管**的 macOS 方案，解决当前宿主在 `hover / click / drag / iframe / canvas / Spine / Unity` 等交互样本上的能力边界，同时把“卡顿 / 延迟 / Space 切换闪烁 / 桌面点击被吞”列为第一约束。
>
> 文档定位：
> 本文不是“双宿主迁移方案”，也不是“长期原生输入态”方案。
> 它只讨论：**在 macOS 桌面限制下，如何用单一 Web 宿主做出接近 Wallpaper Engine 的交互体感。**

---

## 1. 先统一结论

### 1.1 当前真实状态

当前 Web 链路已经大规模重构完成，主线是：

- `project.json -> ResolvedWebProjectDescriptor -> ResolvedWebRuntimeModel -> ResolvedWebPlaybackContext`
- Web 与视频播放链路已经分离
- 当前唯一稳定宿主是 `DedicatedWebWallpaperHostPlaceholderAdapter`
- 当前稳定输入基线是：
  - `click-through`
  - 全局鼠标监听
  - synthetic cursor / pointer / wheel 注入
- 当前已确认：
  - 这条基线能覆盖一部分简单样本
  - 但不能等价于真实浏览器输入路径
- 当前额外已确认：
  - 单宿主默认透传 + 命中后瞬时接管的策略已成为当前稳定方向
  - hover 预热、interactive regions、短时 capture 已进入现有宿主
  - 这条路线上仍需继续补复杂 hover / drag / pointer 语义，而不是再扩散宿主数量

### 1.2 macOS 上的根本限制

想做出“像 Wallpaper Engine 一样默认可交互、无开关、且完全不影响桌面”的体验，在 macOS 上不能完全复刻。

关键不是工程难度，而是系统模型限制：

- 桌面输入优先权由 Finder 持有
- `kCGDesktopWindowLevel` 只是视觉层，不是输入层
- 没有 Windows 那种可插入 WorkerW 风格桌面交互层的公开机制
- 第三方不能重写 Finder 的输入分发链

因此存在一条硬约束：

- 要交互 → 必然会影响桌面点击
- 要完全不影响桌面 → 必然拿不到真正 click

### 1.3 新结论

如果要继续解决真实交互问题，正确方向不是：

- 长期进入“持续原生输入态”
- 再造第二宿主
- 试图让 WebView 永久像浏览器一样接管桌面输入

而应是：

> **只保留一个 Web 宿主；默认始终透传桌面输入，只在命中交互区域时瞬时接管一次输入，再立刻释放。**

也就是说：

- 宿主只有一个
- 默认仍然是 click-through
- 交互不是长期占有，而是短时接管
- 目标不是“技术上完全等价浏览器输入”，而是“用户感知上觉得壁纸可交互”

---

## 2. 当前问题的本质

当前问题不能再泛化成“鼠标交互不好”。

更准确地说，存在两类样本：

### 2.1 可由当前基线接住的样本

这类样本主要依赖：

- `wallpaperEngine_cursor`
- `wallpaperEngine_mouseover`
- 简单 `mousemove`
- 轻量点击触发
- parallax / 跟随效果

它们不一定需要 `WKWebView` 真正吃到原生输入。

### 2.2 必须依赖更真实输入链的样本

这类样本更依赖：

- 原生 DOM hit-testing
- `:hover`
- `mouseenter / mouseleave / mouseover / mouseout`
- 更完整的 `mousedown -> drag -> up`
- pointer capture
- iframe 输入
- canvas / WebGL / Unity / Spine 内部事件链

这类样本当前失败，不是因为“缺少几个 injected JS 字段”，而是因为：

> **整条输入路径不是足够接近原生的。**

但在 macOS 上，解决它们的方式不应是“长期原生输入占有”，而应是：

> **单宿主下的伪交互增强 + 智能命中 + 瞬时接管。**

---

## 3. 设计原则

本方案必须同时满足以下原则：

### 3.1 单宿主唯一方向

后续不再把新方向写成：

- 双宿主
- 长期原生输入态
- 通过宿主类型切换解决交互问题

而应明确为：

- 继续只保留一个 Web 宿主边界
- 在这个宿主内部完成从“纯被动 synthetic”到“瞬时接管”的演进

### 3.2 默认永远不长期抢输入

单宿主默认必须保持：

- `window.ignoresMouseEvents = true`

也就是：

- 默认不影响 Finder / 桌面图标
- 默认不长期抢鼠标

### 3.3 交互是瞬时接管，不是持续占有

接近产品目标的正确做法是：

1. 默认透传
2. Native 层监听鼠标事件
3. 命中交互区域时
4. 仅在极短时间内接管一次输入
5. 立即释放

### 3.4 低卡顿 / 低延迟优先级最高

这不是“后面再优化”的问题，而是第一约束。

任何实现若违反以下任一条，都不应进入主线：

1. 不允许为交互而长期关闭 click-through
2. 不允许 Space 切换时 reload 页面
3. 不允许每次切 Web 壁纸都重建宿主窗口与 `WKWebView`
4. 不允许每次 mouse move 都同步 evaluate 大段 JS
5. 不允许为交互而破坏桌面态稳定性

### 3.5 输入问题与 Web 宿主问题一起解决，但不污染视频链路

这条方案仍然只属于：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/`
- `WallpaperEngine+WebWallpaper.swift`

不回流：

- `WallpaperEngine.swift` 视频主链路
- `SteamWorkshop` 业务层
- `Shell`

---

## 4. 单宿主的目标职责

当前宿主边界仍以 `DedicatedWebWallpaperHostPlaceholderAdapter` 为基础，后续方向不是替它旁边再放一套宿主，而是让它或它的后继单宿主实现承担以下职责：

1. 继续承载当前 Web 生命周期
2. 保留现有 Web 宿主 API：
   - `wallpaperPropertyListener`
   - `applyUserProperties`
   - `applyGeneralProperties`
   - pause / volume / audio / media / plugin bridge
   - 本地 scheme / 本地资源重写
3. 在同一宿主内同时支持：
   - 桌面透传态
   - 瞬时交互接管
4. 通过 Native 侧命中判定与短时接管，把交互体感做对
5. 优先保证宿主窗口和 `WKWebView` 持久存在

非职责：

- 不能成为另一个“浏览器窗口产品”
- 不能默认把桌面永久变成可点击网页层
- 不能承担视频壁纸的链路职责

---

## 5. 目标架构

### 5.1 单宿主 + 默认透传 + 瞬时接管

最终目标应收敛为：

- 一个真正的 Web 宿主
- 默认完全透传桌面输入
- 通过命中判定只在极短时间内接管 click / drag 所需输入
- 接管后立刻释放

这比“长期交互态”更符合 macOS 现实约束，也更接近产品级可接受体验。

### 5.2 调度原则

宿主调度必须遵守：

- **播放前只选择内容，不切宿主类型**
- **同一张壁纸始终由同一宿主承载**
- **默认始终保持 click-through**
- **只有命中交互区域时才允许瞬时接管**

这意味着：

- 详情页可以展示“该样本是否建议开启交互增强路径”
- 校验层可以输出“高交互样本”提示
- 但系统不应进入长期原生输入模式

### 5.3 瞬时接管契约

这是整个方案最关键的契约。

#### 默认状态

默认始终为：

- `window.ignoresMouseEvents = true`

也就是：

- 宿主只监听，不阻断
- Finder / 桌面图标继续保有正常输入优先权

#### 接管条件

只有在以下条件全部满足时，才允许瞬时接管：

1. 监听到鼠标 down / up / drag 相关事件
2. Native 命中判定确认当前落点属于交互区域
3. 当前请求允许交互增强路径

#### 接管动作

推荐的瞬时接管动作应接近：

1. 捕获事件
2. 判定命中交互区域
3. 在极短窗口内切到：
   - `window.ignoresMouseEvents = false`
4. 触发壁纸交互事件
5. 在 10~30ms 等级时间窗内恢复：
   - `window.ignoresMouseEvents = true`

注意：

- 目标不是长期成为 first responder
- 只需要在 click 关键时刻拿到足够输入即可

#### 退出条件

以下任一事件发生时，都必须确保宿主恢复到透传态：

1. 当前 click / drag 瞬时窗口结束
2. 停止当前 Web 壁纸
3. 切换到另一张壁纸
4. Space / 激活变化导致当前瞬时窗口失效

#### 工程含义

这个契约明确区分了三件事：

- **播放内容选择**：播放哪一个 Web 项目
- **交互区域命中**：当前点击是否值得接管
- **输入瞬时接管**：在极短窗口里拿一次输入，然后立刻释放

这三者不能混成一个“长期交互态”开关。

---

## 6. 交互区域系统

这是整个方案真正成败的关键。

如果没有交互区域系统，方案会退化成：

- 要么全屏都尝试接管，桌面体验变差
- 要么完全不知道什么时候该接管，交互仍然失败

### 6.1 交互区域的目标

Native 层需要拥有一个“热点区域”模型，例如：

```json
[
  { "id": "button1", "x": 100, "y": 200, "r": 50 }
]
```

用途：

- 判断鼠标是否命中壁纸内部可交互热点
- 只在命中时触发瞬时接管

### 6.2 交互区域的来源（可并存）

#### A. 页面主动注册

最理想：

- 兼容脚本暴露接口
- 页面或兼容层向 Native 注册 hotspot

#### B. 静态分析推断

可作为初版辅助手段：

- 根据样本结构判断可能存在的热点区域或交互类型
- 可靠性有限，但可帮助首轮分流

#### C. 样本级规则缓存

对已知高交互样本：

- 允许缓存热点区域规则
- 作为现实可用的产品折中

### 6.3 设计原则

- 交互区域系统必须由 Native 持有最终命中权
- 不能每次点击都依赖 Web 先告诉我们“这里可点”
- 不能把交互区域逻辑做成每帧高频 JS 往返

---

## 7. 事件监听与系统前提

### 7.1 监听策略

推荐方向：

- 默认保持 click-through
- 使用事件监听拿到：
  - mouse move
  - mouse down / up
  - drag 相关事件

注意：

- 监听不等于阻断
- 默认只观察，不打断系统输入链

### 7.2 Event Tap 前提

如果使用事件 tap，需要明确：

- 依赖辅助功能权限（Accessibility）
- 未授权时必须有降级路径

### 7.3 多屏与坐标映射

必须明确：

- 坐标系是全局的
- 需要自行做屏幕映射
- 命中判定必须先落到正确 screen / surface

### 7.4 性能要求

必须避免：

- 每次 mouse move 都做重型 JS 往返
- 每次 hover 都重新计算全部区域
- 把输入链做成高频同步阻塞

应优先考虑：

- 批量更新
- 节流
- 每帧合并
- 用更轻量的 Native 命中判定替代高频 JS round-trip

---

## 8. 低卡顿 / 低延迟约束

这是本方案最核心的部分。

### 8.1 不允许的实现方式

以下方式全部禁止：

- 为交互态单独起第二宿主
- 长期关闭 click-through
- Space 切换时 reload 当前页面
- 激活变化时重建 `WKWebView`
- 每次播放都创建新的宿主窗口
- 每次点击都做大段同步 JS 注入

### 8.2 允许的实现方式

优先采用：

1. 宿主一旦创建，优先持久复用
2. 切不同 Web 样本时，优先：
   - 复用 window
   - 复用 `WKWebView`
   - 但不能把“只切内容”理解成零清理复用
3. 在同一宿主内长期保持透传态
4. 命中热点时只做短时接管
5. Space 切换时只恢复：
   - window level
   - collection behavior
   - order/front 状态
   - 宿主桥接状态
   不做 reload

### 8.3 复用时必须执行的状态清理契约

如果宿主复用 window 或 `WKWebView`，必须把“跨样本状态清理”写成强制步骤，而不是实现细节。

#### 必须按 request 重置的状态

以下状态不得从上一个样本泄漏到下一个样本：

- 当前 request / `entryURL` / `rootURL`
- 属性 payload 与 property listener 当前值
- pause / volume / playbackRate / current spectrum snapshot
- 样本级本地资源可访问根
- directory watcher / directory snapshot / directory access error
- media discovery / media state cache / 当前页面级 listener 绑定
- plugin / audio / media runtime listener 注册态
- 页面级注入的样本上下文缓存
- 上一个样本残留的 navigation / loading 状态
- 上一个样本残留的热点区域与命中缓存

#### 可以按 host 保留、但必须重新绑定的状态

以下状态可以跟随 host 长存，但在新 request 到来时必须重新绑定到当前页面：

- 宿主 window
- `WKWebView` 实例本身
- user script 容器
- 本地 scheme handler 外壳
- 生命周期 observer 外壳
- 事件监听外壳

但“保留外壳”不等于“保留内部样本状态”；每次新 request 都要重新同步到当前样本。

#### 不安全的复用方式

以下实现都应视为错误：

- 只调用 `load(URLRequest(...))`，但不清理上一个样本的 watcher / runtime state
- 复用旧的 scheme roots，导致新样本读到旧样本目录
- 沿用上一个样本的 plugin / audio / media listener 状态
- 让旧页面注入的全局状态继续影响新页面
- 让旧样本的热点区域继续参与新样本命中判定

#### 原则

> 可以复用宿主壳，但不能复用样本运行态，也不能复用旧样本的交互热点模型。

### 8.4 对用户感知的目标

用户应感知到：

- hover 动效可以正常工作
- 点击交互在热点区域里“像是可点的”
- 桌面整体仍然正常可用
- Space 切换不应比当前更差

不允许用户感知到：

- 桌面突然整体点不动
- 先显示一层，再闪一下切到另一层
- 切桌面时闪出系统壁纸
- 点击后明显停住等宿主切换

---

## 9. 现实能力边界

这条方案应明确承认：

| 能力 | 是否可实现 |
|---|---|
| hover 动效 | ✔ 可做得很好 |
| 点击交互 | ✔ 可用伪实现 + 瞬时接管达成 |
| 无开关体验 | ✔ 可通过默认透传 + 智能瞬时接管接近实现 |
| 完全不影响桌面 | ❌ 不可能 |
| 与 Windows / Wallpaper Engine 100% 一致 | ❌ 不可能 |

所以产品目标应是：

> 不追求技术上完全正确的桌面浏览器输入，而追求用户感知上正确的壁纸交互。

---

## 10. 代码落点（基于当前仓库现状）

### 10.1 宿主实现入口

已有文件：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+*.swift`

建议：

- 继续围绕现有单宿主实现收敛
- 不再扩 `WebWallpaperHostStrategy`
- 不再新增第二套长期宿主 adapter

### 10.2 单宿主内的后续拆分方向

如当前宿主文件过重，可以在同一宿主职责下继续拆：

- `+Lifecycle.swift`
- `+RuntimeBridge.swift`
- `+Surface.swift`
- `+InputCapture.swift`
- `+InteractiveRegions.swift`

原则：

- 仍然是同一个宿主
- 只是按职责拆文件，不是再造第二套宿主

### 10.3 播放入口

已有文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`

建议：

- `SteamWorkshopService+WebPlayback.swift` 继续只发送统一播放上下文：
  - `entryURL`
  - `rootURL`
  - `propertiesJSON`
- 不把问题重新扩散成“播放前选择宿主类型”
- 交互增强与瞬时接管逻辑应留在宿主内部控制

### 10.4 校验与诊断层

已有文件：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift`

建议：

- 继续在这里补充“高交互样本特征”诊断
- 但诊断结果不应驱动“切到另一套宿主”
- 更合理的是提示：
  - 该样本更依赖交互增强路径
  - 当前默认透传态下能力可能不足

---

## 11. 分阶段实施计划

### Phase 1：继续保持单宿主，先建立瞬时接管设计边界

目标：

- 保持当前唯一宿主路径
- 不再讨论第二宿主
- 把设计收敛到：单宿主 + 瞬时接管

验收：

- 仓库只保留一个 Web 宿主方向
- 文档与实现不再出现第二宿主表述

### Phase 2：在单宿主内建立交互区域与瞬时接管契约

目标：

- 明确热点区域系统
- 明确默认透传与瞬时接管窗口

验收：

- 宿主内部可以明确区分：
  - 默认透传态
  - 命中后的短时接管
- 不会因为交互增强而长期吞掉桌面输入

### Phase 3：逐步增强 hover / click / drag 体感

目标：

- 在同一宿主内让高交互样本的行为更接近“可交互壁纸”
- 优先解决 hover / click / 简单 drag 的体感正确性

验收：

- 高交互样本的 hover / click 表现优于当前基线
- Space 切换不回退
- 不引入新的长期卡顿

---

## 12. 当前建议

当前最合理的下一步不是继续补更多 synthetic 事件字段，也不是再讨论第二宿主。

而是：

1. 保持单宿主唯一方向
2. 在当前宿主内明确“默认透传 + 命中时瞬时接管”的契约
3. 先把交互区域系统做清楚
4. 再逐步增强 hover / click / drag 的用户感知正确性
5. 全程以低卡顿 / 低延迟 / 不闪桌面 / 不吞桌面输入为约束

一句话原则：

> 在 macOS 上，不再追求让壁纸长期像浏览器一样接管输入；而是让单一 Web 宿主默认完全透传桌面，只在命中交互热点时瞬时拿到足够的输入，让用户感觉壁纸本来就可以点。
