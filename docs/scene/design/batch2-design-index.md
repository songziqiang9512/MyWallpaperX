# Batch 2 设计导航

本文只导航设计裁决，不定义新的实施顺序或维护运行能力计数。设计完成登记见 [设计门禁清单](../../../script/design_gated_areas.json)，Scene 实施顺序仍由[兼容路线](../scene-compatibility-roadmap.md)决定。

| 卡 | 设计与责任范围 |
|---|---|
| D1 | [composition 组独立渲染目标](composition-render-target-design.md) |
| D2 | [Scene HDR、tone mapping 与 EDR 输出](hdr-tonemap-edr-design.md) |
| D3 | [2D 材质光照、PBR 与阴影](2d-lighting-material-design.md) |
| D4 | [SceneScript component、object 与 particle API](script-component-api-design.md) |
| D5 | [Web 跨源 frame 定向回包与宿主推送](../../web/cross-origin-reply-delivery-design.md) |
| D6 | [Web 系统 now-playing 数据源与单一媒体状态](../../web/mediaremote-nowplaying-design.md) |
| D7 | [Steam 下载页失败条目可见性](../../web/steam-downloads-failed-items-visibility-design.md) |
| D8 | [RT 名称单点准入与分派](rt-prefix-admission-design.md) |
| D9 | [宿主到渲染的 run、throttle、pause 协议](host-render-power-protocol-design.md) |
| D10 | [帧不重叠准入与 busy 重探测](frame-admission-retry-design.md) |
| D11 | [粒子对象播放门与 reset 边界](particle-playback-state-design.md) |
| D12 | [四类 copy 触发点的 graph 语义收敛](copy-pass-unification-design.md) |

## 基线与合并边界

本批只编写设计。证据行号固定于独立工作树 `93b1b85a`；主开发分支 `codex/engine-refactor-program` 有更晚改动，合并时必须按实际 HEAD 重核 owner 与现有实现。主分支的七项登记仅用于对齐 ID/模式/schema，不把其余产品改动复制到此工作树。

本基线不存在交接中的缺口分析、六域逐条裁决和画质审查三份历史文件，Web 中继符号也未命中；D3 所引点光 ROI 条目未找到。各卡以当前源码与公开行为合同修正这些线索，没有把未复现样本或第三方观察升级为事实。官方静态取证页只读取角色/边界说明，未读取反编译表达；本批无新静态取证、无私有算法/地址/公式。

`approved` 表示可按文档的限定范围进入实施，不表示全部 profile、官方 parity 或发布已通过。D6 默认产品 route 仍不启用私有 backend；D4/D11 未确认 API/reset 的分支仍禁用。D10 首先核实既有 gate 与短重试，不增设第二条时钟链。

本独立基线没有 `script/check_design_gate.py`，JSON 是可审查登记而非已接入 CI 的自动拦截。合并须按 ID 合并 12 项，保留主分支其他条目、policy 与 checker；尤其不能用本工作树的新文件覆盖并行任务新增的登记。结构预算不在本设计批次修改，实施时按实际家族计数审查、增减同批 ratchet。

每卡写入 owner、route、失败半径和正反实施门；没有运行 GPU/VM/WebKit/Steam 实验，也未修改能力台账、运行证据或重构计划。设计不能替代这些权威。
