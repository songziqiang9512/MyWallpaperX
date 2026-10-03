<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF14：真实模型聚光阴影（2026-10-02）

> **历史证据 — 非现役入口**。 本片已获独立产品终审 **ACCEPT RF14 coherent v1**。设计前置提交 `8a4db9b7`，同职责投影数据抽取补充 `0adc0ec4`。本机证据根 `/private/tmp/mwx-rf14/`。

同页历史分节：[已退役设计裁决](#rf14-retired-design)。

## 实际结果与职责

现总四灯准入内全部显式 cast-on spot，可对主链已经准备的真实静态及 source-only named 模型三角形成遮挡。原第一 cast-on directional 优先，其后 spot 按作者顺序；最多四张图，不新增灯、图资源或 compositor 权威。每张图只调制对应灯的 direct，保其它灯、ambient、emission、alpha 和原显示输出。point 全向及其它 directional 仍属后继。

spot 的严格投影开关沿原 SceneShadowCastIntent；typed light snapshot 携带当前身份、意图与锥域参数。原 mandatory 与 RF13 作者序准备只执行一次，原模型主颜色仍一次消费。现 pool 用有界候选槽复用，失败不压缩槽号；成功资源立即 pin 到同提交 completion，某灯失败保其 direct 和其它成功灯。原单图 record/ABI 完整替换为统一 typed 记录与固定四槽 ABI，投影数据从原 Pipeline 移至同职责文件，没有兼容 wrapper 或新 atlas manager。

## 旧反例与独立方法

原 RF13 不可变 App 的四组自有合法 MDL 输入中，cast-on/off/no-caster 两接收 ROI 均62，light-off为9；灯光实际贡献53，而 cast switch 整图完全相同。目标至少变暗20的预注册门为红。独立灯射线与三角确定遮挡和健康位置，主相机射线不经过 caster。旧协议 SHA `3ecb04a512c3b6e854631939b780bf4f30d055c19e8f9b3bdd370a7674b9d8e9`；目录 `baseline-omag2q3t`。

参考资料只提供作者行为、输入和生命周期依据。有限锥投影、几何面深度及接收滤波由本项目独立实现，未复制参考代码或私有公式。最初公开 API 微证直接采用光栅插值轴深度，三个非对齐输入超过原2e-6门；同输入改用实际三角面与 fragment 采样灯射线交点后通过。原红与对齐坐标正控保留，未放宽阈值或增大 bias。实际产品另外使用真实 PSO/backcull、14个输入验证，最大误差约9.62e-8；含非退化双负w、窄宽锥96extent及反面全clear。

严格布尔旧探针证明数字1/0会被原spot宽松桥接为Bool；修复复用已有严格判据。探针字符串转义编译失败、depth壳首轮统一反转winding错误和half输入.5001量化为.5，均属测试基础设施/输入问题，保留现场，不计作三个新产品缺陷。half阈值门改用原存储可精确表示的相邻值；产品coverage阈值未改。

## 冻结身份与运行范围

十产品清单 `implementation/checkpoint-v1-products.json` SHA `33ea91f58bb2318cecaad4a7f8e224f6d5a9dd22e385dcd4c975c02522db9ec8`，diff SHA `9e3f1d0d83cec2bb145a96e7612a1e867e9e654eba7b4b1a59e3082fc436d6c2`。完整 Debug 构建通过，前后十产品身份相同；本机签名 App `source-v1.app` 的五文件身份见 `build-v1/identity.json`，dylib SHA `478eda74b7b45f4acc924f6d10e6c6227a1367158e5d1f345121d5180efa206b`。deep strict 与两个 helper Team requirement 通过，不是公证或发布验收。

`app-v1-e10jqd5y` 原四输入逐字节重用：新 cast-on shadow9/healthy62/caster绿118，off为62/62，no-caster62/62，light-off9/9。ready/after整图相同，后三组与旧App各自整图相同。五App文件、输入和运行源身份一致；frame1/2、shadow写入/接收/completion及安全drain成立。独立审查重算PNG接受这段有限证据，协议SHA `70b14d1f2643efd1ab055496c534f5cd13f851caf0ff5ffbd9e58547904e7560`。独立体积光路径的 spot-light failed 诊断不代表模型直射失败，direct正控与阴影变化区分两条消费路径。

`mixed-app-v1-e8ybx5sa` 另5次App执行：四spot与directional+三spot分别on/off，四个独立遮挡ROI只减少对应颜色通道，健康区与其它通道exact；前者选中通道分别减少23、56、42.33、14，后者第一方向光减少66，其余相同。四个当前light身份都有完成事件，off不生成map。动态spot位置80→100→80时两接收ROI由9/65换为65/9再恢复，健康区始终48；两张中间快照证实换位，ready/after整图exact。五App文件、执行源和输入预冻结，协议SHA `c5ee74735a29bb34759d6f322c05aa8e1c0f3704a784179dea673e84e08e86e2`。合计9次新App输入执行，不称单次全量套件。

多灯数值测试初稿错误地把每个颜色输出视为单次half舍入；实际既有shader包含lighting转换、surface乘法与alpha乘法。独审确认后按原预注册每项两half ULP工程容差及表达式系数传播修订，并保留等效模式逐值相同门。原红保留，未改shader、几何门或单灯容差，也不将工程容差称严格全域误差定理。

新spot十个唯一方法已分组通过：原九个方法覆盖17个深度向量、33个radiance输入、12个多灯输入、8个frame owner输入、3个named组合，另有9项parser取值与实际snapshot。旧邻接36个唯一方法：directional7、FrameOwner3、snapshot7、named11、staticmodel6、spot plan1、spot rendering1；按分组执行，不累计复验次数或把编译失败当方法通过。另一个方法专门验证部分写入后未发布图的生命周期。

最终测试索引 `test-final-v1.json` SHA `a0ff0b1357fac00cac20c1a8b016fbde70e4dee44b6c27c99c8a2f32ce784b8b`，root与独审均核154个显式artifact身份匹配。新模块最终SHA `31c4ea558783faf526468de76062892babf1050a644e220bf77eee2fec3e9315`；实际新一旧六共7测试文件变更，未改的spot rendering另有通过证据。46个唯一方法按索引逐一追到实际通过行。索引初版只有spot plan方法后缀重复，已更正metadata且保留原字节，未改结果或计数。

原frame owner的8输入使用真实pool/native quota，mandatory模型/粒子租约只准备与消费一次；配额仅容0/1/2图时保健康原颜色，directional优先和真实tiny-angle中间失败后的候选槽空洞得到验证。在飞A持4图，reset后B将相机target64改128再取消，A完成后C重新准备4图、真实模型draw及completion成功。图仍固定1024且灯ID未换；这是pool逻辑驻留与提交寿命，不是阴影图resize或Metal对象已析构的证明。terminal closure计数不替代完整Bloom/display容量，邻接原snapshot/named门另验原消费相位。

partial门1方法44.619s：实际CPU RuntimeModelBuilder从作者alpha1e100产出有限Double，按现material转换为不可表示Float，随后在已证明的prepared边界输入实际frame owner。第一caster写出65536个有限非clear深度像素，第二被原guard拒绝，零图发布且pin为1；SharedEvent阻塞中reset保4194304逻辑字节，completion后归零。GPU资源builder未实编，此输入不是端到端加载证明；仍持纹理强引用时，不把逻辑计费归零称物理析构。

named聚光门3输入使用真实ordered/capture/publication与模型GPU consumer，同provider供caster及两个cast=false receiver；这是有准备壳的native证据，不冒称新增named-spot完整App。最终广义协议标签的实际执行边界固定在 `coverage-final-v1.md` SHA `1761a05cd8bca619fbdb647c0138003c28374685118fed996ba19de48377d81f`。实际Pipeline的透视/模型scale与translation已验；本片未新验完整App perspective、作者parent遍历、pending换灯ID、跨queue、多屏或所有feature组合。

code-health通过：1056 Swift、0 locked legacy、8 locked review warnings、240 warnings；scene-defense通过：0 locked dead、18 canonical、3 swallow，保留历史acknowledgement提示；design-gate通过。文档角色13方法通过。未增加结构/防御预算；新投影数据文件仅登记原Rendering.Metal职责。

## 未验范围与后继

不以自有输入宣称官方像素parity、完整原包spot可见收益、性能、所有model格式、普通image/Puppet/particle阴影或全部light atlas。片元写depth可能限制early depth优化，四张1024²图是有界项目质量选择，尚无性能改善结论。

下一主片推进point完整全向域与接缝，通过原typed灯/几何/pool/提交及唯一输出链实现，不用单面图冒充全向。参考方法缺失由独立算法和实验补足；确需外部语义的部分先定行为规格，不把未知扩大为整项跳过。


## 终审与移交

独立报告 `product-final-review-v1.md` SHA `12f2c0d23b6f1cc36a2e983a3e1f9e11ec8b26f210eeac139865a269769b3e17` 接受上述10产品、7变更测试与最终索引，无未关闭产品finding；其重算17depth最大误差约9.62e-8，33radiance均匹配对应A/Full控制，多灯最大误差仅为原工程传播界约0.273，等效权重模式逐值相同。稳定职责移交[架构](../architecture/runtime-architecture.md)，[本批设计](rf14-model-spot-shadow-implementation-2026-10-02.md#rf14-retired-design)归档并删除窄gate；[RF15工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf15-model-point-shadow)承接下一设计与实施。按职责窄提交，不包含并行layout排序或census索引改动；未推送。GPU/App执行结束，原失败现场和精确证据根保留本机。

<a id="rf14-retired-design"></a>

## 已退役设计裁决

下文完整保留该阶段的历史裁决、证据身份和未验证边界；其中状态与后继顺序仅适用于原记录日期。

<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

<a id="rf14-retired-design--rf14-真实模型聚光阴影退役设计"></a>
### RF14 — 真实模型聚光阴影（退役设计）

> **历史证据 — 非现役入口**。 设计批准与实施时的裁决完整保留。RF14已获独立产品终审，窄gate退役；现役职责由[架构](../architecture/runtime-architecture.md)接管，结果及未验边界见[执行记录](rf14-model-spot-shadow-implementation-2026-10-02.md)。下文的“当前”“可实施”仅指前置设计时点。

基线 `170d48dd`。[工作卡](../roadmap/batch2/reference-evidence-implementation-cards.md#rf14-model-spot-shadow)承接RF13；本设计已获独立设计ACCEPT，`scene-static-model-spot-shadow`为`approved`，产品可在前置提交后按本文实施；运行能力尚未验收。本文保存行为合同和项目选型，不含参考代码、私有表达或算法公式。

<a id="rf14-retired-design--目标合同与证据"></a>
#### 目标合同与证据

当前四灯总准入内，全部显式cast-on spot对已合法显示的真实模型几何形成遮挡，包括RF13已准入source-only named albedo。每灯覆盖完整有限前向锥域；只衰减该spot的direct贡献，保其它灯、ambient、emission、alpha与唯一输出。模型默认cast、显式false仍receive、unlit仍可cast；coverage沿现F6合同，不新造receive作者字段。普通image、Puppet、particle不虚构几何成为caster。

[官方3D Advanced Lighting](https://docs.wallpaperengine.io/en/scene/models/lighting.html)提供三光型可投影、逐灯开启与逐模型关闭的公开目标；其未规定投影数值或预算。现役中性入口为[D3 F6](../roadmap/batch2/2d-lighting-material-design.md#f6-model-directional-shadow)。[Mirage参考](../development/reference/miragewallpaper-rendering-reference.md)§6.4支持资源读写版本职责检查，§8.4只有灯输入/shadow flag且无完整atlas；不采用其整灯抑制策略，不据此推断官方算法。缺少可照搬的方法不关闭该能力，以下选择由本项目独立实现和验证。

当前没有已证实的完整原包spot/model可见受益，不以声明数量替代消费证据。首先交付自有合法MDL与lspot组合的真实新能力，再以真实输入扩展；不宣称官方像素一致性。

<a id="rf14-retired-design--修前行为与设计裁决"></a>
#### 修前行为与设计裁决

不可变RF13 App四次新隔离启动已证真实缺影：cast-on/off及no-caster两接收ROI均为62，light-off为9；direct正控差53。on/off整图像素完全相同，目标至少暗20的预登记阴影门为RED。自有三角与独立射线oracle事先确定被遮挡和健康等距位置，主相机不遮住这些位置。四输入exit0、frame0/1/2完成、GPU drain、输入/App不变，ready/after一致；没有shadow事件。`phase=spot-light status=failed`属于另一条volumetric cone路径，不能据此否定已由正控证明的模型direct贡献。

证据根`/private/tmp/mwx-rf14/baseline-omag2q3t/`；protocol SHA `3ecb04a512c3b6e854631939b780bf4f30d055c19e8f9b3bdd370a7674b9d8e9`，index SHA `b465c8d368736ed6b083014cbadafdd8148dd80adc5b318eebaa5d20e2c5619a`。两个编译helper身份为执行后补核，与原App build身份一致，不追写预执行协议。原两parser实编探针`/private/tmp/mwx-rf14/bool-baseline/`另证明数字1/0被当前spot桥接为Bool，而原严格cast parser正确判invalid；显式true/false保持。探针首轮字符串转义编译失败保留，不计产品反例。

独立设计ACCEPT绑定v2 freeze SHA `0e821a6bc6e4defb640b0f5ac231d1df49ddff42c57a9603d6b8b86260f61ed6`；报告`/private/tmp/mwx-rf14/design-review.md` SHA `c04035e9d21d8437cd642974725f4a9e8b5674fc6415a05162d79242cca77c91`。v2裁决批准原九文件方案与后述先导/产品门，不证明深度API、空槽ABI或任何新GPU输出已通过。并行历史索引条目不纳本批。

<a id="rf14-retired-design--当前事实首断点与owner"></a>
#### 当前事实、首断点与owner

以下路径相对`MyWallpaperX/Core/SteamWorkshopScene/`，行号固定于基线：

- `Format/SceneSpotLightDefinition.swift:19,37`保存castshadow，但Foundation的宽松Bool桥接需要原严格布尔parser收敛；数字0/1与显式布尔用真实解析反例区分。`SceneShadowCastIntent`拥有既有严格判据，不增加第二parser。
- `Rendering/Lighting/SceneLightSnapshot.swift:23–30,239–247`的Spot未携带layer identity/cast意图，这是首个确定缺边；`:65–104`按作者顺序准入总计最多四灯，`:223–247`拥有当前world方向、位置、cone/radius与动态颜色强度。新投影只消费此typed snapshot，不再次读作者JSON。保留投影所需的outer角度，不能仅从量化后cosine反解小锥。
- `Rendering/Frame/SceneMetalRenderer.swift:280–319`只以directional触发mandatory；`Frame/SceneMetalRenderer+StaticModels.swift:248–451`已拥有静态/作者序准备、统一draw集合、shadow emitter、pins与cancel/arm。扩展现集合，不增加spot frame owner或重复准备mandatory。
- `Rendering/Metal/SceneStaticModelPipeline.swift:180–198,419–424,522–551`只携带和验证一张directional图；`Rendering/Composition/SceneStaticModel.metal:178–203`的spot直射没有visibility。同一record/ABI/材质累加位置必须闭合，不能只补字段。
- `Rendering/Targets/SceneOffscreenTexturePool.swift:167–227`的单directional key不能同时持有多灯图；原allocation cache与SharedPair拥有物理预算、pin、retired及格式匹配。扩成原owner内有界槽，不能另建atlas manager或registry。

判据①跨typed灯、frame、pool和GPU consumer，②触及identity/ABI/生命周期，④触及冻结结构家族，⑤目标依赖官方作者合同；均命中设计前置。此批不改持久化格式或用户数据。

<a id="rf14-retired-design--选型与替代方案"></a>
#### 选型与替代方案

选择现总四灯内全部cast-on spot；现第一盏cast-on directional先保留，再按spot作者顺序逐灯尝试，因此最多四张图。其它directional保原一灯边界，point保现direct，待下一片实现完整全向域。仅第一spot会留下同一合法灯族的确定缺口，不采用；以一张方向图冒充point也不采用。

<a id="rf14-retired-design--完整锥域独立深度策略"></a>
##### 完整锥域、独立深度策略

使用灯的当前位置/方向建立透视锥，透视XY与片元正向轴深度配合；覆盖现spot直射衰减的有效范围，包括其现有极小radius数值保护。outer视野须包含作者角和当前cosine量化所表达的照明域，inner不缩小投影范围。投影从相对灯位置构造，避免无必要的大世界平移消去；参数由高精度CPU计算后核可表示性。

不设置任意正near而永久漏掉近灯caster，不因某顶点在灯后就丢弃整三角。灯源平面、锥侧与跨平面三角交由真实齐次裁剪，片元在原coverage后写正向轴深度；球域外本来无direct贡献，不产生投影。该方案是本项目待验证的实现选择；[Apple深度接口](https://developer.apple.com/documentation/metal/calculating-primitive-visibility-using-depth-testing)和[公开MSL规格](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)只是接口依据。规格PDF在草案研究中未成功读取，不能把具体裁剪/片元depth组合声称为已证；批准后先导MSL编译与真实三角门必须先验证。

先导执行已纠正轴深度的具体消费点：直接使用光栅插值的位置深度，在非对齐三角上与理想采样灯射线发生偏差；原8组、固定误差门下最大误差约0.000122。由插值位置的真实caster几何面与实际fragment采样中心射线求交，保持同一输入/门后8组通过、最大误差约0.000000217。原红、对齐坐标正控与修正结果保留在`/private/tmp/mwx-rf14/`，只证明公开API微证，不代表产品。

这项澄清已独立接受，仍是同一完整锥和轴深度合同：现depth uniform传实际target extent，fragment位置已经是采样中心，不重复增加半像素；caster导数在coverage/discard分支前取得，实际无定义平面/交点只丢对应片元，不写NaN或退回未校正深度。原微证的无剔除、直角锥和64像素目标不能替代实际产品PSO、其它角度、self与正负间隙门；不改变原directional策略。

保留原directional投影和质量策略，不把它的affine深度梯度直接用于spot。worldPosition导数须在进入spot循环的距离、cone等非一致分支前统一取得，不能在分支内首次求导。spot接收端从当前真实几何的屏幕导数取接收面，按各实际采样texel的灯射线与该面交点作深度比较。材质shading normal不替代几何面。沿原九tap数量和实际texel中心取样；落在有效域外或不存在有效前向交点的tap局部回无影，不用假深度或随意斜率阈值。

数值裕量须对实际相对坐标、旋转、几何面及透视除法传播舍入尺度，保持原算术系数的预注册选择；不看PNG反推bias，不靠放大全局bias掩盖self-shadow。相同几何的self-plane、正间隙与负间隙须配对通过；极端不可表示时只退化对应projection/tap，不把常规窄锥或跨灯面归入极端。实际退化producer是作者有限但接近表示极限的角度/radius/transform，或光栅edge-on/helper quad导致的退化接收面；必须有可执行输入，不能增无producer guard。

片元写depth可能限制early depth优化，最多四次1024² depth32Float写入是有界成本，不宣称性能最优。禁止逐帧编译/建图；质量UI和通用atlas平台不作本片前置。

<a id="rf14-retired-design--唯一记录资源与消费"></a>
##### 唯一记录、资源与消费

现`SceneStaticModelShadow`改为同一typed projection记录，容纳directional与spot两种策略，每条继续绑定actual texture、frameEpoch、generation、light identity与command buffer。同一frame集合替换原scalar，旧单record、单texture/parameters ABI同批退役，不保双系统。新增spot PSO或depth state在load准备失败时，仅使spot optional不可用，沿原pipeline的optional shadow state合同保模型颜色和现directional；不得把它加入必需颜色pipeline的失败guard。当前灯型、id/cast、epoch与CB验证后才绑定GPU；不能以颜色/位置猜灯身份。固定最多四项ABI，Swift/MSL布局和多texture绑定经实际编译验证。无效槽不采样；若Metal绑定要求占位，复用已有成功图而非新造fallback纹理。没有成功图则走原无影draw。

原pool key替换为最多四个model-shadow槽；槽按候选位置稳定编号，directional在前，失败不得压缩槽号使后灯覆写前灯。真实light id仍由record持有，slot只管理复用，不成为identity权威。使用有界slot而非长期light-id键，避免动态灯留下无界历史缓存。现generation/retired/pin保证不同在飞提交不覆写，depth格式、usage、逻辑与实际物理预算沿原owner。

每灯成功分配后即持有原submission pin，再尝试后灯。后灯配额/encoder失败只能不发布该灯，不能逐出已成功directional/spot。已编码但未完整生成的图仍pin到该CB结束；未提交可取消，提交后只由completion释放。reset使在飞资源进入原retired集合，最终释放回原物理预算。新一帧灯的数量/身份/位置/方向/cone变化必须重写当前图，不复用旧光结果。

<a id="rf14-retired-design--mandatory只准备与消费一次"></a>
##### Mandatory只准备与消费一次

原静态路径与RF13作者序路径保原资源次序、draw集合和depth计划；shadow候选非空时只触发一次。原forward、source-only捕获、lighting payload、snapshot、粒子depth、Bloom/display不得按灯数重复执行。完整mandatory之后逐灯做optional投影，普通mandatory失败保原prefix/suffix，停止本帧所有optional影图。某spot optional失败不影响其它成功灯与健康direct。模型主颜色仍只draw一次，在原spot累加位置乘本灯visibility，point/ambient/emission/alpha/HDR输出不变。

<a id="rf14-retired-design--精确实施边界"></a>
#### 精确实施边界

只触达以下十个产品文件，职责仍由既有owner承担（相对`MyWallpaperX/Core/SteamWorkshopScene/`）：

1. `Format/SceneSpotLightDefinition.swift`：原严格cast布尔解析。
2. `Rendering/Lighting/SceneLightSnapshot.swift`：当前light identity/cast和投影参数。
3. `Rendering/Frame/SceneMetalRenderer.swift`：同一mandatory触发与候选。
4. `Rendering/Frame/SceneMetalRenderer+StaticModels.swift`：同一准备集合、多图emitter和pins。
5. `Rendering/Metal/SceneStaticModelPipeline.swift`：独立spot projection、统一record/ABI、准备期PSO与draw。
6. `Rendering/Composition/SceneStaticModel.metal`：spot深度与真实receiver面visibility。
7. `Rendering/Targets/SceneOffscreenTexturePool.swift`：原单图入口扩成有界slot。
8. `Rendering/Targets/SceneOffscreenTextureAllocationCache.swift`：key与pin/retired匹配。
9. `Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift`：既有candidate格式/usage匹配。
10. `Rendering/Metal/SceneStaticModelShadow.swift`：从原Pipeline完整移出的directional projection与统一shadow record，加独立spot projection；只承载数据/数学。

结构补充已独立接受：原Pipeline基线873行，新增projection与四槽ABI将越过1000硬限；因此按同一职责抽出上述第10文件。原定义完整删除，不留别名或wrapper；新文件不负责allocation、pin、arm/cancel、PSO或encode，uniform/PSO/draw仍在原Pipeline。source-layout只登记此文件，不扩家族/行数预算，不混并行排序。此补充不改变已批准算法或运行验收范围。

测试由独立owner实现，新spot输入及既有directional/RF13测试只适配必要ABI，不降低原断言。若还需产品路径，先指出具体consumer缺边并修订设计，不能新增万能wrapper。保护的台账、运行证据和重构计划不写；稳定移交通过本批历史记录、架构和唯一路线完成。

<a id="rf14-retired-design--纠正门与失败处理"></a>
#### 纠正门与失败处理

先固定自有真实MDL、spot、独立Double世界ray/triangle oracle及ROI；expected不能调用产品projector/visibility。旧App须证明未遮挡direct正控、cast-on/off均缺影、模型主颜色和正常completion存在，再要求新版本仅在射线被遮挡处减少本灯贡献。主相机遮挡不能冒充灯阴影。

- 完整App：cast on/off、no-caster、light-off、健康peer、当前publication/terminal/completion/next-frame与安全退出；四spot可区分输入及directional加spot，逐灯切cast不串图。原总灯数不扩。
- GPU几何：不同深度/偏轴/宽窄锥、非恒定透视插值、锥内外/球far边界、灯背面与跨灯源平面三角；世界/parent变换和主相机改变不改变同一灯射线合同。先导失败留反例并纠正同一投影，不能改为永久near盲区。
- 质量/coverage：多个斜率/非中心texel/大平移下self-plane与正负近间隙配对；alpha阈值两侧、tint-mask、unlit caster、castfalse receiver、同provider两个named消费者、冷帧/实际target resize/下一epoch。缺源保健康颜色，恢复沿原owner。
- 资源：真实native budget只能容directional、directional加首spot及四图的边界；mandatory成功不被可选图抢占，后灯失败保前灯。实际epoch/CB/light身份生产与消费不匹配拒该记录，不能只用伪造record证明主链。
- 生命周期：阻住已提交A，再以改变的灯/目标准备B并取消/reset；A图不能alias覆写，retired预算到completion后释放，随后C恢复。hash固定source/App/测试/输入，不能用pool计数替代实际像素或completion。

Swift/Metal与Debug构建、code-health、scene-defense、design-gate及文档门按实际失败半径执行；完整App与native prepared-owner壳分别标明覆盖范围。独立终审逐条核新guard的producer、旧单图职责退役、多灯真实输出与失败半径。构建/非黑/route数不能证明本片完成；性能、官方parity、原包收益、多屏和point全向域无证据不宣称。

<a id="rf14-retired-design--退役条件与后继"></a>
#### 退役条件与后继

完整有限锥输出、全准入spot及混directional、资源生命周期门和独立产品终审通过后，稳定职责移交[runtime architecture](../architecture/runtime-architecture.md)，冻结证据入历史、本文归档并删除窄gate。下一主片在现透视/资源链上做point全向投影与面接缝；不能以本片通过关闭整个D3。reader差额若有具体中性归因与主构图收益，可由[唯一路线](../roadmap/scene-compatibility-roadmap.md)重新排序。
