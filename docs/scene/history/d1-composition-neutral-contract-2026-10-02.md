<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

> **历史证据 — 非现役入口**。当前权威：[D1 设计](../roadmap/batch2/composition-render-target-design.md)、[实施路线](../roadmap/scene-compatibility-roadmap.md)、[资料来源索引](../development/source-index.md)。本记录保存隔离研究者交付、根审查接受的中性报告，不是官方视觉验收，也不独立批准产品实施。原交接SHA256：`7c060ec95b809e7b27b5e5a8067afc40635970e950c4a552e5035c81f9d80514`；落库仅补文档角色与相对导航，保留证据边界。

# D1 composition：中性行为合同与下一片

研究日期：2026-10-02。研究者 `/root/d1_reference_contract`，产品写权限为 false。唯一交付为本报告与同目录研究卡；未修改仓库产品、测试、文档、索引，未构建、运行 Mirage/VM/GPU、暂存或提交。本文不包含源码、伪代码、私有 shader/资产/payload、地址、公式或算法常量。

## 可操作结论

1. **D1 下一片优先闭合真实 source identity、工作空间与目标生命周期**：preparation与encode消费同一source版本，camera/extent与allocation分别保持身份，并用自有输出/残影/resize反例走到publication、terminal compositor和next-frame。composition类型、作者ordinal、parent引用，以及 `copybackground` 省略/false/true和resolved passthrough来源保真只作配套。不能先把省略折成false，再由child数量推模式；不能把纯字段存储充作可见能力。实施仍需按D1设计门批准这一窄profile，不选择未定的成员视觉语义。
2. 固定 Mirage 新核对发现：composition 的 `copybackground` **省略与显式 false 在解析阶段不同**，虽然两者的普通布尔状态相同。显式 false 另改变 base-material variant；省略和 true 不触发这个 presence 分支。未读 stock material/shader，因此不能把该区别翻译成已证的最终 alpha/RGB 公式。
3. 固定 Mirage 能证明作者顺序、parent tree、单层 effect 目标/camera、读写版本与 first-clear/preserve 的职责链；**它不能证明 D1 已执行 parent 后代私有采集**。composition 确实登记了 group camera，但本轮 exact consumer 查找没有发现读方；实际 planner 按父节点、再按 child 列表顺序处理节点，各节点走普通最终输出或已识别 linked-source 输出。登记本身不能升级为可见 group 能力。
4. 因此，`composition + parent` **可以成为一种待检验的作者模式组合**，无需强求新字段；但此 revision 的登记和树结构尚未证明该组合定义隔离采集。`copybackground`/passthrough 也不能被默认解释成成员开关。
5. 官方公开 RGB 说明只已知 composition 能捕获其下方层用于 RGB 输出；普通壁纸可见合成、parent 组合、三个 copybackground 输入和 passthrough 的区别仍需有界正控制实验。它们不阻止项目独立实现输入保真、source identity、工作空间和资源生命周期。

## 身份、来源类别与证据定位

所有仓库文档路径相对 `/Users/songziqiang/Documents/Development/MyWallpaperX`。本轮起始 HEAD `03ba383c1029d85b84a6ac65aa8b167f27e01317`；存在并行改动，不把 live HEAD 当作其他 lane 的冻结身份。

| 证据 | 身份及定位 | 可证明的范围 |
|---|---|---|
| 官方公开 | [RGB Hardware Support](https://docs.wallpaperengine.io/en/scene/rgb/introduction.html#extra-notes-on-composition-layers)，2026-10-02 直接读取；同一事实在 `docs/scene/design/composition-render-target-design.md:16`、`docs/scene/semantics/advanced-object-coverage.md:248-250` | RGB context 的下方层采集方向。此次 live 页面无固定 source revision；`source-index.md:38` 登记的官方文档 revision 不冒充本次已重新核实。 |
| 官方静态研究 | `docs/scene/semantics/client-runtime-static-forensics.md:11-17,164-171,175-180,208-217,229-242`；Wallpaper Engine 2.8.42/build23967692；64位主程序 SHA256 `40e2ce021e9352324fadb3b8f72b8ba2a7ee95b71cc571d5b9f84be75cd993b0`，32位 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`（该文:58-59） | effect pass 的 `compose` 与 layer 自身内容、effect handoff、正常最终输出职责。不是 utility composition + parent 的成员合同；没有本轮动态 golden。 |
| 第三方基础报告 | `docs/scene/semantics/miragewallpaper-rendering-reference.md:187-248`；这些原段固定 revision **`8893b25b3fb4abdd63d72e9fe31bdd59e765208a`**（该文:7,31） | 顺序、working space、graph version、clear/preserve 的基础静态结构。不得整体改署 da4fa7b3。 |
| 第三方增量报告 | `docs/history/scene/mirage-da4fa7b3-six-domain-forensics-verdict-2026-10-01.md:7,15,23,25-30`，固定 **`da4fa7b3ee33e9e94c59307f47098aa521f21aa6`** | render-2 明确同名 composition buffer 是我方 fixture，不能当官方互证；render-4 支持 linked source；render-7/8 的实现细节不收编。 |
| 本轮第三方有界核对 | 以下 `M-*` 全部通过 `git show` 读取 **da4fa7b3ee33e9e94c59307f47098aa521f21aa6**；未 checkout/fetch/build/run | 字段、模式状态、graph 顺序和目标生命周期的静态事实，非官方 parity。 |

Mirage 源码引用根是 `Reference Project/MirageWallpaper/SceneRenderer/Sources/SceneRenderer/`，仅作研究审计定位，实现者不需要打开这些文件：

| ID | 固定 revision 文件与行号 | 中性事实 |
|---|---|---|
| M-input | `Wallpaper/Schema/ImageLayerSpec.cpp:274-287,300-308,323-341,360-371`；声明 `Wallpaper/Schema/ImageLayerSpec.cppm:74-76,92-114` | 由 image 引用识别 composition；资源描述给出部分模式/extent，实例 config 可覆盖 passthrough；保留 parent；copybackground presence 对 composition 的 material preparation 有区别。 |
| M-order | `Wallpaper/Compiler/SceneCompiler.cpp:3684-3690,6087-6109,6143-6156,6422-6453`；`Domain/Scene/World.cppm:1229-1235` | parent identity 与作者声明 ordinal 分别保留；同一 parent 的 child 列表按声明顺序建立。 |
| M-group | `Wallpaper/Compiler/SceneCompiler.cpp:3277-3285`；`Domain/Scene/World.cppm:2970-2977` | composition 建立附着自身节点的 group camera 登记。对 `RenderGroupCamera`/`RegisterRenderGroup` 的固定 revision exact 符号查找只有定义和登记调用；无读方。不能单凭结构认定已执行隔离采集。 |
| M-plan | `Gpu/Pipeline/SceneRenderPlanner.cpp:35-40,247-313,349-390,528-566` | 正常树遍历先处理父再处理子；读取材质的实际 slot；effect 自身 source/中间/final 分开。非消除节点走正常最终目标，已识别 linked source 可走私有依赖目标。没有由 composition 的 parent 后代列表选择 group output 的已核实分支。 |
| M-space | `Wallpaper/Compiler/SceneCompiler.cpp:1328-1334,3255-3285,3292-3328` | fullscreen 的工作 extent 跟随 active camera；其他目标使用对象工作 extent。passthrough camera 可跟随 active camera，不能由此假设目标也全等于 screen；composition group camera 用其工作 extent 并附着该节点。 |
| M-clear | `Wallpaper/Compiler/SceneCompiler.cpp:3311-3328`；`Gpu/Pipeline/SceneRenderPlanner.cpp:398-425`；`Gpu/Pipeline/MaterialPass.cpp:363-372,528-535,737-752` | 私有目标第一次写透明清除；需要 preserve 的后续图版本可以保留本图已有颜色，不能把 preserve 解释成无条件跨帧 history。preserve 还会影响 force-clear 的有效性，不能只照 flag 名称独立决定 load。 |
| M-final | `Domain/Scene/LayerEffectStack.cpp:111-160`；`Wallpaper/Compiler/SceneCompiler.cpp:2799-2839,3594-3651` | 当前启用 effect 依次传递输出；最终输出恢复该层 geometry/camera/render state/alpha 来源。composition 可在没有作者 effect 时准备中性 resolve；copybackground 状态参与 final resolve 准备，但最终颜色/alpha仍依赖未读材质。 |
| M-extent | `Domain/Scene/World.cppm:178-206`；`Gpu/Pipeline/VulkanFrameEngine.cpp:313-355` | logical extent 与设备约束后的 physical allocation 分别保存；绑定尺寸和物理尺寸不应合并。 |

## 实际输入 → 状态 → 输出边界

| 输入形态 | 第三方静态已知 | 官方已知 / 未知 | 自有 fixture 可证伪项 |
|---|---|---|---|
| image 类型为 composition，parent 省略 | 建立 composition 状态、单层 effect 工作空间和 group camera 登记；正常 planner 没有单独读取登记 | 官方 RGB context 已有下方采集；普通可见输出成员未知 | 下方非child颜色单变量是否进入 source；上方独立层不应误混入当前 capture。 |
| 同一 composition，某层 parent 指向它 | tree 和遍历位置由关系与 ordinal决定；未发现把关系转成私有 group 成员的实际 consumer | composition + parent 能否共同构成作者隔离模式仍未知，不能因没新字段而排除，也不能因有child就认定 | 保持世界变换与实际存储顺序相同，只改 parent；若 source/采集时点变，记录是哪种模式。 |
| copybackground 省略 | 普通保存状态沿默认 false；composition 没有显式 false 才触发的额外 material-state变化 | 省略的官方缺省不由第三方的 Bool 默认证明 | 缺省与显式false、true分别比较；不能只测false/true。 |
| copybackground = false | 普通保存状态仍为false；composition 另存在由“明确给出false”触发的material variant变化 | 该变化的alpha/RGB结果未知；没有读取shader/material正文，不推公式 | 在checker背景、透明ROI和可见effect正控制下，缺省与false应能识别是否改变背景透过或源内容。 |
| copybackground = true | 保存true；不走上述显式false的presence分支；状态参与final resolve准备 | 不能从名字推断一定采全场景或关闭组成员 | 与省略同输入比较，再改一个下层非child颜色。 |
| config.passthrough absent / false / true | resolved模式来自资源描述，实例config可覆盖；它影响camera/效果准备 | 官方默认及与copybackground/parent的组合未知 | 实例override后source与extent是否改变；不得按effect数或child数替代模式输入。 |
| size/extent、fullscreen、parent world frame | 工作空间与实际allocation分别保存，camera附着有自己的来源 | exact clipping/alpha施加位置、非screen composition物理分辨率仍未获得官方可见门 | 非方形目标、缩放/平移parent、screen resize；检查source关键点、边界和目标identity。 |

**严格限制**：本轮没读 stock material/shader/资产，未执行 Mirage。base-material究竟绑定哪项screen/capture输入及显式false的最终像素结果，不能只凭源码注释或variant状态推出。这个尚未闭合的直接产生者是 `M-input` 中读取的 composition base-material 声明及其最终采样/alpha consumer；产品只消费本报告的presence区别与实验协议，不消费那份payload。

## 可独立采用的项目策略

以下都是 `MyWallpaperX-strategy`，不是对官方算法的恢复。由现有 Program/graph、source snapshot、target lease/submission coordinator 和唯一 compositor实施，不增加 registry、clock、renderer 或 history owner。owner依据当前设计 `docs/scene/design/composition-render-target-design.md:26,42,48` 与 `AGENTS.md:22-39`。

| 能力 | 现在能做的明确结果 | 正例 / 反例与证据上限 |
|---|---|---|
| 输入保真 | 在既有解析authority保留copybackground三态、resolved passthrough provenance、类型、parent和ordinal；没有新作者mode字段 | 三份自有输入的字段presence保持不同；只改parent不丢ordinal/world frame。不产生视觉路由判决。 |
| source identity | graph preparation与encode消费同一prepared source及版本；不能prepare main source、encode时换外层group request | 把上一个source版本染成不同颜色，当前pass不得误读；source版本改变不借同physical texture蒙混。无需官方数学。 |
| 工作空间 | logical extent、physical target、camera mapping和final geometry分别保留；自行实现坐标映射 | 非方形/不同纹理分辨率/parent平移/resize互相独立；不接受缩小allocation仍当exact viewport。 |
| clear / preserve | 定义项目自有、可执行的“新帧先初始化，当前帧后续写保留已写内容”；无作者history不读上一帧组图像 | 同帧两个半透明成员都留下；下一帧移走成员旧ROI透明；初帧/空内容/resize无残影。此策略可现在用自有GPU门定案，无需官方像素golden。 |
| lifecycle | 同一source/target generation跨reserve、encode、completion、publication和terminal consume保持一致；失败局部保留安全父输出 | in-flight resize、stale handle、预算拒绝、局部effect失败、next-frame不得误消费旧租约。用项目自有事件门证明。 |
| 有序effect与final handoff | 只按作者实际active顺序传输出；final恢复层的geometry、camera与alpha来源 | identity effect、两效果调换、disabled effect、子层自身effect；不能只靠route/非黑证明。 |

这些策略不应被D1成员未知整体冻结；它们的窄设计、真实正反fixture可以独立批准与验证。不能在这些测试中偷偷把parent闭包作为已经定案的默认采集源。

## 真正还需的有界官方实验

研究问题只有一个：**composition的采集来源是否由既有类型/parent/copybackground组合区分；缺省与false是否等价？**无需恢复公式或寻找新mode字段。

先建立公开可见effect启闭正控制：同一自有image启用/禁用Tint必须在预登记ROI产生可重复颜色差；同一信号在实际composition上也必须成立。只启动/保存composition或看到同一红图不计成功。固定客户端build/hash、OS/backend、800×600自有fixture、viewport/颜色状态、输入hash、GUI顺序和实际存储顺序；任何GUI修改导致顺序/世界变换变化，不能冒充parent单变量。

随后最多9个同家族variant，不扩大成全组合扫描：每个copybackground形态（省略、false、true）各用一个基线、一个“下方非child X仅换颜色”、一个“上方 K仅在无parent与parent=C间切换”。三组沿相同self-authored B背景/X条纹/C composition/K角点图；所有图像与效果输入自写，不引用研究用sample identity作dispatch。基线保留不同区域以辨别X、K与背景来源，checker区区分背景透过与颜色变化。

预登记判断：X颜色变化影响composition输出意味着该模式纳入下方非child；K只改parent影响source意味着该模式具有关系相关来源；省略/false/true差异证明不能折叠输入；三个输入完全相同只能说明本profile未观察到区别，不能外推所有alpha/effect/pass组合。离散输入、顺序、identity exact；Tint方向、X/K独占ROI和checker透过按先登记的通道差分判定，容差不得看到结果后再放宽。

实验完成后可批准一个真实bounded来源profile，沿现capture/planner修第一处错误并撤去不再有依据的subtree分派。官方parity与自有实现等级分开：没有官方对照仍可报告项目自有执行；只提升本次实际验证的来源/extent/clear/lifecycle，不宣布全composition完成。

## Clean-room handoff attestation

- 本任务阅读了指定静态报告和固定Mirage相关源码，已处于隔离研究context；本研究者不得随后实现对应D1责任。
- 没有读取官方/第三方stock shader、资产/payload正文、二进制或新的反编译产物；没有保存原始源码摘录、公式、常量表或函数体。
- 本交接只含输入、输出/状态区别、顺序、资源生命周期、来源类别、证据定位、自有可证伪fixture与unknown。源文件路径/行号是审计定位，不是要求implementation context打开原源。
- 本研究conversation/tool输出不可当作实现brief转发。fresh implementation context只能收到经独立审核的本中性报告、批准后的项目合同及自有fixture。
- sanitized_handoff_reviewer：根 `/root` 已于2026-10-02阅读并接受本中性packet，确认无原始表达；sanitized_handoff_approved：true，仅认可资料交接边界，不批准成员或flag视觉语义。实施者仍应登记新的task/context identity并声明 `did-not-receive-raw-static-output`。
- parity_result：not-run。第三方模式不是官方语义，不是Mirage实际画面，也不是Wallpaper Engine像素或时序等价。
