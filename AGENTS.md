# MyWallpaperX 开发规则

本文件只保存会改变实现、验证、提交或工作区安全的长期约束。Scene 的日常操作、验证梯度和消融规则统一见 [`docs/scene/development-workflow.md`](docs/scene/development-workflow.md)；当前能力和运行事实不写在这里。

## 1. 工作区安全

- 开工先运行 `git status --short --branch --untracked-files=all`，划定本批 owned paths；保留其他改动。禁止 `git reset --hard`、`git checkout --`、`git clean`、`git add -A` 和宽泛覆盖操作。
- 只读审查不得编辑、构建、生成缓存、暂存或提交。实现任务按风险完成最小可验证结果；未授权不提交、不推送。
- 真实 Scene 样本根 `~/Movies/MyWallpaperX/创意工坊/Scene` 只读。benchmark、属性注入、缓存、staged App、DerivedData 和临时 `HOME` 使用隔离副本/目录，并在报告后清理可重建产物。
- 只改当前目标的完整职责边界。删除历史材料、唯一失败现场或归属不明的生成物前列出精确清单并取得确认；可重建缓存也必须按精确清单处理，禁止递归清理仓库根、`.codex` 根或真实样本根。

## 2. 事实与目标

- 当前事实按以下顺序核对：当前代码和可复现运行证据 → 本文 → 长期架构合同 → 专题当前表/路线 → 历史证据。目标合同按官方作者行为、本文和长期架构裁决；旧代码、测试、目录和历史报告不能把错误现状升级为规范。
- Scene 资料按 [`source-index.md`](docs/scene/semantics/source-index.md) 的 named source taxonomy 分类，类别清单只由该索引维护；历史摘要、旧计划本身不构成当前事实，也本身不构成上下文污染。
- Scene 当前入口是：[`docs/README.md`](docs/README.md) → [`docs/scene/development-workflow.md`](docs/scene/development-workflow.md) → [架构](docs/scene/runtime-architecture.md)、[路线](docs/scene/scene-compatibility-roadmap.md)、[能力台账](docs/scene/semantics/coverage-ledger.md)、[运行证据](docs/scene/semantics/runtime-evidence-current.md)。不要从历史计划或截图开始任务。
- 目标主链只有一条：`authored data -> prepared Program/graph/resources -> typed frame update -> Metal encode -> unique compositor/output`。不得按 sample/layer/path/hash/screenshot 选择视觉算法，不得新增第二套 property、provider、clock、graph、resource registry 或 compositor。
- 任何偏差都写清目标合同、当前事实、owner、fallback/route、纠正门和退役条件；触达旧 owner 时优先在当前纵向结果内纠偏，不能为兼容错误实现继续扩张 matcher、wrapper、专用分支或测试预期。

## 3. Scene 硬边界

- 普通帧不得重新解析、编译、建图、整图序列化/哈希或构造完整 observation；解析、reflection、ABI/target 检查、Program/graph/pipeline preparation 只在 load、generation 或明确 invalidation 执行。
- identity、作者顺序、frame state、资源/target/publication/completion 生命周期和最终输出各只有一个产品权威。迁移 owner 必须显式为 `observe-only`、`prefer-generic`、`generic-only` 或 `disable-generic`；不得静默双执行。
- 路径逃逸、非法 GPU range、target hazard/ABI 不匹配、stale handle、generation/epoch/publication/lifecycle 破坏、VM/compiler timeout、OOM 或预算超限硬拒绝最小 unsafe unit。shader/pass、optional provider、脚本 API、粒子组件等视觉失败默认局部 fail soft，保留 previous-current 和安全 compositor 输出。
- 完整诊断、hash、route/fallback 聚合、截图和 corpus instrumentation 只在主动诊断、验证或 milestone；不得成为普通播放的提交前置。`recognized`、`wired`、compile success、route 数、非黑、matrix PASS 和单样本通过不能单独宣称视觉兼容、性能完成或官方 parity。
- 真实官方行为研究只有在公开资料、现有黑盒和合法 corpus 无法回答会阻塞当前纵向切片的可观察语义时才启动，并遵守 [`official-client-behavior-research-workflow.md`](docs/scene/semantics/official-client-behavior-research-workflow.md) 的 clean-room 隔离；实现上下文不得消费私有伪代码、地址、shader、payload、资产或算法表达。
- 实现上下文偶遇研究原始表达时，若能够明确证明与当前切片无关则隔离且不传播；否则立即停止该职责的产品写入，无法判断是否重叠时按重叠处理。

## 4. 验证、提交与报告

- 门禁服从实际失败半径：inner → checkpoint → integration → milestone。模块必须显式选择；`--scope scene` 不等于全量，full/fixed/签名/发布只在风险确实跨越时运行。
- Swift 产品改动在 checkpoint 再 Debug build；GPU/VM/资源/生命周期/可见变化使用隔离代表内容；可见结论必须有实际执行身份、completion、publication、terminal compositor、next-frame 及相称 ROI/事件证据。
- 一个批次交付一个可见或可执行结果。提交只包含一个职责批次，信息写明问题、根因、实际结果和验证；禁止宽泛暂存。
- `.codex` 是可重建工作区，不是源码或知识库；`docs/scene/evidence/` 是仓库忽略的本机证据缓存。正式工具进 `script/`，测试进 `script/tests/`，一次性文件进 `/private/tmp`。最终报告明确实际改动、验证结果、跳过/未验证边界、工作区和提交状态。
