# Batch 2 设计导航

本目录保存仍有效的能力设计合同及必要派生证据；包含已实施和未覆盖profile，不是待实施清单。本文导航设计裁决，不定义新的实施顺序或维护运行能力计数。设计完成登记见 [设计门禁清单](../../../../script/design_gated_areas.json)，Scene 实施顺序仍由[兼容路线](../scene-compatibility-roadmap.md)决定。

| 卡 | 设计与责任范围 |
|---|---|
| D1 | [composition 采集范围、source 与目标生命周期（重新裁决）](composition-render-target-design.md) |
| D2 | [Scene HDR、tone mapping 与 EDR 输出](hdr-tonemap-edr-design.md) |
| D3 | [2D 材质光照、PBR 与阴影](2d-lighting-material-design.md) |
| D4 | [SceneScript component、object 与 particle API](script-component-api-design.md)；[Layer host已收尾](../../history/layer-reference-responsibility-convergence-2026-10-13.md) |
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

播放器输入的单producer、来源准入与退出合同见[媒体输入设计](system-media-input-design.md)。已有能力与未覆盖来源分别查[实施记录](../../history/scene-system-media-input-implementation-2026-10-05.md)和[平台供应/自然换曲验证](../../history/system-media-live-supply-verification-2026-10-06.md)，不重复建立统一入口；私有后端仍受D6限制，新的实际缺口由总路线选题。

后续实施与59项参考证据的去向见[派生实施卡](reference-evidence-implementation-cards.md)，选序仍归上述兼容路线；原设计基线的“仅文档”描述不代表后续产品实施状态。

终端细线的有界实现已完成，设计[归档](../../history/terminal-material-raster-design-2026-10-06.md)，现役职责由[运行架构](../../architecture/runtime-architecture.md#terminal-material-raster)接管；不再作为待实施卡。

## 设计与实施边界

设计登记的`approved`只表示限定方案可实施，不代表全部profile、官方parity或发布通过。当前owner/消费者须重核源码，原独立设计基线`93b1b85a`及历史行号不再定义实现状态。D1以现composition合同为准，不回退parent-only旧方案；D6私有backend默认不启用，D4/D11未确认API/reset继续遵守各卡准入，D9/D10沿既有policy/gate，不造第二时钟或重试链。

本导航不保存已完成过程、合并指令、固定开发分支或测试清单。开放问题归[队列](../scene-open-breakpoint-queue.md)，设计的长期合同保留；无独有合同/证据的过程在触达时删除，完成记录按原history链接查询。新增能力沿AGENTS与现设计门，不能把旧卡中的“仅文档/将实施”当作当前缺能力事实。

后继见[终端材质链](terminal-material-chain-design.md)；视频asset设计已[归档](../../history/material-video-assets-2026-10-12.md)，合同归[材质合同](../../capabilities/material-video-assets.md)。
