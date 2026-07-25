# Scene 公共能力依赖图与实施门

> 状态：现役架构入口
>
> 最近核对：2026-07-25
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
| object/content/effect/material/particle/script source preservation | 混合 `L0-L3` | raw + typed round-trip；未知字段可诊断，不静默丢失 |
| derived renderer input | interpretation v25；继承 v24 attachment frame，并增加 authored Puppet animation layer 声明；当前每次解包都会重建，JSON 仍被同进程播放链写入后立即读回，不构成可复用缓存 | 保留 typed interpretation；播放改为内存对象直传，JSON 降为可选诊断证据。若以后恢复复用，必须增加 package/source/compiler identity，而不只校验 version/entry |

<a id="d1"></a>
### D1 Stable identity and dependency graph

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| scene/object/layer/effect/pass/material/target identity | 部分 `L2-L3` | authored ID 优先、ordinal fallback、跨屏/跨帧作用域明确 |
| source order、parent、dependency、provider、read/write edges | 部分 `L2-L3` | cycle、missing、duplicate、read-before-write 和 topology invalidation |
| named/effect/history target identity | `_a` 子集 `L3`、`_b` `L2`、history `L0` | primary/secondary/history 不混用，resize/switch/reset 可测 |

<a id="d2"></a>
### D2 Host/surface frame context and lifecycle

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| host/frame/scene/wall time | `L3` 子集 | pause/resume、delta clamp、dropped time、目标 FPS |
| host-shared vs surface-local scope | property 输入 host-shared；每个 surface 独立 transaction/snapshot/generation，B0 live alpha/solid color/strict Local Contrast strength 已有运行门 | pointer/matrix/provider/script 接入时继续证明 local state 不串屏 |
| fixed simulation step and seed policy | particle 子集 | effect/particle/script/offline 共用 discontinuity 和 seed 合同 |
| resize/switch/stop teardown | surface 子集 `L3` | VM、provider、RT、timer、media、GPU 资源全部归零或稳定复用 |

<a id="d3"></a>
### D3 Typed values, binding program and per-surface evaluation

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| value types and target definitions | 六类 value 与主要 target 由 v22 持久化；direct text 与 strict Local Contrast/Opacity 已注册 typed target | 新类型继续执行 type/finite/default validation；SceneScript 计算值不冒充 direct binding |
| source priority | `authored -> property -> Timeline -> SceneScript` 已定义；property producer 已执行 | Timeline/SceneScript 接入同一 resolver，不在 renderer 内重复求值 |
| binding program | layer alpha/solid color、direct text、Local Contrast/Opacity 编译、验证和持久化已完成；mixed/invalid/SceneScript key 标记 rebuild | 下一 target 必须同批增加 compiler mapping、稳定 identity、snapshot consumer 和 fallback |
| target scope and invalidation domain | direct text 使用 per-layer generation；alpha/color/effect scalar 为 value-only；mixed/hidden/no-consumer 统一 rebuild | topology/provider/simulation target 逐类登记失效域 |
| evaluation transaction | property base evaluation、validation、atomic commit 已按 surface 执行 | events/Timeline/SceneScript mutation 依固定顺序接入同一 transaction |
| immutable snapshot and generation | 每 surface 独立 snapshot/generation；相同 payload 不增 generation | 双屏 local input、script/provider 加入后继续验证不串用 |

目标运行形态必须是：

```text
HostFrameInputs(time, properties, audio, media)
  -> SurfaceFrameContext(viewport, pointer, matrices, providers)
  -> Surface EvaluationTransaction
  -> SurfaceDynamicSnapshot
```

B0 live-property 已由 `1762743` 扩展到 direct text content/point-size/color，并用 per-layer generation/stale cancellation/last-ready fallback 消费同一 snapshot。`2134765860` 证明三字段更新不替换 surface/window；默认隐藏文本第一次会因无活动 consumer 被拒绝，只有作者属性先启用 Custom 模式后才 live。SceneScript/time/media、particle、container、mixed、unsupported 或无活动 consumer 的 key继续整场重建。

<a id="d4"></a>
### D4 Input snapshots and event queues

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| pointer position/buttons/events | position 极窄子集 | world/layer/effect local 变换、button queue、同帧顺序 |
| audio 16/32/64 stereo bins | `L0` | injectable producer、按需注册、无消费者停采集 |
| media state/properties/timeline/thumbnail | identity `L1`、runtime `L0` | generation、取消旧 decode、事件与纹理同代 |
| user/general/animation events | `L0` | per-screen queue、owner isolation、异常隔离 |

<a id="d5"></a>
### D5 Texture, media and provider registry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| provider identity/status/generation/fallback | layer/named/property 子集 `L3`；静态 resource generation 与 named frame epoch 已分离 | 显式 dynamic generation、metadata、video/system/media/variant、nested/effectful/child producer |
| candidate selection | 受限 static image blend | 通用 material slots 0...7；pending/unavailable 不截断 authored fallback |
| upload/cancel/teardown | PNG/JPEG property 子集 | video frame、thumbnail、device rebuild、stale generation 和 budget |

<a id="d6"></a>
### D6 Render-target graph and resource lifetime

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| ordered nodes、target/bind/compose/copy/swap | 通用 IR/runtime `L2`；十一类 strict backend 已按作者顺序消费 target table，真实 chain 覆盖 `Blur Precise -> Shadow`、Blur/Shake 双向顺序、Foliage Sway/Water Ripple、重复 Water Waves、`Water Flow -> Opacity` 与 X-Ray 受限前缀；Precise Blur 的 `material -> copy/swap -> material` 两种白名单拓扑可按 authored nodeIndex 交错执行并达到受限 `L3` | 真实 history consumer、compose/condition/function、跨帧 logical swap 与通用 hazard |
| extent/format/clear/UV/unique | strict Blur 的 input/BGRA 与 stock Local Contrast 的 scale=4/RGBA target 子集为 `L3`；generic table 的其他形态仍为 `L2` | 其余 format-to-Metal、mapped size、sampler、load/store 和跨帧 reset |
| history/ping-pong | `L0` | first frame、resize、seek、switch、stop 和 memory budget |

<a id="d7"></a>
### D7 Material and shader contract

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| material pass/slot hole/combo/constant/render state | IR `L2`；Blur、stock Local Contrast、exact Workshop Shadow、exact stock Opacity、Shake、Water Waves 与 Water Flow profile 子集 `L3`，exact stock/Workshop profile 用完整 authored fingerprint 约束 | annotation defaults、variant key、typed uniform layout 与通用 executor 仍未完成 |
| shader source/include/annotation/declaration | `8474ace` 已以 ShaderContract v1 达到 `L1`：安全保存完整 source/raw hash、stage、include reference、annotation、uniform/attribute/varying declaration、diagnostic 与 canonical identity；Local Contrast 只把 exact identity/fingerprint 用作 strict admission gate，仍调用手写 MSL | typed annotation/default schema、include expansion、macro/permutation preprocessor、stage link/translation/compile 与 executor |
| built-in uniforms | time/pointer/matrix 子集 | per-slot resolution、audio、effect/local matrices、color/alpha contract |

<a id="d8"></a>
### D8 Coordinate spaces and geometry

| 必须稳定的合同 | 当前状态 | 完成门 |
|---|---|---|
| canvas/view/world/layer/effect/particle/control-point spaces | 2D 子集 | parent/rotation/scale/parallax inverse、mapped UV、3D handedness |
| cover/crop/extent/aspect | cover 子集 `L3` | 多比例、多屏、Retina、oversized image 和 Windows golden |
| mask/flow/normal/local region | effect-specific 子集；exact Shake 已消费 RG8 flow、可选 R8 phase/white fallback 与映射 UV | 不得降成整层 transform；Shake MASK1/direction/noise、每种坐标和 sampler 独立验证 |

## 3. 消费层

<a id="d9"></a>
### D9 Generic 2D execution layer

这一层只消费 `D0-D8` 的统一合同：base layer compositor、generic material/pass executor、effect profile registry、particle geometry/material、text texture generation。`b541867` 已完成有界的 ordered strict effect-chain 调度，`809b75e`、`e505a9e`、`31ae557` 与 `94aebc5` 分别闭合 Blur/Shadow、Blur/Shake、重复 Water Waves 与 `Water Flow -> Opacity` 真实 chain；它们都只连接 catalog 中每个 stage 均有严格 backend 的链，不能替代 generic material/pass executor，也不能升级官方 Shadow/lighting 或动态 effect variants。若某项需要在 renderer 内重新解析 JSON、猜 effect 名称、重新决定属性优先级或自行保存 history，说明底座仍有缺口，应回到对应 D 层修复。

<a id="d10"></a>
### D10 System runtimes

| Runtime | 前置依赖 | 最小闭环 |
|---|---|---|
| Timeline | D2 + D3 | lossless IR、Loop/Mirror/Single、tangent、event crossing、typed writes |
| SceneScript | D2 + D3 + D4 + D5 | source/binding IR、sandbox VM、lifecycle、typed writes、budget |
| dynamic text | D3 + D5 + D9 | direct property 子集已完成 per-layer generation、stale cancellation、last-ready；SceneScript/system/media producer 与 layout fidelity仍待推进 |
| particle breadth | D2 + D3 + D4 + D5 + D8 + D9 | control point、child/event、world space、rope、audio、collision |
| audio/media | D4 + D5 | injectable inputs、event ordering、provider generation、teardown |

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

1. B0 live-property、direct dynamic text、B2 target-table、十一类 strict backend、ordered strict chain、同帧 copy/swap command foundation、受限 history seed、Precise Blur material-command interleave、pointer-driven X-Ray、Puppet bind-pose/静态 attachment/严格单 clip MDLA LBS、strict depth-one static/default-static/eventspawn/natural-eventdeath/eventfollow particle child、持续/混合/duration child emitter、root child aggregate budget、18-key built-in particle registry、非音频 turbulent velocity、预算内 CPU 与超预算/多 image GPU BC premultiply、静态 authored 首帧 fallback，以及 REFRACT fail-closed 已合龙。当前实现基线为 `899704b`；隔离 45 样本 census 的 static/default-static 为 119 条，其中 14 条满足 identity strict 子集；collision/delete、inherit-value 和非空 child CP mapping 都是 0，只有两条 event child 使用非 identity scale。当前批次优先级以 [开发计划的当前批次优先级](../scene-capability-development-plan-2026-07-22.md) 为准：下一代码批先补这两条 event scale，105 条 non-identity static 仍按 nested child 等公共前置依赖排序；是否提取共享 material pass executor 按 [Render Graph 覆盖表第 6 节](render-graph-shader-coverage.md) 的 consolidation 判据执行。`route-only` 只是布局诊断，不能决定优先级。
2. 打开对应专项表，确认作者启用、输入、当前等级、未知项、依赖和验收门。
3. 查 [运行证据索引](runtime-evidence-index.md)，确认现有正反例，不重复制造无信息矩阵。
4. 只实现一个可独立验证的公共合同；涉及 live property 时，compiler target、真实 consumer、fallback 和 surface/window identity 必须同批验收，目标样本和相关样本通过后单独提交。
5. 更新专项表、总台账、现役计划和证据索引，再进入下一项。
