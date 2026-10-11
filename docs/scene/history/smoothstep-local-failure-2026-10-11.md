<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。合同归[shader覆盖](../capabilities/render-graph-shader-coverage.md)和[局部失败](../architecture/runtime-architecture.md#32-尽量执行局部降级)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# smoothstep 广播与 launch 局部失败（2026-10-11）

3761619125 的 deformer 调用 mixed vector/scalar smoothstep，在公共 GLSL 边界拒绝。原 built-in vector conversion 现复用既有作用域与 component expression 事实，为已证同宽 float vector 的单个 scalar endpoint 显式广播；vec2/3/4、参数域与标量算术有效，未知、shadow、数组、错误宽度、作者重载/prototype保留原状。没有新parser或帧内工作。VariantAnalysis v19淘汰旧canonical prefix，源key缓存不泛化换代。

首错消失后，depthparallax 的残留 g_Texture1Resolution 仍要求作者未提供的slot1。MASK=0且实际Metal只采样0/2，但vertex仍有未被现有证明消除的分支，不能伪造纹理或常量尺寸。其textureBindingInvalid原来误拒整个layer。现仅精确typed launch/material/texture归因、有效slot通过原effect/pair/依赖拓扑证明后退回effect入口current；引用、身份、资源范围及live-frame错误不放行。

- 广播旧代码六个vec2/3/4混合边界真实编译失败；修后新7项及既有builtin/direct-input相邻门合计23项通过，GLSL→SPIRV-Cross→Metal两帧与显式broadcast一致。持久cache门首次遇并行文件修改失败，冻结后重跑通过；Debug build及防御/依赖/代码健康/设计门通过。
- 真实missing-mask CPU门旧版拒全层，修后resolved/passthrough/resolved保留首尾；四个未归因安全反例仍拒。独立只读审查两部分无新P1/P2；安全归因完整矩阵和多节点FBO不是新CPU门的覆盖。
- 固定App executable `54d00bd8c952e8ef714f4951310e23c422de0563159bdfe249b59735e9759635` / dylib `ab42683cf979dca0cf89b4dcdb5d2c8450815e7e7fd56296d957fdb257230c3b`，签名通过。原包隔离Host恢复layer466五段健康material的首帧/后续GPU，effect4单独passthrough，作者关闭的effect6仍关闭并完成终端合成。脸部颜色细节恢复，大片白矩形仍在。
- 短观察窗42 GPU completed、41 presented、0 failed，排空surfaces=0、exit0；约8.27FPS为带诊断短窗，不是性能收益。原包未修改；不是普通App→daemon→桌面、交互、全属性或官方逐像素验收。deformer本人仍无实际Program执行，不能算其能力已闭合。

## 后继与产物

后继[effect draw g_Alpha已接通并验收](effect-draw-alpha-2026-10-11.md)，14段texture_override的新首错为g_Color4，白块仍在；缺失遮罩尺寸和SceneScript origin TypeError继续留队列。当前39段已定位失败组仍只有前批24段wave已进入真实链，不提高整样本正确率。

本机 `.artifacts/tmp/smoothstep-broadcast-20261011` 保留红绿、首轮整层误拒和修后实际运行、必要截图、App身份及独审收据；原包副本、隔离HOME和重复ready截图已清；原包证据归档受总预算阻挡，必要结果留原目录，细节见[alpha收尾](effect-draw-alpha-2026-10-11.md#后继与产物)。只复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份构建缓存，不改主工作区三份U06并行文件，不推送。
