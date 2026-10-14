<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

本卡与[属性卡](properties-panel-card.md)持续收敛CPU/GPU、内存、启动与交互成本；视觉问题归[队列](scene-open-breakpoint-queue.md)。

**执行顺序。** 本卡是引擎性能选序与验收的唯一工作卡；[顶层设计](engine-refactor-program.md)规定边界，旧 E/AS 编号不另设前置阶段。

1. 整体 CPU/GPU 先联合归因，再联查内存与启动：采样每帧求值/分配、序列化/诊断、主线程阻塞与后台争用，再查压缩纹理展开、解码峰值、重复解析/上传。优先比较 VM/帧桥重复工作、调度 attempt 与实际最贵 GPU pass/shader；局部准备已降而整进程未降时重新选题，不惯性继续微调。温度高、低频与GPU满载须绑定实际工作，不能凭频率或旧样本帧预算判瓶颈。
2. GPU：按真实pass/shader成本选题，持续筛高级混合复制及满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：以现有阶段计时区分解析、准备、编译、资源、首draw/呈现；缩小必须提前完成的范围，保持依赖、首帧完整与失败回退。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**当前进度与下一轮。** [BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX](../history/tex-request-local-convergence-2026-10-13.md)、[区域复制](../history/color-blend-region-convergence-2026-10-13.md)已闭合各记录所列成本。[属性异常恢复](../history/property-callback-recovery-2026-10-14.md)三轮编辑窗App+daemon CPU下降69.535%；[resident查询](../history/graph-residency-query-convergence-2026-10-14.md)固定三配对优化诊断单surface整体CPU中位下降11.055%，保呈现异常、footprint上移及返回基线敏感性。两者均不扩为GPU/能耗。

[属性候选](../history/property-candidate-evaluation-convergence-2026-10-13.md)、[条件准备](../history/property-condition-reachability-2026-10-13.md)、[窗口复用](../history/property-preparation-convergence-2026-10-13.md)、[原生列表](../history/native-property-list-convergence-2026-10-14.md)证局部/暖/面板CPU；[HDR attachment](../history/hdr-attachment-mapping-convergence-2026-10-14.md)仅证复制/驻留；[帧纹理快照](../history/frame-texture-snapshot-convergence-2026-10-14.md)、[材质/Encoder准备](../history/compiled-variant-frame-program-convergence-2026-10-13.md)局部下降未证App整体收益，不扩测。[RegExp](../history/native-regexp-capture-2026-10-13.md)、Vector后继及[换图反馈](../history/property-texture-feedback-2026-10-14.md)是正确性/交互修复，未计性能；其未覆盖运行边界留对应记录与属性卡。

已停止无收益候选：[C消融](../history/script-c-codegen-ablation-2026-10-14.md)、[working-view](../history/graph-residency-query-convergence-2026-10-14.md#后继working-view-查询短筛产品候选已撤回)、[粒子排序](../history/particle-world-depth-2026-10-11.md#后继粒子排序成本短筛2026-10-14)和[capture缓存](../history/gpu-cost-screening-2026-10-14.md#后继capture结果缓存短筛撤回)已撤回；[shader identity](../history/shader-identity-hash-screen-2026-10-14.md)与[属性JSON复用](../history/property-callback-recovery-2026-10-14.md#prepared-property-json)App短筛未达继续门。[GPU筛选](../history/gpu-cost-screening-2026-10-14.md)保普通image片元高成本事实，附件读取/modulation/sampler均未通过继续门，exact-copy资格33/33拒绝；不再盲筛shader或同类缓存。CPU尺寸对象缓存改变JS引用身份，未实施。

**下一批**：[原生CPU/分配归因](../history/native-cpu-allocation-screen-2026-10-15.md)已定位daemon、快照/graph与root物化；root两版及[去graph临时表](../history/native-cpu-allocation-screen-2026-10-15.md#graph-intermediate-screen)未达继续门，均撤回、不进App。[snapshot构造](../history/frame-texture-snapshot-convergence-2026-10-14.md#snapshot-construction-direct-entry)已证非空局部CPU降26.34–60.60%，保lookup噪声与App整体未测边界，不继续同类排序/容器微调。[脚本Color](../history/property-callback-recovery-2026-10-14.md#color-script-input-live)已闭真实改色误重建，未计CPU百分比。[原生GPU资格](../history/gpu-cost-screening-2026-10-14.md#native-gpu-limiter-qualification)仅取到进程阶段累计，未取得limiter/逐shader成本，停止重录/全量导出；普通image片元成本仍开放。下一轮先设计公开stage timestamp的一帧pass归因：M4 probe仅证明atStageBoundary支持，尚无采样数据；不重做全量导出，属性缺口沿属性卡并行选题。

[完成结果缓存](../history/shader-completed-cache-retention-2026-10-15.md)已实现97MiB权重子限/Flight共享，真实owner三轮压力footprint下降85.428740%，保暖重访与轻场景资源回落；App CPU/首帧波动、最终pin与长稳未验，不计整体收益。[ready-request波次](../history/shader-identity-hash-screen-2026-10-14.md#ready-request-screen)、[双层分段](../history/gpu-cost-screening-2026-10-14.md#ordered-pair-segmentation-screen)无收益已撤回；[源码归因资格](../history/gpu-cost-screening-2026-10-14.md#source-cost-qualification)遇原内容Xcode Lite上限，停止重抓/重编及盲改shader。帧内purpose检查各有职责，不凭低覆盖旧暖栈写cache原型。

嵌套String与未绑定Bool已闭实际热编辑，不计CPU百分比。base-image/natural-size、MDL双阶段、分阶段首帧、长期切换仍待验；旧E/AS上传峰值、聚合预算、静态按需/多屏背压、冷暖编译、媒体/音频和最低设备边界按实际热点启用。shader fallback在合法输入与回退审计前不得退役。

<a id="prepared-material-frame-payload"></a>

**材质帧载荷候选已撤回。** [完整局部与App短筛](../history/compiled-variant-frame-program-convergence-2026-10-13.md#material-frame-payload-screen)证局部准备下降，但App单对CPU仅降4.14%、GPU p95升7.87%；未达继续门，不扩测、不认领稳定收益。原型和失败证据保留，设计窄登记退役。

**工具边界。** 保唯一CLI、语义parser与验收入口、严格默认与未舍入ratio；[旧monolith已退役](../history/benchmark-responsibility-convergence-2026-10-13.md)，不另造wrapper/算法。

**筛选与正式验收。** 先用最近门、采样和短实验筛选；短实验不称性能验收，连续两次有区分力实验无收益则停该方向。目标预先锁定整进程 CPU、GPU、内存、启动或明确交互成本，局部阶段数字单列。

正式比较固定机器/OS/热状态、输入/属性/音频、尺寸/FPS、App/优化等级/签名/工具/诊断；至少三份有效基线及三份候选，交替顺序检查时段漂移。稳态每轮30s预热后≥60s；冷/暖cache分开，启动各至少五次，不用五次声称启动尾部分位数。身份、条件与有效性一致的现存基线可复用，重测用于失效或漂移；profiler、详细截图和语义取证另开窗口。普通产品与优化诊断配置分别报告，不能外推为正式Release。

本卡承接原AS1的测量准入，后续阈值变更须在实验前有依据并记录：目标成本配对降幅中位数≥10%且超过基线噪声两倍；主要计时噪声>5%先排干扰，不放宽阈值。非目标CPU/GPU尾部、呈现、首帧与峰值内存不恶化超过max(5%,两倍该项噪声)，并满足预先冻结的设备/内容绝对预算。仅局部收益或结构消融如实登记，不能计整体效率完成；温度/功耗未测则不认领。基线噪声为每轮指标相对其中位数的最大偏差比例；中位数为零用预登记绝对误差门。保留专项原始基线及直接前驱，防止多批累计回退；分位数来自逐帧分布，不由累计均值或嵌套阶段相加推算。

绝对预算按批准设备/内容冻结：连续呈现30/60FPS对应33.33/16.67ms，CPU/GPU/present分别判断；present超过1.5倍目标间隔比例默认≤1%，暂停/按需/切换/缺drawable故障另列，不把既有不达标内容写成全局达标。专项最终稳定性验收至少30分钟稳态及20次轻重切换/resize，覆盖暂停/恢复、错误资源、取消/替换、停止与资源退出；旧代次pin最终归零、owner/cache无持续增长。最低设备、多屏及正式Release缺失时明确未验；这些阶段门不在每个局部修改重复执行。

量CPU时间率与每完成帧成本、调用/分配、内存峰值/稳态、GPU工作/copy及首帧，分冷暖cache与驻留。performance-only矩阵无执行承诺，观察unavailable，不代严格验收；单次ready/FPS不作收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；旧架构可重构；重要变更先落顶层设计，写数据流、owner迁移/退出、失败与验收。按公共语义扩展prepared/typed consumer分支，保唯一链路；局部修复直接实施。每轮实现、验证、独审、提交，汇报收益、边界及下一轮；完成证据归history。用户结束专项或已证成本与长期切换验收完成后退役。
