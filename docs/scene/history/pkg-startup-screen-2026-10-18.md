<!-- document-role: historical-evidence -->
<!-- command-policy: historical-only -->

# PKG 读取与资产解析启动筛选（2026-10-18）

> **历史证据 — 非现役入口**

## 裁决与边界

本批不迁移直接 PKG 挂载，也不裁剪作者资产定义。小包成本不足以支撑跨消费者改造；大包确有显著优化机会，但尚无保留完整身份、安全、真实 URL 消费者和驻留内存语义的产品候选。用户随后明确要求收益不足或风险较大时宁可不改，因此停在测量和设计筛选，不修改播放代码，不加后台预编译、不加 Release 诊断，不提交、不推送。

这不是“PKG 挂载没有收益”的结论。未来若重开，须沿 ResourceView 单一 package → loose → stock namespace，在独立候选中覆盖 shader/includes、纹理、粒子、字体、MDL/puppet、音视频和动态依赖，再按[启动合同](../architecture/scene-launch-responsiveness-contract.md)验收；不能用虚构 URL 或持有整包快照到退出换取局部计时。

当前事实仍以[运行事实地图](../architecture/runtime-as-built-map.md)、[资源准入](../architecture/scene-resource-admission.md)与启动合同为准。本文只保存本次固定输入的历史观察，不决定当前开发顺序，也不证明完整视觉兼容、官方一致性或 Release 性能。

## 固定输入与方法

- 基线源码：`ffcd9f6fa837a0919b4049ba431ed659c6df8328`，从提交导出至隔离源码；并行修改不进入测量。真实作品只读，运行使用四个作品的副本。
- 局部 screen：实际 ScenePkgCacheExtractor 对比一次 Data 快照、实际 ScenePkgReader 索引/范围校验及直接取得同一准入 JSON 集合；`swiftc -O -whole-module-optimization`。五对 B/C 交替，四样本、两臂、冷暖，共80进程。消费字节逐项 hash 相同；20次 baseline 暖缓存的路径、大小、mtime、内容均未变化；源码与二进制 hash 固定。
- 冷为新应用 HOME，暖为另起进程复用该 HOME；OS 文件缓存与驱动缓存未清除。两臂都不解析 JSON，也不执行 GPU；direct screen 有意省略整包摘要、非 JSON 导出、完整资源身份和消费者，不是产品 mount。
- 第一版大包 harness 假定所有包内 JSON 都被旧 extractor 导出，遇 `scripts/camera_paths_705.json` 拒绝。v2 baseline 改用实际 extractedPaths，direct 选择同一准入 JSON；四样本全部重跑，旧结果不混入结论。这不是本批产品回归。
- 原生观察：同一签名优化 Debug App，临时验证副本给 SourceFacts 分项计时；runner 经 `setAsWallpaper` 进入实际产品选择，匹配 request 的 first-present，保留 final active record、失败和后续帧。使用 result-dir，不使用会改变 surface 的 evidence-dir。每样本仅一冷一暖，供归因，不是五对产品 A/B；临时观测代码未进入工作区或最终 Release App。

## 局部包阶段结果

单位 ms，中位数。baseline 包阶段还取得准入 JSON 字节；对照的安全/功能边界较窄，不能把两列差值认作可兑现的产品收益。

| 样本 | PKG bytes | baseline 冷/暖 | direct JSON 冷/暖 | baseline 冷/暖最大相对偏差 |
|---|---:|---:|---:|---:|
| 3287715210 | 17,138,241 | 45.832 / 28.364 | 5.864 / 5.722 | 6.9% / 7.7% |
| 2067939514 | 2,118,068 | 23.171 / 11.953 | 3.303 / 3.140 | 4.1% / 14.9% |
| 3662790108 | 569,384,066 | 1234.012 / 738.425 | 78.004 / 79.121 | 30.8% / 8.7% |
| 3173418061 | 414,563,030 | 620.545 / 437.022 | 58.354 / 55.735 | 22.6% / 5.7% |

预登记产品继续门为首帧配对中位改善至少10%、超过两倍基线最大相对噪声、基线噪声不超过5%，非目标状态不明显退化。本批没有完整产品候选，没有通过该门；大包局部 baseline 波动也超门，不删离群点。大包 direct screen 进程峰值 RSS 约554/403MiB；它不证明真实长期挂载的稳态内存收益。

## 原生产品入口的有界归因

单位 ms；每列冷/暖，只是单次观察。四样本八次均匹配首帧、最终 active record 正确、runner failures 为空并持续渲染，不等于作者效果已逐项验收。

| 样本 | 选择至 first-present | 包阶段 | AssetCatalog 解析 | descriptor（含直接 MDL 材质发现） |
|---|---:|---:|---:|---:|
| 3287715210 | 4990.932 / 1465.980 | 39.124 / 22.578 | 43.696 / 41.743 | 0.417 / 0.384 |
| 2067939514 | 7915.832 / 3134.667 | 17.505 / 8.896 | 38.632 / 39.966 | 0.702 / 0.730 |
| 3173418061 | 2672.797 / 2211.408 | 955.759 / 653.928 | 9.317 / 10.253 | 0.373 / 0.443 |
| 3662790108 | 23772.243 / 17400.576 | 1141.056 / 971.398 | 233.022 / 206.251 | 6980.389 / 6695.340 |

ResourceView 枚举/构造约153–249ms，未进一步拆 root；不能未经测量直接归因为 stock。328/206 的主要冷缓存成本仍在后续材质/变体编译；366 的整个descriptor阶段明显大于包阶段，表中计时不能拆出MDL reader独占成本。10-19复核确认，跨阶段模型复用及声明/variant事实缓存已有[历史STOP与不同consumer的归因复核](native-cpu-allocation-screen-2026-10-15.md#mdl-validation-followup-20261019)；本段不再将这些方向列为待实施。后续必须先给出不同实际consumer的可避免工作与稳定成本证据，不能以本表重开旧筛选，不删安全校验，也不把CPU/GPU准备搬进普通帧。

## 资产裁剪与独立审查

独立代理核对四个包：model/material/effect/particle JSON 数分别为328的2/12/8/2、206的8/20/9/2、366的200/566/13/0、317的9/11/1/1；没有确认可安全裁掉的定义。206隐藏粒子由用户属性启用；366仅沿 JSON 可发现215份材质，MDL段目录另外发现350份，剩余1份对应已引用但轻量分析未接纳头形状的 Deimos 模型，不能据此视为未用。目录分析不是几何准入验证。

动态 createLayer 还会消费初始对象未引用的模型命名空间。现 GPU 准备已经消费成功 owner 汇总的动态请求；保留定义集合不等同上传全部 GPU 资源。直接以初始 referencedResourcePaths 裁定义有功能回退风险。

另一独立代理重算80行、核源码/二进制、消费 hash 和暖缓存稳定性，并复核安全和内存边界；支持本批 NO-GO。补保存覆盖四个 IDS 的 wrapper，修正默认 driver 只有两样本的复验入口缺项。

## 证据与产物

原始数值、命令、hash、App身份、八次原生日志和四样本逐行结果保存在本机 `/private/tmp/mwx-pkg-demand-eyr9forw/evidence/report.json` 及同级四个样本目录；重放 wrapper 和 driver 已嵌入报告。证据库提升因现有总预算已满而拒绝，按规则未提高预算或删除未知材料；这些限量原始证据暂留任务目录，不宣称已归档。临时样本、HOME、派生构建与诊断 App已清理；最终普通 Release 从固定提交 `84b85d4713422d97c70ac6eb840630f478edfd9c` 构建，签名和临时观测标记剥离检查通过，已观察主窗口；App单独保留供用户测试，路径见交接。该产物没有本批性能改造，不将 Debug 测量外推为 Release 性能。
