<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定职责归[运行合同](../architecture/runtime-architecture.md)，余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。
# 缺省纹理尺寸归一化（2026-10-12）

## 首断点与实现

3761619125 的头部 deformer 关闭可选遮罩后仍用其 Resolution 归一化 UV，再参与视差计算。旧证明要求结果只被另一张纹理单次采样，错误地让合法效果要求不存在的纹理。修复现有 prepared proof、typed uniform 与 Program 链，不新增纹理、provider、renderer 或输出 owner。

官方 2.8.0.42 自有 R4 输入已对照：无 sampler 声明、plain unused sampler、关闭的 opacity-mask sampler，三种声明形态已测的 XY/ZW 低范围编码对应名义 2；optional MASK0 slot1/5 在两种 source 尺寸下成对 Z/X、W/Y 均为 1，slot5 绝对 vector 只在300×80源测得。常量与真实绑定采样正控通过；未扩大为三种形态的全部尺寸组合。证据 `.artifacts/tmp/deformer-resolution-20261012/official/neutral-contract.json` SHA-256 `70ad1fa1e268a04dff6230171cc83bd295f9ccc5494ebe337b58c1b682256731`。这不是任意缺省资源或绝对 Resolution 用途的合同，也不证明 Float 位级官方值。

## 单一职责与取舍

沿用 NeutralTextureResolutionAnalyzer，统一 packed/separate 两种赋值形态：只准一个 inactive vec4 Resolution 的四次顶点读取，全部落在同一顶层 vec2 完整表达式 `source.x * R.z / R.x, source.y * R.w / R.y`；保留直接 attribute 或现 authored-UV producer 与声明/遮蔽证明。fragment 不读取 R，但可通过 helper、循环或多处消费归一化结果。使用现 structural syntax 入口，不扩大 bounded frontend 的循环执行准入。

Fact 只保留 resolutionSlot；删掉另一纹理 slot、varying 标签及其下游单采样/identity-mapping限制。它们不决定这个缺省尺寸值。Finalizer 仍要求真实 template/frame hole、无 active sampler、无对应默认资源、无 uniform default/作者覆盖及精确 ABI，编码名义 `[2,2,2,2]`，保留作者原浮点运算顺序；不把 `X*2/2`直接折叠为 X。实际 bound/default、pending、错 purpose/publication 必须继续现资源链，不能被缺省规则吞掉。

默认资源必须在 neutral/dead projection 之前保留判定；复用已有声明/注释解析，不新写注释正则或另造默认解释。Unit 与 source 入口共享同一判定。准备期才做证明，帧内只消费 typed binding。分析及 generic artifact cache 随语义变化失效。

## 失败、验收与退出

错误分量、分母加常量、额外/fragment Resolution 读取、数组、错误类型、shadow、nested赋值、真实采样、默认资源或非 hole 不准中性值，保持原最小失败半径。继续保留旧 packed/separate 合法输入，不按样本名或 shader path 分支。

先跑结构及真实 Program uniform/冷暖缓存正反门；再 Debug build、隔离真实 3761619125，要求目标 deformer 到 GPU/唯一合成及后续帧，比较头部画面并保留裙摆/音乐既有链。代表 shader-default 的非 2×2 资源须仍编码真实尺寸。运行证据不能写成整样本、桌面入口或官方全图 parity。设计已先落库再实施；结果随本页归档，稳定职责并入运行架构，窄设计登记退役。

## 回归边界补充：真实绑定的准备期身份

邻近 mapped-mask 门发现 source-only proof 不能判定模板是否有真实纹理；相同 shader 在空槽与已绑定槽必须保留不同依赖。使用已有 Template.textureSlots 非空集合（不使用 readiness；pending 也是真实绑定），贯穿现 canonicalizer、dead-binding、bounded frontend 与 generic artifact 的归一化资格。真实绑定仅阻止缺省尺寸豁免，仍由既有 Resolution dependency、sampler schema 和 host uniform 消费资源。Variant analysis 已含 slot shapes；Frontend 与 generic request/cache 同步包含此输入，防止同源码的空槽/已绑定暖缓存串用。无新解析器、资源读取或帧内计算路径。


## 执行结果与证据上限

基线 `76029e99` 隔离原包再现 slot1 textureBindingInvalid；原包 SHA `73cbda2910b51043b2beacd6f669e1a0c7d725e59399124dafe986d14cbd784f`。最终 Debug executable SHA `d0f99c49658be3184370dcc7837c233c434f29c3fc68f6587a06f8169e5114e1`、dylib SHA `e2042b2c7e07aa6d88b781010e58b25519d4179ba6064ed952a35e05b355fc5e`。原包原属性隔离 direct Host 播放18秒：头部466的deformer637从拒绝变为真实generic Program，首/后帧GPU完成，其输出交给后继645、最后inactive1101透传到唯一compositor；首帧逐条graph回执中实际材质阶段由77增至78，另37段为作者关闭的activation passthrough，原唯一visual-failure passthrough已消失，退出gpuDrained=true。截图主体、裙摆及肩部仍显示，当前默认歌曲时钟推进。

本批可见收益是头部变形效果不再被整个跳过。78是此输入实际GPU执行的材质阶段数，不是完整正确率；runtime audit的claimed/encoded=39前后相同，不能用于统计全场效果；未独立量化鼠标轨迹对头部的视觉贡献，未做完整原包官方动态图parity、普通桌面入口、所有属性组合或性能验收。无sampler声明且真实template绑定的旧输入继续保守失败，不据本片声称新增支持。

真实Program四门通过：paired nominal bytes、真实未采样shader-default64×32 host bytes、mapped/translated `[4,4,2,4]`、冷暖结果一致（128 records），错purpose/pending/覆盖/错分量等保持拒绝。这里的Metal资源/bytes不是draw像素证据；实际GPU由上述App承担。首次扩大proof导致mapped回归的失败保留first-run，已修真实绑定上下文，未改原mapped断言过门。源码proof两入口、defaults/格式覆盖/遮蔽反例、bounded/generic同源hole→bound→hole依赖及不同key均通过；保留既有dead-binding门，其中历史真实导出语料未配置项skip，不当通过。

证据根 `.artifacts/tmp/deformer-resolution-20261012` 保存官方合同/manifest、自有输入与ROI、最终App身份/日志/截图、编译与测试receipt、失败与冷暖结果。官方manifest SHA `3f5094b353e64f665c4c1d9883cf70bb9dfcbe7600681459e162d9ea6817ea00`；像素只支持量化名义2，不支持bitwise官方值。VM本轮4个自有窗口及4份guest输入已精确清理，用户文件只读。最终只留有界证据与一份复用构建缓存 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`；未知归属 `.mimosa` 保留。

下一批优先 N06 初始图层配置与已有普通image动态模板复用，先消除真实VM事务的首断点；不要把未验的Puppet、composition、text wrapper或perspective直接准入。

收尾门：Debug构建、依赖/防重复/代码健康/设计、文档登记与健康门通过。防重复基线随本轮删除的重复函数体从121收紧至120。结构组合46方法中45通过，一项旧 source-set 测试仅因未修改的frontend测试间接复用canonical source list而失败；该门与被检文件均与HEAD一致，未将其计绿。residue只报原218B `.mimosa`，归属未知保留。
