<!-- document-role: historical-evidence -->

# 普通组合根效果与局部源边界（2026-10-23）

> **历史证据 — 非现役入口**。有界后验，非待修清单。执行顺序只归[当前队列](../roadmap/scene-open-breakpoint-queue.md)，source合同归[D1](../roadmap/batch2/composition-render-target-design.md#ordinary-root-effect-local-boundary)。

<a id="composition-root-effect-local-source-20261023"></a>
## 通用语义与实际收益

获准的正交普通成员组合，其作者局部画布不因根效果的声明或显隐而消失。旧SourceRoute只让透明源、无根效果或顶层passthrough使用local source，导致344的669仅因声明了关闭的Tint而走skippedNoEffect；子层90→627越出父画布，左上多出白卡。现删除这一根效果分派，沿原Planner/SourceGeometry/GroupRuntime/Program与唯一compositor，不改作者数据、坐标或素材，不新增裁切/资源owner。Program准备仍单独准入，source-only不伪造Program。

三诊断臂使用相同旧App、原pkg和显式loose入口，固定作者B姿态：隐藏90同时去掉多余白卡与需要保留的下方白背板；仅删除669的关闭效果则去掉多余白卡、保留下背板。三臂实核入口、语义diff与孔位/前片资格；独审首次缩放图误读时钟已撤回，原PNG小时ROI六图逐像素相同，不能沿用“缺小时”的错误结论。

候选保留原project/pkg和根效果，原344默认及64=true的B姿态均实际去掉左上多余白卡，下方背板、时钟、唱片与封面保留。目录官方截屏支持没有这块白卡的粗构图，非相同媒体/时间/viewport的逐像素golden；本批仅关闭此可归因子现象，不声明全部布局、交互或媒体模式一致。

## 验证及身份

- 两个SourceRoute方法修前4个断言红、修后绿；实际Planner七方法红→绿，含改名/顺序、隐藏根FX的source-only与活动FX未准备拒绝、透视/native/模型/粒子/依赖等相邻反例。新增outer-FX背景组可把无FX的nested passthrough作为同一外组结构成员；它不另建source/output，nested自身有FX仍拒，普通nested背景限制保持。
- 真实App的96×80非居中源保独立红绿UV标记、X/Y越界点和健康后层。水平镜像Program的旧viewport输入10个像素断言失败；候选OFF/ON两门通过，ON核encoded-output与同帧GPU完成，OFF无根Program编码。该opaque门证本地归一UV与边界，不证明全部alpha或官方内部算法。
- 固定Scene源的优化Debug构建31.757秒，5859构建输入无漂移；签名A `d20c964f…dc7402`、候选 `38fa7716…9b872`，唯一Scene差量为本次SourceRoute。构建快照保当时旧UI，不冒充整App最新UI。最近架构/依赖/防线/代码与设计门通过；无性能收益结论。
- 原344三诊断臂及候选默认/B均App0、GPU失败0、stop1→0且GPU排空。实际669由skippedNoEffect转capture，关闭的671保持author-disabled。原件只读、无新增样本根残留。

## 独立322与音频输入资格

原3226487183未参与修法，两组2522/115975有活动根效果。静音A/B的主要三人物、面具、眼、红底和金线保持；两边均保粒子133/40016的aggregateSystemBudget旧FAIL，不能记整样本PASS。

用户补旧版截屏指出白频谱、旋转白环及背景字符变少，故曾暂扣最终GO。1625/2168的作者opacity脚本在audio.average全零时返回0；它们均childless，不经过本次有成员source分叉。同一A改用非零PCM后，后续generation2的opacity为0.169164792，实际白频谱/白弧与下方字符重现；首次callback仍为0，不可拿启动值代末状态。133/40016的rate还影响模拟时钟，字符相位/位置不能跨音频输入作golden。各root有68个静态matrix child，当前保64并继续部分绘制，预算余项未关闭。

用户随后确认最新普通App实际测试正常。该App main `cc58ab6f…8cf33`、debug dylib `fad4e22f…a6a05`，2.11.0(283)；UI会话冻结4362产品输入，当前810个Scene源与其逐文件匹配。此项是用户定性实测，音轨/属性/时相未独立记录，**候选PCM自动B未跑**；不称自动门或官方同态通过。独审据此给出有界GO，322手部、部分child预算与完整动画仍保开放。

## 证据与未覆盖范围

必要原图、测试/失败、原包身份、构建与签名、用户反馈及独审归本机普通14天包 `.artifacts/scene-evidence/runs/composition-root-effect-local-source-20261023/`。344关键图和PCM A保原PNG；322静音A/B仅保有损审阅副本与原PNG哈希，不用于细像素oracle。旧版Desktop图仅保此前验证的哈希/尺寸，原路径随后已不存在，不伪称归档了原像素。

继承原pool/pin/epoch、取消及组失败抑制；未新增生命周期策略。既有官方双子板仅证ON/无FX的X/Y边界，声明OFF官方板未运行；不外推内部RT、非线性RGB、LOD/边缘采样、Resolution像素步长、全部alpha/嵌套或完整HDR/SDR parity。短窗非稳态性能采集，不认CPU/GPU/内存、启动或能耗收益。

同批原3770444459默认20秒复验未圈出可归因黑水ROI，反馈继续开放，不改blend。必要原图与原输入日志归 `.artifacts/scene-evidence/runs/open-visual-current-20261023/`；旧water-particle-current目录不可用，不作为新的当前证据。
