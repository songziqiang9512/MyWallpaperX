<!-- document-role: historical-evidence -->
# 双视频默认播放与Xray当前复核：2026-10-28

> **历史证据 — 非现役入口**：用户确认关闭两份样本的双视频/Xray反馈；当前任务归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，运行摘要归[当前证据](../capabilities/runtime-evidence-current.md#video-pair-current-recheck-20261028)。不据此重开视频同步或性能原型。

<a id="decision-and-scope"></a>
## 结论与范围

用户明确确认 `3775355045`、`3775373546` 两份双视频及Xray正常，要求移出断点队列并停止研究。Root及独审查看同一签名Debug App的22秒默认属性、中心pointer、静音跨loop原图：局部Xray仍在，两时刻内容有变化，未见可行动的明显停帧或丢区首错。本批没有产品、测试、时钟或provider算法修改，也没有性能收益结论。

运行复用 `7933c3921` 对应的冻结App；完整构建/签名身份引用[并行切片验证](parallel-script-compatibility-2026-10-28.md#verification)及正式包 `script-compatibility-20261028-reflect-after/current/report.json`。原项目和包身份见各视频正式report；不修改作者内容或扩展全库分母。生成的验收台账继续保存原归档身份，不把旧 `layer-source-not-ready` 或 `unreviewed` 当本轮当前故障。

## 两个窗口的证据边界

两份项目均由front22的作者脚本控制hidden dependency21，Xray23的slot1引用 `_rt_imageLayerComposite_21_a`。保作者0.5秒等待、两帧重seek、duration比及loop重启语义；本轮每对实际duration相等，未验不等duration。

- **18秒数据窗**：两路epoch均为1，generation连续、frame递增，未见相邻新generation重复同一decoded PTS。至少一路新publication的Scene frame并集为929/835，循环最短phase差P50=0、P95约16.67ms、最大50ms；这不是全部提交/呈现帧分母或性能指标。loop处可有一Scene帧跨首尾，不能把线性PTS的大跳当整圈失步，也不能声称完全同帧循环。约第6秒pointer已离开，后续图不作Xray内正控。
- **22秒遮罩正控窗**：现役timing为count2、press5s、held3s、同点位。每份保留 `drag-01-held` 与 `drag-02-released` 两张原图；后一张在loop事件之后、最后outside之前，四原图已被查看。两run均exit0，surface停止且GPU drained。这里只认本窗口有界正常，不作逐帧相位或官方像素裁决。

`video-frame-v1` 是Host接受surface提交后的provider commit，含requested/decoded PTS与content generation；它不等于逐帧GPU完成或PTS到最终像素映射。独立last-ready与单帧跨圈观察不足以支持全局锁步、PTS clamp或新缓存，故不实施候选。

## 留存与退出

主工作区正式包为 `.artifacts/scene-evidence/runs/video-pair-current-recheck-{3775355045,3775373546}-20261028/`，分别约11.8/11.9MiB，普通14天，单包≤32MiB、总预算5GiB。每包保两张上述原PNG、18/22秒原app.log、22秒preview/runtime输入、PTS摘要与停止收据；App身份引用既有reflect-after包。report中ready/after仅为收集器别名，真实drag文件名、用途和时刻已明列，不改称ready/after采样。

临时inputs、HOME、重复截图及可重建shader在归档核验后清理；复用App与唯一build-cache留给Root后继任务。旧视频定位修复和独立WebM的范围仍见[原证据](../capabilities/runtime-evidence-current.md#video-position-publication-20261022)，不追认其截图为跨loop正控。本批不认官方同phase/parity、长稳pacing、Release/HDR、多屏或性能；其他视频及U22长期反馈不随两份用户确认关闭。
