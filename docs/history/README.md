# MyWallpaperX 历史文档索引

本目录是已退役计划、评审、迁移记录和运行/视觉基线的唯一归纳位置。这里的文件用于解释“当时为什么这样做”和保存不可替代的证据，不决定当前能力、架构或下一任务。

## 使用合同

- 本页是统一历史入口，不是历史证据正文；除此之外，`docs/history/**/*.md` 均由[文档角色索引](../document-role-index.json)自动发现并显式登记为 `historical-evidence`，不能登记为现役计划或稳定合同。
- 文件名带日期的 Markdown 只能位于 `docs/history/`；无日期的现役计划或稳定合同必须通过文档角色索引的 `additionalPaths` 明确纳管。
- 历史正文中的“当前”“下一步”“必须”“运行此命令”只适用于文件注明的截止日期和当时环境。
- 当前事实依次查[文档入口](../README.md)、[Scene 能力台账](../scene/semantics/coverage-ledger.md)、[Scene 运行证据](../scene/semantics/runtime-evidence-current.md)或[Web 现役状态](../web/current-state.md)。
- 当前执行顺序只查[Scene 兼容执行路线](../scene/scene-compatibility-roadmap.md)以及仍明确登记为 active plan 的专题文件。
- 当前文档只有在需要引用独有研究结论或历史证据 anchor 时才深链具体文件；不得从历史文件续接任务。
- 新的当前状态不写入本目录。被新证据或新计划替代的文件在完整保留独有信息后移入本目录，并同步文档角色索引。

## 历史材料

| 截止日期 | 专题 | 类型 | 文件 | 独有价值 | 当前权威 |
|---|---|---|---|---|---|
| 2026-05-05 | Architecture | architecture snapshot | [框架架构备忘](architecture/framework-architecture-memo.md) | 早期模块接入和目录约定 | [AGENTS](../../AGENTS.md)、[文档入口](../README.md)、[技术栈边界](../architecture/technology-stack-boundaries.md) |
| 2026-07-19 至 2026-07-25 | Web + Scene | cross-topic review | [Web 与 Scene 状况评估](cross-topic/web-scene-current-state-roadmap-2026-07-19.md) | 当时的跨专题评估和证据来源 | [Web 现役状态](../web/current-state.md)、[Scene 路线](../scene/scene-compatibility-roadmap.md)、[Scene 能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-07-20 | Web | runtime baseline | [外部代表样本基线](web/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md) | 5 个外部样本的当时运行证据 | [Web 现役状态](../web/current-state.md) |
| 2026-07-20 | Web | runtime baseline | [Steam 代表样本基线](web/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md) | 3 个 Steam 样本的当时运行证据 | [Web 现役状态](../web/current-state.md) |
| 2026-04-13 | Web | plan | [Web 兼容执行方案](web/web-compatibility-execution-plan-2026-04-13.md) | 早期分类修复策略 | [Web 现役状态](../web/current-state.md) |
| 2026-04-14 | Web | plan | [Web 单宿主输入方案](web/web-native-input-host-plan-2026-04-14.md) | 早期 macOS 输入/宿主设计 | [Web 现役状态](../web/current-state.md) |
| 2026-04-15 | Web | progress snapshot | [Web 官方对齐进度](web/web-official-alignment-progress-2026-04-14.md) | 第一轮官方对齐批次记录 | [Web 现役状态](../web/current-state.md) |
| 2026-07-22 | Scene | visual baseline | [21 样本能力与视觉评估](scene/scene-sample-assessment-2026-07-22.md) | 首轮逐样本截图分级 | [Scene 能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md)、[Corpus 清单](../scene/semantics/scene-corpus-capability-inventory.md) |
| 2026-07-27 | Scene | plan | [Scene 播放能力开发计划](scene/scene-capability-development-plan-2026-07-22.md) | 早期 coverage-first 批次和样本门 | [Scene 路线](../scene/scene-compatibility-roadmap.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-08-12 | Scene | migration record | [Render Chain R0-R5 记录](scene/scene-render-chain-refactor-plan-2026-08-03.md) | owner 收敛和旧链删除全过程 | [Scene 路线](../scene/scene-compatibility-roadmap.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-08-15 | Scene | superseded plan | [G0-G5 通用执行计划](scene/scene-generic-execution-refactor-plan-2026-08-15.md) | 被否决的横向平台迁移方案及治理背景 | [Scene 路线](../scene/scene-compatibility-roadmap.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-07-24 | Scene | research | [参考项目全量审查](scene/scene-reference-project-audit-2026-07-24.md) | 当时四个参考项目的格式/架构线索 | [资料来源索引](../scene/semantics/source-index.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-07-24 | Scene | research | [参考项目 Effect/Runtime 审查](scene/scene-reference-audit-effects-runtime-2026-07-24.md) | effect/runtime 专题线索 | [资料来源索引](../scene/semantics/source-index.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-07-25 | Scene | official-client forensics | [Wallpaper Engine 2.8.42 取证](scene/windows-wallpaper-engine-2.8.42-scene-reference-audit-2026-07-25.md) | 固定版本客户端的原始审计快照 | [资料来源索引](../scene/semantics/source-index.md)、[能力台账](../scene/semantics/coverage-ledger.md)、[运行证据](../scene/semantics/runtime-evidence-current.md) |
| 2026-09-05 | Scene | cold reference | [官方客户端二进制与第三方依赖取证](scene/reference/client-binary-dependency-forensics.md) | 固定版本依赖与预览资源取证 | [资料来源索引](../scene/semantics/source-index.md)、[客户端静态取证](../scene/semantics/client-runtime-static-forensics.md) |
| 2026-09-05 | Scene | cold appendix | [官方客户端 changelog 全量附录](scene/reference/client-changelog-appendix.md) | 459 个 revision 的原始逐字附录 | [资料来源索引](../scene/semantics/source-index.md)、[changelog 取证](../scene/semantics/client-changelog-forensics.md)、[能力台账](../scene/semantics/coverage-ledger.md) |
| 2026-09-05 | Scene | cold corpus | [官方默认工程 fixture 清单](scene/reference/official-default-projects-fixture-inventory.md) | 固定版本官方工程静态输入清单 | [资料来源索引](../scene/semantics/source-index.md)、[Scene corpus 清单](../scene/semantics/scene-corpus-capability-inventory.md)、[能力台账](../scene/semantics/coverage-ledger.md) |
| 2026-09-05 | Scene | cold navigation | [官方页面全目录](scene/reference/official-page-catalog.md) | 179 个官方页面的无遗漏 URL 目录 | [资料来源索引](../scene/semantics/source-index.md)、[官方页面逐页映射](../scene/semantics/official-page-map.md) |
| 2026-09-05 | Scene | cold navigation | [官方页面能力映射](scene/reference/official-page-crosswalk.md) | 官方页面分组导航与合同交叉表 | [资料来源索引](../scene/semantics/source-index.md)、[官方页面逐页映射](../scene/semantics/official-page-map.md)、[能力台账](../scene/semantics/coverage-ledger.md) |
| 2026-09-05 | Scene | cold compatibility | [zcompat 向后兼容取证](scene/reference/zcompat-backward-compatibility-forensics.md) | 固定版本兼容 patch record 研究 | [资料来源索引](../scene/semantics/source-index.md)、[changelog 取证](../scene/semantics/client-changelog-forensics.md)、[能力台账](../scene/semantics/coverage-ledger.md) |
| 2026-09-05 | Scene | runtime evidence archive | [Scene 运行证据完整归档](scene/runtime-evidence-index.md) | 现役证据摘要之外的完整 E-* provenance 与历史包 | [Scene 当前证据摘要](../scene/semantics/runtime-evidence-current.md)、[Scene 能力台账](../scene/semantics/coverage-ledger.md) |
| 2026-09-09 | Scene | investigation snapshot | [现存断点修复队列](scene/scene-open-breakpoint-queue-2026-09-09.md) | 当日全量探测归纳的公共首断点、owner 位置和建议执行序 | [Scene 路线](../scene/scene-compatibility-roadmap.md)、[Scene 能力台账](../scene/semantics/coverage-ledger.md)、[Scene 当前证据](../scene/semantics/runtime-evidence-current.md) |

Git 历史继续保存每次文档变更。本目录不是 changelog，也不接受为了“留档”而复制现役文档的平行副本。
