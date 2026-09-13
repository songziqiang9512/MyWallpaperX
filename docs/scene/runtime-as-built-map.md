# Scene Runtime 事实架构地图（as-built）

<!-- document-role: stable-contract -->

> 状态：现役工程参考地图（代码实际接线的事实记录）
>
> 复核：2026-09-14
>
> 角色边界：`runtime-architecture.md` 是目标合同（应该怎样）；能力台账是能力现状；运行证据是跑过什么。**本图记录代码实际接线**：每类对象谁加载、分配到哪、存活期、失效域，以及不改就会出事的隐性不变量与耦合。目标与本图冲突时，以目标合同为准并按偏差债务处理；本图随批次更新。
>
> 现状权威：`docs/scene/semantics/coverage-ledger.md`。
>
> 何时读：改任何 Scene runtime 代码之前；执行[引擎重构工程计划](engine-refactor-program.md) M0（命令层）/M5（daemon）之前必读 §3/§4。
>
> 行号漂移规则：并行批次持续推进，本图 file:line 是 2026-09-14 前后基线，执行时以当次 HEAD 复核锚点。

## 1. 一页总览

### 1.1 加载链（一次 launch）

```
主线程  选壁纸 → 收集属性覆盖（bookmark 同步 IO）→ requestLaunch（世代号++，取消上一代）
后台    launchPreparationQueue 串行：package 解码（project.json/scene.json JSONSerialization、scene.pkg 解包）
        → IR/RenderDescriptor/资产目录 → admission/catalog 编译（concurrentPerform）
        → 材质资产纹理内联解码 → 双后台 worker（基础纹理/模型、first-surface runtime）→ NSCondition join
        → QuickJS 全 family 编译 → launchContext 组装
主线程  activate：QuickJS adoptCurrentThread → 逐屏建 SceneMetalView（同步加载用户属性纹理）
        → loadImageLayers（缓存 miss 同步 decode/puppet 重组/文字/粒子 init）→ 建窗口 → 立即首帧 → Timer 帧循环
```

### 1.2 所有权权威（同一时刻各只有一个，禁止第二套）

| 权威 | 持有者 | 存活期 | 替换方式 |
|---|---|---|---|
| identity/作者顺序 | launchContext.renderDescriptor + catalog | 单次 launch | 场景切换整体替换 |
| frame clock/typed channels | sceneClock + FrameDriver 状态机 | App 激活期 | 暂停/恢复 |
| property/state | liveState.effectiveValues + revision | launch 期，值变 revision++ | value-only 帧路径消费 |
| resource/provider registry | SceneFrameTextureRegistry（per surface view） | per view | 每帧 beginFrame 重发布 |
| graph/target/publication/completion | SceneResolvedMaterialRuntimeBridge（catalog+SubmissionCoordinator，**per surface**） | per surface/场景 | invalidate 整体重置；catalog 不可变、整体替换 |
| compositor/drawable | SceneMetalView 的 CAMetalLayer + 唯一 main pass | per surface | — |

### 1.3 线程地图

| 工作 | 线程 | 备注 |
|---|---|---|
| frame tick / QuickJS / 粒子 / Metal encode / commit | **主线程**（Timer on RunLoop.main） | VM 经 adoptCurrentThread 绑定；0 actor / 0 类型级 @MainActor，全靠约定 |
| GPU 完成终结 | Metal 完成线程 → 唯一每帧 hop：`Task{@MainActor}` 回主线程（SubmissionCoordinator+FrameCommit） | 其余 completion 只做锁内记账 |
| 启动准备 / deferred 纹理 / 动态文字 / 音频分析 / localStorage | 各自后台串行队列 | 跨线程只经 os_unfair_lock inbox（audio/media） |
| shader 编译 | 外部子进程（glslang/spirv-cross，超时+字节+内存预算 SIGKILL） | 产物 MSL 字符串；makeLibrary 在 PassEncoder |

## 2. 加载与分配地图（按对象类）

| 对象类 | 谁加载/构建 | 分配到哪 | 存活期 | 失效域 |
|---|---|---|---|---|
| authored 解码产物（IR/descriptor/资产目录） | launch 队列一次构建 | launchContext | 场景期 | topology（整体替换） |
| author shader 程序（MSL artifact） | admission 编译（子进程）+ 磁盘/内存 artifact cache | capability catalog（不可变，token 寻址） | catalog 生命周期 | program-variant |
| PSO/MTLLibrary | PassEncoder entries，key=MetalCompileStateKey（含完整 metalSource）；launch 期 warmup 预编 | pipeline repository | 直到 executor.reset() 清空 | program-variant；reset 后首帧主线程重编译 |
| 基础纹理 | PreparedBaseImageResources 后台预解码；deferred 按需 worker（per 世代队列） | imageTextures store（per view） | view/场景期，缓存无字节上限 | resource-generation / geometry-extent |
| 材质资产纹理 | MaterialAssetTextureCatalog launch 内联同步解码 | catalog | 场景期 | resource-generation |
| 视频帧 | AVPlayer 解码线程 + CVMetalTextureCache 零拷贝 | per-source pending → 三段栅栏 | 帧期 | resource-generation（每帧 generation++） |
| 动态文字/媒体缩略图 | 专用异步队列，签名/generation 去重 | pending 状态机 → 三段栅栏 | 帧期 | resource-generation |
| graph render target | offscreen allocation cache（LRU 192-512MB + submissionPin/historyPin + history rehydrate） | lease/table（per layer plan） | 跨帧（history）或帧内 | geometry-extent / topology |
| 帧 values | FrameDriver 每帧双 resolve 动态快照 | frameContext（值传递，字典 CoW） | 帧期 | value-only |
| 完成态/history | SubmissionCoordinator pending → committedTails（finalTails 非空时阻塞下帧） | coordinator（per surface） | GPU 终结前 | topology/回滚 |

## 3. 不变量清单（违反即出隐蔽 bug）

1. **一帧一 command buffer**：本帧所有 ledger 共享同一 buffer；sealFrame 要求 `commandBuffer.status == .notEnqueued`。新增提前 enqueue/第二个 encode buffer → seal 拒帧、pin 泄漏。
2. **ledger 相位机**：`prepared→allocationCommitted→encoded→outputConsumed→sealed`；claim/ticket/output 各只消费一次。新资源路径必须产生相位迁移，否则双消费/泄漏。
3. **全 surface 提交栅栏**：任一 surface deferred/dropped → 整帧回滚，回滚必须恢复全部先取状态（clock、timeline observation、parallax、pointer、cursor edge、program/timer frame state、8 组 provider discard）。加状态必须 commit/discard 两处同加。
4. **provider 三段栅栏**：每类动态资源（video/media thumbnail/dynamic text/sprite/material asset/frame texture publication/particle/puppet bone）prepare→commit/discard 成对；commit 只在全 surface 提交后统一执行。漏 discard = deferred 帧后漂移；漏 commit = 永不更新。
5. **in-flight 门**：最大提交数 2 且要求所有 pending 的 finalTails 已终结 → history 图实际单帧 in-flight；acceptance 翻转 100% 经过 completeCommandBuffer。pool 预算/history 保留/in-flight 容量三者联动。
6. **digest = variant memo 键**：registry snapshot 的 SelectionDigest 只含 fact 层（布尔化 generation），跨视频帧稳定；是变体选择的 memo 键且无测试覆盖。往 fact 加逐帧变化字段 = memo 永远 miss。
7. **hasSameValuePayload 是 generation 闸门**：值不变则快照 generation 不递增，下游 memo 依赖此稳定；不能当冗余比较优化掉。
8. **属性 lane 优先级**：user > timeline > sceneScript（合并顺序 + stateful script 值仅在无高优 producer 时前向携带）。动顺序 = 脚本动画被静默覆盖。
9. **VM timer 只在真实帧 dispatch**：busy 重试对 timer frame state 做"快照→guard→discard"防重复执行。绕过 FrameDriver 的帧驱动会双触发或丢 timer。
10. **QuickJS 线程绑定**：VM 创建于 launch 队列、adoptCurrentThread 迁移到使用线程；全部 VM 交互 Swift 状态无隔离标注（约定主线程）。换线程/进程必须 rebase 并迁移全部交互状态。
11. **sticky 遥测只报首次**：effect/graph/失败类日志多为 once-per-subject；"不再报错"≠修复。
12. **debug evidence 门三合一**：诊断 + benchmark 日志行（benchmark 恒传 flag+Debug 构建）+ **窗口层样式**。往门下加行为会改窗口表现；`#if DEBUG` 包裹物 Release 不存在。
13. **puppet 双 lane**：`puppetAtlas` 仅 mesh UV 采样、`puppetComposed` 才能作 layer source；geometry 失败回退 TextureProduct 须保持 coverage 合同。
14. **launch 世代**：newer-wins 世代号 + 取消令牌 + per-generation worker 队列；新后台准备必须持世代令牌，否则旧场景任务污染新场景。
15. **catalog 不可变、整体替换**：capability catalog 无增量失效；token 含 ownerID 不跨 catalog 碰撞。"改一处能力"= 重建 catalog，不是 patch。
16. **控制面单一通道**（M0 起）：UI→引擎只经 `Core/PlaybackControl/` 命令层（`WallpaperEngineCommand` + multiplexer，未消费显式 false）；静音权威 = `PlaybackMuteState`（video 音量滑杆归零的派生静音是例外，同步属设置打通）；预算档权威 = Scene 宿主 `performanceProfile`（UI 只写 UserDefaults + 发命令）。新 UI 入口不得直触引擎内部。

## 4. 改A坏B 雷区对照表

| 你想做 | 必须同改 | 漏改症状 |
|---|---|---|
| 帧路径加"先准备后提交"的新状态/资源 | surface prepareX + FrameDriver commit 族 + 失败 restore/discard 族（不变量 3/4） | deferred 帧后跳变/残留；提交帧不生效 |
| 新增动态纹理来源 | registry.beginFrame 发布类目 + publication generation + 三段栅栏 + snapshot fact | memo 全 miss 或 digest 抖动；纹理永不更新；tails 校验拒帧 |
| 改 fact/digest 字段 | 先补 digest 等值测试（零覆盖）+ 检查 SelectionMemoKey 消费 | 每帧 memo miss（性能悬崖）或 memo 永不失效（陈旧选择） |
| 加第二个 command buffer / 改提交时机 | ledger 相位机 + seal 检查 + 一帧一 buffer（不变量 1/2） | seal 拒帧；pin 泄漏；粒子槽位不释放 |
| 改 in-flight/pool 预算/history 保留 | acceptance 门 + pin/rehydrate + busy 重试节奏一起评估 | .busy 风暴 / target hazard / 内存滞涨 |
| 帧循环换线程/进程（M5） | VM adoptCurrentThread rebase + VM 交互状态全迁移 + AppKit 接触点（drawableSize 主线程写/帧读、指针链 NSEvent/window.convertPoint、surfaces 字典主线程独占、8 组 commit 栅栏）+ launch 状态改事件 + 完成回调落点 | 随机崩溃 / timer 双跑 / 状态漂移 |
| 改属性生效/优先级 | lane 合并顺序 + revision 语义（userPropertiesJSON 缓存键）+ hasSameValuePayload 闸门 | 脚本动画被覆盖；属性改了画面不动 |
| 改 SceneScript 定时器/帧状态 | 快照/discard 对只在真实帧 dispatch 的约定（不变量 9） | timer 双触发/丢失；deferred 帧后 VM 漂移 |
| 加 invalidation 触发（档位切换/重连/显示变化） | executor.reset() 清 PSO 缓存 → warmup 跟进；catalog 整体重建 | 重置后首帧主线程秒级卡顿 |
| 加 per-frame 遥测/诊断 | evidence 门三合一语义（不变量 12）+ sticky 行为 + Release 恒 false | Release 行为漂移；窗口样式意外变化 |
| 新 offscreen target 类型 | allocation cache key + pin 故事 + history-only 降级路径 | 在飞资源被逐出 → GPU target hazard |
| 静音/预算档/命令层（M0.2/M0.7 已落地） | video previousAudibleVolume 恢复语义 + SceneSoundPlaybackRegistry 静音门 + `PlaybackMuteState`/`PlaybackPerformanceProfile` 权威 + daemon `setMuted`/`setPerformanceProfile` | video 音量恢复错档；Scene 音效/帧率不受控；第二静音权威 |
| 动 puppet atlas/composed | coverage ledger + UV 合同 | puppet 采样错位（近期迁移高发区） |
| launch 加后台准备 | 世代令牌 + per-generation 队列 | 旧场景任务写进新场景表面 |
| 退役一条 effect 执行旁路 | route state（observe→prefer→generic-only）+ fixture/golden 转行为合同 | 静默双执行或能力回退 |

## 5. 已做对、明确不动

唯一权威五件套；offscreen 目标 LRU 池（字节预算+history pin）；粒子实例 ring buffer；视频 CVMetal 零拷贝+三段栅栏；动态文字异步光栅+签名去重；deferred base images；编译子进程三重预算 kill；userPropertiesJSON/topology/compiledOperations 等 revision 缓存族。

## 6. 维护规则

- 本图是 as-built 快照：结构/不变量长期有效，file:line 会漂移（每批执行时复核锚点）。
- 任何批次改变了 §2 的一行或 §3 的一条不变量，必须同批更新本图（与[工程计划](engine-refactor-program.md)工位卡一起），否则地图作废。
