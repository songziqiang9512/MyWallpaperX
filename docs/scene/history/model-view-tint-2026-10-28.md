<!-- document-role: historical-evidence -->
# 静态模型视角双色：2026-10-28

> **历史证据 — 非现役入口**：当前问题由[断点队列](../roadmap/scene-open-breakpoint-queue.md)拥有，本文仅记录本批验证边界。

基线 `a6e86559a`，独立工作树 `MWX/scene-capability-followup`。本批只修无 Tint Mask 的视角权重及 tint 的提前 Half；不扩展 Chroma 表面 profile。

## 已复现的公共语义

合法 stock chroma4 的输入行为区分 mask 与无 mask；无 mask 为 signed facing 的线性双色，指数只属于 mask 分支。343 的 Cloud114 确为 chroma4、mask0，现准备结果走 legacy 模型 consumer；Earth112 另有 generic4 profile。修前把两者都截至0…1后指数化，改 exponent 会错误改变无 mask 输出；大 tint 端点在有效乘积前转 Half 会误饱和。

在原 `SceneStaticModel.metal` 复用既有 `materialFlags.w` 分流权重、统一 Float tint 乘法。coverage、PMA、零覆盖 discard、深度和资源/取消链不变；产品净减7行，无新 owner/持久状态。保留 masked 现行为；未声称补齐 mask 纹理混合或整个 Chroma。

## 验证与身份

- 原产品运行扩展后的现役 `test_scene_static_model_emission` 为 RED（20项失败），候选6个行为门全部通过；复用生产 ModelPipeline/MSL，不另造 renderer。
- 独立手算 RGB/A：facing .5、front .75/back .5、基色 .25/coverage .5，无 mask 输出 `.078125/.5`，exp2/4相同；mask分别 `.0703125/.5`、`.064453125/.5`。负 facing -.5 为 `.046875/.5`；法线等比例/载体标签变体、PMA输入、layer fade及等色反例通过。原 emission/fog/表面灯光/HDR边界继续通过。
- Debug 基线与候选构建均成功，6217输入各自冻结且构建期间无漂移；候选增量14.69秒。两份 App 分别真 Team `H9QWU9XN8R` 签名并严格验证，benchmark 前后身份一致。
- 原包343与未参与修法的361各做修前/修后9秒，固定pointer、静音输入，全部exit0、loaded1.0、surface1→0、GPU排空。候选361保罐体、白圈与文字；只证 renderer 相邻健康，不是第二个 Chroma 受益样本。
- 默认343两轮 `colour="2"`，Cloud动态back色相同；Earth/Cloud会按update累计旋转，现报告未绑定snapshot frame，故不能把全部像素差异归给tint。完整官方图还存在viewport/时刻差异，不认整景对齐。
- 仅补两次固定姿态控制：复用同两份已签App和合法启动属性`earthrotation=0`，6秒/固定pointer/静音；各约19.7/19.9秒（含准备与停止），exit0、身份未变、surface1→0/GPU排空。Cloud前三帧world一致。预定全地球ROI的8位可视RGB平均绝对差`.575/.271/.126`，右夜区`.151/.091/.031`；天空对照`0/0/.000026`。这确认局部小幅tint响应，不代表完整夜侧或官方贴合；原始PNG保留，8位统计不冒充线性HDR。
- 独立只读审查未发现本diff新P1/P2。遗留 legacy `litColor` 仍有 Half 转换，不能称任意有限HDR安全；masked纹理混合与完整表面参数不由本批扩展。

## 保留与剩余

必要身份、输入冻结、红绿/治理日志、实际报告及固定姿态修前/修后原图归主仓`.artifacts/scene-evidence/runs/model-view-tint-20261028-baseline/`与`model-view-tint-20261028-candidate/`。同阶段合成一包，均小于32MiB；报告保留原裁决并明确未归档的默认343重复截图。普通结果14天、总预算5GiB。两个已停止的staged App、HOME、样本副本与冗余结果当轮清理；连续后继只留一份构建缓存。

343 的完整夜侧光色/宽暗区因果、MR/specular/pigment、间歇全屏闪烁与collision继续由现役队列拥有。未做CPU/GPU/启动收益比较，无性能收益结论。
