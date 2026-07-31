# Web 壁纸文档入口

> 状态：专题导航与历史基线索引
>
> 最近核对：2026-07-31；尚未建立持续更新的 Web 现役状态台账。
>
> 本页区分稳定规范、历史运行基线和阶段计划。需要判断当前 HEAD 时，必须回到代码、评测标准和最新可复现报告，不能直接复用下列带日期数字。

## 0. 2026-07-22 运行基线

- [../reviews/web-scene-current-state-roadmap-2026-07-19.md](../reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web 2026-07-19 至 2026-07-22 的实现、固定门、完整门和剩余工作快照。
- [regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md](regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)：5 个公开作者源码样本的来源、构建、能力矩阵和证据边界。
- [regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md](regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)：3 个 Steam CDN 代表样本的下载快照、多视口/联网能力和证据边界。

以下数字只描述 2026-07-22 的签名 Debug App：10 项独立偏好域固定门保持全绿；34 项完整门为 32A/2B、平均 97.7、coverage 95.9%，作者源码门为 5A / 98.8 / 97.9%，Steam CDN 门为 3A / 98.0 / 94.8%，三组矩阵门均通过。两个 B 保留 `3700131876`、`3700928191` 当时的样本脚本属性错误，并由矩阵明确允许。该批次仍未覆盖真实 OS/物理设备、runtime 互切、长期性能、真实文件授权 UI/沙盒回归和发布门；这些数据不代表 2026-07-31 的当前 HEAD。

## 1. 长期规范与运行模型

这些文档可作为稳定规则、边界和模型的设计参考；实施前仍需与当前代码核对：

- [wallpaper-engine-web-rules-reference-2026-04-14.md](wallpaper-engine-web-rules-reference-2026-04-14.md)
- [web-project-json-runtime-model-plan-2026-04-14.md](web-project-json-runtime-model-plan-2026-04-14.md)
- [web-project-json-localization-strategy-2026-04-14.md](web-project-json-localization-strategy-2026-04-14.md)
- [web-wallpaper-benchmark-standard.md](web-wallpaper-benchmark-standard.md)

## 2. 历史阶段计划

这些文档保留 2026-04 的实施方案和设计取舍，不直接作为当前执行顺序：

- [web-compatibility-execution-plan-2026-04-13.md](web-compatibility-execution-plan-2026-04-13.md)
- [web-native-input-host-plan-2026-04-14.md](web-native-input-host-plan-2026-04-14.md)

## 3. 进度 / Handoff / 历史执行记录

这些文档记录阶段性进展、样本状态和专项 handoff。它们可作为事实补充，但不应反向覆盖长期规范：

- [web-official-alignment-progress-2026-04-14.md](web-official-alignment-progress-2026-04-14.md)
- [regression/](regression/)：作者源码与 Steam CDN 代表样本的历史基线；旧调试流水和 handoff 由 dated roadmap 与 Git 历史追溯。

## 4. 使用规则

- 判断当前实现边界和闭环状态时，以当前代码、评测标准和最新可复现报告为准；本页的 2026-07-22 基线只用于比较。
- 实现稳定机制时看“长期规范与运行模型”，不要从历史回归记录反推设计规则。
- 历史阶段计划只用于理解当时取舍；排新任务前重新核对代码缺口。
- 查样本状态、临时结论或交接背景时，再看“进度 / Handoff / 历史执行记录”。
- 若文档之间冲突，以当前代码、可复现运行证据和根 `AGENTS.md` 为裁决依据；裁决后就地更新现役状态或长期规范，旧 review 保持历史属性。
