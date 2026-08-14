# SceneScript 内联脚本与 binding target 取证

审查日期：2026-07-25
取证快照：Wallpaper Engine 2.8.42 `projects/defaultprojects`
审查方式：只读静态解析 `scene.json`

> [SceneScript API 覆盖表](scenescript-api-coverage.md) 中「property-bound 实例」一项为 `L0`，缺口写的是「建立 `ScriptSource + owner + target + authoredValue + valueType` IR」。本文用随包工程中的 13 处真实内联脚本，把这五项的**实际 JSON 形态**确定到静态输入层。
>
> 这批工程随正版安装分发，全 docs 此前零引用。

## 1. 结论先行

1. SceneScript 的 binding target **不是**一个独立的引用表达式，而是**脚本源码所在的那个 JSON 位置本身**。`script` 字段出现在哪个属性上，脚本就绑定到哪个属性。
2. 承载 `script` 的是一个 **dynamic value wrapper 对象**，与用户属性绑定复用同一结构。wrapper 中 `script` 与 `value` **同时存在**，`value` 即 `authoredValue`。
3. `value` 的 JSON 类型直接决定 `init(value)` / `update(value)` 的入参类型，其中向量类型以**空格分隔字符串**编码。
4. 13 处样本中有 **5 处不导出 `update`**，只导出 `applyUserProperties`。因此不能假设每个 script binding 都需要每帧求值。
5. binding target 覆盖 5 类位置，最深的一类嵌到 `effects[].passes[].constantshadervalues`，最浅的一类挂在 scene 级 `general` 上。

## 2. 样本清单

`projects/defaultprojects` 共 19 个官方工程，其中 4 个含内联 SceneScript，合计 13 处：

| 工程 | 处数 | 脚本字节数 |
|---|---:|---|
| `razer_bedroom` | 6 | 336-337 |
| `razer_vortex` | 3 | 260 ×3 |
| `dino_run` | 3 | 172 / 701 / 7141 |
| `shimmering_particles` | 1 | 307 |

其余 15 个工程无内联脚本。`corsair_collection` 与 `corsair_o_tron` 中的 `.js` 文件属于 web 类型工程的打包产物，不是 SceneScript。

## 3. dynamic value wrapper 结构

同一个 pass 内可同时出现两种绑定形态（`razer_vortex/objects[0]/effects[0]/passes[0]`）：

| 属性 | wrapper 内容 | 绑定类型 |
|---|---|---|
| `brightness` | `{"user": "ui_editor_properties_brightness", "value": 2.08}` | 用户属性绑定 |
| `colormode` | `{"script": "…", "value": 0}` | SceneScript 绑定 |

可确认：

- `script` 与 `user` 是**同一 wrapper 结构下的两种绑定源**，位置可互换；
- **两种形态都带 `value`**。`value` 是作者在编辑器中保存的静态值；
- 未绑定的属性直接写裸字面量，不套 wrapper。

已观察到的 wrapper 中 `script` 与 `user` 互斥。解析器可分别识别两种键；若同一对象同时出现两者，本地 corpus 没有优先级证据，应诊断并 fail closed，而不是自行规定覆盖顺序。

## 4. 13 处 binding target 全表

| # | 工程 | JSON 路径 | target 类别 | `value` 字面量 | 推定类型 |
|---:|---|---|---|---|---|
| 1-3 | `razer_vortex` | `/objects[0..2]/effects[0]/passes[0]/constantshadervalues/colormode` | shader constant | `0` | Number |
| 4 | `dino_run` | `/objects[1]/origin` | 对象 transform | `"206.33000 57.95600 0.00000"` | Vec3 |
| 5 | `dino_run` | `/objects[22]/visible` | layer 可见性 | `true` | Boolean |
| 6 | `dino_run` | `/objects[33]/effects[0]/visible` | effect 可见性 | `true` | Boolean |
| 7 | `shimmering_particles` | `/general/bloomstrength` | **scene 全局属性** | `1.1200000047683716` | Number |
| 8 | `razer_bedroom` | `/objects[10]/effects[0]/passes[0]/constantshadervalues/color` | shader constant | `"1 0 0"` | Vec3 |
| 9 | `razer_bedroom` | `/objects[11]/…/constantshadervalues/color` | shader constant | `"0.89804 1.00000 0.00000"` | Vec3 |
| 10 | `razer_bedroom` | `/objects[12]/…/constantshadervalues/color` | shader constant | `"1.00000 0.00000 0.00000"` | Vec3 |
| 11 | `razer_bedroom` | `/objects[13]/…/constantshadervalues/color` | shader constant | `"0.00000 1.00000 0.78039"` | Vec3 |
| 12 | `razer_bedroom` | `/objects[14]/…/constantshadervalues/color` | shader constant | `"1 0 0"` | Vec3 |
| 13 | `razer_bedroom` | `/objects[15]/…/constantshadervalues/color` | shader constant | `"1 0 0"` | Vec3 |

归纳为 5 类 target：

| 类别 | 路径模式 | 样本数 |
|---|---|---:|
| shader constant | `objects[N].effects[M].passes[P].constantshadervalues.<name>` | 9 |
| 对象 transform | `objects[N].origin` | 1 |
| layer 可见性 | `objects[N].visible` | 1 |
| effect 可见性 | `objects[N].effects[M].visible` | 1 |
| scene 全局属性 | `general.<name>` | 1 |

`lib.sceneScript.d.ts` 头部说明「通用逻辑通常绑定 Visibility」，样本 #5 正是如此：`dino_run` 把 7141 字节的整套游戏逻辑挂在 `objects[22].visible` 上。

## 5. `authoredValue` 类型编码

`value` 字面量的 JSON 类型即 `valueType`，其中向量用字符串编码：

| 目标类型 | JSON 编码 | 样本 |
|---|---|---|
| Number | JSON number | `0`、`1.1200000047683716` |
| Boolean | JSON bool | `true` |
| Vec3 | **空格分隔字符串** | `"1 0 0"`、`"206.33000 57.95600 0.00000"` |

两条必须处理的细节：

1. **小数位数不统一**。同一 scene 内 `"1 0 0"` 与 `"1.00000 0.00000 0.00000"` 并存（样本 #8 与 #10 同属 `razer_bedroom`）。解析必须容忍任意位数，不能按固定格式匹配。
2. **float32 形态**。`1.1200000047683716` 与 `1.12f` 提升到 double 的值一致，强烈暗示编辑器链路中存在 float32 存储或转换；具体落盘路径仍是 C 级解释。兼容测试应覆盖这种展开值，不能只接受固定小数位数。

字符串向量的形态与 [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) §5.1 的单空格分隔构造/序列化规则一致。两份证据可以建立兼容的往返合同，但静态文件不能证明每个 `scene.json` 字符串都由 `Vec3.toString()` 直接生成。

## 6. 事件覆盖与求值时机

13 处脚本导出的事件：

| 导出组合 | 处数 | 声明指向的候选触发点 |
|---|---:|---|
| 仅 `applyUserProperties` | 5 | 用户属性变更 hook |
| 仅 `update` | 7 | frame update hook |
| `init` + `update` + `cursorDown` + `applyUserProperties` | 1 | 初始化、frame update、指针与属性事件 |

**5 处只导出 `applyUserProperties`** —— 分布在 `razer_vortex` 3 处、`dino_run` 1 处、`shimmering_particles` 1 处。静态导出面没有要求它们进入 frame update 队列；实际触发次数、初次调用和属性批处理顺序仍需 Windows 运行门确认。

这对实现有直接影响：script binding 的调度不能默认把全部实例都作为 `update` consumer。可先按实际导出的事件集建立挂载点，再用 Windows 运行门锁定初次调用、批处理与异常行为。这也与 `lib.sceneScript.d.ts` 头部「PREFER EVENT HOOKS OVER UPDATE」的性能指引一致。

`applyUserProperties` 无返回值写回语义（`d.ts` 只对 `init`/`update` 定义返回值规则），因此这 5 处必须通过直接赋值生效，即声明中的 ASSIGNMENT EXCEPTION 路径。

## 7. `dino_run` 复杂样本的 API 面

样本 #5（7141 字节）是官方提供的最复杂 SceneScript，实现了一个完整的跑酷小游戏。它单个脚本用到 15 个 API：

| 分类 | 调用 |
|---|---|
| 资产 | `engine.registerAsset` |
| 时间 | `engine.frametime` |
| 用户属性 | `engine.userProperties` |
| 输入 | `input.cursorWorldPosition` |
| 持久化 | `localStorage.get`、`localStorage.set`、`localStorage.LOCATION_GLOBAL` |
| 本层 | `thisLayer.origin` |
| 场景查询 | `thisScene.getLayer`、`thisScene.getLayerIndex` |
| 场景变更 | `thisScene.createLayer`、`thisScene.destroyLayer`、`thisScene.sortLayer` |
| 日志 | `console.log` |
| 事件 | `init`、`update`、`cursorDown`、`applyUserProperties` |

价值：这是唯一一份同时覆盖**动态 layer 生命周期**（create/destroy/sort）、**持久化**和**指针事件**的官方样本。[SceneScript API 覆盖表](scenescript-api-coverage.md) 中 `thisScene` layer mutation 与 `ILocalStorage` 均为 `L0`，这份样本可作为实现后的第一个端到端正向门。

`engine.registerAsset` 在该脚本中位于**模块顶层**，符合 `d.ts` 中「MUST be called at the root global level」的约束，可作为该约束的正向样本。

一处不一致值得记录：该脚本的 JSDoc 写 `@param {ICursorEvent}`，但 `lib.sceneScript.d.ts` 中声明的类型名是 `CursorEvent`（class，无 `I` 前缀）。官方样本的 JSDoc 类型名与声明文件不一致，**不要把 JSDoc 类型名当作类型系统依据**。

## 8. 对 MyWallpaperX 的规格与验收门

本文直接证明`ScriptSource IR`的五个官方静态输入字段；MyWallpaperX为精确wrapper shape admission另保留第六个实现字段`wrapperKeys`：

| IR 字段 | 取值来源 |
|---|---|
| `source` | wrapper 的 `script` 字符串，原样保真 |
| `owner` | wrapper 所在的宿主对象（object / effect / pass / scene general） |
| `target` | wrapper 所在的属性 key 及其完整 JSON 路径 |
| `authoredValue` | wrapper 的 `value` |
| `valueType` | 先保留 `value` 的 JSON 类型；字符串是否为向量还需结合 target/property schema，不能只凭空格模式猜测 |
| `wrapperKeys` | 承载`script`的wrapper全部直接key排序后保留，用于精确shape admission；它是项目实现字段，不改变本页官方13处静态取证计数。旧cache缺字段时只允许兼容解码，不得凭缺失字段取得新的执行权 |

另有独立`SceneScriptSourceEvidenceIR`遍历所有string-valued inline `script`，保存原始source、最近owner、完整target path与排序后的wrapper keys。它只提供provenance/conflict rejection，不等于可执行binding；nested/未知wrapper被记录是为了不漏掉writer或冲突，不因此获得target authorization。

建议验收门：

| 门 | 内容 |
|---|---|
| wrapper 判定 | 分别识别 `script`、`user` 与裸字面量；两种绑定可在同一 `constantshadervalues` 内共存，但单个 wrapper 同时含两者时 fail closed |
| 五类 target | 5 类路径均能正确定位 owner 与属性 key，`general` 级不可误挂到 object |
| authoredValue | `"1 0 0"` 与 `"1.00000 0.00000 0.00000"` 解析为同一 Vec3；float32 往返精度 |
| source evidence不越权 | nested/未知路径无损进入source evidence；同一bounded cohort若出现额外writer、owner/path/wrapper不一致则整cohort拒绝，source evidence本身不得生成runtime binding |
| 调度 | 未导出 `update` 的实例不进入每帧队列；`applyUserProperties` 的具体初次/批次触发次数由 Windows 运行门锁定 |
| 回退 | 脚本缺失、解析失败或求值异常时回退到 `authoredValue`，不使属性变为未定义 |

注意本文只确定 target 的**静态形态**，不证明generic求值语义。通用脚本实际执行仍需VM按[SceneScript运行时实现层合同](scenescript-runtime-implementation-contract.md)验证；项目自有bounded typed projection必须另以完整shape、冲突拒绝、runtime接线与隔离证据逐项准入，当前launch-origin子集见[E-BOUNDED-LAUNCH-ORIGIN-TRANSITION](runtime-evidence-index.md#e-bounded-launch-origin-transition)。

## 9. 关联文档

- [SceneScript 运行时实现层合同](scenescript-runtime-implementation-contract.md) —— Vec3 字符串构造与序列化格式
- [SceneScript API 覆盖表](scenescript-api-coverage.md) —— 各 API 当前实现等级
- [场景格式与 Render Graph](scene-format-and-render-graph.md) —— `scene.json` 整体结构
- [资料来源与证据索引](source-index.md) —— 本文来源应登记于此
