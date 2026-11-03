# Scene 准备、启动与缓存

<!-- document-role: stable-contract -->

当前执行 owner 归[总架构](runtime-architecture.md)。本文维护准备工作、候选就绪、缓存和诊断的边界，不维护阶段成绩或任务顺序。

<a id="entry"></a>
## 入口与请求

详情展示只读已有项目元数据。属性入口由原 preparation owner 异步准备；不能为了详情摘要、控件可达性或诊断隐式解析完整 Scene、遍历资源、编译 shader 或创建 pipeline。

App 保产品意图和读取租约；Host 持 request identity、取消 token、准备阶段及 active/candidate Session。新请求 newer-wins，过期结果在接触窗口、publication 或持久配置前退出。普通属性值变化走 typed 更新，只有真实资源/结构变化才重准备对应单元。

资源来源以当前 root、entry、managed generation/storage identity 解析。入库 receipt 证明下载/发布当时完成，不是日后播放许可；启动不复制整库、升级库版本或重新认证全部目录。删除、取消、来源 revision 和实际读取权限仍在原 owner 检查。

源码：[Host 请求与准备](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift)、[SceneRuntimeModel](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRuntimeModel.swift)、[ResourceView](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift)。

<a id="preparation"></a>
## 准备与接管

```text
捕获当前输入和来源租约
  → 后台 ModelBuilder / 资源解析 / typed definitions
  → graph admission / Template / Variant / Program
  → 资源解码上传、设备 warmup、Timeline / QuickJS 构造
  → PreparedLaunch
  → 主线程 Session 接管 Context 与 VM 线程
  → 建立 Surface、准备首帧、GPU 完成
  → candidatePrepared / commit / presented / finalize
```

准备只覆盖当前实际需求及已注册创建模板；隐藏不等于没有资源消费者。`DeferredBaseImages`利用现有 named 引用/潜在引用和模型需求，预备可能被采样的隐藏 source；这只提供资源，不授予 graph 执行或 publication 资格。无需求的 dormant 图片可按原 deferred owner 后台准备。

一个已准入 stage product 的 graph/effect/node/binding 范围由原 Catalog 准备一次，Template 只消费对应节点；不在每 material 重建整图 universe。取消 callback 在批开始和每项入场前检查，抛出原取消错误，不翻译成资源缺失或缓存失败。已进入且仍有消费者的共享 flight 不因单个请求撤销。

设备资源任务、上传队列和 GPU warmup 是原准备链的一部分；首 Surface 仍有必要的实例装配。准备线程转交前不得继续访问已接管 VM。实际首帧/候选协议归[daemon 合同](scene-runtime-daemon-contract.md#candidate)。

视频声明、AV readyToPlay 或 metadata 就绪不等于首帧。每 Surface 的选中视频须取得完整 publication；当前缺失可 deferred，不能借旧源或占位帧宣布候选 ready。可见视频切换保原有界呈现等待，隐藏消费者仍需要真实资源。细节归[视频合同](../capabilities/material-video-assets.md)。

localStorage 沿同一 Session：实际 QuickJS scalar/vector/string/cursor 实例构造成功后、configure 前显式准备；零实例不读。作者 top-level 不提前获得 storage；init/事件前已准备。普通帧 read/apply/begin 只消费内存，激活合并前任最新 envelope，写入沿原 PersistenceCoordinator 后台合并，不在首个帧 getter 同步打开 JSON。

<a id="cache"></a>
## 缓存是可选加速

| 产物 | 原 owner | 采用边界 |
|---|---|---|
| Shader preparation | `SceneAuthoredShaderPreparation` | accepted prepared Program；完整可选持久 store 交 utility |
| Frontend Program | `SceneAuthoredShaderFrontend` | 内存发布/flight 分享同步；hash、编码、目录、prune、写盘交 utility |
| Material demand / Variant analysis | 各自 persistent cache | 当前需求/分析值直接采用；可选 store 不阻塞调用者 |
| Generic shader artifact / analysis | `SceneResolvedMaterialGenericShaderArtifactCache`及原 coordination | Compiler 同次 typed artifact 经 makeProgram 采用；encodedData/analysis 后台发布 |
| MTLLibrary / PSO | 原 repository / PassEncoder | 准备阶段 warmup，帧查询已准备正/负结果 |
| Metal binary archive | `SceneResolvedMaterialPipelineBinaryArchive` | 成功 PSO 先返回；archive add/serialize/替换/prune 交 utility |

命中只复用当前 identity 对应的完整结果。缺失、损坏、超额或不可写均作 miss/跳过可选存储，沿原读取与编译链恢复；不能撤销本次已成功 Program。真实 compiler、ABI 或资源失败仍保持 typed 局部失败。

缓存身份包含实际 source graph 内容、combo、可选资源 readiness/format、render contract 和规则/工具身份。源图摘要在 contract 构造/解码入口形成一次，普通帧不哈希。构建生成的 `SceneShaderCacheIdentity.json`提供语义/工具指纹；进程只读一次小型资源，缺坏时使用进程私有身份继续编译，不运行时扫描源码或 hash 整个 App。

同一消费合同使用既有single-flight；磁盘miss在原受控工作内再查后编译。AuthoredShaderPreparation保留accepted、rejected和notApplicable的有界完成结果，避免同一坏变体反复消耗准备CPU；通用shader resolution只保accepted，compiler失败只在本次flight分享，允许后续修复后重试。各完成缓存按原额度淘汰，超额结果仍交当前消费者。驱逐只移缓存引用，不能清 active/candidate/in-flight 所持产物，也不新增 stop 清全局 cache。

artifact 的 2 MiB 文件预算不等于合法编译产物上限；实际工具输出 16 MiB、MSL/ABI 与资源边界仍由 compiler/makeProgram 控制。可选 publisher 独立创建合法自定义根和版本目录，不依赖另一任务先建目录；读入口不创建。没有生产 flush、待发布镜像或第二缓存 owner。

CPU cache 命中不等于 device resources 或首帧就绪。设备/OS/附件身份和实际 GPU 使用期独立；每屏 encoder token/reset、target/history 不因共享不可变 PSO 而共享。

源码：[指纹](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderCacheIdentity.swift)、[generic artifact](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderArtifactCache.swift)、[Frontend](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderFrontend.swift)、[准备缓存](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderPreparation.swift)、[需求缓存](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneMaterialDemandAnalysisPersistentCache.swift)、[Variant cache](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialVariantAnalysisCache.swift)、[archive](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneResolvedMaterialPipelineBinaryArchive.swift)。

<a id="failure"></a>
## 失败、进度与退出

进度只报告实际准备阶段，不伪造百分比；accepted、prepared、GPU completed 与 presented 分开。取消保当前有效壁纸，晚结果不覆盖新请求；合作取消不能承诺抢占单次 OS I/O、解析或工具调用。

可选资源失败只影响真实消费者。shader 注释、宏、binding 和后端活动接口的规则归[shader 合同](../capabilities/render-graph-shader-coverage.md)，不在启动层再证明或放宽。缓存、诊断和过往摘要不授予播放资格。

Host 停止还需等待已接纳 preparation 队列尾 fence；没有 Session 也不能提前报告资源释放。Session 关闭和 CPU/GPU 排空归[总架构](runtime-architecture.md#threads)。

<a id="diagnostics"></a>
开发诊断从显式 DEBUG runner、CLI、telemetry 或截图入口进入，不借详情保另一条准备链。统计、完整报告和 GPU 观察不得参与产品接纳；真正请求 identity、错误、资源预算和 drain 仍执行。Timeline 的选层观测只读已准备绑定与实际 FrameContext，不调用 compile/values/apply 或改变 snapshot。配置与输出预算以 Diagnostics 实现为准，详情见[观察合同](gpu-stage-timestamp-diagnostics.md)。
