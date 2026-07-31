# Scene 文档入口

> Scene 当前能力和证据以现役台账与运行证据为准；历史计划、样本记录和参考资料不反向覆盖当前结论。

## 当前事实

- [语义与实现覆盖台账](semantics/coverage-ledger.md)：系统级能力、当前边界和下一升级门。
- [运行证据索引](semantics/runtime-evidence-index.md)：当前生产输入边界、签名运行门和可复现证据。
- [Scene 语义手册](semantics/README.md)：按格式、渲染图、属性、粒子、SceneScript 等问题进入专项合同。
- [能力依赖图](semantics/capability-dependency-map.md)：公共前置能力和当前开发顺序。

## 历史实施快照

- [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md)：2026-07-22 至 2026-07-27 的实施顺序、样本和测试门。

该文件用于追溯早期总体实施顺序，不用于选择下一项任务；Timeline 与 Audio 的现役合同、语料结论和剩余缺口已经分别进入运行输入专项表、Effect/粒子覆盖表、总台账和运行证据索引。下一步统一从专项覆盖表和能力依赖图选择。

## 公开参考

- [资料来源与证据索引](semantics/source-index.md)：官方页面、样本、第三方实现和证据等级。
- [官方参考快照](reference/official/)：版本化的公开 API 声明，仅供 API diff 和 fixture 研究，不进入 App bundle 或播放输入。

## 历史资料

- [样本评估](scene-sample-assessment-2026-07-22.md)：2026-07-22 的视觉基线；当前等级以覆盖台账为准。

## 使用规则

- 新的稳定语义、实现边界和证据更新进入 `semantics/` 的权威入口，不在历史报告中追加当前结论。
- 新的官方公开文本或声明放入 `reference/` 时，必须在来源索引记录官方 URL、版本、校验值和可使用边界。
- 删除或合并带日期的计划前，先把仍独有的合同迁入专项表并修复反向引用；未经确认保留原路径，不让历史文件继续承担现役状态。
