<!-- document-role: historical-evidence -->
# Native framebuffer source Program：有序采集与只读深度

> **历史证据 — 非现役入口**。2026-10-19 有界实施。只关闭合法原生透视组合平面的主源执行缺口；3337494481 的盒面穿透、顶面构图、背景及整样本验收继续开放。当前待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，长期职责归[D1](../roadmap/batch2/composition-render-target-design.md#有序-framebuffer-source-program-后继2026-10-19)。

## 公共语义与唯一执行链

原 AssetCatalog 保留 model 的 `passthrough`，沿唯一已加载 model/material、明确 framebuffer 输入及 render state 提名 source role。首片限 native、无成员/依赖/实例覆盖、显式 translucent/nocull/depth-read/no-write 的平面；资源名、shader 名、路径、hash 和固定表达式不决定算法。

作者完整 source Program 经过原 compiler/variant envelope、host binding 与颜色证明，作为 GraphExecutor 的 base command 写入原 working pair；同帧主源仅在 utility 作者顺序截点读取。source 与 effects 保正常 MVP/色彩路径，最终 quad 使用原 StaticModelFrame 的 reverse depth 与只读 compare。普通 affine source 保原链，不增加普通像素除法或无候选 PSO。

StaticModelFrame 继续独占深度 plan、acquisition、首次 clear 与提交生命周期。可选平面在 admission 前取资格：mandatory model/particle allocation 先行，普通 miss 仅排除该 role，busy 保整帧 deferred；不留下未消费 ledger。layer/原 part index 的 frame-local depth 事实包含失败，ordered shadow 提前退出后仍可刷新后层 draw 内容并复用原 lease，不重新将自身判成 isolated。typed source 色彩证明失败沿原 captured-main 局部回退，陈旧/错身份仍拒绝。

## 实际结果

最终 Debug 采用固定 `a06b09767` 加28个 Scene overlay，冻结 SHA `7441420318c6be24f03493947ba88872aa583bbc7f139d24d2f098a3a5530c65`；App executable `1a569f473c71f77141debeb886cdf9cfcfc80cfca4841a37fdf36fc15d50c75d`，dylib `c811a1572ecdb44044d405dc17c5a22e69c551b755cfddd2fa80339146673034`，签名通过。并行 App/Steam 改动不混入该运行身份。

- 自有 native/parent 倾斜网格经 source Program 和反色 effect，在独立预登记点命中精确颜色；前橙模型保持遮挡，后绘且更远的绿模型仍可见，证明终端不写 depth。最终两帧通过，after 与前一有效版本逐字节相同；实际 GPU completion、输入/App 不变和 stop/drain 成立。
- 原 `3337494481` 两 arm 均只设置作者 `newproperty39=false`，实际 layer347=false 且提示消失；固定10s/after8、30fps、非零PCM。旧冻结 Gaussian App 的下沿没有连续白条，r3 source 后继的 ready/after 均新增白色分段音频条，主标题、粉色前面及顶部轮廓保持。70/202/228/591 真正消费非零音频，五层末端均完成 GPU/compositor/下一帧；229首 effect 原有局部 Program fallback 仍在。
- 原333可见收益取得于 r3；最终 r4 只补 shadow 早退 depth 事实与无候选扫描成本，未重复原333。最终自有像素、相关生命周期反例和独立原380接续验证，不把它记成最终 binary 重播333。两个真实对照并非 same-HEAD 或精确音乐/相位比较，不推导性能收益。
- 最终独立原 `3806337293` 8s/after6、非零PCM，人物/眼面、双环、日期时钟和黑背景保持，exit0、FAIL[]、stop1→0/GPUdrained。首次 heldout 相对路径误用在 isolated-root-required 前停止，纠正绝对路径后才有一次有效场景运行。

原333仍有跨面文字穿叠、顶面近乎压扁和全屏背景差异；Rope profile 和229 fallback 保留，runner FAIL 未改成通过。已排除“模型RGB误丢”等旧首错，并未关闭整个样本。

## 验证、审查与边界

最近角色/资源准备门17项、后继负ID角色2项、相机/采集55项、source graph4项、消费者12项、终端GPU6项与最终 depth4项通过；后者两种模式各39项事实，含普通分配失败、busy恢复、错pass/command buffer、arm/cancel、无writer、只读不写及 ordered 提前退出后 fresh payload/同lease。改名、等价输入与相邻非法 profile 保持原拒绝。首轮自有向量运输写法、测试装配和一次 optional caller 编译错误保留为验证失败，不作产品红或视觉收益。

独立审查发现并修复 source typed 失败被吞、depth miss 留 ledger、shadow 早退丢后层 depth 三处问题；最终限定增量无剩余可行动发现。独立像素复核实际查看原图及目录官方，结论限局部贡献。

本片未证明 HDR、任意 downsample/local-size 顶点程序、hidden captured-main provider、nested/成员/多依赖/实例、更广 depth-write/cull、isolated model 互遮、完整动画/交互、官方FFT/像素一致或CPU/GPU/内存收益。无候选普通帧跳过新增全层扫描，无排除则复用原 preparation 数组，仅为实现事实。

必要普通14天证据归 `.artifacts/scene-evidence/runs/native-framebuffer-material-source-20261019/`；完整失败分类、原图、输入身份、最近门和独审收据随包保留。VM及官方主客户端保持运行，本片未增加官方实验。
