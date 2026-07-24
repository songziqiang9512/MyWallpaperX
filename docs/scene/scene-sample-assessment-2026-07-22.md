# Scene 21 个用户样本能力与视觉评估（2026-07-22）

> 本文保留 2026-07-22 的逐样本视觉基线，不再作为当前能力表。现役支持等级、官方能力缺口和下一公共依赖统一查 [Scene 官方语义与实现覆盖台账](semantics/coverage-ledger.md)；本页只有“当前增量覆盖”会随代码纠偏，历史截图表不重写。

## 结论

这批 21 个隔离样本已经全部能进入 Scene 播放流程；这只证明入口识别、包解析、进程存活、非黑画面和资源释放门没有阻断，**不代表画面已经与 Wallpaper Engine 一致**。下列 P0/P1/P2 数量是 2026-07-22 首轮截图基线，早于后续的属性、粒子和文字修复，不应再当成当前精确分布。

按首轮运行截图和作者预览逐个比较后，结果为：

- P0（主构图不可用或明显错误）：5 个；
- P1（主图可辨认，但核心动态、文字、粒子或组合语义缺失）：12 个；
- P2（主体可用，仍有明确的次级效果差距）：4 个；
- P3（仅小幅视觉偏差）：0 个。

首轮评估确认的方向仍成立：优先建设通用 runtime，而不是增加按样本命中的 effect 分支。截至 Shake/preview 批次的历史增量已包含 authored graph、typed texture registry/property fallback、ShaderContract、B0 binding program/per-surface snapshot、direct dynamic text、六个 strict backend、ordered strict chain、同帧 copy/swap、受限 history、Precise Blur interleave/legacy compose 与 exact stock Shake；后续能力不在本历史页逐批追记。Timeline、SceneScript、system/media text producer、Texture Variants、通用/effectful/nested provider、真实 persistent/history、generic compose、其余 effect 和高级粒子仍是主要缺口。精确当前基线只在 [总覆盖台账](semantics/coverage-ledger.md) 维护。

## 范围与证据

- 样本源：`.codex/scene-user-samples-20260722/Scene`。它是用户真实 Workshop 目录的隔离副本；本轮没有写入 `~/Movies/MyWallpaperX/创意工坊/Scene`。
- 20 个 `scene.json` 样本的运行结果：[report.json](../../.codex/scene-visible-effect-full20-20260722/report.json)；人工总览：[contact-sheet.png](../../.codex/scene-visible-effect-full20-20260722/contact-sheet.png)。报告为 20/20 PASS，运行 App 为 `2.0.8 (268)`，签名 Team 为 `H9QWU9XN8R`。
- `3766415113` 使用 `gifscene.json` / `gifscene.pkg`，以包含 entry、sequence 和单图 UV 修正的 [gifscene 最终报告](../../.codex/scene-gifscene-sprite-gate-20260722/report.json) 为准。
- `3738202317` 在 20 样本旧报告中因 `.tex format 6` 显示灰底；该结果已经被 [BC2/DXT3 修复后报告](../../.codex/scene-bc2-format6-final-20260722/report.json) 覆盖，当前为 1/1 纹理加载成功。
- “作者预期”来自包内 scene 描述、`project.json` 属性和样本自带 preview。`3194ac5` 已把 preview reference、中心裁切运行截图、分项指标和并排图接入固定门；preview 仍不是逐帧金标准，最终仍需在相同分辨率、相同属性默认值下与 Wallpaper Engine 录屏做差异验收。
- 首轮 21 样本报告保留为修复前视觉基线；现役提交、正式矩阵、签名与测试总数统一查 [运行证据索引](semantics/runtime-evidence-index.md)，本历史评估不再复制易过期的全局状态。

表中 `I/P/T` 分别表示 image / particle / text 图层声明数量；`prop` 不含每个项目都有的 `schemecolor`。纹理加载率只统计当前 renderer 识别为 image candidate 的图层，不应直接当成视觉完成度。

## 当前增量覆盖

| 能力 | 当前已验证 | 仍未覆盖 |
| --- | --- | --- |
| 用户属性 | bool/slider/combo/color/textinput、group/condition/options；独立窗口和持久化；PNG/JPEG `sceneTexture`；layer alpha、solid color、direct text 三字段、Local Contrast strength 与 Opacity alpha 通过 per-surface snapshot 无重建更新 | 21 样本旧 census 尚未按 v22 重算；hidden/no-consumer text、SceneScript/time/media、Texture Variants、video/general material、transform、particle/audio、puppet 继续重建或 fail closed |
| Solid | 固定 built-in 与 model `solidlayer:true`；共享白纹理、作者 color/alpha/visibility/effect/blend；当前正式门 54/54 | 带动态 `$mediaThumbnail`/sceneTexture 的 solid 实例；普通 image 基础 color multiplier；完整 dependency/mask 组合语义 |
| Utility / Composition | typed composition/project/fullscreen；framebuffer 前缀捕获；局部/full-frame geometry；受限纹理池；mask/partial effect fail-closed；290 的 project 410 / composition 530 与 6 个 named provider / 7 个 consumer 已完成 GPU capture/binding；registry 按 identity/status/generation 选择首个 ready 候选；293 的 providers 141/1340、consumers 299/322 与隐藏 image providers 到 layers 239/657/775/875/1509 的静态 blend 已进入 GPU runtime；受限 property file provider 已接入 | system/media/video/Texture Variants、effectful provider、nested/child target、utility mask、动态 blendgradient 与任意 material/shader pass；不能把受限 named-target/static image 子集写成完整 dependency graph |
| Particle | 包内 texture、sprite sheet、9 个精确 built-in key、continuous/burst schedule、常见 initializer/operator、additive/translucent、Sprite Trail、静态 override、fixed-step/seed/budget 子集；正式门 14/27，`3750813609` 为 7/9 | 21 样本仍有 22 个 built-in texture unavailable；atlas/multi-texture、child runtime、rope/rope trail、world-space、动态 control point/override、collision、音频与属性 operator |
| Text | 当前以 authored `pointsize * 4` 近似官方 300 DPI point raster，处理 vector padding、包内字体、系统字体别名和确定性 fallback 诊断；`3766387484` 3/3、`3122339805` 80/81、`2134765860` 4/6 candidate | 精确 DPI/scene-unit 校准、SceneScript、真实时钟/日期/媒体值、完整对齐/描边/阴影/effect 语义 |
| 自动门（截至 Shake/preview 批次） | 26 样本完整快照与固定 13 样本回归门，interpretation format 22，签名 App、Metal 双帧；六个 strict backend、ordered chain、B0 property、dynamic text generation、provider/file override 与粒子合同；固定门 13/13 均有非阻断 preview 并排图；297 项 Scene 测试为 294 通过、3 跳过；无 timeout、stop 后 surface=0 | 当时 26 门为 3 条 Blur/Shake chain、16 个 legacy blocked layer、64 个 route-only；固定门另保留 1 条 Blur/Shadow chain、2 个 blocked、30 个 route-only；preview 不设绝对阈值且不能跨样本排名，仍没有 Windows WE 同配置录屏差异门 |

## 横向能力判断

### 声明驱动，而不是全局默认

- 明确开启相机视差的样本是 `2802243144`、`2902406982`、`2938612768`、`3750342273`、`3750813609`、`3766387484`；其中部分还受项目属性控制。
- `3768229922` 的视差由属性绑定且默认关闭；其余样本默认不得产生相机视差。
- `2902406982` 有两处 waterwaves 声明但默认均关闭；`3765760121` 的 particle 默认关闭。它们是防止“有能力就全部打开”的负向回归样本。
- 全量报告中的 `camera_parallax` 已能反映上述多数作者默认值，但项目属性的条件、运行时切换和 effect uniform 绑定尚未形成完整闭环，因此还不能只凭日志字段宣称完成。

### Particle

21 个样本中有 18 个声明 particle，共 60 个 root layer、55 个可达 definition 和 77 个 child 引用。当前 renderer 已有作者包内 2D sprite、9 个精确 built-in key、常见 emitter/initializer/operator、Sprite Trail、sprite sheet 与静态 override 子集；正式 13 样本门加载 14/27，其中 `3750813609` 为 7/9，`3765760121` 的默认隐藏 particle 保持不创建。21 样本仍有 22 个 built-in texture unavailable；child graph 只递归发现不实例化，world-space、rope、动态 control point/override、collision 和音频驱动仍未执行。不能用“已有粒子”概括成完整支持。

### 项目属性与详情面板

14/21 个样本声明了自定义项目属性；424 definition、952 binding 与 199 unsupported target 是 v22 前的旧 census，未重算前不得写成当前精确覆盖率。详情页只保留“属性调节”按钮并打开独立窗口。B0 已让 layer alpha、solid color、direct text content/point-size/color、Local Contrast strength 和 Opacity alpha 在同一 surface/window 上更新；动态文本只处理有效可见 direct binding，hidden/no-consumer 与 SceneScript/time/media 仍重建或 fail closed。Texture Variants、video/general material、transform、particle、puppet 尚未闭环。

### Text 与字体

13/21 个样本共声明 258 个 text layer。当前 CoreText 路径以 `pointsize * 4` 近似官方声明的 300 DPI point raster，并处理 vector padding、包内字体和系统字体别名；`3766387484` 的非均匀 scale 静态几何已明显接近 preview，但该倍率仍需 Windows 官方输出校准。`3750813609` 的 200pt 时钟仍是过大的黑色静态占位，说明字号几何修正并未闭合最终字体、颜色和 effect 语义。未知 SceneScript 不执行，时钟、日期、媒体信息和随机文本仍是静态值，对齐、描边/阴影和 effect pass 也未完整复刻。`3750813609`、`3766387484`、`3122339805` 继续作为大字号、非均匀缩放和 100 层压力三类文字基准。

Camera Parallax 的当前负向合同已经补齐：包括 composition 在内，layer 缺失 `parallaxDepth` 或两轴均为零时不产生逐层位移；composition 类型本身不隐含任何视差深度。位移归一化和 delay 曲线仍需 Windows golden 校准。

## 五个重点样本的当前增量状态

- `2802243144`：`e505a9e` 已让未修改样本 layers `[41,64,115]` 的 exact stock Shake 与 Blur Precise 按作者前后顺序进入 GPU；succeeded `[41,64,115]`、failed `[]`、Shake 3、chains 3、stages 6，warm-run changed ratio 约 `0.00977...0.01031`。这修正了首轮“定时双帧无运动”的旧结论，但雪粒子、系统时间/日期 producer、dynamic Shake/audio/noise/direction 和 Windows WE 时序/像素 parity 仍未闭合。
- `3724289844`：当前 authored graph succeeded `[20,28,36]`、failed/blocked `[]`、stages 4、chains 1；layer `20` 的 exact `Blur Precise -> Shadow` 是首条真实 fully-supported strict chain，layers `28/36` 保持 precise Blur singleton。该 Shadow 只按完整 Workshop definition/material/ShaderContract/render-state/combo/static-parameter 合同准入，属于 exact Workshop `L3 executed-degraded`，不代表官方 45 项 Effect 表的通用 Shadow 或 generic shader。`common_blending` mode 0 无官方像素 oracle，当前没有 WE pixel-equivalence 结论。
- `2902406982`：当前 image 30/30、text 44/57、particle 1/1；6 个 named provider capture 与 7 个 consumer binding 全部成功，layers `167/177` 的 Local Contrast、`530` 的 standard Blur 与 `[365,372,647,664]` 的 stock Opacity 均进入 GPU；`newproperty50=0.2` 可 live 更新而不替换 surface/window。三角区域已经采到对应内容，旧截图中的无依据白色三角和背景重复叠影不再是当前现象；字体/文字层、SceneScript、媒体/音频和剩余属性驱动仍不完整。
- `2938612768`：当前 image 44/44、text 8/24、particle 0/1；wrapped alpha、named providers/consumers 和 static image blend 5 层均成功，中央播放器与静态封面已出现。Opacity candidates `[165,454,626,629,924]` 使用 SceneScript 值，当前保持 Opacity/stages 0，不能误写成 direct-binding 正例。属性纹理未绑定时仍回退作者资源；系统媒体封面/标题/时间仍无 producer。另有 1 个 named-target gap、18 个 route-only 诊断，waterwaves 近似、blendgradient、音频和 `particle/chromaticdot` 仍未闭环，当前整体画面仍明显失真。
- `3750813609`：当前 image 2/2、text 1/1、particle 7/9；layers `121/200/90/504/511/516/498` 已加载，其中新增 fog/leaves/light shafts/lightning/halo 是确定性程序近似，不是官方纹理。layers `523/530` 因 world-space 保持 fail closed，121/504/511 仍有 child 诊断。layer `358` 的非默认 Blur+Clouds 图继续 blocked；动态时间脚本、Clouds 和完整文字效果未实现，时钟仍是过大的黑色静态 `12:34`。
- `2998757800`：定向粒子门为 image 5/5、particle 7/15；6 个 `rainperspective` built-in 雨层 172/181/187/193/199/205 与原有作者层 287181 同时绘制，雨幕已覆盖作者声明的多个深度层。其余 8 个粒子层、6 个雨层的动态 `instanceoverride`、天气/触摸、puppet 与完整 foliage/waterripple/xray 语义仍缺失；当前主图和雨可用，不代表交互与天气壁纸已经复刻。

## 首轮逐样本评估（历史基线）

严重度定义：P0 为主内容不可接受；P1 为可识别但核心体验缺失；P2 为主体可用但有明显差距；P3 为可延后微调。下表保留修复前截图结论，已被“当前增量覆盖”命中的属性、粒子和文字描述不再代表 HEAD；待 21 样本重跑后再统一重分级，避免只改少数行造成伪精确。

| 样本 | 入口与作者关键能力 | 首轮显示状态 | 主要缺口 | 严重度 | 推荐验收点 |
| --- | --- | --- | --- | --- | --- |
| `2134765860` Bunk | `scene.json`；42 层，I33/P1/T8，effect 79，prop 33；audio bars/ring、时钟日期、blur/waterwaves；parallax 关 | 房间主构图完整；image 12/33、text 4/6；双帧运动 0 | 大时钟、日期、音频可视化和部分装饰层缺失或尺寸过小；大量 built-in/组合资源未落地 | P1 | 默认无视差；时钟按真实时间更新且字号/位置与 preview 接近；开关 audio ring 后才出现对应效果；无音频时稳定，受控频谱时有响应 |
| `2419444134` Nier Reincarnation - Akeha | `scene.json`；10 层，I5/P4/T0，effect 13，prop 5；fog、audio dots/stars、neon、waterwaves；parallax 关 | 人物和霓虹环完整，image 5/5；仅有极低双帧变化 | 4 个粒子系统及音频响应缺失，fog/星点开关无属性链 | P1 | 默认无视差；5 个属性逐项控制对应层；星点、雾和音频粒子分别可见，关闭后完全停止且不残留 |
| `2802243144` 冰公主 | `scene.json`；12 层，I5/P2/T4，effect 8，prop 13；雪、时钟日期、precise blur；parallax 0.1 与 camera shake 受属性控制 | 首轮主图完整但定时双帧无运动；当前 exact stock Shake 已使 layers 41/64/115 形成 3 条 Blur/Shake chain，changed ratio 约 1% | 雪粒子、系统时间/日期和 dynamic Shake/audio/noise/direction 仍缺；当前不是 WE 时序/像素 parity | P1 | 默认属性值决定视差和 shake，不得强开；鼠标注入时视差幅度受 0.1 限制；雪粒子、时间/日期和位置滑杆均可单独验证 |
| `2902406982` 麻匪 月半与鬼哭 | `scene.json`；140 层，I41/P1/T97，effect 115，prop 172；大量 mask/composite、动态文字、音频 bars、可换背景；parallax 0.5；两处 waterwaves 默认关 | image 21/41、text 44/57；画面被大块白色三角形遮挡，主体布局与 preview 明显不同；双帧无运动 | 组合层/内建 solid/mask 语义、13 个文字 candidate、SceneScript、属性和音频链均不完整 | P0 | 首帧不得出现无依据白块；默认 waterwaves 必须保持关闭；172 项属性按 order/group/condition 生成；背景、文字、颜色和音频条的代表性绑定可切换并持久化 |
| `2938612768` 麻匪 音频识别 Media Player | `scene.json`；85 层，I51/P5/T29，effect 73，prop 78；媒体播放器、scene texture、audio bars、depth parallax/waterwaves；parallax 0.5 | image 33/51、text 8/24；大面积灰底，播放器只剩局部白色组件，和 preview 的彩色完整布局不一致；双帧无运动 | 18 个 image candidate、16 个 text candidate、组合/solid、动态媒体信息、scene texture、粒子和音频响应缺失 | P0 | 无灰底裸露且主播放器构图闭合；默认属性可复现作者首帧；受控曲目元数据、封面和频谱能更新；视差只按作者幅度生效 |
| `2998757800` 碧蓝航线-利托里奥 | `scene.json`；22 层，I5/P15/T1，effect 22，prop 2；touch/weather、foliage、waterripple、puppet；parallax 关 | 主图完整，image 5/5、text 1/1；双帧变化约 16.2% | 15 个粒子、天气状态、触摸交互和 puppet 语义未实现；当前运动不能证明这些能力存在 | P1 | 默认无相机视差；两个属性只控制作者绑定内容；pointer 注入产生局部触摸响应；天气/粒子切换可见且停止后清理；主图不被全局水波扭曲 |
| `3028090166` WLOP Tian Nan2 | `scene.json`；12 层，I9/P2/T1，effect 20，prop 1；waterflow/waterripple/waterwaves、godrays、foliage、puppet；parallax 关 | 主图完整，image 8/9；有约 5.7% 双帧变化，默认隐藏文字未绘制 | 一处 built-in/后处理层缺失；水链多为近似或 route-only；粒子、godrays 和 puppet 不完整 | P1 | 默认无视差；隐藏文字保持隐藏；水面局部 mask、waterflow、ripple 分别与 WE 对照；2 个粒子和 godrays 可单独启停且无全屏误作用 |
| `3122339805` Pixels | `scene.json`；190 层，I90/P0/T100，effect 17，prop 38；桌面窗口、世界时钟、倒计时、自定义图片、audio bars；parallax 关 | image 6/90、text 80/82；灰底上只有两个大图块和散落文字，窗口布局严重断裂 | 84 个 image candidate 多为 built-in/solid/组合资源；动态文字仍是 `00`/默认值；属性、自定义图片和音频未绑定 | P0 | 主要窗口边框、层级和遮罩完整，不出现灰底散件；100 text layer 压力下字号/对齐稳定；世界时钟、倒计时、自定义图片和三组 scene texture 可操作并持久化 |
| `3290491250` frieren | `scene.json`；5 层，I3/P1/T1，effect 3，prop 0；星点粒子、动态 Day 文本、precise blur；parallax 关 | image 2/3、text 1/1；人物可见但背景为灰色，preview 中的 `MONDAY` 与星点构图未还原；双帧无运动 | built-in solid/文字组合和粒子缺失；动态星期脚本不执行 | P1 | 默认无视差；背景、人物、星期文字和星点形成完整构图；星期随系统日期更新；粒子有稳定数量上限并能释放 |
| `3738202317` Albedo. | `scene.json`；1 层，I1/P0/T0，effect 4，prop 0；BC2/DXT3 纹理、waterripple；parallax 关 | 后续报告已为 image 1/1，3840x2160 主图正确显示；约 3.3% 双帧变化 | format 6 阻断已修复；剩余是 waterripple 原始 mask/pass 与当前近似实现的视觉一致性 | P2 | BC2 alpha 与 padded block crop 做像素门；默认无视差；只在作者 waterripple mask 内产生位移，与 WE 同分辨率录屏比较幅度和边界 |
| `3742133044` 凌霄·双司镇命·无常&lt;1&gt; | `scene.json`；4 层，I2/P2/T0，effect 5，prop 2；waterflow、foliage、iris、雪粒子；parallax 关 | 主图完整，image 2/2；双帧变化约 16.3% | 1 个默认有效 particle 及部分 waterflow/foliage 语义缺失；combo 属性没有 UI/绑定 | P2 | 默认无视差；两项 combo 只切换作者定义状态；雪粒子数量、方向和遮挡正确；waterflow 限于作者 mask，不影响人物面部 |
| `3743305891` 战双 | `scene.json`；8 层，I3/P1/T3，effect 4，prop 0；child particle、rope trail、动态日期/时间、audio；parallax 关 | 主图和纹理完整，image 3/3、text 3/3；双帧变化约 63.4%，但作者 preview 的日期与音频条布局未可靠还原 | SceneScript、字体布局、child/rope particle graph 和音频响应缺失 | P1 | 默认无视差；日期时间值、字号、基线和位置与 WE 对齐；受控音频驱动 bars；child 粒子和 rope trail 有确定性截图与生命周期门 |
| `3750342273` Night snowy mountains | `scene.json`；8 层，I2/P1/T4，effect 6，prop 0；waterflow、shake、时钟日期、粒子；parallax 0.14 | 主图完整，image 2/2、text 4/4；中央文字过小/近似乱码，双帧无运动 | 动态文字和字体 fallback/scale 错误；粒子、水流及相机行为未达到作者效果 | P1 | 鼠标注入验证 0.14 视差；时钟日期在相同分辨率下与 preview 的占位和字号一致；粒子/水流只按声明运行，不附加额外 ripple |
| `3750813609` Asian Temple in the Mountains | `scene.json`；13 层，I2/P9/T1，effect 5，prop 2；200pt 时钟、雨/云/叶粒子、depth parallax；parallax 0.1 | image 1/2、text 1/1；背景可用，但时钟发生多重叠影且尺寸远小于 preview；双帧变化约 33.3% | 9 个粒子系统和一处 image 缺失；文字度量/绘制刷新错误；属性开关未连接 | P1 | 200pt 时钟单次清晰绘制、无残影；12/24 小时切换正确；雨、叶、云分别可见；0.1 视差不与粒子漂移混淆 |
| `3757555836` 名将杀 兰汤春酽_赵姬 | `scene.json`；9 层，I2/P7/T0，effect 9，prop 2；waterflow/waterripple、xray、7 粒子；parallax 关 | 主图完整，image 2/2；仅约 3.1% 双帧变化 | 7 个粒子系统缺失；水流/ripple/xray 仍是部分近似；属性滑杆没有绑定 | P1 | 默认无视差；粒子分层、blend 和遮挡与 WE 对照；滑杆只改变绑定参数；水效果不得越过作者 mask 或改变未声明区域 |
| `3765760121` 4K 三色堇与她 | `scene.json`；13 层，I6/P1/T6，effect 12，prop 8；clock/date、audio bars、组合层、glitter；parallax 关；particle 默认关 | 主图完整但 image 3/6；text 3/3 可绘制；precise graph layers 68/76/82 GPU succeeded，隐藏 190/196/202 未执行 | 动态时钟/日期、audio bar、glitter、组合和完整字体效果仍不完整 | P1 | 默认无视差且 particle 保持关闭；用户显式开启后才创建粒子；时钟日期值、字体、位置正确；combo/bool/slider 的 8 项属性均有可见绑定 |
| `3766387484` ARKNIGHTS ENDFIELD ARCANE CHEN XIANGYU | `scene.json`；7 层，I1/P1/T3，effect 13，prop 14；叶片、眼睛、光线、waterflow、depth parallax；parallax 0.06 与 shake 受属性控制 | 主图完整，image 1/1、text 3/3；文字缩得很小并堆在人物中央；双帧变化约 10.2% | point size 与非均匀 layer scale 组合错误；粒子、眼睛、光线和 14 项属性绑定缺失 | P1 | 默认值精确决定 parallax/shake；三层文字的字号、缩放、对齐和层级与 preview 对齐；叶片、眼睛、光线可分别开关，不互相代替 |
| `3766415113` The last pour | `gifscene.json` + `gifscene.pkg`；1 层，I1/P0/T0，effect 0，prop 0；320x200 authored scene；parallax 关 | 入口和纹理 1/1 已加载，但 3200x1600 纹理被重复平铺成网格，画面不可用；上下黑边存在 | sampler/UV 与 10 倍纹理尺寸语义错误。作者 layer scale 约 `1.00471 x 0.86814`，上下黑边是作者构图，不应靠强制 cover 消除 | P0 | 最终只出现一幅完整瓶子画面，不重复采样；保留作者缩放产生的上下黑边；默认无视差、无水波；用边缘采样和重复图案检测锁定回归 |
| `3767232084` 谬因 | `scene.json`；3 层，I1/P2/T0，effect 7，prop 0；waterflow、foliage、shine、puppet；parallax 关 | 主图完整，image 1/1；双帧变化约 1.4% | 2 个粒子和 puppet 缺失；foliage/waterflow/shine 只覆盖部分语义 | P2 | 默认无视差；发光生物粒子、局部水面与角色层遮挡正确；pointer 不应触发未声明的全局效果；停止后粒子资源归零 |
| `3767343314` Universe Abstract | `scene.json`；4 层，I1/P3/T0，effect 3，prop 0；waterripple、cursor ripple、星点粒子；parallax 关 | 月球主图完整，image 1/1；约 5.8% 双帧变化 | 3 个星点粒子缺失；cursor ripple 和 waterripple 尚未按输入、mask 与衰减精确复刻 | P2 | 静止鼠标时无额外相机视差；pointer 移动/点击只产生局部 cursor ripple；星点密度稳定；水面 ripple 不影响天空几何线条 |
| `3768229922` 麻匪 赤芒 音频互动 | `scene.json`；58 层，I52/P2/T0，effect 74，prop 33；音频互动、depth parallax、water、mask/composite、puppet/scripts；parallax 属性绑定且默认关 | image 28/52；当前只停留在 `PSYCHE GEAR` 标题画面，双帧无运动，实际角色构图没有进入 | 24 个 image candidate、组合/脚本状态机、音频、粒子、puppet 和属性链缺失；默认阶段/可见性无法推进 | P0 | 默认首帧最终进入作者主场景而非永久停在 splash；parallax 默认严格关闭，属性开启后才生效；受控音频产生可量化响应；33 项属性和脚本状态切换不出现灰底或残层 |

## 首轮开发与回归顺序及进度

1. 截至 Shake/preview 批次，P0 通用根因已关闭基础 layer/resource、290/293 命中的受限 dependency 子集，并完成 EffectDefinition/authored graph、六个 strict backend、ordered strict effect-chain、Blur/Shadow 与 Blur/Shake 真实 chain、typed registry/property fallback、file-backed `sceneTexture`、统一 Frame Context 第一阶段和首批 built-in 粒子纹理；后续当前状态统一查覆盖台账。
2. B0 binding program、per-surface transaction/snapshot 与 layer alpha、纯 solid color、exact Local Contrast strength consumer 已完成，不再列为当前待启动项。
3. `3724289844:20` exact Workshop Shadow、stock Opacity `MASK=0` live alpha 与 `2802243144` exact stock Shake 已完成；封面方向性视觉门也已作为非阻断证据落地。六样本人工复核中，拼图直接暴露 `2902406982` 的错乱构图、`2938612768` 的过度水波形变和 `3750813609` 的字体/颜色差异；`3742133044` 又证明不同 preview 裁切会让完整画面取得较低数值。因此下一项按结构化样本 census、完整链解锁、同一样本拼图/分项变化和实现成本选择，不以 route-only 或跨样本分数代替能力缺口。
4. B1 并行补 Provider Core 的 metadata/cancellation，再扩 Texture Variants、video/system/media、通用 material、effectful/nested/child source；B2 后续接 persistent/history、material-command interleave 与 compose。
5. 静态 text geometry/font 已通过现有门，但动态时间/日期/媒体、Windows 字号/baseline、完整效果与 100 层最终性能门仍留到共享动态链和 B4 fidelity 阶段统一处理。

每一步都应同时保留两类门：一类证明声明的能力确实出现，另一类证明未声明或默认关闭的效果不会被全局套用。所有样本仍从真实 Workshop 复制到隔离 root，并使用临时 HOME 运行；流程 PASS、非黑截图和加载率只能作为底线，不能替代与作者 preview/Wallpaper Engine 的视觉对照。
