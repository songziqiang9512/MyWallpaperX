# 变体分析缓存合同

<!-- document-role: stable-contract -->

本文维护原 `SceneResolvedMaterialVariantAnalysisCache` 的 v23 持久 wire 与校验职责；执行顺序归[性能工作卡](../roadmap/performance-convergence-card.md)，实现、验收和已撤候选归[修复记录](../history/variant-analysis-cache-wire-correction-2026-10-15.md)。

<a id="variant-analysis-wire"></a>

## 集合 wire 与摘要

缓存仍只有现 owner、key、目录和成功编译发布点。读取当前 tier 的记录时，集合字段先以原 wire 数组顺序重建载荷并验证 `recordSHA256`，通过后才转为运行时 Set；不得用 Set 的重新枚举顺序校验旧摘要。新写仅对具有集合语义的字段排序：source-carried RGBA、conditional-generated RGB、same-alpha reconstructed RGB、auxiliary-red 和 color-blend 五类私有 Wire 投影；非集合数组保留原顺序，不全局排序 JSON 数组。

2026-10-16 的[畸形 COMBO 记录局部失败](runtime-architecture.md#malformed-combo-record)改变 preparation 准入，frontend 49、VariantAnalysis v23、DemandAnalysis v6 共同退出旧 tier；旧目录只作 safe miss，不迁移或改写。record wire、字段与摘要算法保持，测试仅在隔离副本显式重封套旧 payload 以继续验证其 wire，不能当作产品接受旧 schema。损坏、版本/字段/key/摘要失配沿原 safe miss 重算；load 不建目录、不修写文件。沿用现 512KiB 单项上限、目录和首次 store 的 prune；4096 是该次 prune 参数，并非持续硬条目上限。不缓存逐节点 graph、格式、purpose、provider/context 准入，普通帧不增加 IO、解析、哈希或诊断。

原 prefix 分析语义变化仍按 schema 失效；新格式不能悄悄破坏旧 reader 的 payload 摘要。旧 binary 自身的 Set 解码误 miss 未被本次修复，同 schema reader 应保留合法 record wire 的原数组顺序，并保证新写后的 fresh-reader 命中。

<a id="variant-analysis-source-pure-extension"></a>

源纯结果扩展在隔离 App 单对短筛中未达预锁继续门，产品原型、回填和临时诊断均已撤回，不能按早期批准设计继续实施；完整边界见上述修复记录。不将 inclusive worker 区间或一次首帧差幅计作稳定 CPU、内存或启动收益。
