# Scene resident resource admission

<!-- document-role: active-plan -->

2026-10-01，设计 approved；实际验证见当前运行证据。属于跨 resources / targets / particles / Session 的预算权威迁移，generic-only。

## 目标与所有权

当前各屏 target pool、粒子 buffer 和 decode cache 分别限额，不能限制多屏或 active + candidate + retiring 的叠加峰值。增加唯一进程级 SceneResourceBudget，作为这些资源的总准入权威；已有本地预算保留为各 owner 的子上限，不是独立总额度。它只记字节和租约，不注册资源 identity、provider 或 graph，不替代它们的生命周期。所有 Scene 原生 Metal 分配及视频导入通过同一入口预留；decode cache 保留操作同时进入该总账。

总上限为 Metal recommended working set 的四分之一，封顶 3 GiB；设备未给建议时用 512 MiB。decoded cache 在此总账内另限总额四分之一，避免可重建缓存吃完 GPU 额度。性能配置降低本地 cache 上限不撤销已被使用的资源，只拒绝新增。此预算是应用可控 resident admission，**不等于进程 RSS 或 OS OOM 保证**：VM/解析对象、解码器瞬态和 AVFoundation 私有缓冲、driver/pipeline 内存、CAMetalLayer drawable 是未计入项；后者保持原有平台/单对象限制，不能在报告称全进程硬上限。

## 分配与释放

GPU 入口先用 Metal heap size-and-alignment 查询所需字节，在加锁总账中预留，再调用原生分配；失败立即释放。租约附在实际 MTLResource 上，资源被 CPU owner 或 command buffer 保留期间持续记账，最终对象析构才返还。不是按 session.stop 或 cache.remove 提前返还；不同屏或 session 共享同一个对象只记一次。视频导入在发布前按 pixel buffer data size 预留，租约附到 backing buffer；独立的同格式 Metal view 同时保留 CVMetalTexture binding 和 backing，使同一 buffer 的多个 view 只计一次。不能把 backing 关联到 Core Video cache 持有的原纹理，否则退休帧会随 cache 累积；GPU 保留 view 期间不得提前返还额度。解码缓存沿用既有 lease 的 reserve/release，父账先原子准入；没有 payload 哈希或每帧扫描。

base images 清理之后，静态模型与 surface 图片/粒子准备仍可能重新填充同一 loader 的 CPU 解码缓存；各同步准备结束点再次清理可重建缓存，保留已发布 GPU texture 与消费者资源。不得通过清空 GPU cache 或提前返还仍在使用的租约模拟回收。

离屏池 automatic 子额度取 Metal 建议工作集的八分之一，仍限 192 MiB–1536 MiB；默认设备区间相当于父账的一半，实际分配继续先取得同一父租约。10-10 完整封面与波形同时执行的合法驻留集合已超过原 /16 子额度：旧 history 有真实 pin、shared pair 已按尺寸去重，不能为过门丢历史或放宽别名。此次只修子额度策略，不增加总账或动态借贷 owner，显式 residentByteBudget、COW、取消/完成和多屏总额约束保持不变。验收包括实际媒体连续播放、父账占用/拒绝观察及低预算/跨surface争用；不据此宣称降低显存或全部重型样本可运行。

预算拒绝沿现有 nil / allocation failure 通道拒绝最小 unsafe unit；不停止健康屏、不挪用仍在飞行的资源、不自动驱逐其他会话。候选不能首帧则按 Session 合同失败并保留 active。旧会话与新会话在 GPU drain 期间一起占额度。低配额或连续请求下可以明确拒绝新候选，禁止靠清空旧画面省预算。

## Startup source readiness：隐藏 provider 的资源准备

RF05（2026-10-02）纠偏属于①跨 Host/资源/provider 与②唯一资源生命周期的设计前置；不新增预算或资源权威。目标：显示隐藏不等于未被消费，作者普通 image consumer 可采样的隐藏 base image 在启动时须可准备，实际 capture/publication 仍由现役已准入 dependency plan 决定。

当前反例：`Runtime/Session/SceneDesktopWallpaperHost+DeferredBaseImages.swift:38–49` 只豁免 static-model named providers；初始combo覆盖令普通image provider隐藏时仍defer，`PreparedDeviceResources`不加载，consumer缺source。冻结App三对照证明常量隐藏可采蓝、属性隐藏却显示白、无consumer隐藏仍defer；是启动资源策略首断点，不改变可见性或shader。

选择复用 `SceneNamedTextureDependencyReferenceAnalysis.references` 与 `potentialNamedReferences` 的现役作者引用事实，将对应provider与已有static-model provider合并后从defer候选扣除。它只预备base source，不授予执行/graph identity/publication，也不保证资源分配成功。备选逐帧触发provider加载扩大异步首图失败窗口；另造活跃graph会复制owner，均不选。已有terminal user texture遮蔽的named字符串不构成引用；typed optional来源可能发布absent，其fallback与初始inactive effect的direct候选均沿同一投影准备。没有引用的hidden对象继续defer。隐藏consumer潜在引用可保守预备，便于其随后显示；这不是精确active闭包裁剪或性能收益声明，若需缩小须由现有prepared dependency owner发布完整潜在需求后替代，而非独立分析器。

首轮真实App的可见→隐藏对照又暴露同一源的准入断点：`SceneDependencyRenderPlan+ImageProgramReference.swift:436` 及 `+BindingCompilation.swift:570` 对无效果普通图片重复要求初始hidden，造成已加载source仍被拒绝。限定纠偏：无effects、无dependencies/children、非Puppet的普通image，named composite沿既有capture owner提供source，display visibility不改变该源的资格；两入口复用现有predicate，不新建route或重复执行。Renderer在display过滤前已有capture调用。effectful visible image仍须现役graph-final publication，geometry/aggregate及purpose/顺序/cycle约束均不扩大；合法前向引用复用既有capture prepass，顺序与循环失败沿原最小单元处理。备选把visibility变化变成全图重建无必要；仅删除测试不能恢复目标。纠正门新增初值可见→隐藏、反向切换、前向消费及不合profile反例；统一prepared需求同时接管资格和资源准备后退役过渡判据。

资源失败/预算仍走最小局部失败，不伪造publication，其他层与安全输出保留。纠正门：三个真实App对照、provider显示负ROI与consumer采蓝、live双向、terminal-shadow和已准入rgbmask profile的optional fallback，以及零引用继续defer；记录frame completion、provider capture/binding、terminal与next-frame，不能仅查source存在。没有声明或source-proven purpose的system RGBA透传仍可能被现役需求准入拒绝；这是未开放profile，不是非法作者GLSL，也不由资源准备片猜成color。source readiness由单一prepared需求完整接管且同组反例通过后，退役本段过渡selector策略。

## 机器门与反例

增加 allocation-entry 审计，检查 Scene 产品范围的原生 makeTexture/makeBuffer/CV 导入只存在于总准入入口；这属于所有权架构门，产品测试仍断言行为。新入口是全体原生分配的替换，非第二套产品资源 registry。新 helper 家族登记到 source layout；没有按样本或 provider 类型分派策略。

行为门：并发预留不超额；失败分配返还；decode 与 GPU 竞争同一额度；共享纹理不重复收费；停止/删除 cache 后仍被 GPU 引用的资源不提前释放；GPU terminal 后最终引用释放归零；小预算下拒绝候选而旧输出保留。Debug build 与代表原生播放分开验证。所有产品分配接入、反例通过、文档同步后退役迁移登记；新增分配入口必须经过同一架构门。

## 锁内 graph resident 查询

同一批 graph 的 reservation、准备准入与提交刷新只在原 `SceneOffscreenTextureAllocationCache` 锁内使用一份不可变 resident 视图。该操作内的临时索引只存 key，按原 graph key 查询 allocation，按原 history resident key 查询历史，按 generation 区分唯一 key 与歧义；不复制 Entry 作为索引值，不缓存跨锁、跨帧结果，不成为第二份可变 resident/pin/预算账本。原 dictionary 仍是唯一资源与发布权威。

原视图与合法 demotion 后视图分别建立索引；没有发生 resident 变更时复用同一索引，不能给旧 reservation 换 revision 或在修改视图后继续使用旧索引作实时判断。提交循环会变化的 `next` 仍查实际内容；capacity 沿原唯一算法消费惰性序列，减少整份数组复制。foreign preparation、重复 generation、shared pair、in-flight、history/COW、预算、reset、取消和部分选择的原拒绝边界不放宽。索引在操作返回前退出，不延长 texture/pin 至下一帧，也不保留完整 frame Program。

先以真实 pool/准备/提交门覆盖冷暖、多 graph、无关 resident、history、重复 generation、pin 与取消反例，再用短消融比较整体 CPU/准备成本及内存；显著收益才进入工作卡正式多轮对照、独立样本画面与最终独审。单 graph 或密集 resident 反例恶化、正确性退化或两次有区分力试验无收益时修正/撤回，不以局部查询计时替代整体收益。


## 大型静态模型准备后继（已实施）

大型模型的完整校验、累计工作预算及分块identity合同已并入[运行架构](runtime-architecture.md#34-通用执行不等于单体-renderer)相邻静态模型段；真实反例、取舍、CPU/GPU成本与剩余土星画面问题见[实施后验](../history/l1-heavy-retest-2026-10-07.md#large-static-model)，不再作为未执行工作卡。

## 同帧有序合成分段（已撤回）

[双层分段短筛](../history/gpu-cost-screening-2026-10-14.md#ordered-pair-segmentation-screen)在原owner证明资源独立与消费顺序，真实App主pass36→27且无新增copy/分配，但两次同App反序对照均未证整体CPU/GPU收益，候选已恢复，不继续扩大段长。资格、像素/生命周期门及失败证据保留；如将来有新物理成本证据再立切片，不以条件排列数量当性能目标。现役执行顺序归[性能卡](../roadmap/performance-convergence-card.md)。

<a id="shader-completed-cache-retention"></a>

## Shader completed cache retention

2026-10-15：限制跨Scene保留的可重建CPU编译结果，不清空合理复用cache。原generic resolution、compiler completion、Frontend memory和Preparation cache各保唯一owner；共享内部容器只执行completed项LRU，不拥有compiler、Program、资源identity或生命周期。旧行为组合fixture已复现outer重试两次而inner仍返回首次workspace失败；96项小/大Program都全量保留，不能用entry数代表字节边界。

初始子限额为Preparation **64 MiB / 256项**、Frontend **16 MiB / 512项**、generic resolution **16 MiB / 1024项**、compiler completion **1 MiB / 4096项**；独立固定子限额合计97 MiB缓存权重，不借用GPU/decoded预算。旧293 native cache按显式source、sourceMap、annotation双typed值、declaration、layout/binding等字段及容器余量计，Preparation160项约11.77 MB、单项最大140416 B，原256项即使均取已见最大仍约34.3 MiB；Frontend已见单项约29 KB，512项约14.2 MiB。旧304冻结54key的GLSL+MSL合计558376 B，旧293的73个generic Program值约0.67 MB，generic子限留完整GLSL key、语义元数据、合法大项与多重工作集余量。compiler子限只保key与URL。两份旧输入只支撑初始容量，不是当前App性能基线或最重内容上界；当前重样本二遍新增编译/反复驱逐须复核子限，不能仅改数字过门。

权重只在完成发布时按owner的有限typed字段累计UTF8与固定结构余量，新增保有字段须同步成本与反例；不使用Mirror、整图JSON/哈希或逐帧扫描。COW共享可保守重复收费，权重不是严格heap/RSS，也不包含仍被active/candidate/in-flight消费者持有的Program、编译器瞬态或Metal driver对象。Frontend磁盘load及新store均经同一内存准入，磁盘身份/验证及现有磁盘淘汰不变。

驱逐只移除completed缓存引用，活跃CompiledVariant/PreparedAssembly与prepared命令保持原强引用。单项超额/权重溢出仍返回原合法结果，仅不长期缓存；不取消in-flight或拒绝作者内容。原NSCondition内的临时Flight把本次结果交给所有已加入waiter，再退出：即使结果不准入或completed项被驱逐，也不能令waiter逐个重编。generic resolution及compiler失败只在本次Flight共享，后续独立请求可修复后重试；不同material/surface或新准备的串行失败请求仍有重试成本，不保证每generation同key只执行一次。普通帧沿原已准备variant选择，不进入compiler；Preparation现有坏输入负缓存仍受同一LRU约束。无stop清空、跨ownerregistry、新CLI、后台timer或普通帧诊断。

最近门覆盖组合失败→修复、按字节/最近使用驱逐、长key/MSL/map/annotation/layout字段、最大单项不缓存仍成功、活跃值驱逐后可用，以及已加入waiter在超预算/失败时只执行一次operation；再复用cold/warm持久cache门。四owner权重上限与Flight共享由真实owner fixture证明；原daemon连续loadScene用于不同shader/Combo及轻重切换，真实App短筛核同PID重访、编译operation与非零surface资源gauge回落。warm门约束首次已成功的同key，失败key重试单列。现协议无原owner终值，旧session/pin退出仍未验，不把shutdown归零或process退出当资源回落证明。[实施证据](../history/shader-completed-cache-retention-2026-10-15.md)已闭行为门、Debug build、三轮真实owner压力及同PID七步真实画面短筛；暖重访无新增成功编译operation，轻场景GPU/pool回落。App CPU/首帧短窗有波动，尚未通过正式整体性能验收；长期pin退出仍开放。若重访反复编译、启动/CPU明显退化或画面改变，先查成本/容量与Flight合同，修正或撤回，不以清cache认领收益。
