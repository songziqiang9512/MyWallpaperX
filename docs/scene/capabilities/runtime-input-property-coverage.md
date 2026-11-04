# 运行输入、属性与 Timeline

<!-- document-role: current-state -->

<a id="properties"></a>
## 类型与求值

基本优先级为作者 fallback → 有效 user property → Timeline → SceneScript；实际目标 compiler 决定允许的来源组合，不把同名值合成无类型字典。缺值、错型或被拒 producer 保原已定义 fallback/current，不能用 resolver 的回退值覆盖一个健康播放状态。

BindingProgram 在构造/解码时形成验证结果与索引；LaunchContext.liveState 保存当前有效输入和 revision。value-only 更新只写对应状态；资源、combo 或 topology 变化触发原准备/重建边界。混合键按原事务接纳，不能拆开通过其中几项。

property key、原始 value、Combo value 和 condition 始终使用作者数据；本地化只作用于显示标题与选项 label，不回写运行输入。作者 text/group 是只读说明，unsupported 类型不生成可写运行能力。面板以已接纳的 effective value 显示当前值，fallback、用户 override 与资源替换状态分别保留；条件隐藏控件不删除其输入。资源更新沿原选择/准备/发布事务处理，失败保原选择，不把 UI 临时编辑值冒充热更新已生效。

| 用户属性 | 当前消费与边界 |
|---|---|
| Checkbox、Slider、Color、Combo、Text | 保定义、类型、默认值、显示条件及真实绑定；颜色值与显示色彩空间分开 |
| 直接 shader scalar/vector | 需要已准备的目标/ABI/来源证明，不因 material 有同名字段就获得值绑定 |
| Texture/variant | 保选择授权、asset/property identity、purpose 与 generation；坏替换保 last-ready |
| Effect visibility | 准备好的安全 activation 可热更；未准备/无消费者/不支持结构不因 Bool 字段存在而强行接纳 |
| User Shortcut | 原配置和真实输入 scope；不从合成 cursor 或脚本普通更新推定 OS 授权 |

源码：[BindingProgram](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyBindingProgram.swift)、[当前状态](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/ScenePropertyLiveUpdateState.swift)。

<a id="timeline"></a>
## Timeline

Program 保轨道、作者 key、FPS/length、曲线、relative/Combined 关系和事件。普通帧由唯一 PlaybackRuntime 采样已准备数据；play/pause/stop/setFrame 以及 API 快照共用该 state，不能另建第二 clock。

- 数值插值、Bézier 求根、wrap 与 relative 单位由现 evaluator 消费，不能用线性 key 索引替代作者时间。
- target 与 playback owner 不同。Combined/peer 可共享时间 anchor；销毁一个 target 只撤该活动轨道，幸存成员仍保 clock/命令/事件。
- 稳定 Program/C/named 索引不因压缩活动数组而改义；隐藏与暂停不退休轨道。
- 事件按实际时间区间与原确认边界派发，同 cadence 重读或无 drawable 不重复消费。
- 无 lane 的联动值、无真实 target/control owner 的 event-only 及部分类型组合仍有限制；不能只因解析到 track 就声称可播放。

源码：[PlaybackRuntime](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelinePlaybackRuntime.swift)、[TargetCompiler](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Timeline/SceneTimelineTargetCompiler.swift)。

<a id="effect-linked-timeline"></a>
### 数值联动的执行合同

effect instance 的数值常量在同一 layer/effect 内一次收集，再按作者 key 解析 parent/children；每个 pass 的完整 target、类型、fallback 与自身曲线分别保留，不按效果名、属性名或 pass 数准入。未联动的同名常量继续独立。联动可有多个实际 pass 成员、分叉或链式关系，只共享唯一根 clock，不制造子组偏移、独立响应或第二 state。关系解析复用原 TargetCompiler 的准备职责；layer 的值类型、relative 与响应消费边界保持。

同 key 的不同 lanes/fallback 不构成拒绝理由。各 pass 可分布声明 children，合并后须 reciprocal；多个根别名的实际 clock 设置须一致，canonical root 是真实且可执行 target。每个成员继承根时间，继续读取自己的 lanes。effect 不借 layer 的响应模式/UI 数值范围准入；未实现响应保原 descriptor 元数据并明确基础曲线近似。缺成员、矛盾、循环、无可执行根或缺真实值只使相连分量不发布，健康独立输入继续。无 lane 的 child 不从 root、preview、user property 或 shader default 猜值；材质 default 动画的解析与有效 consumer identity 另行接入，不由 instance 资格代验。

名称只服务既有动画 handle：同 owner 的相同根名字导出一次，不同名字保各自实际 target；其他 owner 同名沿原作用域/歧义处理。名称不决定数值资格。原 groupedAnimation 显式接收导出名，layer/camera 继续传其原根名；effect 的多个 pass 名称不能制造多个 clock。

原 PlaybackRuntime 在准备时把同一 state 的实际等价取值成员归组，替换原 flat stateMembers；每帧每种曲线/类型/组合/fallback及有效采样选项求值一次，再写回全部原 target。仅忽略不参与取值的名称，曲线及数值 fallback 按实际 bit 保留 signed zero，不合并不同语义；不建并列 alias registry、帧缓存或整轨 hash。退休成员或代表后，幸存成员保原 owner animation/state、命令和观测；坏值保原分量原子失败，binding/handle ordinal 不改义。

验收沿真实 parser→TargetCompiler→PlaybackRuntime→DynamicSnapshot→prepared uniform bytes→Metal/terminal：不同曲线、跨 pass 别名、改名、同名其他 effect、冲突分量与健康 peer、play/pause/stop/setFrame/完成重启及退休；核实际时间下的动态颜色与独立作者活动相位。编译/绑定或晚相位零值不作可见效果证明；树形合同不冒充官方像素一致性。

<a id="camera"></a>
## 相机、world 与 Cursor

每阶段的 descriptor、layer map、world frames 来自原 FrameWorldProjection；cursor、Puppet 与 emission 复用同阶段数据。camera factory 消费当前成员与 render order；不再从 base descriptor 选已销毁相机。隐藏不等于销毁，parent 变换保持；当前 winner 缺 world/FOV 时回 general，不跳到任意邻 camera。

Default2D origin/zoom 的真实作者来源可能不同，不能用同一个 layer ID 代替两条输入。native perspective 与普通2D、camera parallax、depth parallax 各有自己的空间语义，不统一改成屏幕像素偏移。

原 pointer owner 保存实际本屏坐标、按钮和边沿；命中使用最终输出 geometry/提交结果，不能用 source atlas 框代替。local/global monitor 按活动 owner 安装/移除，状态未变不反复重建或重置手势。

<a id="text"></a>
## 文字

CoreText/CoreGraphics 负责字体、shaping、glyph advance、baseline、行距、对齐、padding 与 raster。字体 explicit-system-default 与当前值缺失分开；作者字体资源经同一路径解析，fallback 不证明字形等价。

Session 共享一个 DynamicTextTextureStore，按内容/样式签名和 generation 合并在途工作。普通稳定帧不重排/重栅格；每屏只采用 ready snapshot、prepared/submitted 纹理与几何。cursor 使用本屏最后提交的文字几何。

初始与动态文字均作为 layer source，raster 颜色与 layer tint 保原乘色语义。没有实际活 layer/clone/named/particle 消费者时退休活动 producer 并撤迟到发布权，保留准备模板与冻结/GPU 引用；hidden 不作为退出。Surface rebuild 复用共享 Store，完整 stop 排空已接纳任务。

### 文字 HDR 亮度

文字前景 `brightness` 是 HDR gain，[官方作者说明](https://docs.wallpaperengine.io/en/scene/effects/bloom.html)也将文字列为此选项的消费者。Document 准备 TextStyle 时按已解析的 `hdrEnabled` 采用：非 HDR 为1、HDR保留声明值；原始对象和 Layer 继续保真。初始/动态栅格共用有效样式，替代无条件烘入亮度的采用方式，不向 Store/loader 传 general，也不加普通帧分支。

新 launch 重建样式，Surface rebuild 复用 Store，不新增缓存字段或迁移状态。`backgroundbrightness` 仍需独立语义资格；HDR开启保既有8bit栅格行为，不表示高光保真。验证使用非白色0/1/高亮、wrapper及改名的初始/动态纹理，核字色、alpha、几何与原声明，并保HDR原输出；固定扫描相位、真实邻例和官方截图各有独立证明边界。

源码：[DynamicTextTextureStore](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneDynamicTextTextureStore.swift)。字体/排版精确像素、所有样式与官方布局 parity 仍需逐输入比较。

<a id="providers"></a>
## Audio、Media 与纹理 provider

平台服务唯一生产，Session 冻结一次快照供 VM 与 Surface 消费。活动需求由真实 prepared material、脚本、Sound/粒子与 source consumer 决定，不从 project 声明或纯 launch 定义猜采集需求。

- Audio 的系统采集与本进程 Sound 播放需求分开；未授权、静音、无数据有明确输入状态，不伪造波形。AudioBuffers 的数组身份、采样时机与处理范围按实际 host 消费。
- 系统 Media 经原服务/系统宿主与 inbox 发布 metadata、状态、进度和封面；平台补充不能替换已选来源或用旧曲冒认新会话。真实播放器字段、权限及切换分别验收。
- current/previous thumbnail、fallback、pending、decode failure 与 accepted clear 分开。Session Store 唯一生产各 purpose；任一屏成功提交后消费单份 pending 输入，所有屏使用同一冻结 snapshot。
- accepted absent 清该 provider 的 current/previous 长期 publication；discard 还原基线；旧 snapshot/GPU 使用期不因订阅退出缩短。
- 需求只在 committed 拓扑或实际 owner 禁用/恢复边界重算；最后 consumer 退出撤采集/订阅。hidden、dormant、bad return 和活 alias 保留合法需求；source alias 依实际 consumer→prototype 关系判断。

视频的逻辑/解码需求与 Sound voice 见[媒体](material-video-assets.md)。普通帧不经 IPC 同步查询播放器、启动 helper 或传完整封面。

<a id="limits"></a>
## 当前限制与最近门

完整平台输入/播放器覆盖、全部 target 组合、原生屏幕映射、任意字体排版及所有跨 owner 事件顺序不能由单个合成输入门推出。开放项见[队列](../roadmap/scene-open-breakpoint-queue.md)。

最近行为入口：[属性准备复用](../../../script/tests/test_scene_property_preparation_reuse.py)、[Timeline](../../../script/tests/test_scene_timeline_runtime.py)、[Default2D](../../../script/tests/test_scene_default_2d_camera_inputs.py)、[动态文字](../../../script/tests/test_scene_dynamic_text_generation.py)、[媒体 Store](../../../script/tests/test_scene_media_thumbnail_provider.py)。
