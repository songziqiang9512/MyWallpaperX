<!-- document-role: active-plan -->

# Scene 兼容执行路线

> 当前主线：**全样本验收收口**。以完整作者内容盘点、公共能力修复和真实播放对照，逐步让样本根中的每一个 Scene 正确运行。
>
> 执行方案复核：2026-09-16。从 **P0 补齐全量关联与验收基线** 开始，再按公共首断点推进 P1–P4；已有实现和历史验收证据保留，不能因重新规划而归零或冒充当前复测。
>
> 本文只拥有阶段顺序和完成门。能力、owner、route、样本和运行结果分别由[能力台账](semantics/coverage-ledger.md)、专项表、[代码地图](design/runtime-as-built-map.md)、[运行证据索引](semantics/runtime-evidence-current.md)、[样本调试台账](semantics/scene-sample-debug-ledger.md)和[样本验收台账](semantics/scene-sample-acceptance-ledger.md)拥有。本文中的新增字段和工具扩展是待实现交付要求，不表示工具已经支持。

## 1. 不变的目标架构

```text
authored data → loss-preserving IR → prepared Program/graph/resources
              → typed frame update → Metal encode → unique compositor/output
```

遵循[播放器设计 §8](design/runtime-architecture.md#8-scene-播放生命周期与落代码合同)的五类产品与逐对象生命周期。Swift/AppKit 持有作者 identity/order、frame state、资源/target/publication/completion 与 Metal 调度；compiler、VM、粒子模拟、文字/媒体 provider 通过共享合同协作。通用不等于一个巨型 renderer，也不要求所有对象先变成平面纹理。

sample、layer、path、hash、截图与 census family key 只能定位证据，不能选择产品视觉算法。不得增加第二套 property、provider、clock、graph、resource registry、history 或 compositor。解析、编译、reflection、ABI/target preparation 和静态索引在 load、generation 或明确 invalidation 执行；普通帧只消费准备结果和 typed 更新，并保留必要安全检查。

本轮不先重写引擎，也不把现状当最终设计：全量关联图定位重复职责与缺口，每个公共修复在完整职责边界内纠偏，积累证据后修订同一目标架构。不得等到抄完所有函数或建好一个新平台才开始取得可见结果。

## 2. 验收标准

### 2.1 “所有作者内容”如何验收

验收全集来自真实样本根的冻结 manifest，不能用矩阵成员替代。读取 `project.json` 的真实入口、PKG 索引或 loose 文件，递归解析作者引用；不能假设每个项目都叫 `scene.pkg/scene.json`。

“全部执行”表示作者语义要求执行的内容在对应状态下正确执行，不是强行开启所有隐藏层或互斥分支。每项声明必须有可解释的去向：

- **运行内容**：对象、material/pass、shader variant、graph command、FBO/history、纹理/字体/模型、粒子及 child/control point、Puppet、相机/灯光/深度、脚本模块/API/事件、Timeline、property/condition、音视频和输入 provider。
- **条件内容**：默认关闭、隐藏 controller、事件激活、互斥 combo、动态创建/销毁等，必须有触发场景与可观测 consumer；默认画面不可见不等于无需执行。
- **非运行元数据或未引用资源**：记录语义依据与引用关系；不得因引擎未识别就归为无关。非法或损坏输入记录最小拒绝单元，并核对官方行为。
- **未知字段、动态引用或未执行分支**：保持 unknown/未覆盖，不能从保真、API 名存在或一次运行无报错推断支持。脚本可计算输入无法用静态扫描穷尽，需公开 API 合同、触发场景、运行观察与未见组合共同覆盖；无法证明的边界必须保留。

### 2.2 每个样本的关闭门

1. **正确显示**：普通 App → client → daemon → 异步 `requestLaunch` 路径的首帧、稳定帧和关键状态与参考一致。检查构图、方向、尺寸、裁切、层序、文字、颜色/alpha、遮罩、背景及缺失对象；禁止隐藏失败层、降分辨率或跳过 effect 换取通过。
2. **正确播放**：多帧截图/视频覆盖启动、循环、暂停/恢复和声明事件。动画、Timeline、脚本、粒子、Puppet、音频/媒体/鼠标在相应输入下有正确时序、结果和生命周期；静态截图不能证明动态内容执行。
3. **作者参数完整**：每个声明参数有 UI/schema 去向、默认值/范围/condition、typed snapshot、实际 consumer 和场景。修改前后有可见/可听或精确事件证据；group 等元数据验收真实 UI 职责，不伪造视觉 consumer。所有离散选项逐项验证；连续值覆盖边界、默认、内部代表值和敏感点；有依赖的参数组合额外覆盖。
4. **执行闭环**：同一身份贯穿 Program/VM/component → completion → publication → terminal compositor → next-frame。画面正确但作者单元被 fallback 替代仍保留缺口；局部失败保 previous-current 与无关输出，unsafe 单元按合同硬拒绝。
5. **官方一致性**：固定官方版本、内容、属性、viewport/scale、色彩、质量、时间/事件和输入，在预登记的 ROI、几何、序列、统计或 exact 状态门内一致。按[官方对照工作流 §8](semantics/official-client-behavior-research-workflow.md#8-官方结果一致性门)执行，不能在失败后放宽容差。

截图是必要验收物，每个关闭样本都有原分辨率对照、关键 ROI 和动态关键帧；自动指标辅助找差异，人工查看真实播放并确认。自动结果与人工裁决分栏，`script/scene_sample_acceptance_verdicts.json` 的 `pass/fail` 仍由实际观看者记录，agent 不能按 benchmark PASS 自动改 verdict。需人工复核时交付具体对照材料及待裁决项，不只请求抽象批准。

### 2.3 现成参考与最终真值

用户确认目前只有现成截图或视频。P0 登记其来源、内容版本、分辨率、已知属性/时间与缺失控制变量：用于定位缺块、位置、层序和可观察动态差异；作者预览、压缩视频与 Mirage 输出不能代替固定官方同输入对照。不能对齐的条目保留 `reference-uncontrolled`；这是拟加入证据层的标签，不是现有人工 verdict 新枚举。

官方环境的取得/提供者、固定版本与可重复采集方式是 **P4 官方一致性关闭的外部依赖**。先完成公共修复和已有参考复核；缺官方环境时继续独立工作，但官方对照保持 `blocked/not-run`，不能宣称官方同款完成。未来可用受控 Windows 环境或由操作者按协议返回带身份的采集包，不预设远程工具已存在。

`platform-unsupported` / `unsupported-by-contract`、缺素材、未覆盖条件或无官方 golden 都是边界，不是本目标通过项。可以交付已完成子集，不能减少分母达成“全部样本正确”。只有用户另行接受范围缩减，才记录新范围与未完成全集；当前不默认缩减。有限 corpus 通过也不外推所有未知 Workshop 内容、未来版本或任意脚本均兼容。

## 3. 阶段

### 3.1 总顺序与退出条件

| 阶段 | 必须交付的结果 | 关闭门 |
|---|---|---|
| **P0 盘点与关联基线（现在）** | 全量清单校验；声明→公共合同→代码 owner→场景→证据关联；普通启动采集校准；依赖与首断点排序 | 无漏样本/漏资源分类、守恒通过；每个声明有去向或 unknown，每个 family 有可复核 route/owner 或定位缺口；每样本有当前基线或明确运行阻塞，不能拿旧报告冒充 fresh |
| **P1 公共能力修复** | 逐个修复证实的最早公共失败，在原 owner 内完成纵向链及必要消融 | 切片正反门通过，受影响样本的该断点消失，后续断点准确迁移；不能仅清空旧 reasonCode |
| **P2 组合与逐样本剩余缺口** | 对仍错误的对象/组合逐 occurrence 追踪，纠正跨能力顺序、坐标、颜色、状态与 publication | 剩余可见/事件失败修复并回归；新公共缺口回 P1，同一问题只维护一个修复项 |
| **P3 参数与条件内容闭环** | 全部参数、事件、隐藏 controller、动态对象和条件分支的场景验收 | 场景清单无未说明 consumer、未覆盖声明或只结构级 target；动态输入逐族关闭，不能用默认截图代替 |
| **P4 全样本官方视觉复核** | 冻结候选构建，全集普通播放对照、人工裁决与官方 bounded profile 证据 | 全集显示/动态/参数通过，官方控制变量和容差门完整；失败回 P1/P2/P3，环境缺失则不关闭 |
| **P5 性能、长稳与发布** | 同画质性能/资源基线、生命周期压力与发布门 | 全部通过样本在声明设备/帧率档正常播放；切换/睡眠/显示变化/退出安全；相应签名和发布门通过 |

这是工作依赖顺序，不要求修完全部静态内容才碰动态能力。P1 每批携带对应 P2/P3 场景与官方参考，P4 是统一复核；紧急可见回归可提前处理。优化遵循[重构执行档案](engine-refactor-program.md)，性能测量从 P0/P1 开始，P5 不是首次测量时间。

### 3.2 P0 的四个有界批次

**P0.1 — 校准盘点，不重建另一份知识库。**

复用[全样本盘点](semantics/scene-corpus-capability-inventory.md)与 `script/scene_capability_census.py`。先校验 corpus、generator/schema、stock 依赖及 fingerprint；变化时才刷新快照。完整读取所有 project、包索引、入口和引用定义，对 loose/外部依赖、重复包项、路径逃逸、解压字节/数量/深度预算、引用环分别记录；必要解包只写隔离目录，不把作者 payload 写入 Git。

先只读 `verify` 判定漂移；`generate` 会写快照和 Markdown，确认 owned paths 后才执行。先区分 corpus/schema 变化与扫描器错误，不用重新生成消掉失败。新增自有 fixture 检查重复项、slot hole、unknown、缺引用和守恒；PKG 与非标准入口均有代表。

必达守恒：`discovered = parsed + failed`；物理项包含重复项；每个观察到的 JSON leaf/资源引用都有 typed 分类或 unknown；occurrence 无丢失和孤儿引用。JSON leaf 守恒不证明 shader/脚本内部执行完整。列出需人工定位的最小未知集合，不宣称 family 数就是能力总数。

**P0.2 — 为现有表补齐执行关系。**

以 `validation.occurrence_index.items` 为连接入口，用 domain/kind/语义 profile 去重。结构 family 可能过细，也可能混入不同颜色/状态语义；映射到稳定公共 `capability_id + contract_profile`，允许多对多且能反查声明。先按职责做全量粗映射，不能确定则记 unknown；进入修复/验收时才细化到首错函数，不手抄数万份相同调用链。

| 关系 | 必须记录 | 唯一落点/待扩展 owner |
|---|---|---|
| sample → occurrence/family/profile | fingerprint、物理/引用位置、作者顺序、可见/条件/动态入口、未知原因 | 既有 census snapshot 与生成 inventory；不存 shader/脚本正文 |
| capability profile → 实现 | 官方合同，parser/prepare/update/execute/publish/composite/teardown 文件及符号、代码 revision、route、typed fallback、失效域、旧 owner/退役门 | 能力专项表保存语义状态，`runtime-as-built-map.md` 保存共享链；occurrence 只引用 |
| sample + scenario + occurrence → evidence | 属性/事件/时间/输入、预期 consumer/ROI、执行 identity、first broken edge、completion/publication/next-frame、run/build/content identity、参考等级 | 扩展既有 debug archive/生成器；主动诊断数据不进入产品常驻路径 |
| shared defect → impact/sentinels | 根因合同、前后依赖、静态可能受益集合、运行证实失败集合、已复测恢复集合、正反/组合回归门 | 既有 repair ledger，当前工作项投影到派生队列 |
| sample → verdict | 观看者/时间、关联 run/scenario 集、截图/视频身份、剩余差异、官方对照状态 | 扩展既有 acceptance verdicts/生成器；保留历史裁决并显示时效 |

先写 schema/migration 和引用完整性门，再落工具。`repair_state` 是修复事件，S0–S5 是证据深度，人工 verdict 是用户结果，三者继续独立；不能从 `implemented/untriaged` 自动生成能力支持状态。旧 schema 可读，缺新字段则 unknown。

输出统计：公共 profile 数、覆盖样本数（去重）、声明数、未关联数、各阶段 first-break 数、受阻下游、实际复测恢复数、待视觉复核数。“结构共享”不能算成“修一个已让全部受益”。

**P0.3 — 校准采集后建立 fresh 基线。**

先用简单静态、多 pass/history、脚本/动态 provider 三类代表校准采集；成员写现有机器表，计划不固化样本。普通产品启动是验收入口，DEBUG benchmark 辅助定位；核对输入、route、viewport、时间/属性并标注启动路径。

优先复用 UI/client/daemon 控制与截图接口，缺批量入口才扩展现有 benchmark/归档工具：验收仍经普通 client → daemon，不建第二 Host/renderer。没有产品路径捕获能力时先交付它，再批量回放。`performance-only` 缺完整 execution observation，不能承担能力闭环证据。

tracked full matrix 扩为全集 identity-only 基线。历史期待先分成有效行为合同、过期实现期待和诊断值；有效行为门迁移到定向回归表，不能随扩容丢弃。身份门不充当视觉 pass。Fast Suite 用真实正反结果选定并登记；不适用候选显式退役，不能把 `selection-required` 当运行门。

首次全集顺序执行 GPU 任务，每波先取 10 个样本作为调度起点，按资源/时长调整。每样本保存身份、属性、首帧/稳定帧/动态关键帧及退出状态；超时、崩溃、缺权限明确登记，不阻塞下一样本。完整场景随后展开，不从一次默认运行外推完成。

时长由启动、循环及事件合同决定，不能统一短窗口跳过延迟行为。波次结束归档紧凑事实、保留唯一失败现场，清理精确登记的可重建隔离产物；恢复时只运行未完成或失效成员。

**P0.4 — 汇总公共依赖，形成首个修复批次。**

依赖图表达公共职责和真实消费边，统计哪个失败阻断哪些下游；只作诊断，不增产品 graph。根因归并必须有相同目标合同、首错阶段/owner、失败机制与修法；reasonCode、effect 名或画面相似不足以合并。

交付全量覆盖差距、公共候选短表、首批具体 owned paths、正反场景及回归集合，事实回写现有台账。以后增量盘点，只有 corpus/schema/family 解释变化或现有快照答不了影响面时才刷新全集。

### 3.3 P1/P2 的公共能力选序

先按依赖拓扑解决上游，再比较候选：

1. 新崩溃、unsafe failure、已有通过样本的可见回归优先。
2. fresh 运行证实的最早公共失败优先于尚未到达的下游。
3. 可独立闭合者中，优先实际受阻样本多、受阻下游广、官方合同明确、改动半径小的项；列受益集合与代价，不只按 occurrence 高频排序。
4. 两次实验均未移动首断点或减少工作量时，重新定位 producer-to-consumer 边，不继续微调同一形状 matcher。

下表是依赖排查顺序，不是已确认缺失列表，也不要求一次实现整个大类：

| 依赖层 | 公共职责 | 必须保护的组合 |
|---|---|---|
| 输入/资源 | 入口/VFS/引用、保真 identity/order、texture purpose/颜色/alpha、font/model/sampler | loose/PKG、slot hole/optional/default、缺失/ready/stale、静态/动态来源 |
| preparation/执行 | shader ABI/variant、render state、graph command/target/history | 多 pass、copy/swap、named dependency、previous-current、同层/跨层输入 |
| 帧状态 | property/condition、Timeline、VM/event、pointer/audio/media | 值变/拓扑变、事件相位、隐藏 controller、暂停恢复、晚到 provider |
| 对象产品 | particle、text/video、Puppet/3D、camera/light/depth | effect+geometry、provider+script、变换/层序、parent/child、跨层消费 |
| 唯一输出 | compositor、viewport/crop、blend、全场 postprocess | 透明边缘、背景、前后层序、resize/多屏、next-frame |

V0–V5 只作能力词汇；不得以另一个 input family 的通过替代 V4 完成。普通视觉失败与路径/ABI/range/生命周期 unsafe 必须区分。“颜色未证明”类拒绝先核对官方行为及 typed 内容合同，形成覆盖未见结构的公共规则；不能每个 source shape 加 analyzer，也不能合同未知时一律放行。

### 3.4 逐样本兜底与架构综合

归并无法解释时，对场景中的每个未闭合 occurrence 跟踪：声明位置 → decode → prepared 产品 → typed 更新 → 执行 → publication → output，记录首个错误/丢失的身份或值。已有共享链只引用 owner map，仅记录该 occurrence 的参数、分支和差异。

每样本可有多个问题，archive 保留全部已观察失败，最早因果失败用于调度。上游修复后重跑以暴露后续失败；旧错误消失不等于样本通过。同根因合并 repair 项；同 family 不同内容语义则拆 profile，以未见组合证实边界，不造样本白名单。

共享 owner 完成一轮或组合回归暴露错误边界时，综合检查：重复状态、帧内 preparation、过大失效、保护旧错误的 fallback、缺失 typed publication。只在可执行反例或测量证明后调整合同与实现；设计回写 `runtime-architecture.md` / `runtime-as-built-map.md`，不另建冲突的“最佳架构总方案”。

## 4. 完成与回滚

### 4.1 每个修复批次的完整循环

1. 核对 status、HEAD、owned paths、输入和恢复点；保护其他改动与真实样本。
2. fresh 隔离复现，列目标合同、owner/route、首错机制、影响集合与 unknown。
3. 冻结正例、局部失败反例、未见组合及预登记 ROI/事件门，保留 before 画面和身份。
4. 修改一个完整公共职责；转移 owner 时先定义 route、fallback、回滚及旧 owner 退役条件。
5. 按风险执行 inner → checkpoint → integration；Swift 产品改动 checkpoint 做 Debug build，GPU/VM/资源/生命周期/可见变化用隔离内容。显式选模块，`--scope scene` 不等于全量。
6. 复测新正例、旧 sentinel、未见组合、局部失败及影响集合，核对 completion/publication/compositor/next-frame 和真实画面；影响不明时扩大到全集。
7. 能力、执行证据、人工裁决和修复事件回写各自 owner；队列只留未完成项，报告实际恢复集合和后续断点集合。
8. 检查 diff/status，清理精确归属可重建产物；用户授权后才单职责提交，不默认推送；未完成则留下恢复信息。

### 4.2 回归集合与证据失效

定向集合取 **失败代表 ∪ 同 profile 旧 sentinel ∪ 依赖该 owner 的交互组合 ∪ 局部失败反例 ∪ 未见组合**。可以集合覆盖减少重复，但必须覆盖关键属性状态、variant、颜色/空间/target/动态组合；不能只选容易通过者。

每批先跑最小集合；公共能力关闭时跑全部受影响样本；共享 ABI、frame transaction、registry、clock、compositor 或影响不明的跨域改动执行全集里程碑。P4 候选构建始终跑全集，代表集不能替代每样本验收。

evidence key 绑定内容 fingerprint、代码/App identity、合同/schema revision、scenario、环境及 oracle revision。源码变化按依赖标记证据待复核，不擦掉旧 pass，也不自动沿用到新构建；影响不明则扩大。最终声明基于同一候选构建。执行身份或采集包缺失可留历史记录，不计当前关闭。

### 4.3 持续消融与回滚

每批列触达职责内的删除候选：重复 owner/matcher/wrapper、快照/序列化、过宽重建、无消费者缓存、重复 pass/copy。相关纠偏随纵向结果完成；无关优化归 E 路线。

成本消融按 E0/AS：同输入、画质/分辨率/优化级别/路由，至少三次成对比较 CPU、GPU、呈现、首帧和内存，区分诊断与产品成本；一次去一种成本。正确性、失败边界或性能退化即撤回优化，不靠丢作者内容或放松安全检查改善数字。

迁移只用 `observe-only`、`prefer-generic`、`generic-only`、`disable-generic`，各自明确唯一输出及退出条件。进入 `generic-only` 需未见组合、局部失败、fallback 审计与回滚演练；撤旧引用后才声明 owner migration。扩大失败半径或损坏画面时原子退回已证安全 route，不静默双执行。

完成声明分开：`slice-visible` 是切片真实闭环；`owner-migration` 是所有权转移和旧引用撤销；`parity-release` 还需官方对照、性能/长稳、发布门。compile、recognized/wired、route 数、matrix PASS、非黑、单截图和单样本不能越级。

## 5. 官方证据、工具与断点续跑

### 5.1 研究只解决当前公共设计歧义

按[来源索引](semantics/source-index.md)及[研究工作流](semantics/official-client-behavior-research-workflow.md)，先查现役合同、官方公开文档/声明、合法 corpus 与已有结果；仍有影响实现选择的 unknown 时设计单变量黑盒实验。Ghidra 只在公开/黑盒不足时做有界职责、顺序、状态或生命周期研究。

MirageWallpaper 有明确问题时才固定 revision，交叉核对职责/状态流并记 divergence；不是官方真值。私有 shader/算法/payload、取证原始输出及第三方实现表达不进入产品上下文。静态研究与 fresh implementation context 分离，只交接经审查中性合同、自有 fixture 和官方对照协议；完整继承研究对话不算隔离。

### 5.2 复用工具与补齐顺序

| 既有入口 | 用途与待补项 |
|---|---|
| `scene_capability_census.py` 及领域 census | 全量声明/结构/参数索引；补 profile/关系引用，不写运行支持判断 |
| `scene_sample_snapshot.py` | 冻结隔离输入及 fingerprint；真实根只读 |
| `scene_wallpaper_benchmark.py` | 已有 DEBUG 运行/截图/事件/资源观测；先补普通产品路径身份和采集，再批处理 |
| `scene_sample_debug_archive.py` | 汇总 run/首断点；补 scenario/occurrence、全失败观察和时效 |
| `scene_sample_acceptance_ledger.py` | 汇总人工 verdict；补参数/条件场景、官方对照完整性，不自动判视觉 pass |
| `scene_capability_repair_ledger.json` | 公共根因、影响/复测集合、sentinel；新增字段先升级 schema/validator |
| `verify_scene_change.py`、gates/Fast Suite | 按 owned paths/风险选门；候选先有真实正反结果，不只改 readiness 标签 |

第一批可先执行的只读命令（仓库根）：

```bash
git status --short --branch --untracked-files=all
python3.12 -B script/scene_capability_census.py verify
python3.12 -B script/scene_capability_census.py query --sample <sample-id>
python3.12 -B script/scene_capability_census.py query --family <family-key>
python3.12 -B script/scene_sample_snapshot.py --help
python3.12 -B script/scene_wallpaper_benchmark.py --help
python3.12 -B script/scene_sample_debug_archive.py --help
python3.12 -B script/scene_sample_acceptance_ledger.py --help
python3.12 -B script/verify_scene_change.py --phase inner --base HEAD --path <owned-path>
```

尖括号需替换；census 默认路径先由 `--help`/源码确认本机存在，`query --live` 才重建私有细节。末条只查看选择，确认后加 `--run`。构建用 `/bin/bash script/run_checkpoint_build.sh`。尚无的 schema/批处理选项先实现验证，不编造命令。

### 5.3 续跑、预算与阶段汇报

恢复信息放既有 repair/归档/派生队列：`batch_id`、阶段、输入/代码身份、owned paths、合同/owner、已完成/待跑集合、精确命令及退出码、首断点、证据身份、依赖、回滚点、下一动作。扩展前用现有条目说明，不新建重复知识库。

每批报告：声明关联覆盖、公共修复与实际恢复集合、截图/事件对照、回归、新断点、删除项和测量、未验证边界、工作区/提交状态。总进度同时看 occurrence/scenario 覆盖、能力证据和人工样本裁决，任一单项百分比不能替代总目标。

不预写若干天全部完成。P0 校准波次取得单样本准备/运行/采集/人工复核成本与公共缺口数后，估算剩余运行时间和人力；构建、冷准备、长循环、官方环境等待单列。基础设施失败保持阻塞并推进独立工作，不以重试次数或超时记通过。

## 6. 何时退休本文

冻结全集每样本均完成声明/条件场景覆盖、真实显示/动态/参数人工验收和固定官方一致性对照，P5 通过，旧 owner 已撤权，unknown/unsupported 未被计作完成，稳定架构/能力/证据权威接管终态后才转历史。范围变更须有新的明确裁决；不能排除失败样本、缺官方环境或扩大容差自行关闭目标。
