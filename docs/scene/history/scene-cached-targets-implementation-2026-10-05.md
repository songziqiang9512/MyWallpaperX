<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# 全缓存渲染目标的正常 completion 交错（2026-10-05）

> **历史证据 — 非现役入口**。稳定职责见[运行架构](../architecture/runtime-architecture.md)，后继由[RF05卡](../roadmap/batch2/reference-evidence-implementation-cards.md)拥有。

基线 `b9480f65`。收口339真实产品来源切换时，60FPS运行发现200次 `frame-target-plan-allocation-failed`，对应整组graph未编码；下一帧恢复。全缓存批次仍进入allocation recovery，旧帧GPU完成释放pin只改变cache revision也可让当前准备失败。修复仅让production预检后的全cached批次复用实际资源，跳过shared-pair分配/recovery；allocator重新验证plan及原reservation身份，原admission/preparation pin/commit继续核对reset、generation、texture及队列。新分配、mixed、retired reuse保持原strict recovery，不改额度、历史、输出或样本算法。

真实cache/Metal的owned与shared正反例先红（两项拒绝）后绿：reservation与prepare之间释放真实外部pin，纹理/代数不变、零factory调用、admission/finalize成功；reset后旧reservation仍拒绝。35项资源池/分配恢复回归、Debug build及设计/防御/代码健康门通过。此前非产品入口的cold preflight顺序变化已撤回，保持既有失败驻留合同。产品冻结与候选均由包内identity拥有；最终dylib `7c1cacd49dbed2916c9ed9681f29631ab507fa97b631134b7d45216f2eaae17b`。

同原339包/default属性、自有媒体字段/红封面、60FPS、55秒direct Host对照：旧版52次此失败，新版1次，且仅在ready后约0.13秒；此后本轮稳态未再出现。两轮退出0且gpuDrained，截图保持文字、封面、音频线及背景合成。未定位剩余一次的具体准备分支，不能声称所有allocation failure已修；真实系统音频未固定，不作像素parity或性能提升声明。最近统计dropped55→3也含其他丢帧；CPU18.25→18.59ms、实际帧数不同，不算性能收益。没有新增effect支持；339整体仍约70–75%/低置信。本轮默认条件实际25个material GPU effect、12个终端compositor consumer；先前底部音频开启等条件的27个执行范围仍是独立既有证据，不能混算本轮。

## 同轮交互收口

上一批最终dylib `98fcf253…7030bf6` 的正常App→Service→daemon链完成两轮：活动339选自有图片、删除源、重开属性显示暂不可用、面板全reset、恢复默认提示；每轮只有一个session activation，reset产生Metal截图并正常退出。媒体关闭轮按作者隐藏面板；系统媒体轮选择及reset截图均保留真实歌曲封面/文字/音频线，高优媒体封面不被文件默认覆盖。无媒体封面的文件回退画面仍由上一批direct证据证明，不能把本轮高优媒体画面冒充作者默认文件像素。

设置试验仅给复制App改独立bundle ID `com.songziqiang.MyWallpaperX.Debug.MediaSwitch20261005` 并重新签名，产品dylib未改，隔离用户偏好。通过设置UI依次系统→关闭→Apple Music→系统：原VM收到清除，reader退出，未运行的Music报告not-running，系统恢复published/state1；只有一次Scene激活。未启动/控制用户播放器或请求新权限，不能算Apple Music、QQ、汽水全部字段/歌词验收。

必要日志、4张截图、原始结果与manifest在 `/private/tmp/mwx-cached-targets-20261005/package/runtime_evidence.zip`，12,490,553 bytes，SHA256 `03dfe49ac16fbd3e7708af74a6e28f50ae77bd298e873d5badfbb7ab4df7d926`。证据根已达总预算，临时限14日保留；本轮运行目录提取后清理，保留最终候选/原样本测试副本及同任务一份checkpoint缓存继续迭代。下一步定位剩余首帧附近的准备失败并完成339音频模式；HDR/SDR与重型启动仍按用户顺序跟进。
