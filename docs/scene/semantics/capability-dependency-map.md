# Scene 公共能力依赖图与实施门

> 状态：现役架构入口
>
> 最近核对：2026-08-09
>
> 本页只维护依赖与完成门；精确当前提交、报告和测试总数统一见 [总覆盖台账](coverage-ledger.md) 与 [运行证据索引](runtime-evidence-index.md)。
>
> 目的：先补公共底座，再扩 Effect、Particle、Text、Timeline、SceneScript 和高级对象；禁止为单个样本建立旁路。

本文把 [总覆盖台账](coverage-ledger.md) 和各专项表中的能力整理成依赖图。它不改变任何能力等级，只回答“哪一层必须先稳定，后面的实现才不会反向推翻前面”。

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
| named/effect/history target identity | `_a` 子集 `L3`、`_b` `L2`、history `L0` | primary/secondary/history 不混用，resize/switch/reset 可测 |

<a id="d2"></a>
### D2 Host/surface frame context and lifecycle

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| host/frame/scene/wall time | `L3` 子集；共享 clock 发布 raw、最大 0.25 秒的 simulation、dropped delta/discontinuity；particle/parallax 消费 simulation，shader/video/Timeline 保持 raw/absolute time；pause 冻结 scene time/frame index，resume 首帧丢弃 host gap | 真实系统 pause/sleep、seek/history、其他 simulation consumer、目标/不同 FPS、离线与 Windows timing 门 |
| host-shared vs surface-local scope | property 输入 host-shared；每个 surface 独立 transaction/snapshot/generation，B0 live alpha/solid color/strict Local Contrast strength 与 root particle direct User Property 已有运行门 | pointer/matrix/provider/script 接入时继续证明 local state 不串屏 |
| fixed simulation step and seed policy | particle fixed step 已消费共享 simulation delta，并保留自身 deterministic seed | effect/script/offline 共用 discontinuity、fixed-clock 和 seed 合同 |
| resize/switch/stop teardown | surface 子集 `L3`；embedded video registry 为 launch-scoped，按 layer/source/device 跨 surface rebuild 复用并在 stop 释放 | VM、system/media provider、RT 与 GPU 资源精确计数；真实 hot-plug/反复切换 soak |

<a id="d3"></a>
### D3 Typed values, binding program and per-surface evaluation

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| value types and target definitions | 六类 value 与主要 target 由 v22 持久化；direct text、strict Local Contrast/Opacity 与 bounded Blend multiply 已注册 typed target | 新类型继续执行 type/finite/default validation；SceneScript 计算值不冒充 direct binding |
| source priority | `authored -> property -> Timeline -> SceneScript` 已定义；property、受限 Timeline 与 bounded text/time-of-day producer 已复用同一 resolver | generic SceneScript/event mutation 接入时不得在 renderer 内重复求值 |
| binding program | layer alpha/solid color、direct text、Local Contrast/Opacity 与 bounded Blend multiply 编译、验证和持久化已完成；mixed/invalid/未知 SceneScript key 标记 rebuild | 下一 target 必须同批增加 compiler mapping、稳定 identity、snapshot consumer 和 fallback |
| target scope and invalidation domain | direct text 使用 per-layer generation；alpha/color/effect scalar 为 value-only；mixed/hidden/no-consumer 统一 rebuild | topology/provider/simulation target 逐类登记失效域 |
| evaluation transaction | property、Timeline 与 bounded text/time-of-day SceneScript evaluation、validation、atomic commit 已按 surface 执行 | generic events/mutation 依固定顺序接入同一 transaction |
| immutable snapshot and generation | 每 surface 独立 snapshot/generation；相同 payload 不增 generation | 双屏 local input、script/provider 加入后继续验证不串用 |

目标运行形态必须是：

```text
HostFrameInputs(time, properties, audio, media)
  -> SurfaceFrameContext(viewport, pointer, matrices, providers)
  -> Surface EvaluationTransaction
  -> SurfaceDynamicSnapshot
```

B0 live-property 已由 `1762743` 扩展到 direct text content/point-size/color，并用 per-layer generation/stale cancellation/last-ready fallback 消费同一 snapshot。`2134765860` 证明三字段更新不替换 surface/window；默认隐藏文本第一次会因无活动 consumer 被拒绝，只有作者属性先启用 Custom 模式后才 live。`32e3a928` 又把已准入的 root particle direct User Property 八字段注册为活动 consumer，并在相同 surface/window 内发布 typed snapshot；particle 的 script/conflict/direct color/child 等未准入形态，以及 time/media、container、mixed、unsupported 或无活动 consumer 的 key 继续整场重建。

<a id="d4"></a>
### D4 Input snapshots and event queues

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| pointer position/buttons/events | position 极窄子集 | world/layer/effect local 变换、button queue、同帧顺序 |
| audio 16 stereo bins | `L3` | 已闭合：injectable producer、按 consumer 存在性注册、无消费者停采集并归零 |
| audio 32/64 stereo bins | `L3 bounded` | 与16档由同次FFT生成；普通/Workshop Effect Audio Bars的现役Program/typed consumer继续消费。B21已删除两个fixed native property-script 64-band consumer，generic SceneScript bridge仍为`L0` |
| media state/properties/timeline/thumbnail | current thumbnail `L3 bounded`；previous/transition及其他media state/property/timeline `L0` | current `$mediaThumbnail` generation、旧request协作取消、replacement pending last-ready、clear/decode-failure作者fallback与strict Blend/visibility consumer保留；B20已删除previous identity/publication和fixed transition。仍缺单次ImageIO调用抢占、通用事件队列、metadata/status/timeline snapshot与live producer |
| user/general/animation events | `L0` | per-screen queue、owner isolation、异常隔离 |

<a id="d5"></a>
### D5 Texture, media and provider registry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| provider identity/status/generation/fallback | bounded layer/named/property consumer保持`L3`；R3 generic carrier为`L2`：`SceneFrameTextureIdentity`精确区分layer/named/graph/asset/property/system，publication atom同时保存request identity、candidate与content generation，immutable frame snapshot冻结frame index并区分ready/incomplete/absent/pending/unavailable与missing。candidate的identity/generation/purpose/content、physical/mapped、UV、sampler raw flags必须同代；stale、mismatch与半publication拒绝。既有direct text/video/media生命周期不变，launch VFS catalog只发布purpose-proven static asset；system demand冲突或lifecycle未证时为unavailable，不伪造absent | graph FBO/effectOutput在command边界的publication、live system media、transition/variant、其余provider主动取消、device loss、多surface/teardown与nested/effectful/child producer |
| candidate selection | 现役 bounded consumer 与 Template 都按 material/instance/graph/user/system 低到高保留 provenance；固定 `0...7` 槽及 hole 不压缩。只有选中 override 的 exact provider state 为显式 `absent` 才允许较低优先级作者候选；missing/pending/unavailable/incomplete/identity mismatch 或未证 purpose 均失败关闭。`material` annotation 只作为 lookup key，numeric format、`normalmap` 字样、文件名和任意 path pattern 都不能推断 purpose；只有由官方公开语义或合法 clean-room stock metadata 逐项支撑的 exact stock identity 才能进入 closed registry，当前只登记 `util/noise -> .noise`。显式 mode/material purpose 与 registry 冲突时返回 unproven，不按 effect/sample/layer/path hash 选择算法。Program 把最终 candidate metadata、active variant/reflection 与 snapshot 同代原子化 | 继续按版本化证据逐项扩 exact stock registry；未证 regular asset purpose、effectful/nested/child provider、其他 stock placeholder、动态 generation 与更多 format/mode |
| upload/cancel/teardown | PNG/JPEG property子集；bounded `.lookupTable` volume以独立purpose上传`rgba8Unorm` Metal `type3D`，普通2D route拒绝volume；embedded video有按帧publication、pause/rebuild/stop状态合同和临时文件清理；current media cover有串行最长边256 decode、旧request协作取消、requested-generation stale completion拒绝、pending last-ready与clear/decode-failure最终fallback。B20不再decode/publish previous，也无per-surface transition | LUT consumer/sampling/color-space、volume cache/lifecycle；单次ImageIO调用不可抢占；device loss、live producer start/pause/stop、多surface/hot-plug、budget与真实lifecycle门 |

<a id="d6"></a>
### D6 Render-target graph and resource lifetime

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| ordered nodes、target/bind/compose/copy/swap | 通用 IR/runtime `L2`；十四类 strict backend 已按作者顺序消费 target table，真实 chain 覆盖 `Blur Precise -> Shadow`、Blur/Shake 双向顺序、Foliage Sway/Water Ripple、重复 Water Waves、`Water Flow -> Opacity`、composition `Clipping Mask -> static Opacity`、X-Ray 受限前缀与 `[Blur Precise, God Rays]`；God Rays 双 half RT 让混合链预算按 target extent 折算，Precise Blur 的 `material -> copy/swap -> material` 两种白名单拓扑仍按 authored nodeIndex 交错执行；所有已声明 target 的 preflight 现与 allocation 共用完整 extent resolver，缺失声明按整张补足、非法 extent 直接拒绝 | 真实 history consumer、generic compose/condition/function、跨帧 logical swap 与通用 hazard |
| extent/format/clear/UV/unique | `width`/`height`/`fit`/`scale` 分别保真并可组合，公共 resolver 依次执行单轴/双轴 override、fit 不放大、scale divisor、floor/min-1；单轴、absolute、`scale<1` 和 composed area 均进入 2048² reference budget，非法/非有限/`<=0` 失败关闭。strict Blur 的 input/BGRA 与 stock Local Contrast 的 scale=4/RGBA target 子集为 `L3`。公共 `r8` Metal-storage target基础已进入 typed plan、1 logical B/texel 预算、`.r8Unorm` table/persistent allocation/lease、format-aware history 账本与 exact-format resource clear/copy；Program attachment 与 graph publication 因尚无 single-channel/purpose/channel-layout 合同而显式失败关闭，generic table/extent/format 家族整体仍为 `L2` | 为R8建立独立于TEX `authoredFormat`的graph storage/content/channel语义，并闭合producer、Program attachment/publication、red-only consumer与错误通道负门；其后再处理`rg88`/`r16f`/`rg1616f`、mapped size、FBO sampler/repeat、load/store/reset及Glitter两个pass的产品/可见闭环 |
| history/ping-pong | `L0` | first frame、resize、seek、switch、stop 和 memory budget |

<a id="d7"></a>
### D7 Material and shader contract

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| material pass/slot hole/combo/constant/render state | `L3 bounded program execution`：`SceneResolvedMaterialTemplate`固定保存8槽及hole、低到高候选provenance、**material显式combo**、static/dynamic uniform与typed state；active shader schema随后按“显式优先，否则所有同名声明给出同一有效default”建立统一macro environment，annotation default不回写Template。一个validated frame/resource/dynamic snapshot再形成active variant/reflection、exact publication、uniform bytes、保守color contract及semantic/exact Program identity。only-explicit-absent fallback与所有unknown fail-closed有门；R4 capability/executor已接管bounded implicit-framebuffer/straight-alpha/dynamic-uniform Program，并让ordinary Opacity、Program-compatible Tint、Film Grain stock/no-mask、stock standalone Blend、Workshop Audio Hue、当前stock Spin及modern `2906937488` Procedural Noise active variants由统一Program执行 | R4 generic state translator/cache与全产品唯一executor；`alphawriting=default`、arbitrary blend/depth/cull/alpha、完整annotation/editor行为、未证purpose/color及command-state publication仍缺；legacy `2924967132`依赖合成近似保持独立边界 |
| shader source/include/annotation/declaration | ShaderContract v1与source/preprocessor/variant preparation保持；同一active source可编译frontend/reflection并与slot/provider/state/color原子形成Program。官方2.8.42 normal pass证据要求annotation default进入player compile map，JSON `require/requireany`只保真为editor关系；sampler readiness/format requirement仍为独立resource fixed point。最终宏值同时驱动`#if/#ifdef/defined`、普通source与variant/prepared identity；缺失所需default、冲突/畸形default和options不匹配拒绝。只有preprocessor后active source实际引用的非sampler uniform进入ABI；built-in `mix/lerp`的独立或有界compound浮点实参及既有乘除链使用typed HLSL分量缩窄，program-scope静态`const`映射为Metal `constant`。声明外、注释独占行的畸形`[COMBO]`只有在root stage存在词法无条件、同名且除坏`options`外所有顶层字段完全相同的合法record时才跳过；附着声明、conditional/conflicting/missing counterpart与其他fatal diagnostic拒绝。uniform-bound loop只接受same-stage唯一`staticExact` producer与有界work budget，不以editor `range/int` clamp/unroll。Film Grain、Light Shafts、Audio Hue与modern Procedural Noise正例分别消费stock/default、alpha-preserving RGB mix、conditional alpha/fixed-point seed/runtime loop等已证子集 | verified environment provider、更多function/helper/cross-language prelude、完整annotation/editor行为、purpose/state/color、完整GLSL与全产品唯一executor；directive-line annotation、dynamic/ambiguous loop producer和未证compound表达式继续显式关闭 |
| built-in / material uniforms | R3 Program可把host、static exact与typed dynamic value编码进reflection layout；Timeline是数值producer，已证stop/play SceneScript只作为control attachment，不是第二个值源。现役GPU仍只由bounded frontend消费time/pointer/matrix、framebuffer resolution与静态constant子集 | R4 Program GPU upload；per-slot官方resolution/texel单位、audio、effect/local matrices、更多dynamic user/timeline/SceneScript与Windows数值门 |

<a id="d8"></a>
### D8 Coordinate spaces and geometry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| canvas/view/world/layer/effect/particle/control-point spaces | 2D 子集 | parent/rotation/scale/parallax inverse、mapped UV、3D handedness |
| cover/crop/extent/aspect | cover 子集 `L3` | 多比例、多屏、Retina、oversized image 和 Windows golden |
| mask/flow/normal/local region | effect-specific 子集；exact Shake 已消费 RG8 flow、可选 R8 phase/white fallback 与映射 UV；Water Flow flow、Standard Blur mask、bounded REFRACT normal 与 exact legacy Blend overlay 已从 typed candidate 消费 axis-aligned mapped UV。Blend 同时消费作者 filter/address sampler，repeatWrap 不再被 shader 预先 clamp；Water Flow phase 与 plain base 仍只接受 identity | 不得降成整层 transform；其余槽位、phase transform、Shake MASK1/direction/noise、sprite rotation、clamp-border、每种坐标和 sampler 独立验证 |

## 3. 消费层

<a id="d9"></a>
### D9 Generic 2D execution layer

这一层只消费 `D0-D8` 的统一合同：base layer compositor、共享 material pass executor、effect profile registry、particle geometry/material、text texture generation。R3 已把 production raw graph、provider snapshot、active variant/reflection、uniform/state/color 收敛为可审计的 `SceneResolvedMaterialProgram`；R4 已让 bounded Program 经统一 executor 取得 GPU/compositor/next-frame 证据，并逐族迁移或撤销旧产品owner。composition子集仍要求每个resolved material含active audio host consumer，并通过显式main-target source route在作者层执行点读取此前已绘制的framebuffer；relocated正例在Program后继续按作者顺序执行strict zero-distortion Fisheye leaf。mixed chain首个active stage必须是resolved，未知形态只能由完整Program/typed adapter接管或整链失败关闭。B22完成R4产品owner撤权，B23删除whole-chain/standalone/frame-batch/旧layer telemetry，B24又删除`fallbackGraph`及`.legacyContract` provenance：缺少typed `sourceGraph`时即`shader-source-graph-missing`，不再从include-free raw contract建立第二条preparation路径；package/loose/stock VFS、include/variant、Program与GraphExecutor保持。现役R5只剩3个diagnostics/disposition observation调用及其他经证明不可达的残留，不能只改名继续可达。提交前仍比较dedicated probes、runtime backends、legacy authority sites、Scene Swift文件/LOC、`<3 KiB`、`<1 KiB`六轴。既有bounded typed backend不替代generic material/pass executor，也不能升级官方Shadow/lighting或动态effect variants。若某项需要在renderer内重新解析JSON、猜effect名称、重新决定属性优先级或自行保存history，说明底座仍有缺口，应回到对应D层修复。

<a id="d10"></a>
### D10 System runtimes

| Runtime | 前置依赖 | 最小闭环 |
|---|---|---|
| Timeline | D2 + D3 | lossless IR、绝对 scene-time evaluator、bounded 作者 Bézier handles、Loop wrap 闭合段与 typed writes 已完成，现役 Workshop **48/48 authored host** 均形成 typed binding：effect constant 23、layer alpha 5、bounded relative layer transform 9、root particle scalar override 7、bounded text `maxwidth` 2，以及唯一 default 2D camera Combined `origin↔zoom` 两成员；实际视觉执行还需对应 renderer/chain 准入，`3769688830:157` 已闭合首条 Tint alpha Timeline consumer。普通段消费 `start.front` / `end.back`，9 条 wrap 声明的末/首段消费末 `front` / 首 `back`；均按 segment-normalized X/property-offset Y 求值，双禁用严格线性，越出周期或 bounded target control hull 的形态失败关闭。camera 两成员共用 owner clock，经同一 per-surface transaction 原子写入 projection、particle camera 与 pointer projection。multiple path、3D/未知 camera、坏组、generic Combined、event crossing、particle relative/colorn/child/存量追溯仍待推进；handle/wrap 单位无 Windows wire/golden |
| Exact native property-script profiles | D0 + D4 + D7 + D8 + D9 | Text七个fixed profile已在B18退役；Audio Bars两个fixed profile又在B21退役。source identity不再为两族建立产品binding，旧报告只作历史 |
| Bounded property-bound text update | D2 + D3 + D4 + D5 + D9 | B18后唯一现役Text脚本合同：唯一`update(value)`的无循环Date/string AST以语法和三层预算准入，复用typed snapshot/dynamic text consumer；无sample/layer/hash旁路。`clockWithPeriod`、greeting等未准入语法保留authored fallback，且该子集不等于VM |
| Generic SceneScript | D2 + D3 + D4 + D5 | 顶层 layer wrapper partial IR 与 bounded String update 子集已有；仍需 generic source/module/value IR、sandbox VM、lifecycle、typed handles/writes、events及 VM 级时间/内存预算 |
| dynamic text | D3 + D5 + D9 | direct property、bounded text update与bounded Timeline width已完成per-layer generation、并发stale cancellation、单在途连续更新合并和last-ready；fixed native Text profile已退役，system/media producer、非String script target、长文本/多屏压力与Windows layout fidelity仍待推进 |
| particle breadth | D2 + D3 + D4 + D5 + D8 + D9 | root direct User Property 八字段和 absolute scalar Timeline 七字段已复用统一 binding compiler、per-surface transaction/snapshot 与 fixed-step simulator；静态 plain-image Layer Image 已复用 typed dependency/texture/simulator；Position Offset Random、initial delay、仅 rate Random periodic、one-per-render-frame、emitter CP identity/static angles/speed/shape、raw parent CP copy、pointer-lock CP Force、uniform child scale、classic Vortex、Cap Velocity、Sprite Trail、Rope 继续各有 bounded 门。`968d86eb` 在 initializer typed plan/fixed-step creation stream 上复用项目 3D gradient-noise 基元，只为已确认五字段开放 finite-octave position offset；`594e52c4` 让 raw bit 2 的每个 emitter 在同一 render advance 的全部 fixed steps 共享一个 rate 配额；`5cc7ee37` 又复用 D4/D5 host audio snapshot、consumer demand 与 fixed-step simulator，建立共享 16-band evaluator，并只为 root Sphere/Box rate emitter、Turbulent Velocity Random/Turbulence phase、底层已合法的 classic Vortex speed 开放 consumer。Position Offset `sign`、官方 default/FBM/RNG/space/time、dynamic override 的 script/conflict/direct color/relative/Combined/child/存量追溯、复杂 emitter/child/其他 operator audio、child 非零 angles/event offset/nonuniform or nested scale、one-per-frame Windows 30/60/120 FPS count/Rope topology、initial-delay Windows timing golden、periodic burst/max-per-period、动态/text/puppet Layer Image、dynamic control point angle/adjusted/world/cross-space、previous pointer 与其他 consumer、event/nested CP copy、force falloff、Vortex CP/center-force/`vortex_v2` ring、Rope animated texture/root-world/multi-renderer/ribbon join、通用 RopeTrail subdivision/UV、collision，以及各项 WE 数值/RNG/分布/轨迹 golden 仍待闭合 |
| audio/media | D4 + D5 | audio侧已闭合consumer-driven 16/32/64 host input、普通/Workshop effect consumers与bounded Particle 16-band consumers；两个fixed native 64-band SceneScript consumers已于B21退役。embedded MP4 image-layer已有受限SceneClock/provider generation/lifecycle；current cover generation、replacement pending last-ready、clear/decode-failure fallback与strict current Blend/visibility consumer保持bounded，previous/transition已于B20退役。通用SceneScript bridge/Sound、其余particle audio、live system media producer、event ordering、metadata/status/timeline、单次decode抢占、多surface/hot-plug与previous/transition仍未闭合 |

Particle breadth 的最新 bounded HSV Color Random 子集由 `9058a8b3` 在既有 definition/parser/fixed-step initializer stream 上闭合，不新增依赖节点：只准七个显式 direct-number wire、normalized ordered HSV ranges 与 `1...1024` hue steps，创建时按 authored order 执行项目自有离散 hue、连续 saturation/value 与 HSV→RGB 近似；有效 instance color override 冲突、官方 default/instance-color 依赖、Windows RNG/端点/色彩空间/pixel golden 继续失败关闭。该子集不改变 dynamic override、child、Control Point、Collision、renderer 或 D11 fidelity 的前置关系。

Particle breadth 的 bounded Color List 子集由 `dbd0f13e` 在既有 definition/parser/fixed-step simulator 上闭合，不新增依赖节点：只准 1...10 个 finite normalized RGB vector3 与 list-only shape，创建时均匀选择并保留 authored initializer order；Color List 自身的 HSV/noise 扩展、extended shape 与 Windows RNG/分布/pixel golden 继续失败关闭。该子集不改变 dynamic override、child、Control Point、Collision 或 renderer 的前置关系。

Particle breadth 的 bounded Position Offset Random 子集由 `968d86eb` 在同一 initializer stream、seed/time context 与项目 noise 基元上闭合，也不新增依赖节点：五个已确认 wire 进入 bounded typed plan，未确认 `sign` 与其他扩展保持 fail closed。它不改变 dynamic override、child、Control Point、Collision、renderer 或坐标空间的前置关系；官方 default/FBM/RNG/space/time 和 Windows trajectory/pixel golden 仍属于 D11 fidelity 门。

<a id="d11"></a>
### D11 Fidelity and advanced runtimes

Puppet、lighting/HDR、3D、RGB 和 offline 复用 D0-D10。Puppet 已有严格单 clip 与 bind-referenced/disjoint-bone additive clips 的 fixed-step CPU LBS 子集，typed animation visibility 复用 D2/D4 snapshot；它仍必须复用统一 frame context、geometry、texture lifetime 和 fail-closed 路由，不代表冲突 animation mixing/权重、动态 attachment 或完整高级对象支持。其他系统在 light/shader/fixed-time consumer 不存在时必须保持 `L0-L2`，不能用普通 image transform、layer Bloom 或 Debug PNG readback 冒充执行。

## 4. Coverage-first 实施波次

| 波次 | 内容 | 退出门 |
|---|---|---|
| F0 语义治理 | 179 页面、45 Effect、Particle、SceneScript、Graph/Shader、输入、对象和平台表 | 每项有唯一落点、单值等级、依赖、未知项和验收门 |
| F1 身份与输入底座 | D1-D5 | 稳定 wire schema、binding program、source IR、provider generation、pause/stop |
| F2 通用执行底座 | D6-D9 | scheduler、RT lifetime、material/shader contract、坐标空间和 fail-closed profile registry |
| F3 常用能力广度 | Timeline、dynamic text、Particle、45 Effect family、audio/media | 每族至少一个完整正向、作者关闭、失败、lifecycle 和真实样本门 |
| F4 视觉精度 | 高频样本、样本封面方向性门与 Windows golden | `3194ac5` 已生成 preview reference、中心裁切截图、分项指标和并排图；只允许同一样本跨提交比较并人工复核。Windows golden 再验证局部区域、字体、颜色/alpha、时序和像素阈值 |
| F5 高级能力 | SceneScript breadth、Puppet、HDR/light、3D、RGB、offline | 各系统独立 IR/runtime/lifecycle/product gate |

F0 完成后才开始下一轮代码。F1/F2 优先级由公共依赖决定，不按单个样本的视觉显眼程度决定；F3 先做广度，再进入 F4 精调。

## 5. 禁止的冲突路径

1. 不在各 renderer 内分别计算 user property、Timeline 或 SceneScript 优先级。
2. 不为 Effect、Particle、Video 分别建立互不兼容的时钟、pause 或 fixed-step 语义。
3. 不把 layer/named/effect/history/system/media texture 塞进同一个无作用域字符串 key。
4. 不用文件名包含关系直接宣称 Effect 支持；文件名只能用于明确注册、完整条件匹配且 fail-closed 的 profile。
5. 不把 effect-local UV 变形写成 object transform，也不把 Camera Parallax 当成所有鼠标交互。
6. 不在没有 shader annotation/slot contract 时自动绑定空白纹理并启用 optional combo。
7. 不在通用 RT lifecycle 之前单独给 Motion Blur、Cursor Ripple 或 Fluid 保存私有 history。
8. 不用普通 composition 代替 scene-background compose、RGB capture 或 nested scene。
9. 不因 parser 能识别字段就升级 executor 等级；不因样本非黑就升级视觉等级。
10. 不让高级对象绕过统一 identity、target、provider、graph、clock 和 teardown 合同。

## 6. 下次会话的决策顺序

1. 先查 [运行证据索引](runtime-evidence-index.md) 确认当前 baseline、45/13 两层门和未闭合边界；本依赖图不复制易漂移的实现 commit。下一代码批再按本图依赖与真实样本收益选择，不得从单个 strict profile 正门外推 generic shader、其他 Effect 或同类格式兼容。
2. 打开对应专项表，确认作者启用、输入、当前等级、未知项、依赖和验收门。
3. 查 [运行证据索引](runtime-evidence-index.md)，确认现有正反例，不重复制造无信息矩阵。
4. 只实现一个可独立验证的公共合同；涉及 live property 时，compiler target、真实 consumer、fallback 和 surface/window identity 必须同批验收，目标样本和相关样本通过后单独提交。
5. 更新专项表、总台账和证据索引，再进入下一项；带日期的计划只保留对应批次历史，不继续承担现役待办。
