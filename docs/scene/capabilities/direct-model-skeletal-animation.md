<!-- document-role: stable-contract -->

# Direct model 的骨骼动画

Direct model 沿原 world transform 消费作者动画，保完整 XYZ、normal、tangent、UV、材质和共享 depth。本批在[严格 bind 几何](direct-model-bind-geometry.md)上恢复原329默认34的蒙皮与动作，实际脚部回到下方盒顶区域；未调 origin、按 bounds 对齐或补偿截图。本文拥有职责与安全合同，支持范围见[高级对象覆盖](advanced-object-coverage.md)，CPU/GPU、App身份与实际画面统一归[运行证据](runtime-evidence-current.md#direct-model-skeletal-animation-20261019)。这不是精确双脚接触、官方同相位或整样本通过。

## 现有职责与数据流

StaticModelReader 保留 validated Rig，PreparedStaticModelResources 准备 immutable bind mesh 与动画集；原 selector、launch playback clock、PlaybackState 和 evaluator 共同服务 image/direct。共享顶点贡献保留 XYZ，image 在输出边界取 XY/SceneQuadVertex，direct 使用原 StaticModel.Vertex 和 layer/surface 私有 stream，不另建 LBS、renderer 或 clock。

| 职责 | 唯一承接者与数据流 |
| --- | --- |
| 格式与准备 | 原 StaticModel/Rig/Animation readers → 现 prepared resources；按原资源 identity 保留 validated bind vertices、indices、Rig、normalized influences、有序 records 与可寻址 clips。`geometryByPath`只可共享 immutable 数据，不存可变 pose/buffer。 |
| 选择与当前 pose | 原 AnimationSelector → AnimationPlaybackRuntime，在同一 SceneClock/launch cadence 推进；各 surface 消费同一 immutable LayerFrame。现 PuppetPlaybackState 复用 TRS、blend、bone override、bone world 与 SkinMatrixProjection，为 image/direct 提供 typed geometry sink。 |
| 几何与绘制 | 现 evaluator 的共同顶点贡献计算保留 XYZ，image 只在最后适配 XY；direct 输出原 StaticModel.Vertex，由原 StaticModelFrame/材质/阴影/共享 depth/compositor 消费。不得制造第二份 Puppet 顶点模型或平行变形算法。 |
| 提交生命周期 | 原 StaticModel mesh/binding owner 承接有界 dynamic vertex stream；当前绑定归 layer/surface 与具体 command submission，immutable mesh、index、material 可共享。现 SourceUpdateTransaction 管 CPU 更新签名，不替代 GPU storage lease。 |

## 先决格式资格

新增导入模型 profile 限定既有 `MDLV0023/MDLS0004/MDLA0006` 配对。Reader 在现24B位置保留6个有限、有界、逐轴 min≤max 的 bounds（零 extent 合法），随后由共享Reader保留已知dense post-bounds scalar的presence，但direct仍拒未消费通道；结构与image附加动作局部降级归[唯一合同](advanced-object-coverage.md#puppet-additive-local-unavailable)，direct可选范围不扩。0021及其他旧版本合同不扩。正式 Reader 已完整读取原329的17条 records，并发布16条 exported clips；格式通过本身不等于这些 clips 均已被实际选择或播放。

record ordinal 是源引用身份，exported animation ID 是作者层选择身份，二者不混用。保留完整有序记录、raw mode/flags和 typed source-reference、frame range、control、root-selector；派生引用只能指向已读取、非派生的 source record，范围有界且长度等于已物化 TRS 的 frameCount。源 take 与派生 clip 可有相同 exported ID，不能 first/last-wins或按名称特判。存在派生记录时，作者选择集合只发布派生 clip，源记录仅供引用；派生之间仍要求 ID 唯一。无派生的旧完整动画集合保持原 ID 唯一合同。

首片导入标记只接受已核结构的0/0x401，派生控制为0、root selector为-1；其他标记/控制/root处理未资格，不静默丢弃。派生描述位于 bounds/scalar 后、原 u32 事件列表前，不能改事件计数宽度。TRS已经物化为当前 clip 样本，source range不再次截帧或取源 take 的时间。原 Rig 无reference pose，default34各track为sampled；后继输入仍须执行原 referenceCandidate 的 constant/bind-equivalence 门。

固定2.8.0.42客户端的有界静态研究确认：MDLA实例把自身mode交原播放初始化，空值与显式loop选择相同默认状态，未观察到源mode继承或0x401改mode。实现只对上述已资格23派生 profile 显式canonicalize empty→loop，并保raw mode；其他未知字符串继续拒绝。官方动态模式对照未资格，不能由该 canonicalization 外推官方时间或像素 golden。

全部record的骨 TRS/state、alpha/aux/events、数值与累计预算按声明顺序完整验证，cursor精确抵达MDLA declaredEnd；不跳坏记录或只找34。新非零bounds/派生profile物理闭尾只接受 exact EOF 或唯一零字节，旧23纯零/非派生通路保持原declaredEnd合同；不把旧Reader描述成已有全文件EOF证明。bounds仅为metadata，不用于改origin、pose或culling。

原 keyed auxiliary 的存在事实保为 typed channel-presence。首片 direct 只准实际参与者的骨alpha缺省/全1且无未消费 scalar/morph/channel；alpha/events/TRS保真，不删除或中和作者channel。非中性alpha或未消费channel使用typed bind降级，旧image行为不收窄。direct非空attachments的Scene坐标基未资格，使用typed bind降级；MDAT解析异常在准备期保留失败，不当成absent，不沿用image的Y反射。

## 默认选择、时间与站位

AnimationSelector 与 AnimationPlaybackRuntime 继续拥有 authored layers、顺序、additive/blend/rate及已支持的 visibility/property/script 选择；可动态显现的合法 binding 也须准备，不能以初始不可见排除。原329的8个条件动画现由成功Bool Program投影动态准备来源，实际全部准备；同session模式1→2→1已消费具体34→35→34并改变模型姿态，沿原clock与surface私有stream，不重建窗口。该条件对象增量限direct model；image对象条件未开放，旧String/image合同保持。不能把16条可寻址clips外推成全部已播放，实际后验见[条件热切换](runtime-evidence-current.md#conditional-model-animation-20261020)。原 Rig 无 reference pose；后继 referenceCandidate仍过constant/bind-equivalence门。play/pause/seek/setRate、事件、bone override与多surface顺序沿原链，不另算elapsed time。

原329的8个rate Number脚本现经原ScalarProgram/QuickJS、accepted typed snapshot进入共享PlaybackRuntime，默认34实际随音频输入改变推进速度；[运行后验](runtime-evidence-current.md#puppet-animation-rate-script-20261020)只关闭该值源，保留原graph、全部模式及完整官方时相边界。

<a id="animation-rate-script-values"></a>
### 动画rate脚本值源

目标是让作者的动画层Number脚本进入现有播放速度消费者，恢复音频/共享属性驱动的动作快慢；不改变姿态、选片、动画时间单位或新建clock。Format的原binding parser保留`animationlayers[index].rate`；visibility与rate共用一个prepared身份资格：parent/index/animation-layer ID、完整path、唯一ID、原wrapper和typed seed必须一致。原ScalarProgram独占Number执行/音频输入/失败回退，原VectorProgram继续Bool visibility，两者不复制求值或跨目标复用有状态模块。

成功rate owner沿原nested animation handle暴露`thisObject`；Swift只准Bool visibility或scalar rate的精确target，C仍拒value-only、current-Timeline及重复配置。两个nested值源只可产生原Puppet控制cohort，不能写parent layer、effect、media、particle或bone；throw/非法返回/host晚拒继续撤销整个owner bundle，健康peer保留。rate采用现控制命令的有限、非负且可表示为Float的值域；0冻结速度，负值/非有限/溢出局部拒绝，不静默钳位。

Scalar结果由原accepted typed snapshot发布，PlaybackRuntime在下一cadence只读取该动画身份的合法`sceneScript`已提交值；缺失、拒绝或Resolver的authored回退不覆盖上一健康速度/API状态。动态值与现`.setRate`共用一份phase-preserving状态更新：先保留当前phase，再改速度和offset；相同速度提前结束，禁止以`sceneTime × 新rate`重算从头位置。每个launch只推进一次，surface只消费同一immutable frame；暂停、隐藏、seek、事件、同cadence重读与新注册parent沿原合同。资源选择、rig/aux/alpha准入、bind降级和属性条件范围均不因rate放宽。

回归贯通真实parser→ScalarProgram/QuickJS→typed snapshot→原PlaybackRuntime，覆盖变量/资源改名、等价式、path/index/ID错配、重复定义、无script邻例、0/正rate、非法返回、throw/晚拒及健康peer；变速点phase连续且暂停/隐藏/同cadence不重复推进。原329默认34的固定PCM/静音已取得实际rate与GPU完成姿态的速度差，独立真实Puppet样本有界渲染/退场；本轮不重认普通Release视频连续播放或全部动作面板。rate带`applyUserProperties`的live readiness未扩，原329仅有init/update，不由此推断该组合已支持。不以owner命中或构建代替播放收益，官方精确audio/phase未对齐不宣称parity；若原作者脚本仍有更早失败或没有可归因动作收益，停止升级能力并重排。

<a id="conditional-animation-properties"></a>
### 条件动画的准备与热切换

准备集合不决定当前pose算法。若当前只有一个实际采样的非additive clip，Evaluator必须保留single-absolute完整骨贡献，使用该clip实际blend；额外准备的隐藏clip保持中性。时间采样统一消费准备期Pose：translation/scale线性插值，rotation沿现有四元数最短弧采样，不直接线性插值Euler分量；角度跨±π或等价角度表示不能使相邻姿态绕远路。原始角度与Reader保持不变，legacy便利入口也归同一Pose采样owner。合法sampled identity是作者的绝对骨姿态，不能因多准备clip而退回bind。零active、多active和additive继续原reference/合成合同，不借本片扩大多层规则。正反例须验证隐藏peer加入前后的XYZ/N/T一致、跨界旋转连续及整数端点，不能以旧Euler数值为目标；真实画面仍须验左臂闪动、骨盆与上下身。

新增条件准备也不得撤销此前健康的默认动画。投影器为本片新补的object来源保留可缺省的prepared provenance；旧String/script的required资格不改。Direct资源owner在已完整读取/验证的同一动画集上先尝试完整选择与Evaluator；仅当新增的当前隐藏需求触发selection/evaluation资格失败时，沿同一Selector/Evaluator重试移除这些新增隐藏需求的集合，并保留typed原因。Reader、rig/附件结构、取消或其他失败不重试，不跳坏record或重读资源。保留clip的DTO/顺序/identity不变，使原完整authoredLayers注册仍匹配；未资格target不进入active集合，整key热改仍拒绝。新object来源缺当前合法Bool时保原resolved visible值，旧String缺值仍隐藏/冻结。缺clip、未资格reference、无当前typed值、旧String和结构错误须有正反例；后继CPU及完整构建见[运行证据](runtime-evidence-current.md#conditional-model-animation-20261020)，新回退分支的真实运行仍待验，不据此升级样本状态。

已支持的属性条件沿原Program选择direct model作者动画并在同一session热切换；不新增image对象条件资格。首个有界正控为既有八选一请求的模式1→2→1；验收须同时确认具体 animation-layer/clip identity、typed Bool、姿态与实际模型画面，不能只看某处运动。条件、Combo完整域及整key原子更新仍归现 BindingProgram/LiveState，pose/phase只归原 PlaybackRuntime。

采用 `现 parser/report → 编译成功的 Bool Program → prepared animation metadata → 原 Selector/资源/PlaybackState → typed snapshot → 原 pose/stream`。仅解析到object引用会把无producer的fallback误隐藏，按当前条件或startupValuePaths准备又会漏掉以后可选动画，因此两者均不作资格。RuntimeModel在唯一Program产生后，按该Program的definition/instruction与原report精确核parent、animation索引/ID、path、property key/condition，排除整key仍需重建的输入，再为direct model现DTO补动态来源标记；不重解析wrapper、不在Format复制条件算法。无成功producer保旧resolved fallback；旧String绑定缺typed值时仍隐藏/冻结。该投影只在准备期发生，原始SceneDocument保持作者事实。属性context复用同Compiler/投影判定可展示项；真实正常App已显示原生String动作Combo并完成保存/重开/reset，确切身份与用户画面反馈归运行证据；不外推App重启持久化或全模式。

Host候选仅来自成功的direct动画selection/evaluator、可绘制Entry和原pipeline；沿现direct channel资格，不把有mesh或一般prepared layer当可消费动画。Session继续在同一live-state入口扣除unavailable targets：要求完整surface集合、同generation，每个view都持有成功构造且注册至原clock的direct playback state和准确动画身份，并扣除现topology已提交删除的parent。复用同一channel判定，unsupported alpha/aux不能冒充可热改；短暂GPU slot busy/奇异帧沿旧局部fallback，不重置clock或抹掉准备资格。不建立第二份availability registry。

验收复用现Document/PropertyProgram/Selector/PlaybackRuntime/DirectModel门：改名与等价条件、missing catalog/非法条件保fallback、合法producer当前无效值后恢复、path/index/ID错配及冲突、完整八目标原子切换、准备/注册/缺surface/旧generation失败、健康image邻例。真实原包同session1→2→1应有对应clip/姿态和画面收益，不能有重建或新clock；未知clip、多alpha/reference composition等原门不放宽，音频rate独立保留。若需跳坏clip、猜phase/参数、旁路surface失败或新建动画执行链才能出图，停止并保旧能力；无实际切换收益则撤回候选。

站位只能由 qualified34当前 pose、完整 XYZ bind mesh、Rig hierarchy/inverse-bind/weights 和原 layer world 共同得到；root/bone translation、inverse-bind、layer world 各只施加一次，保留 author root motion。clip28 bounds、足骨 local translation 或 raw bind 最低点不能代替当前蒙皮足部位置。当前原图及重复运行支持脚部位于盒顶区域和姿态变化；未捕获同帧model world/盒顶的数值join，不宣称双脚全相位精确接触，不能以新AABB调origin、culling或pose。

## XYZ、normal 与 tangent

沿现影响顺序和权重归一计算同一 `skin = boneWorld × inverseBindWorld`；共享accumulation保留XYZ，旧image输出取XY，保持原数值和排序。direct 不使用 image pivot、Y 翻转或 atlas 几何转换；canonical layer/model/camera 变换只施加一次。

首片采用每顶点固定 validated weights 的 full-affine skin-frame：位置为 `Σ(weight×skin×bindPosition).xyz`，线性部 `A=Σ(weight×skinLinear)`；normal 取 `inverseTranspose(A)×bindNormal`，tangent.xyz 取 `A×bindTangent`，原 tangent.w 乘 determinant 符号，UV 不变。保留 raw 方向幅度，零保持零，不额外 normalize/Gram-Schmidt，也不重算面法线；后续沿原材质处理。这是 frame transport，不是已证官方照明公式。复用/提取现 normal-matrix 的纯数学职责，但不能照搬其归一化缩放而改变 raw 结果；model normal transform 仍只执行一次。

即使各骨为 rigid，blended A 也可能 singular；奇异或非有限时，该层当前 geometry binding 使用完整、安全的 bind 几何并标 typed 降级，不混合新 position 与旧方向、不读上一 pose，不补默认 normal/tangent。非均匀、镜像、rigid 混合抵消、零方向须有独立数值/实际绘制正反例，不能只验平移或 position；这种 bind 降级不能作为动画/站位成功。

## 动态 stream 与失败退出

原 StaticModel mesh owner 为每个layer/surface预留3个受现资源预算约束的vertex slots；indices/material 不变。写前核64B ABI、vertex count、安全字节运算、全部通道和当前 bounds。首 encoder 前取得 slot/generation lease，生成 immutable 当前 geometry binding（pose revision、vertex lease、bounds），color 与全部 shadow 必须消费同一绑定；不能按 path 共享可变结果，也不能在深度/阴影已准备后换 pose。

lease 精确关联 layer/surface 和 command buffer，覆盖所有 encoder 直到 completion；仅未 enqueue 的取消可立即回收，迟到 completion 不得释放已复用 generation。禁止只取 modulo slot 或覆盖 in-flight buffer；同帧复用绑定也必须满足该提交归属。SourceUpdateTransaction 在现唯一renderer创建点绑定command buffer；stream只接同CB的事务，lease借其completion/rollback回收，不另装completion owner。该事务的CPU signature不替代slot/generation租约，bind前必须核同CB。容量耗尽、分配/encode/GPU 失败或销毁按原 completion/teardown 路径释放；不回滚 SceneClock/SceneScript，不把旧 vertices/bounds 标成当前 pose。

必需 mesh/Rig 安全失败仍不可用。启动时可选动画缺失/不支持，继续唯一 typed bind-only 降级并保留原因；合格动画绑定生效时 bind-only 退出该层绘制权威，不在其后重画 bind mesh。当前 pose 的奇异/非有限 frame 沿上述 typed bind 降级；lease/encode 失败跳过最小 direct draw，不能静默换成旧 pose 或未持有的 buffer。旧 static 与 image Puppet 的准备、alpha、取消和输出合同不变。

## 验证边界与停止条件

最近Reader门覆盖旧版本/纯零/full合同、新bounds/派生引用/双身份/mode、改名与坏后记录；原329的17 records/16 clips和34单独资格不靠跳记录或截取源take。自有双层输入检查同MDL不同clip/phase的pose隔离；共享XYZ/N/T、镜像/非均匀/奇异、旧image XY、3slot容量/取消/迟到completion及附件失败沿最近门验证。实际运行与门的精确覆盖只由[运行证据](runtime-evidence-current.md#direct-model-skeletal-animation-20261019)登记，不把fake GPU、编译或自有primitive通过算作原包输出。

原329已实看默认34脚部回到盒顶区域并有动作，立方场及既有主体保持；视频及其音频条的当前反馈按[运行证据](runtime-evidence-current.md#conditional-model-animation-20261020)单独核实。细节不扩大为所有clip/channel、完整音频/条件选择、轨迹/密度、官方同相位或性能结论。边缘多色块已由[公共截面后继](runtime-evidence-current.md#screen-displacement-ribbon-20261020)另行关闭具体反馈。音频、pointer和时刻未对齐时不据截图差异另判缺陷。

任何后继输入的格式、reference、channel、N/T或stream生命周期先决失败，沿上述typed bind/最小draw拒绝退出，保留原因；不丢作者channel，不补origin或旧pose。若需要平行clock/LBS/renderer才可推进，须修订本设计，不累积补偿。
