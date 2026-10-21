<!-- document-role: historical-evidence -->
# RopeTrail world/负 subdivision 资格记录

> **历史证据 — 非现役入口**。截止：2026-10-22（只补下述缓存观测资格）。本页只保存固定客户端、自有输入的有界观察；未修改产品，也未新增 RopeTrail 支持、官方算法、像素 parity 或性能结论。当前来源边界归[来源索引](../development/source-index.md#particle-rope-profile-blackbox)，产品范围归[组件台账](../capabilities/particle-component-coverage.md#7-renderers)，排程归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 问题与资格

N08 的真实可见声明同时带 renderer flags=1 与 subdivision=-16，超出现役 profile。本轮只问固定官方客户端能否在项目自有输入下产生输出，以及哪些对照能区分语义；不改作者值、不放宽产品准入。输入由白色 RopeTrail trial、独立 SpriteTrail 正控制和蓝色 engine-age 标记组成，General/Movement flags 固定；不用真实作者 shader/script 或私有实现表达。

客户端为 Wallpaper Engine 2.8.0.42，EXE SHA-256 `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`；Windows 11 Parallels VM、自有 1536×1536 场景和 900×900 client。每组预登记 case、变量、停止门与输入 hash；收据核对 guest project/pkg、客户端、session、路径和唯一自有窗口 title/PID/handle/client。clock 以画面中的 engine age 对齐，宿主经过时间只安排采集，不当作相同模拟帧。

## 观察与反例

| 批次 | 有效输入与画面 | 能保留的结论 | 未解边界 |
|---|---|---|---|
| q1 | 只执行 f0-s0；两图均被 PowerShell/Terminal 遮挡，clock 缺失；其余 case 未运行 | 环境采集无资格，整批退役 | 不能据此判无粒子、不可执行或官方行为 |
| q2 直线 | flags/subdivision 为 0/0、1/0、0/-16、1/-16、0/1；每 case 两图，10 图均有正控制、trial 与推进的 clock | 两种 flags 下，包含 -16 的输入均产生可见线带 | 直线不能区分 world/负值处理；不能排除忽略、default、clamp 或其他解释 |
| q3 曲线 | flags=0，subdivision=0/1/-16；每 case 实测 engine age 48.0533/54.1333，6 图均有 trial 与绿色正控制 | 本组方向变化路径中，0 的接点较尖，1/-16 的外观较圆顺 | 只保留可见接点差异，不推数值大小规则、两值等价、曲线公式或采样密度；白纹理不能观察 UV |
| q4 复合倾斜 | subdivision=0，仅 renderer flags=0/1 不同；4 图均有 trial、正控制与推进的 clock | 本组倾斜下线带宽度/方向接近，未达到预登记区分门 | world orientation 仍 unknown；不推 flags 被忽略、General/Renderer 可互换、历史世界锚定或动态 parent 行为 |

q2 的 trial 白像素均大于预登记的 8 像素可见门。q3 trial 为 312/505、309/507、311/510 像素；绿色正控制只有 4–6 个实际像素，8 像素门针对白色 trial，不据绿色计数错误否决。q4 的宽度区分门要求两次对齐观察均超过 2 client px 且 20%，本组没有取得该区分。数值插值只用于测得 engine-age 重叠内的近似比较，没有生成中间画面；各 analysis 均不授予 automatic parity。

q2–q4 共 20 张 PNG 已逐图检查，无可见控制台/UI 遮挡。冻结输入及 guest hash 核对通过，未见 source drift；首个 execution receipt 未都记录独立 drift 字段，另以冻结清单和 guest hash 核对补足该范围。采集绑定精确窗口，但未独立记录前台窗口 handle，不把画面检查扩大成完整前台所有权证明。每次正常退出均有 exact own-window 关闭、remainingOwnWindows=0 收据。

`locale-ui-filtered.json` 只确认 Rope/RopeTrail 名称和普通说明，没有给出负 subdivision 的含义。初轮宽 regex 的 `rope` 同时命中了 `properties`，无关属性文字不能作为粒子字段证据。公开说明、输出存在和数值近似均未解决完整语义。

## 停止与后继

本轮停止扩展 N08 矩阵。现役拒绝与能力等级保持原样；3337494481 十层的实际恢复仍未证明。只有取得能区分负值及 world 行为的合法作者合同或新证据，才回到同一 trail owner 设计实现与正反验收；本页不授权按 -16 放行、取绝对值或夹值。

<a id="cache-observer-20261022"></a>

10-22另试一次自有单RopeTrail的GS最大输出容量观测，固定同一客户端、640×360、flags0/subdivision0；只派发s0，+1/-16/-3均未运行。两张原图保四角标及右移白trial，640→608白像素、包围盒x=179…218→201…238，只证明可见正控健康。7份自有新缓存均在原观测器的裸DXBC入口返回`UNKNOWN_CACHE_FORMAT`，未调用D3DDisassemble；HRESULT为初始化哨兵，既不是API调用失败，也不是官方App崩溃。未获得单GS身份或容量4，原`STOP_UNKNOWN_CACHE_FORMAT`保留，不改准入。

既有stock资料已记录`SHDV0069`包装；本轮固定stock的候选长度与内层DXBC结构吻合，但均有未解释尾部，未证明完整包络或全部GS归属。此线停止，不试偏移、不追加白线矩阵；后继须先取得可验证的包络/归属证据，再复用已保存缓存，不能由内层自洽外推官方负值规则。最小收据归`.artifacts/scene-evidence/runs/rope-trail-gs-observer-stop-20261022/`；独立审查确认停止裁决。下一项由现役队列重新选择，本页不保存后继排程。

## 收据与保留

详细输入、卡片、hash、原图及分析在忽略目录 `.artifacts/tmp/n08-rope-qualification-20261015/`：q2 的 `research-card.json`、`frozen-inputs.json`、`analysis-q2.json`，q3 的 `research-card.json`、`root-execution-input-freeze.json`、`analysis-r1.json`，q4 的同名卡片/冻结清单、`analysis-q4.json`、`qualification-q4.json`；q1 的 `qualification-q1.json` 保存环境无资格裁决。q4 曾因分析适配器沿用 q2 名称未产出结果，该失败保留，后续真实结果由直接分析取得。

`guest-copy-cleanup-q1-q2.json` 与 `guest-copy-cleanup-q3-q4.json` 已记录全部 11 份精确自有 guest 副本 hash/窗口关闭核对后删除成功。首个不支持的 shutdown 调用虽返回 0，实际状态仍未关闭；随后 `stop --acpi`，`environment-state.json` 核实 VM 为 stopped。`cleanup.json` 记录宿主再生成的工程副本已移除，保留自有源码/生成器/清单、20 张有效 PNG、1 张无资格 PNG 与必要收据，任务根约 0.6 MiB。原始 locale 投影压缩保留，窄过滤元数据保留；`promotion.json` 的保留预算超限，未 prune、未增预算、未删除未知材料。保留根仍为 `.artifacts/tmp/n08-rope-qualification-20261015/`。
