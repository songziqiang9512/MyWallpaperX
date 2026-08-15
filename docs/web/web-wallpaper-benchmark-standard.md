# Web 壁纸运行能力评测标准

<!-- document-role: stable-contract -->

> 状态：现役长期评测合同。本文规定如何证明，不记录当前 HEAD 是否 PASS；当前证据状态只查 [Web 现役状态](current-state.md)，带日期结果只作历史基线。

本文定义 MyWallpaperX Web 模块的长期评测口径。目标不是判断单个样本“能不能打开”，而是把真实运行能力拆成稳定的能力维度，持续发现短板、回归和样本自身问题。

## 评测对象

- 当前 Debug App 的真实 Web 壁纸播放链路。
- 创意工坊 Web 样本，包括：
  - `project.json.type = web` 或 `Web` 的样本；
  - `project.json.file` 指向 HTML 的样本；
  - dependency-backed Web shell 样本。
- 默认不修改样本文件，只读取项目结构、启动 App、采集日志和可选截图。

## 核心证据

评测工具主要读取 App 在 `--mwx-log-web-diagnostics` 下输出的运行诊断：

- `runtime.profile`：样本进入 Web runtime，并确定运行 profile。
- `host.ready`：宿主完成属性回放、输入转发和可播放态建立。
- `navigation.finish`：WebKit 完成导航。
- `resource.*` / `local-resource-*` / `loopback.resource.*`：资源读取、映射和跨源访问问题。
- `properties.*`：Wallpaper Engine Web 属性桥接状态。
- `media.*` / `audio.*`：媒体与音频能力状态。声明 `audio-spectrum` 的样本还必须有 listener 注册、128-bin 分发和连续帧变化证据。
- `pointer.*` / `wheel.*`：输入转发状态。
- `webSnapshot[...]`：WebView、页面 Canvas 或当前进程独立窗口的画面亮度证据。运动比较只允许使用同一来源的非空前后帧。

## 证据身份与污染防护

- 正式样本运行只接受签名有效的 `.app` 内可执行文件。工具在运行前严格验签，将 App 复制到本轮独立 runtime bundle，并在运行结束后复核 bundle ID、Team ID、CDHash、版本和可执行文件 SHA-256；身份写入 `report.json`。
- 显式输出目录必须为空；自动输出目录每轮新建。样本评分只接受本次日志声明、真实存在且解析后仍位于当前样本报告目录内的快照，不再扫描目录接纳未记录的旧文件。
- ScreenCaptureKit 当前进程窗口截图用于证明实际窗口合成结果；WebView 和 Canvas 快照继续提供渲染源交叉证据。窗口采集失败必须保留结构化阶段/错误/重试诊断，不能静默改用旧截图。
- `--screenshot` 生成的系统整屏截图只供人工复核；只有采集成功且存在非黑像素时才写入报告，不能替代样本内视觉评分证据。

## 评分维度

总分 100 分。每个样本独立评分，再聚合为批次平均分。

| 维度 | 权重 | 通过标准 |
| --- | ---: | --- |
| 启动与分类 | 15 | App 找到样本，按 Web 类型启动，并产出 `runtime.profile`。 |
| 宿主就绪与启动性能 | 20 | 产出 `host.ready`，且在评测窗口内没有宿主失败或崩溃。 |
| 导航生命周期 | 15 | 产出 `navigation.finish`；若只有 `host.ready`，记为可播放但导航证据不足。 |
| 本地资源兼容 | 15 | 没有宿主侧资源映射错误；缺失可选资源、远端失败单独降级归因。 |
| 属性桥接 | 15 | 默认属性和运行时属性回放无阻断错误。 |
| 媒体与音频 | 8 | 无 `media.error`、`media.play.error`、`audio.resume.error` 等媒体阻断。 |
| 输入交互 | 7 | 无 pointer/wheel 派发错误；若执行了交互冒烟，应看到对应事件。 |
| 画面输出 | 5 | 有非空白快照证据；普通画面按覆盖率、方差和色彩判断，OLED 星空等稀疏暗色画面还需满足亮点数量、对比度和峰值亮度；未采集快照时只给弱证据分。 |

除总分外，报告还输出 evidence coverage。某些能力没有被当前样本或当前命令覆盖时，不把结论伪装成强验证。

## 短板归因

评测工具按以下类别归因：

- `launch`：样本未找到、App 未启动、未进入 Web 链路。
- `host_runtime`：缺 `host.ready`、宿主失败、进程异常退出。
- `navigation`：导航失败或评测窗口内缺 `navigation.finish`。
- `resource_mapping`：本地 scheme / loopback / 文件映射错误。
- `sample_resource`：样本自身缺文件、远端依赖失败、可选探测资源缺失。
- `properties`：属性桥接错误、属性回放跳过或 partial fallback。
- `media_audio`：媒体、音频播放或 AudioContext 恢复问题。
- `interaction`：鼠标、滚轮、右键等输入派发问题。
- `visual_output`：黑屏、透明、无首帧或缺少画面证据。
- `animation`：声明动态能力但没有同源双帧变化证据，或变化低于门限。
- `performance`：启动慢、ready 慢、导航慢。

## 推荐使用方式

1. 每次 Web runtime 改动后，先跑 3-6 个代表样本。
2. 影响公共解析、资源映射、属性桥接或输入转发时，再跑全量 Web 样本。
3. 保留每次报告目录，把新的 `report.json` 与上一次报告做 baseline 对比。
4. 对低分样本先看归因类别，再决定是否修宿主、补诊断，还是记录为样本自身问题。

## 验收线

- 实际执行门以对应 matrix JSON 中的批次阈值、单样本最低等级、最低 coverage、允许例外和禁止短板为准；本文不复制一份可能漂移的数值作为执行真相。
- 默认代表矩阵、34 项完整基线和外部代表矩阵承担不同层级的验证职责，不因第三方 fixture 缺失而互相替代或合并。
- 新改动不得让任一样本的总分下降 10 分以上，除非报告能证明旧分数是误判。
- `host.ready` 覆盖率应接近 100%；缺失时优先排查宿主链路。
- Debug 音频 fixture 只证明桥接、布局和变化，不替代真实系统音频相关性、设备切换和静音恢复测试，也不能单独证明最终画面幅度合理。绝对响应由 `script/tests/test_system_audio_spectrum.py` 锁定，样本视觉证据和当前结论以 Web / Scene 现役状态文档为准。
