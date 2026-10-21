# Scene 全样本能力分类与修复事件台账

> 状态：现役 corpus 事实、公共结构影响面与修复事件索引。
>
> 本页由 `script/scene_capability_census.py` 的只读 authored corpus 快照投影；当前373行明细独立在[静态清单](scene-corpus-sample-inventory.md)，renderer失败/两页writer边界见下文；完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `.artifacts/scene-evidence/census/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。系统 current capability 只以 `coverage-ledger.md` 为摘要，逐项合同/专题内等级以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-current.md` 为准。

## 1. 当前结论

- 当前真实 Scene 根发现 **373** 个样本，**372/373** 的 project、PKGV 索引和入口 JSON 可解析。
- tracked full-matrix baseline仅45个历史成员、`pending-expansion`；该集合不是本轮运行分母。[验收台账](scene-sample-acceptance-ledger.md)现373目录关联260条混合身份运行、113未关联；本轮仅17新增样本重跑，不能把census未join旧matrix解释为从未播放。
- 全量 authored census 共保存 **176762** 个 typed occurrence、**4609** 个公共结构 family、**2394** 个参数 profile 与 **23126** 个 JSON 字段 profile。
- 物理 corpus 共 **29248** 个 PKG entry / **29244** 个唯一路径，包体约 **17.351 GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 45，期间不得称为当前完整快照门。
- package anomaly：样本 `3690065713` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 36/54，同字节；该包 107 entries / 106 unique paths）；样本 `3744157078` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 93/160，同字节；该包 167 entries / 166 unique paths）；样本 `3768724269` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 59/80，同字节；该包 87 entries / 86 unique paths）；样本 `3807013762` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 49/57，同字节；该包 73 entries / 72 unique paths）；重复entry继续保留在物理守恒中，不是漏扫。
- 结构 fallback 记录为 **93**，另有 **6** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。
- 公共能力粗映射：**4602** 个 family 按声明形态映射到台账登记能力，**7** 个显式 unknown（`{"effect-declaration-unresolved-static": 1, "project-property-kind-empty": 1, "project-property-kind-unknown": 5}`）；映射只表达声明覆盖关系，不表示运行支持。
- 开发按“真实可见链第一断裂边覆盖的共享 family”排序；大类用于汇总，不允许把所有纹理、Effect 或粒子一次性做成巨型补丁。

## 2. 口径与权威边界

1. 本 census 回答样本声明了什么：对象、Effect/Material/Shader/Graph/FBO、纹理、粒子、动态来源和参数形态。
2. `observed`、`resolved`、文件存在或 `repair_state` 都不等于 renderer 已支持；运行 owner、GPU、publication、compositor、next-frame 和 ROI 必须引用运行证据索引。
3. `repair_state` 只描述某个 family 的修复事件工作流。`implemented` 表示该事件所述改动已落地，可能只是保真、拒绝或故障隔离；它不是该 family 的能力实现、current、support 或待办状态。`untriaged` 只表示没有登记该 family 的修复事件，不能解释为 missing、unsupported 或 todo。
4. `family_key` 只由公共语义形态生成；sample/layer/path/hash 只作 evidence identity，产品实现不得按具体值 dispatch。
5. 所有参数以名称、类型、arity、范围、wrapper source 和结构签名记录；只保留 project title 元数据，不复制 layer 文字、shader、SceneScript、纹理、JSON 片段或二进制 payload。
6. 修好一族后在 `scene_capability_repair_ledger.json` 记录根因、公共修法、commit、正反门、真实样本、ROI、剩余边界；重新扫描不会覆盖历史，也不会据此改写 capability current。
7. 先以官方公开资料和当前 corpus 界定作者合同；只有公开材料不足、固定客户端静态证据仍不能回答 producer-to-consumer 链，或需要交叉核对结构时，才读取 MirageWallpaper 的明确固定 revision 并记录 divergence。Mirage 只提供 clean-room 的职责、状态流和顺序参考；其 GPL 源码、shader、资产、payload、常量组合、算法表达和测试数据不得进入项目。

## 3. 大类总览

| 大类 | occurrence | family | family 语义/专项入口（非 current 状态） |
|---|---:|---:|---|
| `resource` | 16083 | 14 | [格式/资源](scene-format-and-render-graph.md) |
| `shader` | 6380 | 403 | [Graph/Shader](render-graph-shader-coverage.md) |
| `layer` | 16077 | 2337 | [格式/对象](scene-format-and-render-graph.md) |
| `material` | 17506 | 68 | [Graph/Shader](render-graph-shader-coverage.md) |
| `effect` | 9819 | 15 | [Effect](effect-execution-coverage.md) |
| `render-graph` | 11734 | 28 | [Graph/Shader](render-graph-shader-coverage.md) |
| `render-target` | 1326 | 8 | [Graph/Shader](render-graph-shader-coverage.md) |
| `texture` | 32723 | 73 | [格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md) |
| `particle` | 32979 | 948 | [粒子](particle-component-coverage.md) |
| `audio-declaration` | 3714 | 40 | [音频声明](coverage-ledger.md) |
| `dynamic-input` | 19215 | 631 | [属性/输入](runtime-input-property-coverage.md) |
| `project-property` | 9206 | 44 | [属性/输入](runtime-input-property-coverage.md) |

### 3.1 纹理本体与使用点

- 包内物理 TEX：**6785**；格式分布：`{"0": 2920, "4": 586, "6": 30, "7": 36, "8": 837, "9": 2376}`。
- TEX 结构特征：`{"animated": 84, "static": 6701, "video-mp4": 5}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。
- 纹理使用 occurrence：**25938**；slot 状态：`{"hole": 6949, "missing": 108, "resolved": 14380, "runtime-provided": 4501}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。

### 3.2 对象、Effect 与动态输入

- 对象类型：`{"camera": 25, "image": 5849, "light": 51, "particle": 1209, "shape": 33, "sound": 233, "text": 1738, "utility": 1090}`；静态非 hidden：`{"camera": 21, "image": 3869, "light": 33, "particle": 956, "shape": 25, "sound": 233, "text": 1135, "utility": 898}`。
- Effect instance **9819**，粒子 root layer **1209**；动态 wrapper：`{"condition_wrappers": 1773, "script_wrappers": 6546, "timeline_wrappers": 1025, "user_bindings": 10125}`。
- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。

### 3.3 音频声明与 consumer 意图关系

- payload-free 音频关系共 **3714** 个 occurrence / **299** 个样本；其中 editor `supportsaudioprocessing=true` 为 **234** 个样本，存在至少一种非 project 声明关系的样本为 **299** 个。
- 标记有而没有非 project 声明关系：`无`；有声明关系而没有 editor 标记：`1553008362, 1636394814, 1695673397, 1926190458, 1994794519, 2069136288, 2112262451, 2269193950, 2473638329, 2505351195, 2524111047, 2607203340, 2616828675, 2775915974, 2797913147, 2802243144, 2811643059, 2824109832, 2896873092, 2942486721, 2959875782, 2987771245, 2998757800, 3021013015, 3025969015, 3088601835, 3167210190, 3187857248, 3221354414, 3323988600, 3395392965, 3486887298, 3549827466, 3576374111, 3663810817, 3680252478, 3699213569, 3703104370, 3721991999, 3738202317, 3750342273, 3750813609, 3757555836, 3762312138, 3764725758, 3766403294, 3767232084, 3769761761, 3770444459, 3781307553, 3782614820, 3782650329, 3786048634, 3786641495, 3787355076, 3788645041, 3790631363, 3790956325, 3791905266, 3793328876, 3801294161, 3803087940, 3807239614, 3807553861, 3822822401`。两者都不是运行支持集合，不能从静态相等或差集推导 capture demand。
- 静态 consumer 意图为 **174** 个样本：`1937925563, 2131872317, 2134765860, 2241938645, 2419444134, 2507971256, 2684431262, 2731896598, 2776912698, 2780710296, 2784267518, 2787219305, 2794098047, 2797943632, 2804817823, 2807058277, 2813231542, 2813240634, 2814167871, 2815826216, 2819143171, 2821634935, 2824690710, 2831174267, 2834973884, 2835398595, 2849382252, 2850139759, 2866086594, 2871552691, 2877499944, 2877855240, 2884170082, 2884628849, 2887542690, 2890473419, 2902406982, 2913492057, 2919854127, 2927205881, 2932157836, 2932631210, 2938612768, 2951452910, 2960821850, 2972071249, 2974757317, 2983846453, 2992924426, 2999907577, 3002649614, 3027056454, 3027068980, 3039704323, 3039882306, 3042492564, 3078285611, 3087231311, 3114332546, 3137495261, 3148125112, 3175039950, 3211615441, 3226487183, 3232289987, 3233141951, 3238423642, 3248220186, 3264246690, 3291326967, 3292370168, 3299228616, 3321237804, 3325624777, 3337494481, 3341111071, 3351163962, 3351179520, 3363252053, 3374523158, 3383535304, 3395777145, 3396722575, 3420215721, 3435573282, 3436945972, 3448845950, 3448877775, 3454689854, 3471294034, 3476868923, 3477054430, 3507496797, 3554161528, 3562021804, 3585542943, 3585875739, 3586705329, 3587571382, 3589454154, 3601964477, 3603711180, 3605722997, 3610154602, 3612199597, 3612795410, 3617056047, 3627973226, 3632513108, 3632522893, 3655958892, 3662790108, 3665307769, 3666041758, 3679907516, 3690065713, 3694697894, 3695791724, 3696646175, 3707474273, 3708363772, 3716328771, 3719111841, 3723344874, 3724289844, 3737432178, 3742497499, 3744157078, 3745828537, 3747190633, 3747492842, 3749463715, 3754639143, 3761619125, 3765904723, 3766299002, 3766310551, 3767460992, 3768020435, 3768229922, 3768724269, 3769688830, 3773747576, 3775655074, 3777761326, 3779026256, 3779107475, 3780119725, 3780391264, 3781757083, 3786330502, 3787382101, 3788066613, 3788467391, 3789316755, 3790806929, 3791967416, 3792249095, 3793998447, 3795384177, 3797217144, 3800356808, 3804441338, 3806202923, 3806337293, 3806836928, 3806887870, 3807013762, 3807151772, 3807668787, 3809034761, 3809609151, 3810943704, 3811154012`。这里只接受精确源码数组形状、显式启用的 material/particle 响应或 proven-global 且分辨率有效的 SceneScript 调用；material active variant/host ABI 与所有运行 execution 尚未 join，因此本批 runtime-confirmed 仍为 **0**。
- 其中同一 SceneScript owner 同时具有静态准入 AudioBuffers 与显式导出 cursor callback 的意图为 **3** 个样本：`3238423642, 3321237804, 3632513108`；这只登记实例化候选关系，不证明 hit、事件触发、snapshot refresh 或可见输出。
- editor 标记有而静态意图无：`2067939514, 2871175822, 2917306763, 2949019513, 2964778792, 2969308380, 3022080536, 3086016320, 3113287126, 3113554287, 3122339805, 3146507587, 3147346398, 3287715210, 3290491250, 3357627941, 3372715909, 3443450456, 3470948192, 3487629864, 3509243656, 3563038726, 3566880847, 3577990983, 3581882134, 3597772384, 3605502569, 3609108600, 3616389236, 3616476797, 3641200550, 3662390671, 3690859128, 3698459055, 3701177677, 3712499998, 3721456868, 3743305891, 3748311238, 3754630802, 3761159935, 3763428294, 3765760121, 3769364482, 3779904456, 3782740481, 3788734811, 3788897599, 3792400801, 3792817546, 3796588443, 3800075350, 3802005866, 3804906814, 3804971850, 3805547608, 3808922316, 3809618616, 3812473896, 3815761795`；静态意图有而 editor 标记无：`无`。普通 App 运行基线必须覆盖这些差集与全部声明关系，不能只测标记集合。

| 声明关系 | occurrence | 样本 | 静态状态分布 |
|---|---:|---:|---|
| `material-audio-response` | 269 | 84 | `{"activation": {"absent": 9, "disabled": 1, "enabled": 259}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `material-host-spectrum` | 2013 | 283 | `{"activation": {"disabled": 1, "enabled": 259, "not-authored": 1753}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {"launch-envelope-unjoined": 2013}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {"preprocessor-conditioned": 5662, "source-shape-exact": 128}}` |
| `particle-audio-response` | 141 | 32 | `{"activation": {"disabled": 4, "enabled": 80, "missing-mode": 57}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `project-support-enabled` | 234 | 234 | `{"activation": {}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `scenescript-registration` | 1057 | 154 | `{"activation": {}, "cursor_audio_consumer": {"no-cursor-event": 1053, "statically-admitted": 4}, "cursor_events": {"cursorEnter+cursorLeave": 4}, "runtime_admission": {}, "script_admission": {"resolution-unresolved": 156, "statically-admitted": 901}, "script_resolution": {"16": 824, "32": 12, "64": 65, "dynamic-or-invalid": 156}, "script_scope": {"proven-global": 1057}, "source_abi": {}}` |

## 4. 当前公共 family 影响面索引

> 这里只按静态可见覆盖排序，不能自动决定实施。最后一列是修复事件工作流，不是能力状态；`untriaged` 不表示缺失。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。

| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复事件（非能力状态） |
|---|---|---:|---:|---:|---|
| `texture/image-material-slot@2e7ce906c5bcf601` | `texture/image-material-slot` | 3339 | 357 | 2198 / 352 | `untriaged` |
| `material/effect-pass@526202cd27954701` | `material/effect-pass` | 10367 | 345 | 6558 / 343 | `untriaged` |
| `effect/authored-graph@9231d5e82bfe3a7f` | `effect/authored-graph` | 8508 | 337 | 5330 / 335 | `untriaged` |
| `render-graph/effect-pass@91c374f0320bbf80` | `render-graph/effect-pass` | 8508 | 337 | 5330 / 335 | `untriaged` |
| `material/image-pass@f0e77c0708dc8bfc` | `material/image-pass` | 2831 | 329 | 1832 / 321 | `untriaged` |
| `texture/effect-material-slot@aba645ada829ada9` | `texture/effect-material-slot` | 6854 | 318 | 4782 / 318 | `untriaged` |
| `texture/effect-material-slot@72d5c351e3518afd` | `texture/effect-material-slot` | 3523 | 252 | 2498 / 249 | `untriaged` |
| `particle/initializer-lifetimerandom@4f49d422ee93b4b2` | `particle/initializer` | 1197 | 253 | 975 / 239 | `untriaged` |
| `particle/initializer-sizerandom@af7900ad7fa8e825` | `particle/initializer` | 1484 | 247 | 1173 / 235 | `untriaged` |
| `layer/image@5e4c8117d0220cb3` | `layer/image` | 1540 | 288 | 973 / 232 | `untriaged` |
| `particle/renderer-sprite@13d5b961a929229b` | `particle/renderer` | 1121 | 245 | 874 / 229 | `untriaged` |
| `particle/controlpoint-1@dd58b5d5d5dc53b6` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-2@610f46c501bc0ab3` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-3@c68c0bfbed2d003f` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-4@836ca1b0e44c7396` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-5@5147f5e0ff1dc4d8` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-6@19856d86c6ba8777` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-7@1981e7ba62a17e45` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `particle/controlpoint-unknown@ab32a4d63b720bf0` | `particle/controlpoint` | 1279 | 228 | 989 / 220 | `untriaged` |
| `texture/effect-material-slot@09cd4f00c72ef79a` | `texture/effect-material-slot` | 1314 | 213 | 927 / 210 | `untriaged` |
| `particle/initializer-velocityrandom@28cd03ab4eb204db` | `particle/initializer` | 849 | 216 | 674 / 206 | `untriaged` |
| `audio-declaration/material-host-spectrum@f54a244027c2d7a1` | `audio-declaration/material-host-spectrum` | 1252 | 212 | 888 / 204 | `untriaged` |
| `particle/initializer-colorrandom@92fe2a1db1c0a335` | `particle/initializer` | 921 | 212 | 761 / 202 | `untriaged` |
| `texture/effect-material-slot@b9dbbf20539e7403` | `texture/effect-material-slot` | 1347 | 211 | 879 / 198 | `untriaged` |
| `particle/material@0cc12e1c65aba7ca` | `particle/material` | 974 | 204 | 775 / 194 | `untriaged` |
| `texture/particle-material-slot@c890a3f690d3cae8` | `texture/particle-material-slot` | 1243 | 208 | 940 / 192 | `untriaged` |
| `texture/image-material-slot@1914e3ff4fa250de` | `texture/image-material-slot` | 815 | 209 | 519 / 190 | `untriaged` |
| `layer/image@740da70a0906f520` | `layer/image` | 680 | 183 | 404 / 163 | `untriaged` |
| `texture/graph-binding@1cb3111748f1f792` | `texture/graph-binding` | 1141 | 180 | 748 / 159 | `untriaged` |
| `particle/operator-movement@241f23d1981eba83` | `particle/operator` | 563 | 166 | 468 / 155 | `untriaged` |
| `layer/image@1963ea2b13ddb536` | `layer/image` | 870 | 158 | 608 / 153 | `untriaged` |
| `material/image-pass@a16e3bc68008f398` | `material/image-pass` | 870 | 158 | 608 / 153 | `untriaged` |
| `texture/graph-binding@dc7a25a33e535aae` | `texture/graph-binding` | 1675 | 172 | 1061 / 151 | `untriaged` |
| `particle/operator-alphafade@79efef34b1e1efd1` | `particle/operator` | 485 | 159 | 409 / 148 | `untriaged` |
| `particle/operator-alphafade@42039ec7351e2817` | `particle/operator` | 503 | 158 | 382 / 145 | `untriaged` |
| `audio-declaration/material-host-spectrum@b45ca2db59b7644c` | `audio-declaration/material-host-spectrum` | 418 | 152 | 210 / 133 | `untriaged` |
| `material/effect-pass@84145b2e51f1d262` | `material/effect-pass` | 491 | 136 | 346 / 128 | `untriaged` |
| `render-graph/effect-pass@27a4e0a2441c4633` | `render-graph/effect-pass` | 491 | 136 | 346 / 128 | `untriaged` |
| `effect/authored-graph@c1df0b7918ba4c2d` | `effect/authored-graph` | 490 | 135 | 345 / 127 | `untriaged` |
| `material/effect-pass@cdf796695d9b62b3` | `material/effect-pass` | 396 | 130 | 267 / 115 | `untriaged` |
| `render-graph/effect-pass@87b44c43e3733ab2` | `render-graph/effect-pass` | 357 | 130 | 232 / 114 | `untriaged` |
| `material/image-pass@3d8e72eb1cf88e44` | `material/image-pass` | 901 | 110 | 641 / 106 | `untriaged` |
| `render-graph/effect-pass@95943be768e36742` | `render-graph/effect-pass` | 474 | 120 | 312 / 104 | `untriaged` |
| `render-graph/effect-pass@aa00f242facc660d` | `render-graph/effect-pass` | 330 | 120 | 208 / 104 | `untriaged` |
| `particle/initializer-rotationrandom@50be9f80182bdd6c` | `particle/initializer` | 338 | 113 | 265 / 101 | `untriaged` |
| `layer/sound@c8fc9e2c506965ac` | `layer/sound` | 127 | 100 | 127 / 100 | `untriaged` |
| `particle/operator-movement@38205f18a84856b8` | `particle/operator` | 303 | 108 | 235 / 98 | `untriaged` |
| `audio-declaration/scenescript-registration@c41c05c7b52d814f` | `audio-declaration/scenescript-registration` | 820 | 113 | 501 / 97 | `untriaged` |
| `particle/emitter-sphererandom@e75b31b9bb9c07b9` | `particle/emitter` | 302 | 111 | 233 / 97 | `untriaged` |
| `render-target/fbo@9901cebdf4c0a822` | `render-target/fbo` | 608 | 111 | 367 / 89 | `implemented` |
| `layer/image@ce6e6edd1955feb5` | `layer/image` | 651 | 95 | 433 / 88 | `untriaged` |
| `particle/initializer-colorrandom@37ca9b83db0e48a4` | `particle/initializer` | 367 | 96 | 267 / 83 | `untriaged` |
| `particle/initializer-alpharandom@6ee0ff0ba37418ef` | `particle/initializer` | 228 | 87 | 178 / 81 | `untriaged` |
| `particle/material@39fc82b1fae017f5` | `particle/material` | 197 | 86 | 149 / 75 | `untriaged` |
| `material/effect-pass@a1fbcf4e6cc961a5` | `material/effect-pass` | 326 | 84 | 233 / 74 | `untriaged` |
| `render-graph/effect-pass@c76a5976d14e6a9b` | `render-graph/effect-pass` | 315 | 83 | 230 / 74 | `untriaged` |
| `material/image-pass@56589507d93ffe7f` | `material/image-pass` | 387 | 88 | 192 / 70 | `untriaged` |
| `particle/operator-controlpointattract@dbf3bebbae124331` | `particle/operator` | 144 | 73 | 126 / 70 | `untriaged` |
| `effect/authored-graph@49c310bdbcb3af55` | `effect/authored-graph` | 303 | 79 | 220 / 69 | `untriaged` |
| `render-graph/effect-pass@419b55fe86b12fd0` | `render-graph/effect-pass` | 303 | 79 | 220 / 69 | `untriaged` |
| `render-target/fbo@b7f0838a5064473e` | `render-target/fbo` | 303 | 79 | 220 / 69 | `untriaged` |
| `particle/operator-alphafade@6e7ca1434b17529b` | `particle/operator` | 287 | 78 | 207 / 69 | `untriaged` |
| `texture/effect-material-slot@8ec2c2b3a7358158` | `texture/effect-material-slot` | 352 | 77 | 227 / 68 | `untriaged` |
| `effect/authored-graph@dfc634e4773519c6` | `effect/authored-graph` | 187 | 82 | 105 / 66 | `untriaged` |
| `texture/particle-material-slot@e4ffb6288070b82c` | `texture/particle-material-slot` | 140 | 72 | 125 / 66 | `untriaged` |
| `render-graph/effect-pass@3c0d08489093a45a` | `render-graph/effect-pass` | 186 | 81 | 104 / 65 | `untriaged` |
| `render-graph/effect-pass@ec2c0b2d9211f95c` | `render-graph/effect-pass` | 168 | 70 | 121 / 64 | `untriaged` |
| `particle/operator-movement@553cd133739c7c5a` | `particle/operator` | 183 | 67 | 146 / 64 | `untriaged` |
| `audio-declaration/material-host-spectrum@4f38735fd4b152f6` | `audio-declaration/material-host-spectrum` | 259 | 80 | 150 / 63 | `untriaged` |
| `particle/operator-movement@632199e7235723e5` | `particle/operator` | 176 | 69 | 133 / 63 | `untriaged` |
| `particle/initializer-angularvelocityrandom@198daf786a62e408` | `particle/initializer` | 177 | 73 | 132 / 62 | `untriaged` |
| `audio-declaration/material-audio-response@19a32783dd328dfa` | `audio-declaration/material-audio-response` | 241 | 78 | 134 / 61 | `untriaged` |
| `particle/operator-oscillateposition@c49553200c2ce38b` | `particle/operator` | 112 | 67 | 96 / 61 | `untriaged` |
| `texture/particle-material-slot@dfeab2f354eab98d` | `texture/particle-material-slot` | 142 | 63 | 119 / 61 | `untriaged` |
| `particle/children-child-definition@9ac07766b41dd3ec` | `particle/children` | 224 | 66 | 190 / 60 | `untriaged` |
| `particle/operator-movement@45cf8638a64d3236` | `particle/operator` | 162 | 64 | 116 / 58 | `untriaged` |
| `layer/image@5af3291c18378ed6` | `layer/image` | 209 | 57 | 149 / 57 | `untriaged` |
| `particle/emitter-sphererandom@5a95afd97c419886` | `particle/emitter` | 100 | 64 | 82 / 56 | `untriaged` |
| `particle/initializer-sizerandom@e0dd54a817ccc18e` | `particle/initializer` | 136 | 64 | 97 / 55 | `untriaged` |
| `effect/authored-graph@812aa00e4d7bfe07` | `effect/authored-graph` | 144 | 60 | 104 / 55 | `untriaged` |

完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。

### 4.1 公共能力映射概览

> family→capability 是 P0.2 的声明覆盖粗映射（`script/scene_capability_family_map.json` 规则驱动，多对多、可反查）；coarse profile 表示语义差异未细化，不能当能力闭合。映射与运行支持无关；每项能力的真实等级只查 [能力台账](coverage-ledger.md)与专项表。

| capability | 台账 authority 行 | family | occurrence | 样本 |
|---|---|---:|---:|---:|
| `cap.audio.declarations` | [Audio declarations](coverage-ledger.md) | 60 | 4197 | 316 |
| `cap.camera.parallax` | [Camera Parallax](coverage-ledger.md) | 12 | 25 | 23 |
| `cap.camera.shake` | [Scene Camera Shake](coverage-ledger.md) | 12 | 25 | 23 |
| `cap.effect.executor` | [Bounded effect executors](coverage-ledger.md) | 14 | 9808 | 349 |
| `cap.graph.fbo` | [Generic FBO command graph](coverage-ledger.md) | 39 | 16169 | 349 |
| `cap.graph.utility-composition` | [Utility composition](coverage-ledger.md) | 97 | 1090 | 84 |
| `cap.layer.ir` | [Scene IR 与基础层级](coverage-ledger.md) | 2337 | 16077 | 372 |
| `cap.light.hdr` | [2D lighting/Scene HDR](coverage-ledger.md) | 16 | 51 | 17 |
| `cap.material.ir` | [EffectDefinition/Material IR](coverage-ledger.md) | 71 | 27806 | 372 |
| `cap.model3d.runtime` | [3D model/camera/physics](coverage-ledger.md) | 2 | 3329 | 371 |
| `cap.particle.runtime` | [Particle runtime](coverage-ledger.md) | 1072 | 35181 | 261 |
| `cap.property.atomic-state` | [Atomic live property state/routing](coverage-ledger.md) | 1 | 1774 | 120 |
| `cap.property.user` | [User Properties](coverage-ledger.md) | 111 | 19329 | 372 |
| `cap.resource.index` | [PKG/TEX/资源索引](coverage-ledger.md) | 42 | 22868 | 372 |
| `cap.resource.texture-provider` | [Typed texture provider](coverage-ledger.md) | 44 | 23027 | 371 |
| `cap.scenescript.binding-ir` | [SceneScript property binding IR](coverage-ledger.md) | 615 | 6548 | 254 |
| `cap.shader.source-contract` | [Shader source/include/annotation/declaration contract](coverage-ledger.md) | 403 | 6380 | 354 |
| `cap.text.runtime` | [Text/Font runtime](coverage-ledger.md) | 398 | 2551 | 225 |
| `cap.timeline.runtime` | [Timeline runtime](coverage-ledger.md) | 32 | 1026 | 141 |

显式 unknown family 共 **7** 个，原因分布：`{"effect-declaration-unresolved-static": 1, "project-property-kind-empty": 1, "project-property-kind-unknown": 5}`；unknown 是静态不可判定的显式登记，不是运行失败，也不得据此宣称缺失。

## 5. 全部样本清单

逐样本的对象、Effect、粒子、occurrence与人工材料状态见[全样本静态明细](scene-corpus-sample-inventory.md)。此处只导航，实际播放与视觉裁决仍归[验收台账](scene-sample-acceptance-ledger.md)。

本轮373目录中372可解析；旧3763323436仅有shader、无project，不列新增播放故障。原生成CLI在该失败目录缺报告元数据时中止Markdown；本页使用同一快照的精确occurrence索引与目录事实恢复报告视图，原失败保留，工具问题归断点队列。

## 6. 修复事件记录与防回归合同

每个已登记公共 family 的修复事件使用三个独立 workflow/evidence 字段；三者都不是 capability current/support/todo 等级：

- `repair_state`: `untriaged -> diagnosed -> in-progress -> implemented -> bounded-verified`；
- `runtime_proof_state`: `none -> partial-chain -> visible-chain-closed -> official-golden-equivalent`；
- `regression_protection_state`: `none -> synthetic -> targeted-runtime -> milestone`。

这里的 `implemented` 只表示该 repair event 描述的改动已落地，可能是解析保真、失败关闭或故障隔离，不表示整个 family 已实现。事件记为 `bounded-verified` 至少要求项目自有 synthetic 正例、反例、真实隔离样本 GPU→publication→compositor→next-frame→ROI 和明确剩余边界；`official-golden-equivalent` 还必须有同相位官方 golden 及像素/时序容差。只降低 rejection 数、只 non-black 或只加载资源不能写成修复完成。

当前已逐族复核并登记的修复事件见机器 repair ledger 与下表；未列 family 显示 `untriaged` 只表示没有修复事件记录，不是 missing/unsupported/todo，也不会因 effect 名、路径或相邻 family 已修而自动产生 current 结论。

| family | 修复事件 / 事件运行证据 / 事件回归保护（非能力状态） | 公共修法 | 真实 sentinel | 剩余边界 |
|---|---|---|---|---|
| `dynamic-input/scenescript+user-property@b6c2ad8748c2c0a7` | `implemented / partial-chain / targeted-runtime` (`cc69da74`) | Make object text a first-class host in the shared SceneScriptDynamicProviderHostContract instead of enumerating key sets per consumer: add the objectText host kind, let it accept script+value and script+user+value in addition to the existing scriptproperties shapes, and allow an outer user key that names a real user property. Route the text content projection through the contract and classify text fields as objectText in sceneScriptHostKind so a user property bound to a text field's script properties resolves to the existing scriptInstanceProperty target. No registry, owner, route or second property channel is added. | `3747492842` | The run closes the authored wrapper -> binding and owner admission -> script execution -> typed target identity and execution chain only. Three independent reasons keep the change unobservable in this run's ready/after captures: the layer 191 script returns its input value unchanged, a thisLayer.angles write does not surface as its own layer mutation (layers 59 and 264 were already live before this batch with the same layers=1 summary), and the before run carried 54 real cursorMove events while the after run carried none, so input.cursorWorldPosition being at the canvas centre is a run state rather than a structural fact. The falsifiable next gate is to move the pointer off centre and assert the .layer(191, .angles) mutation and admission.；189 user property references under text/scriptproperties/<name> across 40 samples now classify, but no per-property visible or audible acceptance scenario was executed; only the static classification is closed. Three-key text wrappers move from unsupported to live as well, so the impact set is wider than the four-key shape alone.；Conditional values, hidden controllers, dynamic input families and official comparison for these bindings remain unverified.；Only one of the 62 corpus-wide [script, scriptproperties, user, value] wrappers sits on a text field; other hosts keep their existing contract entries and were not re-exercised.；The census payload hash is only reproducible by re-running generate; matrix and benchmark do not assert propertyBindingProgram, so the targeted runtime sentinel above is a manual evidence comparison rather than a machine gate. |
| `dynamic-input/scenescript@62583305de1f9a21` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the script family. | `3768229922` | Layer 202 is the authored head hit target and cursorClick producer; ordered pointer edges, solid-only hit testing, capture, shared.clack mutation, alpha blinking and user-property application are not implemented.；The suppression protects static composition but does not make the head clickable or show and hide the authored overlay.；The synthetic-positive gate was repointed to the successor of a rename in 5d7bb4a5. That commit also moved the visible-field assertion from suppression (unproven-inline-scenescript diagnostic) to previous-current (awaiting-scenescript-publication); the gate therefore certifies the current refusal semantics while the public_fix prose above still describes the original suppression behaviour. The owned alpha field stays suppressed in both, and the sibling synthetic-negative gate is unchanged. |
| `dynamic-input/scenescript@82ef17cb868c4f2e` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the script family. | `3768229922` | Layer 397 is a hidden controller that must keep ticking and map shared.clack to sixteen visual layers; its module, shared state, update callback and mutations are not executed.；The suppression protects static composition but provides no click interaction, dynamic overlay visibility or Wallpaper Engine equivalence.；The synthetic-positive gate was repointed to the successor of a rename in 5d7bb4a5. That commit also moved the visible-field assertion from suppression (unproven-inline-scenescript diagnostic) to previous-current (awaiting-scenescript-publication); the gate therefore certifies the current refusal semantics while the public_fix prose above still describes the original suppression behaviour. The owned alpha field stays suppressed in both, and the sibling synthetic-negative gate is unchanged. |
| `dynamic-input/scenescript@c434d003fa58a779` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the opening lifecycle script. | `3768229922` | Layer 354's authored fade, visible mutation and delayed destroy lifecycle are not executed; the correct official opening timing remains unknown in this runtime.；The exposed opening-phase composition is not proof of final-phase or Wallpaper Engine pixel and timing equivalence.；The synthetic-positive gate was repointed to the successor of a rename in 5d7bb4a5. That commit also moved the visible-field assertion from suppression (unproven-inline-scenescript diagnostic) to previous-current (awaiting-scenescript-publication); the gate therefore certifies the current refusal semantics while the public_fix prose above still describes the original suppression behaviour. The owned alpha field stays suppressed in both, and the sibling synthetic-negative gate is unchanged. |
| `render-target/fbo@9901cebdf4c0a822` | `implemented / visible-chain-closed / targeted-runtime` (`8cb2c343`) | Keep the existing per-surface pool, allocation cache and fail-closed frame preflight as the only target residency owner for that surface, but derive the automatic budget from one sixteenth of the recommended working set with the existing 192 MiB floor and a 1.5 GiB upper cap. Explicit injected budgets remain authoritative and over-budget frame sets are still rejected before allocation. | `3754630802` | The targeted run closes identity and execution evidence for this sample only; the preview comparison is advisory and is not fixed-phase official pixel or timing equivalence.；The 1.5 GiB value is an upper cap, not a measured floor. This device was admitted by the one-sixteenth working-set share before the cap; M1 or lower-memory devices, multi-surface pressure, memory-pressure recovery and long-stability behavior remain unverified.；The automatic limit is per surface; there is no process-wide aggregate cap across multiple display surfaces.；This family key anchors the shared RGBA framebuffer residency event. It does not claim semantic closure for every framebuffer family, target format, topology or sample that uses the same pool. |
| `resource/model@9d3474c9219422b7` | `implemented / visible-chain-closed / targeted-runtime` (`07133cbf`) | Add an identity-free geometryLayer dependency profile for a visible image Puppet with no child, authored dependency or utility owner, restricted to primary pass 0 slot 1, normal blend and an admitted resolved MaterialProgram. Reserve a typed named target only when provider and consumer placement match exactly; rasterize the original atlas or graph-final through the same GeometryProduct in authored-local coordinates, proportionally limiting only the physical publication target, and retain exact consumer/provider/variant/slot/blend, texture, generation, frame-epoch, completion and publication checks. A visible Puppet leaf may feed a hidden nested graph provider and then an aggregate without adding an output owner. Ordinary publication misses discard only the provider output or dependent consumer while independent suffix work and a visible color provider's authored-order compositor output continue; data publications and identity drift remain fail closed. Forward visible effectful providers remain rejected because prepass would consume their sole graph ticket. The ordinary flat-image Puppet route remains rejected. | `2959875782` | This family key is the census-minted model-resource anchor for the repaired event; the targeted result does not close all 37 samples, model revisions, arbitrary geometry providers, 3D, Puppet semantics or model-resource families.；Only the placement-exact primary pass-0 slot-1 normal-blend MaterialProgram profile is admitted, including its bounded hidden nested graph-provider form. Different provider/consumer placement, children, provider dependencies, forward visible effectful providers, non-primary variants, other slots or blends remain fail closed.；The Steam preview comparison is advisory and not fixed-phase official pixel or timing equivalence.；The -Onone observation-enabled diagnostic run is not product-performance evidence. A separate optimized no-observation steady-state probe held 30 FPS on the current M4 single-display environment, while the 60 FPS profile remained GPU-limited at about 48.99 FPS; low-end devices, multi-display, long-stability, Release equivalence and the AS3 60 FPS closure remain unverified.；The current uncommitted candidate has not been rerun across all 159 samples. The old full-set baseline plus targeted closure of its two failures cannot be reported as a fresh 159/159 candidate run.；Retired a dangling synthetic-negative gate script/tests/test_scene_resolved_material_runtime_bridge.py#test_resolved_material_runtime_bridge_compiles_and_executes: that test name never existed as a test definition in any commit (the string only ever appeared as ledger text), and the file's actual tests are positive or unrelated; the family's rejection contract stays covered by its other synthetic-negative gate. See E-2026-09-17 census referential-integrity gate. |
| `shader/frag@14c83a36961c3903` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3fa1499c`) | Preserve the authored hidden flag and map only the exact historical token on regular hidden g_Texture0 slot 0 to the current effect graph input, reusing the existing typed graph identity, publication, Program, GraphExecutor and compositor path. | `1553008362` | The related 1636394814 mixed chain was rerun and no longer logged this texture-binding alias failure, but it remains NON-PASS at later dependency-owner and material-template-unsupported gates.；Other ui_editor_properties_* keys, non-slot-0 samplers, non-regular modes, label-only metadata and non-hidden declarations remain rejected.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@1d391ff0fa121323` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3fa1499c`) | Preserve the authored hidden flag and map only the exact historical token on regular hidden g_Texture0 slot 0 to the current effect graph input, reusing the existing typed graph identity, publication, Program, GraphExecutor and compositor path. | `1553008362` | The related 1636394814 mixed chain was rerun and no longer logged this texture-binding alias failure, but it remains NON-PASS at later dependency-owner and material-template-unsupported gates.；Other ui_editor_properties_* keys, non-slot-0 samplers, non-regular modes, label-only metadata and non-hidden declarations remain rejected.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@436c998ccdbec6c2` | `bounded-verified / visible-chain-closed / targeted-runtime` (`e84c39b3`) | Prove a strict same-slot whole-vector affine filter closure, unpremultiply every selected layer-source color sample, clamp the authored straight RGBA result to the UNorm boundary, premultiply once, and require the exact layerSource-to-effectOutput graph role. Auxiliary slots remain data or scalar only, and scalar texture samples use the shared explicit .x conversion rule. | `3290491250` | Multiple color slots, component-wise color mutation, dynamic division, helper side effects, internal graph targets and ordinary effectOutput input remain rejected.；The related 3767343314 occurrence remains NON-PASS at later Water Ripple texture-purpose and Cursor Ripple history or render-state gates; no partial graph publication is claimed.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@60ed3f1823e61bb5` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3df4a94d`) | Recognize only the bounded single-source and uniform-RGB mix with preserved sampled alpha, require every launch-envelope variant to consume one exact captured layerSource Program with no competing authored or default texture source, and resolve composition and project capture with wallpaper-aligned projected geometry while keeping fullscreen capture screen-fixed. Unknown color flows, ambiguous sources and mixed launch envelopes remain fail closed. | `3768229922` | The shader proof covers only one sampled source RGB mixed with one fragment-uniform RGB by a finite bounded scalar while preserving that sample's alpha; second color sources, alpha rewrites, varying tint, custom or shadowed builtins, unbounded weights and ambiguous source identities remain rejected.；The captured-main proof requires one exact layerSource identity across the complete launch envelope; competing graph candidates, authored defaults, non-regular samplers, wrong source modes, mixed variants and independent alpha signals remain rejected.；This repair does not implement the head-click SceneScript toggle, other dynamic overlay effects, unrelated particle families, or Wallpaper Engine pixel and timing equivalence.；Retired a dangling synthetic-negative gate script/tests/test_scene_resolved_material_execution_capability.py#test_launch_precompiles_the_static_texture_readiness_envelope: 87d254c8 retired the dedicated effect runtime and removed that test with it; the family's rejection contract stays covered by its other synthetic-negative gate. See E-2026-09-17 census referential-integrity gate. |
| `shader/frag@aa24ee494d79e460` | `bounded-verified / visible-chain-closed / targeted-runtime` (`9977d585`) | Recognize only that bounded straight-RGB/scalar-alpha dataflow, require one sampled color and alias, one alpha multiply, distinct direct .r auxiliary samples, the exact max(0, rgb) output and a small scalar grammar, then reuse the existing straight-alpha boundary and typed data/scalar auxiliary gate. Unknown helpers, RGB writes, alpha replacement, other channels and repeated auxiliaries remain rejected. | `3768229922` | The proof covers only the structural straight-RGB/scalar-alpha family; RGB modulation, alpha replacement, unknown helpers, other auxiliary channels and untyped auxiliary color remain rejected.；The screenshots are an opening camera-rise phase and prove same-sample visible output, not the final static composition or every dynamic effect.；Display SceneScript, the head-click toggle, shared state, the sixteen dependent overlay layers and Wallpaper Engine pixel or timing equivalence remain unimplemented. |
| `shader/frag@d2da7d15588b9990` | `bounded-verified / visible-chain-closed / targeted-runtime` (`ad78674d`) | Recognize only the bounded single-sample straight-RGB and sampled-alpha-factor dataflow, reuse the existing straight-alpha boundary, provide the exact typed layer model matrix, and keep replacement, additive, conditional, multi-sample, helper side-effect and unknown-matrix forms fail closed. | `3768724269` | Alpha replacement, additive alpha, conditional or loop control flow, multiple samples, mask textures, hidden helper side effects and arbitrary matrices remain rejected.；This proof does not provide Drag-and-Drop SceneScript or mouse interaction and does not upgrade other rounded-mask revisions.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |

## 7. 更新流程

1. 新增/删除样本后先只读运行 corpus census，确认 `discovered = parsed + failed`、occurrence 与 JSON leaf 守恒。
2. authored census 一旦发现样本增删，tracked full-matrix baseline 立即标为 `pending-expansion`，不得再称完整；新样本的运行状态先记为本 census 未 join，随后用独立 milestone 扩容批建立运行期待并更新 matrix。
3. 从 fresh 隔离报告定位首个失败 identity，再按现役通用执行计划选择能让未见内容受益、可局部降级且可独立回滚的公共 primitive；不得把 family 名直接变成产品 dispatch。
4. 先核对官方作者合同和现有固定证据；只有材料不足以解释 producer-to-consumer 结构时才按需固定 MirageWallpaper revision，并记录实际读取模块与 divergence。第三方参考不是每批前置，也不提供算法真值。
5. 同批实现公共代码、synthetic 正反门和与声明相称的代表运行门；只有具体 fidelity 修复才强制真实 ROI。再写 repair event 和必要的专项文档，不建立样本专用分支，也不复制第三方算法或 payload。
6. `targeted_samples` 与 `regression_gates` 是后续必须重跑的 sentinel 合同；触达同 family 或它依赖的 selection/Program/publication/composition 时必须执行，不能用新的 aggregate count 覆盖旧视觉正证。

诊断命令（当前失败行renderer及两页writer尚待修；先写忽略目录，不能直写现役总览/清单，也未声称以下generate/verify已通过）：

```bash
python3.12 script/scene_capability_census.py generate \
  --samples-root "$HOME/Movies/MyWallpaperX/创意工坊/Scene" \
  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \
  --markdown .artifacts/scene-census-generated.md
python3.12 script/scene_capability_census.py verify \
  --samples-root "$HOME/Movies/MyWallpaperX/创意工坊/Scene" \
  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \
  --markdown .artifacts/scene-census-generated.md
python3.12 script/scene_capability_census.py query \
  --family <family-key>
# 需要当前私有 corpus 的详细 resource/owner 事实时显式追加 --live
```
