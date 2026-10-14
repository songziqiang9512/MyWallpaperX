<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

本卡与[属性卡](properties-panel-card.md)持续收敛CPU/GPU、内存、启动与交互成本；视觉问题归[队列](scene-open-breakpoint-queue.md)。

**执行顺序。** 本卡是引擎性能选序与验收的唯一工作卡；[顶层设计](engine-refactor-program.md)规定边界，旧 E/AS 编号不另设前置阶段。

1. 整体 CPU/GPU 先联合归因，再联查内存与启动：采样每帧求值/分配、序列化/诊断、主线程阻塞与后台争用，再查压缩纹理展开、解码峰值、重复解析/上传。优先比较 VM/帧桥重复工作、调度 attempt 与实际最贵 GPU pass/shader；局部准备已降而整进程未降时重新选题，不惯性继续微调。温度高、低频与GPU满载须绑定实际工作，不能凭频率或旧样本帧预算判瓶颈。
2. GPU：先高级混合的全屏复制，再满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：以现有阶段计时区分解析、准备、编译、资源、首draw/呈现；缩小必须提前完成的范围，保持依赖、首帧完整与失败回退。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**当前进度与下一轮。** [BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX](../history/tex-request-local-convergence-2026-10-13.md)、[区域复制](../history/color-blend-region-convergence-2026-10-13.md)闭合所列成本；[材质准备](../history/compiled-variant-frame-program-convergence-2026-10-13.md)未证CPU收益，[RegExp](../history/native-regexp-capture-2026-10-13.md)修时钟不计性能。[属性候选](../history/property-candidate-evaluation-convergence-2026-10-13.md)、[条件准备](../history/property-condition-reachability-2026-10-13.md)、[窗口复用](../history/property-preparation-convergence-2026-10-13.md)、[原生列表](../history/native-property-list-convergence-2026-10-14.md)证局部/暖/面板CPU，不扩为引擎能耗。[C消融](../history/script-c-codegen-ablation-2026-10-14.md)未稳定已撤。[HDR attachment](../history/hdr-attachment-mapping-convergence-2026-10-14.md)仅复制/驻留已证；时序波动与输入消融见记录。[帧纹理快照](../history/frame-texture-snapshot-convergence-2026-10-14.md)证实真实帧准备局部CPU下降，整进程CPU时间率未降，密集覆盖负例保留；[属性异常恢复](../history/property-callback-recovery-2026-10-14.md)证实三轮云层编辑窗App+daemon CPU下降69.535%，不扩为稳态/能耗。[Vector后继](../history/property-callback-recovery-2026-10-14.md#后继无属性回调的-vector-owner-休眠)修复无属性回调owner被revision唤醒，未证整体性能。下一轮优先检查graph/resource准备中重复resident扫描及属性回调失败后的重复准备；1128有真实回调，非有限origin仍开放。GPU合批须先证明物理纹理不别名，不能以新增复制/驻留换表面pass下降；base-image/natural-size、MDL双阶段、分阶段首帧、长期轻重切换待验。旧E/AS尚未闭合的上传并发/峰值、聚合预算、静态按需/多屏背压、冷暖编译、媒体/音频消费者开销与最低设备/长稳恢复仍属条件候选；按实际热点启用，不因归档完成，不逐卡空转。shader fallback退役仍须当前合法输入与回退审计，未证不可删。

**工具边界。** 保唯一CLI、语义parser与验收入口、严格默认与未舍入ratio；[旧monolith已退役](../history/benchmark-responsibility-convergence-2026-10-13.md)，不另造wrapper/算法。

**筛选与正式验收。** 先用最近门、采样和短实验筛选；短实验不称性能验收，连续两次有区分力实验无收益则停该方向。目标预先锁定整进程 CPU、GPU、内存、启动或明确交互成本，局部阶段数字单列。

正式比较固定机器/OS/热状态、输入/属性/音频、尺寸/FPS、App/优化等级/签名/工具/诊断；至少三份有效基线及三份候选，交替顺序检查时段漂移。稳态每轮30s预热后≥60s；冷/暖cache分开，启动各至少五次，不用五次声称启动尾部分位数。身份、条件与有效性一致的现存基线可复用，重测用于失效或漂移；profiler、详细截图和语义取证另开窗口。普通产品与优化诊断配置分别报告，不能外推为正式Release。

本卡承接原AS1的测量准入，后续阈值变更须在实验前有依据并记录：目标成本配对降幅中位数≥10%且超过基线噪声两倍；主要计时噪声>5%先排干扰，不放宽阈值。非目标CPU/GPU尾部、呈现、首帧与峰值内存不恶化超过max(5%,两倍该项噪声)，并满足预先冻结的设备/内容绝对预算。仅局部收益或结构消融如实登记，不能计整体效率完成；温度/功耗未测则不认领。基线噪声为每轮指标相对其中位数的最大偏差比例；中位数为零用预登记绝对误差门。保留专项原始基线及直接前驱，防止多批累计回退；分位数来自逐帧分布，不由累计均值或嵌套阶段相加推算。

绝对预算按批准设备/内容冻结：连续呈现30/60FPS对应33.33/16.67ms，CPU/GPU/present分别判断；present超过1.5倍目标间隔比例默认≤1%，暂停/按需/切换/缺drawable故障另列，不把既有不达标内容写成全局达标。专项最终稳定性验收至少30分钟稳态及20次轻重切换/resize，覆盖暂停/恢复、错误资源、取消/替换、停止与资源退出；旧代次pin最终归零、owner/cache无持续增长。最低设备、多屏及正式Release缺失时明确未验；这些阶段门不在每个局部修改重复执行。

量CPU时间率与每完成帧成本、调用/分配、内存峰值/稳态、GPU工作/copy及首帧，分冷暖cache与驻留。performance-only矩阵无执行承诺，观察unavailable，不代严格验收；单次ready/FPS不作收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；旧架构可重构；重要变更先落顶层设计，写数据流、owner迁移/退出、失败与验收。按公共语义扩展prepared/typed consumer分支，保唯一链路；局部修复直接实施。每轮实现、验证、独审、提交，汇报收益、边界及下一轮；完成证据归history。用户结束专项或已证成本与长期切换验收完成后退役。
