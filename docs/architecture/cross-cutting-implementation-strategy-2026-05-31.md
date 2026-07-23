# Web + Scene 双链路交叉分析与协同实施策略（2026-05-31）

> 本文档保留 2026-05-31 的 Web / Scene 交叉架构分析；原始阶段计划与评审已由后续实现和 Git 历史取代。
>
> 当前事实与实施顺序统一查 [Web / Scene 当前状态路线图](../reviews/web-scene-current-state-roadmap-2026-07-19.md)、[Scene 能力台账](../scene/semantics/coverage-ledger.md) 和 [Scene 开发计划](../scene/scene-capability-development-plan-2026-07-22.md)。

---

## 1. 两份计划的共同基因

两份计划共享相同的底层方法论：

| 共同特征 | Web 计划 | Scene 计划 |
|---------|---------|-----------|
| 分析源 | Windows Wallpaper Engine 实测（`config.json`、进程模型、资源加载日志） | 同 |
| 架构原则 | 不推翻现有解析层，在中间层补差异 | 不推翻现有解释层，在中间层补差异 |
| 入口格式 | `project.json` → `file` 声明 → `index.html` 实际入口 | `project.json` → `file` 声明 → `scene.pkg` 实际入口 |
| 属性模型 | `general.properties` → payload → `wallpaperPropertyListener` | `general.properties` → binding → shader/uniform/visibility |
| 缓存隔离 | 按 `screenID` + `recordID` 维度 | 按 `screenID` + `packagePath` 维度 |
| 不应做的事 | 不推翻解析层、不允许任意 `file:///`、不硬编码单样本修复 | 不转 Web、不执行未知脚本、不做完整 HLSL 转译、不直接依赖原始 scene.json |

两份计划的评审均发现：**现有代码架构已经有正确的接入点，计划是自然演进而非重写。**

---

## 2. 共同缺失项（两份评审一致发现）

这是两份评审交叉验证后最值得重视的部分——独立 agent 在分析两套完全不同的代码后，识别出了相同的结构性缺口：

### 2.1 自动化回归测试（两份评审均列为首要缺失项）

| 维度 | Web | Scene |
|------|-----|-------|
| 现有工作样本数量 | ~110 个 Web 壁纸 | 8 个 Scene 样本 |
| 现状 | 无任何自动测试 | 完全依赖手动检查 `.mywallpaperx-scene-preview-log.txt` |
| 影响 | 每个 P1 变更都是盲目的 | 同 |

**共同需求：** 一个测试 harness，能够对每个样本：
1. 构建运行时模型（Web: `ResolvedWebPlaybackContext`，Scene: `SceneRuntimeModel`）
2. 验证能否进入 `ready` 阶段
3. 对比 `rendererGaps` / `firstStageRendererGaps` 与已知基线
4. 捕获新增的 blocking / warning / error 诊断

**建议：** 在 `Core/` 下新建 `WallpaperRegressionTestHarness`，统一 CLI 入口：
```bash
MyWallpaperX.app/Contents/MacOS/MyWallpaperX --regression-test web    # ~110 samples
MyWallpaperX.app/Contents/MacOS/MyWallpaperX --regression-test scene  # 8+ samples
MyWallpaperX.app/Contents/MacOS/MyWallpaperX --regression-test all
```

### 2.2 GPU / 内存管理策略（两份评审均发现为空白）

| 维度 | Web | Scene |
|------|-----|-------|
| 风险场景 | 3+ 显示器 × 每屏一个 WKWebView（每个 100-500+ MB） | 30+ 效果层 × 屏幕外 ping-pong 纹理（2048² × 4B × 2） |
| 极端消耗 | 3 屏 ≈ 1.5 GB（WebGL 密集型更高） | 30 层 ≈ 960 MB（仅屏幕外纹理，不含源纹理） |
| 现状 | `HostSurface` 无内存管理 | `SceneOffscreenTexturePool` 无全局预算 |

**共同需求：**
- 系统级 GPU 内存预算（例如 512 MB 上限）
- 基于优先级的资源驱逐
- `dispatchSourceMemoryPressure` 监听
- 进程终止恢复（Web: `webViewWebContentProcessDidTerminate`，Scene: MTLDevice 重建）

### 2.3 属性 Schema / 类型系统共享

两份评审一致指出：

| 可以且应该共享的 | 必须保持独立的 |
|---------------|-------------|
| `SteamWorkshopPropertyKind/Value/Definition/Option`（纯 schema） | 运行时模型（`ResolvedWebRuntimeModel` vs `SceneRenderDescriptor`） |
| 用户覆盖持久化格式（每个 recordID × screenID 的键值映射） | 绑定机制（`wallpaperPropertyListener` JS 注入 vs `ScenePropertyBindingIndex` Metal uniform） |
| 缓存清单模式（version + mtime + 路径哈希验证） | 播放上下文（属性 JSON → JS vs 属性 → renderDescriptor） |
| `wallpaperRuntimeWillSwitch` 通知（跨运行时切换） | 诊断事件模型（JS hostLogger vs Scene diagnostics） |

**当前阻塞点：** Scene 端的 `SceneProjectLoader` 完全不解析 `general.properties`——`SceneProject` 没有 `properties` 字段。共享 schema 类型之前，必须先让 Scene 端能解析属性。

---

## 3. 两份计划的关键差异

| 维度 | Web | Scene |
|------|-----|-------|
| 渲染后端 | WKWebView (WebKit) | Metal (CAMetalLayer) |
| 属性绑定目标 | JavaScript `wallpaperPropertyListener` | Shader uniforms / layer visibility / alpha / effect params |
| 资源加载 | `WKURLSchemeHandler` 拦截 `mwx-local://` | `ScenePkgReader` 读取 PKGV 包 + `SceneTextureLoader` |
| 脚本模型 | 不适用（wallpaper JS 原样运行） | SceneScript 需要静态分析 + 白名单求值器 |
| 安全边界 | 符号链接检测、root containment、origin 模式 | 脚本沙箱（不执行未知脚本）、shader 安全 |
| 最大实施风险 | 符号链接严格拒绝破坏现有壁纸 | 屏幕外渲染内存压力（集成 GPU） |
| 成熟度 | 较高 — ~110 个壁纸可运行，属性系统已闭环 | 较低 — 8 个样本测试，属性系统尚未打通 |

---

## 4. 协同实施路线图

### 4.1 共享基础设施（P0 — 先于所有运行时特定工作）

| 顺序 | 任务 | 涉及模块 | 阻塞 |
|-------|------|---------|------|
| 1 | **提取共享属性 schema 类型** | Web `SteamWorkshopWebPropertyModels.swift` → `Core/SteamWorkshop/PropertyModels.swift` | 阻塞 Scene P0（Scene 需要解析 `general.properties`） |
| 2 | **构建回归测试 harness** | 新建 `Core/WallpaperRegressionTestHarness` | 阻塞 Web P1 和 Scene P1（所有运行时变更都需要回归保护） |
| 3 | **制定 GPU/内存管理策略文档** | `docs/gpu-memory-management-strategy.md` | 阻塞 Web P0.6 和 Scene 阶段 2 |
| 4 | **统一 `wallpaperSystemStateDidChange` 通知** | `WallpaperEngine+SystemState.swift` 发布 `WallpaperSystemState` 结构体 | 同时受益 Web Item 5 和 Scene P1 通用状态 |
| 5 | **统一缓存清单模式** | Web `SteamWorkshopWebRuntimeCacheManifest` + Scene `ScenePkgCacheManifest` → 共享协议 `WallpaperCacheManifestProtocol` | 无阻塞 |

### 4.2 Web 特定工作（参考 Web 评审修正后的优先级）

```
P0（设计）：数据隔离策略、拒绝原因结构体、诊断事件模型、缓存签名方案
P1.1：首帧属性预注入（正确性缺陷）
P1.2：Per-screen 数据隔离
P1.3：通用属性 → 系统状态（使用共享 WallpaperSystemState）
P1.4：符号链接宽松策略
P1.5：诊断检查器接入
P2：源兼容模式、暂停/AudioContext 深化、运行时配置文件
```

### 4.3 Scene 特定工作（参考 Scene 评审修正后的优先级）

```
阶段 1a：属性运行时模型（SceneProject.properties 解析、绑定索引、播放上下文）
阶段 1b：着色器参数依赖的效果（opacity multi-mask、shadow）
阶段 2a：缓存清单
阶段 2b：效果覆盖率表 + 每屏诊断（可与阶段 3 并行）
阶段 3：其余高频效果（blur、bloom、bokeh_blur、godrays、glitter）
阶段 4：SceneScript 子集（依赖阶段 1a）
阶段 5：粒子/木偶/音频
```

### 4.4 协同 Timeline

```
Week 1-2:  共享基础设施（属性类型提取、回归测试 harness 骨架、WallpaperSystemState）
Week 3-4:  Web P1.1（首帧注入）+ Scene 阶段 1a（属性解析、绑定索引）
Week 5-6:  Web P1.2（数据隔离）+ Scene 阶段 1b（opacity/shadow 效果）
Week 7-8:  Web P1.3（系统状态联动）+ Scene 阶段 2a（缓存清单）
Week 9-10: Web P1.4（符号链接宽松策略）+ Scene 阶段 2b/3（覆盖率表 + 高频效果）
Week 11+:  Web P2（源兼容、暂停/AudioContext）+ Scene 阶段 4（SceneScript）
Week 15+:  Scene 阶段 5（粒子/木偶/音频）
```

---

## 5. 架构决策记录（建议固化）

以下决策已经过双链路交叉验证，建议写入 `docs/architecture-decisions.md`：

### ADR-001: 属性 Schema 类型共享，运行时模型独立

**决策：** `SteamWorkshopPropertyKind/Value/Definition/Option` 提取到 `Core/SteamWorkshop/PropertyModels.swift`，Web 和 Scene 运行时均使用这些类型解析 `project.json` 的 `general.properties`。但 Web 的 `ResolvedWebRuntimeModel` 和 Scene 的 `SceneRenderDescriptor` 保持完全独立。

**理由：** 属性 schema 是 `project.json` 的格式契约，Web/Scene/Video 三种壁纸类型通用。但属性绑定目标（JS listener vs Metal shader）和运行时状态（JSON payload vs renderDescriptor）从根本上是不同的，强行共享会创建虚假耦合。

### ADR-002: 解释文件边界不可穿透

**决策：** 原始文件（`index.html`，`scene.json`）必须通过中间解释层（`ResolvedWebProjectDescriptor`，`SceneRenderDescriptor`）才能进入运行时。渲染器永远不直接读取原始文件。

**理由：** 两份评审一致确认这是正确的架构边界。Web 计划 Section 16 和 Scene 计划 Section 7 均将其列为"不应做的事"。

### ADR-003: 系统状态单向流动

**决策：** 系统状态（暂停/恢复、FPS、电池、可见性）由 `WallpaperEngine+SystemState` 统一评估，通过 NotificationCenter 单向发布给各个运行时。运行时永远不会将状态回写至评估器。

**理由：** Web 和 Scene 评审均确认单向数据流不会产生循环依赖。Web 的 `resolvedGeneralFPSValue` 从硬编码 30 改为读取系统状态是一致的变化方向。

### ADR-004: 宽松优于严格（安全策略）

**决策：** 资源安全策略采用"记录 + 放行"模式而非"检测 + 拒绝"。仅在已解析目标位于允许根目录外时才拒绝访问。

**理由：** Web 评审的安全 agent 明确建议宽松符号链接处理。Scene 评审同样主张对不支持的脚本/效果采用诊断而非崩溃。两条链路均受益于"不静默失败，但也不轻易拒绝"的原则。

### ADR-005: 按显示器隔离，按项目共享（缓存策略）

**决策：** 运行时缓存和用户属性覆盖按 `screenID` 隔离，但资源提取缓存（pkg 解包、资源下载）按 `recordID/packagePath` 全局共享。

**理由：** Web 原版有 `cacheId monitor0`，Scene 原版按 `Monitor0` 存储属性覆盖。资源提取是重操作（解包大型 pkg），不适合每屏重复。这与两份计划的缓存设计均一致。

---

## 6. 两份评审的局限性

两份评审共享以下局限性，应在后续工作中关注：

| 局限性 | 影响 | 建议 |
|--------|------|------|
| 评审基于静态代码分析，未运行任何实际壁纸 | 可能遗漏运行时行为差异 | 在回归测试 harness 就绪后重新验证 |
| 样本数量有限（Web ~110，Scene 8） | 工坊有数十万项目，样本可能不具代表性 | 扩大样本语料库（按流行度 top 100） |
| WKWebView 与 Metal 的行为依赖 macOS 版本 | 评审基于 API 文档，未在多个 macOS 版本上实测 | 在 macOS 13/14/15 上交叉验证关键 API |
| SceneScript 静态分析无真实语料验证 | 白名单覆盖范围是推测的（80% 估计） | 分析至少 20-30 个真实 Scene 脚本后再确定范围 |
| 未涉及 App Sandbox 兼容性 | Web 方案 handler / Scene Metal 渲染可能在沙盒下有额外限制 | 在沙盒环境下验证关键流程 |

---

## 7. 总结

两份优化计划源自同一套方法论，共享相同的架构原则，受益于相同的共享基础设施。两份独立评审交叉验证了彼此的发现：

- **Web 计划（10 项优化）：置信度 中等。** 架构正确但缺少回归测试、内存管理和 WKWebView 特定限制的正式评估
- **Scene 计划（5 阶段）：置信度 中等偏高（7.5/10）。** Metal 渲染管线基础扎实，但单一大着色器架构需要重构以支持效果扩展

**最高优先级的跨模块共享工作：**
1. 属性 schema 类型提取到 `Core/SteamWorkshop/`
2. 回归测试 harness 统一 CLI
3. `WallpaperSystemState` 统一通知机制
4. GPU/内存管理策略文档

**最不应推迟的运行时特定工作：**
- Web: 首帧属性预注入（正确性缺陷）
- Scene: SceneProject.properties 解析（属性系统在输入端缺失）

如果按本文档的协同路线图执行，Web 和 Scene 两条链路可以在共享基础设施完成后并行推进，互不阻塞。
