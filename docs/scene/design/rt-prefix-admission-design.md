<!-- document-role: active-plan -->
<!-- retirementCondition: 所有 RT 名称解释收敛到准备期唯一入口，旧特判与机器预算同步收缩后归档。 -->

# D8 — RT 名称单点准入与分派

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

WE 来源 render-target 名只在 prepare 阶段解释一次，转换为 typed logical identity；运行期消费者不再各自解析 `_rt_` 字符串。跨 shader schema、material planner 与资源引用，触及 graph/resource 唯一权威和 matcher 机器预算。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialShaderSchema.swift:726` 将 `_rt_` 前缀归为 internal target。
- 同目录 `SceneResolvedMaterialTemplateCompiler.swift:190` 对 FullFrameBuffer 作独立匹配；`Rendering/Bindings/SceneResolvedMaterialTextureResolver+Launch.swift:26` 另有相同名字判断。
- `MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneNamedTextureReference.swift:13` 解析 layer composite，`:31` 保存单独前缀；`Rendering/Dependencies/SceneDependencyRenderPlan+Aggregate.swift:179` 另检查 FullFrameBuffer。
- [Mirage 结构参考](../semantics/miragewallpaper-rendering-reference.md) `:76` 起列出 graph/texture 入口，但此基线没有交接中的六域 59 条裁决文件。render-0…3 在本文只视为待核对方向，不声称已验证完整第三方名称表。

## owner

在既有 texture-reference/material preparation 边界维护一份声明式词汇表，复用现有 typed graph identity 和 SceneNamedTextureReference 的能力。它是编译输入分类，不是资源 registry；allocation、publication 仍由现役资源 owner 决定。

## 方案设计与选型

选择**语义词汇表 + 唯一解析入口**；拒绝“凡 `_rt_` 就是安全 RT”以及多个按前缀堆叠的 resolver。表字段包含精确名称/语法 family、允许上下文、大小写规则、目标类型、producer 要求、clear/preserve 策略及失败类别。

| 输入类 | 命运 | 必须保持的边界 |
|---|---|---|
| 作者显式声明且唯一的 FBO | 保留 authored logical identity | 不因名称相似重命名或改变 history |
| 已证实 FullFrameBuffer 等内建别名 | 改写成既有 typed frame input | 必须绑定相应 frame/publication，不能映射成磁盘路径 |
| 已证实 imageLayerComposite 语法 | 改写为 typed provider reference | 保留 provider ID 与 a/b variant；缺 producer 不造纹理 |
| schema 明确为空/可选占位且没有 producer 语义 | 清空“未绑定引用” | 清空的是 binding，不是清除 RT 像素，不抹掉未知作者输入 |
| 未知/畸形 `_rt_`、冲突声明 | 不准入并保留诊断 token | 不纳入三种成功命运，不能一律清空假装成功 |

第一批仅迁移当前有证据的名字；不从 Mirage 抄完整名称/常量表。大小写保持当前各 public profile 的可观察行为，冲突必须明确回归测试后统一，不能全局 lowercasing 破坏作者 FBO identity。显式作者 FBO 与保留名字冲突时拒绝该 ambiguous binding，禁止 last-writer-wins。

表只做输入归一化，不选视觉算法或 fallback shader。所有下游得到 typed result；动态脚本换纹理是资源 invalidation，在新 token 准入后增量更新，普通帧不重复 parse。D1 组 target 和 [D12](copy-pass-unification-design.md) 的读写端都消费同一 identity。

## fallback / route

未知或跨层 shader default 仅在实际需要该默认值时不准入；已由当前 variant 的候选 readiness 与最终 publication 验证胜出的合法 candidate 不因闲置 default 阻塞。未知 optional binding 局部走已声明的 unavailable/default；required 绑定失败保留该 effect previous-current；非法 identity/path/预算失败 hard reject。迁移先 `observe-only` 比较两种归一化的 typed 结果，仅旧路写产品；随后按 profile `prefer-generic` 到 `generic-only`，不允许两个解析结果各自发布资源。

## 纠正门

- 对公开 family、自有作者 FBO、大小写、空值、畸形后缀、a/b、缺 provider、重名、路径逃逸做输入→typed 结果行为矩阵。
- 将同一个 token 置于 material slot、effect command 和 dependency 引用，结果 identity 必须一致；不同 scene generation 同名不串用。
- 记录 load/invalidation 的解析次数，普通帧零新增分类；源码扫描只用于确认旧特判删除，不作为产品行为通过条件。
- 实施时先记录 `script/scene_source_layout.json` 对应 matcher/registry 家族现值；新入口替换旧入口后同批 ratchet 下调。确有净增长须说明 owner/退役并显式修改预算，本文批准不豁免预算门。

## 退役条件

typed reference 合同入稳定架构，分散解释全部撤权且关闭对应预算卡后归档；新增未知 token 必须走既有判定程序，不能恢复散落特判。
