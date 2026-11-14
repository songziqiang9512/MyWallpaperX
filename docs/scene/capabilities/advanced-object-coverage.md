# 模型、Puppet 与光照

<!-- document-role: current-state -->

<a id="models"></a>
## 模型与几何

Direct MDL 与 Puppet 共用 typed 资源、canonical world/camera、材质、GeometryProduct、依赖发布及唯一 compositor；不能以图片 atlas quad 代替无法读取的真实 mesh。

Direct bind 几何沿原 MDL reader、准备资源和 StaticModel draw。不同 part/submesh/material/stream 只在实际 consumer 已接入时执行。

<a id="model-material-role"></a>
### 显式材质引用的准备角色

MDL实际引用的合法材料由原catalog接纳，不因目录或后缀提示漏掉整个模型。原SourceFacts已一次解析MDL并传additionalMaterialPaths及同份PreparedSource；此链不改、不再次读网格。修正只在原Catalog的cold queue：明确material角色随引用入队，优先调用原loadMaterial；ResourceIndex.kind继续提供普通引用的快速提示，不成为已证消费者的许可名单。

MDL附加材料、JSON model.material、粒子准备返回的材料及effect pass.material均有明确角色；普通effect dependencies仍用hint。原队列按规范资源身份归一，须保同路径先普通入队后明确提升、待处理/已处理两种情况，并保证同一材料至多读取解析一次；用原队列的索引与最小角色位替换仅按path的seen，不建第二parser、catalog、资源owner、持久状态或缓存。保package/loose/stock原来源优先级、取消及revision检查、排序、脚本与粒子交接。明确材料不再靠.json后缀授权，由原JSON材料解析器判断内容；坏材料只丢受影响part/消费者，身份失效沿原错误边界。未引用的合法/损坏.other JSON都不读，不扫描整库JSON，不加普通帧工作。

验收先在当前源取得明确引用的真实catalog/materialPass空失败；扩原catalog门核目录/文件/别名变体、普通先入队及后提升、同材料一次读取、未知JSON零读、真实坏输入与健康peer。原MDL reader→SourceFacts→catalog→materialPass门保多part/PKG及复用PreparedSource。复用本批已冻结的真实月球失败变体：同输入由material准备到实际model/main/seal/GPU并出现球面，另与materials/等价载体及独立原包核结果；不新增fixture算法或按路径选视觉结果。当前结果见[运行证据](model-runtime-evidence.md#model-material-role)。

<a id="model-single-frame-texture"></a>
### 模型静态材质的单帧TEX

静态模型的albedo及可选normal/map/lookup沿原TextureLoader typed candidate供货；一个物理image且恰好一个合法sprite frame没有随时间变化的内容，应按该frame的origin/双轴采样，不能因TEX的animated/sprite标志丢整个模型或静默退可选贴图。现有loadCandidate只接无sprite的整图，此处退该整类拒绝；多frame仍由原Catalog/provider和clock负责，不在静态资源准备中偷偷取第一帧。未接模型多帧资源前仍局部拒绝该类输入。

只在原Loader入口保imageCount1，带动画/frame元数据时须恰好一frame且通过原materialAtlasAdmission。保原axis/正向/atlas范围、duration/imageIndex与非volume结构边界，不借本批扩大仿射或跨image播放。原private makeCandidate接可选已准入frame，在原构造处投影UV并标isSpriteSheet；TEXS按首mip表尺寸归一，而legacy embedded图的实际decoded源尺寸可不同，frame原点/双轴须一次乘首mip尺寸/原缓存的firstEmbeddedMipSize（无embedded则用sourcePhysicalSize），才落回同一源像素，不重读/解码。普通raw/BC比例为1，输出降采样沿同源归一坐标。首mip表与实际源尺寸不同才补投影后的实际图域检查，源中没有的帧像素须局部拒绝，不能用clamp/repeat伪造；相同域不重复验范围。physical/mapped、来源revision、用途/色彩、sampling/format及上传缓存保持同一事实，既有Catalog多帧路径照旧。StaticModel原Entry/Frame/颜色/shadow直接消费同一候选，无新owner、时钟、字段、wrapper、重复上传或普通帧解析；比例/完整图消费者仍执行自己的原几何合同，不把一frame宣为identity。

验收从真实TEX/Loader与实际MDL准备开始：非零origin/非整图frame对照独立裁剪图，核候选元数据及实际模型颜色/遮挡/投影；改名、单帧duration0等价、真退化/非有限/越界及多帧拒绝，健康peer保留。原App用相同自有MDL、材质和相机比较旧缺模型与新frame/裁剪图完整像素，保遮挡/透明孔/健康peer；独立星球作者原包检查实际播放和合成。不靠candidate ready计数代像素，不授相机depth纹理数值读回、多帧热更新、全部静态消费者/仿射、官方像素或性能收益。pigment现pixelFrame以mapped atlas尺寸除frame轴，单帧与独立裁剪noise的像素密度未等值；线性atlas边缘也不等同独立图夹边，二者另按开放队列资格。 当前颜色/遮挡/投影及入口范围见[模型运行证据](model-runtime-evidence.md#model-single-frame-texture)。

<a id="model-named-albedo"></a>
模型材质的 named albedo 由原 dependency plan 准备。隐藏 raw source 须独立供货，隐藏 effect 可消费同一计划排在前面的 primary named 输出。模型的有效需求沿准备好的图边激活上游，依序发布当帧纹理，沿现有 pin 交给原 StaticModel draw。缺失、循环、未准备或要求作者位背景的输入按原图合同隔离。模型专用供货层因缺直接上游而旁路失败时，沿原 ticket 结束发布，不能把入口颜色供给模型。退休模型入口对合格 effect 上游的整类拒绝，普通帧沿现有颜色、采样域与纹理生命周期。实际颜色、改名、上游退出和独立作者模型见[验证](model-runtime-evidence.md#nested-model-albedo).

动态骨骼输出由原 mesh owner 提供按 layer/surface 隔离的有界 vertex slots；index/material 可共享，可写 pose stream 不按 path 共享。color 与 shadow 消费同一 frame binding；编码开始后不能偷偷更换 pose。未准备、lease/encode 失败跳过受影响 draw，不能读取未持有旧 buffer。

源码：[静态模型资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)、[DirectModel playback](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift)。

<a id="model-additive-blend"></a>
### 模型的加法颜色

原材质准备已经解析的 `blending=additive` 直接决定模型颜色管线：片元保持原 PMA，RGB 以 `one/one` 加到已有画布，alpha 沿唯一 compositor 的 source-over 合同；普通/半透明及缺省材质保原策略。层、材质和纹理透明度只乘一次。模型资源准备仅在存在该材质时创建相应原 PSO；反射与加法可组合，复用同一 fragment/资源，不按资源名或模型形状分派。缺失的加法 PSO 只拒对应 draw，不能悄悄按覆盖混合绘制。

保持现有深度测试、写入、cull、caster 和光照职责，不从加法或透明度推导统一停写深度，也不另建排序/深度域。原 Frame 直接把已解析混合事实交给原 Pipeline，退已保存 additive 却固定 source-over 的断点，无热解析、附加 pass、资源或输出 owner。生产 GPU 门以非黑背景检验 full/half/zero alpha、改名、深度写开关与近遮挡，保 normal/translucent 邻例；真实星星模型另验同帧颜色/主画布/GPU，独立无加法作者保持原画面。该 RGB 合成是本引擎明确的通用算法，不授全部官方材质语义。

<a id="model-depth-state"></a>
### 模型的测试与写深度

原模型 Entry 将 `depthtest` 与 `depthwrite` 分别准备成布尔事实，Frame 和原 Pipeline 消费同一对值。沿本引擎已有 image 逆深度合同：测试开启用 greaterEqual，关闭用 always，写入独立；复用现有三个 stencil，只补一份 always/write。关闭测试的后绘模型按作者顺序覆盖，是否改写深度只由写入控制，透明零覆盖仍不写。原冷解析同时归一两字段，沿既有模型策略保 nil/空/未知为开启，仅 disabled/false/off/0 关闭；这是项目默认，不宣官方未知值语义。不用完整材质准入牵连其它字段，也不加普通帧字符串解析。

测试关闭的模型是原透明 image 重排的顺序屏障，退出只凭 normal+写深度即可归入 opaque cohort 的旧判断。实际根域 opaque/alpha1/写深度模型仍由原 VolumeOccluder 收集；它携带相同测试值，原 camera-depth draw 依实际颜色绘制顺序使用比较或无条件写入，避免画面选了远表面、体积仍被旧近表面截止。保持既有实体覆盖资格、mesh/变换/cull、同池同提交，不新增资源、排序器或深度 owner。阴影的灯空间比较、castshadow 与透明资格独立，不跟随 camera test。新增 stencil 不可用时仅跳对应模型绘制；无需改旧比较深度路径。

验收先用生产资源/Frame/Metal 的近红→远蓝四组合及实际深度，保 alias/未知/改名、alpha0、后继绘制状态与原混合邻例；自有完整 App 用中间绿色表面区分写入，再核 transparent image→no-test模型的排序屏障、同模型开启测试的合法重排邻例，以及真实实体收集到体积深度的近远顺序。独立作者启用深度只授原路径回归，不充作 disabled 正例。模型/图像共享原逆深度域，不扩为文字 disabled 排序、任意半透明体积或官方像素一致。

<a id="model-shadow-coverage"></a>
### 模型阴影的实际覆盖

具有可见覆盖的半透明材质网格（如星环）已能遮挡其它模型的直接光，Frame按translucent整类拒绝caster的旧门已退出。颜色blending不充作灯域投影许可；唯一作者cast intent与原prepared可见draw决定候选，normal/缺省/additive现有结果保持。阴影与camera depth test/write独立，不按混合、写深度或材质名建立新白名单；明确不投影、hidden/父隐藏与无prepared几何仍沿原路径退出。

复用drawShadow已有自有二值覆盖合同：clamp(material.opacity×layerAlpha,0,1)，只有原textureAlphaIsOpacity才乘实际albedo A，最终coverage>.5写灯空间深度，≤.5/透明孔保持原深度；tint-mask A不误当洞。三灯共用原shader/cull/当前同帧mesh/world/UV/sampler，原定向bounds本已包含有cast intent的半透明几何，不新建范围计算、PSO、map类型或caster状态。新增caster会沿原有每灯map/同提交增加实际绘制，首个caster也可能触发原map申请，不授零成本或性能收益。这里只恢复该既有覆盖消费者的可达性，不宣半透明透射/有色阴影/官方阈值；原additive既可按作者intent投影，未获新反例不另加类别禁令。

验收沿真实Frame收集→原灯map→接收者像素及map深度，用translucent有覆盖/孔洞/透明边界，与同输入normal及明确castfalse作可区分对照；核material与layer alpha、mask含义、cull/改名和camera-depth独立，保additive原行为与三灯邻例。冻结真实星环MDL/TEX与接收球面、灯/相机/相位，旧/新App核实际投影和孔洞，另用未参与修复的真实作者保原受光/完整图。官方证据不足时依此明确几何覆盖算法验收；若原景投影难以归因，使用同真实资产的自有控制，不拟合阴影ROI或以caster计数代像素收益。当前资格见[模型运行证据](model-runtime-evidence.md#model-shadow-coverage)。

<a id="model-normal-map"></a>
### 模型法线贴图

目标是让实际模型材质的法线图改变世界受光和已有反射，保留真实几何的深度、遮挡和阴影轮廓。沿已资格 stock `generic4/chroma4` surface profile，在实际照明/反射或Chroma非常色view tint消费者需要法线时准备 slot1；显式 `NORMALMAP=0` 关闭，省略时由实际槽供货启用。自定义 shader 和其它材质族仍需各自实际消费者，不由槽序号猜用途。

`authored material/slot1 → 原 TextureLoader(.normal) → 原模型 Entry 的不可变 normal binding → 原模型 draw → 唯一 compositor`。准备期一次决定原 TEX 格式的 RG、A/G 或压缩 A/G 解码；没有 TEX 元数据的普通图片采用标准 RGB 法线。保每张图自己的 UV 和 sampler，不依赖 albedo 的尺寸或格式。原 vertex 以模型线性矩阵变换 tangent，以逆转置变换 normal；fragment 正交化切线，按原 tangent.w 和模型镜像手性构造标准 TBN，再归一化扰动法线。动画继续消费原已更新切线，不增加骨骼计算或第二几何流。该非均匀缩放策略是本引擎的自有几何算法，未授官方像素一致。

无图、显式关闭或可选资源失败保几何法线和原颜色；零切线/退化采样局部保几何法线，不拒整模型。仅启用的图增加一次片元采样；不加逐帧资源解析、缓存、状态树、深度 target 或 PSO 家族。环境的几何方向渐变、阴影的实际接收平面和 caster、alpha/深度继续原合同；直接光、已有反射及Chroma view tint消费扰动法线。原反射的“有 normal 即拒绝”限制随消费者退出，分量图沿[原分量消费者](#model-material-map)独立准备，外部反射图仍待接入。

验收沿原模型资源和 production Metal 门，覆盖平法线、相反切向扰动、tangent.w、旋转/镜像/非均匀变换、独立 UV/采样、原格式与普通图片、显式关闭/缺图和健康 peer；另核原 alpha/深度及反射邻例。真实月球和独立楼体使用原包取得实际 normal binding、同帧 main/GPU 与画面，不以 slot 声明代贡献。实现及运行资格由本节与[模型证据](model-runtime-evidence.md#model-normal-map)分别维护。

<a id="model-material-map"></a>
### 模型的分量贴图

活动stock generic4/chroma4模型的slot2参与金属度、粗糙度、反射与发光，而非只作发光A图。沿原material/Entry/TextureLoader/Pipeline/Metal承接：原SurfaceProfile描述已证明stock来源的静态数值材质，不再把LIGHTING关闭混作非stock资格；normal按实际照明、反射与Chroma view tint需求准备。保原标量M缺省0/R缺省.7及显式0，stock发光亮度缺省按材质合同1，只有真实A分量才产生发光；未取得该profile的材质保原legacy响应和默认，不新增猜测来源。

用一份typed material-map binding替换emissiveMask及其三个可空GPU参数，持原纹理、独立UV/sampler和冷准备有效位。沿已存在TEX bit20…23元数据，R替换metallic、G替换roughness、B乘reflectivity、A乘emissivebrightness；分量combo省略取header，显式0关闭、任意非零开启，与原编译宏的整数#if语义一致；header不是显式分量的授权门，普通PNG也可由作者明确选择通道。PBRMASKS显式0仅关闭整张分量图，保albedo/normal与标量响应；其它非零允许。缺图或无有效位回标量/无附加发光；A combo省略时，MR载入不能把没有A metadata的RGB隐含alpha1当发光；作者显式非零A按原通道值执行。未资格legacy材质仅保原有A路径。退出因发光亮度为零就不准备真实MR、已具map却固定标量、以及因显式MR/B map拒反射的旧限制，不保第二mask字段、第二纹理加载或兼容draw API。

原shader每片元最多一次slot1数据采样同时供四分量，复用原SurfaceResponse、主画布反射、normal、fog、PMA、alpha/depth/caster与唯一compositor；有效位随原uniform传入，不增ABI字节、PSO、缓存或普通帧解析。原资源入口已确认的mapUV/sampling不再以多组可空参数在draw重复校验；可选资源失败只丢相关分量，不阻断albedo/模型。新增typed binding承接真实多消费者数据及退旧nullable三元组，不建资源owner。

验收用真实准备→原Frame/Metal的分区map与相同M/R/B/A的纯标量/显式图邻例作等值像素对照，保省略位缺失/显式启用及禁位、总开关、非零整数变体、标量0、缺图、独立UV/sampler、完整改名、法线/反射共存、HDR/alpha/depth；既有发光及shadow门按影响补测。原月球53/77须实际绑定非恒定分量并取得完整作者画面；分量运算由等值标量门和隔离真实资产的固定球面开关对照归因，不能把作者供货直接升级为严格原景A/B或77逐part贡献。另用独立真实样本检查启用与无map邻例。未取得作者/官方分量像素配对时以明确的本引擎材质运算和等值标量正反例判定，不拟合亮度或宣全部官方像素/性能。

<a id="model-shading-gradient"></a>
### 模型的渐变漫反射

已开启SHADINGGRADIENT的stock generic4/chroma4模型沿原受光链消费真实slot4。只沿原SurfaceProfile资格、LIGHTING与明确非零combo准备；省略/0不读图。沿既有静态文件链消费slot4，文件与typed userTextureInputs[4]均省略时沿该stock材质族声明的默认gradient/gradient_toon_smooth供货；本批不接用户纹理provider，明确用户输入而无文件时只缺该lookup，不能用默认冒充；不授完整user/file优先级。显式坏图只退普通响应，不偷用默认、不拒整part。自定义/覆盖root shader不取得此固定材质语义，不准备整套generic Program来读取这个已资格stock默认。

原Resource/TextureLoader按data用途与真实格式准备一份typed lookup binding：纹理、sampler、R8/RG88复制R或其它RGB，以及由原UV变换一次投影的水平中心采样线(origin+.5*yAxis,xAxis)。Entry→原Frame→Pipeline直接携带；新增一个16B uniform及texture8/sampler3，沿原lightCounts空分量编码禁用/R/RGB，不加varying、PSO、pass、池、cache或owner。普通帧不解析/取资源/重投影不变UV；无图仅保固定ABI与未采样占位绑定，不授零成本。

本引擎明确算法：对实际normal-map扰动后的signed N·L映射u=(N·L+1)/2，沿采样线取得RGB漫反射cosine响应，替换原SurfaceResponse的漫反射cosine因子。共享owner仍唯一计算Fresnel/GGX/Smith，原正向NoL单独供specular；两个实际caller各算一次dot并显式交入两响应，图像仍交普通NoL，不加overload/sentinel或复制BRDF。模型三灯共用原response，radial/cone/light/color/真实shadow visibility继续各乘一次，不再把ramp乘NoL或最终RGB。ambient/skylight、emission、reflection、view tint、fog、覆盖与深度保原次序。没有官方像素对照时依此通用算法验收，不拟合月色；轮廓响应沿[轮廓合同](#model-rim-lighting)独立准备，两项都不授完整stock风格光照。

验收用原实际资源准备→Frame/Metal门的负/零/正signed夹角、常量/彩色ramp及等值灯色邻例，核R8复制R、非零整数、改名、normal扰动、独立有效域/sampler、禁用/unlit/缺图/覆盖shader、阴影/衰减/环境/HDR/alpha/depth；不抄BRDF进测试。冻结真实月球资产同钟前后及on/off输入核像素贡献，并核原月球活动53和77具体part的实际lookup供货与完整图，独立无gradient作者回归。共享SurfaceResponse变更按影响补图像与模型原行为门，既有同身份有效结果复用。当前结果见[运行证据](model-runtime-evidence.md#model-shading-gradient)。

<a id="model-rim-lighting"></a>
### 模型的轮廓漫反射

活动stock generic4/chroma4的RIMLIGHTING沿原直接光执行，不另造灯或视角发光owner。沿原SurfaceProfile资格与LIGHTING，明确任意非零combo才冷准备rimamount/rimexponent，省略默认2/4；0或省略开关关闭。复用原staticComponents的实际静态值合同，错型/动态/不完整值仅令rim amount为0，保原M/R/反射profile；不新增键名单、编辑器范围许可或热解析。数值在冷入口归一到非负GPU Float可表示域，负数归0，超出Float上限夹到其最大有限值；显式amount0与exponent0均合法；原typed ShaderValue尚未区分的错型动态声明仍交原helper的完整声明边界，不删有实际消费者的门。

本引擎明确自有算法：扰动后的world normal与当前view在片元求一次rimWeight=amount×(1−saturate(abs(N·V)))^exponent；exponent0定义曲线恒1，包括正面边界。原model SurfaceResponse把正NoL×rimWeight加到已有diffuseCosine，再交同一shared BRDF，Fresnel/GGX、每灯color/intensity、radial/cone与真实shadow visibility保持原乘法与次序。abs使正背面轮廓对称；此项属于漫反射，metallic1无贡献，NoL0、无直接灯、纯ambient与完全阴影也无rim贡献，即使gradient照亮背半球。该语义比独立自发光更贴物体受光/遮挡目标；不据阅读的stock灯内结构宣称官方像素一致。

在原SurfaceProfile加两值、原uniform末加16B参数，amount0表示关闭；没有新增enabled状态、texture、varying、PSO、pass、池、cache、Frame owner或共享BRDF API。amount0或没有直接灯时不求pow；所有实际灯复用同一片元视角权重。原normal、view、gradient、view tint、fog、PMA/alpha与depth沿当前链；旧‘已保存combo却无消费者’退出，不把rim用作最终RGB增亮、环境或阴影外补色。

验收分静态准备和真实像素：原真实static helper及实际surfaceProfile调用核缺省/普通/user:null、动态/错型与raw/count/finite变体，只退rim而其它profile保持；不拿GPU载体的已类型化静态替身冒充入口验证。复用原Frame/Metal门，以同几何/相机事实的rim闭式权重和独立普通灯色控制核正面/侧面/背面、0/非零整数、exponent0、normal/gradient/金属、三灯/衰减/cone/真实shadow、无灯/ambient/发光/反射/HDR/alpha/depth及改名，不复制BRDF。复用冻结真实月球资产同钟RIM1/0与旧App，核实际像素贡献；原月球和独立作者补完整图。可复用同身份载体与已证输入，只补本批影响范围；rim用户provider/动态MR及官方像素不由静态正例外推。当前结果见[运行证据](model-runtime-evidence.md#model-rim-lighting)。

<a id="model-chroma-surface"></a>
### Chroma 的共同表面受光与颜色次序

真实Cloud模型的stock chroma4已消费共同M/R与高光tint，退出legacy Lambert丢掉声明的路径。原SurfaceProfile承接已资格的generic4/chroma4种类与静态specularTint（缺省白）；同一次冷选择按实际shader标识核原两stage来源，不按模型/媒体路径选算法，不新增分类owner/cache。M/R继续原静态完整值合同；Chroma的specularTint坏/动态值只退白，不丢其它profile；generic4仍白色高光。tint向量沿原三个有限分量合同，不在消费者重解已归一raw文本或增加文本形状许可。任意shader、动态M/R与未资格来源继续原边界，不把本批静态profile授为通用shader执行。

两种stock profile共用原normal、分量图、反射、gradient/rim与shared SurfaceResponse；无直接光/反射的Chroma仍在view tint依赖法线时预载normal（front/back不同或有动态back），静态常色不为view tint读normal；Chroma实际也声明这些consumer。specularTint只乘原weights.specular，不修改F0、Fresnel、diffuse分配、反射或灯能量；roughness0沿项目delta规则无有限高光。mask时高光tint按原albedoA从白混合至作者tint。原light/color/attenuation/cone/真实shadow各乘一次，不复制BRDF或直接调场景灯。

Chroma先形成有效surfaceColor再进BRDF/F0：无mask忽略全局color；有mask按原A混合luma/color，view tint另按同一A从白混合至front/back结果。无mask的view facing保原signed合同，指数只在mask读取；声明单侧front/back时另一侧缺省白，均无声明不准备无用view运算；当前已消费的动态tintback沿原typed copy，更多writer另行资格。generic4保原全局color与受光后view tint次序。原view公式只计算一次后按准备种类应用，退出Chroma通用晚染色职责；Pipeline已经投影的指数下限不再在Metal重复clamp。

HDR时Chroma的raw颜色先不乘brightness，直接光、项目原A追加发光、ambient与reflection合并后统一乘原HDR gain，随后fog/PMA；必须只对Chroma退原reflection内的gain，避免平方。generic4保原HDR算法，不借共同profile改它的已证像素。宿主material/layer alpha、mask覆盖、depth/cull与最终合成继续项目合同，不能由参考片元未读g_TintAlpha推断宿主透明度失效；不照译参考的max/overbright发光。pigment/noise沿[独立颜料合同](#model-chroma-pigment)消费，不宣完整Chroma或官方像素。

只在原profile加种类/静态tint，原uniform末加一份16B（tint.xyz与颜色种类w），不新增flags位、纹理、varying、PSO、pass、Frame、池或状态owner。为前置view tint，原alpha/discard整体前移到albedo/component/normal隐式采样及world导数之后、shadow/灯/tint之前；后续gradient/reflection为显式LOD、shadow为无mip depth，不新增导数状态。普通帧不解析/重新资格或做资源查找；关闭/白默认仍有固定ABI/共享片元成本，不授零成本或性能收益。

验收在原资源→Frame→Metal门用白tint/pigment0的Chroma与generic4等值M/R、三灯/normal/map/gradient/rim/遮挡，R0 tint无贡献、R>0零/白/彩tint从实际输出分离两瓣，反证改F0或最终RGB乘tint。核无mask color无效、单侧默认/动态back与先染albedo参考、mask0/半/1同时限制view/spec tint、HDR反射/发光只一次gain、宿主alpha/depth/坏图/覆盖与改名；含带mip normal的透明边界，确保discard迁移不改采样。复用真实parser/helper/profile CPU门与同身份载体。冻结实际Cloud几何/原TEX与alpha、白front/back、pigment0的同灯旧/新控制只授MR贡献；原作者完整图与独立generic4回归不代R0有限高光或pigment资格。当前结果见[模型证据](model-runtime-evidence.md#model-chroma-surface)。

<a id="model-chroma-pigment"></a>
### Chroma的颜料噪声

实际Cloud的tintpigmentation .2已产生受光表面的细粒明暗，保真实几何遮挡、纹理覆盖与其它辐射来源。只在原已资格Chroma、receivesLighting及静态完整标量amount>0时冷准备slot8；缺省0，沿原staticComponents归一到[0,1]，动态/错型只关此项。明确文件按原静态链，文件与typed user输入都省略才用该stock声明的util/noise；显式坏图或无file的user仅退普通受光，不用默认冒充。将gradient的同一默认所有权判断并入原optionalTexture一次，退原消费者重复判断；不接新provider、cache或Program。

本引擎自有算法：按当前目标物理片元坐标除noise mapped extent，再沿该资源独立UV变换及sampler取data noise，RGB均值先saturate至[0,1]再映射signed[-1,1]（R8/RG复制R）；该采样归一也承接SNORM数据，不按格式白名单拒图；directRadiance乘1+amount×signedNoise。amount≤1使权重非负且最多2，不叠加资源校验、视距/正弦/时间状态或view边缘拟合。此调制在三灯各自BRDF、衰减/cone及真实shadow累加之后执行一次，随后原ambient/skylight、项目追加发光、reflection、Chroma HDR/fog/PMA依原顺序合并；不改shared BRDF、F0或灯能量。全影/无直接光不能由noise补光，alpha、模型depth/caster不变；噪声锚定当前目标像素，物体移动或换target会改变纹理相位，不授world/object锚定；不宣stock空间相位、官方像素或能耗收益。

原Entry新增一份可选不可变pigment binding，只携texture/sampler、预投影pixel→UV及通道事实，amount由原SurfaceProfile唯一保存；静态UV除法在冷准备一次。原Frame传给Pipeline，原uniform加32B、texture9/sampler4，没有新varying/PSO/pass/池/时钟/输出owner。amount0/无图不读noise，无直接灯记录时也不取样；固定ABI/占位绑定不称零成本。原‘已保存数值与slot8却无消费者’退出，不把noise乘最终RGB或albedo。

验收沿现有资源→Frame→Metal：黑/白/彩noise .2与仅灯色.8/1.2的独立等值控制，核三灯、全影、混合ambient/emission/reflection、normal、HDR/half/zero alpha/depth、slot独立采样/空间与改名。缺省/0、generic4、unlit、坏图与明确user缺file不加载噪声；真实parser/helper的静态/动态边界另验。冻结原Cloud几何/TEX/alpha及相同相机/点灯，只切0/.2，核可见颜色贡献与原输入不可变；原Cloud与独立generic4保完整图。真实.2已有细粒颜色贡献，当前范围见[模型运行证据](model-runtime-evidence.md#model-chroma-pigment)；不以绑定或测试数代成果。

<a id="static-model-screen-reflection"></a>
### 静态模型的屏幕反射

已资格 `generic4/chroma4` 的 `REFLECTION` 可用原 mesh 世界法线、视向和主画布片元位置读取场景反射。材质准备保留本路径实际消费的静态 reflectivity、roughness 与 metallic。采样以屏幕偏移、边界淡出和粗糙度 mip 表达，再按材质视角响应加入 HDR 亮度、雾及覆盖所在的原终端顺序。主画布采用几何法线或[实际法线图](#model-normal-map)及[分量材质](#model-material-map)；外部反射纹理、动态MR/reflectivity及局部组反射仍待接入。光照和反射独立，缺反射输入时继续原模型颜色与深度。

反射沿现有 Surface 的 ReflectionFrame 读前一完成的主画布颜色，复用同一 mip 纹理、预算、失效与提交 pin。只有可见且已准备的接收者触发需求。命名颜色仍在原图层位置供货。若当前只有主模型深度域，后到的命名颜色可与已确定可画的反射模型共用这一域。保护既有必需终端及捕获容量后再取得可选 history，部分证明不发布完整模型 draw set。组、深度写粒子、未保留容量的命名供货和命名 shadow 留原容量顺序。首帧、尺寸/代次更换或容量不足只缺本帧反射。

用同一原生帧的反射开关、遮挡与背景控制区核实际模型像素，覆盖同帧上游命名颜色晚供货、首帧和稳定帧。独立样本保原反射消费者与无反射模型。真实作者水滴以固定取景核边缘及尖端，官方开关对照区分材质反射和全屏后处理。


<a id="model-subtree-raster"></a>
## 模型的局部合成

目标是让 composition/project 的实际模型颜色进入原组 source、父 Program 和唯一 compositor，沿原 StaticModel draw 直接承接，不引入 renderer、depth owner、资源、缓存或 GPU ABI。

`authored MDL/material → prepared model/typed frame → shared world/normal/light → nearest MainPass 的 rasterClipProjection(reverseDepthVP) → 原 model color/depth → group source → parent Program/main`。MainPass 只改 clip XY，保原 Z/W；同一 XYW 平面映射的 XY determinant 决定 color raster 的 frontFacing，使镜像组仍按原世界投影选择正反面。VP 与绕序每 layer/pass 只求一次，各 part 复用；不关闭材质 cull，不把 child/world 负缩放当作画布反转。world/normal、camera position、lighting/shadow 继续原世界空间。无局部 map 复用原 VP/CCW。模型和同 pass 的合格 terminal 沿既有按 pass 分域的 reverse-depth target、首清与 lease/pin；不同组不得共享 depth，资源失败局部处理，不用平面 image MVP 改深度。

SourceRoute 不再整类拒绝 model，不追加材质/效果/几何名单。typed snapshot 与当前 visibility 继续决定实际 draw，不创建新的激活状态；只核现已消费的 model tintback producer，未消费材质/光照 writer 仍沿原边界。当前资格含静态初始可见组、已准备 model 自身显隐，以及 composition 父组热显隐和冷 Bool/Script 开启的实际 source、父 Program 与 tintback；child false 保留。冷父自身 visibility 回调和外部图层 setter 分别取证，不由 warm 成功外推其他准备组合，也不以初始 visible 作为播放许可。

父组 visibility 沿原结构需求、RuntimeModel producer 准备、Launch 资源/Program 准备及原消费链收敛：无 layer effect/dependency 的稳定 model leaf 是结构准备需求，替换只接单个 prepared leaf 的例外；实际 leaf 消费仍要求原 GPU Entry。原 mapper 从已解析 property binding 取得潜在 Bool visibility 目标，所需 kind 必须与唯一实际属性 kind 一致，再与 structural vector 目标及原 script layer access 规则共同经过结构准入。准备阶段仅将这些 roots 的 typed visibility 视作 true，复用原 snapshot/visibility memo 取得可被揭示的成员，再沿现有颜色 consumer 分类构造后代 producer；不以 model 全名单构造 VM，不重复编译整套 property program。CandidateCatalog 消费该需求，退出另一处初始 visible 限制。临时准备 snapshot 不发布到 domain 或普通帧，UI 和 Script 共享同一实际 producer；不增加仅 UI 有效的动态 back gate、Launch 需求表或逐帧检查。

必要供货只包括这些 roots 能揭示的成员，后代继续用原 display authority，保 child 和中间组自己的 false；只有其自身也是合法可写 root 时才准备它的未来消费者。祖先 hidden 的合格后代由同一需求供给实际 back owner，不能仅在 UI 拒绝后让 Script 显示旧色。utility 的实际 source/Program 容量仍由原 execution capability、utility plan 和执行者承接；LiveConsumers 复用相同准备事实，hidden 但已准备的 source 仍可 capture，原 local-source 无 effect raster 与合法无输出分支不要求虚构 Program。保既有 cold image/particle、producer 失败的原局部 fallback 和 property transaction，不新建 ready 状态。坏 child 没有 Entry 仍沿原局部跳过，不能要求父组每个 authored child 都有 GPU ID；独立坏 leaf 与其他目标同 property key 的原事务拒绝保持。结构错配、cycle、未支持 utility 和未消费 writer 不借隐藏或 model 放宽；结构准备不等于执行许可。旧 leaf 准入分支及失效全拒断言在替换时退出。

验收用现有原生 App 门的自有 MDL：普通 transform parent 与局部 composition/project 的对应像素，父颜色 Program 和 source→父输入→main/seal/GPU，同组 near/far opaque 与 nonwriting translucent 交叠、独立组 depth、非均匀父 TRS、镜像画布与双负模型的单面正反例及改名，已准备 model 自身和父组 `true → false → true` 不残留、真实 tintback、child false、坏模型/健康 peer。保祖先 hidden 的 Script/UI producer 供货、source 有效但活动 Program 未准备及同 key 独立坏 leaf 的反例，并回归已有 hidden image/particle 准备；准备事实不代替实际 cold 画面资格。沿现有行为门核 pass depth/失败与 root nil-map，不复制渲染算法进测试；独立作者模型核普通路径回归，不称作者 composition 恢复或官方像素一致。若需新状态、重设深度、另一投影/owner 或未知材质语义，回到本设计，不以新白名单掩盖。

<a id="perspective-image-terminal-depth"></a>
### 普通透视贴图的终端深度

原生透视场景明确启用 `general.transparentsorting` 时，先在同一主画布绘制不透明模型，再合成可重排的局部透明图像效果。效果仍使用原 source、graph 与世界投影，终端读共享深度并停写深度，防止空白纹理矩形把后绘的星空挡掉。先接入无外部供货、环境或画布输入的普通透视 image。它不进入 placement 重放，退出用重放能力位跳过该终端状态的分支。关闭排序和其他终端沿各自原路径。

在既有帧顺序内，只重排由合格效果、不透明写深度模型和无绘制项组成的区间。效果按相机深度远到近，同深保作者顺序。实绘但未接入的层、组、供货及画布观察都截断区间。资源准备和实际编码消费同一顺序，命名供货及观察点的位置保持原相对顺序。该范围不接入跨组、透明模型、粒子或依赖当前画布的效果重排。

原 MainPass 的 reverse-depth 域由模型和贴图绘制共享。命名模型颜色尚未发布时，按作者顺序准备已确定的必需深度，推进至第一个主域模型，普通终端可借其中已取得的主域。未准备的模型继续在原作者位置解析颜色，前缀不发布为完整 draw set。Framebuffer source 继续要求完整准备。组、粒子及其他域保原资源优先级，首个实际 encoder 清零，后继读取同一 lease。

普通终端的写深度在实际合成片元上判定覆盖。来源已沿原 straight/PMA 语义、遮罩和透明度形成最终颜色，四通道精确为零的片元退出光栅，不挡住后来图层或模型。极弱覆盖和零 alpha 的非零关联 RGB 保留作者深度策略。仅为现有写深度模式准备同一 fragment 的覆盖变体，读深度、无深度、来源捕获及效果重放沿原管线。无阈值、图层重排或额外深度资源。

验收覆盖透视效果的遮挡区和露出区、明确关闭深度、后绘模型和透明空白区、排序关闭对照、重放邻例、待供货模型、首次清零和容量失败。用同机位的作者地球与关闭 Bloom 的可区分对照，并用原包核对轨道、行星与星轨标签恢复，以及独立世界样本的星空背景和恒星光晕。

#### 作者文字深度

原生透视的普通 source-over 文字，显式 `depthtest: enabled` 在准备阶段转成已有普通终端的读写深度策略。CoreText、Script 与效果先按原路径提供颜色和覆盖，字形直绘与效果尾部在实际世界投影下消费同一主画布逆深度。透明留白沿原零覆盖规则退出，后绘的远模型在字形处被挡，近模型仍可遮住文字。保持作者绘制顺序、原资源与 Pipeline，不新增文字渲染器、深度池或颜色捕获。

透视文字效果沿原颜色输出到普通终端，纯色物化和非透视 replay 保各自原入口。缺省、关闭、错型和其它画布的文字继续原路径；共享深度域不可用时沿用普通 image 终端的失败合同，不另造无深度回退。验收保直绘和透明度效果、后绘远背景、先绘近遮挡、透明留白、关闭及改名；真实世界文字与当前条件差异归[运行证据](runtime-evidence-current.md#authored-text-depth)。345 的关闭深度时钟差异尚未取得通用调度合同；隐藏后绘模型的诊断不能作为排序修法，不将无深度文字统一升级为 overlay。

<a id="legacy-bind-mesh"></a>
### 旧版 Puppet 的网格与动画

MDLV0013 的 52 字节顶点布局与已有 position/UV bind mesh 消费者相容；沿原 MeshReader 读取真实顶点、UV 与索引，再经原 LayerLoad、GeometryProduct、effect graph 和 compositor 输出。版本描述只选择已知存储布局，不以资源名、样本或摘要许可绘制；不增加第二 importer、资源 owner 或逐帧解析。

网格与动画分别准备：MDLV0013 配对 MDLS0001 的 bind-local 矩阵、父索引与四路权重，以及 MDLA0001 的完整 TRS 轨道、frameCount+1 采样和四字节零尾；沿原 Reader、Selector/Evaluator、AnimationPlaybackRuntime 及 Surface geometry 执行。空骨名保数值骨索引，不伪造名称或重排。无 reference、alpha、event 或 morph 数据时不另建通道；各版本仍消费自己的实际 trailer，不用旧版四字节放宽其他格式。

坏 mesh 保对应 draw 失败；坏权重/rig/clip 由原 LayerLoad 保独立 bind mesh 与明确原因，不发布假动画 metadata 或 atlas quad。验收覆盖原 Reader 的改名/偏移、矩阵/权重、轨道/下一 clip 与截断/错配反例，实际不同 phase 的 pose、动态 geometry 及所选帧最终贡献；纯 bind 正例不代替动画资格，更广旧格式和官方像素一致仍需独立验证。

<a id="puppet"></a>
## Puppet 动画与当前 pose

Reader 保 mesh/rig、weights、clips、TRS、alpha、events、reference 与 auxiliary presence；Selector/Evaluator 决定实际可执行通道。会话 AnimationPlaybackRuntime 唯一持当前有序实例、clip 位置、rate、blend、命令和事件；每屏 Surface 持派生 selection、pose/physics 与骨骼写入，不另定实例寿命。

- 同 cadence 先同步 committed 成员、采样动画，准备 pre-script pose，执行 VM，应用骨骼写入，完成 skinning/attachment 并冻结。暂停、无 drawable 和 GPU retry 只消费该帧。
- 新 rate 保当前 phase 后重锚，不按 `sceneTime × 新rate` 从头计算。已准备的合法参数 Timeline 与 String 条件选择使用原 typed producer，当前坏值不覆盖上一健康播放。
- 一个实际 active 的 non-additive clip 使用其完整 absolute pose 和真实 blend；额外准备的隐藏 clip 不改它的算法。translation/scale 线性插值，rotation 用现 quaternion 最短弧，不能线性插 Euler 导致跨界绕远路。
- additive 与多个 opaque/reference contributor 受现选择和 evaluator 范围限制；bind-equivalent reference 不等于所有独立 reference 都已支持。
- 骨 alpha 是该骨的实际贡献，不沿 parent 重复相乘。DirectModel 的非中性 alpha、未消费 auxiliary/shape 和非空 attachment 仍可触发 typed bind-only 降级；必需 mesh/rig 坏数据不能被当作可选动画缺席。

Surface 退休已销毁成员的 CPU/GPU/clock 引用，重建不复活；准备模板与共享资产保留。Puppet geometry storage 与 paint/PSO 准备分开，出生只读准备结果，不重新读取 paint 或编译 clipping pipeline。

源码：[Selection](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationSelection.swift)、[Evaluator](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetAnimationEvaluator.swift)、[Surface 装配](../../../MyWallpaperX/Core/SteamWorkshopScene/Runtime/Session/SceneDesktopWallpaperSession+SurfacePuppets.swift)。

<a id="puppet-instances"></a>
### 运行时 Single 实例

目标是让图片的真实 Puppet 资源可在脚本调用后播放一次并自动退出；[公开 API 合同](https://docs.wallpaperengine.io/en/scene/scenescript/reference/class/IImageLayer.html)与本机桥接范围见[脚本合同](scenescript-api-coverage.md#image-single-animation)。沿原 prepared asset 的 animationSet 在冷准备期准备受支持的 Single 源，源表与当前实例分开；原 asset evaluator 的同一准备结果保各源成功/失败，同 mesh 的实际 authored ID 与可创建 Single 源只冷编译一次，各 pose 共享；必需源沿冷选择抛原失败原因，不编译无需求的其他源；没有作者 animationlayers 的有效图片也保可创建实例的 evaluator/geometry。必需 authored 源失败保原局部降级，可选源失败只失去该源，不重读资源、热 prepare 或制造假 authored 层。

原 playback runtime 的有序实例承接作者和创建实例；作者身份保原 authored ordinal/editor ID，创建身份复用原 callback epoch/command ordinal。原 journal 按 create→control 顺序准入并一次 apply，失败沿原 owner bundle 回滚。出生从本地 phase0 开始，退出 authored first-visible 的绝对场景时间规则；普通作者播放不改。自然 Single 完成由原 cadence 移除一次，与 JS ended、drawable、GPU 和 Surface 数量无关；父/会话退休沿原链释放实例，共享准备资产不随单实例释放。

同一 frozen LayerFrame 给出有序成员到源的投影、samples/blends 与成员 revision。Surface 只在成员变更时采用原 selection、调整原 signature/alpha 派生存储；骨查询、physics、挂点和 geometry 共同采用，保 rig/physics/GPU 寿命。原固定 authored 数量、public stack index 等于 authored identity index、零 authored 永久 bind-only 和 callback 热准备的假设退出；不新增时钟、实例 owner、源 catalog 或 pending 状态副本。重建消费当前成员，不复活已结束实例。

首批只接真实资源名 String、受支持 Single、缺省 config，rate1/blend1/visible/playing 与无额外包络是本项目基本实现选择，尚非官方默认值资格。Object/config、Loop/Mirror 转一次、重叠排序/包络、Single JS ended 及过期句柄精确边界保未资格；原 authored 多源、Loop 事件和 bone 写入继续原规则。验收覆盖真实零 authored 资源的内点 pose、晚场景出生、暂停/定位/恢复/自然移除、同事务后继控制与回滚、成员重建及健康邻例，不以非黑/metadata 或末帧 bind pose 代替实际播放。

<a id="puppet-attachments"></a>
### 有序挂点与名称绑定

目标是让子层持续跟随父 Puppet 的实际挂点，保原图层层级、动画与唯一 world/output。MDAT 是有序记录，名称重复不使整表失效；名称绑定选该名称的首条记录，后续同名记录仍保原 ordinal、骨索引与矩阵，不能重排、覆盖首条或伪造名称。现有 Reader 在入口完成结构、骨索引和有限仿射矩阵检查，并用已有名称 Set 的插入结果保存每条记录不可变的 `isNamedBinding`；这是解析事实，不增加缓存、名称 owner 或逐帧去重。

`MDAT → typed attachment records → 原 Catalog/Descriptor 的 bind frame 与 PreparedPuppet 的 live frame → Surface 当前 pose → 原 LayerWorldFrameResolver(parent × attachment × child) → geometry/compositor`。冷、热两个消费者都只采用选中记录；退出 Reader 的重名抛错、Descriptor 对未筛选重名的 unique-key 构造及 live 投影的重名整表拒绝。两张结果表分别属于准备期 bind 与当前 pose，不合并成第二状态源；普通帧不重读 MDL、不重新决定名称。保原 model→Scene 的 Y 共轭：骨姿态和 MDAT 保模型域，父/子 layer 与最终 geometry 的坐标边界共同完成投影，公开作者 API 的相对平移不能单独授权删除反射。

坏结构/骨/矩阵仍沿原资源局部失败与 bind/parent fallback，不能因允许重名而吞掉坏记录。未找到名称继续使用原 fallback；独立健康模型和层不受影响。本批不新增数字挂点 Script API、不改 BoneCatalog 的名称规则、不解其他样本运动幅度，也不迁移矩阵 owner。首条规则的官方依据限定为固定客户端的同名记录、顺序互换及名称/资源改名对照，资格与未覆盖版本归[运行证据](runtime-evidence-current.md#puppet-attachments)。

验收复用真实 Reader/Descriptor/PoseProjection/WorldResolver：唯一名不变、首尾重名保序、交换后跟新首条、改名及等价父子仿射表达式、缺名与坏记录反例；cold bind 和不同动画 phase 的 live 投影采用同一记录，父 TRS 与原 Y 基闭合。再核原作者头部的实际几何与最终画面，以及未参与修复的唯一名挂点作者。若必须改坐标或引入新准备状态，先修订本设计，不能按名字、资源、偏移或截图选择算法。

<a id="clipping"></a>
## 部件裁剪

当前 MDLV0023 已接入有序 draw-part ranges 与 counted target/source ordinal 数组；空 part 保 ordinal。未知 flags、越界、截断或重复 target 拒绝该 mesh，不压缩 part 表或跳坏 record。

原 `ScenePuppetClipping` 在准备期去重 source、排除当前 target/self 与空 part，建立 nested coverage 顺序；cycle 及真实下游局部不可用，独立分量保持。普通帧只准备当前变形后的 coverage，不重读格式/paint 或重建关系。

main/named consumer 分别按实际 extent/MVP、target bounds 和采样密度取得 R8 coverage，保透明边界。opaque source 重叠采用当前 max coverage、paint red 与 nested coverage 相交；source vertex coverage 非一的合并语义未完整资格。target alpha 与裁剪 coverage 在原 mesh 合成中只乘一次，后继普通 draw 关闭裁剪状态。

每个 target 使用自己的 ROI；pose 相同不能授权跨 consumer 复用 mask。R8 lease/pin 由原 pool、预算和 submission 保留；缺 paint、预算或 encoder/ROI 失败只隐藏相关 target/下游，不用无裁剪画面回退。

源码：[Clipping](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/ScenePuppetClipping.swift)。

<a id="lighting"></a>
## 光照、材质与显示

`SceneLightSnapshot` 从当前 topology/world/typed 值准备 point、spot、directional，按当前预算接纳最多四灯；tube 不能伪装为 point。所有 receiver 消费同帧 light/camera，而不是各自解另一份场景。

- 只有实际启用 lighting/reflection 的材质参与对应 producer；plain image 不因场景有灯而自动受光。
- base material 光照在 layer effects 之前完成，graph 捕获该真实 source。albedo/emissive 与 normal/PBR data 分用途读取；normal、radius、锥角与世界距离使用 canonical 坐标，不随 card 非均匀 scale 错变。
- 2D image 与变形后 mesh 的 receiver mapping 不同；不能从 source atlas unit quad 推出 Puppet/模型的世界位置。未支持 receiver 局部保 unlit，并保原 alpha/geometry。
- 模型 directional/spot/point 阴影沿现 typed light、真实 geometry、target 与 submission；可见光束、受光和投影是三种消费者，不能互作证明。
- 现代点光 `lpoint` 的径向项由作者 `exponent` 决定。Format 保留有限非负的显式值，共享 light snapshot 将缺省解析为 2，StaticModel 和 LightingV1 图像消费同一世界距离衰减。平方保乘法，0 在半径内无衰减，半径外沿现有截止。各自现有 GPU 参数末尾追加一个四灯指数向量，保持颜色和强度分立以保浮点动态范围。退出两条现代点光的固定平方，保 legacy `point` 平面距离与阴影投影；与spot的共同闭半径及近距规则见[径向合同](#spot-radial-falloff)。固定官版字段与 stock shader 支持正指数和缺省值，零指数的官版半径外像素仍待核。
- reflection 只在已有 profile 中取得合适的 scene/environment 输入；模型镜面、所有光源/遮挡与图依赖组合仍不完整。
- HDR scene color/Bloom 与终端 SDR/EDR 映射分开；像素 PNG 不能证明显示器实际 EDR 高光。

源码：[LightSnapshot](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift)、[2D lit material](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLitImageLayer.metal)。采样/颜色合同见[Shader/Graph](render-graph-shader-coverage.md#color)。

<a id="image-material-map-components"></a>
### 图像分量图的显式通道

图像材质沿原LightingProfile与LitCapture供货，分量combo省略取TEX bit20…23默认，显式0禁用、任意非零Int开启；PBRMASKS仅显式0关闭整图。header不是作者显式通道的播放许可，PNG/data候选无header仍可按实际RGBA通道采样。沿原allowed/required两mask：省略只allowed，非零同时allowed|required；原typed payload打包处一次决定(header|required)&allowed，沿现Frame动态emission保有效位。保原emission无效关A、无reflection关B、原receiver/family与标量/混合/HDR/alpha/depth次序，不改变着色算法或默认灯。

退Profile的0/1整数限制、Pipeline对rawFlags缺席的拒绝、required必须存在header的诊断及header∩allowed错误覆盖。原TextureLoader/typed candidate继续保证真实用途、格式与UV/sampler；不加第二texture/map owner、ABI、Program、cache或帧内解析。validated原局部目标别名恢复仍只拒真正冲突的normal/map，重建payload必须保已经决定的有效分量，不能再被header抹掉；map缺失/损坏/禁用仅保标量，不造白图或无header默认通道。R8/RG及其它原格式不借此扩域。

验收扩原PBR/profile/TextureLoader/Metal及既有App载体，先保同输入旧失败；核PNG显式1/2/-1、TEX缺位/冲突header、总开关和分量0/省略、instance优先与完整改名。R/G对等值标量、B对既有反射数值门、A对无灯字面颜色，保独立UV/sampler/alpha及坏normal重建仍保合法map；不复制BRDF。实际App用同图/相机/灯与材质控制取得可区分map贡献和effects同源消费，再以原343活动135按header默认作独立回归；现五星球样本未证受影响显式非零/无header作者consumer，不宣作者缺图修复或官方像素。完成只扩原数值宏语义，不接用户provider、动态分量或新格式。 当前显式通道已沿原消费者接通，实际读回与App范围见[运行证据](runtime-evidence-current.md#image-material-map-components)。

<a id="spot-radial-falloff"></a>
### 聚光灯的表面径向衰减

已解析的作者spot exponent已进入实际模型与图像受光，Snapshot丢值、模型固定平方及图像隐式缺省2的路径已退出。沿原SpotDefinition→共享SpotSnapshot→两表面payload/Metal，不加新light owner、资源、Program或逐帧解析；指数与独立intensity、inner/outer cone及shadow投影分别供货。原Spot入口只把有限非负数保为有效指数，缺省/无效取2、显式0合法；包装只保作者fallback，不授尚无typed target的动态指数热更新。旧2D体积束在原Plan另把exponent用于经验cone形状，已有负数拒绝保持，不借本批重解释或扩粒子/体积消费者。

原sceneRadialFalloff改为消费已求出的worldDistance/radius，唯一owner先按distance≥radius截止，再求remaining=max(0,1−distance/radius)；半径内remaining^exponent，2保持原乘法快路；0在半径内为1，边界/外部为0。模型直接换spot径向因子，图像沿原sceneLitFalloff显式交指数，退出无人需要的默认参数；在除法前的世界距离截止避免fast division残留微正数被exponent0放大为满光；图像保原max-component缩放长度的抗溢出路径，只求一次稳定世界距离，模型复用求灯向量所需的现有距离，不新增重复length/距离计算。模型point/spot只跳真正distanceSquared==0，退有效近距被1e−8平方死区拒绝及radius的1e−4单位下限，直接消费入口已保证的正半径；两者共同保持归一距离语义，不加epsilon或第二距离计算。图像现代lpoint/spot沿原正半径无下限，旧legacy point平面算法本批不改；极端Float平方上溢/下溢不由普通尺度正例外推。各自cone、BRDF/legacy响应、三灯shadow/颜色/强度/alpha/depth与HDR次序保持。stock本地common_pbr_2与volumetricsfront把径向radius/exponent和cone/强度分开；未取得官方LightingV1 host参数接线时，此为明确自有世界距离算法，不宣官方曲线parity。

旧remaining参数API与两模型重复remaining/半径floor退出，不加兼容overload。原SpotSnapshot只加一个default2 Float，两surface原ABI末各加四灯指数向量16B；原图像preflight/packer直传，只带消费者需要的值。图像packer退出首次整包finite扫描，唯一产品caller补scene VP/reflection后由原Capture.init作一次最终完整检查，也覆盖逆矩阵运算溢出；不为direct pack的NaN测试保留双扫或另加指数门。无新缓存/索引/纹理/PSO/光列表排序或重复非负检查。验收用真实parser/snapshot核缺省/0/.54/坏值及颜色/变换更新保值，模型与图像实际Metal核多归一距离、默认2逐像素不变、.54/0与等值入射控制、cone过渡/锥外/半径边界、shadow/alpha/depth和改名；不复制BRDF。复用真实球MDL/TEX、无脚本单spot固定相机/灯/半径/I/cone，仅指数.54/2，旧.54→新.54/2的终端贡献及新2旧图相等，原343与独立作者保完整播放。未参与渲染的单位、更多动态值和经验体积束不由此扩大资格。当前读回与真实资产资格见[运行证据](model-runtime-evidence.md#spot-radial-falloff)。

<a id="point-light-volume"></a>
### 透视世界的无阴影点光体积

作者 `lpoint` 开启 `castvolumetrics` 时，显式体积密度与体积指数独立于表面光的径向指数。沿同一 light snapshot 消费已解析的世界位置、颜色、强度、半径及当前显隐。显式未开启、零密度或零强度无体积贡献，普通受光继续走原消费者。首批接入逐帧清屏、具有根域实体模型的透视场景和无投影阴影的点光。累积画布的体积色须在历史原色之外发布。

透明轨道可在普通合成中按作者策略写深度，弱覆盖在该域仍有意义。体积积分只由实际绘制的实体表面截止。共享深度只保最近写者，无法恢复透轨后方的实体深度。活跃体积光的帧收集已编码的根域透视模型部件，条件为写深度、普通不透明混合与层 alpha 为 1。该类颜色 draw 的覆盖来自几何，体积深度直接复用同一 mesh、投影和剔除做 depth-only draw，无材质采样。该目标由现有有界 offscreen pool 及同一 command buffer 持有。普通共享深度和投影阴影各自保持，终端显示映射的必需 scratch 先保容量。无活动光、无实体或可选目标失败均无此绘制。

根层完成后，主画布在 Bloom 和显示映射之前加上体积色。复用透视相机的解析视锥和这张同帧实体深度，得到每个像素从近裁面到首个实体深度面的视线段。视线与作者半径球相交后积分径向衰减，再用半径、密度、颜色与强度定标。深度清零像素使用解析远裁面，相机在球内取近裁面起点。求积在最接近光源的位置分开两个单调段，避免窄峰由单个样点过度放大。所有点光复用每像素的深度与视线并合在一次 draw，无额外颜色目标、背面深度、模糊或纹理缓存。

官方原包开关对照确立盘外体积色与直接受光的区别。stock 资料用于确定可读深度、有限半径和径向积分的合同；求积、资源及合成落点由本引擎实现。验收包含实体遮挡与透轨、半径边缘、相机内外、开关与非体积点光、动态显隐、作者原包与独立体积点光。投影阴影、组域、无可用世界深度、雾与体积混用及官方精确质量/色值分别取证。

<a id="limits"></a>
## 当前缺口与最近门

MDLA6 `modernBoundsAuxiliary` 的 framing/presence 被 Reader 保留，但未消费的 scalar/shape 仍由 Selection/Evaluator 拒绝；某个恒定数值不能证明它是深度或绘制顺序。bounds 前的 timed morph 曲线与 MDMP 几何尚无 prepared/evaluator 消费者，不能丢弃曲线后把静态 TRS 视为完整动画。更广 dense/reference composition、多 opaque alpha、Direct attachment/多 part 动画、fractional source clipping、未知 MDL profiles、全部光照/物理/阴影组合仍有边界。

最近行为入口：[bind 几何](../../../script/tests/test_scene_direct_model_bind_geometry.py)、[动画消费者](../../../script/tests/test_scene_direct_model_animation_live_consumers.py)、[裁剪 GPU](../../../script/tests/test_scene_puppet_clipping_render.py)、[普通 effect 受光](../../../script/tests/test_scene_ordinary_effect_lighting.py)。未闭项的下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="spot-light-frame"></a>
## 可见 SpotLight 的准备与帧消费

可见 volumetric `lspot` 光锥沿共享帧进入普通父层、composition/project 的局部 source 和最终合成。原 light plan、共享 world frame、MainPass 和 cone pipeline 各保原职责；model 的逆深度、一般体积散射及官方精确公式分别取证，不用已有错误实现定义新合同。

- **数据流与退出**：`authored light → 原 Plan 准备有限参数/几何比例 → 同一 typed snapshot 与共享 worldFrame → nearest MainPass 的 clip XY 映射 → 原 cone draw → group source → 父 Program/tail → unique main`。Pipeline 直接消费完整 worldFrame，保父/自身平移、旋转、缩放、镜像及剪切；角度已由共享 Timeline/Script/world resolver 合成，不再从 worldOrigin 与私有 currentAngle 重建。退役 Plan 的 parent/leaf/无依赖许可、baseAngles/currentAngle 和单一 relative-mirror Timeline 形状门；effect 尚无本绘制消费者，保持局部未支持。
- **准备与读口**：Plan 不再按样本数值上限拒绝可消费的 cone。只保 finite/color 域、非负强度/radius/density/exponents、合法内外锥角及实际可表示的派生几何；半角 trig 与不随帧改变的比例在原 Plan 一次准备，帧不重复计算。零强度/半径/密度沿真实消费者得到无贡献。当前 typed TRS/color/intensity/alpha 与外层 visibility 是实际读口；alpha 沿原 normalized reader 进入既有 color uniform 的 A，保持 PMA。Script 源覆盖只在原准备入口核真实 object/field 身份、已实例化 scalar/vector target 与上述消费集，退出单 intensity/count/源码写法许可；未知、nested 或未消费 radius/density 等 writer 不能静默冻结。共享 Timeline 编译器继续拥有各 host/模式的执行边界，不另建光锥时钟或重放。
- **局部投影与层级**：原 MainPass 从同一 rasterClipRows 提供保 Z/W 的投影矩阵，供既有 cone MVP ABI；无 map 直接复用原 VP。图像的平面矩阵不能用来抹掉新 worldFrame 的近远裁剪。该小方法表达原 owner 的 clip 投影概念，避免在灯光或未来几何消费者复制矩阵规则；不新增 map/cache/状态。SourceRoute 退役已接通实际消费者的整类拒绝，模型的独立合同见[局部合成](#model-subtree-raster)。RuntimeModel 的原颜色 producer 集合准备实际 volumetric cone 消费，不再依赖另有可见 static model，也不因祖先初始隐藏冻结该 cone 的 producer；实际帧仍沿原 visibility 控制 draw。Session 直接汇合已有 scalar/vector definitions 的 target，不重跑绑定解析或认证。
- **失败半径**：未实现 effect/writer、坏数值及实际矩阵乘积溢出只使该 cone 不供货，健康同组成员、父级与后继按原生命周期继续；GPU 边界只核最终可提交矩阵，不层层重验同一输入。资源、visibility、group clear/target、pin、publication 与 compositor 不新增 owner。native 世界中旧独立负角/忽略 Z、XY 角及 scale 的行为由共享 TRS 替换；不能声称这些旧 root 全像素保持。

验收先用真实 Plan/typed writer/Timeline/world resolver 与 production Metal，核 root/parent、绝对/循环/静态、scalar/vector/多 writer、未消费与错身份反例，真实 ABI、alpha/PMA、near/far 与有限乘积溢出。完整 App 比较同 TRS 普通 container 与局部 group，配字面父90°/scale2方向和边界，防两端共同丢父轴；再核非均匀×自身角的 shear、资源/ID/变量改名、父颜色变换、初始隐藏→开启及开启→隐藏无残影，闭合 cone target→父输入→Program→main/seal/GPU。无组和 viewport map=nil 用同身份基线复用；独立真实作者逐层核实际 cone/model 与终端，只把实际改变的字段/画面列为恢复。自有分组、独立作者及未覆盖范围由[运行证据](runtime-evidence-current.md#spot-light-frame)维护；新消费者需要另一 renderer/clock 或未解体积语义时，回到原职责设计，不扩到 model 或改 fallback。
