# Web 壁纸文档入口

> 最后更新：2026-07-22
> 目的：给当前 Web 专题文档提供一个稳定入口，区分长期规范、阶段计划与进度/历史记录，避免继续把状态散落在文件名里猜测。

## 0. 当前状态与验收边界

- [../reviews/web-scene-current-state-roadmap-2026-07-19.md](../reviews/web-scene-current-state-roadmap-2026-07-19.md)：Web 当前实现、10 项固定门、34 项完整门、闭环判断和剩余工作，作为现役状态入口。
- [regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md](regression/WEB_EXTERNAL_SAMPLE_BASELINE_2026-07-20.md)：5 个公开作者源码样本的来源、构建、能力矩阵和证据边界。
- [regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md](regression/WEB_STEAM_REPRESENTATIVE_BASELINE_2026-07-20.md)：3 个 Steam CDN 代表样本的下载快照、多视口/联网能力和证据边界。

截至 2026-07-22，10 项独立偏好域固定门保持全绿；当前最终签名 Debug App 的 34 项完整门为 32A/2B、平均 97.7、coverage 95.9%，作者源码门为 5A / 98.8 / 97.9%，Steam CDN 门为 3A / 98.0 / 94.8%，三组矩阵门均通过。两个 B 只保留 `3700131876`、`3700928191` 的既有样本脚本属性错误，并由矩阵明确允许；当前没有新增启动、宿主、导航、资源映射、交互、视觉或动画短板。评测合同已区分无 listener 页面、正向日志事件和当前 listener/payload 的 DOM 应用签名；Debug evidence 窗口也会进入当前 Space，避免 WebKit 因遮挡停止 rAF。真实 OS/物理设备、runtime 互切、长期性能、真实文件授权 UI/沙盒回归和发布门仍未闭环，因此不能声称发布级最终完全闭环。

## 1. 长期规范与运行模型

这些文档描述当前仍然指导实现的稳定规则、边界和模型，优先作为长期参考：

- [wallpaper-engine-web-rules-reference-2026-04-14.md](wallpaper-engine-web-rules-reference-2026-04-14.md)
- [web-project-json-runtime-model-plan-2026-04-14.md](web-project-json-runtime-model-plan-2026-04-14.md)
- [web-project-json-localization-strategy-2026-04-14.md](web-project-json-localization-strategy-2026-04-14.md)
- [web-wallpaper-benchmark-standard.md](web-wallpaper-benchmark-standard.md)

## 2. 阶段计划

这些文档保留当前阶段仍可执行的实施方案，用于安排工作顺序，不直接代替长期规范：

- [web-compatibility-execution-plan-2026-04-13.md](web-compatibility-execution-plan-2026-04-13.md)
- [web-native-input-host-plan-2026-04-14.md](web-native-input-host-plan-2026-04-14.md)

## 3. 进度 / Handoff / 历史执行记录

这些文档记录阶段性进展、样本状态和专项 handoff。它们可作为事实补充，但不应反向覆盖长期规范：

- [web-official-alignment-progress-2026-04-14.md](web-official-alignment-progress-2026-04-14.md)
- [regression/](regression/)：当前保留的作者源码与 Steam CDN 代表样本基线；旧调试流水和 handoff 已由现役路线图与 Git 历史取代。
- [../agents/web-development-expert-agent/web-handoff-2026-04-16.md](../agents/web-development-expert-agent/web-handoff-2026-04-16.md)

## 4. 角色入口

如果任务不是单纯读规范，而是需要明确由谁处理：

- Steam Web 官方兼容审查：[../agents/steam-web-compat-auditor/AGENTS.md](../agents/steam-web-compat-auditor/AGENTS.md)
- Web 宿主 / Web 模块兼容开发：[../agents/web-development-expert-agent/AGENTS.md](../agents/web-development-expert-agent/AGENTS.md)

## 5. 使用规则

- 判断当前实现边界和闭环状态时，先看“当前状态与验收边界”，再用当前代码和最新报告复核。
- 实现稳定机制时看“长期规范与运行模型”，不要从历史回归记录反推设计规则。
- 排执行顺序和拆阶段任务时，再看“阶段计划”。
- 查样本状态、临时结论或交接背景时，再看“进度 / Handoff / 历史执行记录”。
- 若文档之间冲突，以当前代码、可复现运行证据和根 `AGENTS.md` 为裁决依据；裁决后就地更新现役状态或长期规范，旧 review 保持历史属性。
