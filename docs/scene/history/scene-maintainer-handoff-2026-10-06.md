<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。本页是接手时点的冻结快照；现役顺序归[兼容路线](../roadmap/scene-compatibility-roadmap.md)与[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Scene 暂停交接（2026-10-06）

> **已接手（2026-10-06，后继 Agent）**：用户已向新会话下达恢复授权并重申目标；暂停状态解除，本文第1–5节的范围、已完成能力与工作卡由后继 Agent 沿用执行，不再作为"暂停中"的有效状态。接手核对结果：HEAD `dead0a10`、工作区干净、分支 `codex/engine-refactor-program`，与本记录一致。后续进度以各权威文档与提交为准，本页冻结为接手时点快照。

用户要求本批收尾提交后暂停长期 Goal，原因是额度不足。本文件所在提交是暂停快照；恢复时先核对当前 HEAD 和 dirty paths，不能假定工作区仍与本记录一致。本页是恢复操作说明，长期选序仍归[兼容路线](../roadmap/scene-compatibility-roadmap.md)和[断点队列](../roadmap/scene-open-breakpoint-queue.md)，能力合同仍归相应专题。

## 1. 用户目标与不可改变的顺序

- 最终目标：真实样本正确加载、播放、交互和合成，同时减少复杂度、重复职责与运行成本。正确性优先，其次覆盖收益、简单性和性能；提交、测试、代码数量都不是成果。
- **先完成太阳系 `3662790108` 的剩余问题**，再处理用户重点：HDR/SDR 默认变暗及 HDR 开关不生效；重型星球/三体普通入口不能启动。不得以单模型或 Debug Host 成功关闭整景/普通入口问题。
- 每批汇报当前专项的粗略完成度、真正进入链路的能力、实际画面收益、受益范围与下一批；不要报全语料完整正确率。本次太阳系粗略工程估计约 **65%**，不是测量得出的完整正确率，也不是官方 parity。
- 音乐来源应是跨样本通用能力，目标包括 Apple Music、QQ、汽水、网易云等。不得只给一个样本或一个播放器做专门 renderer。调试窗口不是当前交付目标。

## 2. 恢复的第一步

1. 读根 `AGENTS.md` 和 `.agents/skills/mywallpaperx-maintainer/SKILL.md`，从 `docs/README.md`、仓库地图、技术栈合同与 `docs/scene/README.md` 路由。不要从历史报告或整个 Reference Project 开始。
2. 执行 `git status --short --branch --untracked-files=all`、`git log -8 --oneline`，列精确 owned paths。暂停前分支 `codex/engine-refactor-program`；本批起点 `fa02f6bf3c21c7454aa7134dadcf4e5157e25cc4`。只窄暂存/提交，不推送。
3. 读本页第3、4节及本批[默认模型纹理记录](static-model-default-albedo-implementation-2026-10-06.md)。先确认前批运行与本机文件仍在，丢失旧临时证据时如实重建，不伪称已复验。
4. 只选择一个最早错误的职责，先复现可见问题再改代码；两次实验未推进断点就重新定位。重要能力先更新既有设计和 `script/design_gated_areas.json`；approved 只表示可实施。

## 3. 现在已经有什么，不能重做什么

| 范围 | 已证能力 | 尚未证明 |
|---|---|---|
| 太阳系材料与输入 | 材料值脚本、3D鼠标投影/拖动已分批闭合；轨道由同一 prepared Program 在显示分辨率重光栅，真实总览细线连续 | 全物体交互、全场景光照与完整视觉 |
| 本轮真实原包交互 | 媒体大小 live 1→1.5、窗口0.75→1成功；同一surface/window保持。中文水星标签双击进入近景；原生右箭头进入水星、左箭头返回总览 | 其他天体/探测器全导航、默认布局与官方一致性 |
| 本轮 JUNO 默认 albedo | 使用原MDL/7材料/7TEX的隔离近景，缺失银色机身、天线盘及连接部件恢复；其他材料保留 | 原完整太阳系内导航到JUNO的最终同视角验收，normal/reflection/PBR官方外观 |
| 文件背景/封面 | 既有原位纹理事务与用户确认的选择能力，避免重建整景；详见文件纹理实施记录 | 所有user slot/多pass/动态拓扑组合；不能凭旧“重建慢”反馈再造第二事务 |
| 系统媒体 | 已有统一需求驱动producer/inbox、真实来源Debug实验、封面/文字输入；入口见系统媒体设计 | Release系统私有后端未开放，所有播放器/歌词未覆盖 |
| HDR/SDR | SDR白点纠正、五字段HDR Bloom、可选EDR均已有实施；具体条件见D2设计和执行记录 | 所有样本不暗、物理HDR亮度、混合多屏与全部开关组合 |

轨道实现不要退回“把10×10源纹理放大”或抬 source resolution：源采样尺寸与显示光栅是两种职责。当前同时保留原 graph 执行以维护状态/历史，额外小光栅是明确过渡成本，不声明性能优化。不要删旧执行而破坏 feedback/history。

JUNO 默认输入修复位于 `SceneStaticModelMaterialBindingCompiler` → `MaterialPassDescriptor.staticModelDefaultAlbedoAssetPath` → `ScenePreparedStaticModelResources` → 原 `SceneMetalRenderer+StaticModels`。sampler 元数据与颜色 uniform 证明分离：后者 unavailable 不表示部件应消失；rejected 仍拒绝。显式坏路径绝不能变白。默认只用于未指定的普通颜色资产，不改 authored slots/combo，也不按 generic4/样本名分派。

## 4. 后继工作卡（全部仍待执行或补验）

### S1 — 太阳系近景材质、亮度与JUNO完整场景验收

**用户现象：**本轮水星近景大片发白；总览媒体面板与系统信息在默认1.5大小下重叠。前者为已见画面问题，尚未定位光照、Bloom、材质或输出的首因；后者尚不能认定引擎错误。不要直接改作者参数消除症状。

**先做：**用原pkg隔离副本固定App、属性、相机和曝光条件。水星保留同一场景/相机，依次隔离材质direct light、emission、Bloom、终端transfer，取得能解释像素变化的单一首断点。优先看现 `SceneStaticModelPipeline`/`SceneStaticModel.metal`、光照快照与唯一Bloom/output owner；不要先套新tone mapper或降全局gain。需要官方行为时用自有最小输入并独立中性审查，不能读取私有shader实现。

JUNO先从原总览经右箭头进入木星，开启探测器/标签，再进入JUNO；具体路径是 `s→p1→p2→p3→p4→dp1→p5`，随后木星下JUNO标签/代理。原图层3677对应JUNO，foil_silver原slot0为null、slot1为normal。这些ID只用于诊断。隔离fixture已证明加载收益，不能替代完整层级/脚本可见性验收。

**布局核查：**作者info/media锚点分别约屏幕top47%/19%，内部大小默认1.5，并按屏幕短边/2160缩放；媒体size1时重叠消失。screenResolution已沿drawable物理像素传给VM。本轮resize/属性响应通过；未有官方布局对照，禁止因为肉眼重叠就改screenResolution或自动避让作者层。

**完成门：**原包可进入/返回、标签和材质正确，JUNO不缺主体且其他部件未回退；水星曝光问题有明确责任及有界正反例。粒子、文字、连续轨道、媒体覆盖与拖动需代表回归。`lightsourcesize`尚未接入，先确定可见收益与行为合同，不能把它与阴影半径混用。完成前不把整太阳系标为通过。

### H1 — HDR/SDR 用户反馈收口

先读[现役D2设计](../roadmap/batch2/hdr-tonemap-edr-design.md)第39行后的实施裁决及其链接，**不要重复造Bloom或EDR路径**。旧路线中“尚未开放EDR/缺scatter”是过期导航，本次已纠正。

用固定样本分别记录用户HDR开关、display headroom、surface格式/颜色空间和实际输出。检查SDR设备、EDR设备、移屏、开关热更新、暂停重绘、失败保旧帧。16F不等于线性；PNG只能验证编码后的显示，不是物理EDR亮度；Bloom/输出结果不得回写raw/history。不要重新引入默认压白shoulder，也不要用headroom常数或样本白名单修颜色。

HDR Bloom的五字段与scatter/上采样已存在。`iterations=0/1`的精确官方空间行为仍未定，当前低于2局部跳过Bloom，不能把这个fallback写成官方算法。多屏/物理亮度没有测量条件时明确待验，保持正确SDR。

### L1 — 重型星球/三体普通入口启动

用户尚未给出本轮唯一失败样本identity，先在只读真实目录确认对应项目标题与ID，再从普通 App dispatch→client→daemon 固定一次失败请求。记录 parse/prepare/VM/shader/resource/candidate首帧的最早阻断，不把“没画面”直接归因于GPU预算。

历史Earth隔离Host约10秒启动不能关闭这项。RF16已经修过多材质读取和资源准备，不能再截断parts或抬全局预算绕过失败。真正超预算/整数溢出/stale/generation拒绝必须保留。修共享owner后需要原入口首帧、持续播放、取消/切换/退出drain与普通轻样本回归。

### M1 — 通用播放器、封面与歌词后继

恢复时按[系统媒体设计](../roadmap/batch2/system-media-input-design.md)确认已启用的Debug实验入口和Release边界；D6仍约束私有backend分发。单producer、单inbox、source epoch与迟到回包拒绝必须保留。系统来源未知时不要用Apple Music旧曲目冒充当前来源；不能为QQ/汽水另造状态树。先确认平台实际供应哪些metadata，再补适配、切歌/暂停/退出/无封面和多播放器仲裁；歌词是独立能力，歌曲名/专辑图出现不代表歌词支持。本文没有宣称上述播放器全部已验证。

2026-10-06 第一片已完成：平台供应表与实时链验证见[系统媒体供应与实时链](system-media-live-supply-verification-2026-10-06.md)（WebKit非音乐源活链+自然切歌实时跟随；适配/切歌路径确认无需按播放器新代码，仲裁权在系统localNowPlaying）。剩余：暂停/恢复真实观察、多播放器并发仲裁显式观察、QQ/网易云/汽水账号内实测、歌词独立批。

### 其余已规划、不要误认为完成

[Batch2索引](../roadmap/batch2/batch2-design-index.md)与[派生卡](../roadmap/batch2/reference-evidence-implementation-cards.md)保留完整范围。D1未知passthrough/特殊变换、D4/D11未确认API/reset、Vortex/Remap/collision-bounds剩余profile、D12缺失mip profile仍按各设计执行；D5 Web跨源回包、D7下载失败可见性是独立队列。D9/D10已有policy/frame gate，不再造第二clock/throttle。设计approved、参考报告条目、语料统计都不等于已执行或用户验收。

## 5. 测试、运行和独立审查的最短正确路径

- 修改Swift先跑最近能否定改动的门，再 `bash script/run_checkpoint_build.sh --cache-dir /private/tmp/mwx-scene-next-build/cache`。使用 `verify_scene_change.py --owned-path <精确路径>`查询门，不把它当锁或全部能力证明。
- 本批最近门：`python3.12 -B -m unittest script.tests.test_scene_static_model_material_bindings script.tests.test_scene_static_model_material_properties script.tests.test_scene_static_model_parts.SceneModelPartsNativeTests`。schema相关可补 `test_scene_sampler_default_purpose`。记录源码/fixture/App身份，独立只读审查冻结diff和实际PNG；Agent不能只复述日志就声称看过画面。
- 每次App使用隔离HOME、user-defaults-suite和Workshop副本，真实 `~/Movies/MyWallpaperX/创意工坊/Scene`只读。签名时核nested helper同team；staged App在Debug缓存重建后必须重新复制签名，不能用旧App验新源码。
- Debug Host证明内部链路，普通产品问题仍需App→client→daemon。ready、GPU completion、非黑和脚本无错误都不能单独关闭视觉问题。退出需surfaces1→0且gpuDrained=true。
- 标签会移动；本轮英文层640与中文1340范围不同。先前点x=.151只命中英文，中文范围内x=.107/y=.101的受控双击已切到水星。不要再修一个未复现的doubleClick bug。debug hover override会持续覆盖原生指针；原生交互run必须不传hover参数。CLI参数是 `--mwx-debug-scene-hover-pointer-json`，不是简写。
- Scene主链保持 authored→prepared Program/graph/resources→typed frame→Metal→唯一compositor。普通帧不解析/建图/全图hash；identity、clock、资源寿命、输出各唯一。视觉失败局部降级，unsafe状态最小拒绝。原子资源替换不能重启整景。

## 6. 已知基线失败与证据保存

- structure门有两项既有FAIL，同因 `shape-derived-analyzer-fleet` 66/65；本批无新增该家族。不要为通过直接改基线。前批冻结对照和本批日志均保留。
- graph全门有既有 `unselectedPotentialDoesNotRevokeSystemOnlyProgram` 失败（前批270/271）；实际external-primary与断言none不一致。不能把它伪称本批回归，也不能删断言过门。必要独立修复从其固定反例开始。
- 本批独立证据位于 `/private/tmp/mwx-solar-layout-20261006`，最终四包（默认模型、resize、原生返回、中文双击）的路径/SHA以本批执行记录和archive manifest为准。默认模型包内保留run_app.py、stage_app.py和JUNO包；恢复时先解压到新的隔离目录并改脚本旧绝对路径，再从当前源码构建/签名，不能假定原App/HOME/Workshop副本还在。JUNO官方自有探针包位于 `/private/tmp/mwx-model-default-20261006/model-default-texture-observations-v1.tar.gz`，SHA `d0fe551d3cae55b469c78ba3b3df7124d908118d530a7d61cfd7e08f0da8436f`。
- 前批轨道包 `/private/tmp/mwx-solar-orbits-20261006/runtime-evidence.zip`，SHA `f09d3447f0a0841b8e29faca2cfe495e887cb1addc8ffc42bbdd8152501c453b`，保留至2026-10-20。`.artifacts/scene-evidence/runs`已接近现有总预算，promotion失败不是数据无效，也不授权扩预算/删未知证据；先按既有artifact规则检查到期与唯一性。
- 暂停只留一份build cache `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`、一份shader cache `/private/tmp/mwx-system-media-20261005/runtime-cache`供恢复；缓存不能作运行证据。本机临时路径不保证永存，最终archive与源码冻结是重建入口。

## 7. 已完成设计归档与后继Agent注意事项

本次将终端光栅与诊断截图生命周期两份已完成的有界设计从batch2移到history，移交运行架构并删除其已完成设计门登记。D2/D3/媒体等尚有明确余项的卡不整篇归档，只纠正已完成段和入口；不能把已做的Bloom/EDR或统一媒体producer重新排成待实现。此归档与用户要求的暂停交接是本次文档新增/职责迁移的依据，预算只按精确变化登记，不放宽代码或证据门。

后继Agent特别容易犯的错误：

不要看见材质binding unavailable就认定整模型不能画；不要把502条按segment打印的日志当502次shader编译；不要把上一次App截图当新build证据。不要对整个Xcode工程文件做回退：用户说明它可能由Xcode自动更新，先核当前差异和归属。禁止reset/checkout/clean/add -A等宽操作。不要读私有实现再声称clean-room；只消费公开文档、作者数据和审查通过的中性黑盒合同。不复制参考项目代码，不按sample/path/hash决定算法。

每批只交一个完整可验结果；发现反例就修正假设，不以写报告代替实现。用户暂停后已于 2026-10-06 向后继 Agent 授权恢复；以上工作卡正在按本页顺序执行，其完成状态以各权威文档与提交为准。
