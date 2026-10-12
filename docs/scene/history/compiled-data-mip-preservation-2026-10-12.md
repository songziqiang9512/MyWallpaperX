<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前合同归[运行架构](../architecture/runtime-architecture.md)，运行结果归[证据索引](../capabilities/runtime-evidence-current.md)，未完成项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# 编译纹理的数据用途保留作者 mip（2026-10-12）

## 通用语义与首断点

合法多级 embedded TEX 已经携带作者编译的采样层级；颜色及保留源通道的用途应共同保留这些层级。基线 `a472beb1` 的 `SceneTextureMipUploader.uploadEmbeddedDataImages` 只允许 straight albedo 的多级资源超过单级图片的4096归一化边界，使相同资源的 preserved channels、mask 等用途被拒绝。修复仅移除这项用途限制，复用原上传、candidate、catalog、帧快照及最终材质消费者；不增加资源 owner、解码算法、fallback 或样本例外。

2960821850 的隔离原包在 layer92/effect1 首帧超时。短期诊断确认 slot1 的 `asset:abstract_pack_ix_3:preserved-channels` 为 unavailable，随后已删除诊断产品代码。只读取纹理容器与自有 loader 的独立实验确认：TEXB0003、PNG、header8192×4096、映射及实际基级5160×2160，五级连续缩减；color/straight 候选成功，preserved/mask 精确失败为 `compiled TEX embedded mip chain could not be preserved`。因此问题在资源上传准入，不是媒体身份或 graph 入口丢失。自有4097×2两级纹理在旧实现重现同一拒绝。

单级4096限制、设备尺寸边界、mip连续性、header/实际尺寸一致性、用途和generation检查不变。未把 pending/unavailable 媒体状态改成备用图，不放宽 finalizer 的资源完整性检查。没有新增变量、资源名或源码形状识别规则；资源改名及相邻反例由行为测试验证，实际渲染另验。

证据根为 `.artifacts/tmp/resource-snapshot-20261012`；输入/App身份、producer中性结构、修前失败及后验结果分开保存。不以一次恢复启动宣称整样本或全部纹理效果正确。


## 实际验收与未覆盖范围

- 新增自有三 mip fixture在原 uploader 快照中：七种数据用途×两个文件名均失败；两种颜色用途保留。修后九种2D用途、两种名称共18份候选，实际 Metal blit/readback逐级全字节相等，含零alpha的RGB；小单级正例及超限单级、坏mip表/像素尺寸/header反例通过。没有新增shader表达式规则，变量改名与等价表达式不属于本次新增识别面。
- 最终Debug构建、严格签名校验通过。真实296隔离副本从首帧超时恢复为ready；92的effect0–3均成功执行，最后输出由compositor消费；下一帧与实际窗口确认背景、半透明面板、唱片、文字及粒子。测量段提交193、完成192、呈现191、failed0，退出GPU drain；这不是性能对照。预览准备约64秒，未以启动成功宣称响应性能达标。
- 未参与修复的2932157836修前/后实际窗口均保留人物、蓝色背景、环形效果及星粒；后验提交107、完成106、呈现106、failed0并排空退出。仅作为独立回归，未用其调参；没有真实播放器、完整交互或普通桌面入口验收。
- 用户保存的296官方截图可见相同主要构图；截图viewport、时间和媒体输入不同，未建立逐像素一致性。样本仍有其他准备期拒绝与未验输入，不关闭N05、歌曲来源或整个样本。下一批核对N04其他资源失败的当前首断点，优先复验3039882306与3815761795，区分共同缺口与已被顺带修复的旧记录。

本批只关闭“合法多级数据纹理误拒导致启动失败”这一纵向链；不为整个样本给出未经全面验证的百分比。正式测试和实际运行身份分别保存在测试日志、`final-build-identity.json`及`runtime-summary.json`。


## 收尾

资源producer、sampler优先级、raw上传、完整candidate及JPEG方向最近门通过；其中旧方向测试的裸import无法从标准runner加载，改为现有package路径后通过，产品行为未扩域。结构15项、文档17项、代码健康/依赖/防御及设计门通过；残留门仅报告既有218字节`.mimosa`，归属未知保留。独立只读审查绑定最终产品、测试和运行身份，不把静态准入判断当实际复现。

核对两份原始样本93个文件哈希未变，所有本轮App已退出并GPU drain；清理约276 MiB样本副本、HOME及重复首帧图，保留约23 MiB必要截图、压缩运行报告、日志、manifest与自有probe。证据推广因已有缓存总预算用尽被拒，未提高预算或删未知证据；本包暂保留在上述ignored目录。连续开发只留 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份增量缓存。局部提交后另验committed HEAD；没有推送或发布。
