<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

用户2026-10-12要求：当前遮罩兼容批收尾后，优先推进本卡及[属性面板卡](properties-panel-card.md)。目标是降低运行成本和等待时间，保持画面、交互与能力；视觉断点归[队列](scene-open-breakpoint-queue.md)，兼容目标不变。

**执行顺序。**

1. 内存与启动一起查：压缩纹理展开、解码峰值、同内容重复解析/上传与资源生命周期。
2. GPU：先高级混合的全屏复制，再满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：以现有阶段计时区分解析、准备、编译、资源、首draw/呈现；缩小必须提前完成的范围，保持依赖、首帧完整与失败回退。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**首轮入口与最小交付。** 先查现有texture loader/uploader、decode/store/budget及launch资源准备；找一个已测得的重复解析、无效展开或重复资源点，在唯一现有owner修复。先记录当前事实及2–3个可选点的用户收益/风险，选择最短可验证项；不为计数扩大抽象层、cache或新诊断框架。

**当前进度与下一轮。** 复用结果归[BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX证据](../history/tex-request-local-convergence-2026-10-13.md)。专项约20%（阶段估计），不外推App峰值/首帧。原包开场经[有界host修复](../history/scenescript-host-heap-admission-2026-10-13.md)闭合；旧脚本停用测量不作基线。下一轮补HDR/reflection复制计量，再量普通高级混合quad局部复制；复用既有投影和snapshot，custom geometry/折射保全屏。TEX外层base-image/natural-size、MDL双阶段、首帧范围、长期切换待量；MDL保完整校验，延迟日志不算重复build。属性typed更新/重建归[属性卡](properties-panel-card.md)。

**比较与验收。** 每次修改前取得同样本、作者属性、音频输入、窗口/输出尺寸、App/工具身份与诊断设置下的可比较基线。内存记录峰值和稳态，GPU记录实际工作/时间及copy/target字节，启动记录分阶段耗时和首帧呈现；至少三份有效同条件记录后再做ablation及修后对照。区分冷/暖cache、进程CPU/GPU分配与物理驻留，不拿单次ready或Debug FPS当整体收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；重要新策略先修订对应设计，常规局部修复直接实施。每轮实施、验证、独审、按职责提交，写明真实收益、未覆盖范围及下一轮；已完成证据归history。本卡在用户结束此专项或所有已证成本点闭合、长期切换验收完成后退役，不作为永久第二路线。
