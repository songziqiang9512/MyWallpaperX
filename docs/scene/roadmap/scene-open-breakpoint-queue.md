# Scene 当前开放问题

<!-- document-role: active-plan -->

本页只保留当前用户报告和有可复核证据的未修问题。后续修复从本页选题，优先处理可见合成、播放及交互，其次处理已测性能和热更新。可主动筛查任意样本，实际确认的断点记入本页后再排修。

修复后移出队列，已验证范围、样本和运行身份留在[运行证据](../capabilities/runtime-evidence-current.md)及[能力正文](../capabilities/README.md)。默认隐藏、未触发、短窗缺帧和未有实际消费者的源码边界各归其原证据，样本和图层只用于复现定位。

<a id="user-feedback"></a>
## 当前用户反馈

以下是仍待核查或修复的用户观察。逐项固定原包、属性、画幅和触发输入，对照官方实机后确认差异。证据链接用于复用既有对照条件。

| 样本 | 本轮反馈 | 复验起点 |
|---|---|---|
| 3042492564 | 切「人物动作(动画)」后左人掉下 | [原包热切和冷载对照](../capabilities/runtime-evidence-current.md#author-float-reload-304)中，本机左、右按作者脚本停在 Y665.2/1891.1 并恢复，未复现下坠。本次官版弹窗 CLI 对照仅证明直接绑定生效，仍需通过实际属性面板核热回调和姿态。 |
| 3750813609 | 时钟的白光混入黑色，官版为白光 | 原钟层 358 有 Blur 与 Clouds。固定同一字形和底图，逐步隔离文字覆盖、模糊与末端混合。 |
| 3603711180 | 歌曲文字位置错 | [标题、艺人、时间和封面供给](../capabilities/runtime-evidence-current.md#author-player-text-current-360)有同输入对照。以同媒体、字体和画幅比较首行与次行的盒位置。 |
| 3781003282 | 指针粒子移到浅色区时中央有半透明白方 | [旧红尾随鼠标](../capabilities/runtime-evidence-current.md#pointer-halo-378)。在浅、深背景重复同一路径，检查中央 Sprite 的覆盖与混合。 |
| 2868108515 | 剑链左侧仍有蜘蛛网状叠影 | 沿[旧高通对照](../capabilities/runtime-evidence-current.md#author-chain-godrays-local-grid)，按新叠影位置固定同场景时刻，比较 39/e43181 开关下的残差。 |
| 3769688830 | 本机玩偶水球持续向左转，用户在官版看到头朝上的往返摆动 | [旧实测含 spinorb/e524 与父层摆动](../capabilities/runtime-evidence-current.md#orb-spin-parent-motion-376)。对齐自转属性、父层相位和默认版本，分别比较静止头向和摆动轨迹。 |
| 3382111183 | 人物脚下短横线本机呈白，官版有颜色 | 复用[六层定位](../capabilities/runtime-evidence-current.md#floor-beam-continuous-emission)和[实例色对照](../capabilities/runtime-evidence-current.md#particle-instance-color-revision)，用同曲同布景帧测实际短横线的 RGB 并核对应层，区分地面斜线。 |
| 3673609113 | 人偶运动和音条抖动时出现上一帧残影 | [旧残影归因](../capabilities/runtime-evidence-current.md#author-motion-history-367)覆盖飘带。新对照固定人偶和音条各自的高运动 ROI，比较历史源清除、当前帧及官版连续图。 |
| 3187857248 | 仍有时拖不动 | 沿[拖动证据](../capabilities/runtime-evidence-current.md#puppet-drag-surface-318)匹配两端当前骨位置，重复真实按下、拖动和释放，记录命中归属。 |

<a id="implementation-gaps"></a>
## 独立实测的开放断点

| 定位 | 已确认的差异与下一步 |
|---|---|
| 3463406101 · 前景回亮 | [归一后历史](../capabilities/runtime-evidence-current.md#forefront-normalized-history-346)已接入。[原低多音](../capabilities/runtime-evidence-current.md#forefront-recovery-346)的早期回亮仍有残差。沿同源分析代次核分母与实际供值。 |
| 2927205881 · 高倍率粒群密度 | [同帧出生组](../capabilities/runtime-evidence-current.md#particle-continuous-birth-cadence-292)排除深度开关，官版连续发射在12个相邻对各新增1组，本机按子步分组。核对普通连续出生与积分的职责，保瞬发、寿命和事件，再以同音源复验原包动态切换。 |
| HSV 粒子出生色 | [同板实测](../capabilities/runtime-evidence-current.md#particle-hsv-birth-color-oracle)省略 `huesteps` 时官版着色，本机保白。分开步数缺省、实际色相和两种实例色输入。 |
| Sphere 全零方向 | [隔离对照](../capabilities/runtime-evidence-current.md#zero-radius-sphere-launch)中官版无像素，本机出现静点。原作者盘点未发现活动声明；用实际子事件或占槽对照区分出生和可见性。 |
| 粒子高阻尼和侧转 | [同龄大阻尼](../capabilities/runtime-evidence-current.md#particle-movement-half-life)的 drag40 官/本相差约 15 px，drag20 在容差内。[正交 Sprite](../capabilities/runtime-evidence-current.md#particle-around-phase-frame)的精确 90° 另有投影差。各自核实际步长与局部 quad。 |
| GLSL 作用域与采样声明 | 双阶段 varying/uniform 同名在真编译中触发重定义。另一个实际反例是 slot0 sampler 的宏别名被冷接口拒绝。沿现有 stage ABI 与预处理接口复现，保持健康相邻声明。 |

<a id="performance"></a>
## 已实测的性能问题

| 样本 | 剩余瓶颈 |
|---|---|
| 3337494481 | [签名优化态](../capabilities/runtime-evidence-current.md#particle-turbulence-borrow)首屏仍由完整粒子预热主导。沿实际热采样找可去工作，保首帧和历史。 |
| 3749463715 | [可比 60fps 运行](../capabilities/runtime-evidence-current.md#gpu-admission-wake-374)实呈从 29.96 提升到 34.80fps，尚低于目标。仅跟进当前路径的新显著成本。 |
| 3420215721 | [同包实测](../capabilities/runtime-evidence-current.md#scene-playback-triage-342)仍有 GPU 超预算。固定 scene-time 和实际历史源做消融。 |
| 3673609113 | [实呈与 GPU 回执](../capabilities/runtime-evidence-current.md#inactive-terminal-copy-367)仍显示 GPU 超预算。沿实际帧成本定位，保两级作者历史。人偶及音条残影独立按用户反馈核对。 |
| 3808922316 | [预热读回](../capabilities/runtime-evidence-current.md#particle-prewarm-hotpath)优化态预热 18.12s、Ready 24.05s。围绕已测预热工作量寻找保随机与首帧的删减。 |

测量与退出条件归[性能方法](performance-convergence-card.md)。

<a id="properties"></a>
## 已实测的工具问题

| 定位 | 仍在复现的断点 |
|---|---|
| <a id="legacy-gate-debt"></a>存量回归夹具 | 提交阶段夹具缺 composition trace API；暂停文字的两屏对照在旧签名及文字修订后同样失败。另有旧 347 与 366 resize 的跨 epoch 判定误用，23/23 图在新 epoch 恢复仍被记录为失败。按实际 owner 和输出修对应门。[缩放证据](../capabilities/model-runtime-evidence.md) |
| 呈现与周期截图 | 后台鼠标输入已有合格 GPU 帧，但部分报告缺 presented 计数或 interval 身份。366 的周期截图有 superseded 和 teardown 拒绝。分别核 present 回调与请求排空，保有效的独立捕获。 |
