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

**交接门（2026-09-14，审计基点 c39d78a7）：提交级审计已闭合，全工程验收尚未通过。** 基线 `ec490e1b` 与 `origin/codex/scene-capability-baseline` 一致，35 个本地提交；当前基点及 15 个历史产品提交均已在隔离 checkout 逐一重跑 checkpoint，全部 BUILD SUCCEEDED；另已补建初始文档提交的产品树；按 App 源码、Xcode 工程及 checkpoint 脚本树校验，35 个提交均覆盖到 16 个实测构建树，构建成功不覆盖语义与运行门。已发现 M0 播放态协议分发、M3.2 同步 launch generation、M5.2 EOF/协议事件的纠偏项，须先逐项修复/验证，再进入 M5.3。历史卡内 ✅ 只表示原批落地声明，不等于本轮审计或完整 DoD 通过。Fast Suite manifest 仍含 `selection-required`；两个代表样本已选 `2938612768`、`1300076567`，用户已确认仅恢复同步 generation 的签名 Debug 构建中，两份样本画面与动画正常；后续控制面及回滚候选亦已重跑：签名 Debug 可执行文件 SHA-256 `b39711d88de66e0ee1478f36a6add48bec746c1325899a7c30d58a5389510c36`，两样本各 20 秒、GPU 失败均为 0，用户再次确认画面与动画正常；graph 严格 matrix 的原有 22 项失败仍在，未代替 Fast Suite。当前候选 checkpoint 与 45 项定向测试通过。 已分别提交同步 generation（`c9130e68`）、命令分发（`b2bd56fe`）、executor memo 撤回（`17ecccce`）及 daemon 原型撤回（`df47b579`）；四个提交各自的隔离 checkpoint 均 BUILD SUCCEEDED。消融：generation/命令修复复用原路径，executor 删除一条 Bool memo 路径，daemon 删除一条未接入 CLI 路径，未新增权威或视觉分发。

**交接纠偏闭合（2026-09-14）：** 上述 M0 分发、M3.2 generation 与 M5.2 生命周期反例均已用独立提交或后续安全批修复；原型撤回后没有直接续写不安全路径。提交级构建审计与三份交接文档核对已完成。M5.4 已用 requestID/recordID 事件投影关闭 M0.5 pending 归属缺口；Fast Suite 尚有四个 `selection-required` 成员、现役树的 code-health 超限等工程余项继续由对应工位卡和 M6 门管理，不能由交接门闭合推导完整工程验收。

交接治理校正：历史 Light Shafts 文件链接改为明确退役标记，两个现役 direct-draw 几何类型补入目录合同及事实地图；semantics coverage / 文档登记 / governance 共 31 项通过，不代表运行验收完成。


交接测试纠偏：静态 uniform 缺省/声明冲突在 launch envelope 撤销 owner，executor 测试改验该阶段后继续执行 previous-current、suffix、GPU completion 与像素断言；executor + 独立 finalizer 共 27 项通过。

卡格式：**改哪里 → 怎么做 → 验收门 → 回滚**。状态记录于卡内标题行；执行细节与 file:line 锚点查[事实架构地图](runtime-as-built-map.md)。

### M0 控制面命令化 + 公共层第一批（同进程）

- **M0.1 命令层入公共层** ✅ f33b2386+交接纠偏：`Core/PlaybackControl/` 三件 + Scene 处理端 + video 处理端 + isPlaying 协议要求（交接审计补齐）+ 可执行命令分发测试通过 + 状态栏三键切公共权威。原落地 f33b2386：`Core/PlaybackControl/` 三件（WallpaperEngineCommand / PlaybackEngineControlling / PlaybackCommandMultiplexer，未消费命令显式返回 false）；Scene 处理端接真实入口（loadScene→requestLaunch、pause/resume→setPlaybackPaused、stop→stop()）；video 处理端（pause/resume/stop→WallpaperEngine，setMuted/switchNext→WallpaperManager）。验收：UI 无直触引擎内部 ✅（状态栏已改）；web 处理端待 web 模块需要时补。
- **M0.2 静音态升公共层** ✅ 4626ed6e+30d545d4：公共静音权威 `PlaybackMuteState` 全链闭环——读取点（状态栏菜单/设置开关/全局热键）、音量滑杆 0 边界同步、daemon 回放（client 读权威重放 setMuted）全部切公共权威；video `previousAudibleVolume` 恢复语义保全（独立审查确认）；死镜像清理。验收：任一引擎激活时菜单/设置静音一致生效 ✅（命令链 daemon smoke + 审查确认）。可选跟进：设置面板对 playbackMuteStateDidChange 的活性回读（重开面板即同步，不阻塞）。
- **M0.3 设置容器拆公共层 + FPS 档** ✅ cbd96207+2c72b9d9：文件迁移/依赖倒置/FPS 档/audio 双引擎全部落地。`AppKitSettingsView` 1500 行视图 60 处引用切换为 `dependency.settings/actions`；`SettingsWindowController` 构造 `AppSettingsPanelDependency(settings:actions:)` 注入；FPS 30/60 分段 + 命令层下发；静音经 `PlaybackMuteState` 公共权威。
- **M0.4 状态栏菜单打通** ✅ f33b2386：三键改发命令；播放标题/图标按 video+scene 任一在播判定；注册点=setupStatusBar。Scene 静音消费随 M0.2 补齐。
- **M0.5 播放按钮交互** ✅ ce13c3c0+M5.4：pending 状态在 SteamWorkshopService 保持单一 recordID；点击立即置位、早退即清。Scene client 只投影 requestID/recordID 匹配的终态，runtime switch 通知携带 recordID，service 只清除匹配记录；跨请求门证明旧 A 终态不能清除仍在收集纹理书签或等待 accepted 的新 B。video/web 保留 1.5s 身份不足兜底；详情、共享卡片与两网格继续投影同一 pending。
- **M0.6 属性热更新** ✅ 既有 liveState 链+M5.4 pipe：编辑器持久化仍只有 App 的 SteamWorkshopService；typed `SceneUserPropertyValue` 以 revision+recordID 经 daemon 管道送入唯一 Host liveState。daemon 明确回传 `propertyUpdateResult`；接受时同一 surface 下一帧生效，拒绝时 client 将值先合并进 authored intent，再触发完整 `loadScene` 兜底。数值属性样本验证同 daemon 生效并在强杀恢复后保留；无 live consumer 的属性验证拒绝后同进程完整重载。SceneTexture 变更携带安全作用域书签并直接完整重载以刷新资源。
- **M0.7 性能档两档** ✅ cbd96207：`PlaybackPerformanceProfile`（60/30，UserDefaults）；宿主持有档位，FrameDriver 帧间隔与 busy 重试间隔由档位派生（硬编码 60Hz 常量删除），`.setPerformanceProfile` 热切换下次排帧生效。预算束其余维度（池帽/缓存帽/resident 系数）随 M4.2 接入同枚举。
- 与 M1 文件不重叠，可并行。

### M1 度量地基

- **M1.1 常开定长 counter** ✅ e04d6a26+300f6a1a+本批：hub 共 21 个定长槽，覆盖帧分类、cpuFrame/renderer/drawableWait、7 个帧内阶段 micros、真实 Metal draw 提交、pipeline state bind、geometry draw 与实际视觉 fallback 分支；launch 五阶段/firstVisibleFrame 保持首次时间戳。资源量由 daemon 1Hz 采样：`gpuAllocatedBytes` 使用 Metal 的进程/device 总分配量，避免把 buffer/PSO 混报为 texture-only memory；`renderTargetPoolBytes` 汇总现有有界 offscreen/named/depth/framebuffer 池的驻留预算值。全部 draw/bind 点进入同一 hub，资源采样不触发 lazy pipeline factory；现有 `SceneFramePerformanceTelemetry` 仍只用于 debug 证据窗口。
- **M1.2 signpost** ✅ e04d6a26：OSSignposter 薄封装 + launch-state 事件 + firstVisibleFrame 首次记录。帧内阶段 interval 待按需补（counter 已覆盖归因）。
- **M1.3 Debug HUD** ✅ d427ddaf：`ScenePerformanceHUD`（仅 DEBUG）浮窗 1Hz 差分展示 + 每 5s 结构化 `MWX PERF:` NSLog（累计均值/阶段分解/launch 时间戳），启用门 = evidence window 或 MYWALLPAPERX_SCENE_PERF_HUD=1；不进帧路径，Release 无此类型。
- 验收：基线**机制**就绪 ✅；**M1 基线数字（2026-09-14，样本 1300076567 隔离副本 /tmp/mwx-baseline，Debug+evidence 窗，20s 稳态，6 layers/1 image/0 effects 简单场景）**：稳态 60fps（rendered 1189/busy 0/dropped 0）；cpu frame 累计均值 3.92ms（renderer 2.77 + drawable 0.28）；阶段均值 world-resolve 0.01 / frame-admission 0.30 / **prepass 2.03（占 cpu 52%，首要观测项）** / layer-loop 0.31 / seal 0.07；draw=1/帧；startupElapsedMS=941.7（含 0.4s 调度延迟；runner 同步 launch 路径不经 publishLaunchState——launch 阶段日志在同步路径缺失，已记 M2 后补）。原始日志 /private/tmp/mwx-baseline/run-before.log（临时区）。该样本无 graph/particle，trace/plan 重验证等风险项在复杂样本上占比更高，Patch A/B 后在同类简单样本上先比绝对值。**方法学警示（2026-09-14）**：全部基线/after 数字采自未签名 Debug 构建 → glslang 路由按许可合同不可用，effect 一律走 bounded frontend 回退（cpu/admission 口径=回退模式）；与生产签名模式的绝对值不可直接互换，模式内 before/after 对比有效。

  **M1.1 收尾实测（2026-09-14，签名 Debug，同一机器、1300076567→2938612768 隔离副本、各批同为 20s）**：before `rendered=521/busy=23/dropped=0/cpuFrameMs=14.027`；after `525/23/0/14.459`，画面截图正常、同一 daemon 完成切换并退出。after 回传 `drawCalls=23022/pipelineStateBinds=23022/geometryDrawCalls=2337/fallbackBranches=0/gpuAllocatedBytes=885653504/renderTargetPoolBytes=88628632`。单次整段 CPU 差值混有 shader 准备与 Debug 逐帧诊断，不能归因给 counter；独立 `-O` hub 微基准把一次 bind+draw+geometry 三槽更新测为 38.83ns，按该次 graph 的 43.85 次命令/帧折算约 1.70µs/帧，低于 M1.3 的 0.1ms 常开预算。该数字只界定 hub 更新成本，不等同生产整帧性能。

  最终产品树的 formal checkpoint 共 65 个模块全部通过，checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`、严格 codesign 有效；code-health 保持交接时的 `181 warnings / 19 errors`，本批触达的 `SceneMetalRenderer.swift` 行数回到 HEAD 的 825，`SceneDependencyFrameRuntime.swift` 为 799，没有新增或放大 hard-limit error。最终签名产物再以隔离副本验证强杀恢复：simple `1300076567` 为 `rendered=3641/busy=0/dropped=0/drawCalls=25472/geometryDrawCalls=21831`，graph `2938612768` 为 `433/23/0/55424/433`，两者 pipeline bind 与 draw 提交数一致、fallback 为 0、daemon 退出后无孤儿；恢复后的 Metal 直出截图分别保持窗边人物与霓虹唱片完整构图。消融：删除 renderer 每层 `.encoded` 的 1 个近似 draw 计数入口，计数改附着到既有 9 个真实 Metal primitive 提交和对应 bind 点；没有新增 render/fallback 选择分支，产品视觉路径净增 0，权威数不变。

### M2 引擎减税

- **M2.1 Patch A** ✅ 63de923f：trace 门控（usesDebugEvidenceWindow，Release 恒 nil）+ GraphComposition subjects 循环守卫（收益主体）+ 7 签名可选化；同批修复 utilityCaptureTelemetry 每帧注册 handler（改首次终态后停止，每层恰一次）。实测（graph 样本 2938612768 隔离副本，正常模式 20s）：after 4 tick 全程干净 exit 0，cpu 34.18±0.1ms 稳定——trace 成本本就 <0.5ms/帧，本批收益为架构合规（Release 零 evidence 对象）+ handler 有界化而非该样本毫秒级增益；旧二进制正常模式出现主线程停滞 11s + exit 133（随旧路径消失，根因未查，记观察项）。admission 25.5ms（cpu 62%）不变——M3/M4 目标。
- **M2.2 Patch B** 🔶 已实施并回滚（2026-09-14，实测回归）：两版实现（立即渲染版与 deadline 感知版）在 graph 样本 2938612768 正常模式实测均引入 **busy 509-534 次/20s、attempts 翻倍**（Patch A 基线 busy=0、attempts=rendered），fps/CPU 无改善。根因：GPU 完成事件在编码期中途到达（frame N 的 GPU drain 发生于 frame N+1 编码期），事件路径与 cadence Timer 互相激发产生 attempt 放大；'completion 把 host 唤醒即可消除轮询'的前提在该样本不成立（正常模式 busy 本来=0，CPU 串行 34ms 使下次 attempt 时 GPU 已完成；busy 只在 evidence 读取拖慢 GPU 时出现=诊断模式）。保留资产：acceptance 翻转检测的完备性证明（唯一翻转点=completeCommandBuffer）与两版实现 diff（git 历史）。**重启条件**：出现真实 busy>0 的常规工作负载（GPU 时长>cadence 的样本）时，按 deadline 感知版重启并重测。2ms 兜底轮询维持现状（正常模式无实测成本）。帧时钟权威唯一（coordinator=准入权、FrameDriver=节奏权，回调只是边沿通知）。
- **M2.3 Patch C** ✅ 6aa74ba2：coordinator 持有 `claimExecutionByToken` 缓存 + 独立 NSLock（公共路径在主锁外）；catalog 不可变/token 含 ownerID → 随实例生存即正确、无失效需求；ClaimedExecution 全 let 共享安全。实测 graph 样本无回归（cpu 33.5ms vs 34.2ms、busy=0）。定位：Phase 3 第一小步，单层收益 μs 级、随 graph 层数线性放大。
- 验收：各批独立提交；M1 before/after；消融确认被门控路径关闭后样本无行为差异。

### M3 消融减法 + hot path cleanup

- **M3.1 Frame storage** ✅ 核心 07b2d871：registry liveSelectionDigest 增量维护已落地——entries 写入点仅 2 处（set(status:)/publish(resource:)）+2 处 removeAll，O(changed) 折叠；snapshot() 零全量 fold；digest 不变量 harness 5 组全过（确定性/可逆/generation 值稳定/相异 fact/entryCount，harness 存 docs/scene/evidence/m31-digest-test/，python 驱动被 Mimosa 钩子误报拦截、可人工运行），graph 样本实测无回归（cpu 34.4-34.7ms 噪声带内、busy=0）。**余项显式 defer 至 M4.3**（2026-09-14 裁决）：beginFrame 无变化帧直通与 overlay CoW 消除——判定信号需逐字段比对 8 类输入（含 publication/generation 生命周期语义），误判=陈旧 registry（as-built map 雷区类缺陷），实测收益 µs 级（无变化帧成本=O(N) 便宜槽位写，非 fold/非 25.5ms 量级）；且 M4.3 frame storage 重设计将整体吸收（overlay CoW 与重发布同属一个存储模型）。
- **M3.2 启动链去串行** 🔶 交接修复：恢复同步 launch 每次尝试的 SceneScript generation 递增，18 项启动测试通过；签名 Debug build 成功，两份代表样本已获用户画面与动画正常反馈（仅 generation 修复构建）；graph 严格 matrix 仍有 22 项失败，未标记本批完成。原归因补录完成（1a7e4020）：同步 launch 路径接入 M1 hub 阶段记录，graph 样本（85L/44img/62fx）实测 TTFVF 归因：包解析+IR 0.68s → admission+材质资产解码 2.95s → **catalog 尾+caps+QuickJS+FS join+activate 7.88s（主桶）**；firstVisibleFrame 与 launched 同拍；startupElapsedMS=11934.7ms。**关键归因**：材质资产解码→caps→QuickJS 为真数据依赖串行链，原“解码与 QuickJS 重叠”切片前提不成立。**细分实测（d800ce12 锚点，同样本）**：材质资产解码 728ms；capability catalog 构建 6685ms（主桶 85%）；QuickJS 定点编译 266ms；device/FS join 各 0-5ms（后台 worker 并行已吸收——双 join 并行化无收益，裁决不实施）；activate 表面构建 203ms（独立段）。**caps 6.7s 的定性修正（2026-09-14 二次核查）**：caps 内部已是 `concurrentPerform` 并行（Capability.swift:381），且冷/热两次运行等时（7413/7363ms）→ 非冷缓存问题；真因 = 未签名 Debug 构建中 helpers 为 adhoc 签名，`signedByProductTeam` 按许可合同正确拒绝 → 全部 effect 走进程内 bounded frontend 回退分析（CPU 大户）。生产签名构建走 glslang 路由 + 磁盘 artifact 缓存，该成本大部分不存在。**M4.1 据此改聚焦**：caps 启动成本属 dev 环境回退路径（降优先级）；保持主目标 = 帧路径 admission 25.5ms 的 plan 重推导（与签名无关）。**pool plansMemo 已落地**（08c70d53，内容键=capabilityToken+layerID+尺寸+targets，reset 清空，失败不缓存）：生产签名模式消除每帧 N×make；**回退模式不可测**（effect 全拒 → preflight 0 次进入，探针已移除）——sample 采样证实回退模式 adm 26.8ms 分散于逐层降级判定（TextureSlotBinding.valid/entryMix/cursor/publishLayerSnapshot），记 M3.3/M4 后续观察项。**executor validate memo 已撤回（交接纠偏）**：`8b3a8d58` 把 expected-plan 与 stored-plan 的比较结果缓存为 Bool，却没有把 stored plan 纳入键。相同 capability/generation/角色/尺寸/targets 下，更换 stored plan 的命令表仍被接受；先缓存失败又会误拒合法 plan。已恢复每次完整 plan 对比，独立生产 validator 反例通过。pool 内容缓存保留；executor 优化待 prepared plan 身份与容量门重新设计，不再宣称该 memo 等价或完成。原手动 Hashable 绕过随不安全键一起撤回。
- **M3.3 持续消融**：见 §5，贯穿 M2–M5。

### M4 表示优化

- **M4.1 Phase 3 v2** ✅ 4c15ce95（独立审查通过、无 FAIL）：`makeInputsDigest`（role+extent+targets 异或 fold，`SceneAuthoredEffectInputRole` 补 Hashable）在 pool 推导期计算 → `SceneLayerGraphTargetPlan.Stage` 携带 → allocator `makeMapped` 铸进 `SceneGraphRenderTargetTable.makeInputsDigest`；帧路径 validate 以当帧输入重算摘要 O(1) 比对，命中即接受 stored plan（make 纯函数 + table `let plan` 不可变 ⇒ 摘要命中即等价），未命中回退完整推导+比较（语义逐分支一致）。纹理 `===` 门与 functionTargets 语义门保留；graph 身份经 capability token 绑定链钉死（catalog 不可变）。编译器缺陷：Hashable 合成器对含 Set 成员的 struct 在 app upcoming flags 下错误失败，手动 ==+hash 绕过。默认参数移除（编译器强制摘要传播）+ 无调用者便捷入口删除（消融净路径 -1）。扁平化三条产品路径与 executor memo 重设计（含 stored plan 身份）待后续批次。实测：回退模式 adm 25.2-25.8ms 无变化（该模式下 graph 候选少、make 路径少触发），生产签名模式（graph admitted）为收益路径，待签名运行实测。**稳态 sample 归因（2026-09-15，daemon 模式 graph 样本 2938612768 稳态 6s 采样）**：admission 子树占主线程 78%（2005/2549 samples）；子分解——composition preflight 逐层循环体 ~1322 samples（最大项，分散成本非单一热点）、prepareMaterialPass 416、overlayingGraphResources 136、AllocationCache preflight ~180。pool plansMemo 覆盖的 make 仅占极小部分——admission 真实热点是逐层循环体自身的 Swift Debug -Onone 编译开销，生产 Release -O 构建预计大幅缩减。样本 2938612768 复杂场景稳态 cpu 32.7ms/frame（~30fps 等效）。
- **M4.2 Phase 4 资源缓存** 🔶：executor reset 热缓存子项已落地——reset 只推进命令世代以拒绝旧 PreparedPass，保留由完整 `MetalCompileStateKey`（shader 语义/render state/attachment/sample/write mask/device）寻址的不可变 PSO 与负缓存；相同内容在 reset 后不再重新 `makeLibrary`/创建 PSO。MTLLibrary 复用子项亦已落地：PassEncoder 按完整 `metalSource` 缓存 library 与编译失败，launch warmup 的不同 PSO 变体并发请求同一源时只允许一个编译者，其余等待并消费同一结果。colorBlend pipeline 启动预热亦已落地：不可变 PSO state 由 launch 级 pipeline repository 单次解析，描述符含非零 layer blend 时在既有设备资源 worker 预热；per-surface framebuffer snapshot 仍由各 compositor 独占。loose PNG/JPEG 与内嵌 TEX ImageIO 解码去重亦已落地：同一 loader 内按完整文件身份复用解码结果，纹理仍按 device/purpose 分开。资源上传 queue 合并亦已落地：一次 launch 为每个 Metal device 懒建并负缓存一个共享 upload command queue，注入全部 launch/deferred/surface 资源消费者；renderer 的 per-surface frame command queue 保持独立。纹理解码缓存字节上限亦已接入同一性能档：daemon Host 持有 launch 级共享预算，standard/efficient 分别为 1GB/512MB，降档从下一次准入起拒绝新增中间解码缓存但不阻断当前上传，也不驱逐既有发布纹理。其余：userPropertyTextures 字符串键→整数 ID。

  **reset 热缓存实测（2026-09-14）**：Metal harness 在同一 encoder 内先准备 pipeline，再 reset；旧 PreparedPass 因命令世代变化被拒绝，随后相同 Program prepare 成功且 `pipelineCompilationAttemptCount` 不变，正/负编译缓存及累计统计均保留。改动路径选择的 26 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，可执行文件 SHA-256 `413015c2e179bd52d0a8473caa8dd762dcc2d1b67e35af80e6ab69c7a739468c`。现役 code-health 仍被本批外既有 hard-limit 债阻断，触达的 PassEncoder 为 508 行、未产生新 hard error。签名产物用全新隔离副本强杀恢复：simple `1300076567` 两次 first-present，末值 `rendered=1119/busy=0/dropped=0/fallback=0`；graph `2938612768` 两次 first-present，每次 launch warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`，末值 `135/23/0/0`，两份 Metal 直出截图均保持原构图，退出后无归属进程。daemon 重启会重建 executor，故同 executor reset 的零重编译结论来自上述计数反例，样本只证明当前完整运行链与画面未回退。消融：reset 删除 7 条清缓存/清统计语句，只保留既有命令世代推进；视觉路径净增 0，权威数不变。

  **MTLLibrary 精确源复用实测（2026-09-14）**：Metal harness 以两个不同完整 PSO key（不同 attachment format）并发准备同一 `metalSource`，得到 2 次 PSO 编译尝试但仅 1 次 library 编译；第二个 format 仍取得独立 PSO，证明复用边界没有吞掉 render-state/attachment 语义。该测试与 selector 选中的 26 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，可执行文件 SHA-256 `7bad2bf1c74ebc6ac0560324b821d158b0b14e7f16f0c485c813936f13585b0b`。code-health 仍为本批外继承的 `181 warnings / 19 errors`，触达的 PassEncoder 为 564 行且没有新增 hard-limit error。签名产物用另一组全新隔离副本强杀恢复：simple `1300076567` 两次 first-present，末值 `rendered=1120/busy=0/dropped=0/fallback=0`；graph `2938612768` 两次 first-present，每次 launch warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`，末值 `136/23/0/0`；四张恢复前后 Metal 直出截图经本批逐张检查，人物场景与霓虹唱片构图完整一致，退出后无归属进程。样本只证明签名完整运行链与画面未回退，library 编译去重结论来自上述精确计数反例。消融：既有唯一 `makeLibrary(source:)` 调用移入同一 PassEncoder owner 的 exact-source cache 和 in-flight 合并门，没有新增视觉/fallback 路由；产品视觉路径净增 0，权威数不变。

  **colorBlend 启动预热实测（2026-09-14）**：repository harness 证明构造 repository 不触发编译、首次解析只构造一个 colorBlend state、同 repository 后续消费者复用同一 identity；launch 接线测试锁定仅在 descriptor 存在非零 layer blend 时于设备资源 worker 解析。selector 选中的 19 个 formal 模块全部通过，最终 checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，可执行文件 SHA-256 `13ca293808a9085e3e7de4c3419966aca540d9b50e25e5bd8728be4462dc0155`。code-health 保持本批外继承的 `181 warnings / 19 errors`，本批产品文件均低于 800 行且没有新增 hard-limit error。签名产物以全新隔离副本强杀恢复：simple `1300076567` 为 `rendered=1121/busy=0/dropped=0/fallback=0`，graph `2938612768` 为 `143/22/0/0` 且两次 resolved-material warmup 均为 `20/20 ready`；另加含 4 个 `colorBlendMode=12` 层的定点样本 `3782740481`，两次 actual present 后为 `445/33/0/0`。六张恢复前后 Metal 直出截图经本批逐张检查，窗边人物、霓虹唱片、持乐器人物及其高光/背景叠色均保持完整一致，退出后无归属进程。消融：删除 compositor 内每个 surface 首次命中时各自编译 colorBlend PSO 的路径，改由现有唯一 launch repository 持有 1 个不可变 state；没有新增视觉/fallback 路由，snapshot 仍为 per-surface，产品视觉路径净增 0，权威数不变。

  **loose PNG/JPEG ImageIO 解码去重实测（2026-09-14）**：`SceneTextureLoader` 在既有 owner 内按完整 `SourceKey`（标准化路径、size、mtime、device/inode、ctime）缓存成功 `CGImage` 与失败结果；同一源用于 premultiplied/preserved 两种 purpose 时只执行 1 次 ImageIO decode，但继续生成两个目的语义不同的 Metal texture，文件身份变化仍会失效。直接 harness 与 selector 选中的 10 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，可执行文件 SHA-256 `8a749ca3c23f62c8ae6bbf6d55d7e4d3cf326c0e18527d2ac681477be7632b64`。code-health 保持本批外继承的 `181 warnings / 19 errors`，触达产品文件为 433 行且没有新增 hard-limit error。签名产物以全新隔离副本强杀恢复：simple `1300076567` 两次 first-present，末值 `rendered=1121/busy=0/dropped=0/fallback=0`；graph `2938612768` 两次 first-present，末值 `142/23/0/0`，两次 resolved-material warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`。四张恢复前后 Metal 直出截图经本批逐张检查，窗边人物与霓虹唱片构图、文字和粒子层完整一致，退出后无归属进程。计数反例证明同 loader、同文件身份的跨 purpose ImageIO decode 从 2 次降为 1 次；两个样本只证明签名完整运行链与画面未回退，不外推 corpus 级性能。消融：删除 loose 图片跨 purpose 重复的 `CGImageSourceCreateImageAtIndex` 路径，复用发生在既有 loader/SourceKey 失效域内；纹理目的语义、视觉/fallback 路由与权威数均不变，产品视觉路径净增 0。

  **内嵌 TEX ImageIO 解码去重实测（2026-09-14）**：format-0 mip 链及 legacy embedded payload 在既有 `SceneTextureLoader` 内按完整 `SourceKey` 缓存成功 `[CGImage]` 与失败结果；mip uploader 新增接收已解码图片的入口，原始 mip 入口仍保留相同行为。定点 harness 将同一单 mip TEX 依次作为 premultiplied 与 preserved-channel 纹理加载，取得两个不同 Metal texture，而 `texEmbeddedImageDecodeAttemptCount` 为 1。selector 选中的 10 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，可执行文件 SHA-256 `2d2d6d90780689c1aa5e33fb52d3c98337c310a5896527ed5150d8c7a63eb599`。code-health 保持本批外继承的 `181 warnings / 19 errors`，触达产品文件分别为 467/399 行且没有新增 hard-limit error。签名产物以全新隔离副本强杀恢复：simple `1300076567` 在 20 秒门内两次 first-present，末值 `rendered=1117/busy=0/dropped=0/fallback=0`；graph `2938612768` 的首次 20 秒冷门因两轮约 7.5 秒资源准备而在第二轮完成前到时，35 秒重试两次 first-present，末值 `268/32/0/0`，两次 warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`。四张成功门的 Metal 直出截图经本批逐张检查，窗边人物与霓虹唱片构图、文字和粒子层完整一致，退出后无归属进程。计数反例证明跨 purpose 解码去重；运行样本只证明当前签名完整链与画面未回退，不把延长后的门解释为首帧改善。消融：删除同 loader、同文件身份的内嵌 mip/payload 跨 purpose 重复 ImageIO decode；mip 维度校验、purpose 级 raster/texture、视觉/fallback 路由和权威数均不变，产品视觉路径净增 0。

  **资源上传 command queue 合并实测（2026-09-14）**：`SceneTextureUploadCommandQueue` 在既有 launch 资源边界内按 Metal device registryID 懒建一个线程安全 queue，并缓存不可用结果；同一实例注入材质资产、base/deferred/static-model/particle 纹理、user-property 纹理和跨 surface 媒体缩略图，设备或场景整体替换时释放。renderer 的 per-surface frame queue 仍只负责帧 encode/commit。定点 Metal harness 证明同一 loader 的跨 purpose 上传以及两个独立 loader 共享注入 owner 时，queue 创建尝试均为 1。selector 选中的 35 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，主程序 SHA-256 `53ddd84fd80112a1ee235a7dfe47d574d2e2c63934505aba8d8c306c7bb7db62`，helper SHA-256 `6821cc1c215e4b238930e5f3f4f7cd320bf0cc180af429871b9f054af06a7036`。code-health 保持本批外继承的 `181 warnings / 19 errors`；既有超限的 Launch 文件保持 846 行净零增长，其余触达产品文件均低于 800 行，没有新增 hard-limit error。签名产物以全新隔离副本强杀恢复：simple `1300076567` 两次 first-present，末值 `rendered=1121/busy=0/dropped=0/fallback=0`；graph `2938612768` 两次 first-present，末值 `304/27/0/0`，两次 warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`。四张恢复前后 Metal 直出截图经本批逐张检查，窗边人物与霓虹唱片构图、文字和粒子层完整一致，退出后无归属进程。样本只证明当前签名完整链与画面未回退，不把累计帧数外推为性能改善。消融：两个资源 uploader 的逐上传 `device.makeCommandQueue()` 调用删除，产品资源上传只保留一个 launch 级构造点；未新增视觉/fallback 路由，五类产品协议和权威数不变，产品视觉路径净增 0。

  **纹理解码缓存预算实测（2026-09-14）**：`SceneTextureDecodeCacheBudget` 由 daemon Host 按性能档持有并注入一次 launch 的 material/base/deferred/user-property loader；准入只统计可重建的 TEX 源数据与 ImageIO `CGImage` 字节，loader 释放时归还，已发布 Metal texture 仍由原产品 store 管理。定点反例先准入 PNG，再热降预算至 0；新 loader 两次不同 purpose 的 JPEG 加载均继续完成解码/上传，但不写中间缓存、解码计数为 2、拒绝计数递增，既有 resident 字节保持不变，loader 销毁后归零。selector 选中的 36 个 formal 模块全部通过；checkpoint 与 Developer ID 签名 Debug 构建均 `BUILD SUCCEEDED`，严格 codesign 有效，主程序 SHA-256 `0da97984c20ea08396ce199fd1001cfcc68c8a1f0d55edbd1e6b8c1272251848`，helper SHA-256 `6821cc1c215e4b238930e5f3f4f7cd320bf0cc180af429871b9f054af06a7036`。code-health 保持本批外继承的 `181 warnings / 19 errors`；既有超限 Launch 文件保持 846 行净零增长，本批没有新增 hard-limit error。签名产物以全新隔离副本强杀恢复：simple `1300076567` 两次 first-present，末值 `rendered=1116/busy=0/dropped=0/fallback=0`；graph `2938612768` 两次 first-present，末值 `rendered=266/busy=27/dropped=0/fallback=0`，两次 warmup 均为 `91 planned/20 unique/20 ready/0 failed/20 attempts`，`phase=finished recovered=true presents=2 pids=2`。四张 Metal 直出截图经本批逐张检查，窗边人物与霓虹唱片的构图、文字和粒子层完整一致，退出后无孤儿。复杂样本稳定段 CPU 约 42ms、GPU 约 889MB，继续作为 M4.3/M3.2 优化目标；本批样本只证明完整运行链和画面未回退。消融：把既有无界中间解码缓存写入替换为同 owner 的共享字节准入，超限沿原解码/上传路径继续执行；没有新增视觉/fallback 路由、失效域或权威，产品视觉路径净增 0。
- **M4.3 Phase 5 frame storage**：帧提交快照最小化（uniform/event/generation table/mutation queue 方向），不复制大对象树。

### M5 进程分离 daemon 化（主线）

- **M5.1 设计门** ✅ 4a835efc：交付 [Scene Runtime Daemon 契约](scene-runtime-daemon-contract.md)（stable-contract 已登记）——IPC v1 冻结、生命周期/崩溃退避语义、线程约束审计结论（runtime 原样搬迁、帧循环留 daemon 主线程、帧线程隔离明确排除）。设计门已过，M5.2 起按步骤实施。
- **M5.2 最小 daemon（同二进制模式，契约 §2 修订）** ✅ 安全重做：App `@main` 在 `--mwx-scene-daemon` 下只装配 Scene endpoint 与 accessory `NSApplication`，不装配主 UI；IPC v1 将 load/property/profile/mute/pause/resume/shutdown 解码为 typed 命令，坏版本、坏载荷和未支持命令显式报错。launch 事件携带 requestID/recordID；首帧只由同请求 `CAMetalDrawable.addPresentedHandler` 发布，并异步离开 Core Animation 回调以避免与主线程 `nextDrawable` 锁反转。stdout critical 事件串行，1Hz stats 只保留最新待写值；EOF/shutdown 先 `Host.stop()`，再在各既有 surface command queue 提交 barrier 并等待 GPU terminal，最后发送 `exited{code,gpuDrained}`。签名 Debug 候选严格 codesign 通过；自动选择的 31 个聚焦模块全部通过，checkpoint BUILD SUCCEEDED；code-health 仍被现役树既有超限文件阻断，未伪报通过。隔离 `2938612768` 与 `1300076567` 均取得真实 first-present、持续帧统计、`busy=0/dropped=0`、可见画面及 `gpuDrained=true` 退出；graph 还验证未知命令拒绝及 profile/mute/pause/resume 管道消费。M5.2 只提供 daemon endpoint，主 App 尚无孵化/client，普通产品 Scene 路径保持同进程，迁移由 M5.3/M5.4 接管。消融计数：替代并删除历史不安全 prototype 后新增一条安全 endpoint 路径，普通帧视觉路径净增 0；仅首个 drawable 安装一次性 present handler。
- **M5.3 DaemonKit 公共层第二批** ✅ 双消费者边界闭合：新增无 Scene/Video 业务依赖的 `DaemonNewlineFrameBuffer` 与 `DaemonNewlineJSON`，统一增量分帧和 newline JSON 编码；App 的 video client、既有 WallpaperDaemon tool、Scene endpoint 均为真实消费者，本批新增的双 target membership 只有该文件。协议 payload 仍归各端所有。审计确认 `Process()` 孵化与退避在本步仍只有 video client 一个消费者，未为凑公共层制造 wrapper；两者改在 M5.4 Scene client 接入时再共同抽取。10 个聚焦模块与双架构 WallpaperDaemon target 通过，checkpoint **BUILD SUCCEEDED**；继承的 code-health 超限债务仍单列。签名 Debug App（main executable SHA-256 `4d5f965e206c299fee50b96569d7fe5cf3bfaa1b3e334bb1625ce9316f07f5d3`，CDHash `2f406eb94b9d3dfd0c726b0ec4215853e151d8b6`）实测 video command 拆成两段并夹空帧后仍为 `launched→accepted→ready→stopped`。Scene daemon 隔离 `2938612768` / `1300076567` 分别持续到 244 / 522 rendered、`busy=0/dropped=0`、`gpuDrained=true`；两份窗口截图已人工核对完整构图与可见效果。graph 另跑现役 full-matrix 条目，进程正常、纹理 loaded ratio 1、59/58 submitted/completed、0 failed、ready/after 非黑且 changed ratio 0.739，但因现役期待漂移仍 32 项 NON-PASS，未改期待或冒充能力门通过。消融：删除三处重复分帧/结尾字节拼接实现，视觉路径与权威数净增 0。
- **M5.4 命令迁移** ✅：普通产品 Scene 改由 `SceneDaemonClient` 接收命令并孵化同二进制 daemon；`DaemonProcessTransport` 与 `DaemonRestartBackoff` 成为 Scene/Video 两个真实消费者的公共层。load/cancel/property/profile/mute/pause/resume/stop 均经 newline JSON，事件按请求身份回传，1Hz stats 保持 latest-only；连续断连按 0/1/2/4…有界重启，仅实际 first-present 清零退避并重放已合并 authored intent。App 仍是属性持久化唯一权威，daemon Host 仍是运行属性、五类 prepared 产品与 Metal 输出唯一权威。正式 selector 的 17 个聚焦模块通过，签名 Debug 与最终 checkpoint 均 BUILD SUCCEEDED；code-health 只剩现役树继承超限项，未伪报全绿。隔离 graph `2938612768` 与 simple `1300076567` 各运行 20 秒并强杀 daemon：均出现新 PID、新 request、恢复 actual present，恢复截图构图正确；graph 最新统计 rendered=212/busy=22/dropped=0，simple=821/0/0（未签名 Debug 短窗，只作功能证据）。属性样本 `3747492842` 在同 PID 从 barcount 58.01 热更到 64，强杀后的新 daemon 首帧仍为 64；无 live consumer 的属性触发同 PID 新 load，证明 async 拒绝兜底。Video helper 拆段命令+空帧继续得到 `launched→accepted→ready→stopped`。消融：删除普通产品的 Host 命令 extension，Scene 视觉路径由 App Host 改为 App client→daemon Host，产品视觉路径净增 0、权威数不变；DEBUG direct runner 仅为证据入口，M5.5/M5.6 继续收口。
- **M5.5 Host 瘦身** ✅：删除 `SceneDesktopWallpaperHost.shared` 全局入口，产品 Host 改由 `SceneDaemonRuntime` 显式持有唯一实例；AppDelegate/MainWindowCoordinator/MyWallpaperXApplication/WallpaperEngine/Steam 服务等普通主程序调用面均无 Host 类型引用，产品主进程只保留 `SceneDaemonClient` 的状态机、通知投影与可重放 authored intent。由于 Scene 采用同二进制 daemon，渲染源码仍物理存在于 app target；隔离门以进程装配和实例所有权为准，而不是另造重复 target。旧 direct runner 仅在显式 DEBUG 证据参数下持有自己的隔离 Host，退出也经该 owner 停止。262 个受影响直接测试与正式 selector 的 21 个模块全部通过，签名 Debug 与最终 checkpoint 构建均 BUILD SUCCEEDED；code-health 只报现役树继承债务，本批文件无新增 error。graph `2938612768`（35 秒）和 simple `1300076567`（20 秒）隔离副本均在强杀后以新 PID、新 request 恢复 actual present，恢复截图构图完整，分别为 rendered=303/busy=24/dropped=0 与 1119/0/0。消融：删除可被任意进程内调用者取得的产品 Host 全局路径，产品视觉路径净减 1 个潜在旁路，运行权威仍只有 daemon Host；画面算法、prepared 产品、失效域与帧热路未改。
- **M5.6 收尾** ✅：切壁纸、退出、多屏拓扑与系统暂停/恢复已全链 daemon 化。App 监听屏幕参数并只在拓扑变化时发送 typed `setDisplayConfiguration`；daemon Host 不再监听主进程无效的 runtime-switch/屏幕通知，活动 Space 监听改用正确的 `NSWorkspace` notification center。睡眠、锁屏、全屏暂停与恢复，以及全局热键播放/静音，统一经 multiplexer 到 Scene client；暂停意图在尚无 Scene 或重连窗口也会保留并于 load 后重放。App 退出先停止本地 owner，再等待 daemon GPU-drain 退出；Process 终止投递走主 RunLoop common modes，避免 `terminateLater` 内层事件循环饿死主 GCD 队列，2 秒强退由 transport 后台计时。53 个直接测试与正式 selector 的 19 个聚焦模块通过，签名 Debug 与最终 checkpoint 均 BUILD SUCCEEDED；code-health 的 181 个 warning/19 个 error 全属现役树继承 ratchet 债务，本批文件无新增 hard-limit error。隔离 simple→graph 切换得到两个 record 的 actual present 且 PID 保持 `91071`，退出后无孤儿；simple 强杀恢复由 `91095` 切到 `91097`，恢复 actual present 后两个 PID 均退出。最终统计 graph rendered=675/busy=23/dropped=0，simple rendered=1120/busy=0/dropped=0；两张最终截图已人工核对构图完整。能力语义、五类 prepared 产品、失效域与帧热路未改。消融：删除 Host 两条产品失效的进程内通知入口，以 App→pipe→daemon 的一条 display/control 通道替代屏幕直连旁路；产品视觉路径净减 1，权威数不变。
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

现状已优先使用进程内 typed 热应用，失败时保留 180ms 去抖重启；命令层 `.setProperty` 尚未消费。目标：调节 → `setProperty(properties, revision)` → liveState 值更新 + revision 递增 → 下一帧既有 value-only 路径消费。失效域分类：数值/颜色/bool/文字 → value-only；纹理 URL 类 → resource-generation（复用 deferred 装载机）；combo/可见性默认/结构类 → program-variant/topology 局部失效；任何一类不重启。应用失败保留重启路径兜底。UI 滑杆 ~150ms 去抖；验收 = ≤1 帧 + 轻量上传内可见、launch 状态不重放。M0 进程内实现，M5 同命令走管道。

### 4.3 进程分离

Scene 使用 `Process()` 孵化自身二进制并传 `--mwx-scene-daemon`；video 保留既有 `Contents/Helpers` 工具。共同传输为 stdin/stdout newline JSON，主程序负责退避重启，daemon 内自建桌面级窗口。新 daemon 内含完整 Scene runtime；进程间只传 coarse 命令与轻量 counter，`MTLTexture` 等进程内对象不跨进程；诊断旁路留 daemon 内。IPC 合同：命令 `loadScene{rootURL,propertyOverrides,profile}` / `setProperty{...}` / `setDisplayConfiguration{screens}` / `setPerformanceProfile{fps}` / `setMuted` / `pause` / `resume` / `shutdown`；事件 `launchStateChanged` / `firstFramePresented` / `frameStats`(1Hz) / `error` / `exited`。隔离目标 = UI 响应、崩溃、堆、VM、编译器故障隔离；不承诺总 CPU/GPU 下降。

### 4.4 公共层拆分图

| 批次 | 内容 | 从 | 到 |
|---|---|---|---|
| 一（M0） | 设置容器+分区枚举 | Modules/VideoLibrary/UI | Shared/Settings |
| 一（M0） | 静音公共态、WallpaperEngineCommand+multiplexer | VideoLibrary/Core、新建 | Core/PlaybackControl |
| 二（M5） | daemon 会话（孵化/退避重启/管道帧协议） | Core/Playback、WallpaperDaemonSources/Support | DaemonKit（Scene 在 app target 内复用；video tool 真实消费部分才挂双 target） |

### 4.5 语言选型

默认 **Swift**（AppKit/Metal 集成、产品编排、资源所有权、生命周期、命令编码）。引入 Rust/C/C++ 须同时满足：① Instruments/M1 数据证明的 CPU 热点或全新独立组件；② 算法本质适合 contiguous 低级处理或需要该生态的既有库；③ ABI 边界小而稳定；④ 非每对象/每粒子/每 draw 高频跨语言调用；⑤ 收益显著且可测。现有异构已落在正确位置（QuickJS=C、glslang/spirv-cross=C++ 子进程、shader=MSL）。Rust/C++ 候选域（待 M1 数据裁决）：package/binary 解析、压缩与纹理解码、粒子/物理 kernel、daemon 管道帧协议。渲染主链、UI、控制面不迁移语言；**禁止为语言一致性而迁移，也禁止为语言新鲜感而引入**。防屎山规则优先于一切性能动机：单一权威、双消费者准入、每批消融净路径数不增、改 owner 不包 wrapper。

## 5. 批次 DoD（每批完成定义）

1. `git status` 划 owned paths；有他人 staged/unstaged 的文件不碰；单职责提交。
2. **消融记录**：本批触达的效果链，列出禁用/删除的旁路与最短链论证；被删路径的 fixture/golden 转行为合同或删除；新增/删除路径数计入报告（净路径数不得增长，除非是新能力）。
3. before/after：受影响 M1 指标数字；架构纠偏类附静态违规证据即可。
4. 能力不回退：Fast Scene Suite 相关成员 + ≥2 代表样本人工播放确认；能力台账触达项同步。
5. 报告：改了什么/为什么/语义影响/before/after/剩余热点/回滚方式。
6. 若批次改变了[事实架构地图](runtime-as-built-map.md)中的所有权或不变量，同批更新该地图与本计划卡状态。
