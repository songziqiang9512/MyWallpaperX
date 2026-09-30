# 新样本缺口分析（2026-09-30）

> 基于 census 重扫（208 样本 / 2973 family / 81709 occurrence）+ 12 个问题样本的隔离
> benchmark 实测 + pkg 解包逐层核查。所有症状已映射到引擎日志与作者定义结构。

## 增量总览

208 样本（+36 新）、2973 family（+366）、81709 occurrence（+12947）。Family 增量：
layer +233、particle +49、dynamic-input +45、shader +25、material +3、audio +4、其余 +7。

## 缺口清单（按实测根因）

### 已修复

**缺口 2（自引用依赖黑屏）→ `60154574`**：1926190458 层 13 声明 `dependencies: [13]`，
`DependencyOwnershipCompiler.compile()` 的自引用路径因 `!effectiveReferences.isEmpty` guard
在 shadow 证明成功时返回 nil → 整层被 `execution-route-dependency-owner` 拒绝。修复为允许
空 effectiveReferences（shadow 证明成功正是 graph-internal 的意图）。修复后 169,753 unique
pixels、claimed=1/encoded=1。

### 待修复（按优先级）

**缺口 3（音频条 composition 层 textureBindingInvalid）→ `3d94a3f4` + `9b4086ff` 已修复安全回退**：
影响 3807151772/3806337293/3805547608/3807668787 等。层 399（composition + audio bars）被
`material-variant-envelope-texture-binding / textureBindingInvalid slot=0` 拒绝。根因：
音频条 shader 声明 `g_Texture0` 的 materialKey 是 `"上一个"`（中文编辑器写出的 previous
本地化键，字节级确认）。`3d94a3f4` 把该 rejection code 加入 passthrough allowlist（层不再
被整层丢弃）；`9b4086ff` 泛化 StraightBlendOutputAnalyzer 的 color 定义 gate 接受声明-赋值
分裂形态（colorTransfer 泛化）。

**当前状态（2026-09-30 注解解析修复后实测）**：早期 textureBindingInvalid/materialKey 叙事
已被 HEAD 复测推翻——层 399 在 HEAD 上死于更上游的两条独立拒绝：① `workshop/3635233909/
effects/____________` 的 shader 合同因第 39 行中文注释 `// BLENDMODE 是由顶部的 [COMBO] 宏生成的`
被注解扫描器误判为 malformed COMBO（`shaderContractInvalid` → catalog-failure →
`material-template-unsupported` 整层拒绝）；② `sine_wave` 前端 `varyingUnsupported`（fragment
改写 varying，见下）。修复①：注解 marker 只有负载（JSON 起始符；`[PASS]` 行首）才算注解尝试，
正文引用 `[COMBO]` 字样的普通注释不再产 malformedAnnotation。修复后实测（隔离 benchmark +
频谱夹具）：`____________` 模板接纳，Simple_Audio_Bars 材质执行（encoded-output），
`g_AudioSpectrum16Left/Right` uniform 消费 nonzero（peak≈0.35），PCM vs 静音夹具 A/B 差分
16.3% 像素（>12 阈值、逐通道最大值口径；列分布中间高两侧低）——音频条实际渲染且随频谱
响应。benchmark PASS（两条已分类 passthrough 登记后）。注解行为收窄：marker 后无 JSON 负载
的注释行不再产 `malformedAnnotation`（此前误诊整层拒绝，现按普通注释忽略）。

**剩余降级（层继续渲染、效果级）**：
- ~~effect 1（`____________` 渐变混合）~~ **已修复（第二批）**：原形态
  `ApplyBlending(BLENDMODE, scene.rgb, gradientColor, u_Opacity)` → `vec4(finalColor, scene.a)`
  （采样底 + 生成覆盖 + 标量不透明度 + alpha 直通）被 IndependentAlphaAnalyzer 宽兜底误分为
  `independentAlphaSignalPreserving`，该类要求输入槽为 independentAlphaSignal 表示（实际是
  条形材质输出的 premultipliedAlpha 颜色）→ finalizer 每帧 colorContractUnproven → passthrough。
  修复：StraightBlendOutputAnalyzer 新增 `analyzeScalarOpacitySampledBaseBlend` 证明（单 vec4
  载体、main 内单采样调用、载体仅 .rgb 混合底 + .a 直通两处使用、模式/覆盖/不透明度参数无
  采样无载体引用、ApplyBlending helper 不采样），阶梯插在 IndependentAlphaAnalyzer 兜底之前，
  分类 `straightAlphaPreserving`（合同接受 opaque/premultipliedAlpha 输入，generic 构件走既有
  preserving 下降器族）。实测：effect 1 `profile=source-proven-graph-input-stage-uniform-straight-
  alpha-preserving-no-auxiliary`、slot0 显式别名接入效果 0 输出、`outcome=encoded-output`，
  passthrough 消失，benchmark PASS。作者配色（垂直渐变 起始 1 1 1 → 结束 1 0.714 0、角度
  -90°）即"音频条颜色/光从上面"的静态来源；条形自身灰（Bar Color 0.21、GRADIENT 关闭）。
- effect 2（`sine_wave`，"光闪过"的动态波扫）`material-generic-owner-revoked`：fragment 内
  改写 varying（`v_TexCoord.x += ...`，.frag:34/37）被 VaryingPrefixLink 的写拒绝守卫拦下。
  dd7b1da5（E5 窄化批）只接受"读未初始化分量"族，未覆盖改写形态；归 E5 varying 实施批按
  其 prove 分类协议处置——源级证据已登记（vertex `varying vec4` 只无条件写 `.xy`，fragment
  声明 `vec2`、读 `{x,y}` 整值+分量、并在 `#if AUDIOPROCESSING` 两侧改写 `.x`）。

**缺口 1（image→model→material 链黑屏）**：833227004 渲染纯灰（178,178,178 = 清屏色），
材质管线 planned=0。层 `image: models/background.json` → material `flowimage`。准入的
候选选择不含"无场景效果但模型引用自定义 material"的层。初版候选扩展编译过但被
`raw-graph-count` 拒绝——需要为这类层合成单 pass graph 或放宽该 guard，属独立设计批次。

**缺口 4（effect 执行失败→passthrough 泄漏）**：3809618616（全屏红纯色）、3806337293、
3796588443。根因是 workshop 效果 `video.frag` 第 77 行
`g_AudioSpectrum64Left[barID / 4][barID % 4]`——对一维数组用二维下标，glslang 编译失败。
**这是作者 shader bug**，官方客户端同样编译失败。引擎按合同 fail-soft（previous-current），
但 benchmark 的 passthrough 计数器把这种 previous-current 报为 unexpected（矩阵未预登记）。
无需修产品代码——需要在分析文档记录该形态。

**缺口 5（性能/卡死）**：3589454154（130 层、3.8fps 近冻结）、3232289987（60 层 9 粒子 +
跨 workshop 引用，进程超时）。需 CPU profile。

**缺口 5b（效果链中间目标降尺寸，候选 A）→ 偏差登记（2026-09-30 落地）**：
- **目标合同**：持久效果链 graph 目标规划的工作 extent 是纯拓扑档决策（零样本/效果类知识），
  唯一解析入口 `persistentTargetPlansResult` 调 `SceneOffscreenResolutionPolicy.resolvedDimensions`：
  非 exact 合同层一律 `.standard` 档（2048 上限），裸 poolLimit/hardLimit 不进入链规划；
  `.exactSamplingTexture` 层（Puppet，全仓唯一声明者）逐字保留原 policy 与 exactness 硬拒；
  `compositionTarget` sizing 与 `SceneLayerGraphTargetPlan.make` 的同 inputExtent 合同不变。
- **当前事实**：规则已由规划入口 `SceneOffscreenResolutionPolicy.chainPlanningPolicy` 落地。
  产品唯一调用方（SceneResolvedMaterialFramePreflight 传 `effectSourceExtentContract.targetPolicy`）
  对 scalableStandard 本就映射 `.standard`，故当前产品路径行为不变；本批把该规则从调用方约定
  上收为规划入口裁决，并封死 planner API 层的裸 poolLimit 请求（既有 harness fixture 曾以
  poolLimit 规划出 4000×3000 链，现断言降档到 ≤2048）。
- **取舍**：`SceneLayerGraphTargetPlan.make` 强制全 stage 同 inputExtent，且
  `SceneGraphRenderTargetPlan.make` 只收单一 inputExtent——"中间降档/终端保原幅"异构不可行，
  也不许改 make 同 extent 合同；故整链共用一个降档 extent，终端 effectOutput 随链降档，
  Puppet 精确图集层不降。
- **owner**：`SceneOffscreenResolutionPolicy.chainPlanningPolicy`（档位裁决）+
  `persistentTargetPlansResult`（唯一解析入口执行）；M4.1 memo 键 `PersistentPlansMemoKey`
  已纳入原始 extentPolicy，档位语义再变更时旧 memo 条目不可能命中新计划。
- **route/fallback**：规划失败仍走既有 `localFallbackReasonCode` 局部 fail-soft
  （previous-current），本批无新增兜底分支。
- **纠正门**：改前改后终端输出 montage 差分 + `_rt_imageLayerComposite_<id>`（代码名）
  base capture 变 S-extent（2048 档）后的跨层消费方偏差清单——凡经
  `SceneNamedTextureReference` 消费该层输出的依赖层逐一核对采样偏差；该门属后续验证阶段
  （本批按批次边界不运行 benchmark/xcodebuild）。
- **退役条件**：若后续 parity/兼容证据要求普通层链输出恢复 >2048（例如官方行为按画布投影
  出高幅链），由对应卡显式改基线并退役本档规则；帧率收益为机制推断、未实测，不设具体预期。
- **A/B 实测结论（2026-09-30 同机同构建流程）**：3078285611 为 Puppet exact 合同层，
  档位规则按设计对其不生效——基线 6.04fps → 改后 5.40fps 属运行噪声（montage 差分
  1.5%>12 符合纯动画相位噪声；此前"该样本链填充 ~4.6× 削减"的估算因 exact 合同前提
  不成立而作废，该样本的性能治理属 Puppet 保护下的产品语义裁决，非本档规则范畴）。
  本批的实际价值 = 规划入口档位裁决收口 + planner API 裸 poolLimit 漏洞封死 + 行为
  断言固化（poolLimit 链降档 ≤2048、exact 链保 4000×3000 逐字不变）。

**缺口 5a 重新归因（2026-09-30 LAUNCH-STAGE 实测，3233141951）**：`stage=catalog-decode
elapsedMs=25`、`stage=device-join elapsedMs=28770`——材质资产目录解码仅 25ms，
"内联解码阻塞启动"的原定性被实测推翻；启动主项在 device-join（28.8s，base 车道
`SceneBaseImageTextureLoad` 同步装载，含 18 张首帧可见层底图的解码/预乘/上传）。
缺口 5a 的治理杠杆相应重定域：从 catalog 车道资格扩展改为 base 车道 device-join 内
装载成本的结构性治理（归 warmup/route 启动域协调），deferred 车道扩展方案搁置待
重新定价。

**缺口 6（跨 workshop 粒子引用）→ 定性推翻并关闭（2026-09-30 全语料普查 + 双重审核）**：
208 样本中 135 个带粒子层，70 个含 `particles/workshop/<id>/...` 引用形态；204 个跨
workshop 粒子定义全部嵌入本样本 pkg 索引、0 不可解析（ScenePkgCacheExtractor.swift:195
的 allowedPrefixes 本就含 "particles/"，提取无 workshop id 过滤；纹理另有 stock 回落链
SceneParticleAssetGraph.swift:295-317）。"预下载/补全"方向按过度防御正式驳回——零产生者
的第二资源查找路径（AGENTS.md §2）。原观察样本 3232289987 的 "particle loading
incomplete" 根因另在：child-only 容器准入 fail-closed（SceneParticleRuntime.swift:578
admitsChildOnlyContainer，root renderer 缺席且子集非严格 static 时发 missingSpriteRenderer
诊断并整层跳过）——残留移交粒子语义卡。观测面：benchmark 自 2026-09-30 起解析
`particle diagnostic ...` 与逐层 unavailable 行（镜像
SceneParticlePlaybackState.swift:217-222 输出格式，非贪婪 path 防 detail 吞并），
"particle loading incomplete" 失败从此在 report.json 样本记录（顶层与 runtime 段）携带
逐层原因
（particle_diagnostics/unavailable_layer_ids），期望纪律不变——新字段仅供归因，
generate_scene_full_matrix.py 不得用其放宽既有期望。

## 第二轮 benchmark（8 个代表性新样本，2026-09-30）

| 样本 | 结果 | fps | 观测 |
|---|---|---|---|
| 2163522240 | PASS | 54.4 | composition(2)+self-ref；自引用修复覆盖 |
| 2304304373 | PASS | 50.8 | composition(3)+model-material 链 |
| 2684431262 | **FAIL** | 5.7 | **黑屏**（69k unique 中 4.79M/6.2M 为纯黑 (0,0,0)）|
| 2794098047 | PASS | 56.6 | audio-bars+composition(4) |
| 3078285611 | PASS | 7.9 | **纯粉色**（583k/620k 为 (250,142,200)）——渲染单一覆盖色 |
| 3233141951 | **FAIL** | — | **进程超时**（12 秒窗口被 SIGTERM） |
| 3448845950 | PASS | 18.5 | 深色场景（51 万像素 (0,14,26)——暗色主题正常） |
| 3226487183 | PASS | — | **2026-09-30 复测转 PASS**（`or` 保留字修复后零 passthrough；见下） |

**65 个新增样本匹配已知缺口模式**（音频条/composition/self-ref/model-material 链）。
缺口 3 的修复（`3d94a3f4` passthrough allowlist + `9b4086ff` colorTransfer 泛化）已覆盖
其中音频条+composition 层的 textureBindingInvalid 拒绝。

## 新发现（工作流诊断代理深挖后修正）

- **2684431262（纯黑 5.7fps）→ 症状归因错位**。场景渲染正确（model→material 链 8/8 完整、
  25/25 模板编译零失败、音频链全通），"纯黑"是作者黑底艺术图的设计本底（87% 黑像素，官方
  预览同样黑底）。5.7fps 是 harness 在无 warmup 的测量窗内插入 4 次同步全屏 HDR 快照
  （每次 ~2.4s 阻塞渲染线程）造成的测量伪影。唯一真实的产品侧差距是 HDR bloom 的
  scatter/feather 完整链（台账仍开放）。→ **非引擎渲染缺陷**。

- **3233141951（进程超时）→ 纯解码体量问题**。38 张 .tex 中 24 张 free-image（7 张
  ≥4096×2296 PNG，raw 首 mip ≈335MB），解码→预乘→BC→mip 全部内联阻塞 device-join，
  无逐纹理日志。deferred 车道被两条规则关闭：粒子场景一票否决 + 资格只限无效果层。
  → 需要扩展 deferred 车道资格或增加逐纹理日志（独立批次）。

- **3078285611（纯粉覆盖）→ 证伪**。粉色是 id=93 层「纯色背景」的作者设计背景色
  （solidlayer color = RGB 250,142,200，绑定的用户属性默认值精确匹配）。渲染逐层合成
  正确。7.9fps 是 25 级效果链以 4800×3000 输入逐 pass 的真实成本。→ **非引擎缺陷**。

- **缺口 1（833227004 model→material 链黑屏）→ 代码级排除链已确认**。
  ① `SceneAuthoredEffectRenderPlanner.plans` 对零效果层返回 nil → 无 authored plan；
  ② `candidateLayerIDs` 不含此类层 → 不进候选；即使强行扩入，`raw-graph-count` 和
  `validateOuterGraph` 均以 descriptor layer.effects 为锚，合成 stage 无从对位；
  ③ 无替代执行路由。整层不可见只剩清屏色。→ 需要合成 graph 或新增 material-only
  执行路由，属独立设计批次。
- **缺口 1 子批 A（layer 尺寸推导）→ 已落地（2026-09-30）**：黑屏直接根因之一是
  layer 1 无显式 `size` 字段 → `sizeWH` 缺省 [0,0]（SceneRenderDescriptor+Layer.swift:50
  注释）→ 零面积不可见，而模型描述符 `models/background.json` 自声明
  `{width: 1920, height: 1080}`。修复：ModelAsset 解析标量 `width/height`
  （declaredModelSize，双字段齐备且 >0 才生效），描述符构建对无显式 size 的 model
  引用层继承该设计尺寸（显式 size 逐字优先）。实测：layer 1 `size=(1920.00, 1080.00)`
  （原 0,0），纯灰(178)像素 100% → **0.00%**，星云底图完整渲染，benchmark PASS。
  当前为静态底图降级态（normal image 路径直绘 background.tex）；官方行为是 flowimage
  动画材质——合成 graph（子批 B，走既有 authored-plan→admission 链 + computed index
  寻址拒绝同批）仍是 parity 的后续步骤。工作流 GPU 取证队列（dwfrun-f85d48e7）
  的 DEBUG 运行同时核验了底图加载链本身成功（loaded=1 failed=0），合成方案前提成立。
- **缺口 1 子批 B（合成 plan）→ 锚地图实测完成（2026-09-30，实施回退存档）**。
  合成路线已端到端试通至图执行（descriptor `1#model-material#<materialPath>`、
  compositorConsumed=true），逐锚实证如下（patch 存档
  `docs/scene/evidence/20260930-gap1-synthesis/subbatch-b-threading.patch`，543 行）：
  ① planner 零效果层返回 nil → 合成分支（`isSynthesizedModelMaterialGraph` 结构识别：
  层无 authored effects + effectIndex 0 + definitionPath=模型路径 + 单材质节点命中
  modelMaterialLink）；② admission conservation `plannedEffects` 空守卫 → 合成豁免；
  ③ `validateOuterGraph` zip 锚（key/definitionPath 对位）→ 专用全结构分支（更严：
  节点/目标/链接材质逐项）；④ compileLayer effect-definition 查找
  （effect-definition-count）→ 合成豁免（functions=nil）；⑤
  `SceneGraphConditionProviderSet` instance 对位（descriptorMismatch）→ 旗标豁免
  instance 锚（material combos 仍是唯一 combo 来源）；⑥
  `SceneAuthoredMaterialResolver.instanceOverlay`（instance pass 对位）→ 空 overlay
  （结构识别：层 effects 空——planner 是该形态唯一 plan 产生者）；⑦ 模板
  `renderStateInvalid`（材质未声明 state 即整态无效）→ 合成四边形缺省
  （normal/nocull/disabled/disabled，声明字段逐字优先）。
  **未打通的一锚（修正此前误判）**：`material-variant-envelope-texture-purpose`——
  实测诊断逐字：`slot=0 reference=asset:background sampler=g_Texture0 mode=regular
  material=<none> default=<none>`。用途三路证明全空：采样器 `sourceProvenPurpose=nil`
  （flowimage 采样形状未被既有 source-proven 分析器覆盖）、`declaredPurpose=nil`
  （材质纹理为裸字符串声明，无用途注解）、stock 语义注册表无 "background"。
  修复形状 = 缺口 3 族的"材质资产纹理 source-proven 用途扩展"（内容已测量的
  premultipliedColor 资产 + 采样形状分析器证明）。此前"active-resource-demand
  鸡生蛋"为误判——该字符串只是诊断位，真实 demand issue 即 purposeUnproven。
  另有 runner 侧：合成 effect 无 effectStage 行，disposition/conservation 断言需
  runner 理解合成形态（触 test_scene_wallpaper_benchmark.py，并行会话在途须协调）
  ——**该依赖使子批 B 为跨会话批次**。
  实测序：descriptorMismatch → instanceOverlay 拒 → renderStateInvalid →
  envelope-texture-purpose passthrough（图执行 succeeded、合成 compositorConsumed=true、
  视觉无回退——passthrough 转发层源）。回退原因：⑨ 未通前样本 benchmark 由 PASS
  转 FAIL（证据契约），按"不当场堆补丁"纪律回退至子批 A 已验证态；重放 = patch +
  用途证明扩展 + runner 合成形态断言（须与并行会话协调）。
  附带观察：833227004 夜间运行两次出现 `performance presentation stream count does
  not match surfaces`（22:20 同代码 PASS、23:15 两次 FAIL、同时刻动画样本
  2131872317 PASS）——样本特化的呈现流测量环境敏感观察，与合成回退无关，留观测。

### 非缺口（观察与实测不一致）

- **3805547608**：benchmark PASS，52fps。"图层源切换"是 UI 交互路径，静态测试不覆盖。
- **2983846453**：属性面板缺自定义图像导入是 UI 功能缺失，非 Scene 渲染缺口。

## 3226487183 第三轮复测（2026-09-30，`or` 保留字修复后）

- **已修复**：layer 982（utility composition，`workshop/2179455321/dot_matrix_mobile_fix`
  点阵效果）每帧 `material-pass-preparation-library-compilation` passthrough。根因：作者
  shader 声明 `vec2 or = …`——`or` 属 C++ alternative-operator 拼写，GLSL 未实现该运算符
  故 glslang 当普通标识符收下，SPIRV-Cross 原名发射，Metal 编译器按保留字拒绝
  （`expected unqualified-id`）。修复：normalizer 在解析前对两 stage 原始源做整词改名
  （10 词集合，排除 `not`——GLSL 内建函数名；带碰撞检查后缀 `_mwx`），声明/接口/body
  全链一致。复测：library-compilation 0 条、layer 982 encoded-output、零 effect-local-passthrough
  回退（route-accepted 的 uniform-passthrough profile 行除外）、benchmark PASS
  （证据 docs/scene/evidence/20260930-misalign-3226487183/；瞬态 localcontrast 观察的
  两跑日志为 /private/tmp 临时产物，时间戳 17:51/18:06、同处 ad72bd5a 工作树）。
- **仍未修（错位本源）**：layer 2522（composition 组，chromatic_aberration 效果）被
  `execution-route-utility-composition-subtree-shape` 整层拒绝——其子层在作者顺序中
  不连续（位 21/24/32/35 与非子层交错）且每个子层自带 7 个效果，两条都不满足
  捕获路由的"子树连续+子层无效果"前提。preview 日志的 `unsupportedChildren` 同源。
  修复需要组合组拥有独立渲染目标（当前设计假设子树连续画进主目标后整块捕获，
  SceneUtilityLayerSourceRoute 注释已明确该边界）——与缺口 1 同级的独立架构批次。
- **瞬态观察**：`localcontrast_downsample4`（layer 38）的 stage-link 工具拒绝
  （exitCode 2）在一轮复现后自行消失，同源码两跑结果不同——归 stage-link 工具域
  （E5 队列）跟踪，非本批范围。

## 文档更新

`docs/scene/semantics/scene-corpus-capability-inventory.md` 已由 census 重写（172→208）。
快照 `script/scene_capability_census_snapshot.json` 同步更新。
