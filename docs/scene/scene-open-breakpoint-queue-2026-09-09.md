<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 核对：2026-09-16，依据全量工具/台账审计调整入口，未重跑样本。文件名日期仅保留链接身份。
> 本文是[兼容路线](scene-compatibility-roadmap.md)的短队列，不建立第二套阶段；工程性能工作按[重构计划](engine-refactor-program.md)执行。

## 1. 当前证据边界

样本身份只用于复现，不能进入产品分派。旧 corpus 计数和人工 verdict 不代表当前 HEAD 已重新验证；技术修复不能自动改写人工验收。当前能力查[能力台账](semantics/coverage-ledger.md)，运行身份查[运行证据](semantics/runtime-evidence-current.md)。

## 2. 现役执行顺序

### Q0 — 先完成兼容路线 P0 的全量关联与采集校准

按[兼容路线 §3.2](scene-compatibility-roadmap.md#32-p0-的四个有界批次)依次交付：盘点/fingerprint/守恒校验 → 既有表的声明/公共合同/代码 owner/场景/证据关联 → 普通产品启动采集校准与 fresh 全集基线 → 共享依赖及首批修复集合。工具扩展是待执行工作，不因本次计划修改视为完成。

每一步只改其完整职责；Q1 保留已有反馈作为复现候选，实际修复顺序由 fresh 首断点、公共依赖和影响面确定，不继续按旧报告的集群数字或以下样本顺序硬排。紧急可见回归可提前修复。

当前用户仅有现成截图或视频，先登记可用参考与控制变量缺口。固定官方客户端同输入动态对照是 P4 关闭依赖；缺环境不阻塞公共实现，但不能记官方一致性通过。

### Q1 — 作者参数、视觉验收与 tracked matrix

| 复现索引（非修复优先级） | 尚未关闭的问题 | 下一次操作与关闭条件 |
|---|---|---|
| 1 | `3747492842` 文字裁切、额外闪烁 | 当前签名 App 最小复现，定位最早失效的 text/geometry/graph/compositor 合同；可见正反对照和 next-frame 证据 |
| 2 | `1315486372` 水波纹位置异常 | 先复现与归因，再修公共坐标/采样 owner；不从症状直接指定实现 |
| 3 | `2684431262` 紫色块 | 先复现与归因，验证 source→effect→output；不得按样本特判 |
| 4 | Scene Bloom enable/threshold 尚无完整 live consumer | 沿属性 producer→typed channel→全场 post consumer 闭合；若仍 unsupported 则保留待解决边界，不据此关闭全集目标 |
| 5 | 全 corpus identity-only matrix 与人工视觉复核 | 按路线 P0/P4 维护；人工重新观看后才改 verdict；每批先定向，公共能力关闭复测全部影响集合，最终候选全集复测 |

已关闭的 Puppet、双视频、Water Waves mask、TextureAnimation 等断点不再占队列行；新回归必须建立当前复现后重新入队。其余 authored target 按实际 consumer 缺口拉入，不再把已接通的整个 script/camera/particle family 标为缺失。

### Q2 — 稳定帧性能、长稳与发布

现在即可做重构计划 E0 基线，再按测量进入 E1/E3/E4；P5 只拥有最终验收。维持作者分辨率和正确构图，不能恢复缩小纹理等错误行为换取帧率。

## 3. 观察项与能力边界

异步 provider 的短暂 not-ready 按局部 previous-current 后自然恢复；持续不恢复才登记缺口。Puppet 跨层 geometry provider、IK、完整 3D 等能力按专项合同和真实需求拉入，不恢复压平纹理捷径。

## 4. B1–B9 退役索引

已完成批次的证据只按需从[历史索引](../history/README.md)追溯，不再作为当前任务。这里不复制 PASS 数、旧命令或退役 owner 清单。

## 5. 队列维护与批次门

每项只保留问题、下一操作和关闭条件；完成后从表中移除，证据写回唯一台账。落代码遵守[开发工作流](development/development-workflow.md)，一次闭合一个完整职责并完成相称验证；提交仍需用户授权。

当公共首断点关闭、仅剩路线系统性验收时，将本文归档，取消派生队列。
