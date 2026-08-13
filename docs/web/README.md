# Web 壁纸文档入口

> 状态：Web 专题唯一导航
>
> 最近核对：2026-08-11
>
> 本页区分当前状态、稳定规范和历史证据。标题或正文中的“当前”只对其文档日期负责，不能覆盖现役状态入口。

## 0. 当前状态

- [current-state.md](current-state.md)：当前生产所有权、源码/运行证据边界、发布缺口与下一验收门。判断当前 HEAD 时从这里开始。

## 1. 稳定规范与运行模型

- [wallpaper-engine-web-rules-reference-2026-04-14.md](wallpaper-engine-web-rules-reference-2026-04-14.md)：长期兼容规则。
- [web-project-json-runtime-model-plan-2026-04-14.md](web-project-json-runtime-model-plan-2026-04-14.md)：project/descriptor/runtime/context 的稳定分层合同；当前类型与落点只查现役状态。
- [web-project-json-localization-strategy-2026-04-14.md](web-project-json-localization-strategy-2026-04-14.md)：原始声明、本地派生数据与本地化边界。
- [web-wallpaper-benchmark-standard.md](web-wallpaper-benchmark-standard.md)：长期运行证据与评分合同；不保存当前 PASS 数字。

## 2. 2026-07 历史运行基线

- [../reviews/web-scene-current-state-roadmap-2026-07-19.md](../reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web 2026-07-19 至 2026-07-22 的实现、固定门、完整门和剩余工作快照。
- [regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md](regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)：5 个公开作者源码样本的来源、构建、能力矩阵和证据边界。
- [regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md](regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)：3 个 Steam CDN 代表样本的下载快照、多视口/联网能力和证据边界。

以下数字只描述 2026-07-22 的签名 Debug App：10 项独立偏好域固定门保持全绿；34 项完整门为 32A/2B、平均 97.7、coverage 95.9%，作者源码门为 5A / 98.8 / 97.9%，Steam CDN 门为 3A / 98.0 / 94.8%，三组矩阵门均通过。两个 B 保留 `3700131876`、`3700928191` 当时的样本脚本属性错误，并由矩阵明确允许。该批次仍未覆盖真实 OS/物理设备、runtime 互切、长期性能、真实文件授权 UI/沙盒回归和发布门；这些数据不代表任何后续 HEAD。

## 3. 历史阶段计划

这些文档保留 2026-04 的实施方案和设计取舍，不直接作为当前执行顺序：

- [web-compatibility-execution-plan-2026-04-13.md](web-compatibility-execution-plan-2026-04-13.md)
- [web-native-input-host-plan-2026-04-14.md](web-native-input-host-plan-2026-04-14.md)

## 4. 进度 / Handoff / 历史执行记录

这些文档记录阶段性进展、样本状态和专项 handoff。它们可作为事实补充，但不应反向覆盖长期规范：

- [web-official-alignment-progress-2026-04-14.md](web-official-alignment-progress-2026-04-14.md)
- [regression/](regression/)：作者源码与 Steam CDN 代表样本的历史基线；旧调试流水和 handoff 由 dated roadmap 与 Git 历史追溯。

## 5. 使用规则

- 判断当前实现边界和闭环状态时，先看[现役状态](current-state.md)，再核对当前代码和最新可复现报告；本页的 2026-07-22 基线只用于比较。
- 实现稳定机制时看“长期规范与运行模型”，不要从历史回归记录反推设计规则。
- 历史阶段计划只用于理解当时取舍；排新任务前重新核对代码缺口。
- 查样本状态、临时结论或交接背景时，再看“进度 / Handoff / 历史执行记录”。
- 若文档之间冲突，以当前代码、可复现运行证据、根 `AGENTS.md` 和长期[技术栈路线](../architecture/technology-stack-boundaries.md)为裁决依据；裁决后就地更新现役状态或长期规范，旧 review 保持历史属性。
