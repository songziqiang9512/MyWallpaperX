<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。合同归[shader覆盖](../capabilities/render-graph-shader-coverage.md)，当前结果归[运行证据](../capabilities/runtime-evidence-current.md)，待修归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 只读整数函数输入修复（2026-10-11）

## 首错与修复

3761619125 原包的 24 段 multistage_wave（NODE_COUNT 4/5/6 分别 8/5/11 段）将 `float waveMask` 传给 `calWaveData` 第九个 `in int overflowable` 参数。三个编译变体均被 GLSL 拒绝，实际 CPU 调用和 graph 回退与这些 subject 精确对应。作者文本与实际日志用于定位；未消费私有编译 shader blob 或参考实现。

按公开 [HLSL 浮点/整数转换合同](https://microsoft.github.io/hlsl-specs/specs/4-Conv.html)，在原 shared canonicalizer → direct-function argument owner 显式构造整数，截断小数。复用原 vector return 的唯一 root/global/parameter 类型事实，未添加 parser、profile、renderer 或帧内工作。仅单 token 浮点实参、唯一只读 int 签名可进入；内建重载、prototype、多定义、数组、shadow、out/inout、未知及复合表达式保留原状。不是完整 HLSL 隐式转换支持。

独立只读审查发现内建重载选择和旧 canonical prefix 缓存风险，分别补 intrinsic 排除与 VariantAnalysis v18；排除仅用于新增整数输入转换，旧 vector fallback 未缩减。其他 cache 按 canonical source 建 key，无需泛化换代。五产品文件最终 diff SHA256 `e292f42e0706006f08d1a9dd859a63dc328016a74190a8a45d7f4bd17aa87acc`，复审未见新阻断；其证据上限为静态审查。

## 执行与画面边界

- 固定旧代码红门真实 GLSL 编译失败；新合同测试经原 canonicalizer、normalizer、glslang、SPIRV-Cross 和 Metal 两帧输出 `[1,-1,0,1]`，证明正负浮点截断。既有 return、float index 与 scalar/vector 三模块合计 47 项通过；审查补正后最终产品两模块 16 项、工具路由/依赖与新合同三模块 122 项分别通过，存在覆盖重叠，不相加作为成果；Debug build、防御/依赖/代码健康/设计及文档门通过。
- 同原包隔离 Host 中 24/24 波动 subject 进入实际 GPU、无该组 visual-failure passthrough，其中 2 条直接由最终 compositor 消费，其他为上游图链；不是 24 个独立可见画面。大块白缺失仍存在，不能报该样本已正确。
- 首轮 benchmark 的冷启动 65.14 秒超过工具固定的 60 秒启动预算，被总计 70 秒等待截断。保留失败；后继用同 App 内置 runner 和 240 秒有界外部等待补呈现/退出证据，不修改产品超时或放宽 benchmark 验收。不是普通 App→daemon→桌面入口、交互、全属性、长稳或官方逐像素验收。
- 最终 App executable/debug dylib SHA256 为 `7e94428c2f29b005633e1f149ac59c8486f10fc3a89edcbec22c24485baf10fe` / `43c353cdd8e2b48972ebb39b031cd355cf97a4e0ac34165f94aff6ff3e81f737`，deep/strict 签名验证通过；观察窗 GPU 完成 41、呈现 40、GPU 失败 0，排空后 surfaces=0、exit0。约 4.7 秒观察窗为 8.73 FPS，只是带诊断短窗，未声称稳态或性能收益。
- 仍有 14 段 texture_override 的 `g_Alpha` 来源缺合同、1 段 deformer_simulation 的 smoothstep 向量/标量广播拒绝，以及 SceneScript origin TypeError。短观察窗有明显帧率不足，不能宣称性能提升或把诊断运行当稳态测量。

## 后继与产物

下一项先闭合 texture_override 的 consumer draw alpha 来源：作者默认 RETAIN_ORIG=0，采样命名 provider 的 g_Texture1，末尾乘 `g_Alpha * u_Opacity`，自己的已调制 g_Texture0 被替换分支丢弃。14 个当前 consumer 恰好都是 alpha=1，不能据此全局塞常量1；也不能重复应用 provider alpha。沿现有 typed layer/frame → uniform owner 补 draw 调制，先用非单位 alpha 控制验证。prepared范围应复用effectContext（source material也可能有graphRole），不能全局抢占base material的g_Alpha authored绑定；typed层alpha与provider/source-material alpha须分清。官方effect draw数值仍待证，不将建议视为已获行为合同。随后处理 smoothstep 公共广播；Skew 的 g_TextureReductionScale 尺寸合同留 N03，不能猜单位值。

证据根 `.artifacts/tmp/direct-function-scalar-20261011`：保留红绿、原始运行日志压缩、必要截图、App/源码身份与独审收据；真实样本只读。仅复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份构建缓存。406 份非截图原始文件压缩后逐项 SHA256 校验，保留基线/中断/最终必要截图，共约 15.3 MB；原包副本、临时 HOME 与重复运行输出已清理。自动提取先因中断运行缺 after 截图失败，基线单独提取又被现有全局预算拒绝，prune 无可清记录；未加预算或删除未知证据，必要结果留原根。Git 收据同根；未推送，不改主工作区三份 U06 在途文件。
