# Scene 文档入口

> Scene 当前能力和证据以现役台账与运行证据为准；历史计划、样本记录和参考资料不反向覆盖当前结论。

## 当前事实

- [语义与实现覆盖台账](semantics/coverage-ledger.md)：系统级能力、当前边界和下一升级门。
- [运行证据索引](semantics/runtime-evidence-index.md)：当前生产输入边界、签名运行门和可复现证据。
- [Scene 语义手册](semantics/README.md)：按格式、渲染图、属性、粒子、SceneScript 等问题进入专项合同。

## 实施计划

- [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md)：现役实施顺序、样本和测试门。
- [音频频谱专项计划](scene-audio-spectrum-development-plan-2026-07-27.md)：音频输入、声明 census 和分批验收。
- [时间轴专项计划](scene-timeline-development-plan-2026-07-27.md)：Timeline 语义、目标分层和验收路径。

## 公开参考

- [资料来源与证据索引](semantics/source-index.md)：官方页面、样本、第三方实现和证据等级。
- [官方参考快照](reference/official/)：版本化的公开 API 声明，仅供 API diff 和 fixture 研究，不进入 App bundle 或播放输入。

## 历史资料

- [样本评估](scene-sample-assessment-2026-07-22.md)：2026-07-22 的视觉基线；当前等级以覆盖台账为准。
- [Scene 兼容能力综述](wallpaper_engine_scene_compatibility.md)：上层能力地图和长期背景，具体实现状态以语义手册和运行证据为准。

## 使用规则

- 新的稳定语义、实现边界和证据更新进入 `semantics/` 的权威入口，不在历史报告中追加当前结论。
- 新的官方公开文本或声明放入 `reference/` 时，必须在来源索引记录官方 URL、版本、校验值和可使用边界。
- 带日期的计划、样本评估和取证报告保留原路径，避免破坏可追溯引用；需要新入口时优先补链接，不迁移历史文件。
