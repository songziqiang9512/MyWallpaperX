# Web 壁纸文档入口

> 状态：Web 专题唯一导航
>
> 最近核对：2026-08-11
>
> 本页区分当前状态、稳定规范和历史证据。标题或正文中的“当前”只对其文档日期负责，不能覆盖现役状态入口。

## 0. 当前状态

- [current-state.md](current-state.md)：当前生产所有权、源码/运行证据边界、发布缺口与下一验收门。判断当前 HEAD 时从这里开始。

## 1. 稳定规范与运行模型

- [wallpaper-engine-web-rules.md](wallpaper-engine-web-rules.md)：长期兼容规则。
- [web-project-json-runtime-model.md](web-project-json-runtime-model.md)：project/descriptor/runtime/context 的稳定分层合同；当前类型与落点只查现役状态。
- [web-project-json-localization.md](web-project-json-localization.md)：原始声明、本地派生数据与本地化边界。
- [web-wallpaper-benchmark-standard.md](web-wallpaper-benchmark-standard.md)：长期运行证据与评分合同；不保存当前 PASS 数字。

## 2. 历史材料

- [统一历史索引](../history/README.md)：2026-04 阶段计划、2026-07 Web/Scene 状态快照、作者源码与 Steam CDN 代表样本基线。历史正文中的“当前”“下一步”、样本数字和命令只对其截止日期负责；本入口不再复制历史 PASS/coverage。

## 3. 使用规则

- 判断当前实现边界和闭环状态时，先看[现役状态](current-state.md)，再核对当前代码和最新可复现报告；本页的 2026-07-22 基线只用于比较。
- 实现稳定机制时看“长期规范与运行模型”，不要从历史回归记录反推设计规则。
- 历史阶段计划只用于理解当时取舍；排新任务前重新核对代码缺口。
- 查样本状态、临时结论或交接背景时，再从统一历史索引进入；现役文档不直接维护平行的历史清单。
- 若文档之间冲突，以当前代码、可复现运行证据、根 `AGENTS.md` 和长期[技术栈路线](../architecture/technology-stack-boundaries.md)为裁决依据；裁决后就地更新现役状态或长期规范，旧 review 保持历史属性。
