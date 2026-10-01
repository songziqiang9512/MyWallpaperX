# Scene 启动流程与运行机制（启动专题）

> 状态：现役专题导航。本文是启动知识的**汇总与入口层**：流程、阶段标记、实测数字、
> 暖启动机制与测量方法一目了然；每条事实的**权威解释留在链接的文档**，本文不复制
> 合同条款、不拥有独占事实。数字是 2026-09-29/30 的实测快照，之后以
> [运行证据](../semantics/runtime-evidence-current.md)的对应证据段为准。
>
> 权威分工：启动[合同](scene-launch-responsiveness-contract.md)（两阶段事务、反馈、
> 回滚）｜[运行架构](runtime-architecture.md)（§3.5 缓存与预热、§5 失效域、§8 生命周期）｜
> [事实地图](runtime-as-built-map.md)（当前代码所有权）｜
> [运行证据](../semantics/runtime-evidence-current.md#e-2026-09-30-scene-startup-speed-program)
> （启动提速计划 E 段，本页数字的出处）。

## 1. 两条启动路径

| 路径 | 入口 | 宿主 |
|---|---|---|
| 产品路径（用户设为壁纸） | `SteamWorkshopService.requestSceneRender` → `.steamWorkshopSceneReadyToRender` → multiplexer `.loadScene` → `SceneDaemonClient.requestLaunch` | daemon 子进程（`--mwx-scene-daemon`，同二进制 accessory）内唯一产品 `SceneDesktopWallpaperHost` |
| 证据/调试路径（benchmark、隔离回放） | `DebugScenePlaybackRunner`（direct-host）或 daemon-client product-entry | runner 自己的隔离 Host，与产品分发互斥（见 runtime-as-built-map 进程现状段） |

产品 daemon 生命周期 = 每次 Scene 会话：首次 `requestLaunch` 经 `ensureSession()` 孵化，
`stop()`/runtime 切换即退租并 `shutdown`；空闲不保温。预热见 §4。

## 2. 启动阶段表（LAUNCH-STAGE 标记）

代码在 launch 路径埋有 `MWX LAUNCH-STAGE: stage=<名> elapsedMs=<累计ms>` 标记
（`SceneDesktopWallpaperHost+Launch.swift`、`SceneDesktopWallpaperHost.swift`、
`SceneResolvedMaterialExecutionCapabilityVariant+Compilation.swift`、
`SceneResolvedMaterialRuntimeCatalog.swift`、`SceneResolvedMaterialPassEncoder.swift`、
`DebugScenePlaybackRunner.swift`）。锚点分三组：`runner-*`/`host-launch-return`/`launch-return`
自 `requestUptime` 累计；`prepare-*` 自 `prepareLaunch` 入口累计；其余自 `resourcesStageStart`
或各自局部锚点累计。

| 标记 | 覆盖的工作 | 重样本实测（2026-09-29/30 快照） |
|---|---|---|
| `runner-pre-launch` | 请求受理 → `Host.launch` 调用前（进程引导+参数解析） | ~420ms（三样本恒定） |
| `model-build`（`preludeMs`） | 包校验/解包/场景解析（`SceneRuntimeModelBuilder.build`） | 简单 216 / 中 490 / 重 455ms |
| `prepare-setup` | device/队列/deferred 计算/后台任务启动 | ~180-500ms（含解析；差值即准备模型之后的部分） |
| `prepare-programs` → `prepare-admission` | timeline/脚本 target 编译 → admission 候选编译 | 各 ~1-90ms / ~90-280ms |
| `prepare-catalog`（=prelude 末） | **`SceneResolvedMaterialRuntimeCatalog` 物化（逐材质 resolve）** | 简单 ≈0 / 中 **1105ms** / 重 **2859ms** |
| `catalog-decode` → `capability-catalog` | 纹理目录解码 → 变体编译（prepareShaderStages+分析族+artifact） | 中 147→**4138ms**；重 23→**3468ms** |
| `capability-detail`（聚合行） | 变体内分段：prepare/canonicalize/analysis/artifact | 见 §3 缓存表 |
| `quickjs-compile` → `device-join` → `first-surface-join` → `prepare-end` | QuickJS 程序编译（8-19ms）→ device 资源汇合 → 首表面就绪 | 中 4356 / 重 4760ms |
| `activate-surfaces` ≈ `activate-end` | 表面重建 + 音频/指针接管（launch 尾声 ~1ms） | **151-315ms** |
| `host-launch-return` ≈ `launch-return` | launch 返回（证据写入 <20ms） | = 前四段之和 |
| `phase=ready`（`startupElapsedMS`） | runner 总账 | 简单 753 / 中 6752 / 重 9191ms（改进前） |

早期版本无 `runner-pre-launch`/`prepare-*` 标记，曾把 prelude 尾段误归"激活/首帧"；
现表以 700917d6 后的标记体系为准（更正记录见运行证据段）。

## 3. 暖启动持久层（本计划的主体成果）

所有层共享同一套防护合同与 IO 家（`ScenePersistentCacheSupport` /
`ScenePersistentCacheDigest` / `ScenePersistentSamplerRecord`）：信封
schemaVersion+键摘要+载荷摘要三重校验、load 路径零副作用（不建目录）、只存成功结果、
损坏/版本失配安全 miss、`schemaVersion` 为唯一失效杠杆。防护合同由
`script/tests/test_scene_persistent_cache_behavior.py` 行为回归门锁定
（四层真实 load/store 探针：只读 miss/发布/命中/损坏与篡改安全 miss/过期
schema miss；preparation 层经真实消费方驱动，拒绝不发布、跨进程命中不重发、
损坏自愈）。

| 层 | 文件（Compilation/Material 除注明） | 键 | 缓存内容 | 实测收益 |
|---|---|---|---|---|
| generic 分析前缀 | `SceneResolvedMaterialGenericShaderPreparationCoordination.swift`（持久层）/ `SceneGenericShaderAnalysisCache` 段 | ResolutionCache.Input 全 30 字段 | profile/colorTransfer 终值/expectedTransfer/槽集 | capability-catalog **−32%/−46%** |
| demand 分析 | `SceneMaterialDemandAnalysisPersistentCache.swift` | ResourceDemandAnalysisKey 全字段 | 每变体 samplers+textureFormatSlots | catalog compileMs **−97%**（913→24 / 706→19ms） |
| 变体 fact 族 | `SceneResolvedMaterialVariantAnalysisCache.swift` | 八域（contract/槽形状/combos/readiness/formats/identity/rgba8…） | canonical 双源+names+integerCombos+samplers；**eligibility 前件×3**（校验段重跑） | warm capability **694-798ms / 901-1317ms** |
| preparation v1 | `.../ShaderPreparation/SceneAuthoredShaderPreparation.swift` | contract+graph+combos+readiness+formats | prepared 前端源 | 既有 |
| 编译产物 v10 | `SceneGenericShaderPrograms-v10`（外部编译器产物；请求 key 只覆盖 authored 源，normalizer 语义变更经目录版本整层退役，v10 对应比较操作数左类型证明） | 请求 key（v13 信封） | generic Program artifact | 既有 |
| **PSO binary archive** | `SceneResolvedMaterialPipelineBinaryArchive.swift`（Rendering/Graph） | OS build+device registryID+pixelFormat+sampleCount+writeMask+函数名+renderState+MSL sha256 | 每精确管线身份一个 `.metalarchive` | 机制落地；**命中率需实机统计** |

统一失效规则：任何分析器/normalizer/profile 语义变更必须 bump 对应层
`schemaVersion`（整个 tier 安全 miss 退役）；`frontendSchemaVersion` 无机械 bump
保障，不作为失效依据。

## 4. daemon 预热（L1）

`SceneDaemonClient.warmSession()`：守卫（热 transport / pendingIntent 跳过）后静默孵化
daemon 并完成 role 握手，零可见输出；握手超时/孵化失败全程静默（不 publishFailure、
不 scheduleRestart——intent 门护栏保持）。真实 `requestLaunch` 经 `ensureSession` 的
transport 复用守卫直接在热 transport 上重放 intent。触发点：App 启动 3s 后、
Scene 下载入库完成（`.steamWorkshopSceneDownloadCompleted`）。自动化验收 4/4 PASS
（进程恒 1 / 失败零 UI / 杀后不重启 / 清理完成）；(c) 真实 launch 冷启需实机。
L2（Metal device/固定 MSL 预热）已按实测关闭（冷启动 `device-join` 段仅 0–33ms，
无收益，见运行证据段）。

### PreparedContent 预解析（场景 A）——已评估，决定暂不做（2026-09-30）

**设想**：Scene 下载入库完成后，daemon 后台对刚入库的样本预跑一次
`SceneRuntimeModelBuilder.build` 并驻留产物，使该样本首次"设为壁纸"省去
model-build 段（实测 674–692ms，daemon 热启动路径）。

**决定暂不做，理由是副作用面大于收益面**（收益仅此一个场景；对比前四条
缓存层——它们缓存字节级小、纯函数、命中率高的分析结论，这份缓存字节大、
含解析状态、命中率取决于用户行为）：

1. **常驻内存无上界**：预解析产物是完整 `SceneRuntimeModel` 对象图（重样本
   估计数十 MB 级，未实测），daemon 常驻后逐次下载单调增长；不加淘汰即无界，
   加淘汰即新增治理面。
2. **后台 CPU 抢占播放**：build 在 daemon 进程后台队列跑，与当前壁纸的帧循环
   争核，正在播放的壁纸可能掉帧。
3. **双 build 竞态**：预解析中用户设为壁纸，`prepareLaunch` 无条件重 build——
   需要可取消机制，又是新增复杂度。
4. **缓存键含 `propertyOverrides`**：同一壁纸不同属性设置产生不同 model，
   命中条件比前四层苛刻；要让 launch 消费缓存还需改 `prepareLaunch` 查缓存
   ——第五条缓存层的全套终审成本。

**若将来重启此批，沿用结论**：按"单槽顶替版"收敛——只缓存最近一次下载的
预解析产物，新下载顶替旧的（无淘汰治理、内存上界 = 一份 model、恰好覆盖
"下载完就设置"的最高频路径）；实现批内顺带实测预解析前后 daemon RSS 差
（补上"数十 MB"这个未实测数字）。L2 同理维持关闭，除非实测推翻
`device-join` 0–33ms 的结论。

## 5. 按需加载与失效域

- 五类变化的最小失效域（value-only / resource-generation / geometry / program-variant /
  topology）与"普通帧不重解析、不重编译、不建图"的边界：
  [运行架构 §5](runtime-architecture.md#5-纵向兼容执行)。
- deferred 纹理：启动只加载初始可见项，其余按需（实测 25 项样本 22.9s→1.9s 的来源）；
  隐藏层若有脚本/音频/粒子 child 或作为被采样 provider，仍可能必须运行。
- 普通 value-only 变化不 relaunch；topology 变化不复用 stale graph。

## 6. 测量方法与已知陷阱

- 命令：worktree `-O` Debug 构建 + `script/scene_wallpaper_benchmark.py`
  （`--keep-runtime` 保留 HOME 得热启动；benchmark 用已签名 App，不受 helper 签名
  环境影响）。
- 冷/热对照必须等安静窗口：`pgrep -f "swift-frontend|xcodebuild|run_scene_tests"`
  ——测试 harness 的 swiftc 编译不挂 xcodebuild 名，曾把处置组抬高 3.7s 险些误判。
- `run_scene_tests` 汇总行 "N/N modules" 是运行计数而非全绿；必须 grep 逐模块 FAILED。
- 归因表必须逐日志验证闭合（各段之和 == 总账，残差 ≤1ms）。
- `timestamp.apple.com` 不可达时 ad-hoc helper 签名失败（licensebundle SIGTRAP），
  GPU 类 harness 全挂——环境问题，与代码无关。

## 7. 当前边界与未验收项

1. daemon 预热实机验收：(c) 真实 launch 冷启、sandbox extension 告警复核；
2. 3b archive 命中率/冷启动收益需真机多次启动统计；
3. 4 个 GPU 测试模块待签名环境恢复补跑；
4. L2 预热已按实测关闭（§4）；PreparedContent 预解析已评估并决定暂不做（§4，
   含重启条件与单槽版方案）；
5. preservedAlphaRGBColorSlots 死缓存字段已摘除（schemaVersion 3），analysis 桶残量
   315-674ms 为设计内重算（eligibility 校验段+per-node 集合），继续压缩需扩键，
   终审已论证不划算。
