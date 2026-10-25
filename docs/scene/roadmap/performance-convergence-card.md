<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

本卡维护CPU/GPU、内存、启动与能耗专项。全局按[兼容路线](scene-compatibility-roadmap.md)先处理合成/正常播放问题，再选择有证成本；属性热更新接线归[属性卡](properties-panel-card.md)，开放问题归[队列](scene-open-breakpoint-queue.md)。

**执行顺序。** 当前Scene自主选题服从[兼容路线](scene-compatibility-roadmap.md)与[断点队列](scene-open-breakpoint-queue.md)；本卡维护性能专项选序与验收。原24项和D阶段内部顺序、状态归[Apple silicon全App方案](../../development/apple-silicon-optimization-plan.md)，不扩成后续Scene工作的前置。保留低复杂度可靠局部收益，整体比例未知如实注明；正式整体收益按下述同条件门验收。旧E/AS不作前置，[顶层设计](engine-refactor-program.md)只规定边界。

1. 整体 CPU/GPU 先联合归因，再联查内存与启动：采样每帧求值/分配、序列化/诊断、主线程阻塞与后台争用，再查压缩纹理展开、解码峰值、重复解析/上传。优先比较 VM/帧桥重复工作、调度 attempt 与实际最贵 GPU pass/shader；局部准备已降而整进程未降时重新选题，不惯性继续微调。温度高、低频与GPU满载须绑定实际工作，不能凭频率或旧样本帧预算判瓶颈。
2. GPU：按真实pass/shader成本选题，持续筛高级混合复制及满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：冷暖启动专项的实施、取舍和未覆盖范围已归[完成记录](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)；本卡继续唯一维护统计与非目标门，稳定行为按[启动合同](../architecture/scene-launch-responsiveness-contract.md)。以实际产品阶段区分解析、编译、资源与呈现，保持首帧完整和失败回退；旧 STOP 不因专项结算自动重开。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**当前可行动余项。** 不以数十次局部提交判断整个引擎到瓶颈；先确认普通优化配置仍有的可避免工作及唯一owner，再开实现。没有新可行动信号就回兼容队列，不重复旧消融。10-17原296的646次play已被现emit分支挡在完整population事务外；剩余轻量校验/查找没有CPU成本测量，不据调用数新增缓存或抹掉finished emitter rearm语义。限定资格随[Rope批证据](../capabilities/runtime-evidence-current.md#rope-whole-source-20261017)保存。

- **372水面调度：本轮停止改动**。去掉执行观察器仍见未优化Debug隔帧提交，有界时间线已分清history在途与MainActor完成可见性；但同源码优化Debug普通窗达到目标帧率，未证明当前产品需重做timer/clock或完整Program缓存。具体配置、原数与限制归[资格记录](../capabilities/runtime-evidence-current.md#water-cadence-qualification-20261021)；有新的优化产品成本证据才重开。
- **多路视频实际消费需求**：同App输入消融已支持优先核无消费解码，但删除输入不计性能收益；沿[待实施设计](../capabilities/material-video-assets.md#video-consumer-demand)保逻辑clock、脚本/EOF与跨屏，只在可证明范围接原registry/backend。普通优化配置及实际产品收益仍待验，[资格](../capabilities/runtime-evidence-current.md#video-publication-demand-20261021)不代替实施。
- **337多视频提取：STOP，产品已撤**。保原clock/EOF的无consumer少提取原型，两个30s预热+61.5s稳态配对的footprint分别+69.38%/+29.59%，触原非目标门；Metal分配采样下降不能抵消。第三对未跑，不认3+3/整体收益，不重做同型包装验收；后继先取得不同backend消费或可见供帧机制证据。原秒级空档未闭，[身份/原数与撤回](../capabilities/runtime-evidence-current.md#video-publication-demand-20261021)。

- **整体CPU/GPU**：[普通Release归因](../history/native-cpu-allocation-screen-2026-10-15.md#ordinary-release-cpu-attribution)仍显示材质图准备/粒子成本，尚未证明可省部分。普通image片元高成本保留，但[GPU短筛](../history/gpu-cost-screening-2026-10-14.md)的附件读取、modulation/sampler及exact-copy未通过继续门；源码归因受工具上限阻塞时不盲改shader。 [stage计时资格](../history/gpu-stage-timestamp-qualification-2026-10-15.md)与[TEX存储资格](../history/static-tex-storage-screen-2026-10-15.md)保原工具/格式边界，不据旧清单开新实现。新增优化必须给实际consumer和普通进程分母。
- **相机动画期目标尺寸切换**：10-20原374的6s origin/zoom使693/261在857/858间切换；四run只读归因仅见两种shared pair复用、Program不变，`allocationGeneration`不是Metal分配计数，现resolved-size memo已在。当前不立优化/不跑3+3；若有新成本信号，先区分实际texture factory与table/lease重建，再决定实施，不能重复加同类缓存。资格收据随[字体批报告](../capabilities/runtime-evidence-current.md#image-font-script-state-20261020)保存，无整体CPU/GPU收益或泄漏结论。
- **关闭stage的透传复制**：[10-16资格](../history/gpu-cost-screening-2026-10-14.md#inactive-stage-copy-screen)已将289短Debug窗的7 copy/frame闭合到真实activation caller；最窄连续两尾段的独立GPU增量为0.568375ms，尚无App收益。直接删命令会伪造中间publication，先评估原executor内真实alias/member/完成语义的改动半径；不为两copy微优化新增owner或盲目重排pair，五次source capture未证冗余。当前先推进画面能力，不重跑旧capture cache。 357:210已由[10-18二维fallback后继](../capabilities/runtime-evidence-current.md#shader-vec2-authored-fallback-20261018)恢复真实Program，退出“launch永久visual-failure复制”候选；旧搬运观察只作历史，不能继续假设当前整链永久identity。
- **批内audio factor：335不命中，停止实施**。10-16同实际输入的8粒子层/9递归资源/38 initializer均无audio声明；原parser→AudioResponsePlan返回nil，initializer不会进重复band求值，不能解释该短DEBUG窗的CPU线索。无需为此新build/profile/cache；其他已启用consumer须另有普通优化热栈才重开。位置/time/RNG的turbulence仍逐粒子，嵌套stage与event/帧p95不相加。资格：`.artifacts/tmp/cpu-frame-preparation-qualification-20261016/335-audio-consumer-followup.json`（SHA `0ffa7df181279a60d3822d7bd5412af5583abcdd2393dca5e884a6eb891f2021`）。
- **主pass空重开：未取得实施资格**。10-16只读caller可见`.load/store`空pass机会，但2890473419实际timestamp中6个main均有draw；唯一追加的有成员组候选3226487183在既有冷启动watchdog内未ready，尚未触达目标。产品未改、优化构建及收益A/B未启动；不把静态可省、无draw时间戳或超时写成GPU收益/生命周期缺陷。只有新实际consumer证据再开。限期计数/失败收据：`.artifacts/scene-evidence/runs/main-pass-reopen-screen-20261016/`。
- **内存/退场**：[轻重切换](../history/scene-switch-residency-qualification-2026-10-15.md)观察返回轻场景footprint上移、GPU/目标池回平台，已缩到purgeable分配，持有owner未定；先取得有效分配来源，不重复无caller的整轮切换。逐session drain/pin/总账、最终pin与长期cache增长边界保留，不能把allocator驻留写泄漏或优化收益。
- **启动**：[10-18链接产物复用](../history/linked-stage-startup-convergence-2026-10-18.md)窄接受五对优化Debug产品入口冷启动中位4869→4331ms，Program字节一致；暖启动无确定收益，Web短筛未改产品。原366未见可见结果；[类型名lookup](../history/shader-value-type-recognition-2026-10-16.md)仅局部收益，[原322同次栈](../capabilities/runtime-evidence-current.md#shader-float2-consumer-width-20261017)仍不足重开旧声明扫描。cold/warm分阶段按实际入口验收，保base-image/natural-size依赖，增timeout不算优化。

**10-18工具链资格短筛：STOP。** 同源真实resolve/严格验签与双version，三进程各11次全部成功，但总计时噪声306.98%超过事前5%门；未剔首次慢探针，三个真实normalized pair的工具子链0执行。后10次的乐观可省上界中位103.845ms不是实测收益，不据此加缓存或认App启动收益。原数、固定输入、清理与独审仅保本机收据 `../../../.artifacts/tmp/shader-toolchain-qualification-cost-20261018/summary.json`；本方向无产品修改，不重复旧筛或放宽阈值，先回可执行能力断点。

<a id="movement-access-screen-20261023"></a>

**10-23 Movement访问短筛：停止，产品已撤。** 原304五root的`-O`纯CPU探针未见实质事件导出热点，birth/death仍有短命渲染消费者。薄参数三对CPU中位降5.402%未越双噪声门；单次Array借用降20.247%/升11.882%/降17.589%，方向不一致，均未剔点、补跑或放宽。30个状态字摘要组合相同、借用候选的既有vortex门通过，不代完整FrameSnapshot、实际画面或收益。产品及冻结源码已恢复，0新App/0GPU，无播放链CPU/GPU/能耗收益结论。原栈、身份、各六run与撤回归`.artifacts/scene-evidence/runs/particle-movement-access-stop-20261023/`，普通14天；后继先取完整播放链当前成本，不重复同型微筛。

<a id="keyed-sampling-20261023"></a>

**10-23等值keyed粒子采样：窄保留。** 有限等值范围沿原标量算术直接取值，省去无后续状态的局部hash；出生共享RNG、非等值/非有限路径不变。用户明确允许可靠小收益后，原3%早停门撤销；新HEAD优化Debug隔离Host、原199静音/30FPS、30s预热+≥60s稳态三对AB/BA/AB，每完成帧进程CPU下降1.667%/1.927%/2.467%，中位1.927%，基线噪声0.961%，仅略过两倍噪声。非目标中位未越原门，不认GPU/内存收益；四舍入模式位值/共享RNG门及独立311非等值phase实际输出、正常stop/排空成立。仅本条件小幅CPU改善；普通Service/daemon、Release、能耗与全样本未验。身份、原数、协议覆盖与旧STOP归本机限期包 `.artifacts/scene-evidence/runs/particle-keyed-sampling-20261023/`，首对原始图/CLI归其前驱 `particle-keyed-sampling-stop-20261023`；不扩为正式10%验收。

**10-19粒子phase cosine缓存筛选：STOP。** 原343的Debug instrumented `particle-advance`约15ms仅为局部阶段，不能当整进程CPU或Release成本。隔离副本在原phase cache存Double baseline，真实Runtime→Simulator→instance链按5000+75星、`-O/WMO`前后各编译一次，预登记六进程三组AB的优化链计时窗CPU中位**增加0.979%**，无稳定收益，未实施产品。实际cache值stride96→128，5000项多156.25KiB值载荷；不是RAM footprint，字典容量/开销未据此推算。所测数值/RNG/快照取消恢复指纹一致仅限已覆盖字段，有限筛选结束不扩试；最小收据 `../../../.artifacts/tmp/343-model-lighting-20261019/particle-phase-cache-stop.json`。

**10-19模型场景深度域：仅资源需求观察。** 正确性重构退休隐式私有隔离及其专用几何hash。原343同3024×1964/30FPS的单次Debug对照，目标池采样峰331659520→307902976B，差23756544B恰一张depth32；GPU allocated812515328→787873792B，但进程footprint峰1075135904→1131480480B。只有一次诊断短窗、截图请求有superseded/teardown，非三对普通稳态，不认整体内存、CPU/GPU、启动或能耗稳定收益，不因删除hash推算耗时。必要原数与后继边界归[有界记录](../history/model-scene-depth-domain-2026-10-19.md)，无新热栈/普通成本信号时继续画面队列。

**已接受结果只作前驱。** [BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX](../history/tex-request-local-convergence-2026-10-13.md)、[区域复制](../history/color-blend-region-convergence-2026-10-13.md)、[属性异常恢复](../history/property-callback-recovery-2026-10-14.md)、[resident查询](../history/graph-residency-query-convergence-2026-10-14.md)、[完成结果缓存](../history/shader-completed-cache-retention-2026-10-15.md)的实际收益和非目标回退按各自冻结记录，不扩成整体GPU/能耗或全专项完成。面板准备/列表成本归属性卡，正确性修复不计性能。

<a id="sampler-seed-preparation"></a>

[Sampler seed准备](../history/sampler-seed-preparation-convergence-2026-10-15.md)只窄接受Debug暖重返启动；内存后继类别未定，统一并入上述生命周期余项，不重跑五对。variant analysis Set wire只保正确性，短筛未达继续门。

**已停止的方向。** [C codegen](../history/script-c-codegen-ablation-2026-10-14.md)、[working-view](../history/graph-residency-query-convergence-2026-10-14.md#后继working-view-查询短筛产品候选已撤回)、[粒子排序](../history/particle-world-depth-2026-10-11.md#后继粒子排序成本短筛2026-10-14)、[capture缓存/双层分段](../history/gpu-cost-screening-2026-10-14.md)、[shader identity/ready request](../history/shader-identity-hash-screen-2026-10-14.md)、[属性JSON复用](../history/property-callback-recovery-2026-10-14.md#prepared-property-json)、[声明准备](../history/shader-value-type-recognition-2026-10-16.md#declaration-preparation-screen)、[variant分析](../history/variant-analysis-cache-wire-correction-2026-10-15.md)、[MDL复核/world](../history/native-cpu-allocation-screen-2026-10-15.md#mdl-validation-followup-20261019)保原STOP；不重跑旧campaign，新实际consumer及成本证据才能立题。CPU尺寸对象缓存会改变JS引用identity，未实施。 10-18空journal 16KiB清零的实际C API微筛仅有配对中位5.135µs/frame-equivalent，低于事前0.1ms继续门，NO-GO；32owner×1000合成工作不外推App/RAM收益，未改产品，最小结果随[模型资格包](../capabilities/runtime-evidence-current.md#model-reflection-prototype-20261018)保存。[HDR attachment](../history/hdr-attachment-mapping-convergence-2026-10-14.md)与[帧纹理快照](../history/frame-texture-snapshot-convergence-2026-10-14.md)只保原局部/驻留证据，不宣称整体CPU收益。

<a id="prepared-material-frame-payload"></a>

[材质帧载荷](../history/compiled-variant-frame-program-convergence-2026-10-13.md#material-frame-payload-screen)未达App继续门，原型已撤，设计登记退役，不重新列为待实施。

**10-23 prepared帧输入职责整理：不计性能。** 几何与shader共用原Program数值核，实际值定义退出mutable Catalog；只修依赖方向，未加policy/cache、未省数值检查。CPU/Debug与交叉独审通过，原332及独立311实际回归/排空保持；[唯一设计](batch2/terminal-material-chain-design.md#prepared-frame-uniform-query)。后继HostSchema/帧重复须先取当前整链成本；不重开已撤帧载荷原型、不以函数迁移推算收益。

**工具边界。** 保唯一CLI、语义parser与验收入口、严格默认与未舍入ratio；[旧monolith已退役](../history/benchmark-responsibility-convergence-2026-10-13.md)，不另造wrapper/算法。

**筛选与正式验收。** 先用最近门、采样和短实验筛选；短实验不称性能验收，连续两次有区分力实验无收益则停该方向。目标预先锁定整进程 CPU、GPU、内存、启动或明确交互成本，局部阶段数字单列。

正式比较固定机器/OS/热状态、输入/属性/音频、尺寸/FPS、App/优化等级/签名/工具/诊断；至少三份有效基线及三份候选，交替顺序检查时段漂移。稳态每轮30s预热后≥60s；冷/暖cache分开，启动各至少五次，不用五次声称启动尾部分位数。身份、条件与有效性一致的现存基线可复用，重测用于失效或漂移；profiler、详细截图和语义取证另开窗口。普通产品与优化诊断配置分别报告，不能外推为正式Release。

本卡承接原AS1的测量准入，后续阈值变更须在实验前有依据并记录：目标成本配对降幅中位数≥10%且超过基线噪声两倍；主要计时噪声>5%先排干扰，不放宽阈值。非目标CPU/GPU尾部、呈现、首帧与峰值内存不恶化超过max(5%,两倍该项噪声)，并满足预先冻结的设备/内容绝对预算。仅局部收益或结构消融如实登记，不能计整体效率完成；温度/功耗未测则不认领。基线噪声为每轮指标相对其中位数的最大偏差比例；中位数为零用预登记绝对误差门。保留专项原始基线及直接前驱，防止多批累计回退；分位数来自逐帧分布，不由累计均值或嵌套阶段相加推算。

绝对预算按批准设备/内容冻结：连续呈现30/60FPS对应33.33/16.67ms，CPU/GPU/present分别判断；present超过1.5倍目标间隔比例默认≤1%，暂停/按需/切换/缺drawable故障另列，不把既有不达标内容写成全局达标。专项最终稳定性验收至少30分钟稳态及20次轻重切换/resize，覆盖暂停/恢复、错误资源、取消/替换、停止与资源退出；旧代次pin最终归零、owner/cache无持续增长。最低设备、多屏及正式Release缺失时明确未验；这些阶段门不在每个局部修改重复执行。

量CPU时间率与每完成帧成本、调用/分配、内存峰值/稳态、GPU工作/copy及首帧，分冷暖cache与驻留。performance-only矩阵无执行承诺，观察unavailable，不代严格验收；单次ready/FPS不作收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；旧架构可重构；重要变更先落顶层设计，写数据流、owner迁移/退出、失败与验收。按公共语义扩展prepared/typed consumer分支，保唯一链路；局部修复直接实施。每轮实现、验证、独审、提交，汇报收益、边界及下一轮；完成证据归history。用户结束专项或已证成本与长期切换验收完成后退役。
