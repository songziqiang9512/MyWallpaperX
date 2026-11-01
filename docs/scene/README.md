# Scene 开发入口

<!-- document-role: navigation -->

先由总设计确定职责，再看当前接线与能力证据；实施顺序只由对应路线决定。这个入口提供文档分工，不保存实现状态或重复设计正文。

## 引擎如何工作

| 要回答的问题 | 唯一职责与入口 |
|---|---|
| 最终采用什么架构，准备、更新、渲染和释放如何连接 | [运行时总设计](architecture/runtime-architecture.md) |
| 大量组件如何分类、组合、存储和接入执行链 | [组件职责与运行合同](capabilities/runtime-systems-reference.md) |
| 语言、依赖、进程与跨语言边界 | [技术栈合同](../architecture/technology-stack-boundaries.md)；[Scene 进程与 IPC 合同](architecture/scene-runtime-daemon-contract.md) |
| 当前代码由谁装配、调用和销毁 | [实际代码地图](architecture/runtime-as-built-map.md)；启动细节查[启动接线](architecture/scene-startup-pipeline.md) |
| 当前实现到哪里、明确缺少什么 | [能力索引](capabilities/README.md)与[能力台账](capabilities/coverage-ledger.md#current-overview)；纹理绑定语义查[sampler 合同](capabilities/sampler-alias-precedence.md) |
| 实际验证了什么、证据适用于什么范围 | [运行证据索引](capabilities/runtime-evidence-current.md#current-snapshot) |

总设计规定目标，代码地图说明事实；二者有差距时按总设计记录重构要求，不能用旧代码或旧测试反向定义目标。

## 现在做什么

| 任务 | 现役路线 |
|---|---|
| 工程结构、生命周期与成本精简 | [重构设计](roadmap/engine-refactor-program.md)，服从运行时总设计 |
| 整体 CPU/GPU、内存、启动与能耗 | [性能工作卡](roadmap/performance-convergence-card.md)，维护执行顺序 |
| 属性面板响应、定义与编辑更新 | [属性工作卡](roadmap/properties-panel-card.md)，维护执行顺序 |
| 作者能力、可见正确性与全样本验收 | [兼容 P 路线](roadmap/scene-compatibility-roadmap.md) |
| 具体反馈与公共首断点 | [唯一修复队列](roadmap/scene-open-breakpoint-queue.md)，是兼容路线的派生表 |
| 跨组件专项设计 | [设计索引](roadmap/batch2/batch2-design-index.md)，包含已实施和未闭范围；批准不代表验收 |

## 去哪里改代码

从[实际代码地图](architecture/runtime-as-built-map.md)定位当前 owner，按[组件合同](capabilities/runtime-systems-reference.md)判断应修改的数据与执行职责；跨 App 边界查[仓库源码地图](../architecture/repository-map.md)。实现和验证使用[Scene 开发工作流](development/development-workflow.md)，不为每个组件再建立一套流程。

## 目录怎么读、怎么维护

`architecture/` 维护总体与跨组件合同及代码事实图，`capabilities/` 按能力维护职责、现况和语义，`roadmap/` 维护顺序与专项设计，`development/` 维护开发方法和参考来源，`history/` 保存固定过程与证据。专题设计细节从总设计或能力索引进入，不组成第二套顶层架构。

[来源索引](development/source-index.md)区分官方行为、静态观察、作者数据和第三方参考；[研究工作流](development/official-client-behavior-research-workflow.md)说明如何补足未定语义。[历史索引](history/README.md)仅供追溯，不决定当前能力或下一任务。同一事实只由一个 owner 维护，入口只链接。
