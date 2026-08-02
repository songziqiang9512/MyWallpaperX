# Scene 公共能力依赖图与实施门

> 状态：现役架构入口
>
> 最近核对：2026-08-02
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
| project/scene/PKG/TEX/resource ingest | 常见子集 `L3` | version、case、duplicate、symlink、损坏和 VFS golden |
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
| audio 32/64 stereo bins | `L3 bounded` | 与 16 档由同次 FFT 生成；exact Workshop 32/64 profiles 与两个 exact native property-script 64-band profiles 已消费，generic SceneScript bridge 仍为 `L0` |
| media state/properties/timeline/thumbnail | thumbnail `L3 bounded`；其他 media state/property/timeline `L0` | current/previous generation、旧 request 协作取消、replacement pending last-ready、clear/decode-failure 作者 fallback 与严格 transition profile 已闭合；仍缺单次 ImageIO 调用抢占、通用事件队列、metadata/status/timeline snapshot 与 live producer |
| user/general/animation events | `L0` | per-screen queue、owner isolation、异常隔离 |

<a id="d5"></a>
### D5 Texture, media and provider registry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| provider identity/status/generation/fallback | layer/named/property 子集 `L3`；静态 resource generation 与 named frame epoch 已分离；本机普通文件 generation 使用 canonical path/size/mtime/device/inode/ctime，image/TEX/video 在 cache hit、读取或发布边界复核同一 revision，metadata 不可得、非普通文件或中途变化时失败关闭；direct text/embedded MP4 与 bounded current/previous cover 以显式 content generation publication 进入 frame registry并拒绝 stale/mismatched publication，cover 新 generation 在 current/previous decode/upload 边界协作取消旧 request，replacement pending 保留 last-ready generation、ready 后原子换代、clear/decode-failure 完成后回到作者 fallback，previous transition gradient 另以 typed `.mask`/slot/format/path 准入；Water Flow 2 槽、Standard Blur 1 槽、plain/effectful base image、bounded REFRACT normal 与 Depth Parallax R8 depth 的静态 candidate 已原子携带 generation/metadata，base 无论 direct 或 effect/offscreen 路由都在最终 split 复核同一 candidate；Shake 1/2/3、Foliage Sway 1/2、Water Ripple 1/2、Depth Parallax 1 与 exact legacy Blend 1 共九个 bounded 槽进一步消费共享 slot-binding atom，Blend 的 PNG/JPEG property 与 authored TEX 使用同一 typed candidate 合同；exact composition Clipping Mask 以同一 frame epoch 发布 bounded hidden static provider，并与完整-chain consumer 集合原子规划 capture/binding | live system media、其他 transition/variant、其余 provider 的通用异步取消、单次 decode 抢占、跨网络/粗粒度 metadata 的 content digest、nested/effectful/child producer |
| candidate selection | 受限 static image blend；Particle slot 0 先取样本本地资源，再按官方相对路径直接取 stock bundle TEX；既有 candidate 携带 purpose、actual physical/mapped、UV、sampler、pixel format，authored `0...7` binding carrier 再原子携带 index、identity/generation、mip/resolution/texel。exact legacy Blend slot 1 按 authored asset -> property 的低到高顺序选择最终 ready candidate；property 缺失不截断 authored fallback，已选 candidate 若 purpose/format/UV/sampler 不合合同则在 GPU 拆分前失败关闭。当前拆给 static base 与五个 bounded backend 的九槽 | authored 索引载体已覆盖 `0...7`，但其余 Effect 与 generic material 的 slot population/provider readiness、annotation/combo/state、dynamic generation 仍未开放；effectful/nested/child provider、stock placeholder 的尺寸/通道/mip/atlas metadata |
| upload/cancel/teardown | PNG/JPEG property 子集；embedded video 有按帧 publication、pause/rebuild/stop 状态合同和临时文件清理；media cover 有串行最长边 256 decode、旧 request 协作取消、requested-generation stale completion 拒绝、pending last-ready、clear/decode-failure 最终 fallback、per-surface pause-safe transition 与 rebuild 不重播 | 单次 ImageIO 调用不可抢占；device loss、live producer start/pause/stop、多 surface/hot-plug、budget 与真实 lifecycle 门 |

<a id="d6"></a>
### D6 Render-target graph and resource lifetime

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| ordered nodes、target/bind/compose/copy/swap | 通用 IR/runtime `L2`；十四类 strict backend 已按作者顺序消费 target table，真实 chain 覆盖 `Blur Precise -> Shadow`、Blur/Shake 双向顺序、Foliage Sway/Water Ripple、重复 Water Waves、`Water Flow -> Opacity`、composition `Clipping Mask -> static Opacity`、X-Ray 受限前缀与 `[Blur Precise, God Rays]`；God Rays 双 half RT 让混合链预算按 target extent 折算，Precise Blur 的 `material -> copy/swap -> material` 两种白名单拓扑仍按 authored nodeIndex 交错执行；所有已声明 target 的 preflight 现与 allocation 共用完整 extent resolver，缺失声明按整张补足、非法 extent 直接拒绝 | 真实 history consumer、generic compose/condition/function、跨帧 logical swap 与通用 hazard |
| extent/format/clear/UV/unique | `width`/`height`/`fit`/`scale` 分别保真并可组合，公共 resolver 依次执行单轴/双轴 override、fit 不放大、scale divisor、floor/min-1；单轴、absolute、`scale<1` 和 composed area 均进入 2048² reference budget，非法/非有限/`<=0` 失败关闭。strict Blur 的 input/BGRA 与 stock Local Contrast 的 scale=4/RGBA target 子集为 `L3`；generic table/extent 的其他形态仍为 `L2` | generic material/FBO executor；`r8`/`rg88`/float 等其余 format-to-Metal、mapped size、sampler、load/store 和跨帧 reset；Glitter 仍需 `r8` target、repeat sampler 与两个 pass executor |
| history/ping-pong | `L0` | first frame、resize、seek、switch、stop 和 memory budget |

<a id="d7"></a>
### D7 Material and shader contract

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| material pass/slot hole/combo/constant/render state | IR `L2` 已增加 loss-preserving 五项 raw state 与 observed-enum typed compiler；exact Cursor Ripple、受限 authored shader 和 particle admission 已各自消费固定 tuple，unknown/incomplete state 失败关闭。受限 authored shader 还可用 uniform 声明同行的精确字符串 `material` 键定位静态 constant；direct+alias、alias collision 与动态值拒绝。Blur、stock Local Contrast、exact Workshop Shadow、exact stock Opacity、Shake、Water Waves 与 Water Flow 等既有 profile 子集仍为 `L3`，并继续用完整 authored fingerprint 约束 | generic Metal state translator/cache、`alphawriting=default`、arbitrary blend/depth/cull/alpha、typed annotation default/slot/provider schema、variant key 与通用 executor 仍未完成 |
| shader source/include/annotation/declaration | ShaderContract v1 安全保存完整 source/raw hash、stage、include reference、annotation、uniform/attribute/varying declaration、diagnostic 与 canonical identity；bounded framebuffer-only frontend 已消费 stage link、typed uniform layout 与精确 `material` constant-key annotation，Local Contrast 等 strict profile 仍只把 exact identity/fingerprint 用作手写 MSL 准入 | typed annotation/default schema、include expansion、macro/permutation preprocessor、外部 material slot/provider、完整 GLSL 与通用 executor |
| built-in uniforms | bounded authored frontend 已消费 time/pointer/matrix、framebuffer resolution 与静态 constant direct/annotation key 子集 | per-slot material resolution、audio、effect/local matrices、color/alpha、动态 user/timeline contract |

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

这一层只消费 `D0-D8` 的统一合同：base layer compositor、共享 material pass executor、effect profile registry、particle geometry/material、text texture generation。当前共享层仍是目标，而不是已经完成的事实；`b541867` 已完成有界的 ordered strict effect-chain 调度，`809b75e`、`e505a9e`、`31ae557` 与 `94aebc5` 分别闭合 Blur/Shadow、Blur/Shake、重复 Water Waves 与 `Water Flow -> Opacity` 真实 chain，但它们都只连接 catalog 中每个 stage 均有严格 backend 的链，不能替代 generic material/pass executor，也不能升级官方 Shadow/lighting 或动态 effect variants。若某项需要在 renderer 内重新解析 JSON、猜 effect 名称、重新决定属性优先级或自行保存 history，说明底座仍有缺口，应回到对应 D 层修复。

<a id="d10"></a>
### D10 System runtimes

| Runtime | 前置依赖 | 最小闭环 |
|---|---|---|
| Timeline | D2 + D3 | lossless IR、绝对 scene-time evaluator、bounded 作者 Bézier handles 与 typed writes 已完成，现役 Workshop **48/48 authored host** 有受限 consumer：effect constant 23、layer alpha 5、bounded relative layer transform 9、root particle scalar override 7、bounded text `maxwidth` 2，以及唯一 default 2D camera Combined `origin↔zoom` 两成员。每段按 segment-normalized X/property-offset Y 消费 `start.front` / `end.back`，双禁用严格线性；越出 segment 或 bounded target control hull 的形态失败关闭。camera 两成员共用 owner clock，经同一 per-surface transaction 原子写入 projection、particle camera 与 pointer projection。multiple path、3D/未知 camera、坏组、generic Combined、wrap-loop、event crossing、particle relative/colorn/child/存量追溯仍待推进；handle 单位无 Windows wire/golden |
| Exact native property-script profiles | D0 + D4 + D7 + D8 + D9 | text 七 profile 与 audio bars 两 profile 已形成 bounded native `L3`；完整指纹准入、失败关闭，不开放 API |
| Bounded property-bound text update | D2 + D3 + D4 + D5 + D9 | 唯一 `update(value)` 的无循环 Date/string AST 以语法和三层预算准入，复用 typed snapshot/dynamic text consumer；无 sample/layer/hash 旁路，但不等于 VM |
| Generic SceneScript | D2 + D3 + D4 + D5 | 顶层 layer wrapper partial IR 与 bounded String update 子集已有；仍需 generic source/module/value IR、sandbox VM、lifecycle、typed handles/writes、events及 VM 级时间/内存预算 |
| dynamic text | D3 + D5 + D9 | direct property、exact native profile、bounded text update 与 bounded Timeline width 已完成 per-layer generation、并发 stale cancellation、单在途连续更新合并和 last-ready；system/media producer、非 String script target、长文本/多屏压力与 Windows layout fidelity 仍待推进 |
| particle breadth | D2 + D3 + D4 + D5 + D8 + D9 | root direct User Property 八字段和 absolute scalar Timeline 七字段已复用统一 binding compiler、per-surface transaction/snapshot 与 fixed-step simulator，只覆盖作者 fallback 上的发射/新生粒子；静态 plain-image Layer Image 已复用 typed object dependency、base image texture 与 simulator；仅 rate root Sphere/Box 的 Random periodic 已复用 fixed-step simulation、独立确定性 schedule RNG 与 fail-closed diagnostics；root Sphere/Box emitter 已按 authored CP identity 0...7 准入，emitter speed、Directions/Sphere Sign、depth-one static child raw parent CP copy 与 exact pointer-lock Control Point Force 已各有有界门；Sprite Trail root/child 共用 omitted/`null` length 默认，bounded Rope 支持 subdivision、UV/smoothing/scrolling 与 child 隔离 topology。dynamic override 的 script/conflict/direct color/relative/Combined/child/存量追溯、standalone delay、periodic burst/max-per-period、动态/text/puppet Layer Image、control point angle/adjusted/world/cross-space、previous pointer 与其他 consumer、event/nested CP copy、force falloff、Rope animated texture/root-world/multi-renderer/ribbon join、通用 RopeTrail subdivision/UV、audio、collision，以及各项 WE 数值/RNG/分布/轨迹 golden 仍待闭合 |
| audio/media | D4 + D5 | audio 侧已闭合 consumer-driven 16/32/64 host input、既有 effect consumers 与两个 native 64-band consumers；embedded MP4 image-layer 已有受限 SceneClock/provider generation/lifecycle；current/previous cover generation、replacement pending last-ready、clear/decode-failure fallback 与一个 strict authored transition profile 已闭合 bounded consumer。通用 SceneScript bridge/Sound/particle audio、live system media producer、event ordering、metadata/status/timeline、主动 decode cancel、多 surface/hot-plug 与其他 transition 仍未闭合 |

<a id="d11"></a>
### D11 Fidelity and advanced runtimes

Puppet、lighting/HDR、3D、RGB 和 offline 复用 D0-D10。Puppet 已有严格单 clip 的 fixed-step CPU LBS 子集，但仍必须复用统一 frame context、geometry、texture lifetime 和 fail-closed 路由；它不代表 animation mixing、动态 attachment 或完整高级对象支持。其他系统在 light/shader/fixed-time consumer 不存在时必须保持 `L0-L2`，不能用普通 image transform、layer Bloom 或 Debug PNG readback 冒充执行。

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
