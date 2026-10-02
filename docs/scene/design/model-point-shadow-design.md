<!-- document-role: active-plan -->
<!-- retirementCondition: 完整球域点光阴影通过相称 GPU、实际 App、资源生命周期证据及独立终审后，稳定合同移交 runtime-architecture，本文归档并删除窄设计门；表示被反例推翻时先修设计，不以缩减球域退役。 -->

# RF15 — 模型点光全向阴影

> 基线 `8236d908`，2026-10-02；状态：独立设计审查 ACCEPT，批准实施。设计批准不是实现验收。上接 [RF15 工作卡](reference-evidence-implementation-cards.md#rf15-model-point-shadow) 与 [D3](2d-lighting-material-design.md#f6-model-directional-shadow)。

设计审查收据：`/private/tmp/mwx-rf15/design-review.md`，SHA `d06521fe41e80e058dd14233fd2a85c26e882a8bd2f6583f76d80f3774ec6f93`；审查设计 SHA `5deffd6ebb1b594b7f42076593e3ec7d632b414cc8385c497cc92b21ecee9f97`。本次仅翻批准状态与登记，完整 GPU/App 纠正门仍待实施。

## 目标合同与证据边界

现有总四灯准入内所有 cast-on point 必须覆盖完整球域，包括六个方向、面边和角部。只调制对应点光 direct，保其它灯、ambient、emission、alpha、原 mandatory 及唯一 compositor。模型默认投影、显式关闭仍可接收；沿用当前 coverage 与 prepared 静态/named 几何，不用主相机可见集筛灯的 caster。

五判据：横切 owner=是；触碰唯一资源/发布合同=是；难逆数据/API=否；机器冻结家族=是（不增预算）；外部行为证据=是。

[官方模型光照合同](https://docs.wallpaperengine.io/en/scene/models/lighting.html)说明模型和灯的投影开关，点光、聚光、方向光可投影，不规定算法。[Mirage 中性参考 §8.4](../semantics/miragewallpaper-rendering-reference.md)第323–327行支持灯输入、四灯传递；该参考修订没有 shadow atlas，不能据此跳过实现，也不能宣称沿用官方算法。本项目独立选择六面 atlas、径向比较和跨面采样。正式文档不收录参考代码、地址、伪代码或算法公式。

## 当前事实与首断点

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

## 方案、owner 与备选裁决

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

## 六面、深度与接缝行为

六个轴向面覆盖所有非零光线；平局采用固定规则，规则属于本项目策略。透视裁剪保留跨光源面的真实正向几何，不随意引入正 near 平面。caster 以真实像素中心射线与几何面交点的径向距离写深度；覆盖/UV仍沿原材质采样。真实三角射线 oracle 独立判断结果，不从产品矩阵或GPU深度反推期望。

每灯 atlas 只清一次，每面显式设置 tile viewport 和 scissor。Metal 的 [viewport](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setviewport(_:)) 定像素映射，[scissor](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setscissorrect(_:)) 限制写入；必须同时正确。fragment 像素位置扣除当前 tile origin，不能除整图冒充单面。每灯 encoder 结束，后灯及主颜色使用原新 encoder，不添加跨 encoder 状态缓存。

receiver 使用固定九点权重，每个采样点可跨面：以空间方向定位实际目标面，取该面实际 nearest texel 中心，再以最终中心的世界射线与 receiver 几何面相交，进行同源径向比较。不能用跨面前射线的深度比较跨面后的 texel，不能用轴深度比较径向值；不允许整图线性过滤读到布局相邻但方向不相邻的 tile。

面切换会改变离散采样网格，不承诺解析连续软阴影；要求跨面遮挡不漏面、不读错 tile、无虚假无影带。无正有限 receiver 交点的单 tap 保持原权重并视为可见。原 direct 无贡献的灯源邻域不扩大。数值裕量依据实际运算尺度，在运行前固定，并同时通过同面自影、正负近间隙、平移和倾斜反例；不得观察失败后放大 bias。透明 cutout 跨面也需要实际验证，不能用全不透明测试代替。

## fallback、预算与生命周期

原 mandatory 先行，方向光/spot 成功 pin 保留，再准入 point。矩形尺寸属于原 pool key；切换灯种/extent 是另一 key，旧在飞 texture 仍计费。相同尺寸不同提交的旧 generation、reset-retired 仍由原 pin/completion 释放。两代四点光已达192MiB逻辑成本，再加mandatory可能拒绝后续可选灯，这是局部降级，不提高配额。

真实可失败产生者分别为：作者非法cast值（原strict parser）、现snapshot拒绝的非有限/非正输入、世界变换及真实平面退化、原pool最大尺寸/逻辑及native配额、Metal可选PSO或encoder创建、prepared caster opacity等编码前检查、generation/physical identity破坏。按原最小unsafe unit处理，不新增无产生者防御。

point PSO/target/任一面绘制失败只使该灯无影，仍保对应direct、健康灯和安全主帧；六面不完整不得发布。已经编码访问的资源 pin 留到原提交 completion/cancel，不能因未发布提前释放。identity、range、hazard仍按原硬门，不转成视觉成功。named caster/receiver沿RF13当前发布/coverage，既有mandatory重试语义不被optional阴影改变。

## 纠正门与交付上限

1. 先冻结修前输入与旧App缺影反例，再批准实施。实际产品 PSO/atlas writer 用独立 Double 三角射线验证六面覆盖/clear/最近深度、非零tileorigin、不同extent、非等w、跨w零、半径内外及反向顺序；误差界在GPU前冻结。
2. 完整六轴、12边、8角、平局及各相邻面两侧；独立阻挡/健康控制、同面/前后近gap、平移倾斜、非均匀变换、cutout跨面。部分PCF边界的独立离散oracle使用设计规则而不调用产品helper，真实 radiance/alpha 证明对应direct独占变化。
3. 实际解析、当前snapshot、总四灯/候选稳定顺序、混合各灯贡献、父变换/下一帧、原ordered/named当前coverage。旧directional/spot/RF13回归仅作相邻合同验证，不冒充新点光证据。
4. 实际native/logical quota，先保mandatory/旧灯，后拒可选point；六面完整发布与可达部分编码失败；真实提交A在飞→reset→B取消或提交→A完成→C恢复，核六面像素、pin、resident与next-frame。区分主颜色resize、shadowextent换key及强引用仍持有，不能称物理销毁。
5. 新不可变App先重放原四输入，再实际呈现六方向和混灯、动态/父变换；事前独立确定ROI，完整身份、GPU completion、publication、terminal输出与下一帧链。native全向不能替代App全向。
6. 通过相称模块、Debug build、code-health、scene-defense、design-gate和文档门；冻结完整diff和证据独立终审，窄提交。产品改动一旦改变身份，相应实际证据重跑；不因构建、非黑、有限测试宣称官方parity、性能完成或真实corpus收益。

## 退役条件

完整球域点光阴影通过相称 GPU、实际 App、资源生命周期证据及独立终审后，稳定合同移交 runtime-architecture，本文归档并删除窄设计门；表示被反例推翻时先修设计，不以缩减球域退役。

资源证据：`MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift`（原 owner，不在产品写范围）。

资源证据：`MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneResourceBudget.swift`（原 owner，不在产品写范围）。
