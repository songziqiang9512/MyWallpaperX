<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。合同归[运行架构](../architecture/runtime-architecture.md)，结果归[证据索引](../capabilities/runtime-evidence-current.md)，余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 共享纹理就绪开关的启动枚举（2026-10-12）

## 通用语义与修复范围

同一 presence combo 下，原schema seed保证共同生效、无额外运行条件、仅由 asset/user-property 候选供给的 sampler，假设启动状态必须保留共同就绪与共同缺席。基线 `4e0381d4` 独立枚举两个槽的四种状态，混合状态被原 resolver 拒绝，继而使合法材质的资源需求并集和启动准备全部失败。

仅在既有 `SceneResolvedMaterialShaderSchema.launchAvailabilityMasks` 排除上述已证明共同生效的矛盾假设；资源需求与启动准备两消费者继续共享该入口。实际帧 resolver 未改：真实混合、缺失 readiness、作者 default 与显式 combo 冲突仍拒绝。非共同生效的条件备选、runtime requirements、graph/provider 必需输入、graph alias 和缺候选的组不施加此约束。未选择未知的官方混合资源 OR/AND/最后写入政策，未增资源 owner、算法分支或路径/hash例外。

研究只交付中性接口合同；批准文件独立绑定合同 SHA，保留原合同身份。产品实现上下文未消费作者私有源码。证据根 `.artifacts/tmp/n04-resource-followup-20261012`，自有输入失败及修后行为、App身份、真实截图分别保留。

## 实际结果与验收边界

- 自有输入修前 masks 为0/2/4/6；资源需求与启动均因共享开关冲突失败。改名、等价 guard/表达式、声明和metadata换序仍失败。修后共同状态为0/6，普通、改名、无guard及共同自条件四种输入的实际Metal读回均为四个[100,0,50,255]像素；无guard仅编译ready变体6。真实一ready一absent仍在launch投影后以原冲突拒绝。独立combo、互斥条件/requirements、provider/graph/alias、缺候选、错误default/override与metadata反例保留。4项新测试、2项variant与12项async最近测试通过，标准runner与既有sampler邻门通过；GPU夹具不等同真实compositor验收。
- Debug构建和严格签名通过。真实3815761795的233/effect0旧首错已消失，继续到 `color/colorContractUnproven:shader-color-transfer-unresolved`，仍有0个material node、1个拒绝节点并局部透传。实际底部白色区域仍在，**水面效果尚未恢复**。本批关闭一处准备期误拒，不计算该样本画面修复完成；下一批沿原颜色语义分析查新首错，不放宽颜色检查。
- 未参与实现或调参的3750813609修前/后实际窗口均保留山林、雨线与大时钟；后验提交226、完成225、呈现224、failed0，退出GPU排空。只是独立回归，不证明闪电/辉光全对、桌面入口、系统音源、官方parity或性能提升。
- 3039882306另行复验：原静态 fallback unavailable 仍存在；在隔离副本添加自有RGB色带并初始选择后，1084的原 user-property provider 编码成功，实际背景色带与作者前景文字可见。因此绑定没有丢失，不另造加载链。未验热更新/reset，fallback加载失败仍开放。

真实样本只读，隔离输入和HOME用于运行。核对104个原始文件未变；清理约675 MiB临时输入/HOME、生成shader和重复图，必要截图、压缩报告与日志保留。结构15项、依赖、防御、代码健康及设计门通过；残留门仅旧218字节.mimosa，未知归属保留。收尾身份与独立审查绑定同包manifest；唯一增量缓存仍为 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。证据推广因既有总预算用尽被拒，未提高预算或删除未知材料；本包约28 MiB暂留上述ignored目录。本批不推送、不发布，不关闭N04或长期Goal。
