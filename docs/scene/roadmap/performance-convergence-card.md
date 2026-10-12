<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

本卡及[属性卡](properties-panel-card.md)降低成本和等待，保画面与交互；视觉归[队列](scene-open-breakpoint-queue.md)。

**执行顺序。**

1. 内存与启动一起查：压缩纹理展开、解码峰值、同内容重复解析/上传与资源生命周期。
2. GPU：先高级混合的全屏复制，再满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：以现有阶段计时区分解析、准备、编译、资源、首draw/呈现；缩小必须提前完成的范围，保持依赖、首帧完整与失败回退。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**当前进度与下一轮。** 复用结果归[BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX证据](../history/tex-request-local-convergence-2026-10-13.md)。专项约20%（阶段估计），不外推App峰值/首帧。原包开场经[有界host修复](../history/scenescript-host-heap-admission-2026-10-13.md)闭合；旧脚本停用测量不作基线。下一轮补HDR/reflection复制计量，再量普通高级混合quad局部复制；复用既有投影和snapshot，custom geometry/折射保全屏。base-image/natural-size、MDL双阶段、首帧及长期切换待量，保完整校验。属性typed更新/重建归[属性卡](properties-panel-card.md)。

**工具职责裁决。** runner保唯一CLI/严格默认/矩阵/签名/退出与报告入口；日志解析按语义各一grammar/owner，执行采集→单一验收，保未舍入ratio及失败顺序、API导入、依赖无环。拒绝wrapper、二次解析/JSON转交或第二算法。相较保留长文件/只抽telemetry，用AST/API、完整报告/命令/异常golden、测试唯一发现/门映射限风险，差异停止。独审、golden及签名运行已验，[旧monolith退役](../history/benchmark-responsibility-convergence-2026-10-13.md)，撤登记；剩余职责留本文。

**比较与验收。** 固定输入/属性/音频/尺寸/App/工具/诊断，至少三份有效基线后对照；量峰值/稳态、GPU工作/时间/copy/target、分阶段首帧，分冷暖cache、分配与驻留。performance-only矩阵无执行承诺，观察unavailable，不代严格验收；单次ready/FPS不作收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；重要新策略先修订对应设计，常规局部修复直接实施。每轮实施、验证、独审、按职责提交，写明真实收益、未覆盖范围及下一轮；已完成证据归history。本卡在用户结束此专项或所有已证成本点闭合、长期切换验收完成后退役，不作为永久第二路线。
