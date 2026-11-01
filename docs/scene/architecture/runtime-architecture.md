# Scene 兼容运行时架构

<!-- document-role: stable-contract -->

本文件是 Scene 的唯一顶层设计，规定完整播放链、数据所有权、组件协作、生命周期和代码职责。具体组件语义归[组件与系统职责](../capabilities/runtime-systems-reference.md)，语言与依赖归[技术栈合同](../../architecture/technology-stack-boundaries.md)，实际代码接线归[事实地图](runtime-as-built-map.md)，支持范围与运行结果归[能力台账](../capabilities/coverage-ledger.md)及[证据索引](../capabilities/runtime-evidence-current.md)。目标不等于已经实现。

## 1. 产品目标

在 macOS 26 及以上的 Apple Silicon 上，原生执行 Wallpaper Engine Scene 的作者可观察行为，持续改善画面、交互、响应和能耗。兼容承诺绑定参考版本、输入及结果；打开文件、识别字段或构建成功不能代表完整兼容。

顶层采用 Swift 管理产品和场景状态、Metal 执行图形、真实 ECMAScript VM 执行脚本、通用编译工具处理作者 Shader。当前合理的独立 Scene daemon、QuickJS-NG、glslang/SPIRV-Cross 与单一 Metal 输出继续演进，不因独立通用提案而重新建设另一套底座。Swift language mode 与发行平台以构建配置和技术栈合同为准。

```text
主 App：用户意图、属性、显示配置、共享系统采集
    ↓ coarse request / control / input
Scene daemon / Host：请求 → 准备候选 → 首帧可呈现 → 激活 → 退役旧会话
    ↓
作者文件与资源 → 解码与资源解析 → prepared Program / graph / resources
    ↓
Session：typed 输入 → 时间轴 / VM / 模拟 → 当帧状态
    ↓
每表面：资源与参数 → Metal encode → 图层合成 → 场景后处理 → 唯一最终输出
```

### 1.1 一个产品主干，多个通用语义执行器

| 唯一权威 | 可独立发展的执行职责 |
|---|---|
| 作者身份、顺序与层级 | 图像、文本、模型、Puppet 与粒子专属数据 |
| 场景时钟、输入提交及属性状态 | Timeline、真实 VM、模拟与事件 |
| 资源身份、来源、发布及使用期 | 解码、上传、文字排版、媒体 provider |
| Program、图依赖、target、history 与完成许可 | 材质、计算、几何和各种渲染 Pass |
| 活动会话与最终输出决策 | 每表面输出、预览和按需诊断 |

通用主干不要求一个巨大类、一个 Draw Call 或通用 ECS 框架。采用轻量节点、类型化状态、明确的更新计划与渲染依赖；新增组件主要增加自身的数据和执行逻辑，必要跨层接线只传最小数据。名称用于选择作者声明的通用组件/API，样本、路径、hash 或截图不能选择视觉算法。

## 2. 证据来源及其边界

公开作者合同说明输入与可见 API；固定官方结果说明相应版本和输入的行为；静态研究只补充有界结构；作者语料说明实际声明形状；第三方研究提供结构参照。公式、像素与完整时序不能仅从名称或静态邻域推导。[来源分类](../development/source-index.md)与[研究工作流](../development/official-client-behavior-research-workflow.md)统一维护证据方法。

### 2.1 目标合同、当前事实与偏差债务

| 问题 | 所属权威 |
|---|---|
| 最终如何工作 | 本文件、组件职责及对应专项设计 |
| 当前接线与能力 | 当前源码、事实地图、能力台账 |
| 实际跑过什么 | 对应输入身份与运行证据 |
| 先改什么、旧 owner 何时退出 | 兼容路线与其唯一开放队列 |

已有实现、测试和准入形状不能反向定义永久目标。设计保留必要的解析、身份、内存及 GPU 使用期完整性；重复校验、无消费者状态、为未知情形预先建设的框架和局部视觉失败的扩大拦截应当退役。

## 3. 基于上述证据的 MyWallpaperX 处理策略

### 3.0 最短播放链与复杂度预算

准备发生在加载、资源变化或结构变化的实际边界。普通帧只消费 prepared 数据、更新活动状态和编码指令，不重读 JSON、重新编译、整图建图、序列化、哈希或构造完整诊断。

外部数据在实际入口检查一次。内部消费完整类型；当帧 publication、资源修订、异步请求与 GPU 使用期在真正变化的边界确认。检查只拒绝受影响的最小单元，不能用一个缓存错误封锁整库播放。

<a id="audio-packed-source-view"></a>
音频 Shader 源码适配属于既有 normalization 与 HostUniformSchema，宿主频谱 ABI 保持一个权威。向量读取和数组布局以对应[Shader 合同](../capabilities/shader-prelude-and-backend-abstraction.md)及能力表的真实覆盖为准；不另造音频资源、逐帧源码识别或第二种缓存身份。

### 3.1 数据选择数据，执行器解释数据

作者文件定位资源、材质、组件和脚本；通用执行器解释其语义。按效果资源名选择一段内建视觉算法、扫描脚本写法决定同一 API 是否可用、凭截图识别样本，均不属于通用执行。

作者 IR 保留缺席、原始顺序和来源；准备产物持有已解析类型、索引、引用和执行需求；运行状态只保存当前值。属性系统写入实际类型状态，不维护与其逐帧同步的完整万能字典。GPU 参数是消费产物，不成为第二个可写状态权威。

### 3.2 尽量执行，局部降级

合法作者内容默认获得通用编译与执行尝试。有界实现的已证支持范围由专项表描述，不要求为每个未见组合先登记 profile 或认证才允许开发。

普通 Shader、特效、文本、媒体或粒子失败按实际消费者局部降级，保留安全 previous/current 与健康内容。无效路径、越界、错误身份、释放错误或 GPU hazard 拒绝最小不安全单元。不能伪造资源、binding、history 或显示成功。

可选失败是否使用作者初值、最近有效值或原输入，要由对应语义明确决定。颜色输入失败与数据输入错误具有不同影响，不能仅按“发生在材质模块”统一拒绝整帧。

现有[alpha 失败策略](../capabilities/alpha-display-fallback-design.md)与[仅绘制降级](../capabilities/static-source-draw-only-degradation.md)承接具体消费边界，不能将局部视觉失败升级为播放许可。

### 3.3 保留事务安全，不扩大视觉失败半径

共享模拟与每屏 GPU 提交有不同提交边界。已执行的 JS heap、副作用或其他屏幕已提交 GPU 工作不能假装回滚。取消只回收本次尚未提交的资源，GPU 已使用资源等真正完成。

保留真实保护 target、history、publication 和 completion 的现有 owner。迁移必须移交权威并撤掉旧入口，不能长期静默双执行或让诊断成为提交许可。

### 3.4 通用执行不等于单体 renderer

| 产品类别 | 输出内容 | 接入方式 |
|---|---|---|
| TextureProduct | 图片、文字、视频与栅格结果 | typed 纹理、采样和颜色信息 |
| GeometryProduct | Puppet、模型及其他几何 | mesh、材质、变形与 canonical world frame |
| SimulationProduct | 粒子或物理状态 | 类型化模拟结果与绘制数据 |
| ProviderProduct | 异步或动态资源 | 稳定资源身份、版本、就绪和发布 |
| GraphProduct | Pass、依赖、目标与历史 | 统一图执行及最终合成 |

这是职责分类，不要求新增对应 enum、协议、wrapper 或 registry。相机、灯光、Timeline、脚本、用户属性、输入与声音按组件合同接入，不全部伪装成可见纹理。

<a id="effect-texture-reduction"></a>
特效工作尺寸与纹理降采样分别表达，精确合同归[采样与工作尺寸](../capabilities/sampler-alias-precedence.md#effect-texture-reduction)。

<a id="ordinary-effect-lighting-host"></a>
图像光照的同帧材质输入和几何接线归[既有光照 owner](../roadmap/batch2/2d-lighting-material-design.md#ordinary-effect-lighting-host)。

<a id="static-model-resource-admission"></a>
模型读取、数量与工作预算归[资源合同](scene-resource-admission.md#static-model-resource-admission)。

<a id="model-effectful-named-output"></a>
模型消费隐藏特效输出归[原几何与图依赖合同](../capabilities/direct-model-bind-geometry.md#model-effectful-named-output)。这些专项必须复用身份、相机、资源、图和 compositor；当前 slot 或格式范围不构成未来所有组件的永久架构边界。

### 3.5 启动是候选事务，不是全量兼容门

主 App 传递意图，Host 管 newer-wins 与激活，Session 持有实际场景。当前内容的必需输入和首帧结果就绪后才替换 active；取消、失败和过期保留当前有效画面。

只准备实际需要的资源、变体和输出。未使用的目录、可选缓存和未来可能的输入不增加首帧等待。可选缓存缺失或损坏沿原读取链重建，暖命中不重做冷路径全文工作，缓存写入不阻塞激活。[启动合同](scene-launch-responsiveness-contract.md)维护具体阶段和进度，[变体缓存合同](variant-analysis-cache-contract.md)维护产物格式。

## 4. 目标执行单元

Swift 负责内容、prepared 数据、状态和生命周期；通用编译器负责 Shader 语言；真实 VM 负责 ECMAScript；Metal 负责 GPU。C/C++ 边界传源码、选项、字节、反射和必要 handle，普通帧不跨 ABI 遍历编译器 AST。

### 4.1 作者 shader 的推荐后端

保留 GLSL-like normalization → glslang → SPIR-V → SPIRV-Cross → MSL 的单一正式方向。其他编译器只在有区分力的失败证据后评估，不并行建设多套常驻后端。自有固定 MSL 构建期编译，作者变体在准备阶段编译及预热。

宏、include、注解默认、可选纹理、稀疏槽、反射与渲染状态共同形成完整 Program。Pipeline 缓存不允许遗漏真正影响结果的字段，也不把逐帧当前值放入静态变体身份。

<a id="malformed-combo-record"></a>
错误元数据只影响其实际解析与消费范围，细节由[Shader 元数据失败合同](shader-metadata-failure-contract.md)维护。geometry 等额外阶段单独验证映射与调度；转换库能读取某种阶段不等于 MSL 后端已执行它。

<a id="authored-texture-companion"></a>
### 作者采样与公开纹理 companion

作者 Shader 的坐标、sampler 和显式 LOD 保持作者语义；宿主和 compiler 不能重复注入 atlas/padding 变换。基础图像、effect 输出和 sprite 帧分别按同一采样权威准备。

公开纹理 companion 与 Resolution 共用 HostUniformSchema 和原槽位身份，由当前资源生产 typed 值。具体名称、类型、sprite/non-sprite、缺纹理 Resolution 及当前有界策略只由[采样合同](../capabilities/sampler-alias-precedence.md#authored-texture-companion)维护。工件迁移与原始运行结果归其历史记录，不在顶层复制。

### 4.2 SceneScript 的推荐 VM

保留 QuickJS-NG 的真实语言执行及 C host bridge，按现有 domain、owner、模块、事件与中断生命周期演进。JavaScriptCore/V8 是有明确缺口时的选型对照，不能因重整文档擅自更换已工作的 VM。

脚本按属性绑定，保留源码、owner、target、作者初值及值类型。按实际导出事件调度，只有 update consumer 进入逐帧调用。模块、shared 与对象别名属于真实 VM heap，不能用宿主复制字典假装恢复。[API 与运行合同](../capabilities/scenescript-api-coverage.md)维护精确语义。

## 5. 纵向兼容执行

### 源材质入口（T1，有界合同）

图层基底和 effect 材质沿同一资源解析、Shader schema、参数与颜色合同进入主链。来源名称只定位作者资源。无源程序化图像明确表达生成语义，不为凑纹理产品伪造任意 source。[系统总表中的源材质范围](../capabilities/coverage-ledger.md#3-系统总表)记录当前支持范围。

### 5.1 普通 effect 快速通路

图层源绘制、effect 工作空间和最终合成分别准备。普通 effect 复用统一材质和图执行，不为每个名称创建 planner。只改变数值时更新参数；采样语义、相机和颜色不能因快速通路发生变化。

### 5.2 Effect graph 通路

条件在纳入相关结构前求值。保留 Pass ordinal、空槽、稀疏绑定、命令与目标身份。copy 是内容操作，swap 是逻辑映射变化，compose 是链的可见边界，不能都降为普通滤镜。

区分层级树、更新顺序和渲染依赖。同帧依赖明确前后关系；历史显式引用许可版本。clear 的创建、首次写入、每帧或显式调用含义分别定义。跨帧保留、独占和物理目标复用服从作者语义及实际存活期。[格式与图合同](../capabilities/scene-format-and-render-graph.md)维护详细输入。

### 5.3 动态行为通路

用户属性、Timeline 和 VM 修改同一类型化状态。静态与当前值分开，属性返回与直接赋值分别有效。动态创建从已注册资源和正确类型进入现有生命周期；首次需要的资源或结构在实际变化边界准备，不把文件读取和编译搬进普通帧。

动态变更的立即读回、首次 init/update、排序和销毁可见点必须明确。不能用“统一下一帧生效”替代尚未理解的行为；也不为获得更多动态能力再建一棵状态树。

### 文字宽度与栅格化

文本接收内容和样式，排版、字形及特效在内容变化时准备。CoreText 与可能的距离场实现根据字体与效果对照选择，不能仅凭参考客户端采用 MSDF 就重写现有方案。宽度、行数、锚点、padding、字距与输出尺寸分别保留，静态文字不每帧重新栅格化。

文本中可执行语言应收敛到同一个 VM 和 typed 属性入口；文字 producer 负责字符串到布局与图形，不拥有第二个脚本解释器。

### 5.4 Particle 通路

粒子定义准备为有序发射、初始化、操作、renderer、control point 与 child 计划。实例只保存活动数据、随机状态、局部时间和事件。预热执行真实模拟；不同时间步、子事件和碰撞顺序按对应语义验证。

GPU 迁移按公共数据与真实收益进行，不因 renderer 名称替换成不同视觉。CPU 模拟、几何生成与 GPU 驻留状态清楚分责，共用场景输入、材质和输出。

### 5.5 五类变化与最小失效域

| 变化 | 最小动作 |
|---|---|
| value-only | 修改对应状态与参数，不重载、重编或建图 |
| resource-generation | 准备与发布实际变化的资源和绑定 |
| program-variant | 准备受影响编译产物及 Pipeline |
| geometry-extent | 更新相关排版、几何、视口或目标 |
| topology | 更新受影响节点、任务、依赖与引用 |

<a id="frame-texture-snapshot-values"></a>
异步资源只在真实发布处确认请求与修订；同帧 value、资源发布和 topology 保持不同 typed channel。输入快照与 GPU 参数复用消费者需要的最小数据，不做整场景复制和每次同步调用的重复检查。

<a id="56-v4-是横切输入轨不是-v3-之后的整个平台"></a>

### 5.6 宿主输入与实时资源

音频、鼠标、媒体、文字和动态资源服务当前内容的实际消费者。共享系统音频只采集分析一次；事件快照与实时 getter 分别表达；媒体封面异步结果不能覆盖新歌曲。跨平台 API 不可用时准确说明范围。

视频纹理的准备、发布和退出由[材质视频合同](../capabilities/material-video-assets.md)维护，与声音 voice 和系统频谱分别管理。

<a id="57-v5-是独立-epics-集合"></a>

### 5.7 高级场景能力

Puppet、模型、光照、RGB、离线输出、颜色与恢复分别按真实依赖交付。未知模型或动画通道保留数据和身份，未解释的消费语义不能当 padding 丢弃后宣称兼容。屏保、锁屏和离线能力使用明确宿主，不能从桌面运行外推。

## 6. 三层完成门

### 6.1 `slice-visible`

真实输入经过当前执行器、GPU 或对应事件 consumer 到达可见结果，包含最小正反例和未覆盖范围。工具准备、字段识别和非黑不能替代该证据。

### 6.2 `owner-migration`

新 owner 接管对应职责，旧产品入口和无独立价值的实现耦合测试退役；剩余 fallback 有明确范围、原因和退出条件。只证明该职责迁移，不扩大为整个能力族完成。

### 6.3 `parity-release`

按承诺范围完成官方同输入对照、性能与持续运行，并在发布时核对依赖、arm64、签名及分发。发行门不倒灌成为每次普通开发的前置流程。[开发工作流](../development/development-workflow.md)选择最近必要验证。

## 7. 迁移终态

每种组件拥有明确数据、更新、GPU 接入和释放 owner。合法新组合通过共享 primitive 自动受益；无消费者旧路径、逐样本视觉算法、平行状态、时钟、图或输出撤权。

目录按实际职责演进。现有 Format、Compilation、Resources、Systems、Rendering、Runtime 分工保留；具体源码落点由组件职责和事实地图维护。不要把职责拆分变成纯搬文件或层层 facade。

## 8. Scene 播放生命周期与落代码合同

### 8.1 六个阶段：何时可以做什么

| 阶段 | 必要工作 | 结束条件 |
|---|---|---|
| 接受请求 | 捕获源、属性、显示意图和请求身份 | 请求进入唯一 Host |
| 解码 | 版本化读取、资源定位和类型确定 | 来源及必要定义完整 |
| 准备 | 绑定、Program、更新与渲染计划、资源需求 | 当前结果所需产物可用 |
| 激活 | 建立会话和输出，验证候选首帧 | 真实可呈现后替换 active |
| 运行 | 输入、状态更新、编码、发布与完成 | 每次工作有明确 owner |
| 退役 | 撤销新工作、停止来源、等待在用资源 | GPU 与后台使用期真正结束 |

“加载完成”区分文档、计划、资源、上传、发布、消费和呈现。只有真实依赖影响当前候选，未使用的可选内容不形成全场景阻塞。

### 8.2 所有输入／产品的生命周期矩阵

组件的完整“输入 → prepared → 运行 → 编码或发布 → 释放”矩阵统一在[组件与系统职责](../capabilities/runtime-systems-reference.md)。本文件只规定跨组件共同约束，避免每个组件在多个地方维护生命周期。

| 共同状态 | 归属与约束 |
|---|---|
| 作者定义与不可变准备结果 | 内容/编译职责；来源变化时替换，不被普通 setter 修改 |
| 场景当前状态 | Session 及其类型 owner；屏幕失败不重放已消费模拟 |
| 必要的每屏 CPU 状态 | Session 按 surface identity 组织指针、视口及屏幕存储相关实例；只有语义允许的模拟才共享，View 负责消费 |
| 每表面 GPU 状态 | 原 Rendering owner；targets/history 与实际输出相绑定 |
| 不可变共享资源 | Resources 的缓存与引用；同 device/purpose 的真实可共享内容 |
| 外部输入 | 唯一平台服务生产，按消费者需求订阅 |
| 诊断 | 观察同一执行出口，按需启用，不能授予输出权 |

<a id="timeline-frame-input-observation"></a>
时间、属性与媒体的观察只能引用实际 FrameContext、Program 和输出。诊断阶段命中不代表对应属性已经影响真实绘制。

### 8.3 一帧的有序工作与可见时间

| 阶段 | 共同约束 |
|---|---|
| 确定 cadence | 每 cadence 的共享状态只推进一次，内部按语义允许模拟子步；暂停和零步长重绘不重复事件 |
| 冻结输入 | 单一播放时间与当前属性，保留每屏坐标、来源时间和资源版本 |
| 求值与回调 | Timeline、事件、timer、VM 的可观察顺序由语义合同决定 |
| 提交运行状态 | local setter、world snapshot、pose、附件与可见性使用明确阶段 |
| 准备当前消费 | 采用就绪资源、租赁目标、更新参数，不重新解析作者定义 |
| 编码 | producer 在 consumer 前完成同帧编码，按作者层序合成 |
| 每屏提交 | 每屏资源独立接纳；共享模拟与视频发布只确认一次 |
| 完成与回收 | 完成信息匹配原提交，释放对应 pins，真实 presented 才通知 |

同 command buffer 中的有序 GPU 工作不要求 CPU 等完成；跨队列或提交使用明确同步。GPU deferred 或丢帧不重新执行已消费的输入、VM heap 和声音事件。

### 8.4 编码边界与新增能力写法

新增字段归格式与准备，参数归原属性和 Program，特效依赖归原图，脚本 API 归 VM bridge 与实际状态 owner，粒子操作归 prepared 计划与模拟，坐标归 canonical world/camera，资源来源归 resolver/provider，窗口和显示归宿主。

这是职责边界，不要求把所有专属 parser 搬进 Format。粒子或文本等格式可以在类型族原 owner 内读取与准备，再交付 typed 数据；不要为目录形式增加一对一转发层。

<a id="源输出域与采样输入分离"></a>

跨层只传实际需要的 typed 数据。源采样、effect 工作尺寸和 world placement 各有含义；纹理大小不能替代图层尺寸，atlas 不能冒充已组合几何。缺口在真实所有者修正，避免各消费者各补一套转换。

准备新能力时说明作者结果、数据/执行/释放 owner、最小失效域和替换入口即可。已有合同内的局部修复不需要另建任务书、registry 或完整审计平台。

### 8.5 线程、所有权与释放

当前 daemon 主线程负责帧驱动和 adopt 后的 VM；AppKit surface 遵守主线程要求。解码、文字、编译和媒体任务只交付完整结果或明确的有界输入。迁移执行域需要接管实际可变状态、VM affinity、输入及退出，不能仅把 draw 放到后台。

停止顺序是撤销新工作与发布资格，取消未提交工作，停止 VM/来源/音源，等待后台实际使用和已提交 GPU 完成，再释放资源。窗口隐藏不等于 GPU 停止；缓存淘汰不释放尚在使用的资源。

暂停、作者停止与静音分别保留意图。恢复重新计算有效策略，不能无条件重启所有动画或声音。候选、active 和退役资源共同计入已有父预算；子池上限不成为另一份身份或释放权威。

### 8.6 当前差距与迁移入口

具体偏差通过当前源码复核后列入[唯一开放队列](../roadmap/scene-open-breakpoint-queue.md)，保留原 owner、目标职责、消费者及旧入口退出。代码事实由[事实地图](runtime-as-built-map.md)维护，不能在本节持续追加每轮的 profile、格式、slot 和完成记录。

本次顶层收敛的取舍见[重构设计](../roadmap/engine-refactor-program.md#顶层设计收敛决定)。归整前的完整限定与历史叙述保存在[固定快照](../history/runtime-architecture-through-2026-11-01.md)，只用于追溯；产品当前范围仍由专项能力和实际代码裁决。

<a id="terminal-material-raster"></a>
### 终端材质光栅的有界合同

终端回绘是原 GraphExecutor 内的可选优化，源尺寸采样、实际投影和最终合成保持独立；失败保留安全的 graph-final。具体目标像素证明、输入保留、颜色与 blend 条件由[终端材质链](../roadmap/batch2/terminal-material-chain-design.md#terminal-material-raster)唯一维护，不成为普通 Scene 组件的新执行许可。

<a id="debug-capture-lifecycle"></a>

### 诊断截图生命周期

截图只观察原提交，不拥有正常播放许可。请求、GPU readback、CPU 导出和会话退出各有实际完成边界，不能用 GPU drain 代替 PNG 导出完成。有限容量是可测量调整的诊断策略；数值、一次终结与资源释放由[诊断截图合同](gpu-stage-timestamp-diagnostics.md#debug-capture-lifecycle)维护。

<a id="architecture-before-convergence"></a> [归档记录](../history/runtime-architecture-through-2026-11-01.md#architecture-before-convergence) <!-- archive-redirect -->
