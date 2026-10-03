<!-- document-role: active-plan -->
<!-- retirementCondition: 四类触发点均使用唯一 typed graph transfer 合同，重复路径撤权且 publication 门通过后归档。 -->

# D12 — 四类 copy 触发点的 graph 语义收敛

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

link 名称变化、mip 快照、作者 copy command、post-process 末跳都通过同一个 graph 资源版本与传输合同决策；并非每个“copy”都必须发出物理复制。跨 graph planner、资源 lease、encoder 与 terminal output，触及 hazard、publication 和唯一 compositor。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift:315` 已区分 copy/swap/unknown；`:328` 要求不同且已声明的两端，`:336` 插入有序 node。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneGraphResourcePassEncoder.swift:149` 已有 typed copy operation，先 validCopy 再 encodeCopy。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift:61` 明确 1×1 probe 不能证明实际 copy extent 兼容；`:81` 检查命令源/目的声明与描述符。
- [Mirage 结构参考](../../development/reference/miragewallpaper-rendering-reference.md) `:208` 的资源版本与 `:500` 的最终 copy/blit 是有限对照；交接 render-9 的四触发点作为审计范围，不代表当前四路都已完整实现。

## owner

现役 authored render planner/graph admission owns transfer intent、作者顺序与版本边；target lease owns storage/lifetime；SceneGraphResourcePassEncoder 是既有 transfer encoding 接口；终端 compositor 唯一 owns final present。禁止新增独立 CopyManager 或副 compositor。

## 方案设计与选型

选择**统一语义 IR、按能力降低为 alias/blit/render transfer**。仅把四处调用包成同名函数不能统一版本语义；把全部 copy 变成全屏 draw 会改变 alpha、颜色与性能，均不采用。

| 触发点 | graph 行为 | 不能采用的捷径 |
|---|---|---|
| link 改名 | 先判断只是同版本逻辑别名还是需要独立快照；后者生成新 target version 与 copy node | 名字不同就复制；或需要 snapshot 却 alias 可写 storage |
| mip 快照 | 固定读取时点、source mip/slice/extent 与目标用途；复制既有 mip，与生成 mip 链分为不同操作 | 用 base mip 假装全部 mip；在 source 后续覆写后才取样 |
| authored copy command | 在作者命令所在次序插入，精确 source version→destination new version | 移到 effect 末尾、把未知 command 当 swap |
| post-process 末跳 | 将最后 graph result 交 terminal compositor；若格式/extent/颜色一致且可直接消费，可省物理 copy | 绕过 terminal compositor 自行 present；在 final copy 再次 blend/tone map |

每个 transfer 描述已有 logical identities、读写版本、subresource、extent、format、content/alpha、读写用途与 completion 要求。兼容 bit-preserving copy 用 blit；缩放/颜色转换是明确 render transfer，独立标注，不能借 copy 暗改数据。mip 生成是依赖 source 的显式 prepared 工作，不由一个 copy Bool 隐式触发。

prepare/invalidation 验证源/目的范围、格式、采样数、mip/slice、history pin 和 alias hazard；runtime 检查实际 allocation generation/physical token 与 descriptor。未声明合法 feedback 的 self-copy 拒绝；需要重叠区域 copy 时先显式准备安全中间 target，不原地赌驱动行为。

allocation 未完成、encoder 创建失败或 command buffer 失败不能 advance committed destination version。相同 buffer 内依有序 graph 消费候选版本；跨帧发布仍受现役 completion/history 协议。resize/reload 使旧 transfer reservation 失效，completion 只能回收自己的 token。

[D8](rt-prefix-admission-design.md) 负责两端名字解释，[D1](composition-render-target-design.md) 组目标作为普通 typed target；[D2](hdr-tonemap-edr-design.md) 显示映射只在末端执行，copy 不重复 tone mapping。

## fallback / route

可选 effect 的 copy 不可用时保留进入 effect 前的 previous-current；有真实必需依赖的后继只拒绝最小闭包，不向其发布旧值冒充新版本。hazard/range/generation/预算违规 hard reject。旧 copy 路由迁移 `observe-only` 比较规划，不能双执行；按触发点转 `generic-only` 后删旧 encoder 分支。

## 纠正门

- 四个触发点分别以自有颜色格、不同 mip、alpha/data 纹理验证读取时点和目标内容；copy 前后插入 source 修改可区分 alias 与 snapshot。
- format/extent mismatch、1×1 probe 假阳性、source=target、mip 越界、history pin、resize、encoder/GPU failure 和反序 completion 都必须有反例。
- bit copy 使用精确字节门；缩放/显示转换使用预声明像素容差；命令顺序、publication version、terminal present 次数与 next-frame identity 要 exact。
- 实施时先盘点四类生产入口与现役 copy owner，再收缩重复路径和结构预算；不能根据“统一了函数名”报告完成，不能把 mirror/第三方输出当官方 golden。

## 退役条件

四类路径完成真实 producer→consumer 追踪和正反门，稳定 graph 合同接管且旧 copy 分支与预算同步下降后归档。未知 mip/颜色 profile 仍由 admission 显式拒绝。

<a id="rf04-completed-scene-environment"></a>
## RF04 — 完成画面的共享 mip 输入（2026-10-03）

本节替换 F5 的“首次消费前 main 前缀”项目策略，仅批准下述有界后继，不将 D12 其余触发点计为完成。用户结果是：合法作者 `_rt_MipMappedFrameBuffer` 读取与默认反射使用同一份历史 scene color，后置层也能进入下一次可读画面；不按 sampler 槽号改变资源语义。

**分批裁决。** A 先纠正现有默认 F5 的真实历史源；独立设计审查接受其下述 member、intent、drawable 与 mandatory 保护边界。A 仅按现已准入的 builtin 反射消费需求生成历史，不开放作者 sampler，也不需要将零强度 flag 升为 producer。B 才实现第1项的 scene prerequisite/demand 汇总及第6、7项的作者绑定/回退；B 保持 `blocked-pending-design`，不得将 A 通过写成 B 可用。

B 的实际阶段环已确认：`admitResolvedMaterialFrameTargets` 的实际 Program finalize 在 `reserveOptionalEffectScratch` 之前；F5 可保存延迟闭包，作者 sampler 却需要真实 ready candidate。下述 [B 候选合同](#rf04-b-admission)选择窄容量预检与 terminal 独立可选 mip，仍为 `blocked-pending-design`；本次只读 owner/阶段研究不证明新增容量模型可行。B 不反向阻塞 A，也不能借 A 的运行验收开放作者接口。

### 新证据与可实施边界

[官方中性观察](../../history/rf04-scene-mip-observations-2026-10-03.md)已独审：Q 单变量 reflection 激活、SC 共享 scene scope、静态 source 差分及快速时间词的呈现邻接支持本片；完整输入、计数、冻结与未证明边界只在该证据权威保留。未读取官方或参考项目实现表达。

据此选择“最后成功完成的原始 scene color”作为本项目可验证历史源，优于已被该 profile 反例推翻的 main 前缀。官方 HDR、alpha、首帧占位、重置、失败策略及 mip kernel 尚未定案；以下对应部分是项目策略，不能宣称官方全量 parity。限定 2D、单 sample、当前工作颜色格式的颜色输入；不开放 data、cube、数组、普通 authored FBO 自动 mip 或未知名称。

### 单一职责与阶段

1. **准备期需求。** 生产资格只来自本片准入的 builtin base profile：沿 `supportsBuiltinImage` 合法 shape 读取有效 material/instance 的 `REFLECTION == 1`，由既有 `BaseMaterialProviderBindingProgram` 保存 feature presence；`RuntimeCatalog` 只汇总可达 active environment sampler 的消费需求，不能因任意 custom effect 同名 combo 自造 producer。custom-only 生产资格未证，保持 unavailable。scene 聚合生产资格与 builtin/作者消费需求，不在普通帧解析 authored 字典；已有持久 demand cache 的语义版本随新准入失效，旧缓存不能维持 unadmitted 结果。生产资格与 reflectivity 数值、normal 当前 ready 分离，B 可依赖同 scene 的合法生产资格；没有消费需求不分配历史或 mip。动态可见性沿现有 typed projection，不重建全图。
2. **历史唯一权威。** 扩展 `SceneResolvedMaterialSubmissionCoordinator.completedSceneColor`，不新增 history manager。原 HDR + clear=false 的双 raw 保留路径、seed 与 paused export 不变。reflection-only 场景仍画到现有 main；必需目标准入后，按真实需求尝试同 owner 的可选 snapshot reservation，在终端 Bloom/显示映射之前将最终 raw main 复制到候选 raw member。clear=true 不从前序 raw seed，也不因需要历史跳过当前绘制。`SceneMetalView` 在创建 drawable 前将 prepared history 读需求并入现有 `framebufferOnly` 判定，保证普通 LDR 的 main 可合法 blit；保留现 HDR/Bloom/FullFrameBuffer 等可读条件，无需求不额外关闭 framebufferOnly。Debug capture 的强制可读不能充当该产品门的验收。
3. **分配与版本。** 现 pool 的 sceneColor allocation 按实际工作格式支持双 raw；仅原保留画面输出需要 display scratch，不能给普通 history 无条件多分配第三张纹理或假别名。profile 进入真实 cache key、byteCost、physical identity 与 residency 计数。reservation 冻结前序 texture、producer frame/epoch、allocation generation/reset epoch；记录当前提交 identity，不能拿当前 consumer epoch 冒充生产帧。明确区分 persistence 与 snapshot 模式：原 persistence 同 simulation frame 的 paused export 可以不重画并复用 raw member；snapshot 只要重画 main 就总选非 prior member，即使 frameIndex 相同也不能覆写 completed raw。receipt 含实际生产提交 identity，frameIndex 本身不是内容版本；同 frame 重画后失败必须仍保留旧 completed 字节与身份。
4. **共享派生。** `ReflectionFrame` 仍只属于当前 command buffer；从 reservation 冻结的已完成 raw 复制 level 0，再生成完整 mip 链。第一次实际读取至多执行一次，后续内置 F5 与 authored consumer 共用同一个 typed `.sceneEnvironment` publication。关闭实际活跃 encoder 后再 blit，copy→generate→read 有序；新派生 allocation 用当前提交 epoch，source receipt 保留历史生产身份。原 raw 保留不被懒惰生成 mip 覆写。`Resolution` 使用实际完整 extent。
5. **发布与退出。** reservation 的 intent 与 terminal 完成条件明确区分：persistence 沿原 display-output mark，snapshot 沿成功 raw-copy mark；原 seal 按 intent 验证，不能要求 snapshot 伪造 `displayMapped`。原 HDR persistence 本来已产 raw，直接复用其 reservation/completion 作历史，不再申请第二候选或额外 snapshot copy，seed/display 失败仍保持原 mandatory 行为。普通 snapshot copy 成功只封存候选，原 completion FIFO drain 在 GPU 成功且 epoch/generation 有效时提升。optional copy 失败只 detach 本 CB 的 snapshot reservation，不能调用还会释放 display scratch 的总取消方法；已编码 pin 保留到 CB terminal。取消、失败、resize、reload 不提升。第一次无历史只局部关闭环境采样，正常画面完成后才有下一次可读历史。resize 对所有已准备 history demand 使原 coordinator/pool 失效，不另设 reset owner。
6. **名称到绑定。** 名称 vocabulary 只准入精确 canonical 名称；沿现有 typed provider request、frame binding、candidate/descriptor 校验进入实际 Program sampler，不按 slot3 特判。内置 F5 显式 canonical 输入与默认输入归同一请求；用户自有其他 slot3 仍遵守既有优先级，不能被覆盖。launch 根据静态 typed 颜色/格式合同承认活跃 required sampler 并准备合法 Program，不能因启动时没有历史而永久判 unsupported；真实 texture 只在 frame publication 后绑定。
7. **缺历史的局部证明。** 当前 `TextureResolver.typedVisualFallback` / `ColorBlendEligibility` 的 optional system proof 不覆盖 environment 或 annotation default；本片必须在原 VariantCache proof 和 GraphExecutor rollback 拓扑中增加精确 environment-unavailable 证明，覆盖合法显式及 default 来源，不伪装成 system、不放宽所有 provider。首帧或可选资源失败保留进入该 effect 前的 previous-current，内置只去掉反射分量；真实后继依赖仍按原最小闭包拒绝。缺资源不是 ready，不伪造 1×1 资源或旧 extent。

**A 的跨帧预算让位。** 普通 optional snapshot 完成后，同 coordinator 只保留 pool/key、physical generation/reset、member 与真实 producer receipt 元数据，不持 targets、texture 或 retention pin；完整纹理由原 pool cache 独占，下一帧 mandatory 可以沿原 eviction 驱逐。pending/current CB reservation 仍强 pin 到 terminal。mandatory 保护后取得实际 sceneColor lease，再核 pool/key/generation/reset/extent/format/profile 全匹配，才从该已 pin 的 pair 恢复 prior raw；cache miss 或被替换即无历史，不能凭旧元数据伪造 ready。HDR persistence 继续原强 retention/raw seed，不参加可选让位。这样不重试 admission、不另建回收 owner，也避免已完成 optional 历史长期挤占未来必需资源。验收必须包含前帧有反射、后帧新增 mandatory 驱逐历史后仍正常显示及重新启动。

### 成本、失败与方案取舍

选择原双 raw + 本次派生 mip：保持 raw completion、显示输出与 mip readiness 分开，改动可沿已有 owner 逐段验证。直接把双 raw 改为 mipmapped 并在 producer terminal 生成能减少一次 copy，但扩大持久 allocation、未消费帧成本和 publication 合同，本片不采用。逐 consumer 快照、多独立历史或将 pending raw 当 completed 均不采用。

可选历史必须在现有 graph/group/history、plain/HDR scratch 及可确定的 depth/Bloom/framebuffer 容量获得保护后准入，使用既有 pin/预算，不以固定余量猜测。具体复用 `StaticModelFrame` 的 actual draw/depth lease preparation 与既有 terminal/framebuffer capacity：共用必需准备后，shadow 或 environment 才分别尝试可选分配。model 与 particle 按实际需求独立准备，不能把现 `prepareModelShadow` 的 model pipeline guard 原样搬到整个共用 helper。late named 无法给完整 draw 集等无法保护的真实晚分配依赖，只放弃本帧环境，原画面照旧。snapshot allocation/encoder 失败只撤销本 CB 的可选历史候选；不得取消原 HDR persistence reservation 或使无反射 suffix 丢失。已编码可选资源 pin 随实际 CB 完成释放，不能 CPU 撤销在飞写入。无可读前序时仍可生成本帧候选以便下一帧启动；连续失败后读取的可能是更早成功画面，身份必须如实表示。

<a id="rf04-b-admission"></a>
### B 候选合同：条件读准入与终端可选 mip

**状态与范围。** `blocked-pending-design`。本段只规定 B 的待审后继，替换上文第4项及成本选型中对 B 的“消费 CB 派生 mip”设想；A 已验的 completed raw、默认 F5 延迟派生、失败与普通 drawable 范围不因此扩张，具体结果仍归运行证据权威。B 的最小结果为：合法 builtin 生产资格下，两个不同槽的作者 environment sampler 与 F5 共用最后成功完成 raw 的同一 mip publication，首帧局部降级后能在后继帧实际执行作者 Program。限定能够提前确定 mandatory 容量的 2D、单 sample 颜色 profile；late named 等未闭合 profile 不计支持。

**选型。** 保留原 `actual graph allocation → executor.prepare / Program finalize → commitAndPinPersistentGraphTargets` 顺序。整体提前 graph commit 需要拆开 submission pin 与 executor 结果决定的 history/discarded-effect commit，并处理 provisional abort，超出本片。把 HDR 双 raw 直接改为 mipmapped 又会把可选成本嵌入 mandatory seed storage，均不采用。B 仅在现 pool 增加有限 mandatory frame-scratch 容量需求与条件读 pin；不新增 history、registry、预算或 completion owner。

1. **静态资格与首帧 Program。** 上文第1、6、7项由本片实施：prepared feature presence 决定生产资格，reachable sampler 决定需求，不依赖当前 mip ready、reflectivity 数值或 normal 当前 ready。Template/provider vocabulary、`TextureResolver` launch readiness/format/color fact 与 `VariantCache` 按精确 `.sceneEnvironment` 静态合同预编译真实作者 Program；显式声明和 annotation default 遵守同一优先级，不覆盖其他 slot3 输入。launch 只证明合法 Program，不构造 texture/publication。frame 缺历史返回精确 environment-unavailable，经原 VariantCache 的完整 reachable-envelope 证明和 GraphExecutor previous-current 拓扑检查，只跳过该 effect；不伪装成 system provider，不扩大失败半径。后继帧重新读取 provider 状态并执行已编译 Program，不缓存首帧永久 passthrough。
2. **联合容量需求。** 在 `SceneResolvedMaterialFramePreflight+Admission` 取得 `.ready(plans, localFallbacks, preparationRequests)` 后、调用 `prepareResolvedMaterialFrame` 前，冻结全量 graph/group/history、shared-pair 缺额、plain/display scratch 的 key/extent/format/实际字节成本，以及可确定的 depth/Bloom/framebuffer capacity 条件。复用当前 typed frame projection 和各原 owner 的需求，不在普通帧重解析作者输入。此 hook 不提前物化 plain scratch，不更改原 mandatory 分配顺序。首帧即使没有历史 reader，也须满足相同 mandatory 保护条件，才允许稍后生产可选候选。
3. **精确条件读 pin。** `SceneOffscreenTextureAllocationCache` 在同一锁域中先验证原 mandatory-only 集合，再对拟保护旧 completed mip 的 resident snapshot 验证 `mandatory + read pin`。现 `preflightGraphs` 的 resident/shared-pair 模型须扩展有限的未来 mandatory scratch keys 与缺额：按 key 去重，保护稍后会复用的 resident，覆盖 graph replacement/history seed，不能只算新分配或固定余量。两次判断通过且 pool/key/generation/reset/extent/format/producer receipt 全匹配，才落真实读 pin；失败或 cache miss 为环境 unavailable，原 mandatory 路径照旧。completed 元数据本身不持 texture 或 retention，不能先 pin 再要求 mandatory 让位。读 pin 随实际消费 CB terminal 释放。
4. **预检后的约束与绑定。** 保留原 graph admission、actual leases、finalize、commit 及后续 mandatory 物化顺序；在联合需求全部获得真实容量保护前，不准插入未计入集合的 shadow/history/mip 等可选分配。当前 epoch、extent、visibility 或容量需求改变即令旧证明失效，不继续绑定。`SceneResolvedMaterialFrameSnapshot` 只在条件读准入成功后 overlay 真实已完成 mip；consumer frame epoch 与 source producer receipt 分开。晚 named-model provider/capture/depth 若不能提前列出完整需求，本帧不取得 environment 读 pin、不以估算放行；沿原路径完成 mandatory，该 profile 明确不计 B 支持。覆盖它需要原 owner 的 capacity-only 计划另经验证，不能靠持续 passthrough 宣称完成。
5. **F5 共用与终端生产。** B 切换后 `ReflectionFrame.resolve` 只返回上述本帧 publication，F5 与作者消费者共用资源及 source receipt；撤销 A 的消费 CB copy/generate，不能双执行。全部 mandatory 受保护后，普通 snapshot 在成功 raw copy 后、HDR persistence 在 raw 绘制后，尝试从本生产提交的 raw copy level0 到独立可选 mip candidate，再 generate。仍位于 Bloom/显示映射之前，关闭活跃 encoder 后编码；无消费需求不增加候选或 mip 工作。候选分配/编码失败只关闭环境，HDR raw seed/display 的最低成本与失败合同不变。
6. **单一完成身份与物理隔离。** 原 `SceneColorReservation` 携带可选 mip lease/encode mark，原 `CompletedSceneColor` 仅增加对应 producer receipt 的 mip 元数据。仍由原 FIFO completion 一次裁决：raw/提交失败不提升；raw 成功但 mip 失败则提升 raw、该 receipt 的 mip unavailable；二者成功才发布 mip。不得把旧 mip 挂到新 raw receipt，pending 不能读。terminal writer 必须排除当前 completed mip 的 physical generation，即使同一 CB 已经先读后写；现 `reserveEnvironment` 的同 CB ordering reuse 不能直接用于此候选。复用 pool 的 `.environment` current/retired replacement 与在飞计账，旧读 pin 和新写 pin 均留到各自 terminal；不新增双缓冲 manager。取消、失败、resize、reload/stale completion 不得把旧字节或新候选冒充已完成版本，同 simulation frame 重画也保留真实 submission receipt。

**成本与保留理由。** 本片暂保留 A 的 raw snapshot 权威与失败机制，独立 mip 是同 receipt 的可驱逐派生缓存；raw 与 mip 共存不是语义必需，也不宣称省复制或省内存。设 base level 实际字节为 `R`、完整 mip 链逐级总字节为 `M`，在原单 pending producer 边界内，普通 snapshot 的旧读/新候选峰值可达 `2R + 2M`，HDR 为原 mandatory `3R` 加可选 `2M`，其他 graph/scratch 另计。方形常见 `M≈4R/3`，非方形必须精确求和；无旧在飞读取时允许驱逐，不能把峰值写成固定常驻量。容量不足只拒绝可选部分。以后让 reflection-only mip level0 接管 raw、退掉双 raw 需要另改 reservation 合同，本片不顺带迁移。

**解除设计阻塞的两项定向实验。** 先在自有现 owner harness 中检验，不以 A 的通过代替：

- 容量实验：对同一冻结 frame 比较 mandatory-only、拟 mip 读 pin、实际 graph commit、原顺序 scratch 分配的结果；覆盖缺失 shared pair、cached graph replacement、history pin、scratch key 复用/去重、精确预算边界和 reset/revision 变化。证明可选准入不令原本可行的 mandatory 失败；模型与实际不一致即保留 blocked，不增加余量掩盖。
- 生命周期实验：真实 owner GPU 路径先读旧 mip、同 CB 终端写新候选，断言 physical generation 不同、两份成本与 pin 可追踪；注入 copy/generate 编码失败和 GPU failure seam，核 raw receipt、mip metadata、FIFO promotion 与释放。新提交失败不能发布新 receipt，旧 generation 不得被当作新 completed。

**B 完成门。** 两定向实验、设计独审后才决定实施准入；产品完成另需 actual authored sampler 的首帧 previous-current、下一次成功完成后恢复、两个不同槽与 F5 同源、后置层进入后继环境、FullFrameBuffer 当前语义不变。再验前帧 ready、后帧新增 mandatory 驱逐 mip 后健康图层继续、容量恢复后无需 relaunch 恢复；覆盖 HDR mandatory 原预算、同 frame 重画、resize/stale completion、独立 surface、无 consumer 零新增、普通 capture-off App 运行及 Debug build。最终 frozen diff 独审通过才迁移稳定合同并退役 A 的消费派生路径；官方 GPU 帧延迟、HDR/alpha/kernel parity 仍不在声明内。

### 实施门与完成条件

- A 按独立审查的既有 F5/历史职责登记 `approved`，完成真实可见与生命周期门后提交；B 的 preflight/mandatory 阶段环另经独审定案前保持 blocked，旧 D12/F5/A approved 均不替代它。
- owner 行为门：普通 BGRA8/RGBA8 与既有 RGBA16F、首帧、两次成功提交、取消、GPU 失败 seam、stale completion、resize、paused export、独立 surface、精确预算和 display scratch 按需；pending 不能读，receipt 必须对应实际生产帧。
- GPU 门：A 用自有颜色/时间词经实际 history→copy/mip→不同 LOD consumer→唯一 terminal；两个测试消费者共享源，后置可见层进入后继历史；FullFrameBuffer 仍读当前语义。B 另验实际作者不同槽绑定。明确项目采样容差，不能把 mip 端点量化当官方滤波公式。
- App 门：A 以隔离自有原型检查内置反射、局部缺历史/预算失败、健康邻层、下一帧启动，并包含关闭 Debug capture 的普通 drawable 运行；B 另验实际作者 sampler。Debug build；最终冻结 diff 独立审查。无 consumer 不增加 history 分配或 mip encode。
- 完成后稳定 owner/失败合同移入 runtime architecture，撤销 F5 当前前缀实现与对应断言，本节收口为交接；中性官方结果只保留一份历史事实权威。未执行的 HDR/alpha/kernel parity 不计完成。
