# Scene 语义手册

本目录按需提供作者语义合同、专项覆盖和研究资料。它不是日常任务队列。日常开发先看[Scene 开发工作流](../development/development-workflow.md)，当前阶段看[执行路线](../scene-compatibility-roadmap.md)，当前能力和运行事实分别看[能力台账](coverage-ledger.md)与[运行证据索引](runtime-evidence-current.md)。不要把整个语义目录或整份流水账一次性装入上下文。

## 读取分层

默认只读当前层，只有首断点需要时才向下取证：

| 层 | 内容 | 日常用法 |
| --- | --- | --- |
| 当前合同 | `runtime-architecture.md`、路线、专项覆盖表 | 决定 owner、边界、fallback 和目标行为 |
| 当前状态 | `coverage-ledger.md` 的 `## 1`–`## 7`；`runtime-evidence-current.md` 的 `## 1 当前证据快照` | 只找当前首断点和最近可复核证据；需要细节时按精确 `E-*` anchor 打开一条 |
| 按需研究 | `source-index.md`、官方研究工作流、官方页面映射、客户端/Mirage 取证 | 公开资料和现有代码无法决定当前纵向切片时才读；研究原文不是实现输入 |
| 冷档/附录 | 运行证据 `## 2`、台账 `## 8` 的批次记录、`docs/history/scene/reference/client-changelog-appendix.md`、页面 catalog/crosswalk、`docs/history/` | 只为追溯旧结论、比较回归或恢复唯一失败现场而读；不作为普通开发上下文 |

一条记录只有在仍然改变当前 owner、route、失败半径、验证门或未决问题时才留在当前层。单纯的日期、commit、hash、截图路径、重复 PASS/NON-PASS 和已经被后继证据取代的叙事属于冷档候选。

## 资料和代码的边界

| 资料 | 是否由运行时直接读取 | 进入产品的形态 |
| --- | --- | --- |
| 官方网页、页面 map/catalog、静态取证、Mirage 研究 | 否 | 人工提炼后的合同、正反 fixture 或研究边界；不得复制私有算法、payload、shader 或资产 |
| 语义专项表和能力台账 | 否 | 部分合同已独立转写到 Swift/Metal、测试和资源解析器；文档更新不会自动改变代码 |
| `lib.sceneScript-v2.8.d.ts` 参考快照 | 否 | 仅作为注释、测试和人工核对依据，不进入 App bundle 或编译输入 |
| `SceneStockAssets.bundle` 及其解析器 | 是 | 这是产品资源合同，不是研究资料；资源 identity 以 Swift resolver 和测试为准 |
| 运行证据、修复台账、census 输出 | 否 | 只提供可复核事实和链接；普通播放不得依赖报告、hash、census 或完整 observation |

因此，“资料已纳入代码”只能在对应代码、测试或资源 consumer 能被指出时成立；文档之间互相链接不算代码消费。

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
| 样本验收 | [scene-sample-acceptance-ledger.md](scene-sample-acceptance-ledger.md) | 全部真实样本的首断点集群与人工视觉裁决，以及 P0.2 `sample → verdict` 关系的官方对照状态与缺口计数（逐样本的观看者/run/截图身份/剩余差异只进 `--json` 载荷，页面不逐条渲染）；裁决只改 `script/scene_sample_acceptance_verdicts.json` 后重新生成 |
| 样本调试 | [scene-sample-debug-ledger.md](scene-sample-debug-ledger.md) | 逐样本首断点定位与修复批次证据；不是视觉通过矩阵 |

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
