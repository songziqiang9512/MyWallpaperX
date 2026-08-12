# Scene 文档入口

> Scene 当前能力和证据以现役台账与运行证据为准；历史计划、样本记录和参考资料不反向覆盖当前结论。

> 当前没有仍在执行的 Scene 迁移计划。R0-R5 已完成；新增能力必须从专项覆盖表确认真实缺口，再按能力依赖图进入统一框架，不得从历史批次、样本 ID 或旧 owner 路线续接。

## 当前事实

- [语义与实现覆盖台账](semantics/coverage-ledger.md)：系统级能力、当前边界和下一升级门。
- [运行证据索引](semantics/runtime-evidence-index.md)：当前生产输入边界、签名运行门和可复现证据。
- [Scene 语义手册](semantics/README.md)：按格式、渲染图、属性、粒子、SceneScript 等问题进入专项合同。
- [能力依赖图](semantics/capability-dependency-map.md)：公共前置能力和当前开发顺序。
- [全样本能力分类与修复台账](semantics/scene-corpus-capability-inventory.md)：真实 Scene 根全部 authored 资源、Effect、纹理、粒子、动态输入和参数 family；用于按共享结构立项与防回归，不表示运行支持。

## 历史与已完成记录

- [Scene 解析到合成链路重构计划](scene-render-chain-refactor-plan-2026-08-03.md)：R0-R5 owner 收敛与旧链删除的完整实施记录。该计划已完成并转为历史快照，不再决定下一任务，也不覆盖能力等级或运行基线。

- [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md)：2026-07-22 至 2026-07-27 的实施顺序、样本和测试门。

以上文件只用于追溯当时的总体实施顺序、取舍与证据，不用于选择下一项任务。Timeline、Audio、Effect 与 Render Graph 的现役合同和剩余缺口已经进入对应专项表、总台账和运行证据索引。

## 公开参考

- [资料来源与证据索引](semantics/source-index.md)：官方页面、样本、第三方实现和证据等级。
- [MirageWallpaper Scene 显示链路静态研究](semantics/miragewallpaper-rendering-reference.md)：固定 revision 下的纹理、合成、effect、相机、鼠标及其他显示链路 clean-room 对照；不表示当前能力。
- [官方参考快照](reference/official/)：版本化的公开 API 声明，仅供 API diff 和 fixture 研究，不进入 App bundle 或播放输入。

## 历史资料

- [样本评估](scene-sample-assessment-2026-07-22.md)：2026-07-22 的视觉基线；当前等级以覆盖台账为准。

## 使用规则

- 日常验证先运行 `python3 script/verify_scene_change.py --phase checkpoint --base HEAD --path <path>` 查看按改动选择的最小门，再加 `--run` 执行；fixed/full 必须使用 milestone 阶段并记录原因。
- 新的稳定语义、实现边界和证据更新进入 `semantics/` 的权威入口，不在历史报告中追加当前结论。
- 新的官方公开文本或声明放入 `reference/` 时，必须在来源索引记录官方 URL、版本、校验值和可使用边界。
- 删除或合并带日期的计划前，先把仍独有的合同迁入专项表并修复反向引用；未经确认保留原路径，不让历史文件继续承担现役状态。
