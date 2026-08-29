# Scene 运行输入、Timeline 与属性覆盖表

> 状态：现役专项表
>
> 最近核对：2026-08-29
>
> 本页维护当前能力与缺口；精确运行身份见 [运行证据索引](runtime-evidence-index.md)，唯一实现顺序见 [Scene 兼容执行路线](../scene-compatibility-roadmap.md)。旧 R/B 批次只作证据 provenance。
>
> `311115e3` 新增的native click/launch-origin、hover、property→Vec3与audio-scaled value均已由同一QuickJS-NG domain中的generic cursor/Vec3/AudioBuffers owner取代并删除旧产品族；shared alpha、identity display与media colors仍只有`S2 wired / visible unknown`。真实`2974757317`现分别闭合generic hover和一次press→release→`cursorClick`可见结果，但frame-held button edge不等于ordered sub-frame event queue，边界见[E-V2-SCENESCRIPT-CURSOR-CLICK-LAUNCH-OWNER-RETIREMENT](runtime-evidence-index.md#e-v2-scenescript-cursor-click-launch-owner-retirement)。

> 最新 historical Pulse combined RGB+alpha 更正：同一个typed property producer与static author value可在shared RGB-blend/scalar-alpha source proof成立时跨historical CAST3、literal-zero与`saturate(rgba)`的mask/no-mask形态复用，三种terminal的static与sole direct producer-present候选均已撤权。literal-zero的source rewrite只把字面`0`变为同维零向量，不触碰typed producer、property state、clock或值副本；mixed contributor、SceneScript/Timeline、`bounds`与其他关系域保持原边界。见 [E-V1-PULSE-LIVE-LITERAL-ZERO-RGB-ALPHA-OWNER](runtime-evidence-index.md#e-v1-pulse-live-literal-zero-rgb-alpha-owner)。

> 最新 Pulse staged-scalar/literal-zero 更正：stock `speed/amount/phase` 与 historical fragment-only `phase` 的 definition-only source 现在可在 whole-stage 全 fallback、无同 target producer、definition 与 wrapper/material/ABI/domain 精确时复用现有 typed snapshot 与 Program；没有伪造 live producer。共享 shader frontend 的精确 `max(0, float-vector)`修正只让 static literal-zero alpha no-mask/one typed mask 进入 straight-RGB/scalar-alpha Program；同 fingerprint 存在 live binding 时仍由 incumbent 持权，因为动态 scalar→vector producer lifecycle 尚未在本批证明。`bounds`、mixed source、SceneScript/Timeline及其他关系域保持原边界；见 [staged scalar](runtime-evidence-index.md#e-v1-pulse-staged-scalar-authored-fallback-owner)与[literal-zero alpha](runtime-evidence-index.md#e-v1-pulse-literal-zero-alpha-owner)。

> 最新 Pulse authored fallback 更正：direct wrapper、loss-preserving definition与live producer是三个独立事实。exact stock2842、non-audio、color-only、no-mask stage中，`noisespeed/noiseamount/power` scalar与`tintlow/tinthigh` vector3只有在无同key/target producer、唯一finite/type/shape/bit-exact definition、exact wrapper/material fallback及fragment consumer ABI/domain全部成立时，才允许definition-only source撤销旧candidate；整个stage不能混用live与fallback。三个低对比隔离fixture的scalar、vector3及组合default/recovery均进入既有typed snapshot/Program，坏artifact与profile disable只产生typed previous-current，extra-wrapper仍保留incumbent。该结论不伪造property state或live update，也不开放`speed/amount/phase/bounds`、alpha/audio/mask、Timeline/SceneScript、多contributor或scalar→vector广播。整画面10帧稳定性只排除本fixture的全屏红绿交替，不证明眼部ROI/fidelity；见 [E-V1-PULSE-AUTHORED-FALLBACK-OWNER](runtime-evidence-index.md#e-v1-pulse-authored-fallback-owner)。

> 最新 X-Ray authored scalar fallback 更正：loss-preserving scalar definition 与 live instruction/producer 现在是独立事实。current-stock `size/multiply` 在 exact `{user,value}`、唯一 scalar finite bit-exact definition、material fallback、target/ABI/range 与完整 spatial-weighted Program 均成立，且同 key/target 没有任何 producer 时，可由 definition-only authored fallback 撤销旧 X-Ray candidate；每个 target 可独立选择 static、sole live 或 authored fallback。same-key 双 live/双 fallback可fan-out，mixed live/fallback、错target/key、多producer、duplicate/type/nonfinite/signed-zero/wrapper/script漂移仍保留incumbent或硬拒绝。共享 activation 的真实 caller 同时证明 definition-only `size` 仍持有 pointer consumer与`0.001` minimum。`9000000132` default/disable/recovery均严格 **1/1 PASS / Program owner / 0 dedicated**；额外wrapper近失`9000000133`仍为dedicated X-Ray且严格PASS。该结论取代下表“缺producer一律不撤权”的冻结句，不开放Timeline/SceneScript或其他effect/vector广播；见 [E-V1-XRAY-AUTHORED-SCALAR-FALLBACK-OWNER](runtime-evidence-index.md#e-v1-xray-authored-scalar-fallback-owner)。

> 最新 X-Ray startup-false owner 更正：current-stock safe pair leaf 的 exact direct-bool visibility 现可从 authored false 启动并仍由同一 shared Program持权。dedicated compiler按descriptor authored lifecycle互斥选择startup/active admission；startup只接受 exact target、唯一bool producer、无同层或sibling frame-driven owner。受控`9000000131:69#effect#131`三路均严格 **1/1 PASS / 0 dedicated**，live `xrayenable=false→true` accepted且surface/window不变，启动previous-current与live后的Program都闭合GPU/publication/compositor/next-frame；default/recovery命中generic artifact，profile disable命中shared bounded frontend。该结论取代下表“startup-false无共享Program”及只把controlled target表述为active-only的冻结句；不开放FBO/target/dependency/command、Timeline/SceneScript、mixed producer、utility/child/provider或其他X-Ray shape。见 [E-V1-XRAY-STARTUP-FALSE-SCALAR-OWNER](runtime-evidence-index.md#e-v1-xray-startup-false-scalar-owner)。

> 最新 Pulse direct alpha-binding 更正：基于只读真实 `3738202317` 的受控 `9000001000/1001` 分别以 masked combined `speed` 和 no-mask alpha-only `power` 进入补丁前已有的 typed snapshot/finalizer/Program。新代码只在每个 exact dynamic target 的 producer 集合恰为预期 singleton，且 wrapper、target/type、consumer ABI/domain、source/profile/readiness 守恒时撤销 latent Pulse candidate。现役 controlled direct-scalar 证据口径由 4 扩为 6 个 fixture cohort，但它们均不计入 authored corpus；本 exact cohort 之外的 alpha shape、`bounds`、audio+binding、Timeline/SceneScript、missing/wrong/multi producer 仍保留 incumbent 或失败关闭。这一口径取代下表无限定的“alpha 尚未开放”冻结句；见 [E-V1-PULSE-ALPHA-BINDING-CANDIDATE-REVOCATION](runtime-evidence-index.md#e-v1-pulse-alpha-binding-candidate-revocation)。

> 最新 startup-inactive safe FBO 后继把 startup query 从全局 sole-key view 改为完整校验的 effect-local direct-bool view，并继续由 route admission 过滤。只有同 key 全部 sibling 都是 bool `effectVisibility`、各有 bool authored fallback 且 key 非 rebuild 时才可 fan-out；planner 又只接纳共享 previous-current topology 已证明安全的 exact nonpersistent FBO graph。真实 `3211615441` 的两条 Blur FBO 与两条 VHS suffix 在 `blur=false→true` 中于同一 surface/window 从 typed inactive 恢复 Program、GPU/publication/compositor/next-frame。该结论取代下表中“startup 使用 sole-key / startup FBO 全部关闭”的冻结措辞；persistent/unique/history、dependency/provider、read-before-write、descriptor mismatch、clear/condition/function/compose、mixed/nonbool/rebuild 与无 Program consumer仍关闭。见 [E-V1-STARTUP-INACTIVE-SAFE-FBO](runtime-evidence-index.md#e-v1-startup-inactive-safe-fbo)。

> 现役 owner 更正：上述 startup-safe FBO correctness 现已进入 Standard Blur candidate 撤权边界。Launch 独立转发 validated startup target；compiler 按 exact descriptor lifecycle 互斥选择 admission，作者 `visible=false` 时只接受 exact startup target + 唯一 bool producer，不能从 active/static 的 empty-producer 分支绕过。缺/错/重复 producer、错 target、active-set-only、同层 frame-driven owner均保留 incumbent，X-Ray 不消费这项扩张。真实 `3211615441` 的 default/recovery 均 **1/1 PASS / 23 Program owner / 0 dedicated/fallback**；profile disable 严格 **0/1 NON-PASS**，两条 Blur成为 typed inactive passthrough、live update因无 Program consumer fail closed，VHS suffix 与 GPU/publication/compositor/next-frame 继续。该结论取代下表“不是新 owner migration / startup-false FBO 未开放”的冻结句，只覆盖 `24#effect#613` 与 `26#effect#257`；见 [E-V1-STANDARD-BLUR-STARTUP-FALSE-OWNER](runtime-evidence-index.md#e-v1-standard-blur-startup-false-owner)。

> 现役 Standard Blur authored scalar fallback 更正：property compiler现在分别发布 loss-preserving authored definition 与 live instruction。有限单分量或两个 bit-exact 相等分量的shader string形成scalar definition；同符号零可保留，`-0/+0`不相等。只有唯一有效slider同时形成instruction/sole live producer，missing/duplicate/kind-invalid项目属性不会伪造live producer。两个Gaussian target可以整stage使用同一个sole live scalar source，或在不存在同key/target producer时整stage使用各自唯一且精确匹配的authored fallback definition；两者都须重证exact `{user,value}`、target/type/value、material fallback、ShaderPreparation、唯一active vertex non-array `float2`与finite equal-lane default。mixed live/fallback、缺/错/多definition、错/多producer、非有限/bit mismatch及wrapper/material/ABI漂移继续保留incumbent。`9000000999`的definition-only正例default/recovery均进入4/4/0 Program，mixed-source `9000001002`仍由dedicated执行；disable严格NON-PASS而raw log只证明4/0/4 previous-current与输出链安全。该更正取代下表把“存在producer”写成所有scalar projection的必要条件，不扩张任意scalar→vector广播或其他effect；见 [E-V1-STANDARD-BLUR-AUTHORED-SCALAR-FALLBACK-OWNER](runtime-evidence-index.md#e-v1-standard-blur-authored-scalar-fallback-owner)。

本表把 Frame Context、动态目标、Timeline、用户属性、文字、光标、音频、媒体和纹理 provider 放在同一执行合同下。官方语义摘要见 [`runtime-systems-reference.md`](runtime-systems-reference.md)，等级口径见 [`coverage-ledger.md`](coverage-ledger.md)。

## 1. 固定求值合同

同一 host frame 先捕获共享输入，再为每个 surface 独立求值。目标值只能按以下顺序产生：

```text
HostFrameInputs(time, properties, audio, media)
  -> SurfaceFrameContext(viewport, pointer, matrices, providers)
  -> authored base
  -> user property direct binding
  -> Timeline
  -> lifecycle/input/media event dispatch
  -> SceneScript stable-order execution
  -> mutation/type/finite/target validation
  -> immutable SurfaceDynamicSnapshot commit
  -> generation/invalidation reconciliation
  -> renderer / text / particle / provider consumers
```

高优先级输入无效时保留最近一个合法低优先级值；未知目标、重复定义和非有限数值 fail-closed。这条规则只适用于普通 value 通道；现役纹理 provider 使用 explicit-absent-only 合同，missing、pending、unavailable、incomplete 或 identity mismatch 都不得回退低优先级纹理。纹理内容不进入普通 value 字典，只传 provider identity、状态和 generation。共享时间、用户属性、音频和媒体可以在 host 捕获一次；viewport、pointer、矩阵、surface provider和最终dynamic snapshot按surface隔离。QuickJS runtime/context当前与目标均为per-scene domain，binding owner在该domain内隔离；真实多surface下的输入、consumer、event与teardown一致性仍未验证。

## 2. Frame Context 与动态目标

| 能力 | 等级 | 当前证据 | 当前边界 / 下一门 |
|---|---|---|---|
| 宿主单一 frame driver | `L3` | [`SceneDesktopWallpaperHost.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift)、[`test_scene_frame_context.py`](../../../script/tests/test_scene_frame_context.py)、[E-FRAME](runtime-evidence-index.md#e-frame) | 固定 60 Hz Timer；补屏幕刷新率/目标 FPS |
| 同帧 host/scene/wall time | `L3` | [`SceneFrameContext.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift)、[E-FRAME](runtime-evidence-index.md#e-frame)；同帧发布 raw/simulation/dropped delta 与 discontinuity，pause 冻结 scene time，resume 首帧丢弃 host gap | 真实系统 pause/sleep、seek/其他history topology 与跨 consumer discontinuity 合同 |
| shader/video/particle/parallax/camera shake 共用 timing | `L3` | [`SceneMetalView.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneMetalView.swift)、[E-FRAME](runtime-evidence-index.md#e-frame)；particle/parallax smoother消费受控simulation delta，shader/video保持raw/absolute time，Camera Shake直接消费absolute `sceneTime`且同一frame只构造一个camera frame | 其他simulation consumer、不同FPS、离线adapter、官方pause/seek事件策略与Windows timing golden |
| typed value 六类 | `L2` | `bool/scalar/vector2/vector3/vector4/string`；[`SceneDynamicSnapshot.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Properties/SceneDynamicSnapshot.swift) | texture/provider 不属于普通值；新增类型仍需 wire/type/finite 门 |
| typed target 族 | `L2` | scene/camera/layer/effect/text/particle/script instance 已定义；layer alpha/color、exact stock Local Contrast strength/Opacity alpha、bounded Blend multiply 与 particle CP position/angles 进入 compiler | particle 仅 absolute CP position 有 consumer；其他 effect target 不得直接开放 live，SceneScript 计算值与 direct binding 分开准入 |
| 固定 source priority | `L3` | authored -> property -> Timeline -> SceneScript；property/Timeline与QuickJS scalar/Vec3同target时先形成current-frame preliminary value，VM成功结果再覆盖。property、受限Timeline、bounded text Date、generic VM time-of-day、media event与cursor/shared producer已执行并复用`.sceneScript` source | 重复或仍被bounded producer占用的QuickJS candidate不形成owner并保留现有值，但typed conflict aggregation尚缺。bool/Vec2/Vec4/matrix与更广live event mutation仍未接入 |
| property binding program persistence | `L3` | format 22 持久化 definitions、instructions、rebuild-required keys 与 effective values；严格 decode/validation | layer alpha/solid color、direct text 三字段、Local Contrast strength 与 Opacity alpha 均有真实 consumer |
| user-property scalar → equal-lane `float2` consumer projection | `L3 bounded` | binding compiler在scalar slider的作者shader fallback为单值或两个相等有限component时保留scalar producer；MaterialProgram只有在sole `.userProperty` contributor、exact `{user,value}` wrapper、无script attachment、非数组`float2` reflection且作者fallback/consumer default均为单值或equal pair时编码`(x,x)`。Standard Blur owner gate还会在撤权前准备两个真实Gaussian consumer并逐一验证唯一`scale` mapping、vertex `float2` ABI与typed default；错误类型、数组、缺省或不等默认保留incumbent。compile input的共享visibility查询对user-property匹配exact effect target，对frame-driven Timeline/SceneScript则按下游现役layer-wide admission保守匹配同层任一owner；Standard Blur/X-Ray撤权均先守住相同失败半径。unequal pair、额外key、Timeline/SceneScript、非有限值、数组或类型漂移仍以`dynamicUniformBindingInvalid`关闭。真实`3211615441`两项ordinary Blur消费同一个`blurratio`；受控`9000000966:148#effect#151`先以无mask、再以保留typed static `util/white` opacity mask的组合证明同一投影可在copy+passthrough captured-main中接受live `blurscale`并完成Program/GPU/publication/compositor/next-frame。[E-V1-STANDARD-BLUR-USER-SCALAR-SPLAT-OWNER](runtime-evidence-index.md#e-v1-standard-blur-user-scalar-splat-owner) [E-V1-STANDARD-BLUR-COPY-PASSTHROUGH-USER-SCALAR-OWNER](runtime-evidence-index.md#e-v1-standard-blur-copy-passthrough-user-scalar-owner) [E-V1-STANDARD-BLUR-MASKED-COPY-PASSTHROUGH-USER-SCALAR-OWNER](runtime-evidence-index.md#e-v1-standard-blur-masked-copy-passthrough-user-scalar-owner) | 这是consumer-side有界投影，不把snapshot scalar改型，也不开放任意scalar→vector广播。受控fixture不计入authored corpus；其他effect/vector shape、多个producer、SceneScript/Timeline、动态mask/provider及更宽utility生命周期仍按各自合同处理 |
| direct user-property → exact scalar/vector3 shader consumer | `L3 bounded; vector3 + fragment scalar + cross-stage scalar owner-migration` | binding compiler保留exact `{user,value}`、由authored fallback决定shape的typed definition与target；只有有效property default才发布launch-scoped live producer。Pulse vector3 tint、fragment-only `noisespeed/noiseamount/power`、historical fragment-only `phase`、same-domain双stage `speed/amount`与stage-indexed stock `phase`均要求sole `.userProperty` contributor、无script attachment、旧plan binding全集及key/target/type/domain等值。fragment-only项要求唯一active fragment non-array ABI；双stage项要求同一material key的exact active set为`{vertex,fragment}`与每stage唯一non-array `float`。`speed/amount`逐stagerange相等；stock `phase`分别重证vertex `0...1`与fragment `0...6.282`，historical `phase`只重证fragment `0...6.282`；同一producer在finalizer中逐consumer stage应用各自domain，越界stage恢复该stage authored fallback。缺失producer、任一stage不安全的fallback或其他exact producer缺口在旧plan仍可接纳时都不撤旧owner。受控`9000000967`证明same-domain组合；受控`9000000968`证明stock phase默认/恢复4 Program / 0 dedicated；受控`9000000969`证明historical phase默认/恢复7 Program / 3 fallback / 0 dedicated，profile-local rollback为5 Program / 5 fallback / 0 dedicated，target previous-current与后缀compositor/next-frame继续。[E-V1-PULSE-HISTORICAL-FRAGMENT-PHASE-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-historical-fragment-phase-user-property-owner) [E-V1-PULSE-STAGE-INDEXED-PHASE-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-stage-indexed-phase-user-property-owner) [E-V1-PULSE-CROSS-STAGE-SCALAR-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-cross-stage-scalar-user-property-owner) [E-V1-PULSE-FRAGMENT-SCALAR-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-fragment-scalar-user-property-owner) [E-V1-PULSE-TYPED-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-typed-user-property-owner) | 不做广播或类型转换；关系域`bounds`、其他float2、alpha或audio+binding、额外wrapper key、多contributor、Timeline/SceneScript、数组、target/fallback/ABI/domain漂移与未消费binding继续失败关闭或保留incumbent；受控scalar fixture只作`MyWallpaperX-current-evidence`，不是authored corpus正证 |
| direct user-property → current-stock X-Ray scalar ABI | `L3 bounded owner-migration` | 共享binding program保留exact `{user,value}` scalar与sole launch producer。旧 X-Ray owner只在唯一effect/material、常量全集`size,multiply`、无Timeline/SceneScript/material user value、spatial-weighted source/resource/profile完整重证时撤权；每个readiness variant必须证明`size`唯一映射active vertex非数组`float [0,1]`、`multiply`唯一映射active fragment非数组`float [0,10]`，且至少一项确有direct property producer。exact sole bool visibility可由下行shared activation consumer持有；作者启动为false时也只有同一共享Program可准备且pair-leaf安全才进入graph，不再为这种可执行形态保留旧owner。真实`3757555836:69#effect#131`保留`size={user:"x",value:0.2}`；controlled `9000000131`又闭合live visibility与size-zero previous-current。[E-V1-XRAY-DIRECT-SCALAR-OWNER](runtime-evidence-index.md#e-v1-xray-direct-scalar-owner) [E-V1-XRAY-SHARED-STAGE-ACTIVATION-OWNER](runtime-evidence-index.md#e-v1-xray-shared-stage-activation-owner) [E-V1-XRAY-STARTUP-FALSE-SCALAR-OWNER](runtime-evidence-index.md#e-v1-xray-startup-false-scalar-owner) | 缺producer、错误type/range/ABI、额外wrapper key、多contributor、Timeline/SceneScript scalar或frame-driven effect visibility仍不撤旧owner。startup-false但无共享Program或不满足safe pair-leaf topology的形态、`multiply`真实corpus live门、其他X-Ray形态、独立ROI与官方parity仍缺 |
| startup-inactive safe nonpersistent FBO exact bool activation | `L3 bounded / S4 V1-A correctness` | `SceneRuntimeInput`使用完整校验的`effectLocalDirectBoolEffectVisibilityTargets`，再由ordinary startup route过滤；同key sibling必须全为bool effect visibility、具bool definition/authored fallback且非rebuild。planner只接纳exact单effect、nonunique/nonpersistent FBO、无clear/condition/function/compose/dependency/provider、读由先前作者写支配、copy/swap storage descriptor相容、全部target初始化/消费且terminal读取FBO的共享previous-current topology。inactive只发布activation passthrough，live true后才建立既有target并执行Program | 真实`3211615441`的`blur=false→true`定向1/1 PASS：`24/26#effect#613/257`两条四material/双FBO Blur与同key两条VHS suffix启动时均property-inactive/complete；live更新保持surface/window identity，frame63恢复Program，frame64 next-frame继续，VHS terminal由唯一compositor消费；23 generic / 0 dedicated / 0 fallback，GraphExecutor 246/246/246、0 failure。[E-V1-STARTUP-INACTIVE-SAFE-FBO](runtime-evidence-index.md#e-v1-startup-inactive-safe-fbo) | pointer/scalar不随本批扩张；persistent/unique/history、read-before-write、descriptor mismatch、mixed/nonbool/rebuild、utility/parent/child、dependency/provider、clear/condition/function/compose、Timeline/SceneScript与无Program consumer继续关闭。不是新owner迁移、独立ROI/fidelity、Fast/fixed/full或整个V1 |
| exact effect visibility / pointer / identity scalar activation | `L3 bounded / S4 mixed slice-visible + owner-migration` | binding compiler按exact layer/effect identity把direct bool映射为typed target，不按effect path准入。startup-false继续使用全局sole-key view；active owner gate另消费完整校验的target-local direct-bool view，允许同一key fan-out到多个exact target，但同key全部sibling必须是bool `effectVisibility`、每个target有bool definition/authored fallback且key不要求rebuild。pair leaf继续支持visibility/pointer/identity scalar；pointer须全部variant实际消费spatial-weighted pointer host uniform，`size`须为exact static或sole scalar producer。exact bool visibility可附加到already-admitted安全nonpersistent FBO graph；也可把 authored startup-false effect 纳入 ordinary image/solid/text、无parent/child/utility/cross-layer provider-consumer、无target/blocker、单material、exact current-pair、无command/condition/compose的安全leaf。inactive发布`activation-passthrough` previous-current并保留generation/publication/completion/compositor；Program-backed startup leaf可live激活，Program不可用则以独立passthrough member保留且不形成CPU exact owner或live consumer。controlled `9000000131`现同时闭合既有pair-leaf activation与exact current-stock X-Ray startup lifecycle owner-migration；真实`3211615441`两项Blur先闭合FBO correctness，现又在ordinary-root route gate与完整KERNEL0 proof下完成bounded `generic-only` owner转移；真实`3767460992`的Film Grain闭合startup-false `false→true` Program执行。[E-V1-XRAY-STARTUP-FALSE-SCALAR-OWNER](runtime-evidence-index.md#e-v1-xray-startup-false-scalar-owner) [E-V1-XRAY-SHARED-STAGE-ACTIVATION-OWNER](runtime-evidence-index.md#e-v1-xray-shared-stage-activation-owner) [E-V1-FBO-STAGE-ACTIVATION](runtime-evidence-index.md#e-v1-fbo-stage-activation) [E-V1-STANDARD-BLUR-DIRECT-BOOL-VISIBILITY-OWNER](runtime-evidence-index.md#e-v1-standard-blur-direct-bool-visibility-owner) [E-V1-STARTUP-FALSE-EFFECT-VISIBILITY](runtime-evidence-index.md#e-v1-startup-false-effect-visibility) | startup-false FBO/target/dependency/command、Timeline/SceneScript、mixed/nonbool sibling、rebuild key、utility/parent/child、named/reference/effect consumer、required provider/graph-output provider、多effect、persistent/unique/history、clear/condition/function/compose及任意其他topology未开放；pointer/scalar不随startup admission扩张。owner迁移现覆盖两个exact Blur target及一个exact current-stock X-Ray startup lifecycle；runtime无compiler-preview candidate计数，无Program startup leaf的live更新仍fail closed/relaunch |
| host-shared / surface-local scope | `L3` | property输入由host捕获，每个surface有独立transaction/snapshot/generation；QuickJS domain、binding/cursor owner与mutable `shared`为scene scope，scalar/Vec3 evaluation在surface循环前推进一次并向各surface广播同帧值；surface-local pointer hit/capture只向同一scene domain派发typed event。scene activate建立新domain，teardown/新scene销毁，普通surface rebuild不重建第二VM；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-V2-SCENESCRIPT-CURSOR-CLICK-LAUNCH-OWNER-RETIREMENT](runtime-evidence-index.md#e-v2-scenescript-cursor-click-launch-owner-retirement) | pointer/matrix/provider与真实多surface输入/snapshot/consumer/event一致性继续补双屏隔离门；当前单surface click不能外推多屏capture/ordering |
| target invalidation domain | `L3` | alpha/color/effect scalar为value-only；已准入pair leaf、安全nonpersistent FBO graph、Program-backed startup-false pair leaf及新准入的startup-safe nonpersistent FBO graph之exact effect visibility只做frame-local activation；direct text为per-layer texture generation；mixed/hidden/no-consumer/SceneScript/unsupported key标记rebuild | 未命中共享startup-safe FBO predicate的不安全topology与无Program consumer、通用provider和simulation target继续登记 |
| per-surface evaluation transaction | `L3` | property、Timeline与bounded text/generic QuickJS scalar/String/Vec3 producer的validation、同帧合并及atomic commit已闭环；QuickJS从authored/user/Timeline preliminary snapshot取值，成功后以同帧`.sceneScript`值进入各surface最终transaction，失败保留owner-entry current-frame值。cursor/media event与同帧update共用owner-local mutation事务，异常不提交部分mutation；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline)、[E-V2-SCENESCRIPT-CURSOR-CLICK-LAUNCH-OWNER-RETIREMENT](runtime-evidence-index.md#e-v2-scenescript-cursor-click-launch-owner-retirement) | ordered event queue、同priority多脚本执行、typed conflict aggregation与live media ingress尚未接入 |
| changed-target generation | `L3` | 每 surface 持有 generation，相同 payload 不增加；跨 surface 不共享 owner | local input/script/provider 接入后继续验证独立 diff |
| live consumer | `L3` | layer alpha、solid-only color、visible direct text content/point-size/color、bounded Timeline text width、shared-Program Local Contrast/strict Opacity、initially admitted pair-leaf、already-admitted与startup-safe nonpersistent FBO、Program-backed startup-false pair-leaf exact effect visibility、QuickJS `engine.timeOfDay`驱动的4个Blend `multiply`与2个`alpha` consumer、QuickJS cursor/shared驱动的layer origin、23处Timeline effect constant typed binding、5处ordinary relative layer transform、bounded 2D camera Combined projection，以及absolute Timeline particle CP position/root emitter读取per-surface snapshot；controlled X-Ray、真实Standard Blur、真实`3767460992:17#effect#725` Film Grain及真实`3211615441`的startup-inactive Blur/VHS fan-out都在不换surface/window的live update后进入typed activation/Program链。[E-V2-SCENESCRIPT-CURSOR-CLICK-LAUNCH-OWNER-RETIREMENT](runtime-evidence-index.md#e-v2-scenescript-cursor-click-launch-owner-retirement)、[E-V2-SCENESCRIPT-ENGINE-TIME-OF-DAY](runtime-evidence-index.md#e-v2-scenescript-engine-time-of-day)、[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-TIMELINE](runtime-evidence-index.md#e-timeline) | typed binding不等于对应renderer/effect完整执行；未命中共享startup-safe predicate的不安全FBO、无Program/utility/mixed/no-consumer、bool/Vec2/Vec4/matrix SceneScript与未准入particle/text/camera target仍重建或fail closed |
| Scene pause/resume | `L3 bounded` | 统一播放控制冻结SceneClock、停止frame driver并暂停video provider；重复pause/resume幂等，resume首帧raw/simulation/dropped delta均为0、scene time连续。persistent-history运行门进一步证明surface保持1、driver `active→inactive→active`，一个已提交transaction排空后暂停期无新graph transaction，resume沿同runtime/pool继续COW；[E-FRAME](runtime-evidence-index.md#e-frame)、[E-VIDEO](runtime-evidence-index.md#e-video)、[E-V1-PERSISTENT-HISTORY-PAUSE-RESUME](runtime-evidence-index.md#e-v1-persistent-history-pause-resume) | 系统focus/fullscreen/sleep/lock真实事件、暂停期视觉截图、particle/video动态视觉、seek/discontinuity及其他history topology |
| delta clamp / dropped-time | `L3 bounded` | shared clock 保留 raw delta，把 simulation delta 限为项目 policy 0.25 秒，并发布 dropped delta/discontinuity；纯 clock fixture 有 1 秒长帧数值门，Debug performance 记录次数、累计 dropped 与最大 raw；[E-FRAME](runtime-evidence-index.md#e-frame) | 0.25 秒不是官方常量；真实长卡顿、不同 FPS、其他 simulation consumer、离线/Windows timing golden 仍缺 |
| offline fixed-time adapter | `L0` | Debug PNG readback 不是离线 adapter | 注入 frame index/time/seed/provider replay |

当前 live-property 路径已让 direct text content/point-size/color 等 value-only target 进入真实 producer/consumer。文本 consumer 按 layer signature 去重、异步生成、拒绝 stale completion 并保留 last-ready texture；缺少 compiler mapping、有效可见 consumer 或 direct user binding 时继续走 `requestSceneRender` fallback。

## 3. Scene 与 Camera 输入

| 字段/能力 | 等级 | 当前消费 | 缺口 |
|---|---|---|---|
| `general.orthogonalprojection` | `L3` | cover projection 与 canvas size；[E-BASE](runtime-evidence-index.md#e-base) | Windows 多比例像素门 |
| `general.clearcolor` | `L3` | 主 pass clear color；[E-BASE](runtime-evidence-index.md#e-base) | HDR/color-space golden |
| `general.clearenabled` | `L2` | 已进入 descriptor，但 renderer 总会 clear | author-off 正反门与透明背景策略 |
| `general.nearz/farz` | `L3` | image/particle projection 使用并有边界保护；[E-BASE](runtime-evidence-index.md#e-base) | 3D camera 与异常值 golden |
| Camera Parallax enable | `L3` | 只有作者开启时运行；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | Scene options 完整字段 |
| parallax amount/delay | `L3` | smoother 与 layer transform 消费；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | WE 数值/时序标定 |
| parallax mouse influence | `L2` | 字段已进入 offset；当前还叠加 layer-to-camera 静态项，`0` 不保证所有 2D layer 完全不动 | 先锁定 `0` 关闭鼠标驱动的官方反例，再校准非零幅度 |
| per-layer parallax depth / propagation | `L3` | 非零 depth、parent propagation 和阻断；[E-PARALLAX](runtime-evidence-index.md#e-parallax) | effect-local/3D 坐标 golden |
| camera shake | `L3 bounded` | Scene general作者开关、默认值与amplitude/roughness/speed静态准入进入唯一camera-frame evaluator；当前2D orthographic renderer、particle/pointer/parallax消费同一shake-adjusted camera，User Property经rebuild生效；[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake) | 真正perspective Scene XYZ、3D camera、live/SceneScript写入、官方pause/seek策略、Windows同相位golden与整景视觉 |
| bounded 2D camera path origin/zoom | `L3 bounded` | 单一 default path 的 reciprocal Combined `origin` owner + `zoom` child 共用 owner clock，原子进入 image/particle/pointer projection；zoom 只准 `0.01...100`，作者 Bézier control-value convex hull 也必须保持 origin/zoom/near/far 预算 | 多 path selection/lifecycle、generic setter、3D camera 与 Windows golden |
| 3D camera / perspective runtime control | `L0` | 2D bounded path 不外推 3D Eye/Center/Up/FOV | 3D path identity、queue/lifecycle、typed projection 与运行门 |
| environment/gravity/wind | `L0` | Scene general 无对应 IR | 与 particle/puppet/3D solver 共用输入 |
| official Scene Bloom/HDR target identity | `L1` | `.scene(.bloomEnabled/.bloomThreshold)` 已定义；无 binding/producer | 稳定 authored path 和类型定义 |
| official Scene Bloom/HDR runtime | `L0` | 无 producer/consumer 或全场 post | HDR target、tone map、layer HDR brightness |

现有 `SceneBloomPipeline` 是按 layer effect 路径选择的受限近似，不是 `general` 下官方 Scene Bloom/HDR 的实现。

<a id="op-parallax-camera"></a>
### 3.1 [Camera Parallax](https://docs.wallpaperengine.io/en/scene/parallax/introduction.html) 官方合同

官方 Camera Parallax 是 Scene 级作者开关。`Amount`、`Delay` 和 `Mouse influence` 是所有元素共享的输入；启用后每层才获得独立的二维 `Parallax depth`。`Mouse influence = 0` 在 2D Scene 中等价于鼠标不再驱动该效果；逐层 X 或 Y 深度单独设为 `0` 会关闭对应方向，两轴都为 `0` 会关闭该层 Camera Parallax。播放器不得因为自己具备 pointer 能力而替作者开启它。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| Scene enable 是全局前置条件 | `L3` | [`SceneLayerParallax.swift`](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/SceneLayerParallax.swift) 先检查 `configuration.enabled`；有 author-off 门 | 保持默认关闭，补 cache/重建后的反例 |
| per-axis depth zero | `L3` | X/Y 独立相乘；`xOnly` 与两轴全零有 [`test_scene_layer_parallax.py`](../../../script/tests/test_scene_layer_parallax.py) | 加入负深度、极值和多比例数值门 |
| mouse influence zero | `L2` | mouse 项会归零，但当前公式仍含 layer-to-camera 静态偏移 | 官方零值 fixture 必须对所有普通 2D layer 输出零位移 |
| nonzero mouse influence / delay | `L3` | pointer smoother 和 authored scalar 已消费 | 与 Windows 同输入的幅度、方向和时间曲线 golden |

<a id="op-parallax-oversized"></a>
### 3.2 [Oversized Image](https://docs.wallpaperengine.io/en/scene/parallax/oversized.html) 官方合同

Oversized Image 不是新的 layer/effect 类型，而是作者保留原始大图尺寸、把项目分辨率设为常见桌面尺寸，再调 Camera Parallax strength，使鼠标到四角时可以探索图像但不越出图像边界。官方把边缘覆盖交给作者尺寸和参数，不要求播放器私自 clamp、缩放或补灰底。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| authored source size / layer scale 路由 | `L2` | 普通 image geometry 已进入 descriptor/render transform；没有 oversized 专用分支 | 固定大图 fixture 验证四角映射和作者尺寸不被改写 |
| 边缘覆盖与无灰底 | `L2` | cover/clear 与 Camera Parallax 各自存在，但没有 oversized 四角运行门 | 作者合法 strength 下四角均覆盖；不得增加隐式 clamp |

<a id="op-parallax-depth"></a>
### 3.3 [Depth Parallax](https://docs.wallpaperengine.io/en/scene/parallax/depthparallax.html) 官方合同

Depth Parallax 是独立 image effect，依赖 depth map，并且官方要求先全局启用 Camera Parallax。作者通常把该 image layer 的普通 `Parallax depth` X/Y 都设为 `0`，避免 Camera Parallax 位移与 depth-map UV 变形叠加；effect 自身另有 X/Y `Depth`、`Perspective`、`Center` 和 quality/occlusion 选择。生成 depth map 的 Editor Extensions DLC 只属于作者工具，播放器只消费导出资源。

| 精确合同 | 等级 | 当前代码事实 | 最小升级门 |
|---|---|---|---|
| `depthparallax` declaration identity | `L1` | 通用 effect definition 可保留 file/pass/resource，未形成专用 IR | depth map、可选 mask、depth/perspective/center/quality typed contract |
| global Camera Parallax dependency | `L1` | Camera 开关和普通 layer depth 可执行，但未与该 effect 建依赖诊断 | global-off、layer-depth-nonzero 和缺 depth map 均 fail closed |
| depth-map effect runtime | `L0` | 无专用 executor 或 effect-local pointer projection | 基础/24-layer/64-layer profile、X/Y zero、center/perspective 和 author-off pixel gates |

<a id="op-camera-shake"></a>
### 3.4 Scene Camera Shake 官方客户端合同

Scene Camera Shake 是Scene级全局相机行为，不是对象effect `Shake`。Wallpaper Engine 2.8.42的哈希匹配客户端静态证据给出以下可测试合同；项目只实现其中可证明的2D orthographic子域：

- 作者默认关闭；缺省amplitude/roughness/speed分别为`0.5 / 1 / 3`。同版本editor作者范围为amplitude `0...1`、roughness `0...2`、speed `0...5`；项目用它们做静态准入，不声称player会运行时clamp。
- evaluator由absolute scene time决定，没有RNG、seed或逐帧积分状态；同一时间输入必须得到同一结果。项目pause通过冻结共享`SceneClock`自然冻结结果，这不等于已经证明官方pause/seek事件政策。
- amplitude 0是identity；speed 0停在起始相位而不是关闭；roughness 0保留基础周期向量，roughness 1保持基础轨迹，roughness只重塑径向长度。起始相位为X正峰、Y为0，X/Y采用不同固定频率。
- evaluator给camera eye和center加同一个位移，因此不产生rotation、roll、zoom或FOV变化。base/default/path camera与shake先形成唯一working camera；parallax只读取它的XY并与pointer组合，shared view也只由该shake后状态构建，不得回读pre-shake camera。
- orthographic Scene先丢弃Z、只对XY做roughness整形，最后以作者`orthogonalprojection.height`缩放；不能改用drawable或canvas最小边。真正perspective Scene使用XYZ分支且不会因某个explicit camera禁用，但该分支当前项目尚未准入。
- 分支选择来自Scene全局投影类型，不来自particle `flags=4`。因此正交Scene中的perspective particle仍与普通层共享同一个height-scaled XY shake，只在下游选择perspective VP。
- 当前property wrapper只通过整场rebuild重新解析；没有live snapshot consumer，也没有SceneScript scene-property bridge。

项目正负数值门覆盖author-off、amplitude/speed/roughness的0/1/2边界、absolute-time往返、projection-height缩放、无效投影/范围失败关闭、base/path + shake + parallax顺序，以及正交层和下游perspective particle共用同一camera origin。正式运行见[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake)。

## 4. Timeline

<a id="op-timeline-introduction"></a>
### 4.1 [Introduction](https://docs.wallpaperengine.io/en/scene/timeline/introduction.html)：identity、timebase 与 target axes

Timeline 是带预定义时长的 component-property 动画，不是 Effect animation。官方创建合同包含 mode、从首帧到末帧的 `Seconds`、关键帧槽数量 `Frames`、可选 `Name`、`Start paused` 和 `Wrap loop frames`。目标必须保存 component/object、property 以及 vector axis；例如 `Origin.x` 可以单独动画，隐藏 graph 中的 Y/Z lane 只改变编辑视图，不会把 lane 从 animation 删除。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| dynamic `animation` wrapper presence | `L2` | 粒子 CP position/angles nested wrapper 已保留完整 Timeline IR；随包 7 处 particle Timeline 是其他 scalar override，仍只记 presence 并诊断 | 不得把 CP 子集外推为 generic particle Timeline |
| animation identity / optional name | `L1` | 身份由宿主 JSON 路径（layer + host 属性名、layer + `instanceoverride.controlpoint*`，或 layer/effect/pass/constant 名）决定；官方 optional name 在随包 48 处中未出现，未保存 | 出现合法 fixture 后补 name 与 owner scope |
| duration seconds / authored frame slots | `L2` | `fps`/`length` 原样保存，时长按 `length / fps` 换算（随包三例交叉验证 1.0s / 0.5s / 0.5s）；`smoothing`/`stiffness` 随包 16 处全为 null，只保真不解释 | 异常值（`length` 与末帧不符）无反例可依 |
| component/property/axis target | `L3` | lane 以 `c0/c1/c2/c3` 对应 component 下标，必须从 `c0` 起连续否则 fail-closed；已 typed 编译为 `.camera(.origin/.zoom)`、`.layer(.alpha/.origin/.angles/.scale)`、`.effectConstant`、`.text(.maxWidth)` 与 particle `.controlPoint`/`.controlPointAngles`。effect constant 从完整作者 raw value 严格形成 1–4 维 scalar/vector shape，缺失、空、畸形、非有限、超过四维或 lane 数与 shape 不一致时整条 target 拒绝；合法普通值经同一 per-surface transaction 写入 snapshot。layer transform 仅在 `relative=true` 时准入 additive composition；唯一 camera 组按 relative origin + absolute zoom 准入，组内共用 owner clock；text width 仅准 `limitwidth=true`、absolute 单 lane，且实际 Bézier segment 的端点/control values 全部位于有限 `1...16384` 像素 | vector3 representative Tint color 已经 shared MaterialProgram/GPU/compositor/next-frame 可见，lane mismatch 只局部 passthrough；真实 `3748311238:728` 两个 vector2 Shake consumer 也已执行并通过 frame fault 局部恢复门，但不证明其余 effect constant/vector occurrence、整个 Shake owner、generic Combined、absolute layer transform 或其他非 layer-transform `relative`，后者继续拒绝或待验 |
| `relative` composition | `L3 bounded` | 9 处 layer transform 以“作者基值 + 动画偏移”形成 typed additive binding：5 条 ordinary + 4 条 `lspot`；camera origin 另以相同 composition 进入 bounded Combined camera target。公开官方页只定义 property animation/modes 与 layer transform，不定义私有 serialized `relative` wire 或合成公式 | 合同来自合法语料、既有 black-box 校准与项目自有正反门；其他非 layer target、非有限基值或形态不完整均 fail closed，仍需 Windows golden |
| keyframe frame/time/value | `L3 bounded` | `frame`/`value`/`front`/`back`/`lockangle`/`locklength` 六个键在 180 个真实 keyframe 上全部保真；帧号严格递增；缺失/`null` tangent 合法，非 object 报 `invalidTangent`。enabled front X 只准 `0...1`、back X 只准 `-1...0`，已消费 control value 必须有限；普通动画的首 back/末 front 仅保真，wrap-loop 会把它们作为闭合段 control handles 消费 | 同 frame 多 lane 与异常顺序目前只有负例门；handle 单位与范围无 Windows wire 对照 |
| scene-time evaluation | `L3` | 纯函数 evaluator，同一 `sceneTime` 必得同一结果，不持播放状态、不逐帧累加；host 每帧算一次后经 per-surface transaction 写回；Scene pause 通过冻结共享 scene time 保持结果 | 未接 seek/discontinuity |
| wrap-loop frames | `L3 bounded` | 9 条 Workshop + 2 条随包 stock 声明均把末关键帧留在 `length` 前；Loop 周期尾部以末 keyframe `front` / 下一周期首 keyframe `back` 构造普通 cubic，所有现役 typed consumer 共用。Mirror+wrap、关键帧越出 `[0,length)` 与 bounded target 闭合 control 越界均失败关闭；fixed13 25 bindings / 0 diagnostics | 官方只说明编辑器自动创建到首帧的平滑过渡，不公开私有 JSON 与数值算法；无 Windows 同相位 golden |

<a id="op-timeline-combined"></a>
### 4.2 [Combined Animations](https://docs.wallpaperengine.io/en/scene/timeline/combined.html)

Combined Animation 会把新的 property lane 加入一个已有 animation，并复用已有 animation 的 mode、时长和其他设置；它可以同步不同 property 类型和不同 axis。lane 必须保留作者 membership 与稳定顺序。官方页面没有定义两个 lane 写入同一最终 target 时的冲突优先级，因此在取得合法 fixture 前应拒绝歧义，而不是按 dictionary 顺序猜值。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| existing-animation membership | `L3 bounded` | 双向 key 引用已保真；唯一 default 2D camera `origin` owner + `zoom` child 组验证 reciprocal membership，并把两成员归一到 owner mode/fps/length/start-paused/wrap clock。坏引用、多 path、未知 camera/queue 和普通 Combined 整组 fail closed | generic Combined 的 owner identity、任意 property/axis 组合与 lifecycle |
| authored lane order | `L2` | lane 按 `c0/c1/c2` 下标顺序保真；同一 target 被多条 Timeline 写入时全部拒绝并报 `duplicateTarget`，不按声明序或字典序猜 | 官方未定义冲突优先级，维持 fail closed |
| atomic multi-target commit | `L3` | 全部 Timeline 值在同一帧算出后一次性送进 `SceneSurfaceEvaluationTransaction`，与 property 输入同一次原子提交；camera origin/zoom 有 owner-clock 与同 snapshot 正门 | generic Combined 冲突、seek/重启与多 surface lifecycle |

<a id="op-timeline-modes"></a>
### 4.3 [Playback](https://docs.wallpaperengine.io/en/scene/timeline/modes.html) 与 Bézier modes

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| Loop | `L3` | 按 `length` 取模，跨周期同相位；普通 Loop 与 9 条 wrap-loop 都执行，后者在末 keyframe 后连续插值到下一周期首帧 | 无 Windows 同相位 golden |
| Mirror | `L3` | 周期 `2*length` 的三角波，端点不重复采样；单测覆盖折返段与上行段同值。随包 6 处均为 relative layer transform，现已执行；`2938612768` 的 ordinary origin 有共享 world-frame 隔离正门，`3768903841` 的四束 `lspot` 有既有 strict 真实门 | 端点是否重复采样官方未定义，仍无 Windows 同相位 golden |
| Single | `L3` | 到末帧后保持末值不回绕；真实执行 21 处 | — |
| start paused | `L3` | 恒停首帧，真实执行 6 处；`2067939514` 为负门（同级脚本在 `mediaThumbnailChanged` 里调 `play()`，无 VM 时不得自动播放）；Scene pause 只冻结全局 clock，不改变 animation-local start-paused 状态 | animation-local play/stop/seek 仍需 VM/API |
| Bézier `both/left/right/none` | `L3 bounded` | 每 keyframe 左右 handle 与 `enabled` 独立保真；普通段以 `start.front` / `end.back` 构造 cubic，wrap 闭合段以末 `front` / 首 `back` 构造；X 作为各自 segment span 归一化 offset、Y 作为 property value offset，按 frame progress 二分反求 curve parameter。一侧关闭退化到对应端点，两侧关闭严格线性。44 场景 **48 animations / 180 keyframes / 112 adjacent + 9 wrap segments** 中 178 个 enabled front/back 全部满足范围，自定义 handle 分布于四个样本；定向与 fixed13 见 [E-TIMELINE](runtime-evidence-index.md#e-timeline) | 单位来自合法语料机械定标而非公开私有 wire；无 Windows 同相位数值/像素 golden |

<a id="op-timeline-events"></a>
### 4.4 [Animation Events](https://docs.wallpaperengine.io/en/scene/timeline/animationevents.html)

Animation Event 可放在 Timeline 或 Puppet animation 的指定 frame，包含作者名称，同一 frame 可以有多个事件；只有动画穿过该 frame 时才触发。SceneScript handler 必须绑定在播放该 animation 的同一 layer，并通过 `animationEvent(event, value)` 读取 `event.name`。事件可以再控制 layer/effect、sound 或其他 animation，但不能在没有 VM 时被当作已执行。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| event frame/name IR | `L0` | 无 event IR | 保真顺序、同 frame 多事件和 Timeline/Puppet owner identity |
| forward/reverse/loop crossing | `L0` | 无 evaluator/dispatch | 大 delta 不漏发，Mirror 方向和 Loop 边界不重复 |
| same-layer SceneScript dispatch | `L0` | 无 VM 或 event queue | evaluator 后、script update 前稳定排队；单 handler 异常不破坏其他 surface |

第一实现批必须先完整保存 identity、target axis、keyframe、mode、tangent、combined lane 和 event，再接 scalar/vector evaluator；不能只从 `duration` 或截图推测动画。

## 5. User Property 定义与面板

<a id="op-user-overview"></a>
### 5.1 [Overview](https://docs.wallpaperengine.io/en/scene/userproperties/overview.html)、共享绑定、Group 与 Display Condition

User Property 是 wallpaper 级 key/value，不属于某个单独 layer。一个 key 可以被多个作者目标共享；运行时必须对同一有效值做 fan-out，不能复制成彼此漂移的控件。Group 是线性分段标记：它包含其后全部 property，直到下一个 Group；第一个 Group 之前的 property 不分组，Group 本身没有运行值。Display Condition 的公开形态是 `propertyKey.value == literal`，Checkbox 使用 `true/false`，Combo 使用 option 的隐藏 value；它只控制面板可见性，不能删除或重置隐藏 property 的值。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| wallpaper-level property key/catalog | `L3` | 定义、默认值、override、排序和持久化已存在；[E-PROPERTY](runtime-evidence-index.md#e-property) | 稳定 wire schema 与跨版本 migration |
| one key -> multiple authored targets | `L3` | binding program 保留 fan-out；layer alpha 多 target 原子提交，strict catalog target 可加入同一原子 transaction，混合 target 整 key 重建 | 其他 target 逐项补真实 consumer 与 failure isolation |
| linear Group boundary | `L3` | [`SteamWorkshopSceneService+SceneProperties.swift`](../../../MyWallpaperX/Modules/SteamWorkshop/Scene/SteamWorkshopSceneService+SceneProperties.swift) 按下一个 Group 截止 | 大型表单和空 group UI 门 |
| `key.value == bool/comboValue` condition | `L3` | 复用受控 condition evaluator；隐藏不删除值；[E-PROPERTY](runtime-evidence-index.md#e-property) | 只承诺已测 equality 子集，不扩张成任意表达式 |
| default / override / reset | `L3` | authored fallback与wallpaper-scoped override/reset；layer alpha、solid color、direct text、shared-Program Local Contrast与strict Opacity可live，texture bookmark或非live key重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | 跨重启UI自动门 |
| first/change-only `applyUserProperties` | Vec3 owner `L3 bounded / S4 visible`；其他owner `L0` | QuickJS Vec3 owner首次收到全部typed `scriptProperties`，后续只收到变化键，删除键为null且无变化不派发；真实`2974757317`十个origin owner完成并产生可见卡片位移 | scalar/String/其他owner、批量顺序、reload/多scene与官方行为对照；见 [E-V2-SCENESCRIPT-CURSOR-ENTER-LEAVE](runtime-evidence-index.md#e-v2-scenescript-cursor-enter-leave) |

<a id="op-user-color"></a>
### 5.2 [Color](https://docs.wallpaperengine.io/en/scene/userproperties/color.html) 与 Scheme Color

官方 Editor 会为每个 wallpaper 默认加入 Scheme Color；作者既可新建 color property，也可把多个 effect/target 绑定到同一个 Scheme Color 或自定义 color key。MyWallpaperX 当前只会解析导出文件里实际存在的普通 color definition，不会在缺失时合成 Scheme Color，也没有 Scheme Color 专用 scope。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| ordinary `color` definition/control | `L3` | UI、字符串值和持久化可用；[E-PROPERTY](runtime-evidence-index.md#e-property) | 颜色空间、全部 target 与 live snapshot |
| `schemecolor` exported identity | `L1` | 若导出为普通 color definition 可被 generic parser 识别 | 明确 built-in identity/default/scope；缺失时是否合成需合法 fixture |
| shared color target fan-out | `L2` | 重复 binding 可保留，只有受支持白名单经整场重建应用 | 多 effect/layer 同帧原子更新和颜色类型验证 |

<a id="op-user-slider"></a>
### 5.3 [Slider](https://docs.wallpaperengine.io/en/scene/userproperties/slider.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| default/min/max/fraction/precision UI | `L3` | min/max/step/fraction/precision、UI 和持久化；[E-PROPERTY](runtime-evidence-index.md#e-property) | authored range/step validation 与 live value |
| numeric target update | `L2` | layer alpha slider 与 exact `brcontraststrength` 已 typed/clamp/live；其余 numeric target 仍重建 | 每个 target 分别补 compiler semantic 与 consumer 后才能升级 |

<a id="op-user-checkbox"></a>
### 5.4 [Checkbox](https://docs.wallpaperengine.io/en/scene/userproperties/checkbox.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `bool` control/value | `L3` | UI、条件值、持久化和受支持 visibility/boolean target；[E-PROPERTY](runtime-evidence-index.md#e-property) | live target program；不得按 property 名猜 effect |
| conditional target expected value | `L3` | binding 保存 `condition` 并比较实际 bool/value | 完整类型不匹配和 fallback 反例 |

<a id="op-user-combo"></a>
### 5.5 [Combo](https://docs.wallpaperengine.io/en/scene/userproperties/combo.html)

Combo option 的显示 label 与 hidden value 是两个字段；binding、Display Condition 和 SceneScript 都必须得到 hidden value，不能把本地化 label 当协议值。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| ordered label + hidden value options | `L3` | option label/value、条件和持久化已分离；[E-PROPERTY](runtime-evidence-index.md#e-property) | 重复 hidden value、未知当前值和本地化负向门 |
| combo conditional binding | `L3` | 与 authored option value 比较后控制受支持 target | 编译 target program；不能比较 label |

<a id="op-user-text"></a>
### 5.6 [Text Input](https://docs.wallpaperengine.io/en/scene/userproperties/text.html)

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `textinput` control/value | `L3` | UI、默认值和持久化；[E-PROPERTY](runtime-evidence-index.md#e-property) | Unicode 长度/invalid text policy |
| real-time text target update | `L3` | direct content/point-size/color 经 per-surface snapshot 和 per-layer async generation 更新；重复值去重，stale/failed completion 不替换 last-ready texture；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | SceneScript/time/media producer、长文本布局和 Windows golden |
| author `text` label | `L3` | 只读面板内容；[E-PROPERTY](runtime-evidence-index.md#e-property) | 它不是可写 runtime property |

<a id="op-user-texture"></a>
### 5.7 [Texture](https://docs.wallpaperengine.io/en/scene/userproperties/texture.html)

官方 Texture property 可替换 image layer、effect mask 或 particle texture，允许兼容的 image/video；用户未选择文件时必须使用作者导入的 texture。替换 texture 不会自动重做作者 effect 或 mask，因此播放器必须继续使用原有 graph/mask，不能根据新图片内容猜适配。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `texture` / observed `scenetexture` identity | `L1` | 两种 raw type 归一并保留 runtimeType | 只证明当前 parser 兼容归一，不宣称所有版本 schema 等价 |
| PNG/JPEG picker/bookmark/provider | `L3` | security scope、decode、per-screen upload，以及由现役authored-effect catalog授权的bounded Blend/property texture consumer；B22已删除独立ImageBlend plan/runtime及其额外property execution授权，见[E-PROVIDER](runtime-evidence-index.md#e-provider)与[E-R4-B22-INDEPENDENT-IMAGE-BLEND-RETIREMENT](runtime-evidence-index.md#e-r4-b22-independent-image-blend-retirement) | cancellation、更多格式和通用 material；普通authored Blend不外推generic consumer |
| authored texture fallback | `L3 bounded` | 现役受限 consumer与R3 material contract只在选中property identity被生产者**显式发布为absent**时回退作者纹理；missing state、pending、unavailable、ready publication不完整或identity不匹配均失败关闭，不能把故障解释成“用户未选择”；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program) | 推广至image albedo/effect mask/particle/material GPU consumer，并补更多provider lifecycle门 |
| generic image/video replacement targets | `L0` | effect mask、particle texture、video 和普通 albedo 没有通用 consumer | target/slot identity、自动尺寸映射、格式、generation 和 teardown |

<a id="op-user-texture-variants"></a>
### 5.8 [Texture Variants](https://docs.wallpaperengine.io/en/scene/userproperties/texturevariant.html)

Texture Variant 只能由 Checkbox/Combo User Property 控制，不能由 SceneScript 切换。variant 与 base 必须同为 image 或同为 video，并具有相同分辨率；每个 variant group 同时只显示一个 texture。Combo 多选时应保留一个未分配 option 代表 base texture。`Replace` 与 `Alpha-blended` 是不同合成语义；透明叠加元素要使用独立 group，因为一个 group 不会同时显示两个 variant。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| variant group/option/condition IR | `L0` | 无 schema | group order、Checkbox/Combo hidden value 和 base option |
| type/resolution compatibility | `L0` | 无 validation | image/video 同类型同分辨率正反 fixture |
| one-active-per-group selection | `L0` | 无 selector/provider identity | base fallback、未匹配值和 property generation |
| Replace / Alpha-blended compose | `L0` | 无 executor | 独立 group、alpha/premultiply/order pixel gates |
| SceneScript mutation prohibition | `L0` | 无 VM；未来 API 不得暴露 variant setter | API surface negative test |

<a id="op-user-shortcut"></a>
### 5.9 [User Shortcut](https://docs.wallpaperengine.io/en/scene/userproperties/usershortcut.html)

User Shortcut 可由用户绑定 file、directory、web page 或 console command，但只能通过 SceneScript cursor click 调用 `engine.openUserShortcut(key)`；一次 click/up/down CursorEvent 只允许执行一个 command，重叠 layer 需要作者关闭 click propagation。shortcut 绑定到本机，不能跨电脑共享，也不进入 wallpaper preset，用户必须逐机配置。可选 icon 可作为 texture，`applyUserProperties` payload 通过 `isbound` 和 `file` 暴露绑定状态/label。

| 官方类型/行为 | 等级 | 当前能力 | 缺口 |
|---|---|---|---|
| `usershortcut` definition/persistence | `L0` | parser 归入 unsupported | macOS 类型/授权、逐机存储、preset 排除和安全 UI |
| cursor-triggered open | callback `L3 bounded`；shortcut API `L0` | generic QuickJS cursorDown/up/click与captured owner已执行，但没有`openUserShortcut` host API或本机授权/绑定存储 | ordered单事件单命令、click propagation、invalid key与权限门 |
| shortcut icon provider | `L0` | 无 shortcut provider | bound/unbound generation、square icon fallback 和取消 |
| `isbound` / `file` change payload | `L0` | 无 `applyUserProperties` event | first/full 与 change-only payload、隐私与屏保策略 |

下表沿用 21 样本 target census 快照：424 definitions、952 bindings、195 条 conditional bindings。它只用于解释既有 target 分布，数字不是当前 corpus fingerprint、产品支持率或开发顺序；当前能力以每行代码/运行证据和[总台账](coverage-ledger.md)为准。

## 6. User Property target 矩阵

| target 族 | 观察数量 | 当前分类/执行 | 等级 | 下一门 |
|---|---:|---|---|---|
| layer visibility | 230 | 可分类；受支持 key 通过文档改写和整场重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | 编译 target program；visibility graph invalidation |
| text content/point size/color | 267 | direct binding 编译为 typed text target；有效可见层经 per-layer generation 无重建更新，hidden/no-consumer 整 key 重建；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | `L3` | SceneScript/system/media producer与 Windows layout golden |
| camera binding family | 5 | 字段名可识别；整族没有统一 executor | `L1` | typed compiler 分出可执行与 unsupported |
| camera parallax actionable subset | 3 | 当前白名单经重建生效；[E-PROPERTY](runtime-evidence-index.md#e-property) | `L3` | live camera target 和无重建门 |
| camera shake subset | 2 | 旧target-census中的binding已由2D orthographic bounded consumer执行；四个字段只在有效正交projection时可操作，修改触发rebuild且没有fake live consumer；[E-CAMERA-SHAKE](runtime-evidence-index.md#e-camera-shake) | `L3 bounded` | 重新按同口径统计binding；真正perspective/3D、live/SceneScript与Windows golden |
| effect visibility family | 129（最近一次authored snapshot） | target path与稳定layer/effect identity可识别；direct bool现在由通用binding compiler映射为typed target，不再依赖X-Ray或effect path。这个数字未因受控fixture或本批运行增加，也不证明129项存在执行consumer | `L2 structural` | 条件binding、duplicate/mixed producer、未命中共享startup-safe predicate的FBO/复杂topology与各effect consumer仍逐项准入 |
| effect visibility actionable subset | 22 authored rebuild口径 + 已证cohorts（2 authored FBO owner targets兼startup、1 controlled pair-leaf/X-Ray startup lifecycle、5 earlier startup leaf、2 same-key startup suffix） | 20条旧白名单与2条Local Contrast继续按既有重建口径生效；controlled `9000000131:69#effect#131`在already-admitted pair leaf内消费exact bool，现又以authored false→true闭合current-stock X-Ray candidate撤权。真实`3211615441:24#effect#613`与`26#effect#257`既完成active FBO live/owner迁移，又在`blur=false`启动时与`24#effect#922`、`26#effect#932`两条VHS suffix组成四target完整bool fan-out；frame0/1 typed inactive，live true后两Blur建立各自双FBO并与suffix共同进入Program/next-frame，0 dedicated/fallback。真实`3767460992`的5个startup-false安全leaf进入共享graph，其中Film Grain `17#effect#725`已由`sparklyonoff=true`激活普通Program，另3项无Program只持有graph passthrough member。[E-PROPERTY](runtime-evidence-index.md#e-property) [E-V1-XRAY-STARTUP-FALSE-SCALAR-OWNER](runtime-evidence-index.md#e-v1-xray-startup-false-scalar-owner) [E-V1-XRAY-SHARED-STAGE-ACTIVATION-OWNER](runtime-evidence-index.md#e-v1-xray-shared-stage-activation-owner) [E-V1-FBO-STAGE-ACTIVATION](runtime-evidence-index.md#e-v1-fbo-stage-activation) [E-V1-STANDARD-BLUR-DIRECT-BOOL-VISIBILITY-OWNER](runtime-evidence-index.md#e-v1-standard-blur-direct-bool-visibility-owner) [E-V1-STARTUP-FALSE-EFFECT-VISIBILITY](runtime-evidence-index.md#e-v1-startup-false-effect-visibility) [E-V1-STARTUP-INACTIVE-SAFE-FBO](runtime-evidence-index.md#e-v1-startup-inactive-safe-fbo) | `L3 bounded / exact Blur two-target + X-Ray startup lifecycle owner-migration + V1-A correctness` | controlled target不计corpus；cohort计数不刷新129项全census。candidate撤权仍由compiler guard与可执行partition门证明；不安全FBO/target/dependency/command、Timeline/SceneScript、persistent/unique/history、read-before-write、descriptor mismatch、condition/function/compose与完整authored consumer census仍缺或明确关闭 |
| shader constant family | 122 | UserPropertyBindings census保留target path/value；v22继承Local Contrast/Opacity exact typed target，target identity不等于旧strict renderer owner | `L1` | typed uniform/pass identity和完整compiler |
| shader constant actionable subset | 20 + 5 bounded | census的19条旧白名单经重建进入受限executor；Local Contrast strength与`1937925563:13#effect#321`的direct vector3 `tinthigh`现由共享Program live消费snapshot，fragment-only scalar direct-user能力另由同资源树受控重包的`noiseamount`正反例闭合，`2902406982:[365,372,647,664]` stock Opacity alpha继续由其现役bounded consumer读取；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property)、[E-V1-PULSE-FRAGMENT-SCALAR-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-fragment-scalar-user-property-owner)、[E-V1-PULSE-TYPED-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-typed-user-property-owner) | `L3` | 数字仍是authored census，不把受控scalar fixture计为新corpus实例；其他generic executor、SceneScript与通用live uniform仍待闭合 |
| shader constant equal-lane scalar consumer subset | 2 authored active + 1 controlled source-route target | 真实`3211615441`的`24#effect#613`与`26#effect#257`把同一`blurratio` scalar通过上述严格consumer projection写入两个已预检active ABI/default的Gaussian pass `float2` scale；受控`9000000966:148#effect#151`在copy+passthrough captured-main中用同一合同消费`blurscale`，无mask与typed static opacity-mask两个readiness组合都由共享MaterialProgram/GraphExecutor执行。route rollback只保留previous-current且不复活dedicated owner。[E-V1-STANDARD-BLUR-USER-SCALAR-SPLAT-OWNER](runtime-evidence-index.md#e-v1-standard-blur-user-scalar-splat-owner) [E-V1-STANDARD-BLUR-COPY-PASSTHROUGH-USER-SCALAR-OWNER](runtime-evidence-index.md#e-v1-standard-blur-copy-passthrough-user-scalar-owner) [E-V1-STANDARD-BLUR-MASKED-COPY-PASSTHROUGH-USER-SCALAR-OWNER](runtime-evidence-index.md#e-v1-standard-blur-masked-copy-passthrough-user-scalar-owner) | `L3 bounded / S4 owner-migration` | controlled target不计入authored active；不外推动态mask/provider、其他shader constant、unequal vector、多个property、Timeline/SceneScript、其他Standard Blur remainder或通用scalar broadcast |
| shader constant exact direct user-property consumer subset | 1 authored active + 4 controlled scalar targets | 真实`1937925563:13#effect#321`把`triangle_neon_color` vector3按exact target/fallback/`float3` ABI与`0...1`颜色域写入`tinthigh`；其资源树受控重包先证明fragment-only `noiseamount`的live/range/missing，再以`9000000967`把`speed + amount + noiseamount`同时绑定到一个scalar property，证明same-domain `{vertex,fragment}` consumer set。基于真实`3738202317:16#effect#45`的受控`9000000968`让stock `phase` producer按vertex `0...1`、fragment `0...6.282`分别编码；基于真实`2241938645:68#effect#133`的受控`9000000969`又让historical `phase`只按fragment `0...6.282`编码。四类scalar slice都只在launch producer key/target/type与每个expected stage的ABI/domain精确一致时撤权，exact producer不存在且旧plan仍可接纳时不撤权。各profile-local rollback均保持0 dedicated、目标previous-current与后缀compositor/next-frame存活。[E-V1-PULSE-HISTORICAL-FRAGMENT-PHASE-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-historical-fragment-phase-user-property-owner) [E-V1-PULSE-STAGE-INDEXED-PHASE-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-stage-indexed-phase-user-property-owner) [E-V1-PULSE-CROSS-STAGE-SCALAR-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-cross-stage-scalar-user-property-owner) [E-V1-PULSE-FRAGMENT-SCALAR-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-fragment-scalar-user-property-owner) [E-V1-PULSE-TYPED-USER-PROPERTY-OWNER](runtime-evidence-index.md#e-v1-pulse-typed-user-property-owner) | `L3 bounded / vector3 + producer-present scalar S4 owner-migration` | authored active计数仍为1；四个受控scalar target均不计入corpus。关系域`bounds`、其他float2、alpha/audio+binding、其他property/type/effect、广播、Timeline/SceneScript、多contributor、整个Pulse family或视觉parity不外推 |
| layer alpha | 73 | 编译为 `.layer(.alpha)`；image/solid/text 读取 per-surface snapshot，当前 census 没有 particle/utility alpha binding；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 扩展到新 layer kind 前先补对应 consumer；mixed/no-consumer 继续重建 |
| layer color | 73 | 全部目标为 solid；25 条纯 color key 由 snapshot/tint live 消费并在属性面板开放，48 条 `basecolor` 因同键含未支持目标整场重建；[E-LIVE-PROPERTY](runtime-evidence-index.md#e-live-property) | `L3` | 补颜色空间/premultiply golden；non-solid/mixed target 继续 fail closed |
| Puppet animation visibility | 2（`3769688830`） | `objects[].animationlayers[].visible` 解析为稳定 layer/animation-layer identity，direct bool User Property 编译为 typed target，并由 bounded Puppet playback 每帧 snapshot 消费；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc) | `L3 bounded` | condition/SceneScript、无稳定 ID、冲突 mixing 与 topology mutation 继续 fail closed |
| script instance properties | 43 | 路径存在；不保存源码/绑定程序 | `L1` | 编译 `.scriptInstanceProperty`，等待 VM consumer |
| particle instance override | 6 | authored 静态 override 可消费；动态 binding 未分类 | `L1` | alpha/count/size/speed/color typed target |
| Scene bloom/threshold target identity | 2 | `.scene(.bloomEnabled/.bloomThreshold)` 已定义，binding 尚未分类 | `L1` | 稳定 authored path、type 与 scope |
| Scene bloom/threshold binding/runtime | 2 | 无 binding compiler、producer 或 Scene post consumer | `L0` | target program + HDR post chain |
| layer scale | 1 | binding 未分类；静态 transform 可执行 | `L1` | typed transform target 与 frame geometry |
| sound volume target identity | 1 | `.layer(.volume)` 已定义，binding 未分类 | `L1` | binding compiler 和 sound owner identity |
| sound volume runtime | 1 | 无 sound IR/player | `L0` | playback/lifecycle 后再开放 |

该 census 的 unsupported 总数没有按当前 schema 重算，因此不得引用其聚合数量。当前已确认 alpha/color、Local Contrast、Opacity 与 direct text target 进入 binding program；mixed、hidden/no-consumer、non-solid color、其他 shader constant 和 unsupported key 仍由 rebuild/fail-closed 路径处理。

## 7. Text

| 能力 | 等级 | 当前边界 | 下一门 |
|---|---|---|---|
| static content raster | `L3` | CoreText 启动时栅格；[E-TEXT](runtime-evidence-index.md#e-text) | dynamic layer texture store |
| package/system font resolution | `L3` | 包内字体、8 个官方 `systemfont_*` 别名，15 个客户端 stock 名字全部随包真实字体（8 原版 `stockBundled` / 7 替代 `stockSubstituted`；stock 41/alias 19/包内 184/未知 0）；[E-TEXT-FONTREF](runtime-evidence-index.md#e-text-fontref) | 7 个替代字形非官方轮廓；原版无 Windows 栅格化逐像素对照；family/weight/CJK/emoji golden |
| point size | `L3` | authored `pointsize * 300 / 72` 官方 300 DPI 换算；[E-TEXT-POINTSIZE](runtime-evidence-index.md#e-text-pointsize) | Windows 逐像素对照、去掉本地 1024 px 字号夹取 |
| alignment/padding geometry | `L3` | left/center/right × center/top/bottom 同时进入 CoreText 和 quad pivot；作者 `size` 是含 padding 外框，边对齐以内容边钉住 origin，动态扩框使用当前 render size 归一化 padding；[E-TEXT-PIVOT](runtime-evidence-index.md#e-text-pivot) | Windows 字体/像素 golden、effect 越界裁剪对照 |
| baseline/`blockalign` | `L1` | 字段可见但未形成独立 baseline/block alignment 执行合同 | parser + CoreText baseline/块对齐正反门 |
| row/width overflow limits | `L3` | `limitrows`/`maxrows`/`limitwidth`/`maxwidth`/`limituseellipsis` 进 IR 并由 CoreText 消费，两个数值只在对应开关打开时生效（语料 393 个关闭态带默认 `maxwidth: 500`，79 个已超宽）；bounded Timeline `maxwidth` 复用同一 CoreText consumer，端点与实际消费的 Bézier controls 均需在预算内，并以每层单在途任务合并连续重栅格；[E-TEXT-LIMITS](runtime-evidence-index.md#e-text-limits) | Windows 逐像素对照省略号回退与断点、多屏连续宽度压力门 |
| color/alpha | `L3` | 静态 descriptor 和 direct color generation consumer；[E-DYNAMIC-TEXT](runtime-evidence-index.md#e-dynamic-text) | premultiplied alpha 与 Windows golden |
| outline/shadow/text effects | `L1` | 可见字段/effect 可能被保留 | 独立 style IR 与执行器 |
| property-driven dynamic text | `L3` | 只更新变化 layer，重复值不生成；并发旧 generation/失败结果不覆盖 last-ready，连续 Timeline 则每层只保留一个在途任务、发布单调中间结果后只追最新 generation；真实 `2134765860` 三字段与 `2902406982` 两条 width Timeline 正门 | 长文本/emoji/多语言布局与多屏压力门 |
| fixed native clock/day/date/greeting text | `L0 product owner / historical` | 七个exact source/property profile已于R4-B18删除；B18前报告只作历史，不证明现役Text owner、输出或视觉 | 现役只看下一行bounded AST；`clockWithPeriod`、greeting与其他未准入语法保留authored fallback |
| bounded property-bound text update | `L3 bounded` | B18后唯一现役Text脚本合同：唯一exported `update(value)`解析为无循环AST；primitive property、变量/条件/赋值、`new Date()` getter、string拼接/`slice`由三层预算执行，不依赖sample/layer/source hash；compile/evaluate失败不覆盖作者文字 | 完整ECMAScript/coercion/scope/exception、init/engine/event/module、live script-property event、locale/DST/离线clock adapter |
| fixed native delayed-loop/day-night texture animation | `L0 product owner / historical` | B19已删除两个source SHA profile、compiler、playback plan、专用clock与wall-date sprite plumbing；TextureAnimation SceneScript仍保真但不执行 | 旧delayed-loop/time-of-day报告只作历史，不证明现役owner、当前时序或视觉；通用handle、cursor click、persisted override与Windows timing仍未实现，见 [E-R4-B19](runtime-evidence-index.md#e-r4-b19-fixed-texture-animation-profile-retirement) |
| bounded media placeholder fade | `L3 bounded` | 严格stopped-rise/active-fall结构把effect alpha写入既有Opacity consumer；真实两样本共5层首帧/下一帧GPU与compositor完成，293三个局部区域出现此前缺失的封面/标题/歌手内容 | 无live provider；逆向fade、metadata/text/colors、shared/cursor/angles、其他effect constant与通用VM失败关闭 |
| generic SceneScript/media text | scalar/String VM与thumbnail/playback/properties event `L3 bounded` | QuickJS-NG已执行pass scalar、object-owned String、`WEMath`、immutable engine frame input与三个typed media event；旧placeholder fade已由generic playback event取代。没有live macOS producer、完整media handle/event queue或file module graph | 扩展typed producer时保持syntax/value/budget/lifecycle fail-closed；不得从三个bounded event外推完整media API |
| dynamic Layer Image particle source | `L0` | 无 emission bitmap refresh | 只在 text texture 变化时更新 emission source |

## 8. Cursor、Audio 与 Media

| 输入/provider | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| current pointer bounded projection | `L3 bounded` | view-normalized -> scene world；image-effect Frame Context 另把current/previous投影到同一Program host schema。fresh `3767343314:17#effect#234`固定hover输入已由共享Program/GraphExecutor消费并闭合GPU/publication/compositor/next-frame；[E-V1-CURSOR-RIPPLE-SHARED-FEEDBACK-OWNER](runtime-evidence-index.md#e-v1-cursor-ripple-shared-feedback-owner) | 只证明一个image-effect/effect-matrix consumer和整层安全输出；完整parent/world/control-point逆矩阵、outside/rotation/scale/parallax正反golden与独立Cursor ROI仍缺 |
| full layer/effect/control-point local pointer | `L0` | 无 parent/world inverse 或 effect/control-point 投影 | hierarchy/rotation/scale/parallax 正反 golden |
| previous pointer storage | `L3 bounded` | Frame Context 保存并由Program的`g_PointerPositionLast` host uniform消费；fresh Cursor feedback运行与current pointer同链闭合，但没有单独方向性ROI或event-delta断言 | 其他shader consumer、通用event delta、完整坐标逆变换与Windows同输入golden |
| pointer buttons/down/up/click | generic `L3 bounded / S4 click-visible` | AppKit primary state经surface-local hit-test派发QuickJS down并捕获owner，release向capture派发up，同一object仍命中再派发click；Program host schema仍把primary编码到bounded `g_PointerState.z`。真实`2974757317`exact一次press/release/click使卡片折叠，旧native launch owner已删除 | `g_PointerState`不是已登记的`official-public-contract`；button edge按host frame采样，缺ordered sub-frame queue，快速点击可能漏失。多button、drag-out/capture真实门、候选传播与官方对照仍缺 |
| generic cursor enter/leave | `L3 bounded / S4 visible` | AppKit move/enter/exit经实际camera/world/model inverse与quad hit-test向QuickJS object owner派发immutable world/local Vec3 event；旧native hover owner已删除。真实`2974757317`exact 1 enter + 1 leave并产生可见卡片位移 | parent/rotated/puppet、跨owner顺序、边界抖动、move、ordered queue与官方坐标/事件对照；见 [E-V2-SCENESCRIPT-CURSOR-ENTER-LEAVE](runtime-evidence-index.md#e-v2-scenescript-cursor-enter-leave) |
| audio declarations | `L3` | effect 与粒子两套 schema 分别保真解析（字段名不同，粒子无 `audioamount`）；[E-AUDIO-EFFECT](runtime-evidence-index.md#e-audio-effect) | 粒子声明保真不等于可执行 |
| 16 stereo buffers | `L3` | left/right host-shared 快照每帧广播给所有 surface，静音/无权限稳定归零；stock effect 与统一Program中的relocated Simple Audio Bars stereo up/down作者shader已消费；旧Simple专用consumer已删除；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 频段划分与归一化是工程选择，无官方数值合同；采集 30 Hz 与渲染 60 Hz 之间不插值 |
| 32/64 stereo buffers | `L3 bounded` | 与 16 档由同一次 FFT 生成并进入 host-shared snapshot；供统一Program中的Simple Audio Bars 32/64-band作者shader、Workshop Audio Hue已证作者Program及其他现役effect consumer；旧Simple、Audio Hue与fixed SceneScript Audio Bars专用consumer均已删除；[E-AUDIO-INPUT](runtime-evidence-index.md#e-audio-input) | 其他 Workshop shader 与通用 SceneScript `registerAudioBuffers` 尚无 consumer/bridge，不外推 |
| SceneScript `AudioBuffers` / `average` API | `L0` | host snapshot 只有 left/right；两个 bounded native consumer 在 renderer geometry 内按 `(left + right) / 2` 逐 bin 派生 average，但没有 JS object、Float32Array identity 或订阅 lifecycle | 由通用 SceneScript bridge 建立逐帧受控数组，并验证对象/数组生命周期 |
| audio consumer registration/lifecycle | `L3` | 采集由 consumer 存在性驱动，launch 声明/teardown 撤销，暂停/锁屏/休眠停采并归零；统一Program按实际反射出的audio host uniform声明需求，Simple Audio Bars、Workshop Audio Hue与既有effect consumer共用同一次host snapshot，专用Audio Hue owner删除后需求不丢失 | 新增 consumer 必须同批扩充判定，否则采集不会启动 |
| Scene Sound layer / self-playback | `L0` | `3743305891` authored FLAC 尚未解码/播放；当前 system tap 排除本进程，不会把该声音回送成 Scene 频谱 | sound content IR、提取/解码、状态/volume/teardown，以及 wallpaper-local 频谱源的独立合同 |
| media playback/colors/title/artist snapshot | `L2 wired` | producer-agnostic inbox保存playback、artwork colors、title/artist及独立generation；bounded fade/color/text consumer已接到同一frame transaction。当前无新runtime/ROI | live producer、missing-field/clear语义、fresh visible门 |
| media status/album/timeline | `L0` | 无完整typed snapshot或consumer | 可注入 provider、原子 generation与generic event/VM bridge |
| generic media thumbnail identity | `L3 bounded current cover` | `$mediaThumbnail`是现役system identity；replacement pending保留last-ready current/generation，ready后原子发布current。B20删除`$mediaPreviousThumbnail`产品identity/publication与gradient transition | live platform producer、previous/transition/variant、通用media event与SceneScript lifecycle |
| media events | `L0` | 无 SceneScript dispatch | 每屏队列、顺序和异常隔离 |

Scene 不复用 Web 的固定 FFT 频段/频率合同；SceneScript 按作者选择 16、32 或 64 bins，并在 render frame 更新。

官方 [IEngine.registerAudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IEngine.html) 只接受 16/32/64 三档，[AudioBuffers](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/AudioBuffers.html) 的 `left`/`right`/`average` 等长数组按帧自动更新、由低频排到高频，数值通常在 0...1 但允许超过 1；shader 侧 [Audio globals](https://docs.wallpaperengine.io/en/scene/shader/variables.html) 同样明确为正值且不归一化。当前16/32/64 host snapshot满足effect renderer consumer的输入形状；B21已删除曾逐bin求average的两个fixed native audio profile。项目没有SceneScript VM、engine method、`average`数组对象或脚本订阅，因此不能据此升级任何SceneScript API。

<a id="op-media-overview"></a>
### 8.1 [Audio Visualizer](https://docs.wallpaperengine.io/en/scene/audiovisualizer/overview.html) 资料边界

官方 Audio Visualizer overview 明确仍在建设，目前只公开 Album Cover 和 Media Playback 两篇作者指南。这两个页面不能反向证明完整 audio visualization、FFT 映射或 Windows media backend 私有行为；Scene 的频谱、媒体和 Web audio 合同继续分开建账。

<a id="op-media-information"></a>
### 8.2 [Media Information](https://docs.wallpaperengine.io/en/scene/audiovisualizer/mediainformation.html) 与动态文字

官方通过 SceneScript media events 提供 title、album title、artist、playback/status、timeline 和 thumbnail 派生颜色，但媒体播放器或文件可能不提供某些 metadata。作者必须允许字段缺失。动态媒体文字可能很长，官方要求用 text `Point size` 调字号，不用 layer `Scale` 降低清晰度，并配置 left alignment、`Max width`、`Max rows` 和可选 overflow ellipsis。Playback `stopped` 与 `paused` 不同；官方隐藏示例只在 stopped 时隐藏，paused 仍显示。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| playback/colors/title/artist snapshot | `L2 wired` | inbox与frame driver已有typed generation和bounded consumer；没有fresh runtime evidence | 可注入同host-frame原子更新、clear/missing、stale与多surface门 |
| status/album/timeline snapshot | `L0` | 尚无完整producer/consumer | typed optional fields与原子generation |
| media property events | `L0 generic` | bounded native title/artist projection不是SceneScript event | title/albumTitle/albumArtist等typed event和逐surface queue |
| missing metadata fallback | `L2 wiring incomplete` | title/artist snapshot可为空，但没有fresh切歌/clear证据 | 缺字段不得保留上一首错误文本；作者fallback/空值策略可测 |
| media text layout constraints | `L2 wired` | typed title/artist可进入bounded text runtime；尚无fresh可见门 | point size、max width/rows、ellipsis和长Unicode title golden |
| stopped versus paused visibility | `L2 bounded wiring` | bounded playback-state fade consumer已存在；没有live provider与fresh event门 | 枚举映射、初始stopped、paused保持可见和恢复顺序 |
| thumbnail derived colors | `L2 wired` | artwork color snapshot与bounded transition consumer已接线；不等于generic `MediaThumbnailEvent` | primary/text/其他公开色值、无thumbnail fallback与fresh ROI |
| authored color transition | `L2 bounded wiring` | bounded native projection按simulation delta更新；不是通用作者SceneScript | VM event/update链、作者数学、fresh dynamic ROI与Windows timing |

<a id="op-media-album-cover"></a>
### 8.3 [Current / Previous Album Cover](https://docs.wallpaperengine.io/en/scene/audiovisualizer/albumcover.html)

官方 Album Cover binding 明确区分 `Current album cover` 和 `Previous album cover`。没有媒体或封面时作者 placeholder 必须继续可见；建议封面使用方形 `100x100...256x256`，不把高分辨率封面当作可靠输入。平滑换封面不是 provider 自动效果：官方配方是 current cover 作为当前图，previous cover 绑定到 Blend/Blend Gradient 输入，再由 `Single`、`Start paused` 的 Timeline 控制 Blend amount，并在 `mediaThumbnailChanged` 中播放 animation。

| 官方能力 | 等级 | 当前事实 | 最小实现门 |
|---|---|---|---|
| `$mediaThumbnail` generic reference | `L3 bounded current` | frame registry对显式current publication执行generation前进、同代换纹理和stale拒绝；严格normal/full-strength Blend source replacement与通用visibility binding消费同一typed current identity | generic material、previous/transition/variant与通用event consumer |
| current cover identity/provider | `L3 bounded` | producer-agnostic current-only inbox原子发布encoded current；共享store为每代建立可取消request，新代使排队旧任务在ImageIO前退出，并在current decode/upload边界协作停止已开始的旧任务；publication继续以request identity + requested generation拒绝过期completion。replacement decode未完成时发布last-ready current/content generation，最长边限制256，ready后换代广播所有surface；当前只有隔离debug producer，见 [E-MEDIA-THUMBNAIL](runtime-evidence-index.md#e-media-thumbnail) | 单次ImageIO调用不可抢占；macOS live producer、权限/播放器lifecycle、结构化decode status telemetry与真实切歌门仍缺失 |
| previous cover identity/provider | `L0 product owner / historical` | B20已删除previous payload、identity、publication、decode及所有transition输出；旧A→B→C previous与per-surface transition报告只作历史 | 重新实现需公共typed previous provider与统一graph/event consumer，不得恢复fixed source/profile |
| authored placeholder fallback | `L3 bounded` | 首次没有 current、显式 clear 完成或 replacement decode 最终失败时不覆盖作者 image/solid；已有 current 的 replacement pending 继续显示 last-ready，不再瞬时闪回 placeholder。只为 normal/full-strength、单纹理 current Blend 和通用 `mediaThumbnailChanged(event){ thisObject.visible=event.hasThumbnail; }` 可见性合同准入 layer-source replacement | 其他 Blend mode/强度/transform/mask、多纹理、任意脚本或 generic effect consumer |
| authored cover transition graph | `L0 product owner / historical` | B20删除fixed source/SHA compiler、gradient loader、pipeline、renderer、per-surface encode与layer-source replacement；旧Single/Start paused/stop-play/gradient wipe报告仅描述B20前实现 | generic Blend Gradient、typed previous provider、统一graph/event调度、真实平台切歌与Windows timing/pixel golden |
| recommended cover extent policy | `L2` | encoded input 限 16 MiB，ImageIO thumbnail 保持比例且最长边限 256；只接受可解码 PNG/JPEG 路径作为隔离证据输入 | 非方形/异常 profile 的 GPU 几何门、色彩空间/orientation 与 Windows decode golden |
| live platform media producer | `L0` | 公共 inbox 已提供 producer 边界，但产品没有读取其他 macOS app 当前播放封面的系统 adapter | 选择可公开/可授权的系统来源，定义 start/pause/stop、缺封面、切歌和多播放器仲裁 |

## 9. Texture / Video provider

| provider 能力 | 等级 | 当前能力 | 下一门 |
|---|---|---|---|
| layer/named/graph/asset/property/system identity/status/generation | `L3 bounded；generic carrier L2` | R3统一`SceneFrameTextureIdentity`与`SceneTextureProviderPublication(requestIdentity,candidate,contentGeneration)`；immutable frame snapshot同时冻结frame index、ready/incomplete/absent/pending/unavailable，字典missing仍可区分。candidate的identity/generation/purpose/content、physical/mapped、UV、sampler raw flags必须同代，stale、purpose/identity不匹配与半publication均拒绝。material asset catalog现保持immutable definitions；每个surface/runtime bridge独立持有FrameProvider，single-image animated TEX以exact path+purpose与file lifecycle复用同一GPU texture，同frame publication generation稳定，frame变化及wrap只单调推进content generation并原子更新UV。source revision不随帧变化，wrong request/purpose/provider/file lifecycle/generation与stale继续硬拒绝；既有direct text、embedded MP4和bounded current-cover生命周期不变，previous/transition identity已由B20删除；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program)、[E-V1-SINGLE-IMAGE-ANIMATED-MATERIAL-ATLAS](runtime-evidence-index.md#e-v1-single-image-animated-material-atlas) | graph FBO/effectOutput在command边界的publication、其他provider主动取消、device loss、platform producer/consumer lifecycle；animated material仍缺dynamic replacement、multi-image/rotated/trimmed/fractional frame与官方timing/pixel parity |
| authored fallback chain | `L3 bounded` | 受限static Blend现与R3 material resolver共用explicit-absent-only规则；missing/pending/unavailable/incomplete不能落回较低优先级作者候选；[E-PROVIDER](runtime-evidence-index.md#e-provider)、[E-MATERIAL-PROGRAM](runtime-evidence-index.md#e-material-program) | 推广至material/effect/nested GPU consumer，并逐类证明producer的absent语义 |
| property PNG/JPEG | `L3` | bookmark/security scope/decode/per-screen upload；[E-PROVIDER](runtime-evidence-index.md#e-provider) | cancellation、更多格式、通用 material |
| TEX atlas/sprite playback | `L3 bounded` | 既有base-layer/particle路径继续让普通单图atlas及BC1/2/3、axis-aligned/integer/same-extent的cross-image multi-image按scene time与作者frame duration循环；source按file generation/device跨surface去重，destination按实例计费并随playback释放，设备allocation聚合预算384 MiB。B19撤销fixed TextureAnimation profile不删除该公共autoplay能力。独立的material Program切片现只准已解析single-image、non-volume、nonempty、finite axis-aligned/in-bounds frame atlas；每个authored duration必须finite nonnegative，0按既有sprite autoplay规则规范为effective `1/60 s`。surface-scoped FrameProvider复用physical texture并逐帧发布UV/content generation；它不接管multi-image、base-layer、particle或TextureAnimation SceneScript owner；[E-PUPPET-BC](runtime-evidence-index.md#e-puppet-bc)、[E-V1-SINGLE-IMAGE-ANIMATED-MATERIAL-ATLAS](runtime-evidence-index.md#e-v1-single-image-animated-material-atlas) | material dynamic replacement、multi-image/rotated/trimmed/fractional/out-of-range frame，negative/nonfinite/aggregate-overflow duration，通用SceneScript handle/detach/join/rate/pause/seek/command/timer、Windows timing/color/alpha golden；既有multi-image owner本批未迁移，B19亦未刷新其运行或视觉证据 |
| embedded MP4 image layer | `L3 bounded` | TEX payload 由 launch-scoped registry 管理，按共享 SceneClock 映射 item time；同 frame 去重、成功帧换代，pause 保帧、resume/rebuild 连续、stop 释放；[E-VIDEO](runtime-evidence-index.md#e-video) | 真实系统 pause/hot-plug、seek、loop 首帧/黑场、codec/device-loss 与 Windows parity |
| video as generic material provider | `L0` | typed frame publication 已有，但没有 material/effect slot consumer | slot purpose/UV/sampler/format、fallback、动态尺寸与 generation 原子绑定 |
| named primary variant producer | `L3` | bounded `_a` current-frame publication；[E-UTILITY](runtime-evidence-index.md#e-utility) | 通用 target/extent/format |
| named secondary variant identity | `L2` | registry identity 保留 `_b` | producer/consumer flow 尚未执行 |
| Texture Variant provider | `L0` | 无 variant schema/selection | property selection + authored fallback |
| system/media provider identity | `L2 carrier` | Template保留exact system demand；production snapshot缺少唯一purpose、publication不完整或lifecycle未证时明确发布/解释为unavailable，不伪造absent。current `$mediaThumbnail` bounded producer仍走独立typed合同；previous/transition已撤权 | 统一live producer、purpose仲裁、generic consumer、pause/rebuild/stop与teardown |
| generic material slots `0...7` | `L3 bounded execution；arbitrary S0` | Template固定保留8项及hole；Program原子携带variant/reflection、purpose/readiness、candidate metadata、uniform/state/color与identity。每个active reflected texture slot现在强制两项`float4` host transform，finalizer/encoder把candidate `origin/xAxis/yAxis`写入exact per-frame bytes/identity；boundedSwift与generic artifact都在vertex/fragment、direct/helper及已支持LOD sample中消费。identity static像素等价，mapped/padded static与bounded animated frame共享通用UV correctness，transform值变化不重编Metal pipeline；bounded子集已由唯一GraphExecutor完成GPU/publication/compositor/next-frame | ordinary arbitrary authored stage仍缺完整通用backend；继续补unproven purpose、state/color/helper与FBO command publication。missing/malformed transform ABI、reserved authored name、stage drift、wrong identity/generation/stale必须typed拒绝，不在consumer重做优先级或建立兼容旁路 |

## 10. 现役路线与完成门

输入能力不再按旧B/R批次排序；唯一优先级见[Scene兼容执行路线](../scene-compatibility-roadmap.md)。

- V0/V1只补普通Program/graph当前真实消费的value、resource和topology invalidation，不为输入另建renderer状态。
- V2由per-scene QuickJS-NG VM接管generic script property、shared、handle、cursor/media/audio event与timer。
- V4逐项把property、pointer、audio、media、text和provider接入现有typed snapshot/publication/mutation；一个native bounded projection不升级对应generic SceneScript API。
- 每个新输入必须明确属于value-only、resource-generation、geometry/extent、program-variant或topology变化，只使最小owner失效。
- `311115e3`新接线在取得fresh产品运行和预定义ROI/事件证据前保持`S2 / visible unknown`；自动测试存在、formal matrix或非黑截图都不能替代。

普通material slots现已有bounded GPU consumer，旧`R3 gpuEncoded=0 / 下一步R4`已退役。arbitrary authored shader、generic VM、live media producer和完整event queue仍是明确待办。
