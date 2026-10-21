<!-- document-role: active-plan -->
<!-- retirementCondition: SDR 映射与可选 EDR 的目标合同并入稳定输出架构且通过各自显示验收后归档，删除设计登记。 -->

# D2 — Scene HDR、tone mapping 与 EDR 输出

> 本文拥有设计裁决；当前能力和验收见[运行证据](../../capabilities/runtime-evidence-current.md)，稳定 owner 见[运行时架构](../../architecture/runtime-architecture.md)。`approved` 不代表未验范围已支持。

## 目标合同与设计判据

保留作者高亮的中间精度，在唯一 terminal compositor 的输出阶段做一次有明确颜色语义的显示映射：先保持 SDR 正常颜色与 HDR Bloom，再开放可选 EDR。跨 target、Bloom、surface 和显示状态 owner，触及唯一输出与外部平台合同。

本设计横切准备、颜色与显示 owner，依赖官方和平台行为证据；用户数据与发布语义不变。

## owner

现役 descriptor/preparation 决定颜色内容类型与 storage；Bloom 在同一图内处理；terminal compositor 拥有显示变换；SceneMetalView 只配置 surface 和接收按屏幕发布的显示能力。禁止每个 layer 自做 tone map 或另开 HDR 输出器。

## 方案设计与选型

选择**显式区分 authored HDR 合成与显示 EDR**。HDR 的超白先参与 Bloom，SDR 终端保持正常颜色并裁剪显示范围；不为了压入全部超白层次而默认降低普通白点。只换 16F 不是 EDR，未经确认的系统 metadata 可能重复映射。

| 阶段 | 输入及输出合同 | 开放边界 |
|---|---|---|
| A：颜色语义确认 | 明确纹理 decode、shader 输出、blend、Bloom 的 transfer/primaries/alpha；沿当前 content/publication 表达 | 不得仅因 target=16F 就 reinterpret 为 linear |
| B：SDR | HDR scene color/Bloom → 正常 SDR 范围恒等、超白裁剪 → SDR terminal attachment | 非 HDR 既有 SDR 路径数值守恒；默认先交付此阶段 |
| C：EDR | 相同 HDR scene color → 当前 headroom 的扩展线性显示值 → RGBA16F extended-linear surface | 逐显示器能力、系统开关和用户选择共同允许时开放 |
| D：可选 metadata | 仅存在真实且格式匹配的内容元数据时评估系统映射 | 当前选择自有映射时不叠加系统 tone map；不可从截图猜 metadata |

颜色转换的位置先由 A 的合成 fixture 固定，不能简单给现有 display-referred 输出再套 gamma。HDR Bloom 在输出映射前完成；normal/roughness 等 data 不进入颜色变换。SDR 导出规定连续、单调不减、有限、保留正常范围内的颜色；超白可同白，不声称官方私有曲线或 EDR 高光验收。

**2026-10-06 阶段 B 纠正裁决。** 用户报告默认颜色变暗；无曝光输入、无 EDR surface/headroom 路由却仅因 `general.hdr=true` 自动使用 knee=0.5 的 shoulder，使普通白点 1 变为 0.75。该曲线是本项目旧策略，并非官方合同，本次撤销该默认压暗策略。官方公开 Bloom 文档说明 HDR 超白参与发光，不足以支持对全部普通图像强制降白点；本次是按用户目标纠正产品策略，不宣称官方数值 parity。 阶段 B 的唯一终端输出在 Bloom 之后对有限 RGB 饱和到 `[0,1]`，区间内逐通道恒等；非有限 RGB 归零，alpha 原样保留。非 HDR 路线不创建该 owner。中间 HDR target、raw history、反射及 Bloom 继续保留超白，不提前裁剪；只有最终 SDR 显示丢失超白强度区分，超白的空间发光贡献仍由 Bloom 保留。不要以可选 EDR 尚未完成为由维持默认普通颜色错误，也不能把 SDR 裁剪称为 HDR 显示完成。以后若需要曝光或保高光映射，应有显式输入/显示合同与独立对照，不恢复无条件的压暗曲线。

沿 RF07 的 distinct raw/display 导出与完成权威实施，不新增 renderer、历史、资源池或逐帧分析。清底与累积场景同样保持正常白点；raw 永不接收 Bloom/显示结果，暂停导出不重复合成。现有不透明 surface 边界不变，透明输出另验。GPU 纠正门使用独立已知 SDR 色块（含 0.625、0.75、0.875、1）的逐位保持、超白有限裁剪、非有限局部处理、Bloom 超白产生邻域增亮、source/alpha 保持、失败恢复和 raw 多帧累计；SDR 正常色不以旧曲线公式为 oracle。实际 App 验证 clear true/false 与暂停 resize。EDR 仍按 C 的平台门另行实施。

**2026-10-06 阶段 C 实施裁决。** 现役最终输入是 display-referred sRGB，不把 raw/纹理重新解释为线性。具备映射管线的 authored HDR surface 固定使用 RGBA16F/extended-linear-sRGB；唯一终端将非负有限 RGB 按扩展 sRGB 传递函数解码一次，普通0..1保持显示亮度，超白限制到本屏当前EDR headroom。SDR回退上限1；未准备映射的surface继续原sRGB，不能带错误颜色空间导出raw。线性surface映射失败拒绝本次提交、保留旧帧，不将未解码颜色呈现。透明输出仍不开放。

用户设置“Scene HDR显示”独立于作者Bloom，默认允许在支持的屏幕自动使用，关闭后同会话回到SDR。现役共享设置传递意图，SceneMetalView按所在屏幕的potential能力请求EDR，以current headroom控制typed帧输出；不以current=1拒绝初次opt-in。颜色空间在surface生命周期内固定，避免在途drawable因开关变义；屏幕/设置变化只更新显示状态与重绘，不改Program/图/raw历史。每帧只读取本屏标量headroom，暂停通过现有surface失效入口重绘；不增加计时器或输出owner。验证真实CAMetalLayer配置、GPU普通色/超白/源alpha、设置热切与SDR设备回退、映射失败不发布及raw隔离。截图按其线性输入转换为普通sRGB预览，不把PNG亮度当物理EDR验收；硬件亮度与多屏实测边界分别报告。metadata不叠加。

## 特效颜色边界保留浮点范围（2026-10-08）

PMA→straight 是表示转换，不是显示映射。现有编译器插入的输入 helper 将 RGB/alpha 裁到0–1，违背上文中间HDR不提前裁剪的合同；先用实际accepted Program和F16输入证明超白经作者衰减后仍错误变暗。修复归现有 Metal source 生成职责：共享边界函数供 bounded frontend 与 generic lowering 使用，删除各处重复实现；离线编译工具同步同一合同。只转换已证明的颜色槽，data/signal采样及作者表达式不改。alpha仍按既有coverage域处理，零alpha返回零RGB；有限扩展RGB保留到作者运算与既有终端。作者明确的UNorm输出饱和保留；独立信号合成的自动RGB输出裁剪同样撤销：两个0–1输入的实际generic Program将作者结果1.25裁成1，bounded Program保留1.25。两端覆盖alpha仍有界。持久工件及含生成代码的准备缓存撤销旧版本，不靠用户清缓存。验收覆盖不透明/半透明HDR、普通SDR、零alpha、显式饱和、不同lowering及缓存重启；真实328渐变条纹仍独立验收，不以此共享反例指认其根因。

## 仅 alpha 采样的普通颜色边界（2026-10-21）

只消费 alpha、生成新 RGB 的普通 Program 不应被未读取的 RGB 表示拒绝。沿现有 TextureChannelAnalyzer 扩展 `alphaOnly`：所有活动引用须为直接采样的 `.a/.w`，任一 RGB、整向量、别名或 vertex 引用均不成立；纹理标签保持。准备期将此槽从 RGB 转换集合移入互斥的 `alphaInputSlots`，两编译器复验源码与实际绑定，身份、缓存与解码保真；旧工件缺字段按空集合处理，不补造证明。

launch 与实际 finalization 共用原颜色推导，alpha 槽复用已存在的 scalar-alpha 可用性规则：已解析颜色（含独立信号）与 RGBA data 可读；未知、缺失及 R/RG 存储不能把 Metal 缺省 alpha 冒充作者信号。只有 RGB 槽参与原 PMA 适配，输出仍由作者 Program 证明；局部失败沿原生命周期和输出 owner。

验收包括改名/采样坐标等价与 `.a/.w` 变体，混合 RGB、间接/vertex 读取、未知和无 alpha 的邻例，两 frontend、缓存身份/旧解码及实际 GPU alpha 保真。原始流体样本还须整图和真实画面受益，首拒消失不等于全部流体或光照已支持；独立样本确认原颜色合成未退步。

## HDR Bloom 参数与运行分支（2026-10-06）

**首断点与目标。** Earth 作者 `general.bloomhdrstrength` 绑定 HDR slider；实际 App 三次修改均被 live consumer 拒绝。本批基线仅解析标准 Bloom，不能把 HDR slider 改绑标准强度当作兼容。保留 `bloomhdrstrength/threshold/scatter/feather/iterations` 的作者数值，沿现有 Document → CameraDescriptor/BloomConfiguration → property Program → typed snapshot → 唯一 Bloom owner 进入实际 GPU。标准 Bloom 和 HDR Bloom 各自使用其参数；显示 SDR/EDR 仍由终端 owner 决定。

**实施约束。** 扩展现有 Bloom owner，不建立新 renderer、资源池或逐帧参数解析。HDR 明亮提取、扩散与合成使用自有实现；标准分支保留。有限 strength/threshold 不按猜测的编辑器 UI 范围截断；scatter/feather/iterations 的边界与缺省依公开合同及有界官方自有输入实验裁决，不从两个样本反推默认。强度为零不分配/编码，值变化消费下一帧快照，不重启场景；浮点颜色先参与 Bloom 再进入 SDR 裁剪。中间资源在现有预算内准备，编码失败不把半成品加回原图，下一帧可恢复；超预算局部保留安全原图。

**自有 GPU 方案。** 根据官方自有色块对照选择多尺度明亮提取、下采样和上采样重建，不消费第三方或私有 shader。超白提取保留浮点能量，feather 控制阈值下方的连续贡献，scatter 控制多尺度贡献，权重经有界均匀场和未参与推导的输入验证；中间凸组合、末端与强度/染色一起恢复公共权重，避免大扩散/小强度提前半精度截断，tint 与 strength 在加回原图时应用；不将定性行为相同表述为数值 parity。物理层数受源图可用 mip 尺寸约束，缓存以尺寸及实际层数匹配，prepare/encode 共用计划。所有中间 pass 成功后才进行一次 RGB additive combine，alpha 不变；非法非有限参数或工作量不成立时只跳过 Bloom。

**缺省判定。** 官方 2.8.0.42、640×256 自有灰阶块对照中，逐个省略 HDR 五字段与显式 strength=2、threshold=1、scatter=1.619、feather=0.1、iterations=8 逐像素相等；每项另有可区分替代输入。运行配置使用这组缺字段等价值，不宣称所有输入或未来版本的默认 parity。

**验收。** HDR 开关/profile隔离、五字段实际消费、strength/threshold方向、scatter半径、feather边界与iterations差分均需GPU输出和有界官方对照；原标准Bloom、raw history、零贡献、失败恢复与SDR白点回归。真实Earth验证slider多次更新同PID/窗口、实际合成及退出；未闭合的官方数值差异保留明确边界，不以属性接线冒称HDR完成。官方自有输入的 iterations=0/1 出现独立于 Bloom strength 的全图 transfer，当前未解释；作者值低于2只跳过可选 Bloom、保留原图，不猜 gamma。该边界及精确空间核继续研究，不随本批开放。当前实施/运行证据见[冻结记录](../../history/sdr-white-preservation-implementation-2026-10-06.md#hdr-bloom-参数与重建后继)。

## RF07-HISTORY：已实施的原始颜色与显示导出边界

暂停导出的异步失败与同步拒绝复用 Session 同一有限重试，职责与验收见 [D10 后继](frame-admission-retry-design.md#暂停导出的异步失败恢复2026-10-08)。

原始颜色与显示导出的隔离已实施，过程、失败门和验收边界统一见[冻结执行记录](../../history/rf07-persistent-color-output-implementation-2026-10-02.md)，不在本待实施设计复写。本次 HDR Bloom 必须保留其约束：作者有序合成写入未映射 raw；Bloom 只写 display scratch，终端显示结果不累积回 raw；每帧仍只有一次 layer traversal 和一个 compositor/present。

资源沿现役 allocation cache/residency pin 与 SubmissionCoordinator 管理，只有身份匹配且 GPU completed 才提升 raw。暂停导出不重跑 VM/模拟；resize/reset 后的新 raw epoch 先安全初始化。Bloom失败保留安全原图；线性surface显示映射失败保留旧帧，禁止导出未解码raw；资源/代际错误拒绝对应候选；不新增历史、完成回调或资源 owner。后续 HDR 改动继续通过 raw 多帧累积、paused resize、失败恢复和预算门。

<a id="clear-true-attachment-mapping"></a>

## 清底 HDR 终端 attachment 输入（2026-10-14，实施边界）

**目标与差距。** 当前清底 HDR 先在 drawable 完成作者合成、raw 反射快照及 Bloom，再复制全屏到 terminal scratch，由显示 owner 采样映射回 drawable。首批仅在没有上游 terminal 预算耦合的帧，消除这一次复制与 scratch需求，保持逐像素颜色、alpha、headroom、反射顺序、唯一提交/呈现和失败恢复；不改变作者算法、raw 累积、Bloom、资源预算或显示颜色空间，不按样本/路径挑选。平台依据为 Apple [MSL fragment color 输入](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf#page=146)、[GPU feature table](https://developer.apple.com/metal/feature-sets/) 的 programmable blending 和 [.load/.store](https://developer.apple.com/documentation/Metal/setting-load-and-store-actions)，不依赖 WE 私有实现。

**取舍。** 提前占用独立 full-screen scratch 即使自身准入成功，仍可能挤掉原本可工作的 group/source/capture/Bloom；现役终端能等读者退出后借 group scratch，graph preflight 不能证明全部强制资源已容纳。故不采用“reserve 成功即提前改写主目标”的方案。attachment 输入不增加全屏分配，仍沿原合成与 Bloom 写 drawable；仅把相同映射的输入从 distinct texture 改为当前 color attachment，不再给源域或资源生命周期另设 owner。clear=false 保留 RF07 distinct raw/display，包括 paused export、epoch/bootstrap 与完成提升。删除终端占位也可能让原被拒绝的shadow先获准、随后挤掉原能准备的source（预算100，G40/T40/Z50/source20）；该设计期静态反例已由真实pool复验，首批不改变这些耦合帧的route或资源次序，不用unused分配/虚拟ledger掩盖。

**准备与帧选择。** SceneDisplayMappingPostProcess 仍拥有必需的 texture-source PSO；仅在设备具备 Apple2+ programmable blending、配置 RGBA16Float 时，尝试准备可选 attachment PSO。缺函数或 PSO 失败只关闭该输入方式，必需 owner/颜色 transfer 不退出。实际帧 target 必须为同设备、同格式、2D、单采样 render target；帧还须clear=true、无persistence/main-target raw、既有hasShadowReceiver=false、原hasReflectionConsumers(...)返回false且sourceMaterials为空（固定runtime缺席也使原if-let支路不执行），保证原三处terminal保护分支均不执行。准备不进入普通帧；原graph admission不依赖此mode且main target不改，renderer在该准入后、首次optional/source/named-shadow预算前，复用已算的visible/plan/shadow/reflection事实冻结一次typed input，tail消费；原reflection需求惰性缓存一次供原两处共用，保耦合帧的短路；graph拒绝/取消不产生可消费attachment mode。不同设备/格式、累积或任一预算耦合帧保留原distinct输入与全部原保护/优先级，不事后改模式。clear=true合法的intent.snapshot不是persistence/main target，不因其出现撤换mode；当前有reflection需求的帧本就走legacy。

**数据流。** 原作者合成 → 原 raw 反射快照 → 原 Bloom → 同 drawable 的独立 fullscreen 映射 pass，attachment .load/.store、固定 blending 关闭，fragment 以 [[color(0)]] 读取已存值；不得把同目标同时绑定为 sampled texture。texture 与 attachment fragment 共用一个 RGB/headroom/alpha 数学 helper，沿现 vertex coverage、三角 strip 和唯一输出 owner，不复制曲线。符合条件的attachment帧中，原三处terminal保护已不执行，故其资源申请序列直到tail与旧路一致，只有tail的copy/scratch省去；graph、源、named capture、depth、反射与Bloom保护不减。不在source/shadow/reflection耦合帧删除占位；后继扩范围先由原公共资源owner设计优先级与全部预算反例，不把本设计批准扩大解释。

**失败与退出。** 先消费现有mainSourceCompleted或已完成paused raw事实；主clear/编码失败时所有终端输入都拒绝本帧，不让Bloom或映射读未定义主源，复用原失败原因与取消/恢复。这也修正旧清底texture输入的存量缺口，不增源完成owner。attachment encoder创建失败发生在任何写入前：SDR 保留已合成/Bloom的安全原图；extended-linear surface 拒绝本次输出、保旧帧，由现 Session/SubmissionCoordinator 管恢复。不得编码后迟申请未受保护的 legacy scratch。GPU 完成失败/取消、resize/reset、迟到事件仍归原完成与资源 owner；本方式不保 history、pin、另一路呈现或 retry。supported route 只执行一种输入，unsupported 准备事实仍是平台合同，不建立逐帧影子链。通过本批门后，将稳定输入合同移交输出架构并退役新增窄登记；其他 HDR/物理显示未定范围保留。

**验收与停止。** 实际 Metal/Swift owner 门覆盖非均匀且奇数尺寸完整像素、边缘/strip 对角、普通 SDR、超白、负值/非有限、alpha 和 headroom1/>1及非法值；以现 distinct 输出与已知普通色 oracle 比较，容差先冻结。验证 optional 函数/PSO 准备失败和真实 encoder 故障、线性映射失败不呈现、下一帧恢复；保 RF07 多帧/暂停/resize/reset/cancel、反射 raw 先于 Bloom/映射、原预算下group/source/capture能工作；用真实pool/owner复验预算100的顺序反例，耦合帧必须选择legacy且保持原source/shadow资格，不能以另一个功能改善抵销退化。测试输入改名、尺寸/颜色/表达变体及8位格式/累积帧、shadow/reflection/source非空等相邻不命中。做 Debug build 与优化诊断 App 三轮同条件 baseline/candidate/必要返回，对照实际 copy bytes、GPU、CPU/完成帧、驻留与首帧，不推定 .load 免费。另采真实样本后期完整画面、heldout 与普通产品入口；若像素/生命周期/预算退化或收益不稳定，撤回或重排，门禁和少画内容不算收益。实际硬件 EDR亮度、多屏及非 Apple device 的运行覆盖单列未验，不能以 PSO 准备或 PNG 关闭。

实施后仅接收少一次全屏复制及有界驻留收益；整帧CPU/GPU与启动未证稳定改善，负面轮次保留。稳定职责归[运行合同](../../architecture/runtime-architecture.md)，同条件测量、GPU/实际App、产品入口及未覆盖边界归[执行记录](../../history/hdr-attachment-mapping-convergence-2026-10-14.md)。物理EDR、多屏及其余HDR范围仍开放。

## fallback / route

平台不支持、headroom 回到 SDR、可选 metadata 不可用时走已验证 SDR 导出。颜色语义不明的输入保留现役 SDR route 并标记未兼容；不得默默 reinterpret。非法 format/range/generation 拒绝候选输出，保留安全旧帧。普通映射管线失败不破坏前序 graph current。

## 纠正门

- GPU 自有阶梯覆盖暗部、中灰、白点、超白和多彩高亮；检查有限、单调、颜色/alpha 边界与未开启 HDR 的输出守恒。容差在执行前冻结，不以 8 位截图判断浮点精度。
- 同一输入分别经过 SDR 与 EDR；检查实际 colorspace、format、屏幕 headroom、submission completion、terminal present 和 next-frame；EDR 设备不可用则 C/D 标为 not-run。
- 移屏、headroom改变、暂停恢复必须获得有效显示输出；allocation/encoder失败保留安全旧帧并能恢复，不导出错误颜色空间。
- 2684431262 只作为后续隔离回归输入；官方高亮对照与平台 EDR 验收分别记录，不能用一项代替另一项。

<a id="independent-signal-opaque-auxiliary"></a>
## 独立信号合成的不透明辅助输入（2026-10-21）

当前原299的combine已越过宿主数组，仍在共享颜色推导拒绝。源码表明normal producer输出alpha1，合成主颜色和独立信号以外的槽却一律要求data；先用真实prepared profile与2×2 typed反例核实，不能从normal名字或截图推资源标签。最小结果是在现有`resolveColor`中，仅独立信号合成及underlay合成的辅助槽允许现publication权威给出的`.opaque`，复用其既有恒等输入边界。保留原content、主color边界和发布身份，不把opaque重标data、不改作者运算或补法线算法；片元字面alpha1不能单独证明清区、顶点覆盖及过滤采样全域不透明，不在consumer另推或改标签。普通transfer、信号保留/直通及未知/PMA/straight辅助仍沿原严格合同。若实际首错不在此处，停止扩准入，先修最早producer事实。

验收复用原Program/Finalizer及GPU链，覆盖data/opaque辅助组合、重命名与等价表达、underlay、非平凡RGB和输出alpha；PMA/straight/unresolved辅助、错误主角色及陈旧/缺publication继续拒绝。再以原299整图和实际流体画面、未参与修法的邻例验收，音频/鼠标/时机差异不作颜色缺陷；首门消失不足以关闭样本。此修复不引入逐帧解析/编译、另一个资源或合成owner，不据功能门声明性能收益。稳定合同归现运行时颜色边界，剩余断点继续入现役队列。

**同一信号反馈原子的后继。** 当前颜色首门退出后，真实node15在首帧读到PMA种子而非独立信号；现反馈资格只允许update与terminal两位reader，新增的合法alpha-only中间consumer使整对信号表示证明退出。沿原`independentAlphaSignalTargetRepresentations`修闭合资格：仍须唯一update、透明零种子、同描述符唯一swap与terminal合成；附加reader仅可位于update与terminal之间、只读取scratch的alpha、无pair写入/其他pair绑定，并由现prepared channel/boundary逐variant证明。不得将所有RGBA或alpha1结果冒充signal，也不凭纹理名补标签。RGB/whole-vector/vertex读取、history旁读、额外writer、乱序/条件/swap冲突及缺variant证明继续拒；普通frame不重扫图，已有prepared表示沿原池/初始化/publication/历史与回滚链消费。先通过alpha-only/改名与上述相邻反例、首帧/下一帧种子和实际GPU，再回原299看画面；若另有首断点如实保留。

## 退役条件

每阶段完成行为门、颜色权威归入稳定架构、旧输出路径按 route 撤权后归档。未验证的 metadata profile 继续显式禁用，不随 SDR 验收自动解锁。


<a id="作者颜色跨-effect-连续性2026-10-08待实施"></a>

## 作者颜色跨 effect 连续性（2026-10-08）

设计结论：沿既有 Program、graph publication 与唯一 compositor 保留作者可观察的 straight RGB；中间普通 color overwrite 不再无条件预乘。第一卡生成颜色→连续effect→compositor已实施，证据与退出边界见[执行记录](../../history/authored-color-continuity-2026-10-09.md)；第二卡普通静态源上传/capture已接入同一合同，验收见同一执行记录的后继章节。同输入差异见[颜色证据](../../history/authored-color-continuity-2026-10-09.md#e-2026-10-08-transparent-color-continuity)。证据分别记录生成颜色、静态源像素与真实头冠后验；source小输入官方准入失败，不计同输入parity。PMA 输入零 alpha 已无可恢复颜色，不能通过改反预乘 helper 猜回 RGB。

**职责与取舍。** 在现有 Program/variant 准备阶段携带 slot 的实际 content/representation、作者数学输入域及输出存储表示；原 builder 统一实施 sampler/output 适配。straight 到 straight 为恒等，真实 PMA 到 straight 才反预乘，opaque 为恒等，data/independent signal 沿原 typed 合同。profile 继续证明数学与用途，不再分别猜普通 graph 的存储表示。保留扩展 RGB；alpha coverage clamp 与作者明确 UNorm clamp 独立保留。输入数学用途、允许的颜色表示及输出边界身份进入现有 request/cache，旧工件安全失效。源码已证passthrough可指定一个signal槽；同一uint的低8位标记实际PMA，高8位标记实际signal，只有被证明的指定槽可按signal保留raw输出，普通颜色仍走同一适配。nominal输出事实由variant一次发布供同effect后继pass准备，未知保持未知，不能替代帧事实；跨effect保持原并行编译。每帧由已验证 publication 填写掩码，只有对应 color 槽执行反预乘；这同时覆盖前序成功输出 straight 与局部失败保留 PMA 的切换，不枚举表示组合、不临帧编译。普通帧只消费准备布局与 typed 资源事实，不分析源码或生成 shader。

唯一 image compositor 按实际表示关联化一次，与 additive 的 source-alpha 权重正交；不得复用现有 `weightsSourceAlpha` 的不同语义来凑结果。attachment、publication、copy/swap/history 均传播真实表示；普通 color 不冒充 data。未迁移的直接 terminal replay 回到原 offscreen→compositor，不丢整层。拒绝隐藏 RGB companion、原图补色、GodRays 特判或另一个颜色 renderer：它们会重复采样、坐标、生命周期职责，且原图 RGB 不能代替作者前序计算结果。

**两张纵向工作卡。** 第一张贯通生成颜色→连续 ordinary effect→graph publication→唯一合成器；同一编译边界覆盖 generic 与 bounded，验证混合 straight/PMA 槽、data/signal 不变、HDR/SDR、alpha0/.5/1、图层 opacity、normal/additive 与 copy/swap，缓存重启及旧工件退出。不得只改 helper 或输出标签后交付。第二张将同一合同向前延伸到原 ordinary texture/source/capture，复用 `straightAlbedo` 和现有 uploader；source tint 与 opacity/coverage 按表示正确消费，验证 PNG/BC3 的零 alpha RGB、无 effect 直采、线性边缘、材质/图层颜色与 alpha、自定义 source material。真实样本用到的 named/history 必须同期闭环；确未覆盖的边界保留 typed 限制与队列，不删除安全校验充当支持。

**验收、失败与退出。** 两段官方输入要求三张 override 卡同亮，零 alpha 卡不得发黑；增加非白 RGB 和同 pass 两种表示反例。所有旧非零 alpha、PMA producer、data/signal 与现有输出门必须保持。最后回到原头冠及其他 alpha 扩大样本观察真实收益，未验不计受益。表示/身份不明时沿原最小 effect fail-soft，资源身份错误仍拒绝；不得用普通帧双执行或影子链回退。每张卡迁移完成即删除被替代的重复边界适配，存量 producer 的真实 PMA 表示不是第二执行链。达到完整纵向结果后再评估源链范围，不将本设计批准写成实现完成。


**Graph颜色用途协调修复设计（2026-10-12，实施前）。** 首批自有基线暴露直色数学与graph名义PMA传输用途冲突；沿原TextureSlotPurpose事实owner接纳已证straight颜色consumer读取合法graph颜色publication，实际straight/PMA表示仍由原Program输入转换消费，不改publication标签或另造转换。只修已证source/direct purpose冲突，mask、preserved、R/RG/data与未知颜色仍服从原typed selection/资源/ABI；不扩大所有graph为颜色。shape/source、候选ordinal/provenance、identity/epoch/generation与失败半径保持；选中graph与lower资产逐候选核用途，graph缺席不得继承不兼容lower数据。普通帧不解析或重建。先自有schema→fact→实际frame资源→Program/GPU红绿与alpha/availability分离矩阵，再完整271bool及真正样本/未参与修法样本画面；不得以旧baseline免责或删失败、放宽正确性条件。若旧fixture表示与现typed合同冲突，须先对照实际中间表示及生产末合成全部像素，再更正fixture。若alpha或其他回退仍有独立首错，沿原owner另核，不叠第二链路。

**源链第二卡实施边界（2026-10-09）。** 首错已定位为普通图片与静态Puppet atlas上传选择PMA，提前清掉零alpha RGB；3807668787的BC3原始透明texel含非零RGB，后续作者pass提高alpha，因而具有真实受益可能，原包后验灰边已恢复亮色，完整官方数值仍未证明。静态单图复用原`straightAlbedo`上传及Candidate的物理/映射UV合同；Puppet沿已有samplingCandidate保留采样元数据，不发布atlas为已完成图层，不新增专用纹理或旁路map。普通无effect直采在原compositor关联一次；graph源capture在原全quad写入保持straight，tint影响RGB，opacity影响alpha；PreparedCommand发布该次实际存储表示。真实PMA的动态文字/媒体、动画生产者及lit输出仍按其真实表示消费，不伪称已保留丢失RGB。自定义source Program沿同一边界输出straight。大尺寸原生BC不能丢Candidate再默认为PMA；必须验证原native格式与映射后沿同一采样入口接纳。验收必须含padded BC3、PNG透明彩色texel、线性采样边缘、无effect/alpha扩张、材质alpha/tint与Puppet原包；若物理尺寸改变导致UV或effect extent错配，在现有extent/UV owner修复，不补一层裁图。命名几何的真实PMA栅格化边界暂不改变，涉及它的隐藏RGB能力不计完成。
