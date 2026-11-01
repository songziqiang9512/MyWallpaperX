# Scene 能力与语义索引

<!-- document-role: navigation -->

本目录按能力提供职责、覆盖和语义入口。先以[运行时总设计](../architecture/runtime-architecture.md)确定共同数据流，以[组件合同](runtime-systems-reference.md)确定具体能力如何组合；当前代码、能力和运行结果分别查询，不把它们混成实施顺序。

<a id="reading-layers"></a>

## 读取分层

按正在回答的问题选读：

| 层 | 内容 | 日常用法 |
| --- | --- | --- |
| 架构与组件 | [总设计](../architecture/runtime-architecture.md)、[组件合同](runtime-systems-reference.md)、[实际代码地图](../architecture/runtime-as-built-map.md) | 分别回答目标职责、组合方式和当前源码 owner |
| 能力状态 | [能力快照](coverage-ledger.md#current-overview) → [系统总表](coverage-ledger.md#capability-tables)与专项表 | 确认已执行范围、缺口和当前消费者 |
| 运行证据 | [证据快照](runtime-evidence-current.md#current-snapshot)、[证据深度](runtime-evidence-current.md#evidence-levels)及[精确证据包](runtime-evidence-current.md#evidence-packages) | 确认真实验证、身份、限制和失败，不从字段存在推导画面正确 |
| 设计与顺序 | [专项设计](../roadmap/batch2/batch2-design-index.md)、[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[修复队列](../roadmap/scene-open-breakpoint-queue.md) | 设计决定边界，路线决定顺序，队列列出具体开放问题 |
| 研究与历史 | [来源索引](../development/source-index.md)、[研究工作流](../development/official-client-behavior-research-workflow.md)、[历史索引](../history/README.md) | 按问题读取固定资料与独有证据，不作为当前能力或执行指令 |

稳定职责放合同，当前缺口放专项表，批次过程和被后继取代的记录放历史。条目保留在当前层的理由应是仍然影响当前实现或未决问题，而不是包含新的日期、commit 或截图。

## 资料和代码的边界

| 资料 | 是否由运行时直接读取 | 进入产品的形态 |
| --- | --- | --- |
| 官方网页、页面 map/catalog、静态取证、Mirage 研究 | 否 | 提炼行为与边界后独立实现，用正反用例验证；不复制或移植参考实现 |
| 语义专项表和能力台账 | 否 | 部分合同已独立转写到 Swift/Metal、测试和资源解析器；文档更新不会自动改变代码 |
| `lib.sceneScript-v2.8.d.ts` 参考快照 | 否 | 仅作为注释、测试和人工核对依据，不进入 App bundle 或编译输入 |
| `SceneStockAssets.bundle` 及其解析器 | 是 | 这是产品资源合同，不是研究资料；资源 identity 以 Swift resolver 和测试为准 |
| 运行证据、修复台账、census 输出 | 否 | 只提供可复核事实和链接；普通播放不得依赖报告、hash、census 或完整 observation |

因此，“资料已纳入代码”只能在对应代码、测试或资源 consumer 能被指出时成立；文档之间互相链接不算代码消费。

## 当前能力入口

| 主题 | 当前权威 | 适用场景 |
| --- | --- | --- |
| Effect | [effect-execution-coverage.md](effect-execution-coverage.md) | effect 分类、执行 owner、局部降级和迁移状态 |
| Graph / Shader | [render-graph-shader-coverage.md](render-graph-shader-coverage.md)、[uniform 派生常量合同](uniform-invariant-shader-constants.md) | Program、pass、FBO、history、target、shader primitive |
| SceneScript | [scenescript-api-coverage.md](scenescript-api-coverage.md) | ECMAScript、host API、handle、event、timer |
| Particle | [particle-component-coverage.md](particle-component-coverage.md) | component 组合、实例生命周期、预算和局部失败 |
| 属性与输入 | [runtime-input-property-coverage.md](runtime-input-property-coverage.md) | Timeline、property、pointer、audio、media、text 和 provider |
| 高级对象 | [advanced-object-coverage.md](advanced-object-coverage.md) | Puppet、lighting/HDR、3D、RGB、离线与发布 |
| 全局依赖 | [capability-dependency-map.md](../architecture/capability-dependency-map.md) | 公共能力依赖关系；当前差距查能力台账，不另设实施门 |
| 样本验收 | [scene-sample-acceptance-ledger.md](scene-sample-acceptance-ledger.md) | 真实样本的首断点、人工裁决与官方对照状态；修改生成源 `script/scene_sample_acceptance_verdicts.json` 后重新生成 |
| 样本调试 | [scene-sample-debug-ledger.md](scene-sample-debug-ledger.md) | 逐样本首断点定位与修复批次证据；不是视觉通过矩阵 |
| 光线/光照样本 | [lighting-sample-inventory.md](lighting-sample-inventory.md) | 声明分类、去重样本身份与未知边界；不证明运行或官方parity |

共享架构与组件职责只在前述合同维护；专项表承接具体能力语义、当前消费者、首断点和未支持边界。窄合同如[采样缺省](sampler-alias-precedence.md)、[模型绑定几何](direct-model-bind-geometry.md)、[骨骼动画](direct-model-skeletal-animation.md)由对应专项入口链接，不复制成多份总设计。

历史样本诊断仅按[Scene历史索引](../history/README.md)查证；旧失败解释不替代当前代码、能力台账和现役路线。

## 资料来源和研究边界

- [资料来源索引](../development/source-index.md)：官方公开资料、官方黑盒/静态观察、corpus、第三方参考的裁决边界。
- [官方客户端行为研究工作流](../development/official-client-behavior-research-workflow.md)：只有公开资料和现有证据不足以决定当前纵向切片时才使用。
- [官方页面映射](../development/reference/official-page-map.md)：公开页面到合同 anchor 的入口；目录和 crosswalk 仅作按需交叉参考。
- [官方客户端静态取证](../development/reference/client-runtime-static-forensics.md)：版本有界的研究观察，不是稳定实现合同。
- [MirageWallpaper 静态研究](../development/reference/miragewallpaper-rendering-reference.md)：固定 revision 的参考研究，不定义官方语义或像素真值。
- [Scene corpus 清单](scene-corpus-capability-inventory.md)：作者输入的声明范围与影响面，不证明执行或画面正确。

研究资料按需阅读，不作为每批前置；可以在同一上下文研究后独立实现，不因阅读停工。不得直接复制、照译或移植参考实现，目标行为与验收仍归本项目现役合同。

## 维护规则

1. 一个事实只保留一个权威解释；其他入口只链接。
2. `recognized`、`wired`、静态 census、compile success、route 数、matrix PASS、非黑像素和单样本通过都不能单独升级为视觉兼容、性能完成或官方 parity。
3. 普通帧保持 prepare-once/execute-many；诊断、hash、完整 observation、census 和 full matrix 只在主动验证或 milestone 使用。
4. 架构变化更新总设计或组件合同，具体能力变化更新专项表，运行结果更新证据；不要在 README、路线和报告之间复制当前数字。
