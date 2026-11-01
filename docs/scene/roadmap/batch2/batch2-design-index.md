# Batch 2 设计导航

<!-- document-role: navigation -->

本目录保存跨组件专项的设计裁决。共同职责以[运行时总设计](../../architecture/runtime-architecture.md)和[组件合同](../../capabilities/runtime-systems-reference.md)为准；这里按专题链接其具体取舍，不组成另一套顶层架构或待办清单。旧 D 编号只用于定位，具体未闭范围查[兼容路线](../scene-compatibility-roadmap.md)与[修复队列](../scene-open-breakpoint-queue.md)。

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
| D10 | [共享模拟与独立屏幕提交](frame-admission-retry-design.md) |
| D11 | [粒子对象播放门与 reset 边界](particle-playback-state-design.md) |
| D12 | [四类 copy 触发点的 graph 语义收敛](copy-pass-unification-design.md) |

Scene 的[兼容选序](../scene-compatibility-roadmap.md#batch-2-后继选序2026-10-02)由总路线维护；Web/App 设计由各自专题承接。读取一张卡不表示它仍待实施，也不要求先完成全部旧编号才能处理当前用户问题。

粒子专题裁决见[Vortex](particle-vortex-design.md)、[Remap](particle-remap-design.md)、[壁纸边界碰撞](particle-collision-bounds-design.md)，实际范围由[粒子专项](../../capabilities/particle-component-coverage.md)及证据维护。

文件纹理原位事务由[运行架构](../../architecture/runtime-architecture.md)接管；[实施记录](../../history/user-texture-live-update-implementation-2026-10-05.md)保存原设计与有界验证。

播放器输入的单 producer、来源与退出合同见[媒体输入设计](system-media-input-design.md)。平台来源与真实运行范围查[输入专项](../../capabilities/runtime-input-property-coverage.md)，私有 backend 的边界由 D6 维护。

原参考证据实施卡已退役，仅保留[历史锚点](reference-evidence-implementation-cards.md)供追溯。固定原型的停止依据、Layer host、材质变体等完成过程由[历史索引](../../history/README.md)进入，不继续拥有实施顺序。

终端细线的有界实现已完成，设计[归档](../../history/terminal-material-raster-design-2026-10-06.md)，现役职责由[运行架构](../../architecture/runtime-architecture.md#terminal-material-raster)接管；不再作为待实施卡。

## 设计与实施边界

设计登记的 `approved` 只表示原限定方案可实施，不代表全部输入、官方一致性或发行通过。登记指向能承接决策的现役合同或专项设计；具体有界取舍与历史依据保留在 `design_notes`。共同合同接管且已经完成的窄登记可以退役，不能用历史完成记录或导航页继续授予执行范围。

当前 owner 和消费者需核对源码。D1 不回退 parent-only 旧方案；D4/D11 的未定 API/reset 不由总设计猜测补全；D9/D10 保持唯一策略、时钟与提交职责。原设计基线、历史行号及“仅文档/将实施”措辞均不定义当前状态。

终端输出取舍查[终端材质链](terminal-material-chain-design.md)，视频资源职责查[材质合同](../../capabilities/material-video-assets.md)。新增重要能力修订相应设计，完成过程归历史，不增设平行任务队列。
