# Scene 全样本能力分类与修复事件台账

> 状态：现役 corpus 事实、公共结构影响面与修复事件索引。
>
> 本页静态数据由 `script/scene_capability_census.py` 从只读 authored corpus 扫描；2026-10-21 的有界资料同步例外见下文；完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `.artifacts/scene-evidence/census/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。系统 current capability 只以 `coverage-ledger.md` 为摘要，逐项合同/专题内等级以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-current.md` 为准。

## 1. 当前结论

- 当前真实 Scene 根有 **351** 个数字目录：**350** 个完整项目的 project、PKGV 索引和入口 JSON 可解析；既有 `3763323436` 目录仅残留 `shaders`，缺 `project.json`，保留为 **1** 个解析失败项。350 个 project 的类型均为 Scene（`scene` 273 / `Scene` 77）。
- 相对旧验收台账的 327 个 ID，本轮新增 **24** 个目录、减少 **0** 个目录；旧成员为 326 个完整项目和上述 1 个残缺项。按完整输入集合比较的 `+24/-1` 不能写成目录删除，也不撤销历史运行或人工裁决。
- 2026-10-21 原 `generate` 已完成扫描并写出 raw snapshot，随后在 `render_markdown` 访问 failed row 的 `has_manual_screenshot` 时触发 `KeyError`，未完整通过。本页复用该快照及现有 renderer，仅在内存为残缺项补入实查为 false 的截图/观察说明展示字段；未修改生成器，未重扫语料，未运行或宣称 `verify` 通过。原错误保留在 `.artifacts/scene-evidence/runs/new-sample-intake-20261021/index/current/samples/2784267518/runtime_evidence.zip` 的 `census/generate.log`；该工具问题修复前本页为有界资料同步结果。
- 新增 24 项贡献 **16549** 个 occurrence，触达 844 个 family，其中 **195** 个仅见于新增（layer 112、particle 40、dynamic-input 21、shader 17、material 4、audio-declaration 1）；另有 33 个新参数 profile、318 个新字段 profile，没有新 domain/kind。作者属性除 schemecolor 外为 806 项、condition 175 项，无新增 property kind；这些新声明形态不是运行能力缺口或失败结论。
- tracked full-matrix baseline 当前覆盖 **45** 个历史成员，状态为 `pending-expansion`；本 census 新发现但未 join 运行证据的样本为 `1195626192, 1300076567, 1315486372, 1439846152, 1480826543, 1507413154, 1507593643, 1511889295, 1695673397, 1926190458, 1989767609, 1994794519, 2069136288, 2112262451, 2163522240, 2179185481, 2181251652, 2231088993, 2269193950, 2304304373, 2347762662, 2356604986, 2505351195, 2507971256, 2524111047, 2607203340, 2616828675, 2684431262, 2731896598, 2735160334, 2775915974, 2776912698, 2780710296, 2784267518, 2787219305, 2794098047, 2797913147, 2797943632, 2804817823, 2807058277, 2808874251, 2811643059, 2813231542, 2813240634, 2814167871, 2815826216, 2819143171, 2821634935, 2824109832, 2824690710, 2831174267, 2834973884, 2835398595, 2837223712, 2849382252, 2850139759, 2866086594, 2871175822, 2871552691, 2877499944, 2877855240, 2884170082, 2887542690, 2890473419, 2896873092, 2913492057, 2917306763, 2919854127, 2927205881, 2932157836, 2932631210, 2942486721, 2949019513, 2951452910, 2959875782, 2960821850, 2964778792, 2969308380, 2972071249, 2981249186, 2983846453, 2986218263, 2987771245, 2992924426, 2999907577, 3002649614, 3021013015, 3022080536, 3025969015, 3027056454, 3027068980, 3039704323, 3039882306, 3042492564, 3078285611, 3086016320, 3087231311, 3113287126, 3113554287, 3114332546, 3115163440, 3137495261, 3146507587, 3147346398, 3148125112, 3167210190, 3173418061, 3175039950, 3211615441, 3219398263, 3221354414, 3226487183, 3232289987, 3233141951, 3238423642, 3248220186, 3264246690, 3287715210, 3291326967, 3292370168, 3323988600, 3325624777, 3337494481, 3341111071, 3351163962, 3351179520, 3357627941, 3363252053, 3372715909, 3374523158, 3383535304, 3389974179, 3395392965, 3395777145, 3396722575, 3420215721, 3435573282, 3436945972, 3437487219, 3446316682, 3448845950, 3448877775, 3470948192, 3471294034, 3472940912, 3476868923, 3477054430, 3486887298, 3487629864, 3507496797, 3509243656, 3549827466, 3554161528, 3562021804, 3563038726, 3566880847, 3577990983, 3581882134, 3585542943, 3585875739, 3586705329, 3587571382, 3589454154, 3597772384, 3599986633, 3601801724, 3601964477, 3603711180, 3605502569, 3605722997, 3609108600, 3610154602, 3612058080, 3612199597, 3612795410, 3616389236, 3617056047, 3627973226, 3629927359, 3632513108, 3632522893, 3641200550, 3655958892, 3662245960, 3662390671, 3662790108, 3663810817, 3665307769, 3666041758, 3680252478, 3690065713, 3690859128, 3694697894, 3695791724, 3698459055, 3699213569, 3703104370, 3708363772, 3712499998, 3719111841, 3721456868, 3722749868, 3723344874, 3742497499, 3745828537, 3746422401, 3747190633, 3748311238, 3749463715, 3754630802, 3754639143, 3754908581, 3761159935, 3761619125, 3762312138, 3763323436, 3763428294, 3764725758, 3765904723, 3766299002, 3766310551, 3773747576, 3775355045, 3775373546, 3777761326, 3779026256, 3779107475, 3779904456, 3780119725, 3780391264, 3780940857, 3781307553, 3781757083, 3782650329, 3782740481, 3784012236, 3786048634, 3786185473, 3786330502, 3786641495, 3787355076, 3787382101, 3788066613, 3788467391, 3788645041, 3788698200, 3788734811, 3788897599, 3789316755, 3790631363, 3790726145, 3790806929, 3790956325, 3791905266, 3791967416, 3792249095, 3792400801, 3792817546, 3793328876, 3793978239, 3793998447, 3796588443, 3797217144, 3800075350, 3800356808, 3800572533, 3800728730, 3801294161, 3801984224, 3802005866, 3803087940, 3803482159, 3803576671, 3804441338, 3804906814, 3804971850, 3805449677, 3805547608, 3806006894, 3806016969, 3806202923, 3806337293, 3807013762, 3807121855, 3807151772, 3807239614, 3807436394, 3807553861, 3807668787, 3807861954, 3808922316, 3809034761, 3809541486, 3809609151, 3809618616, 3810943704, 3811154012, 3811216799, 3812249745, 3812473896, 3814040466, 3815761795, 3818943255, 3820312181, 3822822401, 833227004`，是否曾单独运行不能由静态扫描判断。
- 全量 authored census 共保存 **169346** 个 typed occurrence、**4449** 个公共结构 family、**2368** 个参数 profile 与 **22979** 个 JSON 字段 profile。
- 物理 corpus 共 **27802** 个 PKG entry / **27799** 个唯一路径，包体约 **16.887 GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 45，期间不得称为当前完整快照门。
- package anomaly：样本 `3690065713` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 36/54，同字节；该包 107 entries / 106 unique paths）；样本 `3768724269` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 59/80，同字节；该包 87 entries / 86 unique paths）；样本 `3807013762` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 49/57，同字节；该包 73 entries / 72 unique paths）；重复entry继续保留在物理守恒中，不是漏扫。
- 结构 fallback 记录为 **93**，另有 **6** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。
- 公共能力粗映射：**4442** 个 family 按声明形态映射到台账登记能力，**7** 个显式 unknown（`{"effect-declaration-unresolved-static": 1, "project-property-kind-empty": 1, "project-property-kind-unknown": 5}`）；映射只表达声明覆盖关系，不表示运行支持。
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
| `resource` | 15300 | 14 | [格式/资源](scene-format-and-render-graph.md) |
| `shader` | 5958 | 397 | [Graph/Shader](render-graph-shader-coverage.md) |
| `layer` | 15309 | 2208 | [格式/对象](scene-format-and-render-graph.md) |
| `material` | 16675 | 68 | [Graph/Shader](render-graph-shader-coverage.md) |
| `effect` | 9365 | 15 | [Effect](effect-execution-coverage.md) |
| `render-graph` | 11186 | 28 | [Graph/Shader](render-graph-shader-coverage.md) |
| `render-target` | 1253 | 8 | [Graph/Shader](render-graph-shader-coverage.md) |
| `texture` | 31486 | 72 | [格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md) |
| `particle` | 32054 | 940 | [粒子](particle-component-coverage.md) |
| `audio-declaration` | 3479 | 39 | [音频声明](coverage-ledger.md) |
| `dynamic-input` | 18345 | 616 | [属性/输入](runtime-input-property-coverage.md) |
| `project-property` | 8936 | 44 | [属性/输入](runtime-input-property-coverage.md) |

### 3.1 纹理本体与使用点

- 包内物理 TEX：**6544**；格式分布：`{"0": 2835, "4": 556, "6": 28, "7": 36, "8": 787, "9": 2302}`。
- TEX 结构特征：`{"animated": 77, "static": 6467, "video-mp4": 5}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。
- 纹理使用 occurrence：**24942**；slot 状态：`{"hole": 6737, "missing": 101, "resolved": 13831, "runtime-provided": 4273}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。

### 3.2 对象、Effect 与动态输入

- 对象类型：`{"camera": 23, "image": 5565, "light": 51, "particle": 1171, "shape": 30, "sound": 225, "text": 1608, "utility": 1071}`；静态非 hidden：`{"camera": 19, "image": 3673, "light": 33, "particle": 920, "shape": 23, "sound": 225, "text": 1053, "utility": 882}`。
- Effect instance **9365**，粒子 root layer **1171**；动态 wrapper：`{"condition_wrappers": 1711, "script_wrappers": 6170, "timeline_wrappers": 997, "user_bindings": 9709}`。
- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。

### 3.3 音频声明与 consumer 意图关系

- payload-free 音频关系共 **3479** 个 occurrence / **279** 个样本；其中 editor `supportsaudioprocessing=true` 为 **218** 个样本，存在至少一种非 project 声明关系的样本为 **279** 个。
- 标记有而没有非 project 声明关系：`无`；有声明关系而没有 editor 标记：`1553008362, 1636394814, 1695673397, 1926190458, 1994794519, 2069136288, 2112262451, 2269193950, 2473638329, 2505351195, 2524111047, 2607203340, 2616828675, 2775915974, 2797913147, 2802243144, 2811643059, 2824109832, 2896873092, 2942486721, 2959875782, 2987771245, 2998757800, 3021013015, 3025969015, 3088601835, 3167210190, 3221354414, 3323988600, 3395392965, 3486887298, 3549827466, 3663810817, 3680252478, 3699213569, 3703104370, 3738202317, 3750342273, 3750813609, 3757555836, 3762312138, 3764725758, 3766403294, 3767232084, 3769761761, 3770444459, 3781307553, 3782650329, 3786048634, 3786641495, 3787355076, 3788645041, 3790631363, 3790956325, 3791905266, 3793328876, 3801294161, 3803087940, 3807239614, 3807553861, 3822822401`。两者都不是运行支持集合，不能从静态相等或差集推导 capture demand。
- 静态 consumer 意图为 **161** 个样本：`1937925563, 2131872317, 2134765860, 2241938645, 2419444134, 2507971256, 2684431262, 2731896598, 2776912698, 2780710296, 2784267518, 2787219305, 2794098047, 2797943632, 2804817823, 2807058277, 2813231542, 2813240634, 2814167871, 2815826216, 2819143171, 2821634935, 2824690710, 2831174267, 2834973884, 2835398595, 2849382252, 2850139759, 2866086594, 2871552691, 2877499944, 2877855240, 2884170082, 2884628849, 2887542690, 2890473419, 2902406982, 2913492057, 2919854127, 2927205881, 2932157836, 2932631210, 2938612768, 2951452910, 2960821850, 2972071249, 2974757317, 2983846453, 2992924426, 2999907577, 3002649614, 3027056454, 3027068980, 3039704323, 3039882306, 3042492564, 3078285611, 3087231311, 3114332546, 3137495261, 3148125112, 3175039950, 3211615441, 3226487183, 3232289987, 3233141951, 3238423642, 3248220186, 3264246690, 3291326967, 3292370168, 3299228616, 3325624777, 3337494481, 3341111071, 3351163962, 3351179520, 3363252053, 3374523158, 3383535304, 3395777145, 3396722575, 3420215721, 3435573282, 3436945972, 3448845950, 3448877775, 3471294034, 3476868923, 3477054430, 3507496797, 3554161528, 3562021804, 3585542943, 3585875739, 3586705329, 3587571382, 3589454154, 3601964477, 3603711180, 3605722997, 3610154602, 3612199597, 3612795410, 3617056047, 3627973226, 3632513108, 3632522893, 3655958892, 3662790108, 3665307769, 3666041758, 3690065713, 3694697894, 3695791724, 3708363772, 3719111841, 3723344874, 3742497499, 3745828537, 3747190633, 3747492842, 3749463715, 3754639143, 3761619125, 3765904723, 3766299002, 3766310551, 3767460992, 3768020435, 3768229922, 3768724269, 3769688830, 3773747576, 3777761326, 3779026256, 3779107475, 3780119725, 3780391264, 3781757083, 3786330502, 3787382101, 3788066613, 3788467391, 3789316755, 3790806929, 3791967416, 3792249095, 3793998447, 3797217144, 3800356808, 3804441338, 3806202923, 3806337293, 3807013762, 3807151772, 3807668787, 3809034761, 3809609151, 3810943704, 3811154012`。这里只接受精确源码数组形状、显式启用的 material/particle 响应或 proven-global 且分辨率有效的 SceneScript 调用；material active variant/host ABI 与所有运行 execution 尚未 join，因此本批 runtime-confirmed 仍为 **0**。
- 其中同一 SceneScript owner 同时具有静态准入 AudioBuffers 与显式导出 cursor callback 的意图为 **2** 个样本：`3238423642, 3632513108`；这只登记实例化候选关系，不证明 hit、事件触发、snapshot refresh 或可见输出。
- editor 标记有而静态意图无：`2067939514, 2871175822, 2917306763, 2949019513, 2964778792, 2969308380, 3022080536, 3086016320, 3113287126, 3113554287, 3122339805, 3146507587, 3147346398, 3287715210, 3290491250, 3357627941, 3372715909, 3470948192, 3487629864, 3509243656, 3563038726, 3566880847, 3577990983, 3581882134, 3597772384, 3605502569, 3609108600, 3616389236, 3641200550, 3662390671, 3690859128, 3698459055, 3712499998, 3721456868, 3743305891, 3748311238, 3754630802, 3761159935, 3763428294, 3765760121, 3769364482, 3779904456, 3782740481, 3788734811, 3788897599, 3792400801, 3792817546, 3796588443, 3800075350, 3802005866, 3804906814, 3804971850, 3805547608, 3808922316, 3809618616, 3812473896, 3815761795`；静态意图有而 editor 标记无：`无`。普通 App 运行基线必须覆盖这些差集与全部声明关系，不能只测标记集合。

| 声明关系 | occurrence | 样本 | 静态状态分布 |
|---|---:|---:|---|
| `material-audio-response` | 235 | 77 | `{"activation": {"absent": 5, "disabled": 1, "enabled": 229}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `material-host-spectrum` | 1897 | 264 | `{"activation": {"disabled": 1, "enabled": 229, "not-authored": 1667}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {"launch-envelope-unjoined": 1897}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {"preprocessor-conditioned": 5318, "source-shape-exact": 124}}` |
| `particle-audio-response` | 139 | 31 | `{"activation": {"disabled": 4, "enabled": 78, "missing-mode": 57}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `project-support-enabled` | 218 | 218 | `{"activation": {}, "cursor_audio_consumer": {}, "cursor_events": {}, "runtime_admission": {}, "script_admission": {}, "script_resolution": {}, "script_scope": {}, "source_abi": {}}` |
| `scenescript-registration` | 990 | 143 | `{"activation": {}, "cursor_audio_consumer": {"no-cursor-event": 987, "statically-admitted": 3}, "cursor_events": {"cursorEnter+cursorLeave": 3}, "runtime_admission": {}, "script_admission": {"resolution-unresolved": 144, "statically-admitted": 846}, "script_resolution": {"16": 776, "32": 10, "64": 60, "dynamic-or-invalid": 144}, "script_scope": {"proven-global": 990}, "source_abi": {}}` |

## 4. 当前公共 family 影响面索引

> 这里只按静态可见覆盖排序，不能自动决定实施。最后一列是修复事件工作流，不是能力状态；`untriaged` 不表示缺失。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。

| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复事件（非能力状态） |
|---|---|---:|---:|---:|---|
| `texture/image-material-slot@2e7ce906c5bcf601` | `texture/image-material-slot` | 3181 | 337 | 2081 / 332 | `untriaged` |
| `material/effect-pass@526202cd27954701` | `material/effect-pass` | 9883 | 323 | 6232 / 321 | `untriaged` |
| `effect/authored-graph@9231d5e82bfe3a7f` | `effect/authored-graph` | 8118 | 315 | 5067 / 313 | `untriaged` |
| `render-graph/effect-pass@91c374f0320bbf80` | `render-graph/effect-pass` | 8118 | 315 | 5067 / 313 | `untriaged` |
| `material/image-pass@f0e77c0708dc8bfc` | `material/image-pass` | 2638 | 308 | 1677 / 300 | `untriaged` |
| `texture/effect-material-slot@aba645ada829ada9` | `texture/effect-material-slot` | 6643 | 297 | 4605 / 297 | `untriaged` |
| `texture/effect-material-slot@72d5c351e3518afd` | `texture/effect-material-slot` | 3424 | 233 | 2413 / 230 | `untriaged` |
| `particle/initializer-lifetimerandom@4f49d422ee93b4b2` | `particle/initializer` | 1156 | 237 | 936 / 223 | `untriaged` |
| `particle/initializer-sizerandom@af7900ad7fa8e825` | `particle/initializer` | 1449 | 233 | 1140 / 222 | `untriaged` |
| `particle/renderer-sprite@13d5b961a929229b` | `particle/renderer` | 1091 | 229 | 846 / 213 | `untriaged` |
| `layer/image@5e4c8117d0220cb3` | `layer/image` | 1429 | 268 | 875 / 212 | `untriaged` |
| `particle/controlpoint-1@dd58b5d5d5dc53b6` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-2@610f46c501bc0ab3` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-3@c68c0bfbed2d003f` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-4@836ca1b0e44c7396` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-5@5147f5e0ff1dc4d8` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-6@19856d86c6ba8777` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-7@1981e7ba62a17e45` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `particle/controlpoint-unknown@ab32a4d63b720bf0` | `particle/controlpoint` | 1244 | 213 | 956 / 205 | `untriaged` |
| `texture/effect-material-slot@09cd4f00c72ef79a` | `texture/effect-material-slot` | 1260 | 199 | 877 / 197 | `untriaged` |
| `particle/initializer-velocityrandom@28cd03ab4eb204db` | `particle/initializer` | 819 | 203 | 646 / 193 | `untriaged` |
| `audio-declaration/material-host-spectrum@f54a244027c2d7a1` | `audio-declaration/material-host-spectrum` | 1197 | 198 | 837 / 191 | `untriaged` |
| `texture/effect-material-slot@b9dbbf20539e7403` | `texture/effect-material-slot` | 1332 | 200 | 866 / 188 | `untriaged` |
| `particle/initializer-colorrandom@92fe2a1db1c0a335` | `particle/initializer` | 885 | 197 | 725 / 187 | `untriaged` |
| `particle/material@0cc12e1c65aba7ca` | `particle/material` | 954 | 193 | 755 / 183 | `untriaged` |
| `texture/particle-material-slot@c890a3f690d3cae8` | `texture/particle-material-slot` | 1213 | 198 | 910 / 182 | `untriaged` |
| `texture/image-material-slot@1914e3ff4fa250de` | `texture/image-material-slot` | 769 | 193 | 484 / 175 | `untriaged` |
| `layer/image@740da70a0906f520` | `layer/image` | 639 | 168 | 373 / 149 | `untriaged` |
| `texture/graph-binding@1cb3111748f1f792` | `texture/graph-binding` | 1070 | 166 | 703 / 148 | `untriaged` |
| `particle/operator-movement@241f23d1981eba83` | `particle/operator` | 550 | 159 | 455 / 148 | `untriaged` |
| `particle/operator-alphafade@79efef34b1e1efd1` | `particle/operator` | 469 | 153 | 393 / 142 | `untriaged` |
| `layer/image@1963ea2b13ddb536` | `layer/image` | 837 | 147 | 586 / 142 | `untriaged` |
| `material/image-pass@a16e3bc68008f398` | `material/image-pass` | 837 | 147 | 586 / 142 | `untriaged` |
| `texture/graph-binding@dc7a25a33e535aae` | `texture/graph-binding` | 1580 | 158 | 995 / 140 | `untriaged` |
| `particle/operator-alphafade@42039ec7351e2817` | `particle/operator` | 484 | 144 | 363 / 131 | `untriaged` |
| `audio-declaration/material-host-spectrum@b45ca2db59b7644c` | `audio-declaration/material-host-spectrum` | 389 | 140 | 196 / 124 | `untriaged` |
| `material/effect-pass@84145b2e51f1d262` | `material/effect-pass` | 482 | 129 | 337 / 121 | `untriaged` |
| `render-graph/effect-pass@27a4e0a2441c4633` | `render-graph/effect-pass` | 482 | 129 | 337 / 121 | `untriaged` |
| `effect/authored-graph@c1df0b7918ba4c2d` | `effect/authored-graph` | 481 | 128 | 336 / 120 | `untriaged` |
| `material/effect-pass@cdf796695d9b62b3` | `material/effect-pass` | 382 | 124 | 256 / 111 | `untriaged` |
| `render-graph/effect-pass@87b44c43e3733ab2` | `render-graph/effect-pass` | 341 | 123 | 220 / 109 | `untriaged` |
| `material/image-pass@3d8e72eb1cf88e44` | `material/image-pass` | 887 | 105 | 632 / 102 | `untriaged` |
| `render-graph/effect-pass@95943be768e36742` | `render-graph/effect-pass` | 453 | 114 | 296 / 100 | `untriaged` |
| `render-graph/effect-pass@aa00f242facc660d` | `render-graph/effect-pass` | 316 | 114 | 197 / 100 | `untriaged` |
| `layer/sound@c8fc9e2c506965ac` | `layer/sound` | 121 | 97 | 121 / 97 | `untriaged` |
| `particle/initializer-rotationrandom@50be9f80182bdd6c` | `particle/initializer` | 322 | 107 | 249 / 95 | `untriaged` |
| `particle/operator-movement@38205f18a84856b8` | `particle/operator` | 297 | 104 | 229 / 94 | `untriaged` |
| `particle/emitter-sphererandom@e75b31b9bb9c07b9` | `particle/emitter` | 292 | 106 | 223 / 92 | `untriaged` |
| `audio-declaration/scenescript-registration@c41c05c7b52d814f` | `audio-declaration/scenescript-registration` | 773 | 104 | 477 / 90 | `untriaged` |
| `layer/image@ce6e6edd1955feb5` | `layer/image` | 645 | 92 | 428 / 86 | `untriaged` |
| `render-target/fbo@9901cebdf4c0a822` | `render-target/fbo` | 579 | 103 | 345 / 83 | `implemented` |
| `particle/initializer-colorrandom@37ca9b83db0e48a4` | `particle/initializer` | 362 | 92 | 262 / 79 | `untriaged` |
| `particle/initializer-alpharandom@6ee0ff0ba37418ef` | `particle/initializer` | 223 | 83 | 173 / 77 | `untriaged` |
| `particle/material@39fc82b1fae017f5` | `particle/material` | 185 | 80 | 139 / 69 | `untriaged` |
| `material/effect-pass@a1fbcf4e6cc961a5` | `material/effect-pass` | 292 | 75 | 217 / 67 | `untriaged` |
| `texture/effect-material-slot@8ec2c2b3a7358158` | `texture/effect-material-slot` | 345 | 73 | 226 / 67 | `untriaged` |
| `material/image-pass@56589507d93ffe7f` | `material/image-pass` | 353 | 83 | 184 / 66 | `untriaged` |
| `particle/operator-alphafade@6e7ca1434b17529b` | `particle/operator` | 281 | 74 | 203 / 66 | `untriaged` |
| `render-graph/effect-pass@c76a5976d14e6a9b` | `render-graph/effect-pass` | 280 | 73 | 213 / 66 | `untriaged` |
| `effect/authored-graph@dfc634e4773519c6` | `effect/authored-graph` | 180 | 78 | 99 / 63 | `untriaged` |
| `particle/operator-controlpointattract@dbf3bebbae124331` | `particle/operator` | 136 | 66 | 118 / 63 | `untriaged` |
| `render-graph/effect-pass@3c0d08489093a45a` | `render-graph/effect-pass` | 179 | 77 | 98 / 62 | `untriaged` |
| `effect/authored-graph@49c310bdbcb3af55` | `effect/authored-graph` | 269 | 70 | 204 / 62 | `untriaged` |
| `render-graph/effect-pass@419b55fe86b12fd0` | `render-graph/effect-pass` | 269 | 70 | 204 / 62 | `untriaged` |
| `render-target/fbo@b7f0838a5064473e` | `render-target/fbo` | 269 | 70 | 204 / 62 | `untriaged` |
| `texture/particle-material-slot@e4ffb6288070b82c` | `texture/particle-material-slot` | 134 | 67 | 119 / 61 | `untriaged` |
| `particle/operator-oscillateposition@c49553200c2ce38b` | `particle/operator` | 111 | 66 | 95 / 60 | `untriaged` |
| `render-graph/effect-pass@ec2c0b2d9211f95c` | `render-graph/effect-pass` | 158 | 65 | 113 / 60 | `untriaged` |
| `particle/operator-movement@553cd133739c7c5a` | `particle/operator` | 171 | 63 | 134 / 60 | `untriaged` |
| `audio-declaration/material-host-spectrum@4f38735fd4b152f6` | `audio-declaration/material-host-spectrum` | 229 | 73 | 138 / 59 | `untriaged` |
| `texture/particle-material-slot@dfeab2f354eab98d` | `texture/particle-material-slot` | 137 | 61 | 114 / 59 | `untriaged` |
| `particle/initializer-angularvelocityrandom@198daf786a62e408` | `particle/initializer` | 167 | 69 | 124 / 58 | `untriaged` |
| `particle/operator-movement@632199e7235723e5` | `particle/operator` | 168 | 64 | 125 / 58 | `untriaged` |
| `audio-declaration/material-audio-response@19a32783dd328dfa` | `audio-declaration/material-audio-response` | 211 | 71 | 122 / 57 | `untriaged` |
| `particle/children-child-definition@9ac07766b41dd3ec` | `particle/children` | 221 | 63 | 187 / 57 | `untriaged` |
| `particle/emitter-sphererandom@5a95afd97c419886` | `particle/emitter` | 100 | 64 | 82 / 56 | `untriaged` |
| `particle/operator-movement@45cf8638a64d3236` | `particle/operator` | 159 | 61 | 113 / 55 | `untriaged` |
| `layer/image@5af3291c18378ed6` | `layer/image` | 207 | 55 | 147 / 55 | `untriaged` |
| `effect/authored-graph@812aa00e4d7bfe07` | `effect/authored-graph` | 137 | 57 | 99 / 53 | `untriaged` |
| `particle/emitter-sphererandom@d1f27f5059ca5180` | `particle/emitter` | 91 | 57 | 85 / 53 | `untriaged` |

完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。

### 4.1 公共能力映射概览

> family→capability 是 P0.2 的声明覆盖粗映射（`script/scene_capability_family_map.json` 规则驱动，多对多、可反查）；coarse profile 表示语义差异未细化，不能当能力闭合。映射与运行支持无关；每项能力的真实等级只查 [能力台账](coverage-ledger.md)与专项表。

| capability | 台账 authority 行 | family | occurrence | 样本 |
|---|---|---:|---:|---:|
| `cap.audio.declarations` | [Audio declarations](coverage-ledger.md) | 59 | 3946 | 296 |
| `cap.camera.parallax` | [Camera Parallax](coverage-ledger.md) | 11 | 23 | 21 |
| `cap.camera.shake` | [Scene Camera Shake](coverage-ledger.md) | 11 | 23 | 21 |
| `cap.effect.executor` | [Bounded effect executors](coverage-ledger.md) | 14 | 9354 | 327 |
| `cap.graph.fbo` | [Generic FBO command graph](coverage-ledger.md) | 39 | 15380 | 327 |
| `cap.graph.utility-composition` | [Utility composition](coverage-ledger.md) | 93 | 1071 | 77 |
| `cap.layer.ir` | [Scene IR 与基础层级](coverage-ledger.md) | 2208 | 15309 | 350 |
| `cap.light.hdr` | [2D lighting/Scene HDR](coverage-ledger.md) | 16 | 51 | 17 |
| `cap.material.ir` | [EffectDefinition/Material IR](coverage-ledger.md) | 71 | 26429 | 350 |
| `cap.model3d.runtime` | [3D model/camera/physics](coverage-ledger.md) | 2 | 3218 | 349 |
| `cap.particle.runtime` | [Particle runtime](coverage-ledger.md) | 1062 | 34181 | 245 |
| `cap.property.atomic-state` | [Atomic live property state/routing](coverage-ledger.md) | 1 | 1712 | 113 |
| `cap.property.user` | [User Properties](coverage-ledger.md) | 111 | 18652 | 350 |
| `cap.resource.index` | [PKG/TEX/资源索引](coverage-ledger.md) | 42 | 21844 | 350 |
| `cap.resource.texture-provider` | [Typed texture provider](coverage-ledger.md) | 43 | 22197 | 349 |
| `cap.scenescript.binding-ir` | [SceneScript property binding IR](coverage-ledger.md) | 601 | 6172 | 239 |
| `cap.shader.source-contract` | [Shader source/include/annotation/declaration contract](coverage-ledger.md) | 397 | 5958 | 332 |
| `cap.text.runtime` | [Text/Font runtime](coverage-ledger.md) | 367 | 2364 | 210 |
| `cap.timeline.runtime` | [Timeline runtime](coverage-ledger.md) | 29 | 998 | 133 |

显式 unknown family 共 **7** 个，原因分布：`{"effect-declaration-unresolved-static": 1, "project-property-kind-empty": 1, "project-property-kind-unknown": 5}`；unknown 是静态不可判定的显式登记，不是运行失败，也不得据此宣称缺失。

## 5. 全部样本清单

| 样本 | 标题 | 对象 | Effect | 粒子层 | occurrence | 人工对照 | matrix/runtime |
|---|---|---:|---:|---:|---:|---|---|
| `1195626192` | Gaze | 3 | 1 | 2 | 96 | 无 | 新增 / census未join runtime |
| `1300076567` | 阳光少女 | 6 | 0 | 4 | 159 | 无 | 新增 / census未join runtime |
| `1315486372` | 貂蝉拜月 | 3 | 1 | 2 | 72 | 截图 | 新增 / census未join runtime |
| `1439846152` | 腿 | 2 | 0 | 1 | 33 | 无 | 新增 / census未join runtime |
| `1480826543` | Emilia X-ray NSFW | 2 | 2 | 1 | 62 | 无 | 新增 / census未join runtime |
| `1507413154` | 百褶裙 | 3 | 1 | 1 | 72 | 无 | 新增 / census未join runtime |
| `1507593643` | 蕾丝吊带 | 3 | 0 | 2 | 83 | 无 | 新增 / census未join runtime |
| `1511889295` | 死库水 | 3 | 1 | 2 | 119 | 无 | 新增 / census未join runtime |
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in the Franxx) - animated | 1 | 4 | 0 | 53 | 截图 | tracked45 / census未join runtime |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection) - animated xray | 3 | 21 | 0 | 209 | 截图 | tracked45 / census未join runtime |
| `1695673397` | 白发少女 4k动漫壁纸 | 4 | 1 | 2 | 72 | 截图 | 新增 / census未join runtime |
| `1926190458` | Morning_4k | 3 | 9 | 1 | 147 | 无 | 新增 / census未join runtime |
| `1937925563` | Tropical Paradise 4K [Customizable Colors &amp; Audio Visualizer] - Vaporwave &amp; Neon | 16 | 51 | 3 | 761 | 截图 | tracked45 / census未join runtime |
| `1989767609` | Black tights（透视） | 1 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `1994794519` | D.VA_OVERWATCH[X-Ray] | 3 | 2 | 2 | 87 | 无 | 新增 / census未join runtime |
| `2067939514` | Windows Visualizer | 45 | 80 | 4 | 850 | 截图 | tracked45 / census未join runtime |
| `2069136288` | [R18] Lexaiduer DOA Nagisa x Tamaki X-Ray Animated | 5 | 27 | 0 | 251 | 无 | 新增 / census未join runtime |
| `2112262451` | [R18] Sakimi Chan Azur Lane Belfast X-Ray Animated | 6 | 35 | 0 | 300 | 无 | 新增 / census未join runtime |
| `2131872317` | Night Market by 俊伦 何 in 4K | 18 | 21 | 9 | 667 | 截图 | tracked45 / census未join runtime |
| `2134765860` | Bunk | 42 | 79 | 1 | 949 | 截图 | tracked45 / census未join runtime |
| `2163522240` | [18+] jk x-ray 🔞😍 | 3 | 2 | 0 | 38 | 无 | 新增 / census未join runtime |
| `2179185481` | Azur Lane / 18+ X-ray NSFW &amp; SFW (3 Versions ) | 3 | 1 | 0 | 39 | 无 | 新增 / census未join runtime |
| `2181251652` | Mio Tokisaki (X-Ray) | 1 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `2231088993` | Ahri X-Ray | 1 | 3 | 0 | 42 | 无 | 新增 / census未join runtime |
| `2241938645` | KDA Akali [4k Version] | 6 | 10 | 2 | 228 | 截图 | tracked45 / census未join runtime |
| `2269193950` | WLOP - Nap | 4 | 4 | 2 | 135 | 无 | 新增 / census未join runtime |
| `2304304373` | Don't Die | 22 | 8 | 10 | 439 | 无 | 新增 / census未join runtime |
| `2347762662` | 18+ X-Ray │NSFW &amp; SFW│ ♥ 여대생♡ PT 2 ♥ ( 4 VERSIONS ) | 5 | 1 | 0 | 57 | 无 | 新增 / census未join runtime |
| `2356604986` | 1265079-1322607782 | 1 | 0 | 0 | 9 | 无 | 新增 / census未join runtime |
| `2419444134` | Nier Reincarnation - Akeha | 10 | 13 | 4 | 290 | 截图 | tracked45 / census未join runtime |
| `2470144420` | 女孩独享的宁静傍晚 | 4 | 6 | 2 | 124 | 截图 | tracked45 / census未join runtime |
| `2473638329` | Genshin Impact \| +18 / NSFW &amp; SFW | 2 | 7 | 1 | 111 | 截图 | tracked45 / census未join runtime |
| `2505351195` | Nier Automata / +21 \| NSFW &amp; SFW | 2 | 6 | 1 | 99 | 无 | 新增 / census未join runtime |
| `2507971256` | 麻匪 骚气音频可视化 | 9 | 6 | 0 | 124 | 截图 | 新增 / census未join runtime |
| `2524111047` | Liu Meryl Wei wei（被举报下架-重发） | 2 | 5 | 0 | 81 | 无 | 新增 / census未join runtime |
| `2607203340` | Tomb Raider +18 | 2 | 4 | 1 | 77 | 无 | 新增 / census未join runtime |
| `2616828675` | 【R18】别看了，快点啦~#4K#动态#16:9 | 6 | 14 | 4 | 252 | 无 | 新增 / census未join runtime |
| `2684431262` | 麻匪 炫酷音频律动 Windows | 17 | 25 | 1 | 273 | 无 | 新增 / census未join runtime |
| `2731896598` | 麻匪 A-SOUL | 27 | 21 | 3 | 408 | 截图 | 新增 / census未join runtime |
| `2735160334` | 麻匪 山景城 | 8 | 15 | 4 | 232 | 截图 | 新增 / census未join runtime |
| `2775915974` | R18*JK(escalator)エスカレーターJKさんX-ray | 4 | 12 | 0 | 150 | 无 | 新增 / census未join runtime |
| `2776912698` | 麻匪 洛天依 Android | 20 | 26 | 0 | 327 | 截图 | 新增 / census未join runtime |
| `2780710296` | 麻匪 miku 初音ミク 初音未来 Windows | 17 | 12 | 2 | 290 | 截图 | 新增 / census未join runtime |
| `2784267518` | 麻匪 D.Va 守望先锋 Windows | 15 | 18 | 1 | 312 | 截图 | 新增 / census未join runtime |
| `2787219305` | 麻匪 你的责任 Windows 4K 21:9 16:9 | 15 | 13 | 2 | 246 | 截图 | 新增 / census未join runtime |
| `2794098047` | 麻匪 是姐姐还是妹妹 windows | 15 | 20 | 1 | 332 | 无 | 新增 / census未join runtime |
| `2797913147` | 【R18】连体黑丝#4K#视差#可互动臀部#动态 | 3 | 7 | 0 | 83 | 无 | 新增 / census未join runtime |
| `2797943632` | 麻匪 僵尸女孩 Windows | 16 | 14 | 2 | 293 | 截图 | 新增 / census未join runtime |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养成好习惯 | 12 | 8 | 2 | 188 | 截图 | tracked45 / census未join runtime |
| `2804817823` | Yor Forger \| Spy x Family | 11 | 18 | 2 | 314 | 截图 | 新增 / census未join runtime |
| `2807058277` | 麻匪 森美声 森カリオペ Windows | 24 | 60 | 0 | 558 | 截图 | 新增 / census未join runtime |
| `2808874251` | youer | 6 | 0 | 5 | 138 | 无 | 新增 / census未join runtime |
| `2811643059` | 原神 | 1 | 4 | 0 | 60 | 无 | 新增 / census未join runtime |
| `2813231542` | 清新美女 R-18 | 6 | 13 | 1 | 202 | 无 | 新增 / census未join runtime |
| `2813240634` | 麻匪 NIXEU 九尾妖狐 | 10 | 15 | 1 | 214 | 截图 | 新增 / census未join runtime |
| `2814167871` | 麻匪 明日方舟 凯尔希 Windows | 40 | 33 | 1 | 615 | 截图 | 新增 / census未join runtime |
| `2815826216` | 麻匪 约尔·福杰 间谍过家家 SPY×FAMILY | 18 | 17 | 0 | 268 | 无 | 新增 / census未join runtime |
| `2819143171` | 麻匪 夜兰 原神 16:9 21:9 | 30 | 40 | 1 | 549 | 截图 | 新增 / census未join runtime |
| `2821634935` | 麻匪 德克萨斯 明日方舟 | 32 | 39 | 0 | 508 | 截图 | 新增 / census未join runtime |
| `2824109832` | Yor Forger - NIXEU 4K | 5 | 17 | 2 | 295 | 无 | 新增 / census未join runtime |
| `2824690710` | 麻匪 原神 雷电将军 Windows 16:9 21:9 | 44 | 51 | 3 | 623 | 截图 | 新增 / census未join runtime |
| `2831174267` | 麻匪 Lycoris Recoil 21:9 16:9 | 20 | 23 | 4 | 407 | 截图 | 新增 / census未join runtime |
| `2834973884` | 麻匪 wlop-鬼刀 重置版 | 9 | 12 | 1 | 212 | 无 | 新增 / census未join runtime |
| `2835398595` | 麻匪 碧蓝航线 独角兽 Windows | 52 | 30 | 8 | 675 | 截图 | 新增 / census未join runtime |
| `2837223712` | 李擎洲：阿狸[4K] | 7 | 1 | 4 | 142 | 无 | 新增 / census未join runtime |
| `2849382252` | 麻匪 死亡笔记 L·Lawliet | 18 | 17 | 9 | 481 | 无 | 新增 / census未join runtime |
| `2850139759` | 麻匪 血妖姬 16:9 / 21:9 | 15 | 15 | 2 | 315 | 截图 | 新增 / census未join runtime |
| `2866086594` | 麻匪 赛博朋克 边缘行者 露西 Lucy | 7 | 13 | 0 | 212 | 截图 | 新增 / census未join runtime |
| `2871175822` | 麻匪 猫 | 9 | 12 | 3 | 249 | 截图 | 新增 / census未join runtime |
| `2871552691` | 麻匪 操 | 6 | 3 | 0 | 73 | 截图 | 新增 / census未join runtime |
| `2877499944` | 麻匪 做什么壁纸？看美女不香？ | 15 | 10 | 0 | 156 | 截图 | 新增 / census未join runtime |
| `2877855240` | 麻匪 雷电将军 泳装 | 49 | 63 | 0 | 724 | 截图 | 新增 / census未join runtime |
| `2884170082` | 麻匪 wlop 小绿 | 20 | 34 | 0 | 406 | 截图 | 新增 / census未join runtime |
| `2884628849` | 麻匪 小姐姐 | 26 | 33 | 0 | 466 | 截图 | tracked45 / census未join runtime |
| `2887542690` | 麻匪 礼服斯卡蒂 3D版 | 57 | 53 | 2 | 771 | 截图 | 新增 / census未join runtime |
| `2890473419` | 麻匪 肉肉的雷电将军 3D 21:9 16:9 | 28 | 41 | 4 | 580 | 截图 | 新增 / census未join runtime |
| `2896873092` | Genshin Impact: Thicc Girls Spread Collage X-Ray R18+ | 11 | 64 | 0 | 579 | 无 | 新增 / census未join runtime |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 140 | 115 | 1 | 1754 | 截图 | tracked45 / census未join runtime |
| `2913492057` | 麻匪 粒子音频互动 | 5 | 2 | 3 | 159 | 截图 | 新增 / census未join runtime |
| `2917306763` | [4K/动态/R18/衣服透视可调]碧蓝航线-独角兽妹妹「天使的护理时间」-B站慕慕慕慕斯小蛋糕 | 8 | 15 | 0 | 173 | 无 | 新增 / census未join runtime |
| `2919854127` | 麻匪 辉夜 AHEGAO | 11 | 29 | 0 | 315 | 截图 | 新增 / census未join runtime |
| `2927205881` | 麻匪 音频识别 多素材自定义 | 65 | 97 | 9 | 1594 | 截图 | 新增 / census未join runtime |
| `2932157836` | [4K \| 可自定义] 星浴 \| Hoshi-yoku | 22 | 74 | 1 | 985 | 截图 | 新增 / census未join runtime |
| `2932631210` | 欧派-音乐乱动 | 6 | 7 | 3 | 188 | 无 | 新增 / census未join runtime |
| `2938612768` | 麻匪 音频识别 Media Player | 85 | 73 | 5 | 1369 | 截图 | tracked45 / census未join runtime |
| `2942486721` | R18 Ishtar And Ereshkigal / 遠坂 凛 Tohsaka Rin 4K [Fate/Grand Order] [NSFW] | 1 | 5 | 0 | 61 | 无 | 新增 / census未join runtime |
| `2949019513` | [4K \| 可自定义] A.R.O.N.A. (碧蓝档案) | 16 | 47 | 2 | 656 | 截图 | 新增 / census未join runtime |
| `2951452910` | 麻匪 一伊那尔栖 21:9 16:9 | 20 | 28 | 3 | 561 | 截图 | 新增 / census未join runtime |
| `2959875782` | [R18] Lexaiduer Last Origin Dark Elven Forest Ranger Wedding Dress X-Ray Animated | 136 | 292 | 0 | 2883 | 无 | 新增 / census未join runtime |
| `2960821850` | Media Player (2.0) | 16 | 26 | 2 | 387 | 截图 | 新增 / census未join runtime |
| `2964778792` | [4K/动态/R18-3.0版]碧蓝航线-莱莎琳·斯托特「熬夜的炼金术士」补档-B站慕慕慕慕斯小蛋糕 | 14 | 13 | 5 | 308 | 截图 | 新增 / census未join runtime |
| `2969308380` | 麻匪 三分钟一张流水线壁纸 简单且无聊 | 34 | 18 | 1 | 430 | 截图 | 新增 / census未join runtime |
| `2972071249` | 麻匪 宵剑 | 8 | 28 | 1 | 380 | 截图 | 新增 / census未join runtime |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 53 | 67 | 4 | 1163 | 截图 | tracked45 / census未join runtime |
| `2981249186` | 4K SCI-FI Black Hole | 12 | 9 | 4 | 256 | 无 | 新增 / census未join runtime |
| `2983846453` | 麻匪 自定义双背景开关 - Customizable Day/Night Switcher | 37 | 13 | 0 | 386 | 无 | 新增 / census未join runtime |
| `2986218263` | Tokisaki Asaba &amp; Tokisaki Mio │18+ X-Ray │NSFW &amp; SFW│VERSIONS | 5 | 1 | 1 | 73 | 无 | 新增 / census未join runtime |
| `2987771245` | 麻匪 Wlop鬼刀画作 雨儿 | 45 | 51 | 9 | 832 | 截图 | 新增 / census未join runtime |
| `2992924426` | 麻匪 炫彩男孩 16:9 21:9 | 19 | 43 | 0 | 460 | 截图 | 新增 / census未join runtime |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 22 | 22 | 15 | 738 | 截图 | tracked45 / census未join runtime |
| `2999907577` | 麻匪 站姬 16:9 21:9 | 10 | 39 | 0 | 357 | 截图 | 新增 / census未join runtime |
| `3002649614` | 纯欲少女 | 4 | 0 | 0 | 27 | 无 | 新增 / census未join runtime |
| `3021013015` | 赛博color-墨侠客行 | 3 | 6 | 1 | 114 | 无 | 新增 / census未join runtime |
| `3022080536` | 赛博color-宣纸国画-紫罗兰永恒花园 | 4 | 5 | 1 | 149 | 截图 | 新增 / census未join runtime |
| `3025969015` | 黑龙闹海 | 9 | 7 | 7 | 280 | 无 | 新增 / census未join runtime |
| `3027056454` | 麻匪 多娜多娜 Dohna Dohna | 24 | 24 | 1 | 422 | 截图 | 新增 / census未join runtime |
| `3027068980` | 麻匪 Miku 初音未来 自定义音频识别 Media Player | 32 | 51 | 5 | 673 | 截图 | 新增 / census未join runtime |
| `3028090166` | WLOP [Tian Nan2] | 12 | 20 | 2 | 347 | 截图 | tracked45 / census未join runtime |
| `3039704323` | 赛博color-宣纸国画-紫罗兰永恒花园3 | 7 | 9 | 2 | 239 | 截图 | 新增 / census未join runtime |
| `3039882306` | 麻匪 音频识别 抽签 Media Player | 45 | 54 | 0 | 718 | 截图 | 新增 / census未join runtime |
| `3042492564` | [4K \| Customizable] Hoshi-Tele \| 星屑テレパス | 79 | 90 | 10 | 2363 | 截图 | 新增 / census未join runtime |
| `3078285611` | 麻匪 金克丝 jinx 音频识别 Media Player | 70 | 31 | 4 | 757 | 无 | 新增 / census未join runtime |
| `3086016320` | 麻匪 发如雪 21:9 16:9 | 26 | 30 | 3 | 478 | 截图 | 新增 / census未join runtime |
| `3087231311` | 麻匪 明日方舟 凯尔希 | 23 | 35 | 2 | 498 | 截图 | 新增 / census未join runtime |
| `3088601835` | Winter Wanderer Xayah - League of Legends [ NAMAKXIN ] | 31 | 36 | 19 | 875 | 截图 | tracked45 / census未join runtime |
| `3113287126` | Dome 4k {Artwork by WLOP} | 31 | 46 | 5 | 801 | 无 | 新增 / census未join runtime |
| `3113554287` | 【可随时间变化】窗旁の伊蕾娜 （优化版本） | 6 | 1 | 0 | 56 | 无 | 新增 / census未join runtime |
| `3114332546` | 麻匪 云兮 竹林的小师妹 | 46 | 55 | 9 | 1054 | 截图 | 新增 / census未join runtime |
| `3115163440` | Shadow Garden (X-Ray) | 2 | 1 | 0 | 34 | 无 | 新增 / census未join runtime |
| `3122339805` | Pixels | 190 | 17 | 0 | 790 | 截图 | tracked45 / census未join runtime |
| `3137495261` | 麻匪 花姐 21:9 16:9 | 94 | 34 | 6 | 978 | 截图 | 新增 / census未join runtime |
| `3141421197` | GraspOfTheAbyss | 1 | 1 | 0 | 12 | 截图 | tracked45 / census未join runtime |
| `3146507587` | こきん【吉罗】 | 18 | 32 | 6 | 561 | 无 | 新增 / census未join runtime |
| `3147346398` | ⛏🧱Minecraft Lo-Fi Fireplace [4k HDR] WE adaptation by Becco38 | 11 | 2 | 0 | 89 | 无 | 新增 / census未join runtime |
| `3148125112` | 麻匪 薇薇安娜 明日方舟 4K | 68 | 51 | 3 | 853 | 截图 | 新增 / census未join runtime |
| `3167210190` | [Blue Archive] 奶牛装明日奈 | 1 | 5 | 0 | 65 | 无 | 新增 / census未join runtime |
| `3173418061` | Persona 5/女神异闻录5 音乐播放器 | 21 | 7 | 1 | 162 | 截图 | 新增 / census未join runtime |
| `3175039950` | 麻匪 音频节拍互动 Music beat interaction | 33 | 26 | 2 | 518 | 截图 | 新增 / census未join runtime |
| `3211615441` | 捆绑悬挂 \| Bind &amp; Suspend [ 可交互/interactive \| iumu \| X-ray \| 4k \| 明日方舟/Arknights ] | 26 | 116 | 0 | 1049 | 无 | 新增 / census未join runtime |
| `3219398263` | Acheron Black Hole (StarchaserArt) | 10 | 1 | 6 | 187 | 无 | 新增 / census未join runtime |
| `3221354414` | dynamic Ginka 神轿银花 [GINKA OST: 祭神纸偶与愿望 梦浮桥（Instrumental）][8K HDR ] | 7 | 11 | 5 | 227 | 无 | 新增 / census未join runtime |
| `3226487183` | 麻匪 花火 五角色自定义 崩坏星穹铁道 Sparkle Honkai: Star Rail 媒体音频识别 Media Player 16:9 16:10 21:9 32 | 52 | 105 | 3 | 1327 | 截图 | 新增 / census未join runtime |
| `3232289987` | 【4k 高度自定义】流萤&amp;萨姆 丝袜可更改——夜莺Night【崩坏星穹铁道】 | 60 | 52 | 9 | 1377 | 无 | 新增 / census未join runtime |
| `3233141951` | 熠烛 御剑驭龙-红鸾樱落 高度自定义Red Warbler-Sakura falls （Highly customizable） | 65 | 59 | 9 | 1022 | 无 | 新增 / census未join runtime |
| `3238423642` | Katana Girl with Hologram (Adjustable; 4k; Cyberpunk Samurai) MX | 96 | 123 | 31 | 3035 | 无 | 新增 / census未join runtime |
| `3248220186` | 麻匪 音频粒子球 Audio Particle Ball 16:9 16:10 21:9 32:9 | 14 | 4 | 6 | 451 | 截图 | 新增 / census未join runtime |
| `3264246690` | 麻匪 wlop 鬼刀 月牙儿 16:9 16:10 21:9 32:9 | 36 | 33 | 0 | 571 | 截图 | 新增 / census未join runtime |
| `3287715210` | 发光少女 4K动态壁纸 | 12 | 8 | 2 | 192 | 无 | 新增 / census未join runtime |
| `3290491250` | frieren | 5 | 3 | 1 | 76 | 截图 | tracked45 / census未join runtime |
| `3291326967` | 蒙眼少女 4K动态壁纸 | 19 | 13 | 11 | 507 | 截图 | 新增 / census未join runtime |
| `3292370168` | 麻匪 3D 自定义动态交互 骷髅 音频识别 Human Skeleton Media Player | 150 | 15 | 10 | 852 | 截图 | 新增 / census未join runtime |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , Chill , Multi language | 271 | 276 | 42 | 4346 | 截图 | tracked45 / census未join runtime |
| `3323988600` | Hentai Goddess of Victory Nikke ANIMATED \| Huge Ass Cowgirl \| NSFW R-18 \| Customizable | 6 | 6 | 4 | 207 | 无 | 新增 / census未join runtime |
| `3325624777` | 麻匪 修女 鼠标互动 nun 16:9 21:9 32:9 16:10 | 12 | 19 | 4 | 600 | 截图 | 新增 / census未join runtime |
| `3337494481` | 麻匪 3D交互音频模块 媒体识别 Media Player 16:9 16:10 21:9 32:9 | 72 | 25 | 22 | 1154 | 截图 | 新增 / census未join runtime |
| `3341111071` | 麻匪 初音未来 MIKU 海边 32:9 21:9 16:9 16:10 | 18 | 51 | 2 | 511 | 截图 | 新增 / census未join runtime |
| `3351163962` | [高度自定义] 樱花庄的宠物女孩 椎名真白 | 136 | 59 | 8 | 1528 | 截图 | 新增 / census未join runtime |
| `3351179520` | 麻匪 東京喰种 高槻泉 媒体识别 Media Player 16:9 16:10 21:9 32:9 | 55 | 72 | 8 | 1067 | 截图 | 新增 / census未join runtime |
| `3357627941` | 麻匪 开门见喜 鼠标交互 自定义本地文件 Windows door 16:9 21:9 | 13 | 7 | 1 | 204 | 无 | 新增 / census未join runtime |
| `3363252053` | 【Parallax视差】Hatsune Miku 初音未来 光与影——夜莺Night Light and Shadow | 48 | 34 | 4 | 801 | 无 | 新增 / census未join runtime |
| `3372715909` | 御坂美琴 旗袍 | 17 | 1 | 0 | 153 | 无 | 新增 / census未join runtime |
| `3374523158` | 麻匪 极光音频响应式 交互壁纸 Aurora audio-responsive interactive | 18 | 21 | 1 | 427 | 截图 | 新增 / census未join runtime |
| `3383535304` | 麻匪 顶顶 音频感应自动场景切换 Audio monitoring scene switching | 51 | 81 | 4 | 898 | 截图 | 新增 / census未join runtime |
| `3389974179` | 落日与白皙的大腿 | 4 | 4 | 0 | 99 | 无 | 新增 / census未join runtime |
| `3395392965` | 请叫我帅锅-小姨定制 | 1 | 1 | 0 | 22 | 无 | 新增 / census未join runtime |
| `3395777145` | 麻匪 光 音频识别 Media Player 16:9 16:10 21:9 | 21 | 39 | 0 | 533 | 无 | 新增 / census未join runtime |
| `3396722575` | 麻匪 NIXEU 黄泉 超多自定义模块 音频识别 Media Player 16:9 16:10 4:3 21:9 32:9 | 61 | 76 | 16 | 1827 | 无 | 新增 / census未join runtime |
| `3420215721` | 麻匪 圈 媒体识别交互壁纸 Circle Media Player | 41 | 59 | 2 | 764 | 无 | 新增 / census未join runtime |
| `3435573282` | 麻匪 巳蛇 自定义动画 音频识别 Media Player | 73 | 109 | 11 | 1492 | 截图 | 新增 / census未join runtime |
| `3436945972` | 麻匪 Wlop 远方来客 | 102 | 117 | 30 | 3169 | 截图 | 新增 / census未join runtime |
| `3437487219` | 3D Earth - Close Orbit [HDR10 Optimized] | 21 | 4 | 2 | 201 | 截图 | 新增 / census未join runtime |
| `3446316682` | 【完美世界】柳神 无敌道 | 6 | 10 | 4 | 248 | 截图 | 新增 / census未join runtime |
| `3448845950` | 麻匪 媒体音频标签【148项自定义】Media Player 16:9 16:10 21:9 32:9 | 81 | 103 | 2 | 1291 | 截图 | 新增 / census未join runtime |
| `3448877775` | 【Time Variation 时间变化】Alone 孤独の少女——夜莺Night【原画：Rella] | 103 | 40 | 14 | 1525 | 截图 | 新增 / census未join runtime |
| `3470948192` | 水滴 三体 \| Droplet -SYKM | 49 | 6 | 0 | 338 | 无 | 新增 / census未join runtime |
| `3471294034` | 麻匪 巳 UnclePanda [3大UI布局切换] | 100 | 109 | 20 | 1660 | 截图 | 新增 / census未join runtime |
| `3472940912` | -Tsukatsuki Rio [ blue archive ] - 4K | 3 | 6 | 0 | 90 | 无 | 新增 / census未join runtime |
| `3476868923` | 麻匪 索泰ZOTAC 天启姬 (角色双动画 点击互动) 120项自定义 | 84 | 124 | 2 | 1414 | 截图 | 新增 / census未join runtime |
| `3477054430` | Cat with headphones on the roof | 15 | 2 | 0 | 133 | 截图 | 新增 / census未join runtime |
| `3486887298` | 风景系列-真4K【流星、夜晚】-B站慕慕慕慕斯小蛋糕 | 6 | 7 | 0 | 117 | 截图 | 新增 / census未join runtime |
| `3487629864` | 云曦老婆 (18+) | 4 | 5 | 2 | 102 | 无 | 新增 / census未join runtime |
| `3507496797` | 麻匪 龙吟锦鲤赋 32:9 | 35 | 116 | 4 | 1206 | 截图 | 新增 / census未join runtime |
| `3509243656` | 三体实时演算 \| Three-Body problem - SYKM | 142 | 12 | 4 | 1255 | 无 | 新增 / census未join runtime |
| `3549827466` | 【完美世界 火灵儿】盛典妆容 | 7 | 9 | 5 | 279 | 截图 | 新增 / census未join runtime |
| `3554161528` | Blue Archive-Sorasaki Hina 空崎日奈[4K] | 37 | 24 | 13 | 855 | 无 | 新增 / census未join runtime |
| `3562021804` | 【完美世界】石昊 以身为种 | 9 | 14 | 1 | 198 | 截图 | 新增 / census未join runtime |
| `3563038726` | 【凡人修仙传】梅凝 乖巧可怜 | 13 | 12 | 3 | 257 | 截图 | 新增 / census未join runtime |
| `3566880847` | 【凡人修仙传】紫灵 白色限定 | 8 | 15 | 4 | 305 | 截图 | 新增 / census未join runtime |
| `3577990983` | Chainsaw Man-Reze 蕾塞[4K] | 46 | 27 | 2 | 697 | 截图 | 新增 / census未join runtime |
| `3581882134` | 【凡人修仙传】紫灵 冰清玉洁 | 26 | 41 | 9 | 782 | 截图 | 新增 / census未join runtime |
| `3585542943` | 【凡人修仙传】元瑶 灵泉沐浴 | 22 | 29 | 5 | 602 | 截图 | 新增 / census未join runtime |
| `3585875739` | Miku Monitoring | 3 | 6 | 2 | 148 | 无 | 新增 / census未join runtime |
| `3586705329` | [甜蜜女友3]柳木诗梦 | 23 | 14 | 1 | 316 | 截图 | 新增 / census未join runtime |
| `3587571382` | 【凡人修仙传】宋玉 璀璨夺目 | 26 | 23 | 6 | 460 | 截图 | 新增 / census未join runtime |
| `3589454154` | 土星 \| Saturn - Sykm | 130 | 44 | 1 | 955 | 截图 | 新增 / census未join runtime |
| `3597772384` | Lost Landscape \| northway. | 63 | 74 | 7 | 1200 | 截图 | 新增 / census未join runtime |
| `3599986633` | 麻匪 杉泽 观山海 | 52 | 71 | 1 | 770 | 截图 | 新增 / census未join runtime |
| `3601801724` | ash一爪布鲁托 | 2 | 0 | 1 | 33 | 截图 | 新增 / census未join runtime |
| `3601964477` | 千咲 \|\| 鸣潮 \|\| 枫 \|\| 4K | 33 | 20 | 3 | 519 | 无 | 新增 / census未join runtime |
| `3603711180` | 【凡人修仙传】慕沛灵 金屋藏娇 | 63 | 52 | 6 | 920 | 截图 | 新增 / census未join runtime |
| `3605502569` | 顾州-暗影魅眸｜Shadow · Charming Eyes | 10 | 7 | 1 | 198 | 截图 | 新增 / census未join runtime |
| `3605722997` | [假装4K]魔王-追悼【可交互壁纸】（喜欢的点个赞呗） | 41 | 8 | 5 | 435 | 截图 | 新增 / census未join runtime |
| `3609108600` | 千咲 \|\| 鸣潮 \|\| 4K | 5 | 12 | 0 | 143 | 无 | 新增 / census未join runtime |
| `3610154602` | 千咲 \|\| 鸣潮 \|\| 高塔 \|\| 4K | 26 | 16 | 2 | 409 | 无 | 新增 / census未join runtime |
| `3612058080` | 吞噬星空-星幻王 | 1 | 2 | 0 | 28 | 无 | 新增 / census未join runtime |
| `3612199597` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 咖啡厅天台 \|\| 4K | 30 | 20 | 5 | 716 | 无 | 新增 / census未join runtime |
| `3612795410` | 千咲 \|\| 鸣潮 \|\| 与千咲的穗波散步 \|\| 喷泉广场 \|\| 4K | 30 | 22 | 1 | 454 | 无 | 新增 / census未join runtime |
| `3616389236` | Aesthetic Media Visualizer (Shortcut) \| 𝙎𝙚𝙮𝙪𝙡.𝙎𝙖𝙡𝙩𝙯 | 77 | 102 | 0 | 1212 | 截图 | 新增 / census未join runtime |
| `3617056047` | 麻匪 模型音频互动 Model - audio interaction | 13 | 4 | 0 | 169 | 截图 | 新增 / census未join runtime |
| `3627973226` | [Sakiko Togawa]snowy night - It's MyGO!!!!!/AveMujica | 40 | 36 | 10 | 793 | 截图 | 新增 / census未join runtime |
| `3629927359` | 奶牛大鸭鸭 2 | 25 | 0 | 0 | 203 | 无 | 新增 / census未join runtime |
| `3632513108` | 千咲 不散的春之花——夜莺Night《鸣潮 Wuthering Waves》 | 140 | 98 | 2 | 1947 | 截图 | 新增 / census未join runtime |
| `3632522893` | Widescreen Mount Fuji Visualiser | 36 | 27 | 1 | 468 | 截图 | 新增 / census未join runtime |
| `3641200550` | 樱羽艾玛 | 2 | 1 | 0 | 22 | 截图 | 新增 / census未join runtime |
| `3655958892` | R18 Acheron &amp; Black Swan 黄泉&amp;黑天鹅 [Honkai:Star Rail] [NSFW] | 11 | 10 | 0 | 180 | 无 | 新增 / census未join runtime |
| `3662245960` | Wuthering Waves - Aemeath | 4 | 6 | 1 | 137 | 截图 | 新增 / census未join runtime |
| `3662390671` | 【Angels of Delusion】\| Sunna \| Aria \| Nangong Yu \| Zenless Zone Zero (ZZZ) \| Customizable \| Media Integration | 58 | 70 | 1 | 928 | 无 | 新增 / census未join runtime |
| `3662790108` | 实时太阳系 Live Solar System - SYKM | 847 | 70 | 0 | 4615 | 无 | 新增 / census未join runtime |
| `3663810817` | 鎏金狮影映娇颜 | 30 | 19 | 12 | 917 | 无 | 新增 / census未join runtime |
| `3665307769` | 爱弥斯1 \|\| 鸣潮 \|\| 4K | 29 | 30 | 3 | 603 | 无 | 新增 / census未join runtime |
| `3666041758` | 麻匪 磁流体 Magnetofluid 音频相应 | 18 | 8 | 0 | 455 | 截图 | 新增 / census未join runtime |
| `3680252478` | SUPRA A80 \| GREY HORIZON | 9 | 25 | 2 | 303 | 截图 | 新增 / census未join runtime |
| `3690065713` | 老人-棕发女孩 [带鱼屏4K] | 17 | 19 | 3 | 345 | 截图 | 新增 / census未join runtime |
| `3690859128` | 爱弥斯2 \|\| 鸣潮 \|\| 4K | 21 | 14 | 9 | 605 | 无 | 新增 / census未join runtime |
| `3694697894` | 星街すいせい 星街彗星（第二版） | 6 | 5 | 1 | 182 | 截图 | 新增 / census未join runtime |
| `3695791724` | Angel (Commission; Adjustable; 4k) MX | 30 | 27 | 12 | 844 | 截图 | 新增 / census未join runtime |
| `3698459055` | 凡人修仙传-梅凝·暗系[4K] | 23 | 3 | 5 | 328 | 截图 | 新增 / census未join runtime |
| `3699213569` | 碧蓝航线Azurlane-斯特拉斯堡&amp;克莱蒙梭（By Adramahlihk） | 1 | 5 | 0 | 62 | 无 | 新增 / census未join runtime |
| `3703104370` | Rio&amp;菲比-adoc(涟) | 1 | 6 | 0 | 69 | 无 | 新增 / census未join runtime |
| `3708363772` | 麻匪 3D磨砂 音频识别 Media Player | 72 | 67 | 1 | 1038 | 截图 | 新增 / census未join runtime |
| `3712499998` | 鸣潮 \|\| 3.3pv \| 自星海尽处回响 | 21 | 0 | 5 | 463 | 无 | 新增 / census未join runtime |
| `3719111841` | 【明日方舟/Arknights】凯尔希•思衡托——Kal'tsit·Esperanta | 43 | 23 | 8 | 672 | 截图 | 新增 / census未join runtime |
| `3721456868` | 绯雪1 \|\| 鸣潮 | 13 | 18 | 2 | 317 | 无 | 新增 / census未join runtime |
| `3722749868` | Porsche GT3 RS | 11 | 6 | 7 | 265 | 截图 | 新增 / census未join runtime |
| `3723344874` | 【凡人修仙传】玄骨 借尸还魂 | 35 | 37 | 4 | 818 | 截图 | 新增 / census未join runtime |
| `3738202317` | Albedo. | 1 | 4 | 0 | 60 | 截图 | tracked45 / census未join runtime |
| `3742133044` | 凌霄·双司镇命·无常&lt;1&gt;-[深空之眼] | 4 | 5 | 2 | 122 | 截图 | tracked45 / census未join runtime |
| `3742497499` | 麻匪 白泽夢 | 141 | 120 | 10 | 1741 | 截图 | 新增 / census未join runtime |
| `3743305891` | 战双 | 8 | 4 | 1 | 145 | 截图 | tracked45 / census未join runtime |
| `3745828537` | 麻匪 xraypad-眠 | 214 | 328 | 11 | 2846 | 截图 | 新增 / census未join runtime |
| `3746422401` | 麻匪 泠泠泉心 21:9 16:9 | 34 | 59 | 0 | 660 | 截图 | 新增 / census未join runtime |
| `3747190633` | 【凡人修仙传】银月 惹人怜惜 | 38 | 29 | 7 | 571 | 截图 | 新增 / census未join runtime |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Evil 4 Remake \| Re4 | 21 | 13 | 1 | 592 | 截图 | tracked45 / census未join runtime |
| `3748311238` | 大 | 6 | 17 | 0 | 265 | 无 | 新增 / census未join runtime |
| `3749463715` | 还能在大 ∑ 2 | 28 | 37 | 8 | 1018 | 无 | 新增 / census未join runtime |
| `3750342273` | Night snowy mountains | 8 | 6 | 1 | 115 | 截图 | tracked45 / census未join runtime |
| `3750813609` | Asian Temple in the Mountains | 13 | 5 | 9 | 391 | 截图 | tracked45 / census未join runtime |
| `3754630802` | WLOP [ChineseNewYear 7] | 38 | 31 | 10 | 1052 | 无 | 新增 / census未join runtime |
| `3754639143` | WLOP 银月 | 22 | 20 | 2 | 465 | 无 | 新增 / census未join runtime |
| `3754908581` | DJGun Making Noise!(Lite) | 5 | 3 | 0 | 34 | 截图 | 新增 / census未join runtime |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 9 | 9 | 7 | 425 | 截图 | tracked45 / census未join runtime |
| `3761159935` | 【诛仙】陆雪琪 等待的沉默 | 32 | 27 | 13 | 767 | 无 | 新增 / census未join runtime |
| `3761619125` | 麻匪 雪竹 | 73 | 123 | 3 | 1321 | 截图 | 新增 / census未join runtime |
| `3762312138` | Elf x Goth | 2 | 9 | 0 | 100 | 无 | 新增 / census未join runtime |
| `3763323436` | 3763323436 | 0 | 0 | 0 | 0 | 无 | 新增 / census未join runtime |
| `3763428294` | 秧秧·玄翎1\|\|穗穗\|\|舟行画中，心随风远\|\|鸣潮 | 16 | 25 | 3 | 413 | 无 | 新增 / census未join runtime |
| `3764725758` | Lumine_HuuOliv | 17 | 10 | 4 | 262 | 截图 | 新增 / census未join runtime |
| `3765760121` | 【4K】三色堇与她 | 13 | 12 | 1 | 209 | 截图 | tracked45 / census未join runtime |
| `3765904723` | 调月莉音 | 5 | 9 | 0 | 128 | 无 | 新增 / census未join runtime |
| `3766299002` | 麻匪 皓风琦修罗 双主题切换 | 62 | 71 | 3 | 945 | 截图 | 新增 / census未join runtime |
| `3766310551` | 【完美世界】柳神 九劫焚天 | 21 | 25 | 6 | 502 | 截图 | 新增 / census未join runtime |
| `3766387484` | ARKNIGHTS ENDFIELD ARCANE CHEN XIANGYU | 7 | 13 | 1 | 229 | 截图 | tracked45 / census未join runtime |
| `3766403294` | 仪玄(AI) | 2 | 1 | 0 | 30 | 截图 | tracked45 / census未join runtime |
| `3766415113` | The last pour | 1 | 0 | 0 | 9 | 截图 | tracked45 / census未join runtime |
| `3767232084` | 谬因 | 3 | 7 | 2 | 159 | 截图 | tracked45 / census未join runtime |
| `3767343314` | Universe Abstract - By: CroSsHaiR-&gt; | 4 | 3 | 3 | 117 | 截图 | tracked45 / census未join runtime |
| `3767460992` | Magic mushroom | 9 | 39 | 0 | 281 | 截图 | tracked45 / census未join runtime |
| `3768020435` | Silver Wolf with media integration | 9 | 3 | 0 | 73 | 截图 | tracked45 / census未join runtime |
| `3768229922` | 麻匪 赤芒 音频互动 | 58 | 74 | 2 | 838 | 截图 | tracked45 / census未join runtime |
| `3768724269` | ARKNIGHTS ENDFIELD 4K GILBERTA IN CLOUDS | 17 | 12 | 4 | 315 | 截图 | tracked45 / census未join runtime |
| `3768903841` | Naha Gaze at Firework \| northway. | 37 | 18 | 5 | 413 | 截图 | tracked45 / census未join runtime |
| `3769364482` | 戴拿奥特曼 强壮型【Ultraman Dyna Strong Type】dy柊明 | 10 | 13 | 3 | 384 | 截图 | tracked45 / census未join runtime |
| `3769688830` | Spirit Blossom Springs Ahri (Adjustable; League of Legends) MX | 26 | 59 | 6 | 777 | 截图 | tracked45 / census未join runtime |
| `3769761761` | Yoru and Mitaka asa | 20 | 24 | 5 | 524 | 截图 | tracked45 / census未join runtime |
| `3770444459` | 三国杀【节气 夏至 2026】8K | 6 | 4 | 5 | 247 | 截图 | tracked45 / census未join runtime |
| `3770462923` | gt3rs@d4rk | 4 | 5 | 0 | 100 | 截图 | tracked45 / census未join runtime |
| `3773747576` | 麻匪 棘 三模式切换 | 47 | 49 | 4 | 619 | 截图 | 新增 / census未join runtime |
| `3775355045` | 交错战线_DAIBLOS CORE_x-ray_4K_1 | 2 | 1 | 0 | 31 | 无 | 新增 / census未join runtime |
| `3775373546` | 交错战线_DAIBLOS CORE_x-ray_4K_2 | 2 | 1 | 0 | 31 | 无 | 新增 / census未join runtime |
| `3777761326` | I do Anything | 7 | 22 | 1 | 266 | 无 | 新增 / census未join runtime |
| `3779026256` | [魔法少女的魔女审判] 月代雪 X 樱羽艾玛 音频识别 | 30 | 22 | 2 | 487 | 无 | 新增 / census未join runtime |
| `3779107475` | 麻匪 赛驴 音频识别互动 | 11 | 15 | 0 | 210 | 截图 | 新增 / census未join runtime |
| `3779904456` | 尤诺2 \|\| 鸣潮 | 15 | 11 | 5 | 397 | 无 | 新增 / census未join runtime |
| `3780119725` | in the rain V 31 | 89 | 37 | 48 | 1993 | 截图 | 新增 / census未join runtime |
| `3780391264` | Agnes Tachyon Umamusume Neon | 19 | 7 | 10 | 516 | 截图 | 新增 / census未join runtime |
| `3780940857` | 枕澜 蒂法 电脑动态壁纸 最终幻想7 TIFA Final Fantasy VII | 2 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `3781307553` | Look this | 2 | 5 | 0 | 66 | 无 | 新增 / census未join runtime |
| `3781757083` | 羽毛笔-天国来信・Arknights | 48 | 27 | 6 | 596 | 截图 | 新增 / census未join runtime |
| `3782650329` | 我们三 X-ray | 1 | 3 | 0 | 46 | 无 | 新增 / census未join runtime |
| `3782740481` | WLOP Violet 紫 | 23 | 21 | 1 | 480 | 无 | 新增 / census未join runtime |
| `3784012236` | &gt;R-18&lt; 蔚蓝档案 Blue_Archive\|06\|飛鳥馬 トキ 时 Toki_Asuma X-ray | 2 | 1 | 0 | 35 | 无 | 新增 / census未join runtime |
| `3786048634` | 2B and A2 | 2 | 7 | 0 | 74 | 无 | 新增 / census未join runtime |
| `3786185473` | ELF PARADISE～欢迎来到性夜♪色情精灵们的淫乱圣诞节特别篇～ \| (x-ray) | 4 | 4 | 0 | 79 | 无 | 新增 / census未join runtime |
| `3786330502` | 麻匪 Astra GamingGear 含羞 | 113 | 184 | 6 | 2037 | 截图 | 新增 / census未join runtime |
| `3786641495` | Albedo - Look at here my master | 2 | 12 | 0 | 109 | 无 | 新增 / census未join runtime |
| `3787355076` | 维琳娜-申请入股 | 1 | 1 | 0 | 22 | 无 | 新增 / census未join runtime |
| `3787382101` | 清宵 \|\| 万剑 \|\| 鸣潮 | 15 | 12 | 3 | 375 | 无 | 新增 / census未join runtime |
| `3788066613` | [Hajily-1825][R-18]2025-07-04 Fleurdelys 3D P1 | 17 | 1 | 2 | 202 | 无 | 新增 / census未join runtime |
| `3788467391` | Miku and Monster | 5 | 18 | 1 | 190 | 无 | 新增 / census未join runtime |
| `3788645041` | 奥黛塔(破洞版) | 3 | 8 | 0 | 100 | 无 | 新增 / census未join runtime |
| `3788698200` | NFFA画风 维琳娜2（可去防封马赛克+可去时钟） | 3 | 1 | 1 | 69 | 无 | 新增 / census未join runtime |
| `3788734811` | 庄方宜-1 | 4 | 5 | 2 | 113 | 无 | 新增 / census未join runtime |
| `3788897599` | ArT丨R18丨4K丨Red Q | 18 | 25 | 3 | 540 | 无 | 新增 / census未join runtime |
| `3789316755` | Fern_Frieren | 8 | 6 | 2 | 149 | 无 | 新增 / census未join runtime |
| `3790631363` | 三国杀【水殿香来 曹金玉】限制级 4K | 8 | 7 | 6 | 330 | 无 | 新增 / census未join runtime |
| `3790726145` | 周于希54 | 2 | 0 | 1 | 31 | 无 | 新增 / census未join runtime |
| `3790806929` | Winter Artoria Pendragon \| Fate/Zero [4K] | 7 | 9 | 3 | 183 | 无 | 新增 / census未join runtime |
| `3790956325` | 骚暖暖 | 1 | 2 | 0 | 31 | 无 | 新增 / census未join runtime |
| `3791905266` | Dohrn's Vision | 2 | 3 | 1 | 97 | 无 | 新增 / census未join runtime |
| `3791967416` | 麻匪 虎符电竞 兰 16:9 21:9 | 58 | 102 | 0 | 967 | 截图 | 新增 / census未join runtime |
| `3792249095` | Beth's Wallpaper | 17 | 10 | 2 | 233 | 截图 | 新增 / census未join runtime |
| `3792400801` | Girl \| Dark Background \| Dark / Colored Versions \| 4K | 8 | 14 | 1 | 196 | 无 | 新增 / census未join runtime |
| `3792817546` | 小羊不吃草 (地雷系)#滕子京大王 | 5 | 0 | 1 | 62 | 无 | 新增 / census未join runtime |
| `3793328876` | 大凤Taihou&amp;白凤Hakuhou-HanAI | 1 | 6 | 0 | 69 | 无 | 新增 / census未join runtime |
| `3793978239` | 埃吉尔掰穴 | 1 | 0 | 0 | 9 | 无 | 新增 / census未join runtime |
| `3793998447` | 枕中梦 | 4 | 2 | 0 | 55 | 截图 | 新增 / census未join runtime |
| `3796588443` | ZZZ 薇薇安 法厄同 Vivian Belle 鼠标互动揉胸 | 16 | 44 | 2 | 500 | 无 | 新增 / census未join runtime |
| `3797217144` | 迪迦奥特曼 出场动画 镜头视差【Ultraman Tiga】dy柊明 | 26 | 30 | 5 | 535 | 无 | 新增 / census未join runtime |
| `3800075350` | 三角洲三小只-RX | 5 | 0 | 2 | 51 | 无 | 新增 / census未join runtime |
| `3800356808` | Warmth Valley Misty \| northway. | 31 | 15 | 10 | 536 | 无 | 新增 / census未join runtime |
| `3800572533` | [4K \| Day/Night] Neuro and Evil (by ArissamuHoshi) | 5 | 2 | 0 | 61 | 无 | 新增 / census未join runtime |
| `3800728730` | 浮士德ego穴 | 2 | 0 | 0 | 13 | 无 | 新增 / census未join runtime |
| `3801294161` | Reze - Let's turn off the lights | 5 | 13 | 1 | 154 | 无 | 新增 / census未join runtime |
| `3801984224` | 粉红护士 | 1 | 0 | 0 | 9 | 无 | 新增 / census未join runtime |
| `3802005866` | 绝区零 维琳娜 西域风 Zenless Zone Zero Velina | 13 | 14 | 0 | 248 | 截图 | 新增 / census未join runtime |
| `3803087940` | 原神 少女黑丝玉足 X - ray NSFW 差分 | 3 | 3 | 1 | 79 | 无 | 新增 / census未join runtime |
| `3803482159` | Black Morpho | 6 | 3 | 3 | 161 | 无 | 新增 / census未join runtime |
| `3803576671` | NFFA画风 冰雪公主（可去防封马赛克+可去时钟） | 3 | 1 | 1 | 69 | 无 | 新增 / census未join runtime |
| `3804441338` | Misty Summit 2 \| northway. | 27 | 18 | 10 | 494 | 无 | 新增 / census未join runtime |
| `3804906814` | 瞳中星火 新约能天使 明日方舟 4k60fps 组件自定义 【bilibili钻石什么屑】 | 10 | 5 | 1 | 166 | 无 | 新增 / census未join runtime |
| `3804971850` | Mobius梅比乌斯4 | 7 | 5 | 2 | 142 | 无 | 新增 / census未join runtime |
| `3805449677` | 御图网-浅雾藏山语 | 2 | 0 | 1 | 36 | 无 | 新增 / census未join runtime |
| `3805547608` | 碧蓝航线 金鹿号【R18版/语音/多功能壁纸】-B站慕慕慕慕斯小蛋糕1.0 | 23 | 3 | 5 | 270 | 无 | 新增 / census未join runtime |
| `3806006894` | 三角洲行动露娜天际线_LUNA_4K动态初版FLYSMALLPIG | 5 | 3 | 1 | 76 | 无 | 新增 / census未join runtime |
| `3806016969` | 三角洲行动红狼蚀金玫瑰_黑金_动态版4K_FLYSMALLPIG | 5 | 3 | 1 | 73 | 无 | 新增 / census未join runtime |
| `3806202923` | Azur Lane 碧蓝航线光辉 | 27 | 24 | 5 | 440 | 无 | 新增 / census未join runtime |
| `3806337293` | 初音未来 hatsune miku 3d视差 4k | 11 | 21 | 0 | 272 | 截图 | 新增 / census未join runtime |
| `3807013762` | Frieren | 30 | 21 | 1 | 339 | 无 | 新增 / census未join runtime |
| `3807121855` | 鸣潮今汐-桃花鸢 | 3 | 0 | 1 | 49 | 无 | 新增 / census未join runtime |
| `3807151772` | MyGO 长崎素世 Soyo 鼠标互动 捧脸 | 7 | 20 | 1 | 405 | 无 | 新增 / census未join runtime |
| `3807239614` | 清霄&amp;心 | 3 | 6 | 0 | 82 | 无 | 新增 / census未join runtime |
| `3807436394` | Ronova | 5 | 3 | 3 | 155 | 无 | 新增 / census未join runtime |
| `3807553861` | Albedo - After the bath | 8 | 26 | 0 | 223 | 无 | 新增 / census未join runtime |
| `3807668787` | 霜翼剑使 | 19 | 12 | 8 | 400 | 无 | 新增 / census未join runtime |
| `3807861954` | 鬼方 カヨコ | 10 | 3 | 5 | 188 | 无 | 新增 / census未join runtime |
| `3808922316` | 麻匪 Elisa | 182 | 259 | 2 | 2639 | 截图 | 新增 / census未join runtime |
| `3809034761` | 白丝·斜身侧立[4K] | 16 | 2 | 0 | 132 | 截图 | 新增 / census未join runtime |
| `3809541486` | Moon Princess | 11 | 4 | 7 | 256 | 无 | 新增 / census未join runtime |
| `3809609151` | League of Legends Gwen \| 6 character poses, click to switch \| R18 mouse interaction \| Customizable | 89 | 95 | 13 | 1391 | 截图 | 新增 / census未join runtime |
| `3809618616` | 芒果青青 | 4 | 5 | 0 | 60 | 截图 | 新增 / census未join runtime |
| `3810943704` | Empress of Grace (Commission; Adjustable) MX | 36 | 53 | 11 | 1002 | 截图 | 新增 / census未join runtime |
| `3811154012` | 麻匪 Uncle Panda 残叙 | 58 | 54 | 9 | 910 | 无 | 新增 / census未join runtime |
| `3811216799` | Nikke - Guilty (Mighty Bunny) Desktop Avatar Delight Version | 3 | 0 | 0 | 13 | 截图 | 新增 / census未join runtime |
| `3812249745` | 完美世界-九劫柳神 | 1 | 4 | 0 | 47 | 无 | 新增 / census未join runtime |
| `3812473896` | 原神芙宁娜-水畔芙谣[Furina's Ballad by the Waterside] | 8 | 0 | 2 | 198 | 截图 | 新增 / census未join runtime |
| `3814040466` | Nikke - Privaty - Sharp Lesson | 4 | 0 | 1 | 38 | 截图 | 新增 / census未join runtime |
| `3815761795` | 明日方舟・夕｜画桥（4K） | 60 | 12 | 28 | 1135 | 截图 | 新增 / census未join runtime |
| `3818943255` | 美女肚兜 | 1 | 0 | 0 | 12 | 无 | 新增 / census未join runtime |
| `3820312181` | Void Edge Theme R6S [High Resolution] | 2 | 2 | 0 | 61 | 截图 | 新增 / census未join runtime |
| `3822822401` | 麻匪 穿云 | 56 | 57 | 6 | 1016 | 截图 | 新增 / census未join runtime |
| `833227004` | 星云变换t001 | 1 | 0 | 0 | 13 | 截图 | 新增 / census未join runtime |

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

生成命令：

```bash
python3.12 script/scene_capability_census.py generate \
  --samples-root "$HOME/Movies/MyWallpaperX/创意工坊/Scene" \
  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \
  --markdown docs/scene/capabilities/scene-corpus-capability-inventory.md
python3.12 script/scene_capability_census.py verify \
  --samples-root "$HOME/Movies/MyWallpaperX/创意工坊/Scene" \
  --snapshot .artifacts/scene-evidence/census/scene_capability_census_snapshot.json \
  --markdown docs/scene/capabilities/scene-corpus-capability-inventory.md
python3.12 script/scene_capability_census.py query \
  --family <family-key>
# 需要当前私有 corpus 的详细 resource/owner 事实时显式追加 --live
```
