<!-- document-role: active-plan -->

# Scene 性能收敛工作卡

本卡与[属性卡](properties-panel-card.md)持续收敛CPU/GPU、内存、启动与交互成本；视觉问题归[队列](scene-open-breakpoint-queue.md)。

**执行顺序。**

1. CPU、内存与启动联查：采样每帧求值/分配、序列化/诊断、主线程阻塞与后台争用，再查压缩纹理展开、解码峰值、重复解析/上传。温度高、低频与GPU满载是待解释现象，须绑定实际CPU/GPU工作，不能凭频率判瓶颈。
2. GPU：先高级混合的全屏复制，再满足条件的HDR历史画面路径；实际需要的背景、history、反馈及完成屏障必须保留。
3. 首帧：以现有阶段计时区分解析、准备、编译、资源、首draw/呈现；缩小必须提前完成的范围，保持依赖、首帧完整与失败回退。
4. 长时间使用：连续切换轻/重壁纸，观察cache增长是否有界及停止后transient资源是否回落；保留合理复用cache，不把清空cache当性能优化。

**当前进度与下一轮。** 专项约30%（阶段估计）；[BC](../history/native-bc-memory-convergence-2026-10-12.md)、[PKG](../history/pkg-extraction-memory-convergence-2026-10-12.md)、[TEX](../history/tex-request-local-convergence-2026-10-13.md)、[区域复制](../history/color-blend-region-convergence-2026-10-13.md)与[属性候选复用](../history/property-candidate-evaluation-convergence-2026-10-13.md)已实施。开场copy -63%、GPU p95 -9.7%、FPS +8.4%仅内部Host；属性复用只证局部CPU。[图层引用](../history/layer-reference-responsibility-convergence-2026-10-13.md)恢复时钟；[材质静态准备](../history/compiled-variant-frame-program-convergence-2026-10-13.md)删除逐帧重复投影，三组CPU小幅下降仍低于旧噪声，按结构消融交付，不计稳定性能达成。下一轮闭[编辑重建](properties-panel-card.md)，随后量HDR history；base-image/natural-size、MDL双阶段、首帧及长期切换仍待量，保完整校验。

**工具边界。** 保唯一CLI、语义parser与验收入口、严格默认与未舍入ratio；[旧monolith已退役](../history/benchmark-responsibility-convergence-2026-10-13.md)，不另造wrapper/算法。

**比较与验收。** 固定输入/属性/音频/尺寸/App/工具/诊断，至少三份有效基线后对照；量CPU时间/调用/分配、内存峰值/稳态、GPU工作/copy及首帧，分冷暖cache与驻留。performance-only矩阵无执行承诺，观察unavailable，不代严格验收；单次ready/FPS不作收益。

必须检查原样本实际画面/下一帧、独立健康样本、启动失败/取消/替换及资源释放；涉及HDR/高级混合/history时保实际触发与不应触发反例。普通产品入口与内部Host证据分开。收益未稳定或功能回退先查因、修正或撤回本轮修改，不以放低效果质量、减少作者内容、提高timeout或丢诊断换通过。

**职责与退出。** 身份、资源、clock、准备图与最终输出沿[运行合同](../architecture/runtime-architecture.md)各保唯一权威；旧架构可重构；重要变更先落顶层设计，写数据流、owner迁移/退出、失败与验收。按公共语义扩展prepared/typed consumer分支，保唯一链路；局部修复直接实施。每轮实现、验证、独审、提交，汇报收益、边界及下一轮；完成证据归history。用户结束专项或已证成本与长期切换验收完成后退役。
