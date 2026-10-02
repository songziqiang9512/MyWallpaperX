<!-- document-role: active-plan -->
<!-- retirementCondition: 已准入聚光灯对真实模型的完整有限锥投影经旧反例、实际GPU/App、多灯资源生命周期及独立终审通过，稳定职责移交架构、冻结结果归历史后归档本文并删除窄gate。 -->

# RF14 — 真实模型聚光阴影

基线 `170d48dd`。[工作卡](reference-evidence-implementation-cards.md#rf14-model-spot-shadow)承接RF13；本设计已获独立设计ACCEPT，`scene-static-model-spot-shadow`为`approved`，产品可在前置提交后按本文实施；运行能力尚未验收。本文保存行为合同和项目选型，不含参考代码、私有表达或算法公式。

## 目标合同与证据

当前四灯总准入内，全部显式cast-on spot对已合法显示的真实模型几何形成遮挡，包括RF13已准入source-only named albedo。每灯覆盖完整有限前向锥域；只衰减该spot的direct贡献，保其它灯、ambient、emission、alpha与唯一输出。模型默认cast、显式false仍receive、unlit仍可cast；coverage沿现F6合同，不新造receive作者字段。普通image、Puppet、particle不虚构几何成为caster。

[官方3D Advanced Lighting](https://docs.wallpaperengine.io/en/scene/models/lighting.html)提供三光型可投影、逐灯开启与逐模型关闭的公开目标；其未规定投影数值或预算。现役中性入口为[D3 F6](2d-lighting-material-design.md#f6-model-directional-shadow)。[Mirage参考](../semantics/miragewallpaper-rendering-reference.md)§6.4支持资源读写版本职责检查，§8.4只有灯输入/shadow flag且无完整atlas；不采用其整灯抑制策略，不据此推断官方算法。缺少可照搬的方法不关闭该能力，以下选择由本项目独立实现和验证。

当前没有已证实的完整原包spot/model可见受益，不以声明数量替代消费证据。首先交付自有合法MDL与lspot组合的真实新能力，再以真实输入扩展；不宣称官方像素一致性。

## 修前行为与设计裁决

不可变RF13 App四次新隔离启动已证真实缺影：cast-on/off及no-caster两接收ROI均为62，light-off为9；direct正控差53。on/off整图像素完全相同，目标至少暗20的预登记阴影门为RED。自有三角与独立射线oracle事先确定被遮挡和健康等距位置，主相机不遮住这些位置。四输入exit0、frame0/1/2完成、GPU drain、输入/App不变，ready/after一致；没有shadow事件。`phase=spot-light status=failed`属于另一条volumetric cone路径，不能据此否定已由正控证明的模型direct贡献。

证据根`/private/tmp/mwx-rf14/baseline-omag2q3t/`；protocol SHA `3ecb04a512c3b6e854631939b780bf4f30d055c19e8f9b3bdd370a7674b9d8e9`，index SHA `b465c8d368736ed6b083014cbadafdd8148dd80adc5b318eebaa5d20e2c5619a`。两个编译helper身份为执行后补核，与原App build身份一致，不追写预执行协议。原两parser实编探针`/private/tmp/mwx-rf14/bool-baseline/`另证明数字1/0被当前spot桥接为Bool，而原严格cast parser正确判invalid；显式true/false保持。探针首轮字符串转义编译失败保留，不计产品反例。

独立设计ACCEPT绑定v2 freeze SHA `0e821a6bc6e4defb640b0f5ac231d1df49ddff42c57a9603d6b8b86260f61ed6`；报告`/private/tmp/mwx-rf14/design-review.md` SHA `c04035e9d21d8437cd642974725f4a9e8b5674fc6415a05162d79242cca77c91`。裁决仅批准九owner方案与后述先导/产品门，不证明深度API、空槽ABI或任何新GPU输出已通过。并行历史索引条目不纳本批。

## 当前事实、首断点与owner

以下路径相对`MyWallpaperX/Core/SteamWorkshopScene/`，行号固定于基线：

- `Format/SceneSpotLightDefinition.swift:19,37`保存castshadow，但Foundation的宽松Bool桥接需要原严格布尔parser收敛；数字0/1与显式布尔用真实解析反例区分。`SceneShadowCastIntent`拥有既有严格判据，不增加第二parser。
- `Rendering/Lighting/SceneLightSnapshot.swift:23–30,239–247`的Spot未携带layer identity/cast意图，这是首个确定缺边；`:65–104`按作者顺序准入总计最多四灯，`:223–247`拥有当前world方向、位置、cone/radius与动态颜色强度。新投影只消费此typed snapshot，不再次读作者JSON。保留投影所需的outer角度，不能仅从量化后cosine反解小锥。
- `Rendering/Frame/SceneMetalRenderer.swift:280–319`只以directional触发mandatory；`Frame/SceneMetalRenderer+StaticModels.swift:248–451`已拥有静态/作者序准备、统一draw集合、shadow emitter、pins与cancel/arm。扩展现集合，不增加spot frame owner或重复准备mandatory。
- `Rendering/Metal/SceneStaticModelPipeline.swift:180–198,419–424,522–551`只携带和验证一张directional图；`Rendering/Composition/SceneStaticModel.metal:178–203`的spot直射没有visibility。同一record/ABI/材质累加位置必须闭合，不能只补字段。
- `Rendering/Targets/SceneOffscreenTexturePool.swift:167–227`的单directional key不能同时持有多灯图；原allocation cache与SharedPair拥有物理预算、pin、retired及格式匹配。扩成原owner内有界槽，不能另建atlas manager或registry。

判据①跨typed灯、frame、pool和GPU consumer，②触及identity/ABI/生命周期，④触及冻结结构家族，⑤目标依赖官方作者合同；均命中设计前置。此批不改持久化格式或用户数据。

## 选型与替代方案

选择现总四灯内全部cast-on spot；现第一盏cast-on directional先保留，再按spot作者顺序逐灯尝试，因此最多四张图。其它directional保原一灯边界，point保现direct，待下一片实现完整全向域。仅第一spot会留下同一合法灯族的确定缺口，不采用；以一张方向图冒充point也不采用。

### 完整锥域、独立深度策略

使用灯的当前位置/方向建立透视锥，透视XY与片元正向轴深度配合；覆盖现spot直射衰减的有效范围，包括其现有极小radius数值保护。outer视野须包含作者角和当前cosine量化所表达的照明域，inner不缩小投影范围。投影从相对灯位置构造，避免无必要的大世界平移消去；参数由高精度CPU计算后核可表示性。

不设置任意正near而永久漏掉近灯caster，不因某顶点在灯后就丢弃整三角。灯源平面、锥侧与跨平面三角交由真实齐次裁剪，片元在原coverage后写正向轴深度；球域外本来无direct贡献，不产生投影。该方案是本项目待验证的实现选择；[Apple深度接口](https://developer.apple.com/documentation/metal/calculating-primitive-visibility-using-depth-testing)和[公开MSL规格](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)只是接口依据。规格PDF在草案研究中未成功读取，不能把具体裁剪/片元depth组合声称为已证；批准后先导MSL编译与真实三角门必须先验证。

保留原directional投影和质量策略，不把它的affine深度梯度直接用于spot。worldPosition导数须在进入spot循环的距离、cone等非一致分支前统一取得，不能在分支内首次求导。spot接收端从当前真实几何的屏幕导数取接收面，按各实际采样texel的灯射线与该面交点作深度比较。材质shading normal不替代几何面。沿原九tap数量和实际texel中心取样；落在有效域外或不存在有效前向交点的tap局部回无影，不用假深度或随意斜率阈值。

数值裕量须对实际相对坐标、旋转、几何面及透视除法传播舍入尺度，保持原算术系数的预注册选择；不看PNG反推bias，不靠放大全局bias掩盖self-shadow。相同几何的self-plane、正间隙与负间隙须配对通过；极端不可表示时只退化对应projection/tap，不把常规窄锥或跨灯面归入极端。实际退化producer是作者有限但接近表示极限的角度/radius/transform，或光栅edge-on/helper quad导致的退化接收面；必须有可执行输入，不能增无producer guard。

片元写depth可能限制early depth优化，最多四次1024² depth32Float写入是有界成本，不宣称性能最优。禁止逐帧编译/建图；质量UI和通用atlas平台不作本片前置。

### 唯一记录、资源与消费

现`SceneStaticModelShadow`改为同一typed projection记录，容纳directional与spot两种策略，每条继续绑定actual texture、frameEpoch、generation、light identity与command buffer。同一frame集合替换原scalar，旧单record、单texture/parameters ABI同批退役，不保双系统。新增spot PSO或depth state在load准备失败时，仅使spot optional不可用，沿原pipeline的optional shadow state合同保模型颜色和现directional；不得把它加入必需颜色pipeline的失败guard。当前灯型、id/cast、epoch与CB验证后才绑定GPU；不能以颜色/位置猜灯身份。固定最多四项ABI，Swift/MSL布局和多texture绑定经实际编译验证。无效槽不采样；若Metal绑定要求占位，复用已有成功图而非新造fallback纹理。没有成功图则走原无影draw。

原pool key替换为最多四个model-shadow槽；槽按候选位置稳定编号，directional在前，失败不得压缩槽号使后灯覆写前灯。真实light id仍由record持有，slot只管理复用，不成为identity权威。使用有界slot而非长期light-id键，避免动态灯留下无界历史缓存。现generation/retired/pin保证不同在飞提交不覆写，depth格式、usage、逻辑与实际物理预算沿原owner。

每灯成功分配后即持有原submission pin，再尝试后灯。后灯配额/encoder失败只能不发布该灯，不能逐出已成功directional/spot。已编码但未完整生成的图仍pin到该CB结束；未提交可取消，提交后只由completion释放。reset使在飞资源进入原retired集合，最终释放回原物理预算。新一帧灯的数量/身份/位置/方向/cone变化必须重写当前图，不复用旧光结果。

### Mandatory只准备与消费一次

原静态路径与RF13作者序路径保原资源次序、draw集合和depth计划；shadow候选非空时只触发一次。原forward、source-only捕获、lighting payload、snapshot、粒子depth、Bloom/display不得按灯数重复执行。完整mandatory之后逐灯做optional投影，普通mandatory失败保原prefix/suffix，停止本帧所有optional影图。某spot optional失败不影响其它成功灯与健康direct。模型主颜色仍只draw一次，在原spot累加位置乘本灯visibility，point/ambient/emission/alpha/HDR输出不变。

## 精确实施边界

只触达以下九个现owner（相对`MyWallpaperX/Core/SteamWorkshopScene/`）：

1. `Format/SceneSpotLightDefinition.swift`：原严格cast布尔解析。
2. `Rendering/Lighting/SceneLightSnapshot.swift`：当前light identity/cast和投影参数。
3. `Rendering/Frame/SceneMetalRenderer.swift`：同一mandatory触发与候选。
4. `Rendering/Frame/SceneMetalRenderer+StaticModels.swift`：同一准备集合、多图emitter和pins。
5. `Rendering/Metal/SceneStaticModelPipeline.swift`：独立spot projection、统一record/ABI、准备期PSO与draw。
6. `Rendering/Composition/SceneStaticModel.metal`：spot深度与真实receiver面visibility。
7. `Rendering/Targets/SceneOffscreenTexturePool.swift`：原单图入口扩成有界slot。
8. `Rendering/Targets/SceneOffscreenTextureAllocationCache.swift`：key与pin/retired匹配。
9. `Rendering/Targets/SceneOffscreenTextureAllocationCache+SharedPair.swift`：既有candidate格式/usage匹配。

测试由独立owner实现，新spot输入及既有directional/RF13测试只适配必要ABI，不降低原断言。若还需产品路径，先指出具体consumer缺边并修订设计，不能新增万能wrapper。保护的台账、运行证据和重构计划不写；稳定移交通过本批历史记录、架构和唯一路线完成。

## 纠正门与失败处理

先固定自有真实MDL、spot、独立Double世界ray/triangle oracle及ROI；expected不能调用产品projector/visibility。旧App须证明未遮挡direct正控、cast-on/off均缺影、模型主颜色和正常completion存在，再要求新版本仅在射线被遮挡处减少本灯贡献。主相机遮挡不能冒充灯阴影。

- 完整App：cast on/off、no-caster、light-off、健康peer、当前publication/terminal/completion/next-frame与安全退出；四spot可区分输入及directional加spot，逐灯切cast不串图。原总灯数不扩。
- GPU几何：不同深度/偏轴/宽窄锥、非恒定透视插值、锥内外/球far边界、灯背面与跨灯源平面三角；世界/parent变换和主相机改变不改变同一灯射线合同。先导失败留反例并纠正同一投影，不能改为永久near盲区。
- 质量/coverage：多个斜率/非中心texel/大平移下self-plane与正负近间隙配对；alpha阈值两侧、tint-mask、unlit caster、castfalse receiver、同provider两个named消费者、冷帧/实际target resize/下一epoch。缺源保健康颜色，恢复沿原owner。
- 资源：真实native budget只能容directional、directional加首spot及四图的边界；mandatory成功不被可选图抢占，后灯失败保前灯。实际epoch/CB/light身份生产与消费不匹配拒该记录，不能只用伪造record证明主链。
- 生命周期：阻住已提交A，再以改变的灯/目标准备B并取消/reset；A图不能alias覆写，retired预算到completion后释放，随后C恢复。hash固定source/App/测试/输入，不能用pool计数替代实际像素或completion。

Swift/Metal与Debug构建、code-health、scene-defense、design-gate及文档门按实际失败半径执行；完整App与native prepared-owner壳分别标明覆盖范围。独立终审逐条核新guard的producer、旧单图职责退役、多灯真实输出与失败半径。构建/非黑/route数不能证明本片完成；性能、官方parity、原包收益、多屏和point全向域无证据不宣称。

## 退役条件与后继

完整有限锥输出、全准入spot及混directional、资源生命周期门和独立产品终审通过后，稳定职责移交[runtime architecture](runtime-architecture.md)，冻结证据入历史、本文归档并删除窄gate。下一主片在现透视/资源链上做point全向投影与面接缝；不能以本片通过关闭整个D3。reader差额若有具体中性归因与主构图收益，可由[唯一路线](../scene-compatibility-roadmap.md)重新排序。
