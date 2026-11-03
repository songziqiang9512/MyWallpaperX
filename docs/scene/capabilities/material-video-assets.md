# 视频与声音运行边界

<!-- document-role: current-state -->

<a id="sources"></a>
## 原媒体 owner

视频 layer、material 资产、用户纹理视频和已支持动态实例沿原资源入口准备，Session 的 video registry/source 持有实际播放状态与 AV 生命周期。帧只消费 ready/last-ready texture publication；AVFoundation 可读格式与作者入口资格分别判断，不因文件扩展名宣称 codec 支持。

Sound 使用独立的 SoundPlaybackProgram/Registry、voice 和局部播放计划。声音播放不拥有视频 clock、Scene 频谱采集或最终视觉输出；随机等待、hidden、暂停与退休分别处理。

素材文件的授权/OwnedFile 与 AV borrower 持续到实际读取结束。stop、释放一个 texture 或 GPU barrier 都不能代替 AV item/asset 借用终态。

<a id="position"></a>
## 视频时间与发布

原 lifecycle 持 Scene 时间与播放意图，Source 持同 item/目标/UUID 的定位状态。currentTime/stop、真实 EOF 及影响 duration 映射的 loop 变化可请求定位；普通 play/rate/恢复只重锚，不每帧 seek。

- 定位完成只记录 backend 事实，不修改逻辑时钟或立即发布。后续 prepare 按最新 Scene 相位取图；失败保 last-ready，不重建 player/output 猜恢复。
- Source 至多保一份未发布 decoded payload。同源同目标可复用，但新定位、目标变化、stop/退出使候选和旧 token 失效；6→2→6 必须产生新的定位关系。
- publication 由本次计划生成，成功 commit 才推进 generation/last-ready。取得的像素不是可回滚时钟；普通拒帧不恢复已经消费的 Scene 命令或后台 anchor。
- 未准备输入、坏解码和暂时 pending 只影响实际 consumer；不能重放 VM、回滚整景或拿旧 ready 冒充新定位成功。

源码：[VideoTextureSource](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSource.swift)。

<a id="switching"></a>
## 切换与呈现

原 Surface 保存上次正常呈现提交的普通视频 source incarnation。旧实际来源退出、新可见 ordinary source pending 时，原 PreparedFrame 可短暂不 present，沿原时钟/GPU事务继续工作，让系统保留上帧；不使用 cancel/deferred 冻结 VM。

当前等待上限为决策点 hostTime 后250ms，不因新 layer ID 或连续改选续期。同源换 ID、optional 增添、隐藏/离屏源和首次启动不冒充该切换。新帧 ready、永久不可用或到期即退出；group/named/effect 的一般依赖不从此直接路径推断。

暂停期沿原资源重试；prepared→submit、共享 provider commit/discard 与正常 stop/drain 保持。当前可见性资格使用实际 quad/alpha，不能拿初始 visible 一个字段推导所有解码需求。

<a id="sound"></a>
## Sound 与命令

声音定义从原资源闭包进入 Registry；已接入的 play/pause/stop/volume、循环和随机计划由实际 voice 消费。SceneScript 命令与当前 callback/API 快照各有可见时点，不能因意图已入队就伪造 backend 已播放或已结束。

资源、目标和 request/command generation 决定命令落点；同路径不等于同播放实例。退休只撤该活实例，健康 peer 与实际输出保持。

<a id="limits"></a>
## 当前缺口

隐藏/离屏视频的逻辑时间、EOF/事件与 backend 解码停用尚无完整通用资格，当前不能直接 skip prepare 或借全局 pause 停掉无图源。多屏需求应取并集，不能由某屏缺 drawable 撤另一屏所需 source。现有 eager 工作仍可能是性能调查对象，不等于已证明可停。

全部容器/codec、seek/loop/负相位、group/named/effect 组合、长时间 AV 驻留以及所有播放器源都未由短窗代表证明。真实系统 Media metadata/封面见[provider](runtime-input-property-coverage.md#providers)；具体未闭项见[队列](../roadmap/scene-open-breakpoint-queue.md)。

最近行为入口：[材质视频资产](../../../script/tests/test_scene_material_video_asset.py)、[视频 source](../../../script/tests/test_scene_video_texture_source.py)、[重复命令](../../../script/tests/test_scene_video_repeated_commands.py)、[初始呈现](../../../script/tests/test_scene_initial_video_presentation.py)、[Sound 命令](../../../script/tests/test_scene_sound_script_commands.py)。
