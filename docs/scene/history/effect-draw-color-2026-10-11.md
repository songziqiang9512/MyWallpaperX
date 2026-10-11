<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定职责归[运行合同](../architecture/runtime-architecture.md)，未闭问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Effect draw颜色（2026-10-11）

## 决策与实现

上一片alpha接通后，3761619125的14段texture_override首拒推进到g_Color4。本批在实施前把窄设计写入运行合同§3.0及design登记，选择复用同一host schema/Program scope/typed frame：g_Color=float3，g_Color4=float4，RGB取既有SceneDynamicLayerValues.color，w复用effectDrawAlpha。source/base同名作者static/dynamic来源不被抢占；变体前筛、准备与identity仍共用effectContext。复用同一次RGB求值给原source tint分支，保留capture中性source tint；effect不读sourceMaterialColor、provider色或已合成tint，也不额外乘brightness或alpha。复制/terminal replay保值，错误类型、数组、来源冲突和非有限值沿原最小边界拒绝。没有新registry、颜色算法或compositor分支。完成后撤窄登记，稳定合同并回原段。

[官方公开变量说明](https://docs.wallpaperengine.io/en/scene/shader/variables.html)只定义绘制乘色参数，不能决定effect中的亮度/provider含义。固定官方2.8.0.42（binary SHA `daac1ea7c991207fbd6098616757e3dae393850f6862845db55d04921b6bda07`）自有r5/r6分别22/26文件，host/guest哈希一致；三消费RGB两颜色探针均为26,51,77 /51,102,26 /77,26,51，gColor4.w为64/128/191；独立provider采样(a,r,g)三格恒191,51,178。独审复测30格、离差0，未消费私有实现。r5同RGB的brightness=.5/1/2未改变host RGB，但sourceRGB也不变，因此不证明brightness字段有效执行或完整亮度合同，不扩父层/model/HDR。

## 实际结果与边界

- 真实CPU旧版color/Color4不是host而红，原alpha正例仍成立；修后9项CPU通过。原alpha与新增颜色复用既有测试/Metal harness，2项GPU测试共15帧覆盖非单位消费RGB/alpha、独立provider、不同source capture、prepared Program复用与无fallback。首次分屏测试shader被既有color-contract准入拒绝，改成直接分量输出的自有probe后通过，未为测试放宽产品。邻接动态layer值、source静态tint/provider绑定31项通过。
- 最终Debug build和签名通过。App executable `41f0d94fc7476d6aeb965569779b17d9bca04555a590c8524e99480a4e1ac34c` / dylib `7e0d733de9bdd931ee1e0ab939c343125a88a304dacaad8be77f765d434866b3`。同语义r5打包输入9个颜色/alpha格，18条首帧+次帧实际Program/GPU/compositor记录，像素与官方吻合，安全排空exit0。
- 原包3761619125的14段texture_override首帧+次帧全为真实material/GPU，其同层后继终端均被compositor消费。大片白遮挡消失，肩部、手和衣袖重新可见；**下方仍有矩形纹理错位/重复**，不能称整图正确。24段wave在最终App继续实际执行，原39段失败组现38段接通，约97%仅是该组执行进度。deformer仍因slot1尺寸降级，SceneScript origin TypeError尚未关闭。截图SHA `baf801cdabe4f43a6e500987c05b6c11af7802629e915324b739cae2fff29f87`。
- 只读扫描279个pkg的作者frag/vert声明命中376及3435573282两包，不证明全语料受益。第二包343的21段gColor4准备拒绝消失，但活跃消费者仍material-template/named-binding失败、隐藏层仍inactive，**没有目标GPU或显著画面恢复**，不报35段实际受益。
- r5普通solid sourceRGB三档原生为(12,24,40)/(26,52,76)/(51,103,154)，修前后相同；官方均(26,51,77)。此source brightness偏差单独留队，不能把本批effect行通过扩成全fixture一致，也不能立即全局删brightness。image+effects颜色user/script producer、layer色Timeline及brightness动态仍未准入；typed多帧不证明这些作者通道。直接Host不证明完整App→daemon桌面、长期播放/交互、HDR或性能。

## 下一项与保留

优先验证376下方重复矩形的逻辑采样尺寸与屏幕scale后的RT尺寸关系；已记录layer1954作者size1180×403、scale2，实际effect input2048×700。只是有证尺寸候选，尚不是已证明根因。不能按样本缩UV或填固定尺寸；应从既有source extent/texture companion producer核到consumer，并对照官方。其后保持缺失遮罩、named依赖、Skew缩减尺寸等队列。

本机 `.artifacts/tmp/effect-draw-color-20261011` 保存官方自有输入/哈希/截图、实际红绿及两原包前后、最终App身份、CPU/Metal和独审收据。归档工具因总预算拒绝本次提升，必要结果暂留原目录，未扩预算或删除未知证据。已清理两原包副本、五份隔离HOME与重复ready图，约642 MiB；必要after图和失败日志保留。官方自有窗口及两个guest输入目录已关闭/清除，VM继续运行。连续开发仅复用 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`；真实媒体与主工作区原三份并行改动未改，不推送。
