# 模型、Puppet 与光照

<!-- document-role: current-state -->

<a id="models"></a>
## 模型与几何

Direct MDL 与 Puppet 共用 typed 资源、canonical world/camera、材质、GeometryProduct、依赖发布及唯一 compositor；不能以图片 atlas quad 代替无法读取的真实 mesh。

Direct bind 几何沿原 MDL reader、准备资源和 StaticModel draw。不同 part/submesh/material/stream 只在实际 consumer 已接入时执行。 资产albedo及固定normal/map沿[完整源帧合同](render-graph-shader-coverage.md#material-affine-frames)消费原双轴；已验真实TEX旋转/镜像的颜色/alpha孔/投影与skew字面采样，范围归[模型证据](model-runtime-evidence.md#model-affine-frames)，不等同所有作者shader自动应用frame。

<a id="model-material-role"></a>
### 显式 JSON 消费者的准备角色

对象image引用的JSON模型、MDL实际引用的材料和对象effect均由原Catalog按消费者角色接纳，不以目录或后缀提示决定许可。原SourceFacts一次解析MDL并传additionalMaterialPaths及同份PreparedSource；另只把原objects.imagePath/effectFiles的两组路径数组传入Catalog，不耦合完整Document或再读网格。ResourceIndex.kind继续提供普通引用的快速提示；明确imageModel/material/effect角色分别调用原loadModel/loadMaterial/loadEffectDefinition，由各自内容解析器判定，不要求文件名为effect.json。

MDL附加材料、JSON model.material、粒子准备返回的材料及effect pass.material保持明确material角色；对象imagePath/effectFiles分别供明确imageModel/effect角色，普通effect dependencies仍是hint。原cold queue用同一规范身份/queueIndex和三位值类型角色集，统一三类JSON解析分发；待处理项原位汇合，已处理项只追加尚未执行的角色差额，避免重复loadEffect或旧角色重放。路径hint不在入队时并为角色，仅实际处理仍无明确角色的项时选择原hint parser并记入已选择集合；因此materials目录的effect和名为effect.json的material不会多跑无消费者schema。同一身份每个实际解析角色至多执行一次；同文件若有多种真实消费者，只做各自一次解析，不另建缓存。保package/loose/stock原来源、取消/revision、顺序、脚本与粒子交接。局部坏effect保原诊断及其消费者失败，不带走健康peer；身份失效沿原错误边界。未被任何消费者选中的合法/损坏.other JSON都不读，不扫描整库JSON，不加普通帧工作、第二parser/catalog、资源owner或持久状态。

验收先在当前源取得明确引用的真实catalog/materialPass空失败；扩原catalog门核目录/文件/别名变体、普通先入队及后提升、同材料一次读取、未知JSON零读、真实坏输入与健康peer。原MDL reader→SourceFacts→catalog→materialPass门保多part/PKG及复用PreparedSource。复用本批已冻结的真实月球失败变体：同输入由material准备到实际model/main/seal/GPU并出现球面，另与materials/等价载体及独立原包核结果；不新增fixture算法或按路径选视觉结果。当前结果见[运行证据](model-runtime-evidence.md#model-material-role)。

<a id="model-effect-role"></a>
明确effect角色扩原Catalog/readProbe门，核标准路径、改目录/后缀/大小写、hint先入队后提升、角色差额、未引用JSON零读取、损坏/缺失及原material/来源/取消反例。真实模型验收复用原named-late的一跳隐藏image provider11→caster2与现有own_dim着色；同包同时保两个相同effect别名，只改显式引用，旧标准模型G45、非标准无Program而取raw G90，影保持5。修后须复用两包使非标准整图等健康控制，并加模型/资源/变量及等值表达式变体，补独立原作者播放。graph provider的实际发布与模型binding/最终像素负责资格，不强求不存在的raw capture事件；现日志未暴露中间named copy完整token链，不虚构直接纹理同一。旧image-only路径报告不冒充模型恢复；只在本链生产像素及独审闭合后退队列。

<a id="image-model-role"></a>
imagePath语义所需的JSON模型由真实consumer选择loadModel，不再靠models目录及.json后缀授权；原独立kind.model解析分支退出，普通hint也在统一角色选择处记账。模型解析成功后仍沿原material引用闭包及model→material链接供TextureResolver，失败只退对应模型，且不跳过同资源其它真实角色。解析成功且kind不是.model的路径补进原modelNames候选数组，供原动态引用分析使用；同imageModel角色只执行一次，不新建名字索引/cache，也不扫描未知JSON。原MDL binary/PreparedSource与additionalModelPaths职责不变，不为补JSON元数据再次读取网格。

验收复用原named-late/provider11/caster2与标准own_dim；两包同时保models/provider.json和providers/provider.json同body别名，只改image一处。旧目录外effect仍准入，但无model→material link/texture，named binding失败、模型和影均露receiver81；标准G45/影5。修后两包整PNG相等，并核模型/资源/变量与等价表达式变体。原Catalog门补目录/后缀/大小写、pending/processed与hint冲突、多个实际schema各一次、局部坏/缺及未知JSON零读；实际SourceFacts接线、供货与最终像素由App资格，另保独立原作者及一次独审。只闭明确image模型，不授全部Script-only非标准模板发现或资源热换。

<a id="model-single-frame-texture"></a>
### 静态材质候选的单帧TEX

原 TextureLoader.loadCandidate 对一个物理 image、恰一合法 sprite frame 返回带实际 origin/双轴和 isSpriteSheet 的 typed candidate，保 physical/mapped、revision、purpose、sampling/format；多帧不偷偷取 frame0。无帧和单帧都沿[共享源帧准备](render-graph-shader-coverage.md#material-atlas-source-frames)，Reader 在字节入口校验，异域只投影一次，时长沿原 Double 合同。有限非退化双轴、实际源范围、非 volume 与各消费者几何合同仍各自成立。

该静态入口继续供模型 normal/map/gradient/pigment 等现有可选数据图；slot0 albedo 已迁入下节统一资产链。原单帧实际模型颜色/孔/投影与Loader反例范围见[证据](model-runtime-evidence.md#model-single-frame-texture)，不授可选贴图多帧。pigment 像素域见[局部寻址](#model-pigment-frame-addressing)，仿射按[完整源帧合同](render-graph-shader-coverage.md#material-affine-frames)；线性 atlas 边缘仍只授已验范围。

<a id="model-albedo-frames"></a>
### 模型 albedo 的统一资产供货

目标是使同一模型的静态、单帧与多帧 slot0 沿同一供货链正确着色、遮挡和投影。Entry携asset/named缺省身份及可选typed用户属性身份，不自持冷加载candidate；全部albedo共用原播放生命周期，named图输入保原依赖链。normal/map/gradient/pigment的静态职责暂不扩大。

`已准备 MDL 材料链接 → 原 descriptor 首个 pass0 → 冷 MaterialPlan → 原 Catalog demands → 原 FrameProvider(sceneTime) → 原 FrameTextureRegistry → 当帧 model draw → 颜色与 shadow`。计划只处理已标记的 direct model 材料，先固定首个 pass0（包括 rejected），不能用后项替换失败首项；material 数值投影一次。冷计划携原 pass 供现有可选贴图准备，Entry持缺省asset/named及可选typed用户身份，退出 slot0 的直接 resolve/loadCandidate、candidate 驻留与重复材料扫描。FrameProvider 是唯一推进者，颜色与阴影复用同一冻结 draw 的 texture/UV/sampler/content，普通帧不解析、不另推时钟或上传。

Host 在原 Catalog 前编译该计划并合并需求。原资源 worker 仍先发布 geometry，之后由现有一次 Script resource-planning handoff 同时交动态 image 需求、model 计划和最小 launch readiness；不能提前 join 等待 Catalog。两既有 Task 类整体归位，去测试专属免交接模式，不增 condition、barrier、worker 或 cache。冷 missing/unavailable 只丢受影响 part，保原 prepared IDs/隐藏组合语义；ready/preparedVideo 保留 Entry，实际帧资产尚未 ready 时只跳该 part，不能冒充 named 依赖失败或扩大 requiresCompleteNamedInputs。

视频声明不等于首帧 ready。模型实际资产需求并入原视频独立消费者集合，避免与隐藏 effect 共用时暂停；同 launch 的资产身份不变，冷准备只索引实际视频 albedo 的 layer/asset，逐帧不重扫静态模型 Entry；可见模型的 pending 沿原 InitialVideoPresentation 等首个真实 publication 和 GPU 提交，主 pass 同时保暂停重试，group 输入只阻启动资格，不造 decoder、就绪 owner 或视频扩展名名单。仍消费当前 candidate.content，保原颜色表示。

<a id="model-user-albedo"></a>
用户静态图片slot0设计：MaterialPlan在原首pass0只读取已解析`userTextureInputs[0].property`，准备`.straightAlbedo`身份并保原可选asset/named缺省；Entry保存同一可选身份。只有用户输入而无缺省时仍保Entry，用户absent则跳该part，不伪造white。原Service属性context按首pass0、模型绑定状态和去重材料路径投影可调键，直接消费原typed TextureInput的property键，与MaterialPlan保持同一已解析输入，不重建GPU/完整材料计划。原Host/Session将模型需求并入同一次用户文件加载，复用purpose-qualified publication与既有资源/值事务。Frame对该身份只有`.absent`才用缺省；`.ready`直接采用当前texture/UV/sampling/content，pending/unavailable/incomplete或未发布只跳该part，不把已选坏图冒充空值。用户输入存在时，缺省资产未准备不应提前删除Entry；空值仍由原缺省就绪状态决定是否绘制。named缺省保冷依赖binding，但本帧只有实际选择缺省的模型才激活对应provider；用户ready或缺供时不提前执行未选缺省，混合part及非模型共享消费者仍按原需求激活。原反射准备与视频pending呈现资格均按本帧所选输入判断，退出冷缺省分类对用户ready的误拒绝。颜色、camera depth与caster复用同一冻结draw，无第二provider、缓存、纹理时钟、逐帧descriptor扫描或文件读取。旧‘模型只消费asset/named’在此退出；坏热换保上次资源/值，reset回原缺省，继续归原Session修订/取消/退出合同。当前用户视频只提供PMA，不能反推A0隐藏RGB；本slice仅接已支持straight用途的静态图片，不扩大视频/其它slot或userShortcut语义。

验收须取得真实作者选文件的旧App像素红例与同Session红→绿→坏文件保旧→reset，配原Loader隐藏RGB A0/normal模型实际像素、属性/材料/资源改名、无引用peer及缺省坏但用户ready反例；独立未改作者保健康。准入/回调不替代model draw与同capture main/seal/GPU完成；不以自然旋转帧的全PNG相等或本slice宣称完整媒体/官方一致性。

验收复用真实 Catalog/MDL/Frame 门：静态与单帧原输出不变，两帧纹理按原 sceneTime 对照独立裁剪图，颜色、移动透明孔与对应阴影同帧一致；包含改名、缺供局部失败、首 pass rejected/重复材料、取消/早失败/空交接和健康 peer。原 App 保旧像素红例及新两时间裁剪图等值，另用未参与修复的星球作者原包检查实际播放/合成；模型视频只按实际运行覆盖声明，不以静态 TEX 测试授视频解码或官方一致性。达到同链供货与实际像素验收后，队列退出该缺口；其它贴图动画、跨 image 与一般 atlas 线性边缘仍分别资格。

<a id="model-named-albedo"></a>
模型材质的 named albedo 由原 dependency plan 准备。隐藏 raw source 须独立供货，隐藏 effect 可消费同一计划排在前面的 primary named 输出。模型的有效需求沿准备好的图边激活上游，依序发布当帧纹理，沿现有 pin 交给原 StaticModel draw。缺失、循环、未准备或要求作者位背景的输入按原图合同隔离。模型专用供货层因缺直接上游而旁路失败时，沿原 ticket 结束发布，不能把入口颜色供给模型。退休模型入口对合格 effect 上游的整类拒绝，普通帧沿现有颜色、采样域与纹理生命周期。实际颜色、改名、上游退出和独立作者模型见[验证](model-runtime-evidence.md#nested-model-albedo).

动态骨骼输出由原 mesh owner 提供按 layer/surface 隔离的有界 vertex slots；index/material 可共享，可写 pose stream 不按 path 共享。color 与 shadow 消费同一 frame binding；编码开始后不能偷偷更换 pose。未准备、lease/encode 失败跳过受影响 draw，不能读取未持有旧 buffer。

<a id="model-perspective-parallax"></a>
### 透视模型与附属图像的共同视差

透视 Direct MDL 的显示位置使用同一帧、同一层级视差解析。父层的有效深度及当前原点随现有传播规则供模型、封面和同组面片。官版只隔离实体并分别关视差、关实体，足以分辨 3708363772 的实体移动；本机旧封面与实体没有共用可见位移。

现有模型相机 VP 在投影前接同一 XY 偏移，供颜色、主深度、体积遮挡和定向阴影接收区的可见范围。灯空间 caster、表面世界坐标、脚本与骨骼读取仍使用原 world。视差关闭或解析为零时沿原投影；透视与局部目标复用原 clip 映射，正交模型保既有投影范围。无需第二个帧缓存、材质、资源、矩阵源或后置屏幕平移。

验收先核原包及隔离实体的左右两点、反复保持与关视差对照，确保位移实际发生且封面和同组实体不再分离。近门验证继承、断开传播、原有深度遮挡、改名与等价资源，另取独立作者。真实媒体封面身份与模型定位分别记录，普通静态封面可证明几何关系。 [实机结果](model-runtime-evidence.md#model-perspective-parallax-370)。

### 模型GPU顶点存储 <a id="model-gpu-vertex-storage"></a>

目标是在原模型上传和pose发布边界减少不承载通道的存储，保持颜色、相机深度与三灯阴影逐值相同。CPU Reader/skinning的64B Vertex及冻结帧不变；GPU采用唯一48B记录：三个Float4依次存position.xyz/uv.x、normal.xyz/uv.y、tangent.xyzw。只移动原Float32位，不量化、归一化或改几何。直接改CPU布局会同时触及Reader、skin与热点向量读取，当前收益不足以承担该范围；也不保两套GPU格式或按模型选择stride。

沿原`Reader/完整pose → makeMesh/VertexStream → 原MTLBuffer/预算和lease → color/camera-depth/shadow/receiver-face读取 → 唯一合成`。两处写入直接写原最终buffer，退出raw64复制；冷不可变上传可合并既有bounds遍历，pose仍先取得原bounds再按原锁/slot/transaction发布。所有MSL顶点和片元indexed-face消费者、DEBUG实际提交/bind位置读取同批迁移；不加packed数组、缓存、后台转换、PSO或分配owner，不改独立image puppet ABI。新增数据记录只表达共享物理布局，两处消费者需要它，不能以减少字节冒零CPU成本。

验收锁原12通道的Float位、signed zero、16/32位索引、精确bounds、实际色深/法线纹理与receiver-face，保三slot、冻结pose、取消/完成和健康peer。真实大模型须核buffer.length、allocatedSize及原预算，不把纹理pool算作顶点收益；另量冷打包与动态发布CPU，补原包和独立动画/材质样本。若实际分配未降、需要额外副本或发布CPU代价抵销收益则撤候选，不以理论字节或新构建认领优化。

源码：[静态模型资源](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/ScenePreparedStaticModelResources.swift)、[DirectModel playback](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Puppet/ScenePuppetPlaybackState+DirectModel.swift)。

<a id="model-additive-blend"></a>
### 模型的加法颜色

原材质准备已经解析的 `blending=additive` 直接决定模型颜色管线：片元保持原 PMA，RGB 以 `one/one` 加到已有画布，alpha 沿唯一 compositor 的 source-over 合同；普通/半透明及缺省材质保原策略。层、材质和纹理透明度只乘一次。模型资源准备仅在存在该材质时创建相应原 PSO；反射与加法可组合，复用同一 fragment/资源，不按资源名或模型形状分派。缺失的加法 PSO 只拒对应 draw，不能悄悄按覆盖混合绘制。

加法保原相机深度、cull、caster 和光照职责，半透明模型深度另遵下节，不另建排序/深度域。原 Frame 直接把已解析混合事实交给原 Pipeline，退已保存 additive 却固定 source-over 的断点，无热解析、附加 pass、资源或输出 owner。生产 GPU 门以非黑背景检验 full/half/zero alpha、改名、深度写开关与近遮挡，保 normal/translucent 邻例；真实星星模型另验同帧颜色/主画布/GPU，独立无加法作者保持原画面。该 RGB 合成是本引擎明确的通用算法，不授全部官方材质语义。

<a id="model-depth-state"></a>
### 模型的测试与写深度

原 `compileMaterialPlan` 将相机测试、有效写入和混合方式一次准备给 Entry，Frame 与 Pipeline 只消费这组事实。`translucent` 模型不写相机深度，即使保存的 `depthwrite=enabled`；其深度测试仍消费原声明，后方透明面不能穿过前方实体。这样同半径云层/大气可按作者顺序混合，不由互写深度形成斜纹。退役半透明材质按存储位写深度的旧投影，不改资源、壳层半径、投影、排序、ABI 或 PSO；normal/additive 保原策略，灯空间 caster 与 coverage 独立。测试开启用 greaterEqual，关闭用 always，透明零覆盖仍不写。原冷解析保 nil/空/未知为开启，仅 disabled/false/off/0 关闭；此缺省是项目策略，不外推官方未知值或其他混合方式。

测试关闭的模型是原透明 image 重排的顺序屏障，退出只凭 normal+写深度即可归入 opaque cohort 的旧判断。实际根域 opaque/alpha1/写深度模型仍由原 VolumeOccluder 收集；它携带相同测试值，原 camera-depth draw 依实际颜色绘制顺序使用比较或无条件写入，避免画面选了远表面、体积仍被旧近表面截止。保持既有实体覆盖资格、mesh/变换/cull、同池同提交，不新增资源、排序器或深度 owner。阴影的灯空间比较、castshadow 与透明资格独立，不跟随 camera test。新增 stencil 不可用时仅跳对应模型绘制；无需改旧比较深度路径。

验收复用生产资源→Frame→Metal 门，核近透明红/远实体蓝的两顺序×写入声明，另以实体前/透明后的一对测试开关保遮挡，先资格完整模型与独立健康peer，再比官方颜色类别；相机不一致的裁剪输入不得定语义。保原normal四态、alias/未知/改名、alpha0、后继状态、加法、排序屏障、volume与三灯shadow；按影响面复用已验证范围。真实地球核原包资源、云/大气相互分离与合成后的无斜纹，另核土星及独立作者。[实际范围](model-runtime-evidence.md#model-translucent-camera-depth)不授文字 disabled 排序、任意半透明体积或整样本官方一致。

<a id="model-directional-shadow-fit"></a>
### 定向阴影的可见接收区

目标是让远处天体仍可正确投影，同时不把当前可见球面和星环压缩到整张世界阴影图的少数像素。原单图以全部caster的灯域XY拟合，远caster/receiver的Z跨度又参与XY padding；真实3589454154只保球/环投影后粗暗带消失，单关近环陨石仍存在。该对照尚不授全部黑点来源，近环微几何的采样另行归因，不能以关闭其它物体投影修产品。

沿`当帧prepared draw/world → 原颜色pass的rasterClipProjection与逐层相机 → 原DirectionalShadowProjection → 原灯map/比较 → 原compositor`修正范围。接收区只收实际受光draw，在每个真实颜色域将模型包围盒与齐次clip体求交；双向裁剪box和frustum的12条边，直接归约端点，不存多面体或去重顶点。使用原Float world/clip系数提升Double做交点/逆矩阵；无法形成有限clip体的域保其原完整bounds，不扩成整灯/帧拒绝。group/named/canvas/perspective均消费各自实际pass投影，不能只用主相机筛接收者。只有当前确有受光prepared draw的层才求pass/clip，不为其它层预约pass；完整receiver bounds只在无clip或退化域的保守回退时计算。

每灯XY取可见接收区与caster灯域覆盖的保守交集；仅灯域XY相交的caster扩展深度。屏外caster仍沿原cast intent绘制，能投到可见接收者的物体不能因未上屏被删。XY padding只由XY尺度/分辨率决定，深度padding独立；退全世界caster拟合及Z驱动的XY放大。保持每灯单图与四灯预算，实际尺寸归[输出密度](#model-directional-shadow-density)。二值材质/层/纹理覆盖、当前pose/UV/cull和三灯生命周期继续原合同，拟合不新增map、纹理、ABI、历史、缓存或资源owner。稳定化和滤波只在修正范围后仍有可归属残余时另立输入，不凭单图扩大PCF成本。

验收先用生产数学的相机内/外、擦边长盒、相机在盒内、相反视角及混合投影正反例，核远处无关caster不再稀释近处投影，屏外但灯域相交caster仍在深度域；含改名、同一world几何的等价TRS表达和退化clip域保守回退；共同平移后的采样相位遵下节固定网格合同。沿真实Frame/Metal补屏外合法影、group/named及阴影覆盖邻例，用冻结真实球/环/陨石/远卫星输入核旧/新可见投影、成熟原景连续帧和独立作者。若范围修正不能带来明确像素收益，退候选并重排；不能把map尺寸、caster计数或构建通过当修复。实际范围归[模型运行证据](model-runtime-evidence.md#model-directional-shadow-fit)。

<a id="model-directional-shadow-grid"></a>
### 定向阴影的固定世界采样网格

受控真实479 caster/462 BC3 receiver/456 cameraDepth探针已资格：只微移远lit noncaster时，近面alpha/PID/颜色几何固定，重拟合仍改变近影；完整覆盖且滤波余量充分的held-fit及shadowoff均逐bit稳定。这只证独立fit依赖，不授自然闪烁首因或作者完整BRDF，实际记录归模型证据。当前候选在原`SceneDirectionalShadowProjection.make`找到相关bounds后替换XY，不改凸裁剪、合法屏外caster、Z、depthBias、map/分配和原N3比较；无历史、持久状态、层名单或第二fitter。

每轴原跨度S、中心C及原XY padding p复用；R 沿当前阴影档的基础贴图尺寸（低档 512，其余启用档 1024）。最小跨度M=max(S+2p,S/(1−6/R))，再E=2^(ceil(16·log2(M))/16)，世界格距q=E/R，C按q就近取整。正负取整规则固定；输出直接由E及格中心构造一次矩阵，不先建旧矩阵再反解。E≥S/(1−6/R)保证取整前至少3格余量，中心最大移动.5格后保≥2.5格N3保守footprint；原退化轴正padding仍保。只拟合实际档位所用的基础网格。物理密图是 coarse 格的整数倍，中心移动整 coarse 格不改变理想采样相位。

尺度向上分档自身最多扩 4.427%。采样余量主导时，R=1024 与 R=512 的离散跨度相对紧边界 S 的上界分别约为 5.04% 与 5.67%。原有正 padding 主导时，按 S+2p 再向上分档。跨档可pop，光向旋转/相机裁剪成员变化及实际几何/无shadow颜色欠采样仍可能闪；不以本算法授全部稳定。明确选择固定world原点：任意共同平移可改变采样相位，旧连续fit的逐UV平移不变要求退出，几何/深度/完整覆盖不退出。同一world几何的等价parent表达及改名保持；任意平移核≤一coarse格的相位差与覆盖，整格平移核原等价，不选第一caster/物体名作锚。普通帧只新增两轴log2/ceil/exp2与round，不重做bounds/clip、不添GPU工作或资源；实际成本仍须观测。

先在原CPU fit门核clip/屏外/退化域及真实变换，补正负/镜像/非uniform、跨度档边界、网格格边界和2.5格余量，按新采样合同修订上述旧UV断言而不放宽几何判定。GPU对比必须直接复用旧探针已执行的四个receiverWorld Float32矩阵，不按新texel重新生成位移；原点位、caster/相机/BC3、held/off及完整主影均保持。候选未带来可归属像素稳定或损坏主影时撤回，不继续加迟滞/缓存；通过后再核成熟原景、独立作者与同输入成本。

<a id="model-directional-shadow-density"></a>
### 定向阴影的输出密度与共同预约

受光 prepared draw 的实际颜色 pass 物理范围决定定向图的原自适应档 1024／2048／4096，结果由当前阴影档封顶。低档使用 512，点光六面和聚光单面也用 512；其它启用档的局部单面为 1024。每灯只按本档基础尺寸拟合一次 guard-band，密图和回退图复用同一世界域。每帧至多四个短期 plan 只带 slot、lightID、projection 和实际 resolution。采样消费实际图宽高。 [设置生效合同](../architecture/runtime-architecture.md#effective-quality-policy)

确有高图plan才升级整组已资格灯：唯一pool事务一次stage所有各自desired尺寸，全部成功后才发布pins和编码。失败退该档基础尺寸的逐灯局部成功链，保原灯序与无效projection空slot；不能让前灯高图挤掉本可保留的后灯。Frame只传实际fallback slot/extent，pool仅在真实allocation失败的reclaim阶段保护这些暖图；成功stage仍可沿原预算退出闲置低图，不预占双份pin或另造回滚。原私有事务接收混合kind/extent并按CacheKey返回，旧公开adapter沿同一core，单kind-only core退出；Collection惰性映射避免转换请求数组，预算、物理identity、revision、stage、submission pin、reset/cancel继续唯一原owner。缓存受原预算及有界尺寸控制，没有新cache/历史/资源owner、shader、PSO或ABI。

更密图会增加depth带宽、驻留和在途图成本，不能把放大map当成零代价修复。按[实际运行证据](model-runtime-evidence.md#model-directional-shadow-density)保冻结同世界域/资源的质量对照、原作者成熟播放与独立作者；生产门核尺寸边界、高度主导、四灯紧预算/原partial、混合灯与无效spot空slot、无受光接收者，以及高图失败后暖低图零分配复用/原内容和在途生命周期。高图收益不足时收敛尺寸或转覆盖积分；不能用圆形大模糊掩盖真实各向异性，也不据未知cascade参数删远caster。快速闪烁的频率、一般大场景稳定化及所有硬件成本仍须独立资格。

<a id="model-shadow-primitive-coverage"></a>
### 定向阴影深度重建的三角覆盖

目标是消除微小投影面在栅格吸附后向原三角外延伸的虚假遮挡。原caster在actual texel中心重建无限平面，只核整图0…1；自有178个三角的实际GPU诊断取得44个严格ray miss却写深度的反例。现三角覆盖约束只允许原面内部写影；它不等于真实479全部黑点已归因，不能用放大bias、关闭cast或扩大map代替覆盖修正。

沿原`indexed mesh → directional shadow vertex/fragment → 同map/PCF → 原模型颜色/唯一合成`修正。支持shader barycentric coordinates的设备在原Pipeline初始化时选择具有barycentric输入的定向fragment，仍只创建一份定向PSO；不支持的设备保原fragment，不拒模型或整灯。两入口共用原平面/材质覆盖实现，无新buffer、顶点展开、持久状态、map或普通帧能力分支。用现有lightPosition的二维导数与texel中心位移校正当前重心坐标，只有原三角覆盖内才写重建深度；导数/Jacobian复用原plane计算，全部导数在材质coverage之前求出。重心边界只留与实际加减项幅度成比例的Float舍入余量，不能加像素尺度的任意扩边。albedo隐式采样先于新的非一致discard，保持原coverage LOD；点/聚光灯不扩域。旧无三角覆盖的重建仅在硬件缺能力时保留，其限制明确留在运行证据，不新增另一套资源或渲染owner。

验收用独立ray/有向边oracle核严格外部采样保持clear、内部深度正确、共边不裂；保原斜面自影、正负接触间隙、cull/二值材质覆盖、三灯和indexed共享顶点邻例。先以隔离原型核同输入红绿，再做真实冻结土星/星环/微几何及成熟原景连续帧，另用独立作者保可见遮挡。硬件未实际执行的fallback不冒称新GPU资格。若真实画面没有可归属收益或引入裂缝/明显额外成本，撤候选并保该断点，转到输出密度/覆盖积分方案；构建和几何门通过不能代替黑点减少与主阴影保留。

<a id="model-shadow-receiver-plane"></a>
### 模型阴影的实际接收平面

接收面由当前绘制三角形决定。真实细面已出现屏幕导数偏离该面、把本应受光的PCF taps判暗；不能靠统一加大bias抹掉接触遮挡。沿原`prepared mesh → Pipeline绑定 → model fragment → 原三灯比较`，片元以primitive ID从当前同一顶点/索引缓冲读取三角形，在模型局部先做两条边之差，再以同world矩阵的线性部分变换。原定向及point/spot接收面数学消费这两条边，退出用屏幕相邻差充当几何平面的职责；BRDF仍用原插值/normal-map法线，纹理、世界位置、相机、cast与数值余量不改；定向有限滤波另归下节，point/spot保4tap。

复用现有缓冲及提交寿命，无网格展开、缓存、附加资源或新owner；Pipeline只增加片元绑定及由现indexType提供的索引宽度。16/32bit沿原上传者的已证范围读取，不在像素中重验索引。没有实际受光阴影时不取三角形；新增读取及边变换的成本须随真实画面核对。验收保小三角原GPU红例、真实face/ray oracle、宽窄索引及改名/等价变体，有间隙遮挡与无阴影/未受光反例、三灯邻例和独立作者。若不能消除真实暗点或破坏原遮挡，撤候选并保断点，不追加第二套接收面或bias分支。

<a id="model-directional-shadow-filter"></a>
### 定向微阴影的有限覆盖滤波

四组真实环面采样已核实caster覆盖及深度正确；二值map的单个微影texel却可占双线性权重约.95。沿原shadow tap/receiver-plane比较采用三texel方盒与双线性重建的有限卷积：每轴保N+1点，端点权重(1−f)/N、f/N，内部1/N，二维相乘；定向N=3共16比较，point/spot保N=1的原4比较。同一tap helper直接承接参数化权重，定向旧2×2重建退出；每tap仍在真实接收面上算reference与原bias，不改合法caster、map/fit/density、材质、光照强度或最终输出。同16个深度按四个2×2块逐组gather读取，不保跨组深度数组；逐lane仍保独立reference/bias与原比较语义；不能用共用reference的硬件linear PCF取代面校正。无随机抖动、历史、缓存、额外纹理/PSO/ABI或预铺性能档位。

这是明确的自有抗欠采样方案，不授官方滤波公式或全闪烁因果。代价是每个活动定向receiver多12次比较及更宽的影边；先用同输入原型核孤立微影跨亚texel相位的权重连续、全明/全暗、倾斜接收面/接触间隙和原point/spot不变，再核同姿态原图、成熟原景连续帧、主影及独立作者，补相同App身份/输入的成本观测。真实环粒/闪动无可见收益、主影过糊或成本不可接受时撤候选并重排，不保留并列旧算法/样本分支，也不改caster平面来拟合已正确的深度。

<a id="model-shadow-demand"></a>
### 实际直接光贡献之后的阴影读取

原fragment先求所有灯影，再求实际材质/灯贡献，会为确定零贡献片元做多次比较。候选沿原fragment将visibility消费移入原灯循环，退三个预计算数组及前置遍历，不改shader ABI、灯/图身份、滤波公式、caster/资源/owner或原材质响应。用法线贴图后的实际normal；无surface或无gradient的signedNoL≤0时diffuse/specular/rim都为零，可在查影前退出。背光gradient仍可能有光必须保留；point保原重合/radial0，spot保原cone0，零指数半径外仍按原非零径向贡献。四张图只沿原kind/index查找，不新增映射缓存；indexed边读取不依赖quad导数，可在coverage discard后执行，纹理隐式采样仍在前。

验收沿原真实Metal三灯/多灯、gradient背光/NoL0、normal扰动、零指数、ambient/emission/健康peer与改名变体，再核同frozen33原图/1×App成本和独立作者。当前实际小幅成本及原图保持归[模型证据](model-runtime-evidence.md#model-shadow-demand)，不授稳定提速或环闪关闭；不继续为此分支增加状态。

<a id="model-raster-coverage"></a>
### 世界模型的亚像素颜色覆盖

真实479碎石在关闭全部阴影后仍可随相机亚像素移动，突然以alpha1覆盖亮环面；这与微影滤波是两个职责。保原网格、BC3、受光、cast与深度，不以删碎石、放大bias或更亮的ambient掩盖。采样与resolve统一遵[光栅域合同](../architecture/runtime-architecture.md#raster-sample-domain)；受控1×/2×/4×已取得覆盖证据，默认2×实际候选因播放/驻留成本撤回，产品保原1×。结果与重启条件归[模型证据](model-runtime-evidence.md#model-raster-coverage)。

<a id="model-shadow-coverage"></a>
### 模型阴影的实际覆盖

定向投影消费已准备的材质与作者cast intent。已准入 stock `generic4` 的 `translucent` 部件继续绘色、接收阴影，退出定向caster边界与深度绘制。官版已用479全不透明纹理、462带孔纹理分别核实此混合区别。normal、其他材质、点灯和聚光灯沿原资格；相机深度各自消费原声明。Frame保一组部件和定向资格，空caster不申请影图。

合格部件沿原 `drawShadow` 的二值覆盖计算。先取 clamp(material.opacity×layerAlpha,0,1)，原 textureAlphaIsOpacity 才乘实际 albedo A。最终 coverage>.5 写光域深度，≤.5 保留空孔；tint-mask A 由原颜色消费者使用。三灯共用原 shader、cull 及同帧 mesh/world/UV/sampler。

验收沿真实 Frame 收集、光域深度及接收像素。用 stock generic4 同纹理 normal/translucent、改名、cast 开关及点聚邻例区分投影与颜色；保覆盖阈值、材质/层 alpha、cull、相机深度与健康 normal 宽影。以冻结原环和独立作者实际绘制验收。范围见[模型运行证据](model-runtime-evidence.md#model-shadow-coverage)。

有序命名来源准备以已就绪部件为当前阴影输入。纯模型raw provider确定无当前源，或模型部件在其准备位置尚拿不到当前publication，只退出缺失部件的本帧投影及接收范围；前后健康层和同层ready部件继续沿原顺序取得必需附件，再用原灯图。部分draw只供本次发图，颜色准备缓存仍只收完整层，使普通绘制在publication晚到后重新取资源；发图截点后的供货随下一帧进入影图。某pass尚无深度决定时，已接纳的当前graph输出在原位置保留颜色深度；raw来源须在可选影图前确有本帧完整发布才预约。尚无发布或已经退役的raw来源不耗该域深度。保原身份失败、混合provider、已有源的容量或编码失败和必需附件优先级，不加跨帧缓存、回放或第二资源owner。验收同时量缺失时的健康投影、普通颜色晚取、完整回供、同层健康部件及原配额和取消反例，以实际接收像素为准。

<a id="model-zero-coverage-work"></a>
### 确定零覆盖的模型工作

目标是让确定不可见的模型不稀释健康接收者阴影，也跳过该draw的albedo绑定、姿态网格/法线准备和无消费者色深预约。原`SceneDynamicLayerValues.alpha`是层alpha归一权威，输出已在[0,1]；`staticModelDraws`在已有parts入口每层读取一次，严格零返回原空draw集合，再由原Frame消费者自然跳过。正值沿原world/pose、资源、材质和cast链；退逐part重复读取，不另添shadow过滤器、有效性许可、状态、缓存或隐显owner。

每cadence直接消费当前snapshot，0→1→0恢复时重新沿原资源与姿态入口，不缓存零态；Script、Timeline、动画和provider的生命周期不由draw裁剪接管。只据层alpha证明全层无覆盖。逐part在原材质动态投影后按实际混合语义消费opacity：非normal且严格零的part在mesh/pose和albedo前退出，不进颜色、接收范围与cast；normal颜色独立于材质alpha，仍保draw、相机深度与receivesLighting，原caster处的opacity正值条件只退出它的无贡献投影。原viewTintBack投影随材质一起前移，不另加解析、临时材质数组或第二遍遍历；整层原normalMatrix仍可能已求一次，不为退这一步增状态。零part的缺named输入不触发无用失败，上游provider生命周期与graph demand保持。不扫描纹理A或推导其上界，不扩大正值门槛；原逐texel二值覆盖继续上节合同。

先用真实Frame的absent/层alpha0/1及同renderer往返、改名、只剩零受光接收者的正反例，核零态与absent的生产fit/近像素一致、无消费者不预约map，恢复态仍有合法影。非normal材质零接收者先以同真实星环几何的absent/opacity0/1取得旧红，层alpha固定1，核typed材质值、生产fit与近像素；carrier不健康即停，不凭源码推断修改成功。保normal材质opacity0但层alpha1的实际颜色与camera depth，并以镜头外正caster的shadow on/off证实它仍接受真实投影；原217行及合法正值影不变。另补原模型/透明覆盖/命名输入邻例和独立作者；新像素与成本必须由实际运行资格，不能只据空候选数量授修复或自然环闪关闭。

<a id="model-material-opacity"></a>
### 模型材质 opacity 的单一归一入口

目标是避免一个可归一的作者alpha使自身消失或撤掉整灯阴影。原material投影会把hostBuiltin genericimage2的有限Double alpha1e300变Float inf，实际旧App中独立健康caster随之失影；真实供货与像素范围归[运行证据](model-runtime-evidence.md#model-material-opacity)。原authored binding则在同消费者之前以Float范围拒绝有限alpha，造成两入口不一致。opacity是覆盖比例，其冷值在乘layerAlpha之前取[0,1]；例如冷2×layer.5应为.5，原shadow末端只clamp乘积得到1不是该域合同。HDR颜色、亮度与opacity不共用范围。

沿`原Catalog/ShaderValue → 原StaticModelBindingCompiler → 原MaterialPlan/Resources.material → immutable Entry/dynamic material → 同Frame color/shadow → unique output`。Compiler保数量、完整numeric原文证明和Double有限性，仅对已证alpha角色退Float范围许可；原始Double仍交Resources，不在两层重复clamp，其它颜色/亮度的现Float域不扩大。Resources在原legacy/builtin入口仅对尚未资格的raw opacity作非有限回既有缺省1；authored分支直接消费Compiler已证的有限Double，不重验。两者在构造opacity那一处唯一clamp0…1后再Float，不拒整material或创造备用材质。authored非有限输入若先被原完整numeric证明拒绝继续局部拒，不宣所有材质族的坏输入处理相同。

产品只有这一raw Material构造及原两个Self重建者；dynamic scalar先保Double/Float有限再clamp，viewTintBack只复制opacity，Entry/Plan/Draw不改此let值，纹理/几何/动画不重新供alpha。因此退Pipeline颜色和drawShadow的两处opacity.isFinite同步重验；保原layerAlpha/矩阵/资源及实际GPU失败边界，不吞drawShadow false、不另建shadow状态。shadow仍读同opacity×layerAlpha及原TEX A/二值阈值；normal颜色的opaque策略、材质/层alpha分立、test/write与cast intent不变。无新helper、owner、cache、状态、ABI、shader或普通帧解析。Script/property仍有各自raw seed/Float边界，巨大动态值继续回冷值；本批不冒称巨值属性回流、全静动态数值等价或一般HDR/half域已解。

验收复用有效before CPU/App及最近资源→Frame→Metal门：同冻结输入旧源红、新源绿，hostBuiltin与authored有限巨alpha对1、数字/字符串/数组及合法别名/资源改名、冷2与layer.5的先后、0/负值/.5阈值、builtin非有限fallback及authored拒绝/健康peer；相邻RGB/brightness巨大输入保原局部拒绝。实际MDL/材质准备到三灯map深度与receiver像素，不用手造Entry代冷入口；原合规opacity输出保持。完整App以独立健康caster的影辨别整map发布，alpha1控制、巨alpha castfalse归因、巨alpha及改名严格图对照；另保独立星球原包播放。只在真实投影/颜色及独立审查闭合后退该队列部分，其它数值与raw UV失败边界继续记录，不加新名单或合成路径。

<a id="model-hdr-color-intermediates"></a>
### 模型颜色的 Float 中间态与唯一存储投影

目标是让有限、最终可存储的HDR颜色经过低纹理值、view tint、雾和透明度后正确进入主画布。原未资格surface profile的legacy分支先将Float材质色转Half，再在后段把surfaceColor/lighting转Half；实际旧GPU与App中，合法131072×低U8纹理×1/1024在PMA前溢出，末端65504 clamp不能恢复应有半亮色。PMA采样的Half除法与1e-5阈值也会丢小正A；实际范围归[运行证据](model-runtime-evidence.md#model-hdr-color-intermediates)，不宣所有作者HDR错误。

沿`prepared material/当前纹理与typed frame → 原StaticModel Metal采样 → Float颜色/光照/反射/雾/coverage/PMA → 原Half存储与唯一compositor`。颜色texture用float采样，albedo立即为float4；仅在原PMA标志内对A>0除、非正清RGB，退无必要1e-5而不全局抹straight A0的合法opaque/tint-mask RGB。统一原mask/普通Float surface合成，保Chroma无mask忽略全局color与各自BRDF/radiance资格；legacy Half分支、后段Half往返及其旧舍入职责退出。coverage在Float算、保持原≤0 discard，fog后一次PMA与既有[0,65504]颜色存储投影、最终half4量化；不提前按maxFloat/1截HDR输入。shadow的albedo A也用float采样再沿原>.5阈值，与颜色消费同一源A；阈值、cast intent、世界/normal/cull/test/write不改。

本批不加精度开关、shader分支族、PSO、ABI、纹理副本、采样次数、状态/cache/owner或每像素有限性防线。原RGBA16存储动态范围和极小Alpha量化、一般Float32乘积/除法/灯和溢出不由此解决；不按样本/路径/数值特例选算法。普通精度变化由最近行为门及独立Float/Half存储oracle核对，不能为了保存旧Half中间舍入保无用路径，也不为过门随意扩大容差。surfaceEnabled只拥有原PBR radiance资格，不给legacy增加无消费者的求和。

验收扩既有emission的真实RGBA16Float/Float16读回：finite高色×低tex与安全色×white同opacity的存储等值、mask、PMA小正A/零A与straight A0反例、viewTint后再fog使最终有限的晚cast反例，含资源/producer改名及合法等值载体；近期普通emission/ambient/alpha/depth/反射与Chroma按影响复用或补测。另在原Frame三灯门用线性RGBA8或Float输入的有效A略高于.5、=.5、略低于.5，按实际format/UV推导并区分真实采样精度和既有cutoff，不用emission固定忽略textureAlpha的结果代证。完整App沿真实TEX/材料用相同几何/背景/opacity，低纹理+高color对安全control与改名核整图；原星球只授独立回归。达到生产像素正反、实际旧新贡献和独审后退相应队列部分；不宣官方parity或全部HDR输入健康。

<a id="model-hdr-disabled-brightness"></a>
HDR关闭时，原usesHDRBrightness使实际亮度统一取1；原始brightness即使超出Float范围，也不参与颜色、反射或Chroma末端增益，不得因其finite检查拒整draw。该flag由原general.hdr冷供、Material与动态Self重建保留，无热setter或新状态。仅令原Pipeline亮度finite许可跟随这个实际消费条件，保HDR开启的非有限拒绝和原非负投影；不截HDR为1、不改变其余字段或shader。hostBuiltin的有限Double大值可由真实Catalog到达这条边界；authored Float接口仍由原Compiler先拒超域，不藉此放宽类型、property/script seed或动态范围。

实际App先用general.hdr=false、genericimage2的同MDL/纹理/材质对照，只将brightness1改为1e300；旧主体缺色而原投影/孔洞/peer保持。验收在同输入恢复后，以整PNG等控制及真实资源/数值载体改名为准，另核HDR开启的正常亮度确有消费、活跃非有限值继续局部拒和健康邻物。扩原最近行为门、保独立星球播放与一次独审，不新增fallback、normal/shadow许可或资源owner。

<a id="model-hdr-emissive-gain"></a>
### 默认完整的 HDR 发光

默认播放以完整作者发光能力为目标，包含官方后处理超高档所需的效果，不等将来增加档位界面才接入。作者General HDR、Bloom各自的开关、strength与材质分量声明仍决定对应贡献；默认能力不能强开作者关闭的项、改写强度或按样本补光。普通“启用”档的官版观察不能否定超高目标；当前有界运行及显式材质HDR组合的未覆盖边界见[模型证据](model-runtime-evidence.md#model-hdr-emissive-gain)和[开放队列](../roadmap/scene-open-breakpoint-queue.md#implementation-gaps)。未来质量选择的职责归[准备期策略](../architecture/runtime-architecture.md#effective-quality-policy)。

已资格stock generic4/chroma4共用原Float颜色链：直接光、ambient、原A追加发光与reflection完成，各族brightness仍只乘一次；随后在fog、coverage/PMA和Half存储之前，对当前RGB施加彩色增益`1 + emissiveColor × max(0, A × (E−1))`。只有有效HDR、真实A分量及作者LIGHTING或REFLECTION非零时启用；A0、E≤1、HDR关闭、两功能均关闭或legacy材质保原输出。该项可增强黑albedo已有的反射，不把A只当albedo自发光。 仅正的额外强度进入新增贡献，先用当前RGB乘emissiveColor，再乘额外强度并回加RGB，避免先构造巨大独立增益因子，使最终可存颜色因中间Float溢出被截亮；E≤1或A0直接保原RGB，不为零贡献做可能溢出的乘加。该分支表达发光消费，不增加数值许可、截断或逐片元finite校验。前置A的max与现有add、ambient归属差异仍是独立问题，不在此迁移整个发光算法。

原Resources.surfaceProfile已解析的authoredReflection随SurfaceProfile保留为reflectionEnabled，与最终reflectivity分立；标量0、B0、首帧无history不抹作者REFLECTION语义。原Pipeline把`profile存在 && usesHDRBrightness && (receivesLighting || reflectionEnabled)`投影为materialFlags.x的bit2（值4），Metal结合原components的A位执行上述增益，复用现有componentMaps一次采样和E/color。该bit不是质量档位、反射纹理存在或PSO状态；不从brightness1、实际灯数或反射强度猜条件。实际normal/reflection需求仍按原真实消费者决定，不因保留该Bool增加求逆、history或贴图准备。退出冷准备丢失REFLECTION语义及片元缺少后反射HDR增益的职责；无新owner、cache、pass、PSO、ABI扩容、采样或普通帧解析。

原ReflectionFrame仍取前一完成的完整raw主画布，包含模型自身及后续全屏效果/UI；raw复制在最终Bloom/display mapping之前，显示晕光不回流history。新增增益会提高已有自反馈环的增益，可能改变收敛和亮斑持续；当前反射子项已有saturate上限，不能据增益推断无限发散，也不能用峰后亮图认定反馈因果。只有实际固定输入出现持续增亮、闪烁或拖影，才沿原history owner分离捕获/采样原因；未见异常不加逐模型history副本、抑制状态、任意衰减或低于作者能量的截断。首帧/容量不足保原局部缺反射，不关闭其余材质颜色或改变作者增益条件。

验收先扩原material-map/reflection门：黑albedo的A1/E4/B1与A0/E1/B4实际反射颜色等值，覆盖generic4、Chroma与彩色emissiveColor；核HDRoff、A禁用/0、E≤1、legacy、LIGHTING0/REFLECTION0，以及REFLECTION非零但强度0/无history和LIGHTING非零但无灯的条件边界，保原alpha/depth/caster及资源/变量改名。再在确认超高已应用的官方窗口与本地默认能力下，按实际viewport、作者控制及当前201/入场相位核真实水滴边缘/尖端与稳定播放，另保独立作者。draw、配置或一次强亮图不代替完整效果，普通启用档、不同相位和导出色域也不授超高精确RGB一致；只有相应生产像素与独审闭合才退出队列。

<a id="model-normal-consumers"></a>
### 模型法线的实际消费者

目标是让有限世界变换中仍有面积的无光照平面正常显示、遮挡与投影；旧Frame在part之前求逆，任一零轴使整层退出，即使材质输出不用法线。材质的真实法线需求只有receivesLighting、存在viewTint或潜在reflectivity>0；以原Material的纯计算属性供Frame和独立Pipeline共用，不保存状态，不从几何、路径、rank或样本猜许可。原可选normal纹理的stock/Chroma非常色准备资格保持，不能因几何需求复用而扩大加载范围。

数据流仍为`prepared Material/mesh → 同一typed world → part draw → 原颜色/depth/shadow/volume → unique compositor`。Frame在世界入口核完整4×4有限性一次；有实际需求才至多求一次layer线性3×3逆转置，并在每part、albedo及named完整性需求之前局部决定供货。无需求用既有identity normal载体，跳过求逆；需要法线且线性不可逆的part局部退出，不能带走健康unlit part。独立Pipeline沿同一需求选择prepared normal或原数学计算，无需求忽略未消费的prepared normal。退整层求逆许可及数学函数内重复world有限性，原数学函数保签名并直接提取前三轴作Double非零det、归一逆转置和输出有限性；不为无内置构造的类型转换另加helper或重复坐标提取。prepared normal唯一来自已验证不可变draw，Pipeline不再重验该同步产物；独立nil分支仍由原数学函数判输出。两真实world入口各守各自提交域，不加wrapper、缓存、flag、PSO或ABI。

有限性不能随求逆退出：父矩阵乘积可能溢出，坏world须在caster bounds与三灯map之前局部退出，避免污染健康投影。零面积/线/全零几何由原光栅器给出无覆盖，不新造rank判定或cofactor替代法线。原受光、tint、反射的非均匀/镜像/小非零缩放与光照公式保持；geometry、cull、albedo/alpha、深度test/write、cast intent、camera-depth及volume仍消费同份world/draw，不另建许可链。

验收沿原Frame/Metal门，先保旧源码/旧App红例，再核XY scaleZ0与YZ scaleX0对各自有面积控制的颜色/实际深度/三灯投影等值，父旋转/镜像和改名；混part中unlit继续而lit/view/reflection局部拒，named未消费不牵连完整性，非finite world整层局部退、全零不覆盖健康peer。保原小非零/非均匀/负det的normal数值与有光照像素。完整App只用可区分遮挡/投影控制闭合main/seal/GPU，独立真实星球保原运行；未证作者rank2命中或官方对应语义时，以上述自有消费者算法验收，不以绑定计数代像素或宣性能收益。最小结果达此合同后退出该断点，剩余真正normal需求不借本批放宽。

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

两种stock profile的HDR brightness均属于受光完成后的颜色增益，不是材质反射率：Pipeline先保raw颜色，BRDF/F0、直接光、项目原A追加发光、ambient与reflection合并后统一乘brightness一次，再进入[后反射HDR/A增益](#model-hdr-emissive-gain)、fog/PMA。generic4旧的前乘会改变有色金属F0，并漏增亮黑色金属的非零Fresnel高光；退这条前乘和reflection单独乘亮度，复用原surfaceMaterial.z判定，不增flag、ABI、owner、pass或采样。无profile的legacy保原前乘；HDR关闭取1，alpha、mask、depth/cull及反射缺失的局部语义保持。前置A的max与项目add差异仍独立；pigment/noise沿[独立颜料合同](#model-chroma-pigment)消费，不宣完整Chroma或官方像素。

此亮度修正先以实际prepared资源→Frame→Metal验证：两族白tint同材质等值、B1/B2的直接光/反射/混合发光成比例，有色M/R和黑色金属斜入射区分F0变化与漏增益；保B0、HDR关闭、资源改名、无灯、alpha/depth及legacy反例。真实水滴原输入核直接高光与完整画面，独立作者核回归；同输入旧实现须被新断言拒绝。黑albedo不能代替零高光控制，不以shader公式或测试数授外晕改善；当前实际资格仍由运行证据维护。

只在原profile加种类/静态tint，原uniform末加一份16B（tint.xyz与颜色种类w），不新增flags位、纹理、varying、PSO、pass、Frame、池或状态owner。为前置view tint，原alpha/discard整体前移到albedo/component/normal隐式采样及world导数之后、shadow/灯/tint之前；后续gradient/reflection为显式LOD、shadow为无mip depth，不新增导数状态。普通帧不解析/重新资格或做资源查找；关闭/白默认仍有固定ABI/共享片元成本，不授零成本或性能收益。

验收在原资源→Frame→Metal门用白tint/pigment0的Chroma与generic4等值M/R、三灯/normal/map/gradient/rim/遮挡，R0 tint无贡献、R>0零/白/彩tint从实际输出分离两瓣，反证改F0或最终RGB乘tint。核无mask color无效、单侧默认/动态back与先染albedo参考、mask0/半/1同时限制view/spec tint、HDR反射/发光只一次gain、宿主alpha/depth/坏图/覆盖与改名；含带mip normal的透明边界，确保discard迁移不改采样。复用真实parser/helper/profile CPU门与同身份载体。冻结实际Cloud几何/原TEX与alpha、白front/back、pigment0的同灯旧/新控制只授MR贡献；原作者完整图与独立generic4回归不代R0有限高光或pigment资格。当前结果见[模型证据](model-runtime-evidence.md#model-chroma-surface)。

<a id="model-chroma-pigment"></a>
### Chroma的颜料噪声

实际Cloud的tintpigmentation .2已产生受光表面的细粒明暗，保真实几何遮挡、纹理覆盖与其它辐射来源。只在原已资格Chroma、receivesLighting及静态完整标量amount>0时冷准备slot8；缺省0，沿原staticComponents归一到[0,1]，动态/错型只关此项。明确文件按原静态链，文件与typed user输入都省略才用该stock声明的util/noise；显式坏图或无file的user仅退普通受光，不用默认冒充。将gradient的同一默认所有权判断并入原optionalTexture一次，退原消费者重复判断；不接新provider、cache或Program。

本引擎自有算法：噪声锚定当前目标物理片元坐标。普通非sprite保原pixel→UV仿射（轴除mapped extent）与原sampler，真实padding时等于每屏幕像素走一physical texel；不全局改除数或加局部wrap。RGB均值先saturate至[0,1]再映射signed[-1,1]（R8/RG复制R）；该采样归一也承接SNORM数据，不按格式白名单拒图；directRadiance乘1+amount×signedNoise。amount≤1使权重非负且最多2，不叠加资源校验、视距/正弦/时间状态或view边缘拟合。此调制在三灯各自BRDF、衰减/cone及真实shadow累加之后执行一次，随后原ambient/skylight、项目追加发光、reflection、Chroma HDR/fog/PMA依原顺序合并；不改shared BRDF、F0或灯能量。全影/无直接光不能由noise补光，alpha、模型depth/caster不变；噪声锚定当前目标像素，物体移动或换target会改变纹理相位，不授world/object锚定；不宣stock空间相位、官方像素或能耗收益。

原Entry的可选不可变pigment binding携texture/sampler、预投影pixel→UV、局部像素尺寸及通道事实，amount仍由原SurfaceProfile唯一保存；UV除法、尺寸和倒数只冷准备一次。原Frame传给Pipeline，保原32B noise参数、texture9/sampler4，另尾追加16B局部尺寸/倒数，ABI1488→1504B，原offset不动；不挤占rim等其它职责的空lane，没有新varying/PSO/pass/池/时钟/输出owner。amount0/无图不读noise，无直接灯记录时也不取样；固定ABI/占位绑定不称零成本。原‘已保存数值与slot8却无消费者’退出，不把noise乘最终RGB或albedo。

<a id="model-pigment-frame-addressing"></a>
图集源帧的自有域合同：一个sprite frame是独立noise域，不从crop比较反推官方规则。原Loader已供合法frame/isSpriteSheet；只在该分支以UV双轴乘实际physical尺寸的长度形成采样域宽高，每轴最小为1目标像素，再将pixelFrame双轴除该尺寸；整数frame是一屏幕像素前进一源纹素。小于一纹素的frame在目标像素中心退为固定局部中心，不以其亚像素宽度制造无限频率或不可表示倒数；不新增拒绝门或热校验。普通非sprite完整保原表达式、padding/轴交换与sampler行为。新增同binding的float4保存宽高/倒数，零向量表示无局部域；同pigment标记以bit0复制R、bit1局部repeat，普通原0/1不变，不造新资源、纹理副本或可变状态。

Metal对有局部域者先在目标像素坐标做repeat或clamp，再用同pixelFrame；repeat用原typed addressMode决定周期回绕，clamp到该域首末texel中心[.5,extent-.5]；冷准备已保证域≥1，不再在fragment重验，不用saturate把nearest送到frame外。保level0取样；该规则约束采样中心，未宣称fractional origin/extent的线性footprint隔离或普遍crop等值，不为未知边界新增拒绝门或四采样重建。退出sprite沿整atlas mapped除法及跨frame重复的旧职责，不改普通UV/Loader准入/alpha、BRDF、灯、depth和最终输出。

本批最小验收为真实raw TEX的非恒色整数frame/crop，nearest/linear level0、repeat/clamp、资源改名；相邻物理pixel及frame外洋红分开反证错密度、只改除数和错误末端clamp。复用原pigment Prepared/Frame/Metal门保padding、轴交换、关闭与混合辐射原输出，另以真实Loader与完整App的像素闭合，受控texture transport不冒充decoder。达到此独立域像素合同即退出队列；实际作者整图只作回归，不因Cloud原整图正常而宣称作者sprite缺陷已修复。

验收沿现有资源→Frame→Metal：黑/白/彩noise .2与仅灯色.8/1.2的独立等值控制，核三灯、全影、混合ambient/emission/reflection、normal、HDR/half/zero alpha/depth、slot独立采样/空间与改名。缺省/0、generic4、unlit、坏图与明确user缺file不加载噪声；真实parser/helper的静态/动态边界另验。冻结原Cloud几何/TEX/alpha及相同相机/点灯，只切0/.2，核可见颜色贡献与原输入不可变；原Cloud与独立generic4保完整图。真实.2已有细粒颜色贡献，原贡献范围见[模型运行证据](model-runtime-evidence.md#model-chroma-pigment)，sprite像素域与完整App见[局部寻址证据](model-runtime-evidence.md#model-pigment-frame-addressing)；不以绑定或测试数代成果。

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

原生透视的普通 PMA 终端（已接纳的 builtin image、neutral solid）不写相机深度，测试仍消费作者声明，与 `general.transparentsorting`、alpha是否为1和图层有无效果独立。原 Builder 的 preparedImageMaterialFacts 一次准备有效状态，动态 image 模板复制同值，Frame 与唯一 compositor 只消费；保原 raw 材质及 source/graph，不按名称、资产或微小Z差选择算法。粒子、custom Program、Puppet、Framebuffer source 及灯空间深度各归原 owner，不由此扩域。

排序开启时，无效果的普通贴图和 neutral solid 用独立 unclaimed source 资格，局部效果沿原 Graph source route。两者在同一主画布区间按当前 world 原点的相机深度由远到近，同深保作者顺序。不透明写深度模型与无绘制项保原资格。组、画布混合与截点、具名供货及实绘未接入层保原分界。资源准备和编码消费同一顺序。

原 MainPass 的 reverse-depth 域由模型和普通终端共享，深度附件不依赖模型颜色纹理就绪。命名颜色尚未发布时，先保已知必需前缀的分配顺序；有已就绪主域模型时仍推进至该模型，否则走完整已知前缀。普通终端自身的深度需求可在原 StaticModelFrame 建立同一主域，不要求另一个模型先可绘制；晚到模型继续在作者位置解析颜色并复用同一 lease，前缀不发布为完整 draw set。Framebuffer source 继续要求完整准备，组、粒子及其他域保原优先级。原按 pass/command buffer 的单次分配、失败粘滞、busy 延后、容量局部失败和首个实际 encoder 清零不变，不新增资源或状态 owner；退出以首个模型颜色就绪作为普通终端播放许可的关卡。验收覆盖首模型待 named 供货时的文字/效果文字、改名、遮挡与暴露、晚模型复用，以及无 ordinary 的原拒绝、物理失败和容量邻例；真实水滴须恢复字钟，独立模型文字样本保持原画面。

普通贴图与 solid 的末端消费冷准备状态，关排序保作者顺序。独立的 native solid source Program 仍由实际 replay owner 直达 main。验收含近图远底的排序开/关与同主图混合像素。

验收用完整取景及健康peer的六图像/四文字官方颜色类别，保实体前/透明后测试开关；alpha1模型另作边界。复用实际App门的排序开/关、改名、单pass可replay效果、neutral solid、实体遮挡与后绘模型、透明留白、真正solid replay、待供货/清零/局部容量失败，不保旧写入或跳测试的像素预期。原366自然第二段须不改资产/Z/时钟恢复说明文字，独立原作者保模型与文字；neutral普通终端统一策略是本引擎算法，不由有限官方控制授全部solid/FX像素或完整样本一致。

<a id="stock-image-normal-depth"></a>
#### 原生单纹理的覆盖与写深度

stock `genericimage3` 的单纹理、无光照及无雾分支可直接生成图层颜色。材质准备使用原 shader 来源、有效分支、单色纹理和明确的 `normal/default` 深度声明生成普通图像状态，供作者层与相同模型的动态实例复用。非预乘 RGB 覆盖目标，目标 alpha 保持。官版对照中源 alpha 为255、128、0、16时均覆盖 RGB 并写深度，图层 alpha 从1变0.5保持两者。后置画布读取分别证实目标 alpha 255和32都保持。仅关写深度时后绘的较远测试层能覆盖。相同管线不依赖实例名或贴图路径。

保留既有源程序和普通 PMA 终端的适用域。已接纳的 stock 图像借原采样、静态 source candidate、主画布反向深度及最终合成，按需要准备一份颜色覆写变体。动态点共用源产品和 PSO，无需为每个实例建立源程序、离屏色纹理或新深度域。既有画布截点不得跨越这种实际 writer；其他混合、效果回放、资源覆盖或未证明的活动分支保原线路。验收含单纹理透明 RGB、后绘深度邻例、正反写入和等价取样分支，以及原包轨迹冷/热正反切、真实生点到 GPU 和独立作者。原作者与逐像素对照见[同帧运行证据](runtime-evidence-current.md#author-normal-depth-trails-350)。

#### 作者文字深度

原生透视场景有已读取模型实体时，省略 `depthtest` 的普通世界文字默认读取同一主画布相机深度，保留无遮处字形及同平面的字、影叠加。只读默认在 RenderDescriptor 准备，沿原深度附件和终端 compositor。主画布捕获的排序截点保持原作者资格。显式关闭保无深度路径，显式开启沿原状态。屏幕平面、其他深度域及未接纳的混合模式不进入本规则。无匹配模型的场景不为该默认另设深度资源。验收用同盒体的远字、近字、同平面叠字，并核只关测试的原作者反例和独立作者。

显式 `depthtest: enabled` 的原生透视文字，在主画布最后一段独立世界绘制内，与普通透贴共用顺序及已有只读相机深度。该区间只含自身字形、已准备的局部捕获效果、同域透明图像、合格不透明写深度模型和无绘制项。组、供货、当前主画布读取以及其他实绘层划开区间。聚光锥仅在原 Runtime 保有可绘的准备计划和 PSO、且该层可见时划开；作者体积声明未形成可绘计划时仍保实际供货和作者依赖，不切断独立的透明排序。绘制与排序消费同一份已准备资格。开启 `transparentsorting` 时，区间内不透明模型先画，透明终端按相机距离远到近，同深保作者顺序。关闭时保作者顺序，文字仍测试已有实体深度，后继实体在无文字写入的深度上照常绘制。CoreText、Script、局部效果与最终PMA世界quad沿原路径，原终端请求承接帧选定的有效状态。

前区间和不独立文字继续消费写深度及其零覆盖 discard。符合资格的实体可进入 [Composition 背景截点](effect-execution-coverage.md#perspective-composition-prefix)。3455121165 的背景读取范围与早绘时钟字形分离，退出该类文字的旧 writer 仍需实际覆盖字形的官版对照。验收覆盖顺序开关、显式测试近远、半透明字形与改名局部效果、共享目标内只画一次、真实前缀及独立作者。[运行证据](runtime-evidence-current.md#authored-text-depth)

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

<a id="puppet-dense-bind-reference-tracks"></a>
### MDLA0006 的逐骨参考轨

`MDLV0023/MDLS0004/MDLA0006` 的 bounds 布局在 `rawFlags=0` 且没有独立组装姿态或未知参考段时，state1 的密集记录仍按原长度与数值读取，姿态准备把该轨投成 bind 参考。官版固定作者同一槽和相邻帧，只扰动 state1 的 F125 旋转不改变目标骨；只把该轨改为 state0 后同一扰动显现在实际骨轴，独立 state0 骨保持原运动。逐骨处理可保同一作者 clip 中的正常运动。

Reader 由布局和 flags 传已确认角色，Evaluator 沿原 prepared clip：state0 提供普通 TRS，state1 在绝对采样保 bind、在叠加中无贡献。退出要求所有 state1 样本逐值等于 bind 才能准备整槽的旧判据，准备结果无需存放或插值被忽略的样本。其他布局与派生 flags 保既有 bind 等价规则；独立组装姿态、后置曲线、坏 framing 及复杂 opaque 组合仍沿各自边界。

验收锁同槽的正常骨、参考骨、帧和关联实际 skin/画面。近门覆盖改名、可变参考采样、state0 阳性、旧布局与独立 reference 反例；原包验证头肩，另核独立动力样本和已知后置 track 的局部退化。 [实际骨与画面](runtime-evidence-current.md#puppet-body-slot-330)。

<a id="puppet-counted-reference-envelope"></a>
### MDLS0002 的约束记录与组装姿态

MDLS0002 的骨记录状态低两位用于已见布局，实测 1 与 3 共用父索引、矩阵和权重结构。骨表后的两字节小端计数标明组装姿态前的记录数。已证每条为零标识、骨索引、0/1选择字段及64字节记录数据，共73字节。原 RigReader 在声明的 skeleton 末界内推进这一段，只把其后的组装姿态标志及骨数对应矩阵交给现有 reference 消费者。计数表越界或记录形状未知时沿原诊断保留骨架。声明存在且矩阵段损坏时保原错误，父索引与权重的合法边界保持。

组装矩阵和[编译约束链](#puppet-planar-compiled-constraints)由同一次骨读取取得。保空名骨索引、原 skinning bind 与骨 metadata 诊断。MDLS0001/0003/0004 沿原骨尾、组装矩阵和挂点范围。

验收以官版原包与只关作者动画时的实际组装为依据。对照本机仅接纳状态与完整读取组装矩阵，保真实 texture、动态 mesh、主合成与排空。近门覆盖空表、非空表有无组装矩阵、改名与可变条数、坏形状、越过后继 MDLA 的坏长度、现有 reference 及相邻版本拒绝。原包的独立 MDLV0017 手臂与健康 MDLV0019 再核播放。

<a id="puppet-planar-compiled-constraints"></a>
#### 旧版图片 Puppet 的平面约束

MDLS0002 的编译段承载单条连续双段链的骨序，前置记录以末端索引关联引导1和目标0。RigReader 按声明块界准备一次骨序与有序轨映射。控制参考取组装段随附的实际控制矩阵，省组装时取前置矩阵。由已读 rig 把映射交给图片 MDLA0004/0005。辅助轨与普通 TRS 共用 `frameCount+1`、准备预算及原采样时钟，在普通骨轨和原版本尾之间读取。计数为零仍读原尾。已定长的异常控制保普通轨，链无效且存在独立组装矩阵时退回组装姿态，避免把未辨出的骨轨占位叠到组装矩阵。跨度不明沿原动画失败边界。

已见链的中段和末端普通轨是 bind 占位。在原冷 clip 准备中投影为空贡献，当前骨架以组装偏移为准，其余普通骨照原选择。当前对照范围为 additive。按现槽时序与权重累计控制相对参考的增量，目标消费平面位移与末端 Z 旋转，引导决定弯向。用当前根锚、两段实长和目标做闭式投影，超长和过近目标投到最近可达距离。实际局部矩阵沿原父序供蒙皮与后代，约束根脚本保求解前局部和世界矩阵。复用现有查询/渲染局部通道和单个根索引。蒙皮继续用同一实际世界矩阵乘 inverse bind。时变辅助轨参与原 Surface 位姿版本，脚本读前与几何提交采用同一已求解姿态，已采样相位的重复呈现消费冻结结果。

首批以固定根闭式投影实现已证主要运动。官版近伸直的收敛和约束后的少量根平移保留为剩余差异，沿后续实测限定。脚本后写继续通过现有骨写消费同一实际父基。复杂链、挂点和骨物理叠加待独立验收。以两个真实作者的自然播放与同帧成图为准，补改名、编译骨索引变体、坏跨度、同版空表、控制方向和冻结帧读回。运行收据归[旧约束实机](runtime-evidence-current.md#puppet-planar-constraints-official)。

<a id="puppet-prebounds-curves"></a>
### 带未消费曲线的骨骼动画

MDLA6 的 bounds 前辅助区按有序事件、隐式首曲线与后续显式编号和计长跨度推进。bounds 后有独立的每骨定长 `frameCount+1` 标量。仍由原 Reader 确认记录边界和后继事件，未消费载荷仅跳过。失去边界或坏骨轨保原降级。

图片作者槽沿原 ID、顺序、混合、cadence 和 pose 发布已解 TRS、骨 alpha、事件及可配对形变。前置曲线未配对或后置标量未消费时诊断指出局部缺口，退役后置标量挡住整段骨轨的门。固定官版同相位替换后置采样，384身体与377拉弦的主要轮廓由普通轨驱动；沿原部件顺序呈现，不推断标量排序或写入骨坐标。Direct 的后置轨整槽边界归其冷准备，前置曲线仍可保骨查询而绘bind。动态 Single 须有完整消费。验收核同相位运动、坏 framing、改名和独立原作者，沿[图片形变](#puppet-mdmp-morph)与[运行证据](runtime-evidence-current.md#puppet-prebounds-curve-evidence)。

<a id="puppet-mdmp-morph"></a>
### 图片 Puppet 的 MDMP 形变

MDLA 和 MDMP 以四字节关联值的位模式配对，同一值按 Float32 解释为位移尺度。MDMP0001 按声明边界读每形态两个独立计长向量，依次是小端 signed 16-bit XYZ 与每点 u16 覆盖量。MDLV0023 的 84 字节图片顶点流用第四 Float 分量选择一基形态地址，0 跳过。单组 clip 的连续曲线编号按形态顺序绑定，编辑器 ID 独立。长度使组边界不可追踪时仅舍 MDMP，已知边界内的非法组或曲线只影响关联的形变。

冷准备沿原图片 asset/evaluator 一次绑定曲线和形态地址，保持 mesh 资源共享。活动 clip 从既有 FrameSample 与 blend 求各形态权重，每形态采样一次。局部 XYZ 位移用有符号归一分量、组尺度及权重累加到 bind position 后再蒙皮。覆盖量以 0x7fff 为满量程，形态覆盖按 `1 + (目标覆盖 − 1) × 权重` 逐项相乘，再和骨覆盖合成。同一现有发布将顶点与覆盖交给绘制、裁剪、命名输出和唯一合成。单个有非零形态权重的 clip 可与普通骨骼同播。多个 clip 同时贡献形变时保骨骼及其覆盖，单个顶点的形变溢出也沿原骨结果。Direct、动态 Single、跨组曲线与 modifier 延续原路径；超出官方对照权重范围的外推未做画面对照。

现有 image pose 签名计入已绑定曲线的变化，纯形态也要重新发布实际几何；重复相位及休眠保持原快路。无形态的资源继续原 skin/coverage 循环，无 per-vertex 新检查、scratch、纹理或新时钟。形态准备与采样由原图片 pose owner 承接，预脚本骨查询和附件矩阵不消费形态。验收有两个零相位对一个峰值的真实眼周画面、shape隔离、符号/比例/覆盖/slot blend，以及一基地址零对照、带旋转骨的前后次序、同相位复用、隐藏、独立 MDMP 坏长度后健康骨骼、改名及独立作者。MDLA 本身失去可信记录边界时仍沿原拒绝。数值与当前实现差异见[官方对照](runtime-evidence-current.md#puppet-mdmp-oracle)。

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

颜色终端沿同一组已准备的裁剪依赖，将在 source 前的 target 移至其最后一个有效 source 之后。原在依赖之后的部件及无关部件沿作者顺序，嵌套 target 继承 source 的插入位置。顺序只在原几何资源准备时计算，实际颜色绘制与现有 R8 采样同一路径。原包验收同时保瞳孔、眼睑和裁剪边界；仅关效果、仅去裁剪、索引后绘与独立作者为判别对照。

main/named consumer 分别按实际 extent/MVP、target bounds 和采样密度取得 R8 coverage，保透明边界。opaque source 重叠采用当前 max coverage、paint red 与 nested coverage 相交；source vertex coverage 非一的合并语义未完整资格。target alpha 与裁剪 coverage 在原 mesh 合成中只乘一次，后继普通 draw 关闭裁剪状态。

每个 target 使用自己的 ROI；pose 相同不能授权跨 consumer 复用 mask。R8 lease/pin 由原 pool、预算和 submission 保留；缺 paint、预算或 encoder/ROI 失败只隐藏相关 target/下游，不用无裁剪画面回退。

源码：[Clipping](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/ScenePuppetClipping.swift)。

<a id="lighting"></a>
## 光照、材质与显示

`SceneLightSnapshot` 从当前 topology/world/typed 值准备 point、spot、directional、tube，按当前预算接纳最多四灯；tube 保独立有限线段语义。所有 receiver 消费同帧 light/camera，而不是各自解另一份场景。

- 只有实际启用 lighting/reflection 的材质参与对应 producer；plain image 不因场景有灯而自动受光。
- base material 光照在 layer effects 之前完成，graph 捕获该真实 source。albedo/emissive 与 normal/PBR data 分用途读取；normal、radius、锥角与世界距离使用 canonical 坐标，不随 card 非均匀 scale 错变。
- 2D image 与变形后 mesh 的 receiver mapping 不同；不能从 source atlas unit quad 推出 Puppet/模型的世界位置。未支持 receiver 局部保 unlit，并保原 alpha/geometry。
- 模型 directional/spot/point 阴影沿现 typed light、真实 geometry、target 与 submission；可见光束、受光和投影是三种消费者，不能互作证明。
- 现代点光 `lpoint` 的径向项由作者 `exponent` 决定。Format 保留有限非负的显式值，共享 light snapshot 将缺省解析为 2，StaticModel 和 LightingV1 图像消费同一世界距离衰减。平方保乘法；0 无径向衰减，正指数才在半径边界及外截止。各自现有 GPU 参数末尾追加一个四灯指数向量，保持颜色和强度分立以保浮点动态范围。退出两条现代点光的固定平方，保 legacy `point` 平面距离与阴影投影；与spot的共同规则及有限官方资格见[径向合同](#spot-radial-falloff)和[运行证据](model-runtime-evidence.md#spot-radial-falloff)。
- reflection 只在已有 profile 中取得合适的 scene/environment 输入；模型镜面、所有光源/遮挡与图依赖组合仍不完整。
- HDR scene color/Bloom 与终端 SDR/EDR 映射分开；像素 PNG 不能证明显示器实际 EDR 高光。

源码：[LightSnapshot](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Lighting/SceneLightSnapshot.swift)、[2D lit material](../../../MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneLitImageLayer.metal)。采样/颜色合同见[Shader/Graph](render-graph-shader-coverage.md#color)。

<a id="legacy-generic2-model-lighting"></a>
### 正交画布上 stock generic2 的旧点光

同一作者网格及两组等值色隔离了封面取色。官版壳面在无灯时混合环境色与天光，有旧 `point` 时再受随世界距离衰减的漫反射与高光。当前固定模型路径在该材质 `LIGHTING=0` 时直接输出原色。stock generic2 自身不以该 combo 选择受光分支，现代 `lpoint` 与旧点光亦分属不同灯组。选原模型材质和现有点光槽承接这个响应，现代 PBR 与旧平面图像入口保各自合同。

原 MaterialPlan 确认同名 stock shader 的两根阶段及各自通用 include 来自 stock，几何法线变体无 normal map、反射及 detail alpha。准备 `Light`、`Metal`、`Rough` 的静态响应系数，缺省为零并保作者已证 `Metal=2`；非有限系数或会使正面/背向入射零点失去定义的幂值沿原模型 fallback。原冻结 draw 保这一个 profile，旧 `LIGHTING` combo 在已接管的材质上退出颜色选择。原相机帧供画布中点 XY 和 Z 2000 的旧 shader 眼位，保模型原 VP、group 局部尺寸及位置。原世界基的前向线性变换给顶点法线，天空与环境插值在该基下复用共享灯快照的半球系数；片元漫反射和高光使用重新归一化的插值法线。

同一光快照中原始 `point` 按作者顺序向该 draw 供最多四灯，不占现代灯或 shadow atlas 预算。片元共用原 point 循环的世界位差和距离，按半径归一余量平方衰减漫反射，`Light` 控制 Lambert 与 half-Lambert 的插值，金属边缘项同属漫反射；Blinn 半角高光按余量一次衰减并加回表面。两种材质响应共用常量槽、顶点/片元路径与最终合成；旧分支复用 rim 向量、相机槽和 material flags，保现有 ABI 大小、纹理、alpha、深度、排序和投影。旧灯不走现代 shadow 采样。由原顶点 shader 应用前向矩阵，免重复逆矩阵及无必要的可逆性检查。无新资源、缓存、pass、所有者或逐帧材料解析。动态材质参数和其余 generic2 贴图/反射分支仍走现有路径，各自待真实结果资格。

验收冻结同网格、同色、零灯、彩色半球、范围内外的单灯、改名以及现代灯和作者覆盖 shader 对照。以相同输入两端的原像素和实际模型到 drawable 的 GPU 完成为准，另核独立作者和现代模型回归；不以重用素材的单包衍生物代替独立作者。分别记录取色与着色结果，剩余取色缺口保持开放。

<a id="tube-light"></a>
### 管状光源的线段受光

本切片补真实`ltube`到stock generic4/chroma4模型的直接受光。原Format未保留该类，灯86未进入3617056047罐体的共享灯快照；旧App固定实际MDL/TEX的管灯开关无像素贡献；现已闭合[管灯实际受光](model-runtime-evidence.md#tube-light)。沿现Format/Layer descriptor保controlpoint、颜色、强度、半径和指数，原General.lightconfig保tube资格；使用既有当前world/visibility和typed color/intensity/radius，按作者顺序与directional/lpoint/spot共用四灯预算。新增真实Tube数据，不借Point记录或另建灯、世界变换、clock、缓存与compositor owner。原scene每launch从原字节重新解析，现持久缓存不保存这两份解析DTO；shader缓存继续沿原构建source语义身份，不新增revision或目录认证。

项目线段语义先以灯自身局部controlpoint为另一端，复用完整当前world变换；端点世界坐标、单位轴和长度每帧每灯准备一次，片元不重复变换或求线段长度。零长线段保其数学点源极限；无效灯只影响自身。该坐标选择及下述响应是本项目有界算法，官方host的controlpoint坐标域尚需合格平移/旋转对照，不能从stock最近点函数或本地几何推为官方合同；若实际反例否定，修正同一语义入口后再验。

模型片元把表面投影到有限线段最近点，以该入射方向、距离和原径向exponent消费同一SurfaceResponse；强度与颜色仍分立，不按样本、截图或线长添加补偿。原normal/MR/gradient/rim/pigment、HDR、fog、alpha及depth继续现合同；有灯判定同时包含Tube。GPU参数仅在原ModelUniform末尾追加固定四灯小记录、指数和计数，保旧字段偏移，以Swift/Metal实际读回核ABI；每个活动Tube只求一次原表面响应，不增加纹理、pass或PSO。原Pipeline承接且保持1000行以内，不为行数拆wrapper。

首批覆盖实际不投影的管灯：tube阴影、体积、旧材质及Generic/图像LightingV1不由模型结果授予，已有shadowLights及其预算不伪造tube map。验收包括真实Format/General准入、父变换/当前typed值、隐藏/四灯顺序、退化点源等值、线段内部与两端夹取、半径/指数0、无灯/零强度、PBR/Chroma/normal/rim/alpha/depth和改名；保非tube灯的既有行为。用冻结罐体灯开关/点光正控闭合实际像素，原作者与独立星球补代表运行和一次独审；最终贡献、坐标域与官方精确一致分别授予。

<a id="image-material-map-components"></a>
### 图像分量图的显式通道

图像材质沿原LightingProfile与LitCapture供货，分量combo省略取TEX bit20…23默认，显式0禁用、任意非零Int开启；PBRMASKS仅显式0关闭整图。header不是作者显式通道的播放许可，PNG/data候选无header仍可按实际RGBA通道采样。沿原allowed/required两mask：省略只allowed，非零同时allowed|required；原typed payload打包处一次决定(header|required)&allowed，沿现Frame动态emission保有效位。保原emission无效关A、无reflection关B、原receiver/family与标量/混合/HDR/alpha/depth次序，不改变着色算法或默认灯。

退Profile的0/1整数限制、Pipeline对rawFlags缺席的拒绝、required必须存在header的诊断及header∩allowed错误覆盖。原TextureLoader/typed candidate继续保证真实用途、格式与UV/sampler；不加第二texture/map owner、ABI、Program、cache或帧内解析。validated原局部目标别名恢复仍只拒真正冲突的normal/map，重建payload必须保已经决定的有效分量，不能再被header抹掉；map缺失/损坏/禁用仅保标量，不造白图或无header默认通道。R8/RG及其它原格式不借此扩域。

验收扩原PBR/profile/TextureLoader/Metal及既有App载体，先保同输入旧失败；核PNG显式1/2/-1、TEX缺位/冲突header、总开关和分量0/省略、instance优先与完整改名。R/G对等值标量、B对既有反射数值门、A对无灯字面颜色，保独立UV/sampler/alpha及坏normal重建仍保合法map；不复制BRDF。实际App用同图/相机/灯与材质控制取得可区分map贡献和effects同源消费，再以原343活动135按header默认作独立回归；现五星球样本未证受影响显式非零/无header作者consumer，不宣作者缺图修复或官方像素。完成只扩原数值宏语义，不接用户provider、动态分量或新格式。 当前显式通道已沿原消费者接通，实际读回与App范围见[运行证据](runtime-evidence-current.md#image-material-map-components)。

<a id="spot-radial-falloff"></a>
### 聚光灯的表面径向衰减

已解析的作者spot exponent已进入实际模型与图像受光，Snapshot丢值、模型固定平方及图像隐式缺省2的路径已退出。沿原SpotDefinition→共享SpotSnapshot→两表面payload/Metal，不加新light owner、资源、Program或逐帧解析；指数与独立intensity、inner/outer cone及shadow投影分别供货。原Spot入口只把有限非负数保为有效指数，缺省/无效取2、显式0合法；包装只保作者fallback，不授尚无typed target的动态指数热更新。旧2D体积束在原Plan另把exponent用于经验cone形状，已有负数拒绝保持，不借本批重解释或扩粒子/体积消费者。

共享sceneRadialFalloff消费已求出的worldDistance/radius。指数0表示无径向衰减，在半径内、边界与半径外均为1；先由显式0分支返回，退出该语义下错误的半径硬截止。正指数保持distance≥radius为0，再求remaining=max(0,1−distance/radius)及原乘方，2保持原乘法快路；其除法前截止仍避免边界残差，不再借此改写零指数。模型point/spot与现代LightingV1图像共用这一owner，spot cone、shadow范围和volume自己的半径/指数各自保持，旧2D point不扩域。重合点仍由caller跳过无定义方向；shadow采样在半径外沿原visibility1与有限投影，未取得半径外阴影的官版资格，不扩shadow范围。不能以加大半径或调颜色/强度补偿截止。图像保原max-component缩放长度的抗溢出路径，只求一次稳定世界距离，模型复用求灯向量所需的现有距离，不新增重复length/距离计算。模型point/spot只跳真正distanceSquared==0，退有效近距被1e−8平方死区拒绝及radius的1e−4单位下限，直接消费入口已保证的正半径；两者共同保持归一距离语义，不加epsilon或第二距离计算。图像现代lpoint/spot沿原正半径无下限，旧legacy point平面算法本批不改；极端Float平方上溢/下溢不由普通尺度正例外推。各自cone、BRDF/legacy响应、三灯shadow/颜色/强度/alpha/depth与HDR次序保持。stock本地common_pbr_2与volumetricsfront把径向radius/exponent和cone/强度分开；官方366阋神星同焦点已见受光纹理、本地两相反视角近黑；太阳声明radius100000/exponent0，脚本世界距离约120万，构成零指数边界的可区分作者证据。源链和已选实际draw不冒充GPU灯uniform读回；以独立近远控制、正指数反例和缩放改名复核，有限官方观察不授完整BRDF/曝光或所有灯参数接线。

旧remaining参数API与两模型重复remaining/半径floor退出，不加兼容overload。此修正仅替换共享函数的零指数分支，不加状态、payload、PSO、资源或重复距离计算。验收保旧源在新字面预期下的真实Metal失败、同输入新源恢复；保正指数、重合点无方向、锥外、shadow/alpha/HDR及两表面消费原邻例，核真实Eris及独立作者，不按样本或资源选择算法。

原SpotSnapshot只加一个default2 Float，两surface原ABI末各加四灯指数向量16B；原图像preflight/packer直传，只带消费者需要的值。图像packer退出首次整包finite扫描，唯一产品caller补scene VP/reflection后由原Capture.init作一次最终完整检查，也覆盖逆矩阵运算溢出；不为direct pack的NaN测试保留双扫或另加指数门。无新缓存/索引/纹理/PSO/光列表排序或重复非负检查。验收用真实parser/snapshot核缺省/0/.54/坏值及颜色/变换更新保值，模型与图像实际Metal核多归一距离、默认2逐像素不变、.54/0与等值入射控制、cone过渡/锥外/半径边界、shadow/alpha/depth和改名；不复制BRDF。复用真实球MDL/TEX、无脚本单spot固定相机/灯/半径/I/cone，仅指数.54/2，旧.54→新.54/2的终端贡献及新2旧图相等，原343与独立作者保完整播放。未参与渲染的单位、更多动态值和经验体积束不由此扩大资格。当前读回与真实资产资格见[运行证据](model-runtime-evidence.md#spot-radial-falloff)。

<a id="point-light-volume"></a>
### 透视世界的无阴影点光体积

作者 `lpoint` 开启 `castvolumetrics` 时，显式体积密度与体积指数独立于表面光的径向指数。沿同一 light snapshot 消费已解析的世界位置、颜色、强度、半径及当前显隐。显式未开启、零密度或零强度无体积贡献，普通受光继续走原消费者。首批接入逐帧清屏、具有根域实体模型的透视场景和无投影阴影的点光。累积画布的体积色须在历史原色之外发布。

普通透明轨道按有效终端策略不写相机深度；体积积分仍只由实际绘制的实体表面截止，不以alpha或普通颜色混合替代实体覆盖。活跃体积光的帧收集已编码的根域透视模型部件，条件为写深度、普通不透明混合与层 alpha 为 1。该类颜色 draw 的覆盖来自几何，体积深度直接复用同一 mesh、投影和剔除做 depth-only draw，无材质采样。该目标由现有有界 offscreen pool 及同一 command buffer 持有。普通共享深度和投影阴影各自保持，终端显示映射的必需 scratch 先保容量。无活动光、无实体或可选目标失败均无此绘制。

根层完成后，主画布在 Bloom 和显示映射之前加上体积色。复用透视相机的解析视锥和这张同帧实体深度，得到每个像素从近裁面到首个实体深度面的视线段。视线与作者半径球相交后积分径向衰减，再用半径、密度、颜色与强度定标。深度清零像素使用解析远裁面，相机在球内取近裁面起点。求积在最接近光源的位置分开两个单调段，避免窄峰由单个样点过度放大。所有点光复用每像素的深度与视线并合在一次 draw，无额外颜色目标、背面深度、模糊或纹理缓存。

官方原包开关对照确立盘外体积色与直接受光的区别。stock 资料用于确定可读深度、有限半径和径向积分的合同；求积、资源及合成落点由本引擎实现。验收包含实体遮挡与透轨、半径边缘、相机内外、开关与非体积点光、动态显隐、作者原包与独立体积点光。投影阴影、组域、无可用世界深度、雾与体积混用及官方精确质量/色值分别取证。

<a id="limits"></a>
## 当前缺口与最近门

MDLA6 `modernBoundsAuxiliary` 的 framing/presence 被 Reader 保留，但未消费的 scalar/shape 仍由 Selection/Evaluator 拒绝；某个恒定数值不能证明它是深度或绘制顺序。bounds 前曲线的骨骼播放边界见[对应合同](#puppet-prebounds-curves)，MDMP 形变尚无几何消费者。更广 dense/reference composition、多 opaque alpha、Direct attachment/多 part 动画、fractional source clipping、未知 MDL profiles、全部光照/物理/阴影组合仍有边界。

最近行为入口：[bind 几何](../../../script/tests/scene/test_scene_direct_model_bind_geometry.py)、[动画消费者](../../../script/tests/scene/test_scene_direct_model_animation_live_consumers.py)、[裁剪 GPU](../../../script/tests/scene/test_scene_puppet_clipping_render.py)、[普通 effect 受光](../../../script/tests/scene/test_scene_ordinary_effect_lighting.py)。未闭项的下一资格见[队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="spot-light-frame"></a>
## 可见 SpotLight 的准备与帧消费

可见 volumetric `lspot` 光锥沿共享帧进入普通父层、composition/project 的局部 source 和最终合成。帧分发仅在已有可绘计划时建立体积帧。显式 `castvolumetrics=true` 的坏 Plan、pipeline、worldFrame 或 encoder 仍由原 Debug owner 记录失败，false／省略不产生失败遥测，表面直接光继续由独立LightSnapshot供货。原 light plan、共享 world frame、MainPass 和 cone pipeline 各保原职责；model 的逆深度、一般体积散射及官方精确公式分别取证，不用已有错误实现定义新合同。

- **数据流与退出**：`authored light → 原 Plan 准备有限参数/几何比例 → 同一 typed snapshot 与共享 worldFrame → nearest MainPass 的 clip XY 映射 → 原 cone draw → group source → 父 Program/tail → unique main`。Pipeline 直接消费完整 worldFrame，保父/自身平移、旋转、缩放、镜像及剪切；角度已由共享 Timeline/Script/world resolver 合成，不再从 worldOrigin 与私有 currentAngle 重建。退役 Plan 的 parent/leaf/无依赖许可、baseAngles/currentAngle 和单一 relative-mirror Timeline 形状门；effect 尚无本绘制消费者，保持局部未支持。
- **准备与读口**：Plan 不再按样本数值上限拒绝可消费的 cone。只保 finite/color 域、非负强度/radius/density/exponents、合法内外锥角及实际可表示的派生几何；半角 trig 与不随帧改变的比例在原 Plan 一次准备，帧不重复计算。零强度/半径/密度沿真实消费者得到无贡献。当前 typed TRS/color/intensity/alpha 与外层 visibility 是实际读口；alpha 沿原 normalized reader 进入既有 color uniform 的 A，保持 PMA。Script 源覆盖只在原准备入口核真实 object/field 身份、已实例化 scalar/vector target 与上述消费集，退出单 intensity/count/源码写法许可；未知、nested 或未消费 radius/density 等 writer 不能静默冻结。共享 Timeline 编译器继续拥有各 host/模式的执行边界，不另建光锥时钟或重放。
- **局部投影与层级**：原 MainPass 从同一 rasterClipRows 提供保 Z/W 的投影矩阵，供既有 cone MVP ABI；无 map 直接复用原 VP。图像的平面矩阵不能用来抹掉新 worldFrame 的近远裁剪。该小方法表达原 owner 的 clip 投影概念，避免在灯光或未来几何消费者复制矩阵规则；不新增 map/cache/状态。SourceRoute 退役已接通实际消费者的整类拒绝，模型的独立合同见[局部合成](#model-subtree-raster)。RuntimeModel 的原颜色 producer 集合准备实际 volumetric cone 消费，不再依赖另有可见 static model，也不因祖先初始隐藏冻结该 cone 的 producer；实际帧仍沿原 visibility 控制 draw。Session 直接汇合已有 scalar/vector definitions 的 target，不重跑绑定解析或认证。
- **失败半径**：未实现 effect/writer、坏数值及实际矩阵乘积溢出只使该 cone 不供货，健康同组成员、父级与后继按原生命周期继续；GPU 边界只核最终可提交矩阵，不层层重验同一输入。资源、visibility、group clear/target、pin、publication 与 compositor 不新增 owner。native 世界中旧独立负角/忽略 Z、XY 角及 scale 的行为由共享 TRS 替换；不能声称这些旧 root 全像素保持。

验收先用真实 Plan/typed writer/Timeline/world resolver 与 production Metal，核 root/parent、绝对/循环/静态、scalar/vector/多 writer、未消费与错身份反例，真实 ABI、alpha/PMA、near/far 与有限乘积溢出。完整 App 比较同 TRS 普通 container 与局部 group，配字面父90°/scale2方向和边界，防两端共同丢父轴；再核非均匀×自身角的 shear、资源/ID/变量改名、父颜色变换、初始隐藏→开启及开启→隐藏无残影，闭合 cone target→父输入→Program→main/seal/GPU。无组和 viewport map=nil 用同身份基线复用；独立真实作者逐层核实际 cone/model 与终端，只把实际改变的字段/画面列为恢复。自有分组、独立作者及未覆盖范围由[运行证据](runtime-evidence-current.md#spot-light-frame)维护；新消费者需要另一 renderer/clock 或未解体积语义时，回到原职责设计，不扩到 model 或改 fallback。
