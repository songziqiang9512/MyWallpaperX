<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

> **历史证据 — 非现役入口**。当前权威：[D3设计](../roadmap/batch2/2d-lighting-material-design.md)、[实施路线](../roadmap/scene-compatibility-roadmap.md)、[来源分类](../development/source-index.md)。
>
> 2026-10-02 独立审查批准v1已定中性字段用于无map标量设计与反例，并批准v2/v3新增第三方组件presence链及有界corpus聚合作为后继输入；归档v3原研究正文SHA `8d4c2343f525cefe04f3dcd5c5c1efaec3527c233c1324180ebe3cf84605c731`；v1输入身份仍在正文保留。下文保留交接时pending字样和未知项，不能将其升为已验证贴图通道或官方运行合同。实际实施准入及后继只看现役设计；此归档不含原始参考实现。

# RF10 PBR 作者输入中性合同（v3，补齐有界作者资源 header/通道聚合）

2026-10-02。研究 context `/root/d3_neutral_review` 永久 research-only，product_write_authority=false。本文仅中性输入合同，无 shader 源码、函数体、私有数学、常量表、资源 payload 或像素。独立审查尚 pending；不得把本文或声明元数据当作产品/官方 parity 通过。

## 已可独立用于设计的输入

固定客户端 2.8.42 的 genericimage2/4 **slot2 为 PBR masks**；四个作者组件名称及 per-map presence keys 已定。**scalar exact keys、默认、editor range 也已定，genericimage2/4 的 metallic/roughness 默认不同。** 本 v3 尚不能把组件数组 index 推为 RGBA；不采用 model slot2 alpha-emissive 作该证据。通道/各分量 runtime gate 的补证继续中。

### official-public-contract（2026-10-02 实际读取）

- [Lighting & Reflections](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)：网页行 43/50 允许 Lighting、Reflection 单独或共同启用；行 68–69 指明场景光只影响启用 Lighting 的 image layer。不能把 UI require 列表当 AND 门。
- 同页行 89–94、95–102：metallic 控制金属感、roughness 控制反射散布；其 map 留空时有对应 slider 替代输入。行 105–106：Reflection map 可局部减弱反射，Reflectivity slider 控制整体反射强度。该页不说明 RGBA packing 或各分量的内部 gate。
- [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)：行 154–156/166、219–228 分开 texture material key、default 与作者 presence combo；行 245–251 定义 slider 的 material key/default/range。generic stock exact key/默认值仍须下列固定声明证据。

### official-client-static-observation：仅作者声明元数据

身份根 `/Users/songziqiang/Documents/Development/MyWallpaperX/Reference Project/wallpaper_engine`。`version.json` 实读 version=2.8.42，SHA-256 `63d3083d31280df36b37855ea833a6bcdb49afd59dd7963a27cf771e3532d1e1`；wallpaper32.exe SHA-256 实算 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。build 23967692 只来自来源索引历史登记；version.json 无 build 字段，本轮未独立再证 build。实际内容以文件 hash 为界，不宣称其他版本不变。

| 声明输入 | genericimage2.frag | genericimage4.frag |
| --- | --- | --- |
| 文件 SHA-256 | `1e252e2271cae57fcfdecf3bd79d1685bb726e1e8afe09ba863dca2e1b12d68e` | `6b5344953054ae853ff8a7942f716dd9eb67f61cc1526bd8b6bc67df92c76e1f` |
| slot2 声明 | `assets/shaders/genericimage2.frag:22` | `assets/shaders/genericimage4.frag:39` |
| slot2 metadata | combo=PBRMASKS；mode=opacitymask；无 texture default；paintdefaultcolor="0 0 0 1"；UI require={LIGHTING:1,REFLECTION:1} | 同左 |
| component index 0 的声明 | label=Metallic map；combo=METALLIC_MAP | 同左 |
| component index 1 的声明 | label=Roughness map；combo=ROUGHNESS_MAP | 同左 |
| component index 2 的声明 | label=Reflection map；combo=REFLECTION_MAP | 同左 |
| component index 3 的声明 | label=Emissive map；combo=EMISSIVE_MAP | 同左 |
| feature combo 声明 | 本轮该 fragment 过滤未取得 LIGHTING/REFLECTION default，保持 unknown | `:2` LIGHTING default=0；`:3` REFLECTION default=0 |

**component index 是声明数组索引，尚不是已证实的 stored channel。** 此声明没有 r/g/b/a/channel 属性。本轮提取器只输出作者 JSON 白名单字段及标识，不输出 uniform 行源码或代码分支；无数值处理/BRDF 观察。paintdefaultcolor 是编辑器开始绘制的颜色声明，不是可任意绑定的 stock default 资源，也不能反向制造 PBRMASKS presence。

| exact material key / 作者 label | type | genericimage2 默认 / 位置 | genericimage4 默认 / 位置 | editor range |
| --- | --- | --- | --- | --- |
| `roughness` / Roughness | float | 0.5，`:23` | 0.7，`:40` | [0,1] |
| `metallic` / Metallic | float | 0.5，`:24` | 0，`:41` | [0,1] |
| `reflectivity` / Reflectivity | float | 1，`:48` | 1，`:69` | [0,1] |
| `emissivecolor` / Emissive color | vec3/color | white，`:26` | white，`:44` | 无 range 声明 |
| `emissivebrightness` / Emissive brightness | float | 1，`:27` | 1，`:45` | [0,10] |

所有位置均是对应 fragment 文件行号。shader symbol 分别为 g_Roughness、g_Metallic、g_Reflectivity、g_EmissiveColor、g_EmissiveBrightness；它们只作为 exact 输入声明身份，不带函数表达。genericimage4 `:70` 另声明 hidden `reflectivitydistance` default=4/range=[0.01,10]；其环境职责属于 N3，不纳入本片 direct-light 输入开放。

Locale `locale/ui_en-us.json` SHA-256 `3a58e712363f8f20bf7c371746462ecaf36919be949dcc968a3785d07f251ea0`；labels 对应行：Metallic/Metallic map `:2773/2774`，Roughness/Roughness map `:2992/2993`，Reflection map/Reflectivity `:2937/2938`，Emissive brightness/color/map `:2588/2589/2590`。语义由作者 label 声明与 locale 确认，不靠变量名或文件名猜。

### authored-corpus-observation：只读精确 JSON，未运行

真实根 `~/Movies/MyWallpaperX/创意工坊/Scene`。JSON 阶段复用只读 PkgArchive，未提取、未读取 binary model/shader payload。下列 SHA 都是完整 JSON entry 字节，不是整包 SHA；后续新增的授权 slot2 资源只读统计另列，不把 JSON 观察冒称像素/官方运行证据。

| 包 / material entry | 作者组合 / 相关值 | entry SHA-256 |
| --- | --- | --- |
| 3662790108 / `materials/sun-4.json` | genericimage4；LIGHTING=1；slot1 null、slot2非空；emissivebrightness=1，emissivecolor 为 vec3 | `5d0d88f8980a46779960b22003095ddf46662ece56e0a9b139b7d1fcc9bf307c` |
| 3662790108 / `materials/sun-1.json` | 同类组合；roughness=0；emissivebrightness=1 | `85557e23bd3daa0ab30d1db829540c771a8b14d1f5fd4419bd6339ed9997747d` |
| 3437487219 / `materials/Universe.json` | LIGHTING=1；slot1 null、slot2非空；roughness=1；emissivebrightness 是 {user,value} 结构 | `4fc65fa8a29edccefbe94fb0fed2ea0fc45c87e2607d5b91e2fbb34d804d2cd3` |
| 3777761326 / `materials/workshop/3685680567/2block_ertbuild_02_light.json` | LIGHTING=0、REFLECTION=1；slot1/2非空；reflectivity=1 | `bc7621003fbe982921c87f8308e18236c662a117c5a0e6c127b29c93a9205e70` |
| 3780119725 / `materials/земля.json` | LIGHTING缺省、REFLECTION=1；slot1/2非空；metallic=1、roughness=.93、**reflectivity=3** | `cd682831e2a317c6e53777eea78efac9e1c02980ce27b3c5888923dcbe8f0200` |

五项均未显式写 PBRMASKS 或四个 per-map combo；非空 slot2 是实际作者 binding，不能因 JSON 未重复写 presence=1 就当不存在。presence 仍不同于 availability，缺图也不能偷偷置成未启用。JSON 值 reflectivity=3 说明 editor range 不能直接冒称播放器对所有作者输入的 clamp/reject 合同。

对应 scene object 的 instance 均缺省：sun-4/sun-1 id1121/1336；Universe id146/135/143；Heart 1 id320/343/360；земля id308。未从这组语料证明 static override/reset 优先级或实际可见收益。scene entry SHA 复核与先前中性包相同：3662790108 `faea17adcce6b09b40c1a722c08b53bc4f3588c3189873986c754517a9500cc5`；3437487219 `845a96e6ee0adc935aa2dd368a5be140a164221b21a1424179296ab85f2b52b5`；3777761326 `d0ede920c7aaecf7bd6e22651d221aefb22643fcd99dbcd424b505536fb58d88`；3780119725 `5bbf4fb8f117ead862c27d9f40cac7305fa3167d88c917f56e80a57e17408df4`。

### third-party-reference-pattern：固定 Mirage 的 metadata/resource 职责互证

唯一 revision `da4fa7b3ee33e9e94c59307f47098aa521f21aa6`，文件根 `Reference Project/MirageWallpaper/SceneRenderer/Sources/SceneRenderer/`。以下是该公开参考项目的输入行为，**不是官方客户端运行真值**；仅输出职责事实，无实现代码或算法表达。

| owner / 精确位置 | 本轮中性观察 | 固定文件 SHA-256 |
| --- | --- | --- |
| `Wallpaper/Compiler/TextureDecoder.cpp:19`、`:170` | TEX header 的 compo1..4 保存为四项 component-enabled 元数据；对应 flags 的 bit20..23。仅查看头部 flag producer，未读 payload/像素解码。 | `1cbed63d0aabcdaecdc15d37a17c37209232eaf53b9ebf14a90c7d62cf373c95` |
| `Wallpaper/Compiler/SceneCompiler.cpp:1870` | 实际 material 非空、普通资源 binding 会读取 header；compo1..4 顺序对应 texture compile info 的 index0..3。空槽产生 disabled；普通资源缺少 compo1 header 的此第三方路径也 disabled。special typed binding 有独立 enabled 路径。 | `856016a5aae99c4a9dcdcdf634aa28897dabff34480eab0f80af4307be7dfdba` |
| `Wallpaper/Compiler/UniformSpec.cppm:16`、`:48` | author components 数组保留顺序，每项只读 label/combo；没有 channel 字段或 RGB 映射。 | `f656e96192e03fbed7101600dbb430f3a146ba13dadc3c8cb4a3510fc63a6063` |
| `Wallpaper/Compiler/ShaderAnnotations.cpp:178`、`:181` | texture-enabled 决定整体 sampler presence；enabled resource 的 component-enabled[index] 对齐 author components[index]，对应 component combo 启用。**未显式写 per-map combo 并不表示缺少 component；非空 slot2 也不等于四项全开。** | `89f89ae700deb64ae19af920156cf0874f39bed60b6c22876cbb27e2144c010f` |
| `Wallpaper/Compiler/MaterialShaderCompiler.cppm:69`；`MaterialShaderCompiler.cpp:2117`、`:2375` | compile info 传递四项布尔 component 元数据；轻量单独编译入口省略 header，其四项都 false，注释明确可能与 production packed-channel variant 不同。该轻量路径不适合作官方/生产 presence 真值。 | cppm `66cdb96a746c3550e5808f1ea762fef7a8ac3acaaacc13db8c4244d4c9f1a1cd`；cpp `278301ca9fc4c81fbab3f85ab733b9c40d88641ecbbb4834ef2b79d390440f89` |
| `Wallpaper/Schema/ImageLayerSpec.cpp:57`、`:89`、`:381` | material 载入后应用 object instance；instance textures 只接收字符串，null/非字符串变为空；instance 声明域是 combos/textures/usertextures。 | `60d97b9744a15ff69452f302f6181741244f4d6d4876cf9af458a59384ea2c84` |
| `Wallpaper/Schema/MaterialSpec.cpp:129` | static instance 同槽非空 texture 覆盖；空槽继承 material；数组按需要扩展；combo 同键 instance 胜，usertextures 同键合并。未证明官方空槽 reset，也未证明 instance scalar override；此第三方 instance schema 没有 constantshadervalues 字段。 | `84cc831f55298254f6a995cd7374817d1e1eae233bb47da5b79bf2ddd3e09a3f` |

由 stock 作者声明身份与这条第三方 component-index 链可互证：**compo1→index0 Metallic-map presence、compo2→index1 Roughness-map presence、compo3→index2 Reflection-map presence、compo4→index3 Emissive-map presence**。这里的箭头仅是元数据启用对应关系，**不声明 compo1=R、compo2=G、compo3=B、compo4=A**。它也没有证明 tex header flag 一定等于像素通道是否非零；后继不得用扫描像素、全 component 默认启用或 JSON 缺省0代替已声明 component metadata。

### authored-corpus-observation：仅现五个 slot2 的 header 与通道聚合

公开作者页补查未取得 packed-channel 明确说明。root 随后授权在这五个已有材料的精确 slot2 内做 header/format 身份及每通道恒定/变化聚合；先在卡预声明 single-component/combination 判别、authored 证据上限、预算后执行。不读 stock 资产，不扩 corpus，不保存/交付任何像素或纹理 payload。

下表的 component-enabled 顺序仅是 compo1..4 元数据，关联作者 Metallic/Roughness/Reflection/Emissive presence；不是直接 RGBA 声明。每个 header SHA 是 entry 前46字节；全 entry SHA 只作可复核身份。

| 包 / slot2 TEX entry | format / flags / components | header SHA-256；entry SHA-256 |
| --- | --- | --- |
| 3662790108 / `materials/masks/sun-4_mask_5cf68527.tex` | format0；flags8388610；[false,false,false,true] | `525c3e6fc02c751f9504d746905e654b7d9d81c3b9f4665192195c0d36f4d358`；`82ce1a1a094e4eb5cb98ca5ba72d9e2165373d30039112dd5d52d6f72bdae707` |
| 3662790108 / `materials/masks/sun-1_mask_30d1021b.tex` | format0；flags8388610；[false,false,false,true] | `0dd9024de5e75b0425929436e39e6d7e50bbfb1170be82543b88359877fa55f2`；`57593aabf825468521654e711b43277ec4754ac4acd1b231ea8ed8dd5f34db81` |
| 3437487219 / `materials/masks/Universe_mask_806e3b20.tex` | format4（当前项目格式解释为BC3）；flags8388608；[false,false,false,true] | `3c075f7878279fc0db3597cfcf7ad4db3c3076aa575b9a07ee767e5b48fab373`；`b556692407f100171f463dcf5f7d2d4450cfa37f97d3e8df5ae1f4141c2647c6` |
| 3777761326 / `materials/workshop/3685680567/masks/2block_ertbuild_02_light_mask_647b9c36.tex` | format0；flags15728642；[true,true,true,true] | `e5bd6786ac013e07271d9c15c673203f42ba98827ea3ef160c92acb37e991359`；`f36a861018b68e5e3a0e5ce6905b0bc81a2e19abfd37dc737ae26498779c239b` |
| 3780119725 / `materials/masks/земля_mask_38f2ba2d.tex` | format0；flags4194306；[false,false,true,false] | `7903e9d8c0d13ceeef73b8f93a1e6105fa14a078a56e6eee3a8a5935974e8829`；`c7d9e8de18cb083729197a011e6da493733988a00ad827b0e9c0d7ff1c173da6` |

CPU 统计脚本为自有 `aggregate-authored-masks.py`；Python3.12.13/Pillow12.2.0/numpy2.4.6，PNG 不颜色转换、不预乘；Universe 用标准 LZ4 + Pillow DDS BC3 decoder，最大17M像素/128MiB数组，不取 shader 实现。raw 四字节排列只记 byte0..3，不假定物理 channel。统计输出只含身份、extent、各通道 min/max/distinct-count/constant；没有相邻像素、坐标、图像、encoded payload。

| 精确已有 entry | 聚合事实 | 判别上限 |
| --- | --- | --- |
| sun-4 | PNG R/G/B 恒0、A 恒255 | 全恒定；只能区别声明存在与是否变化，不能独立证明 emissive/A runtime mapping |
| sun-1 | raw byte0..2 恒0、byte3 恒255 | 不声明 raw 物理顺序；全恒定 |
| Universe | BC3 标准 RGBA decode：R/G/B 恒0；A 范围0..255、distinct256 | 仅 compo4 单组件且只有A变化，是 authored 的 Emissive/A **相关证据**；未运行官方客户端，不单独升格官方 mapping |
| Heart 1 | PNG R/G/B/A 都变化，范围各0..255；distinct分别255/256/255/246 | 四组件组合；无法从此区分 Metallic/Roughness 互换或 Reflection/Emissive 对应关系 |
| земля | PNG R/G 恒0、B/A 恒255 | 仅 compo3；B与A都是常数255，仍不能排除 Reflection/B 与 Reflection/A 两个候选 |

**N1 physical channel 合同仍 partial/pending**：本集合没有 Metallic-only、Roughness-only 或 Reflection-only 非恒定且可区分的保存样本，不能定完整RGBA。Universe 给 emissive/A 的有限 authored inference，后三个映射不可猜。三项真实 LIGHTING=1 材料均只有 compo4 presence：即使整个 slot2 已绑定，也不能把 metallic/roughness map 标成存在并用其恒零输入覆盖作者 scalar/default；这是 per-component presence 设计必须解决的具体反例。这里没有执行/收益/parity 结论。

## 官方黑盒环境实际检查（结果仍 not-run）

现有 Parallels Windows11 VM UUID `{a5728853-08c0-4e63-bbd7-4b0200e50dd5}`，研究开始前 stopped，已启动为 running；只读 guest version 查询为 Windows `10.0.26200.8875`。CUA 实际界面停在 PIN 登录，用户已由 root 单独请求手动登录。未读取/猜测/填写凭据、未绕过认证、未用 guest exec 冒充已登录 GUI；未执行官方 App toggle/save/像素试验。VM 保持 running，等待用户登录及后续状态恢复裁决，不自主关闭。

## inference / MyWallpaperX-strategy（不是官方事实）

1. 可以先设计明确 scalar、无 map 的 direct-light 材质反例：使用已有 LIGHTING=1 与 point/spot/normal owner，按固定 builtin tier 取声明默认；数值方法独立编写并用自有反例验收。不等待官方 BRDF。尚未证明的环境反射不借 sceneBackground 冒充。
2. N1 channel 未定前不得给带 slot2 的样本猜 RGBA；逐component presence 必须与整体texture binding分开；可把这一个 map 解码分支记为待补，保留已验证 diffuse/normal，而不是把整个 scalar/PBR 家族跳过。map-slider 对 metallic/roughness 的空图替代方向由公开页面支持，map存在时确切组合仍需下面补证。
3. `REFLECTION=1、LIGHTING=0/缺省` 原样本保留后继；不能为制造本片受益改其 Lighting，再声称原样本通过。

## remaining unknown / 正在有界补证

- N1a：component index→物理 stored RGBA channel 仍未证；map存在时各scalar替代/乘法/全局调节仍未证。compo1..4→四component presence 的第三方职责已核，不等于物理通道。下一个可区分的合法观察是官方单组件 paint/save 输出的通道声明/可分发 structured metadata，或自有四通道单变量图的官方可见响应。现5材料的授权聚合只给 emissive/A authored 相关证据，完整mapping仍partial；不读第三方执行 shader 函数补算法。
- N2：场景灯需要 Lighting 的公开 gate 已定；PBR direct specular、emissive、Reflection 分量各自 gate、明确0/缺省/default 的运行关系还未观测。UI require 不能代替 runtime gate。
- N4-static：第三方已核非空同槽覆盖、空继承、combo同键 instance 胜；本组合法语料没有 instance，官方空/null reset 与 scalar instance 支持仍未知。第三方只能支撑职责/项目策略，不能替代官方真值。
- 官方 black-box/parity not-run。本研究将先核现有已授权本机官方环境能否做最小 toggle/save 或有界差分，不扩大 BRDF/格式/corpus。

## 交接与停止边界

当前 v3 是 v1 的可审查扩充；已冻结 neutral-contract-v1.md SHA-256 `94e2dfaee39c7206484dd86e2fe4fe25ec8dda2c885f01a07bf4bafa1be49480` 不变；channel/runtime gate 补证尚继续，独立审查身份 pending、sanitized_handoff_approved=false。研究者永久不实施 PBR；fresh 实施 context 只接本中性合同、卡、自有 fixture/协议，不接研究聊天或原始参考。后续更新必须给新 SHA，不能让实现者无身份地续读变动 packet。仓库、foreign script/scene_source_layout.json 保留；未 build/GPU/暂存/提交。
