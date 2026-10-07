# 混合纹理颜色输入合同修复

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-08；本页保存已完成修复的固定证据。当前合同归[运行架构](../architecture/runtime-architecture.md)，待办归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 问题与改动

真实3078285611的layer192/effect2使用named图层189和可选上一张媒体封面作为同槽两候选。named publication已经生成，特效却因`material-optional-named-fallback-unproven`透传，未执行作者材质。

真实编译器工件的两个ordinary变体分别携带PMA槽`[1]`和`[]`；旧accepted返回值丢弃该字段，Frontend又用bounded规则重推，两者最终都变成`[]`。修复仅让ArtifactCache.accepted携带其已验证的槽集合，Frontend/Compilation发布同一集合；bounded分支继续发布自身实际编译输入。没有放宽exact mixed证明、候选链、资源身份或失败半径，也没有新增渲染算法、profile或运行owner；default color boundary仍由colorTransfer独立表达。

## 冻结验证

证据根：`/private/tmp/mwx-named-fallback-20261008`。基线`cccea6c1`；新签名Debug App executable SHA `659c24640291bf6e0961d3798c25877736abe534f1307006013636168bbcd2a9`，实际代码dylib SHA `f702a66d2f26582afcefc99f9e9e788b2a5d8f8b6401ef42c6a9661698ac4118`。产品输入与签名由`build-receipt.json`固定。

| 输入与门 | 结果及上限 |
|---|---|
| 真实作者contract `48f5a051…`经过生产VariantCache | 前后均两个genericCompilerArtifact；原工件已具正确ABI，修后下游PMA变为`[1]`/`[]`，exactMixedProof由false变true；复用相同工件key。`review/`保留完整身份及失败探针日志 |
| 自有三sampler半透明色+mask，named/system两候选 | 旧App ready/after均白255/255/255；修后均在预注册RGB50/20/40容差2内，provider捕获、绑定、GPU完成与最终ROI成立；健康peer保持绿色。三个候选仍局部降级，不伪造named输出 |
| 原有两候选/三候选App门 | 两项均通过，与新门合计四项实际App正反例；`integration-final/` |
| 原307包和颜色热切 | 原包SHA `dfad976105f6d3dc9138c759922872c31ffc6994fdffdd8c6c69fe3b728f488a`；benchmark由前批FAIL转本批PASS。192/effect2的首帧/下一帧均materialNodes=1、GPU completed、compositorConsumed=true，依赖189，named binding成功；颜色热切同窗口343156。`native-receipt.json` |
| CPU/结构 | typed ABI、artifact/owner、source sets/local failure、background合同及结构门通过；正常签名Debug build成功 |
| 原graph大门 | **仍FAIL**：同harness在基线与候选均271检查、同30项false，新增失败0；六项mixed/system潜在依赖反例均true。该harness固定disable-generic，不替代本批generic/App证据。`graph-regressions-comparison.json` |

最初probe混合源码编译失败与漏mask readiness的执行失败均保留，之后固定完整源码/合法资源才取得有效前后证据。自有App源材质准备日志中的`source:22/white.png`未证用途不属于effect slot2；没有用全局计数推断mask失败或修改颜色期待来过门。

## 未覆盖与产物

307仍有layer60/effect6、22、24的speed脚本`TypeError: toPrimitive`及有界粒子限制。此次没有真实播放器换曲、previous封面过渡、全部交互或官方画面对照；benchmark PASS不能解释为整样本正确率。性能测量不满足稳定窗口，不宣称性能收益。受益合同是已编译generic材质中named/optional共享槽的正确接线，不能外推所有243样本。

已停probe/App、媒体副本、测试HOME和缓存按本批cleanup/retention收据清理；保留日志、输入/代码身份、可重跑探针与必要PNG。唯一连续构建缓存继续保留`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。30项基线检查失败转待归因队列；其余共因继续按纹理合成、特效/频谱顺序处理。
