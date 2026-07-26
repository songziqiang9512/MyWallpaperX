# Scene 音频频谱链路开发计划

> 建立日期：2026-07-27
>
> 实现基线：`b86db59`（interpretation v29）
>
> 作用：定义 Scene 音频频谱从当前 `L0/L1` 到可运行、可诊断、fail-closed 最小闭环的实施顺序、样本门与验收标准。
>
> 依赖约束见 [公共能力依赖图](semantics/capability-dependency-map.md)；等级口径与当前事实见 [总覆盖台账](coverage-ledger.md)；本计划是 [Scene 播放能力开发计划](scene-capability-development-plan-2026-07-22.md) 中 `S5 音频` 与 `B4 Feature Breadth` 的展开，不改变任何现有能力等级。

## 1. 当前事实

### 1.1 已有能力

| 位置 | 当前状态 |
|---|---|
| Audio frame input（Scene） | `L0`：`SceneFrameContext` 无频谱字段，host 不采集 |
| Audio declarations（effect） | `L1`：`AUDIOPROCESSING` combo 与 `audio*` constant 进 IR，strict planner 遇到非 0 整段拒绝 |
| Audio declarations（particle） | `L1`：`audioprocessingmode`/`audioamount`/`audioexponent`/`audiofrequency`/`audioprocessingbounds` 已解析，simulation 报 `audioResponseIgnored` |
| SceneScript `AudioBuffers` | `L0`：无 VM |
| Sound layer | `L0`：无 sound content IR/player |
| **系统音频采集** | **已存在且在同进程**：`SystemAudioSpectrumService` 用 `CATapDescription` 全局 tap（macOS 14.2+），30 Hz 处理节流，按需采集，含设备失效重启与退避重试 |

关键架构事实：`SceneDesktopWallpaperHost.shared` 与 `SystemAudioSpectrumService` 同在主 App 进程（Scene 不走 daemon session），因此音频接入是**进程内直连**，不需要新增 IPC 通道。`PlaybackContentKind` 当前只有 `.video`/`.web`，Scene 的采集需求信号要单独建立。

### 1.2 官方算法合同（一手证据）

stock `pulse.vert` / `shake.vert` 完整公开了音频响应算法，这是 WE-compatible asset 直接证据，不是推断：

```glsl
// [COMBO] {"combo":"AUDIOPROCESSING","type":"audioprocessingoptions","default":0}
uniform float g_AudioSpectrum16Left[16];
uniform float g_AudioSpectrum16Right[16];
uniform float g_AudioFrequencyMin;  // int, range [0,15], default 0
uniform float g_AudioFrequencyMax;  // int, range [0,15], default 1
uniform float g_AudioPower;         // audioexponent, range [0,4], default 1
uniform vec2  g_AudioBounds;        // audiobounds
uniform float g_AudioMultiply;      // audioamount, range [0,2], default 1

// AUDIOPROCESSING: 0=off, 1=left, 2=right, 3=left+right 平均
audioResponse = Σ buffer[min..max] / (max - min + 1)      // mode 3 再除以 2
audioResponse = smoothstep(bounds.x, bounds.y, audioResponse)
audioResponse = saturate(pow(audioResponse, power)) * multiply
```

三点直接影响设计：

1. **计算在 vertex stage**，结果以 `varying float v_AudioPulse` 传给 fragment。effect 侧是**每 draw 一个标量**，不是逐像素纹理采样。
2. **effect 只消费 16-bin**。32/64-bin uniform 在 stock effect 中不出现，只在 workshop 自定义 shader（`zcompat/.../Simple_Audio_Bars.frag`）里按 `RESOLUTION` 宏三选一。
3. 字段名与 particle 的 `audioamount`/`audioexponent`/`audiofrequency`/`audioprocessingbounds` **完全同构**，因此 effect 与 particle 可共用一个 evaluator。

`audiobounds` 的 stock 默认值按 effect 不同：pulse 为 `0.5 1.0`，shake 为 `0.0 1.2`。默认值必须来自各自 shader annotation，不能统一硬编码。

### 1.3 真实样本 census（45 样本隔离缓存，只读扫描）

只统计作者 `scene.json` 中 `AUDIOPROCESSING != 0` 与 particle `audioprocessingmode != 0`，排除 stock shader 自带的 `[COMBO]` 声明和我们自己生成的 interpretation 文件：

| 类别 | 样本数 | 处数 | 分布 |
|---|---:|---:|---|
| effect audio（合计） | 11 | 54 | — |
| ├ stock `shake` | 6 | 23 | `1937925563`(12)、`2134765860`(5)、`3767460992`(2)、`3768229922`(2)、`2419444134`(1)、`2938612768`(1) |
| ├ stock `pulse` | 4 | 7 | `3768229922`(4)、`2419444134`(1)、`2938612768`(1)、`2974757317`(1) |
| └ workshop 自定义 shader | 6 | 24 | `3299228616`(12)、`3767460992`(6)、`2884628849`(2)、`2902406982`(2)、`2134765860`(1)、`3747492842`(1) |
| particle audio | 3 | 11 | `3299228616`(6 boxrandom)、`2419444134`(4)、`2131872317`(1 sphererandom) |
| sound layer | 0 | 0 | — |
| SceneScript `registerAudioBuffers` | 0 | 0 | — |

命中的 combo 值：`AUDIOPROCESSING=3`（left+right）53 处，`=1`（left）1 处，`=2`（right）0 处。particle 侧 `audioprocessingmode=3` 全部 11 处。

粒子命中的组件类型：`sphererandom`/`boxrandom` emitter（7）、`turbulentvelocityrandom` initializer（1）、`vortex` operator（1，该 operator 本身仍是 `L1`）。

四条结论直接决定批次顺序：

1. **stock shake/pulse（30 处、8 个样本）是短期唯一可执行的 effect consumer**。workshop 自定义 shader 的 24 处需要通用 shader 翻译（`L0`，属 S5/P3），本计划不承诺。
2. **固定 13 样本门已覆盖 4 个音频样本**（`2131872317` particle、`2938612768` stock shake+pulse、`2902406982` 与 `3747492842` workshop shader），日常验证不需要每轮跑完整 45 门。但 stock shake/pulse 的主力正门样本 `2134765860`、`2974757317`、`3299228616` 都**不在**固定 13 门内，必须各自建定向门。
3. **`2134765860` 是现成的 stock shake audio 正门候选**：它当前正是 [Effect 执行覆盖表](semantics/effect-execution-coverage.md) 记录的"动态 audio/speed Shake 负门"（历史定向报告 `.codex/scene-shake-20260724/targeted-contract-final/report.json` 中它保持 Shake/stage 0）。接通后由负门转正门，负门角色需同批改由其他样本承担。
4. **sound layer 与 SceneScript audio 在本语料 0 命中**，不进入当前批次；它们的前置（sound IR/player、ECMAScript VM）也都未闭合。

### 1.4 未知项（必须标为推断，不得反向写成官方规则）

| 项 | 状态 |
|---|---|
| 16-bin 的频率边界与分布 | 官方未公开。Web 侧当前用 32 Hz→20 kHz 对数分布，是 Web 合同的工程选择，**不能直接断言等于 Scene 的 16-bin 划分** |
| 频谱幅度归一化与 dB 映射 | 官方未公开。Web 侧 `-80 dB` 下限 + `gain 0.18`/`power 1.35` 是为 Web 兼容调的经验值，**不得套用到 Scene** |
| 平滑/衰减策略 | 官方只说"每个渲染帧更新"。采集实际为 30 Hz，渲染为 60 Hz，是否插值、如何衰减无官方依据 |
| 静音与无信号的确切数值 | 官方文档要求"稳定零输入"，但 WE 是否有本底噪声门未知 |

因此本链路的 `L3` 上限是 **"作者启用、输入、顺序、生命周期、确定性可验证"**；数值/像素 parity 需要 Windows WE golden（V4），当前不具备。

## 2. 依赖顺序

```text
D2 Host frame context ─┐
                       ├─> A0 Audio frame input（D4）
D4 Input snapshots ────┘        │
                                ├─> A1 共享 audio response evaluator（D3/D7）
                                │        │
                                │        ├─> A2 stock Shake AUDIOPROCESSING（D6/D7/D9）
                                │        ├─> A3 stock Pulse backend + AUDIOPROCESSING
                                │        └─> A4 Particle audio response（D9/D10）
                                │
                                └─> A5 SceneScript AudioBuffers（需 D10 VM 前置，本计划不排期）
```

`A0` 是唯一的公共前置；`A2`/`A3`/`A4` 在 `A1` 之后互不阻塞，可按样本收益独立提交。

## 3. 批次计划

### A0 音频 frame 输入底座（已完成，见 §3.1 实际边界）

**目标**：让 Scene 在 host frame 层拿到 16 × left/right 频谱快照，并具备按需采集与零输入。

**代码落点**

| 动作 | 位置 |
|---|---|
| 新增 Scene 频谱分析器（16/32/64 三档 × left/right） | `Core/Playback/SystemAudioSceneSpectrumAnalyzer.swift`（新） |
| `SystemAudioSpectrumService` 增加第三类 consumer | `Core/Playback/SystemAudioSpectrumService.swift`（`setConsumers` 增 `sceneEnabled`、新增 `onSceneLevels`） |
| Scene 采集需求信号与生命周期 | `Core/Playback/WallpaperEngine+SystemAudioLifecycle.swift`、`WallpaperEngine+SystemAudioSpectrum.swift`（`refreshSystemAudioSpectrumCapture` 增 scene 分支） |
| Scene 侧频谱快照类型 | `Core/SteamWorkshopScene/Runtime/SceneAudioSpectrumSnapshot.swift`（新） |
| 折进 frame context | `Core/SteamWorkshopScene/Runtime/SceneFrameContext.swift`（`SceneFrameTiming` 之外新增 host-shared audio 字段） |
| host 每帧读取最新快照 | `Core/SteamWorkshopScene/Runtime/SceneDesktopWallpaperHost.swift`（`renderFrame`） |

**设计约束**

- 频谱是 **host-shared** 输入（与 property 同级），不是 per-surface；多屏共用同一份快照，与 `HostFrameInputs(time, properties, audio, media)` 的目标形态一致。
- 采集 30 Hz、渲染 60 Hz：**首批不插值**，同一快照在两帧间重复使用，快照带 generation。插值/衰减留到有 V3/V4 对照证据后再决定，避免用无依据的经验曲线冒充官方行为。
- 复用现有 `SystemAudioCaptureBuffer.decodedFrame.signedChannels` 的左右声道，不重复建采集链。三档分辨率共用一次 FFT，按 bin 聚合，避免 3× FFT 开销。
- 无 Scene consumer 时**不请求采集**；`playbackPaused`/`screenLocked`/`systemSleeping`/`displaysSleeping` 沿用现有 `captureAllowed` 判断。
- 采集不可用（macOS < 14.2、无权限、设备失败）时输出**稳定全零**并出诊断，不产生假波形，不阻塞渲染。

**验收门**

1. 单元：三档分辨率数组长度、left/right 独立、静音输入全零、非有限值被夹断；确定性合成波形（固定正弦）产出稳定 bin 分布。
2. 生命周期：无 consumer → 不采集；consumer 出现 → 采集启动；stop/switch → 归零且 tap 释放；pause/lock/sleep → 停止采集并推零。
3. 注入：提供 `#if DEBUG` 的可注入快照入口，使后续 A2-A4 的门不依赖真实声音。
4. 不改变任何现有画面：固定 13 样本门 PASS 13/13，指标与 `b86db59` 一致。

**边界**：本批只建输入，不接任何 consumer；等级从 `L0` 升到 `L2`（有 snapshot 与路由，无消费者），**不得写成 audio response 已支持**。

<a id="a0-actual"></a>
#### 3.1 A0 实际交付边界（与上文计划的差异）

实施时对计划做了三处收窄，均为减少与并行批次的耦合、避免预埋无消费者的扩展点：

| 计划 | 实际 | 原因 |
|---|---|---|
| 16/32/64 三档分辨率 | **只做 16 档** | census 显示 effect 侧 stock shader 只用 `g_AudioSpectrum16*`；32/64 仅出现在 workshop 自定义 shader 与 SceneScript `registerAudioBuffers`，两者前置均未闭合。预留档位属于预埋扩展点 |
| 折进 `SceneFrameContext`、host 每帧采样 | **不改 `SceneFrameContext`、不改 `SceneDesktopWallpaperHost`、不改 renderer 签名** | A0 无任何消费者，加一个没人读的字段是预埋。数据流终点定在 `SceneAudioSpectrumInbox`（Scene Runtime 侧），A2 接第一个 consumer 时再决定按帧采样的接法 |
| demand 由 scene 内容自动判定 | **默认关闭，由 `setDemand(_:)` 显式驱动** | `SceneRenderDescriptor` 不携带 `supportsAudioProcessing`，取它要 bump interpretation format；且 `supportsaudioprocessing` 与真实 audio 声明只部分重叠（45 样本中 12 个为 true，与 11 个 effect-audio 样本互有出入），不是可靠的 consumer 信号。A0 无消费者时自动开启采集只会白占系统音频权限 |

**落地位置**

| 文件 | 作用 |
|---|---|
| `Runtime/SceneAudioSpectrum.swift`（新） | `SceneAudioSpectrumSnapshot`（16 band × left/right + generation，非法值归零）与 `SceneAudioSpectrumInbox`（`os_unfair_lock` 保护的最近一帧 + demand 生命周期） |
| `Playback/SystemAudioSceneSpectrumAnalyzer.swift`（新） | 16 频段 FFT，32 Hz→16 kHz 对数划分、-80 dB 归一化，与 Web 分析器完全独立 |
| `Playback/SystemAudioSpectrumService.swift` | 新增第三类 consumer `sceneEnabled` 与 `onSceneLevels`；采集门统一为 `hasActiveConsumer` |
| `Playback/WallpaperEngine+SystemAudioSpectrum.swift` | scene levels 直接发布到 inbox（不经主队列）；`refreshSystemAudioSpectrumCapture` 增 scene 分支并在不采集时归零 |
| `Playback/WallpaperEngine.swift` | 初始化时注册 demand observer（1 行） |
| `script/tests/test_scene_audio_spectrum_input.py`（新） | 20 项门：snapshot 形状/归零、inbox 代际/需求生命周期、analyzer 静音零输入/频段顺序/确定性/fail-closed，以及服务与引擎的静态接线断言 |

**验收结果**：新增门 20/20；`test_scene_frame_context` 8/8、`test_scene_semantics_coverage` 11/11 无回归；代码健康 471 Swift files / 44 locked / 400 行上限通过；签名 Debug 构建 `BUILD SUCCEEDED`。

**A2 必须同批补上的两件事**：consumer 存在性驱动 demand（并在 Scene stop/switch 时撤销），以及按渲染帧采样进入 surface 求值链路。

---

### A1 共享 audio response evaluator

**目标**：把 §1.2 的官方公式实现为**一处**共享求值器，供 effect 与 particle 共用。

**代码落点**：`Core/SteamWorkshopScene/Runtime/SceneAudioResponse.swift`（新，约 80-120 行）

**输入合同**：`(spectrum, mode, frequencyMin, frequencyMax, bounds, exponent, amount) -> Float`

**设计约束**

- 逐字实现 stock 公式，包括 `mode 3` 的 `×2` 分母、`smoothstep`、`saturate(pow(...))` 顺序，不做"等价化简"。
- `frequencyMin > frequencyMax`、越界索引、非有限参数一律 fail closed 返回 0 并诊断，不静默夹断成看似合理的值。
- 默认值不内置：由各 consumer 从自己的 shader annotation / particle schema 提供（pulse `0.5 1.0` vs shake `0.0 1.2` 不同）。
- 单次使用的逻辑不额外包装；这是真实两侧复用，符合建新类型的判据。

**验收门**：三种 mode 的数值表、边界值（min==max、min>max、bounds 反序、exponent 0/4）、静音全零、固定频谱 fixture 的逐值断言。

**边界**：纯函数，不接 GPU，不改任何现有 profile 准入。

---

### A2 stock Shake `AUDIOPROCESSING`（第一个 consumer）

**为什么先做**：Shake 已有完整 exact stock strict backend（flow RG8、phase fallback、ordered chain、真实样本门），音频是其**唯一缺失分支**；23 处命中、6 个样本，是 effect 侧最大单点收益，且改动面被现有 planner 的 fingerprint 准入牢牢框住。

**代码落点**

| 动作 | 位置 |
|---|---|
| 放开 `AUDIOPROCESSING ∈ {1,2,3}` 准入 | `RenderGraph/SceneAuthoredShakePlanner.swift:319`（`validCombos` 当前强制 `== 0`） |
| 解析 `frequencymin`/`frequencymax`/`audioexponent`/`audiobounds`/`audioamount` 常量 | 同文件的 `scalar`/常量提取路径 |
| runtime plan 增加 audio 字段 | Shake runtime plan 结构 |
| MSL 增加 audio 分支 | `Effects/SceneShakeRenderer.swift` / 对应 `.metal` |

**实现要点**

- 官方在 vertex stage 求值。我方 backend 用 fullscreen quad，**在 CPU 侧按帧求值出单个标量后随 uniform 上传**，与官方 `varying` 语义等价（每 draw 常量），并在文档写明这是等价替换而非同址实现。
- `DIRECTION` 分支与音频耦合（`0`: `offset += pulse`；`1`: `offset = 1 - pulse`；`2`: `offset -= pulse`），且 `AUDIOPROCESSING != 0` 时**跳过整段时间驱动 offset 计算**。必须按 shader 原样分支，不能在时间驱动结果上叠加音频。
- 当前 planner 只接受 `DIRECTION == 0`；本批**保持该限制**，`DIRECTION` 1/2 继续 fail closed，避免一次放开两个维度。
- `audioamount` 等常量若带 `user` binding（census 中已出现此形态），本批继续 fail closed，留给后续 live target 批次。

**验收门**

1. 正门：`2134765860` 的 stock shake 层在注入固定频谱下产生与静音不同的位移，逐像素离屏 GPU 断言；静音时与 `AUDIOPROCESSING=0` 路径像素一致。
2. 反门：作者未启用（`=0`）行为完全不变；`DIRECTION != 0`、带 user binding 的 audio 常量、未知 fingerprint 继续整段拒绝。
3. 回归：固定 13 样本门 PASS 13/13（其中 `2938612768` 含 stock shake audio）；`2134765860` 定向门。
4. 覆盖表同批更新：Shake 行的 profile 描述、`2134765860` 从负门改为正门并指定新的负门样本。

---

### A3 stock Pulse backend + `AUDIOPROCESSING`

**目标**：新建 exact stock Pulse strict backend（Pulse 当前 `L1` 无 executor），同批带音频与非音频两条输入路径。

**为什么在 A2 之后**：Pulse 需要从零建 backend，成本高于 A2；但 `pulse.frag` 结构简单（`smoothstep`/`pow`/`ApplyBlending`/alpha 乘），7 处命中、4 个样本，且 `PULSECOLOR`/`PULSEALPHA`/`BLENDMODE` 组合有限。

**边界**

- 只接受完整 authored fingerprint（definition + material + ShaderContract）的 exact stock Pulse。
- `BLENDMODE` 只实现命中的值（census 中为 `9`），其余 fail closed。
- 非音频路径需要 `util/noise` 纹理与 `g_NoiseSpeed`/`g_NoiseAmount`；stock bundle 已有该资源路径，按现有 resolver 消费，缺失则 fail closed。
- 按 [Render Graph 覆盖表第 6 节](semantics/render-graph-shader-coverage.md) 的 consolidation 判据：**这是"下一个新增 strict profile"**，若仍需复制 source capture/uniform 组装/target 绑定/合成提交四段调度代码，则先提取共享 material pass executor 再接本 profile。

**验收门**：正/负/静音/作者关闭四类 + `2974757317` 定向门（完整 45 门内，固定 13 门外）+ 固定 13 门（其中 `2938612768` 含 stock pulse audio）+ 离屏像素门。

---

### A4 Particle audio response

**目标**：让 `sphererandom`/`boxrandom` emitter 与 `turbulentvelocityrandom` initializer 消费同一频谱快照。

**范围**（严格按 census 命中，11 处中 10 处可执行）

| 组件 | 命中 | 样本 | 本批 |
|---|---:|---|---|
| `sphererandom` emitter | 2 | `2131872317`、`2419444134` | ✅ |
| `boxrandom` emitter | 7 | `3299228616`(6)、`2419444134`(1) | ✅ |
| `turbulentvelocityrandom` initializer | 1 | `2419444134` | ✅（`4a17ee6` 已建非音频 profile，audio 分支当前 fail closed） |
| `vortex` operator | 1 | `2419444134` | ❌ operator 本身 `L1`，前置未闭合 |

`2419444134` 是四类组件唯一同时命中的样本，也是 `turbulentvelocityrandom` audio 的唯一正门来源；它不在固定 13 门内，需建定向门。

**代码落点**：`Particles/SceneParticleSimulationSupport.swift`（当前 `audioResponseIgnored` 诊断点）、`Particles/SceneParticleRuntime.swift`、`Particles/SceneParticleChildLifecycle.swift`（当前 `(emitter.audioProcessingMode ?? 0) == 0` 的 child 准入）。

**设计约束**

- 粒子用 **fixed simulation step**，音频快照是 30 Hz 实时输入。必须明确：每个 simulation step 读取**该帧开始时的快照**，同帧内所有 step 用同一值，保证同帧确定性；跨帧变化不做插值。这一条要写进合同，否则 determinism 门无法成立。
- 音频调制的目标量（emitter rate / speed）按官方语义乘算；`audioamount`/`audioexponent`/`audiofrequency`/`audioprocessingbounds` 缺省值取 particle schema 默认，不复用 effect 默认。
- child 粒子的 audio 准入在 parent 闭合前保持 fail closed。

**验收门**

1. 确定性：固定注入频谱 + 固定 seed → 两次运行粒子数/位置完全一致。
2. 静音负门：全零频谱下行为与 `audioprocessingmode=0` 在数值上可区分且稳定（不是"看起来一样"，要有断言）。
3. 正门：`2131872317`（固定 13 门内）的 sphererandom、`3299228616` 的 6 层 boxrandom、`2419444134` 的 turbulentvelocity 各建定向门，emitter 计数/初速随注入频谱变化。
4. `audioResponseIgnored` 诊断在已接通的三类组件上消失，其余组件保留。

<a id="a4-blocked"></a>
#### 3.2 A4 执行被证据缺口阻断（取证结论）

实施时取证发现 **A4 的执行部分当前不具备实现条件**，只交付了声明 IR 的正确性修正。

**粒子与 effect 是两套独立 schema**，不能套用 A1 的求值器：

| | effect | 粒子 |
|---|---|---|
| 启用 | `AUDIOPROCESSING` combo | `audioprocessingmode` |
| 边界 | `audiobounds` | `audioprocessingbounds` |
| 指数 | `audioexponent` | `audioprocessingexponent` |
| 频段 | `frequencymin` / `frequencymax` | `audioprocessingfrequencystart` / `audioprocessingfrequencyend` |
| 幅度 | `audioamount` | **无对应字段** |

45 样本语料中启用 audio 的 11 处粒子组件，字段只出现 `audioprocessingmode`（11）、`audioprocessingbounds`（6）、`audioprocessingfrequencyend`（1），未出现任何 effect 字段名；`mode` 全部为 3。

**证据状况**

| 项 | 证据等级 | 结论 |
|---|---|---|
| 字段名 | 真实样本 + 第三方 parser 交叉验证 | 可用 |
| 默认值 | **仅第三方 parser**，且其自身矛盾——emitter 处为 `bounds 0.8/1.0, exponent 2, frequencyEnd 1`，initializer 处为 `bounds 0.0/1.0, exponent 1, frequencyEnd 15` | 不可用 |
| 频谱聚合公式 | **无**。effect 侧有 shader 源码，粒子侧没有对应源码 | 缺失 |
| 调制目标与方式 | **无**。第三方 `CParticle.cpp` 相关代码是 `float audioAmplitude = 0.0f; // TODO`，`speed *= (1 + amplitude)` 从未真正运行，是未接通的占位 | 缺失 |

官方文档只有一句"rate/shape/speed 等参数可由频谱范围、amount、exponent 调制"，不足以确定调制的是 rate 还是 speed、是乘是加、系数几何。在此基础上实现等于用视觉近似反向定义官方语义，为计划第 1 节与 AGENTS.md 明确禁止。

**本批实际交付**（等级仍为 `L1`，不升 `L3`）

1. 修正 parser 字段名：此前误用 effect 侧的 `audioamount`/`audioexponent`/`audiofrequency`，解析出恒为 nil 的字段，同时漏掉真实存在的 `audioprocessingfrequencyend`——`2131872317` 的该字段被静默丢弃，违反 D0 的 loss-preserving 合同；
2. 三类组件（emitter / turbulent velocity / operator）共用 `SceneParticleAudioResponse` 声明类型，补齐 `exponent` / `frequencyStart` / `frequencyEnd`，且**不内置任何默认值**；
3. operator 的 audio 启用此前不产生任何诊断、会静默按无音频路径模拟，现纳入 `audioResponseIgnored`。

**解除阻断所需**：合法 Windows WE 的固定输入对照（V4 级证据），或官方公开粒子 audio 算法。在此之前 E15 / O29 / I09-audio 保持 `L1`，`audioResponseIgnored` 继续如实报告。

---

### A5 / A6 不排期项

| 项 | 原因 |
|---|---|
| SceneScript `AudioBuffers` | 前置是 ECMAScript VM（`L0`）；本语料 0 命中。A0 的三档快照已为其预留形状，VM 落地后直接消费 |
| Sound layer | 无 sound content IR/player；本语料 0 命中 |
| Media（status/thumbnail/timeline） | 独立链路，与频谱不共用输入，按 B1 Provider Core 排期 |
| workshop 自定义 audio shader（24 处） | 需要通用 shader 翻译（`L0`，S5/P3）。**不得**为 `audio_ring`/`hue_shift`/`kaleidoscope` 等建 effect-name 手写近似 |

## 4. 等级预期

| 能力 | 当前 | A0 后 | A2/A3/A4 后 |
|---|---|---|---|
| Audio frame input | `L0` | `L2` | `L3`（受限：无 Windows 数值 golden） |
| Audio effect consumer | `L0` | `L0` | `L3`（仅 stock shake/pulse exact profile） |
| Audio particle consumer | `L0` | `L0` | `L3`（仅 3 类组件） |
| SceneScript AudioBuffers | `L0` | `L0` | `L0` |

**任何批次都不足以升到 `L4`**：16-bin 频率划分、幅度归一化与平滑策略均无官方公开合同，需 V4 Windows golden。文档中不得把"频谱接通"写成"音频可视化兼容"。

## 5. 验证范围规则

按 AGENTS.md 第 6 条，逐批选择最小充分范围：

| 批次 | 影响面 | 验证范围 |
|---|---|---|
| A0 | 新增 host 输入，不改渲染 | 单元 + 生命周期门 + 固定 13 门（证明无回归） |
| A1 | 纯函数 | 单元数值表 |
| A2 | Shake planner 准入 + renderer | `2134765860` 定向 + 固定 13 门 |
| A3 | 新增 strict profile + 可能的 executor 提取 | `2974757317` 定向 + 固定 13 门；若做 executor 提取则加跑完整 45 门 |
| A4 | 粒子 simulation 公共路径 | `2131872317` + `3299228616` + `2419444134` 定向 + 固定 13 门 |
| 收口 | 全链路 | 完整 45 快照门 + 完整 Scene suite + 代码健康 + 签名构建 |

音频依赖真实声音会破坏确定性，因此**所有自动门一律走 A0 的注入入口**，不依赖播放中的系统音频；真实声音只作为人工 V1/V3 复核。

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 30 Hz 采集 vs 60 Hz 渲染的视觉抖动 | 首批不插值、快照带 generation；若 V1 复核发现明显阶梯，再基于证据决定平滑策略，不预先埋经验曲线 |
| 用 Web 的频段/增益参数套 Scene | A0 的 Scene 分析器与 Web 分析器**分开实现**，不共用归一化常量；文档明确两套合同不互推 |
| 放开 Shake combo 导致既有 strict chain 回归 | `validCombos` 只放开 `AUDIOPROCESSING` 一个键，`DIRECTION`/`NOISE`/`MASK` 维持 `== 0`；固定 13 门逐指标比对 |
| 系统音频权限/设备变化 | 复用现有退避重试与 `SystemAudioCaptureConfigurationMonitor`；Scene 侧只消费快照，失败即全零 |
| 把路径接通写成兼容 | 每批同步更新 [覆盖台账](semantics/coverage-ledger.md)、[Effect 执行覆盖表](semantics/effect-execution-coverage.md)、[粒子组件覆盖表](semantics/particle-component-coverage.md)、[运行输入与属性覆盖表](semantics/runtime-input-property-coverage.md) 的对应行与精确边界 |

## 7. 待补的仓库入口

本计划的 census 结论由一次性只读扫描得出。按 AGENTS.md 第 13 条，A0 实施时必须把它整理为 `script/` 下的通用入口（建议 `script/scene_audio_declaration_census.py`），使"作者启用的 audio 声明分布"成为可复现的长期断言，并纳入语义覆盖测试。
