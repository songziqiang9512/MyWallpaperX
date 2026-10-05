# Batch 2 设计导航

本目录保存 Batch 2 后续将实施的现役设计与派生卡。本文导航设计裁决，不定义新的实施顺序或维护运行能力计数。设计完成登记见 [设计门禁清单](../../../../script/design_gated_areas.json)，Scene 实施顺序仍由[兼容路线](../scene-compatibility-roadmap.md)决定。

| 卡 | 设计与责任范围 |
|---|---|
| D1 | [composition 采集范围、source 与目标生命周期（重新裁决）](composition-render-target-design.md) |
| D2 | [Scene HDR、tone mapping 与 EDR 输出](hdr-tonemap-edr-design.md) |
| D3 | [2D 材质光照、PBR 与阴影](2d-lighting-material-design.md) |
| D4 | [SceneScript component、object 与 particle API](script-component-api-design.md) |
| D5 | [Web 跨源 frame 定向回包与宿主推送](../../../web/cross-origin-reply-delivery-design.md) |
| D6 | [Web 系统 now-playing 数据源与单一媒体状态](../../../web/mediaremote-nowplaying-design.md) |
| D7 | [Steam 下载页失败条目可见性](../../../web/steam-downloads-failed-items-visibility-design.md) |
| D8 | [RT 名称单点准入与分派](rt-prefix-admission-design.md) |
| D9 | [宿主到渲染的 run、throttle、pause 协议](host-render-power-protocol-design.md) |
| D10 | [帧不重叠准入与 busy 重探测](frame-admission-retry-design.md) |
| D11 | [粒子对象播放门与 reset 边界](particle-playback-state-design.md) |
| D12 | [四类 copy 触发点的 graph 语义收敛](copy-pass-unification-design.md) |

十二项不按编号机械实施：当前选序及每批提交/下一批边界见[后继选序](../scene-compatibility-roadmap.md#batch-2-后继选序2026-10-02)。Scene 缺失能力持续落代码，已有能力按反例收敛；Web/App 项独立排队，私有后端遵守各卡限制。

粒子后继的独立行为裁决见[Vortex 后继设计](particle-vortex-design.md)、[Remap 后继设计](particle-remap-design.md)与[壁纸边界碰撞设计](particle-collision-bounds-design.md)，沿既有解释器与合成链实施。

文件纹理原位事务由[运行架构](../../architecture/runtime-architecture.md)接管；[实施记录](../../history/user-texture-live-update-implementation-2026-10-05.md)保存原设计与有界验证。

播放器输入见[Scene真实媒体来源设计](system-media-input-design.md)：优先闭合已取得网易云metadata的统一系统实验入口，Music公开只读接口保留为显式补充；单producer与退出沿现有媒体收件箱，私有后端仍受D6限制；真实Scene验收边界以设计链接的实施记录为准。

后续实施与59项参考证据的去向见[派生实施卡](reference-evidence-implementation-cards.md)，选序仍归上述兼容路线；原设计基线的“仅文档”描述不代表后续产品实施状态。

终端细线的有界实现已完成，设计[归档](../../history/terminal-material-raster-design-2026-10-06.md)，现役职责由[运行架构](../../architecture/runtime-architecture.md#terminal-material-raster)接管；不再作为待实施卡。

## 基线与合并边界

最初设计批次仅编写文档。原证据行号固定于独立工作树 `93b1b85a`；本批现已合入主开发分支 `codex/engine-refactor-program`；该分支有更晚产品改动，实施时须重核 owner 与现有实现，原基线观察不能当作最新能力结论。主分支的七项登记仅用于对齐 ID/模式/schema，不把其余产品改动复制到此工作树。

本基线不存在交接中的缺口分析、六域逐条裁决和画质审查三份历史文件，Web 中继符号也未命中；D3 所引点光 ROI 条目未找到。各卡以当前源码与公开行为合同修正这些线索，没有把未复现样本或第三方观察升级为事实。官方静态取证页只读取角色/边界说明，未读取反编译表达；本批无新静态取证、无私有算法/地址/公式。

`approved` 表示可按文档的限定范围进入实施，不表示全部 profile、官方 parity 或发布已通过。D1于2026-10-02因公开composition采集语义与旧parent-only方案冲突而重新进入设计裁决，不能沿旧方案实施。D6 默认产品 route 仍不启用私有 backend；D4/D11 未确认 API/reset 的分支仍禁用。D10 首先核实既有 gate 与短重试，不增设第二条时钟链。

原独立基线没有设计检查器；合入主开发分支后使用其既有 `script/check_design_gate.py` 与严格登记 schema。本批 12 项按 ID 合并，保留主分支其他条目、policy 与 checker；五判据移入各设计正文，不扩张检查器字段。带触发模式的条目受现役机器门检查，无模式条目仍按 AGENTS.md 人工判定职责范围。结构预算不在本设计批次修改，实施时按实际家族计数审查、增减同批 ratchet。

最初设计批次为每卡写入 owner、route、失败半径和正反实施门；该批次当时没有运行 GPU/VM/WebKit/Steam 实验，也未修改能力台账、运行证据或重构计划。后续实施与运行事实仍由相应现役台账和证据拥有，设计不能替代这些权威。
