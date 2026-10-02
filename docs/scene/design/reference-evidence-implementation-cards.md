<!-- document-role: active-plan -->
<!-- retirementCondition: 各派生卡完成或明确退役，未完成能力由唯一 P 路线及其能力/证据 owner 接管，59 项去向无悬空项后归档；本文不保留完成日志。 -->

# 参考证据实施卡

本文是 [Scene 兼容路线](../scene-compatibility-roadmap.md) 下的派生实施卡，不增加阶段、不取代 P 路线的选序判定，也不把第三方报告变成目标合同。卡执行前仍须 fresh 复现、冻结 owned diff、按失败半径验证和独立终审。实施顺序改变只在 P 路线裁决，本文随之收敛。

复核日为 2026-10-02；产品证据来自主目录 `codex/engine-refactor-program`，HEAD `85415320` 及当时并行 D2/D3 的未提交改动。下列行号是这次静态核对的定位线索，开工须按冻结代码重新定位；“实现存在”不表示本轮运行通过。59项初始整理为只读静态核对；后续已执行批次只链接其冻结证据，不沿用初始“未运行”口径。历史输入是 [Mirage da4fa7b3 六域59项裁决](../../history/scene/mirage-da4fa7b3-six-domain-forensics-verdict-2026-10-01.md)，不读取或复制 `Reference Project`、私有取证原始表达、shader、payload 或第三方算法。

## 1. 来源与准入边界

- `third-party-reference-pattern` 只提供职责、状态、顺序及待证候选；报告中的 gap 多数是文档记载缺口，不自动表示产品缺功能。既有实现先补反例，不重写同构 owner。
- 2026-10-02 实读官方 [Shader Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html)：Texture 伴随参数适用8个 sampler（0…7），新增、hidden 和 visible sampler 也限定0…7；hidden texture 可使用 internal render target/default。故 Mirage `g_Texture0..12` 和 `MipMapInfo` 不能直接扩为作者 API。8…12 的 runtime profile 须有具体合法 stock/corpus occurrence、producer/类型/消费相位证据，再经设计门；公开页面未列的 companion 也不凭名称猜值。
- 2026-10-02 实读官方 [IParticleSystem](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystem.html)：对象 pause 停止新排放，已有粒子仍模拟；stop 清空，play 恢复或结束后重启，显式 emitParticles 可绕过对象 pause/stop。Mirage play-reset、模拟冻结、stayPaused/reset_sequence 不升级为公开 API。实例字段以 [IParticleSystemInstance](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IParticleSystemInstance.html) 为准，不扩张本卡首片。
- 项目自有曲线、粒子权重/排序、音频聚合及预算仍标项目策略。编译、route、非黑、单样本、mirror 截图不能代替官方同输入对照。

## 2. 派生工作卡

以下排列细化 P1/P2 已选责任，不另立总路线。RF00/RF01 与 RF05 诊断导出片已转证据移交；RF03 限定粒子四方法与 RF07 raw/display 分离也已转证据移交。RF05 其余既有能力组合仍待补证，条件卡在前置合同和证据满足后才进入产品写入。

### RF00 — D2/D3 有界首片已移交证据

首片已完成独立终审、Debug 构建、受控作者输入像素门及两个原样本隔离回归；范围、反例和未验证边界仅由[本批执行记录](../../history/scene/d2-d3-bounded-output-implementation-2026-10-02.md)保存。本卡不继续维护结果计数。设计仍见[D2](hdr-tonemap-edr-design.md)/[D3](2d-lighting-material-design.md)；EDR/PBR/阴影等后继未自动开放，clear=false 单列下卡。受保护能力/运行总表由其唯一 owner 引用执行记录后撤销本移交指针。

### RF01 — 现役 RT default 消费首片已移交证据

现役 FullFrameBuffer 与同层 composite default 的 typed identity 到实际 binding 已闭合，包括两项独立终审发现的 absent候选回落及captured-main首consumer闲置default问题；边界、修前反例、终审、冻结App及七项正反像素门仅见[执行记录](../../history/scene/rf01-shader-default-binding-implementation-2026-10-02.md)。[D8](rt-prefix-admission-design.md)仍约束未知名字/跨层default，不据本片扩大family或声明parity。唯一能力/运行owner引用执行记录后删除此移交指针，不在本文维护完成计数。

### RF02 — 公开 uniform 的反射到consumer合同

**owner / 输入输出。** ShaderContract/schema/finalizer保留作者声明和active reflection，现役HostUniformSchema为每个支持的uniform发布type/shape/source及typed frame值；UniformEncoder与同一material binding消费，Program identity包含必要ABI事实。

**首断点。** `Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift:35`目前分派synthetic texture transform、Resolution和audio；`:59`识别Resolution，`:28`已有ParallaxPosition。`Compilation/ShaderFrontend/SceneAuthoredShaderTextureTransformABI.swift:36`与`Compilation/ShaderPreparation/SceneShaderVariantResolver+Schema.swift:278`限定8槽，符合公开author合同。自动纹理变换存在不等于显式Rotation/Translation uniform已消费；现役产品未找到MipMapInfo producer。

**前置 / 范围 / 不做。** 在现有shader合同设计中先登记每个公开uniform的准确类型、物理/映射尺寸、sprite旋转平移的值与更新相位、active sampler依赖、失败分类。首批只处理0…7有真实声明/消费的公开companion，逐producer闭合，不为清空缺口增加mirror符号或第二ABI。8…12、MipMapInfo/未公开Texel family保持待证；只有具体合法stock/corpus occurrence和中性行为规格能触发独立runtime profile设计，不能直接改变UInt8 mask/槽宽。本次实读[官方Variables](https://docs.wallpaperengine.io/en/scene/shader/variables.html#texture)与[Desaturation教程](https://docs.wallpaperengine.io/en/scene/shader/tutorials/desaturation.html#editing-the-shader)只固定Translation(vec2)/Rotation(vec4)及0…7声明范围。Translation单位/原点/符号、Rotation分量布局与自动texturetransform应用阶段仍unknown；须有官方黑盒或合法公开明确行为证据，冻结输入输出与不重复变换合同后才准实施。

**正反验收。** 自有declared+active fixture区分physical/mapped size、非方形sprite、rotation/translation与neutral transform；shader直接读取uniform与自动sampling结果各有oracle。缺sampler/dead uniform、类型/array/stage冲突、padding、wrong generation、provider尺寸变化、sprite新frame、ABI缓存失效及普通帧无reflection分别验证；最终GPU/ROI/publication/next-frame。未知uniform仍局部失败，不能用零值猜测成功。

**依赖 / 复杂度。** 公开类型/更新相位与合法 active consumer 先定案，RT companion 消费依赖 RF01；中等至高，未公开 family 不进入实施估算。

**退役。** 支持profile的反射→typed值→GPU consumer闭合且证据/ABI回稳定权威后删卡；未公开family明确unknown，不计支持。

**下一取证批（已找到执行入口）。** 2026-10-02 公开检索及207个合法 package/2864个shader声明扫描未得到 companion数值布局；这只限定本轮检索，不代表永久不可知。现有 Parallels Windows 11 VM可用于实验，尚未核guest官方客户端版本/安装就绪。先核client build/hash/backend，以自有非方形atlas配公开pause/setFrame固定帧，独立阈值读取Rotation四分量/Translation两分量，再比较无变换/显式一次/显式两次的采样ROI，确定单位、分量布局、自动应用阶段与同帧publication。不能把本项目synthetic affine ABI直接别名成官方uniform；当前每次sampling自动变换尤其需排除重复变换。黑盒不能执行时登记具体缺失依赖并继续D1自有fixture及现役source/preflight边审查（D1作者输出顺序也依赖官方环境，不能猜定），不停止整个能力队列。

### RF03 — D4+D11 限定播放与显式出生

prepared root、无 authored child、单个 supported 确定性 schedule 的 play/pause/stop/isPlaying 已完成真实VM事务、模拟/资源、冻结App六项显示/故障门及独立终审。当前能力边界、三项事务审查修复、错误分类反例、未验证GPU错误/RNG边界和冻结身份仅见[执行记录](../../history/scene/rf03-particle-playback-implementation-2026-10-02.md)；目标仍由[D4](script-component-api-design.md)/[D11](particle-playback-state-design.md)约束。默认emit数量、reset、多emitter、children、随机周期未开放，不能据限定方法升级为完整组件API。唯一能力/运行owner接管后删除本移交指针，不在派生卡重复结果计数。

RF03 连续排放后继已独立验收：缺省/0 duration四方法和显式非法duration边界已闭合，修前反例、最终App与证据边界见[独立执行记录](../../history/scene/rf03-continuous-playback-implementation-2026-10-02.md)。显式burst未随连续排放片开放；其独立后继现已完成调用期真实出生事务与最终App验证，冻结范围、审查修复和HEAD既有失败仅见[显式出生记录](../../history/scene/rf03-explicit-particle-emission-implementation-2026-10-02.md)，已获独立终审ACCEPT并随该职责批提交。下一主能力片按路线回到RF08/D1实际source一致性；不重复创建粒子模拟或播放owner。

### RF04 — D12 mip触发与快照语义先定案

**owner / 输入输出。** 既有graph准备生成source version→mip snapshot/generation→consumer依赖；lease/allocation/publication仍唯一。SceneGraphResourcePassEncoder降低明确copy或mip生成操作，terminal compositor只消费末结果。

**首断点。** `Compilation/Material/SceneResolvedMaterialShaderSchema.swift:23`未准入MipMappedFrameBuffer；`Rendering/Composition/SceneFramebufferSnapshot.swift:43`只复制level0、`:65`非mip；`Rendering/Targets/SceneGraphRenderTargetTable.swift:199`非mip；`Rendering/Graph/SceneGraphResourcePassEncoder.swift:339`限定单mip。相反，authored copy已经由`Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift:317`保序并由encoder:105准备，不重写该链。

**前置 / 范围 / 不做。** [D12](copy-pass-unification-design.md)批准typed transfer边界，不证明mip消费者全部语义。先用合法内容与公开/中性行为协议固定hidden g_Texture3 default等具体消费者的读取时点、尺寸、level、颜色/alpha/data用途及source覆写命运；无证据不能把mip生成绑到slot3或“copy=true”。D8身份是前置，颜色域与D2一致。link别名、authored copy、末跳已有路径先审计alias/snapshot与版本，不因名字不同做物理copy；无消费者零生产。未知mip/颜色profile保持准入拒绝。

**正反验收。** 不同mip独立色格，copy前后覆写source区分alias与snapshot；精确subresource/extent/format、1×1 probe反例、self-copy/hazard、mip/slice越界、history pin、resize、encoder/GPU失败、反序completion、无consumer成本与next-frame版本。bit-copy精确字节，明确render transfer用预冻结容差；不在copy重复blend/tone map，不绕terminal自行present。

**依赖 / 复杂度。** 必须先有区分 alias/snapshot/mip 读取时点的合法 consumer 证据，RF01 身份和颜色域合同就绪；高，涉及 graph/version/lease 与 GPU subresource 生命周期。

**退役。** 每个已开放触发profile的producer→transfer→consumer/版本生命周期闭合，旧重复路径与预算下降，稳定graph合同接管后删卡。

**下一取证批。** 与RF02共用已识别Windows环境，但分别冻结输入。公开ordinary FBO与texSample2DLod不足以证明自动mip生成；先让自有effect实际使用候选hidden/default target，以普通纹理为control验证名称准入，再分别改变frame/layer/effect/pass颜色、FBO extent、LOD频率格及source后续覆盖，区分读取相位、alias/snapshot和level可用性。slot置换必须不改变资源语义；颜色/alpha/数据用途另测。只有实际合法consumer及前述事实定案后扩D12，不凭`_rt_`或槽3生成资源。

### RF05 — 既有能力补真正跨层/跨屏反例

**owner / 输入输出。** 复用property、dependency/provider、frame session、目标publication和唯一compositor；输出是实际执行证据，发现首断点后才投影回P路线修复卡，不把测试owner变产品协调器。

**现有实现与范围。** Document:111已在object parse前应用effective property、:107先保真script IR；Document:293/Bindings:228已有visible布尔/wrapper/user载体。DependencyRenderPlan+Aggregate:112维护visible root与provider闭包；Session+FrameDriver:622/692 session evaluation一次消费，MetalView:581保存simulationFrame、FrameDriver:751独立提交surface。PolicyController:94唯一macOSpolicy；Session+VideoProviders:17停clock/timer、:26同步pause sound。已存在能力只补相称反例，不能把历史“零记载”当新功能。

**正反验收。** 诊断导出片已完成独立终审、真实AppKit反例及完整App退出/呈现门，结果仅见[冻结执行记录](../../history/scene/rf05-debug-capture-lifecycle-implementation-2026-10-02.md)，合同见[诊断截图生命周期设计](debug-frame-capture-lifecycle-design.md)；短HDR对照不宣称性能完成。named provider 准备及显示分离片已完成八项签名App门，范围、原失败、受限optional profile与独立终审见[冻结记录](../../history/scene/rf05-named-provider-readiness-implementation-2026-10-02.md)。途中发现的三候选未支持组合阻断首帧，已由[独立局部失败批](../../history/scene/rf05-optional-named-failure-implementation-2026-10-02.md)恢复安全入口和健康邻层；未扩大候选执行profile，RF05全卡仍未完成。其余组合门仍待执行： 初值覆盖→首帧hidden剪枝→live变化→script authored fallback不污染；visible bool/value-bool/user string/name-condition及数值wrapper保守分支分别验证。隐藏provider被跨层采样仍执行，隐藏未消费对象不贡献输出；toggle、同帧不同消费者、错purpose/stale generation、resize/reload和provider晚到验证publication闭包。一屏drawable缺失、另一屏真实completion、所有屏失败后恢复，VM heap/timer/input/localStorage与粒子RNG/child births/Puppet physics每cadence一次消费，恢复使用最新typed snapshot。pause首帧、run profile切换、政策重连/继承及旧epoch分别验收。

**D9/D10边界。** D9只在确有App可表达throttle需求时扩协议，不制造空第三态或renderer系统observer。当前FrameDriver:770只在paused未提交时返回busy，:773运行态未提交返回dropped正常cadence；:149已具simulationFrame的paused重试仅renderSurfaces。故“interval/8重复模拟”静态猜测不成立，只有执行反例可重新立修复项。不复制Miragefade、重放结构、计时/超时常量。

**依赖 / 复杂度。** 先固定每个现役 profile 的输入与独立 oracle，再运行反例；中等，物理多屏或异步失败门需相应执行环境，不把缺环境写成通过。

**退役。** 相应profile反例和真实跨层/跨屏证据归能力/运行权威，实际新缺陷归单一P修复项后删卡；不得声称未执行条件或物理多屏已通过。

### RF06 — 另域与明确隔离

Web输入转发/scheme/audio已有owner，只补对照引用；Web脚本egress缺宿主策略，但属Web用户数据/兼容政策，须先走设计门③，不在本Scene批偷偷阻断fetch/XHR/WebSocket/subresource。daemon父死/分帧需先裁决EOF、pipe继承、超限帧及写失败命运；当前EOF退出和串行完整JSON帧已存在，不据Mirage直接加watchdog常量。两项如被P路线选中，派生到既有DaemonKit/Web专项责任后删这里的候选指针。

Vulkan缓存键/HLSL装配、per-display独立可执行模型、playlist、transcoder、独立Web spawn信任门、Steam内置key/镜像路由、宽松可见性比较、scheme_color单源别名、音频均值表及私有算法/常量不实施。未知公开API、官方parity、EDR/PBR/shadow/reflect/ltube/mip、8…12 sampler不计完成，不为关闭报告分母造实现。

**依赖 / 复杂度 / 退役。** Web egress 与 daemon 异常生命周期各须责任域先定政策和设计，未裁决不估算产品改动；现有桥接补证为低至中等，安全/兼容政策改动为高。另域 owner 接管或明确排除后，删除这里的候选指针；不得借本 Scene 卡改变 Web 行为。


<a id="rf07-history--clearfalse-原始颜色历史已移交证据"></a>

### RF07-HISTORY — clear=false 原始颜色历史已移交证据

HDR clear=false 的 raw/candidate/display 分离、GPU成功提升、paused新epoch重绘及clear=true精确输出守恒已完成独立终审。实际owner反例、两项输出修复、诊断采样修正、冻结标准/故障App与未验证边界仅由[执行记录](../../history/scene/rf07-persistent-color-output-implementation-2026-10-02.md)保存；目标见[D2](hdr-tonemap-edr-design.md)，稳定生命周期见[架构§3.3](runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)。不据本片开放透明终端、EDR或声明性能完成。唯一能力/运行owner接管后删除此移交指针，不在派生卡重复完成计数。

### RF08 — D1 composition 的采集合同纠偏

**目标/owner。** [D1](composition-render-target-design.md)已重新进入设计裁决。作者格式/descriptor拥有类型、parent和order，现planner拥有采集时点及读写边，pool/lease与唯一compositor保留职责。目标是正确作者输出，不是把旧isolated-group方案补完整。

**当前事实。** 2026-10-02公开[RGB composition说明](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers)描述采集下方全部层，如场景相机；现parser只保留utility两flag及独立parent，没有已识别的isolated字段。`SceneUtilityLayerSourceRoute.swift:36,199–223,265–273`才将parent后代升级为私有target成员，且改变触发位置。现有isolated代码、旧设计和3226487183都不能作为该语义正确的证明。

**实施/备选。** 已从固定参考项目提炼[中性合同](../../history/scene/d1-composition-neutral-contract-2026-10-02.md)。D1资源窄片已修正group key/尺寸准入、prepare与实际source错配，以及组内无子层composition的写回目标/同trigger执行序；真实反例、冻结App与clear/resize/completion结果见[执行记录](../../history/scene/d1-composition-source-implementation-2026-10-02.md)，稳定资源合同由架构§3.3接管。成员/flag仍用有可见effect正控制的官方自有输入区分below非child/above child、copybackground缺省/false/true；仅确认的profile才改变source route。资源修复不升级为官方隔离语义。

**纠正门/退役。** 自写parent单变量、非child颜色、区域内外、child自身effect、root无effect及模式切换；实际source→effect→publication→terminal→next-frame与ROI，相称resize/迟到completion门，普通帧prepare次数不增长。真实样本只作回归；行为合同与实现闭合、无依据路撤权后交稳定架构并退役。

### RF09 — D3 作者 normal 输入与采样

**目标/owner。** 将固定builtin作者slot1 normal接入现base profile→asset catalog→typed frame registry→lit producer→唯一compositor，沿现资源和normal basis独立实现方向处理。[D3后继设计](2d-lighting-material-design.md)拥有格式/覆盖/失败裁决，[经审查的中性交接](../../history/scene/d3-normal-input-neutral-contract-2026-10-02.md)提供声明与职责证据；不复制参考算法。

**首断点/实施。** 基线按stock路径扫描导致普通slot1无需求、slot2误归normal及frame丢失；已沿同一profile/catalog/registry/producer贯通。真实App又揭示固有图片尺寸污染normal方向，已分离位置model与同帧作者world方向，并由原PNG反例证明修复。格式/方向GPU门、精确逐槽采样及实际App组合已通过独立产品终审；RF10后继复核又发现一项instance fixture错字段，已收紧该项旧证据并安排真实入口补跑。失败、测试身份澄清与更正见[执行记录](../../history/scene/d3-authored-normal-input-implementation-2026-10-02.md)。稳定职责由[架构§3.4](runtime-architecture.md#34-通用执行不等于单体-renderer)接管，窄登记退役；NORMALMAP/instance及独立方向策略仍按D3设计，不冒称官方reset/parity。

**纠正门/后继。** 自有normal方向、neutral/缺图、Lighting关闭、错误sRGB、purpose区分、nonzero-origin frame/下一帧、plain/effects两路均验证实际输出与生命周期；真实正样本另核，不从genericimage出现次数推断受益。本片按职责提交；下一批由RF10落实slot2直射材质响应，环境反射与阴影分别补其输入合同，不能借normal上线宣称整项D3完成。

<a id="rf10-pbr-direct"></a>

### RF10 — D3 slot2 PBR 的首个直射材质响应（normal 后继工作卡）

**目标/选型。** normal 窄片关闭后，优先将普通2D quad的作者slot2 PBR输入接到既有point/spot材质响应，形成可区分的粗糙度、金属度响应。[D3设计](2d-lighting-material-design.md)已批准先闭合明确的无map标量/default切片，贴图通道补证并行；标量提交后继续slot2，不能把一个未知分支扩大为整项冻结。沿现base profile→同catalog/data purpose→typed frame→lit source→effects→唯一terminal复用normal与相机owner；采用可验证的独立shading策略，不等待官方私有公式，也不复制参考实现。

**实施前事实与首断点（1548aad4，2026-10-02）。** `Resources/Assets/SceneAssetCatalog.swift:233–238`和`Runtime/Frame/SceneRenderDescriptor.swift:264–276`仍保留slot2、combos与shader values；`Compilation/Material/SceneBaseMaterialLightingProfile.swift:36–55`只消费LIGHTING/NORMALMAP/slot1，是普通builtin PBR语义的首断点。`Rendering/Composition/SceneLitImageLayer.metal`已有世界位置、normal和point/spot，尚无PBR/view参数。以上路径以`MyWallpaperX/Core/SteamWorkshopScene/`为前缀，实施前重核。合法corpus已有LIGHTING=1且slot2非空的作者材料，但尚不能据声明称受益。

**先补输入，再自主实现。** [PBR中性交接](../../history/scene/d3-pbr-input-neutral-contract-2026-10-02.md)已定各tier的metallic/roughness键与default、map空用slider及场景灯的LIGHTING合同。没有slot2仍须消费声明default，不能另造PBR总开关。标量/default已沿同一lit producer落实，真实App缺响应反例及独立数值、启动用户属性与normal回归见[本片执行记录](../../history/scene/d3-pbr-scalar-implementation-2026-10-02.md)；此结果不代表slot2已实现。[v6/v7中性增量](../../history/scene/d3-pbr-map-input-neutral-contract-2026-10-02.md)已通过隔离审查，区分component presence、逻辑R/G/A选择与第三方采样保持。F3按D3设计同时接入MR贴图和静态自发光，共享一次slot2采样，两个sun作者材料已通过有界贡献消融；F3已沿九个既有owner接通，通过独立数值、资源、冻结App及真实材料贡献消融验收；实际红绿、身份与最终结论只见[执行记录](../../history/scene/d3-pbr-map-emission-implementation-2026-10-02.md)。显式combo/header冲突及headerless采用明确项目保守分支，官方动态parity仍未运行。Universe材料用户属性另追原owner，不能把raw fallback冒称已解析；只限制具体未决分支。

**最近纠正门。** 普通instance静态slot0漏接已在Layer准备与共享path resolver纠正，真实不同灰底图、normal继承、同model隔离、动画下一帧及缺坏资源局部失败通过实际App；冻结身份与证据见[本片记录](../../history/scene/d3-instance-base-texture-implementation-2026-10-02.md)。F2底图与F3贴图消费职责均由稳定架构接管，不另建provider/loader。

**owner与失败路。** prepared material profile拥有有效feature与需求；现cache/catalog/registry拥有数据纹理、逐槽frame与生命周期；同帧camera/light与lit producer拥有方向/材质响应。缺可选PBR资源只移除未可用的map输入，沿设计使用合法scalar/default并保留normal/alpha；identity/range/hazard仍拒最小unsafe unit，不能新建PBR registry、camera或compositor。

**备选与边界。** 明确typed环境输入的reflection-only是第一备选；现sameFrameSceneBackground是作者顺序前缀颜色、单mip资源，不是已有环境反射合同。真实REFLECTION=1/LIGHTING=0的两包保留后继，不能改作者LIGHTING后声称原样本恢复。第二备选为既有direct-static 3D有界PBR，须独立核该model家族输入，不照搬2D slot2。环境来源、reset和额外动态provider不作为直射片的无限前置。RF11首帧预算片已恢复实际原包输出；[D3 F4](2d-lighting-material-design.md#f4-material-user-emission)已沿原属性owner接通catalog emissivebrightness启动、实时0→1→0与回滚，实际App、原包六目标和固定alpha材料贡献门已执行，冻结结果与终审状态见[执行记录](../../history/scene/d3-material-user-emission-implementation-2026-10-02.md)。下一片先定环境reflection输入身份并落实自有实现，再推进有合法caster/depth输入的阴影；其它字段、Puppet受光与instance实时输入按真实consumer独立扩展，不在profile直接求值raw、不建立第二属性通路。真实sun完整包的共同既有首帧预算断点已在RF11消除重复计费；这不是完整画面一致性结论。

**纠正门/退役。** 先建立实际缺响应反例；逐通道自写阶梯、固定灯与normal，检查独立分量、粗糙度高光范围、相机/灯移动、作者开关和无串通道。slot2独立frame/sampler、同路径color/data、下一帧更新、缺图局部退化与健康邻层均过实际消费门；plain/effect到terminal有身份、completion、publication与ROI。真实作者材料另做隔离回归，不能以自有oracle宣称官方PBR。设计、实现和独立终审闭合后移交稳定owner，继续环境反射与有合法caster/depth的阴影。

<a id="rf11-frame-target-budget"></a>

### RF11 — 真实复杂场景的首帧目标预算（F3后继优先）

**结果与owner。** 完整作者包原先被shared HDR pair重复计费阻断首帧。`SceneLayerGraphTargetPlan`现只累加实际私有槽，shared pair仍由原pool按key及实际格式计费；不涨预算、不降精度、不改变alias或lease。行为红证、HDR/SDR预算边界、真实allocation/completion/next-frame及原包输出证据见[执行记录](../../history/scene/rf11-shared-hdr-target-budget-implementation-2026-10-02.md)。稳定职责移交[架构§3.3](runtime-architecture.md#33-保留事务安全不扩大视觉失败半径)，原[窄设计](../../history/scene/rf11-shared-graph-pair-budget-design-2026-10-02.md)保留设计决策来源。

**验证上限与后继。** 相同原输入、预算策略和单surface配置已完成GPU frame0/1/2及安全drain，作者开场字卡可见并变化；不证明后续太阳系全景、官方parity或性能改善。真正超预算、整数溢出、history、generation和在飞资源门保持原拒绝。下一片回RF10的2D材料用户属性：先沿唯一resolver核声明、层身份和事务，再接现lit consumer，之后继续明确环境资源的reflection和阴影。

## 3. 全部59项去向

下表每条有我方现役owner定位；不存在第三方对应能力时，该定位是最近的明确责任/边界，不表示能力存在。代码路径均为仓库相对路径，行号属于本次复核；实施前以冻结代码验证。历史裁决计数保持gap24、corroborated17、mirage-specific18。`补证`意味着不重写已存在链；`待证`须固定语义才准实施；`隔离`不成为作者合同。

### render（10）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| render-0 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema.swift:49`；`Compilation/ShaderPreparation/SceneShaderVariantResolver+Schema.swift:278`（后二级路径均相对SteamWorkshopScene） | 有限定RT词汇表；8槽符合官方公开author合同。RF01已闭合现役family首片，见上方执行记录；RF02取证companion，8…12/MipMapInfo待证，不复制14名前缀表。 |
| render-1 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialTemplateCompiler.swift:193`；`Compilation/Material/SceneResolvedMaterialShaderSchema.swift:787` | 初次复核时explicit已用单点，default仍lowercase/raw分派；这条缺边已由RF01闭合，见上方移交记录。 |
| render-2 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift:306`、`:328` | 作者FBO/命令端点已保留。补证/消歧；自有FullCompoBuffer1/2 fixture不证明内建名字语义。 |
| render-3 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneBloomPostProcess.swift:6`、`:51`；`Rendering/Frame/SceneMetalRenderer.swift:925` | scene Bloom已存在。RF00验D2显示域与一次映射；Mirage双别名/内部名字不增API。 |
| render-4 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift:13`；`Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift:112` | provider reference及消费闭包已存在；RF05补hidden-reference/resize/generation。 |
| render-5 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift:111`；`Compilation/Material/SceneResolvedMaterialProgramFinalizer.swift:296` | prepare/finalize到执行链已有。补职责引用；不为四阶段函数形状重新组织产品。 |
| render-6 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderContract/SceneShaderContract.swift:257`、`:312`；`Compilation/Material/SceneResolvedMaterialShaderSchema.swift:316` | lexical/annotation/schema/reflection已存在并支持PASS。RF02仅追具体未闭合uniform；Mirage缺PASS不继承。 |
| render-7 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgramFinalizer.swift:454` | 最近owner为我方prepared ABI验证；隔离HLSL packoffset/glslang workaround。 |
| render-8 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialProgramIdentity.swift:1` | 我方Program identity已独立；隔离Vulkan缓存键字节/哈希算法。 |
| render-9 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift:317`；`Rendering/Graph/SceneGraphResourcePassEncoder.swift:105`；`Rendering/Composition/SceneFramebufferSnapshot.swift:43` | authored copy已实现；mip snapshot缺生产/身份/trigger合同→RF04待证后实施。 |

### particle（10）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| particle-0 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift:17`；`Systems/Particles/SceneParticlePlaybackState.swift:59` | host pause/共享delta存在；RF05补停发/冻结/恢复实际count/time。 |
| particle-1 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptLayerHandleBridge.swift:79`；`Systems/Particles/SceneParticleSimulator.swift:517` | 初次复核缺少的command/emission链已由RF03限定四方法闭合，见上方冻结记录；显式count出生见RF03独立后继；默认count/reset等仍未开放，第三方freeze/stayPaused不升级为合同。 |
| particle-2 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelineTargetCompiler.swift:91`、`:194` | root instance scalar/CP Timeline有bounded消费；报告节点四曲线不等于该profile，节点transform/child曲线继续待证，补实际consumer反例。 |
| particle-3 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift:65`、`:66` | segments/subdivision默认与预算已有；补引用和边界，不升级parity。 |
| particle-4 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleChildLifecycle.swift:4`、`:42` | 子系统准入/事件identity自有owner；隔离particle_idx/spawn_sequence簿记，不关闭CP eventfollow待验。 |
| particle-5 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePlaybackState.swift:63`；`Systems/Particles/SceneParticleSimulator.swift:576` | audio snapshot→emission multiplier已有；补输入/频段/pause组合，不从Mirage自选schema名扩API。 |
| particle-6 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulator.swift:224`、`:590`、`:595`、`:607`；`Systems/Particles/SceneParticlePeriodicEmission.swift:25` | frame quota、activeDuration、burst、remainder/periodic计划已有；补不同callback/fixed-step/边界计数，不复制公式实现。 |
| particle-7 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTrailRenderPlan.swift:8`；`Systems/Particles/SceneParticleSimulator.swift:560` | 自有trail历史记录已有；补暂停/恢复/寿命组合；容量/间隔不变成官方常量。 |
| particle-8 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleUnaryOperatorPlans.swift:10`；`Systems/Particles/SceneParticleSimulator.swift:751`、`:756`、`:761` | alphaFade淡入淡出已存在；补lifetime窗口/组合反例，不重写。 |
| particle-9 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleLayerImageEmissionMap.swift:4`、`:48`；`Systems/Particles/SceneParticleRuntime.swift:626` | alpha加权与条件排序是项目自有bounded策略；隔离“Mirage互证”推导，文档只保持正确当前边界。 |

### clock（9）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| clock-0 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:15`、`:70`、`:770` | cadence/paused retry已存在；RF05验实际消费，不移植5帧/15FPS常量。 |
| clock-1 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:94`、`:118` | 单次timer/deadline已有，不补过期帧；补profile切换和停止后旧timer反例，不复制WorkerTimer结构。 |
| clock-2 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:165`、`:622` | sceneClock与session evaluation为唯一authority；补shared dt/暂停恢复，不采用Mirage speed²细节。 |
| clock-3 / gap | `MyWallpaperX/Core/PlaybackControl/PlaybackPolicyController.swift:5`、`:94`；`MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift:43` | App唯一policy与fan-out已有；RF05/D9补序列证据，无需求不造第三态。 |
| clock-4 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+VideoProviders.swift:17`、`:26`；`Systems/Media/SceneSoundPlaybackRegistry.swift:62` | 帧与声音同步pause是当前项目行为；fade官方语义未定，补generation/迟到事件，Mirage延迟/常量不实施。 |
| clock-5 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift:15`、`:52` | candidate/first-completion/旧输出保全已有；补启动事务组合，不复制九相位枚举。 |
| clock-6 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift:15`；`Runtime/IPC/SceneDaemonClient.swift:95` | 我方candidate与完整desired状态owner；隔离per-display进程两段重放。 |
| clock-7 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Launch.swift:80` | 最近owner为我方launch lifecycle；隔离第三方阶段超时表，不新增常量。 |
| clock-8 / mirage-specific | `MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift:43` | 最近责任为App播放意图；playlist未立项，明确排除本Scene实施卡。 |

### property（10）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| property-0 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift:12`、`:45` | typed属性状态已有；隔离wire字符串二次JSON解析，不新增解析层。 |
| property-1 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift:228`；`Format/SceneDocument.swift:111` | key保持现役authored identity；scheme_color归一缺官方生产者/合法正例，待证，不据单源增别名。 |
| property-2 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift:107`、`:111`、`:118` | 初值注入先于objects parse已实现，script IR先保真；RF05补首图/override/fallback。 |
| property-3 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift:14`、`:45`；`Systems/Properties/ScenePropertyBindingProgram.swift:71` | revision→typed binding/live消费者链已有；补失效域组合，不重做property owner。 |
| property-4 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession.swift:225`、`:281` | 当前transaction/consumer admission已有；隔离双消息循环prepared绕行。 |
| property-5 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Format/ScenePkgReader.swift:89`；`Format/SceneDocument.swift:147` | 包头与declaredVersion保留已有；字段级版本门待官方profile，不照Mirage general版本表启闭字段。 |
| property-6 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Format/SceneDocument.swift:293`；`Systems/Properties/SceneUserPropertyBindings.swift:228` | visible布尔/wrapper/user绑定载体已有；RF05补每字段独立wrapper和数值保守分支。 |
| property-7 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift:82`、`:130` | strict string==string现役合同；隔离bool↔"1"/"0"宽松匹配。 |
| property-8 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneUserPropertyBindings.swift:228`；`Systems/Properties/ScenePropertyBindingProgram.swift:82` | binding/条件消费使用我方bounded grammar；隔离编辑器JS求值、缓存、排序/迁移，不替换owner。 |
| property-9 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift:80` | 音频uniform集合有我方typed schema；保留项目聚合策略，隔离Mirage均值/装配表；官方oracle待证。 |

### camera（10）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| camera-0 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Camera.swift:17`、`:18` | 我方shake owner/已定合同；隔离第三方方向查表/beat算法。 |
| camera-1 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Systems/Input/SceneLayerParallax.swift:128`、`:151` | pointer smoothing已有；补NaN/delay/pause输入边界，不改已验证项目跟随行为。 |
| camera-2 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Camera.swift:25`、`:85` | working-camera含shake并供parallax消费；补组合，不能退回Mirage base-camera差异。 |
| camera-3 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialHostUniformSchema.swift:28`；`Rendering/Bindings/SceneResolvedMaterialUniformEncoder.swift:87` | ParallaxPosition uniform通路已有；补证据指针和动态值/ROI，不新建input通路。 |
| camera-4 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift:111`；`Systems/Script/SceneScriptLayerRuntimeDescriptorBridge.swift:98` | property/script typed visibility已有；D3当前light consumer另验，RF05补入口/顺序，不复制pending结构。 |
| camera-5 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift:112` | hidden provider消费闭包已有；补隐藏但被采样/独立消费者及generation反例。 |
| camera-6 / gap | `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift:12`、`:62` | Web polling/event→surface桥已有；另域补证，不复制数值throttle。 |
| camera-7 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:159`；`Rendering/Frame/SceneMetalView.swift:566` | Scene指针poll/frame state已有；补前后台/多屏输入，Mirage窗口/input_hz常量隔离。 |
| camera-8 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneScreenTopology.swift:9`；`Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:751` | 多surface拓扑/独立提交已有，物理多屏/恢复未以静态代码证明；RF05；DisplayKey格式隔离。 |
| camera-9 / corroborated | `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Frame/SceneMetalRenderer+Camera.swift:9`、`:10`、`:67` | camera typed property projection已有；补live change，不每帧重新解析属性。 |

### modules（10）

| ID / 历史裁决 | 我方owner证据 path:line | 当前判定与去向 |
|---|---|---|
| modules-0 / corroborated | `MyWallpaperX/Core/PlaybackControl/PlaybackPolicyController.swift:94`；`MyWallpaperX/Core/PlaybackControl/PlaybackCommandMultiplexer.swift:43` | App唯一policy已有，补互证/继承门；renderer不监听系统policy。 |
| modules-1 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift:136` | 单二进制Scene daemon现役责任；隔离三个工具target/每显示器一进程模型。 |
| modules-2 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperHost+Activation.swift:15`；`Runtime/Session/SceneDesktopWallpaperSession+FrameDriver.swift:751` | 候选/首帧事务和各屏提交责任已存在；隔离九相位/window-server双向协议。 |
| modules-3 / gap | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift:22`、`:192`、`:212`；`MyWallpaperX/Core/DaemonKit/DaemonNewlineJSON.swift:10` | EOF退出/串行事件帧已有，parent death异常与最大帧/写失败边界待owner裁决→RF06另域设计。 |
| modules-4 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopScene/Runtime/IPC/SceneDaemonRuntime.swift:462` | 最近跨进程失败/退出责任为daemon；无transcoder能力立项，明确排除。 |
| modules-5 / mirage-specific | `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift:110` | 我方App内WebKit宿主，无独立spawn gate；隔离第三方进程信任门，不顺手加产品确认。 |
| modules-6 / gap | `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+NavigationDelegate.swift:57`；`Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift:110`（后者相对SteamWorkshopWeb） | 主frame/资源凭据不限制页面脚本egress，实际策略缺口；RF06另域设计门③，政策未定不实施。 |
| modules-7 / gap | `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift:100`；`Host/DedicatedWebWallpaperHostPlaceholderAdapter+AudioDemand.swift:19`；`Engine/WallpaperEngine+WebAudioSpectrum.swift:17`（后二级路径相对SteamWorkshopWeb） | scheme、host脚本bridge与audio fan-out已有；另域补职责互证/生命周期，函数名/频率常量不复制。 |
| modules-8 / corroborated | `MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceClient.swift:511`；`MyWallpaperX/Modules/SteamWorkshop/Core/SteamServiceProtocol.swift:204` | 我方SteamKit helper握手与协议已有；仅补引用，不与第三方同名Program.cs混淆，不自动声称live-account/release验收。 |
| modules-9 / mirage-specific | `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+SteamKitBrowse.swift:1` | 我方已选SteamKit browse责任；隔离内置key/镜像WebAPI路由，明确不迁移。 |

## 4. 卡关闭与证据落点

每卡交付一个可执行或可见纵向结果；未实施的待证项只能交付中性行为规格、区分实验及明确准入边界。能力状态回能力台账/专项表，执行身份与GPU/compositor/next-frame结果回运行证据，任务顺序回P路线，稳定owner/ABI/生命周期回架构合同。本文只留未关闭卡与59项有去向的裁决，不复制完成日志、不修改人工视觉verdict、不降低失败分母。

卡关闭时保留实际受影响集合、失败反例及后续首断点；owned diff和证据identity冻结后独立只读终审。Swift产品改动按inner→checkpoint→integration选择现役模块及code-health/scene-defense/design-gate，checkpoint做Debug build；GPU/VM/资源/可见变化使用隔离内容。本文只陈列准入与验收要求；已执行批次以各冻结证据为准，其余卡不得据本文视为通过。
