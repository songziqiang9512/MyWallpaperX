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
- `3749463715` 的 feedback content 与 utility-capture 语义断点仍由既有 strict PASS 证据关闭：完整 Program variant envelope 在 launch preparation 区分颜色与 typed data。2026-09-13 的动态 attachment fresh 回放另稳定复现 `frame-target-plan-allocation-failed`：成功帧仍有16/16 graph encode、terminal compositor与0 GPU failed frame，但失败观察与成功观察交替，整份 benchmark严格为NON-PASS。该现象是独立的target allocator/identity transition断点，不推翻feedback content合同，也不能继续把“graph已全部关闭”写成当前样本事实；见[动态 attachment 当前证据](semantics/runtime-evidence-current.md#e-2026-09-13-puppet-dynamic-attachment)。
- 旧 Q1 的四个 effect-local passthrough 观察断点已关闭。当前签名 App 对 `3323988600 / 3395777145 / 3472940912 / 3754630802` 均为 strict PASS；Pixelate 的 component-wise vector conversion、跨 stage loop guard 符号冲突、Standard Blur 静态 tint 准入和 Fire 标量 LOD data sampling 已分别修正。后继又按作者 media 事件合同关闭 `3395777145` layer 125 的三项 active unsupported：25/25 active effect 均由 Program 执行，playback state 1 正例持续显示封面/文字，无 media 反例按作者 state 0 隐藏；作者脚本没有鼠标点击回调。现役证据见[作者 media 面板闭环](semantics/runtime-evidence-current.md#e-2026-09-13-authored-media-panel)。该结论不证明 macOS live now-playing producer或整样本逐像素 parity。
- `3754630802` 最后的 Workshop Bokeh Blur 与 Motion Blur active unsupported 已关闭。terminal Program 现在接受精确 `effect.output` 或同 effect 内部 FBO；共享全帧工作对可与独立 authored FBO history 共存，但工作对仍不进入 history closure，并以独立 storage/generation/physical token 审计。fresh 真实运行 31/31 active effect 均由 Program 执行，92/92 frame 完成、0 failed，五个 utility capture 全部成功，完整人物、舞狮、灯笼和动态构图在 ready/after 中持续存在。现役证据见[共享工作对与历史终端闭环](semantics/runtime-evidence-current.md#e-2026-09-13-shared-pair-history-terminal)。该证据不证明独立 Bokeh/Motion Blur ROI、逐像素官方 parity 或性能完成。
- `3787382101` 的旧 Water Waves “整个人物扭曲”债务已由当前架构下的同构 A/B 关闭。真实样本 fresh 运行 strict PASS；隔离副本只保留人物 layer 28，并以相同 Program/graph/资源分别比较作者 `strength=0.04` 与 `strength=0`。左波、右波、双波及三份零强度对照全部 strict PASS；零强度 ready/after 逐字节相同，作者强度的像素差分别落在两张 `1400×600` R8 作者 mask 选中的左右部件，双波为两者并集。没有新增 Water Waves owner、预算、fallback 或身份分派。现役证据见[Water Waves 作者 mask 同构 A/B](semantics/runtime-evidence-current.md#e-2026-09-13-water-waves-mask-ab)。人工 acceptance verdict 仍须维护者观看完整样本后单独更新。
- SceneScript `ITextureAnimation` 公共 API 已沿唯一 QuickJS/frame/resource/compositor 主链关闭。`3299228616 / 3768903841` 在当前签名 App 上 2/2 strict PASS，作者 `frameCount/duration/rate/play/pause/stop/isPlaying/getFrame/setFrame/join` 通过同一 SceneClock、owner transaction 和现有 atlas/multi-image provider 消费；两个完整构图持续可见且动画发生变化。没有恢复 fixed profile，也没有新增 provider、clock 或 renderer。现役证据见[TextureAnimation 公共 API 闭环](semantics/runtime-evidence-current.md#e-2026-09-13-texture-animation-api)。
- SceneScript `ILayer.getTransformMatrix()` 与只读 `size` 首断点已关闭。world matrix 由 renderer 现役 world-frame resolver 投影到同一 immutable layer snapshot，C/QuickJS bridge 不做坐标计算；作者 layer `918 / 920 / 921 / 944 / 947 / 950` 在 `3238423642` 中全部 `generic-only` 完成，0 SceneScript VM failure，真实画面中的主体、日期与时钟保持正确合成。现役证据见[ILayer world matrix 闭环](semantics/runtime-evidence-current.md#e-2026-09-13-ilayer-world-matrix)。
- 旧 Q1 的 `nomip / halfmip sampler policy` 已按作者数据纠正并关闭。`nomip` 是离线编译输入，编译后的实际 mip level 序列才是运行时权威；`halfmip` 当前只有 importer declaration，不能映射成猜测的 TEX V5 bit。现役 loader 原样保留有效单级/多级链，超限单级 embedded TEX 的 bounded decode 仍保持单级，多级链不能完整保留时局部失败，直接图片才生成完整链。真实 `2470144420` 的单级 `halo_6` 与 7 级 `rosepetals` 同时加载并保持完整动态构图。现役证据见[编译 mip 链闭环](semantics/runtime-evidence-current.md#e-2026-09-13-compiled-mip-chain)。
- Camera Parallax 与 2D Camera Shake 的 direct User Property 纵向链已关闭。八个 exact 字段由现役 binding program 进入同一 typed snapshot；Parallax 复用既有 configuration/smoother，Shake 只在有效 authored 正交投影内合并进唯一 camera frame。当前签名 App 对真实 `3766387484` 分别完成 parallax false→true 与 shake false→true，两次都保持 surface/window identity、GPU/graph/compositor/next-frame和完整构图。真正 perspective Shake 仍拒绝 live update。现役证据见[Camera live 属性闭环](semantics/runtime-evidence-current.md#e-2026-09-13-camera-live-properties)。
- `3768229922` 的启动过渡与 head-click 首断点已关闭。作者 camera path 在 30 FPS 下前 60 帧保持 `origin=(-99.999,681.99994)`、`zoom=2.4`，再到第 180 帧回到 `(0,0)`、`zoom=1`；镜头从下向上展开是作者定义。旧准入用 JavaScript 源码写法筛 object visibility owner，导致 layer `354` 的提示自销毁和 layer `202` 的点击控制都未进入现役 VM；cursor 又要求 child layer 重复声明本应从 parent/default 得到的 transform。现按 descriptor/type/wrapper 准入同一 effectful Boolean owner，自身 authored destroy 进入 topology transaction，cursor hit 复用 canonical world/camera projection。当前签名 App 中 layer 354 退出、主场景保持，延迟点击 layer 202 精确触发 `cursorClick` 并展开作者信息面板。现役证据见[作者启动与点击闭环](semantics/runtime-evidence-current.md#e-2026-09-13-authored-startup-destroy-cursor)。

## 2. 现役执行顺序

### Q1 — 作者参数、视觉验收与 tracked matrix

**状态：P0/P3/P4 长期开放。**

- tracked full-corpus identity-only matrix 尚未覆盖真实样本根全部成员；扩展矩阵不等于每个开发批次都运行全 corpus。
- script instance scalar/String/Vec2/Vec3、root particle override 八字段与本批 camera 八字段已有 typed live consumer；它们不再是整族缺失。现役明确开放的 Scene 级 target 首断点是 Bloom enable/threshold：已有 identity，但没有 binding producer 或全场 HDR post consumer。其余 unsupported target 继续逐个按作者类型、作用域和真实 consumer 建立纵向闭环，不能按字段相似性扩权。
- 以下是维护者基于 `be9858e` 播放观察登记的**待复现、待归因**清单。它们尚未在当前 HEAD 建立首断点，不能从症状直接推断 owner，也不能因本批 `3768229922` 通过而批量改写状态：

  | 样本 | 观察到的异常 |
  |---|---|
  | `3748311238 / 2932631210 / 2813231542 / 3788467391 / 2797913147` | 主体人物消失 |
  | `3747492842` | 无法播放 |
  | `3775355045 / 3775373546` | 两层视频经遮罩合成后，下层播放数秒开始卡顿并落后于上层动画 |
  | `1315486372` | 水波纹特效位置不正确 |
  | `2684431262` | 合成画面出现异常紫色块 |
  | `3749463715` | 动态 attachment current-pose已接通，胸部/手部child与parent骨骼在同一world-frame链更新，真实拖拽/回弹子证据通过；整样本仍被可重复的`frame-target-plan-allocation-failed`阻断strict PASS |

  下一批从当前签名 App 逐组做最小复现，先确定最早失效的 prepared product、typed frame state、provider/graph/geometry encode 或 compositor 环节，再按公共 owner 修复；不得把样本 ID 写入产品路由。
- 全部样本最终必须由人工裁决为 `pass` 或显式 `platform-unsupported`。当前开发仍按公共首断点和受影响样本推进，不用大批量回放代替逐项可见验收。
- 验收覆盖层中的 `fail` 与 `unreviewed` 必须逐个由维护者重新观看。`3264246690 / 3780119725 / 3238423642` 的旧 Puppet 技术原因及 `3787382101` 的旧 Water Waves mask 债务都已被 2026-09-13 后继证据取代，但没有维护者的新 verdict 时不得直接改成整样本 `pass`。
- 新发现的公共首断点回到 P1/P2；结构 PASS、非黑截图、route 数或完成事件不能单独改变人工 verdict。

### Q2 — 稳定帧性能、长稳与发布

**状态：P5；只有已妨碍当前样本正确播放时提前。**

旧 B7 对 Puppet source-update、coverage texture 和固定 `16.67 ms` 的归因已经失效。2026-09-13 四样本回放只说明当前 CPU/GPU 帧时间仍值得重新 profile；它没有建立发布阈值，也不能证明旧 source-update 是当前热点。进入本项时必须在当前 GeometryProduct/graph/compositor 路径重新采样，先区分 CPU submission、GPU execution、display cadence 与 benchmark driver，再按共享 owner 降本。系统性阈值、睡眠/唤醒、显示器变化、场景切换和签名发布门由 P5 建立。

## 3. 观察项与能力边界

以下内容不作为当前产品修复，除非新的定向复现把它们提升为最早可见断点：

- `3749463715` 已稳定复现隔帧 `frame-target-plan-allocation-failed`：14次executor failure与15批16/16成功encode交替，0 GPU failed frame但allocation identity transition门失败。下一批从target pool lease/释放、generation/physical token与同frame graph plan identity定位公共owner；不得放宽观察门或把成功邻帧当作恢复完成。
- 异步 provider 首帧 `layer-source-not-ready`；B8 已按公开合同定案为局部 previous-current/fallback 后自然恢复，不增加阻塞等待。若超时后仍未恢复，再按 provider 生命周期缺口处理。
- Puppet 跨层 geometry provider、rotation/gravity/IK、完整 3D 和逐像素官方 parity。当前命名 provider 只接受完整栅格 layer source，不能为了这些能力重新引入 Puppet 压平纹理。
- 旧 appendix 中未被当前运行证据复现的线索。能力宽度查[能力台账](semantics/coverage-ledger.md)，逐样本历史查[样本调试台账](semantics/scene-sample-debug-ledger.md)，不要从本队列复制历史数量。

## 4. B1–B9 退役索引

| 旧批次 | 当前结论 | 后继归属 |
| --- | --- | --- |
| B1 shader backend vector2 | 公共编译首断点已结构闭合 | 新 visual/parameter 缺口进入 Q1 |
| B2 dependency binding/publication | provider、隐藏 text dependency 与下游消费观察已闭合 | 新 graph first failure 进入路线 P1 |
| B3 SceneScript event/property | 已登记的 event-only、visibility、property color/vector、TextureAnimation 与 `getTransformMatrix` 初始化链已闭合 | 其余 API 进入 Q1 |
| B4 material envelope | 已登记 shape/format/compose owner 闭合 | 新 effect family 依路线 P1 归类 |
| B5 graph owner/publication | 2026-09-13 已分离 feedback persistence 与 content semantic；`3749463715` color terminal consumption、`3448845950` typed data publication和`3754630802` shared-pair/history terminal 均闭合 | 新 graph 缺口按路线 P1 归类 |
| B6 QuickJS typed semantics | angle/Vec3/string/error、TextureAnimation 命令事务与 bounded world-matrix snapshot 闭合 | 其余 API 进入 Q1 |
| B7 performance | 启动/teardown 与旧 micro-optimization 批次结束；稳定帧工作未完成 | Q2，用当前架构重建 profile |
| B8 async readiness | 合同闭合，首帧局部失败保持可观察并自然恢复 | §3 观察项 |
| B9 Puppet interaction/geometry | cursor→bone、世界空间直绘与受限MDAT动态attachment current-pose闭合 | Q1 其余人工验收；高级能力见 §3 |

旧 B1–B9 的逐次命令、临时路径、历史 HEAD 和中间失败保留在 Git 历史及语义证据文档中，不再作为现役执行说明。

## 5. 队列维护与批次门

1. 开始条目前先用当前签名 App 和最小样本集刷新首断点；不继承旧报告中的行号、耗时、数量或 owner 归因。
2. 一个职责批次必须同时完成产品实现、focused 正反门、checkpoint build、受影响真实样本证据和权威文档同步，再提交一次。不得以单文件或单行提交拆散能力项。
3. 普通开发批次禁止运行全量样本；只有路线 milestone 确实需要刷新整体集群时才运行，并仍不得把 strict PASS 当成视觉通过。
4. 设计错误直接删除或重写；不得通过增加纹理预算、扩大缓存、堆叠 fallback 或按样本分支掩盖根因。
5. 每次只在本文保留尚能驱动下一步的事实。已完成条目压缩进退役索引，详细证据写入对应能力/运行/样本台账。

当 Q1 的公共 authored target 首断点关闭，后续只剩路线 P0/P3/P4/P5 的系统性验收时，删除这个日期化派生入口或将其移入历史目录。
