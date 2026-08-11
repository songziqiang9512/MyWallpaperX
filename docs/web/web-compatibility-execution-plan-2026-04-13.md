# Web 样本全面兼容执行方案（2026-04-13）

> 状态：历史实施方案，不是当前执行顺序、能力或运行证据入口。文中的“当前”“已支持”和文件路径只描述 2026-04-13 批次；后续工作从 [Web 现役状态](current-state.md)选择。

## 背景

基于以下资料汇总：

- 项目根目录已有文档：
  - `web-sample-regression-matrix-draft-v1.md`
  - `web-sample-structure-strategy-draft-v1.md`
  - `web-user-properties-macos-porting-plan-2026-04-10.md`
- 运行表现记录：
  - `docs/web-sample-validation-form-2026-04-12.md`
- 实际样本目录：
  - `/Users/songziqiang/Movies/MyWallpaperX/创意工坊`

目标不是继续“按样本一个个碰运气修”，而是把真实样本拆成少数几类宿主问题，按类别闭环。

---

## 一、先统一结论

### 1. 目前不是“完全没兼容”

当前项目已经具备这些基础能力：

- `.web` / HTML 入口识别已基本成型
- `dependency-backed shell` 已有第一版识别
- `project.json.file` 非 `index.html` 入口已支持
- Web User Properties 已覆盖主要类型
- `combo.text`、`precision`、`localization`、`display condition` 已有第一轮支持
- Web 宿主、兼容脚本、目录同步、输入转发已经拆出独立目录
- Web 宿主当前稳定方向是单宿主默认透传 + 命中后瞬时接管
- Web 宿主当前已开始向视频壁纸的“持久播放窗口不轻易重建”思路靠拢
- Web 音频频谱已统一兼容旧 listener 与新事件监听

### 2. 目前也绝不能宣称“已经全面兼容”

从现有样本表现看，当前问题已经收敛为 5 个主故障族：

1. `内容识别与播放链路选择错误`
2. `dependency-backed shell` 预设壳与依赖宿主合成不完整
3. `透明/背景/视频层级` 与桌面宿主叠加不符合 Wallpaper Engine 预期
4. `重资源样本` 在 Web 宿主内卡死、暴涨内存、启动超慢
5. `属性热更新` 只是“字段注入了”，但页面没有按官方运行语义真正生效

补充说明（2026-04-14）：

- 鼠标交互兼容问题已正式收敛为“宿主输入策略问题”，而不是继续被理解为单个 DOM 字段补丁问题。
- 当前默认宿主不再适合被长期描述为“永远 click-through”；更合理的演进是：
  - 简单样本继续走 `passiveSynthetic`
  - 高交互样本需要新的独立原生交互宿主，而不是继续在 placeholder 上硬切
- Space 切换卡顿问题也应优先往“持久宿主 / 减少 teardown”方向修，不再只靠页面侧 `visibility/focus` 回放兜底。
- 2026-04-14 的一次 placeholder 原生交互试验已确认失败：直接在现有桌面层窗口上切原生交互，并在 Space 切换时 reload 内容，会带来更严重的输入失效与桌面壁纸闪现，因此该试验已回滚。

---

## 二、当前样本建议分组

### A 组：已基本兼容，只差局部补完

样本：

- `3701406439`
- `3690554020`
- `3689993041`
- `3679297219`
- `1648488669`
- `3637719365`
- `3701026371`

这组的共同特征：

- 页面能起来
- 入口识别大体正确
- 鼠标或点击至少部分成立
- 问题集中在颜色属性、音频响应、视频尺寸、局部热更新

这组不该再按“能不能播放”处理，而该按“属性语义补完”处理。

### B 组：识别层/链路选择错误

样本：

- `921617616`
- `923576681`

这组的共同特征：

- `project.json` 明确是 Web
- 页面本体实际是 HTML + JS + video/canvas 组合
- 当前却被错误归类或退化成视频壁纸/纯黑底

这组优先修 `.web` 识别与“video-heavy web”宿主选择，不应走视频壁纸主链路。

### C 组：dependency-backed shell 壳项目

样本：

- `1835932397`
- `3703664123`
- 以及同类 `dependency` / `preset` 样本

这组的共同特征：

- 本体不是完整宿主
- 真正入口与资源在依赖宿主
- 壳样本只负责 preset 覆盖、参数覆盖或资源选择

这组如果不先把“壳 + 宿主 + preset”三者真正合成，页面即使能打开，也会出现：

- 背景透桌面
- 默认背景缺失
- 点击后空白
- 右键查看文件直接落到 `.webm`

### D 组：重资源/大配置/高复杂度宿主压力样本

样本：

- `884307090`
- `1081733658`
- `1396475780`
- `3137947556`
- `3700131876`

这组的共同特征：

- 大量属性
- 复杂 JS runtime
- canvas / WebGL / 粒子 / 多媒体 / 外部服务混合
- 启动就容易卡死、内存暴涨、长时间无 ready

这组的关键不是“再多补几条属性规则”，而是宿主运行策略和加载时机控制。

### E 组：多媒体前置条件样本

典型样本：

- `884307090`
- `921617616`
- `923576681`

这组常见能力：

- `file` / `directory`
- 本地视频 / 音频
- 背景图片、背景视频、幻灯片

这里很多问题其实不是项目损坏，而是当前宿主没有完整复现 Wallpaper Engine 的本地媒体注入与背景层语义。

---

## 三、必须改成“按故障族修”，不要按样本逐个修

### 1. 故障族一：内容识别与主链路选择错误

症状：

- Web 样本被识别成视频
- 明明有 `index.html` 与属性，却走了本地视频链路
- 查看文件定位直接落到 `.webm`

直接影响样本：

- `921617616`
- `923576681`

建议处理：

- 强化 `SteamWorkshopService+LibraryRecords.swift` 的分类规则
- 对 `project.json.file` 指向 HTML 且存在 HTML 入口的项目，优先保留 `.web`
- 即便目录内存在大量 `.webm`，只要 HTML 是真实入口，也不能回退成视频主链路
- 对 `video-heavy web` 增加显式分类标签，后续在 Web 详情页与诊断中单独提示

落点：

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`

### 2. 故障族二：dependency 壳与宿主的合成不完整

症状：

- 壳样本能识别为 Web，但播放后透桌面
- 依赖宿主里的视频/背景没有真正接上
- 当前记录里只知道 dependency 存在，但实际运行仍像“单项目”

直接影响样本：

- `1835932397`
- `3703664123`

建议处理：

- 把“播放入口来源”和“属性定义来源”之外，再加一层“运行资源根来源”概念
- 壳样本播放时，要明确：
  - HTML 入口来自哪里
  - 资源根来自哪里
  - preset 覆盖值来自哪里
  - 壳自身是否带补丁资源目录
- 对 `dependency-backed shell` 生成一份最终合成运行模型，而不是运行时零散判断

建议新增或强化：

- `SteamWorkshopService+WebPlayback.swift`
- `SteamWorkshopService+WebValidation.swift`
- `SteamWorkshopService+WebProjectSupport.swift`

目标：

- 对壳项目输出“最终运行宿主说明”
- 不是只显示“有依赖”，而是显示“当前实际取用的入口、资源根、preset 覆盖项”

### 3. 故障族三：背景透明、背景层级、视频铺放语义不对

症状：

- 页面元素出现了，但背景透到桌面默认壁纸
- 视频有播放，但比例不对、未 cover/contain 到屏幕
- 默认背景应该显示，却因为透明层或 CSS 初值错误而漏出桌面

直接影响样本：

- `3703664123`
- `3679297219`
- `923576681`
- `921617616`
- `1396475780`

建议处理：

- 在 Web 宿主层补一层“页面背景可见性与媒体首帧监测”
- 宿主不直接强行给所有页面加黑底，但要检测：
  - 主背景视频节点是否找到
  - 主背景视频是否 ready
  - 页面根是否长期透明
  - canvas 是否有首帧输出
- 对“背景型 video 元素”做 Wallpaper Engine 风格默认修正：
  - `object-fit: cover`
  - `width/height: 100%`
  - 保证铺满宿主 surface
- 对全透明且无首帧输出的页面给出 runtime-blocking 诊断，而不是让桌面直接透出

落点：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+MediaDiscovery.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+DOMLifecycle.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+MediaState.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift`

### 4. 故障族四：重资源样本启动卡死、内存暴涨

症状：

- 点击播放后长时间无画面
- App 占用 1G+ 内存
- 页面未 ready 前一直重试或持续注入
- WebGL / 大量 canvas / 大 localization / 大属性表样本特别容易触发

直接影响样本：

- `884307090`
- `1081733658`
- `1396475780`
- `3137947556`
- `3700131876`

建议处理：

- 给 Web 宿主加“分阶段启动观测”：
  - `navigation committed`
  - `DOMContentLoaded`
  - `compatibility script ready`
  - `first paint candidate`
  - `media ready`
  - `first successful property apply`
- 首次属性注入不要在宿主未 ready 时高频重复打
- 对大 JSON 属性集做节流和一次性全量首发
- 对频繁热更新做合并派发，避免页面初始化阶段被高频 apply 打爆
- 对外部服务与本地目录同步分离，不要让目录扫描阻塞主启动
- 对 `884307090` 类旧音频可视化样本，优先把“运行稳定性”和“频谱体感”分开处理，不要把频谱节奏调优重新误归因成宿主泄漏

落点：

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+DirectorySync.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`

### 5. 故障族五：属性已经注入，但页面语义没真正跑通

症状：

- 颜色参数无效
- 页面 UI 上能调，实际运行没变化
- 部分属性生效，部分完全无反应

直接影响样本：

- `3701406439`
- `3679297219`
- `1648488669`
- `3637719365`

建议处理：

- 不要只看我们是否发了 JSON，要验证页面是否按 Wallpaper Engine 语义消费
- 重点补齐：
  - `color` 字符串格式和页面常见解析兼容
  - `combo.text`
  - 首次全量属性集 + 后续 delta
  - `setPaused`
  - 音频数据流桥接
- 对“颜色参数无效”的页面，优先检查它们是否要求十六进制或自定义转换，再决定是否要在兼容脚本里加兜底转换层

落点：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProperties.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntime.swift`

---

## 四、建议执行顺序

### Phase 1：先修分类与壳项目合成

目标：

- 避免继续把 Web 样本误送进视频链路
- 让 dependency 壳样本至少进入正确宿主

优先样本：

- `921617616`
- `923576681`
- `1835932397`
- `3703664123`

完成标志：

- 详情页识别正确
- 点击播放进入 Web 宿主
- 壳样本能清晰显示“实际运行入口/资源根/宿主来源”

### Phase 2：修背景层、视频层和首帧可见性

目标：

- 解决“透桌面”“黑底”“比例不对”

优先样本：

- `3703664123`
- `3679297219`
- `923576681`
- `921617616`

完成标志：

- 主背景视频可见
- 页面无透明漏底
- cover / contain 行为符合项目本身预期

### Phase 3：修启动卡死与内存暴涨

目标：

- 让复杂样本先稳定起来，再谈高兼容

优先样本：

- `884307090`
- `1081733658`
- `1396475780`
- `3137947556`

完成标志：

- 启动不再长期卡死
- 内存曲线不再异常暴涨
- 至少能进入首帧或明确报出 runtime-blocking 原因

### Phase 4：修属性热更新语义

目标：

- 让“能打开”升级为“真的像 Wallpaper Engine 一样可调”

优先样本：

- `3701406439`
- `1648488669`
- `3637719365`
- `3679297219`

完成标志：

- 首次属性注入成立
- 至少核心属性都能热更新
- 颜色类不再大面积失效

---

## 五、样本如何处理，建议不是“全量同时测”，而是维护一个固定执行集

建议把样本池拆成三层：

### L1：主回归样本

每次改宿主必跑：

- `921617616`
- `923576681`
- `1835932397`
- `3703664123`
- `884307090`
- `1081733658`
- `1396475780`
- `3679297219`
- `3690554020`
- `3689993041`
- `1648488669`
- `3701406439`

### L2：扩展覆盖样本

按修复类别选择性跑：

- `3137947556`
- `3700131876`
- `3701026371`
- `3637719365`

### L3：归档样本

只在某类能力大改后回跑，不做每日回归。

---

## 六、文档与实现如何衔接

当前三份文档其实已经够用了，不建议推倒重写。

建议这样使用：

- `web-sample-structure-strategy-draft-v1.md`
  - 继续作为“结构分型总说明”
- `web-sample-regression-matrix-draft-v1.md`
  - 继续作为“固定回归池与验收矩阵”
- `web-user-properties-macos-porting-plan-2026-04-10.md`
  - 继续作为“属性标准兼容契约”
- 本文档
  - 作为“样本问题到工程改动落点的执行桥”

也就是说：

- 结构文档告诉我们“样本是什么”
- 回归文档告诉我们“测什么”
- 属性文档告诉我们“兼容标准是什么”
- 执行文档告诉我们“先改哪、改哪里、为什么”

---

## 七、最重要的一句话

如果目标是“尽可能全面兼容真实样本”，正确做法不是追求一个万能规则，而是：

先把样本压缩成少数几个宿主故障族，再按故障族批量修复，让每修一类问题都能带动一批样本一起变好。
