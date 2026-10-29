<!-- document-role: historical-evidence -->
# 普通视频实例、播放与切换衔接（2026-10-29）

> **历史证据 — 非现役入口**

本记录保存[动态视频设计](../roadmap/batch2/script-component-api-design.md#prepared-dynamic-video)的固定官方依据及原生验收边界；当前剩余问题归唯一队列，不由局部结果推整样本通过。

## 输入与身份

固定 Wallpaper Engine 2.8.42。自有 20 秒、600 帧 H.264 视频烧录 T/F 时间码，原静态层及两个动态实例引用相同 TEX；控制器只使用内部阶段，不依赖未送达的外部属性指令。冻结包 SHA256：`19661bbc1c2b7c697702fc602a630733b412a5da44dae43b2ca63f0d6d6dca59`。

正式本机证据：`.artifacts/scene-evidence/runs/video-instance-observed-20261029`，普通 14 天包；`official/samples/0/runtime_evidence.zip` 为 12,538,001 字节，SHA256 `0423a21370fa30fe9ca019021a4efa58494492ecb0c3ae3630bd73a961800941`。包内含冻结输入、控制器、命令回执、两个结果摘要及 16 张必要原始截图；裁图仅辅助查看，未替代原图。

## 实际取得的结果

- 静态 Control 的 T/F 持续变化；两个动态实例也有完整时间码推进、随后共同暂停的正控。
- P7 两边均暂停，查询值 1.25，画面保留 T2.066。之后仅 A 收到 play；P9 仅 B 收到 pause 时，两边画面已到 T19.133，两边查询均为暂停，后续画面保持。结合冻结发令序，支持跨实例共享播放控制；未直接截到 P8 的连续运动双图。
- 暂停后的 seek 查询与最后解码画面可以分离。P7 请求 3.25 未取得相应完成画面，不能将缓存帧时间写回逻辑时钟，也不能声称 seek 一致性已完成。
- P14 实见两个面板均消失；P15 新 A 未主动 seek，查询恢复 8.25，画面保留旧 T19.133，P16 仍保持。支持跨销毁、重建保留逻辑状态和最后帧；单张空板不证明连续八秒空窗或 decoder 常驻。

有限 prepared catalog 的普通视频按 SourceKey 与 device 共享原 Source，并在 launch 内保留，是基于上述结果、减少 owner 的工程选择，不能称为官方内部缓存键或完整寿命合同。asset、userProperty 身份保持隔离；本批不以可见性增设暂停或改写既有 Scene clock 政策。

## 未覆盖与实验限制

同 callback 重建未直接采到；最后 carrier 退出时若正在播放，其空窗时钟继续、冻结或重置仍未知。官方实验没有性能对照，不授予帧率、能耗或内存收益。

第一次运行在单实例控制前被 Mac 空闲锁屏中断，已停止、关闭并记录，不解释缺失阶段。第二次沿相同冻结输入运行，临时显示唤醒断言在 200 秒自动退出，未改变锁屏或认证设置。分段采样、查看截图造成阶段缺口，预览于 236 秒关闭，超过预定 200 秒外部关闭预算；控制器在 162 秒结束后不再发令。实际关闭已核图，官方主客户端与虚拟机保留。后续无需重做整板，只补真正影响设计选择的最小未知轴。

独立审查同意上述有界设计选择，保留全部官方未覆盖项；以下原生结果不能补写官方未知语义。

## 原生闭合的通用语义

原 prepared 资源现在区分静态 candidate 与视频 file lease/extent，普通视频按 SourceKey/device 共用原 Source；新生层直接读 Source 观察表，命令保 callback 发令序与来源 UUID，旧镜像 rollback 不能转绑新媒体。构造读取一层 Boolean value 包装，资源资格只在原 prepared 拓扑准入；不执行配置里的 script/user。未开放动态 WebM、任意 material 或嵌套媒体贡献。

实际最先阻断的 Boolean image-only 二次门曾使控制器整包拒绝：12 原层未退出，18 秒内12源都持续供帧。撤门后仅选中1源，却在约93张视频纹理后耗尽约3GB预算：FrameTextureRegistry按不断变化的逻辑ID永久留历史publication。现按已提交拓扑退休双source别名及rollback历史，活跃pending和generation保持。净消费者退出只停原backend，保逻辑clock/last-ready；同源每帧换ID不反复暂停、定位、写MP4或建播放器。

[呈现合同](../capabilities/material-video-assets.md#video-switch-presentation)沿原Surface/PreparedFrame对直接主输出的真实新源pending短暂暂缓present，GPU/Source/graph/script仍提交；不建全屏copy/history。有限250ms截止不被改选、丢drawable或新层ID重置，暂停时继续资源重试。上一来源事实是有序提交呈现的集合，不冒称已物理显示；group/named/effect未知范围仍走原路径。

## 当前原生身份与结果

同一签名Debug候选 executable SHA256 `a69766362439a52a528111bb3011c7c62debab2a1c7d23fa39675e3de59c3a9c`，构建67.893秒、owned inputs无漂移。 Debug实际主体`MyWallpaperX.debug.dylib`的构建源包与运行包SHA256均为`9e00e31dbe95d555a509c3c829ab39cdbcd617022ee3978f27090c95394e8fd9`，整包复制，未只替换启动shim。原包337项目默认时段是手动白天（tod=2），另显式tod=1验自动模式，未实际跨整点改系统时间。默认/自动单源持续18秒；最终自动约1064次视频publication，完整12主题/时段热改均接纳、无控制器异常。热切记录88帧暂缓呈现，0条pending仍被present；此日志只证明提交选择。

自有不同红/蓝H.264、资源/变量改名与等价选择式，经真实窗口CGWindow采样：自动12张、改名双surface合30张、属性热改26张，均红→蓝→红，无采到的黑帧。采样间隔不覆盖全部物理显示瞬间，不能称绝对无闪。原自建载体首次缺合法材质recipe/evidence窗口、外部fixture签名过期，失败结果保留；修载体未放宽产品资格。最终原包热改、自动和独立3775355045双视频均正常停止、surface归零/GPU排空；独立双源约1323次publication，hover图已复核，未把其视为普通A/B切换正例。

原Source/Registry真实GPU借用/净consumer/文件lease反例、Boolean/C VM、历史纹理弱引用/预算/提交回滚均通过；Surface提交、冷暂停、alpha0和离屏相邻反例亦已复验通过；原始计数、逐门首次失败/修后收据与窗口PNG在本机`.artifacts/video-texture-instance-20261029`，必要原生结果已归档`.artifacts/scene-evidence/runs/video-runtime-switch-20261029/native/samples/3372715909/runtime_evidence.zip`，11,818,278字节，SHA256 `15c325cc10441341bef101191996bb8cfdd1b0cb002aed73fe2953f213b0dd72`；普通14天/单包32MiB/本机5GiB上限。构建或提交FPS不替代上述像素与播放证据。

收尾行为、首次失败及修后回执、静态门与Debug主体身份另存`.artifacts/scene-evidence/runs/video-runtime-closure-20261029/final/samples/3372715909/runtime_evidence.zip`，34,872字节，SHA256 `4b4f86688b42d3c24960141bbdb9ba688d0111bafe101c710713b13fd20c15ec`。原生已绿输入未重复构建或重跑整板；最后只复验失败夹具及受影响的终结门。

## 明确保留的成本与边界

单源GPU分配约0.8GB且不再随每帧换ID增长；完整遍历12源后MTL allocated仍约9.75GB，不能把它等同进程物理RAM，也没有已证整体CPU/能耗收益。停后台和flush没有闭合AV解码/转换池驻留，仍须按实际Source寿命测量后收敛，不能提高预算过门。DEBUG进程结束后曾留7个私有MP4共约310MB；这不证明生产in-process退场失败，也不能用exit0/GPU排空授予完整AV借用回落。实际borrower门有界通过，整Session释放另验。

未覆盖动态WebM、未知group/named/effect首帧衔接、所有HDR/SDR组合、跨整点自动切换、任意作者材质与官方完整seek/播放态空窗。官方客户端及虚拟机保留运行，本轮未重试已停止的大实验。
