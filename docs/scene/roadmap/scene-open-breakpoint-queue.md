# Scene 当前开放问题

<!-- document-role: active-plan -->

本页只保留当前用户报告和有可复核证据的未修问题。后续修复从本页选题，优先处理可见合成、播放及交互，其次处理已测性能和热更新。可主动筛查任意样本，实际确认的断点记入本页后再排修。

修复后移出队列，已验证范围、样本和运行身份留在[运行证据](../capabilities/runtime-evidence-current.md)及[能力正文](../capabilities/README.md)。默认隐藏、未触发、短窗缺帧和未有实际消费者的源码边界各归其原证据，样本和图层只用于复现定位。

<a id="user-feedback"></a>
## 当前用户反馈

优先处理最近仍在复报的项目。逐项固定原包、属性、画幅和触发输入，对照官方实机确认差异，优先复用已有对照条件。

| 样本 | 本轮反馈 | 复验起点 |
|---|---|---|
| 2868108515 | 剑链左侧的叠影仍可见 | [两端原包及只关 Godrays 的对照](../capabilities/runtime-evidence-current.md#author-chain-left-step-286)已定位接缝，单独冻结剑图与 Godrays 未重现原包幅度。用可见时间标记对齐完整效果链，再控制底色比较覆盖。 |
| 3769688830 | 本机玩偶水球持续向左转，用户在官版看到头朝上的往返摆动 | [两端同窗热切](../capabilities/runtime-evidence-current.md#orb-spin-official-live-376)和[本机冷启动读取](../capabilities/runtime-evidence-current.md#orb-spin-cold-defaults-376)已核。待验证真实面板写入及官版冷启动恢复。 |
| 3673609113 | 人偶运动和音条抖动时出现上一帧残影 | [受控姿态](../capabilities/runtime-evidence-current.md#author-puppet-history-367)定位末级历史，[自然动作与脉冲](../capabilities/runtime-evidence-current.md#author-natural-audio-history-367)核本机图像顺序和频谱同代。余下对齐官版本机的连续呈现与实际频带值，区分整图残影和1552音频累计。 |
| 3586705329 | 图5的拼贴竖状拉伸随镜头大小变化 | [官版同样出现的 Scroll 边带](../capabilities/runtime-evidence-current.md#author-collage-edge-358)可复用。将反馈图注册到同画幅、镜头和滚动相位，区分已量过的边带与额外变形。 |
| 3337494481 | 图6封面与环字斜视错位 | [环字深度](../capabilities/runtime-evidence-current.md#author-box-ring-depth-333)已消除背面穿透。[两端冻结投影](../capabilities/runtime-evidence-current.md#author-box-oblique-333)偏移符合作者高度，剩原包同轨迹、同 PCM 对照。加载见性能区。 |
| 3372715909 | 右上角时钟仍缺失 | [当前本机原包](../capabilities/runtime-evidence-current.md#author-clock-full-337)确认重开后仍由视频盖住钟字，官版原包冷开黑帧后退出。剩余要有官版原包可见帧或用户当时的属性、视频和画面，现有缩减包已确认克隆追加层序。 |
| 3042492564 | 切「人物动作(动画)」后左人掉下 | [原包热切和冷载对照](../capabilities/runtime-evidence-current.md#author-float-reload-304)中，本机左、右按作者脚本停在 Y665.2/1891.1 并恢复，未复现下坠。本次官版弹窗 CLI 对照仅证明直接绑定生效，仍需通过实际属性面板核热回调和姿态。 |

<a id="implementation-gaps"></a>
## 独立实测的开放断点

| 定位 | 已确认的差异与下一步 |
|---|---|
| 3463406101 · 前景回亮 | [归一后历史](../capabilities/runtime-evidence-current.md#forefront-normalized-history-346)已接入。[原低多音](../capabilities/runtime-evidence-current.md#forefront-recovery-346)的早期回亮仍有残差。沿同源分析代次核分母与实际供值。 |
| 2927205881 · 高倍率剩余覆盖 | [同包晚帧](../capabilities/runtime-evidence-current.md#particle-live-continuous-frame-292)仍有亮列及左缘残差。对齐实际更新时长与同源音频，核精确阻尼和控制点组合。 |
| Sphere 全零方向 | [隔离对照](../capabilities/runtime-evidence-current.md#zero-radius-sphere-launch)中官版无像素，本机出现静点。原作者盘点未发现活动声明；用实际子事件或占槽对照区分出生和可见性。 |
| 粒子高阻尼和侧转 | [同龄大阻尼](../capabilities/runtime-evidence-current.md#particle-movement-half-life)的 drag40 官/本相差约 15 px，drag20 在容差内。[正交 Sprite](../capabilities/runtime-evidence-current.md#particle-around-phase-frame)的精确 90° 另有投影差。[分相位板](../capabilities/runtime-evidence-current.md#particle-live-update-phases-292)证实首步重力与后继阻尼的差异，继续核阻尼时长、组合输入与正交 quad。 |
| 粒子颜色定义空值 | [同板实测](../capabilities/runtime-evidence-current.md#particle-birth-color-composition)有实例色时，空 Color List 在 v4/v5、HSV `huemin:null` 在 v4 的官版结果与本机不同。先区分缺项、显式空和错误类型的定义入口语义。 |

<a id="performance"></a>
## 已实测的性能问题

| 样本 | 剩余瓶颈 |
|---|---|
| 3337494481 | [最新同包预热对照](../capabilities/runtime-evidence-current.md#particle-life-buffer-evidence)一对首帧20.86→18.23秒，候选预热13.48秒。只跟进可复验的新热点，保持历史及 RNG。 |
| 3749463715 | [可比 60fps 运行](../capabilities/runtime-evidence-current.md#gpu-admission-wake-374)实呈从 29.96 提升到 34.80fps，尚低于目标。仅跟进当前路径的新显著成本。 |
| 3420215721 | [同包实测](../capabilities/runtime-evidence-current.md#scene-playback-triage-342)仍有 GPU 超预算。固定 scene-time 和实际历史源做消融。 |
| 3673609113 | [实呈与 GPU 回执](../capabilities/runtime-evidence-current.md#inactive-terminal-copy-367)仍显示 GPU 超预算。沿实际帧成本定位，保两级作者历史。人偶及音条残影独立按用户反馈核对。 |
| 3808922316 | [同包交错实测](../capabilities/runtime-evidence-current.md#particle-life-buffer-evidence)预热中位降至41.67秒，首帧49.09秒。沿现役短栈找保随机、存量和首帧的单根工作删减。 |

测量与退出条件归[性能方法](performance-convergence-card.md)。

<a id="properties"></a>
## 已实测的工具问题

| 定位 | 仍在复现的断点 |
|---|---|
| <a id="legacy-gate-debt"></a>存量回归夹具 | 提交阶段夹具缺 composition trace API；暂停文字的两屏对照在旧签名及文字修订后同样失败。另有旧 347 与 366 resize 的跨 epoch 判定误用，23/23 图在新 epoch 恢复仍被记录为失败。EventDeath 子系统时长在冻结父版本与当前均为.125秒，夹具断言.1333秒。按实际 owner 和输出修对应门。[缩放证据](../capabilities/model-runtime-evidence.md) |
| 呈现与周期截图 | 后台鼠标输入已有合格 GPU 帧，但部分报告缺 presented 计数或 interval 身份。366 的周期截图有 superseded 和 teardown 拒绝。分别核 present 回调与请求排空，保有效的独立捕获。 |
