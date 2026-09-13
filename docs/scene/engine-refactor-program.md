# Scene 引擎重构工程计划（Engine Refactor Program）

<!-- document-role: active-plan -->

> 状态：现役专项工程计划（Scene 专题的派生工程队列）
>
> 复核：2026-09-14
>
> 职责边界：本计划只拥有**引擎工程架构**——性能、进程隔离、控制面统一、性能预算、公共层拆分——的阶段顺序与完成门。Scene 兼容能力路线、段位顺序与样本验收的唯一现役计划仍是[兼容执行路线](scene-compatibility-roadmap.md)；两者冲突时兼容语义合同优先，本计划服从。目标合同查[运行时架构](runtime-architecture.md)；能力现状查[能力台账](semantics/coverage-ledger.md)；代码实际接线与"改A坏B"雷区查[事实架构地图](runtime-as-built-map.md)。
>
> 退役条件：M0–M6 全部完成、daemon 化与两档性能预算成为产品默认形态、每帧执行消费 prepared 表示、控制面统一经命令层，且稳定架构合同与能力台账接管全部终态描述后，本计划转 historical-evidence。

## 1. 长期目标

一个**清晰、快速、高效、框架结构清楚、兼容性好**的 Scene 后端引擎：

- 单一权威主链：`authored data -> prepared Program/graph/resources -> typed frame update -> Metal encode -> 唯一 compositor/output`；
- 正常帧只消费 prepared 表示与 value 更新，任何解释、验证、哈希、重建只发生在 cold path 与显式失效点；
- 播放引擎运行在独立 daemon 进程，主程序经粗粒度命令控制（与 video/web daemon 同模式）；
- 引擎受两档性能预算约束（60/30 FPS 一档一束），设置面用户可见项只有一个；
- 状态栏、设置面板、播放按钮经统一命令层控制所有壁纸引擎；属性调节热更新不重启；
- 工程标准：持续消融到最短实际链路；跨模块共享代码整块沉淀公共层；每个抽象有 ≥2 真实消费者；禁止第二套权威、禁止补丁摞补丁。

## 2. 硬约束（每批开工前逐条自查）

**架构**

- 不推倒兼容架构；Swift+AppKit 宿主 / Swift+Metal 底座 / authored→IR→Program/Graph→Executor→Compositor / 通用 shader backend / 真 ECMAScript VM（QuickJS-NG）/ particle component interpreter。
- 唯一 compositor、registry、frame clock、property authority、graph owner；PreparedProduct 五类产品协议不变；禁止第二套任何权威。
- 永不按 sample/layer/path/hash/screenshot 选择视觉算法。
- hot path 只允许：clock/SceneScript tick/粒子模拟/动态值/audio/资源 publication/uniform/encode/commit/present。禁止逐帧 JSON、hash、graph rebuild、reflection、pipeline 创建、全 catalog scan、evidence object tree、大规模 String、文件扫描（runtime-architecture §5.5）。
- 失效域按五类表最小化：value-only / resource-generation / geometry-extent / program-variant / topology。
- 安全合同保留：路径逃逸、GPU 越界、target hazard、ABI/stale generation、VM 超时、OOM 硬拒绝；视觉失败局部 fail-soft 保 previous-current。诊断是旁路，不是提交/出画面前置。

**工程**

- 每批先证明热点（架构回归纠偏除外）→ 最小范围 → 保语义 → 保测试 → 有 measurement → 重新 profiling。
- 禁止：无 profiling 全面重写、为性能绕过兼容语义、为抽象新增单一消费者包装。
- 高频 identity 用整数/struct ID；同一资源/管线不重复创建；draw/encode 热路径禁止首次 `makeLibrary`/`makeRenderPipelineState`/同步 decode/读文件。

**公共层**

- 与其他模块耦合的共享代码**整块拆出**到公共层（半拆留桩视为未完成）。
- 依赖方向单向：`Shared` ← `Core` ← `Modules` ← `App`；公共层禁止反向依赖任何具体引擎模块。
- 公共层准入须有 ≥2 个模块的真实消费者。
- 拆分是搬移+最小改名，不借机重写逻辑。

## 3. 里程碑与工位卡

卡格式：**改哪里 → 怎么做 → 验收门 → 回滚**。状态记录于卡内标题行；执行细节与 file:line 锚点查[事实架构地图](runtime-as-built-map.md)。

### M0 控制面命令化 + 公共层第一批（同进程）

- **M0.1 命令层入公共层** ⬜：新建 `Core/PlaybackControl/`：`WallpaperEngineCommand`（loadScene/playVideo/setProperty/setPerformanceProfile/setMuted/pause/resume/switchNext/shutdown）+ `PlaybackEngineControlling` 协议 + 命令 multiplexer；video/scene/web 引擎各实现处理端；UI 只发命令。验收：UI 无直触引擎内部；依赖方向检查通过。
- **M0.2 静音态升公共层** ⬜：静音从 video 音量派生态（`WallpaperManager+PlaybackSettings`）拆为公共回放态；video 保 volume 恢复语义，Scene 接 `SceneSoundPlaybackRegistry`。验收：任一引擎激活时菜单/设置静音一致生效。
- **M0.3 设置容器拆公共层 + FPS 档** ⬜：`AppKitSettingsContainerView`/`AppSettingsSection` 从 `Modules/VideoLibrary/UI` 整块搬 `Shared/Settings/`；`efficiency` 分区加"最高 FPS：30/60"（默认 60）；audio 区双引擎生效。验收：30 档下一帧起 30Hz；重启保持。
- **M0.4 状态栏菜单打通** ⬜：`App/StatusBarController` 三键（切换壁纸/静音/播放暂停）改发命令，跨引擎生效；文案图标随引擎状态刷新。验收：Scene 激活时三键全部作用于 Scene。
- **M0.5 播放按钮交互** ⬜：点击 ≤1 runloop turn 切 pending 图标；订阅 launch 五阶段状态映射 loading/就绪/失败；video 路径同型。
- **M0.6 属性热更新** ⬜（§4.2）。
- **M0.7 性能档两档** ⬜（§4.1）。
- 与 M1 文件不重叠，可并行。

### M1 度量地基

- **M1.1 常开定长 counter**：新 hub（定长累加槽，禁止无界数组/percentile；现有 `SceneFramePerformanceTelemetry` 禁改常开）。指标：frameTime/cpuUpdate/encode/gpuTime/drawCalls/passes/pipelineSwitches/targetSwitch/visibleObjects/textureMemory/rtMemory/busy 空转/geometry 与 fallback 分支计数。
- **M1.2 signpost**：帧内阶段 + 启动五阶段 + FirstVisibleFrame 时间戳。
- **M1.3 Debug HUD**：debug 构建读 counter 展示全指标；常开成本 <0.1ms/帧。
- 验收：实测基线报告（各风险项占比 + TTFVF），作为 M2-M6 的 before。

### M2 引擎减税

- **M2.1 Patch A** 门控每帧 EffectExecution trace（渲染器入口 + GraphComposition subjects 循环守卫为收益主体 + 7 处签名可选化）；同批处理 utilityCapture 遥测每帧注册 completion handler 的问题。
- **M2.2 Patch B** GPU 完成事件驱动重排帧：acceptance 翻转检测在 coordinator 锁内判、解锁后回调；re-arm 复用 startFrameDriver（禁 frameTimer==nil 前置）；2ms 兜底轮询永久保留；回调闭包捕获 launch 身份。帧时钟权威唯一（coordinator=准入权、FrameDriver=节奏权，回调只是边沿通知）。
- **M2.3 Patch C** ClaimedExecution 按 capability token 缓存（独立 NSLock；随实例生存）。
- 验收：各批独立提交；M1 before/after；消融确认被门控路径关闭后样本无行为差异。

### M3 消融减法 + hot path cleanup

- **M3.1 Frame storage**：registry snapshot+digest 合并改——publish 时 fact 层 O(1) 脏标记，脏才全量 fold（digest 是 variant memo 键，不可删只可免重算；先补 digest 等值测试）；overlay 字典 CoW 与 snapshot 持久化联动；beginFrame 无变化帧直通。
- **M3.2 启动链去串行**：activate/rebuildSurfaces 同步解码出主线程；双 join 并行化；pkg 解包与材质资产内联解码移出关键路径；候选首帧最小纠偏（对齐启动响应合同）。验收 = TTFVF before/after。
- **M3.3 持续消融**：见 §5，贯穿 M2–M5。

### M4 表示优化

- **M4.1 Phase 3 v2**：graph plan 校验从每帧重推导改为内容 key 缓存（capabilityID+inputRole+inputExtent+functionTargets digest；generation 仅作负守卫——generation-only 键已被证伪：materialFunctionTargets 逐帧可变且 composition 侧 plan 推导先于当帧 generation 铸造）；更优路径在 allocation 铸造点持久化 plan+planSignature，per-frame 校验退化为 O(1) 身份检查 + signature 比较 + functionTargets 集合比较。必须保留纹理身份门（target hazard）与 functionTargets 语义门。扁平化覆盖三条产品路径：GeometryProduct（含依赖）、TextureProduct 稳定回退、普通纹理。
- **M4.2 Phase 4 资源缓存**：colorBlend pipeline 启动预热、MTLLibrary 按 metalSource 复用（同一 shader 变体不重编译）、executor.reset 保留热缓存或跟进 warmup、纹理 decode 去重、上传私有 queue 合并、纹理缓存字节上限（接预算档）、userPropertyTextures 字符串键→整数 ID。
- **M4.3 Phase 5 frame storage**：帧提交快照最小化（uniform/event/generation table/mutation queue 方向），不复制大对象树。

### M5 进程分离 daemon 化（主线）

- **M5.1 设计门**：SceneRuntimeService 契约文档（IPC 全集/生命周期/崩溃语义）+ MainActor 与线程约束审计报告。准入门，未过不动进程边界。
- **M5.2 最小 daemon**：新 target `MyWallpaperXSceneDaemon`（tool → Contents/Helpers，仿 WallpaperDaemon 工程结构），起桌面窗口出首帧 + 管道 JSON 命令框架。
- **M5.3 DaemonKit 公共层第二批**：daemon 孵化/指数退避重启/管道帧协议抽为共享 kit；注意 daemon target 只同步 `WallpaperDaemonSources/`，共享代码需新增挂双 target 的同步组。
- **M5.4 命令迁移**：WallpaperEngineCommand 逐条改走管道；事件回传（launchState/firstFrame/frameStats 1Hz/error/exited）；断连 = 指数退避重启。
- **M5.5 Host 瘦身**：主程序 Scene 宿主变 client stub（状态机+通知投影保留，渲染全删）；菜单/设置/热更新无感切换。
- **M5.6 收尾**：切壁纸/退出/多屏拓扑/暂停恢复全链 daemon 化；旧同进程路径删除（消融）。
- 验收：M6 全套 + Scene 满载时主程序 UI 无掉帧（对比 M1 基线）+ daemon 强杀自动恢复。

### M6 验收

Fast Scene Suite → fixed/full matrix → 长稳（两档各跑）→ daemon 崩溃/断连演练 → arm64/x86_64 → 签名公证；能力台账零回退为门。

## 4. 关键设计裁决

### 4.1 两档性能预算

原则：用户只见一个选项（设置"最高 FPS：30/60"，默认 60），内部是一整套预算束；只降频率/字节/容量，不关任何能力；超限走既有 LRU/容量拒绝，不硬中断；档位 = 一条命令热切换。

| 维度 | standard（60） | efficient（30） | 落点 |
|---|---|---|---|
| 帧节奏 | 60Hz | 30Hz | FrameDriver 帧间隔改可变 |
| CPU 每帧软预算 | 5ms | 10ms | M1 counter + HUD 超限指示；不硬中断 |
| offscreen 池上限 | 512MB | 256MB | 纹理池 byteBudget 档位帽 |
| 纹理解码缓存上限 | 1GB | 512MB | 纹理缓存准入上限（M4.2 落地） |
| sprite/粒子 resident | 1.0× | 0.5× | 既有预算类系数 |
| 音频频谱/动态文字 | 30Hz/事件驱动 | 不变 | — |
| 质量（mip/分辨率/特效） | 全量 | 全量 | — |

生效：cadence 下次排帧生效；池预算下次淘汰生效；缓存上限下次准入生效。30 档靠频率减半降总量，单帧 CPU 或因 simulationFrameTime 变大略升，以 M1 实测为准。

### 4.2 属性热更新

现状属性调节触发整卡重启；目标：调节 → `setProperty(properties, revision)` → liveState 值更新 + revision 递增 → 下一帧既有 value-only 路径消费。失效域分类：数值/颜色/bool/文字 → value-only；纹理 URL 类 → resource-generation（复用 deferred 装载机）；combo/可见性默认/结构类 → program-variant/topology 局部失效；任何一类不重启。应用失败保留重启路径兜底。UI 滑杆 ~150ms 去抖；验收 = ≤1 帧 + 轻量上传内可见、launch 状态不重放。M0 进程内实现，M5 同命令走管道。

### 4.3 进程分离

参照 video daemon：`Process()` 孵化 `Contents/Helpers` 工具、stdin/stdout newline JSON、崩溃指数退避重启、daemon 内自建桌面级窗口。新 daemon 内含完整 Scene runtime；进程间只传 coarse 命令与轻量 counter，`MTLTexture` 等进程内对象不跨进程；诊断旁路留 daemon 内。IPC 合同：命令 `loadScene{rootURL,propertyOverrides,profile}` / `setProperty{...}` / `setDisplayConfiguration{screens}` / `setPerformanceProfile{fps}` / `setMuted` / `pause` / `resume` / `shutdown`；事件 `launchStateChanged` / `firstFramePresented` / `frameStats`(1Hz) / `error` / `exited`。隔离目标 = UI 响应、崩溃、堆、VM、编译器故障隔离；不承诺总 CPU/GPU 下降。

### 4.4 公共层拆分图

| 批次 | 内容 | 从 | 到 |
|---|---|---|---|
| 一（M0） | 设置容器+分区枚举 | Modules/VideoLibrary/UI | Shared/Settings |
| 一（M0） | 静音公共态、WallpaperEngineCommand+multiplexer | VideoLibrary/Core、新建 | Core/PlaybackControl |
| 二（M5） | daemon 会话（孵化/退避重启/管道帧协议） | Core/Playback、WallpaperDaemonSources/Support | 新同步组 DaemonKit（挂 app+daemon 双 target） |

### 4.5 语言选型

默认 **Swift**（AppKit/Metal 集成、产品编排、资源所有权、生命周期、命令编码）。引入 Rust/C/C++ 须同时满足：① Instruments/M1 数据证明的 CPU 热点或全新独立组件；② 算法本质适合 contiguous 低级处理或需要该生态的既有库；③ ABI 边界小而稳定；④ 非每对象/每粒子/每 draw 高频跨语言调用；⑤ 收益显著且可测。现有异构已落在正确位置（QuickJS=C、glslang/spirv-cross=C++ 子进程、shader=MSL）。Rust/C++ 候选域（待 M1 数据裁决）：package/binary 解析、压缩与纹理解码、粒子/物理 kernel、daemon 管道帧协议。渲染主链、UI、控制面不迁移语言；**禁止为语言一致性而迁移，也禁止为语言新鲜感而引入**。防屎山规则优先于一切性能动机：单一权威、双消费者准入、每批消融净路径数不增、改 owner 不包 wrapper。

## 5. 批次 DoD（每批完成定义）

1. `git status` 划 owned paths；有他人 staged/unstaged 的文件不碰；单职责提交。
2. **消融记录**：本批触达的效果链，列出禁用/删除的旁路与最短链论证；被删路径的 fixture/golden 转行为合同或删除；新增/删除路径数计入报告（净路径数不得增长，除非是新能力）。
3. before/after：受影响 M1 指标数字；架构纠偏类附静态违规证据即可。
4. 能力不回退：Fast Scene Suite 相关成员 + ≥2 代表样本人工播放确认；能力台账触达项同步。
5. 报告：改了什么/为什么/语义影响/before/after/剩余热点/回滚方式。
6. 若批次改变了[事实架构地图](runtime-as-built-map.md)中的所有权或不变量，同批更新该地图与本计划卡状态。
