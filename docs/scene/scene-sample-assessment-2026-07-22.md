# Scene 21 个用户样本能力与视觉评估（2026-07-22）

## 结论

这批 21 个隔离样本已经全部能进入 Scene 播放流程；这只证明入口识别、包解析、进程存活、非黑画面和资源释放门没有阻断，**不代表画面已经与 Wallpaper Engine 一致**。下列 P0/P1/P2 数量是 2026-07-22 首轮截图基线，早于后续的属性、粒子和文字修复，不应再当成当前精确分布。

按首轮运行截图和作者预览逐个比较后，结果为：

- P0（主构图不可用或明显错误）：5 个；
- P1（主图可辨认，但核心动态、文字、粒子或组合语义缺失）：12 个；
- P2（主体可用，仍有明确的次级效果差距）：4 个；
- P3（仅小幅视觉偏差）：0 个。

首轮评估确认的方向仍成立：优先建设通用 runtime，而不是增加按样本命中的 effect 分支。此后属性主链、基础 layer/resource、受限 dependency/effect/particle 执行器、EffectDefinition、v16 authored graph、strict precise/standard Blur 默认 profile graph backend，以及 v17 的首个 typed texture registry/property authored-fallback 切片已落地。renderer 仍只消费两个严格 Blur graph 子集和若干受限 executor；动态脚本/文字、实际文件或媒体 sceneTexture provider、Texture Variants、effectful/nested provider、utility mask、其余内建效果和高级粒子仍是主要缺口。底层作者/执行合同查 [Scene 语义手册](semantics/README.md)，现有开发顺序和架构约束见 [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md)；Web 与 Scene 的统一状态入口见 [Web / Scene 当前状态与路线图](../reviews/web-scene-current-state-roadmap-2026-07-19.md)。

## 范围与证据

- 样本源：`.codex/scene-user-samples-20260722/Scene`。它是用户真实 Workshop 目录的隔离副本；本轮没有写入 `~/Movies/MyWallpaperX/创意工坊/Scene`。
- 20 个 `scene.json` 样本的运行结果：[report.json](../../.codex/scene-visible-effect-full20-20260722/report.json)；人工总览：[contact-sheet.png](../../.codex/scene-visible-effect-full20-20260722/contact-sheet.png)。报告为 20/20 PASS，运行 App 为 `2.0.8 (268)`，签名 Team 为 `H9QWU9XN8R`。
- `3766415113` 使用 `gifscene.json` / `gifscene.pkg`，以包含 entry、sequence 和单图 UV 修正的 [gifscene 最终报告](../../.codex/scene-gifscene-sprite-gate-20260722/report.json) 为准。
- `3738202317` 在 20 样本旧报告中因 `.tex format 6` 显示灰底；该结果已经被 [BC2/DXT3 修复后报告](../../.codex/scene-bc2-format6-final-20260722/report.json) 覆盖，当前为 1/1 纹理加载成功。
- “作者预期”来自包内 scene 描述、`project.json` 属性和样本自带 preview。preview 不是逐帧金标准，最终仍需在相同分辨率、相同属性默认值下与 Wallpaper Engine 录屏做差异验收。
- 首轮 21 样本报告保留为修复前视觉基线。v16 结构基线仍见 [canonical graph 报告](../../.codex/scene-effect-graph-canonical-final-20260723/report.json)；当前正式运行门为 [texture registry 最终 13 样本报告](../../.codex/scene-texture-registry-final13-20260723/report.json)，13/13 PASS、interpretation format 17。GPU Blur 成功层仍为 `2902406982:[530]`、`3724289844:[28,36]` 与 `3765760121:[68,76,82]`，失败 0；legacy blur blocked layers 为 `20/348/358`。`2938612768` 的 static image blend 为 5/5，`2902406982/2938612768` 的磁盘缺失资源计数均为 0；这仍不证明 authored shader、动态 provider 或 Wallpaper Engine 逐帧一致。

表中 `I/P/T` 分别表示 image / particle / text 图层声明数量；`prop` 不含每个项目都有的 `schemecolor`。纹理加载率只统计当前 renderer 识别为 image candidate 的图层，不应直接当成视觉完成度。

## 当前增量覆盖

| 能力 | 当前已验证 | 仍未覆盖 |
| --- | --- | --- |
| 用户属性 | bool/slider/combo/color/textinput、group/condition/options；`texture`/`scenetexture` 保留 raw type 后归一为内部 texture-provider 类型；layer visibility、text、camera parallax 与部分 effect target；按壁纸持久化；独立可拖动属性窗口 | sceneTexture 文件选择/bookmark/decode 与真实 override、Texture Variants、transform、particle/audio、puppet、未支持 effect target；无需重建的通用热更新 |
| Solid | 固定 built-in 与 model `solidlayer:true`；共享白纹理、作者 color/alpha/visibility/effect/blend；当前正式门 54/54 | 带动态 `$mediaThumbnail`/sceneTexture 的 solid 实例；普通 image 基础 color multiplier；完整 dependency/mask 组合语义 |
| Utility / Composition | typed composition/project/fullscreen；当前 framebuffer 前缀捕获；局部/full-frame geometry；受限纹理池；mask/partial effect fail-closed；290 的 project 410 / composition 530 与 6 个 named provider / 7 个 consumer 已完成 GPU capture/binding；typed frame registry 按 identity/status/generation 选择首个 ready 候选；293 的 providers 141/1340、consumers 299/322 与隐藏普通 image providers 到 layers 239/657/775/875/1509 的静态 blend 已进入 GPU runtime | property 文件/媒体/Texture Variants、effectful provider、nested/child target、utility mask、动态 blendgradient 与任意 material/shader pass；不能把受限 named-target / static image 子集写成完整 dependency graph |
| Particle | 包内 texture、sprite/sequence、built-in `particle/drop`、continuous/burst initial、基础 lifetime/opacity/color/size/rotation/velocity、additive/translucent blend、Sprite Trail 沿速度方向并按作者 length/min/max 拉伸、正交/透视相机、层级可见性与 parallax；正式门 6/27，375 雨层 516 已加载；定向门中 299 的 6 个 `rainperspective` 层与原有作者层共 7/15 | 其余 built-in texture/preset、child system、rope/rope trail、world-space、完整 control point/attractor、动态 instance override、音频与属性动态 operator |
| Text | 当前以 authored `pointsize * 4` 近似官方 300 DPI point raster，处理 vector padding、包内字体、系统字体别名和确定性 fallback 诊断；`3766387484` 3/3、`3122339805` 80/81、`2134765860` 4/6 candidate | 精确 DPI/scene-unit 校准、SceneScript、真实时钟/日期/媒体值、完整对齐/描边/阴影/effect 语义 |
| 自动门 | 13 个真实隔离样本，interpretation format 17，签名 App、Metal ready/after 非黑帧；既有 layer/dependency GPU 门、definition/graph canonical SHA、precise/standard exact-ID GPU completion/failure/legacy-blocked，以及 property fallback 的 5 个 blend layer 均进入合同；无 timeout、stop 后 surface=0 | 只有 strict precise 与 standard-default 子图被消费；其余 graph、5 个 fluid blocker、本轮观测到的 37 个 route-only effect 和 1 个 named-target gap 仍保留；不是 21 样本视觉重评，也没有 Windows WE 同配置录屏差异门 |

## 横向能力判断

### 声明驱动，而不是全局默认

- 明确开启相机视差的样本是 `2802243144`、`2902406982`、`2938612768`、`3750342273`、`3750813609`、`3766387484`；其中部分还受项目属性控制。
- `3768229922` 的视差由属性绑定且默认关闭；其余样本默认不得产生相机视差。
- `2902406982` 有两处 waterwaves 声明但默认均关闭；`3765760121` 的 particle 默认关闭。它们是防止“有能力就全部打开”的负向回归样本。
- 全量报告中的 `camera_parallax` 已能反映上述多数作者默认值，但项目属性的条件、运行时切换和 effect uniform 绑定尚未形成完整闭环，因此还不能只凭日志字段宣称完成。

### Particle

21 个样本中有 18 个声明 particle，共 60 个 particle layer，按默认可见性与父链计算有 54 个有效层。当前 renderer 已有作者包内 2D sprite、built-in `particle/drop` 与 Sprite Trail 高频子集；正式 13 样本门加载 6/27，其中 `3750813609` 已同时加载原有层 200 和雨层 516，`3765760121` 的默认隐藏 particle 保持不创建。额外定向门中 `2998757800` 加载 7/15：原有作者层 287181 加 6 个 `rainperspective` 层 172/181/187/193/199/205；这 6 层的动态 `instanceoverride` 仍被诊断为未支持。样本还声明 box/sphere emitter、rope/rope trail、child graph、音频驱动和更多 Wallpaper Engine 内建资源；这些高级语义仍需逐类补齐，不能用“已有粒子”概括成完整支持。

### 项目属性与详情面板

14/21 个样本声明了自定义项目属性，共 403 项（不含 `schemecolor`），覆盖 bool、slider、combo、color、textinput、scenetexture、分组、条件可见和 combo options。当前详情页只保留“属性调节”按钮，点击后打开独立可拖动窗口；已支持控件、条件、默认值/override、按壁纸持久化和活动 Scene 重建。parser 已把 `texture`/`scenetexture` 归入同一内部 provider 类型，runtime 也能在属性未提供纹理时使用作者 fallback；但 UI/file picker、security-scoped bookmark、decode 和真实 override 尚未接通。transform、particle、puppet 等 target 也未闭环，因此 403 项并非全部可调。

### Text 与字体

13/21 个样本共声明 258 个 text layer。当前 CoreText 路径以 `pointsize * 4` 近似官方声明的 300 DPI point raster，并处理 vector padding、包内字体和系统字体别名；`3766387484` 的非均匀 scale 静态几何已明显接近 preview，但该倍率仍需 Windows 官方输出校准。`3750813609` 的 200pt 时钟仍是过大的黑色静态占位，说明字号几何修正并未闭合最终字体、颜色和 effect 语义。未知 SceneScript 不执行，时钟、日期、媒体信息和随机文本仍是静态值，对齐、描边/阴影和 effect pass 也未完整复刻。`3750813609`、`3766387484`、`3122339805` 继续作为大字号、非均匀缩放和 100 层压力三类文字基准。

Camera Parallax 的当前负向合同已经补齐：包括 composition 在内，layer 缺失 `parallaxDepth` 或两轴均为零时不产生逐层位移；composition 类型本身不隐含任何视差深度。位移归一化和 delay 曲线仍需 Windows golden 校准。

## 四个重点样本的当前增量状态

- `2902406982`：当前 image 30/30、text 44/57、particle 0/1；6 个 named provider capture 与 7 个 consumer binding 全部成功，layer `530` 的 stock standard Blur 默认图已通过真实 4-pass quarter-RT 执行。三角区域已经采到对应内容，旧截图中的无依据白色三角和背景重复叠影不再是当前现象；定向截图中的全背景模糊也比旧 coarse 路径更干净。最新 interpretation 的磁盘缺失资源计数为 0，但 9 个 effect 仍是 route-only，字体/文字层、SceneScript、媒体/音频和属性驱动仍不完整，不能从“主体已可辨认”推导出主构图完全一致。
- `2938612768`：当前 image 44/44、text 8/24、particle 0/1；wrapped alpha 已消除错误黑色覆盖，named providers 141/1340、consumers 299/322 和 static image blend layers 239/657/775/875/1509 均成功，中央播放器与静态封面已出现。layers 775/875 在属性纹理未绑定时分别回退作者 layers 890/1174；775 只读取 authored-initial alpha，并未执行 SceneScript 更新。磁盘缺失资源计数为 0，但仍有 1 个 named-target gap、18 个 route-only effect；背景被现有 waterwaves 近似严重扭曲，媒体动态封面/标题/时间、真实 sceneTexture override、blendgradient、音频和粒子仍未闭环。
- `3750813609`：当前 image 2/2、text 1/1、particle 2/9；layer `358` 的非默认 Blur+Clouds 图不满足 default-profile 合同，现已明确 blocked，不再错误套用 legacy blur。单个 built-in UV Foliage Sway 作者参数已生效，雨层 516 使用 built-in drop + Sprite Trail 进入运行时，画面已能看到贯穿场景的雨线。剩余 7 个粒子层、本轮观测到的 2 个 route-only effect、动态时间脚本和完整文字效果未实现；时钟目前仍是过大的黑色静态 `12:34`，不能当成最终字体/时钟效果。
- `2998757800`：定向粒子门为 image 5/5、particle 7/15；6 个 `rainperspective` built-in 雨层 172/181/187/193/199/205 与原有作者层 287181 同时绘制，雨幕已覆盖作者声明的多个深度层。其余 8 个粒子层、6 个雨层的动态 `instanceoverride`、天气/触摸、puppet 与完整 foliage/waterripple/xray 语义仍缺失；当前主图和雨可用，不代表交互与天气壁纸已经复刻。

## 首轮逐样本评估（历史基线）

严重度定义：P0 为主内容不可接受；P1 为可识别但核心体验缺失；P2 为主体可用但有明显差距；P3 为可延后微调。下表保留修复前截图结论，已被“当前增量覆盖”命中的属性、粒子和文字描述不再代表 HEAD；待 21 样本重跑后再统一重分级，避免只改少数行造成伪精确。

| 样本 | 入口与作者关键能力 | 首轮显示状态 | 主要缺口 | 严重度 | 推荐验收点 |
| --- | --- | --- | --- | --- | --- |
| `2134765860` Bunk | `scene.json`；42 层，I33/P1/T8，effect 79，prop 33；audio bars/ring、时钟日期、blur/waterwaves；parallax 关 | 房间主构图完整；image 12/33、text 4/6；双帧运动 0 | 大时钟、日期、音频可视化和部分装饰层缺失或尺寸过小；大量 built-in/组合资源未落地 | P1 | 默认无视差；时钟按真实时间更新且字号/位置与 preview 接近；开关 audio ring 后才出现对应效果；无音频时稳定，受控频谱时有响应 |
| `2419444134` Nier Reincarnation - Akeha | `scene.json`；10 层，I5/P4/T0，effect 13，prop 5；fog、audio dots/stars、neon、waterwaves；parallax 关 | 人物和霓虹环完整，image 5/5；仅有极低双帧变化 | 4 个粒子系统及音频响应缺失，fog/星点开关无属性链 | P1 | 默认无视差；5 个属性逐项控制对应层；星点、雾和音频粒子分别可见，关闭后完全停止且不残留 |
| `2802243144` 冰公主 | `scene.json`；12 层，I5/P2/T4，effect 8，prop 13；雪、时钟日期、precise blur；parallax 0.1 与 camera shake 受属性控制 | 主图完整，image 5/5、text 2/2；报告识别 parallax=true，但定时双帧无运动 | 雪粒子缺失；文字仅静态值，字体/时间格式未对齐；属性未生成 | P1 | 默认属性值决定视差和 shake，不得强开；鼠标注入时视差幅度受 0.1 限制；雪粒子、时间/日期和位置滑杆均可单独验证 |
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

1. P0 通用根因已关闭基础 layer/resource、290/293 命中的受限 dependency 子集，并完成 v15 EffectDefinition、v16 graph planner、strict precise/standard Blur 默认 profile backend，以及 v17 registry identity/property authored-fallback 第一切片。当前下一步是实际 file/system/media provider source、Texture Variants、effectful/nested composition 与更广 executor；compose/functions/conditions 和 standard 非默认 profile 在语义未闭合前继续 fail closed。
2. 项目属性主链已完成第一阶段：parser、condition、受支持 target、持久化、独立窗口和 `texture`/`scenetexture` 内部归一化已落地；`3766387484` parallax off 与 `2134765860` text/day-night/custom text 门通过。sceneTexture 文件选择/授权/解码与真实 override、transform、particle/audio target 和 `2902406982` 大规模 UI/滚动门仍未完成。
3. particle runtime 已完成第二个高频切片：作者 sprite、built-in drop 和 Sprite Trail 已进入真实渲染，正式门 6/27，375 的雨层 516 与 299 的 6 个雨层有定向证据，`3765760121` 默认隐藏负向门通过。其余 built-in、child、rope/rope trail、动态 override、world-space 和音频粒子仍未完成。
4. 静态 text geometry/font 已修正并通过 3 样本门；动态时间/日期/媒体、完整效果与 100 层最终性能门仍未完成。
5. standard Blur 默认图和首个 typed registry/fallback 已完成；主构图 P0 现转向 actual file/media/system provider、Texture Variants、effectful/nested/child composition 与更广 graph executor，不重复实现已有 identity registry、bounded named-target capture/binding。随后补 live-value runtime 与高命中粒子；任意 shader、waterflow/ripple、depth parallax、godrays/glitter、puppet 和音频仍按样本命中与视觉影响逐类推进。

每一步都应同时保留两类门：一类证明声明的能力确实出现，另一类证明未声明或默认关闭的效果不会被全局套用。所有样本仍从真实 Workshop 复制到隔离 root，并使用临时 HOME 运行；流程 PASS、非黑截图和加载率只能作为底线，不能替代与作者 preview/Wallpaper Engine 的视觉对照。
