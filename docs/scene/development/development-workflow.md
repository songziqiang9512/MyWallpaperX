# Scene 开发与验证

<!-- document-role: stable-contract -->

从[运行架构](../architecture/runtime-architecture.md)定位 owner，从[能力索引](../capabilities/README.md)确认当前范围，从[开放问题](../roadmap/scene-open-breakpoint-queue.md)选择真实断点。仓库通用规则与设计判定见[开发工作流](../../development/repository-workflow.md)。

## 修改与验证范围

先说明用户可见问题、输入到输出的第一个错误、负责代码和最小正反例。外部数据在实际入口校验，内部传 typed 值；准备工作放在加载或真实失效边界，普通帧消费 prepared 结果。状态、资源与最终输出的归属按运行架构核对，不为修复再建平行 owner。

验证按影响面选择已有最近门：

```sh
python3.12 -B script/verify_scene_change.py --phase inner --base HEAD --path <修改路径>
```

先检查选择结果，再加 `--run` 执行。Swift 产品修改做 Debug build；GPU、VM、生命周期和可见变化补隔离真实运行。纯文档修改检查索引、链接与内容，不自动构建 App。构建使用 `script/run_checkpoint_build.sh`；`script/build_and_run.sh` 会停止正在运行的 App。

自有 fixture 测实际输入、输出、顺序和失败半径，保留健康相邻 consumer。兼容规则用变量或资源改名、等价表达式及相邻反例验证；另外选择未参与调参的真实内容核画面。实际过程只证明被执行的条件，编译、ready、非黑画面与日志无错都不能单独证明正确兼容。

## 隔离运行与配置

真实 Workshop 目录只读。输入副本、HOME、TMPDIR、缓存、App staging 和报告放任务隔离目录；记录实际 App、输入、工具和环境身份。共享构建目录、原生窗口、GPU、真实鼠标、音频与系统媒体实验串行协调。只退出精确归属本次任务的进程。

`script/scene_diagnostic_build.xcconfig` 供短筛查和交互诊断，保留 DEBUG 入口并使用优化 Swift/C；它的 single-file 配置不代表正式 Release WMO。性能对照使用相同 Swift/C 参数、诊断开关、输入、音源、viewport、帧率与热状态，不能新配置候选配旧配置基线。测量及停止标准见[性能工作卡](../roadmap/performance-convergence-card.md)。

DEBUG direct-host、产品 client→daemon 和正常桌面有不同覆盖范围。截图入口可能改变目标的 framebuffer-only 权限或使用合成 provider；桌面、真实媒体和终端 attachment 的修改还要走正常桌面路径。产品控制链的测试必须实际经过 App 服务、client 与 daemon，不能用独立 Host 代替。

## 声明扫描与运行诊断

| 工作 | 当前工具与输出含义 |
|---|---|
| 观察目录、资源和作者声明 | `scene_capability_census.py`；snapshot、总览与样本明细由同一次观察产生，不证明已执行或可见 |
| 启动、控制、截图与收集日志 | `scene_wallpaper_benchmark.py`；实际运行身份与原始结果是该次观察的依据 |
| 归一公共首断点 | `scene_diagnostic_report.py`；保留 stage、owner、reasonCode、profile 和失败范围，不以聚类代因果 |
| 关联样本与多次运行 | `scene_sample_debug_archive.py`；保留各行的原报告身份，不把多次观察称同次全量运行 |
| 人工视觉裁决 | `scene_sample_acceptance_ledger.py` 读取现有 verdict 数据；不得由声明、日志健康或生成器补成视觉通过 |

报告写入忽略的任务输出目录，不作为长期能力文档。显式输出示例：

```sh
python3.12 -B script/scene_capability_census.py generate \
  --snapshot .artifacts/scene-reports/corpus/snapshot.json \
  --markdown .artifacts/scene-reports/corpus/overview.md \
  --sample-markdown .artifacts/scene-reports/corpus/samples.md
python3.12 -B script/scene_capability_census.py verify \
  --snapshot .artifacts/scene-reports/corpus/snapshot.json \
  --markdown .artifacts/scene-reports/corpus/overview.md \
  --sample-markdown .artifacts/scene-reports/corpus/samples.md
```

`--sample-id` 可重复选择子集，子集须使用专用输出；`query` 默认查已有 snapshot，`--live` 才读取真实目录。单目录解析失败仍计入发现集合并保留原因，不丢分母。输出不得落在只读输入内，也不得互相覆盖。

运行用当前 snapshot 的 sample identity 构造所需 matrix，选择报告所需的少量代表，不继承不适用的截图、计数或性能期待：

```sh
python3.12 -B script/scene_wallpaper_benchmark.py \
  --app <签名App可执行文件> --sample-root <只读且含Scene的输入父目录> \
  --matrix <本次matrix.json> --output-dir <本次结果目录> \
  --log-only --duration 4 --jobs 1
python3.12 -B script/scene_sample_debug_archive.py \
  --snapshot <本次snapshot.json> --report <本次结果目录/report.json> \
  --output <本次archive.json>
```

具体参数以脚本 `--help` 为准。单独 `--log-only` 保留执行观察与停止；加 `--terminal-snapshot` 在 after 点取一张 Metal PNG，缺省最长1280。活动 pointer 轨迹需要普通模式的各相位捕获；普通模式缺省保全分辨率，也可显式 `--snapshot-max-edge` 缩导出。细线或弱信号须回看原尺寸，缩图消失不能判原始像素缺失。执行观测开启的轨迹请求复用组件事实接口；粒子 bind 行同时记录传给 draw 的 blend/cull/depth、相机选择与实际 depth attachment。导出缩放不改变渲染或完整读回尺寸，编码事实不增加逐输入可见贡献或性能资格。筛查模式允许 `--jobs > 1`；增加并发前核资源/进程隔离、每图 request 与 Surface/GPU 回执及排空。正式性能和真实系统输入仍串行。`--startup-timeout-allowance` 是 supervisor 总期限中额外的准备余量，不改变 Ready 后观察时长。短窗未触发的定时、随机、条件或输入分支只对对应子集延长。

分别判断 `declared / prepared / executed / failed / not-triggered / unknown`。图层隐藏、alpha 为零、离屏、延迟或缺输入不能直接判缺图；先确认目标 consumer、作者过渡和实际 scene time。并发超时、OOM、缺 drawable 等现象先用同输入串行复核。原始失败与后续恢复保留在同次报告，不用重试覆盖失败。

<a id="corpus-runtime-measurement"></a>
### 全量运行测量

目标是逐样本定位合法输入的首个缺口，同时保留通用能力与样本个别问题。复用上述工具链和现有 DEBUG trace、提交 completion、terminal capture；产品执行仍由原资源、组件、Graph 和 compositor 负责，观测不参与准入或改变画面。

- **输入与分母**：census 保发现集合、非法 project 和合法 loose；注释不作 shader 声明，条件分支保声明 ordinal。树清单共用口径、复用已读摘要，benchmark 记录隔离副本实际身份。archive 按内容关联显式 attempt，保原失败，末次传入作为当前投影；库存及其派生声明与真实 scene consumer 分开。聚合加载比例只作cohort线索，不顶替精确consumer失败。身份缺失或内容漂移只影响测量资格，不升级为播放许可。
- **实际消费**：Program 既有选中 slot/资源归因随真实 encode 保留；replay 取替换后的物理 binding，attachment-read 独立标记。普通 source、geometry、particle、group 与颜色导出记录实际 input→target，沿原 command-buffer completion 和 sealed tail 接终端；保 Surface/提交身份及 presentRequested。图输出纹理合成与 terminal material replay 分开。
- **逐组件**：准备期保作者原 ordinal、definition/child 身份与选中 renderer；模拟观察区分尝试、实际求值、接纳出生及真实拒绝。batch/draw/GPU 与 CPU 观察分别记录；effect旁路保copy/GPU事实与原失败，不算作者operation执行。无法将某组件结果精确接到实例或最终像素时保 unknown，不能用下游非空代替因果证明。
- **成本与边界**：新载荷只在显式 DEBUG 测量启用，沿原捕获请求选少量帧，在分配和格式化前取样；只传小值，不持有纹理，不新增全图 hash、逐粒子历史或 completion owner。Release在调用处退出；关闭时没有新增观测表/循环，避免逐粒子进入空helper或构造payload，普通成功算子在实际循环后记首witness。达到诊断容量明确报告截断。bound、draw-encoded、GPU-completed、terminal-consumed/exported、present-requested 和 PNG-observed 分开，均不自动授予逐纹理可见贡献或官方 parity。
- **运行与画面**：普通样本 Ready 后观察3–4秒，慢准备使用现有 supervisor allowance，过场/延迟只延长对应子集。日志模式可显式请求一张指定 Surface 的 terminal PNG 并保原渲染尺寸；预览缩放只影响导出，记录源/导出尺寸。同request/CB/Surface/GPU与drawable token/extent唯一匹配可证明普通/粒子场景终端，不制造不存在的graph分母或覆盖真实错误。此筛查允许隔离并发，真实系统输入和正式性能仍串行；先小批核每进程路径、实际读回、GPU与停止排空，再按宿主余量增并发。

验收先覆盖坏/非对象 project、loose、内容漂移、多 attempt、无终端或跨层拼接反例，以及真实改名输入、replay/attachment-read、纯普通层和粒子、取样关闭与截断。冻结源码/构建/运行身份后再全量；缺读口、未触发、作者错误、实际不支持、错误拒绝与视觉疑点分别归队。PNG本身不要求每个包内闲置或未选资源出画；需要可见贡献裁决的未决项用实际时间/输入及局部差分复核。测量完成后按当前证据替换开放队列，不以日志无错关闭未取得资格的能力。

## 截图与时序

固定属性、时间、指针、音源、媒体状态、viewport 与随机条件后再比较画面。`--after-snapshot-delay` 约束 ready 后开始安排截图的单调时钟；指针交互还要完成退出和稳定步骤，after 取两者较晚时刻。请求时刻、实际 GPU 捕获和文件写出是不同阶段，比较时核对实际日志与捕获身份。

benchmark 清除继承的 Scene DEBUG 配置；样本的 `timeline_frame_evidence` 显式携带原 `SceneTimelineFrameEvidence` 配置对象，并记入运行报告。它只选择已有 layer/context 时间读口，不把 transform 值当 effect uniform。样本显式整数数组 `puppet_interaction_layer_ids` 可在无 cursor 输入时选择原骨骼/geometry 读口。先核配置确实到达 App，再按 stream/frame/snapshot generation 关联实际 uniform 消费与捕获；窗口外或无记录保未知。log-only 不支持 periodic；短 Single 动画可先用 early terminal capture，按实际 sceneTime/elapsed frame 判活动相位。

停止或取消后不再请求新截图；收尾须确认准备、CPU worker、GPU、导出和进程分别完成。证据保留与清理按[产物规则](../../../.agents/skills/mywallpaperx-maintainer/references/artifact-governance.md)，只保必要日志、报告和画面。

<a id="compatibility-exceptions"></a>
## 有界兼容规则

| 当前限制 | 负责代码 | 扩展时应验证 |
|---|---|---|
| 动态图片依赖在准备期从 `thisScene.createLayer` 的直接路径或平面配置 literal 发现，不求值任意 JavaScript 表达式 | [ReferenceAnalysis](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneScriptDynamicImageReferenceAnalysis.swift) | typed 间接依赖、模块/嵌套表达式及健康邻例；不能改成帧内 IO 或整目录预加载 |
| 无typed边界的颜色兼容与未表达通道角色仍依赖有界source/MSL分析 | [SourceAnalyzer](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderFrontend/SceneAuthoredShaderPreviousBlurredCompositeAnalyzer.swift)、[颜色编译](../capabilities/render-graph-shader-coverage.md#typed-color-compilation) | 普通typed边界直接编译；剩余真实通道/操作缺口沿原compiler/ABI补齐，保data/signal、PMA/straight、alpha/HDR及实际像素反例，不增加算法族或固定源码名单 |

路径、hash 或固定源码形状若承担兼容选择，须在本节说明实际必要性、影响范围、正反例和替换条件。资源查找 identity、缓存键和标准 API 名称不因此成为视觉特判许可；样本身份不得选择产品算法。

<a id="document-maintenance"></a>
## 文档维护

Scene 文档维护当前代码职责、能力范围、可复核运行证据和必要开发方法。同一事实只在负责文档写一次，入口直接链接该文档；已实现、未实现和未验证明确区分，旧结果不得作为当前状态。代码或运行条件改变后，重新核对受影响结论。

源码与自动门决定代码事实；可见、性能和官方一致性分别需要相应运行依据。当前缺口写入开放问题，来源及其适用边界写入来源索引。过程、旧版本和旧结论通过 Git 查询，不持续累积为开发前置文档。
