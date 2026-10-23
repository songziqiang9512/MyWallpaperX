<!-- document-role: historical-evidence -->
# 声明图片属性与保留源 alpha 的 RGB 图

> **历史证据 — 非现役入口**。本批有界事实与失败记录；剩余待修及执行顺序只归[唯一队列](../roadmap/scene-open-breakpoint-queue.md)。

<a id="declared-texture-rgb-graph-20261024"></a>

本批闭合已声明图片属性的准备身份与颜色用途，未增加 shader 家族、资源或 compositor owner。长期合同见[输入身份与颜色用途](../architecture/shader-metadata-failure-contract.md#declared-texture-input-and-color-purpose)，剩余问题只归[唯一队列](../roadmap/scene-open-breakpoint-queue.md)。

## 实际改动

- 原 parse 接收项目 sceneTexture 精确键集合，Document effect/instance、AssetCatalog material、SourceFacts 共用该裁决。已声明 `_1` 保 property 身份；无声明、路径语法、内部 RT、显式 kind 和材质/instance 优先级保持。
- 原 ColorMixGraph 扩展有界 RGB DAG，分别跟踪 RGB 版本与未改写的采样 alpha；完整 sample、alias、coverage 使用闭包及已验证 normal helper 共同证明输入颜色用途和输出 alpha。数据/UV 混用、额外读取、写入、helper 逃逸与 vertex 采样不获新输入事实。
- Schema 与 ColorTransfer 投影同一事实；实际输入 0/3 的 PMA、1 的 straight 沿既有 ordinaryColorBoundary/frame mask 转换。未放开 terminal replay，未修改作者混合算法；构建期 producer 身份使旧准备缓存退出。

## 有界验收

原样本 `3586705329` 的 project/pkg SHA 为 `4856263d…12c` / `9681ab8f…c3239`。测试副本只增加自有 256×256 绿/蓝/黄图片；原媒体只读。固定 profile 仅用作者开关 `newproperty3=false` 关闭滚动，保持默认可见门，输入同一份非零 PCM、中心 pointer、10s/after5/30FPS。

修前七个效果被纹理用途门拒绝，图片虽加载却未被消费。修后七个 root（165/169/187/191/195/199/203）均沿 genericCompilerArtifact 实际执行、GPU 完成并被合成。`_1` 选图的两个预登记 32×32 ROI 从各 0/1024 绿色像素变为 1024/1024；清空启动选择恢复作者 fallback。另验默认滚动与未参与修法的 `3448845950`：四轮正式运行均 PASS/exit0，failedFrames=0，停止 surfaces 1→0、GPU 排空。

正式 App SHA `20a135db917986e0fc6fd1edc83bb5ae48518b3d6ab74b020b2ecccf26e35344`，Debug `-O` 构建 47.898s，5859 冻结输入无漂移，严格深签名通过。另以最新 UI 提交 `54c206846` 与相同九个 Scene 文件完成组合 Debug 编译/链接：42.111s、5863 个冻结输入无漂移；未以这次未重签构建替代上述运行身份。构建时间不是性能收益。

CPU 门覆盖身份跨入口、优先级、用途冲突、变量/资源/helper 改名、mix/lerp、别名与相邻拒例。三输入 GPU 门用真正 Program/Finalizer/GraphExecutor 和生产 SceneImageLayer fragment、normal PMA PSO、MainPassEncoder：0/3 PMA、1 straight，mask=9；图输出 BGRA `[127,96,100,128]`，partial-alpha 目标中心 `[68,56,62,160]`，外侧 12 点保持 `[8,16,24,64]`（±1）。三例与 typed RT/data/wrong-purpose 拒例通过。该数值门不冒充完整 Swift compositor claim/ticket；完整提交链另由真实 App 运行覆盖。

独立审查未发现新增 P1/P2。source/test/Metal 哈希与最终 GPU 结果绑定；`final-execution.json` 明确取代 CPU 准备收据的 NOT_RUN 状态。

## 失败尝试与未覆盖边界

- 初次 243-source CPU 编译超时、旧 Context closure 缺真实 light owner、测试的陈旧 alpha channel 标签均单独留证，不认成功执行。最终最近门有有效绿色结果。
- 首包漏签 compiler helpers，使另一个效果 110 局部拒绝；正确签名包复验后正常。错误包装不归为产品回归，也不计正式验收。
- 数值载体曾误用多阶段 admission、误要求 background cohort 的 terminal replay、遗漏普通 compositor bind；独审/实际门发现后修正载体，未因此放宽产品，失败日志保留。
- live product-entry 的临时 HOME 放在真实 home 子目录，被隔离前置条件拒绝：issued=false、0 present、0 update。它没有执行热更新，不证明失败或成功；本批只认启动选择/恢复，未认真实面板热切换。
- 独立入口依赖审计为 11 个测试补齐真实 Vocabulary/Named 等来源；5 个 CPU 模块 33 方法通过，vector 邻类另 1 方法通过。static model document、timeline target compiler、vector 主类仍在旧载体的 DTO/依赖闭包处未能执行；未扩建这些载体或放宽断言。两个 video 入口仅离线编译通过、未执行 GPU；solid 入口因缺 MaterialRenderState 未编译完成，均保留日志，不计测试通过。
- 不认整样本官方 parity、全时相/全属性、MASK/WRITEALPHA 非默认组合、HDR/多屏或性能收益。

## 证据与退出

必要日志、完整固定 A/B/恢复与独立样本 PNG、默认滚动预览、测试/身份/失败/审查收据归 `.artifacts/scene-evidence/runs/declared-texture-rgb-graph-20261024/`。默认滚动预览为缩放 JPEG，保原 PNG 哈希，不作精确像素 oracle；正式包经 CRC 与逐成员哈希验证，按 32 MiB/14 天/总量 5 GiB 规则保留。组合构建、独立入口依赖审计与提交前检查另归 `.artifacts/scene-evidence/runs/declared-texture-rgb-graph-closeout-20261024/`，不修改原正式包。

临时样本、staged App、CPU binary/module cache、连续构建缓存和冻结源码在归档核验后清理；其他会话的试用 App 与启动专项未提交文件保留。按用户要求，本批窄提交后暂停长期 Goal，不开始下一项。
