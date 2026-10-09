<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。断点定位见[L1 复测与土星对比](l1-heavy-retest-2026-10-07.md)；官方对照截图为用户提供（只读引用）。

> **2026-10-09 纠正**：下文“隐藏灯仍照明”的推断及据此修改的测试不再作为合同。固定日期的官方消融表明，删除隐藏点光没有可检测的大尺度贡献；原场景还有方向光，不能从“场景亮了”推断隐藏点光有效。后继验证与修复见[有效可见性与方向](#effective-light-visibility)。`destroy` 准入和模拟恢复是独立结果，不随此推断撤销。

# 土星静态模型灯光送达修复（destroy 导出准入，2026-10-07）

起点 `a13ae170`。承接[L1 复测](l1-heavy-retest-2026-10-07.md)钉死的断点：土星层 443 'main'（54KB VSOP87 模拟脚本）的 Bool 可见性 owner 构造被 `invalidSource` 拒收——脚本导出 `destroy`（官方生命周期回调），而 Bool 可见性准入一概拒绝带 destroy 的脚本 → 模拟永不运行 → `shared.sun_pos*` 无发布 → 灯 origin/angles 脚本求值 NaN → 两灯逐帧 `badReturn("non-finite vector output")` 拒入（17,256 行）→ 行星零受光黑剪影。

## 修复（1 产品文件）

`SceneScriptValueRuntime.swift` Bool owner 准入：`!handlesDestroy` → `allowsStatefulLayerSideEffects || !handlesDestroy`（仅 init/update lane；event-only lane 维持原状）。依据：`destroy()` 是 L3 bounded 官方生命周期回调（API 覆盖表），teardown 的 exactly-once destroy 派发机制全 owner 通用（S4 生命周期连续性已证：`owners=N destroyCallbacks=N quiescent=N failures=0`）；stateful owner 带完整 mutation journal 与 quiescence 门，destroy 在 teardown 派发、失败 fail-soft（threw 计数）、journal 随 teardown 丢弃。value-only lane 保持拒绝（无 teardown 生命周期归属）。

## 验证

- 单元：`test_scene_script_boolean_visibility` 16 测试 OK——含新合同断言：stateful+update+destroy 的可见性 owner 获准（definitions=1）且 `destroyProgram.teardown` 恰好派发一次 destroy（invoked=true、quiescent=true、failed=false）；value-only lane 拒绝与主 program teardown 零误派发保持。
- 实机（重建签名 App，75s 调试探针同 L1 口径）：`non-finite vector output` **17,256 → 0**；层 443 `source=authored`（构造失败回退）→ **`source=sceneScript value=true`**（模拟 owner 运行）；稳态帧土星盘面从纯黑剪影变为**受光暖棕+云带+明暗界线**（盘面 ROI mean 0→13.7、带纹 std 28.3、峰值 255），异常蓝灰放射背景消失，文字正常。
  - 口径注记：17,256 为修复前 probe 运行计数（该日志路径被修复后重跑覆盖，工件不再可复核）；幸存同族证据=产品入口 `run-3589454154/app.log` 的 28,520 行同型 badReturn（含 daemon stderr 双写）。ROI 为会话内定义（盘面矩形裁剪），lit-only 口径下能量差约 1.4×；量级方向不受口径影响。
- 同族：放宽覆盖全部 stateful 层字段 owner（场景级）；灯位脚本驱动样本当前证实的为土星，其余样本按需经 census 复查。

## 与官方截图的残余差异（登记，下一层归因）

盘面受光后与官方截图仍有两处量化差异：①明暗界线镜像——官方左亮右暗，我方右亮左暗；②能量偏低——盘面 ROI mean 13.7 vs 官方 60.2（~4.4×），光环近黑 vs 官方 60.8。方向光精确响应曲线族（已登记开放）只能解释 6–25%，不能解释 4.4×；下一归因层=灯 origin/angles 的**值约定**（`0.0005*shared.sun_pos*` 的坐标符号/单位与 typed lightAngles 逐帧值的追踪），需逐帧灯光值探针。

## 当日后续批：度→弧转换与隐藏灯推断（后者已撤销）

**逐帧灯光值探针**（DEBUG 环境门控 `MWX_SCENE_DEBUG_LIGHT_TRACE`，SceneLightSnapshot 节流日志）拿到实际值，两段归因：

1. **typed lightAngles 单位=度**：ldirectional angles 脚本 `deg=-atan2(z,x)*180/PI; value.y=deg-180` 带作者度数方位表（x=-1,z=0→0°…），度数值被 directional() 按弧度直读 → 方向错 57.3× 因子。修：`SceneDynamicLayerValues.lightAngles` 的 typed 分支度→弧转换（authored JSON 角度的弧度合同不动——61 夹具仅覆盖 authored 路径；脚本边界官方按度换算，作者注释表即官方校准）。实机：帧均值 2.55→5.24、盘面带纹增强（方向值生效）。
2. **真因=可见性过滤丢灯**：trace 显示快照只有 directional、point 整帧缺失——`lpoint` 作者 `visible:false`（L1 复测已录）被 `visibleLayerIDs` 门控整灯跳过，而 **origin 脚本本身正常发布 `(-11.04, 0.003, …)`（太阳在 -X，正是官方左亮侧）**。修：`SceneLightSnapshot.make` 灯光层不再按可见集过滤（灯光对象无网格，`visible` 只隐藏编辑表示；官方数据 visible:false 且场景被点亮即官方行为），无用的 `visibleLayerIDs` 参数随删。实机：**双灯入快照**（point 433 position=(-11.64,0.003,-2.71) r=100 i=6.0 + directional 259），盘面亮侧翻到 -X（左），暗侧能量与官方完全一致（34.9 vs 35.7），环点亮（下左带 mean 17.7/max 108）。

## 当时与官方的差距（不能作为当前归因）

受光侧能量 0.44×（我方盘面左 37.2 vs 官方 84.5；暗侧 34.9 vs 35.7 完全一致 ⇒ 差异纯在直接光照能量）+ 光环偏暗（17.7 vs 88.3）。候选=逐灯能量分解（双灯叠加口径、衰减形状、响应曲线在真实 E 处的取值）——已登记的响应曲线开放族的延伸，需逐灯值探针带 albedo/NdotL 分解。

## 门禁

三产品文件（ValueRuntime 度→弧 / LightSnapshot 可见过滤+trace+参数 / SceneDrawing 调用点）推导 50 模块套件 **ALL OK**（含连带偿清 `test_scene_text_width_property` 的旧式裸 import 在并行 runner 下的收集失败——改 `script.tests.` 前缀）。

**推导盲区与探针迁移**：登记路由不含"直接编译产品文件的 harness 探针"——`test_scene_point_model_shadow` 与 `test_scene_static_model_pipeline` 直接编译 `SceneLightSnapshot.make`，两条钉旧合同（visibleLayerIDs 门控丢弃灯）的探针随本批迁移为新合同钉定：authored `visible:false` 的灯仍入快照（point_model_shadow 新增 hidden-author 场景反例）与脚本隐藏灯保留在四槽预算（static_model_pipeline bounded 集从 [17,15,12]+溢出1 改为 point[17,15]+spot[16]+溢出3）。独立全语料扫描：216 场景中 visible:false 灯光仅土星 433 一例，行为变更半径=已证实样本。后续 harness 类模块的门禁推导需补"编译该产品文件的测试"通道。

## 产物

`/private/tmp/mwx-l1-retest-20261007/saturn/`（修复后日志+14 张快照）保留至 2026-10-21；对比图 `/tmp/saturn-side-by-side.png`、`/tmp/saturn-disk-crops.png`（会话临时）。

<a id="effective-light-visibility"></a>
## 2026-10-09 有效可见性与方向纠正

起点 `d4cdb4fd`。固定土星作者天文日期为 `2026-10-09T12:00:00Z`，其累积模拟秒置零；其余脚本、全部模型/材质及相机保留。三包193个entry逐字节比对只有scene.json变化：baseline、仅删除隐藏点光433、仅关闭259方向光阴影。真实样本根只读，官方与Native消费相同包SHA；研究仅为黑盒，不消费私有实现。

官方2.8.0.42、1210×786在同输入baseline与删433之间，预选左/中/右球体及前环ROI的median RGB差均不超过3/255，右暗面逐像素相同。移除巨大479模型的同构轻型正控只改变433.visible：左球median RGB由140/125/107变为255/255/255，前环144/136/121变为255/255/253，右面均0。该证据推翻上面的单张截图归因，确认此输入的可见性门控，不决定照明公式。首次完整阴影组和完整visible正控因官方渲染异常/遮挡失效，未当作算法证据；恢复后轻型两组同PID、同输入身份并准确关闭。

初次只恢复visibility后，Native右侧亮、环带近黑；错误点光曾掩盖方向光错误，因此没有单独交付此中间态。后续四个固定法线±X/±Z模型按轮廓直径排序识别，避免按屏幕左右猜法线。官方三组同输入：child yaw π/4、parent0照亮−X/+Z；parent yaw改π/2照亮+X/+Z；child/parent均0仅−X亮。其余面全黑，几何边界漂移≤1px。这否定旧符号、忽略父旋转和零角默认−Z，不推导新的能量公式或全角度parity。

接线：frame已计算的有效visibility与world-frame直接送入唯一LightSnapshot。三类灯先按可见性过滤，再做类别、四槽容量和阴影准入；启动候选保全，使隐藏灯仍可重新显示。三类light leaf补入原visibility route和原Boolean candidate projection；父container沿原规则，模型混合子树没有扩大准入。方向光复用现有world-frame朝向，删除独立raw-angle解算器和已无调用的lightAngles helper；单位转换、脚本、父链及正交映射由通用transform链负责。direct/shadow共消费同一结果，没有第二旋转、显隐、属性或输出owner。standalone volumetric cone的inline脚本仍仅准入原exact intensity，不能把direct light Bool补接外推给cone。

验证：Debug构建、签名及全部Scene源身份一致；实际三探针12项明暗分类与官方一致，受光RGB 54/77对官方56/79，暗面均0。Native要求pkg，初次散装输入launch-failed且没有画面，其exit0不作成功；接受的pkg每entry与官方相同散装输入逐SHA对应。真实QuickJS三灯的child/parent Bool经typed publication→visibility→LightSnapshot/shadow得到[0,1,0,0,1]，实际live property hide/show与候选保全通过；静态/动态父旋转、无效轴局部拒绝及原灯影回归按最终日志冻结。

相邻App shadow夹具同步显式directional class与原world ray：directional z20→X20、parts/cull z20→X12，ROI不改。首轮parts通过，另4项因旧强度0.6在现行表面合同下只产生27/32、低于原无影区>50前提而失败；固定法线解析与实测一致。只将这两组自有输入强度改2，保持非饱和正控、阴影位置/相对阈值/动态恢复全部不变；没有为测试修改产品能量。最终4项App重跑通过（108.328秒），加前轮5材质段App项通过；原生Metal近门5项、方向/Boolean最近CPU23项及独立cone窄边界1项通过。此前38项与本次有重叠，不累加；新producer测试已接原登记组，相称selector门6项通过。

完整土星固定日期包在新App运行50秒、40秒取稳态图，startup约39秒，VM 92 owners/1 destroy callback全部quiescent、零失败且GPU drain。盘面恢复左亮右暗；预登记左/右ROI median RGB由107/99/86与63/59/52变为151/138/118与0/0/0，官方139/125/106与0/0/0。巨大479陨石环仍入链且颗粒可见。前环ROI由3/3/3升到19/18.5/17.5，但官方141/133/120；环带仍有扇形三角暗纹，文本/布局也未对齐。只冻结作者天文时间，实际时钟、媒体及其他随机内容不相同，不计算整图正确率。下一首断点是环带几何/法线、材质和阴影消费，需要有界消融定位，禁止全局补亮。

证据：`.artifacts/tmp/saturn-light-ablation-20261009/`内`direction-native-comparison.json`、`saturn-final-comparison.json`、`build-final.json`及CPU/GPU门；新App dylib SHA `d43dba2c9bc16886bb1e02ef95e06ad0ad664d01fc7d202eceef8f335a91b49e`，土星固定输入pkg SHA `b9d7255300d5399e25822330c26bb85e6f8a9a6cc00f77ba273498cbd8d2ad91`。官方任务窗口均关闭，VM已挂起。全样本、任意3D方向/父缩放、完整2D/阴影官方parity及性能改善未声明。


<a id="native-shadow-winding"></a>
## 2026-10-09 原生相机阴影面向纠正

起点 `69523150`。上批恢复正确灯输入后，土星环仍有大块三角暗纹。本批完整包消融表明，关闭全部方向光阴影使暗纹消失，但同时丢失星球投影；只关闭星环 caster 则主要暗纹消失。两者只是诊断输入，未作为产品修复。原包与全部模型在最终运行保留，没有按样本或材质名分支。

先前共面探针未复现错误，不能证明精度问题。随后通过原 DEBUG 出口临时采集真实 frame 的相机、模型、灯及投影；首次诊断因双重节流与 direct 入口缺相机参数未触发，修正后采到13帧，临时诊断已精确撤回。固定天文日期不等于冻结所有模型姿态，因此离线重放使用完整同一 epoch1441及原完整阴影范围。真实环是朝内的薄壳：GPU 深度读回与朝光背面的另一片几何匹配，误差远小于两片间距；绝大暗区不是需要加大 bias 的数值 acne。单变量面向纠正后，原228773个覆盖像素中ring-only暗像素从223886降到0，ring+sphere与sphere-only暗区一致，证明修正没有靠关闭星球投影。

根因是原生3D与画布相机的正面约定不同，shadow却固定CCW。现有`SceneParticleCameraFrame`同时提供native默认与逐层透视决议；direct/ordered准备路径都将同一frame传到原`emitModelShadow`，按每个caster解析面向，交给唯一`drawShadow`。原生且该层实际透视时使用CW，canvas/fitted、显式正交与utility保原CCW；每次draw显式设置，混合模型不沿用前一caster状态。directional/spot/point共用原入口，材质normal/nocull准入、shader、投影、bias和资源所有权不变。没有新增阴影算法或相机分类owner。

最终Debug App签名与全部Scene源码身份一致，dylib SHA `080bf84fc6eb33775891033c929c56d47c034b99739f34a3aa103884c8cadb8d`。完整土星固定日期包运行50秒、40秒取图，三角暗纹消失，星球左亮右暗、右上投影和陨石颗粒保留。原前环ROI median RGB从19/18.5/17.5改善到98/93/85.5，官方141/133/120；左球保持151/138/118。运行正常退出，92个VM owner全部quiescent、1次destroy、零失败且GPU drain。

前环剩余亮度、投影细节及文字/布局仍未关闭；不宣称完整土星或三类灯全部官方parity。新官方轻型A/B未执行：guest普通桌面黑，安全菜单可见，未把该前置失败算作渲染结果；VM已挂起。此前有效官方完整/轻型截图仍是有界视觉参照。

证据：`.artifacts/tmp/saturn-ring-20261009/`内`audit/candidate-freeze.json`、`audit/real-depth-analysis.json`、实际同帧重放、`build-final.json`、`native-final-comparison.json`与`native-final/baseline`。新增真实GPU门1项通过，覆盖三灯型、五相机族、正反绕序、normal/nocull及同map混合提交；4个既有caller仅做CPU typecheck并通过，不计运行测试。原有4项App回归（投影开关/缺caster、透视与父变换、灯移动恢复、八种材质cull）全部通过，旧画布oracle未改。新GPU门接入原rendering/material-segments测试组，三产品逐path预览均可选中，6项selector检查通过。测试开发中一次point peer采错atlas face，按射线最大分量纠正采样位置、保持原阈值；失败result仍存，原断言整日志被重跑覆盖的限制明确记录。结构/依赖/代码健康/防重复/设计门通过；全局文档检查仍只报并行Web的3个健康问题与1个入口反链问题，未混入本批。独立审查绑定最终freeze。


<a id="oblique-texture-sampling"></a>
## 2026-10-10 斜视纹理采样

同姿态、unlit、关闭Bloom的原环材质在Native偏暗。实际frame900的color/brightness/opacity/layerAlpha均为1，straight albedo和原9级mip完整入链。按实际mesh/UV复原预声明600像素ROI，普通trilinear的逐通道95%误差<0.88/255；该处纹理足迹长短轴比约34。仅保留原最高级mip后，Native中值从165/158/145变185/174/156.5；官方2.8.0.42同包两组ROI逐像素不变，仍181.5/175/159。这定位采样差异，不支持改灯光增益或重复alpha补偿。

唯一`SceneTextureSamplerStateSet.makeState`为linear启用Metal硬件16×各向异性过滤；nearest、寻址、UV、完整mip链及alpha保持原路径，不新增采样算法或资源owner。这是经有界视觉验证的项目质量策略，配置窄查未确认官方实际过滤倍数。保留全部mip的候选App在同包ROI对官方逐通道median误差0、最大1/255；恢复作者光照/Bloom的固定姿态前环中值118/114/104→131.5/126/115，官方140/133/120，尚有照明/后处理偏差，不宣称土星全画面一致。

证据位于`.artifacts/tmp/saturn-energy-20261009/`：`audit/sampler-candidate-comparison.json`、`audit/ring-roi-sampling-result.json`与输入/build收据。相关首断点与后继顺序回到派生队列；同轮自有7卡另确认两个字体的center文字锚点偏差，top/bottom一致、单行blockalign Bool无差异，尚未修改文字产品代码。硬件质量策略影响共享模型/材质/粒子sampler；未外推全样本或性能改善。

最终产品源码冻结后Debug构建/签名通过，dylib `0818e13a78208d9bab7f70bb56bf4582a46809ccaa1314ca29dc0fba4a5ddac8`。原始完整pkg `8cb79fa9f77c992c2bc3c3ea6300af0f058bf5e85b96ae1d1f300fdf3c037bb0`保留全部大型模型/脚本，最终App运行50秒并取40秒图，陨石可见，92/92脚本quiescent、零失败、GPU drain；使用隔离HOME和静音输入，不等于外部音源/交互验收。共享sampler自有GPU斜视/isotropic反例、nearest/四种寻址/方形足迹/单级控制通过；粒子filter/address/mip/straight-alpha、BC原mip保留和typed candidate近门通过。代码结构、依赖、防御与设计门通过；全仓Web文档及未知`.mimosa`残留检查另有非本批问题，未改动。候选与最终产品仅注释措辞有别，ROI证据保留候选身份，完整原包绑定最终身份；不宣称性能提升。


<a id="text-center-anchor"></a>
## 2026-10-10 文字中心锚点

自有同字体控制确认center偏差跨单行、两行、三行稳定，top/bottom正确；单行blockalign两值无差，不为该字段新增分支。原单行Chathura/Arial的H0中心对官方偏差25/9 viewport像素；多行在半比例画布分别偏12–12.5/4.5–5像素。复用resolved CoreText字体的descent/2作为逻辑源像素偏移，唯一pivot仅center消费；栅格、padding、装饰、换行、UV与最终输出owner不变。初始/动态纹理与extent/anchor合成一个raster结果，替换原并行字典；既有publication、fallback、effect源材质重发布保留同代锚点。cursor采用同Store最后已提交snapshot，避免异步ready提前改变位置；点击框仍为作者尺寸，未宣称动态墨迹或官方点击parity。

候选签名Debug App dylib `d2bd63df853d46bbc603ff069f049a7442f2a6d405756fceb94ca38c851d47a7`在7卡单行和12卡多行实际运行：每行H0中心对官方2.8.0.42差≤1 viewport像素，center差≤0.5；所有top/bottom相对Native修前位置不变。相同字体文件、原点marker、冻结作者输入与逐卡ROI绑定；不同系统hinting不作为逐像素相同。原有字号/自动换行/行数/省略号/留白/装饰/降采样反例通过；这些内部回归不外推所有字体官方parity。

证据：`.artifacts/tmp/saturn-text-anchor-20261010/`的`official/`、`audit/singleline-candidate-comparison.json`、`audit/multiline-candidate-comparison.json`、`build-candidate.json`。该修复适用于现有共用文字链，未新增字体/样本专用算法。土星亮度/Bloom、上后方投影、亚像素细线及完整媒体/交互验收仍开放。

完整原始土星包SHA `8cb79fa9f77c992c2bc3c3ea6300af0f058bf5e85b96ae1d1f300fdf3c037bb0`在同一候选App运行50秒、40秒取图，保留大型陨石模型与脚本；PID55491正常退出、92/92脚本quiescent、零失败、GPU drain。原包时间/音频未与官方冻结一致，仅证明新锚点进入真实3D/effect/最终合成链和运行收尾，不作为整图parity或性能验收。


<a id="directional-material-response"></a>
## 方向光消费既有模型表面响应（2026-10-10）

起点`82a4dc3c`（Scene为`3d934ffd`）。当前AF/文字版本的同姿态有影无Bloom对照仍有球亮侧偏亮、前环偏暗；球及环unlit对照排除了简单底图增益解释。复用四固定法线/不同直径的自有几何，固定实际作者child/parent角度，唯一材质变量为metallic 0→0.14，roughness保持1。官方2.8.0.42的−X区域从238降至190，原Native两图完全相同、均229；其它三法线保原始低值，不用亮暗分类推断完整BRDF或3D旋转合同。

修复沿已准入的`surfaceProfile`进入既有表面求值，directional/point/spot收拢同一组合入口；不新建BRDF、材质状态、方向或合成链。nil profile保legacy，显式metallic0仍使用surface；shadow作用于完整直接光响应，ambient/emission及coverage、雾、最终预乘各保原序。未扩大动态MR、贴图或作者shader override准入；实现前取舍见[D3](../roadmap/batch2/2d-lighting-material-design.md#generic4-模型静态表面响应2026-10-09有界后继)。

冻结候选App的8个四法线ROI中值与官方全部一致：neutral `[0,238,5,0]`，metallic0.14 `[0,190,4,0]`。真实有影无Bloom包SHA`c49bdf2f…0e29032`在固定区域得到：

| 区域 | 修复前RGB中值 | 修复后RGB中值 | 官方RGB中值 |
|---|---|---|---|
| 球体左亮侧 | 126/115/98 | 114/105/91 | 116/107/92 |
| 前环 | 116.5/112/101.5 | 120/116/105 | 120/116/105 |

这是同一共用材质修复同时减少相反偏差，不是全局曝光补偿；球仍有1–2阶残差，区域中值不能升级为整图像素一致。输入、官方GDI、各版App/source身份及固定ROI保留于`.artifacts/tmp/saturn-light-residual-20261010/`。后继仍需处理上后方投影与亚像素细线，并保留完整媒体/交互验收边界。

保留Bloom的同姿态包SHA`e44babef…596e2ef`中，球左从146/134/114变为128/118/103（官方134/123/105），前环从131.5/126/115变为137.5/132/120.5（官方140/133/119.5）。该结果仍有Bloom端残差，不能将本次材质修复记为完整亮度/Bloom验收。

隔离Debug/签名通过，762个Scene输入按最终三产品文件冻结，dylib `f0570670…56a9da6`。有影无Bloom、同姿态有Bloom及原完整包均exit0并GPU drained；原包SHA`8cb79fa9…c037bb0`运行91.86秒，92/92脚本owner quiescent、0 teardown failure，实际图保留大型陨石环、球体及文字。该原包用实时日期，只作完整资源/合成回归，不与冻结官方姿态混算parity。已停止HOME/TMP清理，留必要PNG/收据及共用构建缓存。

最近回归：emission 5项、directional shadow 2项、模型pipeline/准入5项及parts 3项通过，保nil旧输出、point/spot既有外部oracle、显式0/.14、unlit、coverage/HDR和材质分段。旧parts首次失败来自上批文字入口的共享非目标stub签名陈旧，本批只同步原共享stub，不新增产品分支。Scene结构/依赖/防御/设计及文档健康通过；全仓code-health、文档导航和residue分别仍报告并行Web的1008行文件、既存Web设计回链及未知归属`.mimosa`，保留并未当作本批通过。独立审查分别核产品、官方/候选ROI、运行身份及有界声明。
