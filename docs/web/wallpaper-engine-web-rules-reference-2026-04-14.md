# Wallpaper Engine Web 规则参考（2026-04-15）

> 状态：稳定合同。本文只规定 Web 兼容应保持的语义和职责边界；当前源码所有权、运行证据和未闭合项只查 [Web 现役状态](current-state.md)，本文不保存样本数量、实现落点或 PASS 结论。
>
> 目的：沉淀 `MyWallpaperX` 继续开发 Wallpaper Engine Web 支持时需要遵守的稳定规则。
>
> 说明：本文件只保留跨版本仍成立的规则，不展开某次实现状态或历史排障细节。

---

## 1. 核心原则

1. `Wallpaper Engine Web Wallpaper` 是**宿主驱动的本地 Web 项目**，不是普通网页浏览。
2. 兼容判断不能只看“页面能否显示”，还要看：
   - 入口识别
   - 本地资源加载
   - 宿主注入 API
   - 属性系统
   - 生命周期
   - 暂停 / 音频 / 媒体语义
3. Web 链路必须与本地视频播放链路保持解耦。
4. 原始 `project.json` 是声明源，`MyWallpaperX` 的 descriptor / runtime model 是执行依据。

---

## 2. 项目识别与入口规则

### 2.1 目录级项目

Web 壁纸应按“目录级项目”处理：

- HTML 入口
- 同级或子目录资源
- 相对路径引用

不能把 Web 壁纸降级理解为单个 HTML 文件或远程网页。

### 2.2 入口优先级

入口解析应坚持以下优先级：

1. `project.json.file`
2. 与项目根匹配的实际 HTML 入口
3. dependency-backed shell 合成后的有效入口

只要真实入口仍然是 HTML，就不能因为目录里有大量 `.webm` 或图片资源而自动回退到视频链路。

---

## 3. `project.json` 处理规则

### 3.1 原始文件角色

原始 `project.json` 继续作为：

- 项目声明源
- 事实源
- 诊断与回溯依据

不默认覆盖，不静默改写。

### 3.2 稳定分层

项目始终按四层理解：

- `Raw project`：原始输入
- `ResolvedWebProjectDescriptor`：静态解释结果
- `ResolvedWebRuntimeModel`：当前会话运行态
- `ResolvedWebPlaybackContext`：最小播放执行态

---

## 4. User Properties 规则

兼容层应覆盖这些主类型：

- `slider`
- `color`
- `bool/toggle`
- `combo`
- `textinput/text`
- `file`
- `directory`

并继续遵守这些语义：

### 4.1 `combo`

- 页面逻辑优先消费 `value`
- 显示文本与真实值不能混淆

### 4.2 `slider`

- 需保留 fractional / precision 语义
- precision 缺失时默认按 `2` 处理

### 4.3 `file`

- 本地文件路径由宿主注入
- 页面通常仍按本地资源 URL 消费
- 空值 / fallback 语义必须保留

### 4.4 `directory`

必须区分：

- `ondemand`
- `fetchall`

不能把 `directory` 简化成“只是一个目录路径字符串”。

---

## 5. General Properties 规则

宿主必须保留：

- `applyGeneralProperties`
- `fps` 基础值注入
- 旧样本可直接读取 `properties.fps` 的标量语义兼容

这条兼容已被真实样本验证为必要规则，而不是临时猜测。

---

## 6. Display Condition 与 Localization

### 6.1 Display Condition

最低兼容语法范围：

- `&&`
- `||`
- 括号
- `== / === / != / !== / > / >= / < / <=`
- `.value`
- `.text`
- 布尔 / 数字 / 字符串比较

对未完全支持的复杂表达式，应优先 fail-open，避免原生属性 UI 被误隐藏。

### 6.2 Localization

稳定规则：

- 支持 `general.localization.{lang}`
- 按系统语言回退
- 英文回退
- token 缺失时原值回退

---

## 7. 媒体 / 音频 / 暂停规则

宿主应保留以下基础桥接：

- audio listener
- audio spectrum push
- volume / paused
- media state / playback / timeline / thumbnail
- 本地媒体资源通过 local scheme 承载
- 实时频谱统一兼容旧 listener 与新事件监听

兼容验收必须同时覆盖旧 listener 和新事件监听，不能因为其中一条路径可用就省略另一条；某个版本是否已经闭合这些路径只由[现役状态](current-state.md)及其运行证据回答。

---

## 8. plugin / RGB 规则

合同应统一表述为：

- 未接入真实设备时只允许 placeholder 级兼容
- plugin loaded 初始化顺序与状态回放必须保持一致
- 仍不能宣称真实硬件 RGB 能力完整实现

---

## 9. dependency-backed shell 规则

这类样本不能当作普通单项目处理。

实现必须明确区分：

- HTML 入口来自谁
- 资源根来自谁
- 属性定义来自谁
- preset override 来自谁
- 最终运行时如何合成

如果不先完成这层合成，页面即使能打开，也容易出现：

- 背景缺失
- 资源错根
- 查看文件落点错误
- 属性覆盖不生效

---

## 10. 稳定表述边界

### 10.1 合同允许表述

- Web 链路是独立、宿主驱动的运行体系
- 兼容目标不等同于普通网页加载能力
- 核心宿主对齐必须分别验证入口、资源、属性、生命周期和媒体桥接

### 10.2 不能夸大说的

- 不能说已经全面兼容所有 Workshop Web 样本
- 不能说 plugin / RGB / 高负载样本已经完全对齐 Wallpaper Engine

### 10.3 必须单独保留证据的风险面

- 高负载样本稳定性
- 旧生态复杂样本运行语义
- 目录型属性的复杂动态行为
- 更完整的宿主诊断链

---

## 11. 实现职责边界

继续开发时保持以下职责边界：

- 入口、依赖与资源校验属于 Web 项目解析职责
- 属性定义、默认值、用户覆盖与运行时值属于 Web 属性解析职责
- descriptor 到播放请求的转换属于 Web 播放接入职责
- 播放请求到宿主生命周期的转换属于 Web 引擎桥接职责
- 页面注入、兼容脚本和本地资源承载属于 Web 宿主职责

不要把新的 Web 宿主逻辑重新堆回视频主链路或 UI 宿主文件。
