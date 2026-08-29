# Scene 公共能力依赖图与实施门

> 状态：现役依赖参考
>
> 最近核对：2026-08-25
>
> 本页只维护依赖边与完成门，不拥有 current capability 状态；系统级 current 摘要只见 [总覆盖台账](coverage-ledger.md)，精确 App、报告和测试身份只见 [运行证据索引](runtime-evidence-index.md)。表内等级只是所链接专题的局部摘录，不可横向比较或反向覆盖总台账。
>
> 目的：表达通用执行单元之间不可绕过的运行依赖。当前用户结果和优先级只由[Scene 兼容执行路线](../scene-compatibility-roadmap.md)决定；本图不是逐节点实施队列，也不能把整层依赖变成首次出画面的前置工程。

本文把 [总覆盖台账](coverage-ledger.md) 和各专项表中的能力整理成依赖图。它不改变任何能力等级，只回答“一个通用 compiler、VM、graph 或 executor 在执行某类输入时依赖哪些公共状态”。前置合同可以在同一可回滚批次中按实际消费面闭合，不要求先把整层所有语义逐项证明完毕。

[全样本能力分类与修复事件台账](scene-corpus-capability-inventory.md) 提供另一条正交轴：某个公共结构 family 在真实 corpus 中覆盖多少样本与可见 occurrence，以及哪些修复事件曾以它为作用域。依赖图用于发现旁路和缺失前置，corpus 用于估计受益面，隔离样本用于定位失败；三者都不拥有 current capability 或现役计划，也不能合并成按名称或数量机械排序的专用工作队列。

## 1. 依赖图

```text
D0 Source/VFS/Scene IR
  -> D1 Stable identity and authored dependency graph

D2 Host/surface frame context and lifecycle
  -> D3 Typed values, binding program and per-surface evaluation
  -> D4 Input snapshots and event queues

D1 + D2 -> D5 Texture/media/provider registry
D1 + D5 -> D6 Render-target graph and resource lifetime
D0 + D3 + D5 -> D7 Material/shader contract
D1 + D2 -> D8 Coordinate spaces and geometry

D3 + D4 + D5 + D6 + D7 + D8
  -> D9 Generic 2D execution layer
  -> D10 System runtimes
  -> D11 Fidelity and advanced runtimes
```

`D9` 是通用 layer/effect/particle/text consumer；`D10` 是 Timeline、SceneScript、audio/media、dynamic text 和 particle event；`D11` 是 Puppet、lighting/HDR、3D、RGB 和 offline。后层可以与前层研究并行，但不能在前层合同未闭合时写产品执行旁路。

### 1.1 如何使用本图

依赖与优先级是两条轴：本图决定一个已执行切片不能缺少哪些运行合同，现役路线决定当前先闭合哪个可见结果。隔离真实样本的首个失败 identity 用于定位缺失 primitive，但不自动决定架构；优先选择能让同类 authored 内容受益、并能局部降级的 compiler/VM/graph/executor 修法。definition/material/shader/component/API identity 可以加载声明、资源或共享 primitive；sample/layer/path/hash 不得选择样本专用视觉答案。

一个批次可以跨多个 D 节点和源码目录，只需闭合本批实际消费的 identity、order、resource、target、budget 与 lifecycle。涉及 GPU 或可见输出时验证到 `GPU -> publication -> compositor -> next-frame`；只有声称具体 fidelity 回归恢复时才要求目标 ROI/事件断言。未知 optional 语义可保真、告警或局部 passthrough，安全与状态完整性风险仍 hard fail。

本图不得被用于：

- 要求 D0-D8 所有字段全部达到某等级后才允许 D9 通用执行；
- 从某个 `L3 bounded` 子集推导新的 exact planner、renderer 或 admission catalog；
- 以 rejection 数、strict profile 或单样本闭环代替 corpus 广度、故障隔离和产品运行证据。

## 2. 公共底座

<a id="d0"></a>
### D0 Source / VFS / Scene IR

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| project/scene/PKG/TEX/resource ingest | 常见 2D 子集 `L3`；严格 `TEXV0005/TEXI0001/TEXB0004` format-0 vertical-PNG 3D LUT profile 可保留 depth 并上传 Metal volume | LUT material/effect consumer、其他 volume 版本/codec/mip、version、case、duplicate、symlink、损坏和 VFS golden |
| project/scene declared compatibility facts | `L2`；project 与 scene version 分别保留 missing/value/invalid/out-of-range 及 provenance，不合成 effective version，也不按版本猜默认 | 只有合法文档/资料和跨版本 fixture 支撑后才登记 compatibility default/patch rule；未知版本继续失败关闭 |
| shader source VFS graph | `L2 bounded`；在同一 `SceneResourceView` 上保留 package/loose/stock 候选、provenance、冲突、include edge/content digest 与预算，旧 raw stage projection不被改写 | package -> loose -> stock 只是当前项目 policy；仍需 verified official/version precedence、动态 resource generation 与 executor consumer |
| object/content/effect/material/particle/script source preservation | 混合 `L0-L3`；SceneScript 文档级 inline binding 已保真五类 owner/完整 target path/properties/authored fallback/JSON value type，局部 `L1` | raw + typed round-trip；file/module、schema-resolved value type、handle 与未知 owner 可诊断，不静默丢失 |
| typed renderer input | `a77b875` 起宿主接收原始项目目录与属性覆盖，解析后直接构建内存 `SceneRuntimeInput`；生产播放不再生成或读取私有解释 JSON/preview log | 已闭合：Debug 结构证据只写入显式 evidence directory 的 `scene-runtime-evidence.json`（schema 1），不作为播放输入；固定 13 样本 raw-root 门 13/13 |

<a id="d1"></a>
### D1 Stable identity and dependency graph

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| scene/object/layer/effect/pass/material/target identity | 部分 `L2-L3`；Scene loader 与 descriptor admission 双重拒绝重复 authored object ID，报告排序后的冲突 ID并沿 launch error 保留具体原因，避免下游 identity dictionary runtime trap | authored ID 优先、合法缺失时的 ordinal fallback、跨屏/跨帧作用域明确；effect/pass/material/target duplicate 继续逐类补门 |
| source order、parent、dependency、provider、read/write edges | 部分 `L2-L3` | cycle、missing、duplicate、read-before-write 和 topology invalidation |
| named/effect/history target identity | `_a` 子集 `L3`、`_b` `L2`；primary named target除classic/static provider、multi-consumer/multi-reference/two-provider外，又闭合backward acyclic hidden-image effectful provider closure：GraphExecutor final复制到独立named reservation，中间provider不占compositor。exact Cursor Ripple strict history target与普通Motion Blur material/copy/unique-history graph各有bounded `L3` consumer，后者已闭合initial/COW、executor invalidation、同输入及same-identity/different-authored-state scene re-launch、surface stop/relaunch与正式pause/resume生命周期 | primary/secondary/history不混用；继续补secondary、forward/cycle execution、child/non-image、multi-dependency/reference、arbitrary depth、nested provider的history/resize/seek/device loss、多surface与预算门 |

<a id="d2"></a>
### D2 Host/surface frame context and lifecycle

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| host/frame/scene/wall time | `L3` 子集；共享 clock 发布 raw、最大 0.25 秒的 simulation、dropped delta/discontinuity；particle/parallax 消费 simulation，shader/video/Timeline 保持 raw/absolute time；pause 冻结 scene time/frame index，resume 首帧丢弃 host gap；有界persistent-history运行门证明正式pause排空已提交工作后无新transaction并沿同runtime/pool恢复COW | 真实系统 pause/sleep、seek/其他history topology、其他 simulation consumer、目标/不同 FPS、离线与 Windows timing 门 |
| host-shared vs surface-local scope | property输入host-shared；每个surface独立transaction/snapshot/generation，B0 live alpha/solid color、exact Local Contrast typed strength与root particle direct User Property已有运行门；Local Contrast现由共享Program消费该snapshot | pointer/matrix/provider/script接入时继续证明local state不串屏 |
| fixed simulation step and seed policy | particle fixed step 已消费共享 simulation delta，并保留自身 deterministic seed | effect/script/offline 共用 discontinuity、fixed-clock 和 seed 合同 |
| resize/switch/stop teardown | surface子集`L3`；embedded video registry为launch-scoped，按layer/source/device跨surface rebuild复用并在stop释放。普通persistent graph已证明同输入及same-identity/different-authored-state scene switch各自创建独立runtime/pool、surface stop清空到0再重建；input extent A→B→A另有allocation/history门 | VM、system/media provider、其他RT topology与GPU资源精确计数；真实hot-plug、device loss、multi-surface与反复切换soak |

<a id="d3"></a>
### D3 Typed values, binding program and per-surface evaluation

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| value types and target definitions | 六类value与主要target由v22持久化；direct text、exact Local Contrast/Opacity与bounded Blend multiply已注册typed target。Local Contrast target现由共享MaterialProgram消费；shared layer alpha、audio-scaled particle rate/layer scale与identity display保持bounded native projection。property slider→Vec3 origin/scale已迁入同一QuickJS-NG domain并以真实`2802243144`闭合两个origin owner | 新类型继续执行type/finite/default validation；其余native projection不冒充ECMAScript、mutable shared或generic binding，当前Vec3正证也不外推全部Vec target/API |
| source priority | `authored -> property -> Timeline -> SceneScript` 已定义；property、受限Timeline与bounded text/time-of-day/fade producer已复用同一resolver | generic SceneScript/event mutation接入时不得在renderer内重复求值 |
| binding program | layer alpha/solid color、direct text、Local Contrast/Opacity 与 bounded Blend multiply 编译、验证和持久化已完成；`311115e3` 的 shared/audio/property/identity bounded program 已接入 definition/snapshot consumer；mixed/invalid/未知 SceneScript key 标记 rebuild | 下一 target 必须同批增加 compiler mapping、稳定 identity、snapshot consumer 和 fallback；新增接线补 fresh runtime/ROI 前保持 `S2` |
| target scope and invalidation domain | direct text 使用 per-layer generation；alpha/color/effect scalar 为 value-only；mixed/hidden/no-consumer 统一 rebuild | topology/provider/simulation target 逐类登记失效域 |
| evaluation transaction | property、Timeline与bounded text/time-of-day/fade evaluation、validation、atomic commit已执行；fade scene state及 `311115e3` 的 shared/audio/property projection 在 surface loop 外求值，hover/click 则在每 surface hit-test 后进入最终 transaction | generic events/mutation依固定顺序接入同一transaction；live media provider另立生命周期门；新接线补 fresh 可见证据 |
| immutable snapshot and generation | 每surface独立snapshot/generation；相同payload不增generation；bounded shared alpha、audio-scaled value、QuickJS Vec3、identity display与media playback/colors/title/artist合并进现役carrier；scalar/Vec3 callback共用per-scene VM generation与typed immutable user-property snapshot | 双屏local input、generic handle/event、live media provider加入后继续验证不串用；当前单surface Vec3正证不证明多屏或其他carrier可见结果 |

目标运行形态必须是：

```text
HostFrameInputs(time, properties, audio, media)
  -> SurfaceFrameContext(viewport, pointer, matrices, providers)
  -> Surface EvaluationTransaction
  -> SurfaceDynamicSnapshot
```

B0 live-property 已由 `1762743` 扩展到 direct text content/point-size/color，并用 per-layer generation/stale cancellation/last-ready fallback 消费同一 snapshot。`2134765860` 证明三字段更新不替换 surface/window；默认隐藏文本第一次会因无活动 consumer 被拒绝，只有作者属性先启用 Custom 模式后才 live。`32e3a928` 又把已准入的 root particle direct User Property 八字段注册为活动 consumer，并在相同 surface/window 内发布 typed snapshot。property→Vec3、audio与media carriers已迁入共享QuickJS owner并分别取得bounded真实consumer证据；shared alpha、identity display仍保持`S2 / visible unknown`。particle script/conflict/direct color/child、live media producer、container、mixed、unsupported或无活动consumer的key仍重建或失败关闭。

<a id="d4"></a>
### D4 Input snapshots and event queues

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| pointer position/buttons/events | view-normalized→scene world/layer local position、ordered primary-button edge、inside-hit move与bounded click/hover已进入共享QuickJS cursor owner并有fresh real-consumer/visible证据 | 多按钮、drag-out/capture move、parent/rotated/puppet hit、跨layer传播、multi-surface与官方对照仍缺 |
| audio 16 stereo bins | `L3` | 已闭合：injectable producer、按 consumer 存在性注册、无消费者停采集并归零 |
| audio 32/64 stereo bins | `L3 bounded` | 与16档由同次FFT生成；普通/Workshop Effect、Particle与bounded QuickJS `AudioBuffers` consumers复用同一snapshot/demand。B21已删除两个fixed native property-script 64-band consumer |
| media state/properties/timeline/thumbnail | current thumbnail provider为`L3 bounded`；playback、properties与five-color thumbnail generation已有共享QuickJS event owner及fresh real-consumer证据 | 保留current `$mediaThumbnail` generation/cancel/last-ready/fallback；继续补live producer、status/album/timeline、单次ImageIO抢占、previous/transition、跨类型全局顺序与官方对照 |
| user/general/animation events | `L0` | per-screen queue、owner isolation、异常隔离 |

<a id="d5"></a>
### D5 Texture, media and provider registry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| provider identity/status/generation/fallback | bounded layer/named/property consumer保持`L3`；R3 generic carrier为`L2`：`SceneFrameTextureIdentity`精确区分layer/named/graph/asset/property/system，publication atom同时保存request identity、candidate与content generation，immutable frame snapshot冻结frame index并区分ready/incomplete/absent/pending/unavailable与missing。candidate的identity/generation/purpose/content、physical/mapped、UV、sampler raw flags必须同代；stale、mismatch与半publication拒绝。bounded nested/effectful hidden-image provider把graph final blit到已预留、不同object且同extent/format/usage的named target，再沿现有registry发布，避免graph pool复用造成alias。既有direct text/video/media生命周期不变 | live system media、transition/variant、其余provider主动取消、device loss、多surface/teardown，以及child/non-image/multi-dependency或带history/resize的nested producer |
| candidate selection | 现役 bounded consumer 与 Template 都按 material/instance/graph/user/system 低到高保留 provenance；固定 `0...7` 槽及 hole 不压缩。只有选中 override 的 exact provider state 为显式 `absent` 才允许较低优先级作者候选；missing/pending/unavailable/incomplete/identity mismatch、错 publication/generation 或未证 purpose 均失败关闭。`material` annotation 只作为 lookup key，numeric format、channel、`normalmap` 字样、文件名、effect/sample identity和任意 path pattern 都不能推断 purpose；只有由官方公开语义或合法 clean-room stock metadata 逐项支撑的 exact stock identity 才能进入 closed registry。新增 shared ordinal-aware fact 只允许未登记的高优先级 `.instance` asset 从同槽全部低 ordinal `.material` asset candidates 的唯一一致 exact registry purpose 继承；untyped/conflicting lower、registered high conflict、graph/provider/user/intervening、wrong provenance/order 均拒绝，`particle/normal_pinch_rotate` 本身没有 registry entry。Catalog demand、launch envelope/reference 与 frame/Program selection 共用该事实，并原子保存 selected reference、exact/semantic identity、purpose 与 publication/generation。implicit graph-input projection 仍只在 slot 0 无 material/default/candidate，且其余 active sampler 均有显式非 graph authored candidate时识别 previous/current；named layer target仍由compositor publication合同固定为`.premultipliedColor`。真实 `3749463715:533` effect0现为ordinary Program且GraphExecutor local fallback为0，见[E-V1-SLOT-CHAIN-TEXTURE-PURPOSE](runtime-evidence-index.md#e-v1-slot-chain-texture-purpose) | 继续按版本化证据逐项扩 exact stock registry；未证 single asset purpose、secondary/child/non-image/multi-dependency provider、其他 stock placeholder、动态 generation 与更多 format/mode；不得把 slot-chain 继承扩成 path/channel/shader-use 推断或宽泛 texture-binding fallback |
| upload/cancel/teardown | PNG/JPEG property子集；bounded `.lookupTable` volume以独立purpose上传`rgba8Unorm` Metal `type3D`，普通2D route拒绝volume；embedded video有按帧publication、pause/rebuild/stop状态合同和临时文件清理；current media cover有串行最长边256 decode、旧request协作取消、requested-generation stale completion拒绝、pending last-ready与clear/decode-failure最终fallback。B20不再decode/publish previous，也无per-surface transition | LUT consumer/sampling/color-space、volume cache/lifecycle；单次ImageIO调用不可抢占；device loss、live producer start/pause/stop、多surface/hot-plug、budget与真实lifecycle门 |

<a id="d6"></a>
### D6 Render-target graph and resource lifetime

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| ordered nodes、target/bind/compose/copy/swap | 通用 IR/runtime `L2`；strict backend 已按作者顺序消费 target table，真实 chain 覆盖 `Blur Precise -> Shadow`、Blur/Shake 双向顺序、Foliage Sway/Water Ripple、重复 Water Waves、`Water Flow -> Opacity`、composition `Clipping Mask -> static Opacity`、pair-only exact X-Ray 与 `[Blur Precise, God Rays]`；exact Cursor Ripple 另以 strict history topology 进入统一 GraphExecutor。God Rays 双 half RT 让混合链预算按 target extent 折算，Precise Blur 的 `material -> copy/swap -> material` 两种白名单拓扑仍按 authored nodeIndex 交错执行；所有已声明 target 的 preflight 现与 allocation 共用完整 extent resolver，缺失声明按整张补足、非法 extent 直接拒绝 | generic history/compose/condition/function、跨帧 logical swap、其他 X-Ray/Cursor topology 与通用 hazard；bounded consumer 不外推 family |
| extent/format/clear/UV/unique | `width`/`height`/`fit`/`scale` 分别保真并可组合，公共 resolver 依次执行单轴/双轴 override、fit 不放大、scale divisor、floor/min-1；单轴、absolute、`scale<1` 和 composed area 均进入 2048² reference budget，非法/非有限/`<=0` 失败关闭。strict Blur 的 input/BGRA 与 stock Local Contrast 的 scale=4/RGBA target 子集为 `L3`。公共 `r8` Metal-storage target已进入 typed plan、1 logical B/texel预算、`.r8Unorm` allocation/lease、format-aware history账本与exact-format resource clear/copy；独立于TEX `authoredFormat`的`.scalarRedUnorm` atom再以typed capability闭合无clear/非unique/无command的单writer、later direct-`.r` consumer、publication与RGBA terminal，`.g`/whole/alias、mixed/empty channel envelope、clear/unique、无consumer、多writer、copy/swap与repeat均在claim前失败关闭。generic table/extent/format家族整体仍为`L2` | 在不放宽现有负门的前提下建立FBO sampler/address identity与`repeat` GPU wrap合同；之后才可把stock Glitter固定256² tile pass、combine pass及可见动态作为完整产品/样本门。`rg88`/`r16f`/`rg1616f`、mapped size、load/store/reset、clear/history/command上的scalar语义继续逐项独立闭合 |
| history/ping-pong、frame-local unique 与 typed signal feedback | exact Cursor Ripple strict topology与普通Motion Blur `material → material → copy → unique history/FBO → material`分别为bounded `L3` consumer；preserved-channel又把actual read-before-write unique、terminal swap pair与ordered feedback分别接入唯一persistent table/lease/publication/generation/rollback链。相反，R8/RG88/R16F/RG1616F中single-writer、无command/clear且writer先于typed later reader的`unique:true` target只需frame-local allocation/publication。新增independent-signal RGBA pair只在same descriptor、unique+透明clear、唯一history→scratch preserving update、唯一signal-compositing terminal consumer和terminal swap同时成立时，把两张target从初始化到publication保持`.independentAlphaSignal`；真实Fluid完整19-node graph现沿同一GraphTargets/GraphExecutor完成GPU、compositor与next-frame | 其他authored topology/consumer、logical swap、不同Scene/provider/format/SceneScript/particle state、seek/discontinuity、device loss、多surface、epoch rollback和memory budget通用门；现有真实运行观察到input extent变化触发allocation reprepare/reseed，但不等于已闭合全部resize语义。nonzero clear、copy、额外reader、wrong composite与冲突identity继续关闭；不得从Fluid这一个bounded topology外推任意`unique:true`、signal graph或视觉parity。见[E-V1-INDEPENDENT-SIGNAL-FEEDBACK](runtime-evidence-index.md#e-v1-independent-signal-feedback) |

<a id="d7"></a>
### D7 Material and shader contract

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| material pass/slot hole/combo/constant/render state | `L3 bounded program execution`：`SceneResolvedMaterialTemplate`固定保存8槽及hole、候选provenance、combo、static/dynamic uniform与typed state；presence combo/default分离。validated frame形成active reflection、publication、uniform与Program identity；launch以完整typed asset状态执行与frame相同的候选优先级，并仅对renderer-owned premultiplied `layerSource`首段复用同一颜色推导；该子集内可预知的frame颜色失败不再取得owner。公共frontend可证明唯一sample、RGB不写、alpha为sampled-alpha乘法链的straight-color形态，也可证明同一layerSource color slot上的bounded whole-RGBA affine邻域滤镜并以独立straight UNorm边界输出。`3768724269:163` Rounded Mask与`3290491250:116` Sharpen都已闭合GPU/publication/compositor/next-frame和固定ROI | 普通`effectOutput`后续stage与internal FBO颜色传播、dynamic provider/user content fixed point、alpha replacement/additive/conditional、多个color slot、component mutation、dynamic division、`alphawriting=default`、arbitrary state/current stock `PerformBlend`及其他未证purpose/color仍缺；不得把单形态或单样本正证外推为generic effect支持 |
| shader source/include/annotation/declaration | ShaderContract v1与source/preprocessor/variant preparation保持；同一active source可编译frontend/reflection并与slot/provider/state/color原子形成Program。官方2.8.42 normal pass证据要求普通annotation default进入player compile map，JSON `require/requireany`只保真为editor关系；sampler presence readiness/format requirement仍为独立resource fixed point，`default + combo`无author binding时toggle保持off。规范optional读取被prepared source裁掉时不形成资源；历史作者source若在toggle off后仍保留active sampler读取，只有窄typed asset default可绑定且不改变toggle，其他情况失败关闭。最终宏值同时驱动`#if/#ifdef/defined`、普通source与variant/prepared identity；缺失所需default、冲突/畸形default和options不匹配拒绝。只有preprocessor后active source实际引用的非sampler uniform进入ABI；built-in `mix/lerp`的独立或有界compound浮点实参及既有乘除链使用typed HLSL分量缩窄，program-scope静态`const`映射为Metal `constant`。声明外、注释独占行的畸形`[COMBO]`只有在root stage存在词法无条件、同名且除坏`options`外所有顶层字段完全相同的合法record时才跳过；附着声明、conditional/conflicting/missing counterpart与其他fatal diagnostic拒绝。uniform-bound loop只接受same-stage唯一`staticExact` producer与有界work budget，不以editor `range/int` clamp/unroll | verified environment provider、更多function/helper/cross-language prelude、完整annotation/editor行为、purpose/state/color、完整GLSL；directive-line annotation、dynamic/ambiguous loop producer和未证compound表达式继续显式关闭 |
| built-in / material uniforms | R3 Program可把host、static exact与typed dynamic value编码进reflection layout；Timeline是数值producer，已证stop/play SceneScript只作为control attachment，不是第二个值源。现役GPU仍只由bounded frontend消费time/pointer/matrix、framebuffer resolution与静态constant子集 | R4 Program GPU upload；per-slot官方resolution/texel单位、audio、effect/local matrices、更多dynamic user/timeline/SceneScript与Windows数值门 |

<a id="d8"></a>
### D8 Coordinate spaces and geometry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| canvas/view/world/layer/effect/particle/control-point spaces | 2D 子集；Program的`g_LayerModelMatrix`现从同帧layer world frame取得，包含现役parent/local动态transform并由`3768724269:163`真实消费 | geometry-size/pivot与layer model的完整组合、其他effect/view矩阵、mapped UV、3D handedness及Windows逐值golden |
| cover/crop/extent/aspect | cover 子集 `L3` | 多比例、多屏、Retina、oversized image 和 Windows golden |
| mask/flow/normal/local region | effect-specific 子集；exact Shake 已消费 RG8 flow、可选 R8 phase/white fallback 与映射 UV；Water Flow flow、Standard Blur mask、bounded REFRACT normal 与 exact legacy Blend overlay 已从 typed candidate 消费 axis-aligned mapped UV。Blend 同时消费作者 filter/address sampler，repeatWrap 不再被 shader 预先 clamp；Water Flow phase 与 plain base 仍只接受 identity | 不得降成整层 transform；其余槽位、phase transform、Shake MASK1/direction/noise、sprite rotation、clamp-border、每种坐标和 sampler 独立验证 |

## 3. 消费层

<a id="d9"></a>
### D9 Generic 2D execution layer

这一层只消费 `D0-D8` 的统一合同：base layer compositor、Material Program、graph/target executor、particle geometry/material 和 text/provider output。现役产品已收敛为 typed VFS/preparation → admission/Program/resource → GraphExecutor → compositor；旧 whole-chain、standalone、frame-batch 和 planner authority 已退役并由稳定零门保护。当前主要缺口不是再删旧 owner，而是普通 authored stage 仍只能依赖 bounded/dedicated backend，mixed chain 的未知 stage 仍可能扩大成整链或后续 layer suffix 失败。

V0/V1 在这层只做两件事：让 ordinary authored Program 成为默认候选；把失败收窄到 effect/pass/真实依赖子图并保留 previous current。既有 bounded backend 只作显式 fallback/oracle，不能替代 generic material/pass executor，也不能升级 Shadow、lighting 或动态 variant。若某项需要在 renderer 内重新解析 JSON、猜 sample/effect 身份、重算属性优先级或保存私有 history，说明共享 D 层仍有缺口，应回到对应 producer/contract 修复。

<a id="d10"></a>
### D10 System runtimes

| Runtime | 前置依赖 | 最小闭环 |
|---|---|---|
| Timeline | D2 + D3 | lossless IR、绝对 scene-time evaluator、bounded 作者 Bézier handles、Loop wrap 闭合段与 typed writes 已完成，现役 Workshop **48/48 authored host** 均形成 typed binding：effect constant 23、layer alpha 5、bounded relative layer transform 9、root particle scalar override 7、bounded text `maxwidth` 2，以及唯一 default 2D camera Combined `origin↔zoom` 两成员；实际视觉执行还需对应 renderer/chain 准入，`3769688830:157` 已闭合首条 Tint alpha Timeline consumer。普通段消费 `start.front` / `end.back`，9 条 wrap 声明的末/首段消费末 `front` / 首 `back`；均按 segment-normalized X/property-offset Y 求值，双禁用严格线性，越出周期或 bounded target control hull 的形态失败关闭。camera 两成员共用 owner clock，经同一 per-surface transaction 原子写入 projection、particle camera 与 pointer projection。multiple path、3D/未知 camera、坏组、generic Combined、event crossing、particle relative/colorn/child/存量追溯仍待推进；handle/wrap 单位无 Windows wire/golden |
| Exact native property-script profiles | D0 + D4 + D7 + D8 + D9 | Text七个fixed profile已在B18退役；Audio Bars两个fixed profile又在B21退役。source identity不再为两族建立产品binding，旧报告只作历史 |
| Bounded property-bound text update | D2 + D3 + D4 + D5 + D9 | B18后唯一现役Text脚本合同：唯一`update(value)`的无循环Date/string AST以语法和三层预算准入，复用typed snapshot/dynamic text consumer；无sample/layer/hash旁路。`clockWithPeriod`、greeting等未准入语法保留authored fallback，且该子集不等于VM |
| Bounded media placeholder fade | D2 + D3 + D4 + D5 + D7 + D8 + D9 | 旧strict AST owner已由共享QuickJS scalar `mediaPlaybackChanged` owner取代并删除；event-before-update、typed mutation、Opacity Program/GraphExecutor/compositor与真实执行证据保留。产品仍无live media ingress，反向脚本、跨类型全局顺序及完整media API继续关闭 |
| Generic SceneScript | D2 + D3 + D4 + D5 | 单一QuickJS-NG scene domain已执行bounded scalar/String/Vec2/Vec3 owner、typed handles、cursor/media/audio callback、jobs/timers、dynamic layer mutation与destroy，旧重叠native owner按证据撤权。继续扩bool/Vec4/matrix、完整module/shared/reload/host API、通用事件传播及官方对照 |
| dynamic text | D3 + D5 + D9 | direct property、String/point-size SceneScript与bounded Timeline width已完成per-layer generation、stale cancellation、单在途合并和last-ready；fixed native Text profile已退役，system media、更多script target、长文本/多屏压力与Windows layout fidelity仍待推进 |
| particle breadth | D2 + D3 + D4 + D5 + D8 + D9 | root direct User Property 八字段和 absolute scalar Timeline 七字段已复用统一 binding compiler、per-surface transaction/snapshot 与 fixed-step simulator；静态 plain-image Layer Image 已复用 typed dependency/texture/simulator；Position Offset Random、initial delay、仅 rate Random periodic、one-per-render-frame、emitter CP identity/static angles/speed/shape、raw parent CP copy、pointer-lock CP Force、uniform child scale、classic Vortex、Cap Velocity、Sprite Trail、Rope 继续各有 bounded 门。`968d86eb` 在 initializer typed plan/fixed-step creation stream 上复用项目 3D gradient-noise 基元，只为已确认五字段开放 finite-octave position offset；`594e52c4` 让 raw bit 2 的每个 emitter 在同一 render advance 的全部 fixed steps 共享一个 rate 配额；`5cc7ee37` 又复用 D4/D5 host audio snapshot、consumer demand 与 fixed-step simulator，建立共享 16-band evaluator，并只为 root Sphere/Box rate emitter、Turbulent Velocity Random/Turbulence phase、底层已合法的 classic Vortex speed 开放 consumer。Position Offset `sign`、官方 default/FBM/RNG/space/time、dynamic override 的 script/conflict/direct color/relative/Combined/child/存量追溯、复杂 emitter/child/其他 operator audio、child 非零 angles/event offset/nonuniform or nested scale、one-per-frame Windows 30/60/120 FPS count/Rope topology、initial-delay Windows timing golden、periodic burst/max-per-period、动态/text/puppet Layer Image、dynamic control point angle/adjusted/world/cross-space、previous pointer 与其他 consumer、event/nested CP copy、force falloff、Vortex CP/center-force/`vortex_v2` ring、Rope animated texture/root-world/multi-renderer/ribbon join、通用 RopeTrail subdivision/UV、collision，以及各项 WE 数值/RNG/分布/轨迹 golden 仍待闭合 |
| audio/media | D4 + D5 | audio侧已闭合consumer-driven 16/32/64 host input及bounded effect/Particle/QuickJS consumers；embedded MP4与current cover provider保持bounded，playback/properties/five-color thumbnail已进入共享QuickJS event owner。Sound、其余particle audio、live producer、完整event ordering、metadata/status/timeline、单次decode抢占、多surface/hot-plug与previous/transition仍未闭合 |

Particle breadth 的最新 bounded HSV Color Random 子集由 `9058a8b3` 在既有 definition/parser/fixed-step initializer stream 上闭合，不新增依赖节点：只准七个显式 direct-number wire、normalized ordered HSV ranges 与 `1...1024` hue steps，创建时按 authored order 执行项目自有离散 hue、连续 saturation/value 与 HSV→RGB 近似；有效 instance color override 冲突、官方 default/instance-color 依赖、Windows RNG/端点/色彩空间/pixel golden 继续失败关闭。该子集不改变 dynamic override、child、Control Point、Collision、renderer 或 D11 fidelity 的前置关系。

Particle breadth 的 bounded Color List 子集由 `dbd0f13e` 在既有 definition/parser/fixed-step simulator 上闭合，不新增依赖节点：只准 1...10 个 finite normalized RGB vector3 与 list-only shape，创建时均匀选择并保留 authored initializer order；Color List 自身的 HSV/noise 扩展、extended shape 与 Windows RNG/分布/pixel golden 继续失败关闭。该子集不改变 dynamic override、child、Control Point、Collision 或 renderer 的前置关系。

Particle breadth 的 bounded Position Offset Random 子集由 `968d86eb` 在同一 initializer stream、seed/time context 与项目 noise 基元上闭合，也不新增依赖节点：五个已确认 wire 进入 bounded typed plan，未确认 `sign` 与其他扩展保持 fail closed。它不改变 dynamic override、child、Control Point、Collision、renderer 或坐标空间的前置关系；官方 default/FBM/RNG/space/time 和 Windows trajectory/pixel golden 仍属于 D11 fidelity 门。

<a id="d11"></a>
### D11 Fidelity and advanced runtimes

Puppet、lighting/HDR、3D、RGB 和 offline 复用 D0-D10。Puppet 已有严格单 clip 与 bind-referenced/disjoint-bone additive clips 的 fixed-step CPU LBS 子集，typed animation visibility 复用 D2/D4 snapshot；它仍必须复用统一 frame context、geometry、texture lifetime 和 fail-closed 路由，不代表冲突 animation mixing/权重、动态 attachment 或完整高级对象支持。其他系统在 light/shader/fixed-time consumer 不存在时必须保持 `L0-L2`，不能用普通 image transform、layer Bloom 或 Debug PNG readback 冒充执行。

## 4. 与现役 V0-V5 路线的关系

历史的 Coverage-first F0-F5 与 G0-G5 排序均已停止作为实施路线。当前段位、先后关系和完成门只见[Scene 兼容执行路线](../scene-compatibility-roadmap.md)；本图不再复述并行或串行落地策略，只检查路线中当前纵向切片实际消费的公共依赖。

本页 D0-D11 只用于检查每个 V 路线切片实际消费的前置，允许在同一可回滚批次中跨层闭合。不得要求一个 D 层所有专项条目完成后才开始下游通用执行，也不得从当前表格的 bounded 状态反推新的专用 owner。

| 路线 | 主要 D 节点 | 首要产品结果 |
|---|---|---|
| V0 | D0/D3/D5/D7/D9 的最小已消费子集 | 普通 authored material/shader 经过通用 backend、Program、GraphExecutor 与 compositor 首次出画面 |
| V1 | D1/D5/D6/D7/D9 | ordered pass、FBO、copy/swap/compose、history、named/cross-layer graph |
| V2 | D2/D3/D4/D10 | 真正 ECMAScript VM、host bridge、typed mutation 与生命周期隔离 |
| V3 | D1/D2/D3/D5/D8/D10 | 粒子 component registry/interpreter 与共享 operation stream |
| V4 | D2-D5/D8-D10 | properties、pointer、audio、media、text 与 provider 贯穿式补齐 |
| V5 | D8/D11 | Puppet、lighting/HDR、3D、RGB、offline、性能与发行闭合 |

## 5. 禁止的冲突路径

1. 不在各 renderer 内分别计算 user property、Timeline 或 SceneScript 优先级。
2. 不为 Effect、Particle、Video 分别建立互不兼容的时钟、pause 或 fixed-step 语义。
3. 不把 layer/named/effect/history/system/media texture 塞进同一个无作用域字符串 key。
4. definition/material/shader/component/API identity 只选择作者声明、资源或共享 primitive；不用 sample/layer/path/hash 选择样本专用视觉答案。固定 identity 还可用于缓存、publication、provenance、诊断和回归。
5. 不把 effect-local UV 变形写成 object transform，也不把 Camera Parallax 当成所有鼠标交互。
6. 不在没有 shader annotation/slot contract 时自动绑定空白纹理并启用 optional combo。
7. 不在通用 RT lifecycle 之前单独给 Motion Blur、Cursor Ripple 或 Fluid 保存私有 history。
8. 不用普通 composition 代替 scene-background compose、RGB capture 或 nested scene。
9. 不因 parser 能识别字段就升级 executor 等级；不因样本非黑就升级视觉等级。
10. 不让高级对象绕过统一 identity、target、provider、graph、clock 和 teardown 合同。

## 6. 使用顺序

1. 先查[Scene 兼容执行路线](../scene-compatibility-roadmap.md)确定当前 V 目标、首个真实断点和可回滚边界。
2. 查[覆盖台账](coverage-ledger.md)、对应专项表和[运行证据索引](runtime-evidence-index.md)，确认当前 owner、已有正反例和未验证边界；它们提供事实，不决定专用实现方法。
3. 用本图检查本批实际消费的 identity、order、resource、target、budget 和 lifecycle 前置，不为尚未消费的未知项预建 admission。
4. 只实现一个可独立回滚的纵向切片；编码循环用最小 synthetic 正反门和一个真实代表内容，到 checkpoint 再用未见结构组合证明没有样本/path/hash 视觉 dispatch，并验证局部失败不扩大为整场拒绝。
5. 只有能力等级、产品 owner、matrix 合同或现役运行事实变化时才更新相应专项表、总台账和证据索引；微小内部改动不做全库文档同步。
