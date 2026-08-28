# Scene 全样本能力分类与修复事件台账

> 状态：现役 corpus 事实、公共结构影响面与修复事件索引。
>
> 本页由 `script/scene_capability_census.py` 从只读 authored corpus 生成；完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `script/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。系统 current capability 只以 `coverage-ledger.md` 为摘要，逐项合同/专题内等级以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-index.md` 为准。

## 1. 当前结论

- 当前真实 Scene 根发现 **104** 个样本，**104/104** 的 project、PKGV 索引和入口 JSON 可解析。
- tracked full-matrix baseline 当前覆盖 **45** 个历史成员，状态为 `pending-expansion`；本 census 新发现但未 join 运行证据的样本为 `1315486372, 1480826543, 1507593643, 1989767609, 1994794519, 2069136288, 2112262451, 2163522240, 2179185481, 2181251652, 2231088993, 2269193950, 2304304373, 2356604986, 2684431262, 2775915974, 2797913147, 2813231542, 2824109832, 2896873092, 2917306763, 2932631210, 2942486721, 2959875782, 2986218263, 3002649614, 3167210190, 3211615441, 3219398263, 3233141951, 3389974179, 3395392965, 3396722575, 3437487219, 3472940912, 3585875739, 3629927359, 3748311238, 3749463715, 3754630802, 3754639143, 3763323436, 3765904723, 3777761326, 3779026256, 3780119725, 3780391264, 3780940857, 3781307553, 3782740481, 3784012236, 3786185473, 3786641495, 3787355076, 3788066613, 3788467391, 3788645041, 3788698200, 3788897599`，是否曾单独运行不能由静态扫描判断。
- 全量 authored census 共保存 **41453** 个 typed occurrence、**1747** 个公共结构 family、**1244** 个参数 profile 与 **6702** 个 JSON 字段 profile。
- 物理 corpus 共 **6192** 个 PKG entry / **6191** 个唯一路径，包体约 **3.071 GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 45，期间不得称为当前完整快照门。
- package anomaly：样本 `3768724269` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 59/80，同字节；该包 87 entries / 86 unique paths）；重复entry继续保留在物理守恒中，不是漏扫。
- 结构 fallback 记录为 **0**，另有 **2** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。
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
| `resource` | 3323 | 12 | [格式/资源](scene-format-and-render-graph.md) |
| `shader` | 1456 | 251 | [Graph/Shader](render-graph-shader-coverage.md) |
| `layer` | 3309 | 610 | [格式/对象](scene-format-and-render-graph.md) |
| `material` | 4202 | 32 | [Graph/Shader](render-graph-shader-coverage.md) |
| `effect` | 2425 | 12 | [Effect](effect-execution-coverage.md) |
| `render-graph` | 2996 | 24 | [Graph/Shader](render-graph-shader-coverage.md) |
| `render-target` | 361 | 7 | [Graph/Shader](render-graph-shader-coverage.md) |
| `texture` | 8339 | 61 | [格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md) |
| `particle` | 9523 | 531 | [粒子](particle-component-coverage.md) |
| `dynamic-input` | 4202 | 180 | [属性/输入](runtime-input-property-coverage.md) |
| `project-property` | 1317 | 27 | [属性/输入](runtime-input-property-coverage.md) |

### 3.1 纹理本体与使用点

- 包内物理 TEX：**1413**；格式分布：`{"0": 722, "4": 50, "6": 12, "7": 14, "8": 230, "9": 385}`。
- TEX 结构特征：`{"animated": 14, "static": 1399}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。
- 纹理使用 occurrence：**6926**；slot 状态：`{"hole": 1850, "missing": 26, "resolved": 3778, "runtime-provided": 1272}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。

### 3.2 对象、Effect 与动态输入

- 对象类型：`{"camera": 1, "image": 1210, "light": 7, "particle": 327, "shape": 14, "sound": 30, "text": 463, "utility": 47}`；静态非 hidden：`{"image": 719, "light": 7, "particle": 270, "shape": 8, "sound": 30, "text": 285, "utility": 15}`。
- Effect instance **2425**，粒子 root layer **327**；动态 wrapper：`{"condition_wrappers": 720, "script_wrappers": 1073, "timeline_wrappers": 199, "user_bindings": 2294}`。
- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。

#### V2 authored sentinel（防上下文丢失，不是支持清单）

- 当前 104 样本的全部 `script_wrappers` 已按无 payload 的 owner/target/wrapper shape 保存在机器快照；后续不需要靠聊天记录恢复“新增样本里出现过什么”。只有某个真实纵向批需要判断 API/source 语义时，才对精确样本做只读重读并把结果写回对应专项覆盖表。
- 只读真实 `2134765860` 当前可复核出 **11 个 pass scalar VM owner**：6 个为 `WEMath.smoothStep + engine.timeOfDay`（4 个 `multiply` wrapper 显式带 `user:null`，另 2 个写 `alpha`），其余 5 个为普通 scalar `multiply` update。该结构属于 `authored-corpus-observation`；当前 App 的实际执行等级只查 [E-V2-SCENESCRIPT-ENGINE-TIME-OF-DAY](runtime-evidence-index.md#e-v2-scenescript-engine-time-of-day)。
- 这 11 项不能外推同一样本或 corpus 的 Vec/bool/string/object、audio registration、event、timer、layer handle、file module、particle script 或完整 SceneScript 支持；这些仍由 [SceneScript API 覆盖表](scenescript-api-coverage.md)逐 API 登记，不在本 inventory 猜测 current。

## 4. 当前公共 family 影响面索引

> 这里只按静态可见覆盖排序，不能自动决定实施。最后一列是修复事件工作流，不是能力状态；`untriaged` 不表示缺失。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。

| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复事件（非能力状态） |
|---|---|---:|---:|---:|---|
| `material/effect-pass@526202cd27954701` | `material/effect-pass` | 2658 | 97 | 1519 / 96 | `untriaged` |
| `texture/image-material-slot@2e7ce906c5bcf601` | `texture/image-material-slot` | 680 | 96 | 444 / 96 | `untriaged` |
| `effect/authored-graph@9231d5e82bfe3a7f` | `effect/authored-graph` | 2122 | 94 | 1138 / 93 | `untriaged` |
| `render-graph/effect-pass@91c374f0320bbf80` | `render-graph/effect-pass` | 2122 | 94 | 1138 / 93 | `untriaged` |
| `texture/effect-material-slot@aba645ada829ada9` | `texture/effect-material-slot` | 1825 | 93 | 1104 / 93 | `untriaged` |
| `material/image-pass@f0e77c0708dc8bfc` | `material/image-pass` | 594 | 82 | 371 / 82 | `untriaged` |
| `layer/image@5e4c8117d0220cb3` | `layer/image` | 218 | 69 | 146 / 64 | `untriaged` |
| `texture/effect-material-slot@b9dbbf20539e7403` | `texture/effect-material-slot` | 627 | 65 | 380 / 61 | `untriaged` |
| `texture/effect-material-slot@72d5c351e3518afd` | `texture/effect-material-slot` | 742 | 61 | 424 / 61 | `untriaged` |
| `particle/initializer-lifetimerandom@4f49d422ee93b4b2` | `particle/initializer` | 364 | 60 | 291 / 58 | `untriaged` |
| `particle/initializer-sizerandom@af7900ad7fa8e825` | `particle/initializer` | 450 | 59 | 373 / 58 | `untriaged` |
| `texture/effect-material-slot@09cd4f00c72ef79a` | `texture/effect-material-slot` | 466 | 55 | 261 / 55 | `untriaged` |
| `particle/renderer-sprite@13d5b961a929229b` | `particle/renderer` | 319 | 57 | 260 / 54 | `untriaged` |
| `texture/particle-material-slot@c890a3f690d3cae8` | `texture/particle-material-slot` | 361 | 52 | 286 / 51 | `untriaged` |
| `particle/controlpoint-1@dd58b5d5d5dc53b6` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-2@610f46c501bc0ab3` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-3@c68c0bfbed2d003f` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-4@836ca1b0e44c7396` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-5@5147f5e0ff1dc4d8` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-6@19856d86c6ba8777` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-7@1981e7ba62a17e45` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/controlpoint-unknown@ab32a4d63b720bf0` | `particle/controlpoint` | 346 | 52 | 274 / 51 | `untriaged` |
| `particle/initializer-colorrandom@92fe2a1db1c0a335` | `particle/initializer` | 275 | 50 | 239 / 48 | `untriaged` |
| `particle/initializer-velocityrandom@28cd03ab4eb204db` | `particle/initializer` | 228 | 50 | 204 / 48 | `untriaged` |
| `particle/material@0cc12e1c65aba7ca` | `particle/material` | 310 | 48 | 245 / 47 | `untriaged` |
| `particle/operator-alphafade@79efef34b1e1efd1` | `particle/operator` | 170 | 44 | 152 / 43 | `untriaged` |
| `texture/graph-binding@1cb3111748f1f792` | `texture/graph-binding` | 308 | 43 | 220 / 41 | `untriaged` |
| `particle/operator-movement@241f23d1981eba83` | `particle/operator` | 181 | 40 | 161 / 39 | `untriaged` |
| `texture/graph-binding@dc7a25a33e535aae` | `texture/graph-binding` | 452 | 41 | 310 / 38 | `untriaged` |
| `particle/operator-alphafade@42039ec7351e2817` | `particle/operator` | 153 | 39 | 103 / 35 | `untriaged` |
| `texture/image-material-slot@1914e3ff4fa250de` | `texture/image-material-slot` | 261 | 35 | 122 / 34 | `untriaged` |
| `material/effect-pass@cdf796695d9b62b3` | `material/effect-pass` | 125 | 35 | 88 / 34 | `untriaged` |
| `render-graph/effect-pass@87b44c43e3733ab2` | `render-graph/effect-pass` | 113 | 35 | 79 / 34 | `untriaged` |
| `effect/authored-graph@c1df0b7918ba4c2d` | `effect/authored-graph` | 94 | 35 | 68 / 32 | `untriaged` |
| `material/effect-pass@84145b2e51f1d262` | `material/effect-pass` | 94 | 35 | 68 / 32 | `untriaged` |
| `render-graph/effect-pass@27a4e0a2441c4633` | `render-graph/effect-pass` | 94 | 35 | 68 / 32 | `untriaged` |
| `layer/image@740da70a0906f520` | `layer/image` | 230 | 32 | 93 / 31 | `untriaged` |
| `render-graph/effect-pass@95943be768e36742` | `render-graph/effect-pass` | 154 | 32 | 109 / 30 | `untriaged` |
| `render-graph/effect-pass@aa00f242facc660d` | `render-graph/effect-pass` | 101 | 32 | 68 / 30 | `untriaged` |
| `particle/initializer-rotationrandom@50be9f80182bdd6c` | `particle/initializer` | 110 | 29 | 98 / 26 | `untriaged` |
| `material/image-pass@56589507d93ffe7f` | `material/image-pass` | 82 | 26 | 53 / 26 | `untriaged` |
| `render-target/fbo@9901cebdf4c0a822` | `render-target/fbo` | 158 | 28 | 107 / 25 | `untriaged` |
| `layer/image@1963ea2b13ddb536` | `layer/image` | 161 | 25 | 104 / 25 | `untriaged` |
| `material/image-pass@a16e3bc68008f398` | `material/image-pass` | 161 | 25 | 104 / 25 | `untriaged` |
| `particle/emitter-sphererandom@e75b31b9bb9c07b9` | `particle/emitter` | 86 | 26 | 73 / 23 | `untriaged` |
| `material/image-pass@3d8e72eb1cf88e44` | `material/image-pass` | 269 | 22 | 128 / 22 | `untriaged` |
| `render-graph/effect-pass@ec2c0b2d9211f95c` | `render-graph/effect-pass` | 62 | 23 | 45 / 21 | `untriaged` |
| `layer/image@ce6e6edd1955feb5` | `layer/image` | 227 | 22 | 112 / 21 | `untriaged` |
| `particle/initializer-alpharandom@6ee0ff0ba37418ef` | `particle/initializer` | 89 | 21 | 69 / 21 | `untriaged` |
| `particle/initializer-colorrandom@37ca9b83db0e48a4` | `particle/initializer` | 126 | 22 | 85 / 20 | `untriaged` |
| `texture/particle-material-slot@dfeab2f354eab98d` | `texture/particle-material-slot` | 49 | 21 | 45 / 20 | `untriaged` |
| `particle/operator-movement@38205f18a84856b8` | `particle/operator` | 95 | 20 | 73 / 19 | `untriaged` |
| `texture/particle-material-slot@e4ffb6288070b82c` | `texture/particle-material-slot` | 43 | 20 | 42 / 19 | `untriaged` |
| `effect/authored-graph@812aa00e4d7bfe07` | `effect/authored-graph` | 53 | 20 | 41 / 18 | `untriaged` |
| `particle/operator-angularmovement@60d6a8e0f4658b34` | `particle/operator` | 36 | 19 | 33 / 18 | `untriaged` |
| `particle/children-child-definition@9ac07766b41dd3ec` | `particle/children` | 85 | 18 | 80 / 18 | `untriaged` |
| `particle/operator-movement@632199e7235723e5` | `particle/operator` | 54 | 18 | 38 / 18 | `untriaged` |
| `particle/material@39fc82b1fae017f5` | `particle/material` | 39 | 19 | 32 / 17 | `untriaged` |
| `particle/operator-movement@553cd133739c7c5a` | `particle/operator` | 48 | 18 | 45 / 17 | `untriaged` |
| `particle/emitter-sphererandom@d1f27f5059ca5180` | `particle/emitter` | 31 | 17 | 31 / 17 | `untriaged` |
| `particle/initializer-angularvelocityrandom@198daf786a62e408` | `particle/initializer` | 35 | 19 | 30 / 16 | `untriaged` |
| `texture/effect-material-slot@8ec2c2b3a7358158` | `texture/effect-material-slot` | 103 | 17 | 68 / 16 | `untriaged` |
| `effect/authored-graph@dfc634e4773519c6` | `effect/authored-graph` | 48 | 17 | 27 / 16 | `untriaged` |
| `render-graph/effect-pass@3c0d08489093a45a` | `render-graph/effect-pass` | 48 | 17 | 27 / 16 | `untriaged` |
| `particle/operator-oscillateposition@c49553200c2ce38b` | `particle/operator` | 37 | 16 | 36 / 16 | `untriaged` |
| `layer/image@46ce5d8c009d3a5b` | `layer/image` | 47 | 16 | 26 / 16 | `untriaged` |
| `layer/sound@c8fc9e2c506965ac` | `layer/sound` | 16 | 16 | 16 / 16 | `untriaged` |
| `material/effect-pass@a1fbcf4e6cc961a5` | `material/effect-pass` | 81 | 16 | 58 / 15 | `untriaged` |
| `particle/operator-controlpointattract@dbf3bebbae124331` | `particle/operator` | 33 | 16 | 28 / 15 | `untriaged` |
| `layer/particle@7e8a8ba4b06bd409` | `layer/particle` | 56 | 15 | 54 / 15 | `untriaged` |
| `particle/initializer-sizerandom@e0dd54a817ccc18e` | `particle/initializer` | 35 | 17 | 26 / 14 | `untriaged` |
| `particle/operator-alphafade@6e7ca1434b17529b` | `particle/operator` | 52 | 15 | 42 / 14 | `untriaged` |
| `particle/operator-oscillatealpha@2022845e81a0933b` | `particle/operator` | 49 | 15 | 33 / 14 | `untriaged` |
| `particle/controlpoint-2@7c86ea44340e0cde` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/controlpoint-3@3bdff8cdd5c735a6` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/controlpoint-4@b3f2f2b3dee04ff7` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/controlpoint-5@023884c1ea1cda46` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/controlpoint-6@e8fb3f11c6b7a3f8` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/controlpoint-7@e40b75574f9be222` | `particle/controlpoint` | 58 | 16 | 48 / 13 | `untriaged` |
| `particle/emitter-boxrandom@4e417bee7aab34b7` | `particle/emitter` | 39 | 14 | 37 / 13 | `untriaged` |

完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。

## 5. 全部样本清单

| 样本 | 标题 | 对象 | Effect | 粒子层 | occurrence | 人工对照 | matrix/runtime |
|---|---|---:|---:|---:|---:|---|---|
| `1315486372` | 貂蝉拜月 | 3 | 1 | 2 | 72 | 无 | 新增 / census未join runtime |
| `1480826543` | Emilia X-ray NSFW | 2 | 2 | 1 | 62 | 无 | 新增 / census未join runtime |
| `1507593643` | 蕾丝吊带 | 3 | 0 | 2 | 83 | 无 | 新增 / census未join runtime |
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in the Franxx) - animated | 1 | 4 | 0 | 50 | 截图+说明 | tracked45 / census未join runtime |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection) - animated xray | 3 | 21 | 0 | 191 | 截图+说明 | tracked45 / census未join runtime |
| `1937925563` | Tropical Paradise 4K [Customizable Colors &amp; Audio Visualizer] - Vaporwave &amp; Neon | 16 | 51 | 3 | 735 | 截图+说明 | tracked45 / census未join runtime |
| `1989767609` | Black tights（透视） | 1 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `1994794519` | D.VA_OVERWATCH[X-Ray] | 3 | 2 | 2 | 86 | 无 | 新增 / census未join runtime |
| `2067939514` | Windows Visualizer | 45 | 80 | 4 | 805 | 截图+说明 | tracked45 / census未join runtime |
| `2069136288` | [R18] Lexaiduer DOA Nagisa x Tamaki X-Ray Animated | 5 | 27 | 0 | 236 | 无 | 新增 / census未join runtime |
| `2112262451` | [R18] Sakimi Chan Azur Lane Belfast X-Ray Animated | 6 | 35 | 0 | 282 | 无 | 新增 / census未join runtime |
| `2131872317` | Night Market by 俊伦 何 in 4K | 18 | 21 | 9 | 653 | 截图+说明 | tracked45 / census未join runtime |
| `2134765860` | Bunk | 42 | 79 | 1 | 921 | 截图+说明 | tracked45 / census未join runtime |
| `2163522240` | [18+] jk x-ray 🔞😍 | 3 | 2 | 0 | 38 | 无 | 新增 / census未join runtime |
| `2179185481` | Azur Lane / 18+ X-ray NSFW &amp; SFW (3 Versions ) | 3 | 1 | 0 | 39 | 无 | 新增 / census未join runtime |
| `2181251652` | Mio Tokisaki (X-Ray) | 1 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `2231088993` | Ahri X-Ray | 1 | 3 | 0 | 42 | 无 | 新增 / census未join runtime |
| `2241938645` | KDA Akali [4k Version] | 6 | 10 | 2 | 221 | 截图+说明 | tracked45 / census未join runtime |
| `2269193950` | WLOP - Nap | 4 | 4 | 2 | 134 | 无 | 新增 / census未join runtime |
| `2304304373` | Don't Die | 22 | 8 | 10 | 439 | 无 | 新增 / census未join runtime |
| `2356604986` | 1265079-1322607782 | 1 | 0 | 0 | 9 | 无 | 新增 / census未join runtime |
| `2419444134` | Nier Reincarnation - Akeha | 10 | 13 | 4 | 272 | 截图+说明 | tracked45 / census未join runtime |
| `2470144420` | 女孩独享的宁静傍晚 | 4 | 6 | 2 | 124 | 截图+说明 | tracked45 / census未join runtime |
| `2473638329` | Genshin Impact \| +18 / NSFW &amp; SFW | 2 | 7 | 1 | 105 | 截图+说明 | tracked45 / census未join runtime |
| `2684431262` | 麻匪 炫酷音频律动 Windows | 17 | 25 | 1 | 262 | 无 | 新增 / census未join runtime |
| `2775915974` | R18*JK(escalator)エスカレーターJKさんX-ray | 4 | 12 | 0 | 144 | 无 | 新增 / census未join runtime |
| `2797913147` | 【R18】连体黑丝#4K#视差#可互动臀部#动态 | 3 | 7 | 0 | 79 | 无 | 新增 / census未join runtime |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养成好习惯 | 12 | 8 | 2 | 184 | 截图+说明 | tracked45 / census未join runtime |
| `2813231542` | 清新美女 R-18 | 6 | 13 | 1 | 196 | 无 | 新增 / census未join runtime |
| `2824109832` | Yor Forger - NIXEU 4K | 5 | 17 | 2 | 283 | 无 | 新增 / census未join runtime |
| `2884628849` | 麻匪 小姐姐 | 26 | 33 | 0 | 442 | 截图+说明 | tracked45 / census未join runtime |
| `2896873092` | Genshin Impact: Thicc Girls Spread Collage X-Ray R18+ | 11 | 64 | 0 | 536 | 无 | 新增 / census未join runtime |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 140 | 115 | 1 | 1670 | 截图+说明 | tracked45 / census未join runtime |
| `2917306763` | [4K/动态/R18/衣服透视可调]碧蓝航线-独角兽妹妹「天使的护理时间」-B站慕慕慕慕斯小蛋糕 | 8 | 15 | 0 | 163 | 无 | 新增 / census未join runtime |
| `2932631210` | 欧派-音乐乱动 | 6 | 7 | 3 | 181 | 无 | 新增 / census未join runtime |
| `2938612768` | 麻匪 音频识别 Media Player | 85 | 73 | 5 | 1339 | 截图+说明 | tracked45 / census未join runtime |
| `2942486721` | R18 Ishtar And Ereshkigal / 遠坂 凛 Tohsaka Rin 4K [Fate/Grand Order] [NSFW] | 1 | 5 | 0 | 56 | 无 | 新增 / census未join runtime |
| `2959875782` | [R18] Lexaiduer Last Origin Dark Elven Forest Ranger Wedding Dress X-Ray Animated | 136 | 292 | 0 | 2729 | 无 | 新增 / census未join runtime |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 53 | 67 | 4 | 1136 | 截图+说明 | tracked45 / census未join runtime |
| `2986218263` | Tokisaki Asaba &amp; Tokisaki Mio │18+ X-Ray │NSFW &amp; SFW│VERSIONS | 5 | 1 | 1 | 73 | 无 | 新增 / census未join runtime |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 22 | 22 | 15 | 722 | 截图+说明 | tracked45 / census未join runtime |
| `3002649614` | 纯欲少女 | 4 | 0 | 0 | 25 | 无 | 新增 / census未join runtime |
| `3028090166` | WLOP [Tian Nan2] | 12 | 20 | 2 | 347 | 截图+说明 | tracked45 / census未join runtime |
| `3088601835` | Winter Wanderer Xayah - League of Legends [ NAMAKXIN ] | 31 | 36 | 19 | 853 | 截图+说明 | tracked45 / census未join runtime |
| `3122339805` | Pixels | 190 | 17 | 0 | 786 | 截图+说明 | tracked45 / census未join runtime |
| `3141421197` | GraspOfTheAbyss | 1 | 1 | 0 | 12 | 截图+说明 | tracked45 / census未join runtime |
| `3167210190` | [Blue Archive] 奶牛装明日奈 | 1 | 5 | 0 | 61 | 无 | 新增 / census未join runtime |
| `3211615441` | 捆绑悬挂 \| Bind &amp; Suspend [ 可交互/interactive \| iumu \| X-ray \| 4k \| 明日方舟/Arknights ] | 26 | 116 | 0 | 998 | 无 | 新增 / census未join runtime |
| `3219398263` | Acheron Black Hole (StarchaserArt) | 10 | 1 | 6 | 187 | 无 | 新增 / census未join runtime |
| `3233141951` | 熠烛 御剑驭龙-红鸾樱落 高度自定义Red Warbler-Sakura falls （Highly customizable） | 65 | 59 | 9 | 998 | 无 | 新增 / census未join runtime |
| `3290491250` | frieren | 5 | 3 | 1 | 73 | 截图+说明 | tracked45 / census未join runtime |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , Chill , Multi language | 271 | 276 | 42 | 4189 | 截图+说明 | tracked45 / census未join runtime |
| `3389974179` | 落日与白皙的大腿 | 4 | 4 | 0 | 99 | 无 | 新增 / census未join runtime |
| `3395392965` | 请叫我帅锅-小姨定制 | 1 | 1 | 0 | 21 | 无 | 新增 / census未join runtime |
| `3396722575` | 麻匪 NIXEU 黄泉 超多自定义模块 音频识别 Media Player 16:9 16:10 4:3 21:9 32:9 | 61 | 76 | 16 | 1797 | 无 | 新增 / census未join runtime |
| `3437487219` | 3D Earth - Close Orbit [HDR10 Optimized] | 21 | 4 | 2 | 201 | 无 | 新增 / census未join runtime |
| `3472940912` | -Tsukatsuki Rio [ blue archive ] - 4K | 3 | 6 | 0 | 90 | 无 | 新增 / census未join runtime |
| `3585875739` | Miku Monitoring | 3 | 6 | 2 | 133 | 无 | 新增 / census未join runtime |
| `3629927359` | 奶牛大鸭鸭 2 | 25 | 0 | 0 | 203 | 无 | 新增 / census未join runtime |
| `3738202317` | Albedo. | 1 | 4 | 0 | 57 | 截图+说明 | tracked45 / census未join runtime |
| `3742133044` | 凌霄·双司镇命·无常&lt;1&gt;-[深空之眼] | 4 | 5 | 2 | 122 | 截图+说明 | tracked45 / census未join runtime |
| `3743305891` | 战双 | 8 | 4 | 1 | 143 | 截图+说明 | tracked45 / census未join runtime |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Evil 4 Remake \| Re4 | 21 | 13 | 1 | 575 | 截图+说明 | tracked45 / census未join runtime |
| `3748311238` | 大 | 6 | 17 | 0 | 260 | 无 | 新增 / census未join runtime |
| `3749463715` | 还能在大 ∑ 2 | 28 | 37 | 8 | 1013 | 无 | 新增 / census未join runtime |
| `3750342273` | Night snowy mountains | 8 | 6 | 1 | 114 | 截图+说明 | tracked45 / census未join runtime |
| `3750813609` | Asian Temple in the Mountains | 13 | 5 | 9 | 390 | 截图+说明 | tracked45 / census未join runtime |
| `3754630802` | WLOP [ChineseNewYear 7] | 38 | 31 | 10 | 1043 | 无 | 新增 / census未join runtime |
| `3754639143` | WLOP 银月 | 22 | 20 | 2 | 457 | 无 | 新增 / census未join runtime |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 9 | 9 | 7 | 423 | 截图+说明 | tracked45 / census未join runtime |
| `3763323436` | 补 碧蓝航线 拉菲 Azur lane Laffey | 4 | 6 | 1 | 97 | 无 | 新增 / census未join runtime |
| `3765760121` | 【4K】三色堇与她 | 13 | 12 | 1 | 207 | 截图+说明 | tracked45 / census未join runtime |
| `3765904723` | 调月莉音 | 5 | 9 | 0 | 124 | 无 | 新增 / census未join runtime |
| `3766387484` | ARKNIGHTS ENDFIELD ARCANE CHEN XIANGYU | 7 | 13 | 1 | 229 | 截图+说明 | tracked45 / census未join runtime |
| `3766403294` | 仪玄(AI) | 2 | 1 | 0 | 29 | 截图+说明 | tracked45 / census未join runtime |
| `3766415113` | The last pour | 1 | 0 | 0 | 9 | 截图+说明 | tracked45 / census未join runtime |
| `3767232084` | 谬因 | 3 | 7 | 2 | 157 | 截图+说明 | tracked45 / census未join runtime |
| `3767343314` | Universe Abstract - By: CroSsHaiR-&gt; | 4 | 3 | 3 | 117 | 截图+说明 | tracked45 / census未join runtime |
| `3767460992` | Magic mushroom | 9 | 39 | 0 | 261 | 截图+说明 | tracked45 / census未join runtime |
| `3768020435` | Silver Wolf with media integration | 9 | 3 | 0 | 70 | 截图+说明 | tracked45 / census未join runtime |
| `3768229922` | 麻匪 赤芒 音频互动 | 58 | 74 | 2 | 815 | 截图+说明 | tracked45 / census未join runtime |
| `3768724269` | ARKNIGHTS ENDFIELD 4K GILBERTA IN CLOUDS | 17 | 12 | 4 | 311 | 截图+说明 | tracked45 / census未join runtime |
| `3768903841` | Naha Gaze at Firework \| northway. | 37 | 18 | 5 | 413 | 截图+说明 | tracked45 / census未join runtime |
| `3769364482` | 戴拿奥特曼 强壮型【Ultraman Dyna Strong Type】dy柊明 | 10 | 13 | 3 | 378 | 截图+说明 | tracked45 / census未join runtime |
| `3769688830` | Spirit Blossom Springs Ahri (Adjustable; League of Legends) MX | 26 | 59 | 6 | 771 | 截图+说明 | tracked45 / census未join runtime |
| `3769761761` | Yoru and Mitaka asa | 20 | 24 | 5 | 512 | 截图+说明 | tracked45 / census未join runtime |
| `3770444459` | 三国杀【节气 夏至 2026】8K | 6 | 4 | 5 | 245 | 截图+说明 | tracked45 / census未join runtime |
| `3770462923` | gt3rs@d4rk | 4 | 5 | 0 | 100 | 截图+说明 | tracked45 / census未join runtime |
| `3777761326` | I do Anything | 7 | 22 | 1 | 254 | 无 | 新增 / census未join runtime |
| `3779026256` | [魔法少女的魔女审判] 月代雪 X 樱羽艾玛 音频识别 | 30 | 22 | 2 | 481 | 无 | 新增 / census未join runtime |
| `3780119725` | in the rain V 31 | 89 | 37 | 48 | 1982 | 无 | 新增 / census未join runtime |
| `3780391264` | Agnes Tachyon Umamusume Neon | 19 | 7 | 10 | 512 | 无 | 新增 / census未join runtime |
| `3780940857` | 枕澜 蒂法 电脑动态壁纸 最终幻想7 TIFA Final Fantasy VII | 2 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `3781307553` | Look this | 2 | 5 | 0 | 63 | 无 | 新增 / census未join runtime |
| `3782740481` | WLOP Violet 紫 | 23 | 21 | 1 | 472 | 无 | 新增 / census未join runtime |
| `3784012236` | &gt;R-18&lt; 蔚蓝档案 Blue_Archive\|06\|飛鳥馬 トキ 时 Toki_Asuma X-ray | 2 | 1 | 0 | 35 | 无 | 新增 / census未join runtime |
| `3786185473` | ELF PARADISE～欢迎来到性夜♪色情精灵们的淫乱圣诞节特别篇～ \| (x-ray) | 4 | 4 | 0 | 79 | 无 | 新增 / census未join runtime |
| `3786641495` | Albedo - Look at here my master | 2 | 12 | 0 | 99 | 无 | 新增 / census未join runtime |
| `3787355076` | 维琳娜-申请入股 | 1 | 1 | 0 | 21 | 无 | 新增 / census未join runtime |
| `3788066613` | [Hajily-1825][R-18]2025-07-04 Fleurdelys 3D P1 | 17 | 1 | 2 | 200 | 无 | 新增 / census未join runtime |
| `3788467391` | Miku and Monster | 5 | 18 | 1 | 179 | 无 | 新增 / census未join runtime |
| `3788645041` | 奥黛塔(破洞版) | 3 | 8 | 0 | 97 | 无 | 新增 / census未join runtime |
| `3788698200` | NFFA画风 维琳娜2（可去防封马赛克+可去时钟） | 3 | 1 | 1 | 69 | 无 | 新增 / census未join runtime |
| `3788897599` | ArT丨R18丨4K丨Red Q | 18 | 25 | 3 | 532 | 无 | 新增 / census未join runtime |

## 6. 修复事件记录与防回归合同

每个已登记公共 family 的修复事件使用三个独立 workflow/evidence 字段；三者都不是 capability current/support/todo 等级：

- `repair_state`: `untriaged -> diagnosed -> in-progress -> implemented -> bounded-verified`；
- `runtime_proof_state`: `none -> partial-chain -> visible-chain-closed -> official-golden-equivalent`；
- `regression_protection_state`: `none -> synthetic -> targeted-runtime -> milestone`。

这里的 `implemented` 只表示该 repair event 描述的改动已落地，可能是解析保真、失败关闭或故障隔离，不表示整个 family 已实现。事件记为 `bounded-verified` 至少要求项目自有 synthetic 正例、反例、真实隔离样本 GPU→publication→compositor→next-frame→ROI 和明确剩余边界；`official-golden-equivalent` 还必须有同相位官方 golden 及像素/时序容差。只降低 rejection 数、只 non-black 或只加载资源不能写成修复完成。

当前已逐族复核并登记的修复事件见机器 repair ledger 与下表；未列 family 显示 `untriaged` 只表示没有修复事件记录，不是 missing/unsupported/todo，也不会因 effect 名、路径或相邻 family 已修而自动产生 current 结论。

| family | 修复事件 / 事件运行证据 / 事件回归保护（非能力状态） | 公共修法 | 真实 sentinel | 剩余边界 |
|---|---|---|---|---|
| `dynamic-input/scenescript@62583305de1f9a21` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the script family. | `3768229922` | Layer 202 is the authored head hit target and cursorClick producer; ordered pointer edges, solid-only hit testing, capture, shared.clack mutation, alpha blinking and user-property application are not implemented.；The suppression protects static composition but does not make the head clickable or show and hide the authored overlay. |
| `dynamic-input/scenescript@82ef17cb868c4f2e` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the script family. | `3768229922` | Layer 397 is a hidden controller that must keep ticking and map shared.clack to sixteen visual layers; its module, shared state, update callback and mutations are not executed.；The suppression protects static composition but provides no click interaction, dynamic overlay visibility or Wallpaper Engine equivalence. |
| `dynamic-input/scenescript@c434d003fa58a779` | `implemented / partial-chain / targeted-runtime` (`9977d585`) | Preserve visible/alpha SceneScript ownership before value resolution and suppress the owned layer and descendants with an exact diagnostic until an executable script runtime can provide display authority. This is failure isolation only, not execution of the opening lifecycle script. | `3768229922` | Layer 354's authored fade, visible mutation and delayed destroy lifecycle are not executed; the correct official opening timing remains unknown in this runtime.；The exposed opening-phase composition is not proof of final-phase or Wallpaper Engine pixel and timing equivalence. |
| `shader/frag@14c83a36961c3903` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3fa1499c`) | Preserve the authored hidden flag and map only the exact historical token on regular hidden g_Texture0 slot 0 to the current effect graph input, reusing the existing typed graph identity, publication, Program, GraphExecutor and compositor path. | `1553008362` | The related 1636394814 mixed chain was rerun and no longer logged this texture-binding alias failure, but it remains NON-PASS at later dependency-owner and material-template-unsupported gates.；Other ui_editor_properties_* keys, non-slot-0 samplers, non-regular modes, label-only metadata and non-hidden declarations remain rejected.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@1d391ff0fa121323` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3fa1499c`) | Preserve the authored hidden flag and map only the exact historical token on regular hidden g_Texture0 slot 0 to the current effect graph input, reusing the existing typed graph identity, publication, Program, GraphExecutor and compositor path. | `1553008362` | The related 1636394814 mixed chain was rerun and no longer logged this texture-binding alias failure, but it remains NON-PASS at later dependency-owner and material-template-unsupported gates.；Other ui_editor_properties_* keys, non-slot-0 samplers, non-regular modes, label-only metadata and non-hidden declarations remain rejected.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@436c998ccdbec6c2` | `bounded-verified / visible-chain-closed / targeted-runtime` (`e84c39b3`) | Prove a strict same-slot whole-vector affine filter closure, unpremultiply every selected layer-source color sample, clamp the authored straight RGBA result to the UNorm boundary, premultiply once, and require the exact layerSource-to-effectOutput graph role. Auxiliary slots remain data or scalar only, and scalar texture samples use the shared explicit .x conversion rule. | `3290491250` | Multiple color slots, component-wise color mutation, dynamic division, helper side effects, internal graph targets and ordinary effectOutput input remain rejected.；The related 3767343314 occurrence remains NON-PASS at later Water Ripple texture-purpose and Cursor Ripple history or render-state gates; no partial graph publication is claimed.；The targeted run proves the visible MyWallpaperX chain, not Wallpaper Engine pixel or timing equivalence. |
| `shader/frag@60ed3f1823e61bb5` | `bounded-verified / visible-chain-closed / targeted-runtime` (`3df4a94d`) | Recognize only the bounded single-source and uniform-RGB mix with preserved sampled alpha, require every launch-envelope variant to consume one exact captured layerSource Program with no competing authored or default texture source, and resolve composition and project capture with wallpaper-aligned projected geometry while keeping fullscreen capture screen-fixed. Unknown color flows, ambiguous sources and mixed launch envelopes remain fail closed. | `3768229922` | The shader proof covers only one sampled source RGB mixed with one fragment-uniform RGB by a finite bounded scalar while preserving that sample's alpha; second color sources, alpha rewrites, varying tint, custom or shadowed builtins, unbounded weights and ambiguous source identities remain rejected.；The captured-main proof requires one exact layerSource identity across the complete launch envelope; competing graph candidates, authored defaults, non-regular samplers, wrong source modes, mixed variants and independent alpha signals remain rejected.；This repair does not implement the head-click SceneScript toggle, other dynamic overlay effects, unrelated particle families, or Wallpaper Engine pixel and timing equivalence. |
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
  --snapshot script/scene_capability_census_snapshot.json \
  --markdown docs/scene/semantics/scene-corpus-capability-inventory.md
python3.12 script/scene_capability_census.py verify \
  --samples-root "$HOME/Movies/MyWallpaperX/创意工坊/Scene" \
  --snapshot script/scene_capability_census_snapshot.json \
  --markdown docs/scene/semantics/scene-corpus-capability-inventory.md
python3.12 script/scene_capability_census.py query \
  --family <family-key>
# 需要当前私有 corpus 的详细 resource/owner 事实时显式追加 --live
```
