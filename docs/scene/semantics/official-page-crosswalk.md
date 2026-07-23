# Wallpaper Engine Scene 官方页面能力映射

> 状态：现役；与 [`official-page-catalog.md`](official-page-catalog.md) 配套使用
>
> 最近核对：2026-07-23
>
> 官方文档快照：179 个 `/en/scene/` 页面，另有 `lib.sceneScript.d.ts` v2.8

本表回答“16 个官方目录组分别路由到哪张专项能力表”。它是分组导航，不是逐页证明；179 页的唯一 URL、分类、稳定合同 anchor 和产品决策以 [官方页面逐页表](official-page-map.md) 为准。目录负责入口无遗漏，逐页表负责机械完整性，专项覆盖表负责当前等级、代码证据和下一验收门。

## 1. 分类口径

| 分类 | 含义 | 对播放器的要求 |
|---|---|---|
| `runtime-required` | 作者可见能力会进入壁纸播放结果 | 必须有 IR、作者启用条件、执行或 fail-closed、测试证据 |
| `ingest-required` | 编辑器产物、资源或发布流程会影响输入 | 必须安全读取导出结果；不复刻编辑器 UI |
| `editor-only` | 只指导作者在 Wallpaper Engine 编辑器内制作内容 | 记录为产品不适用，不实现编辑器工作流 |
| `platform-decision` | Windows 集成、设备或移动端策略 | 明确 macOS 支持、替代或关闭策略 |
| `research-boundary` | 官方只公开作者合同，未公开私有格式或算法 | 不从截图反推为官方定义；使用合法样本和 golden 补证 |

“页面已映射”不等于“能力已实现”。所有执行结论仍按 `L0` 到 `L4` 覆盖等级记录。

## 2. 16 组路由总表

| 官方目录集合 | 页面数 | 分类 | 能力落点 | 当前处理结论 |
|---|---:|---|---|---|
| Overview 与入门 | 6 | `ingest-required` + `editor-only` | [格式与 Render Graph](scene-format-and-render-graph.md)、[开发计划](../scene-capability-development-plan-2026-07-22.md) | 读取导出产物；不复刻编辑、发布 UI |
| Assets | 2 | `ingest-required` + `editor-only` | [格式与 Render Graph](scene-format-and-render-graph.md)、[来源索引](source-index.md) | 资源身份和依赖属于 runtime；资产分享 UI 不适用 |
| Image Preparation | 3 | `editor-only` | [高级对象覆盖表](advanced-object-coverage.md) | 只影响作者素材制作；播放器消费最终图像/puppet 产物 |
| Effects | 48 | `runtime-required` + `research-boundary` | [45 类 Effect 全表](effects-reference.md)、[总台账](coverage-ledger.md)、[Graph/Shader 覆盖表](render-graph-shader-coverage.md) | 45 类逐项记账；私有 shader 算法不冒充公开合同 |
| Parallax | 3 | `runtime-required` | [格式与 Render Graph](scene-format-and-render-graph.md)、[运行输入与属性覆盖表](runtime-input-property-coverage.md) | Camera 与 Depth Parallax 分离，作者未启用时不得默认套用 |
| Particles | 10 | `runtime-required` | [粒子组件覆盖表](particle-component-coverage.md) | General 到 Children、renderer 和 override 逐项记账 |
| Timeline | 4 | `runtime-required` | [运行时系统语义](runtime-systems-reference.md)、[运行输入与属性覆盖表](runtime-input-property-coverage.md) | target/keyframe/mode/tangent/event 分层实现 |
| User Properties | 9 | `runtime-required` + `platform-decision` | [运行输入与属性覆盖表](runtime-input-property-coverage.md) | 控件、binding、持久化和 Texture Variant 必须支持；shortcut 单列 macOS 策略 |
| Audio 与 Media | 3 | `runtime-required` + `platform-decision` | [运行时系统语义](runtime-systems-reference.md)、[运行输入与属性覆盖表](runtime-input-property-coverage.md) | 使用可注入 provider；不得复用 Web 回调频率假设 |
| SceneScript | 58 | `runtime-required` + `research-boundary` | [SceneScript API 覆盖表](scenescript-api-coverage.md) | 官方 API 全面建账；执行前必须有源码 IR、沙箱和预算 |
| Shader | 6 | `runtime-required` + `platform-decision` + `research-boundary` | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) | 保存作者合同；DirectX/GLSL 到 Metal 的通用执行仍需受控方案 |
| Puppet Warp | 13 | `runtime-required` | [高级对象覆盖表](advanced-object-coverage.md) | mesh/bone/constraint/IK/interaction/animation 逐项建账 |
| Models | 8 | `runtime-required` | [高级对象覆盖表](advanced-object-coverage.md) | model/camera/fog/animation/attachment/lighting/shader/simulation 分开建账 |
| Lighting | 2 | `runtime-required` | [高级对象覆盖表](advanced-object-coverage.md) | 2D 与 3D lighting、shadow 和 HDR 不与 layer Bloom 混写 |
| Performance | 3 | `runtime-required` + `platform-decision` | [高级对象覆盖表](advanced-object-coverage.md)、[开发计划](../scene-capability-development-plan-2026-07-22.md) | 分辨率、纹理和预算成为产品策略及回归门 |
| RGB | 1 | `platform-decision` | [高级对象覆盖表](advanced-object-coverage.md) | macOS 默认关闭；若无设备/授权集成则明确 fail-closed |

目录计数：`6 + 2 + 3 + 48 + 3 + 10 + 4 + 9 + 3 + 58 + 6 + 13 + 8 + 2 + 3 + 1 = 179`。`lib.sceneScript.d.ts` v2.8 是第 180 个独立权威资源，不计入 `/en/scene/` 页面数，映射到 SceneScript API 覆盖表。

## 3. 实现合同交叉表

| 合同 | 官方页面集合 | 当前权威状态表 | 开发时先看 |
|---|---|---|---|
| 文件、对象、层级、Camera、资源 | Overview、Assets、Parallax | [总台账](coverage-ledger.md)、[高级对象覆盖表](advanced-object-coverage.md) | scene/project schema、作者 enable、资源 identity |
| Effect、Material、Shader、FBO | Effects、Shader | [Graph/Shader 覆盖表](render-graph-shader-coverage.md) | IR 与 executor 必须分级，slot/order/RT 不能丢 |
| Particle | Particles | [粒子组件覆盖表](particle-component-coverage.md) | emitter/initializer/operator/renderer/control point/children |
| Live values | Timeline、User Properties、Audio/Media、Parallax | [运行输入与属性覆盖表](runtime-input-property-coverage.md) | authored -> property -> Timeline -> SceneScript |
| Script | SceneScript、Timeline events | [SceneScript API 覆盖表](scenescript-api-coverage.md) | source/binding IR、每屏 VM、预算、事件顺序 |
| 高级对象 | Puppet、Models、Lighting | [高级对象覆盖表](advanced-object-coverage.md) | 不以普通 image transform 或 layer Bloom 冒充 |
| 产品策略 | Performance、RGB、Publishing、Mobile shader | [高级对象覆盖表](advanced-object-coverage.md)、[开发计划](../scene-capability-development-plan-2026-07-22.md) | macOS 决策、预算、生命周期和发布门 |

## 4. 完整性状态

| 项目 | 数量 | 状态 |
|---|---:|---|
| 官方 `/en/scene/` 页面入口 | 179 | 已全部收入目录 |
| 已路由页面 | 179 | 已在 [逐页表](official-page-map.md) 中逐 URL 映射；本表只做 16 组汇总 |
| 未路由页面 | 0 | 新页面出现时必须先补目录和本表 |
| 官方类型声明 | 1 | `lib.sceneScript.d.ts` v2.8 已映射 |
| Effect 专项 | 45 | 逐项覆盖表已存在 |

这里的“完整”仅指目录与逐页合同归属完整，不能由本表的分组计数单独证明。任何 `L0-L3` 项都仍有兼容边界；官方未公开的私有序列化、shader 算法和 Windows renderer 行为也继续保持 unknown。

## 5. 维护门

1. 官方 sitemap 数量或类型声明版本变化时，先更新目录，再更新本表和相应专项表。
2. 新能力必须有唯一专项落点；不得只在开发计划或样本报告里留一句描述。
3. `L3` 必须链接代码、自动测试和运行证据；缺任一项时降为 `L2` 或明确写 `gate incomplete`。
4. editor-only 页面仍保留映射，但不能因此扩大播放器产品范围。
5. 第三方项目只用于解释和测试设计，不改变官方页面分类或 `L4` 真值来源。
