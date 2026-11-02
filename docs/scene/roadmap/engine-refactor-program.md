# Scene 引擎重构顶层设计

<!-- document-role: stable-contract -->

本设计规定优化方向、职责和退出条件，不维护批次顺序或完成状态。全局优先级归[兼容路线](scene-compatibility-roadmap.md)：画面合成/正常播放、性能、属性热更新、其他；当前开放项归[断点队列](scene-open-breakpoint-queue.md)。[性能卡](performance-convergence-card.md)与[属性卡](properties-panel-card.md)只维护各自专项选序和验收；已完成的SteamKit迁移退役，获取服务按[稳定合同](../../architecture/steam-workshop-acquisition-contract.md)维护。旧 E/AS 编号只用于历史追溯，不是串行前置门。

## 目标与取舍

真实 Scene 正确加载、播放、交互和合成；正确性优先，其次覆盖收益、简单性与性能。在相同作者内容、画质和资源安全条件下，减少整体 CPU/GPU 工作、内存与启动成本，改善属性响应。帧时限达标不能证明能耗合理；局部阶段下降也不能替代整进程或用户交互收益。

以现有 Swift/AppKit、Metal、系统媒体能力和通用编译/VM 底座演进。重构围绕已证成本、能力缺口或确认的职责偏差展开，允许替换不合理的旧结构；整体换语言、新框架、第二 renderer 或更多缓存均不预设为目标。新增或替代机制须说明旧职责何时撤权。

### 顶层设计收敛决定

完整设计由[运行架构](../architecture/runtime-architecture.md)统领，[组件与系统职责](../capabilities/runtime-systems-reference.md)定义组件分类、状态所有者和代码落点；二者分别回答整体如何运行、组件如何接入。[实际代码地图](../architecture/runtime-as-built-map.md)仅记录当前接线，不能把暂时准入形状变成长期架构。

| 设计选择 | 裁决与理由 |
|---|---|
| Swift/Metal、少量 C/C++ | 保留产品状态与图形 owner；C 承接 VM ABI，C++ 承接通用编译依赖，不重写整个引擎 |
| 独立 Scene daemon | 保留已实现的控制面/播放面隔离，不回退到外部初始提案的同进程起步 |
| QuickJS-NG | 保留真实 VM、预算与中断能力；系统 JavaScriptCore 不因一份通用提案重新成为首选 |
| 作者数据、准备产物、运行状态 | 明确分期和唯一可写权威；让普通帧直接消费已准备结果，退役字符串重解和互相同步的镜像 |
| 多类组件 | 保留已有粒子、文字、媒体和几何 producer；统一身份、属性、时间、资源和输出，不提前建设通用 ECS 或插件框架 |
| 目录演进 | 沿 Format/Compilation/Resources/Systems/Rendering/Runtime 的真实职责纠偏，不整仓机械改成提案目录 |
| 当前有界实现 | 用能力表说明真实支持范围；不把固定 slot、格式或组合白名单写成所有未来组件必须遵守的架构 |
| 设计与验收 | 重要边界先设计，局部实现直接推进；既有门保护真实错误，不新增设计评分或逐组件认证层 |

不合理的现有职责允许整体替换。每次替换明确目标数据、原 owner、消费者、释放点与旧入口退出；代码编写量不作为保留已证错误 owner 的理由。当前具体重构要求统一进入[开放队列](scene-open-breakpoint-queue.md)，不由本设计另外建立执行顺序。

### 架构级迁移合同

本次长期重构以当前独立工作树为实施域。终态是原 Scene 能力进入同一准备、类型状态更新和 Metal 合成主链，数据与资源各有实际所有者，旧职责退出；不能以搬目录、拆扩展或增加 facade 代替迁移。阶段顺序与未闭状态只维护在[架构重构队列](scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)，设计改动先保存，再实施对应代码。每批按能力族独立提交，包含实现、必要测试、合同及旧路径退役；不把全引擎混成一次提交，不推送或发布。

外部初始方案 `Scene-Engine-Architecture-Design.md` 的有效原则已纳入总设计和组件合同：作者定义/准备结果/实例/GPU 状态分期、轻量节点与类型数据、parent/update/render 三种关系、最小失效域、缓存可重建、CPU 模拟与上传分开、实时/离屏共用执行链。保留现有目录、daemon 与 QuickJS；不重新实施初始提案的同进程、JSC 或新建通用 ECS。模块数和代码量不作为收敛成果。

**能力保持。** 首个产品改动前固定产品源码基线和一份可运行 App；旧能力台账及真实成功输入作为比较起点，不能把迁移后的新拒绝重新解释为原本不支持。使用现有样本快照、benchmark 和行为门保存同输入结果，覆盖文本、脚本、属性/Timeline、图/历史、粒子/child、Puppet/模型、视频与声音等已有能力。45 项矩阵和尚未全部就绪的 Fast Suite 只是其中一部分，不代表全部语料。每批验证受影响族及健康相邻族，最终按实际可用语料交叉回归；时间、属性、声源、指针、视口与 App 身份不相同时不宣称画面等价。

迁移中允许未完成路径暂时异常，但必须保留基线与未闭项；全部迁移完成前须恢复迁移前正确播放能力。日志、构建和非黑只证明各自范围，最终还需相应真实可见、交互、切换/暂停/恢复及资源退出证据；对不能冻结的实时输入按可观察事件和结果比较，不伪造逐像素等价。未验能力保持未闭，不通过改期望值、缩小成功集合或降低质量结项。

**成本与纠偏。** 普通帧只推进活动状态、消费已准备资源与编码。入口检查一次；保留真实防止越界、串台和 GPU 使用期错误的边界，撤掉重复检查、无消费者投影、每帧重解、复制与诊断。新增状态或抽象要有真实消费者，并同步移除被替代者；每批分别报告产品、测试、文档增删和用户收益。遇到只能继续叠排除集合、形状白名单或转发层的方案，先回到公共语义与所有权调整设计，不能沿旧错误路径硬推。结构改造的收益须体现为更直接的执行/释放链和更少的重复工作，性能提升另以同条件测量证明。

**整体退出。** 架构合同的职责要求、实际运行正确性和验证覆盖分别裁决。没有普通帧重解析、没有可测热点或门禁通过，不能关闭仍违反目标合同的准备/运行依赖；也不能为了词法库存归零机械搬文件或公开内部算法。按组件合同完整核对作者数据、准备、实例状态、帧消费、GPU和退出，再把具体未闭职责留在唯一队列。每轮实施和最终复核都重新对照总设计、组件合同与实际接线；记录完整链的审查范围，有限Context/descriptor审查不代替全组件审查。

最终能力保持须覆盖受影响及健康相邻族，另贯通实际App入口、client/daemon、属性更新、暂停恢复、切换及资源退出；直接Host、直接client和产品入口按各自真正经过的链分别声明。已确认结构职责全部落地且相称运行/失败反例完成后才结算整体；独立兼容缺口或不可得硬件资格明示范围，不靠重复相同实验、代码数量或阶段记录充作完成依据。

### 语言执行收敛：文本首批

文字定义从格式入口进入既有 SceneScript binding；同一 Session QuickJS domain 负责源码、属性、init/update、媒体事件、异常与销毁，文本 producer 只消费当前字符串及样式并排版。撤销 `SceneTextScriptCompiler`、Subset evaluator、MediaProperties 源码识别、独立 Program/帧合并与重复 `textScript` 描述；共享 alpha 的手写语言另在同一语言收敛阶段迁入 VM，不永久保留第二 shared heap。

迁移不能只删除旧解释器。现有旧日期路径使用冻结的 wall date，VM 的 Date 必须在回调中消费同一帧输入，保留显式 Date 构造、解析、原型和本地时区语义，不修改第三方 VM 源码或另建时钟。JSON scriptproperties 的值包装和无关元数据在读取/准备入口归一，合法附加字段不成为执行许可；属性值继续走同一类型桥接。旧路径已支持的隐式 scriptProperties 输入由同一 VM owner 承接，与作者显式导出的对象分清，不能按源码写法选择另一解释器。

媒体事件未到时保作者值；有效事件里的空字符串清空内容，不当缺数据。隐藏但已进入准备集合的文本、纯事件和 init-only 绑定、用户属性、错误回退及 owner 退出沿既有 VM/typed 状态语义。保留实际语言、日期、媒体、优先级和绘制行为用例；退役仅锁旧语法拒绝域或源码形状的断言。验证复用 StringProgram、QuickJS、动态文字与真实文本作品，不复制旧 evaluator 到测试。

### 语言执行收敛：共享状态与 alpha

共享 alpha 沿现有 IR → 同 domain 的模块初始化/事件 → scalar update(current) → typed snapshot → 原 compositor 执行。Bool/visible 模块的顶层初始化、cursor 与 applyUserProperties 写入真实 shared heap；alpha 读取同一对象，不再从源码抽取并保存第二份 flags。作者 rise/fall、上下界与条件属于脚本本身，VM 返回值仍按原 scalar/consumer 合同处理，不能先把合法上限 50 截成 1。

模块生命周期不能以内容种类或旧utility源码准入代替。现有资源/graph准备已经保留依赖composition的可见消费者；真正不支持的project/fullscreen依赖、子层与effects仍在SourceRoute/UtilityRuntimePlanner实际消费处局部拒绝。删除Bool投影中重复且更严的kind白名单与utility形状关卡，让旧初始化路径接受的模型、带依赖或层级utility沿同一Bool owner构造、事件与退出；不新增output-admission flag或模块管理器。Bool值仍进入原typed snapshot，不能凭该值产生不存在的资源/target plan。验证无callback初始化、属性事件/返回值与无prepared plan的真实consumer反例，不能仅测无依赖project。

退出四个 SharedLayerAlpha Syntax/Compiler/Program/Runtime 文件、RuntimeModel 的独立投影与 claimed-target 分流，以及 LaunchContext/FrameSchema/Session 的旧字段、预求值/合并、pending/commit 与启动报告。仅剩一个 vector producer 的通用集合循环改为原集合直接使用；由投影已排除的 target 不在同一同步准备中重复校验互斥，不删除真实 duplicate/property/Timeline 冲突检查。

复用现有 authored owner 顺序、初始化 barrier、cadence cache、property revision、surface commit 与生命周期；失败只撤受影响 typed 输出，不能为模拟旧 CPU candidate 而克隆或回滚 JS shared heap。先用真实 VM 正反门覆盖初始化、开关、2×上升/6×下降、上限热改、嵌套 fallback、等价 JS、异常与重复 cadence，再用原始作品的默认/点击/属性变化及健康文本邻例验证实际画面。旧语法白名单和与假 shared 状态绑定的断言同批退出；未过完整多屏、暂停/恢复或官方语义范围保持未闭。

### 属性绑定程序的准备与实例值

`ScenePropertyBindingProgram`是不可变作者绑定程序；结构验证和必要索引只在构造/解码入口形成一次。复用现有Validator与Validation，不新增PreparedScene、registry或缓存owner。Validation保存唯一有效definition查找；Program保存按property key分组、conditional组及rebuild-key集合。各准备期visibility投影读取这些结果，不为仅在准备期查询的target集合增加持久缓存。

普通属性求值只转换当前输入、检查实际数值域并产生typed值；不再验证整Program、重建definition map或conditional组。LiveUpdateState只持实例输入、当前user值、revision及其实际consumer资格，撤销自身重复validation/group/rebuild集合；Session、Puppet准备与text template沿同一Program消费准备事实。旧外传validation的evaluate重载与接受完整Program的重复验证入口同批退出。Program构造仍可保有效子集及结构诊断，解码继续拒绝结构非法输入；不能对未经筛选的重复target直接创建唯一键字典。

Codable保原四项作者字段，派生索引不进入IPC/磁盘载荷，Equatable继续只比较作者程序；新进程解码为自己准备一次。有效值每次仍按类型/finite/range和conditional组原子语义求值；same-value revision、active/unavailable/retired consumer、资源请求及异步newer-wins边界保持，不把本批扩大成增量求值算法或LaunchContext字段搬家。

最近门验证compile/decode等价、坏结构拒绝、direct/conditional target、输入连续改变、两实例不共享current和失败不改revision；保现有真实行为断言，删除只锁LiveState旧私有字段的源码形状测试。再比较同输入旧/新真实求值成本与原包属性→VM/typed→compositor及正常退出；局部阶段成本不外推整体帧率、面板延迟或能耗收益。验收后按属性数据分期独立提交，其他descriptor、资源与组件寿命债继续按队列推进。

### 自然尺寸回填保留准备事实

资源自然尺寸只回填descriptor的`sizeWH`，不重新生成与该字段无关的authored effect计划、visibility集合、属性程序或shader合同。沿原RuntimeInput值副本更新唯一descriptor，其他准备字段保`let`；Host继续让runtime与authored descriptor消费同一尺寸来源，不新增构造器、缓存或同步镜像。

这里保留的是作者拓扑、slot、命令与尺寸表达式；后续preflight仍读取回填后的`renderSizeWH`，结合真实input extent求物理frame target，不能缓存回填前的物理计划。缺省、未知ID及资源失败沿原回填语义。用非空计划/visibility与自然非方尺寸、cursor、相对/绝对target extent验证保持，Debug及实际非方image/effect链补可见结果；消除重复调用不自动等于整体启动或能耗收益。

### 用户纹理的准备交接与活动所有权

初始用户纹理与视频声明由既有`PreparedLaunch`短期携带，显式经过Host候选入口交给Session；LaunchContext不保存初始或当前纹理结果。Session持有唯一活动结果，异步采用时只替换这个结果并更新属性实例值，不再向Context写入纹理镜像。准备完成回调只保留模型，避免候选首帧闭包继续持有整个准备载体和已被替换的初始纹理。

各SceneMetalView仍保留实际绘制所需的不可变绑定快照；新表面从Session当前结果构造，in-flight资源沿既有GPU completion/drain寿命释放。这不是第二资源权威。保留跨await的请求、revision、device和Registry检查、同key newer-wins、不同key重基及整key各purpose原子采用；不添加移交状态机或默认空结果兜底。

用现有用户纹理事务与候选激活门验证初始交接、替换/重置释放、双表面一致、失败保旧及迟到拒绝；Debug与隔离真实App覆盖静态/视频选择、正常退出及GPU drain。不能以去掉一个字段声称整体峰值内存下降；释放与画面证据按实际经过的边界记录。

### 材质管线只在准备边界编译

现有GraphExecutor初始化已预备各合法variant、attachment格式与terminal role，source material也在设备准备入口单独warmup；reset仅作prepared command代次失效，不清不可变PSO。沿这两处准备owner补齐实际缺失计划，不能在普通帧遇到key缺失时重新调用Metal compiler。PassEncoder只查询已有结果并绑定当前纹理/目标/uniform，不持第二套lazy编译与origin状态。

撤`framePreparation`编译分支、仅为它服务的cacheFailure和origin字段；warmup继续拥有唯一的正/负PSO缓存、并发源码合并与可选binary archive。正确key缺少准备结果使用独立typed失败，局部拒绝实际受影响的effect/source单元；不能假称key非法、重新编译整景或吞掉该失败。真实无效target、binding、代次与设备边界仍保留。普通帧不为此新增hash、完整诊断或准备关卡。

先用冻结旧App及真实门确认现有准备/帧路径，再验证cold miss零compiler调用、加载成功/失败缓存、reset保PSO、合法format/variant与terminal/source的实际GPU结果；standalone fixture按真实加载→帧顺序显式warmup，不以旧测试依赖保lazy产品入口。实际App覆盖effect/source、属性变体、相邻内容与正常退出；若发现合法遗漏，在原准备owner修正计划再验，不能重新打开draw内同步编译。没有真实测量就不报启动、帧率或能耗改善。

### 文字生产归会话、提交快照归表面

同一Session的文字内容、样式、字体资源、typed值及Metal device相同；当前栅格不消费viewport或backingScale。因此初始CoreText栅格/纹理上传与动态串行worker沿既有`SceneDynamicTextTextureStore`只创建一次，由Session持有，屏幕重建复用。Store保存作者/动态层身份、最新请求、就绪raster和唯一publication；不另建内容hash缓存、跨层去重或producer管理器。相同内容的不同layer仍有各自身份、代次和寿命。

首次成功构造View后、进入其资源装配前，Session完成一次初始load并交给Store；诊断消息只临时传给原启动报告，不保存第二份初始raster。初始generation 0已是合法完整的dynamicText layer-source atom，首帧与后续更新都经Store snapshot→FrameLayerTextureAssembly进入原source/graph/compositor。删除View向base image表merge初始文字的路径，避免动态更新后继续pin旧seed；现有image-only粒子发射图不消费该seed。资源失败仍只缺实际受影响文字，不加假texture、另路fallback或整景拒绝。

prepared/submitted snapshot是每屏呈现事实，不归共享Store。每次Session `renderSurfaces`在循环前取一次就绪publication，直接传给各View；View只固定本次prepared snapshot，并在自己成功提交时替换submitted snapshot，失败或drawable不可用保原submitted。cursor的文字centerOffset继续读取本屏最后提交几何，不读最新异步就绪结果，也不把“已提交”改称GPU完成。Store撤旧prepare/commit/discard/submitted接口及字段，View撤producer、字段兴趣镜像、每屏pending更新与SimulationFrame.textFields。

异步文字请求保持在“至少一个表面成功提交之后”更新，不能顺便提前到CPU cadence而改变初始/克隆可见时序。Session用一份既有pending tuple承接typed snapshot、dynamic layers和字段兴趣，替代各View副本；新cadence覆盖，全未提交时留待重试，首次成功提交后更新Store一次并清除。一个attempt内即使worker完成，后面的屏仍使用循环前固定的同一publication。暂停publication只触发既有driver重绘，不重放VM；初始cohort已held时继续忽略异步publication通知。

单屏关闭/重建只退役自己的GPU与capture，不停止共享worker。清除Session时将唯一Store的closeAndDrain挂到既有retiringSurfaceDrain，然后清活动引用；stop-before-drain、没有surface和失败重建也须等待该CPU尾任务，再沿原surface队列barrier完成GPU释放。不新增退场状态机或第二release fence。

最近门执行真实Store、真实View提交/丢弃与Session调度/退出方法：初始原子可用；连续值只保单任务及最新请求；A/B均提交R0后R1就绪，A提交/B取消时两屏cursor分别保持R1/R0；退役B不关producer且A可继续采用R2；所有surface未提交时不提前请求，暂停重试成功仅发一次；重建复用与stop-before-drain等待真实worker。再用冻结旧App同输入对照双surface动态文字、改名/克隆和原包邻例，核真实像素、字体几何、正常退出与drain。可证明重复生产次数减少，不在未测时宣称整体帧率、能耗或峰值内存收益；媒体、Puppet和粒子剩余寿命不在本批伪称完成。

### 媒体封面生产与冻结帧消费

系统媒体输入已由唯一Inbox提供；同一Session的各屏却通过各自Coordinator/Store重复解码、PMA及preserved上传。直接让Session持一个现有`SceneMediaThumbnailTextureStore`，删除只转发的Coordinator及View内producer；资源就绪由同一Store发布current/previous、mask用途及generation原子。binding Program继续由既有准备事实和Renderer持有，不为启动报告新增镜像。View初始化中只服务旧coordinator的上传queue参数及已无消费者的decode budget参数退出。

每cadence在VM事件前取一次Store snapshot，terminal判断和所有View消费同一值；取消Store的prepare/commit/discard pin及原每屏快照字典，普通帧不重复生成provider表。媒体仍走system-provider通道，退出FrameLayerTextureAssembly中已无消费者的media参数，不把媒体覆盖到layer-source。PMA/preserved/mask保持不同用途及原上传、坏图fallback、current/previous旋转、同图颜色更新和clear语义，不顺便改色彩、解码上限或取色算法。

原文字pending tuple扩为Session唯一`pendingProviderUpdate`，携同cadence的typed文字输入和media input，替代每View媒体请求；任一表面实际提交后清tuple并各请求一次，全部未提交保留到重试或下一cadence覆盖。媒体不等待GPU完成再消费，也不能提前到VM采样或View编码前请求。颜色-only快路径会同步调用producer handler，Session通知必须继续异步进入main，避免post-submit内重入driver。停止清tuple并detach Store，迟到通知在Session实际消费处按Store身份拒绝；不加第二状态机、请求owner或普通帧认证。

View的SimulationFrame只保绘制snapshot和已消费media generation，退出完整encoded input与commit/discard转发；原binding报告读Renderer既有Program。暂停时Session从唯一Store读取一次，仍要求完整surface cohort、同一冻结frame及每View期望的generation全部匹配且terminal，才更新各屏绘制snapshot并标记重绘，不读取新Inbox或重跑VM。publication不再借View转发；View通知只剩surface变化，退役单case reason包装。

Store的publication callback在构造时固定，携自身身份；删除后设handler入口。完整Session stop将`cancelAndDrain`挂原retiringSurfaceDrain后detach，取消当前request并沿原锁内queue尾任务等待已接纳decode/upload；surface重建不取消producer。唯一update入口已经撤权，worker只完成而不再admit，不为假设的Store复用增加closed bool；实际update排队与drain tail共用原锁的顺序。活动上传已同步等待自己的upload command，CPU tail后复用原surface GPU barriers，不新增fence。

先冻结本批前App，复用真实provider门验证两次采用共享texture、同图换色零额外decode、pending/ready/current/previous/mask/fallback/clear及取消尾任务；捕获值固定一帧，替换旧Store pin形状断言。真实Session门覆盖双屏一次请求、全失败保留、部分成功、worker在屏间完成、暂停同generation刷新、held通知和stop-before-drain/无surface。再执行原双Surface paused-media/拒绝一次/坏图fallback App门，以及有界current→previous→clear/邻例，保同输入像素与原失败记录；若现有载体缺五色或previous实际consumer，不以path换图冒称取色或全transition能力。按能力族独立提交，其他媒体、Puppet、动态Layer与粒子职责继续开放，不由减少producer数外推整体性能。

### 动态图层的准备事实与当前值

动态图层沿现有Mutation Runtime/Plan承接创建、完整upsert、排序、销毁和owner原子拒绝，不增加第二份value map、PreparedLayer包装或注册器。Layer仅保存出生时准备的资源、创建尺寸、根层关系和作者seed；C接口不可变的asset/size不在普通upsert重新解析或准备。已有typed定义及`authoredLayerValues`承接当前变换、visibility、solid、alpha、颜色与文字样式。dynamic upsert是完整record，不能按仅供authored局部写使用的Fields筛掉变换；定义在出生一次准备，值变化不推进schema/topology revision。可选perspective保nil的camera默认语义，首次真实Bool写入才建立相应typed lane。

prepared text wrapper已有独立String producer，普通upsert携带的text可能仍是回调前值，不能覆写最新String结果。保既有template content的显式text字段写入与outer-user优先级；literal动态文字无第二producer，content沿完整record更新。新创建template的初值从同Plan最终内容读取，不能在出生seed固定后丢掉显式改写。pointSize保合法原始Double，仅现有文字producer作显示clamp；font保持真实非空路径入口，并复用既有normalizedPath在typed输入处保空白/路径归一；规范化后的显式空值代表系统默认字体，不能误用birth字体回退。动态文字的layer tint与raster颜色两条既有消费均迁入typed值，不顺便改变原颜色相乘结果。

Session继续在回调前捕获已提交拓扑和typed值、末尾提交Plan。首次采用新拓扑的cadence必须拿到同份新定义及当前值，不多迟一帧，也不把所有setter提前到当前回调帧；camera、visibility与particle的现有当帧例外不扩大。失败仍只拒整个实际受影响owner包，保健康peer和此前完整snapshot。动态变换的Float ABI范围约束在Mutation实际入口一次检查，准备函数消费该结果；不能把旧owner拒绝改成绘制时单字段静默回退。

RenderTopologyCache只按结构revision准备descriptor、索引、order、world seed及preparation集合；同revision直接返回，撤`applyingFrameValues`及只服务其覆盖的三个位置表。原WorldFrameResolver复用同一局部矩阵计算；只有dynamic根层变换时在staticFrames上更新这些根，不因typed override出现而退回全作者层级遍历。存在authored变换或Puppet attachment时保原canonical层级路径；不新增world owner或复制矩阵算法。QuickJS作者catalog的Mat4发布只消费既有prepared byID内的变换ID，commit/rollback沿同一过滤结果；动态clone仍由原C record及renderer typed变换负责，不能因新增typed clone target而逐帧重发全部作者矩阵。Text Store首次接纳动态层直接以该cadence snapshot形成signature，退出每帧回写Layer；内容/字体/字号变化只推进既有producer代次。

验收先固定本批前源码/App，复用真实Mutation、QuickJS clone、world、frame与文字门：完整record的无dirty-fields变换、冻结birth/独立snapshot、非空font和空text、raw pointSize、template stateful update与显式setter、变换溢出原子拒绝、排序/销毁/净零出生及peer保持。检查同revision prepared集合不被live值覆写，dynamic根与authored父/attachment反例走原几何语义；再沿同输入旧/新App核动态image/text、多Surface、非原色tint、正常退出及GPU排空。局部准备成本另以相同实现入口和输入比较；不以删除复制次数或benchmark原非PASS结果宣称整体帧率、能耗、完整语料或官方parity。

### 粒子实例与 GPU 上传的所有权

粒子 CPU runtime 继续拥有模拟器、RNG、child 生命周期、当前实例与 Rope/Trail 历史，每次 advance 消费一次 step snapshots。每屏 PlaybackState 的唯一强 owner 归既有 Session.Surface，退出 View 的构造、保存与 ABI 转发；PlaybackState 退出 pipeline 持有和构造，只发布所需 variant 与 CPU 结果。Session 在图像资源装配后沿原 textures/animated IDs 形成 Layer Image map、构造 CPU 实例和独立 GPU pipeline，两者都就绪才安装；pipeline 失败沿原局部粒子不可用语义 teardown CPU。prepared variant 集合为空时保CPU实例/identity/报告，跳过无消费者的粒子library、sampler与depth state构造；不能按当帧空batch跳过dormant child需求。最后由原 loader 释放 decoded cache，不重复驱逐。

原 SimulationFrame optional 从 View 移到 Surface，仍只有一个冻结帧，不新建 Frame DTO、状态镜像或反向回调。原更新流程由 Surface 承接：本屏 pointer/parallax、Puppet 已有阶段、world/camera、粒子推进再冻结；sprite times 由 Session 唯一 texture clock 求值后传入。View退出该clock持有，只在图像装配入口借用其注册动画。View.renderFrame 只消费冻结帧及 Rendering 资源；重试、无 drawable 或 GPU deferred 不再推进 CPU。粒子 emission 的实际坐标准备留 Surface，Session 的查询、计数、安装、验证与转换直达 State，撤纯转发。暂停媒体按原完整 cohort 与同 generation 检查更新 Surface 冻结帧，不读取新输入或推进模拟。退场先撤 CPU，GPU pipeline 随原 Surface/command drain 存活；重建和迟到事务保原 UUID、surface identity 与代次。

退出 root、child template 和 CPU DrawBatch 对可写 instance buffer 的持有；batch 只携实例值、已有不可变准备资源与语义身份。纹理、refraction 等已有准备句柄本批保持，不将 CPU 数据全无 Metal 类型当完成条件。Puppet 的实例持有仍是下一组件族的显式债务，本批不新增其能力或改变其采样阶段。

既有 `SceneParticleMetalPipeline` 在每个 playback/surface 独立构造，改为直接拥有实例 buffer 的引用 owner，不增加 Renderer cache、Registry、引用盒或 Session 共享模拟。复用 key 为 `layerID + childTemplateIndex?`，nil 表 root；同路径不同模板必须独立，同模板多个 child 系统继续沿原合并顺序产生一个 batch。暂时没有 batch 不代表退休，缓存随原 pipeline 释放，不新增 LRU、退休协议或逐帧清表。

DrawBatch 作为 CPU 生产的绘制输入，唯一声明归现有粒子 pipeline 文件，不放进被纯数学消费者共用的 RenderSupport，避免反向引入 Metal/refraction 依赖。实际上传后形成 frame-local PreparedBatch，仅绑定原 draw 值与该次 buffer。它不是第二运行状态或转发 facade，renderer 的深度/快照准备直接读取其中 draw 元数据。pipeline 负责 prepare、draw、arm/mark 与未提交取消；原 renderer 粒子编码扩展退出，正常层循环直接调用粒子 owner。高层 frame 编码与低层 Metal draw 分开仅为真实依赖边界，不另建协调者。

上传仍在原深度资格检查之前，沿原 buffer 过滤非有限实例、保持顺序并使用实际 draw count。原 slot 的使用期合同不重写：draw 前安装 completion，成功编码后 mark，只有 notEnqueued command 可撤销其提交占用，in-flight slot 仅由所属 command 完成释放。移除 renderer 无效的可空 command 镜像和外层重复 arm 去重，复用 buffer 自身的幂等协议；失败只取消本批候选，不释放其他帧使用中的 slot。depth/refraction 顺序、child 最后 render-only sample、CPU rollback 与各屏 pointer/world 输入保持。

主pass writer库存记录实际调用点；本次方法接管有正文调整，不适用字节相同文件移动豁免。复用现有owner_relocation凭据，退出只准一个shader frontend名称的限制：原pattern、总调用数、扫描范围与角色不变，仅一个源文件的相同完整调用迁到一个目标，其他文件及调用保持，关联已批准设计；已提交凭据继续冻结，扩张不获豁免。历史源码从指定Git版本读取，使用与现树相同的Python正则，不将其误作Git ERE。此项只证明有界库存迁移，不能代替职责审查或运行证据。

先冻结旧 App 和最近粒子门，再用真实 Metal 验证 key 隔离、暂隐再现复用、两 pipeline 独立、连续上传、in-flight/取消及坏实例局部过滤；CPU 门保 child 末帧、history、脚本控制、世界坐标与回滚，并复用 Session/暂停媒体门验证同帧交接、屏间完成与 stale Surface 拒绝。保启动报告的初始/后继两阶段，不因移 owner 丢弃诊断。补原始 root、event child、refraction、RopeTrail 和健康邻例的同输入旧/新 App 运行与正常退出。逐像素等价仅对时间、输入与呈现相位可冻结的结果声明；不因减少 owner 或一个 GPU 门宣称 FPS、能耗、全语料及官方 parity。验收后按粒子实例与 GPU 能力族独立提交，其他准备数据与组件职责按唯一队列继续。

### Puppet 姿态、实例与 GPU 几何的所有权

本族完整迁移 image Puppet 与 direct model animation，不以移动文件或增加转发层结算。现有 State 混持 pose/physics、Metal buffers、clipping 和提交状态，GPU encode 又调用 CPU prepare；View 保存每屏 CPU 字典及动态成员，动态出生现场编译 clipping PSO、读取 paint。目标是 Surface 拥有 CPU 实例，既有 MeshGeometry 拥有 GPU 几何，普通 encode 只消费冻结结果，准备期共享 PSO/paint，保持旧可见能力与局部失败。

Surface 唯一保存 Puppet PlaybackState、动态 topology revision/成员及骨骼脚本阶段状态。原骨骼 pose/physics、VM 发布和坐标计算迁到 Surface 的实际实现，直接借现有 renderer 的 world/camera 查询，不保 View ABI 转发或第二时钟。LaunchContext 的 animation playback runtime 仍是唯一 clock/command/event owner。提交后的拓扑在下一 cadence 先同步成员，再采样 clock、准备 pre-script pose、执行 VM、应用骨骼写入、完成 skinning/attachments，最后连同原 SimulationFrame 冻结。暂停、无 drawable 与 GPU 重试只消费该帧，不重算 pose 或 physics。

State 保 evaluator/selection、骨骼修改与物理、矩阵/position/coverage scratch、完整顶点输出和签名；退出 Metal import、设备、PSO、texture、buffer、stream、clipping、FIFO 及 command qualification。RenderFrame 是 revision 与 image/direct 顶点及必要状态的值，不是另一个持久 registry；Surface 冻结时取得值，CPU 后续写入遵循数组值语义。image 的完整 vertex 输出只有一份，失败前的部分 position/coverage 不覆盖它；direct 保不可变 bind 与 deform scratch，失败选择完整 bind 并发布新 revision。冻结旧帧仍在消费时的数组 COW 属必要隔离，不主动复制整帧或另存 RenderFrame 镜像；重复 pose 签名不写顶点。GPU clipping/DEBUG 优先读取已上传 shared buffer，不为 ROI 长期保留 CPU 数组。

既有 ScenePuppetMeshGeometry 接管静态 image、动画 image 和 direct stream 的实际 GPU 工作并归 Rendering/Geometry；ScenePuppetClipping 同归该目录。静态保持单 buffer，动画保持原三槽/FIFO 与完成/取消合同，不为统一类型增加资源。FIFO 只记录上传 revision/槽位，退出完整 CPU 签名、bone revision 与 attachments 副本。GeometryProduct 在安装时产生一次，闭包只捕获 GPU owner；owner 不反持该 product 形成环。direct publication 复用原 vertex stream 的 transaction/lease 检查，不另造状态机。CPU prepare 退出 GPU 回调；同一冻结 revision 重复发布不能推进 CPU。

资源装配保持原 atlas 到达、Puppet 分配、geometry/缺 mesh fallback、诊断的作者顺序。View.loadImageLayers 在原 Puppet 分支同步调用不保存的 nonescaping preparation hook；Surface 真实装配 CPU/GPU、注册 shared clock，全部成功才安装，hook 只返回 GPU outcome。Surface 在资源装配前建立，窗口仍在准备完成后显示；不新增临时 atlas publication 或事后重扫/修报告。direct 在原图像加载后安装。PreparedPose 只保 CPU 准备事实，LayerLoad 的 Metal factory/Outcome 与 State 的 GPU factory 同批退役。

clipping PSO 在已有 PipelineRepository 按真实 clip demand 准备一次，帧和出生只读已准备结果，失败 nil 也不重复编译。已有 PreparedBaseImageResources 按准备集合（含 creation templates）读取共享只读 paint；不在 CPU PreparedPuppetResources 放 Metal，亦不建独立资源 owner。缺 paint 仍局部隐藏受影响目标；真实读取失败拒绝该 Puppet，不能误降成整幅 atlas quad。clipping 的 extent/MVP/ROI、mask union、嵌套/循环、domain/pin 与下一 ordinary draw mask reset 保持；pose revision 相同不意味着 mask 可跨 consumer 复用。

动态成员同步同时消费 destroyed authored IDs：退出对应 CPU/GPU references 及 shared clock 的 state/event/command，不在 screen 重建时复活；默认 creation template 与共享资产保留，单屏退出不重置其他屏 clock。只在既有 committed topology/cadence 边界执行，不能提前撤当前冻结帧。failed/bind-only 动态 ID 的成员记录保留，避免每帧重试。

验收复用准备、动画 clock、真实 GPU publication/clipping/pool、direct stream、physics 和真实 QuickJS bones/pose 门。新增冻结 A→CPU 准备 B→GPU 仍发布 A 的 vertices/coverage/ROI、重复 GPU 发布不推进 CPU、两 Surface 独立以及 authored destroy/clone 保持反例。旧源码形状断言退役，独立行为保留；嵌入 Swift fixture 只按完整载体抽出，避免测试文件超限。完成 Debug build，再用冻结旧 App 对原始多 clip、optional additive、physics 交互、健康邻例及动态出生/销毁作同输入新旧运行，核正常退出与 GPU drain。成本只按实际准备次数和可比较测量声明，不凭 owner 数量宣称 FPS、能耗、完整语料或官方 parity。完成后按 Puppet 完整族独立提交；其余组件与跨层依赖继续按整体退出条件核对，有限审计不预先限定剩余职责，不将独立兼容缺口扩成无限重构前置项。

### 材质格式与槽位事实的准备交接

资源需求准备、variant与帧绑定共用同一静态事实。当前Rendering的launch格式助手解析shader，Compilation再反向调用；既有ResourceDemandAnalysis已在single-flight/持久缓存形成formatSlots，不能为调整目录在Template/ShaderContract工厂提前重扫。原Catalog.Entry携带该准备结果，经TemplateAdmission/Stages与SourceMaterials原入口交给VariantCache；格式注解解释归现有ShaderSchema，Rendering解析助手和VariantCache中的重复扫描退出。格式无效与格式有效但reachability失败分别保留原局部失败，不把合法空集合当未准备。

CompiledVariant在已有provider分析中保存mixed-provider纯值、regular-named槽和按候选ordinal排列的声明purpose；graph-input事实的空集合也是最终准备结果。原reachability准备值在所有可达变体汇合后，同时形成inactive-but-reachable候选purpose共识，替换原sampler缓存值，不另加cache或owner。帧直接取得所属CompiledVariant，不为已准备事实再包单字段Selection；TextureSelection、TextureResolver和GraphSelection退出静态schema、mixed/named形状与候选purpose重推导。共识只供准备阶段的候选key选择，帧active-slot绑定不透传无用共识。GraphSelection仍按实际publication content调整用途，当前readiness、absent/pending、wrong-purpose、颜色/ABI、generation及GPU使用期检查留在原消费者。

Demand磁盘缓存继续使用已有formatSlots载荷，保持暖命中不扫描、损坏沿冷路径重建。节点相关槽事实按material/node在launch准备，不塞入缺节点身份的source-pure磁盘缓存，不以新增持久缓存取得本次收益。新旧准备事实、格式错误/合法空结果、活动/可达/不活动槽、改名、半透明named与同/跨层、三候选局部失败由现有Template/Finalizer/persistent-cache及presence/source-purpose/mixed-provider真实GPU门验证；随后Debug与隔离原包/健康邻例保实际结果和排空。结构退出与解析次数可直接说明，启动/CPU收益另测，不预报性能。

### 材质静态装配与当前帧输入

每个material的template、variants、静态uniform来源与ABI只有一个准备权威。当前frame input重复携template，VariantCache在memo前重比定义；PreparedAssembly与preparedUniformBindings已形成静态归属，assemblePrepared仍逐field再推host schema和静态ActiveUniformIdentity。目标是帧接口只传当前值、矩阵、纹理snapshot和输出用途，从所属准备产品读取定义；template/cache不再由任意帧调用者重新配对。跨模板错误须在实际绑定/构造入口拒绝或由类型关系消除，不能直接删guard而让错误组合可执行，也不新增token/摘要认证替代大比较。

静态uniform schema与ActiveUniformIdentity在既有PreparedAssembly工厂生成一次，完整数值binding计划归同一准备产物并保留真正求值消费者；复用原ResolvedUniform仅携当前bytes和dynamic的resolvedSource，静态field/声明/target/attachments从所属准备产物读取。Program的terminal replay和DEBUG诊断也读这份来源，不抹去其真实元数据需求。真实snapshot来源/值在Finalizer消费处检查一次，Assembly不再重复相同source配对与host schema推导，仍检查当前count/bytes等真正动态ABI关系。

无产品消费者的raw装配入口及仅服务旧源码形状的fixture同批退役；非法布局、UBO、slot、binding和render state在准备工厂保反例，wrong-source用真实snapshot→query/finalize验证。工厂一次形成完整产物，不为原多重非法输入的错误排序再建两阶段组装，不伪造Dynamic binding。旧字段/API和重复验证同批退出，复用现有Finalizer、Program derivation、纹理变换、alpha及真实GPU门，测实际生产finalize路径，不抄业务逻辑做微基准。

### Launch准备与帧资源消费分界

launch envelope的readiness/format/purpose及颜色准入由原VariantCache准备链执行，不能继续由Rendering的Launch/LaunchSelection/LaunchColor助手反向调用compiler内部选择。作者default与graph引用解释归现有ShaderSchema准备职责，envelope及候选归VariantCache的LaunchEnvelope，颜色可执行性归其ColorAnalysis；原helper及旧调用入口随迁移退出，不保留转发。当前帧仅按已准备计划和实际publication选择、检查与绑定，资源content/generation/extent、target/hazard和GPU使用期仍由原消费者裁决。纯Sampler/Uniform等结果值与schema算法另按真实消费者分开，不公开整套混合namespace。

现有Finalizer、SamplerDefault、SharedPresence、source-purpose、mixed-provider及terminal门覆盖局部失败、改名/等价和像素；Debug与代表App运行再确认实际prepare链。此批收回真实准入职责，不以词法边数归零或源码搬迁本身当能力、性能收益。

### Prepared身份与设备准备键

shader、prepared及render-state identity由既有PreparedAssembly生成一次。PassEncoder的warmup直接消费该准备事实，再附加实际device、attachment、sampleCount、writeMask和passRole形成设备键；binary archive消费相同静态身份，保其实际OS/驱动、设备与附件区分。退役raw frontend/state重复推导入口，不新增摘要认证或身份owner。MTLLibrary/PSO、archive装载和正负缓存仍在原PassEncoder设备准备阶段，不能因消除Compilation内部引用把真实Metal工作搬给compiler或放回普通帧。

复用warmup、PassEncoder、terminal replay、binary archive冷暖/损坏恢复门，验证同准备身份复用、不同附件/设备参数隔离和真实失败；只有完整prepare→frame encode证明后才关闭职责，缓存命中不代替GPU结果。

### 已准备执行能力的交接

执行能力的Token、Layer/Material能力和查找/claim寿命是准备结果及既有运行身份，编译构造另归Compilation；按实际需要分开声明与构造，原身份和唯一claim权威不变，不另建registry或发布协调器。RuntimeBridge只取其真正消费的资源demands，不保整份compiler RuntimeCatalog；GraphExecutor的编译cache诊断通过既有执行观测链取证，观测关闭不访问compiler cache。纯值与算法逐符号裁决，不因现有Rendering消费者扩大公共命名空间。

复用RuntimeBridge/GraphExecutor的prepared能力、stale claim、局部失败、观测关闭及正常提交/取消门，移除替代后的旧字段/API和无消费者的诊断入口。目标是缩窄数据、消除反向算法依赖，不能为一条依赖边制造额外wrapper或持久状态。

### Sprite与当前拓扑消费者

Sprite时间由Session现有clock在当前Surface执行阶段采样，各Surface共享同一cadence结果；只收集实际消费者ID，使用本次临时集合/字典，不增加持久镜像。现texture commands在commit时接纳并标记nextFrame，不能为合并采样提前应用；采样只移到原Surface loop前，前置VM snapshot仍保独立语义。销毁commit时退休动画runtime的活动layer状态；View实例/GPU输出在Surface下一次采用该committed topology时退休，暂停重绘旧冻结帧仍有其Sprite资源，不提前破坏已采纳画面。复用原simulationFrame.topologyRevision判定采用变化，不新增revision镜像或每帧retired guard。

重建View在原装配入口构造Sprite实例前消费现有committed成员，不能先重注册死实例再删；可复用源定义、健康peer和已提交GPU资源保原使用期。按真实source消费者裁决，不能仅按作者ID猜clone/粒子继承：当前动态image与粒子layer-image emitter的动画源限制仍保持，不借整理补隐含新能力。hidden仍live，销毁provider沿原live成员局部失效，不靠hidden guard遮住旧工作。

MultiImage播放原completion回调持有正在执行的playback及其destination reservation，直到GPU完成；未提交沿原cancel/rollback退出。不新增retired manager、额外fence或第二释放账本。

相机及其他拓扑消费者从同一本次projection取得候选集合、顺序和world frame，不能从作者base descriptor选出已删除camera后直接退回默认。先以现有native-camera门验证two-camera删除/排序与相邻不应变化反例，再在原选择owner直接消费最小当前数据，不增状态树。Sprite出生/销毁、暂停/恢复、多Surface和当前camera选择均补真实实现门及隔离输出；未知官方组合先登记资格，不假定所有未测族有错。

### Timeline活动轨道的退出

隐藏可以仍有clock/脚本消费者，销毁则须在原committed拓扑变化边界退休已无消费者的活动轨道。保Program及C named catalog的稳定索引，原Timeline runtime一次整理live bindings、state indices/members和owner映射，幸存state保持原anchor；不重建整个runtime重置peer，不增加每帧retired检查或镜像registry。以写入target及实际playbackOwner关系裁决，不按发命令的Script owner一并删别层轨道；Combined共享state及全局camera origin/zoom分别按真实来源处理。

同一cadence已接纳的动画命令阶段保留，退休在原commit/finalize后只随拓扑变化执行；pending next-frame观察只保幸存target。复用真实Timeline和QuickJS named-animation门，验证Combined、活peer精确时间、hidden继续、旧handle stale、跨owner事件控制、play/destroy顺序及camera两lane。没有现成Timeline事件序列时不顺便新建事件系统，销毁后少求值不等于已测CPU收益。

### Shader编译结果与可选持久缓存

成功编译的typed产物由原compiler直接交付给现有artifact owner；持久cache只加速后续读取，不是本次成功结果的运输通道或播放前提。保原single-flight、key/ABI及不可信编译输出的必要边界，退出“必须创建持久目录→成功写文件→再读回才有Program”的链。临时compiler workspace仍服务实际隔离与编译需要，不用另一个临时cache模拟可写持久目录，也不新增常驻cache/fallback状态机。

持久目录不可创建/不可写时沿正常编译工作并采用结果，可选发布不阻塞采用；cache损坏/过期仍作miss，真实编译失败保持typed局部失败，不能伪造成功或用缓存错误覆盖compiler错误。先以现有artifact recovery门及真实编译对照正常、cache路径为文件/不可写、临时workspace可用、坏cache和真正编译失败；再核相同shader的Program/实际输出、正常退出及当前结果复用。缓存wire如需变化，旧可选条目miss重建，不造迁移许可。

### localStorage的准备输入与帧事务

同一storage Session在已有prepareLaunch后台完成有界文件读取、解码与入口验证；普通帧begin transaction只消费准备内存，不首次同步打开/解析持久JSON。没有实际VM实例的场景沿原实例需求处理，不以脚本源码形状猜测storage使用。保现有PersistenceCoordinator合并后台写入、激活时与前任最新envelope合并及原事务接纳/撤回；不新增worker、storage镜像或为每帧认证磁盘版本。

复用storage transaction和String lifecycle门，覆盖首次cadence无文件读取、坏/未来envelope只影响storage、候选准备后前任继续写而激活不丢最新值、取消/退出和两实例隔离。frame和准备使用同一owner，不能通过新建空Session跳过持久状态或从主线程延迟到第一次实际get来掩盖错位I/O。

### 现役证据阅读与固定历史

运行证据入口按组件职责索引有界结果，不把固定实验全文、旧App身份和流水账当当前HEAD状态。原页600行正文仍约225KB，首读百余巨长表格行妨碍定位；本轮在既有architecture/capabilities/development/roadmap/history分类内，将固定正文移一份history，当前页保短职责入口、证据深度与未验边界，不重写其他历史、能力合同或新建治理工具。

迁移以完成Puppet提交的原页Git blob与完整字节SHA为源；全部旧anchor保可达，已有兼容跳转不改。capabilities→history只转换必要相对链接，登记原文/保留正文两个不同SHA及可逆转换清单，不冒充字节相同移动；沿现有archive schema保存源版本、正文边界与永久锚点。当前正文预算同步收紧，保原600行/150行硬限，现有任务路由只补自然查询关键词，不新增执行owner。验证原链接目标、全部旧URL、原失败/STOP载荷及现有文档门；不以整理文档补写新的运行、性能或兼容结论。

## 职责与数据流

```text
authored data → prepared Program/graph/resources → typed frame update
              → Metal encode → unique compositor/output
```

具体阶段、对象生命周期与编码落点由[运行架构](../architecture/runtime-architecture.md#8-scene-播放生命周期与落代码合同)维护，实际接线查[代码地图](../architecture/runtime-as-built-map.md)。本设计不复制另一份对象表。

- App 保存选择与属性意图；既有播放控制边界统一切换 epoch 和有效暂停状态；adapter 保存执行事实，UI 消费投影。Video/Web 保留各自系统媒体与窗口生命周期。
- Scene client 传递可重放意图、请求/修订及显示配置；VM、frame、纹理和 GPU 由现役 daemon/session 持有，不跨 IPC 重建第二份。
- identity、clock、graph、资源生命周期与最终输出各有唯一权威。Shared 提供可复用值、视图与注入接口，具体服务由 App 装配。
- 切换目标为 request→prepare candidate→可呈现确认→commit active→retire previous；失败/取消保留旧安全画面。多 surface、部分 GPU 提交和迟到结果遵循原事务，不能伪造整体回滚。

## 优化边界

下表是可选择的职责面，不规定执行先后；每批比较实际热点、覆盖收益、风险与可验证性，只选一个完整结果。

| 职责 | 优先减少的工作 | 必须保持 |
|---|---|---|
| CPU/VM/帧准备 | 重复解析、投影、序列化、字典/数组复制、分配、锁与桥接 | 静态事实在生成/失效边界准备；当帧 live identity、fresh JS 引用、getter/setter、副作用与事件仍有效；不跨 command buffer 缓存完整帧 Program |
| 资源/启动 | 压缩纹理展开、重复解码/上传/编译、逐资源等待及无消费者预热 | purpose、mip、颜色、lease、completion 和取消发布；以首帧依赖缩小提前准备，失败局部回退 |
| GPU 合成 | 多余 copy/capture、store/load、pass 切换及实际最贵 shader 工作 | 作者顺序、背景读取、HDR/SDR、history/copy/swap、最后 store 和唯一 compositor；不全局降精度或减少内容 |
| 内存/退场 | 重复驻留、无界 cache、多 surface/候选叠加峰值 | 聚合既有 owner 预算；in-flight/history/provider 在安全点释放；allocator 驻留与泄漏分别判断 |
| 调度/能耗 | 无效 attempt、重复唤醒及无消费者采样/解码 | 唯一时钟与提交权；completion 不递归 render；不能因 GPU 忙跳过原本应消费的作者事件/VM；静态按需须证明动态依赖与 invalidation 完整 |
| 属性编辑 | 主线程重复准备、控件重建、通知风暴和可避免整景重建 | 复用现解析、控件、store 与 typed value/resource/variant/graph 更新；真实拓扑变化仍重建，跨 surface 与 clock 保持一致 |
| 工程反馈 | 重复 harness 编译、失效源码形状断言、重复文档和证据整理 | 保留独立行为与安全反例；同一事实一个权威，验证按影响面升级 |

<a id="apple-silicon"></a>

Apple Silicon 的平台、语言和依赖政策由[技术栈合同](../../architecture/technology-stack-boundaries.md)维护。原生 BC、附件寿命、shader 精度、GPU 几何、显示节奏及系统媒体转换均按上表热点条件选择；新 Metal API、memoryless/aliasing、DisplayLink、PSO archive 或 GPU simulation 不作为必做迁移。采用前须核实基线设备能力、总成本及安全退出，不新增第二执行链。

## 设计、失败与验收

重要能力或 owner/identity/lifecycle 变化先修订所属专题设计，再实施；普通局部修复直接推进。设计说明完整数据流、替代方案、失败半径、取消/退出和最近正反例，沿[仓库工作流](../../development/repository-workflow.md#设计判定与记录)登记，不为每个 helper 新建任务书。

资源越界、stale handle 和错误代次拒绝最小不安全单元；普通视觉失败局部降级，保留合法 previous/current 与不受影响内容。不按样本、路径、哈希或源码形状选择视觉算法，不复制参考实现；参考阅读与独立实现遵循[研究工作流](../development/official-client-behavior-research-workflow.md)。

验证复用[工作流的风险分级](../../development/repository-workflow.md#并行与验证)。先用最近门和短实验筛选，短实验不作性能验收；目标收益成立后执行工作卡规定的同条件多轮比较、变体/相邻反例、独立真实样本和一次最终独审。正确性或生命周期退化立即纠偏；连续两次有区分力实验仍无收益，停止重复同一候选，回到根因与设计。已证真实能力缺口按[路线](scene-compatibility-roadmap.md)优先补齐，不能仅因候选失败就退回覆盖小项。

同源码/工具/配置/输入身份的构建与有效证据复用；修订只重验受影响部分。共享合同、高风险生命周期或发布结论才扩大门，不能省掉实际变化需要的验收。测量期间避免构建/测试/profiler争用，诊断与普通播放分开；性能阈值与噪声规则在比较前冻结，失败后不放宽。

关闭一个切片须有用户结果、旧职责退出、成本影响与未覆盖边界；宣称性能收益时须有同条件可比较测量。结构调整可说明实际移除的重复工作及未测收益，不强行新增性能实验。构建、测试、提交或代码数量不计性能收益；局部计时、整体 CPU、GPU、内存、启动与能耗分别报告。最低设备、多屏、长稳、恢复和正式发行验收按声明范围执行，不作为每个局部修改的重复前置门。

依赖图只保留公共能力关系，不再复制过时等级、旧路线或未来完成门；其原状态摘录固定归档。旧专项内仍有效的设计保留，已经裁决或被稳定合同接管的阶段叙述明确标为历史，不继续阻塞当前开发。

本次文档归整退役两条仅锁定旧措辞的断言：Skill 是否允许写入由当前用户授权决定，不能靠特定中英文短语判断；冷热阅读边界由现有 query 的 firstRead 范围和角色路由检查保证，不再要求导航保留旧句子。保留实际文档角色、查询范围、链接、归档身份与设计登记验证，不调整这些门的失败标准。

## 历史与追溯

早期候选查[调查线索](../architecture/refactor-baseline.md)，使用前须核对当前调用与成本。

<a id="5-可直接交接的执行卡"></a> [归档记录](../history/engine-refactor-program-through-2026-10-14.md#5-可直接交接的执行卡) <!-- archive-redirect -->

[截至 2026-10-14 的 E/AS 档案](../history/engine-refactor-program-through-2026-10-14.md)保留原实验、失败和未闭合事项；[更早工程记录](../history/engine-refactor-program-before-2026-09-15.md)保留 completion 唤醒失败、validation memo 撤回等约束。它们只供对应职责按需追溯，不能用历史数字判断当前瓶颈。当前能力归[能力台账](../capabilities/coverage-ledger.md)，实际结果归[证据索引](../capabilities/runtime-evidence-current.md)及其历史链接。
