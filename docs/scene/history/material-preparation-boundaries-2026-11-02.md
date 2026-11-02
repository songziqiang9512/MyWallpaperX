# 材质准备边界整理后验

> **历史证据 — 非现役入口**

<!-- document-role: historical-evidence -->

> 2026-11-02 固定批次证据，不是整个 Scene 架构完成声明。现役目标归[迁移设计](../roadmap/engine-refactor-program.md)，未闭职责归[唯一队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)。

<a id="m1-format-slot-handoff"></a>
## M1 格式与槽位准备交接

Catalog 将原 Demand 分析及 v10 持久缓存的格式槽结果交给原 Variant 准备入口；合法空集合与格式失败、reachability 失败分别保留。CompiledVariant 在准备阶段形成 mixed/named、候选 purpose、default 和 graph-input 事实，普通帧不再解析格式或推导这些静态形状；当前 publication、颜色/ABI、generation 与 GPU 使用期检查仍由原消费者执行。无消费者的共识透传和单字段 Selection 退出。

19 个产品文件净增 77 行：新增代码承载实际跨阶段事实，替换 Rendering 的重复推导；未新增源文件、owner、cache 或持久 wire。38 个测试文件净增 159 行，包括新格式结果反例及真实 API 接线；不以增删行、依赖边数或构建结果宣称性能收益。

### 身份与范围

| 身份 | 固定值 |
|---|---|
| 迁移前源码 | `02dce22bf7862eb60bc83f5a4d4e47a1d3602237` |
| 本批产品 patch SHA-256 | `a740a6e5acf0f86a602024cb0cc593949ce1d25b8bc453d6c1099aafffbaeb50` |
| 迁移前签名 App SHA-256 | `7f53c0969eed829c679276c18dbc8ebe93140c5df7eae9bdd5f6f6a444883d56` |
| M1 签名 App SHA-256 | `40cca59a65ddb392e6aaf0366f6e7089bd48a27900326c68a8e809d6e36d5381` |
| 签名 / 构建 | Team `H9QWU9XN8R`；严格验签；arm64 Debug、`-O`；构建前后本批产品源码身份相同 |
| 本机证据 provenance | `.artifacts/scene-architecture-continuation-20261102/` 中的 M1 源码、命令、原始日志、报告和 PNG；可用性按产物规则，不作为现役文档依赖 |

### 实际验证

| 责任 | 结果与边界 |
|---|---|
| 格式与准备交接 | Template、Finalizer、persistent-cache、graph source purpose、scalar mask、SamplerDefault、SharedPresence 通过；覆盖合法空/格式错误、格式有效但 reachability 失败及健康单元保留 |
| 当前帧与合成 | prepared material output、terminal graph、OptionalNamed、PreparedBaseImage 及 GraphExecutor 六个用例均有通过记录；首轮三项测试接线错误修复后只重跑对应失败用例，原失败保留，不把首轮整组选集改写成 PASS |
| 真实 GPU | SharedPresence 保原 shader/backend 与 R100/B50 像素断言；修正载体后，迁移前源码与 M1 均通过 |
| 签名 App 固定像素 | 新旧 App 各运行半透明 named 与三候选局部失败两例；ready/after 的固定 ROI 保原 99% / tolerance 2 门槛，健康 peer、后续帧完成和 GPU drain 均通过 |
| 原包与独立邻例 | `3351163962`、`3589819394` 同输入新旧共四次通过，输入 hash 相同、退出 0、无超时并正常 drain；复核 after 图保文字、背景与对应可见内容。墙钟、粒子和动画相位未冻结，不宣称逐像素等价 |
| 实际暖复用 | M1 半透明例复用同一隔离 HOME/cache 再播放，固定 ROI、后续帧与退出通过；两份 Demand v10 条目的内容及 mtime 不变。结合原 load 先于 parser 的接线说明复用边界，不冒充 parser 调用计数或启动收益测量 |
| 结构与治理 | 结构、断言、产物、依赖、残留、代码健康、防御棘轮及设计门通过；原四条实际内部引用退出后库存 44→40，余下真实结构债未关闭 |

### 保留的首失败与纠正

- 原 Template 载体把 Windows 盘符样式误作越界；当前 VFS 将其规范为 root-relative token。修正正反输入，不向产品补路径拒绝；真实 escape 的资源入口边界保持。
- SharedPresence 原 uniform 全零，真实 bounded vertex wrapper 按 `vertex_id` 读坐标 uniform，四点因此重合。原源码同样失败；仅以生产 HostUniformSchema/UniformEncoder 编码 unit quad 修正载体，原 shader、后端、纹理、像素及容差未改。迁移前修正载体再次通过，产品未为黑图加 fallback。
- SamplerDefault 的 throwing Catalog 构造补完整 `try` 传播；PreparedBaseImage 夹具补显式 `return`；OptionalNamed 删除重复 source；GraphExecutor 两处改用真实 Variant 返回入口。未放宽行为、counter 或像素断言。

### 未覆盖与后续边界

材质帧 template 双来源、静态 uniform 装配、launch 选择、设备准备身份和执行能力交接继续按现役设计处理；本批不关闭它们。当前 App 证据经过 direct Host，不能代替普通 App→client→daemon 完整控制链。未认领整体 CPU/GPU、启动或能耗收益，也未证明完整语料、物理多屏、长稳、官方 parity 或正式 Release。


<a id="m2-prepared-uniform-frame"></a>
## M2 静态 uniform 计划与当前帧

FrameInput 退出独立 template；所属 Variant/PreparedAssembly 是定义、binding plan、layout 和静态 identity 的唯一来源。工厂一次形成 host/static/dynamic 归属及 ActiveUniformIdentity，帧只求当前动态 source/value 和编码 bytes；Program、terminal replay 与 DEBUG 诊断读取同一计划。原 raw assemble/compileFrontend 等无产品消费者入口及重复装配检查退出，真实 snapshot 来源、range/fallback、bytes、当前纹理 content/generation/extent/UV 和 GPU 使用期检查保留。

SourceMaterial 原 template 的 live property 消费者没有删除：准备时投影全部声明的 dynamic targets，包含暂不 active 的声明；Host 消费最小集合，不保整份模板或误用当前 active uniform 计划，也不把此集合当更早 QuickJS 构造条件。

16 个产品文件增 163、删 468 行，净减 305；38 个测试文件增 542、删 663，净减 121。未新增产品文件、owner、cache、wire 或新的认证阶段；增删行及静态推导退出不作为实测性能结论。

### 冻结身份

| 身份 | 固定值 |
|---|---|
| 产品基线 | `77139ae02b7daa2b2219da08f35c48a68123ce18` |
| M2 产品 patch SHA-256 | `0c410f1c68f7d3eef664cb800553bc91b257e8b126a3df3c0875e9d739877408` |
| 对照 App | M1 `40cca59a65ddb392e6aaf0366f6e7089bd48a27900326c68a8e809d6e36d5381` |
| 本批运行 App | `5e41db87ff8fb4a26bfdb4e52570fe9675caf2b82ee4c1dbf0c8c6140a96e5dd`，同时包含独立 Sprite/Timeline 批；不把联合身份伪称单批 App |
| 构建 / 签名 | arm64 Debug `-O`；Team `H9QWU9XN8R`；严格验签，联合产品 28 文件构建前后 hash 相同 |
| 本机 provenance | `.artifacts/scene-architecture-continuation-20261102/` 的 `material-frame-*`、M2 manifest 与版本化 source freeze；临时源码副本只用于串行验收，不是新产品路径 |

### 已执行边界

| 责任 | 结果与边界 |
|---|---|
| 准备与实际消费者 | hidden property、source prepared base-image、prepared uniform query、texture transform、previous composite、execution capability、PassEncoder、Program derivation 均通过；覆盖未 active 的声明和精确 target 身份 |
| Effect host/source 归属 | 修正载体后完整 11 例通过；source 的静态 default/gain 与 effect host 分别核真实 prepared plan 和精确 resolved bytes，声明冲突与类型反例保留 |
| Finalizer | 保当前 serial frame 的 source/fallback/range、动态 bytes、layout/resource 和恢复；修正旧多重非法输入优先级断言后对应 serial 用例通过，不为错误优先级恢复第二组装阶段 |
| 生产 Metal/Graph | GraphExecutor 六例及独立 signal/color 组合门通过，包含实际 graph 编码、PMA/straight、跨 effect、最新同层 named 和真实 fallback；不是仅 profile 命中 |
| 签名 App 固定像素 | 半透明 named 与三候选局部失败保持原固定 ROI、99% / tolerance 2 门槛、健康 peer、后续完成及 GPU drain |
| 原包与独立邻例 | `3351163962`、`3589819394` 同 M1 输入 snapshot 运行均退出 0、无超时并通过原门；复核 after 对照图保文字、背景、主体和光效。墙钟及动画相位不同，不宣称逐像素相同 |

### 首失败与纠正

- 首次完整 Debug 揭示 Host 仍读取 SourceMaterial 全部 uniform declarations。以准备 target 集合承接真实消费者并重建通过；不能凭显式类型名搜索无结果就判字段已无消费者。
- EffectDrawAlpha 的真实 loader 源闭包补回 ShaderSourceResolver。source alias 成功分支原错误地要求 effect host 归属；现从真实 PreparedAssembly 核 source 静态 default/gain，分别调用真实 resolver 比较精确 bytes，effect 仍核 host。真实声明冲突、类型、动态 source 与像素反例保留。
- Finalizer 的多重非法 layout/schema 与 sampler 组合原锁定失败优先级。改用各自单一失败反例保精确 code，当前帧、计数和有效 ABI 断言未放宽；原始失败日志保留。

结构门首次指出已退出的 raw frontend 调用仍登记在旧库存；按真实调用将该 inventory 由 2 收紧为 1，原迁移凭据不改，其余 Compilation→Rendering 债不据此关闭。

Launch 准备算法、device key 与执行能力交接继续开放，实际产品 daemon 完整链另验。未认领整体启动、CPU/GPU、能耗、全语料、物理多屏、长期稳定或官方 parity。


<a id="m3-launch-device-resource"></a>
## M3 Launch、设备身份与资源值交接

2026-11-03固定边界：Launch选择、mixed解析与颜色准入归原Schema/Variant准备owner，Rendering三个Launch文件退出。PreparedSampler交付准备事实，逻辑VFS/purpose identity与Candidate物理纹理、Uploader的GPU工作分开；purpose持久wire复用同一codec，未知非空token整record miss。资源identity文件仅依Foundation；Sampler仍复用既有FrontendModel的ChannelUse，不称为独立Foundation模块。

Warmup及binary archive直接消费PreparedAssembly既有shader/render-state identity，Rendering只附设备和附件事实，退出重复推导。此批不改变PSO设备准备owner，也不关闭当时的可选archive同步发布等待；后续整改按现役设计独立验证。

38个产品路径净减170行（含三个旧入口删除、两个值文件新增），没有新增owner或运行状态。79个测试路径净增200行，其中三个过长driver改为完整职责fixture；保真实输入/输出和编译边界，不以搬迁或增删行宣称性能提升。SourceSet共享named leaf按首次使用展开一次，真实循环和不同集合重复声明仍拒绝。

| 已执行边界 | 固定结果与限制 |
|---|---|
| SourceSet与准备 | 12个source-set反例、SamplerDefault、Template、ProgramFinalizer及SharedPresence通过；保合法空、未知purpose、资源来源/通道和失败邻例 |
| 设备准备与GPU | PassEncoder真实编译/encode、冷暖archive、格式隔离和损坏恢复通过；Terminal straight调用改用真实preparedAssembly，原断言保持 |
| 资源消费者 | FrameTextureRegistry、TextureCandidate及粒子Rendering最近门通过；不是只验证类型名或source list |
| 签名联合构建 | arm64 Debug `-O`构建通过，Team `H9QWU9XN8R`严格验签；App `98539ede73e5ab7aa14babd2e9805f28b085643492755feae22404f7a6a7d6a2`同时含独立Camera批，不能称为单独M3 App |
| 冻结范围 | 对应产品后像与构建保护源码核SHA，提交仅另规范一份产品文件的EOF空行，原后像和trivia差异清单保留；删除项从现役source/layout退出。构建记录保护45个Scene文件，不能改称全仓逐文件冻结 |
| 结构 | 11条直接内部边随真实职责退出，阶段基线40→29，public_contracts未扩；后续能力载体、活动消费者及全链验收仍归现役队列 |

首轮SourceSet重复展开共享leaf、Terminal straight旧调用及漏登layout均作为载体/接线失败保留，修原入口和注册，不为过门恢复旧产品转发。代码地图、组件合同与运行证据维护当前答案；本段不重写M1/M2当时未覆盖边界。

本机provenance位于`.artifacts/scene-architecture-continuation-20261102/`的`m3-*`、`resource-lookup-*`、`m3-commit-*`冻结清单及原始日志。该范围不证明完整语料、普通产品daemon全生命周期、物理多屏、长期稳定、官方parity或整体启动/CPU/GPU/能耗收益；后续联合版本回验另登记。
