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

<a id="depth-submission-order"></a>
### 深度与帧临时附件的提交时序

同MTLCommandQueue中，前驱已enqueue、后继仍pending且资源为直接绑定的tracked纹理时，可复用同尺寸临时附件；不依靠CPU等待，不恢复默认MSAA。依据[Metal资源同步](https://developer.apple.com/documentation/metal/resource-synchronization)与[命令缓冲顺序](https://developer.apple.com/documentation/metal/mtlcommandbuffer)。跨queue、未enqueue前驱、改尺寸和额外history/preparation/sceneColor持有不借此覆盖。

深度池保原pool/lease、三个物理slot及每CB独立预约，最多三个CB×三个slot记录；同CB不同pass仍隔离。取消/完成只释放自己的预约，退出每在途CB独占相同附件的旧条件。工厂和pass准入已确定format/sample/extent，不逐part重验；保真实CB/pass域与不可用租约结果，Frame/history/publication不迁移。

原frame scratch事务沿既有Entry/submission pin判断，`reserveFrameTextures`与`compositionTarget`共同消费，不加状态、缓存或预算owner。保同帧同key及untracked的原同CB许可；跨CB必须逐pin满足同queue已enqueue且实际纹理tracked，不按影图名字或样本选择。nil观察只复用无pin对象。队列事实沿一个Metal小谓词；`Context.accepts`仍为精确CB身份，不能放宽已准备资源/请求归属。compositionGroup独立入口尚未授此扩展。

验收先证旧跨CB副本，再核共享对象及各CB内编码的.75/.25或红/蓝原读回；补同CB、跨queue、未enqueue、untracked、取消/完成、容量和resize。现役graph/history与相机深度门保持，完整星环及独立作者保画面/排空，并以同场景实际pool/设备采样裁决。小载体或算术节省不能代完整App峰值、稳态、能耗；未获益就停止该候选，资源构成未知不作影图归因。

<a id="framebuffer-snapshot"></a>
## 背景快照容量

普通特殊混合与粒子折射复用原`SceneFramebufferSnapshot`，按真实目标的尺寸/format分配，再沿原顺序copy、采样与绘制。默认容量直接服从`makeSceneTexture`的全局实际分配计费，不另设固定默认子额度；显式调用者提供的`byteBudget`仍约束逻辑字节成本。缓存命中的尺寸/format不可变、实例设备与显式限额固定，直接复用，不重复计算已准入对象的成本。真实全局计费仍以设备size/alignment为准，逻辑统计不代总账。

`prepareCapacity`只准备容量，不编码背景或认领当前像素；命中也要执行原continuation。第二owner或continuation失败时恢复先前slot和统计，新旧在途对象沿原租约释放；不足只拒对应分配，不抬总额、不改变分辨率/格式或停止健康peer。每次capture仍读取该作者顺序截点的当前背景。

选择沿原分配链退掉重复默认限制，保全部采样/生命周期接口；ROI目前只减copy、驻留仍全尺寸。本决策不扩纹理原点、shader接口、多slot缓存或第二预算owner，也不认领驻留/带宽下降。验收用超过原默认额度的真实BGRA/HDR准备与capture、可见大目标混合像素、cache命中/全局不足/显式限额、双owner回滚及在途最终释放；达到能力与相邻像素合同后停止此切片。

<a id="source-readiness"></a>
## 来源、用途与准备

逻辑 path/purpose identity 在[SceneTextureLookupIdentity](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureLookupIdentity.swift)；物理解码、上传、Candidate 和 publication 留在各资源 owner。路径归一与资源访问在实际入口检查，内部不重复解析 identity。

隐藏不代表无消费。现有 named/potential 引用和 static-model 需求参与 base source 准备；capture、可见绘制和 graph-final publication 仍需自己的实际资格。不以 visibility 代替资源消费者，也不因预备 source 就宣布 graph 可执行。

图片自然/显示尺寸与物理纹理尺寸分别保留；EXIF 方向由 ImageTextureUploader 解释，像素、mapped/physical extent 保持一致。source size 回填不重算已准备 graph 计划。purpose、alpha、数据通道和编码格式不是可互换的事实，领域规则归[采样与颜色](../capabilities/render-graph-shader-coverage.md#sampling)。

<a id="conditional-tex-atlas"></a>
### 条件 TEX 图集

TEXB0004 的条件声明和 mip 内图块由原容器入口读取。各 mip 的矩形坐标独立，图块按记录引用条件 ID，替换基图该矩形的 RGBA。官版全透明图块通过清除覆盖区露出背景。每级原 atlas extent、UV、颜色用途和 mip 顺序保持。入口验证范围和长度，并把未陈述的字段按位置读取。已知布局失效时沿基图局部恢复，未知条件和缺键选择默认。普通 PNG、压缩、sprite、volume 和视频仍走各自的原入口。此前把声明计数当 mip 计数的读取分支在已确认的条件域退出。多条同时成立且相交时的官方次序、半透明图块的精确颜色均待独立验收。

准备阶段把条件声明编译为原 typed property 的键和比较值，基图链的预算优先于可选图块。原 base-image 资源 owner 按真实纹理来源及用途合并同一 atlas 的消费者，启动只准备当前选择。已准备的真实消费者将其条件键提供给原属性可用性报告。对热编辑复用现有资源就绪与 property revision 的提交门，按变化键请求下一份完整候选，保持当前纹理和已提交属性到共同可用。已经准备的普通静态资源直接交给 Surface，省略视频识别重读。每份物理纹理发布后保持不变，新旧交叠只到在途帧或正在准备的请求退出。无需在帧内重读文件、重求条件、重编材质、重建 Puppet 或永久保留全部候选。

接纳在各 Surface 与下一份真实 property snapshot 同批切换。普通来源更新沿原发布，Puppet 复用当前几何的 encode/prepare 和本地坐标，只重新绑定实际采样图集及 resource generation。失败或过期请求由原资源事务结束，保持健康 peer 与当前图。当前热接入覆盖作者基图和 Puppet。材质附属纹理、动态构造和发射图沿各自资源消费者验收。

原包复现以面具正反切、两主题、同图集双消费者和真实 GPU 末端为验收。独立原包需有非零并逐级变化的图块矩形，另核改名、条件等价、缺键、范围坏枝和普通 TEX 邻例。记录首次准备与反复切换的开销、过期结果和退出，现行实现与画面见[原包对照](../capabilities/runtime-evidence-current.md#author-conditional-mask-376)。

<a id="material-graph-view"></a>
### 材质的图资源视图

整组persistent目标的完整驻留预检只归原FrameResourceBundle准备入口；上层FramePreflight组装当前计划，不先扫一轮同组resident。资源入口以有载荷的ready、temporarilyBlocked、rejected结果返回原Admission：busy仍延期，预算/计划拒绝保原因，不压成bundle缺失。实际reserve/commit仍核当前pin、代次与请求身份；不加已预检布尔许可、持久token、镜像缓存或第二预约owner。验收核busy→完成→ready、真超额零分配、取消与history使用期，并比较完整作者像素/播放及成本。

每次 material 绑定只把已准入 `Graph.Node.bindings` 的完整候选集合及该 effect 的隐式 framebuffer input 投影到原 frame snapshot；不能只取 State 的 framebuffer bindings 或当前 variant 的 active slots。冷 template admission 已将 graph 候选与 node bindings 对齐，暖帧沿这份事实取当前资源，不另建 read-set cache、游标或认证。原 base/named 依赖快照保持，退出每个 material 都重新校验、转换和折叠全部已发布 graph 原子的旧范围。

完整 publications 仍归原 graph 事务，供 history、copy/swap、后继 stage、最终输出及失败回滚使用；局部视图不改变它、不跨 material/帧持久化。仍由原 overlay 验证所传原子并按值生成 snapshot，selectionDigest 沿原增量算法反映本视图；未读原子退出可使摘要数值改变，不能重做全量 digest 或伪装旧值。选出的 Program、实际 slot/资源代次与输出 identity 必须保持，集合外实际 lookup 一旦出现就停止此替代，不补全量 fallback 或第二资源 owner。

验收沿真实 graph/material 门核未选中候选的 readiness、显式 pair alias、隐式 input、named 混合、history/copy/swap 与拒绝重试，保已有颜色和局部失败半径。只有同条件运行证明成本下降才记录性能收益，不从投影项数、Debug 诊断减少或构建成功外推。

<a id="static-models"></a>
## 模型与有界读取

资源 reader 对文件、数组、索引及工作量有自己的输入预算。当前静态 MDL reader 限总 vertex bytes 256 MiB、index bytes 32 MiB，并检查实际索引/范围；这是解析与工作预算，不是样本白名单。父 resident 账另在实际分配时准入。模型/材质/纹理路径沿同一 ResourceView 根解析，不新增模型专属来源或借无关资源改变资格。

PKGV 同一已打开包的索引字段与所选条目由 [包 reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift) 以至多 64 KiB 的单次读取直接填入返回块。正短读按实际字节推进，取消、提前 EOF 或 revision 改变沿原入口拒绝。ResourceView 负责条目范围和消费，完整 snapshot 仍等待原读循环成功，流式消费者按原事务暂存。 [范围与性能证据](../../development/wallpaper-quality-work-card.md#scene-package-read-copy)

不可变 bind 顶点可共享；skinning 完整成功才发布当前顶点，失败使用完整 bind，不发布半写 scratch。精确 bounds、device、generation、command buffer 与 storage lease 留在实际消费者。具体格式、几何与动画范围归[模型合同](../capabilities/advanced-object-coverage.md#models)。

源码：[MDL reader](../../../MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlStaticModelReader.swift)、[准备设备资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/ScenePreparedDeviceResources.swift)。

<a id="cache-retention"></a>
## 可重建缓存

已完成 Shader/Program 缓存按原字节权重和 LRU 有界保留；flight 的当前结果独立交给 waiter，超额不长期缓存也不能令合法产物失败或让同一批 waiter 各自重编。活跃消费者持有与缓存引用分开。持久发布不阻挡采用，归[启动与缓存](scene-launch-responsiveness-contract.md#cache)。

外部用户纹理/视频由原请求、来源权限和 owned-file lease 管理；临时快照不进入持久用户配置或 IPC replay。取消清本候选，失败保旧资源；source、Registry、Surface/GPU 和文件最终引用分别退出。视频读取和格式范围归[视频合同](../capabilities/material-video-assets.md)。

新增原生分配必须接原总额入口；测试应覆盖实际对象共享、失败返还、GPU 在途及最终释放，而不是仅检查 stop 后计数。更多额度不等于支持全部内容，驱逐缓存也不等于降低实际峰值。
