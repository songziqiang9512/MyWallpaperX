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

P0 续跑状态（2026-09-16 夜间窗口，HEAD `a8e30458`+未提交批次）：

- P0.1 校准盘点：census 漂移已诊断并刷新（快照内容原定格 `a7b0111a`；`7a4cb4b4` 改生成器模板未重生成 → 源码自哈希漂移；corpus 实变＝45 份 `用户观察说明.md` 消失、`3477054430` 新增截图、32 样本被注入 root 属主 `shaders/blobsSM40/*.dxs` 树共 +592 文件、34 目录新增已排除的 `.mywallpaperx-scene-*` 派生文件）。`verify` passed（payload `9839015b…`），守恒全平衡（64816 occurrence、159/159、orphan 0），census 测试 9/9，独立子代理审查通过（P3 叙述类）。改动未提交：`script/scene_capability_census_snapshot.json`、`docs/scene/semantics/scene-corpus-capability-inventory.md`。
- 待用户裁决：45 份观察说明内容去向不明（本机常规缓存无副本）；样本根 root 属主注入的写入者未查。
- 生成器候选缺陷（另批处理）：md 证据列二元口径（census.py `render_markdown` 附近，仅有截图无说明的样本显示"无"）。
- 下一动作：P0.2 声明→能力/合同/owner→场景→证据关联，schema/migration 与引用完整性门先行。
- P0.2 粗映射已落地（2026-09-17 凌晨）：新增 `script/scene_capability_family_map.json`（19 能力词表锚定台账 §3 行名 + 70 规则）；census 扩展结构门/锚点门/映射守恒；2507 family = 2500 mapped + 7 显式 unknown（1 effect/unresolved、6 project-property kind 空/unknown），多对多、快照内可反查（`families[].capability_refs`、`summary.capability_mapping`、inventory §4.1）。独立子代理审查两轮：P2×2（override 引用完整性）已修，P3×3（类型门/sorted key/测试唯一性）已按处方修正；16 tests OK。verify 最终态以本块记录时的最后一次 generate+verify 为准。
- P0.3a 采集校准（DEBUG 隔离路径，App 身份 = `.codex/DerivedData` 2026-09-17 00:17 arm64 Debug ad-hoc 签名，隔离副本 `/private/tmp/mwx-p03-calibration`）：三代表 `3766415113`（纯静态）/`3767343314`（多 pass+feedback）/`2067939514`（脚本动态，45 层 72 效果）均真实运行，submitted/completed 全量 0 failed，截图/执行观测/route 证据可采。**采集缺口（阻塞，非样本失败）**：本机当前会话环境下 `presented=0 / presentStreams=0`（CAMetalLayer presentedHandler 未带有效 presentedTime），performance presentation 门三样本同因 FAIL；需在显示器活动会话复采后才能区分环境与产品缺口。首轮 CPU 分位数受并行构建/审查负载污染，不得当基线。
- 三元 stage-link 断点已修复（2026-09-17 本批，owner `SceneGenericShaderTernaryScalarConditionNormalizer.swift`）：`3767343314` layer 17 `ui_editor_properties_opacity_mask` 材质 shader 的 stage-link 拒绝（`author.frag:59: '' : boolean expression expected`）消失，复跑 `stage-link:rejected` 0 处、shader request `published/accepted`；benchmark PASS failures=[]，3060 callbacks / 3059 completed / 0 failed，60.0 FPS，presented=3058——前次记录的 `presented=0 / presentStreams=0` 为瞬时环境态，本轮同环境实测正常，非持续阻塞，修正此前记录。证据：`docs/scene/evidence/20260917-ternary-scalar-condition/`。**无迁移断点（修正此前两次误判）**：复跑日志中的 `launch-program-failure slot=1 material=mask` 是 launch 时 slot 未就绪→被 `presenceIndependentDefault`（作者声明 `default:util/white`）救援的**前置 trace**，非失败——graph-execution 证据显示 `17#effect#32`（即带 mask 的 sharpen）自 frame 0 起每帧 `program=5bad29f6… outcome=succeeded gpuCompletion=completed`，`17#effect#38/#234` 同样全 succeeded，publication/compositor 消费正常。该样本无残留断点。诊断改进候选（P3，另批）：该 NSLog 名为 "failure" 但在救援成功时也打印，误导归因，建议改名或补充 disposition 字段。
- P0.4 回写与影响面（2026-09-17 凌晨）：三元修复事件已按 schema 追加至 repair ledger `shader/frag@436c998ccdbec6c2`（state=implemented、commit=uncommitted-working-tree、证据指向 evidence 目录与 fixed 复跑报告）；family 的 corpus 共享集合 = {3290491250, 3767343314, 3789316755}。全 corpus 形状扫描（只读，2242 个 shader 文本，1415 个 `.dxs` 二进制正确排除）：**精确形状（整条件裸字面量）除 3767343314 外为 0**；26 处粗命中全部是合法比较条件（`< 0.5 ?` 等），非本缺口。修复的静态受益集合 = {3767343314}（已恢复）。census 重新 generate+verify passed（payload `7afb971b…`）。
- **全集 identity-only 基线完成（2026-09-17 06:43，单二进制干净重跑，4 路并行 62 分钟）**：159/159 report，0 超时 0 崩溃。verdict 原始值 87 PASS / 72 FAIL；**70 个 FAIL 的主因是显示器锁屏/非活跃**（用户晨间指认并实测证实：屏幕活跃后单样本立即 PASS），窗口遮挡为次要因素——presentation 遥测必须串行采集，身份/route/执行数据不受并行影响。70 个样本已全部串行重扫：67 个转 PASS、`3738202317` 复检亦 PASS（偶发计时边缘）。**最终真实失败 = 2 个样本（P0.4 排序，未修）**：`2959875782`（executor 实际在跑 claimed=33-38/gpuEncoded 正常 + 168 次成功，但 accepted 层的 GPU completion/compositor/next-frame/exact-backend **观测证据缺失**——观测捕获缺口而非引擎失效，下一批 probe=定位该层 completion 观测未捕获的原因）+ `3754630802`（**已修复**：必需目标实测 411,292,672B > 旧预算 397,284,864B，预算公式改 `recommendedMaxWorkingSetSize/16`、顶 1.5GiB——commit `8cb2c343`；复跑 PASS failures=[]、rtPools 462MB、607 帧无预算阻塞）。修复已验证的两批（三元条件、puppet stride-48）在本轮全集中保持恢复状态；benchmark 恢复感知观测门在全集规模工作正常（6 个 mp4 视频瞬态样本全部 PASS）。数据：`/private/tmp/mwx-fullset-baseline/`（final-verdicts.json + run-*/report.json）。
  - **首断点 No.1 已修复（2026-09-17 04:2x 批次，复审通过）**：model-backed（Puppet）image layer 的 layer-source launch 未就绪，字节级根因 = `3767232084` 的 `models/e00207ce…_puppet.mdl`（MDLV0023，13361B，无 MDLS）使用 **48 字节顶点 stride**（offset=106：vb=10752=224×48，索引 1242 个 min=0/max=223 全覆盖、224 顶点全部有限、位置域恰为层声明 1920×1080 之半、UV∈[-0.004,1.005]），而 `SceneMdlPuppetMeshReader` 的 MDLV0023 stride 表只有 [80,84] → 全覆盖检查（maxIdx==vb/stride−1）永不成立 → `meshBlockNotFound` fail closed → 整层永久 previous-current。修复 = stride 表加 48（真实资产证明路径，覆盖检查天然消歧；复审确认对既有 80/84 资产零回归）。**受益集合实测 = {3767232084}（PASS failures=[]，claimed/encoded/gpuEncoded 从全 0 恢复 + 14 次成功图执行）**。曾误判为受益者的 `3743305891` 实际**不含任何 .mdl**，其 layer 23 是 mp4 payload 视频源的 frame-0 瞬态 not-ready（后续帧已恢复、compositor 消费成功），与 stride 修复无关。剩余 FAIL（2959875782、3754630802、3585875739、3747492842、3775355045、3775373546、3780940857）各需单独归因（部分疑为同款 mp4/layer-source 瞬态，部分为真实执行链缺失）。遗留 P3：`test_scene_puppet_mesh.py` 补 stride-48 合成 fixture（已补，20 tests OK）；frame-0 瞬态 not-ready 是否应豁免 observation 门属 benchmark 期待问题，待裁决。
  - benchmark 观测门已恢复感知（2026-09-17 05:3x 批次，复审通过，`scene_wallpaper_graph_output_metrics.py`）：原"任何 layer-local-fallback 诊断 → FAIL"改为按既有合同分类——`layer-source-not-ready` 瞬态若每个引用层都在严格更晚帧取得 next-frame trigger 的 succeeded+compositorConsumed 成功，计为 recovered 数据字段不再失败；未恢复/其他诊断照旧 FAIL（不放松）。验证：3585875739、3743305891（mp4 视频层 frame-0 瞬态）复跑 PASS failures=[]；3754630802（executor 全零、non-black 缺失）仍 FAIL。遗留：新分支入仓单测（复审 P3）。六个视频瞬态样本复跑全部 PASS（见上条最终数字：raw 87/72，其中 70 为并行 presentation 噪声；真实失败 2 个）。
  - `3754630802` 最重（另含 non-black 缺失、utility capture 计数不足、executor reported failures）；`3780119725` actual-present intervals 不可用。
  - 数据：`/private/tmp/mwx-fullset-baseline/`（final-verdicts.json + run-*/report.json + worker logs）；analysis：`/private/tmp/mwx-fullset-summarize.py`。并行经验：4 路并发 Metal 实例 55 分钟跑完全集，但 presentation 遥测仅前台窗口有效——身份/route 数据不受影响，presentation 门必须串行。
- P0.3b 产品路径采集（情报已齐，待选型）：普通链路为 UI 设为壁纸 → SteamWorkshopService.setAsWallpaper → SceneDaemonClient.requestLaunch → daemon 子进程。现有 typed 命令**无截图/证据通道**；`--mwx-debug-scene-evidence-dir` 仅 DEBUG 透传且会切换 floating 证据窗（改变产品行为，验收语义失效）；`MWX LAUNCH-STAGE`/route NSLog 在 Host 公共代码无条件输出（普通路径可用）。最小缺口 = 普通路径截图 + 身份/事件落盘 + 批量编排。方案：(a) UI 自动化驱动真实 App（零产品风险、取证弱）；(b) client/daemon 增加显式可取消 evidence 命令（中大型，须保持"诊断非播放前置"边界）；(c) 拆分 DEBUG 帧捕获与窗口行为解耦开关（中小，依赖 DEBUG 构建）。建议：identity-only 批量先用现有 benchmark 通道（已验证可行）；普通路径截图捕获按 (b) 立项，须独立设计审查。并行跑批经验：4 路并发 Metal 实例 55 分钟完成全集，但 presentation 遥测仅前台窗口有效——身份/route 数据不受影响，视觉/presentation 门必须串行。

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
