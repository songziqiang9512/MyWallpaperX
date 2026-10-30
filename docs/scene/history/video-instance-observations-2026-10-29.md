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

<a id="video-output-residency-20261030"></a>
## 输出驻留后继：原型撤回（2026-10-30）

固定主线 `015781e87`。原337两份完整TEX分别为37,141,320/40,932,255B，经原prepared动态实例链组成A→B→原A→净零；没有转码或降低尺寸，均3750×2250、H.264 High、60fps、12s、无音轨。相同Source UUID回访，实际binding/提交UUID、代次和解码时间推进；净零保持Scene/Surface/bridge活跃，consumer=0而cached/prepared=2。不是隐藏、暂停或杀进程代替退场。

一次性weak探针只强持同一个MTLDevice及一份明确的末帧view。Registry单独stop使Metal allocated从1497.516降至106.063MiB，整Scene仍在；仅断开player.currentItem后10s保持1465.156MiB，元数据仍ready/12s。净零10s后手动移除item的output并沿原suspend/flush，使1465.156降至170.781MiB，Source/player/item/output仍活；因此只有输出关联/缓存整组寿命的因果线索，不能据此声称实际热切已修。整Session真实drain后持view约34.516MiB，撤view后同device约2.156MiB、Scene预算0、所有AV/Session弱引用退出；该残余不是通过surface消失自动记0。

**候选反证。** 第一版只在原净零入口移除output、真实定位时重关联，产品净增6行。三份基线/候选的四秒A/B/A短窗均仍约1.43GiB，虽实际关联已退出，不能把手动静置消融当收益。最后一版在原Source内退休output/cache资源对、保player/item/clock/file/last-ready，净增30行；三次实际A回访约786–818MiB，净零均170.781MiB，对照约1432.797/1465–1498MiB；源身份、相位、3750×2250供帧与R0保持。这只证明有限两源资源机制，不是正式稳态性能或完整原包无退步。

| 原337完整12主题/时段，同诊断优化配置32s、同输入/属性/静音/FPS | 基线 | 最后候选 |
| --- | ---: | ---: |
| Metal allocated采样峰值（B） | 9,547,710,464 | 1,234,518,016 |
| process footprint采样峰值（B） | 269,681,720 | 1,033,766,520 |
| 进程CPU时间（ms） | 10,018.198 | 9,792.256 |
| 已完成GPU帧／失败 | 1650／0 | 1650／0 |
| 实际present超过1.5倍预算／间隔数 | 43／1548 | 61／1535 |

12次属性更新各自全部接纳，约60次提交/s，正常stop至0 surface且GPU排空；但footprint峰值达3.83倍、超预算呈现比例2.78%→3.97%。**NO-GO，两个产品候选、三个临时App/Debug观测文件及尚未实施的候选测试全部恢复。** 不用Metal下降抵消非目标退步；单对短窗不够解释物理分配归属、泄漏、热状态或稳定CPU/GPU收益，也不把推测的IOSurface归属转移当免责理由。保原clock/EOF/last-ready，隐藏/离屏需求及完整官方空窗语义仍未资格；该方向仅凭新物理驻留/实际供帧证据重入，不加延时清池、提高预算或重复上述原型。

基线App SHA `41ee7438a2c7d2f82b90a304571706f88186277c821a9ebdae067091cf3b5e00`，最后候选 `d05f051df5515deba89469b046867250a89236db9f5ec6bc6cae04a6ef74e197`；均由同一Release+diagnostic xcconfig构建，单独签名隔离运行。常规Release、30s预热/60s稳态、长期循环和官方画面未验，不授整样本PASS。必要原日志、弱引用/预算、输入身份、探针/候选差异、失败及独审按普通14天归 `.artifacts/scene-evidence/runs/video-output-residency-stop-20261030/`；未查看自动截图不作画面证据，78MB测试媒体、App/HOME/解码文件只作临时执行物。

另在完全未修改的Source/原6方法基线中，discard-before/after两子场景同frameIndex重试2s仍无新候选；合并重复编译后另两处same-inflight6/paused-discard-after失败，失败场景随运行变化。原6次及新1次编译的实际probe SHA均`7f54dd78041400fde09fd543458104044dda79769d02f7b690d439990c2f620b`，输入/进程仍各自隔离、断言未变；总时长120.993→53.371s，仅认测试准备节省，不报原门全绿。失败均有目标pixel buffer、playerTime=6而定位pending；Source/AV完成与测试执行边界待资格，不归因于已撤退休原型或编译复用，不判真实样本卡帧/官方差异，不放宽2s预算或绕过定位资格。

<a id="video-item-stop-boundary-20261030"></a>
### 单源复合stop：未隔离item寿命

后继仅用原337单源A、未改Source，真实3750×2250供帧215代，decoded display time为.16→3.9833秒。保同Source/player/output/cache/file与末张view，先同cache flush控制10秒，再原stop10秒；device allocated 713,031,680→34,406,400B、footprint 13,140,760→10,322,688B，Scene预算均33,930,304B，旧view中心GPU读回相同。source.item/currentItem已撤，old item/asset weak却仍活，因此本轮没有隔离其物理寿命；对象仍活也不等于资源泄漏。只认复合stop边界的观测，不归因decoder独占字节，不授Host/Registry恢复或产品性能收益，原12切换NO-GO不变。

单次probe exit0/24.591秒，无重试；新供帧恢复门未实施，不能以旧view代替。必要原日志、harness、编译/输入身份、独审和STOP归本机`.artifacts/scene-evidence/runs/video-item-stop-boundary-20261030/probe/`（ZIP55,950B，普通14天）；未存MP4/binary/cache。确认PID退出/无句柄后，三个可重建目录已清，逻辑295,747,945B；不改原媒体、产品或预算。
