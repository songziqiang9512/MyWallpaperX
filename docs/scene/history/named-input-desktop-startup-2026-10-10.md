# Named 输入颜色合同与桌面启动（2026-10-10）

> **历史证据 — 非现役入口**。当前状态归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本页只保留本批根因、验证身份及边界。

## 根因与最小修复

基线 `702262d5782b554424e107932e15495d4687dfb3`。用户先报告安装版不能启动3078285611、2974757317，后确认Xcode构建同样失败。隔离HOME与只读原包的测试副本使用普通 `--mwx-scene-daemon`、真实桌面surface和默认系统媒体；不使用debug截图窗口，不操作用户正在运行的App。

307在安装版、基线Release及同Scene源码Debug均首帧零提交。297在Debug同样失败。两者分别在layer192与1314出现 `dependency-input-mismatch`，候选首帧超时是后果，不是需要延长的预算。

307精确诊断：同一个纹理、epoch及effect slot，预留写PMA而实际raw image capture发布straight-alpha。`reserveEffectInput`改复用capture的颜色表示判定；geometry、solid、main capture仍PMA，prepared graph output仍由原graph权威填写。严格identity比较不放宽，像素采集算法不变。

第一处修复后，307继续暴露 `textureMetadataIncomplete`：slot1为named图层颜色，`providerColorSlots=[1]`，sampler为rgbMask、selectedPurpose=nil；ordinary边界又按sampler模式把这个已有类型证明丢弃。过滤改保留已证provider颜色槽，复用现有shader输入颜色转换。typed data在此前已剔除、conditional scalar在此后仍剔除，不将蒙版数据误转为颜色；没有新算法、新provider或按样本分支。boundary已经进入request/analysis缓存键与artifact一致性检查，无需再升namespace。

## 验证记录

最终构建无临时诊断改动。Debug dylib SHA `085f7268bee298d819d79f94a3ea49a9b10860136986265581a58325b696cd83`；Release exe SHA `8dd608ab97dece74b700fc063abac6440ef67f94aa5aa446c7da74b019173f66`。两者构建、严格签名检查通过，729个Scene Swift/Metal源与隔离构建树字节一致。

所有运行请求30fps，首帧后观察约33秒。Debug 307首帧24.20秒、211提交/2drop；297首帧26.42秒、406提交/407drop，两者真实媒体进入后持续出帧。Debug慢帧仍存在，不能用启动修复关闭性能项。

追加样本Debug：2938612768首帧24.90秒、881提交/0drop；3395777145首帧27.00秒、949提交/0drop。对应Release分别10.95秒、955提交/11drop，以及11.09秒、963提交/0drop。两者封面、歌曲文字可见，媒体事件后继续播放。293已有官方截图为无媒体/不同布局状态，时钟位于右下而本次在卡片下方；属性身份未知，不据此判颜色或布局正确。339有一处`compiler-normalization-varyingunsupported`进入既有shared-backend fallback，未据该日志判效果缺失；完整effect消费、真实频谱及官方同状态视觉仍待验。

两原样本Release：307首帧9.54秒、963提交/5drop；297首帧10.65秒、955提交/8drop。二者从零提交恢复到持续播放，已有媒体动态进入。所有8次最终运行都exit0，真实像素留存；只读普通桌面daemon不等于App音频采集转发验收。当前重现场景的启动阻断已闭，整样本视觉、全部特效/交互仍未关闭。

Raw预留门在旧产品上编译/运行成功，两个straight raw分支及mixed aggregate明确因预留content错误失败，实际GPU字节仍正确；这证明修复的是合同错配而非重写像素算法。首次旧harness缺uniform成员造成的compile失败另存，不算行为反例。raw最终9项全部通过，含原有geometry、资源拒绝、resize/cancel、过期句柄与多消费者控制。颜色输入门在最终同fixture旧产品上两backend均行为红，修后完整4项通过，包含half-alpha PMA/straight等价与preserved数据不转换。中途一次`StopIteration`是fixture误用bounded profile辅助集合识别mixed variant，已按真实typed候选修正；旧失败源码/日志绑定收据保留，不算产品缺陷。两套门只覆盖各自owner，完整桌面提交由8次App运行证明，不宣称全finalizer组合已测。

独立只读审查核对三个产品文件、真实GPU回归和构建/运行身份，无阻断。Scene结构、依赖、defense、设计门通过。本批同时补登记此前两份本线程历史记录及历史入口。全仓门仍有本批未修改的Web 1008行、两份Web文档入口缺链接、既存文档预算/导航收据超限，以及未知归属`.mimosa`；不修改基线掩盖，也不删除未知文件。

## Debug、Release与未覆盖边界

安装版2.10.0/280的源码提交未知，不能由相同版本号判同源码。安装exe SHA `4e8151cb4e26bd230a02195dd736c161c43e05037c1a01cfd785d7ba70b50f46`；基线Release exe SHA `6c8f784e311131c6b27b6aa6a997a846afb64ca2e3ba914826804d69de809581`。只读包检查：两者App及compiler helper签名通过，8份license、2273份StockAssets相同，没有证实打包缺件导致本次失败。构建中的Debug资源签名快照无效，已撤回，不记产品缺陷。

Debug使用Swift `-Onone`、测试能力与Metal源码调试信息；Release启用优化和wholemodule。当前普通桌面失败发生在两配置共享的准备/提交合同，不能归于优化器。启动速度和稳态FPS还受缓存、作者内容、媒体、显示与其他运行进程影响；这里的少量有界运行不是性能基准。隔离daemon仍未覆盖App音频采集转发、全部设置/交互和正式分发签名环境；297的U35多余矩形、307作者脚本异常及3662790108偶发启动失败独立保留。

最终有界证据包 `.artifacts/tmp/release-parity-20261010/evidence-bundle.zip`（6,550,276字节，SHA `b2653f83608170ce392a88cddcc6e56e5f34be93cfacbe4f2ca4d29c30fe0ecd`）含红绿、8次最终桌面、必要前后图片、失败根因与身份。正式证据库晋升受既有1GiB预算阻挡，不扩预算、不删除他人材料；到期清理无可删除项。已清本轮停止的HOME/TMP、测试编译缓存及五份样本副本，逻辑字节约2.33GB（不宣称APFS物理释放量），保留清理收据。连续迭代只复用 `.build-cache/solid-source-domains-recovery-20261009` 一份构建缓存及其隔离源码worktree；安装版App和原始样本未改。
