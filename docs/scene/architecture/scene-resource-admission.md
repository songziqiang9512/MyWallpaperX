# Scene 资源计费与使用期

<!-- document-role: stable-contract -->

<a id="budget"></a>
## 总额与原 owner

`SceneResourceBudget.shared`是进程内应用可控 Scene resident allocation 的总准入账。Surface pool、粒子 buffer、decode cache 与 active/candidate/retiring 共同占用；本地 cache/pool 上限是子约束，不是另一总额或资源 identity。

当前默认总额取 Metal recommended working set 的四分之一、封顶 3 GiB；没有建议值时为 512 MiB。decoded 驻留另限总额四分之一。策略源为[SceneResourceBudget](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift)，它不是 RSS、OS OOM 或框架全部内存保证。

计费不包含全部 VM/解析对象、解码瞬态、AV/driver/pipeline 私有内存或 CAMetalLayer drawable。报告必须区分应用计费、pool resident、实际对象、进程 footprint 与系统驻留。

<a id="allocation"></a>
## 分配与释放

GPU 入口以 Metal size/alignment 需求先预留，分配失败返还。租约附在实际资源对象，CPU owner 或 command buffer 仍持有时持续计费；最终对象释放才返还，不能在 stop/cache.remove 时提前退款。共享同一对象只记一次。

视频导入按 backing pixel buffer 计费；Metal view 同时保持 CV binding/backing，不能让退休帧随 Core Video cache 累积。decode cache 的原 lease 同时遵守父账和自身上限。loader 结束清可重建 CPU 缓存，不清仍被消费的 GPU texture。

预算拒绝沿原 allocation failure 拒最小不安全单元；不驱逐在途资源或停止健康屏。新候选不能就绪则保 active，退役期间旧/新会话仍一起计费。pool 内可复用 resident 不等于泄漏，history pin 与 submission pin 的使用期另由原 owner 管理。

源码：[texture/buffer 分配与预算入口](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift)、[离屏池](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTexturePool.swift)、[allocation cache](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache.swift)。

<a id="source-readiness"></a>
## 来源、用途与准备

逻辑 path/purpose identity 在[SceneTextureLookupIdentity](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift)；物理解码、上传、Candidate 和 publication 留在各资源 owner。路径归一与资源访问在实际入口检查，内部不重复解析 identity。

隐藏不代表无消费。现有 named/potential 引用和 static-model 需求参与 base source 准备；capture、可见绘制和 graph-final publication 仍需自己的实际资格。不以 visibility 代替资源消费者，也不因预备 source 就宣布 graph 可执行。

图片自然/显示尺寸与物理纹理尺寸分别保留；EXIF 方向由 ImageTextureUploader 解释，像素、mapped/physical extent 保持一致。source size 回填不重算已准备 graph 计划。purpose、alpha、数据通道和编码格式不是可互换的事实，领域规则归[采样与颜色](../capabilities/render-graph-shader-coverage.md#sampling)。

<a id="static-models"></a>
## 模型与有界读取

资源 reader 对文件、数组、索引及工作量有自己的输入预算。当前静态 MDL reader 限总 vertex bytes 256 MiB、index bytes 32 MiB，并检查实际索引/范围；这是解析与工作预算，不是样本白名单。父 resident 账另在实际分配时准入。模型/材质/纹理路径沿同一 ResourceView 根解析，不新增模型专属来源或借无关资源改变资格。

不可变 bind 顶点可共享；skinning 完整成功才发布当前顶点，失败使用完整 bind，不发布半写 scratch。精确 bounds、device、generation、command buffer 与 storage lease 留在实际消费者。具体格式、几何与动画范围归[模型合同](../capabilities/advanced-object-coverage.md#models)。

源码：[MDL reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlStaticModelReader.swift)、[准备设备资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift)。

<a id="cache-retention"></a>
## 可重建缓存

已完成 Shader/Program 缓存按原字节权重和 LRU 有界保留；flight 的当前结果独立交给 waiter，超额不长期缓存也不能令合法产物失败或让同一批 waiter 各自重编。活跃消费者持有与缓存引用分开。持久发布不阻挡采用，归[启动与缓存](scene-launch-responsiveness-contract.md#cache)。

外部用户纹理/视频由原请求、来源权限和 owned-file lease 管理；临时快照不进入持久用户配置或 IPC replay。取消清本候选，失败保旧资源；source、Registry、Surface/GPU 和文件最终引用分别退出。视频读取和格式范围归[视频合同](../capabilities/material-video-assets.md)。

新增原生分配必须接原总额入口；测试应覆盖实际对象共享、失败返还、GPU 在途及最终释放，而不是仅检查 stop 后计数。更多额度不等于支持全部内容，驱逐缓存也不等于降低实际峰值。
