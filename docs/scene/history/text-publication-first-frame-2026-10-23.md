# 动态文字发布与候选首帧保留

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。截止2026-10-23；稳定职责归[启动合同](../architecture/scene-launch-responsiveness-contract.md#initial-video-presentation)，当前运行归[证据索引](../capabilities/runtime-evidence-current.md)，开放问题归[队列](../roadmap/scene-open-breakpoint-queue.md)。只关闭这条发布通知导致的启动失败，不代表全场景验收。

<a id="text-publication-first-frame-20261023"></a>
## 最早职责与修复

动态文字的accepted raster尚未被下一帧采用，却以`.surface`通知Session。候选首帧已提交并held等待GPU时，这种通知撤销attempt、重新启动cadence；高频文字使成功GPU callback始终属于旧token，Host最终超时。纹理store已持有新raster，已提交帧仍持原引用，通知本身不使冻结帧失效。

MetalView改发独立`.textPublication`，Session只在held期间与media publication一起延后处理；promote沿原reset、清提交标记及driver补画，下一帧由唯一text provider读取最新结果。未held的文字仍补画，不能走media专属暂停刷新。未增加队列、owner或超时；真实尺寸/输出环境/资源失效、surface替换、取消、GPU失败和Host提升权威不变。

## 反例与实际输出

同一CPU harness执行从产品提取的真实text producer、Session回调、SurfaceSubmission、Cohort与PreparedFrame。旧`ae334f7d7`在held单双屏、publication先于GPU失败、delivered后publication四场景实际RED；真实surface失效和active-paused文字两相邻场景PASS。候选18/18 PASS，保留旧12场景并校正提取位置；active重试不再错误期待候选Host回调，原重试期限/旧对象/取消断言仍在。另8项cohort及Host activation失败/完成顺序/drain门通过；这些为CPU受控terminal，不冒充真实GPU故障。

固定`ae334f7d7`加两产品文件的签名优化Debug通过；App SHA256 `c229d27f6037fafcda7121f5a0bc85f1be435e53f1100fce1e5ae2d9e4252625`。1165份Swift/Metal/头文件及构建定义核对冻结导出，排除并行UI未提交修改；嵌套签名与strict验证通过。

- 原`3662790108`：相同project/PKG、10秒运行/after6。纯`1ac578a18`旧App为94次attempt、29次held、零Host首帧/提升；候选一次attempt/held即一次Host首帧和提升。实际开场中英文说明与图标出现、可见帧持续输出，正常停止排空。候选总ready约19.4秒包含装载，不宣称启动性能提升；后续太阳系、完整交互、作者灯光与官方同状态未验。
- 独立`3321237804`：普通视频先发布再提升，人物背景、光束、时间/日期与频谱保留；15次候选尝试等待内容，一次held/Host提升。前后快照不是相位或音频锁定的整图对照。
- 既有实际App三门全部通过：冷暂停首视频且VM计数不重跑、资源改名双屏同attempt、坏视频局部fallback；真实红/青终端像素正反例保留。没有调整timeout、内容就绪或旧active门来获得通过。

独立审查核代码、旧红/新绿与实际图像，结论随包保存。未验证Release、HDR显示、物理多屏、真实GPU硬件失败、所有异步组合、长稳或性能；一次恢复不使全样本verdict升为完成。

## 证据与产物

正式包 `.artifacts/scene-evidence/runs/text-publication-first-frame-20261023/` 保存两版本失败/成功身份、生产源冻结、CPU因果反例、App三门输入与像素、366/332原图、构建与独审；单包32MiB、普通14天、总5GiB。原366灯光批的失败收据保持历史含义，不再作为当前未修启动项。

本轮进程与临时HOME已退出，设备交回并行UI会话；停用样本/重复运行输出归档后清理。继续迭代仅保 `.build-cache/video-extraction-demand-20261021` 单份构建缓存与对应冻结源码；不改用户真实样本、安装App、官方VM或另一会话产物。
