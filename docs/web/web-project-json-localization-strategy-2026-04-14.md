# MyWallpaperX Web `project.json` 处理与本地化策略

> 状态：现役稳定设计参考。本文规定原始声明、本地派生数据与本地化边界；当前实现、运行证据和未闭合项只查 [Web 现役状态](current-state.md)。
>
> 文档目的：
> 明确 `MyWallpaperX` 对 `Wallpaper Engine` Web 项目的 `project.json` 应如何处理，尤其是：
> 1. 是否直接使用原文件
> 2. 是否允许生成本地运行配置
> 3. 如何在 macOS 侧做本地化与运行时归一化
>
> 更新时间：
> 2026-04-14

---

## 1. 背景判断

根据官方公开文档：

- `Wallpaper Engine` 在导入 Web 项目时会自动创建 `project.json`
- 该文件至少承载：
  - 项目类型
  - 入口文件
  - User Properties
  - localization

但对 `MyWallpaperX` 来说，不能简单得出以下结论：

- 既然它是自动生成的，我们就可以忽略它
- 既然它偏 Windows，我们就应该直接完全重写并替换原文件

这两种理解都过于极端。

---

## 2. 统一结论

`MyWallpaperX` 对 Web `project.json` 的推荐策略是：

1. 原始 `project.json` 仍作为事实输入源保留。
2. `MyWallpaperX` 不应默认直接覆写原始 `project.json`。
3. `MyWallpaperX` 应在 macOS 侧生成自己的“解析结果”和“运行时派生配置”。
4. `MyWallpaperX` 的本地化、属性面板、路径规则、宿主行为，应以我们自己的运行模型为准，而不是完全照搬 Windows 宿主文件的最终呈现方式。
5. 换句话说：
   - 原始 `project.json` 是输入
   - `MyWallpaperX` 的 resolved runtime model 才是执行依据

---

## 3. 为什么不能直接丢弃原始 `project.json`

### 3.1 它承载的是项目声明，不只是缓存

从官方已公开规则可知，`project.json` 至少定义：

- `type`
- `file`
- `general.properties`
- `general.localization`

这些信息都会直接影响：

- 项目是否属于 Web
- HTML 入口文件是谁
- 属性面板如何生成
- 属性默认值与选项如何解释
- localization token 如何解析

所以它不是简单的“临时缓存文件”。

### 3.2 官方没有公开完整字段规范

当前公开文档不足以完整覆盖：

- 全字段集合
- 历史兼容字段
- 隐式编辑器字段
- 样本中的扩展行为字段

如果我们直接重写原文件，很可能会：

- 丢失未知但真实有用的信息
- 破坏后续兼容追踪
- 让排查问题时无法区分“原项目问题”和“我们改写带来的问题”

### 3.3 原文件是最重要的回溯依据

兼容过程中经常需要回答这些问题：

- 作者原始入口是什么
- 原始属性定义是什么
- 原始默认值是什么
- 原始 localization token 是什么
- 当前渲染行为是否与原项目声明一致

如果覆盖原文件，上述问题会失去可信对照基线。

---

## 4. 为什么也不能原样完全照搬它

虽然原始 `project.json` 要保留，但也不能把它直接当成 `MyWallpaperX` 的最终运行配置。

原因如下。

### 4.1 它面向的是 `Wallpaper Engine` Windows 宿主

它的定义前提是：

- 运行在 Windows 生态下
- 运行在 Wallpaper Engine 自己的宿主里
- 使用其自己的 Web runtime、属性面板和本地化体系

而 `MyWallpaperX` 当前是：

- macOS 宿主
- 自己的 Web 宿主与桥接实现
- 自己的 Swift / SwiftUI / AppKit 属性面板承载方式

因此不能假设原始文件的每个表现层语义都应原样照搬。

### 4.2 本地化体系不应完全受原项目显示文本约束

原始 `project.json` 的 localization 更像：

- 项目侧 token 声明
- 供官方宿主解析的翻译字典

`MyWallpaperX` 需要的是：

- 适合 macOS 原生 UI 的展示文本
- 适合我们自己的语言优先级与回退规则
- 适合 Swift 侧属性摘要、诊断、Inspector、面板控件的文本模型

也就是说：

- 我们应读取它的 token 和字典
- 但最终 UI 呈现应由 `MyWallpaperX` 自己决定

### 4.3 路径与运行时注入规则也需要本地归一化

例如：

- `file` 属性的路径使用方式
- 本地目录读取
- 入口解析
- 资源根合成
- dependency-backed shell 的实际运行资源归并

这些都不是单靠原始 `project.json` 文本就能直接解决的。

---

## 5. 推荐的数据分层

`MyWallpaperX` 应采用三层模型。

## 5.1 原始层：Raw Project Layer

保留原始输入：

- 原始 `project.json`
- 原始项目目录
- 原始资源布局
- 原始依赖关系

这一层的职责：

- 作为事实来源
- 作为调试回溯依据
- 作为兼容诊断基线

这一层不应被任意重写。

## 5.2 解析层：Resolved Descriptor Layer

把原始信息解析成 `MyWallpaperX` 自己的内部结构，例如：

- `ResolvedWebProjectDescriptor`
- `ResolvedWebEntry`
- `ResolvedWebPropertySet`
- `ResolvedWebLocalizationMap`
- `ResolvedWebDependencyGraph`

这一层的职责：

- 统一不同样本的字段结构
- 做字段归一化
- 做 fallback
- 区分官方明确字段与推断字段
- 给后续运行层提供稳定输入

## 5.3 运行层：Runtime Model Layer

在播放前，基于解析结果再生成当前会话的运行模型，例如：

- `ResolvedWebRuntimeSession`
- `ResolvedWebRuntimeProperties`
- `ResolvedWebHostBridgePayload`

这一层的职责：

- 绑定当前 macOS 宿主
- 注入本地化后的可展示文本
- 注入最终可运行的属性值
- 注入入口 URL、资源根、目录桥接、FPS、pause 状态等

这一层才是 `MyWallpaperX` 真正执行时依赖的配置层。

---

## 6. 本地化策略

本项目应采用“读取原 token，macOS 侧自建显示模型”的策略。

### 6.1 原则

1. 保留原始 localization token 与字典。
2. 不直接把原始 token 当最终 UI 文本。
3. 不要求原始文件文本表现与 macOS 面板表现完全一致。
4. `MyWallpaperX` 负责把属性标题、选项标题、诊断文案转换为适合本地宿主的显示文本。

### 6.2 建议的文本决策顺序

对于一个属性或选项的显示文本，建议按以下优先级解析：

1. `MyWallpaperX` 本地覆盖文本
2. 原始 `project.json.localization` 中匹配当前语言的 token 文本
3. 英文或默认语言回退
4. 原始 label 本文
5. token 原文作为最后兜底

### 6.3 为什么要允许本地覆盖

因为 macOS 原生界面和官方 Windows 面板在表达层上不同。

典型差异包括：

- 文本长度容忍度不同
- 面板布局与行高不同
- 诊断摘要需要更短文本
- Inspector 可能需要更说明性的名称

因此允许 `MyWallpaperX` 做本地覆盖是合理的，并且不应视为偏离兼容目标。

### 6.4 对兼容性的边界要求

本地化覆盖只应影响：

- 原生展示文本
- 原生摘要文案
- 原生诊断标签

不应影响：

- 属性 key
- combo value
- 运行时真实逻辑值
- 条件表达式引用字段

也就是说：

- 可以改“看起来叫什么”
- 不能改“内部用什么 key 运作”

---

## 7. 路径与宿主相关字段的本地归一化

`project.json` 可以继续作为声明源，但 `MyWallpaperX` 应把这些运行前提本地归一化：

- 入口文件最终解析路径
- 资源根目录
- dependency-backed shell 合成结果
- `file` 属性的本地 URL 形式
- `directory` 属性的运行态目录桥接
- 本地 scheme 映射

### 7.1 统一原则

应优先生成：

- `resolvedEntryURL`
- `resolvedResourceRoot`
- `resolvedDependencyResourceRoots`
- `resolvedPropertyPayload`

而不是尝试把这些结果再回写成一个伪官方 `project.json`。

---

## 8. 什么时候允许生成我们自己的配置文件

可以生成，但要明确它不是原始 `project.json` 的替代品。

### 8.1 允许生成的场景

#### 场景 A：运行时派生配置

为了驱动本地宿主，可以生成例如：

- `resolved-web-runtime.json`
- `web-runtime-session.json`
- 或内存态结构

这类文件或模型的用途是：

- 宿主执行
- 调试
- 诊断
- 崩溃恢复

#### 场景 B：导入缓存

如果读取和解析代价较高，也可以生成本地缓存，例如：

- 归一化属性缓存
- localization 解析缓存
- dependency 合成缓存

#### 场景 C：原文件缺失时的最小补全

当目录明确是 Web 项目，但原始 `project.json` 缺失时，可以考虑生成：

- 最小兼容 project descriptor

但要明确标记：

- 这是 `MyWallpaperX` 推断生成
- 不是作者原始文件

### 8.2 不建议的场景

不建议：

- 读取原项目后直接重写原始 `project.json`
- 删除原始信息，只保留我们自己的版本
- 用我们生成的简化文件覆盖原样本声明

---

## 9. 是否应该使用它原始的 localization 文件

结论是：

- 应读取
- 应参考
- 不应机械照搬为最终 UI

### 9.1 应读取的原因

因为它仍然表达了：

- 作者原始命名意图
- token 与字段对应关系
- 语言版本映射

### 9.2 不应完全照搬的原因

因为 `MyWallpaperX` 需要适配：

- macOS 原生界面承载
- 我们自己的属性面板结构
- Inspector、诊断、摘要卡片等原生展示层

### 9.3 推荐策略

把原始 localization 当作：

- 文本源之一

而不是：

- 唯一且不可改动的最终显示文本

---

## 10. 对 `MyWallpaperX` 代码结构的建议落点

结合当前职责边界，建议这样落：

### 10.1 原始 `project.json` 读取与解析

优先落点：

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebValidation.swift`

职责：

- 识别原始文件
- 建立原始描述
- 定位入口与依赖

### 10.2 属性归一化与本地化

优先落点：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebProperties.swift`

职责：

- 原始 properties 解析
- 显示 token 解析
- 本地文本回退
- 默认值、预设值、运行时注入值归一化

### 10.3 运行时派生模型

优先落点：

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/`

职责：

- 把解析结果转换成可执行的宿主桥接 payload
- 注入 pause、fps、directory、file、audio、media 等运行态信息

### 10.4 原生 UI 展示

优先落点：

- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopItemDetailWebSections.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/UI/SteamWorkshopActiveWebInspectorView.swift`

职责：

- 展示“原始声明”
- 展示“本地归一化结果”
- 展示“当前运行时实际采用的文本与值”

---

## 11. 推荐的实现规则

后续代码实现建议遵守以下规则。

### 规则 1

原始 `project.json` 只读看待，默认不覆盖。

### 规则 2

所有本地化显示文本都走 `MyWallpaperX` 的解析层，不在 UI 层临时拼凑。

### 规则 3

内部逻辑 key 与 UI 显示文本必须分离。

### 规则 4

条件表达式、combo value、property key 必须保持原始语义，不因本地化而变更。

### 规则 5

运行前应生成统一的 resolved runtime model，避免运行过程中零散判断。

### 规则 6

当原始字段缺失或异常时，生成诊断与 fallback，不静默篡改原文件。

---

## 12. 最终策略总结

一句话总结：

> `MyWallpaperX` 不应把 `Wallpaper Engine` 的原始 `project.json` 当成最终可直接执行的 macOS 配置，也不应粗暴替换它；正确做法是保留原始声明，解析出我们自己的本地化与运行时派生模型，再由 macOS 宿主执行。

进一步拆开说：

1. 原文件保留，作为声明源和回溯基线。
2. 我们自己做解析、归一化、本地化和运行时桥接。
3. 我们自己的 UI 文本由 macOS 侧控制，不机械照搬原始 Windows 面板表现。
4. 运行逻辑仍要尊重原始 key、value、入口和属性语义。

这套策略既能保住兼容基线，也能避免把 Windows 宿主表达硬塞进 macOS。
