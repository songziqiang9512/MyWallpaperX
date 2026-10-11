<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定职责归[运行合同](../architecture/runtime-architecture.md)，未闭问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Effect draw alpha（2026-10-11）

## 决策与实现

3761619125 的14段 texture_override 原先在 g_Alpha 首拒。实现前将设计落到运行合同§3.0.1与窄设计登记；选择扩展既有 host semantic 和 typed frame，不从采样纹理反推、不固定1、不增加合成乘法或第二个owner。完成后本记录保存决策，稳定合同并回3.0，窄登记退出。只接受 effect scope 非数组 float；source 同名静态/动态仍走作者来源，非法类型/数组/冲突及NaN拒绝。复用已求值 layer alpha，经原FrameInputs→UniformInputs→encoder传递，Program identity与前置variant分类使用同一scope，copy/terminal replay保值。

独立审查发现前置 nonHost 分类漏传effectContext，可能把带material别名的g_Alpha误计为作者键并产生假冲突，已在原入口补齐。没有额外缓存换代：host绑定不在持久VariantAnalysis缓存内；同批v19仅属于smoothstep前端变更。

## 官方与执行证据

- 官方2.8.0.42，wallpaper32.exe SHA `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`。仅自有shader/JSON和截图观察，没有消费私有实现。r2三档消费alpha=.25/.5/1，g_Alpha灰阶64/128/255，opaque对照255。r4独立named provider RGBA(.2,.7,.3,.75)，(g_Alpha,provider.a,provider.r)输出(64,191,51)/(128,191,51)/(255,191,51)。host/guest输入hash一致，独审核对ROI与来源。r1红占位、被console遮挡r2及binding未证的r3不计正证据。
- 真实CPU旧版effect错误准备为static而红；最终6项通过，包括实际launch/precompile后的alias-key效果host正例、source既有冲突反例、来源/类型/身份/NaN/copy/terminal。实际Metal三帧1项通过：不同provider/source capture alpha不改变消费层g_Alpha，像素、Program复用、无fallback均验证；该GPU门在第10路径前置scope补接前运行，不能冒充最终产品身份。邻接derivation/static-tint共23项通过。
- 最终Debug构建与签名通过。App executable `d8f8265ecf746d4d1c83a31d123c1824b1b488e0acfaa515af40b8c1d2822c78`，dylib `6f986aa73c69034cc7b4d18dc8d03edf8f254876bd2b19eb9055b3f29584bb51`。自有r2原语义打包输入的104/105/106，首帧+次帧实际Program/GPU/最终compositor通过，截图三格64/128/255与官方一致，PNG `02de51a6e4e7932360bec5c59d60190f97fbd9d562dead84444f126ed357b981`。exit0、surfaces0、gpuDrained=true；不外推其他颜色uniform行。
- 最终同App原包3761619125保持脸部恢复和健康effect，14段texture_override的下一首错为`uniform/staticUniformBindingInvalid details=g_Color4`，大片白块仍在。短窗41 completed/40 presented/0 failed、安全排空，约8.11FPS仅诊断观察，没有性能提升结论。已定位39段失败组仍只有前批24段wave进入真实GPU，不把参数首错前移报成38/39或整样本正确。
- 自有r4 native provider已执行，但三个consumer在`dependency-stage-reference-unsupported`降级，归N04，不能用typed Metal探针替代作者图准入验收。直接Host运行不是普通App→daemon→桌面、长期播放、交互、HDR或整样本官方parity。

## 后继与产物

下一批优先沿同一schema/typed frame研究并接通g_Color4/g_Color消费层颜色；非单位RGB、brightness与source/provider边界须补证，不以本批alpha外推。缺失slot1尺寸、SceneScript origin TypeError、named依赖准入继续留队列。

最终r2/named失败已提取 `.artifacts/scene-evidence/runs/effect-draw-alpha-20261011`（有未解决原因保护）。本机 `.artifacts/tmp/effect-draw-modulation-20261011` 保存官方自有输入/manifest/截图、原生成功与N04失败、最终App身份和独审；CPU/Metal收据在其 `alpha-validation`。原包最终运行归 `.artifacts/tmp/smoothstep-broadcast-20261011/alpha-host`。原包三次结果归档受总预算阻挡，必要after截图/日志暂留原路径；未删未知旧证据或扩预算。已清理本轮原包副本、七份隔离HOME和三张重复ready截图，约385 MiB；官方自有guest目录与实验窗口已清理，用户VM保持运行。连续开发仅留 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份构建缓存；真实媒体及主工作区三份并行改动未改，不推送。
