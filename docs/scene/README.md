# Scene 开发入口

<!-- document-role: navigation -->

按问题选择入口，再从文档中的源码路径追到实际消费者。

| 要解决的问题 | 文档 |
|---|---|
| 进程、加载、逐帧执行、组件所有权与退出 | [当前运行架构](architecture/runtime-architecture.md) |
| 组件分类、状态、更新顺序与资源寿命 | [组件职责](capabilities/runtime-systems-reference.md) |
| 功能支持和已知限制 | [能力总览](capabilities/README.md) |
| 最近运行结果及其适用范围 | [运行证据](capabilities/runtime-evidence-current.md) |
| 当前待解决的问题 | [问题队列](roadmap/scene-open-breakpoint-queue.md) |
| 修改、验证和文档维护 | [开发工作流](development/development-workflow.md) |

## 架构专题

- [启动、准备与缓存](architecture/scene-launch-responsiveness-contract.md)
- [daemon 与 IPC](architecture/scene-runtime-daemon-contract.md)
- [资源分配与额度](architecture/scene-resource-admission.md)
- [源码依赖边界](architecture/scene-dependency-boundaries.md)
- [GPU 计时与截图](architecture/gpu-stage-timestamp-diagnostics.md)

## 开发工具与研究

- [性能测量](roadmap/performance-convergence-card.md)
- [官方行为研究](development/official-client-behavior-research-workflow.md)
- [资料来源](development/source-index.md)
- [仓库工作流](../development/repository-workflow.md)
- [技术栈与平台](../architecture/technology-stack-boundaries.md)
