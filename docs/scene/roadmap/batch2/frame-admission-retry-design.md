<!-- document-role: active-plan -->
<!-- retirementCondition: 模拟一次消费、独立 surface 提交及恢复门闭合并入稳定架构后归档。 -->

# D10 — 共享模拟与独立屏幕提交

本设计替换旧 all-surface rollback 方案。用户在 2026-10-01 明确选择：暂时没有 drawable 的屏幕不阻塞正常屏幕，恢复后呈现最新状态。approved 只批准边界，不代表运行验收。

## 目标、偏差与 owner

SceneDesktopWallpaperHost 的唯一时钟和 typed evaluation 拥有模拟帧。现役代码在执行 VM 后因任一 surface 无 drawable 回退时钟、事件 watermark 和 timer，但 JS heap 无法回退；下一次调用因而会重复副作用。每屏持有 evaluation 并从任意一屏读取 previous-current 也混淆了共享状态和呈现状态。

本批横切 clock、VM、粒子、Puppet、provider 与提交生命周期，命中设计前置判据 ①②④；不依赖外部视觉语义，不引入新 registry、clock 或 compositor。迁移在现役链 generic-only 完成。

## 决策

1. 每个 cadence 只执行一次共享模拟：冻结输入、执行回调、owner admission、发布 typed snapshot、消费事件/timer/localStorage。surface 的 drawable、target 或 command buffer 不决定已执行 VM 是否重放。局部 callback 失败仍采用现有 owner admission；JS heap 从来不作事务回滚。
2. evaluation authority 从 Surface 移到 scene session；所有屏幕使用同一 frameIndex/generation 和 typed payload。输入的屏幕坐标仍按现有 surface 合同投影，不从任意屏幕猜测共享坐标。
3. 粒子 CPU 状态与 Puppet bone/physics 在模拟阶段更新，与 GPU 上传分离。每屏投影相关的粒子实例仍归本屏，但即使该屏不能呈现也执行相同 cadence，恢复只上传当前结果。模拟不占用 GPU ring slot；上传失败不回退模拟。
4. 每屏 encode/seal/submit 独立完成；未提交候选只取消自身资源。persistent history 保持本屏上次 GPU 完成版本，缺失期间不生成虚构 history。恢复使用最新模拟输入接续该 history，不补播过期 tick 或脚本事件；仅当实际绘制该帧时执行 frame-scoped material function。
5. 共享 video provider 的 pending frame 由 registry 在模拟帧末统一完成；一个屏幕失败不能 discard 另一屏正在使用的版本。sprite/source GPU 更新沿既有 FIFO transaction 与 command-buffer 依赖，各屏及时提交或取消，不留下跨屏未提交前驱。
6. shader/target/publication 身份约束仍在每屏 owner 强制执行。诊断不能参与准入。所有输出失败也不重新执行已消费输入；下一 cadence 更新最新状态。暂停首帧可以进行有界绘制尝试，不能靠恢复 VM watermark 重播 init/event。

## P1-5 职责提取裁决（2026-10-03）

OQ2 的行数观察只能证明热点集中，不能证明人为压线动机。本次以现有数据流和词法生命周期为边界：`renderFrame` 保留 command buffer 准入、全部失败路径的资源 `defer`、terminal encode 和 PreparedFrame 所有权移交；绘制阶段按帧准备、prepass、作者顺序 layer loop、image layer 编码分别提取。循环内 utility `defer` 随完整循环迁移，不能提前到单层 draw 返回前运行。资源只由原方法持有，通过 `inout` 传递实际产生的 lease/pin/batch；stage 的计算结果不是新增 registry、frame clock 或独立提交权威。

PreparedFrame 的 submit/cancel 闭包整体提取到同一 renderer extension，保持 readback、present、arm、commit、didSubmit 顺序和重复 resolve 的一次性语义。prepared 返回之前仍由 `renderFrame` 的既有 `defer` 取消，移交之后由 PreparedFrame 负责。现役 debug-frame-capture-lifecycle 与 persistent-color-output 的 readback、reservation、completion、previous-current 边界不变；不改变任意视觉算法或普通帧诊断策略。

同批的 Variant Compilation 在同一 `SceneResolvedMaterialVariantCache` 内按 authored preparation/analysis、artifact route、binding/finalization 拆分。编译期缓存 key、命中分支、shader expressions、错误码和 owner 路由原样保留；launch profile 归入独立 profiling 职责。阶段结果仅搬运原计算值，不新增 analyzer/matcher 或 fallback 家族。纯结构移动的退出门是两个原文件脱离巨函数，新增阶段各有明确输入输出、没有第二 owner，code-health/布局预算随实际结果收紧。

验证必须运行真实提取代码的 submission/cancel 事件门与实际 variant 编译门，并注入破坏 arm/commit 或提交后取消顺序的反例，证明 oracle 不因同形复制而通过；Debug build 由整合批串行完成。原有源码断言不作为本次正确性证据，拆分涉及的 standalone source list 必须更新。行为测试和构建都不外推为视觉 parity。`bounded-frontend-product-entry` 的调用职责移动以一次性 receipt 绑定旧/新机器合同 SHA、精确一对 from/to owner、全仓调用数和不变调用 token；新增 scope、调用变化或 receipt 提交后改写均拒绝。文件体量遵守统一 1000 行门，不再维护这两个 owner 的 400 行家族例外；职责边界仍由真实调用、状态归属、事务和行为反例检验，不能靠拆扩展或改名证明架构健康。

## 验证与退役

行为门包含：共享脚本 heap 计数加 timer/input/localStorage，在一屏 drawable 缺失、另一屏实际 Metal completion 的多帧序列中每 tick 只消费一次；恢复屏使用最新 typed generation；粒子随机状态/child births 和 Puppet physics 在连续无 drawable 后对应同 cadence 基线；局部失败、所有屏失败、GPU 异步失败、stale completion、暂停与停止释放只影响各自 owner。发布/GPU/next-frame 与脚本 C/Swift 路径分别实测，构建不能替代。

删除旧 host 全屏 rollback、per-surface evaluation 与仅为呈现失败服务的快照；保留真正有调用方的局部 owner rollback。完成以上行为门、Debug 构建和结构基线审查后，将稳定合同留在 runtime-architecture，本文归档。外部 Agent 的改动在本隔离树内不覆盖，用户通知后才进行集成。

### 独立编译消费者的准入词汇表职责

2026-10-03 P1-5整合发现：TemplateCompiler依赖SceneRenderTargetVocabulary，但该独立准入owner与完整shader schema共文件，最小census/template harness被迫遗漏它或拉入整个shader compiler。批准把此enum连同既有注释原字节移到同目录SceneRenderTargetVocabulary.swift；不改dispatch、case或参数，不新增类型与产品依赖边。五问中命中准备主链职责边界，未触碰用户数据/外部取证，仍归现役Compilation owner。消费者通过源集合纳入真实词汇表；用原Template/census行为门、源码字节保存和Debug构建验收。退役条件是独立源集合与消费者全部落地，不能以编译替身复制词汇表。
