<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。现役顺序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)；样本调试现状归[调试台账](../capabilities/scene-sample-debug-ledger.md)，稳定合同见[运行架构](../architecture/runtime-architecture.md)，当前结果见[运行证据](../capabilities/runtime-evidence-current.md)。

# L1 重型样本普通入口 fresh 复测（当前 HEAD，2026-10-07）

起点 `c0ecd5ca`（光照合同+mixed 收口后）。承接[重型入口复验](heavy-entry-verify-and-saturn-exposure-2026-10-06.md)（基线 `dead0a10`：三体 ~14.5s/土星 ~15.1s launched、无可复现启动失败、关闭待用户实机复测）。

## 启动复测（产品完整入口链，无回归）

签名 Debug App（同源码树，HDR 批 staging 复用）经 `--mwx-debug-scene-daemon-client --mwx-debug-scene-daemon-stable --mwx-debug-scene-product-entry` 完整链、隔离 HOME/defaults/Workshop 副本：

| 样本 | launched | 首帧 | 结束 | 收尾 |
|---|---|---|---|---|
| 三体 `3509243656` | ~14s（04:29:16→04:29:30 ready） | session-first-frame | 120s exit0 | Particle/Surface/SceneScript VM lifecycle 全部干净 |
| 土星 `3589454154` | ~14s（04:31:23→04:31:37 ready） | session-first-frame | 120s exit0 | 同上 |

两样本零 `scene-*-export-unavailable`、零 frontend failure。**启动无回归**，与 10-06 基线一致。

## 视觉状态（修正本会话初判的"整景黑"）

调试入口 90s 探针（5s 周期快照）初判"整景黑"系**本会话临时 16 位 PNG 解码器 bug**（字节级 unfilter 对 depth=16 PNG 产生全零），经 PIL 交叉解码与用户实机观察（"那个样本实际运行我看是挺正常的"）推翻：当前 HEAD 渲染正常——银河星野、时钟（04:46 Wednesday）、三体星体与坐标/状态文字块全部在帧（快照 `scene-series-0016`，PIL 解码 mean 12.3、95% 非零，符合暗空场景）。

顺带在当前 HEAD 复核了调试台账两记录的时效：MAIN 的 sceneScript visibility producer **已执行**（`frame=1 source=sceneScript value=true`），坐标文字（layer 337 State2）content **已发布**（9 UTF-8 bytes）且可见——旧"MAIN 未执行 / text undefined"记录为旧空输入状态（与[既有修正](../capabilities/scene-sample-debug-ledger.md)一致），非当前 HEAD 行为。

## 结论与下一断点

- 三体启动关闭条件（用户实机确认正常）已满足：**L1 启动项关闭**；土星入口同测通过。
- 剩余未验收：三体模拟/坐标文字细项、整样本逐项人工验收；本批未发现新的产品缺陷，无产品代码改动。
- 方法教训：**快照取证必须用成熟解码器**（PIL/sips）；本会话自写字节级 16 位 unfilter 的全零输出曾误判"整景黑"，被用户实机观察纠正。
- 产物 `/private/tmp/mwx-l1-retest-20261007/`（两产品入口日志、探针快照、时间戳）保留至 2026-10-21。

## 土星官方截图对比（用户指派，同日追加）

用户提供官方客户端截图（`~/Movies/MyWallpaperX/创意工坊/Scene/3589454154/截屏2026-10-06 10.07.18.png`，只读引用；WE/Windows，3248×1952）。我方 75s 调试探针（5s 周期快照）末帧（~75s，过场后稳态）对齐比较：

| 指标 | 官方 | 我方 HEAD |
|---|---|---|
| 全图 mean / near-white>250 | 17.75 / 0.1% | 16.89 / 0.03% |
| 土星盘面 | 暖棕云带、右侧明暗界线，清晰受光 | **纯黑剪影，无任何受光/云带** |
| 光环 | 暖米色、卡西尼缝与颗粒可辨 | 存在但极暗（近黑灰） |
| 背景 | 黑空+稀疏暗星 | 蓝灰放射状光轴纹理（异常） |
| 文字（日期/SATURN/音量行） | 正常 | 正常 |

**近白指标盲区**：10-06 修复验证用的"近白 8.1→0.0%/17.5→1.9%"无法区分"正确照亮"与"打黑"——当前 HEAD 盘面已从修复前的 89% 顶格白变为**完全未受光**。回归窗口在[光照能量合同批](model-light-energy-contract-implementation-2026-10-06.md)（当时仅验证近白下降）之后的光照语义批（弧度直读/lightconfig 门控/typed lightAngles）。

**新首断点=静态模型灯光送达链**：土星场景 `lightconfig` 四键全开、ambient/skylight 黑（合合同），照明仅来自 `lpoint` 6.0（radius 100，**origin 脚本读 `shared.sun_pos*`×0.0005**）+ `ldirectional` 5.0（**angles 脚本读 shared**），行星为 24 个静态模型之一。盘面全黑 ⇒ 两灯对静态模型贡献为零。**日志级坐实**（独立终审发现）：`saturn/app.log` 两灯层（433/259）每帧 `failure=badReturn("non-finite vector output") fallback=current-frame-lower-priority`（badReturn 共 17,256 行）且 `sun_pos` 全日志零命中——`shared.sun_pos*` 无 producer 注册，灯 origin/angles 求值为 NaN 矢量、逐帧拒入；另 `lpoint` 作者 `visible:false`（灯体隐藏，行为不变）。与光照输入语义批的 typed light 通道改动交汇处即修复落点。已入断点队列。


<a id="large-static-model"></a>

## 大型陨石环进入实际链路（2026-10-09 后继）

基线`d33f7bf5`、原包SHA `8cb79fa9f77c992c2bc3c3ea6300af0f058bf5e85b96ae1d1f300fdf3c037bb0`。当前签名App能启动，但479陨石环没有model-material或draw。首错是同一reader在metadata与full decode均以64MiB顶点工作预算拒绝；真实MDLV0023为150,933,888顶点bytes/3,144,456顶点、12,826,368索引bytes/3,206,592索引。完整独立扫描证有限值、bounds、索引与尾部均合法；不是缺shader、normal map或HDR终端原因。

沿原reader将累计顶点输入预算扩大至256MiB，索引32MiB/材质段64及全部结构验证不变；GPU仍走原SceneResourceBudget，不扩大总账、不拆模型绕限、不新增加载链。旧几何identity会另分配163,760,256-byte序列化Data，现改64KiB分块SHA，保原canonical字流/digest。单模型最坏decoded顶点约341MiB，输入UInt16索引扩UInt32后最多约64MiB；mapped输入、已建GPU buffer和upload瞬态还可能共存，不能称405MiB为RSS保证。取舍是恢复合法重型输入，并限制新增哈希复制；不宣称减少真实新增几何的成本。

旧真实reader在两个入口均明确budget拒绝；新优化CPU探针完整metadata/decode通过，进程峰值384,172,032 bytes。最终签名Debug dylib `ca7722f65e7d228da637420d937e4ab763986e4eb5b3ab5fe7d47e07f73ae40d`，两产品源与构建冻结一致。原包副本80秒实际运行：479材料authored，frame0与2进入同一静态模型GPU并completed，最终截图恢复环上大量陨石颗粒；exit0/gpuDrained。Debug冷启动13.8→39.8秒，候选进程峰值1,420,623,872 bytes，末段GPU诊断约1.30GB；单次观察不能作优化/长期稳态结论。243包只读头部扫描仅此模型超过旧顶点上限，不能声称多个样本已实测受益；分块hash适用于全部静态模型。

同日官方2.8.0.42于19:58:25、原包和project与native相同、1210×786 viewport：左侧球面亮而右半黑，前景星环大段明亮。候选仍有球体双侧亮、星环暗带/条纹和环影差异，**未关闭土星整体显示**。两端模拟分钟未冻结，不能把截图差直接反推数值光照公式。下一批先用同输入灯/阴影消融定位方向光或材质消费者，禁止全局补亮。HDR输出只读审查未证新缺陷；243包22个默认HDR、16个同时默认Bloom，默认iterations0/1无命中，未因此注销该开放合同。

reader15项通过，含自有越64MiB合法输入、旧边界后的NaN、单段和累计新预算拒绝。parts的9项测试通过，另有App测试类因未配置而显式跳过（实际App由本批单独运行），真实prepared identity跨vertex/narrow/wide index chunk与Python独立字流SHA一致，GPU两帧/配额局部失败及释放回收通过。独立只读审查通过；构建、结构、依赖、代码健康、防御门通过。普通产品IPC、加载中取消、多屏与完整parity未验。

本机证据包`.artifacts/tmp/saturn-model-budget-20261009/saturn-model-evidence.zip`：10,365,046 bytes，SHA256 `7686ff9876cd45b18650e68a35cdec3822abc0d1fe00b8d11ce87f64c07c4634`。总证据缓存仍触及1GiB且无到期项，暂留有界本机包；本批两次已退出运行的副本/HOME/cache、reader原模型副本和探针缓存清理1,248,634,948逻辑bytes。继续复用唯一Debug构建缓存。官方preview已关、VM suspended；独占guest副本保留供受光差异后继，不动用户内容。全局文档门仅剩并行Web预算与入口问题，本批Scene链接/历史authority映射通过。
