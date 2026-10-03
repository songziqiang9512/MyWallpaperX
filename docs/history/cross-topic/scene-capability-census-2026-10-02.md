# Scene 引擎能力全景统计（终版）

> **历史证据 — 非现役入口**
>
> 截止日期：2026-10-02
>
> 终版 = 合成稿并入官方站联网普查差异（D）。**经 2026-10-02 官方站联网复核（72 URL 内容级亲核，D 产物）**。唯一权威 = [能力台账](../../scene/capabilities/coverage-ledger.md)，本文为派生统计快照。

## 0. 口径与边界声明

- 本文是**派生统计快照**：合成日期 2026-10-02，锚定工作树 HEAD `de72544b`（2026-10-02 21:09 +0800）。工作树另有未提交改动（渲染/静态模型等 8 文件 + 2 脚本），不在本文统计输入内。**唯一权威 = `docs/scene/semantics/coverage-ledger.md`；本文不修改任何登记**，只做 A/B/C/D 四份普查产物的对齐与求和。
- 输入：A=官方能力全集（分母，`A-official-universe.md`）；B=实现状态（分子，`B-implementation-status.md`，源自 coverage-ledger 191 条）；C=语料使用量（权重，`C-corpus-usage.md` + `incremental-stats.json`，208 样本）；D=官方站联网普查差异（`D-official-web-census.md`，72 URL 内容级亲核 + 107 页结构级确认）。
- **B 的 L0/L1/L2 换算口径（原文引用）**：「台账行『当前级别』为无 bounded/executed-degraded/historical 限定的 `L3`/`L4` → **L2 完整执行**；`L3 bounded`、`L2`、`L1`、`L0-L1`、`L0 product owner / historical`（已有 bounded 通用后继）、executed-degraded → **L1 部分或有条件**；纯 `L0` → **L0 未实现**。同名能力多节时取最新节状态。」B 另做 26 条 L2 实码抽验，虚报 0 条。
- **A 的分母裁决**：MirageWallpaper 自有实现（Y=0 反射相机、1920×1080 硬编码 kernel 等）一律排除；未定案推测不入分母、只入脚注（`camerafade` 行为、`shape` 对象类别 18 occ、MDLA0003 scalar、`halfmip` runtime bit、sound spatialization 运行语义、Timeline weight 优先级、renderContext 外 `thisObject` union——末项已经 D 官方页 `IThisPropertyObject.html` 关闭，见 §2.6 新增行）。我方项目 policy（tone mapping knee、delta clamp 0.25s、粒子 2 万上限等）只作边界证据不计入官方数值分母。
- **D 快照时效性结论（分母有效性）**：当日实拉 sitemap `/en/scene/` 恰 179 页，与 A 冻结快照**结构零增删**，45 effect 页与 6 组分组逐一在册吻合；GitBook 软 404 已验证（video/text/font-effects 无专节）。A 未引用的在册页（puppet-warp/extending、shader/mobile、assets/*、image-preparation/* 等）属 **A 的覆盖缺口而非官方改版**。**本次分母 = 179 页快照能力归并（424 项）∪ 官方站新发现 7 项 = 431 项**（§1/§6/§16 各 +1、§19 +2、§20 +2）；新发现行状态标「官方站新发现——台账无登记（即 L0 面）」，只增分母不增 L2/L1/L0 计数。
- **C 的方法与未统计面**：208/208 scene.json 直解（0 失败，与 census 快照逐类一致）＋ 引用既有机器快照；未统计面 = 效果「运行态实际执行 vs 静态声明」（需运行证据 join）、245 项效果全量矩阵（仅 top50）、puppet 层（并入 image 口径未独立分类）、媒体事件/专辑封面、输出 Bloom/RGB/HDR 声明、3D 模型层（C 的「model 引用」是 2D `models/*.json`，非 3D 模型层）、时钟 uniforms。
- **完成率列的粒度警告**：完成率 = B 台账 L2 行数 ÷ 官方全集项数。分子是台账登记行（实现机制粒度）、分母是官方能力项（能力粒度），二者**不一一对应**（例：特效分子 2 条是机制级，分母 45 是逐 effect 页；粒子分母取 171 细项口径）。完成率只作横向粗排序，**不是逐项 parity 声明**。
- 明细表「状态」列 = 所并入台账行的级别（指针，标注台账行号〔NNNN〕）；多个官方项并入同一台账行**不重复计数**；跨维引用（如时钟引文字维 Date 行）不计入本维计数。标「台账未单列」= B 无对应登记行，**不代表未实现**，仅代表无独立分级。〔站补 D#〕= 官方站补充合同注记（参数/合同级，16 条）；「D核」= 存疑/过时查证注记（12 条，A 原文不改）。

### 官方站口径差异说明（D §三，8 条）

1. SceneScript 全局对象：官方 reference 索引表 **7 个**（含 `thisObject`、无 `renderContext`），`localStorage` 归入"类"而非全局表但官方明文"global localStorage object"；A=8（含 renderContext、不含 thisObject）。本文 §2.6 行内注明双源。
2. 事件归类：官方事件索引列 17（无 `animationEvent`），后者记载于 Timeline 分节教程页；官方具名 handler 总数 18。A"19 槽"与其自身枚举 18 名不符，第 19 槽若来自 d.ts 应单独标注。
3. 粒子组件粒度：官方 7 组件页（材质设置并入 General 页）；A/我方台账 10 族（含 Instance Overrides、Particle Material、执行顺序）为更细归并，两侧不冲突——统计沿用 A 10 族/171 细项。
4. 类数量：官方 reference 索引 **36 类**（A ~34）；D 逐一亲核 18 个类页均实存（含 IAssetHandle/IThisPropertyObject/IConsole）。分母按 A 14 组口径不变，类数差异记注不调分母。
5. Bloom 归属：官方 effects/overview 明确 Bloom 独立分节不计入效果列表——与 A §11 归法**一致**（确认项）。
6. 效果分组：45=12+4+4+16+5+4 与官方同名同数同分组——**一致**（确认项）。
7. 相机属性归属：官方把 nearz/farz 作为 scene 属性（`IScene`），相机页只管 eye/center/up/FOV；A §8 将其并入"3D 相机"行——本文在 §2.8 加注、不改分母。
8. 用户属性内部名：官方 overview 载全 7 内部协议名（bool/combo/textinput/color/slider/texture/usershortcut），与 A §9 类型行一一对应；本文作站补注记。

## 1. 总览表

| # | 维度 | 官方全集项数 | L2 | L1 | L0 | 完成率% | 语料使用摘要（样本/occ） |
|---|---|---:|---:|---:|---:|---:|---|
| 1 | 图层与对象类型 | 18 | 2 | 0 | 0 | 11.1 | image 208/2539、text 104/958、particle 135/580、sound 61/79、utility 29/646、light 8/19、shape 12/18、camera 8/8 |
| 2 | 灯光 | 14 | 0 | 3 | 3 | 0.0 | light 8/19（castshadow 4/8、volumetrics 2/5、parented 5/8） |
| 3 | 粒子组件 | 171 | 24 | 19 | 1 | 14.0 | 135 样本/580 层；CP 6041、initializer 3557、operator 2460、emitter 843、renderer 806、children 826 occ |
| 4 | 特效/效果族 | 45 | 2 | 14 | 1 | 4.4 | effect 4107 occ/192 样本（shake 715、waterwaves 484、tint 296；跨 workshop 1159） |
| 5 | 材质能力 | 16 | 2 | 3 | 0 | 12.5 | texture 14725 occ/71 family、material 7519/49（引用快照，非 2D 专属） |
| 6 | SceneScript API | 15 | 0 | 16 | 1 | 0.0 | scenescript 3146 occ/116 样本；script wrapper 3355 occ |
| 7 | 音频 | 8 | 5 | 8 | 0 | 62.5 | audio-declaration 1778/155；材质频谱 1136/147；脚本音频注册 358/67 |
| 8 | 相机 | 11 | 1 | 1 | 0 | 9.1 | camera 层 8 样本/8 occ（parallax/shake 各 8 样本） |
| 9 | 用户属性系统 | 13 | 9 | 4 | 3 | 69.2 | 208/208 样本有用户属性；user-property 4800 occ/141 样本 |
| 10 | 媒体集成 | 10 | 1 | 8 | 1 | 10.0 | video-mp4 3 occ（引用）；媒体事件/封面未统计 |
| 11 | 输出（HDR/Bloom/RGB） | 11 | 0 | 2 | 3 | 0.0 | 未统计（Bloom/RGB/HDR 声明无语料数据） |
| 12 | 声音播放 | 5 | 0 | 2 | 0 | 0.0 | sound 层 61 样本/79 occ |
| 13 | 时钟与暂停 | 8 | 1 | 0 | 0 | 12.5 | 未统计 |
| 14 | Timeline 动画 † | 9 | 5 | 4 | 1 | 55.6 | timeline 296 occ/47 样本 |
| 15 | 文字（含字体效果） | 13 | 7 | 11 | 0 | 53.8 | text 层 104 样本/958 occ（静态非 hidden 632） |
| 16 | Puppet Warp | 14 | 2 | 4 | 0 | 14.3 | 未统计（puppet 层未独立分类） |
| 17 | 3D 模型 † | 10 | 0 | 2 | 2 | 0.0 | 未统计（C 的 model 引用为 2D models/*.json） |
| 18 | 合成/依赖/命名目标 | 8 | 0 | 7 | 0 | 0.0 | utility 29/646、composelayer 69/339、fullscreen 27/43、projectlayer 14/15 |
| 19 | 资源与纹理格式 † | 14 | 未单列 | 未单列 | 未单列 | — | texture 14725 occ/71（animated 39、static 2941、video 3）；slot resolved 6574/hole 3037 |
| 20 | Render Graph / Effect 机制 † | 12 | 未单列 | 未单列 | 未单列 | — | render-graph 4995 occ/27、shader 2864/327、render-target 589/8（引用快照） |
| 21 | 性能与分辨率策略 † | 6 | 0 | 0 | 1 | 0.0 | 未统计 |
| — | 补充：跨维度机制（生命周期/诊断/离线烘焙） | n/a | 1 | 2 | 2 | n/a | n/a（A 无对应官方维度行） |
| | **合计** | **431**（21 维） | **62** | **110** | **19** | **15.3**（62/405，19 个可计数维） | 台账口径 62/191 = 32.5%；全维口径 62/431 = 14.4% |

† 说明：B 原表 16+1 个维度对齐到 A 的 21 维时——**Timeline** 拆分自 B「属性」维度（B 自注「Timeline 归本维度」，其明细条目名可机械拆出用户属性 16 条 + Timeline 10 条，拆分只重排 B 既有状态、不新增裁决）；**3D 模型/性能策略** 拆分自 B「其他」维度（3D 4 条、Performance budgets 1 条，余 5 条进补充行）；**资源与纹理格式、Render Graph 机制** 的台账行并入材质/粒子/媒体/特效等维度登记，为避免重复计数不单列（逐项去向见 §2.19、§2.20）。未单列 ≠ 未实现。**官方站新发现 7 项已计入全集**（§1 Transform Layer、§6 thisObject、§16 Extending、§19 资产共享面+图像编辑工具族、§20 移动端 shader 合同+Effect 遮罩），其行不计入 L2/L1/L0。

## 2. 逐维明细

### 2.1 图层与对象类型（全集 18=17+新发现 1；B 图层维度 2 行）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Image Layer | L2〔1048〕 | 对象树/顺序/父子变换与可见性、alignment pivot | effect/pass duplicate、动态字段、Windows 逐像素 golden | 208 样本/2539 occ |
| Text Layer | L2（并入〔1048〕+文字维 7 条 L2） | 静态排版主链全链路（见 §2.15） | 字体效果、locale | 104/958 |
| Solid Layer | L2（并入〔1048〕） | solid 以 typed purpose 绘制 | — | solid 64/472 |
| Solid Placeholder | 台账未单列（并入 Scene IR 与属性 texture 替换） | scenetexture 属性 bounded 通路存在 | 动态替换语义未单列 | scenetexture 20/86 |
| Particle System layer | L2（并入粒子维〔1073〕） | root/child 模拟全链（见 §2.3） | 未接算子族 | 135/580 |
| Light layer | L1（并入灯光维 bounded direct-static） | ≤4 灯 typed snapshot + 直照 static model | 2D lit material 全缺（§2.2） | 8/19 |
| Camera layer | L2（并入相机维〔1075/1076〕） | parallax L2 + shake L1 | 3D 相机 bounded | 8/8 |
| Sound layer | L1（并入声音维〔1268〕） | FLAC/MP3/WAV、loop/single、volume | 0 L2（§2.12） | 61/79 |
| 3D Model layer | L1（并入其他维〔1099/1300〕bounded） | direct-static 模型绘制 | 骨骼/物理/attachment L0 | 未统计 |
| Puppet（image+puppet warp） | L2（并入 puppet 维〔1096/1291〕） | bind/CPU LBS/attachment pose 合同 | mixing、GPU skinning | 未统计 |
| Adjustable Composition Layer | L1（并入 composition 维〔1049〕） | bounded 子树合成 | nested/cycle、secondary 数据流 | composelayer 69/339 |
| Full Composition Layer | L1（并入〔1049〕） | projectlayer 随壁纸对齐 bounded | 同上 | projectlayer 14/15 |
| Post-processing Layer | L1（并入〔1049〕） | fullscreenlayer bounded | 同上 | fullscreen 27/43 |
| Built-in Post-processing Controller | 台账未单列（并入 composition/输出登记面） | — | — | 未统计 |
| Transform Layer（Add Asset 类型） | 官方站新发现——台账无登记（即 L0 面） | — | 挂脚本的纯变换层（官方教程 Add Asset）；corpus `shape` 类别是否同物**未定案，不合并** | shape 12 样本/18 occ（同物未定案） |
| dependency/hidden image provider | L1（并入〔1085〕命名 `_a`） | 隐藏图层发布为命名输入 bounded | secondary、history/resize | 未统计 |
| parent/child 层级与传播 | L2（并入〔1048〕） | 父子 transform/visibility 传播 | — | 未统计 |
| 对象通用状态（visible/alpha/…/effects[]） | L2（并入〔1048〕） | 有序绘制 + 通用作者状态 | 有序 effect 栈的任意拓扑（§2.4） | 未统计 |

### 2.2 灯光（全集 14；B 灯光维度 L1:3 L0:3；完成率 0%）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Point Light | L1〔1295〕 | ≤4 灯 typed snapshot + direct static-model diffuse，intensity live | 2D lit material、衰减 parity | lpoint+point 4/5 |
| Spot Light | L1〔1097/1294〕 | standalone 2D 投影锥、typed color/intensity、direct-static 加光 | 投影图/视频、lit material 交互 | lspot 3/9 |
| Tube Light | L1（并入〔1295〕，tube 在缺口列） | 通用灯 bounded 框架内 | tube 未接 | 0 occ |
| Directional Light | L1〔1295〕 | direct-static 消费 | 全场均匀照亮的 parity | ldirectional 3/5 |
| 最多 4 光源/场景 | L1（并入〔1295〕） | ≤4 typed snapshot 已实现 | 超额拒绝/降级策略未单列 | 8/19 |
| Ambient Lighting | L0〔1098〕 | 无 | ambient 进光照 | 未统计 |
| Skylight | L0（并入〔1098〕） | 无 | skylightcolor 消费 | 未统计 |
| 2D 材质受光开关 | L0〔1098〕 | image material 不响应光照 | lit material 全链 | 未统计 |
| Spot 投影纹理 | L0（并入〔1296〕缺口） | 无 | 图/视频/图层投影 | 未统计 |
| 阴影（2D/3D 双侧开关） | L0〔1296〕 | 无 | RT graph、depth/occlusion | castshadow 4/8 |
| Volumetric 光体积 | L0〔1296〕 | 无 | 体积光束 | castvolumetrics 2/5 |
| 2D Reflection | L0（并入〔1296〕） | 无 | 反射响应 + reflection map | 未统计 |
| 灯驱动（Timeline/Script/audio；Z 语义） | L1（并入〔1295〕） | user/SceneScript intensity live | Timeline/audio 驱动与 Z parity | 未统计 |
| 官方未知算法边界 | 台账未单列（分母只含能力名） | — | 数值算法官方未公开 | n/a |

### 2.3 粒子组件（全集 10 族/171 细项；B 粒子维度 44 行 L2:24 L1:19 L0:1）

| 组件族 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| General（18 细项） | L2〔1126/1164〕 | 执行子集、fixed step/seed/maxcount；字段 IR L1 | 未接字段、prewarm 预算；D核：fixed step/seed/visibility/pause 官方页未列（源 corpus/string-table） | definition/material 837 occ/135 |
| Emitter（17） | L2〔1127-1131〕 | schedule/launch speed/shape、Sphere/Box Random；Layer Image L1 | Layer Image 之外的第三型、audio bounds 细节 | emitter 843 occ/135（sphere 627、box 216） |
| Initializer（18） | L2〔1134/1165〕 | 已接子集 + Turbulent Velocity；HSV/Rotation/未接族 L1 | mapsequence*、inherit/event 族 | initializer 3557 occ/135 |
| Operator（29） | L1〔1138-1140〕 | movement/alphafade/sizechange 等已接子集 | Collision execution L0〔1156〕、vortex_v2/Boids/Cap Velocity 等未接 | operator 2460 occ/135 |
| Renderer（14） | L2〔1141-1145〕 | Sprite/Sprite Trail/Rope/Rope Trail 四 renderer | Windows 数值 golden | renderer 806 occ/134 |
| Control Point（12） | L2〔1146〕静态；L1〔1147-1149〕动态/指针 | 静态 CP L2；动态声明/执行、指针 L1 | 跨空间转换、gizmo；D核：angles 官方页未列 | controlpoint 6041 occ/134 |
| Children 与事件（12） | L2〔1150/1151〕 | child asset graph + 事件执行 | 执行/预算边界 | children 826 occ/49 |
| Instance Overrides（16） | L2〔1160〕静态；L1〔1162〕动态 | 静态覆盖 L2；动态覆盖 L1 | 全字段动态化；D核：brightness/color/CP angles 官方页未列（官方 Instance 页=alpha/size/count/speed/lifetime/rate/colorn/cp0–7） | 未统计 |
| Particle Material（22）〔站补 D23：粒子 Lighting 含 Double-sided；Cutout 区间重映射+目标不透明度〕 | L2〔1152/1163〕 | genericparticle 材质/blend、built-in 纹理 22 个 | Refraction 变体执行面、atlas metadata 细节 | particle 域 material 837 occ/135 |
| 执行顺序/生命周期（13） | L2〔1073/1153/1154〕 | emitter→init→op 主链、world-space、runtime 总行 | delta clamp/prewarm L1〔1166〕、实时/离线等价 | 未统计 |

### 2.4 特效/效果族（全集 45；B 特效维度 17 行 L2:2 L1:14 L0:1；完成率 4.4%＝机制级分子/逐 effect 分母）

| 能力（机制行） | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Effect execution evidence | L2〔1081〕 | EffectKey/owner/route/eligible-gap 分轴 Debug 报告、矩阵 7 字段 | shared completion ≠ 逐 stage GPU 成功，无视觉/长稳声明 | 4107 occ/192 样本 |
| Bounded effect executors | L2〔1082〕 | Program-first、typed previous-current 恢复、0 dedicated owner | 任意 compose/secondary/nested topology、Windows parity | 同上 |
| 14 条 L1 机制行 | L1 | Blend 子集〔1059/1215〕、Noise〔1083〕、FBO command graph〔1087〕、History RT〔1088〕、feedback swap〔1089〕、条件信号〔1090〕、shader path/contract〔1092/1093〕、Workshop Bloom 近似〔1299〕、ShaderContract〔1304〕、Resolved material〔1305〕、custom shader bounded〔1303/1306〕各有真实样本证据 | 任意 shader/FBO/condition 组合与官方 golden | 同上 |
| Arbitrary custom shader execution | L0〔1094〕 | 严格单 pass framebuffer 子集 | 通用翻译/映射/资源分级 | 跨 workshop effect 1159 occ |

逐 effect 执行等级**台账未单列**（B 按机制族登记）。官方 45 项 effect 的语料频次（内置，occ 降序，两列排版）：

| effect | occ | effect | occ |
|---|---:|---|---:|
| shake | 715 | waterwaves | 484 |
| tint | 296 | opacity | 216 |
| foliagesway | 144 | blend | 108 |
| xray | 90 | pulse | 74 |
| iris | 73 | waterripple | 66 |
| waterflow | 58 | scroll | 52 |
| depthparallax | 44 | blurprecise | 40 |
| fisheye | 39 | spin | 38 |
| godrays | 34 | blur | 34 |
| twirl | 32 | shine | 31 |
| transform | 28 | perspective | 26 |
| localcontrast | 26 | reflection | 23 |
| vhs | 21 | blendgradient | 18 |
| lightshafts | 18 | shimmer | 18 |

其余 17 项官方 effect 未进语料 top50（occ < 12）：cloudmotion、swing、motionblur、blurradial、cursorripple、fluidsimulation、chromaticaberration、clouds、colorkey、filmgrain、glitter、fire、nitro、watercaustics、refraction、skew、edgedetection。D核：`_empty` 内部占位官方无页面，联网亦未发现——维持（D 存疑 12）。

### 2.5 材质能力（全集 16；B 材质维度 5 行 L2:2 L1:3）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 材质 Lighting 启用 | L0（并入灯光〔1098〕） | 无 | lit material | 未统计 |
| 材质 Reflection 启用 | L0（并入灯光〔1296〕列） | 无 | 反射响应 | 未统计 |
| Normal map〔站补 D22：官方生成器参数面=Shape/Details 共 8 参数，editor-only〕 | L0（2D，并入〔1293〕）；3D 并入〔1300〕 | 3D bounded direct-static 内消费 | 2D PBR slot | 未统计 |
| Metallic map/slider | L0〔1293〕（2D） | 无 | 2D 金属度 | 未统计 |
| Roughness map/slider | L0〔1293〕（2D） | 无 | 2D 粗糙度 | 未统计 |
| Reflection map/slider | L0〔1293〕（2D） | 无 | 2D 反射强度 | 未统计 |
| Emissive | L0（2D）；L1（3D 并入〔1300〕bounded） | 3D direct-static 内 | 2D emissivebrightness | 未统计 |
| 3D 材质通道全集 | L1〔1300〕 | bounded direct-static 模型材质 | 完整通道 parity | 未统计 |
| genericimage2/4 LIGHTING combo | L0（并入〔1098〕） | 无 | 受光变体键 | 未统计 |
| Stock 模型 shader：Fur | 台账未单列（3D bounded 内无独立行） | — | — | 未统计 |
| Stock 模型 shader：Vegetation | 台账未单列（同上） | — | — | 未统计 |
| Stock 模型 shader：Chroma | 台账未单列（同上） | — | — | 未统计 |
| 粒子材质变体（Cutout/Lighting/Refraction/overbright） | L2（并入粒子〔1163/1152〕） | genericparticle combo 族执行 | Refraction 背景采样执行面 | 未统计 |
| Blend 模式 + render state | L2〔1163〕 | material/blend 状态执行 | 其他 blend 变体 | 未统计 |
| 纹理槽 0…7 + combos + constants | L1〔1280/1305〕 | 8 槽 Template/Program bounded | 完整 schema、动态 provider 固定点 | slot resolved 6574/hole 3037（引用） |
| 3D LUT（32³ volume TEX） | L0（LUT consumer 为〔1047〕缺口列） | TEX 容器与资源索引 L2 支撑 | LUT consumer 未接 | 未统计 |

### 2.6 SceneScript API 面（全集 15=14 组+新发现 thisObject；B 脚本维度 17 行 L1:16 L0:1；完成率 0%）

| 组 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 全局对象（8） | L1（并入〔1218/1220〕） | QuickJS-NG 单 domain VM | shared/localStorage 逐对象验收；D核：官方全局表 7（含 thisObject、无 renderContext），localStorage 明文 global——renderContext 仅 d.ts | 未逐组统计（维表 3146 occ/116 样本） |
| 事件槽（19）〔站补 D18：cursor 事件仅 Solid 标记对象生效；cursorClick 在 Down+Up 之后触发〕 | L1〔1219/1222/1267〕 | init/update/destroy、cursor、user/audio/media 事件 | 完整槽位覆盖表未单列；D核：官方索引 17（无 animationEvent，载于 Timeline 教程页），具名 handler 18，"19"与 A 自身枚举不符 | 同上 |
| 值/数学类（Vec2…Mat4） | L1（并入〔1220〕） | Math 基础 | Vec4/矩阵类 | 同上 |
| 内容句柄类（ILayer/IModel…）〔站补 D8：ILayer setParent 双载（含 puppet attachment 名）、getAttachmentIndex/Matrix/Origin/Angles、rotateObjectSpace、parallaxDepth: Vec2〕 | L0〔1223〕 | typed handles 未开放 | 图层/效果/粒子/模型句柄族 | 同上 |
| 动画/媒体句柄类〔站补 D9：addEndedCallback 实为 IAnimationLayer（另有 blend/visible、blendin/out/blendtime/autosort）；IVideoTexture 有 getCurrentTime/setCurrentTime/addEndedCallback、无音量。站补 D23：ITextureAnimation.join() 重挂共享动画态〕 | L1（并入〔1063/1064〕） | ITextureAnimation bounded 后继 | IVideoTexture/AnimationEvent 族 | 同上 |
| 模块（WEMath/WEColor/WEVector）〔站补 D20：`import * as WEColor` 语法；脚本色为 0–255 Vec3（shader 侧 g_Color 才归一）。站补 D23：WEMath 官方面恰为 smoothStep/mix/deg2rad/rad2deg〕 | L1（并入〔1220〕） | Math 子集 | Color/Vector 模块 | 同上 |
| timers | L1〔1224〕 | setTimeout/setInterval 返回取消函数 | clearTimeout（官方也未实现） | 同上 |
| localStorage〔站补 D10：100KB/wallpaper 上限；用户 Reset 即清空；LOCATION_SCREEN/GLOBAL〕 | 台账未单列（并入〔1064〕bounded） | VM 基座存在 | 两作用域 API 验收 | 同上 |
| engine 状态查询 | L1〔1220〕 | engine globals 子集 | timeOfDay 等逐字段 | 同上 |
| engine 音频注册 | L1〔1266〕 | registerAudioBuffers bounded | resolution 档位 parity | 358 occ/67 样本 |
| input | L1〔1061/1065-1067〕 | cursor 轮询/按钮/edge 事件 | — | 同上 |
| 动态层/资产〔站补 D12：registerAsset(file,precache) 第二参、支持材质/粒子/模型/声音/字体、file 须硬编码字符串（拼接破坏 Android 导出）。站补 D13：createModelData vertexFormat=[POSITION,NORMAL,UV]+TANGENT_SIGNED（bitangent sign 须 -1）、dynamic 缺省抛错、applyData 逐帧/replaceData 仅事件回调内、indexBuffer Uint16 CCW（跨 §17）〕 | L1〔1052/1053/1056〕 | 动态 text/image 层、binding program | createModelData/applyData 族 | 同上 |
| 场景属性 setter〔站补 D19：init/update 值进值出、返回 number 自动扩散 Vec2/Vec3、不返回不改属性、engine.runtime float 回卷（计时用 setTimeout）〕 | L1〔1056〕 | property binding IR | bloom/clearcolor/camera setter 族 | 同上 |
| Puppet/粒子脚本 | L1（并入 puppet 骨骼 API 系列） | 骨骼 local 读写、pose 原子性 | IParticleSystem、angles/impulse/reset | 同上 |
| thisObject 全局（IThisPropertyObject） | 官方站新发现——台账无登记（即 L0 面） | —（A 脚注「union 未定案」据此关闭：类型随绑定目标动态，仅 getAnimation(name?) 一法） | 实现无登记 | 未统计（并入 script wrapper 3355 occ 口径） |

### 2.7 音频（全集 8；B 音频维度 13 行 L2:5 L1:8；完成率 62.5%，全维最高）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| AudioBuffers 16/32/64 | L2〔1261〕16 档；L1〔1262〕32/64 | 唯一 tap/analyzer 共享快照 | 32/64 数值 parity | 注册 358 occ/67 样本 |
| shader 音频 uniforms | L2〔1263/1070〕 | effect consumer + resolved-material arrays | 官方 FFT 数值 | 材质频谱 1136 occ/147 样本 |
| Effect audio response | L2〔1263〕 | 16 bins effect 消费闭环 | include=false 切换、长稳 | 107 occ/31 样本 |
| 粒子 audio response | L1〔1259/1257/1258〕 | schema + 声明 | 执行 parity、missing-mode 19 occ | 75 occ/16 样本 |
| 灯光音频驱动 | L1（并入灯光〔1295〕intensity live） | 脚本强度调制通路 | 数值 parity | 未统计 |
| Audio Visualizer overview | 台账未单列（官方建设中） | — | — | 未统计 |
| 声音自采集进频谱 | L1〔1260/1268〕 | 系统音频 daemon、sound 共享 tap | 本地声音独立幅度 | audio-declaration 1778 occ/155 样本 |
| 音频驱动 Timeline/属性 | L1（并入〔1222/1266〕） | audio 事件 + 绑定 bounded | 任意属性音频响应 | 未统计 |

### 2.8 相机（全集 11；B 相机维度 2 行 L2:1 L1:1）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Camera Parallax | L2〔1075〕 | 作者门 + 层级传播/阻断、4 个 direct User Property live | mouse influence zero 反例、zoom、3D、多屏 | 8 样本 |
| per-layer parallax depth | L2（并入〔1075〕） | 逐轴深度传播 | —；D核：父子传播官方页无载，语义靠 sem/实现取证 | 未统计 |
| Oversized Image 视差 | L2（并入〔1050/1075〕） | cover 投影 + 视差门 | 多比例探索 | 未统计 |
| Scene Camera Shake | L1〔1076〕 | 静态值 + 4 属性 typed snapshot、2D 正交 live | perspective XYZ、官方 pause/seek | 8 样本 |
| 2D 相机 path（origin/zoom） | L1（并入〔1076〕缺口列 zoom） | 2D 正交路径 bounded | zoom、Combined | 未统计 |
| 3D 相机（eye/center/FOV） | L1（并入〔1099〕camera bounded） | bounded | 全参数；D核：官方相机页仅 eye/center/up/FOV，nearz/farz 官方载体是 IScene（scene 属性） | 未统计 |
| 相机 path 序列（random/sequential） | 台账未单列（并入〔1099〕） | — | Loop/Mirror 不结束语义 | 未统计 |
| 正交投影 | L2（并入〔1050〕画布/cover） | cover 投影与作者画布 | — | 未统计 |
| 填充/裁切（cover/crop/stretch） | L2〔1050〕 | cover 投影、未覆盖区不露灰底 | 多比例、多屏 | 未统计 |
| camerafade | 未定案（A 脚注，不入数值分母） | d.ts 声明；D核：存在性升级——官方 IScene.html 明文 `camerafade: Boolean` | 行为仍未公开，脚注保留 | 未统计 |
| 相机层 live 切换 | 台账未单列 | — | — | 8/8 |

### 2.9 用户属性系统（全集 13；B 属性维度拆分 A：16 行 L2:9 L1:4 L0:3；完成率 69.2%，全维第一）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| bool / Checkbox〔站补 D23：官方内部名 7 个（bool/combo/textinput/color/slider/texture/usershortcut）与本表类型行一一对应〕 | L2〔1235〕 | 独立 UI 窗口/持久化/条件 | Windows 数值 | 125 样本/1103 occ |
| Slider | L2〔1234〕 | live 数值 | — | 94/891 |
| Combo（label+hidden value） | L2〔1236〕 | condition + conditionalValueDomainsByPropertyKey 完整 domain | — | 49/161 |
| Text Input | L2〔1237〕 | live 文本 | — | 32/110（text 类型 39/686） |
| Color | L1〔1233 bounded〕 | bounded 通路 | 超出 bounded 的形态 | 208/664 |
| Texture（texture/scenetexture） | L1〔1238 bounded〕 | bounded 通路 | 完整替换语义 | scenetexture 20/86 |
| Texture Variants | L0〔1242〕 | 无 | 变体组切换 | 未统计 |
| User Shortcut | L0〔1239〕 | 无 | engine.openUserShortcut | 2/37 |
| Group | L2〔1240〕 | 线性分段 | — | 37/163 |
| Display Condition | L2（并入〔1240〕） | key.value==literal | — | condition 1034 occ/51 样本 |
| 一 key 多 target fan-out | L2〔1232〕 | catalog/bindings 广播 | —；D核：官方 overview 未载 fan-out，实际出处 userproperties/color.html（"Multiple effects can also share a single property"） | user_bindings 4890 occ |
| 属性绑定五源 | L1〔1212/1277〕 | user/timeline/script 三源接通 | album cover/attachment 源 | user-property 4800/141、scenescript 3146/116、timeline 296/47 |
| 求值优先级（authored→property→Timeline→Script） | L2〔1054/1241〕 | Atomic live property routing、reset/default/override | mixed/SceneScript binding；D核：优先级官方页未载（出处应为 sem/d.ts），官方仅记载禁 Timeline 与 Script 同绑一属性 | 未统计 |

### 2.10 媒体集成（全集 10；B 媒体维度 10 行 L2:1 L1:8 L0:1）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 内嵌视频帧管线（对应 A §19 内嵌 MP4 TEX） | L2〔1269〕 | 共享 frame timing/registry/pause 保帧/stop 释放 | seek、热插拔、loop 首帧、A/V parity | video-mp4 3 occ |
| $mediaThumbnail | L1〔1272/1273〕 | thumbnail identity + purpose-qualified publication | live producer（platform-policy） | 未统计 |
| $mediaPreviousThumbnail | L1（并入〔1273〕） | previous 封面 purpose 通路 | — | 未统计 |
| 封面五色 | L1〔1270/1271〕 | 五色 typed 事件 | 跨类型全局顺序 | 未统计 |
| Playback 状态 | L1〔1270〕 | 三态 typed 事件 | — | 未统计 |
| Properties 七字段 | L1〔1270〕 | title/artist 等七字段 | 缺失字段语义 | 未统计 |
| Status 事件 | L1〔1271〕 | 可用性枚举 | — | 未统计 |
| Timeline 事件 | L1〔1271〕 | position/duration 秒 | — | 未统计 |
| 封面切换配方 | L1（并入〔1273〕bounded） | current+previous 组合 bounded | 官方配方逐元素 | 未统计 |
| stopped vs paused 可见性 | 台账未单列 | — | — | 未统计 |
| 媒体文字排版约束 | L2（并入文字〔1255/1257〕） | point size/限行限宽/省略号 + 动态文字 | — | 未统计 |
| （B 行）Video/system generic producer | L0〔1278/1279〕 | identity 登记 | 通用 provider lifecycle | 未统计 |

### 2.11 输出（全集 11；B 输出维度 5 行 L1:2 L0:3；完成率 0%）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Scene Bloom 标准模式〔站补 D11：需用户 post-processing≥enabled；编辑器恒按 HDR 预览（须双配置验证）〕 | L1〔1299〕 | Workshop Bloom approximation | 官方 target binding 未分类 | 未统计 |
| Ultra HDR Bloom〔站补 D11：需用户端 Ultra 档〕 | L0（并入〔1298〕） | 无 | scene post HDR pipeline | 未统计 |
| Bloom 参数面（10 参数） | L1（并入〔1299〕） | 近似参数子集 | 全参数 parity；D核：官方页仅 strength/threshold+HDR 4 参数（strength/scatter/threshold/threshold smoothing），无 tint/feather——10 参数源自 string-table，两源并列 | 未统计 |
| Scene HDR（general.hdr） | L1（流水 2026-09-27） | RGBA16Float 统一选型并贯通 Bloom/CAMetalLayer | tone mapping、官方 parity | 未统计 |
| per-layer HDR brightness〔站补 D11：可超滑条上限，text/particle 亦有〕 | 台账未单列（并入 HDR 颜色精度行） | 颜色目标精度基座 | 逐层能量 | 未统计 |
| Tone mapping / 显示映射 | L0（并入〔1298〕缺口） | 无 | 官方曲线（未公开）、EDR knee | 未统计 |
| EDR 扩展动态范围 | L0（并入〔1298〕缺口） | 无 | headroom 线性输出 | 未统计 |
| Video HDR | L1（并入〔1278〕typed output-mode identity） | 输出模式 identity 登记 | 执行面 | 未统计 |
| 多屏 / resize / 显示变化 | L0（多屏为〔1050/1075/1076〕共同缺口） | 单屏 cover/resize 基座 | 多屏、热插拔 | 未统计 |
| clear color / clear enabled | 台账未单列（并入〔1048〕Scene IR） | 场景清屏基础 | 作者背景色 parity | 未统计 |
| RGB 设备输出（iCUE/Chroma）〔站补 D23：limit-to-layer 多层启用时仅最上层生效〕 | L0〔1100/1307〕 | 无 | macOS 策略、授权、adapter | 未统计 |

### 2.12 声音播放（全集 5；B 声音维度 2 行 L1:2；完成率 0%）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| Sound layer〔站补 D17：Android 端壁纸无音频播放（help FAQ 平台约束）〕 | L1〔1268〕 | FLAC/MP3/WAV、loop/single、多音源取首个、volume/pause/stop、共享 tap | 本地独立幅度、官方 FFT 数值、全集 census | 61 样本/79 occ |
| 音量属性绑定 | L1（并入〔1268〕volume live） | volume 通路 | — | 未统计 |
| ISoundLayer API | L1（并入〔1268〕bounded） | play/pause/stop/isPlaying 面向 | 完整 API parity | 未统计 |
| Sound 空间化 | 台账未单列（A 脚注：官方仅 changelog 字段族） | — | 运行语义未定案；D核：官方站确认无专页——维持 A 定级（changelog/string-table 唯一载体） | 未统计 |
| 随机播放/环境声 | 台账未单列（loop/single 已接，随机未列） | 双模式播放 | 随机调度 | 未统计 |
| （B 行）三引擎主音量/静音 | L1（流水 2026-09-22） | IPC/registry 乘法链 + 持久化 | 实机电平、ROI | 未统计 |

### 2.13 时钟与暂停（全集 8；B 时钟维度 1 行 L2:1；Date/delta 状态引自其登记维度）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| g_Time / g_Frametime / g_Daytime | L2（并入〔1051〕） | raw/simulation/dropped/discontinuity 时钟 | 逐 uniform 消费面验收 | 未统计 |
| engine.timeOfDay | 台账未单列 | — | 24h 归一输入 | 未统计 |
| ECMAScript Date | L1（并入文字维〔1221〕bounded new Date()） | bounded | 任意回滚 | 未统计 |
| Scene pause/resume | L2〔1051〕 | 冻结 scene time、resume 不补帧 | 真实系统 pause/sleep、seek | 未统计 |
| Timeline 时基（Seconds/Frames） | L2（并入〔1055〕） | typed playback | 目标 FPS | 未统计 |
| 粒子固定步进 + prewarm | L2〔1164〕步进；L1〔1166〕prewarm | per-fixed-step 主路径 | prewarm 预算 | 未统计 |
| Texture/Video/Puppet 共用 SceneClock | L2（并入〔1051/1269〕） | 60Hz 单 driver 统一时钟 | Windows timing golden | 未统计 |
| delta clamp / dropped time | L1（并入粒子〔1166〕，0.25s 项目 policy） | 长帧截断 | 官方常量未公开 | 未统计 |

### 2.14 Timeline 动画（全集 9；B 属性维度拆分 B：10 行 L2:5 L1:4 L0:1）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 关键帧/property/axis target | L2〔1203〕target；L1〔1204〕tangent | 逐通道 target typed 执行 | Bézier tangent 全形态 | timeline 296 occ/47 样本 |
| Loop / Mirror / Single | L2〔1205/1206〕 | 三模式 evaluator | — | 同上 |
| Bézier handle（both/left/right/none） | L1〔1204 bounded〕 | bounded 切线 | 全 handle 形态 | 同上 |
| Wrap loop frames | L1〔1208〕 | 首尾闭合 bounded | — | 同上 |
| Start paused | L2〔1207〕 | 初始暂停 | — | 同上 |
| Combined Animations | L1〔1210〕 | 跨 property 组合 bounded | 完整复用设置 | 同上 |
| Animation Events | L0〔1211〕 | 无 | 指定帧触发、同帧多个 | 同上 |
| IAnimation/IAnimationLayer 播放控制〔站补 D9：addEndedCallback 落点为 IAnimationLayer（IAnimation 页无之）〕 | L2〔1055〕 | 唯一 playback owner、fps/rate/frame seek、ended callback | — | 同上 |
| animationEvent handler | L0（并入〔1211〕） | 无 | 同层脚本接收（官方载于 Timeline 教程页，不在事件索引——见口径差异 2） | 同上 |

### 2.15 文字（全集 13；B 文字维度 18 行 L2:7 L1:11）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 静态栅格/package+system 字体 | L2〔1249/1250〕 | CoreText 栅格、8 别名+stock 三级 fallback | Windows 栅格 golden、locale/DST | text 104 样本/958 occ |
| point size（300 DPI 换算） | L2〔1251〕 | authoredPointSize×300/72 夹 [1,1024] | — | 同上 |
| horizontal/vertical alignment | L2〔1253〕 | pivot+padding 排版 | — | 同上 |
| Screen anchor | L2〔1254〕 | 九锚点 | — | 同上 |
| padding / opaquebackground | L2〔1253〕padding；opaquebackground 台账未单列 | 边距 | 底色 | 同上 |
| Limit rows / width / ellipsis | L2〔1255〕 | 换行省略号 | —；D核：limituseellipsis 官方类页（15 属性）无之，仅 string-table/d.ts（"Overflow ellipsis" 编辑器选项官方在 audiovisualizer/mediainformation 有载） | 同上 |
| baseline / blockalign | L1〔1252〕 | baseline/alignment bounded | —；D核：baseline/blockalign 官方类页无，仅 string-table/d.ts | 同上 |
| 颜色/alpha 动态重栅格 | L2〔1257〕 | direct property 无重建更新 | — | 同上 |
| MSDF 字体管线 | 台账未单列（CoreText 栅格替代） | — | MSDF atlas/彩色字体二通道；D核：官方站确认无 text/font-effects 专页（软 404 已验）——维持 A 定级（changelog/string-table 唯一载体） | 同上 |
| Font Effect：Outline | L1〔1256〕 | outline/shadow/text effects bounded | 完整效果 | 同上 |
| Font Effect：Drop Shadow | L1（并入〔1256〕） | 同上 | 同上 | 同上 |
| Font Effect：Blur | L1（并入〔1256〕） | 同上 | 同上 | 同上 |
| ITextLayer API | L1〔1258 + 流水文字鼠标事件〕 | SceneScript clock/text、点击回归 | 完整 API 面 | 同上 |

### 2.16 Puppet Warp（全集 14=13+新发现 1；B puppet 维度 6 行 L2:2 L1:4）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| mesh/bone/weight 导出消费 | L2〔1291〕 | MDLV0014/16/17/19/23 严格 rig + CPU LBS | MDLV0014 动画 | 未统计 |
| Character Sheet 重组 | L2（并入〔1096〕atlas mapped extent） | atlas 精确 graph | depth order 重排 | 未统计 |
| Timeline 动画（TRS、三模式） | L2〔1096〕 | bind/单 clip/layered | 冲突 mixing 权重、GPU skinning | 未统计 |
| Attachments | L2（并入〔1291〕） | attachment + cursor/Script 共用 pose 合同 | point-property attachment | 未统计 |
| Clipping Masks | L1（并入 composition 维 resolvedMaterial 路径） | Clipping 走 resolvedMaterial | 可嵌套/环非法全语义 | 未统计 |
| Texture Channels | 台账未单列 | — | 同分辨率叠加/opacity 动画 | 未统计 |
| Bone Constraints（Spring/Rigid/Rope） | L1〔1292 表记 L0→流水 09-10/09-28 取最新〕 | 平移 spring/rigid 拖拽回弹 + impulse 部分 | 完整 solver、rope/wind、确定性 golden | 未统计 |
| Inverse Kinematics | 台账未单列（constraints 行缺口未点名） | — | chain/target/orientation | 未统计 |
| Interactive（SceneScript 读写 bone） | L1（流水 2026-09-28 骨骼 API） | local 读写、原子 pose、Scalar/String 命令 | angles/impulse/reset、多 owner 回滚 | 未统计 |
| Perspective（painted depth） | 台账未单列 | — | 2D 网格伪 3D | 未统计 |
| Blend Shapes | 台账未单列 | — | shape/expression weight | 未统计 |
| Blend Rules | 台账未单列 | — | bone 权重切换 parent | 未统计 |
| Animation Mixing | 台账未单列（〔1096〕缺口列 mixing 权重） | — | 多 clip duration/rate 合并 | 未统计 |
| Puppet Warp Extending（角色表扩展） | 官方站新发现——台账无登记（即 L0 面） | — | 已动画化 puppet 重导入右/下扩边放大角色表并保留原动画（1.7 及更早项目可能失败） | 未统计 |

### 2.17 3D 模型（全集 10；B 其他维度拆分：L1:2 L0:2；完成率 0%）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| FBX/OBJ 导入（-Z/+Y、scale normalize） | L1〔1300 bounded〕 | bounded direct-static 模型/节点/材质 | 完整导入约定 parity | 未统计（C 的 model 引用为 2D models/*.json） |
| 2D/3D 模式 | L1〔1099 model bounded〕 | bounded 放置 | 3D 场景全模式 | 未统计 |
| 模型材质通道 | L1〔1300〕 | direct-static 材质消费 | 完整通道（见 §2.5） | 未统计 |
| 相机（path/random+sequential） | L1〔1099 camera bounded〕 | bounded | path 序列、Loop/Mirror | 未统计 |
| Animation（clips/root motion）〔站补 D21：Add FBX File 多动画合并，须相同骨骼层级〕 | L0〔1301〕 | 无 | 骨骼动画 | 未统计 |
| Attachment（bone 挂点） | L0（并入〔1301〕） | 无 | 模型挂接 | 未统计 |
| Fog（distance/height） | 台账未单列 | — | 双雾模式 | 未统计 |
| Lighting（3D：shadow/volumetric） | L1（并入灯光〔1295〕direct-static）/shadow、volumetric L0 | direct-static diffuse 消费 | per-model shadow、volumetric | 未统计 |
| Stock shaders（Fur/Vegetation/Chroma） | 台账未单列 | — | — | 未统计 |
| Simulation（骨骼物理） | L0〔1302〕 | 无 | presets/advanced、与 animation 混合 | 未统计 |

### 2.18 合成/依赖/命名目标（全集 8；B composition 维度 7 行全 L1；完成率 0%）

| 能力 | 状态 | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 三种 utility composition | L1〔1049〕 | compose/project/fullscreen bounded | nested forward/cycle | utility 29/646、composelayer 69/339、fullscreen 27/43、projectlayer 14/15 |
| 命名 target `_a`（primary） | L1〔1084/1085〕 | bounded 生产/消费、placement-exact geometry | history/resize/device-loss | 未统计 |
| 命名 target `_b`（secondary） | L1〔1086/1275/1276〕 | secondary identity 登记 | secondary 数据流 | 未统计 |
| dependency layer IDs / 跨层引用 | L1〔1274〕 | layer/named target provider | 通用跨层资源边 | 未统计 |
| `previous`（layer-local 双缓冲） | L2（并入特效〔1082〕typed previous-current） | 恢复链 | 任意 compose 拓扑 | 未统计 |
| `_rt_FullFrameBuffer` | 台账未单列 | — | 全帧 alias flag | render-target 589 occ/8 family（引用） |
| 自引用/隐藏边语义 | L1（并入〔1091〕source preparation） | 依赖图守卫 | — | 未统计 |
| RGB composition | L0（并入〔1100/1307〕RGB L0） | 无 | 像相机捕获下方层 | 未统计 |

### 2.19 资源与纹理格式（全集 14=12+新发现 2；**台账未单列维度**——各行并入其登记维度，不重复计数）

| 能力 | 状态（并入处） | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| PKG 打包 + loose VFS | L2（并入材质〔1047〕） | loose/PKG/stock 统一查找 | 跨进程 lock | texture 14725 occ/71 family（引用） |
| TEX 容器（TEXV0005 族） | L2（并入〔1047〕） | 官方容器解析 | — | 同上 |
| BC 压缩（DXT1/5、BC2；BC5 候选） | L2（并入〔1047〕） | BC1/2/3 | BC5 | 同上 |
| POT physical/mapped size | 台账未单列（并入〔1047〕口径内） | padding 补齐基础 | 逐项验收 | 同上 |
| mip 链 | L2（并入〔1047〕mip 链权威） | 编译 mip 序列权威 | — | 同上 |
| sprite 序列 / atlas | L2（并入粒子〔1159〕Sprite Sheet） | Sequence/Random Frame、frame blending | — | 同上 |
| 内嵌 MP4 视频 TEX | L2（并入媒体〔1269/1071〕） | AVPlayer 唯一 owner、pause 保帧 | seek、loop 首帧 | video-mp4 3 occ |
| sampler 状态（nointerpolation/clampuvs） | L2（并入粒子 sampler 四态） | linear/nearest × clamp/repeat 四态 | — | 同上 |
| 3D LUT volume TEX | L0（LUT consumer 为〔1047〕缺口） | 容器支撑 | consumer 未接 | 未统计 |
| 内置 stock 资产（SceneStockAssets） | L2（并入粒子〔1152〕） | 确定性遮罩生成、stock key 消费 | — | 同上 |
| VRAM 预算（300/500MB） | L0（并入〔1104〕Performance budgets） | 无 | 预算执行 | 未统计 |
| 压缩建议（发布优化） | 台账未单列（编辑器侧建议，非运行能力） | — | — | 未统计 |
| 资产创建与工坊共享面（authoring） | 官方站新发现——台账无登记（即 L0 面） | — | View→Enable Asset Creation 后共享 layers（含依赖打包 asset pack）/effects/scripts 三类到工坊 | 未统计 |
| 编辑器内建图像编辑工具族（editor-only） | 官方站新发现——台账无登记（即 L0 面） | — | Foreground Separation（笔刷/多边形、tolerance/quality、背景模糊填充）、Character Sheet Creation、External Editor 往返（Quick Save 重载） | 未统计 |

### 2.20 Render Graph / Effect 机制（全集 12=10+新发现 2；**台账未单列维度**——并入特效/材质维度登记）

| 能力 | 状态（并入处） | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| FBO 定义（scale/format/clear/unique/uvs） | L1（并入特效〔1087〕+材质〔1080〕IR） | definition/pass 保真建图 | 任意组合 | render-graph 4995 occ/27 family（引用） |
| ordered passes（material ordinal） | L1（并入〔1087〕） | ordinal 对齐 bounded | — | 同上 |
| bind{name,index,conditions} | L2 slot 绑定（并入材质〔1078〕）/L1 FBO | slot-binding 原子 | conditions 全形态 | 同上 |
| copy command | L1（并入〔1087〕） | 像素复制 bounded | 不耗 ordinal parity | 同上 |
| swap command | L1〔1089〕 | preserved-channel feedback swap | ping-pong 全形态 | 同上 |
| raw compose（layer-local 双缓冲推进） | L2（并入特效〔1082〕bounded）/L1 外围 | bounded compose 执行 | 任意 compose 拓扑 | 同上 |
| condition（combo 准入剪枝） | L1〔1090〕 | component/whole-vector/independent-signal | — | 同上 |
| definition function（clear action） | L1（并入〔1304〕ShaderContract） | 命名函数调用 bounded | — | 同上 |
| shader 方言（[COMBO]/texSample2D）〔站补 D14-16：common*.h 头文件库（M_PI 族/DecompressNormal(DXT5n)/BuildTangentSpace/ApplyBlending+imageblending combo）；顶点属性全集（a_Tangent4、附加通道 C1–C5、无 #elif、GLSL/HLSL/HLSL_SM40 等 defines）；uniform/常量官方全表（g_PointerPosition(Last)/g_TexelSize/g_Screen/g_Color4/g_ParallaxPosition/矩阵族/g_TextureN{Resolution,Rotation,Translation}、sampler JSON 选项、用户 uniform 三型 slider/color/UV Picker）〕 | L1〔1092/1093〕 | path identity + source contract | 完整方言翻译 | shader 2864 occ/327 family（引用） |
| shader [PASS] token | 台账未单列（3D shadow 路径未接） | — | frontend metadata | 同上 |
| 移动端 shader 双目标编译合同 | 官方站新发现——台账无登记（即 L0 面） | — | DX11 HLSL4.0 + GLSL ES 3.00 双目标、CAST/texSample2D(Lod) 等别名族、`WEMOBILE_DISABLE_INTEGER_CONVERSION`、无 `#elif`；移动端编译失败→效果静默移除壁纸继续运行；须真机测 ES | 未统计 |
| Effect 遮罩种类（Opacity Mask / Flow Map / RGB mask） | 官方站新发现——台账无登记（即 L0 面） | — | uniform `mode`: opacitymask/rgbmask/flowmask 三种逐层限域遮罩通道 | 未统计（并入 effect 语料口径） |

（遮罩项 D 给出 §4/§20 两候选；因 §4 分母定义为官方 effect 逐页 45 项、mask 属 shader uniform 机制，本文归 §20。）

### 2.21 性能与分辨率策略（全集 6；B 其他维度拆分：L0:1，其余并入或未单列；完成率 0%）

| 能力 | 状态（并入处） | 已实现要点 | 缺口要点 | 语料 |
|---|---|---|---|---|
| 分辨率分类（common/portrait/Other） | 台账未单列（发布分类，非运行白名单） | — | — | project type：scene 157/Scene 51 |
| 任意分辨率可接受（cover crop） | L2 bounded（并入图层〔1050〕；多比例在其缺口列） | cover 投影不露灰底 | 多比例、多屏 | 未统计 |
| VRAM 300/500MB 阈值 | L0〔1104〕 | 无 | 预算执行 | 未统计 |
| DXT 压缩建议 | L2（并入材质〔1047〕BC1/2/3） | 压缩纹理消费 | BC5 | 同上 |
| 灯光/反射性能告警（4 灯上限） | L1（并入灯光〔1295〕≤4 snapshot） | 4 灯内执行 | 超额拒绝策略 | light 8/19 |
| volumetric 昂贵告警 | 台账未单列 | — | 成本策略 | 未统计 |

### 2.22 补充：跨维度机制（A 无对应官方维度；B 其他维度拆分剩余 5 行）

| 能力 | 状态 | 已实现要点 | 缺口要点 |
|---|---|---|---|
| Stop/switch lifecycle | L2〔1103〕 | surface=0 与部分资源释放门、teardown exact-once | VM/provider/GPU 细粒度计数与长稳 |
| Debug PNG readback（×2 表行） | L1〔1101/1308〕 | 同一样本跨提交比较 | 跨样本/自动比对 |
| Offline bake（×2 表行） | L0〔1102/1309〕 | 无 | 离线烘焙管线 |

## 3. 交叉洞察

### 3.1 高使用 × 低完成 = 优先缺口 top10

| # | 能力 | 语料使用 | 状态 | 缺口 |
|---|---|---|---|---|
| 1 | 特效逐项执行（shake 715/waterwaves 484/tint 296 领衔） | 4107 occ / 192 样本 | 逐项未分级；机制 L1、任意拓扑 L0 | bounded 外 compose/secondary/nested 与 arbitrary custom shader |
| 2 | 粒子动态/指针 Control Point | 6041 occ / 134 样本 | L1 | 动态 CP 执行、跨空间转换 |
| 3 | SceneScript API 面 | 3146 occ / 116 样本 | 0 L2；typed handles L0 | 内容句柄类、完整 API |
| 4 | 粒子未接 operator 族 | 2460 occ / 135 样本 | 子集 L1；collision L0 | Collision solver、vortex_v2/Boids 等 |
| 5 | 用户属性 color/texture + Variants | color 664 occ/208 样本 + scenetexture 86 | color/texture L1；Variants L0 | bounded 外形态、变体组 |
| 6 | composition/命名目标 | utility 646 + composelayer 339 occ / 29+69 样本 | 0 L2（7 行全 L1） | secondary 数据流、nested/cycle |
| 7 | Timeline Animation Events | timeline 296 occ / 47 样本 | L0 | 指定帧触发、animationEvent handler |
| 8 | 2D lighting 全链（lit material/阴影/反射） | light 19 occ + castshadow 8 occ / 8 样本 | 全 L0 | PBR maps、shadow/reflection/volumetric |
| 9 | Sound layer | 79 occ / 61 样本 | L1（0 L2） | 独立幅度、官方 FFT |
| 10 | 粒子 audio response | 75 occ / 16 样本 | L1 | 执行 parity、missing-mode 19 occ |

注 1：Audio 32/64 bins（注册 358 occ/67 样本，L1）同属该模式，因 AudioBuffers 维度整体 62.5% 居首而列注。注 2：官方站新发现 7 项均为 L0 面且语料低（Transform Layer≈shape 12/18，同物未定案）或未统计，**不改变 top10 构成**；仅 §1/§6/§16 完成率分母 +1（图层 11.8%→11.1%、puppet 15.4%→14.3%，排序不变）。

### 3.2 L2 完成 × 语料零/低使用 = 待实机验收或低频能力

| 能力 | 状态 | 语料 | 解读 |
|---|---|---|---|
| Embedded MP4 frame | L2 | video-mp4 仅 3 occ | 主链完成但语料极少，验收靠代表样本 |
| Camera Parallax（含 per-layer depth） | L2 | 8 样本/8 occ | 低频但官方核心交互，需实机验收 |
| Puppet runtime 全族（runtime/rig/attachment） | L2 | 未统计（未独立分类） | 语料面缺失，优先补 puppet 层普查 |
| Frame Context / pause / SceneClock | L2 | 未统计 | 时钟无语料面，验收靠运行证据 |
| Stop/switch lifecycle | L2 | 未统计 | 同上 |
| 文字字体三级 fallback / Timeline runtime | L2 | text 104/958、timeline 47/296（中等） | 已有中频使用，验收可顺带 |

### 3.3 量级冠军（语料侧）

- **覆盖之最**：model 引用 207/208 样本（1402 occ + 跨 workshop 283 occ）；用户属性 208/208 样本全覆盖（color 单类 208 样本）；image 层 208/208（2539 occ）。
- **occurrence 之最**（引用快照大类）：particle 16787 occ/704 family > texture 14725/71 > material 7519/49 > dynamic-input 9487/396 > render-graph 4995/27 > effect 4107/15；组件级：粒子 controlpoint 6041 > initializer 3557 > operator 2460。
- **单项之最**：effect shake 715 occ（第 2 名 waterwaves 484）；跨 workshop effect 引用 1159 occ（占 4107 的 28.2%）——通用执行缺口直接影响近三成 effect 声明。
- **结构比**：script wrapper 3355 occ/116 样本对脚本 API 0 L2，是「高使用×零完整实现」的最大单点。

## 4. 数字自洽校验

- 全集 Σ = **431**（21 维求和：快照口径 424 + 官方站新发现 7：§1 +1、§6 +1、§16 +1、§19 +2、§20 +2）；可计数 19 维全集 = **405**（402+3，新发现落在未单列维 §19/§20 的 4 项不增计数维分母）；总完成率 62/405 = **15.3%**（可计数维）、62/431 = **14.4%**（全维）、62/191 = **32.5%**（台账口径，D 并入不变）。
- L2/L1/L0 列求和 = 62/110/19，合计 191 = B 总表 ✓；新发现 7 行状态=「官方站新发现——台账无登记」，只增分母不增分子分母计数列 ✓。逐维：属性拆分（9+5, 4+4, 3+1）= B 属性 26 ✓；3D 4 行 + 性能 1 行 + 补充 5 行 = B 其他 10 ✓；粒子 44、特效 17、材质 5、脚本 17、音频 13、媒体 10、文字 18、puppet 6、composition 7 与 B 原维一致 ✓。
- §2.19、§2.20 无独立计数（并入处已标注），避免与 §2.3/2.4/2.5/2.10 重复求和；明细表状态为台账行指针，多项并入同一行不重复计数。
- 语料侧 208/208 解析、对象 kind 与 census 快照逐类一致（C 自验）；本文引用 occ 均出自 C 表或 incremental-stats.json，未做二次推断。D 注记（站补 16 + D核 12 + 口径差异 8）只作标注，不改任何 A/B/C 计数。

---

*派生统计快照，非登记文件；任何登记变更以 `docs/scene/semantics/coverage-ledger.md` 为准。官方站差异依 D 普查（2026-10-02，72 URL 内容级亲核）。*
