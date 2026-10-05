# Scene 开发入口

先从 `roadmap/` 选一条现役路线；其余材料在同一 Scene 专题内按需读取，不决定下一步。

2026-10-06 用户要求收尾后暂停；接手先读[暂停交接与后继工作卡](roadmap/scene-maintainer-handoff-2026-10-06.md)，恢复须用户授权。

## 现在做什么

| 任务 | 现役路线 |
|---|---|
| 工程结构、生命周期、性能与消融 | [工程 E 路线](roadmap/engine-refactor-program.md) |
| 作者能力、可见正确性与全样本验收 | [兼容 P 路线](roadmap/scene-compatibility-roadmap.md) |
| Steam 获取、账号、下载与入库 | [SteamKit 专项](roadmap/scene-steamkit-migration-plan.md)，细化 E 路线 |
| 用户反馈与公共首断点 | [派生断点队列](roadmap/scene-open-breakpoint-queue.md)，服从 P 路线 |
| Batch 2 待实施能力设计与派生卡 | [设计与后继卡](roadmap/batch2/batch2-design-index.md)，服从兼容路线选序，批准不代表实现完成 |

## 引擎如何工作

[运行时架构](architecture/runtime-architecture.md)、[实际代码地图](architecture/runtime-as-built-map.md)、[进程合同](architecture/scene-runtime-daemon-contract.md)、[启动响应合同](architecture/scene-launch-responsiveness-contract.md)与[启动现况图](architecture/scene-startup-pipeline.md)各自维护目标或当前事实。

[Sampler 合同](capabilities/sampler-alias-precedence.md)、[作者采样与公开 companion](architecture/runtime-architecture.md#authored-texture-companion)、[设计索引](roadmap/batch2/batch2-design-index.md)按首断点读取；局部失败查[alpha fallback](capabilities/alpha-display-fallback-design.md)、[资源准入](architecture/scene-resource-admission.md)与[draw-only降级](capabilities/static-source-draw-only-degradation.md)。

## 去哪里改代码

[仓库源码地图](../architecture/repository-map.md)定位 owner；[Scene 开发工作流](development/development-workflow.md)说明实现与验证方法。

## 目录怎么读、怎么维护

[当前能力、证据摘要与语义参考](capabilities/README.md)按主题和精确锚点查询；[Scene 历史索引](history/README.md)保留已完成过程。`roadmap/batch2/` 保留待实施设计及派生卡，`architecture/` 放总体与跨能力合同，`capabilities/` 放能力设计、现况与语义参考，`development/` 放开发和研究方法，`history/` 保存完成过程；本页只导航。
