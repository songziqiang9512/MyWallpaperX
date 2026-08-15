# Scene 全样本能力分类与修复台账

> 状态：现役 corpus 事实与公共修复候选索引。
>
> 本页由 `script/scene_capability_census.py` 从只读 authored corpus 生成；完整 family、样本归属、参数/字段 profile、compact layer/pass/slot occurrence index 与守恒摘要在 `script/scene_capability_census_snapshot.json`。资源 identity 和详细 owner 事实仅在显式 `query --live` 时从私有 corpus 重建。能力等级仍以专项表为准，App/GPU/ROI 证据仍以 `runtime-evidence-index.md` 为准。

## 1. 当前结论

- 当前真实 Scene 根发现 **49** 个样本，**49/49** 的 project、PKGV 索引和入口 JSON 可解析。
- tracked full-matrix baseline 当前覆盖 **45** 个历史成员，状态为 `pending-expansion`；本 census 新发现但未 join 运行证据的样本为 `3780119725, 3780391264, 3780940857, 3781307553`，是否曾单独运行不能由静态扫描判断。
- 全量 authored census 共保存 **24858** 个 typed occurrence、**1255** 个公共结构 family、**934** 个参数 profile 与 **5030** 个 JSON 字段 profile。
- 物理 corpus 共 **3153** 个 PKG entry / **3152** 个唯一路径，包体约 **1.583 GB**；tracked baseline 在单独的 milestone 扩容并建立运行期待前仍为 45，期间不得称为当前完整快照门。
- package anomaly：样本 `3768724269` 的 `fonts/workshop/3651835769/nasalization.otf` entry重复（indices 59/80，同字节；该包 87 entries / 86 unique paths）；重复entry继续保留在物理守恒中，不是漏扫。
- 结构 fallback 记录为 **0**，另有 **1** 个 generic/unknown/unresolved family；两者都不是运行失败数。本 census 未 join 运行证据的样本，其第一 blocker 保持 `unknown`，不得从静态形态猜测。
- 开发按“真实可见链第一断裂边覆盖的共享 family”排序；大类用于汇总，不允许把所有纹理、Effect 或粒子一次性做成巨型补丁。

## 2. 口径与权威边界

1. 本 census 回答样本声明了什么：对象、Effect/Material/Shader/Graph/FBO、纹理、粒子、动态来源和参数形态。
2. `observed`、`resolved` 或文件存在不等于 renderer 已支持；运行 owner、GPU、publication、compositor、next-frame 和 ROI 必须引用运行证据索引。
3. `family_key` 只由公共语义形态生成；sample/layer/path/hash 只作 evidence identity，产品实现不得按具体值 dispatch。
4. 所有参数以名称、类型、arity、范围、wrapper source 和结构签名记录；只保留 project title 元数据，不复制 layer 文字、shader、SceneScript、纹理、JSON 片段或二进制 payload。
5. 修好一族后在 `scene_capability_repair_ledger.json` 记录根因、公共修法、commit、正反门、真实样本、ROI、剩余边界；重新扫描不会覆盖历史。
6. 每个 family 开批前先以官方资料界定作者合同，再实际读取 MirageWallpaper 固定 revision 的相关 producer/state/consumer/frame/failure 源码并记录 divergence；第三方总结不能代替本批源码审查，GPL 实现不能进入项目。

## 3. 大类总览

| 大类 | occurrence | family | 现役能力事实入口 |
|---|---:|---:|---|
| `resource` | 1735 | 11 | [格式/资源](scene-format-and-render-graph.md) |
| `shader` | 754 | 192 | [Graph/Shader](render-graph-shader-coverage.md) |
| `layer` | 2093 | 400 | [格式/对象](scene-format-and-render-graph.md) |
| `material` | 2393 | 25 | [Graph/Shader](render-graph-shader-coverage.md) |
| `effect` | 1346 | 9 | [Effect](effect-execution-coverage.md) |
| `render-graph` | 1697 | 16 | [Graph/Shader](render-graph-shader-coverage.md) |
| `render-target` | 218 | 6 | [Graph/Shader](render-graph-shader-coverage.md) |
| `texture` | 4178 | 54 | [格式/资源](scene-format-and-render-graph.md) / [Graph/Shader](render-graph-shader-coverage.md) / [Provider](runtime-input-property-coverage.md) |
| `particle` | 6546 | 382 | [粒子](particle-component-coverage.md) |
| `dynamic-input` | 3062 | 135 | [属性/输入](runtime-input-property-coverage.md) |
| `project-property` | 836 | 25 | [属性/输入](runtime-input-property-coverage.md) |

### 3.1 纹理本体与使用点

- 包内物理 TEX：**664**；格式分布：`{"0": 374, "4": 14, "6": 12, "7": 2, "8": 78, "9": 184}`。
- TEX 结构特征：`{"animated": 12, "static": 652}`。这些只证明文件结构可读，不证明上传、purpose、sampler 或合成正确。
- 纹理使用 occurrence：**3514**；slot 状态：`{"hole": 849, "missing": 12, "resolved": 1839, "runtime-provided": 814}`。`runtime-provided` 是 graph/named target 等运行身份，`missing` 需要结合 default/optional combo/VFS 语义判断，不能一律当缺图。

### 3.2 对象、Effect 与动态输入

- 对象类型：`{"camera": 1, "image": 696, "light": 4, "particle": 233, "shape": 10, "sound": 23, "text": 396, "utility": 34}`；静态非 hidden：`{"image": 408, "light": 4, "particle": 185, "shape": 5, "sound": 23, "text": 253, "utility": 4}`。
- Effect instance **1346**，粒子 root layer **233**；动态 wrapper：`{"condition_wrappers": 529, "script_wrappers": 766, "timeline_wrappers": 100, "user_bindings": 1745}`。
- 粒子组件分布完整保存在机器快照 `summary.particle.component_counts`；Effect/Graph/FBO、包内 shader uniform/annotation/combo、material authored combo/constant 与全部 JSON 字段可按 family/profile 查询。active/prepared shader variant 仍以专项 census 与运行证据为准。

## 4. 当前公共 family 影响面索引

> 这里只按静态可见覆盖排序，不能自动决定实施。真正开批前必须由 fresh 隔离运行确认第一断裂边；高频但位于链后段的 family 不得抢占当前可见首断点。

| family | domain/kind | occurrence | 样本 | 可见 occurrence / 样本 | 修复状态 |
|---|---|---:|---:|---:|---|
| `material/effect-pass@526202cd27954701` | `material/effect-pass` | 1469 | 48 | 864 / 48 | `untriaged` |
| `effect/authored-graph@9231d5e82bfe3a7f` | `effect/authored-graph` | 1134 | 47 | 622 / 47 | `untriaged` |
| `render-graph/effect-pass@91c374f0320bbf80` | `render-graph/effect-pass` | 1134 | 47 | 622 / 47 | `untriaged` |
| `texture/image-material-slot@2e7ce906c5bcf601` | `texture/image-material-slot` | 289 | 45 | 219 / 45 | `untriaged` |
| `texture/effect-material-slot@aba645ada829ada9` | `texture/effect-material-slot` | 833 | 44 | 606 / 44 | `untriaged` |
| `material/image-pass@f0e77c0708dc8bfc` | `material/image-pass` | 335 | 41 | 178 / 41 | `untriaged` |
| `particle/initializer-lifetimerandom@4f49d422ee93b4b2` | `particle/initializer` | 261 | 36 | 196 / 35 | `untriaged` |
| `particle/initializer-sizerandom@af7900ad7fa8e825` | `particle/initializer` | 320 | 35 | 253 / 35 | `untriaged` |
| `particle/renderer-sprite@13d5b961a929229b` | `particle/renderer` | 231 | 35 | 176 / 34 | `untriaged` |
| `particle/controlpoint-1@dd58b5d5d5dc53b6` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-2@610f46c501bc0ab3` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-3@c68c0bfbed2d003f` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-4@836ca1b0e44c7396` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-5@5147f5e0ff1dc4d8` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-6@19856d86c6ba8777` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-7@1981e7ba62a17e45` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `particle/controlpoint-unknown@ab32a4d63b720bf0` | `particle/controlpoint` | 245 | 32 | 179 / 32 | `untriaged` |
| `texture/effect-material-slot@b9dbbf20539e7403` | `texture/effect-material-slot` | 328 | 32 | 262 / 31 | `untriaged` |
| `texture/effect-material-slot@72d5c351e3518afd` | `texture/effect-material-slot` | 333 | 31 | 211 / 31 | `untriaged` |
| `texture/particle-material-slot@c890a3f690d3cae8` | `texture/particle-material-slot` | 271 | 31 | 199 / 31 | `untriaged` |
| `layer/image@5e4c8117d0220cb3` | `layer/image` | 78 | 34 | 57 / 30 | `untriaged` |
| `particle/initializer-velocityrandom@28cd03ab4eb204db` | `particle/initializer` | 157 | 31 | 135 / 30 | `untriaged` |
| `particle/initializer-colorrandom@92fe2a1db1c0a335` | `particle/initializer` | 188 | 30 | 159 / 29 | `untriaged` |
| `particle/material@0cc12e1c65aba7ca` | `particle/material` | 218 | 29 | 154 / 29 | `untriaged` |
| `particle/operator-alphafade@79efef34b1e1efd1` | `particle/operator` | 118 | 28 | 101 / 28 | `untriaged` |
| `texture/effect-material-slot@09cd4f00c72ef79a` | `texture/effect-material-slot` | 120 | 25 | 105 / 25 | `untriaged` |
| `texture/graph-binding@1cb3111748f1f792` | `texture/graph-binding` | 192 | 25 | 131 / 24 | `untriaged` |
| `particle/operator-movement@241f23d1981eba83` | `particle/operator` | 138 | 24 | 119 / 24 | `untriaged` |
| `texture/graph-binding@dc7a25a33e535aae` | `texture/graph-binding` | 295 | 24 | 202 / 23 | `untriaged` |
| `particle/operator-alphafade@42039ec7351e2817` | `particle/operator` | 117 | 25 | 76 / 22 | `untriaged` |
| `effect/authored-graph@c1df0b7918ba4c2d` | `effect/authored-graph` | 68 | 22 | 47 / 21 | `untriaged` |
| `material/effect-pass@84145b2e51f1d262` | `material/effect-pass` | 68 | 22 | 47 / 21 | `untriaged` |
| `render-graph/effect-pass@27a4e0a2441c4633` | `render-graph/effect-pass` | 68 | 22 | 47 / 21 | `untriaged` |
| `layer/image@1963ea2b13ddb536` | `layer/image` | 132 | 17 | 79 / 17 | `untriaged` |
| `material/image-pass@a16e3bc68008f398` | `material/image-pass` | 132 | 17 | 79 / 17 | `untriaged` |
| `material/effect-pass@cdf796695d9b62b3` | `material/effect-pass` | 76 | 17 | 55 / 17 | `untriaged` |
| `render-graph/effect-pass@87b44c43e3733ab2` | `render-graph/effect-pass` | 67 | 17 | 46 / 17 | `untriaged` |
| `particle/initializer-rotationrandom@50be9f80182bdd6c` | `particle/initializer` | 81 | 18 | 72 / 16 | `untriaged` |
| `particle/emitter-sphererandom@e75b31b9bb9c07b9` | `particle/emitter` | 63 | 18 | 51 / 16 | `untriaged` |
| `texture/image-material-slot@1914e3ff4fa250de` | `texture/image-material-slot` | 211 | 16 | 78 / 16 | `untriaged` |
| `render-graph/effect-pass@95943be768e36742` | `render-graph/effect-pass` | 93 | 16 | 71 / 16 | `untriaged` |
| `render-graph/effect-pass@aa00f242facc660d` | `render-graph/effect-pass` | 64 | 16 | 43 / 16 | `untriaged` |
| `layer/image@740da70a0906f520` | `layer/image` | 185 | 15 | 54 / 15 | `untriaged` |
| `particle/operator-movement@632199e7235723e5` | `particle/operator` | 45 | 15 | 30 / 15 | `untriaged` |
| `particle/initializer-alpharandom@6ee0ff0ba37418ef` | `particle/initializer` | 77 | 14 | 57 / 14 | `untriaged` |
| `material/image-pass@56589507d93ffe7f` | `material/image-pass` | 53 | 14 | 31 / 14 | `untriaged` |
| `particle/operator-angularmovement@60d6a8e0f4658b34` | `particle/operator` | 29 | 14 | 27 / 14 | `untriaged` |
| `particle/operator-movement@38205f18a84856b8` | `particle/operator` | 61 | 13 | 41 / 12 | `untriaged` |
| `particle/material@39fc82b1fae017f5` | `particle/material` | 25 | 13 | 22 / 12 | `untriaged` |
| `particle/children-child-definition@9ac07766b41dd3ec` | `particle/children` | 56 | 12 | 52 / 12 | `untriaged` |
| `render-graph/effect-pass@ec2c0b2d9211f95c` | `render-graph/effect-pass` | 37 | 12 | 31 / 12 | `untriaged` |
| `texture/particle-material-slot@e4ffb6288070b82c` | `texture/particle-material-slot` | 28 | 12 | 28 / 12 | `untriaged` |
| `particle/emitter-sphererandom@d1f27f5059ca5180` | `particle/emitter` | 24 | 12 | 24 / 12 | `untriaged` |
| `texture/particle-material-slot@dfeab2f354eab98d` | `texture/particle-material-slot` | 23 | 12 | 23 / 12 | `untriaged` |
| `particle/initializer-colorrandom@37ca9b83db0e48a4` | `particle/initializer` | 103 | 13 | 63 / 11 | `untriaged` |
| `render-target/fbo@9901cebdf4c0a822` | `render-target/fbo` | 68 | 13 | 40 / 11 | `untriaged` |
| `particle/initializer-angularvelocityrandom@198daf786a62e408` | `particle/initializer` | 26 | 13 | 22 / 11 | `untriaged` |
| `material/effect-pass@a1fbcf4e6cc961a5` | `material/effect-pass` | 68 | 12 | 46 / 11 | `untriaged` |
| `layer/sound@c8fc9e2c506965ac` | `layer/sound` | 11 | 11 | 11 / 11 | `untriaged` |
| `particle/operator-movement@553cd133739c7c5a` | `particle/operator` | 31 | 11 | 28 / 10 | `untriaged` |
| `particle/emitter-boxrandom@4e417bee7aab34b7` | `particle/emitter` | 34 | 10 | 33 / 10 | `untriaged` |
| `particle/operator-oscillatealpha@2022845e81a0933b` | `particle/operator` | 39 | 10 | 24 / 10 | `untriaged` |
| `particle/operator-oscillateposition@c49553200c2ce38b` | `particle/operator` | 22 | 10 | 21 / 10 | `untriaged` |
| `effect/authored-graph@49c310bdbcb3af55` | `effect/authored-graph` | 49 | 10 | 36 / 9 | `untriaged` |
| `render-graph/effect-pass@419b55fe86b12fd0` | `render-graph/effect-pass` | 49 | 10 | 36 / 9 | `untriaged` |
| `render-graph/effect-pass@c76a5976d14e6a9b` | `render-graph/effect-pass` | 50 | 10 | 36 / 9 | `untriaged` |
| `render-target/fbo@b7f0838a5064473e` | `render-target/fbo` | 49 | 10 | 36 / 9 | `untriaged` |
| `material/image-pass@3d8e72eb1cf88e44` | `material/image-pass` | 87 | 9 | 70 / 9 | `untriaged` |
| `layer/image@ce6e6edd1955feb5` | `layer/image` | 76 | 9 | 61 / 9 | `untriaged` |
| `effect/authored-graph@812aa00e4d7bfe07` | `effect/authored-graph` | 29 | 9 | 28 / 9 | `untriaged` |
| `particle/initializer-rotationrandom@5933ed3a457c6381` | `particle/initializer` | 26 | 9 | 26 / 9 | `untriaged` |
| `layer/image@46ce5d8c009d3a5b` | `layer/image` | 33 | 9 | 19 / 9 | `untriaged` |
| `particle/emitter-sphererandom@5a95afd97c419886` | `particle/emitter` | 19 | 9 | 18 / 9 | `untriaged` |
| `particle/definition@287577c33dc5c10d` | `particle/definition` | 12 | 9 | 12 / 9 | `untriaged` |
| `texture/effect-material-slot@8ec2c2b3a7358158` | `texture/effect-material-slot` | 71 | 9 | 52 / 8 | `untriaged` |
| `particle/operator-controlpointattract@dbf3bebbae124331` | `particle/operator` | 14 | 9 | 12 / 8 | `untriaged` |
| `layer/particle@7e8a8ba4b06bd409` | `layer/particle` | 35 | 8 | 35 / 8 | `untriaged` |
| `layer/image@afc7972d972dbecb` | `layer/image` | 20 | 8 | 18 / 8 | `untriaged` |
| `particle/children-child-definition@e731d75e8854d375` | `particle/children` | 33 | 8 | 18 / 8 | `untriaged` |
| `effect/authored-graph@dfc634e4773519c6` | `effect/authored-graph` | 35 | 8 | 15 / 8 | `untriaged` |

完整 family、payload-free feature summary、样本归属与 revision 数在机器快照中；此表故意只保留前 80 个高覆盖项，避免人类文档成为不可维护的 payload 转储。

## 5. 全部样本清单

| 样本 | 标题 | 对象 | Effect | 粒子层 | occurrence | 人工对照 | matrix/runtime |
|---|---|---:|---:|---:|---:|---|---|
| `1553008362` | [Jidan Hua] Ichigo and 002 (Darling in the Franxx) - animated | 1 | 4 | 0 | 50 | 截图+说明 | tracked45 / census未join runtime |
| `1636394814` | [Jaku Denpa] Shigure (Kantai Collection) - animated xray | 3 | 21 | 0 | 191 | 截图+说明 | tracked45 / census未join runtime |
| `1937925563` | Tropical Paradise 4K [Customizable Colors &amp; Audio Visualizer] - Vaporwave &amp; Neon | 16 | 51 | 3 | 735 | 截图+说明 | tracked45 / census未join runtime |
| `2067939514` | Windows Visualizer | 45 | 80 | 4 | 805 | 截图+说明 | tracked45 / census未join runtime |
| `2131872317` | Night Market by 俊伦 何 in 4K | 18 | 21 | 9 | 653 | 截图+说明 | tracked45 / census未join runtime |
| `2134765860` | Bunk | 42 | 79 | 1 | 921 | 截图+说明 | tracked45 / census未join runtime |
| `2241938645` | KDA Akali [4k Version] | 6 | 10 | 2 | 221 | 截图+说明 | tracked45 / census未join runtime |
| `2419444134` | Nier Reincarnation - Akeha | 10 | 13 | 4 | 272 | 截图+说明 | tracked45 / census未join runtime |
| `2470144420` | 女孩独享的宁静傍晚 | 4 | 6 | 2 | 124 | 截图+说明 | tracked45 / census未join runtime |
| `2473638329` | Genshin Impact \| +18 / NSFW &amp; SFW | 2 | 7 | 1 | 105 | 截图+说明 | tracked45 / census未join runtime |
| `2802243144` | 冰公主-by Wlop 时间日期已修复 16:9 -music 订阅后点赞，养成好习惯 | 12 | 8 | 2 | 184 | 截图+说明 | tracked45 / census未join runtime |
| `2884628849` | 麻匪 小姐姐 | 26 | 33 | 0 | 442 | 截图+说明 | tracked45 / census未join runtime |
| `2902406982` | 麻匪 月半与鬼哭 所有元素自定义 | 140 | 115 | 1 | 1670 | 截图+说明 | tracked45 / census未join runtime |
| `2938612768` | 麻匪 音频识别 Media Player | 85 | 73 | 5 | 1339 | 截图+说明 | tracked45 / census未join runtime |
| `2974757317` | 麻匪 音频识别 悬浮窗 Media Player | 53 | 67 | 4 | 1136 | 截图+说明 | tracked45 / census未join runtime |
| `2998757800` | 碧蓝航线-利托里奥【R18版/可触摸/天气变化】-B站慕慕慕慕斯小蛋糕 | 22 | 22 | 15 | 722 | 截图+说明 | tracked45 / census未join runtime |
| `3028090166` | WLOP [Tian Nan2] | 12 | 20 | 2 | 347 | 截图+说明 | tracked45 / census未join runtime |
| `3088601835` | Winter Wanderer Xayah - League of Legends [ NAMAKXIN ] | 31 | 36 | 19 | 853 | 截图+说明 | tracked45 / census未join runtime |
| `3122339805` | Pixels | 190 | 17 | 0 | 786 | 截图+说明 | tracked45 / census未join runtime |
| `3141421197` | GraspOfTheAbyss | 1 | 1 | 0 | 12 | 截图+说明 | tracked45 / census未join runtime |
| `3290491250` | frieren | 5 | 3 | 1 | 73 | 截图+说明 | tracked45 / census未join runtime |
| `3299228616` | Lonely Cat: Audio visualizer , Clock , Chill , Multi language | 271 | 276 | 42 | 4189 | 截图+说明 | tracked45 / census未join runtime |
| `3738202317` | Albedo. | 1 | 4 | 0 | 57 | 截图+说明 | tracked45 / census未join runtime |
| `3742133044` | 凌霄·双司镇命·无常&lt;1&gt;-[深空之眼] | 4 | 5 | 2 | 122 | 截图+说明 | tracked45 / census未join runtime |
| `3743305891` | 战双 | 8 | 4 | 1 | 143 | 截图+说明 | tracked45 / census未join runtime |
| `3747492842` | [4k]Leon S Kennedy X-ray \| Resident Evil 4 Remake \| Re4 | 21 | 13 | 1 | 575 | 截图+说明 | tracked45 / census未join runtime |
| `3750342273` | Night snowy mountains | 8 | 6 | 1 | 114 | 截图+说明 | tracked45 / census未join runtime |
| `3750813609` | Asian Temple in the Mountains | 13 | 5 | 9 | 390 | 截图+说明 | tracked45 / census未join runtime |
| `3757555836` | 名将杀【兰汤春酽_赵姬】限制级8K | 9 | 9 | 7 | 423 | 截图+说明 | tracked45 / census未join runtime |
| `3765760121` | 【4K】三色堇与她 | 13 | 12 | 1 | 207 | 截图+说明 | tracked45 / census未join runtime |
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
| `3780119725` | in the rain V 31 | 89 | 37 | 48 | 1982 | 无 | 新增 / census未join runtime |
| `3780391264` | Agnes Tachyon Umamusume Neon | 19 | 7 | 10 | 512 | 无 | 新增 / census未join runtime |
| `3780940857` | 枕澜 蒂法 电脑动态壁纸 最终幻想7 TIFA Final Fantasy VII | 2 | 1 | 0 | 23 | 无 | 新增 / census未join runtime |
| `3781307553` | Look this | 2 | 5 | 0 | 63 | 无 | 新增 / census未join runtime |

## 6. 修复记录与防回归合同

每个公共 family 使用三个独立状态：

- `repair_state`: `untriaged -> diagnosed -> in-progress -> implemented -> bounded-verified`；
- `runtime_proof_state`: `none -> partial-chain -> visible-chain-closed -> official-golden-equivalent`；
- `regression_protection_state`: `none -> synthetic -> targeted-runtime -> milestone`。

`bounded-verified` 至少要求项目自有 synthetic 正例、反例、真实隔离样本 GPU→publication→compositor→next-frame→ROI 和明确剩余边界。`official-golden-equivalent` 还必须有同相位官方 golden 及像素/时序容差。只降低 rejection 数、只 non-black 或只加载资源不能写成修复完成。

当前已逐族复核并登记的修复见机器 repair ledger 与下方状态表；未列 family 继续保持 `untriaged`，不会因 effect 名、路径或相邻 family 已修而自动升级。

| family | 修复 / 运行 / 回归状态 | 公共修法 | 真实 sentinel | 剩余边界 |
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
