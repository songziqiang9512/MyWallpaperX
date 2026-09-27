<!-- document-role: active-plan -->

# Scene 当前断点修复队列

> 2026-09-25 精简重排（用户授权）：只保留开放项与其参考事实；已关闭项的过程流水一律退役，历史证据查 [运行证据](semantics/runtime-evidence-current.md) 与 git log。文件名日期仅保留链接身份。
> 本文是[兼容路线](scene-compatibility-roadmap.md)的短队列，不建立第二套阶段；工程性能工作按[重构计划](engine-refactor-program.md)执行。
> 用户优先级（2026-09-27 最新实测）：优先本页 QV 中仍被点名的音频显示、漩涡、光束、细条纹、粒子位置和交互问题。音频频谱节奏感恢复推进；3088601835 及本轮未提及的旧问题允许搁置，不推定全部修复。最新用户观察与构建关联见[实测登记](semantics/runtime-evidence-current.md#e-2026-09-27-user-retest-priorities)。

## 1. 当前证据边界

样本身份只用于复现，不能进入产品分派。旧 corpus 计数和人工 verdict 不代表当前 HEAD 已重新验证；技术修复不能自动改写人工验收。当前能力查[能力台账](semantics/coverage-ledger.md)，运行身份查[运行证据](semantics/runtime-evidence-current.md)。语料分母 **172**（159 bare-id + 13 v2 布局；后者无身份/归档/矩阵条目，合并条件=全样本当前身份重跑）。

## 2. 现役执行顺序

<a id="qv-visual-repairs"></a>

### QV — 最新实测驱动的可见修复（2026-09-27）

下表区分用户观察、已核实局部修复和待验证原因。按公共首断点推进：先查音频条/音频环的加载与脚本执行，再查共享频谱分布；随后处理漩涡、光束/合成、粒子锚点、细条纹及交互剩余断点。样本只用于取证，不进入产品算法分派。用户正在测试的 App 保持运行，自动诊断使用隔离内容。

| 当前问题 | 首查职责与下一验收门 |
|---|---|
| `3789316755` 音频条不出现 | [动态层预算批](semantics/runtime-evidence-current.md#e-2026-09-27-dynamic-layer-capacity)删除额外owner64限制；[变换局部拒绝批](semantics/runtime-evidence-current.md#e-2026-09-27-transform-nonfinite-local)又将数值NaN/Inf的失败缩到单次变换赋值，原包已在固定PCM下恢复柱条、静音收回且新进程重启再次响应，73动态层连续完成publication/encode/GPU。整owner消失断点有界闭合；末档作者无效采样保留安全旧值，不补假频谱、不改柱数。当前剩余门：普通入口真实音乐和用户复测、同runtime切换；形状/幅度/全柱活跃度并入共享音频视觉项，不能把恢复出现当作整体通过。 |
| `3211615441` 音频环缺失、点击切换中央图片功能、鼠标跟随位置疑似错误 | [连续频带批](semantics/runtime-evidence-current.md#e-2026-09-27-audio-continuous-bands)纠正首查对象：音圈来自689/697的test_shader，六组Simple_Audio_Bars为另一路条形显示。共享频谱已消除永久空档、降低低频专用门，原包固定PCM后段出现细环，前段仍弱；仅部分恢复，不关闭显示达标。下一门为真实音乐强度/完整形态与用户复测；点击由cursorClick改visible，heart由cursorWorldPosition驱动，切图与跟随仍需独立实际执行及坐标证据，不以VM无异常替代。 |
| 跨样本音频柱形状、大小和幅度不佳；中段活跃、两端弱 | 用户明确要求所有柱子都有相近的活跃程度。恢复 Q1.4 音频线；[连续频带批](semantics/runtime-evidence-current.md#e-2026-09-27-audio-continuous-bands)已消除离散分档的永久空档并移除较强低频门，五采样率扫频可激活每档，仍未达到全柱活跃度验收。继续用固定PCM/实际音乐核对剩余幅度、平滑和作者布局，比较最终条形与环形画面。该偏好不是官方行为证明，也不等同把所有柱高强制设为相同；避免无依据叠加 gain/warp 或破坏静音。交付同声源 A/B 后请用户确认活跃度是否达标。 |
| `3788467391` 背景漩涡不旋转，形态/算法可能错误 | 用户确认目标为“明显绕中心持续转动”。[当前构建诊断](semantics/runtime-evidence-current.md#e-2026-09-27-vortex-motion-diagnosis)确认层218的classic vortex与ropetrail已加载并提交，生产模拟器的同粒子位置持续转动；尚未闭合最终画面旋转感。零轴已转+Z，不再重复修加载；作者小尺寸GIF与Mirage切向符号差异不足以直接改方向或增大速度。下一门：当前App人工复测，并沿轨迹历史、贴图采样和最终像素核对运动呈现。关闭仍需中心、方向、速度和形态依据，不能用整张背景旋转掩盖缺失算法。 |
| `1315486372`、`3769761761`、`3768724269` 光效仍不完整；`3768724269` 右上固定区域有不断变化的暗红蓝渐变 | 粒子贴图光束与 shader 光束分别追踪。既有预热、TEX 长宽比、三轴旋转和径向锚点局部修复不等于完整光效；1315486372 顶部光线和中部渐隐渐显都必须保留，size 单位/旧 scalar 角度仍待区分。3768724269 的独立 quad100 终端误用普通图片 source-over，已改为现有 additive 混合；原包新画面右上恢复亮色放射束，故障启动与三种光束执行回归通过，见[独立光束合成修复](semantics/runtime-evidence-current.md#e-2026-09-27-direct-draw-additive)。用户在本批最新 App 复测确认“暗色异常已改善，光束仍需调整”；作者 iridescent 渐变仍保留；后续用户明确指出“光束被拉伸，形状不自然”，[等边载体批](semantics/runtime-evidence-current.md#e-2026-09-27-direct-draw-square)已移除half-canvas和顶部补偿；用户最新复测确认“拉伸改善，但尺寸或位置仍不对”，随后明确“光束范围过大或根部太靠画面内部”；又报告鼠标/镜头晃动时背景人物移动而光源像固定，需要按作者定义核对独立层与深度视差。作者背景17含depthparallax，quad100声明视差0.88、粒子54声明0.79，不能未经核对将光束强行绑定背景纹理变形。[视差隔离证据](semantics/runtime-evidence-current.md#e-2026-09-27-light-parallax-diagnosis)证明quad100按0.88深度随鼠标平移，零depth负例像素不动；作者两个相机开关标签与实际绑定交叉，Mirage的quad解析另有漏传depth，均不能作为统一粘连背景的依据。后续发现背景shader视差遗漏mouse influence且纵轴误用普通pointer编码，[共享输入修正](semantics/runtime-evidence-current.md#e-2026-09-27-parallax-shader-input)已按同帧相机值和Y-up归一化，隔离四方向实际输出与目标坐标对照逐像素一致；仍待用户确认整体脱层感。[四点覆盖GPU探针](semantics/runtime-evidence-current.md#e-2026-09-27-direct-quad-coverage-probe)显示该点集的方形/四点裁剪只有少量边缘差异，尚不足以解释明显范围偏差；降低单纯重建网格的优先级。下一门核对作者变换与实际uniform、载体原点和particle54；旧scalar角度轴仍未裁定，不能关闭整项。参考[亮根诊断](semantics/runtime-evidence-current.md#e-2026-09-27-lightshaft-root)、[同状态几何消融](semantics/runtime-evidence-current.md#e-2026-09-27-lightshaft-geometry-ablation)和[锚点修复](semantics/runtime-evidence-current.md#e-2026-09-27-radial-carrier-anchor)。关闭门：完整光束范围、根部轮廓、渐变和该右上区域连续画面符合预期。 |
| `3287715210` 眼周发光过强、渐隐渐现缺失或不明显 | 用户在等边载体候选复测并提供截图：右眼白粉色放射光过强，播放时渐隐渐现不明显。截图只支持亮部集中，时序按用户实测记录。已发现终端只累加RGB、未按源alpha衰减，与参考SRC_ALPHA/ONE不同；现役同一prepared fragment补回源coverage，再应用一次图层透明度。透明/半透明GPU反例与普通图片回归见[源coverage修正](semantics/runtime-evidence-current.md#e-2026-09-27-direct-draw-coverage)。没有压暗系数、替换噪声或改变作者speed。下一门：用户原样本复测亮部和渐隐渐现，未复测前保持OPEN；不把carrier比例或执行通过当视觉验收。 |
| `3287715210` 全屏极淡的竖向条纹从左向右移动 | 用户明确范围为全屏，并实测把“渐变循环”调为0后“停止移动或明显改善”。[渐变隔离证据](semantics/runtime-evidence-current.md#e-2026-09-27-gradient-stripe-isolation)：关闭Bloom、去掉眼周光束与风粒子后，仅背景gradient_color仍产生全高竖向时间变化；去掉该效果后背景带状差分基本消失，仅保留该效果且速度0时四张连续输出逐像素相同。此前生产Bloom零贡献GPU门及近期Bloom提交只能作排查背景，不再优先重复Bloom消融。后续固定4/6/8秒的作者fragment GPU探针证明：16F中间贴图降低中间舍入误差，但最终RGBA8输出重新产生列阶梯，不能仅换中间格式。[颜色精度批](semantics/runtime-evidence-current.md#e-2026-09-27-scene-color-precision)已沿唯一target/pipeline/publication到CAMetalLayer恢复作者HDR的RGBA16F，显式data/scalar格式保持；原包与隔离渐变执行PASS，终端16位读回实际保留超过256级颜色。下一门：最新App在渐变循环恢复原值后人工复测全屏移动细条纹，区分剩余作者纹理、输出精度与系统呈现；保留作者渐变，不用关闭效果或任意补偿作修复。尚无物理屏幕/官方对照，仍OPEN。 |
| `3113287126` 红色粒子位置错误 | [旧版附着点批](semantics/runtime-evidence-current.md#e-2026-09-27-puppet-legacy-attachments)已修正MDLV0017被attachment reader拒绝的问题，恢复parent500的三个作者锚点；原包12秒前后对照中红橙粒子由裙摆/腿部附近回到小提琴与持弓手区域。明显位移首断点已修正，保留用户复测具体发散形态与锚定效果；鼠标/视差变体、长稳与完整粒子组件未验收。 |

**本轮可搁置：**

| 问题 | 当前处理与保留边界 |
|---|---|
| `3088601835` 雪雾过曝 | 用户最新实测认为已较为正常，并指出官方原版也有一定过曝；降为可搁置，不再优先追查亮度，也不登记为受控官方 parity。保留[子系统参数修复](semantics/runtime-evidence-current.md#e-2026-09-27-child-instance-modifiers)、[退场实验](semantics/runtime-evidence-current.md#e-2026-09-27-snow-fog-retirement)与[目标 alpha 排除](semantics/runtime-evidence-current.md#e-2026-09-27-snow-fog-target-alpha)证据。 |
| 本轮未提及的旧问题 | 按用户明确指示视为非严重或部分解决，可搁置：包括 `3028090166` 光束、`2419444134` 白点、`3113554287` 顿挫、`2304304373` 雾气、烟花/洋红与一般拖尾样式。既有局部修复及未关闭边界留在[运行证据](semantics/runtime-evidence-current.md)，不以本次沉默生成 pass。下方旧 Q1/Q0/Q3 等作为存量余项，除非阻塞本表公共修复或用户重新点名，不抢占本表。 |

实现允许在完整职责范围内简化或重写；优先删除重复状态推导、绕行适配与无收益补偿，不能为每个样本再套一层专用分支。需要用户视觉判断时先准备能直接测试的构建/对照和具体问题，再询问效果是否达标。

### Q1 — 鼠标/指针交互簇（保留既有闭合与挂起边界）

**Q1-A 粒子控制点鼠标跟随缺失（2026-09-25 已修复，待用户实机验收）**

- 症状：`3792817546` 作者心形应跟随鼠标、`3790726145` 应有鼠标拖尾，均不动；同类"鼠标跟随"效果广泛缺失（census：CP0 `flags=1` 形态 **26 定义/14 样本**）。
- 取证事实（2026-09-25，全部已核实）：
  - 两样本粒子定义均声明 `controlpoint[0] flags=1` 且**无任何组件显式引用控制点**：心形 = `controlpointattract` **省略 `controlpoint` 字段**（官方默认 CP0）+ sphererandom 发射；拖尾 = `rope` 渲染器（默认 subdivision，不撞预算门）+ 原点发射。
  - 引擎 `SceneParticleControlPointForce.hasBoundedPointerInput` 守卫 `(1...7).contains(id)` **显式排除 CP0**；parser 对省略 `controlpoint` 无默认 0；`emitterPointerControlPointIdentities` 要求显式 `emitter.controlPoint`。
  - 官方文档示例用 CP1+ Lock-to-pointer（source-index 2026-08-01 复核），但官方 patch note 证实控制点可 "follow the cursor"，且用户实机观察证实 CP0-flags-1 样本在官方客户端跟随鼠标——旧 census "CP0 按合同无效" 结论被推翻。
- 根因定性：官方语义 = **CP0 `flags` bit0 时系统原点跟随鼠标**（发射与默认 CP 消费随动）；引擎设计把 CP0 固定为原点、指针输入只给 CP1+。
- 修复方向：①`hasBoundedPointerInput` 放行 id 0（其余约束不变）；②operator/initializer/emitter 省略 `controlpoint` 时默认 0；③CP0 指针输入驱动系统原点（含 attract 消费与发射）。
- 已实施（2026-09-25）：三处编辑（两谓词 `(1...7)`→`(0...7)`；emitter 省略源默认指针驱动 CP0，范围与 demand 收集的 sphere/box 锁定；identities 同步默认）。**影响面复核口径：28 定义/15 样本**（复扫 172 语料根，旧 census 26/14 已过期）。positionAround 路径经既有 `controlPoint ?? 0` 默认同批扩展（无样本实证，登记）。
- 验证：心形/拖尾受控指针回放视觉确认跟随；15 影响样本全复跑（10+1 遥测抖动 PASS + 3363252053 PASS + sentinel `3238423642` 四点轨迹夹具 PASS failures=[]）；`test_scene_particle_simulator` 55 用例（两处旧语义断言已迁移）+ particle_runtime/boids/refraction 全绿；独立审查 P1/P2 已闭环（测试迁移、覆盖声明更正、positionAround 登记）。
- 余量：用户实机鼠标验收；Q1-B（同批样本的镜头问题）另修。

**Q1-B 镜头视差幅度过大 + 垂直方向反转（未解决挂起，用户裁决 2026-09-25）**

- 症状：`3750813609`、`3363252053` 鼠标移动时内景晃动幅度过大；上下移动鼠标时镜头变化方向与鼠标相反。
- 状态：三轮修复（常量项移除→Mirage 完整移植→垂直轴符号+收敛语义）均未通过用户实机验收；用户裁决挂起，后续有机会再解决。已验证的子缺陷修复保留在提交链中，但整体问题按未解决登记。
- 取证事实（插桩实测，2026-09-25）：
  - `3750813609`：ortho 3840×2160、amount=0.1、mouseinfluence=0.15、delay=2.0，层 parallaxDepth 为 **-2/-1/0（负深度为主）**；`3363252053` 类似且 parallax 属性门控。运行时插桩确认 amount/influence/ortho/depth 逐值与作者数据一致，公式量级正确（全程 ~50px@3024 屏）。
  - 已修子缺陷①（方向，591cf1d8 移植丢鼠标空间转换）：平滑指针为 y-up NDC、世界为 y-down，垂直轴反向、水平跟随 → 斜向剪切。修复 = 指针项 `(−NDC.x, +NDC.y)×halfSize×influence`，与 Mirage `Scaling(1,-1)×(0.5−m)×ortho×inf` 在两侧相反的轴约定下代数恒等（Mirage：GLFW y-down 鼠标入 y-up 世界；本仓：AppKit y-up NDC 入 y-down 世界）。
  - 已修子缺陷②（动态）：桌面宿主每帧轮询鼠标位置调 `setTarget`，未变化轮询重置延迟累加 → 永不收敛。修复 = setTarget 对未变化值早退（事件语义；早退不更新 lastInputTimestamp，避免静止后下次移动瞬跳）。
  - 余留疑点：用户实测仍判无效，说明官方行为的判定输入不止这两个子缺陷（候选：常量项 layout 感知、多显示器 NDC、脚本驱动相机交互、样本差异——未验证）。
- 验证记录：指针 down/up 受控 A/B——高分稳定块 18/15 个 dy=+25px（跟随鼠标下移）；fixed13 与基线零新增；layer_parallax/camera_shake 测试绿。
- 重启条件：后续有官方同输入对照（P4）或用户愿意再验收时，从"余留疑点"清单继续。`g_ParallaxPosition` shader uniform 缺 0.5 中心化+influence 缩放——全语料零消费，随本项延后。

**Q1-C 点击/拖动已闭合项的余量**：真实 AppKit 鼠标录屏验收、多步连续 move、compositor 窗口切片（仪器=from-launch 开关+命中盒探针；退役条件=Q1-C 收口）。**Q1-D previous-pointer 作者效果**：连续轨迹批已修正 current-only；previous 侧作者效果未验收。点击拖放本身用户已确认正确（2026-09-25）。

### Q0 — 兼容路线 P0 尾项

- SteamKit 安装身份：等用户安装签名 2.0.9 (277) 候选后冻结 bundle identity，再跑真实 QR/授权下载/三引擎播放门（用户动作）。
- 13 个 v2 布局样本：11 PASS / 2 FAIL——`2849382252`（效果首断点已修，见 Q3 crt_scan_line 落地）、`3357627941`（层 55 见 Q3）。
- `2959875782` X-Ray：跨层 813 提供链已修复落地（outfit=4 验证门全过）。①同层 effectOutput 引用排除——**2026-09-25 收口（被超越）**：语料扫描定族=9 样本 21 处同层 composite 引用（`_a` 17 / `_b` 4；1937925563×13、2241938645/2269193950/2304304373/2815826216/2824109832/2849382252/3448845950/3792249095 各 1）；当年登记的"排除"窄方案已被 crt 批（536d8b80）的完整 graphInternal 编译超越（ownership 同层双变体认领 + 执行器双变体 overlay 发布），`dependencyEdges` 亦早已跳过同层边；9 样本全回放零依赖拒绝（overlay 活跃样本 1937925563=2353 帧/3448845950=175/3792249095=486，其余四样本同层引用走非 graphInternal 既有路由同样零失败）。剩余：②`.resolvedMaterial` 隐藏提供者 extent 分支的 Python 桩覆盖（审查 P2-1）。
- benchmark 时间门控层误报（`2959875782` 层 1654 墙钟门控）——**已核实为过期项（2026-09-26）收口**：2959875782 不在当前 full matrix（45 样本集验证 `2959875782 in ids == False`）也不在 fixed13；该门控期望随矩阵演进退役（仅存 scene_sample_debug_archive 历史报告引用）。若样本回归被跟踪矩阵，需按 oracle 登记或 next-frame 窗口语义重建设计再开门。

### Q3 — 效果/依赖能力缺口

- `crt_scan_line` 同层合成引用 `_rt_imageLayerComposite_<id>_{a,b}`（`2849382252` 层 205，效果整体 passthrough）——**2026-09-25 三切片已落地并过验证门**：
  落地形态（与侦察设计差异：b 引用实际以**模板 provider candidate**（authored pass textures）进入，非 sampler 默认纹理；拒绝链比设计多两环——conservation 分析的 primary-only 守卫与 named-target 预留的 primary-only 守卫）：
  ①ownership：同层分支接受 secondary，但仅限引用槽位无图绑定的合成形态（`previous` 绑定遮蔽形态保持原 fail-soft 合同，executor 测试场景守卫）；
  ②分类：`graphInputSourceSlotFacts` 新增 `sameLayerCompositeDefault` provenance（认模板同层合成 candidate 与 sampler 默认两种形态）；`variantRole` 三处守卫按该形态放宽（facts 循环 defaultTexture、sourceSampler defaultTexture、else 分支 bindings 从 isEmpty 放宽为不占 sourceSlot + 模板槽位允许纯同层合成 candidate）；conservation 分析 `resolvedExternalDependencies` 放行同层 secondary（跨层 secondary 保持 invalid）；
  ③运行时：执行器 graphInternal overlay 同时发布 primary+secondary（基准=pair base capture）；`reservedNamedLayerTarget` 带 `consumerLayerID` 放行同层 secondary（`isCompleteNamedLayerTarget` 相应接受两变体；registry 跨层发布路径保持 primary-only）；`TextureSelection` internalTarget 非场景背景默认对同层合成改走 named target 解析。
  验证（2026-09-25）：2849382252 能力拒绝链全通、self-composite overlay 481 帧零 resource-invalid、噪声分量可见渲染（作者 Scan Line Intensity=0，扫描线本身 authored 关闭）；2815826216 同形态 476 帧 ✓；fixed13 与基线逐样本零差异；graph_executor/fbo_stage_activation/execution_capability 测试绿（含跨层 secondary 拒绝与 previous 遮蔽形态回归场景）。
  余量：全语料其他 `_b` 引用形态样本的可见收益盘点（当前仅上述两实例登记）。
- `sine_wave_circle` varyingUnsupported = 作者内容限制（激活变体下读未初始化分量）；恢复需先决定"未定义分量语义"（零填充 vs 未定义），属官方对照语义决定，不得猜测放宽。
- `3357627941` 层 55 可见性脚本 `invalidSource`——**2026-09-25 已修复**。根因不是 cursor 守卫（守卫合同正确）而是路由：composelayer 的脚本可见性被 `visibilityProjection` 的 `utilityLayer == nil` 排除 + contentKind 白名单缺 "composition" → 绑定孤儿化到 cursor 独立候选 → 帧求值脚本被无帧合同拒绝 → 可见性永驻 authored。修复 = 收编无依赖 composelayer（`admitsUtilityLayerVisibility`：kind composition 且 deps/authoredDeps 均空；带依赖 composition、project、fullscreen 维持排除，与 utility 消费者判定可证不相交）到向量 lane，cursor 导出走既有借用通道（claimedCursorTargets 扣除链）。验证：层 55 source=authored→sceneScript、cursor-normalized-bounds 借用接管、cursor 零失败；语料同形态 4 样本（2974757317/3264246690/3448845950）回放全过；fixed13 passed+失败清单零差异；6 测试文件绿（collision 期望按新路由迁移 5→7 + mixed-standalone 形态从 invalid-source 改为 vector+borrowed；两 harness 桩 utilityLayer 升级）；终审五项 PASS。余量：纯事件脚本执行模型从独立 cursor lane 移至向量+借用（行为等价、机制由 collision 测试覆盖）；`SceneDependencyRenderPlan+BindingCompilation.swift:520` 预存 DEBUG NSLog（XG1）待后续清理。
- `2938612768` execution contract not satisfied + passthrough 激活证据缺失——**2026-09-25 矩阵对账收尾，样本回绿**。取证定性（见前批）：执行健康（executor 22/22 零失败、层 1513 缺口已消），失败全为期望漂移五族。本批落地：①checker 的激活直通 program_identity 判定从单一硬编码（initially-inactive-property-stage-passthrough）对齐产品白名单五理由集（D2b'' 50672fda 引入 script-gated-dependency-preproof-mismatch）；②full matrix 条目对账（utility 9/6/9/0、succeeded 22 层、effect_graph 60/90/90+sha、text binding 0/五层）；③wrapper remove 补 13 个退役计数器键 + base_matrix_sha256 同步。验证：单样本 passed True；观察模式 fixed13 全跑——2938612768 False→True，其余 12 样本 passed 标志与基线逐一致（8 个仍失败为 79719606 已登记存量漂移族，非回归）。**门教训**：矩阵对比必须比 passed 标志与失败清单，不能只比 outcome 字段（恒 None）；且对照运行必须同观察模式（no-obs 会灭证据族）。

### Q4 — 登记边界/暂缓

- **3750813609 时钟文字黑白混合（用户报告 2026-09-26）——保持视觉待验收**：历史隔离 A/B 禁用 clouds 后时钟亮像素 41%→0%，说明亮色来自该特效；此前把 authored pass `bindings=[]` 等同运行时缺纹理的归因不充分，shader 默认纹理还经 metadata/resource demand 进入唯一资产链。当前签名 Debug App 的真实回放确认材质资产 `6 ready / 0 absent`、stock 合成 `prepared=0`，包内已含 clouds_256，不能把程序化噪声修复当作时钟视觉修复。通用资源缺口已推进：`33d4e7df` 引入的六种 stock 替代，其随机半量程与 mipmap 失败仍发布已修正，后继又改为 launch 按需不可变准备，移除逐帧生成/失败重试，修正 media-only provider block 覆盖准备态，并补齐 launch/readiness/format/color 与帧内选择不一致导致的默认纹理准入缺口。见[当前能力](semantics/coverage-ledger.md#2026-09-26-stock-noise-按需启动准备与上传完成s3)及[对应运行证据](semantics/runtime-evidence-current.md#e-2026-09-26-stock-noise-preparation)。**剩余**：真实时钟 ROI 与作者预期的画面复核；缺失资产时合成 noise 与官方 stock 的密度/语义等价仍未证明。
- `2986218263` rope trail：三处放宽全部 A/B 证据回退（flag bit0 造成 `3665307769` 红烟回归；预算放宽可见收益为零）。前置=世界空间 rope 支持设计（登记 Ⅰ/Ⅱ/Ⅲ 假设）；rope 批须同批补"粒子加载完整性"PASS 门（0/1 仍 PASS 的测量缺口）。
- `3662790108` 动态 point 光：**2026-09-26 当前事实已刷新，视觉仍未闭合**。旧 4096/4096 耗尽在本批修前基线已不再复现；本批修复三条仅注释 String module 的误拒绝，构造失败 3→0、teardown owner 920→923，避免其触发 fresh-domain 重建。23 个 graph layer 合同继续通过，但修前/修后截图都仍为低亮说明画面，尚无 point 光/天体 ROI 正证。当前帧仍见 visibility 859/860 bad-return、alpha 1459 properties unavailable。见[当前运行证据](semantics/runtime-evidence-current.md#e-2026-09-26-string-module-admission)。
- **event-only Boolean audio owner 准入回归：2026-09-26 已修复**。合法事件 owner 沿 vector+borrowed 保留唯一音频 demand，并在 init/property/media callback 前刷新当前 generation；无事件继续休眠。cursor/property/media 的真实 Swift/C 行为门通过，隔离 App PCM 点击位移 615.5 px、静音对照 0 px、离开复位；静音通用 benchmark 的位移不足 FAIL 原样保留，仅独立负例 ROI 门通过。详见[对应运行证据](semantics/runtime-evidence-current.md#e-2026-09-26-event-audio-admission)，不外推真实内容、graph publication 或性能。
- **初始化事务卡：继续开放，String init-only 仍拒绝**。2026-09-26 已统一 C pending/committed 初始化状态、移除 Scalar/Vector Swift 副本、保留被拒消费的已提交 cursor 值，并让 init timer 基线随 owner 撤销；六类 BAD_RETURN 可重试，Host 整帧 timer snapshot 补释放。9 组 Owner API 反例及正常 App init→timer 可见链通过，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-26-initialization-transaction)。2026-09-27 又闭合 target 事件确认：Scalar/String/Vector 的四类媒体 generation 与属性值/revision 在后置拒绝时局部恢复；cursor 先成功而 update 后失败的整 owner 效果也会被排除。隔离签名 App 的属性冲突证明 Host owner 拒绝→重试→可见提交，已接受 peer 不重放，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-owner-event-transaction)。2026-09-27 localStorage 后继又闭合现有 session 内的有序 owner 批次撤回、同帧读取依赖传递和 quota 重验；真实 Host 持续 layer 冲突中，失败写者/只读消费者的值与存储不发布，独立 peer 显示并保存，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-storage-owner-transaction)。同日 cursor 后继以现有 Program 的有界 target 事件记录闭合 single-surface 局部拒绝后的完整 click 重试，已接受 peer 不重复，整帧 snapshot 与原 pointer batch 恢复不重份，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-cursor-owner-transaction)。shared 后继撤除每帧全图序列化及替换根的伪回滚，函数/对象身份沿真实 JS heap 保留；typed 拒绝仍可保留 heap 写入，读取者没有 localStorage 式依赖撤回，重试可重复非事务副作用。这是明确产品失败边界，不是 shared 回滚完成，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-shared-identity)。同日修复 Vec3 非法临时字符串诊断的释放后读取：7 项 ASan 门与真实 App BAD_RETURN→恢复/独立 peer 可见链通过，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-return-diagnostic)。timer 后继修复 snapshot 回退身份计数导致的旧取消闭包误删新任务；7 项 VM 门与签名 App 同输入 A/B 证明 init 撤回后新 timer 正常触发，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-timer-identity)。后继已通过 single-surface 实际提交前拒帧：自有双 pass/FBO graph 在 frame 0/1 拒绝后，init/property 或 timer 重跑，typed seed 与 storage 保持事务边界，同帧及下一帧 GPU 完成、最终 ROI 有正证，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-frame-rejection)。多 surface 后继已把所有编码封口放到提交前屏障，并以单调 completion 注册代次隔离旧取消结果；同物理屏两个独立 surface 的 init/timer 拒帧与重试通过专项门，真实双屏呈现不作通过结论，见[对应证据](semantics/runtime-evidence-current.md#e-2026-09-27-multisurface-submission)。**下一门**：多 surface cursor 的完整边沿（现路径仍 latest-only），以及其他事件/资源家族与异步 GPU 失败的事务集成、真实多显示器呈现；String init-only 需另行验证完整初始化合同。不以本批局部状态修复宣称整张卡闭合。
- 音频频谱节奏感（Q1.4x 线）：**用户 2026-09-27 最新实测恢复推进**，具体缺失、形状/幅度与全柱活跃度验收统一见 QV；沿用固定 PCM+时间轴 A/B，不以旧 Q1.4y 候选的审查代替当前画面验收。
- 一般鼠标拖尾/流星样式按最新反馈可搁置；本轮明确点名的 `3211615441` 跟随位置仍在 QV 推进。
- `3747492842` 额外闪烁：需固定 phase 动态对照。

### Q1T — 作者参数、视觉验收与 tracked matrix

| 尚未关闭的问题 | 下一步与关闭条件 |
|---|---|
| Scene Bloom enable/threshold 无完整 live consumer（**取证升级 2026-09-26**：语料 172/172 全部 author bloom 键（编辑器默认写入，bloom:true 未必代表视觉显著）；仓库侧仅有 SceneDynamicSceneField 枚举脚手架——authored 键解析、属性通道、post consumer 三段全缺。Mirage 参考有完整实现锚点：`__bloom` post-process（SceneCompiler.cpp:6880-6967，`pp->enabled = g.bloom` 门控，_rt_bloom_mip1/mip2/combine 三目标，HDR 分支 mip 尺寸不同，effect cam 上保留 alpha）。实现=E3 性质的全场 post pass（bright-pass+模糊+合成），需独立设计批） | **已实现（2026-09-26，用户裁决：完整 Bloom 参考 Mirage）**：authored 键解析（general bloom/bloomstrength/bloomthreshold/bloomtint → CameraDescriptor.bloom）+ LDR 四 pass 链（亮部提取 4-tap×0.25 平均+阈值+饱和增强 / 13-tap 高斯 V / 13-tap 高斯 H（8-texel 步距，参考权重）/ 加性合成）+ blit 回写 drawable——挂点在 finishEnsuringClear 后、readback 前（证据观察 bloomed 帧）；管线与中间纹理按尺寸缓存、fail-soft 合同。**登记**：HDR 分支（19/172 样本 hdr=true）未实现——本引擎合成链为 LDR，HDR 专属 scatter/knee/上采样栈按需要另批；用户属性热调（bloomstrength/bloomtint 绑定）未接（无脚本消费语料证据）。验证：3750813609 A/B p99 亮度 158→171（bloom 生效）；fixed13 观察模式 13/13 全绿（全部样本 bloom 激活下零回归）；结构门三绿。 |
| 全 corpus identity-only matrix 与人工视觉复核 | **fixed13 已于 2026-09-25 全绿（13/13，观察模式）**：存量 8 样本漂移完成对账（succeeded/utility/text/sha/puppet 数值随能力演进更新；2902406982 层 410/414 处置从 unsupportedEffects 迁移为 capture=能力成长；puppet checker 正则跟上 cbd126d3 的 "puppet world geometry OK" 改名，数据与原期望完全吻合零矩阵改动；8 样本计数器按 retire 全有或全无合同全量退役）。矩阵期望漂移仍用 `generate_scene_full_matrix.py` 正规流程（fixed13 sha pin 已同步）；人工重看后才改 verdict |

### Q2 — 稳定帧性能

性能批次排在真实样本画面正确性之后（用户 2026-09-25 重申）。现役热点地图与已修项见 git（`e5b38f32` 池去重 -2.5ms/帧）；剩余增量项均 <2ms/项，下一杠杆=跨帧 program/derivation 复用（架构级，需专项设计批）。维持作者分辨率与正确构图，不以缩小纹理换帧率。

## 3. 观察项与能力边界

异步 provider 的短暂 not-ready 按局部 previous-current 恢复；持续不恢复才登记缺口。Puppet 跨层 geometry provider、IK、完整 3D 按专项合同拉入。操作纪律：presentation 遥测单实例串行+前台+caffeinate；新 Swift 文件同步测试源清单与 `scene_swift_source_sets.json`；新 python compile+run 测试走 evidence 手动门（Mimosa hook）。

## 4. B1–B9 退役索引

已完成批次的证据按需从[历史索引](../history/README.md)追溯。本表不复制 PASS 数、旧命令或退役 owner 清单。

## 5. 队列维护与批次门

每项只保留问题、根因、下一步和关闭门；完成后从表中移除，证据写回唯一台账。落码遵守[开发工作流](development/development-workflow.md)，一次闭合一个完整职责并完成相称验证；提交仍需用户授权。当公共首断点关闭、仅剩路线系统性验收时，将本文归档。
