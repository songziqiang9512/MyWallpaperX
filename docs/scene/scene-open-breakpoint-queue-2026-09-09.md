<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 最后核对：2026-09-13，当前工作分支 `codex/scene-capability-baseline`。文件名保留日期只为链接稳定；本文内容只描述当前可执行队列，不保存某次提交现场。
>
> [Scene 兼容执行路线](scene-compatibility-roadmap.md)拥有 P0–P5 的阶段顺序和最终完成门；本文把当前代码、能力台账、运行证据和人工裁决中仍可执行的首断点压成短队列。样本 ID 只用于复现与验收，不得进入产品路由。

## 1. 当前证据边界

- 2026-09-13 的 Puppet 世界空间直绘已经删除 coverage 中间纹理、尺寸预算补丁和普通 layer-source publication。当前签名 Debug App 对 `3665307769 / 3780119725 / 3264246690 / 3238423642` 的定向运行均为 strict PASS；稳定帧人工复核确认角色组合、位置、大小、头部和肢体完整，人物细节不再被 coverage 降采样。现役事实见[样本调试台账](semantics/scene-sample-debug-ledger.md#2026-09-13-puppet-世界空间直绘最终定向复核)和[运行证据](semantics/runtime-evidence-current.md#e-2026-09-13-puppet-world-geometry)。这些样本不再属于 Puppet 技术断点。
- [样本验收台账](semantics/scene-sample-acceptance-ledger.md)当前保存的 `19 fail / 140 unreviewed` 和各首断点集群来自 2026-09-12 的归档，早于信号载体 lowering 与 Puppet 世界空间直绘。它仍是人工裁决的唯一写入面，但其计数和部分备注不是当前 HEAD 的技术缺口统计；必须在维护者重新观看后才更新 verdict，不能用 benchmark 结果代替。
- 2026-09-12 的 full-corpus `135/159 strict PASS` 只是一份历史结构快照。后继修复没有重新执行全 corpus，本队列也不以重复全量回放刷新数字。每个条目先用受影响样本和 focused 模块建立当前首断点。
- 五类产品——纹理、世界空间几何、模拟状态、异步 provider、多 pass graph——都必须产出或消费同一 prepared product、typed frame state、Metal execution 和唯一 compositor 合同。它们可以拥有不同的数据形状与生命周期，但不得形成第二套 property、clock、resource registry、graph 或 output owner。
- `3749463715` 的 graph / utility-capture 断点已经在当前签名 App 上关闭。旧实现把 feedback 的持久 RGBA target 直接判成 typed data，Motion Blur 颜色输出因此不能进入 compositor，并留下未消费 transaction；现由完整 Program variant envelope 在 launch preparation 解析内容语义，颜色反馈进入 compositor，只有被所有 variant 证明为整值状态变换的反馈才发布为 data。`3749463715` 与 data 反例 `3448845950` 均取得 strict PASS，详细证据见[当前运行证据](semantics/runtime-evidence-current.md#e-2026-09-13-feedback-content-contract)。这不改变两者尚未更新的人工视觉 verdict。
- 旧 Q1 的四个 effect-local passthrough 观察断点已关闭。当前签名 App 对 `3323988600 / 3395777145 / 3472940912 / 3754630802` 均为 strict PASS；Pixelate 的 component-wise vector conversion、跨 stage loop guard 符号冲突、Standard Blur 静态 tint 准入和 Fire 标量 LOD data sampling 已分别修正，目标 Program 均有 CPU invocation、GPU completion、publication 与 terminal/next-frame 证据。该结论只关闭四个已登记 effect-local 首断点；`3395777145` 与 `3754630802` 仍有下述 active unsupported effect，不能写成整样本视觉完成。

## 2. 现役执行顺序

### Q1 — `3395777145 / 3754630802` 的 active unsupported authored effect

**状态：当前最高优先级，已有 fresh 首断点。**

`3395777145` 现有 25 个 active effect，其中 22 个已由 Program 执行；layer 125 的两项 Workshop Blend 与一项 BlendGradient 仍为 `unified-capability-unavailable / r5-no-runtime-owner`。ready/after 截图中的房间、时钟和动态声波存在，但作者 preview 的墙面海报/文字缺失，优先从这三项的 authored source、resource、graph role 和 output contract 建立公共 owner，不按样本或路径分派。

`3754630802` 现有 31 个 active effect，其中 29 个已由 Program 执行；layer 607 的 Workshop Bokeh Blur 与 layer 743 的 Motion Blur 仍为相同的无 owner 状态。当前人物、舞狮、灯笼、火焰与大范围动态均可见，尚无隔离 ROI 证明这两个 effect 的视觉贡献；先在 `3395777145` 闭合共享能力，再用该样本作为同一 owner 的正反回归。完成门必须包含 typed admission、CPU encode、GPU completion、publication、terminal/next-frame 和相称视觉对照。

### Q2 — 已确认的用户可见债务与人工重新裁决

**状态：P2/P4 开放。**

- `3787382101`：Water Waves 仍影响人物全身，尚未证明位移受作者 mask 限制。这是当前明确保留的视觉缺口。
- 验收覆盖层中的其他 `fail` 与 `unreviewed` 必须逐个由维护者重新观看。`3264246690 / 3780119725 / 3238423642` 的旧 Puppet 模糊、缺头、错位技术原因已被 2026-09-13 证据取代，但没有维护者的新 verdict 时不得直接改成整样本 `pass`。
- 新发现的公共首断点回到 P1/P2；结构 PASS、非黑截图、route 数或完成事件不能单独改变人工 verdict。

### Q3 — SceneScript TextureAnimation 官方 API

**状态：能力缺口，需独立立项。**

普通 TEX autoplay 已是 bounded L3；`thisLayer.getTextureAnimation().setFrame(...)` 以及 frame/rate/play/pause/stop/join 等 SceneScript handle 仍为 L0。现存 corpus 中曾有 20 个相关样本，15 个在旧归档中 strict PASS，剩余失败表现为 typed `TypeError`；这些数量不是当前 HEAD 的完成统计。实现必须先建立公开 API 证据、instance-local identity、时钟/seek 冲突、generation 与 teardown 合同，再接入唯一 timeline/texture provider，不能恢复已退役的 fixed profile owner。现役等级见[SceneScript API 覆盖表](semantics/scenescript-api-coverage.md)。

### Q4 — authored `nomip` / `halfmip` sampler policy

**状态：次级纹理合同缺口。**

当前 texture upload 可以生成 mip，但作者 TEX V5 的 `nomip` / `halfmip` 状态尚未进入 sampler/LOD policy。实现需要从格式解析、prepared texture description、upload/storage 到 material sampler 保留同一 typed 意图；不得通过 effect 名称、路径或样本身份选择策略。完成门包含状态组合正反例、普通图片无回归和一个真实 authored consumer 的可见证据。

### Q5 — 作者参数、视觉验收与 tracked matrix

**状态：P0/P3/P4 长期开放。**

- tracked full-corpus identity-only matrix 尚未覆盖真实样本根全部成员；扩展矩阵不等于每个开发批次都运行全 corpus。
- script instance、particle override、bloom、camera 等 authored target 族仍需完成 property panel → typed snapshot → consumer → next-frame/event 的纵向闭环，或明确标为平台策略。
- 全部样本最终必须由人工裁决为 `pass` 或显式 `platform-unsupported`。当前开发仍按公共首断点和受影响样本推进，不用大批量回放代替逐项可见验收。

### Q6 — 稳定帧性能、长稳与发布

**状态：P5；只有已妨碍当前样本正确播放时提前。**

旧 B7 对 Puppet source-update、coverage texture 和固定 `16.67 ms` 的归因已经失效。2026-09-13 四样本回放只说明当前 CPU/GPU 帧时间仍值得重新 profile；它没有建立发布阈值，也不能证明旧 source-update 是当前热点。进入本项时必须在当前 GeometryProduct/graph/compositor 路径重新采样，先区分 CPU submission、GPU execution、display cadence 与 benchmark driver，再按共享 owner 降本。系统性阈值、睡眠/唤醒、显示器变化、场景切换和签名发布门由 P5 建立。

## 3. 观察项与能力边界

以下内容不作为当前产品修复，除非新的定向复现把它们提升为最早可见断点：

- 偶发且能自愈的 `frame-target-plan-allocation-failed` reset；保留诊断，先取得稳定复现再改 owner。
- 异步 provider 首帧 `layer-source-not-ready`；B8 已按公开合同定案为局部 previous-current/fallback 后自然恢复，不增加阻塞等待。若超时后仍未恢复，再按 provider 生命周期缺口处理。
- Puppet 跨层 geometry provider、rotation/gravity/IK、完整 3D 和逐像素官方 parity。当前命名 provider 只接受完整栅格 layer source，不能为了这些能力重新引入 Puppet 压平纹理。
- 旧 appendix 中未被当前运行证据复现的线索。能力宽度查[能力台账](semantics/coverage-ledger.md)，逐样本历史查[样本调试台账](semantics/scene-sample-debug-ledger.md)，不要从本队列复制历史数量。

## 4. B1–B9 退役索引

| 旧批次 | 当前结论 | 后继归属 |
| --- | --- | --- |
| B1 shader backend vector2 | 公共编译首断点已结构闭合 | 新 visual/parameter 缺口进入 Q2/Q5 |
| B2 dependency binding/publication | provider、隐藏 text dependency 与下游消费观察已闭合 | 新 graph first failure 进入 Q1 |
| B3 SceneScript event/property | 已登记的 event-only、visibility 与 property color/vector 链已闭合 | 未实现官方 API 进入 Q3/Q5 |
| B4 material envelope | 已登记 shape/format/compose owner 闭合 | 新 effect family 依路线 P1 归类 |
| B5 graph owner/publication | 2026-09-13 已分离 feedback persistence 与 content semantic；`3749463715` color terminal consumption、`3448845950` typed data publication 均闭合 | 新 graph 缺口按 Q1 或路线 P1 归类 |
| B6 QuickJS typed semantics | 原 angle/Vec3/string/error 子断点闭合 | 新 API 按 Q3/Q5 建合同 |
| B7 performance | 启动/teardown 与旧 micro-optimization 批次结束；稳定帧工作未完成 | Q6，用当前架构重建 profile |
| B8 async readiness | 合同闭合，首帧局部失败保持可观察并自然恢复 | §3 观察项 |
| B9 Puppet interaction/geometry | cursor→bone 与 2026-09-13 世界空间直绘闭合 | Q2 人工验收；高级能力见 §3 |

旧 B1–B9 的逐次命令、临时路径、历史 HEAD 和中间失败保留在 Git 历史及语义证据文档中，不再作为现役执行说明。

## 5. 队列维护与批次门

1. 开始条目前先用当前签名 App 和最小样本集刷新首断点；不继承旧报告中的行号、耗时、数量或 owner 归因。
2. 一个职责批次必须同时完成产品实现、focused 正反门、checkpoint build、受影响真实样本证据和权威文档同步，再提交一次。不得以单文件或单行提交拆散能力项。
3. 普通开发批次禁止运行全量样本；只有路线 milestone 确实需要刷新整体集群时才运行，并仍不得把 strict PASS 当成视觉通过。
4. 设计错误直接删除或重写；不得通过增加纹理预算、扩大缓存、堆叠 fallback 或按样本分支掩盖根因。
5. 每次只在本文保留尚能驱动下一步的事实。已完成条目压缩进退役索引，详细证据写入对应能力/运行/样本台账。

当 Q1–Q4 的当前公共断点均关闭，后续工作只剩路线 P0/P3/P4/P5 的系统性验收时，删除这个日期化派生入口或将其移入历史目录。
