# Scene 语义手册

本目录按需提供作者语义合同、专项覆盖和研究资料。它不是日常任务队列。日常开发先看[Scene 开发工作流](../development-workflow.md)，当前阶段看[执行路线](../scene-compatibility-roadmap.md)，当前能力和运行事实分别看[能力台账](coverage-ledger.md)与[运行证据索引](runtime-evidence-index.md)。

## 当前能力入口

| 主题 | 当前权威 | 适用场景 |
| --- | --- | --- |
| Effect | [effect-execution-coverage.md](effect-execution-coverage.md) | effect 分类、执行 owner、fallback 和迁移状态 |
| Graph / Shader | [render-graph-shader-coverage.md](render-graph-shader-coverage.md) | Program、pass、FBO、history、target、shader primitive |
| SceneScript | [scenescript-api-coverage.md](scenescript-api-coverage.md) | ECMAScript、host API、handle、event、timer |
| Particle | [particle-component-coverage.md](particle-component-coverage.md) | component 组合、实例生命周期、预算和局部失败 |
| Input / Provider | [runtime-input-property-coverage.md](runtime-input-property-coverage.md) | Timeline、property、pointer、audio、media、text、provider |
| 高级对象 | [advanced-object-coverage.md](advanced-object-coverage.md) | Puppet、lighting/HDR、3D、RGB、离线与发布 |
| 全局依赖 | [capability-dependency-map.md](capability-dependency-map.md) | 公共 owner、不可绕过边界和依赖关系 |

专项表只拥有稳定合同、当前 route、首断点、正反门和未支持边界。批次过程、截图流水账和旧命令回到运行证据、Git 或 `docs/history/`，不要在专项表追加日志。

## 资料来源和研究边界

- [资料来源索引](source-index.md)：官方公开资料、官方黑盒/静态观察、corpus、第三方参考的裁决边界。
- [官方客户端行为研究工作流](official-client-behavior-research-workflow.md)：只有公开资料和现有证据不足以决定当前纵向切片时才使用。
- [官方页面映射](official-page-map.md)：公开页面到合同 anchor 的入口；目录和 crosswalk 仅作按需交叉参考。
- [官方客户端静态取证](client-runtime-static-forensics.md)：版本有界的高层职责和顺序，不是产品实现输入。
- [MirageWallpaper 静态研究](miragewallpaper-rendering-reference.md)：固定 revision 的 clean-room 结构对照，不定义官方语义或像素真值。
- [Scene corpus 清单](scene-corpus-capability-inventory.md)：作者输入影响面，不证明当前运行支持。

标为取证或研究用途的文档不得成为普通实现上下文的前置阅读。实现只消费项目自有行为合同、正反 fixture 和可复核的官方结果摘要；不得复制地址、伪代码、私有 shader/payload、资产或算法表达。

## 维护规则

1. 一个事实只保留一个权威解释；其他入口只链接。
2. `recognized`、`wired`、静态 census、compile success、route 数、matrix PASS、非黑像素和单样本通过都不能单独升级为视觉兼容、性能完成或官方 parity。
3. 普通帧保持 prepare-once/execute-many；诊断、hash、完整 observation、census 和 full matrix 只在主动验证或 milestone 使用。
4. 语义变化先更新对应专项表，再更新台账/运行证据；不要在 README、路线和报告之间复制当前数字。
