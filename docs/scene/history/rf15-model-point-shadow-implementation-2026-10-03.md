<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF15：真实模型点光全向阴影（2026-10-03）

> **历史证据 — 非现役入口**。本批设计前置提交 `a2197d71`。产品冻结为 v3，独立产品终审 **ACCEPT RF15 coherent v3**。本机证据根 `/private/tmp/mwx-rf15/`；现役职责由[架构](../architecture/runtime-architecture.md)接管，后继只由[兼容路线](../roadmap/scene-compatibility-roadmap.md)选择。

同页历史分节：[已退役设计裁决](#rf15-retired-design)。

## 实际结果与职责

现总四灯准入内所有 cast-on point 可对已经准备的静态及 source-only named 模型投影，覆盖六轴、面边和角部的完整球域。原首方向光优先，其后聚光、点光分别保作者顺序；最多四项记录，失败不压缩原候选槽。只衰减对应灯的 direct，保其它灯、ambient、emission、alpha 和唯一输出。不把普通 image、particle 或 Puppet 虚构为模型 caster。

每个点光使用原 pool 的一张 3072×2048 depth32Float atlas，六面各1024²；每灯逻辑24MiB，四灯96MiB，native 成本另按真实 descriptor 计费。原 mandatory/gather 与主颜色各一次，原 pin/completion 管理已编码资源，六面全部写完才发布一项 typed map；某面失败取消该灯阴影，保原 direct、健康灯和主画面。没有新资源 registry、灯时钟或 compositor，没有提高结构与预算基线。

参考资料提供作者行为、输入及生命周期依据；本项目独立选择六面表示、径向深度及跨面九点消费，不复制参考代码或私有算法。点光开关复用既有严格布尔判据，snapshot 保存当前灯身份与意图。caster 使用真实三角面与实际片元射线交点写径向深度；receiver 每个 tap 独立选面，重定位到最终 nearest texel，再按该射线求接收面深度。不把布局相邻 tile 当空间邻面，不借上一帧图。

## 反例与本批修复

旧 RF14 不可变 App 的四输入位于 `baseline-6gy9prgy`：cast-on/off/no-caster 的接收区均62，light-off为9，灯光贡献53但 on/off 整图完全相同。四次真实完成、drain 与身份通过，只证明一个实际缺影方向。protocol SHA `b2171728060220777231b14fbe8f1b163cd52fdb6b30d6cef954b230d4080e2d`。

v1 的完整遮挡门通过后，部分覆盖的面角门暴露实际数值缺陷：中心片元三个相对分量逐位相同，但快速除法消去使本应为0的面UV变成约−9.84e−9，floor选到了前一格。先排除测试片元一ULP偏移和 tint/opacity 非法并用，再用同一预登记独立九射线期望证明产品反例。v2 仅将点光两个UV换算消费点改用精确除法与融合仿射映射；原143行部分PCF、阈值和bias未放宽。原红、centered红及诊断保留。

v2 的真实缺入口注入又发现：Metal 允许无 fragment 的 depth-only PSO，原可选点光状态仍成功创建并发布错误图。该问题同样影响方向光coverage和聚光轴深度，v3 在原三类PSO各自创建边界确认必要vertex和fragment均存在。分别缺三种fragment只退化对应阴影；缺共享透视vertex时保方向光和主颜色。这是由真实缺函数library证明的失败边界，不新增无产生者兜底。

两类测试输入纠正不计作产品缺陷：动态移动灯的不同位置存在正常直接光空间梯度，最初把跨位置健康ROI当精确相等而失败；新增同状态cast-off对照，用两个清晰direct控制区匹配状态后，健康ROI逐像素相等。named App初稿将父层隐藏，导致子灯按既有父可见性合同也隐藏；只改父可见，保持world、ROI和阈值再执行。所有原红保留，未通过放宽产品阈值取得绿。

## 冻结身份与验证

六产品清单 `implementation/checkpoint-v3-products.json` SHA `a2f6372da3678f7698c0f411e9caa1924dbd2dc219d43fab8b723d3b5d459d19`；相对设计提交的六产品diff SHA `f9a5e3dca867a87d331ac62e32180d03ffd738f60673f5534a139301e28821d6`。最终三测试清单 `test-sources-final-v3.json` SHA `da58ebe332918ccb19abbe03ec575753c1a1406b8b50efa5cf495ddf6ebda974`。两个旧模块仅更新三处真实drawShadow调用参数，原行为断言未弱化。

完整 Debug 构建、code-health、scene-defense、design-gate、文档门通过；build-v3/receipt.json记录六产品前后不变、同一source-v3.app五文件身份、deep strict和两个helper Team requirement。code-health为1056 Swift、240 warnings，不是零警告或发布验收。构建之后产品未变。并行owner随后提交 `8c2429c2`，仅三份census文档，未改变本批六产品/三测试；最终diff仍与冻结产品一致。

最终点光11方法通过164.966s，连同下述18个相邻方法合计29个唯一方法。总索引 `test-final-v3.json` SHA `2f3bbd0802ab827e74c6fa028ca79e106205e2608008669caf2e20700c5d92ca` 的475个显式工件及root索引68项均重新校验一致；`coverage-gap-map-final.md` SHA `0e0891b6f6d1a846f7661a7c03a69f3b169e8da179f101c048099814622149b9`限定每项证据上限。G0包含12种真实三角输入的六面写入/clear及两个extent；G1含238行self/正负间隙、143行独立部分PCF与6行倾斜/非均匀/平移；G2实际解析/世界帧有12检查；G3涵盖10资源输入、部分写入及4种缺入口library各3场景。旧相邻directional7、spot10及spot-plan1已按实际方法通过，不累计同版本聚焦重跑次数。部分编码门的作者大alpha由真实CPU RuntimeModelBuilder进入prepared边界；未实编GPU资源builder，不能称端到端资产加载。资源零光强用例只证明mandatory、slot、pin与配额，不作为辐射证据。

最终实际App分四组，同source-v3：

- 原四输入重放 `original-four-v3-tg55lxok`：阴影恢复，off/no-caster/light-off保控制输出。
- 六方向8输入 `six-axis-app-pd8_yreo`：真实透视相机分别观察±X/±Y/±Z，六向shadow9、healthy62、caster125；另有cast-off与light-off。相机/ROI事先确定，无结果后修订。
- 混灯/动态6输入 `mixed-app-v3-foxmu_vb`：四点光与directional+spot+两point分别on/off，四个ROI各自衰减，健康区和其它通道exact。动态光80→100→80时遮挡位置交换并恢复，与同状态cast-off对照的健康区逐像素相等。协议 SHA `ff4e6c290a1514681d2159e24f44fcfc779c6dc50f0af4aedfbf7e6713ba3b37`；68项显式索引 `root-app-index-v3.json` SHA `de2d3e12ffea12493385ec99f9f5d923a486d98978104cad43e4461eb91ee1ce`。
- named当前纹理1输入 `named-point-v3-trdip5ro`：带实际父变换，receiver cast=false；provider alpha变化使shadow9→62→9，健康区始终62。当前named绑定、主颜色、frame0/1/2、completion及drain成立；协议 SHA `addedb0256bfe587e12cea9881a324265ad65b81eca722ca4965159a4f60dcac`。

以上共19次最终App执行，不将旧v1/v2复验累计进去；各组身份、输入、completion、发布、terminal输出和next-frame检查由其协议/结果限定。纯native接缝数值门不冒充App逐接缝截图。

## 未验边界与移交

没有证明官方图像parity、完整原包收益、性能提升、所有模型格式、全部阴影组合或多方向光。项目固定分辨率、九点过滤和8epsilon尺度裕量是有限质量策略，不是全域数值误差定理；片元depth及每灯六次几何绘制的性能仍需实际优化构建度量。资源证据区分逻辑驻留、native计费和仍被强引用的Metal对象，不将计费归零称物理析构。

独立终审 `product-final-review-v3.md` SHA `a7fb0cee8d563adc17d952dd1dae58fab7e8cc6e108c45f331dba7b8b9edbc15` 接受上述六产品、三测试及最终索引，无剩余阻断finding。[前置设计](rf15-model-point-shadow-implementation-2026-10-03.md#rf15-retired-design)归档、窄gate删除，稳定合同移交架构；完整D3仍未关闭。下一RF16已用原reader准确归因历史24→22：层479顶点预算超限，层724五材质触发四段准入上限。先追较小的多材质完整资源链及当前可见受害，再按设计修一个实际断点；不抬高顶点预算，不把旧零shadow事件当当前点光实现失败。CPU归因不是实际画面恢复，后继证据单独记录。

<a id="rf15-retired-design"></a>

## 已退役设计裁决

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf15-retired-design--rf15-模型点光全向阴影退役设计"></a>
### RF15 — 模型点光全向阴影（退役设计）

> **历史证据 — 非现役入口**。本文保留批准设计时的行为合同与选型。RF15已通过独立产品终审；窄登记退役，稳定职责移交[架构](../architecture/runtime-architecture.md)，实际结果与未验边界见[执行记录](rf15-model-point-shadow-implementation-2026-10-03.md)。下文“待实施”仅指设计时点。

> 基线 `8236d908`，2026-10-02；状态：独立设计审查 ACCEPT，批准实施。设计批准不是实现验收。上接 [RF15 工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf15-model-point-shadow) 与 [D3](../roadmap/batch2/2d-lighting-material-design.md#f6-model-directional-shadow)。

设计审查收据：`/private/tmp/mwx-rf15/design-review.md`，SHA `d06521fe41e80e058dd14233fd2a85c26e882a8bd2f6583f76d80f3774ec6f93`；审查设计 SHA `5deffd6ebb1b594b7f42076593e3ec7d632b414cc8385c497cc92b21ecee9f97`。本次仅翻批准状态与登记，完整 GPU/App 纠正门仍待实施。

<a id="rf15-retired-design--目标合同与证据边界"></a>
#### 目标合同与证据边界

现有总四灯准入内所有 cast-on point 必须覆盖完整球域，包括六个方向、面边和角部。只调制对应点光 direct，保其它灯、ambient、emission、alpha、原 mandatory 及唯一 compositor。模型默认投影、显式关闭仍可接收；沿用当前 coverage 与 prepared 静态/named 几何，不用主相机可见集筛灯的 caster。

五判据：横切 owner=是；触碰唯一资源/发布合同=是；难逆数据/API=否；机器冻结家族=是（不增预算）；外部行为证据=是。

[官方模型光照合同](https://docs.wallpaperengine.io/en/scene/models/lighting.html)说明模型和灯的投影开关，点光、聚光、方向光可投影，不规定算法。[Mirage 中性参考 §8.4](../development/reference/miragewallpaper-rendering-reference.md)第323–327行支持灯输入、四灯传递；该参考修订没有 shadow atlas，不能据此跳过实现，也不能宣称沿用官方算法。本项目独立选择六面 atlas、径向比较和跨面采样。正式文档不收录参考代码、地址、伪代码或算法公式。

<a id="rf15-retired-design--当前事实与首断点"></a>
#### 当前事实与首断点

以下产品路径相对 `MyWallpaperX/Core/SteamWorkshopScene/`，行号属于上述基线。

| 证据 | 当前事实 |
|---|---|
| `Format/ScenePointLightDefinition.swift:28` | cast 仍使用宽松 Bool 桥接，须复用既有严格意图解析。 |
| `Rendering/Lighting/SceneLightSnapshot.swift:16–21,36–56,222–240` | Point 缺 identity/cast；shadow candidate 只有方向光和聚光；位置、强度、半径已有准入。 |
| `Rendering/Composition/SceneStaticModel.metal:251–269` | 点光 direct 没有 visibility；光源附近零贡献和有效半径已有唯一规则。 |
| `Rendering/Frame/SceneMetalRenderer+StaticModels.swift:400–466` | 原 caster gather、mandatory、稳定候选槽、每灯 encoder、pin/completion 已存在。 |
| `Rendering/Metal/SceneStaticModelPipeline.swift:561–605` | 真实 prepared caster/coverage 及可选阴影 PSO 已是原消费链。 |
| `Rendering/Targets/SceneOffscreenTexturePool.swift` | 实际路径见下段；不存在需要新增的 atlas manager。 |

`Rendering/Targets/SceneOffscreenTexturePool.swift:175–228` 用 slot 与真实宽高建 key，矩形 depth32Float 单 mip 已支持；原 SharedPair 校验格式/usage，原 SceneResourceBudget 以实际 descriptor 的 native size 计费。

修前真实 App：`/private/tmp/mwx-rf15/baseline-6gy9prgy/` 的 protocol SHA `b2171728060220777231b14fbe8f1b163cd52fdb6b30d6cef954b230d4080e2d`、summary SHA `e63f9126fb1c08922440f65cff853cd6f5bd733a05ac157c791b2eb5e75e9ece`。四个输入 cast-on/off/no-caster/light-off；on/off 全图相同，两个 receiver ROI 都62，关灯9，caster118。四次退出、frame0/1/2完成及 drain、输入/App身份均通过。仅证明一个实际缺影方向，不是全向验收。

<a id="rf15-retired-design--方案owner-与备选裁决"></a>
#### 方案、owner 与备选裁决

选择每灯一张 3×2 depth32Float atlas，六面各1024像素边长，整图3072×2048，单 mip；六面都完成才发布一项 typed shadow record。单灯逻辑24MiB，四灯96MiB，native实际成本另计。保持原固定四个 depth2D 绑定和 pool slot；不增加 registry、资源协议、时钟或输出路径。

备选 cube/array 有自然分面采样优势，但现资源池、descriptor校验和绑定均为2D，扩展会增加本片的生命周期与ABI迁移；本片选择已有矩形 target，实际 GPU 必须证明接缝消费正确。六个独立纹理会扩大资源事务和绑定，故不选。单面/半球不能满足目标，不是可交付降级。若 atlas 先导失败，保留失败证据回修本设计，不同时留下两种产品路径。

产品职责冻结为以下六个现存文件：

- `Format/ScenePointLightDefinition.swift`：复用严格 cast 解析；不另建判据。
- `Rendering/Lighting/SceneLightSnapshot.swift`：当前 identity、position、radius、cast；原总四灯不变，shadow 顺序为原首方向光、全部 spot、全部 point，各组保作者顺序，失败不压缩槽号。
- `Rendering/Metal/SceneStaticModelShadow.swift`：唯一六面表示、布局与 typed point record，投影依灯世界位置和有效半径。
- `Rendering/Frame/SceneMetalRenderer+StaticModels.swift`：原 mandatory/gather 一次、每点光一个 atlas/encoder/pin，六面绘制后原发布。
- `Rendering/Metal/SceneStaticModelPipeline.swift`：原 caster ABI 与独立可选 point PSO，原颜色只绘制一次；预计低于1000行，不以提高预算拆包装层。
- `Rendering/Composition/SceneStaticModel.metal`：实际 caster 径向深度、receiver 跨面采样与对应 direct visibility。

现 pool/cache/主 encoder 不在写范围；若实证必须改，先修职责和设计再实施。

<a id="rf15-retired-design--六面深度与接缝行为"></a>
#### 六面、深度与接缝行为

六个轴向面覆盖所有非零光线；平局采用固定规则，规则属于本项目策略。透视裁剪保留跨光源面的真实正向几何，不随意引入正 near 平面。caster 以真实像素中心射线与几何面交点的径向距离写深度；覆盖/UV仍沿原材质采样。真实三角射线 oracle 独立判断结果，不从产品矩阵或GPU深度反推期望。

每灯 atlas 只清一次，每面显式设置 tile viewport 和 scissor。Metal 的 [viewport](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setviewport(_:)) 定像素映射，[scissor](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setscissorrect(_:)) 限制写入；必须同时正确。fragment 像素位置扣除当前 tile origin，不能除整图冒充单面。每灯 encoder 结束，后灯及主颜色使用原新 encoder，不添加跨 encoder 状态缓存。

receiver 使用固定九点权重，每个采样点可跨面：以空间方向定位实际目标面，取该面实际 nearest texel 中心，再以最终中心的世界射线与 receiver 几何面相交，进行同源径向比较。不能用跨面前射线的深度比较跨面后的 texel，不能用轴深度比较径向值；不允许整图线性过滤读到布局相邻但方向不相邻的 tile。

面切换会改变离散采样网格，不承诺解析连续软阴影；要求跨面遮挡不漏面、不读错 tile、无虚假无影带。无正有限 receiver 交点的单 tap 保持原权重并视为可见。原 direct 无贡献的灯源邻域不扩大。数值裕量依据实际运算尺度，在运行前固定，并同时通过同面自影、正负近间隙、平移和倾斜反例；不得观察失败后放大 bias。透明 cutout 跨面也需要实际验证，不能用全不透明测试代替。

<a id="rf15-retired-design--fallback预算与生命周期"></a>
#### fallback、预算与生命周期

原 mandatory 先行，方向光/spot 成功 pin 保留，再准入 point。矩形尺寸属于原 pool key；切换灯种/extent 是另一 key，旧在飞 texture 仍计费。相同尺寸不同提交的旧 generation、reset-retired 仍由原 pin/completion 释放。两代四点光已达192MiB逻辑成本，再加mandatory可能拒绝后续可选灯，这是局部降级，不提高配额。

真实可失败产生者分别为：作者非法cast值（原strict parser）、现snapshot拒绝的非有限/非正输入、世界变换及真实平面退化、原pool最大尺寸/逻辑及native配额、Metal可选PSO或encoder创建、prepared caster opacity等编码前检查、generation/physical identity破坏。按原最小unsafe unit处理，不新增无产生者防御。

point PSO/target/任一面绘制失败只使该灯无影，仍保对应direct、健康灯和安全主帧；六面不完整不得发布。已经编码访问的资源 pin 留到原提交 completion/cancel，不能因未发布提前释放。identity、range、hazard仍按原硬门，不转成视觉成功。named caster/receiver沿RF13当前发布/coverage，既有mandatory重试语义不被optional阴影改变。

<a id="rf15-retired-design--纠正门与交付上限"></a>
#### 纠正门与交付上限

1. 先冻结修前输入与旧App缺影反例，再批准实施。实际产品 PSO/atlas writer 用独立 Double 三角射线验证六面覆盖/clear/最近深度、非零tileorigin、不同extent、非等w、跨w零、半径内外及反向顺序；误差界在GPU前冻结。
2. 完整六轴、12边、8角、平局及各相邻面两侧；独立阻挡/健康控制、同面/前后近gap、平移倾斜、非均匀变换、cutout跨面。部分PCF边界的独立离散oracle使用设计规则而不调用产品helper，真实 radiance/alpha 证明对应direct独占变化。
3. 实际解析、当前snapshot、总四灯/候选稳定顺序、混合各灯贡献、父变换/下一帧、原ordered/named当前coverage。旧directional/spot/RF13回归仅作相邻合同验证，不冒充新点光证据。
4. 实际native/logical quota，先保mandatory/旧灯，后拒可选point；六面完整发布与可达部分编码失败；真实提交A在飞→reset→B取消或提交→A完成→C恢复，核六面像素、pin、resident与next-frame。区分主颜色resize、shadowextent换key及强引用仍持有，不能称物理销毁。
5. 新不可变App先重放原四输入，再实际呈现六方向和混灯、动态/父变换；事前独立确定ROI，完整身份、GPU completion、publication、terminal输出与下一帧链。native全向不能替代App全向。
6. 通过相称模块、Debug build、code-health、scene-defense、design-gate和文档门；冻结完整diff和证据独立终审，窄提交。产品改动一旦改变身份，相应实际证据重跑；不因构建、非黑、有限测试宣称官方parity、性能完成或真实corpus收益。

<a id="rf15-retired-design--退役条件"></a>
#### 退役条件

完整球域点光阴影通过相称 GPU、实际 App、资源生命周期证据及独立终审后，稳定合同移交 runtime-architecture，本文归档并删除窄设计门；表示被反例推翻时先修设计，不以缩减球域退役。

资源证据：`MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift`（原 owner，不在产品写范围）。

资源证据：`MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift`（原 owner，不在产品写范围）。
