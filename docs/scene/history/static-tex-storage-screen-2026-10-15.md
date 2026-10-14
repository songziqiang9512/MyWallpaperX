<!-- document-role: historical-evidence -->

# 静态 TEX shared/private 局部筛选（2026-10-15）

> **历史证据 — 非现役入口**

现役选序与门槛归[性能卡](../roadmap/performance-convergence-card.md)。结论STOP，不做默认private迁移或App campaign；本次结果不证明所有设备/内容private无收益。

只在临时probe比较真实raw uploader/预算/upload queue、原image pipeline/MSL：3427×897静态RGBA8、5个独立authored mip，smooth/noise两固定输入；B仅多同格式逐mip复制到private。单CB/encoder/quad、相同sampler/target/uniform，一次编译共binary `84c742535593ff52e0a6d424029054522cfb7f927625e322457aed0ad6c5b66c`。11真实Swift产品源+原MSL/header，无owner stub；独审后只在scheduler补原预算回落断言并更新freeze，不重编。

先18项真实owner检查全真（各mip/原shader输出、坏尾、预算、故障/批次）；再五对AB/BA、每arm/输入fresh process，64 warm+256 measured CB。唯一一次执行20臂、5120原始值，全部exit0；输入mip SHA一致、staging/final释放观测通过，checks及各臂原预算0→0。没有并行App/测试/编译/profiler。局部短筛未满足正式30s预热/60s稳态条件。

| 输入 | 配对GPU p50降幅中位 | 基线噪声 | 额外准备wall中位 | 判断 |
|---|---:|---:|---:|---|
| smooth | 9.5178% | 119.5925% | +2.941ms | <10%且噪声>5%，无继续资格 |
| noise | −11.6397% | 5.9066% | +3.375ms | 五对B均慢且噪声超限，无稳定规律claim |

smooth第四对shared p50=361.458µs离群，原值保留，不筛除或重跑。copy GPU中位smooth236.25µs/noise411.46µs。扣固定target后预算账峰值shared18,711,040B；private暂存+目标37,422,080B。双份峰值和准备代价存在，但这些不是RSS/物理footprint或App首帧；无GPU limiter、App CPU/GPU/能耗结论。

PreparedDeviceResources publication/cache eviction、Session/Coordinator取消/代次/替换/退出未接此小fixture，不模拟。PNG生成mip、嵌入图/PMA转换、动画/volume/BC/MPS不外推；若未来另有实际热点证据，按新问题重新设计，不惯性改shader/sampler或加draw放大差异。

材料在`.artifacts/tmp/static-tex-storage-screen-20261015/`：协议/独审、18输入freeze、临时源码、build identity与proof原始值/summary/screen-receipt。临时module-cache、binary/objects已精确清52,919,356B；未改产品，不重建App。[CPU pin基线](native-cpu-allocation-screen-2026-10-15.md#pin-retirement-baseline)亦未获产品实施资格；后继核属性通知引起的外层详情重复重建。
