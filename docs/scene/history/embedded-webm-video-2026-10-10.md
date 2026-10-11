<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。合同归[运行架构](../architecture/runtime-architecture.md)，余项和选序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。本记录不代表全 WebM、全样本或发布验收。

# 内嵌 WebM 视频背景恢复（2026-10-10）

## 首断点与实现

U06 `3662390671` 的 layer185 没有 effects，背景和人物来自 `materials/Scene.tex` 中的 WebM/VP9。此前灰底仅有前景时钟/Logo，源视频从未出帧。原 WebM 在 AVFoundation 报 -11828；同码流 MP4 未注册系统 VP9 decoder 时报 -11833，不能据此断言系统无法解码。显式 `VTRegisterSupplementalVideoDecoderIfAvailable` 后 MP4 连续解码成功，但系统仍不能读取 WebM 容器。

按[公开 WebM 容器规范](https://www.webmproject.org/docs/container/)及[VP9 MP4 绑定规范](https://www.webmproject.org/vp9/mp4/)，Format 一次性有界读取压缩包、时间戳与 vpcC，原 provider 持有的后台任务通过 AVAssetWriter 无损封装。没有产品 FFmpeg 依赖、转码、第二播放器/时钟/纹理发布者。准备期命令仍进原 lifecycle；完成回原 actor 安装 AVPlayerItem，不重置时钟；停止取消并撤销安装资格，迟到与失败清理独占文件。最终 alpha 仍只认 CoreVideo 附件。

边界：单轨、无音频/额外 alpha 的 VP9，SimpleBlock 与有限 BlockGroup；未知长度 Segment/Cluster 仅在可判定边界接纳。多轨、加密/ContentEncoding、lacing、隐藏/show-existing/superframe、配置变化及末帧时长无法确定均局部拒绝。公开 profile/depth/chroma/color 解析生成 vpcC，缺 level 用 Undefined 0；不按样本硬编码。输入/packet/元素/时间线预算及取消/30秒写入期限覆盖准备，普通帧无容器解析。

## 身份与实际结果

本机证据根 `.artifacts/tmp/embedded-video-20261010`。基线 Scene `0a99ec43`；隔离 Debug build 精确绑定761个 Scene 文件，旧 Web checkout 保持隔离，因此不称完整 HEAD 或 release build。签名验证通过；executable SHA `321e6d1a75fd17868007c59d3257080d13abe7158f10d2c8bcb32a86e274b9db`，debug dylib SHA `2a36fc0ec8834378a9da037e1a1584994e5b707306128ac3f2a26e9a648d9c45`。

原包 SHA `856528f60bed34a4e205b674383c804a8d82fc769add18c1f225aef9cd6440ff`；WebM payload SHA `1cd989f958260a74722e3137c796e41f6efe5dfd57d4f6f856242850f208dfbd`。原件只读，运行使用未改内容的隔离副本与 HOME。

- parser CPU10门通过，真实1920×1080/8秒/480 packet的大小、SHA、PTS和keyflag对ffprobe全部相同；产品writer生成的MP4也对全部480 packet复核相同。无需重新压缩，原素材清晰度不变。
- 原包修前0次video publication；修后636次，3次accepted EOF/循环，首次及约12秒后截图均显示完整人物/彩色背景、前景文字和Logo。PID42384，约62秒总运行（准备35.9秒、约25秒播放），exit0、gpuDrained=true。不能据此声称启动加速或长期性能改善。
- 当前默认状态15个活动effect occurrence进入graph，14个执行材质、1个仍用局部passthrough；它们与修前相同。本次新增的是独立视频底图输入，不能声称视频经过不存在的layer185 effects。
- 产品等价MainActor/Swift5的原生provider永久5门全通过（4个既有MP4门+1个WebM门）；准备期pause/rate/seek、真实Metal像素变化、多个loop、暂停seek、立即stop无迟到item/纹理/文件均通过。新WebM门173次发布、3次loop，166个steady点有源时间网格对应，至少两个loop各有5个以上steady点；前后产品SHA相同。
- 原AVPlayerItemVideoOutput的首seek/loop重锚displayTime不一定落源packet grid；永久测试保留全部观测，按操作前已知phase划分重锚与steady，不更改产品时间或按误差筛选。容器PTS保真由上述独立packet读回证明。

## 剩余与覆盖边界

U06大面积缺图主现象已闭。该样本Audio bar layer58的effect612（作者lens_distorsion）仍在`material-variant-envelope-color-contract`局部回退；其余默认未激活组合、全部属性/真实媒体/交互、官方同输入画面对照与长稳未验，不能称整样本完成。没有该样本`截屏*`官方实机图，不用作者预览替代官方parity。

243包头部复扫发现31个内嵌视频payload：21样本中的30个MP4，加U06的1个WebM；这是头部分类，不是31个运行通过。旧静态审计“video-mp4 4”口径不足，不能作为WebM影响数。本批直接已证受益1个真实样本，公共能力适用于同合同的其他WebM；既有MP4走原链保留。

下一批先复核U16 `3122339805`两个可移动窗口消失（含3个MP4 payload），随后U24/U34曾好后坏与U22长期掉帧。土星已按用户指示暂缓；U06余effect单列，不能因背景恢复清空整行。

## 门禁与保留

公开容器reader是实际新增职责。全局five-suffix结构门保持发现，以绑定旧/新metric摘要、精确文件/声明/初次source SHA及设计的单次收据接纳65→66；不重命名避门、不把active reader伪装passive、不放宽未来增长。既有声明保持不变，提交后允许正文修错，不能再扩大owner。

Scene依赖/防御门、Debug及上述运行通过。全局code-health仍有本批外Web文件1008行，residue仍有未知归属`.mimosa`，document-registry仍有两处Web入口缺反链；均为既有失败，本批不修改或声称全门通过。最终独立审查与精确diff身份见本机review/freeze收据。

证据缓存总预算已满，`promote_scene_evidence.py`拒绝新增，`--prune-expired`没有可回收已登记包；没有提高预算或删除他人证据。本批必要截图、日志/原始观察、源码/App/输入身份压缩留在`.artifacts/tmp/embedded-video-20261010/retained-evidence.zip`，保留可复核的单份构建缓存`.build-cache/solid-source-domains-recovery-20261009`供下一批；临时媒体、两次运行HOME/缓存与重复输出在提取后删除。


<a id="large-video-payload"></a>

## 10-11 后继：大体积内嵌视频入口（N01）

新增原包3811216799只有主video layer17与文字/声音；257,625,236 B MP4在TEXB0004零metadata容器内，被250 MB静态mip门提前拒绝，画面仅剩灰底与时钟。修复只改既有Container/DataReader：format0、非volume/sprite、单image单mip、未压缩载荷且共享视频签名成立时，存储字节不套静态解码mip上限；先验证完整范围、至多读12 B前缀，复制前仍全额扣原容器总预算。静态/压缩/volume/sprite限制不变，继续原provider、clock与compositor；没有增大全局预算或新增播放器。签名只用于分类，不能证明媒体可播放；总预算不等于RSS上限，WebM自身容量/profile限制不变。

基线4196869f，产品两路径diff SHA `543114daa783db72ab2514a054dd92c82092690ea0480f1997de3d4c7cf1c7c8`；四路径含测试diff `5ed17cbad68c9e0f2ac1294d22beb69478c94d1b3abb295309f2c30cd7e3a9e2`。独立worktree排除原工作区U06三路径在途改动。签名Debug构建成功，App executable SHA `a31a1f2bcea5cfd552b5ba64ca42954ef8d8b2d6499fc3824f3f9bbd70bfdb0e`，dylib `1dacf5094ee9d136fac6377a7b31d27e8abbdd7852c5511281bf6c01491199dc`；正式发布状态不由该开发App裁决。

- 新增行为反例先红后绿；media identity、aggregate budget、truncation、decompression四模块7门通过。大MP4/WebM稀疏签名fixture只证明读取边界；精确预算/少1 B、异常shape、截断、跨payload签名和小视频旧兼容均有反例。
- 同一App、原包隔离副本及HOME，既有direct Host入口ready后18秒：381主视频从0恢复1,072次发布，末次decoded=18.016667秒；健康3814040466为1,067次、18.025秒。两者exit0、gpuDrained=true，benchmark通过。
- 修后5秒与约16秒截图显示人物姿态变化、完整黑白底图及斜向时钟；用户原目录`截屏2026-10-11 14.40.11.png`支持缺失主体已恢复的视觉判断。屏幕比例及动画相位不同，未作逐像素parity。没有验证普通App→daemon桌面入口、所有交互、长稳、多屏或性能改善；不能记整样本100%正确。
- 四路径独立只读审查无阻断；静态安全审查与实际视频验证分别成立。必要身份、日志、报告和两帧留在`.artifacts/tmp/large-video-payload-20261011`；构建缓存沿用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`供连续迭代。

本条关闭N01大载荷入口及对应主画面缺失；不覆盖N02 Puppet及其他新样本问题，后续顺序仍由现役断点队列决定。
