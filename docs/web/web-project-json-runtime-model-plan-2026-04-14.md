# Web `project.json` 解析层 / 运行模型方案（2026-04-15）

> 状态：现役稳定合同；当前代码仍使用本文的 project/descriptor/runtime/context 分层。能力、证据与剩余缺口只查 [Web 现役状态](current-state.md)。
>
> 目的：保留当前 Web 解析层与运行层设计中仍然有效的最小共识，作为后续实现的稳定参考。

---

## 1. 统一结论

当前应坚持：

- 原始 `project.json` = 声明源 / 事实源
- `ResolvedWebProjectDescriptor` = 静态解释结果
- `ResolvedWebRuntimeModel` = 当前会话的动态运行结果
- `ResolvedWebPlaybackContext` = 最小播放执行态

不采用：

- 覆盖原始 `project.json`
- 以本地重写文件替代原始项目语义
- 在播放前重复做整套重型解释

---

## 2. 当前三层职责

### 2.1 Raw Project Layer

职责：

- 保留原始 `project.json`
- 保留原始目录与资源布局
- 作为诊断与回溯依据

### 2.2 Descriptor Layer

职责：

- 解析入口来源
- 解析 property definitions 与 property source
- 前置计算 preset override
- 前置计算资源绑定
- 前置生成 baseline visible / precondition / static summary
- 承载静态宿主能力快照与风险标记

### 2.3 Runtime Model Layer

职责：

- 合并 user overrides
- 生成当前 effective values
- 计算当前 visible properties / options
- 绑定当前文件与目录资源
- 输出 property payload / diagnostics snapshot

### 2.4 Playback Context

职责：

- 只承载播放真正必需的最小执行态
- 当前重点保留：
  - `effectiveEntryURL`
  - `effectiveRootURL`
  - `propertyPayloadJSON`
  - `generalPropertiesPayloadJSON`（如当前播放链需要）
  - 频谱/暂停/音量等运行时桥接所依赖的最小上下文

---

## 3. 当前已落地的关键对象

### 3.1 `ResolvedWebProjectDescriptor`

当前已承载的核心信息：

- 入口解析结果
- property source / definitions
- `defaultValueMap`
- `presetOverrideMap`
- `presetResourceBindingsByKey`
- `baselineVisiblePropertyKeys`
- `baselineVisibleOptionsByKey`
- `baselinePreconditionStates`
- `hostCapabilitySnapshot`
- `staticContentSummary`
- `runtimeRiskFlags`

### 3.2 `ResolvedWebRuntimeModel`

当前已承载的核心信息：

- 当前 user overrides
- 当前 effective values
- 当前 visible properties / options
- 当前 resource bindings
- 当前 preconditions
- property payload JSON
- validation report / diagnostics snapshot

### 3.3 `ResolvedWebPlaybackContext`

当前定位：

- 更偏播放执行层
- 不承载重型展示或诊断字段

---

## 4. 当前方案的价值

这套模型当前主要解决三类问题：

1. **避免重复解释**
   - detail / validation / playback 不必各自从原始 `project.json` 重新推导
2. **把静态问题前置**
   - dependency shell
   - preset 绑定
   - baseline visible
   - baseline preconditions
3. **把播放态收缩到最小执行输入**
   - 让宿主播放链更轻，不再背负大块展示性字段

---

## 5. 当前仍应继续坚持的方向

### 5.1 静态前置，动态最小化

继续优先把这些内容前置到 descriptor / analysis cache：

- 入口来源
- 依赖壳资源绑定
- baseline visible
- baseline preconditions
- 静态风险标记

而把播放执行层保持在最小范围。

### 5.2 validation / detail 优先消费 descriptor / runtime model

后续代码继续收口时，应优先：

- 少做二次解析
- 多复用 descriptor / runtime model

### 5.3 不把 descriptor 做成第二份原始 `project.json`

descriptor 的职责是：

- 解释结果
- 宿主归一化结果
- 可复用静态摘要

而不是原文件的镜像副本。

---

## 6. 当前不再推荐保留的做法

不再推荐：

- 为文档目的重复列出大量尚未落地的理想对象树
- 把未来可能的字段设计写得过细但实际代码并未采用
- 把“理论上想要的运行模型”与“当前已落地模型”混写在一起

后续如继续更新，应优先记录：

- 当前真实已落地字段
- 当前仍需前置的最小语义
- 当前哪些消费方仍在绕过 descriptor / runtime model

---

## 7. 当前文档分工建议

- `docs/web/wallpaper-engine-web-rules-reference-2026-04-14.md`
  - 记录官方规则与项目内稳定解释
- `docs/web/web-project-json-runtime-model-plan-2026-04-14.md`
  - 记录当前解析层 / 运行层主方案
- `docs/web/web-official-alignment-progress-2026-04-14.md`
  - 记录当前落地状态与剩余缺口

详细设计如果后续继续保留，应只服务实现，不再单独维护一份大量重复的长篇说明。
