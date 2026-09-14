# Scene Runtime Daemon 契约（SceneRuntimeService 设计门 M5.1）

<!-- document-role: stable-contract -->

> 状态：现役设计契约（M5 进程分离的设计门交付物；实施进度查[引擎重构工程计划](engine-refactor-program.md) §3 M5 工位卡）
>
> 复核：2026-09-14
>
> 现状权威：`docs/scene/semantics/coverage-ledger.md`。代码实际接线查[事实架构地图](runtime-as-built-map.md)。
>
> 退役条件：daemon 化完成并稳定后，本契约并入长期架构合同（runtime-architecture.md 增补进程章节），本文转 historical-evidence。

## 1. 目标与非目标

**目标**：Scene 播放引擎运行在独立 daemon 进程（与 video/web 的 `MyWallpaperXWallpaperDaemon` 同模式）；主程序只做 UI/选择/设置/命令下发；崩溃/堆/QuickJS/编译器故障与主程序隔离；UI 永不掉帧。

**非目标（如实）**：不承诺总 CPU/GPU 下降；不改变引擎内部架构（唯一权威五件套、PreparedProduct 协议、失效域合同原样保留）；不在进程间传输任何 Metal 对象。

## 2. 进程模型

| 项 | 裁决 |
|---|---|
| 新 target | `MyWallpaperXSceneDaemon`（`com.apple.product-type.tool` → `Contents/Helpers`，仿 WallpaperDaemon pbxproj 结构） |
| 共享代码 | `DaemonKit/` 新同步组挂 app+daemon 双 target：daemon 会话（孵化/退避重启/管道帧协议，抽自 `WallpaperEngine+DaemonSessionLifecycle`） |
| 传输 | stdin/stdout newline-delimited JSON（与 video daemon 同协议族）；无 XPC |
| 引擎代码 | Scene runtime **原样搬迁**（渲染/QuickJS/粒子/compositor/frame loop/预算执行）——不重写线程模型：帧循环仍在 daemon 主线程（AppKit 约束原样成立，见 §5） |
| 状态存储 | 属性覆盖 UserDefaults 沿用主进程侧写入？否——daemon 拥有运行时状态；持久化设置由主程序经命令下发，daemon 无本地持久化（除既有 shader artifact 磁盘缓存，路径不变） |

## 3. IPC 合同（= EngineCommand 的传输化，v1 冻结）

### 3.1 命令（主程序 → daemon，逐行 JSON）

| 命令 | 载荷 | 语义 |
|---|---|---|
| `loadScene` | `{rootURL, propertyOverrides, profile}` | newer-wins 世代接受；后台准备；进度经事件回传 |
| `setProperty` | `{values, revision}` | 属性热更新（value-only/资源/局部失效三分类），不重启 |
| `setDisplayConfiguration` | `{screens:[{id, frame, scale}]}` | 多屏拓扑重建 |
| `setPerformanceProfile` | `{maxFPS}` | 60/30 档热切换（下一次排帧生效） |
| `setMuted` | `{muted}` | 静音公共态（Scene Sound 层 0 增益） |
| `pause` / `resume` | — | 播放暂停/恢复（时钟+视频+音效） |
| `shutdown` | — | 有序退出（先释放表面再退进程） |

### 3.2 事件（daemon → 主程序）

| 事件 | 载荷 | 时机 |
|---|---|---|
| `launchStateChanged` | `{phase, message, requestID, recordID}` | 五阶段状态机（accepted/preparingModel/preparingPrograms/preparingResources/preparingSurfaces/launched/failed/cancelled） |
| `firstFramePresented` | `{uptimeMs}` | 首帧 present 后 |
| `frameStats` | 轻量 counter 集合 | 1Hz（hub 定长快照；textureMemory/rtMemory 等接入后自动包含） |
| `error` | `{code, message, context}` | 引擎内部失败的可上报子集 |
| `exited` | `{code}` | 进程退出前 |

### 3.3 硬边界

- 进程间**只传** coarse 命令与轻量统计；`MTLTexture`/registry/coordinator/任何进程内对象不跨进程。
- daemon 内保持唯一权威五件套与失效域合同；诊断旁路（evidence window/HUD）留在 daemon 内。
- 协议版本：首行 `{"v":1}` 握手；不匹配 → 主程序拒绝启动该 daemon 并报错。

## 4. 生命周期与崩溃语义

- **孵化**：主程序 `Process()` 启动 `Contents/Helpers/MyWallpaperXSceneDaemon`，三根管道；参数 `--display-id <id>` 族（多屏 = 每 daemon 一实例或单实例多表面，按 §5.2 原型实测裁决，优先单实例多表面）。
- **崩溃/断连**：主程序侧指数退避重启（复用 video daemon 的 0.5s→…→上限退避），重启后自动 `loadScene` 恢复当前壁纸（rootURL 与属性覆盖由主程序持有）；连续失败超阈值 → 停止重试 + UI 错误态。
- **有序退出**：`shutdown` → daemon 排空在飞 command buffer → `exited` → 进程退出；超时 3s 强杀。
- **世代语义**：`loadScene` 世代号新者胜——旧准备的取消/回滚全部在 daemon 内完成，主程序无感知（只看到新 launchState 事件流）。

## 5. 线程约束审计结论（M5.1 审计；细节查事实架构地图 §1.3/§4）

daemon 化采用"runtime 原样搬迁"策略——**不重写线程模型**，以下主线程约束在 daemon 进程内原样成立，因此不构成迁移障碍：

1. 帧循环/QuickJS/粒子/Metal encode 在 daemon 主线程（Timer on RunLoop.main）；AppKit 接触点（drawableSize 主线程写、指针链 NSEvent/window.convertPoint、surfaces 主线程独占、8 组 commit 栅栏）在 daemon 内与今天同构。
2. QuickJS VM 线程绑定：launch 队列创建 → adoptCurrentThread 到 daemon 主线程，机制既有。
3. 与主程序的边界只有管道 JSON：主线程事件（NSEvent 采样、窗口生命周期）全部是 daemon 进程自己的主线程事务。
4. 需要防范的两点：①daemon 内 `Task { @MainActor }` 完成回调照旧；②`framesStats` 1Hz 事件从 hub 定长快照读取（锁内拷贝），不经帧路径。

**帧线程隔离（RenderLoop 独立线程/DisplayLink）明确不在 M5 范围**——此前裁决：接触面大、无编译器护栏，daemon 边界已达成隔离目标。

## 6. 迁移步骤（M5.2–M5.6）与验收门

| 步 | 内容 | 验收门 |
|---|---|---|
| M5.2 | 最小 daemon target 起桌面窗口出首帧 + 命令框架 | 手动：样本文隔离副本出首帧 |
| M5.3 | DaemonKit 抽取（孵化/退避/帧协议）+ 双 target 同步组 | video daemon 行为回归不受影响 |
| M5.4 | 命令迁移（EngineCommand→管道）+ 事件回传 + 退避重启 | 属性热更新/静音/FPS 档经管道全链可用 |
| M5.5 | Host 瘦身为 client stub | 主程序无 Scene 渲染代码路径（grep 门） |
| M5.6 | 生命周期收尾 + 旧路径删除（消融） | 切换/退出/多屏/暂停全链 + 能力台账零回退 |

每步过 checkpoint 构建；M5.4 起用 graph 样本隔离副本做 smoke（首帧 + setProperty 热更新 + 崩溃恢复）。

## 7. 风险登记

| 风险 | 缓解 |
|---|---|
| 多屏单实例 vs 多实例未定 | M5.2 原型实测（单实例多表面优先，与今天 surfaces 字典同构） |
| QuickJS artifact 磁盘缓存并发（主程序预编译 + daemon 编译） | 缓存协议本就单写者原子替换；daemon 成为唯一编译者后主程序不再触发编译 |
| 管道背压（frameStats 1Hz 足够小） | 事件丢弃策略：主程序忙时 daemon 侧只保留最新 frameStats |
| 属性覆盖持久化迁移 | UserDefaults 键不动，读写方迁至 daemon；主程序设置面板经命令写 |
