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

新增导入模型 profile 限定既有 `MDLV0023/MDLS0004/MDLA0006` 配对。Reader 在现24B位置保留6个有限、有界、逐轴 min≤max 的 bounds（零 extent 合法），随后保严格 absent scalar 字段；0021及其他旧版本合同不扩。正式 Reader 已完整读取原329的17条 records，并发布16条 exported clips；格式通过本身不等于这些 clips 均已被实际选择或播放。

record ordinal 是源引用身份，exported animation ID 是作者层选择身份，二者不混用。保留完整有序记录、raw mode/flags和 typed source-reference、frame range、control、root-selector；派生引用只能指向已读取、非派生的 source record，范围有界且长度等于已物化 TRS 的 frameCount。源 take 与派生 clip 可有相同 exported ID，不能 first/last-wins或按名称特判。存在派生记录时，作者选择集合只发布派生 clip，源记录仅供引用；派生之间仍要求 ID 唯一。无派生的旧完整动画集合保持原 ID 唯一合同。

首片导入标记只接受已核结构的0/0x401，派生控制为0、root selector为-1；其他标记/控制/root处理未资格，不静默丢弃。派生描述位于 bounds/scalar 后、原 u32 事件列表前，不能改事件计数宽度。TRS已经物化为当前 clip 样本，source range不再次截帧或取源 take 的时间。原 Rig 无reference pose，default34各track为sampled；后继输入仍须执行原 referenceCandidate 的 constant/bind-equivalence 门。

固定2.8.0.42客户端的有界静态研究确认：MDLA实例把自身mode交原播放初始化，空值与显式loop选择相同默认状态，未观察到源mode继承或0x401改mode。实现只对上述已资格23派生 profile 显式canonicalize empty→loop，并保raw mode；其他未知字符串继续拒绝。官方动态模式对照未资格，不能由该 canonicalization 外推官方时间或像素 golden。

全部record的骨 TRS/state、alpha/aux/events、数值与累计预算按声明顺序完整验证，cursor精确抵达MDLA declaredEnd；不跳坏记录或只找34。新非零bounds/派生profile物理闭尾只接受 exact EOF 或唯一零字节，旧23纯零/非派生通路保持原declaredEnd合同；不把旧Reader描述成已有全文件EOF证明。bounds仅为metadata，不用于改origin、pose或culling。

原 keyed auxiliary 的存在事实保为 typed channel-presence。首片 direct 只准实际参与者的骨alpha缺省/全1且无未消费 scalar/morph/channel；alpha/events/TRS保真，不删除或中和作者channel。非中性alpha或未消费channel使用typed bind降级，旧image行为不收窄。direct非空attachments的Scene坐标基未资格，使用typed bind降级；MDAT解析异常在准备期保留失败，不当成absent，不沿用image的Y反射。

## 默认选择、时间与站位

AnimationSelector 与 AnimationPlaybackRuntime 继续拥有 authored layers、顺序、additive/blend/rate及已支持的 visibility/property/script 选择；可动态显现的合法 binding 也须准备，不能以初始不可见排除。原329虽有8个动画层请求，本轮实际只准入固定 true 的34；`user:{name,condition}` 条件对象尚未进入 String-only visibility binding，其他请求的条件选择及热更新仍开放，不能把16条可寻址 clips记成8条已准备。原 Rig 无 reference pose；后继 referenceCandidate仍过constant/bind-equivalence门。play/pause/seek/setRate、事件、bone override与多surface顺序沿原链，不另算elapsed time。

原329的rate wrapper含音频脚本，当前未消费且保留诊断；`.setRate` API存在不等于该来源已接通。实际恢复限静态fallback rate=1的连续TRS。音频rate后继须沿script binding → typed animation control → PlaybackRuntime接入并补来源/失败合同，不以新clock或复制脚本替代。

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

原329已实看默认34脚部回到盒顶区域并有动作，视频、立方场及既有主体保持；细节不扩大为所有clip/channel、完整音频/条件选择、轨迹/密度、官方同相位或性能结论。边缘多色块已由[公共截面后继](runtime-evidence-current.md#screen-displacement-ribbon-20261020)另行关闭具体反馈。音频、pointer和时刻未对齐时不据截图差异另判缺陷。

任何后继输入的格式、reference、channel、N/T或stream生命周期先决失败，沿上述typed bind/最小draw拒绝退出，保留原因；不丢作者channel，不补origin或旧pose。若需要平行clock/LBS/renderer才可推进，须修订本设计，不累积补偿。
