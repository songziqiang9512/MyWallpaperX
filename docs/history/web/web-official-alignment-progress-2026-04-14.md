# Wallpaper Engine Web 官方对齐进度备注（2026-04-15）

> **历史证据 — 非现役入口**
>
> 本文仅保存 2026-04-15 的第一轮官方对齐进度；其中“当前”“已完成”、范围、路径和下一步均不得作为现役能力或任务入口。
>
> 现役能力、所有权、证据和剩余工作只查 [Web 现役状态](../../web/current-state.md)；全部历史材料见[历史索引](../README.md)。

> 状态：历史进度快照，不是当前能力、证据或任务入口。本文所有“当前”“已完成”只对 2026-04-15 批次负责；现役结论只查 [Web 现役状态](../../web/current-state.md)。
>
> 目的：记录 `MyWallpaperX` 当前对 `Wallpaper Engine Web Wallpaper` 的已落地能力、已确认结论和剩余缺口。
>
> 范围：只保留仍然指导当前实现的内容，不再混入已经回滚或已过时的试验路线。

---

## 1. 当前总状态

当前状态应统一表述为：

> `MyWallpaperX` 已完成 Wallpaper Engine Web 第一轮核心宿主对齐，已经不是“普通网页能打开”的阶段；但仍未达到“全面兼容所有 Workshop Web 样本”。

当前主线已经稳定在：

- Web 与本地视频播放链路分离
- `project.json -> descriptor -> runtime model -> playback context` 四层结构
- 单宿主 Web 承载
- 本地 scheme 资源加载
- User Properties / General Properties / audio / media / pause 等基础桥接
- 静态分析缓存与最小执行态缓存拆分
- 单宿主默认透传 + 命中后瞬时接管的交互策略
- Web 频谱统一兼容入口（新事件 + 旧 listener）

---

## 2. 已确认落地的能力

### 2.1 项目识别与入口

已完成：

- `.web` 内容识别
- `project.json.file` 入口定位
- 非 `index.html` 入口支持
- Web 与视频链路解耦
- dependency-backed shell 第一轮识别与资源绑定前置解释

结论：

- Web 项目已按“目录级 HTML 项目”处理
- 不能再把当前链路视为普通网页加载器

### 2.2 属性系统

已完成：

- `slider`
- `color`
- `toggle/bool`
- `combo`
- `text`
- `file`
- `directory`
- label / group 等展示型定义

并已具备：

- baseline + preset override + user override 合并
- file / directory 本地路径解析
- localization 回退
- display condition 第一轮求值
- fractional slider / precision 对齐

### 2.3 General Properties

已完成：

- `applyGeneralProperties` 注入
- `fps` 基础值注入
- 旧样本直接读取 `properties.fps` 的标量语义兼容

已确认结论：

- 样本 `1748506393` 的交互回归根因不是输入链，而是 `generalProperties` 语义回归
- 兼容层补回标量语义后，该样本恢复正常

### 2.4 媒体 / 音频 / 暂停桥接

已完成：

- audio listener 注册与频谱分发第一轮
- media state / timeline / thumbnail / playback listener 基础桥接
- pause / volume 基础桥接
- 本地媒体 URL 重写到宿主 local scheme
- 实时频谱统一走 `__myWallpaperPushAudioSpectrum(...)`
- 旧式 `wallpaperRegisterAudioListener(...)` 与新式事件监听同时兼容
- Web 专属频谱节奏/平滑已收敛出当前可用基线

结论：

- 当前已具备基础桥接，不再是“完全没有音频/媒体宿主接口”
- `884307090` 类旧音频可视化样本已从“只在切焦点时动”推进到“持续响应，体感接近正常”
- 剩余问题更偏高负载、旧生态样本时序与稳定性

### 2.5 plugin / RGB

当前状态：

- `wallpaperPluginListener`
- `wpPlugins.led`
- `wpPlugins.rgb`
- plugin loaded 顺序与回放已补齐

结论：

- 当前仍应视为 `placeholder` 兼容
- 不能表述为真实硬件能力已完整实现

### 2.6 解释层与运行层

当前已落地：

- `ResolvedWebProjectDescriptor`
- `ResolvedWebRuntimeModel`
- `ResolvedWebPlaybackContext`
- analysis cache / runtime cache 双缓存拆分

当前职责已经清晰：

- descriptor：静态解释结果
- runtime model：当前会话的动态合成结果
- playback context：最小播放执行态

---

## 3. 当前已确认的兼容结论

### 3.1 不能再说“只是网页能打开”

因为当前已经实际覆盖：

- 本地入口识别
- 宿主专用属性系统
- General Properties
- localization
- display condition
- audio / media / pause 基础桥接
- dependency shell 第一轮合成

### 3.2 也不能宣称“全面兼容”

当前仍未完成的部分主要是：

- 高负载样本的稳定性与止损
- 旧生态样本更细的运行语义
- 更完整的目录型属性动态行为
- placeholder 宿主下的复杂桌面交互边界
- 更系统的宿主内诊断落点

---

## 4. 当前仍需继续推进的缺口

### 4.1 高负载样本

重点仍在：

- `921617616`
- `884307090`
- `1081733658`
- `1396475780`

这些问题更像：

- 运行负载
- 媒体/脚本时序
- 宿主稳定性

而不是入口识别或基础桥接缺失。

### 4.2 目录与本地媒体细节

仍需继续验证：

- `directory` 的 `ondemand / fetchall` 在旧样本里的真实体感
- 大目录下的节流与资源控制
- 本地媒体缺失、替换、刷新后的页面响应

### 4.3 复杂交互样本

当前结论：

- 简单交互样本已可覆盖一批
- 复杂 hover / drag / pointer 语义仍受当前宿主边界限制
- 当前主线是单宿主默认透传 + 命中后瞬时接管，不再继续扩散“双宿主/长期原生输入态”方案
- 不应再把这个问题写成“另起一套原生输入宿主”的已落地方案

### 4.4 诊断链

仍需加强：

- 宿主内本地诊断落点
- 更稳定的播放阶段观测点
- 高负载样本首帧 / ready / media ready 诊断

### 4.5 Web 频谱体感调优

当前结论：

- `884307090` 类旧样本的主断点已经不再是“listener 收不到持续更新”，而是体感参数调优
- 当前可用基线已经收敛为：
  - 频谱实时推送统一走 `__myWallpaperPushAudioSpectrum(...)`
  - Web 频谱恢复到 `30Hz`
  - 保留一层 Web 专属轻量时间平滑
- 后续如再调优，优先只微调 Web 专属平滑，不建议再次显著下调 Web 频谱节奏

---

## 5. 当前建议的对外表述

推荐统一表述：

> `MyWallpaperX` 当前已完成 Wallpaper Engine Web 官方公开规则的第一轮核心对齐，重点剩余问题已从“基础接口缺失”收敛为“复杂样本的高负载、运行稳定性和部分旧生态交互语义”。

不建议再使用：

- “已经全面兼容”
- “现在只是能打开网页”

---

## 6. 当前保留的文档分工

建议把这几份文档视为当前主参考：

- `docs/web/wallpaper-engine-web-rules-reference-2026-04-14.md`
- `docs/web/web-project-json-runtime-model-plan-2026-04-14.md`
- `docs/web/web-official-alignment-progress-2026-04-14.md`

其中：

- 规则参考：记录官方规则与本项目的稳定解释
- runtime model：记录当前解析层/运行层设计
- progress：记录当前真实落地状态与剩余缺口
