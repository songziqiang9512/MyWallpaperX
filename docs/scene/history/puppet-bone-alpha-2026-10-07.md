<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前合同见[高级对象第3.3节](../capabilities/advanced-object-coverage.md#33-骨骼透明度动画)，剩余任务见[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Puppet 骨骼 alpha 修复（2026-10-07）

起点 `2e3173e2`：聚光灯3791967416小眼睛6542在MDLA0006 trailer被拒。reader原先将逐骨骼presence flag要求为零；合法形状是四零字节、bone flag、24组state/964bytes/241floats，再接原keyed flag和29零字节。bone6/7在frames103–107变化，frame105为零，影响372个引用顶点。不能跳过数据后声称动画支持。

## 有界官方证据

仅公开文档、作者资产和客户端黑盒，无私有实现。官方[2.2公告](https://steamcommunity.com/games/431960/announcements/detail/3275829772736032226?l=english)独立列出bone alpha和texture channel animation。固定wallpaper32版本2.8.0.42、SHA256 `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`。

隔离小眼睛、无effect、暂停frame105，原始/全一/全零scalar的24根公开骨骼矩阵完全相同；全零不显示。frame0固定后全一显示，全骨骼0.5半透明而非随层级重复相乘；单opaque与单additive的alpha0/blend0.5均为半透明。白色内部ROI由RGB(237,236,232)变为(208,207,205)，背景(179,179,179)，符合约半覆盖。截图包含栅格边缘与重叠，不将此观察升级为全像素官方parity。多clip alpha冲突、更多权重和额外版本仍未取证。

## 实现、审查与产品验证

先在高级对象第3.3节保存设计，再实施。legacy/modern复用有界per-bone reader，IR保真；同FrameSample插值alpha并使纯alpha动画参与时间变化判定。沿已准备四权重计算coverage，不再乘parent；同一成功顶点提交携带位置、UV、coverage，失败保留上一完整发布。共享vertex为24-byte，普通quad默认coverage1，无alpha的Puppet跳过逐顶点alpha求值。

独立只读审查修正两处遗漏：ColorBlend替代fragment必须在反预乘前同乘RGBA；全一alpha轨道不可阻断既有多clip组合。三个MSL镜像与所有生产端stride一致，没有新增clock、graph或输出owner。最终九产品文件diff SHA256 `238ad280f14b3833d374f62edc9706ab4461b77ad75a6761ccba9c6269bc08b8`，静态审查ACCEPT。

格式门26项（25通过、原有可选fixture1跳过）；临时真实reader逐值核对24×241原始alpha。真实Metal12项覆盖纯alpha插值、隐藏恢复、四权重、父子不重复相乘、首帧/部分失败/恢复、普通quad与两类颜色混合。BGRA(32,64,96,128)×layer alpha0.5×coverage0.5输出(8,16,24,32)；additive/multiply反例均验证预乘RGBA只衰减一次。关联76模块除收尾前文档体量门外均通过，文档同步后复验；构建、门禁与提交后身份日志保留在证据包。

最终Debug build成功，签名App CDHash `dfd07acb83f8d5da900230c0d61930f9accfefed`，team `H9QWU9XN8R`。30秒隔离direct Host回放exit0、无超时：小眼睛由bind回退转为`single-absolute ids=6542`，3396顶点进入world draw，Iris effect有encoded-output；身体原三clip仍进入绘制。series-0001图已目视核对。此证据连接动画加载与真实绘制；透明度精确数值由上述真实Metal反例证明，未做真实样本眨眼全周期逐像素官方对齐。

样本整体仍FAIL：effect CPU invocation、unexpected effect-local passthrough与hover输出阈值。眼部组装/半透明副本、脚本seek、偏暗和barcode仍待闭合；不同viewport/时刻截图不直接用于HDR归因。没有整样本正确率、性能或普通App入口完整验收结论。本次GPU顶点覆盖率限定闭合，不补称多clip alpha、VM/geometry全链原子或所有Puppet能力已完成。

## 产物

证据根`/private/tmp/mwx-puppet-eye-20261007`保留身份、probe输入/脚本、官方数值、少量代表图、格式/Metal/构建/运行日志和manifest。promotion因既有证据缓存总预算不足失败，工具prune没有可清项；保留本包而不删除未知证据。staged App、输入副本、临时HOME、共享/VM测试目录与重试输出清理；VM恢复suspended。继续共用`/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`这一份构建缓存。
