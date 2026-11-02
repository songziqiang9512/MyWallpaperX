<!-- document-role: current-state -->
# Scene 当前运行证据摘要

本页按职责索引已记录的有界证据。各记录绑定自己的代码、输入、App 与执行日期；旧 PASS 或截图不代表当前 HEAD 已统一复验。当前能力查[能力台账](coverage-ledger.md#current-overview)，组件职责查[运行合同](runtime-systems-reference.md)，任务顺序从[Scene 入口](../README.md)选择路线。

<a id="current-snapshot"></a>
## 1. 当前证据快照

| 要查什么 | 阅读入口 |
|---|---|
| 启动、候选、会话、Surface 与退场 | [准备与生命周期](#evidence-lifecycle) |
| 脚本、Timeline、用户属性与热更新 | [脚本与属性](#evidence-script-properties) |
| Cursor、Audio、Media 与视频 | [输入与媒体](#evidence-input-media) |
| 文字、图片与资源准备 | [文字与图片](#evidence-text-image) |
| Shader、材质、graph 与最终合成 | [材质与合成](#evidence-material-graph) |
| 粒子、Sprite、Rope 与深度 | [Particle Systems](#evidence-particles) |
| Puppet、模型、骨骼、动画与裁剪 | [Puppet 与模型](#evidence-puppet-model) |
| 相机、光照、颜色与显示 | [相机与显示](#evidence-camera-display) |

各族未闭项以对应现役专项表和[唯一断点队列](../roadmap/scene-open-breakpoint-queue.md)为准；不同身份的历史记录不能合并成一次全引擎验收。

<a id="architecture-integration-20261102"></a>
### 架构迁移阶段证据

[2026-11-02冻结后验](../history/runtime-evidence-index.md#e-architecture-final-integration-20261102)记录11个能力族退出和12次direct-host跨族运行，仅是阶段证据，不能证明整体架构已完成。材质准备/帧边界、Sprite/当前拓扑与实际产品daemon验收继续按[唯一队列](../roadmap/scene-open-breakpoint-queue.md#51-顶层设计已裁决的代码职责重构)推进。登记范围内未证新增回退，原FAIL及改名文字、动态过渡/交互资格仍保留；暂停文字门已通过，三轮成本没有认领整体提速。完整语料、物理多屏、长期切换、能耗与正式Release未验；历史结果不因继续改造而重写或升级。

[M1](../history/material-preparation-boundaries-2026-11-02.md#m1-format-slot-handoff)已交接格式/槽位，[M2](../history/material-preparation-boundaries-2026-11-02.md#m2-prepared-uniform-frame)已收敛帧 template 与静态 uniform 计划；真实 GPU、签名 App 固定像素、原包/邻例分别有界通过，原载体失败保留。Launch、设备键、能力交接及产品 daemon 继续开放，不认领整体性能收益。

[Sprite/Timeline退休](../history/topology-lifecycle-2026-11-03.md#sprite-timeline-retirement)有真实VM、MPS事务、暂停冻结UV和同Session双Surface重建/恢复的有界证据；产品daemon控制链及其余活动消费者退休继续开放。

[直接shader结果/可选cache](../history/shader-result-cache-boundary-2026-11-03.md#optional-cache-adoption)复现旧App文件根白图，并由新App正常/文件根/只读根的固定像素门关闭该依赖；真实cache/GPU及原包边界分别保留，不外推整体性能。

[localStorage准备](../history/storage-preparation-2026-11-03.md#storage-before-frame)已用真实Candidate/同Session磁盘变更、19事务反例及相邻VM门确认帧不重新打开文件；保前任merge，不认领启动或能耗收益。

<a id="evidence-lifecycle"></a>
### 准备与生命周期

[启动结算](../../history/cross-topic/wallpaper-startup-optimization-completed-2026-10-25.md)保留候选、缓存及原始失败；[会话文字](../history/runtime-evidence-index.md#e-session-text-production-20261102)与[媒体封面](../history/runtime-evidence-index.md#e-session-media-production-20261102)分别记录生产、冻结消费与退场。瞬态峰值、物理多屏、长稳及整体性能不能由这些独立记录合并推出；当前 owner 查[代码地图](../architecture/runtime-as-built-map.md)。

<a id="evidence-script-properties"></a>
### 脚本与属性

[统一文字/alpha VM](../history/runtime-evidence-current-through-2026-11-02.md#text-vm-convergence-20261102)、[命令保序](../history/runtime-evidence-current-through-2026-11-02.md#timeline-command-owner-order-20261018)及[属性准备](../history/runtime-evidence-current-through-2026-11-02.md#e-property-preparation-reuse)有各自限定记录。跨 pass Combined、全部 API、响应数学与整面板收益仍按[SceneScript](scenescript-api-coverage.md)及[属性输入](runtime-input-property-coverage.md)分项裁决。

<a id="evidence-input-media"></a>
### 输入与媒体

[物理 Cursor 与最终放置](../history/runtime-evidence-current-through-2026-11-02.md#physical-pointer-ingress-20261023)、[音频 IPC](../history/runtime-evidence-current-through-2026-11-02.md#audio-ipc-version-20261021)和[视频定位/供帧](material-video-assets.md#video-position-publication)按各自输入与观测边界读取。合成注入、单窗短播不外推物理输入、真实系统来源、跨 loop、所有 seek/多实例组合；当前范围查[输入合同](runtime-input-property-coverage.md)与[视频合同](material-video-assets.md)。

<a id="evidence-text-image"></a>
### 文字与图片

[会话文字](../history/runtime-evidence-index.md#e-session-text-production-20261102)、[动态出生](../history/runtime-evidence-index.md#e-dynamic-layer-preparation-20261102)、[图片几何准备复用](../history/runtime-evidence-index.md#e-prepared-image-geometry-reuse-20261102)和[用户纹理结果转移](../history/runtime-evidence-index.md#e-user-texture-session-ownership-20261102)保留各自输出与退场边界。字体精确像素、全部动态实例组合及整样本结果不据此提升；语义与缺口查[Text/动态层 API](scenescript-api-coverage.md)和[高级对象](advanced-object-coverage.md)。

<a id="evidence-material-graph"></a>
### 材质与合成

[共享 shader/source/终端](../history/runtime-evidence-current-through-2026-11-02.md#audio-index-preparation-order-20261018)、[局部 composition](../history/runtime-evidence-current-through-2026-11-02.md#composition-local-source-20261018)及[provider 保全](../history/runtime-evidence-current-through-2026-11-02.md#selected-provider-admission-20261018)分别保留执行、像素、局部失败与反例。跨 pass Combined、完整 effect/HDR 组合及官方同相位仍按[shader/graph](render-graph-shader-coverage.md)与[effect](effect-execution-coverage.md)逐项判断。

<a id="evidence-particles"></a>
### Particle Systems

[Surface 实例与 GPU 后验](../history/runtime-evidence-index.md#e-particle-surface-gpu-ownership-20261102)及[同层只读折射深度](../history/particle-material-depth-2026-11-01.md#bounded-result)保留相应生命周期、邻例和原矩阵/呈现 FAIL。参数资格 STOP、整图相位、物理多屏及整体性能边界保持；逐项入口查[粒子合同与状态](particle-component-coverage.md)。

<a id="evidence-puppet-model"></a>
### Puppet 与模型

[Surface/GPU 后验](../history/runtime-evidence-index.md#e-puppet-surface-gpu-ownership-20261102)、[骨骼与条件动画](direct-model-skeletal-animation.md)及[裁剪](puppet-clipping-design.md)分别保留冻结顶点、输出、CPU 回退、出生/销毁与交互范围，原 benchmark 失败仍保留。完整版本族、附加动作、物理/API 组合及官方同相位不合并声明通过；缺口查[高级对象](advanced-object-coverage.md)与[SceneScript](scenescript-api-coverage.md)。

<a id="evidence-camera-display"></a>
### 相机与显示

[当前相机拓扑](../history/camera-current-topology-2026-11-03.md#current-camera-topology)：真实factory与新/旧签名App同输入，删除、排序、无camera回退及原角度固定双深度ROI通过；保原粒子/cursor、Default2D及Puppet邻例。

[默认/原生相机](../history/runtime-evidence-current-through-2026-11-02.md#native-camera-frame-transforms-20261019)、[颜色与显示边界](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-hdr-color-boundary)及[灯影记录](../history/runtime-evidence-current-through-2026-11-02.md#static-model-depth-pending-20261019)只覆盖原记录输入。[反射原型未接纳](../history/runtime-evidence-current-through-2026-11-02.md#model-reflection-prototype-20261018)及低能光照等未闭边界保留；当前目标查[2D/模型光照设计](../roadmap/batch2/2d-lighting-material-design.md)与[输入状态](runtime-input-property-coverage.md)。

<a id="evidence-levels"></a>

## 2. 运行证据深度 S0–S5

本页采用唯一的运行证据深度口径：

| 深度 | 原始标记 |
|---|---|
| S0 | `S0 missing/unknown` |
| S1 | `S1 preserved` |
| S2 | `S2 wired` |
| S3 | `S3 executed` |
| S4 | `S4 visible` |
| S5 | `S5 parity-ready` |

`S0` 只表示精确能力 identity 没有已保存或可执行的项目证据，不证明官方没有该能力，也不决定待办优先级。每个非 `S0` 证据包必须明确代码/测试、实际运行身份、可见断言和未验证边界；缺少 fresh 产品运行的最新接线只能记 `S2`。 最终载荷由 `script/promote_scene_evidence.py` 归档到仓库忽略的本机证据缓存 `.artifacts/scene-evidence/runs/`，按[保留规则](../../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)固定身份和有界结论。旧 `docs/scene/evidence/` 与临时路径仅作当时 provenance，缺失时不能用摘要冒充 fresh 复现。

<a id="evidence-packages"></a>

## 3. 证据包

固定实验正文、App/输入身份、原始失败与 STOP 见[归整前完整快照](../history/runtime-evidence-current-through-2026-11-02.md)；更早批次仍从其原历史锚点进入，旧历史正文不在本批重写。页面下方保持原 URL 的兼容导航。

<a id="local-evidence-availability"></a>
旧本机路径只表示执行当时的 provenance。可用载荷和已清理来源查[样本验收台账](scene-sample-acceptance-ledger.md)；缺失载荷不能当作 fresh 复现，也不能据缓存消失重开已修反馈。

### 旧锚点兼容导航

<a id="2026-09-05-v4-particle-child-template-selection-index"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-05-v4-particle-child-template-selection-index) <!-- archive-redirect -->
<a id="2026-09-05-v4-puppet-physical-target-scaling历史已退役"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-05-v4-puppet-physical-target-scaling历史已退役) <!-- archive-redirect -->
<a id="2026-09-06-puppet-frame-溢出适配-mdlv0019-版本族"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-06-puppet-frame-溢出适配-mdlv0019-版本族) <!-- archive-redirect -->
<a id="2026-09-06-puppet-layered-组合与-loopmirrorsingle-interval-采样"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-06-puppet-layered-组合与-loopmirrorsingle-interval-采样) <!-- archive-redirect -->
<a id="2026-09-06-当前三样本-puppet-资源发布与整链回归"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-06-当前三样本-puppet-资源发布与整链回归) <!-- archive-redirect -->
<a id="2026-09-08-audio-bars-布尔标量进入通用数值转换"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-audio-bars-布尔标量进入通用数值转换) <!-- archive-redirect -->
<a id="2026-09-08-pointer-顶部边界与视差纵向坐标"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-pointer-顶部边界与视差纵向坐标) <!-- archive-redirect -->
<a id="2026-09-08-scenescript-string-callback-only-quiescence-authored-text-provider"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-scenescript-string-callback-only-quiescence-authored-text-provider) <!-- archive-redirect -->
<a id="2026-09-08-tex媒体身份与首帧局部准入"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-tex媒体身份与首帧局部准入) <!-- archive-redirect -->
<a id="2026-09-08-utility-model-与-projection-共用有效-camera-决策"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-utility-model-与-projection-共用有效-camera-决策) <!-- archive-redirect -->
<a id="2026-09-08-vector-prepared-input-schema-与正交旋转裁切"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-vector-prepared-input-schema-与正交旋转裁切) <!-- archive-redirect -->
<a id="2026-09-08-初始-text-texture-与-logical-size-同步发布"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-初始-text-texture-与-logical-size-同步发布) <!-- archive-redirect -->
<a id="2026-09-08-太阳系作者布局控制器与标签样式"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-太阳系作者布局控制器与标签样式) <!-- archive-redirect -->
<a id="2026-09-08-普通-app-异步-quickjs-handoff-与真实日期文字"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-普通-app-异步-quickjs-handoff-与真实日期文字) <!-- archive-redirect -->
<a id="2026-09-08-源颜色辅助函数与轨道恢复"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-源颜色辅助函数与轨道恢复) <!-- archive-redirect -->
<a id="2026-09-08-音频替换透明度与已有混合证明复用"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-08-音频替换透明度与已有混合证明复用) <!-- archive-redirect -->
<a id="2026-09-09-backend-vector2-interface-arithmetic-narrowing3749463715"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-09-backend-vector2-interface-arithmetic-narrowing3749463715) <!-- archive-redirect -->
<a id="2026-09-09-loop-guard-隔离运行3662790108"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-09-loop-guard-隔离运行3662790108) <!-- archive-redirect -->
<a id="2026-09-09-当前身份复跑与阶段判定"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-09-当前身份复跑与阶段判定) <!-- archive-redirect -->
<a id="2026-09-09-接手工作树与断点集群状态接手快照"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-09-接手工作树与断点集群状态接手快照) <!-- archive-redirect -->
<a id="2026-09-09-默认直色-fallback-的-dormant-graph-ingress-修正3749463715"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-09-默认直色-fallback-的-dormant-graph-ingress-修正3749463715) <!-- archive-redirect -->
<a id="2026-09-10-b3-event-only-scenescript-producer-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-b3-event-only-scenescript-producer-闭环) <!-- archive-redirect -->
<a id="2026-09-10-b3-颜色属性输入-scenescript-material-uniform"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-b3-颜色属性输入-scenescript-material-uniform) <!-- archive-redirect -->
<a id="2026-09-10-b5-packed-rgba-provider-颜色-consumer-执行闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-b5-packed-rgba-provider-颜色-consumer-执行闭环) <!-- archive-redirect -->
<a id="2026-09-10-b9-上层接线审核真实-bone-drag-与剩余可见验收"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-b9-上层接线审核真实-bone-drag-与剩余可见验收) <!-- archive-redirect -->
<a id="2026-09-10-b9-完成真实骨骼拖动限幅与-spring-回弹"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-b9-完成真实骨骼拖动限幅与-spring-回弹) <!-- archive-redirect -->
<a id="2026-09-10-puppet-骨骼身份坐标合同与矩阵复用b7b9"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-10-puppet-骨骼身份坐标合同与矩阵复用b7b9) <!-- archive-redirect -->
<a id="2026-09-11-b2-三处-dependency-binding-合同清零与-180691-执行"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-b2-三处-dependency-binding-合同清零与-180691-执行) <!-- archive-redirect -->
<a id="2026-09-11-b4-geodraw-严格闭合与-b5-379-公共合同收敛"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-b4-geodraw-严格闭合与-b5-379-公共合同收敛) <!-- archive-redirect -->
<a id="2026-09-11-b5-379-严格闭合scene-background-graphinternal-compose-优先级"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-b5-379-严格闭合scene-background-graphinternal-compose-优先级) <!-- archive-redirect -->
<a id="2026-09-11-b5-发布者消费归因-gate-闭合"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-b5-发布者消费归因-gate-闭合) <!-- archive-redirect -->
<a id="2026-09-11-b7-source-update-scratch-reuse"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-b7-source-update-scratch-reuse) <!-- archive-redirect -->
<a id="2026-09-11-回归断点visibility-owner-与-strict-compiler-boundary"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-11-回归断点visibility-owner-与-strict-compiler-boundary) <!-- archive-redirect -->
<a id="2026-09-13-3787382101-water-waves-作者-mask-同构-ab"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-3787382101-water-waves-作者-mask-同构-ab) <!-- archive-redirect -->
<a id="2026-09-13-camera-parallax-2d-camera-shake-live-user-property-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-camera-parallax-2d-camera-shake-live-user-property-闭环) <!-- archive-redirect -->
<a id="2026-09-13-feedback-生命周期与内容语义分离"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-feedback-生命周期与内容语义分离) <!-- archive-redirect -->
<a id="2026-09-13-puppet-geometryproduct-世界空间绘制闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-puppet-geometryproduct-世界空间绘制闭环) <!-- archive-redirect -->
<a id="2026-09-13-puppet-动态-attachment-current-pose-与真实拖拽闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-puppet-动态-attachment-current-pose-与真实拖拽闭环) <!-- archive-redirect -->
<a id="2026-09-13-scenescript-ilayergettransformmatrix-与只读-size-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-scenescript-ilayergettransformmatrix-与只读-size-闭环) <!-- archive-redirect -->
<a id="2026-09-13-scenescript-itextureanimation-公共-api-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-scenescript-itextureanimation-公共-api-闭环) <!-- archive-redirect -->
<a id="2026-09-13-shared-full-frame-pair-与-authored-fbo-history-terminal-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-shared-full-frame-pair-与-authored-fbo-history-terminal-闭环) <!-- archive-redirect -->
<a id="2026-09-13-作者-media-event-面板与同-provider-候选闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-作者-media-event-面板与同-provider-候选闭环) <!-- archive-redirect -->
<a id="2026-09-13-作者启动自销毁与-parentdefault-transform-点击闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-作者启动自销毁与-parentdefault-transform-点击闭环) <!-- archive-redirect -->
<a id="2026-09-13-四个-effect-local-首断点闭环与后继-unsupported-边界"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-四个-effect-local-首断点闭环与后继-unsupported-边界) <!-- archive-redirect -->
<a id="2026-09-13-编译-tex-mip-链权威与单级归一化闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-13-编译-tex-mip-链权威与单级归一化闭环) <!-- archive-redirect -->
<a id="2026-09-14-mdlv0014-mdls0002-puppet-geometryproduct-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-mdlv0014-mdls0002-puppet-geometryproduct-闭环) <!-- archive-redirect -->
<a id="2026-09-14-prepared-direct-draw-output-geometry-与-3747492842-顶部光束"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-prepared-direct-draw-output-geometry-与-3747492842-顶部光束) <!-- archive-redirect -->
<a id="2026-09-14-prepared-effect-参数执行与-emitted-geometry-projection-合同"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-prepared-effect-参数执行与-emitted-geometry-projection-合同) <!-- archive-redirect -->
<a id="2026-09-14-puppet-原始-atlas-与精确-effect-extent-闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-puppet-原始-atlas-与精确-effect-extent-闭环) <!-- archive-redirect -->
<a id="2026-09-14-video-provider-command-generation-与双视频循环同步"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-video-provider-command-generation-与双视频循环同步) <!-- archive-redirect -->
<a id="2026-09-14-三个历史主体人物消失观察的当前刷新"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-三个历史主体人物消失观察的当前刷新) <!-- archive-redirect -->
<a id="2026-09-14-同帧-shared-pair-驻留与-3749463715-唯一输出闭环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-14-同帧-shared-pair-驻留与-3749463715-唯一输出闭环) <!-- archive-redirect -->
<a id="2026-09-16-as1-仪器耦合分阶段遥测与-execution-observation-同标志重-graph-测得帧约一半是仪器"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as1-仪器耦合分阶段遥测与-execution-observation-同标志重-graph-测得帧约一半是仪器) <!-- archive-redirect -->
<a id="2026-09-16-as1-优化等级对照未优化-debug-基线不作产品代表"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as1-优化等级对照未优化-debug-基线不作产品代表) <!-- archive-redirect -->
<a id="2026-09-16-as1-去仪器产品代表性重-graph-基线"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as1-去仪器产品代表性重-graph-基线) <!-- archive-redirect -->
<a id="2026-09-16-as1-简单-workload-未优化-debug-基线进程-cpu-计量单位修复后"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as1-简单-workload-未优化-debug-基线进程-cpu-计量单位修复后) <!-- archive-redirect -->
<a id="2026-09-16-as1-重-graph-基线与-matrix-期望差异分类"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as1-重-graph-基线与-matrix-期望差异分类) <!-- archive-redirect -->
<a id="2026-09-16-as3-gpu-操作普查重-graph-每帧-23-个主-pass78-个-offscreen-pass0-个-blit-拷贝"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-as3-gpu-操作普查重-graph-每帧-23-个主-pass78-个-offscreen-pass0-个-blit-拷贝) <!-- archive-redirect -->
<a id="2026-09-16-e1c-消融普通帧不再整图序列化重-graph"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-e1c-消融普通帧不再整图序列化重-graph) <!-- archive-redirect -->
<a id="2026-09-16-重-graph-cpu-首断点根因每帧整图-json-序列化"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-16-重-graph-cpu-首断点根因每帧整图-json-序列化) <!-- archive-redirect -->
<a id="2026-09-22-light-shafts-raymode-012-共同直绘几何"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-22-light-shafts-raymode-012-共同直绘几何) <!-- archive-redirect -->
<a id="2026-09-22-light-shafts-线性直绘水平边界-overscan"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-22-light-shafts-线性直绘水平边界-overscan) <!-- archive-redirect -->
<a id="2026-09-28-combo-boolean-条件准入与特效准备共用现役链"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-28-combo-boolean-条件准入与特效准备共用现役链) <!-- archive-redirect -->
<a id="2026-09-28-初始隐藏根层的关闭特效准备补齐"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-28-初始隐藏根层的关闭特效准备补齐) <!-- archive-redirect -->
<a id="2026-09-28-条件脚本输入与启动覆盖的布局热切"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-28-条件脚本输入与启动覆盖的布局热切) <!-- archive-redirect -->
<a id="2026-09-28-混合布尔目标的effect准备去除重复限制"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#2026-09-28-混合布尔目标的effect准备去除重复限制) <!-- archive-redirect -->
<a id="4-原索引元数据与读取说明"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#4-原索引元数据与读取说明) <!-- archive-redirect -->
<a id="e-2026-09-09-default-straight-boundary-graph-ingress"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-09-default-straight-boundary-graph-ingress) <!-- archive-redirect -->
<a id="e-2026-09-09-vector2-interface-arithmetic"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-09-vector2-interface-arithmetic) <!-- archive-redirect -->
<a id="e-2026-09-10-b3-event-only-closure"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b3-event-only-closure) <!-- archive-redirect -->
<a id="e-2026-09-10-b3-property-vector-input"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b3-property-vector-input) <!-- archive-redirect -->
<a id="e-2026-09-10-b5-feedback-frontend"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b5-feedback-frontend) <!-- archive-redirect -->
<a id="e-2026-09-10-b5-typed-data-publication-progress"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b5-typed-data-publication-progress) <!-- archive-redirect -->
<a id="e-2026-09-10-b9-spring-closure"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b9-spring-closure) <!-- archive-redirect -->
<a id="e-2026-09-10-b9-wiring-review"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-b9-wiring-review) <!-- archive-redirect -->
<a id="e-2026-09-10-puppet-bone-frame"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-10-puppet-bone-frame) <!-- archive-redirect -->
<a id="e-2026-09-11-b2-dependency-binding-extension"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-11-b2-dependency-binding-extension) <!-- archive-redirect -->
<a id="e-2026-09-11-b45-379-background-compose-closure"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-11-b45-379-background-compose-closure) <!-- archive-redirect -->
<a id="e-2026-09-11-b45-geodraw-closure"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-11-b45-geodraw-closure) <!-- archive-redirect -->
<a id="e-2026-09-11-b5-provider-consumption-gate"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-11-b5-provider-consumption-gate) <!-- archive-redirect -->
<a id="e-2026-09-13-authored-media-panel"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-authored-media-panel) <!-- archive-redirect -->
<a id="e-2026-09-13-authored-startup-destroy-cursor"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-authored-startup-destroy-cursor) <!-- archive-redirect -->
<a id="e-2026-09-13-camera-live-properties"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-camera-live-properties) <!-- archive-redirect -->
<a id="e-2026-09-13-compiled-mip-chain"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-compiled-mip-chain) <!-- archive-redirect -->
<a id="e-2026-09-13-effect-local-four"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-effect-local-four) <!-- archive-redirect -->
<a id="e-2026-09-13-feedback-content-contract"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-feedback-content-contract) <!-- archive-redirect -->
<a id="e-2026-09-13-ilayer-world-matrix"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-ilayer-world-matrix) <!-- archive-redirect -->
<a id="e-2026-09-13-puppet-dynamic-attachment"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-puppet-dynamic-attachment) <!-- archive-redirect -->
<a id="e-2026-09-13-puppet-world-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-puppet-world-geometry) <!-- archive-redirect -->
<a id="e-2026-09-13-shared-pair-history-terminal"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-shared-pair-history-terminal) <!-- archive-redirect -->
<a id="e-2026-09-13-texture-animation-api"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-texture-animation-api) <!-- archive-redirect -->
<a id="e-2026-09-13-water-waves-mask-ab"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-13-water-waves-mask-ab) <!-- archive-redirect -->
<a id="e-2026-09-14-missing-subject-refresh"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-missing-subject-refresh) <!-- archive-redirect -->
<a id="e-2026-09-14-prepared-direct-draw-output-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-prepared-direct-draw-output-geometry) <!-- archive-redirect -->
<a id="e-2026-09-14-prepared-effect-parameter-contract"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-prepared-effect-parameter-contract) <!-- archive-redirect -->
<a id="e-2026-09-14-puppet-exact-atlas-effect-extent"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-puppet-exact-atlas-effect-extent) <!-- archive-redirect -->
<a id="e-2026-09-14-puppet-mdlv0014"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-puppet-mdlv0014) <!-- archive-redirect -->
<a id="e-2026-09-14-video-provider-command-generation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-video-provider-command-generation) <!-- archive-redirect -->
<a id="e-2026-09-14-whole-frame-shared-pair-residency"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-14-whole-frame-shared-pair-residency) <!-- archive-redirect -->
<a id="e-2026-09-16-as1-cpu-baseline"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as1-cpu-baseline) <!-- archive-redirect -->
<a id="e-2026-09-16-as1-decoupled-heavy-baseline"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as1-decoupled-heavy-baseline) <!-- archive-redirect -->
<a id="e-2026-09-16-as1-heavy-graph-baseline"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as1-heavy-graph-baseline) <!-- archive-redirect -->
<a id="e-2026-09-16-as1-instrument-coupling"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as1-instrument-coupling) <!-- archive-redirect -->
<a id="e-2026-09-16-as1-optimization-level"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as1-optimization-level) <!-- archive-redirect -->
<a id="e-2026-09-16-as3-gpu-operation-census"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-as3-gpu-operation-census) <!-- archive-redirect -->
<a id="e-2026-09-16-corpus-plan-audit"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-corpus-plan-audit) <!-- archive-redirect -->
<a id="e-2026-09-16-corpus-plan-audit-全量计划的输入与工具审计只读事实"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-corpus-plan-audit-全量计划的输入与工具审计只读事实) <!-- archive-redirect -->
<a id="e-2026-09-16-e1c-whole-graph-serialization-ablation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-e1c-whole-graph-serialization-ablation) <!-- archive-redirect -->
<a id="e-2026-09-16-heavy-graph-cpu-root-cause"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-16-heavy-graph-cpu-root-cause) <!-- archive-redirect -->
<a id="e-2026-09-17-geometry-named-publication"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-geometry-named-publication) <!-- archive-redirect -->
<a id="e-2026-09-17-geometry-named-publication-placement-exact-geometryproduct-闭合-puppet-跨层-publication"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-geometry-named-publication-placement-exact-geometryproduct-闭合-puppet-跨层-publication) <!-- archive-redirect -->
<a id="e-2026-09-17-p03-fullset-baseline-and-split-identity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-p03-fullset-baseline-and-split-identity) <!-- archive-redirect -->
<a id="e-2026-09-17-p03-fullset-baseline-and-split-identity-全量-sweep-是单二进制留存-report-曾含两个身份83-个未覆盖样本已于-2026-09-18-补齐159159-当时语料2026-09-23-语料更正为-172-个样本目录159-bare-id13-v2-布局13-个新样本尚无该身份证据"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-p03-fullset-baseline-and-split-identity-全量-sweep-是单二进制留存-report-曾含两个身份83-个未覆盖样本已于-2026-09-18-补齐159159-当时语料2026-09-23-语料更正为-172-个样本目录159-bare-id13-v2-布局13-个新样本尚无该身份证据) <!-- archive-redirect -->
<a id="e-2026-09-17-reference-viewport-uncontrolled"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-reference-viewport-uncontrolled) <!-- archive-redirect -->
<a id="e-2026-09-17-reference-viewport-uncontrolled-断点-1-参考图不可作绝对位置-oracle两个报告症状都不是产品缺陷"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-reference-viewport-uncontrolled-断点-1-参考图不可作绝对位置-oracle两个报告症状都不是产品缺陷) <!-- archive-redirect -->
<a id="e-2026-09-17-resident-target-budget"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-resident-target-budget) <!-- archive-redirect -->
<a id="e-2026-09-17-resident-target-budget-设备比例-target-驻留预算解除逐帧硬拒绝"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-resident-target-budget-设备比例-target-驻留预算解除逐帧硬拒绝) <!-- archive-redirect -->
<a id="e-2026-09-17-text-host-contract"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-text-host-contract) <!-- archive-redirect -->
<a id="e-2026-09-17-text-host-contract-text-成为共享-provider-host脚本与脚本属性绑定恢复-typed-消费"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-17-text-host-contract-text-成为共享-provider-host脚本与脚本属性绑定恢复-typed-消费) <!-- archive-redirect -->
<a id="e-2026-09-18-authored-layer-sort"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-authored-layer-sort) <!-- archive-redirect -->
<a id="e-2026-09-18-authored-layer-sort-脚本驱动的作者层重排"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-authored-layer-sort-脚本驱动的作者层重排) <!-- archive-redirect -->
<a id="e-2026-09-18-effect-visibility-live-channel"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-effect-visibility-live-channel) <!-- archive-redirect -->
<a id="e-2026-09-18-effect-visibility-live-channel-效果可见性脚本的实时通道"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-effect-visibility-live-channel-效果可见性脚本的实时通道) <!-- archive-redirect -->
<a id="e-2026-09-18-launch-visibility-optimistic"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-launch-visibility-optimistic) <!-- archive-redirect -->
<a id="e-2026-09-18-launch-visibility-optimistic-脚本拥有可见性的层不再被启动路由判死"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-launch-visibility-optimistic-脚本拥有可见性的层不再被启动路由判死) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-badreturn-retry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-badreturn-retry) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-badreturn-retry-数据型-bad-return-改为逐帧重试"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-badreturn-retry-数据型-bad-return-改为逐帧重试) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-event-only-owners"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-event-only-owners) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-event-only-owners-bool-事件-only-owner-合法构造与每帧跳过"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-event-only-owners-bool-事件-only-owner-合法构造与每帧跳过) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-object-model-layer-object"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-object-model-layer-object) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-object-model-layer-object-layer-属性脚本的-thisobject-是层自身对象"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-object-model-layer-object-layer-属性脚本的-thisobject-是层自身对象) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-value-coercion"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-value-coercion) <!-- archive-redirect -->
<a id="e-2026-09-18-scenescript-value-coercion-vecmix-与字符串属性-number-返回强转"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-18-scenescript-value-coercion-vecmix-与字符串属性-number-返回强转) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-capture-resource-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-capture-resource-retirement) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-capture-resource-retirement-live-tapaggregate-销毁后由单一-start-gate-延迟重建真实-scope-切换不再先失败一次"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-capture-resource-retirement-live-tapaggregate-销毁后由单一-start-gate-延迟重建真实-scope-切换不再先失败一次) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-daemon-product-bridge"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-daemon-product-bridge) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-daemon-product-bridge-daemon需求回到主app唯一taptyped快照以latest-only命令返回daemon-local-inbox"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-daemon-product-bridge-daemon需求回到主app唯一taptyped快照以latest-only命令返回daemon-local-inbox) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-product-entry-corpus-baseline"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-product-entry-corpus-baseline) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-product-entry-corpus-baseline-120-个声明关系样本沿普通产品入口完成首断点分桶"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-product-entry-corpus-baseline-120-个声明关系样本沿普通产品入口完成首断点分桶) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-programmatic-product-entry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-programmatic-product-entry) <!-- archive-redirect -->
<a id="e-2026-09-20-audio-programmatic-product-entry-真实-steamworkshopservice-通知入口到-daemon-非零频谱可执行"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-audio-programmatic-product-entry-真实-steamworkshopservice-通知入口到-daemon-非零频谱可执行) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-optional-normal"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-optional-normal) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-optional-normal-strict-refract-接受公开合同允许的省略-normal真实-pointer-emitter-样本解除-material-准入阻断"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-optional-normal-strict-refract-接受公开合同允许的省略-normal真实-pointer-emitter-样本解除-material-准入阻断) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-pointer-emitter"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-pointer-emitter) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-pointer-emitter-显式-cp1-emitter-已接入公共-pointer-frame旧冻结运行当时被-refract-material-准入阻断"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-pointer-emitter-显式-cp1-emitter-已接入公共-pointer-frame旧冻结运行当时被-refract-material-准入阻断) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-pointer-trajectory"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-pointer-trajectory) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-pointer-trajectory-连续pointer输入不再拥有previous派生状态真实shuriken-cursor四点序列达到有界s4"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-pointer-trajectory-连续pointer输入不再拥有previous派生状态真实shuriken-cursor四点序列达到有界s4) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-subframe-lifetime"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-subframe-lifetime) <!-- archive-redirect -->
<a id="e-2026-09-20-particle-subframe-lifetime-同一显示回调内出生并死亡的-sprite-保留一次-birth-state-render-sample真实-shuriken-cursor-达到有界-s4"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-particle-subframe-lifetime-同一显示回调内出生并死亡的-sprite-保留一次-birth-state-render-sample真实-shuriken-cursor-达到有界-s4) <!-- archive-redirect -->
<a id="e-2026-09-20-point-light-static-model"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-point-light-static-model) <!-- archive-redirect -->
<a id="e-2026-09-20-point-light-static-model-lpointpoint声明进入共享四灯snapshot与direct-static-model-metal-consumer真实样本达到s3-executed"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-point-light-static-model-lpointpoint声明进入共享四灯snapshot与direct-static-model-metal-consumer真实样本达到s3-executed) <!-- archive-redirect -->
<a id="e-2026-09-20-shared-light-intensity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-shared-light-intensity) <!-- archive-redirect -->
<a id="e-2026-09-20-shared-light-intensity-userscenescript-light-intensity进入唯一typed-snapshot与共享光照consumerdirectional真实样本达到有界s4"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-shared-light-intensity-userscenescript-light-intensity进入唯一typed-snapshot与共享光照consumerdirectional真实样本达到有界s4) <!-- archive-redirect -->
<a id="e-2026-09-20-xray-effect-projection"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-xray-effect-projection) <!-- archive-redirect -->
<a id="e-2026-09-20-xray-effect-projection-effect-texture-inverse与output-mvp分权真实x-ray四象限轨迹达到有界s4"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-20-xray-effect-projection-effect-texture-inverse与output-mvp分权真实x-ray四象限轨迹达到有界s4) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-3765760121-condition"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-3765760121-condition) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-3765760121-condition-音频感应typed启动条件接通真实64-band-material-consumer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-3765760121-condition-音频感应typed启动条件接通真实64-band-material-consumer) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-author-reachable-consumer-inventory"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-author-reachable-consumer-inventory) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-author-reachable-consumer-inventory-跨4个已登记构建身份的78个作者可达音频样本保存日志执行关系"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-author-reachable-consumer-inventory-跨4个已登记构建身份的78个作者可达音频样本保存日志执行关系) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-conditional-consumers"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-conditional-consumers) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-conditional-consumers-typed启动属性闭合两个默认隐藏的音频consumer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-conditional-consumers-typed启动属性闭合两个默认隐藏的音频consumer) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-current-head-controlled-corpus"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-current-head-controlled-corpus) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-current-head-controlled-corpus-当前签名debug-app以普通system-tap重跑120样本产品入口基线"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-current-head-controlled-corpus-当前签名debug-app以普通system-tap重跑120样本产品入口基线) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-demand-switch-continuity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-demand-switch-continuity) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-demand-switch-continuity-surface-rebuild未知期不再撤销旧音频需求"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-demand-switch-continuity-surface-rebuild未知期不再撤销旧音频需求) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-no-demand-declaration-reconciliation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-no-demand-declaration-reconciliation) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-no-demand-declaration-reconciliation-41项默认no-demand声明闭合为未作者激活的负例"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-no-demand-declaration-reconciliation-41项默认no-demand声明闭合为未作者激活的负例) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-spectrum-band-distribution"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-spectrum-band-distribution) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-spectrum-band-distribution-共享-analyzer-恢复横轴频段分布并排除右半长时冻结"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-spectrum-band-distribution-共享-analyzer-恢复横轴频段分布并排除右半长时冻结) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-stateful-bool-media-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-stateful-bool-media-owner) <!-- archive-redirect -->
<a id="e-2026-09-21-audio-stateful-bool-media-owner-组合媒体事件与音频消费不再被-bool-owner-准入误拒"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-audio-stateful-bool-media-owner-组合媒体事件与音频消费不再被-bool-owner-准入误拒) <!-- archive-redirect -->
<a id="e-2026-09-21-cursor-audio-owner-refresh"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-cursor-audio-owner-refresh) <!-- archive-redirect -->
<a id="e-2026-09-21-cursor-audio-owner-refresh-cursor-callback-owner加入唯一demand并在事件前读取同帧频谱"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-cursor-audio-owner-refresh-cursor-callback-owner加入唯一demand并在事件前读取同帧频谱) <!-- archive-redirect -->
<a id="e-2026-09-21-particle-audio-component-execution"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-particle-audio-component-execution) <!-- archive-redirect -->
<a id="e-2026-09-21-particle-audio-component-execution-真实粒子组件在提交帧消费非零共享频谱"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-particle-audio-component-execution-真实粒子组件在提交帧消费非零共享频谱) <!-- archive-redirect -->
<a id="e-2026-09-21-scenescript-wevector-audio-ring"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-scenescript-wevector-audio-ring) <!-- archive-redirect -->
<a id="e-2026-09-21-scenescript-wevector-audio-ring-同一quickjs-module-owner恢复degree向量与vec3vec2频谱环"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-21-scenescript-wevector-audio-ring-同一quickjs-module-owner恢复degree向量与vec3vec2频谱环) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-cross-engine-volume"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-cross-engine-volume) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-cross-engine-volume-三引擎主音量静音公共控制合同"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-cross-engine-volume-三引擎主音量静音公共控制合同) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-named-samples-product-entry-recheck"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-named-samples-product-entry-recheck) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-named-samples-product-entry-recheck-213378-真实入口复核"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-named-samples-product-entry-recheck-213378-真实入口复核) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-ordinary-scene-web"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-ordinary-scene-web) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-ordinary-scene-web-已提交统一-producer-的普通系统声音代表入口"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-ordinary-scene-web-已提交统一-producer-的普通系统声音代表入口) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-overlay-ceiling"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-overlay-ceiling) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-overlay-ceiling-共享-producer-后-video-投影强输入同高夹断"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-overlay-ceiling-共享-producer-后-video-投影强输入同高夹断) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-rhythm-candidate"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-rhythm-candidate) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-rhythm-candidate-低频映射与能量起音候选代码已审查视觉未闭合"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-rhythm-candidate-低频映射与能量起音候选代码已审查视觉未闭合) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-rhythm-open"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-rhythm-open) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-rhythm-open-首档比例与节奏感仍为用户可见失败"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-rhythm-open-首档比例与节奏感仍为用户可见失败) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-shared-canonical-producer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-shared-canonical-producer) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-shared-canonical-producer-videowebscene-共用单一-pcm频谱-producer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-shared-canonical-producer-videowebscene-共用单一-pcm频谱-producer) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-spectrum-policy"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-spectrum-policy) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-spectrum-policy-三引擎系统频谱策略门与-daemon-旧快照清除"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-spectrum-policy-三引擎系统频谱策略门与-daemon-旧快照清除) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-spectrum-reference-envelope"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-spectrum-reference-envelope) <!-- archive-redirect -->
<a id="e-2026-09-22-audio-spectrum-reference-envelope-统一-producer-单次包络与无状态投影"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-audio-spectrum-reference-envelope-统一-producer-单次包络与无状态投影) <!-- archive-redirect -->
<a id="e-2026-09-22-light-shafts-border-overscan"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-light-shafts-border-overscan) <!-- archive-redirect -->
<a id="e-2026-09-22-light-shafts-raymode-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-light-shafts-raymode-geometry) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-aggregate-construction-work"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-aggregate-construction-work) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-aggregate-construction-work-实际-owner-构造计数与-fresh-domain-重建成本"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-aggregate-construction-work-实际-owner-构造计数与-fresh-domain-重建成本) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-aggregate-source-budget"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-aggregate-source-budget) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-aggregate-source-budget-互斥-vectorcursor-候选的重复预算审计与新首断点"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-aggregate-source-budget-互斥-vectorcursor-候选的重复预算审计与新首断点) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-cursor-only-admission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-cursor-only-admission) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-cursor-only-admission-visibility-的单一-typed-owner-与-quickjs-实际导出准入"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-cursor-only-admission-visibility-的单一-typed-owner-与-quickjs-实际导出准入) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-dynamic-layer-frame-values"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-dynamic-layer-frame-values) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-dynamic-layer-frame-values-动态图层逐帧-transform-不再被拓扑缓存冻结"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-dynamic-layer-frame-values-动态图层逐帧-transform-不再被拓扑缓存冻结) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-fresh-domain-preflight"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-fresh-domain-preflight) <!-- archive-redirect -->
<a id="e-2026-09-22-scenescript-fresh-domain-preflight-swift-only-预检失败不再触发-quickjs-fresh-domain-重建"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-22-scenescript-fresh-domain-preflight-swift-only-预检失败不再触发-quickjs-fresh-domain-重建) <!-- archive-redirect -->
<a id="e-2026-09-23-authored-numeric-float-range"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-authored-numeric-float-range) <!-- archive-redirect -->
<a id="e-2026-09-23-authored-numeric-float-range-作者数值收窄的可达性与饱和门"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-authored-numeric-float-range-作者数值收窄的可达性与饱和门) <!-- archive-redirect -->
<a id="e-2026-09-23-cursor-solid-host-contract"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-cursor-solid-host-contract) <!-- archive-redirect -->
<a id="e-2026-09-23-cursor-solid-host-contract-cursor-的官方-solid-合同effectpass-边界与语料分歧"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-cursor-solid-host-contract-cursor-的官方-solid-合同effectpass-边界与语料分歧) <!-- archive-redirect -->
<a id="e-2026-09-23-declaration-terminator-whitespace"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-declaration-terminator-whitespace) <!-- archive-redirect -->
<a id="e-2026-09-23-declaration-terminator-whitespace-声明行尾随空白不再被当作不支持的声明产品修复样本仍-fail"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-declaration-terminator-whitespace-声明行尾随空白不再被当作不支持的声明产品修复样本仍-fail) <!-- archive-redirect -->
<a id="e-2026-09-23-dynamic-layer-transform-range"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-dynamic-layer-transform-range) <!-- archive-redirect -->
<a id="e-2026-09-23-dynamic-layer-transform-range-动态层-descriptor-收窄的同一值域门"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-dynamic-layer-transform-range-动态层-descriptor-收窄的同一值域门) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-capture-chain"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-capture-chain) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-capture-chain-真实样本的-cursor-captureinside-与-click-受控取证"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-capture-chain-真实样本的-cursor-captureinside-与-click-受控取证) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-typed-drag"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-typed-drag) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-typed-drag-回调直接写-typed-属性的真实样本-drag-链"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-typed-drag-回调直接写-typed-属性的真实样本-drag-链) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-typed-target-ownership"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-typed-target-ownership) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-cursor-typed-target-ownership-cursor-owner-的精确-typed-target-身份与作者-init-顺序"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-cursor-typed-target-ownership-cursor-owner-的精确-typed-target-身份与作者-init-顺序) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-nonfinite-world-transform"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-nonfinite-world-transform) <!-- archive-redirect -->
<a id="e-2026-09-23-scenescript-nonfinite-world-transform-超出-float-可表示范围的动态变换收敛为该层自身"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-scenescript-nonfinite-world-transform-超出-float-可表示范围的动态变换收敛为该层自身) <!-- archive-redirect -->
<a id="e-2026-09-23-v2-layout-first-run"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-v2-layout-first-run) <!-- archive-redirect -->
<a id="e-2026-09-23-v2-layout-first-run-13-个-v2-布局样本的首次隔离运行11-pass-2-fail"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-v2-layout-first-run-13-个-v2-布局样本的首次隔离运行11-pass-2-fail) <!-- archive-redirect -->
<a id="e-2026-09-23-varying-prefix-partition"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-varying-prefix-partition) <!-- archive-redirect -->
<a id="e-2026-09-23-varying-prefix-partition-顶点分段初始化被前缀证明接受样本仍因内容限制-fail"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-23-varying-prefix-partition-顶点分段初始化被前缀证明接受样本仍因内容限制-fail) <!-- archive-redirect -->
<a id="e-2026-09-24-trail-bend-calibration-用官方预览斜率变化率定标轨迹弯曲两次修正确认错误并回退"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-24-trail-bend-calibration-用官方预览斜率变化率定标轨迹弯曲两次修正确认错误并回退) <!-- archive-redirect -->
<a id="e-2026-09-25-as1-regression-protection-rerun"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-25-as1-regression-protection-rerun) <!-- archive-redirect -->
<a id="e-2026-09-25-as1-regression-protection-rerun-head-复测cpu-改善present-完美但每帧-6-次-history-rehydration-拷贝回归e1c-前提失效"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-25-as1-regression-protection-rerun-head-复测cpu-改善present-完美但每帧-6-次-history-rehydration-拷贝回归e1c-前提失效) <!-- archive-redirect -->
<a id="e-2026-09-26-as3-alias-verdict"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-as3-alias-verdict) <!-- archive-redirect -->
<a id="e-2026-09-26-as3-alias-verdict-跨成员别名发布消融裁决有证据不实施渲染冒险-运行时条件成员调度"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-as3-alias-verdict-跨成员别名发布消融裁决有证据不实施渲染冒险-运行时条件成员调度) <!-- archive-redirect -->
<a id="e-2026-09-26-as3-copy-attribution"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-as3-copy-attribution) <!-- archive-redirect -->
<a id="e-2026-09-26-as3-copy-attribution-6-次帧拷贝归因d2b-激活直通的-ping-pong-成员保留拷贝非-rehydration"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-as3-copy-attribution-6-次帧拷贝归因d2b-激活直通的-ping-pong-成员保留拷贝非-rehydration) <!-- archive-redirect -->
<a id="e-2026-09-26-event-audio-admission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-event-audio-admission) <!-- archive-redirect -->
<a id="e-2026-09-26-event-audio-admission-事件-owner-允许音频并在回调前刷新"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-event-audio-admission-事件-owner-允许音频并在回调前刷新) <!-- archive-redirect -->
<a id="e-2026-09-26-initialization-transaction"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-initialization-transaction) <!-- archive-redirect -->
<a id="e-2026-09-26-initialization-transaction-初始化完成状态待消费值和-timer-随现有-owner-transaction-提交"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-initialization-transaction-初始化完成状态待消费值和-timer-随现有-owner-transaction-提交) <!-- archive-redirect -->
<a id="e-2026-09-26-stock-noise-preparation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-stock-noise-preparation) <!-- archive-redirect -->
<a id="e-2026-09-26-stock-noise-preparation-按需启动准备与默认纹理准入一致性"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-stock-noise-preparation-按需启动准备与默认纹理准入一致性) <!-- archive-redirect -->
<a id="e-2026-09-26-stock-noise-range-and-upload"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-stock-noise-range-and-upload) <!-- archive-redirect -->
<a id="e-2026-09-26-stock-noise-range-and-upload-固定噪声全量程与失败不发布"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-stock-noise-range-and-upload-固定噪声全量程与失败不发布) <!-- archive-redirect -->
<a id="e-2026-09-26-string-module-admission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-string-module-admission) <!-- archive-redirect -->
<a id="e-2026-09-26-string-module-admission-有效无帧回调模块不再误触发域重建"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-26-string-module-admission-有效无帧回调模块不再误触发域重建) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-capture-native-replay"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-capture-native-replay) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-capture-native-replay-连续采集修复接入原包画面验证"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-capture-native-replay-连续采集修复接入原包画面验证) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-contiguous-capture"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-contiguous-capture) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-contiguous-capture-频谱节流不再截断输入波形"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-contiguous-capture-频谱节流不再截断输入波形) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-continuous-bands"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-continuous-bands) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-continuous-bands-消除频谱永久空档并降低重复低频门原包音圈恢复部分可见"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-continuous-bands-消除频谱永久空档并降低重复低频门原包音圈恢复部分可见) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-real-music"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-real-music) <!-- archive-redirect -->
<a id="e-2026-09-27-audio-real-music-真实system-tap的音圈可见普通ipc收到非零频谱"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-audio-real-music-真实system-tap的音圈可见普通ipc收到非零频谱) <!-- archive-redirect -->
<a id="e-2026-09-27-child-capacity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-capacity) <!-- archive-redirect -->
<a id="e-2026-09-27-child-capacity-保留烟花爆发数量与活跃容量预算"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-capacity-保留烟花爆发数量与活跃容量预算) <!-- archive-redirect -->
<a id="e-2026-09-27-child-delayed-emission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-delayed-emission) <!-- archive-redirect -->
<a id="e-2026-09-27-child-delayed-emission-延迟粒子等待发射完成状态归回现有-emitter"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-delayed-emission-延迟粒子等待发射完成状态归回现有-emitter) <!-- archive-redirect -->
<a id="e-2026-09-27-child-instance-modifiers"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-instance-modifiers) <!-- archive-redirect -->
<a id="e-2026-09-27-child-instance-modifiers-子雾气继承层参数原样本泛白收敛"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-instance-modifiers-子雾气继承层参数原样本泛白收敛) <!-- archive-redirect -->
<a id="e-2026-09-27-child-offset-scale-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-offset-scale-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-27-child-offset-scale-diagnosis-静态子雾偏移对父缩放敏感合同仍待定"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-child-offset-scale-diagnosis-静态子雾偏移对父缩放敏感合同仍待定) <!-- archive-redirect -->
<a id="e-2026-09-27-conditional-cursor-binding"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-conditional-cursor-binding) <!-- archive-redirect -->
<a id="e-2026-09-27-conditional-cursor-binding-条件显隐脚本恢复加载点击后继接口仍缺失"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-conditional-cursor-binding-条件显隐脚本恢复加载点击后继接口仍缺失) <!-- archive-redirect -->
<a id="e-2026-09-27-cross-layer-effect-visibility"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-cross-layer-effect-visibility) <!-- archive-redirect -->
<a id="e-2026-09-27-cross-layer-effect-visibility-跨层特效显隐事务恢复点击切图隐藏层效果仍开放"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-cross-layer-effect-visibility-跨层特效显隐事务恢复点击切图隐藏层效果仍开放) <!-- archive-redirect -->
<a id="e-2026-09-27-cursor-owner-transaction"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-cursor-owner-transaction) <!-- archive-redirect -->
<a id="e-2026-09-27-cursor-owner-transaction-被拒-target-保留完整事件已接受-peer-不重放"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-cursor-owner-transaction-被拒-target-保留完整事件已接受-peer-不重放) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-additive"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-additive) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-additive-独立光束终端不再压暗背景"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-additive-独立光束终端不再压暗背景) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-coverage"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-coverage) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-coverage-独立光效恢复源透明度衰减"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-coverage-独立光效恢复源透明度衰减) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-square"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-square) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-draw-square-光束等边单位与旧顶部补偿退役"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-draw-square-光束等边单位与旧顶部补偿退役) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-quad-coverage-probe"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-quad-coverage-probe) <!-- archive-redirect -->
<a id="e-2026-09-27-direct-quad-coverage-probe-四点网格候选的定量筛选"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-direct-quad-coverage-probe-四点网格候选的定量筛选) <!-- archive-redirect -->
<a id="e-2026-09-27-dynamic-layer-capacity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-dynamic-layer-capacity) <!-- archive-redirect -->
<a id="e-2026-09-27-dynamic-layer-capacity-删除重复-owner64-限制原包后继非有限值错误仍开放"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-dynamic-layer-capacity-删除重复-owner64-限制原包后继非有限值错误仍开放) <!-- archive-redirect -->
<a id="e-2026-09-27-eight-visual-reports"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-eight-visual-reports) <!-- archive-redirect -->
<a id="e-2026-09-27-eight-visual-reports-用户实际播放反馈与静态输入核对"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-eight-visual-reports-用户实际播放反馈与静态输入核对) <!-- archive-redirect -->
<a id="e-2026-09-27-firework-emission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-firework-emission) <!-- archive-redirect -->
<a id="e-2026-09-27-firework-emission-非零音频不等于达到一粒的发射量"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-firework-emission-非零音频不等于达到一粒的发射量) <!-- archive-redirect -->
<a id="e-2026-09-27-firework-magenta-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-firework-magenta-geometry) <!-- archive-redirect -->
<a id="e-2026-09-27-firework-magenta-geometry-洋红缺陷的既有证据与径向中心位移"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-firework-magenta-geometry-洋红缺陷的既有证据与径向中心位移) <!-- archive-redirect -->
<a id="e-2026-09-27-frame-rejection"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-frame-rejection) <!-- archive-redirect -->
<a id="e-2026-09-27-frame-rejection-实际提交前拒帧同帧重试与下一帧完成"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-frame-rejection-实际提交前拒帧同帧重试与下一帧完成) <!-- archive-redirect -->
<a id="e-2026-09-27-gradient-stripe-isolation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-gradient-stripe-isolation) <!-- archive-redirect -->
<a id="e-2026-09-27-gradient-stripe-isolation-全屏移动细条纹的渐变循环归因"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-gradient-stripe-isolation-全屏移动细条纹的渐变循环归因) <!-- archive-redirect -->
<a id="e-2026-09-27-light-parallax-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-light-parallax-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-27-light-parallax-diagnosis-作者独立光束与背景深度视差分离核对"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-light-parallax-diagnosis-作者独立光束与背景深度视差分离核对) <!-- archive-redirect -->
<a id="e-2026-09-27-lightshaft-geometry-ablation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-lightshaft-geometry-ablation) <!-- archive-redirect -->
<a id="e-2026-09-27-lightshaft-geometry-ablation-同状态区分尺寸与标量轴候选"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-lightshaft-geometry-ablation-同状态区分尺寸与标量轴候选) <!-- archive-redirect -->
<a id="e-2026-09-27-lightshaft-root"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-lightshaft-root) <!-- archive-redirect -->
<a id="e-2026-09-27-lightshaft-root-中部亮根复现与尺寸旋转判别夹具"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-lightshaft-root-中部亮根复现与尺寸旋转判别夹具) <!-- archive-redirect -->
<a id="e-2026-09-27-multisurface-submission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-multisurface-submission) <!-- archive-redirect -->
<a id="e-2026-09-27-multisurface-submission-全-surface-提交前屏障与-completion-注册代次"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-multisurface-submission-全-surface-提交前屏障与-completion-注册代次) <!-- archive-redirect -->
<a id="e-2026-09-27-owner-event-transaction"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-owner-event-transaction) <!-- archive-redirect -->
<a id="e-2026-09-27-owner-event-transaction-被拒-owner-的事件确认重试已接受-peer-保持"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-owner-event-transaction-被拒-owner-的事件确认重试已接受-peer-保持) <!-- archive-redirect -->
<a id="e-2026-09-27-parallax-shader-input"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-parallax-shader-input) <!-- archive-redirect -->
<a id="e-2026-09-27-parallax-shader-input-背景深度输入的影响系数和纵轴"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-parallax-shader-input-背景深度输入的影响系数和纵轴) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-fixed-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-fixed-geometry) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-fixed-geometry-固定朝向-sprite-保留模型三轴"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-fixed-geometry-固定朝向-sprite-保留模型三轴) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-geometry"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-geometry) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-geometry-sprite-宽度基准静态长宽比与-padded-uv"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-geometry-sprite-宽度基准静态长宽比与-padded-uv) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-normal-format"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-normal-format) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-normal-format-法线原始格式与无-normal-零位移"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-normal-format-法线原始格式与无-normal-零位移) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-prewarm"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-prewarm) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-prewarm-光束根系统恢复预算内作者预热"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-prewarm-光束根系统恢复预算内作者预热) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-refraction-basis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-refraction-basis) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-refraction-basis-折射方向与几何尺寸分离"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-refraction-basis-折射方向与几何尺寸分离) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-refraction-mask"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-refraction-mask) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-refraction-mask-折射遮罩与粒子淡出衰减"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-refraction-mask-折射遮罩与粒子淡出衰减) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-rotation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-rotation) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-rotation-明确三轴-sprite-旋转对齐现有作者-shader-路径"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-rotation-明确三轴-sprite-旋转对齐现有作者-shader-路径) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-scalar-scripts"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-scalar-scripts) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-scalar-scripts-七标量脚本与白点密度恢复"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-scalar-scripts-七标量脚本与白点密度恢复) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-sequence-end"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-sequence-end) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-sequence-end-粒子序列末帧保持不提前混回首帧"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-sequence-end-粒子序列末帧保持不提前混回首帧) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-simulation-rate"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-simulation-rate) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-simulation-rate-粒子倍率共用模拟时间发射数值边界局部拒绝"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-simulation-rate-粒子倍率共用模拟时间发射数值边界局部拒绝) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-straight-interpolation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-straight-interpolation) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-straight-interpolation-普通粒子保留透明rgb后插值与合成"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-straight-interpolation-普通粒子保留透明rgb后插值与合成) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-upright"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-upright) <!-- archive-redirect -->
<a id="e-2026-09-27-particle-upright-系统世界竖轴与相机-roll-分离"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-particle-upright-系统世界竖轴与相机-roll-分离) <!-- archive-redirect -->
<a id="e-2026-09-27-puppet-legacy-attachments"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-puppet-legacy-attachments) <!-- archive-redirect -->
<a id="e-2026-09-27-puppet-legacy-attachments-旧版模型附着点恢复小提琴粒子位置"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-puppet-legacy-attachments-旧版模型附着点恢复小提琴粒子位置) <!-- archive-redirect -->
<a id="e-2026-09-27-radial-carrier-anchor"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-radial-carrier-anchor) <!-- archive-redirect -->
<a id="e-2026-09-27-radial-carrier-anchor-径向角向光束保留作者中心收回额外顶部平移"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-radial-carrier-anchor-径向角向光束保留作者中心收回额外顶部平移) <!-- archive-redirect -->
<a id="e-2026-09-27-return-diagnostic"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-return-diagnostic) <!-- archive-redirect -->
<a id="e-2026-09-27-return-diagnostic-非法临时-vec3-字符串安全诊断与恢复"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-return-diagnostic-非法临时-vec3-字符串安全诊断与恢复) <!-- archive-redirect -->
<a id="e-2026-09-27-rope-shared-endpoints"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-rope-shared-endpoints) <!-- archive-redirect -->
<a id="e-2026-09-27-rope-shared-endpoints-真实画面排查与-rope-接缝修复"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-rope-shared-endpoints-真实画面排查与-rope-接缝修复) <!-- archive-redirect -->
<a id="e-2026-09-27-scene-color-precision"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-scene-color-precision) <!-- archive-redirect -->
<a id="e-2026-09-27-scene-color-precision-作者-hdr-颜色精度贯通终端"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-scene-color-precision-作者-hdr-颜色精度贯通终端) <!-- archive-redirect -->
<a id="e-2026-09-27-script-visible-roots"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-script-visible-roots) <!-- archive-redirect -->
<a id="e-2026-09-27-script-visible-roots-跨层显示的特效准备与隐藏文字资源贯通"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-script-visible-roots-跨层显示的特效准备与隐藏文字资源贯通) <!-- archive-redirect -->
<a id="e-2026-09-27-shared-identity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-shared-identity) <!-- archive-redirect -->
<a id="e-2026-09-27-shared-identity-撤除-shared-伪回滚保留函数与对象身份"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-shared-identity-撤除-shared-伪回滚保留函数与对象身份) <!-- archive-redirect -->
<a id="e-2026-09-27-signed-drag"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-signed-drag) <!-- archive-redirect -->
<a id="e-2026-09-27-signed-drag-开源逐项对照与运动负阻力"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-signed-drag-开源逐项对照与运动负阻力) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-contributor-ablation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-contributor-ablation) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-contributor-ablation-后段泛白主要跟随-snowstorm-子雾气"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-contributor-ablation-后段泛白主要跟随-snowstorm-子雾气) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-resource-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-resource-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-resource-diagnosis-真实烟雾图集与有限粒子数量过曝仍待合成对照"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-resource-diagnosis-真实烟雾图集与有限粒子数量过曝仍待合成对照) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-retirement) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-retirement-高亮形成后随子雾退场消退未见持续残留"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-retirement-高亮形成后随子雾退场消退未见持续残留) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-target-alpha"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-target-alpha) <!-- archive-redirect -->
<a id="e-2026-09-27-snow-fog-target-alpha-同帧绘制前后读回排除目标alpha候选"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-snow-fog-target-alpha-同帧绘制前后读回排除目标alpha候选) <!-- archive-redirect -->
<a id="e-2026-09-27-sphere-emitter"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-sphere-emitter) <!-- archive-redirect -->
<a id="e-2026-09-27-sphere-emitter-修复球形发射的固定轴回退"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-sphere-emitter-修复球形发射的固定轴回退) <!-- archive-redirect -->
<a id="e-2026-09-27-storage-owner-transaction"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-storage-owner-transaction) <!-- archive-redirect -->
<a id="e-2026-09-27-storage-owner-transaction-有序存储批次撤回与同帧消费者拒绝"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-storage-owner-transaction-有序存储批次撤回与同帧消费者拒绝) <!-- archive-redirect -->
<a id="e-2026-09-27-straight-albedo-resize"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-straight-albedo-resize) <!-- archive-redirect -->
<a id="e-2026-09-27-straight-albedo-resize-透明大图恢复加载且保留颜色通道"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-straight-albedo-resize-透明大图恢复加载且保留颜色通道) <!-- archive-redirect -->
<a id="e-2026-09-27-timer-identity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-timer-identity) <!-- archive-redirect -->
<a id="e-2026-09-27-timer-identity-撤回后-timer-取消能力不再误命中新任务"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-timer-identity-撤回后-timer-取消能力不再误命中新任务) <!-- archive-redirect -->
<a id="e-2026-09-27-transform-nonfinite-local"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-transform-nonfinite-local) <!-- archive-redirect -->
<a id="e-2026-09-27-transform-nonfinite-local-原包音频条恢复数值非有限变换只拒绝单次赋值"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-transform-nonfinite-local-原包音频条恢复数值非有限变换只拒绝单次赋值) <!-- archive-redirect -->
<a id="e-2026-09-27-unified-effect-visibility"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-unified-effect-visibility) <!-- archive-redirect -->
<a id="e-2026-09-27-unified-effect-visibility-合并显隐准备并接通跨层光效开关"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-unified-effect-visibility-合并显隐准备并接通跨层光效开关) <!-- archive-redirect -->
<a id="e-2026-09-27-user-retest-priorities"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-user-retest-priorities) <!-- archive-redirect -->
<a id="e-2026-09-27-user-retest-priorities-用户最新实测反馈非自动回放结论"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-user-retest-priorities-用户最新实测反馈非自动回放结论) <!-- archive-redirect -->
<a id="e-2026-09-27-video-command-idempotence"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-command-idempotence) <!-- archive-redirect -->
<a id="e-2026-09-27-video-command-idempotence-重复视频命令不再暂停播放器"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-command-idempotence-重复视频命令不再暂停播放器) <!-- archive-redirect -->
<a id="e-2026-09-27-video-display-time"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-display-time) <!-- archive-redirect -->
<a id="e-2026-09-27-video-display-time-真实视频输出时间与循环间隔"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-display-time-真实视频输出时间与循环间隔) <!-- archive-redirect -->
<a id="e-2026-09-27-video-eof-discard"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-eof-discard) <!-- archive-redirect -->
<a id="e-2026-09-27-video-eof-discard-帧撤回保留已确认-eof撤回双槽实验"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-eof-discard-帧撤回保留已确认-eof撤回双槽实验) <!-- archive-redirect -->
<a id="e-2026-09-27-video-loop-phase"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-loop-phase) <!-- archive-redirect -->
<a id="e-2026-09-27-video-loop-phase-eof-保留-scene-时钟相位"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-loop-phase-eof-保留-scene-时钟相位) <!-- archive-redirect -->
<a id="e-2026-09-27-video-looper-screening"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-looper-screening) <!-- archive-redirect -->
<a id="e-2026-09-27-video-looper-screening-实际4k否决原生循环器接入"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-video-looper-screening-实际4k否决原生循环器接入) <!-- archive-redirect -->
<a id="e-2026-09-27-vortex-motion-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-vortex-motion-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-27-vortex-motion-diagnosis-已加载且模拟位置持续转动视觉验收仍开放"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-vortex-motion-diagnosis-已加载且模拟位置持续转动视觉验收仍开放) <!-- archive-redirect -->
<a id="e-2026-09-27-world-x-reflection"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-world-x-reflection) <!-- archive-redirect -->
<a id="e-2026-09-27-world-x-reflection-正交作者空间的三轴变换一致性"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-27-world-x-reflection-正交作者空间的三轴变换一致性) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-band-peaks"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-band-peaks) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-band-peaks-消除宽高频档对窄带幅度的稀释"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-band-peaks-消除宽高频档对窄带幅度的稀释) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-bounds-gate"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-bounds-gate) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-bounds-gate-粒子音频门控按字段存在启用rope-门-2-前置"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-bounds-gate-粒子音频门控按字段存在启用rope-门-2-前置) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-legacy-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-legacy-retirement) <!-- archive-redirect -->
<a id="e-2026-09-28-audio-legacy-retirement-删除无调用-cpu-effect-音频实现"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-audio-legacy-retirement-删除无调用-cpu-effect-音频实现) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-failure-atomicity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-failure-atomicity) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-failure-atomicity-bloom-完整准备与中断保源"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-failure-atomicity-bloom-完整准备与中断保源) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-live-properties"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-live-properties) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-live-properties-bloom-直接属性到合成输出"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-live-properties-bloom-直接属性到合成输出) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-zero-strength"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-zero-strength) <!-- archive-redirect -->
<a id="e-2026-09-28-bloom-zero-strength-精确零贡献免编码"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bloom-zero-strength-精确零贡献免编码) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-author-world"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-author-world) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-author-world-骨骼与鼠标共用作者世界坐标"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-author-world-骨骼与鼠标共用作者世界坐标) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-impulse-research"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-impulse-research) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-impulse-research-冲量桥接研究收口数值实现暂挂"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-impulse-research-冲量桥接研究收口数值实现暂挂) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-local-only"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-local-only) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-local-only-退役骨骼下游世界坐标旧表示"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-local-only-退役骨骼下游世界坐标旧表示) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-origin-api"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-origin-api) <!-- archive-redirect -->
<a id="e-2026-09-28-bone-origin-api-局部骨骼位置读写复用矩阵事务"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bone-origin-api-局部骨骼位置读写复用矩阵事务) <!-- archive-redirect -->
<a id="e-2026-09-28-bool-number-coercion"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bool-number-coercion) <!-- archive-redirect -->
<a id="e-2026-09-28-bool-number-coercion-boolean-属性边界的-js-赋值强转补齐"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-bool-number-coercion-boolean-属性边界的-js-赋值强转补齐) <!-- archive-redirect -->
<a id="e-2026-09-28-child-builder-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-child-builder-retirement) <!-- archive-redirect -->
<a id="e-2026-09-28-child-builder-retirement-子粒子实例构建旧入口退役"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-child-builder-retirement-子粒子实例构建旧入口退役) <!-- archive-redirect -->
<a id="e-2026-09-28-combo-boolean-visibility"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-combo-boolean-visibility) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-batch-world-frames"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-batch-world-frames) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-batch-world-frames-鼠标事件批复用同一层级变换"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-batch-world-frames-鼠标事件批复用同一层级变换) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-local-pixels"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-local-pixels) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-local-pixels-脚本局部坐标恢复图层像素单位"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-local-pixels-脚本局部坐标恢复图层像素单位) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-parallax"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-parallax) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-parallax-点击命中继承同帧平滑视差"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-parallax-点击命中继承同帧平滑视差) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-solid"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-solid) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-solid-作者静态-solid-控制鼠标命中"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-solid-作者静态-solid-控制鼠标命中) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-surface-routing"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-surface-routing) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-surface-routing-子帧鼠标边沿沿同一-host-路径跨-surface-保留"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-surface-routing-子帧鼠标边沿沿同一-host-路径跨-surface-保留) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-video-commands"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-video-commands) <!-- archive-redirect -->
<a id="e-2026-09-28-cursor-video-commands-鼠标视频命令保序提交与暂停跳转正确取帧"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-cursor-video-commands-鼠标视频命令保序提交与暂停跳转正确取帧) <!-- archive-redirect -->
<a id="e-2026-09-28-dependency-reference-index"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dependency-reference-index) <!-- archive-redirect -->
<a id="e-2026-09-28-dependency-reference-index-依赖准备阶段消除重复全图扫描"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dependency-reference-index-依赖准备阶段消除重复全图扫描) <!-- archive-redirect -->
<a id="e-2026-09-28-dynamic-solid"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dynamic-solid) <!-- archive-redirect -->
<a id="e-2026-09-28-dynamic-solid-baseline"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dynamic-solid-baseline) <!-- archive-redirect -->
<a id="e-2026-09-28-dynamic-solid-baseline-脚本交互开关未进入帧状态修前基线"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dynamic-solid-baseline-脚本交互开关未进入帧状态修前基线) <!-- archive-redirect -->
<a id="e-2026-09-28-dynamic-solid-脚本交互开关进入统一帧事务"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-dynamic-solid-脚本交互开关进入统一帧事务) <!-- archive-redirect -->
<a id="e-2026-09-28-effect-cursor-visibility"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-effect-cursor-visibility) <!-- archive-redirect -->
<a id="e-2026-09-28-effect-cursor-visibility-特效自身显隐复用鼠标事件及原提交事务"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-effect-cursor-visibility-特效自身显隐复用鼠标事件及原提交事务) <!-- archive-redirect -->
<a id="e-2026-09-28-effect-parameter-cursor"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-effect-parameter-cursor) <!-- archive-redirect -->
<a id="e-2026-09-28-effect-parameter-cursor-特效向量参数共享所属层鼠标事件"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-effect-parameter-cursor-特效向量参数共享所属层鼠标事件) <!-- archive-redirect -->
<a id="e-2026-09-28-hidden-layer-effect-preparation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-hidden-layer-effect-preparation) <!-- archive-redirect -->
<a id="e-2026-09-28-integrated-playback"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-integrated-playback) <!-- archive-redirect -->
<a id="e-2026-09-28-integrated-playback-准备计划复用与统一暂停策略整合回归"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-integrated-playback-准备计划复用与统一暂停策略整合回归) <!-- archive-redirect -->
<a id="e-2026-09-28-local-particle-transform"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-local-particle-transform) <!-- archive-redirect -->
<a id="e-2026-09-28-local-particle-transform-两样本光束定义对照与局部卡片变换修正"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-local-particle-transform-两样本光束定义对照与局部卡片变换修正) <!-- archive-redirect -->
<a id="e-2026-09-28-mixed-visibility-preparation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-mixed-visibility-preparation) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-angular-speed"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-angular-speed) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-angular-speed-出生-speed-倍率补齐角速度"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-angular-speed-出生-speed-倍率补齐角速度) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-color-script"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-color-script) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-color-script-粒子颜色脚本接入现有-vec3-通道"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-color-script-粒子颜色脚本接入现有-vec3-通道) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-force-safety"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-force-safety) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-force-safety-粒子向量累加统一-float-安全边界"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-force-safety-粒子向量累加统一-float-安全边界) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-gravity-speed"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-gravity-speed) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-gravity-speed-movement-重力消费同一-speed-倍率"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-gravity-speed-movement-重力消费同一-speed-倍率) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-implicit-origin"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-implicit-origin) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-implicit-origin-鼠标原点不再被计入粒子排列半径"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-implicit-origin-鼠标原点不再被计入粒子排列半径) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-layer-alpha"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-layer-alpha) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-layer-alpha-图层透明度实时作用于根粒子和子粒子"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-layer-alpha-图层透明度实时作用于根粒子和子粒子) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-loading-completeness"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-loading-completeness) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-loading-completeness-未加载粒子不再被默认验收忽略"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-loading-completeness-未加载粒子不再被默认验收忽略) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-pointer-frame"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-pointer-frame) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-pointer-frame-挂接粒子的鼠标反算复用当帧绘制变换"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-pointer-frame-挂接粒子的鼠标反算复用当帧绘制变换) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-speed-disable"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-speed-disable) <!-- archive-redirect -->
<a id="e-2026-09-28-particle-speed-disable-speed-禁用门统一并补齐湍流"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-particle-speed-disable-speed-禁用门统一并补齐湍流) <!-- archive-redirect -->
<a id="e-2026-09-28-periodic-instance-overrides"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-periodic-instance-overrides) <!-- archive-redirect -->
<a id="e-2026-09-28-periodic-instance-overrides-周期发射接入原-ratecount-通道"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-periodic-instance-overrides-周期发射接入原-ratecount-通道) <!-- archive-redirect -->
<a id="e-2026-09-28-point-light-roi"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-point-light-roi) <!-- archive-redirect -->
<a id="e-2026-09-28-point-light-roi-3662790108-动态-point-光执行与可见贡献正证证据批无产品改动"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-point-light-roi-3662790108-动态-point-光执行与可见贡献正证证据批无产品改动) <!-- archive-redirect -->
<a id="e-2026-09-28-prepared-dependency-plan-reuse"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-prepared-dependency-plan-reuse) <!-- archive-redirect -->
<a id="e-2026-09-28-prepared-dependency-plan-reuse-utility与drawable消费同一准备计划"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-prepared-dependency-plan-reuse-utility与drawable消费同一准备计划) <!-- archive-redirect -->
<a id="e-2026-09-28-puppet-pose-publication"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-puppet-pose-publication) <!-- archive-redirect -->
<a id="e-2026-09-28-puppet-pose-publication-非法骨骼刷新保留完整旧姿态"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-puppet-pose-publication-非法骨骼刷新保留完整旧姿态) <!-- archive-redirect -->
<a id="e-2026-09-28-ray-source-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-ray-source-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-28-ray-source-diagnosis-固定斜光目标并排除背景效果整体丢失"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-ray-source-diagnosis-固定斜光目标并排除背景效果整体丢失) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-breakpoint-isolation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-breakpoint-isolation) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-breakpoint-isolation-鼠标拖尾分层断点产品未放宽"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-breakpoint-isolation-鼠标拖尾分层断点产品未放宽) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-gate-admission"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-gate-admission) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-gate-admission-rope-renderer-放行指针拖尾家族rope-恢复门-2-主体"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-gate-admission-rope-renderer-放行指针拖尾家族rope-恢复门-2-主体) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-trail-texture"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-trail-texture) <!-- archive-redirect -->
<a id="e-2026-09-28-rope-trail-texture-完整纹理覆盖恢复拖尾旋转感"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rope-trail-texture-完整纹理覆盖恢复拖尾旋转感) <!-- archive-redirect -->
<a id="e-2026-09-28-rotation-source-types"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rotation-source-types) <!-- archive-redirect -->
<a id="e-2026-09-28-rotation-source-types-保留旧式初始旋转输入类型"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-rotation-source-types-保留旧式初始旋转输入类型) <!-- archive-redirect -->
<a id="e-2026-09-28-scalar-cursor-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-scalar-cursor-owner) <!-- archive-redirect -->
<a id="e-2026-09-28-scalar-cursor-owner-标量鼠标事件与属性求值共用-typed-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-scalar-cursor-owner-标量鼠标事件与属性求值共用-typed-owner) <!-- archive-redirect -->
<a id="e-2026-09-28-script-combo-layout"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-script-combo-layout) <!-- archive-redirect -->
<a id="e-2026-09-28-solid-live-transitions"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-solid-live-transitions) <!-- archive-redirect -->
<a id="e-2026-09-28-solid-live-transitions-普通帧反复切换交互开关的实际输出"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-solid-live-transitions-普通帧反复切换交互开关的实际输出) <!-- archive-redirect -->
<a id="e-2026-09-28-sprite-size-diagnosis"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-sprite-size-diagnosis) <!-- archive-redirect -->
<a id="e-2026-09-28-sprite-size-diagnosis-不采纳整体尺寸补偿"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-sprite-size-diagnosis-不采纳整体尺寸补偿) <!-- archive-redirect -->
<a id="e-2026-09-28-string-cursor-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-string-cursor-owner) <!-- archive-redirect -->
<a id="e-2026-09-28-string-cursor-owner-文字脚本共用-typed-owner-并接入鼠标事件"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-string-cursor-owner-文字脚本共用-typed-owner-并接入鼠标事件) <!-- archive-redirect -->
<a id="e-2026-09-28-string-init-only"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-string-init-only) <!-- archive-redirect -->
<a id="e-2026-09-28-string-init-only-文字初始化沿现有事务执行并休眠"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-string-init-only-文字初始化沿现有事务执行并休眠) <!-- archive-redirect -->
<a id="e-2026-09-28-trail-defaults"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-trail-defaults) <!-- archive-redirect -->
<a id="e-2026-09-28-trail-defaults-修正省略边界导致拖尾锁长"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-trail-defaults-修正省略边界导致拖尾锁长) <!-- archive-redirect -->
<a id="e-2026-09-28-value-bone-output"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-value-bone-output) <!-- archive-redirect -->
<a id="e-2026-09-28-value-bone-output-补齐标量文字骨骼输出并合并副作用汇总"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-value-bone-output-补齐标量文字骨骼输出并合并副作用汇总) <!-- archive-redirect -->
<a id="e-2026-09-28-value-video-commands"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-value-video-commands) <!-- archive-redirect -->
<a id="e-2026-09-28-value-video-commands-标量与文字脚本保留视频控制命令"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-value-video-commands-标量与文字脚本保留视频控制命令) <!-- archive-redirect -->
<a id="e-2026-09-28-vector-dimensions"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-vector-dimensions) <!-- archive-redirect -->
<a id="e-2026-09-28-vector-dimensions-二维脚本输入与返回沿同一typed向量桥接"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-vector-dimensions-二维脚本输入与返回沿同一typed向量桥接) <!-- archive-redirect -->
<a id="e-2026-09-28-video-real-samples"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-video-real-samples) <!-- archive-redirect -->
<a id="e-2026-09-28-video-real-samples-脚本视频命令链三个真实样本验收通过证据批无产品改动"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-video-real-samples-脚本视频命令链三个真实样本验收通过证据批无产品改动) <!-- archive-redirect -->
<a id="e-2026-09-28-world-pointer-demand"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-pointer-demand) <!-- archive-redirect -->
<a id="e-2026-09-28-world-pointer-demand-worldperspective-系统的-emitter-指针需求解除rope-恢复门-3"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-pointer-demand-worldperspective-系统的-emitter-指针需求解除rope-恢复门-3) <!-- archive-redirect -->
<a id="e-2026-09-28-world-pointer-force"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-pointer-force) <!-- archive-redirect -->
<a id="e-2026-09-28-world-pointer-force-forcepositionaround-指针需求同族放开门-3-完成"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-pointer-force-forcepositionaround-指针需求同族放开门-3-完成) <!-- archive-redirect -->
<a id="e-2026-09-28-world-space-gate"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-space-gate) <!-- archive-redirect -->
<a id="e-2026-09-28-world-space-gate-世界空间首门按声明变换写者收窄并补运行时安全失效切片-1a"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-space-gate-世界空间首门按声明变换写者收窄并补运行时安全失效切片-1a) <!-- archive-redirect -->
<a id="e-2026-09-28-world-space-live-frame"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-space-live-frame) <!-- archive-redirect -->
<a id="e-2026-09-28-world-space-live-frame-模拟器消费渲染同一逐帧世界帧切片-1b冻结降为回退"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-28-world-space-live-frame-模拟器消费渲染同一逐帧世界帧切片-1b冻结降为回退) <!-- archive-redirect -->
<a id="e-2026-09-29-arc-regression-sweep"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-arc-regression-sweep) <!-- archive-redirect -->
<a id="e-2026-09-29-arc-regression-sweep-世界空间音频门弧线受影响样本回归扫描证据批无产品改动"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-arc-regression-sweep-世界空间音频门弧线受影响样本回归扫描证据批无产品改动) <!-- archive-redirect -->
<a id="e-2026-09-29-daemon-web-lane"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-daemon-web-lane) <!-- archive-redirect -->
<a id="e-2026-09-29-daemon-web-lane-daemon-web-宿主-lane-退役e6-死路径批审查-approve936c1f87"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-daemon-web-lane-daemon-web-宿主-lane-退役e6-死路径批审查-approve936c1f87) <!-- archive-redirect -->
<a id="e-2026-09-29-dependency-vector-convergence"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-dependency-vector-convergence) <!-- archive-redirect -->
<a id="e-2026-09-29-dependency-vector-convergence-依赖双通道收敛为唯一有序向量e1-③结构消融审查三轮"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-dependency-vector-convergence-依赖双通道收敛为唯一有序向量e1-③结构消融审查三轮) <!-- archive-redirect -->
<a id="e-2026-09-29-e5-fallback-audit"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-e5-fallback-audit) <!-- archive-redirect -->
<a id="e-2026-09-29-e5-fallback-audit-genericboundedfrontend-fallback-语料审计e5-退役前置裁决拒绝整批退役只读分析批"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-e5-fallback-audit-genericboundedfrontend-fallback-语料审计e5-退役前置裁决拒绝整批退役只读分析批) <!-- archive-redirect -->
<a id="e-2026-09-29-launch-reporter-census"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-launch-reporter-census) <!-- archive-redirect -->
<a id="e-2026-09-29-launch-reporter-census-launch-一次性报告器成员级识别收口e6-候选-3-完成f2158e40"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-launch-reporter-census-launch-一次性报告器成员级识别收口e6-候选-3-完成f2158e40) <!-- archive-redirect -->
<a id="e-2026-09-29-script-frame-ledger"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-script-frame-ledger) <!-- archive-redirect -->
<a id="e-2026-09-29-script-frame-ledger-scenescript-程序家族帧账本共享e1-④-收口审查-approvebb4d4dae"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-script-frame-ledger-scenescript-程序家族帧账本共享e1-④-收口审查-approvebb4d4dae) <!-- archive-redirect -->
<a id="e-2026-09-29-visibility-dedup"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-visibility-dedup) <!-- archive-redirect -->
<a id="e-2026-09-29-visibility-dedup-帧可见性走查去重e1-②最小切片结构消融"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-visibility-dedup-帧可见性走查去重e1-②最小切片结构消融) <!-- archive-redirect -->
<a id="e-2026-09-29-web-harness-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-web-harness-retirement) <!-- archive-redirect -->
<a id="e-2026-09-29-web-harness-retirement-不可达-daemon-harness-web-宿主策略删除e6-死路径批审查通过aee7c08a"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-web-harness-retirement-不可达-daemon-harness-web-宿主策略删除e6-死路径批审查通过aee7c08a) <!-- archive-redirect -->
<a id="e-2026-09-29-wrapper-collapse"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-wrapper-collapse) <!-- archive-redirect -->
<a id="e-2026-09-29-wrapper-collapse-帧预检请求包装双走查压扁为单走查e1-①第一切片结构消融审查两轮-rejectapprove"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-29-wrapper-collapse-帧预检请求包装双走查压扁为单走查e1-①第一切片结构消融审查两轮-rejectapprove) <!-- archive-redirect -->
<a id="e-2026-09-30-hlsl-attribute-strip"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-hlsl-attribute-strip) <!-- archive-redirect -->
<a id="e-2026-09-30-hlsl-attribute-strip-syntax-error-子类修复e5-按类解锁第五子类审查-approveea6f0781"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-hlsl-attribute-strip-syntax-error-子类修复e5-按类解锁第五子类审查-approveea6f0781) <!-- archive-redirect -->
<a id="e-2026-09-30-scene-startup-speed-program"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-scene-startup-speed-program) <!-- archive-redirect -->
<a id="e-2026-09-30-scene-startup-speed-program-scene-启动提速计划十一批测量驱动的预热持久化层独立审查逐批通过"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-scene-startup-speed-program-scene-启动提速计划十一批测量驱动的预热持久化层独立审查逐批通过) <!-- archive-redirect -->
<a id="e-2026-09-30-stage-link-loose-builtin-compat"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-stage-link-loose-builtin-compat) <!-- archive-redirect -->
<a id="e-2026-09-30-stage-link-loose-builtin-compat-log10-兼容宏-标量在前-maxmin-广播第七子类2849382252-失败链闭合零-fallback"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-stage-link-loose-builtin-compat-log10-兼容宏-标量在前-maxmin-广播第七子类2849382252-失败链闭合零-fallback) <!-- archive-redirect -->
<a id="e-2026-09-30-stage-link-scalar-truncation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-stage-link-scalar-truncation) <!-- archive-redirect -->
<a id="e-2026-09-30-stage-link-scalar-truncation-标量形参向量实参截断stage-link-第六子类2849382252-首次-pass"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-stage-link-scalar-truncation-标量形参向量实参截断stage-link-第六子类2849382252-首次-pass) <!-- archive-redirect -->
<a id="e-2026-09-30-varying-isolation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-varying-isolation) <!-- archive-redirect -->
<a id="e-2026-09-30-varying-isolation-varying-隔离架构提案独立评审通过e5-varying-类架构裁决登记锚点"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-varying-isolation-varying-隔离架构提案独立评审通过e5-varying-类架构裁决登记锚点) <!-- archive-redirect -->
<a id="e-2026-09-30-varying-narrowing-impl"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-varying-narrowing-impl) <!-- archive-redirect -->
<a id="e-2026-09-30-varying-narrowing-impl-窄化前缀链接零填充实施varying-门归零effect-渲染由下一层已登记类接棒"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-09-30-varying-narrowing-impl-窄化前缀链接零填充实施varying-门归零effect-渲染由下一层已登记类接棒) <!-- archive-redirect -->
<a id="e-2026-10-01-lifecycle-integrity"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-10-01-lifecycle-integrity) <!-- archive-redirect -->
<a id="e-2026-10-01-lifecycle-integrity-候选提升共享模拟独立呈现与-resident-准入"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-10-01-lifecycle-integrity-候选提升共享模拟独立呈现与-resident-准入) <!-- archive-redirect -->
<a id="e-2026-10-01-sampler-baseline-repair"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-10-01-sampler-baseline-repair) <!-- archive-redirect -->
<a id="e-2026-10-01-sampler-baseline-repair-四项既存失败闭合"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-2026-10-01-sampler-baseline-repair-四项既存失败闭合) <!-- archive-redirect -->
<a id="e-launch-diagnostics-split"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-diagnostics-split) <!-- archive-redirect -->
<a id="e-launch-diagnostics-split-播放必需source-facts与用户按需诊断分权"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-diagnostics-split-播放必需source-facts与用户按需诊断分权) <!-- archive-redirect -->
<a id="e-launch-first-surface-pipeline-warmup"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-first-surface-pipeline-warmup) <!-- archive-redirect -->
<a id="e-launch-first-surface-pipeline-warmup-首surface独立runtime与有界并行pipeline预热"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-first-surface-pipeline-warmup-首surface独立runtime与有界并行pipeline预热) <!-- archive-redirect -->
<a id="e-launch-prepared-device-resources"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-prepared-device-resources) <!-- archive-redirect -->
<a id="e-launch-prepared-device-resources-不可变vfs索引与启动期设备资源单点汇合"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-launch-prepared-device-resources-不可变vfs索引与启动期设备资源单点汇合) <!-- archive-redirect -->
<a id="e-material-program-source-fact-cache"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-material-program-source-fact-cache) <!-- archive-redirect -->
<a id="e-material-program-source-fact-cache-compiled-variant持有不可变shader-source-fact"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-material-program-source-fact-cache-compiled-variant持有不可变shader-source-fact) <!-- archive-redirect -->
<a id="e-v1-broad-preserving-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-broad-preserving-owner) <!-- archive-redirect -->
<a id="e-v1-broad-preserving-owner-最后一个-v1-b-shared-fallback-route-撤权"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-broad-preserving-owner-最后一个-v1-b-shared-fallback-route-撤权) <!-- archive-redirect -->
<a id="e-v1-direct-vector-conversion-shimmer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-direct-vector-conversion-shimmer) <!-- archive-redirect -->
<a id="e-v1-direct-vector-conversion-shimmer-direct向量转换闭合三份真实shimmer-program"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-direct-vector-conversion-shimmer-direct向量转换闭合三份真实shimmer-program) <!-- archive-redirect -->
<a id="e-v1-pulse-alpha-binding-candidate-revocation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-pulse-alpha-binding-candidate-revocation) <!-- archive-redirect -->
<a id="e-v1-pulse-alpha-binding-candidate-revocation-direct-alpha-binding-潜在-pulse-candidate-撤权"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-pulse-alpha-binding-candidate-revocation-direct-alpha-binding-潜在-pulse-candidate-撤权) <!-- archive-redirect -->
<a id="e-v1-pulse-audio-tint-alpha-candidate-revocation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-pulse-audio-tint-alpha-candidate-revocation) <!-- archive-redirect -->
<a id="e-v1-pulse-audio-tint-alpha-candidate-revocation-stock-audio-direct-tint-alpha-writing-candidate撤权"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-pulse-audio-tint-alpha-candidate-revocation-stock-audio-direct-tint-alpha-writing-candidate撤权) <!-- archive-redirect -->
<a id="e-v1-shader-compatibility-target"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-shader-compatibility-target) <!-- archive-redirect -->
<a id="e-v1-shader-compatibility-target-显式-author-facing-target-闭合-tone-语言分支"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-shader-compatibility-target-显式-author-facing-target-闭合-tone-语言分支) <!-- archive-redirect -->
<a id="e-v1-standard-blur-dedicated-family-retirement"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-standard-blur-dedicated-family-retirement) <!-- archive-redirect -->
<a id="e-v1-standard-blur-dedicated-family-retirement-删除最后一套专用-effect-产品执行链"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-standard-blur-dedicated-family-retirement-删除最后一套专用-effect-产品执行链) <!-- archive-redirect -->
<a id="e-v1-static-base-image-sampler-atom"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-static-base-image-sampler-atom) <!-- archive-redirect -->
<a id="e-v1-static-base-image-sampler-atom-static-base-image-保留-authored-uv-与-sampler-atom"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v1-static-base-image-sampler-atom-static-base-image-保留-authored-uv-与-sampler-atom) <!-- archive-redirect -->
<a id="e-v4-conditional-combo-layer-selection"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-conditional-combo-layer-selection) <!-- archive-redirect -->
<a id="e-v4-conditional-combo-layer-selection-exact-combo整层选择与同owner按需纹理"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-conditional-combo-layer-selection-exact-combo整层选择与同owner按需纹理) <!-- archive-redirect -->
<a id="e-v4-effect-execution-authority"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-effect-execution-authority) <!-- archive-redirect -->
<a id="e-v4-effect-execution-authority-未知-effect-family-不得取得-dedicated-产品-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-effect-execution-authority-未知-effect-family-不得取得-dedicated-产品-owner) <!-- archive-redirect -->
<a id="e-v4-generated-auxiliary-rgb-preserved-alpha"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-generated-auxiliary-rgb-preserved-alpha) <!-- archive-redirect -->
<a id="e-v4-generated-auxiliary-rgb-preserved-alpha-typed-lut数据进入普通artifact"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-generated-auxiliary-rgb-preserved-alpha-typed-lut数据进入普通artifact) <!-- archive-redirect -->
<a id="e-v4-graph-output-typed-publication"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-graph-output-typed-publication) <!-- archive-redirect -->
<a id="e-v4-graph-output-typed-publication-graph-output-走-typed-named-target-publication"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-graph-output-typed-publication-graph-output-走-typed-named-target-publication) <!-- archive-redirect -->
<a id="e-v4-media-properties-seven-field-string"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-media-properties-seven-field-string) <!-- archive-redirect -->
<a id="e-v4-media-properties-seven-field-string-七字段媒体属性进入共享-stringtext-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-media-properties-seven-field-string-七字段媒体属性进入共享-stringtext-owner) <!-- archive-redirect -->
<a id="e-v4-same-slot-color-blend-alpha-union"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-same-slot-color-blend-alpha-union) <!-- archive-redirect -->
<a id="e-v4-same-slot-color-blend-alpha-union-同槽双rgba颜色合成进入普通artifact"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-same-slot-color-blend-alpha-union-同槽双rgba颜色合成进入普通artifact) <!-- archive-redirect -->
<a id="e-v4-scene-clear-enabled"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scene-clear-enabled) <!-- archive-redirect -->
<a id="e-v4-scene-clear-enabled-author-清屏开关进入唯一主-pass"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scene-clear-enabled-author-清屏开关进入唯一主-pass) <!-- archive-redirect -->
<a id="e-v4-scene-source-ownership-split"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scene-source-ownership-split) <!-- archive-redirect -->
<a id="e-v4-scene-source-ownership-split-三个主链文件恢复可构建性"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scene-source-ownership-split-三个主链文件恢复可构建性) <!-- archive-redirect -->
<a id="e-v4-scenescript-dynamic-image-layer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-dynamic-image-layer) <!-- archive-redirect -->
<a id="e-v4-scenescript-dynamic-image-layer-package-imagematerial-color与唯一compositor"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-dynamic-image-layer-package-imagematerial-color与唯一compositor) <!-- archive-redirect -->
<a id="e-v4-scenescript-layer-visibility-boolean"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-layer-visibility-boolean) <!-- archive-redirect -->
<a id="e-v4-scenescript-layer-visibility-boolean-strict-boolean-layer-visibility-owner"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-layer-visibility-boolean-strict-boolean-layer-visibility-owner) <!-- archive-redirect -->
<a id="e-v4-scenescript-local-storage"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-local-storage) <!-- archive-redirect -->
<a id="e-v4-scenescript-local-storage-screenglobal持久化进入共享vm-transaction"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-local-storage-screenglobal持久化进入共享vm-transaction) <!-- archive-redirect -->
<a id="e-v4-scenescript-stateful-update"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-stateful-update) <!-- archive-redirect -->
<a id="e-v4-scenescript-stateful-update-typed-updatevalue-读取上一帧-published-current"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-stateful-update-typed-updatevalue-读取上一帧-published-current) <!-- archive-redirect -->
<a id="e-v4-scenescript-text-image-color-consumers"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-text-image-color-consumers) <!-- archive-redirect -->
<a id="e-v4-scenescript-text-image-color-consumers-object颜色进入coretext与direct-image共享consumer"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-text-image-color-consumers-object颜色进入coretext与direct-image共享consumer) <!-- archive-redirect -->
<a id="e-v4-scenescript-video-xray"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-video-xray) <!-- archive-redirect -->
<a id="e-v4-scenescript-video-xray-typed-video-handle与hidden-dependency恢复真实x-ray交互"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-scenescript-video-xray-typed-video-handle与hidden-dependency恢复真实x-ray交互) <!-- archive-redirect -->
<a id="e-v4-system-provider-absence-fallback"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-system-provider-absence-fallback) <!-- archive-redirect -->
<a id="e-v4-system-provider-absence-fallback-无媒体封面选择作者mask并执行普通program"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-system-provider-absence-fallback-无媒体封面选择作者mask并执行普通program) <!-- archive-redirect -->
<a id="e-v4-typed-named-publication-generation"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-typed-named-publication-generation) <!-- archive-redirect -->
<a id="e-v4-typed-named-publication-generation-registry-generation-与-frame-epoch-分责"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-typed-named-publication-generation-registry-generation-与-frame-epoch-分责) <!-- archive-redirect -->
<a id="e-v4-unified-media-frame-batch"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-unified-media-frame-batch) <!-- archive-redirect -->
<a id="e-v4-unified-media-frame-batch-跨类型有序媒体事件与自动-visibility-mutation-合同"></a> [归档记录](../history/runtime-evidence-batches-through-2026-10-03.md#e-v4-unified-media-frame-batch-跨类型有序媒体事件与自动-visibility-mutation-合同) <!-- archive-redirect -->
<a id="composition-background-bounds-20261022"></a> [归档记录](../history/composition-background-bounds-2026-10-22.md#composition-background-bounds-20261022) <!-- archive-redirect -->
<a id="authored-direct-draw-domain-20261023"></a> [归档记录](../history/authored-direct-draw-domain-2026-10-23.md#authored-direct-draw-domain-20261023) <!-- archive-redirect -->
<a id="initial-video-presentation-20261023"></a> [归档记录](../history/initial-video-presentation-2026-10-23.md#initial-video-presentation-20261023) <!-- archive-redirect -->
<a id="light-particle-qualification-20261023"></a> [归档记录](../history/light-particle-qualification-2026-10-23.md#light-particle-qualification-20261023) <!-- archive-redirect -->
<a id="builtin-image-light-families-20261023"></a> [归档记录](../history/builtin-image-light-families-2026-10-23.md#builtin-image-light-families-20261023) <!-- archive-redirect -->
<a id="text-publication-first-frame-20261023"></a> [归档记录](../history/text-publication-first-frame-2026-10-23.md#text-publication-first-frame-20261023) <!-- archive-redirect -->
<a id="default-camera-origin-setter-20261023"></a> [归档记录](../history/default-2d-camera-inputs-2026-10-16.md#default-camera-origin-setter-20261023) <!-- archive-redirect -->
<a id="composition-root-effect-local-source-20261023"></a> [归档记录](../history/composition-root-effect-local-source-2026-10-23.md#composition-root-effect-local-source-20261023) <!-- archive-redirect -->
<a id="declared-texture-rgb-graph-20261024"></a> [归档记录](../history/declared-texture-rgb-graph-2026-10-24.md#declared-texture-rgb-graph-20261024) <!-- archive-redirect -->
<a id="2026-10-18u02剩余三包照明现况复验"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-18u02剩余三包照明现况复验) <!-- archive-redirect -->
<a id="2026-10-18函数宏逻辑调用与物理来源行"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-18函数宏逻辑调用与物理来源行) <!-- archive-redirect -->
<a id="2026-10-18静态模型-normal-rgb-与几何-coverage"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-18静态模型-normal-rgb-与几何-coverage) <!-- archive-redirect -->
<a id="2026-10-20-普通-sprite-coverage外围花簇恢复"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-20-普通-sprite-coverage外围花簇恢复) <!-- archive-redirect -->
<a id="2026-10-20命名依赖锚点一致性恢复首帧"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-20命名依赖锚点一致性恢复首帧) <!-- archive-redirect -->
<a id="2026-10-20本机快捷方式配置与实际打开"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-20本机快捷方式配置与实际打开) <!-- archive-redirect -->
<a id="2026-10-20鼠标缩放反馈的资格边界"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-20鼠标缩放反馈的资格边界) <!-- archive-redirect -->
<a id="2026-10-2129视频供帧候选撤回与实例资格"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-2129视频供帧候选撤回与实例资格) <!-- archive-redirect -->
<a id="2026-10-21bool可见性owner复用动态文字事务"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-21bool可见性owner复用动态文字事务) <!-- archive-redirect -->
<a id="2026-10-21generic固定float数组恢复默认32频带波形"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-21generic固定float数组恢复默认32频带波形) <!-- archive-redirect -->
<a id="2026-10-21共享vec3判等恢复作者颜色过渡"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-21共享vec3判等恢复作者颜色过渡) <!-- archive-redirect -->
<a id="2026-10-21新增24样本的debug诊断入库"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-21新增24样本的debug诊断入库) <!-- archive-redirect -->
<a id="2026-10-21普通图片末材质响应最终放置坐标"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-21普通图片末材质响应最终放置坐标) <!-- archive-redirect -->
<a id="2026-10-22新增17原包默认诊断"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-22新增17原包默认诊断) <!-- archive-redirect -->
<a id="2026-10-22视频定位完成已取像素与呈现提交分责"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-22视频定位完成已取像素与呈现提交分责) <!-- archive-redirect -->
<a id="2026-10-22顶层普通成员组合的根效果接入局部源"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#2026-10-22顶层普通成员组合的根效果接入局部源) <!-- archive-redirect -->
<a id="335-ui-group-attribution-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#335-ui-group-attribution-20261018) <!-- archive-redirect -->
<a id="additive-terminal-density-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#additive-terminal-density-20261019) <!-- archive-redirect -->
<a id="alpha-only-color-boundary-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#alpha-only-color-boundary-20261021) <!-- archive-redirect -->
<a id="asset-path-string-values-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#asset-path-string-values-20261018) <!-- archive-redirect -->
<a id="audio-index-preparation-order-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#audio-index-preparation-order-20261018) <!-- archive-redirect -->
<a id="audio-ipc-version-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#audio-ipc-version-20261021) <!-- archive-redirect -->
<a id="audio-packed-source-view-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#audio-packed-source-view-20261020) <!-- archive-redirect -->
<a id="background-terminal-density-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#background-terminal-density-20261019) <!-- archive-redirect -->
<a id="batch2-frozen-records"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#batch2-frozen-records) <!-- archive-redirect -->
<a id="batch2-冻结执行记录"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#batch2-冻结执行记录) <!-- archive-redirect -->
<a id="blue-firework-qualification-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#blue-firework-qualification-20261020) <!-- archive-redirect -->
<a id="boolean-dynamic-text-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#boolean-dynamic-text-20261021) <!-- archive-redirect -->
<a id="builtin-image-additive-rgb-20261022"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#builtin-image-additive-rgb-20261022) <!-- archive-redirect -->
<a id="childless-passthrough-background-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#childless-passthrough-background-20261018) <!-- archive-redirect -->
<a id="childless-passthrough尊重背景选择2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#childless-passthrough尊重背景选择2026-10-18) <!-- archive-redirect -->
<a id="clock-color-current-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#clock-color-current-20261019) <!-- archive-redirect -->
<a id="combined-timeline-playback-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#combined-timeline-playback-20261017) <!-- archive-redirect -->
<a id="compose-subtree-qualification-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#compose-subtree-qualification-20261021) <!-- archive-redirect -->
<a id="composition-local-source-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#composition-local-source-20261018) <!-- archive-redirect -->
<a id="composition-member-bounds-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#composition-member-bounds-20261018) <!-- archive-redirect -->
<a id="conditional-model-animation-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#conditional-model-animation-20261020) <!-- archive-redirect -->
<a id="constant-dense-state1-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#constant-dense-state1-20261018) <!-- archive-redirect -->
<a id="corpus-log-audit-20261029"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#corpus-log-audit-20261029) <!-- archive-redirect -->
<a id="cp-force-source-space-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#cp-force-source-space-20261017) <!-- archive-redirect -->
<a id="default-camera-single-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#default-camera-single-20261019) <!-- archive-redirect -->
<a id="direct-model-bind-geometry-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#direct-model-bind-geometry-20261019) <!-- archive-redirect -->
<a id="direct-model-skeletal-animation-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#direct-model-skeletal-animation-20261019) <!-- archive-redirect -->
<a id="dynamic-layer-slot-lifetime-20261029"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#dynamic-layer-slot-lifetime-20261029) <!-- archive-redirect -->
<a id="e-2026-10-07-authored-layer-retirement"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-authored-layer-retirement) <!-- archive-redirect -->
<a id="e-2026-10-07-puppet-animation-control"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-puppet-animation-control) <!-- archive-redirect -->
<a id="e-2026-10-07-puppet-animation-visibility"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-puppet-animation-visibility) <!-- archive-redirect -->
<a id="e-2026-10-07-puppet-bone-alpha"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-puppet-bone-alpha) <!-- archive-redirect -->
<a id="e-2026-10-07-puppet-static-weight"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-puppet-static-weight) <!-- archive-redirect -->
<a id="e-2026-10-07-signal-color"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-07-signal-color) <!-- archive-redirect -->
<a id="e-2026-10-08-frame-declaration"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-frame-declaration) <!-- archive-redirect -->
<a id="e-2026-10-08-gradient-storage-isolation"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-gradient-storage-isolation) <!-- archive-redirect -->
<a id="e-2026-10-08-hdr-color-boundary"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-hdr-color-boundary) <!-- archive-redirect -->
<a id="e-2026-10-08-inherited-parallax"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-inherited-parallax) <!-- archive-redirect -->
<a id="e-2026-10-08-localized-graph-input"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-localized-graph-input) <!-- archive-redirect -->
<a id="e-2026-10-08-media-base-fallback"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-media-base-fallback) <!-- archive-redirect -->
<a id="e-2026-10-08-paused-display-recovery"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-paused-display-recovery) <!-- archive-redirect -->
<a id="e-2026-10-08-puppet-clipping"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-puppet-clipping) <!-- archive-redirect -->
<a id="e-2026-10-08-puppet-v21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-puppet-v21) <!-- archive-redirect -->
<a id="e-2026-10-08-shared-source-material"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-shared-source-material) <!-- archive-redirect -->
<a id="e-2026-10-08-source-material"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-source-material) <!-- archive-redirect -->
<a id="e-2026-10-08-unlit-product"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-unlit-product) <!-- archive-redirect -->
<a id="e-2026-10-08-varying-scalar-conversion"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-08-varying-scalar-conversion) <!-- archive-redirect -->
<a id="e-2026-10-09-single-replay"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-09-single-replay) <!-- archive-redirect -->
<a id="e-2026-10-10-webm-video"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-10-webm-video) <!-- archive-redirect -->
<a id="e-2026-10-11-puppet-reference"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-11-puppet-reference) <!-- archive-redirect -->
<a id="e-2026-10-16-bool-return"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-bool-return) <!-- archive-redirect -->
<a id="e-2026-10-16-composition-local-perspective"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-composition-local-perspective) <!-- archive-redirect -->
<a id="e-2026-10-16-dynamic-image-material"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-dynamic-image-material) <!-- archive-redirect -->
<a id="e-2026-10-16-general-bloom-strength-script"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-general-bloom-strength-script) <!-- archive-redirect -->
<a id="e-2026-10-16-general-bloom-strength-script-scene-scalar到现有bloom"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-general-bloom-strength-script-scene-scalar到现有bloom) <!-- archive-redirect -->
<a id="e-2026-10-16-intro-phase"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-intro-phase) <!-- archive-redirect -->
<a id="e-2026-10-16-puppet-animation-events"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-puppet-animation-events) <!-- archive-redirect -->
<a id="e-2026-10-16-puppet-animation-events-现代mdla与原包接续"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-puppet-animation-events-现代mdla与原包接续) <!-- archive-redirect -->
<a id="e-2026-10-16-puppet-animation-layer-lookup"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-puppet-animation-layer-lookup) <!-- archive-redirect -->
<a id="e-2026-10-16-sound-random"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-sound-random) <!-- archive-redirect -->
<a id="e-2026-10-16-unused-version-combo"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-2026-10-16-unused-version-combo) <!-- archive-redirect -->
<a id="e-native-regexp-captures"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-native-regexp-captures) <!-- archive-redirect -->
<a id="e-property-condition-reachability"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-property-condition-reachability) <!-- archive-redirect -->
<a id="e-property-preparation-reuse"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#e-property-preparation-reuse) <!-- archive-redirect -->
<a id="effect-combined-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#effect-combined-qualification-20261018) <!-- archive-redirect -->
<a id="empty-effect-lookup-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#empty-effect-lookup-20261017) <!-- archive-redirect -->
<a id="forward-composition-prefix-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#forward-composition-prefix-20261019) <!-- archive-redirect -->
<a id="fullscreen-visible-owner-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#fullscreen-visible-owner-20261017) <!-- archive-redirect -->
<a id="gaussian-zero-axis-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#gaussian-zero-axis-20261019) <!-- archive-redirect -->
<a id="generic-varying-array-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#generic-varying-array-20261021) <!-- archive-redirect -->
<a id="generic-varying-first-gate-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#generic-varying-first-gate-20261019) <!-- archive-redirect -->
<a id="grouped-varying-prefix-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#grouped-varying-prefix-20261021) <!-- archive-redirect -->
<a id="image-font-script-state-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#image-font-script-state-20261020) <!-- archive-redirect -->
<a id="image-terminal-placement-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#image-terminal-placement-20261021) <!-- archive-redirect -->
<a id="independent-signal-opaque-auxiliary-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#independent-signal-opaque-auxiliary-20261021) <!-- archive-redirect -->
<a id="intake-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-20261017) <!-- archive-redirect -->
<a id="intake-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-20261019) <!-- archive-redirect -->
<a id="intake-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-20261021) <!-- archive-redirect -->
<a id="intake-20261022"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-20261022) <!-- archive-redirect -->
<a id="intake-3221354414-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-3221354414-20261017) <!-- archive-redirect -->
<a id="intake-five-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#intake-five-20261021) <!-- archive-redirect -->
<a id="light-water-current-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#light-water-current-20261019) <!-- archive-redirect -->
<a id="lit-image-emission-albedo-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#lit-image-emission-albedo-20261019) <!-- archive-redirect -->
<a id="logical-macro-invocation-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#logical-macro-invocation-20261018) <!-- archive-redirect -->
<a id="mdl-static-position-uv20-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#mdl-static-position-uv20-20261017) <!-- archive-redirect -->
<a id="mixed-vector-mix-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#mixed-vector-mix-20261019) <!-- archive-redirect -->
<a id="model-reflection-prototype-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#model-reflection-prototype-20261018) <!-- archive-redirect -->
<a id="named-dependency-direct-anchor-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#named-dependency-direct-anchor-20261020) <!-- archive-redirect -->
<a id="native-camera-frame-transforms-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-camera-frame-transforms-20261019) <!-- archive-redirect -->
<a id="native-framebuffer-source-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-framebuffer-source-20261019) <!-- archive-redirect -->
<a id="native-rope-camera-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-rope-camera-20261019) <!-- archive-redirect -->
<a id="native-text-bounds-20261022"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-text-bounds-20261022) <!-- archive-redirect -->
<a id="native-text-depth-qualification-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-text-depth-qualification-20261020) <!-- archive-redirect -->
<a id="native-text-depth-qualification-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#native-text-depth-qualification-20261023) <!-- archive-redirect -->
<a id="open-visual-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#open-visual-qualification-20261018) <!-- archive-redirect -->
<a id="optional-graph-output-slot-vector-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#optional-graph-output-slot-vector-20261020) <!-- archive-redirect -->
<a id="ordinary-effect-light-host-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#ordinary-effect-light-host-20261021) <!-- archive-redirect -->
<a id="ordinary-native-image-depth-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#ordinary-native-image-depth-20261019) <!-- archive-redirect -->
<a id="packaged-ogg-extraction-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#packaged-ogg-extraction-20261021) <!-- archive-redirect -->
<a id="parallax-depth-omission-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#parallax-depth-omission-20261018) <!-- archive-redirect -->
<a id="particle-audio-mode-default-20261028"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-audio-mode-default-20261028) <!-- archive-redirect -->
<a id="particle-color-composition-20261029"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-color-composition-20261029) <!-- archive-redirect -->
<a id="particle-coverage-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-coverage-qualification-20261018) <!-- archive-redirect -->
<a id="particle-event-inheritance-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-event-inheritance-20261023) <!-- archive-redirect -->
<a id="particle-fractional-count-20261022"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-fractional-count-20261022) <!-- archive-redirect -->
<a id="particle-position-defaults-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-position-defaults-20261023) <!-- archive-redirect -->
<a id="particle-position-mapping-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-position-mapping-20261023) <!-- archive-redirect -->
<a id="particle-root-world-translation-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-root-world-translation-20261017) <!-- archive-redirect -->
<a id="particle-sprite-size-unit-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#particle-sprite-size-unit-20261018) <!-- archive-redirect -->
<a id="physical-pointer-ingress-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#physical-pointer-ingress-20261023) <!-- archive-redirect -->
<a id="pointer-scale-qualification-199-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#pointer-scale-qualification-199-20261020) <!-- archive-redirect -->
<a id="procedural-solid-local-source-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#procedural-solid-local-source-20261018) <!-- archive-redirect -->
<a id="pulse-eye-response-278-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#pulse-eye-response-278-20261021) <!-- archive-redirect -->
<a id="puppet-additive-local-fallback-20261029"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-additive-local-fallback-20261029) <!-- archive-redirect -->
<a id="puppet-animation-rate-script-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-animation-rate-script-20261020) <!-- archive-redirect -->
<a id="puppet-attachment-mdlv19-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-attachment-mdlv19-20261017) <!-- archive-redirect -->
<a id="puppet-bone-matrix-order-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-bone-matrix-order-20261018) <!-- archive-redirect -->
<a id="puppet-mdla5-alpha-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-mdla5-alpha-20261017) <!-- archive-redirect -->
<a id="puppet-multi-target-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-multi-target-20261017) <!-- archive-redirect -->
<a id="puppet-reference-fallback-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-reference-fallback-20261017) <!-- archive-redirect -->
<a id="puppet-rotation-continuity-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#puppet-rotation-continuity-20261020) <!-- archive-redirect -->
<a id="quad-visibility-live-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#quad-visibility-live-20261020) <!-- archive-redirect -->
<a id="refraction-static-primary-20261101"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#refraction-static-primary-20261101) <!-- archive-redirect -->
<a id="retired-layer-diagnostic-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#retired-layer-diagnostic-20261023) <!-- archive-redirect -->
<a id="ring-motion-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#ring-motion-qualification-20261018) <!-- archive-redirect -->
<a id="rope-whole-source-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#rope-whole-source-20261017) <!-- archive-redirect -->
<a id="sampler-presence-requirements-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#sampler-presence-requirements-20261017) <!-- archive-redirect -->
<a id="scene-named-animation-scope-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#scene-named-animation-scope-20261017) <!-- archive-redirect -->
<a id="scene-video-stale-query-329-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#scene-video-stale-query-329-20261020) <!-- archive-redirect -->
<a id="screen-displacement-ribbon-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#screen-displacement-ribbon-20261020) <!-- archive-redirect -->
<a id="selected-provider-admission-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#selected-provider-admission-20261018) <!-- archive-redirect -->
<a id="shader-float2-consumer-width-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#shader-float2-consumer-width-20261017) <!-- archive-redirect -->
<a id="shader-vec2-authored-fallback-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#shader-vec2-authored-fallback-20261018) <!-- archive-redirect -->
<a id="shared-alpha-vm-convergence-20261102"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#shared-alpha-vm-convergence-20261102) <!-- archive-redirect -->
<a id="shared-timer-cancellation-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#shared-timer-cancellation-20261018) <!-- archive-redirect -->
<a id="shortcut-beneficiary-intake-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#shortcut-beneficiary-intake-20261017) <!-- archive-redirect -->
<a id="single-slot-default-20261023"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#single-slot-default-20261023) <!-- archive-redirect -->
<a id="single-timeline-response-fallback-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#single-timeline-response-fallback-20261018) <!-- archive-redirect -->
<a id="sprite-alpha-coverage-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#sprite-alpha-coverage-20261020) <!-- archive-redirect -->
<a id="static-camera-transforms-20261028"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#static-camera-transforms-20261028) <!-- archive-redirect -->
<a id="static-model-canvas-basis-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#static-model-canvas-basis-20261018) <!-- archive-redirect -->
<a id="static-model-depth-pending-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#static-model-depth-pending-20261019) <!-- archive-redirect -->
<a id="static-model-normal-coverage-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#static-model-normal-coverage-20261018) <!-- archive-redirect -->
<a id="surface-zero-roughness-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#surface-zero-roughness-20261019) <!-- archive-redirect -->
<a id="text-vm-convergence-20261102"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#text-vm-convergence-20261102) <!-- archive-redirect -->
<a id="timeline-command-owner-order-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#timeline-command-owner-order-20261018) <!-- archive-redirect -->
<a id="u02-three-lighting-fresh-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u02-three-lighting-fresh-20261018) <!-- archive-redirect -->
<a id="u05-fluid-content-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u05-fluid-content-20261018) <!-- archive-redirect -->
<a id="u05-source-proven-signal-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u05-source-proven-signal-20261017) <!-- archive-redirect -->
<a id="u05流体单帧内容资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u05流体单帧内容资格2026-10-18) <!-- archive-redirect -->
<a id="u10-active-ring-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u10-active-ring-20261018) <!-- archive-redirect -->
<a id="u10默认音频细环资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u10默认音频细环资格2026-10-18) <!-- archive-redirect -->
<a id="u11-visible-ring-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u11-visible-ring-20261018) <!-- archive-redirect -->
<a id="u11亮紫能量与形态落点资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u11亮紫能量与形态落点资格2026-10-18) <!-- archive-redirect -->
<a id="u25-u35-current-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u25-u35-current-qualification-20261018) <!-- archive-redirect -->
<a id="u25u35当前视觉资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u25u35当前视觉资格2026-10-18) <!-- archive-redirect -->
<a id="u26-source-resolution-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u26-source-resolution-20261018) <!-- archive-redirect -->
<a id="u26白弧与source尺寸资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u26白弧与source尺寸资格2026-10-18) <!-- archive-redirect -->
<a id="u27-lion-blink-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u27-lion-blink-qualification-20261018) <!-- archive-redirect -->
<a id="u27蒙皮源深度与狮头眨眼2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u27蒙皮源深度与狮头眨眼2026-10-18) <!-- archive-redirect -->
<a id="u28-visual-qualification-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u28-visual-qualification-20261018) <!-- archive-redirect -->
<a id="u37-scalar-loop-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u37-scalar-loop-20261018) <!-- archive-redirect -->
<a id="u37实际标量循环资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#u37实际标量循环资格2026-10-18) <!-- archive-redirect -->
<a id="uniform-pure-initializer-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#uniform-pure-initializer-20261021) <!-- archive-redirect -->
<a id="uniform派生纯内建全局初始化2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#uniform派生纯内建全局初始化2026-10-21) <!-- archive-redirect -->
<a id="user-shortcut-authored-fallback-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#user-shortcut-authored-fallback-20261017) <!-- archive-redirect -->
<a id="user-shortcut-native-20261020"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#user-shortcut-native-20261020) <!-- archive-redirect -->
<a id="utility-axis-domain-20261019"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#utility-axis-domain-20261019) <!-- archive-redirect -->
<a id="vec3-equals-color-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#vec3-equals-color-20261021) <!-- archive-redirect -->
<a id="video-pair-current-recheck-20261028"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#video-pair-current-recheck-20261028) <!-- archive-redirect -->
<a id="video-position-publication-20261022"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#video-position-publication-20261022) <!-- archive-redirect -->
<a id="video-publication-demand-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#video-publication-demand-20261021) <!-- archive-redirect -->
<a id="visual-feedback-followup-20261018"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#visual-feedback-followup-20261018) <!-- archive-redirect -->
<a id="water-cadence-qualification-20261021"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#water-cadence-qualification-20261021) <!-- archive-redirect -->
<a id="wemath-mix-value-boundary-20261017"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#wemath-mix-value-boundary-20261017) <!-- archive-redirect -->
<a id="共享timer取消与原包hover2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#共享timer取消与原包hover2026-10-18) <!-- archive-redirect -->
<a id="分组只读-varying-前缀读取2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#分组只读-varying-前缀读取2026-10-21) <!-- archive-redirect -->
<a id="动画rate-number值源与原作者音频变速2026-10-20"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#动画rate-number值源与原作者音频变速2026-10-20) <!-- archive-redirect -->
<a id="后继5包增量诊断2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#后继5包增量诊断2026-10-21) <!-- archive-redirect -->
<a id="图像font脚本状态与真实字体热切换2026-10-20"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#图像font脚本状态与真实字体热切换2026-10-20) <!-- archive-redirect -->
<a id="基础方形sprite的绝对尺寸标尺2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#基础方形sprite的绝对尺寸标尺2026-10-18) <!-- archive-redirect -->
<a id="已打包-ogg-与声音准入一致2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#已打包-ogg-与声音准入一致2026-10-21) <!-- archive-redirect -->
<a id="文字环与挂点运动资格2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#文字环与挂点运动资格2026-10-18) <!-- archive-redirect -->
<a id="普通-effect-灯光宿主与同帧半径2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#普通-effect-灯光宿主与同帧半径2026-10-21) <!-- archive-redirect -->
<a id="普通-program-仅-alpha-读取2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#普通-program-仅-alpha-读取2026-10-21) <!-- archive-redirect -->
<a id="未消费版本字段材质变换恢复2026-10-16"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#未消费版本字段材质变换恢复2026-10-16) <!-- archive-redirect -->
<a id="水面帧节奏资格未实施调度修改2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#水面帧节奏资格未实施调度修改2026-10-21) <!-- archive-redirect -->
<a id="独立信号合成的-opaque-辅助与-alpha-only-旁读2026-10-21"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#独立信号合成的-opaque-辅助与-alpha-only-旁读2026-10-21) <!-- archive-redirect -->
<a id="现代dense常量参考轨道有界准备与播放2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#现代dense常量参考轨道有界准备与播放2026-10-18) <!-- archive-redirect -->
<a id="程序化quad整层显隐热更新"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#程序化quad整层显隐热更新) <!-- archive-redirect -->
<a id="粒子覆盖材质原型未采纳2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#粒子覆盖材质原型未采纳2026-10-18) <!-- archive-redirect -->
<a id="蓝烟花事件与画面资格"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#蓝烟花事件与画面资格) <!-- archive-redirect -->
<a id="资产路径string与字体回调2026-10-18"></a> [归档记录](../history/runtime-evidence-current-through-2026-11-02.md#资产路径string与字体回调2026-10-18) <!-- archive-redirect -->
