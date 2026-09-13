# Scene 文档入口

Scene 当前路线是“保留 Swift/Metal 底座，优先执行声明式作者内容，按纵向切片快速得到真实效果”。日常操作只看[开发工作流](development-workflow.md)；本页只做角色导航。

## 开始工作

1. 先看[开发工作流](development-workflow.md)；
2. 查[能力台账](semantics/coverage-ledger.md)和[运行证据索引](semantics/runtime-evidence-current.md)找首断点；
3. 用[兼容执行路线](scene-compatibility-roadmap.md)确认当前 V 轨和完成门；
4. 只有需要理解长期 owner/data flow 或专项语义时，才进入架构和语义手册。

对每个触达范围都要分开写目标合同、当前事实和偏差债务。现有代码与测试只能证明当前实现；它们偏离目标架构时，应在当前纵向 atom 所需范围内主动纠正，而不是新增兼容错误实现的 wrapper、matcher 或专用分支。

当前阶段、顺序和完成门只查[兼容执行路线](scene-compatibility-roadmap.md)；本导航不复制会随批次变化的阶段状态。当前能力宽度和最新证据分别只查能力台账、专项表与运行证据索引。旧 G0–G5 计划、R0–R5 记录和 coverage-first 批次均已退役，只能从[历史索引](../history/README.md)追溯。

## 当前架构与计划

- [Scene 兼容运行时架构](runtime-architecture.md)：官方公开合同、固定客户端静态观察、Mirage clean-room 结构和项目独立方案；规定 identity、失败粒度、compiler/VM/particle/executor 的职责。
- [Scene 兼容执行路线](scene-compatibility-roadmap.md)：唯一现役计划；以全样本验收台账的人工裁决为完成门，按共享首断点集群排序 P0–P5；V0–V5 只保留为能力轨名称。
- [Scene 引擎重构工程计划](engine-refactor-program.md)：派生工程队列，只拥有性能、进程隔离（daemon）、控制面统一、性能预算与公共层的阶段与完成门；与兼容路线冲突时兼容语义合同优先。
- [Scene Runtime 事实架构地图](runtime-as-built-map.md)：代码实际接线的 as-built 参考——加载链、所有权、线程地图、不变量与"改A坏B"雷区表；改 runtime 代码前必读。
- [Scene 当前断点修复队列](scene-open-breakpoint-queue-2026-09-09.md)：按当前证据维护的短执行入口；分开记录现役首断点、人工裁决债务、观察项与 B1–B9 退役状态，不拥有阶段顺序或完成门。
- [Scene 开发工作流](development-workflow.md)：首断点、最小正反门、验证梯度和消融准则；不保存批次状态。
- [Scene 启动响应与按需诊断合同](../architecture/scene-launch-responsiveness-contract.md)：详情默认不诊断、异步 preparation、候选首帧提交、回滚、进度和缓存边界；进入时机仍由唯一现役路线决定。
- [长期技术边界](../architecture/technology-stack-boundaries.md)：Swift/AppKit/Metal、QuickJS-NG、glslang/SPIRV-Cross、跨语言和发布边界。

## 当前事实

- [能力台账](semantics/coverage-ledger.md)：所有系统的当前能力、部分能力、缺失项和待办。
- [运行证据索引](semantics/runtime-evidence-current.md)：当前构建/运行身份、样本结果和证据限制。
- [样本验收台账](semantics/scene-sample-acceptance-ledger.md)：真实样本根全部成员的作者参数形状、隔离运行状态、首断点集群与人工视觉裁决；最终验收门的唯一进度事实，由 `script/scene_sample_acceptance_ledger.py` 从裁决覆盖层生成。
- [样本调试台账](semantics/scene-sample-debug-ledger.md)：逐样本首断点定位与修复批次的运行证据。
- 版本化证据载荷位于被 Git 忽略的本机缓存，只由[运行证据索引](semantics/runtime-evidence-current.md)保存输入、App、报告、manifest 身份与哈希摘要；现役文档不链接或依赖该本机目录。
- [Corpus 能力清单](semantics/scene-corpus-capability-inventory.md)：真实 authored occurrence、family、参数和资源影响面；不表示运行支持。
- [能力依赖图](semantics/capability-dependency-map.md)：公共依赖和不可绕过边界；不是任务队列。
- [Fast Scene Suite 机器合同](../../script/scene_fast_suite.json)：成员、选择状态和 readiness 的唯一事实入口；任何 `selection-required` 成员都不能执行或计为 Suite PASS。

## 专项合同与覆盖

- [语义手册](semantics/README.md)：全部专项文档导航。
- [Effect 执行覆盖](semantics/effect-execution-coverage.md)：官方 Effect taxonomy 各类输入的当前执行通路和缺口。
- [Render Graph / Shader 覆盖](semantics/render-graph-shader-coverage.md)：Program、pass、FBO、command、target 和 shader primitive。
- [SceneScript API 覆盖](semantics/scenescript-api-coverage.md)：语言、module、host API、handle、event 和 timer。
- [Particle 组件覆盖](semantics/particle-component-coverage.md)：General、Emitter、Initializer、Operator、Renderer、Child 和 Control Point。
- [运行输入与属性覆盖](semantics/runtime-input-property-coverage.md)：Timeline、user property、pointer、audio、media 和 provider。
- [高级对象覆盖](semantics/advanced-object-coverage.md)：Puppet、lighting/HDR、3D、RGB、offline 和性能。

## 资料与参考

- [资料来源索引](semantics/source-index.md)：官方、客户端取证、项目 corpus 和第三方证据边界。
- [官方客户端行为研究与一致性验证工作流](semantics/official-client-behavior-research-workflow.md)：公开资料不足时的触发条件、AI 研究卡、clean-room 静态边界和官方黑盒结果门。
- [官方页面映射](semantics/official-page-map.md)：官方 Scene 页面到唯一合同 anchor 的映射。
- [官方客户端静态取证](semantics/client-runtime-static-forensics.md)：Wallpaper Engine 2.8.42 的版本有界职责和顺序，不是公开跨版本 API。
- [MirageWallpaper 静态研究](semantics/miragewallpaper-rendering-reference.md)：固定 revision 的 GPL-3.0 第三方结构对照，不是官方或像素真值。
- [官方公开快照](reference/official/)：版本化 API 声明，只用于 diff/fixture，不进入 App bundle。

官方资料优先。只有公开合同、现有固定客户端证据和当前 corpus 仍不足以解释 producer-to-consumer 链时，才按固定 revision 读取 Mirage；不得把第三方审查变成每个 family 的前置仪式。

## 验证入口

```bash
python3.12 script/verify_scene_change.py --phase <inner|checkpoint|integration|milestone> --base HEAD --path <owned-path> --run
```

开发循环先跑最近 inner 门并尽早进入一个真实代表内容；只有 manifest 已批准的成员才能称 Fast Scene Suite，未批准时必须报告 `representative-content`。checkpoint 再加入未见组合；fixed/full、性能、签名和发布属于 milestone。可见声明必须证明实际执行和与声明相称的画面/事件变化，不能用 compiler success、route、matrix 或非黑像素代替。

历史计划、评审、基线和迁移过程统一见[历史文档索引](../history/README.md)。现役文件不得链接历史材料来决定下一任务。
