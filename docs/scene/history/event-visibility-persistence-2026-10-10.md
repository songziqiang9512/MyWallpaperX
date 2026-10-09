<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定消费合同归[属性能力](../capabilities/runtime-input-property-coverage.md)，后续任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。只关闭有运行证据的窗口回归，不代表全样本验收。

# 事件型显隐写入持久修复（2026-10-10）

## 首断点与实现

U16 `3122339805` 的 EYES（父144）与 NUMBERS（父207）作者显隐绑定默认 false，同时引用 hideeyeswindow/hidenumberswindow；两属性默认 false，applyUserProperties 明确写入相反的 visible=true，且没有 update。基线 VM 和 frame0 正确发布 true，frame1 退回 userProperty=false，完整子树消失。

首错是 Boolean 校验把本层 visible setter 折叠为瞬时 Bool 后丢弃 mutation；事件 owner 休眠时没有新输出。现在仅在没有 update 时保留显式 setter，沿原 DynamicLayerRuntime authoredLayerValues/preflight/commit，与 origin/scale 写入相同。未增加 VM 执行、持久字典、显隐计算或 compositor。主动 update 仍只发布当帧值，避免 init/属性 setter 固定后续返回；纯输入透传不生成持久值；effect/Puppet Bool 的既有准入不变。失败的新事件不提交，保留前次已提交修改；可恢复准入拒绝沿原事件水位重试，VM exception按现合同永久停用该owner。

## 冻结身份与实际输出

证据根 `.artifacts/tmp/pixels-windows-20261010`。基线 Scene `2e0f6514`，产品只改上述校验与唯一调用点。Debug 构建精确复制并冻结全部761个 Scene 源文件，独立旧 Web checkout 避开并行改动；不称完整 HEAD/release 构建。签名验证通过，debug dylib SHA `ed642e7bad3cda62815ba17c9be62a35f6f599b5754ba52f70f4ac255c806506`；完整 App/输入/Scene SHA 在 build-candidate.json、input.json。

真实媒体只读，五次运行用相同包的隔离副本、独立 HOME：

| 运行 | PID | 实际观察 |
|---|---:|---|
| baseline | 52343 | 两父层 frame0 true→frame1 false，窗口消失 |
| fixed-default | 56369 | 两父层持续 sceneScript=true，EYES 视频、NUMBERS三列数字和子层显示；数字随时间更新 |
| live-toggle | 57078 | 四次属性批次接受，同一个 window9861/surface；两窗隐藏→显示，随后单独EYES隐藏→显示，未重建 |
| drag-eyes | 58322 | cursorDown→captured Move→Up；父144 origin从633.80573,701.87219变为775.126348,780.712217，子树一起移动 |
| drag-numbers | 58486 | 同一拖动链；父207 origin从1250,800变为1083.740479,744.380005，子树一起移动 |

均约25秒实际播放、exit0、gpuDrained=true、无SceneScript VM失败。默认活动effect中，实际material/GPU/compositor完成的独立effect从13变14（窗口478的Tint恢复消费）；17项是作者声明，不直接作活动能力分母。其余已活动13项仍执行。内部Host runner验证了真实资源/VM/Metal/输入链，不替代普通App选择→client/daemon入口或长期运行验收。

EYES中心黑块是原视频内容：从原TEX提取未修改MP4，独立解码1秒帧已含同形黑块；官方截屏也含此黑区。不能因黑色面积误加合成修复。X icon未声明关闭handler，不把作者图案误记成缺少关闭交互。独立局部对照以标题栏/按钮框归一：EYES/NUMBERS标题中心Y差约−0.50/−0.29像素，X中心差最大0.58像素；栅格/取整不确定性约±1像素，支持无明显偏移，与用户实机复核一致，不宣称精确像素parity。

## 验证与范围

原Boolean与initialization事务26门通过；新增事件显隐测试使用真实VM→typed result→DynamicLayerRuntime准入/提交→SnapshotResolver→parent-aware visibility，覆盖同target反向user输入、连续休眠、属性反转、拒绝与重试、无setter透传、active update不固定旧值。新增5门全部通过，另有15项结构门及依赖/防御门通过；异常fuse与可恢复拒绝重试分别断言。独立审查身份见本机freeze/review收据。

窗口专项显示/热切/拖动三项已进入真实链路。文字/X偏移由用户在本轮实机复核确认为前几批已恢复，本批不修改字体/位置算法；全部设置组合、真实媒体来源、重复同会话拖动与多屏尚未验，不报整样本完整正确率。公共修复适用于同类无update的显隐setter，实际已证受益是本样本两个父窗口及其子树；不据源码匹配声称其他样本全部通过。

## 保留

本批必要输入/App身份、测试日志、运行日志与有限截图压缩保留于上述证据根；临时HOME、媒体副本及生成shader缓存在收尾提取后删除。沿用唯一构建缓存 `.build-cache/solid-source-domains-recovery-20261009`。并行Web提交不纳入Scene diff；不推送。
