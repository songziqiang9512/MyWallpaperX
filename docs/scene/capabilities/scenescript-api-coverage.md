# SceneScript 当前接口与语义

<!-- document-role: current-state -->

<a id="contract"></a>
## 作者合同与运行模型

SceneScript 是 property-bound ECMAScript：脚本附着于一个有类型的属性，`init(value)`/`update(value)` 的返回值可写回该目标，直接 setter 可修改其他准入目标。`update` 可选，只有实际导出的 update consumer 进入逐帧调用。声明面见[SceneScript v2.8 类型声明](../development/reference/lib.sceneScript-v2.8.d.ts)；声明存在不表示本项目全部 host API 已实现。

当前使用真实 QuickJS-NG、模块解析和同一 domain 的 heap；不以源码形状、小解释器或 Swift 字典复制 JS 对象。绑定记录 source、owner、target、作者初值及值类型；模块、shared、闭包和脚本 owner 是不同寿命对象。

初始化、属性事件、输入、媒体、动画和 destroy 由实际导出及当前 owner 调度。事件型/idle owner 不因缺 update 被当作不存在。数组、对象别名、RegExp 等语言行为归真实 VM；用户 API 和模块数学归项目 host/value 实现。

<a id="layers"></a>
## Layer、Scene 与当前值

| 接口面 | 当前消费者 | 边界 |
|---|---|---|
| `thisLayer`、`thisScene`、layer 查询/枚举 | 原 LayerHost/SceneHost 与 typed snapshot | 句柄必须属于当前 domain/generation 且对象仍活；查询不取得资源或 graph 执行权 |
| transform、visibility、alpha、color、文字等 | 原目标定义与 mutation journal | 仅已接入目标有 setter；属性类型和合法值在实际入口判定 |
| `createLayer` | 现有动态图层模板与 Mutation Runtime | 已准备 image/solid/text 和受限 composition 形态；不是任意对象复制器 |
| `destroyLayer` | committed topology 与原组件退休 | 不提前撤当前冻结帧/GPU 引用；重复 destroy 不复活实例 |
| `sortLayer` | 当前拓扑排序 | 使用实际 layer handle 与合法位置；名称字符串不能代替该 handle 参数 |
| 文字 clone/模板 | 原 String/Vector program、文本模板与 Store | definition 保留，活动实例有独立值和退出；不是复制 VM heap |

动态 Layer 仅保存出生资源、创建尺寸、根关系及作者 seed；完整 upsert 的当前变换/可见性/颜色/文字走原 typed 值通道。结构 revision 不因普通值 setter 推进，也不在稳定帧回填整份作者 Layer。

普通命令在既有 commit/下一 cadence 可见；camera、visibility、particle 的已实现当帧例外不能推广到所有 setter。同字段跨 owner 按真实回调顺序消费，不能恢复额外仲裁或镜像状态；非法 owner bundle 原子拒绝，健康 peer 保持。

动态创建仍拒绝未接入的 Puppet animation/effects 以及复杂 composition 的 parent/children/dependency/copybackground 组合。普通动态 image 不自动继承作者 Sprite/Timeline/effect 能力；资源定义可供合法消费者复用，不等于实例已获全部组件。

源码：[SceneHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerSceneHost.c)、[LayerHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSLayerHost.c)。

<a id="commands"></a>
## 播放、事件与副作用

| 领域 | 当前实际入口 |
|---|---|
| Property Animation | 原 animation handle → TimelinePlaybackRuntime；play/pause/stop/setFrame 与同一轨道 state |
| TEX animation | `getTextureAnimation` → TextureAnimationPlaybackRuntime；typed handle 入口检查存活一次，命令保原 next-frame 顺序 |
| Particle | 原 Layer/ParticleInstance host 的 play/pause/stop/isPlaying/emitParticles 与 typed override；真实出生和预算由原模拟器处理 |
| Puppet | 原 animation/bone handle、会话 animation runtime 与每屏 pose；未接入 clip/channel 不从 handle 存在推定可播 |
| 视频 | 原 material/layer video handle → 视频 registry/source；命令目标与被选资源身份保持，不能按路径广播 |
| Sound | 原声音定义与 voice registry，volume/播放命令消费既有 typed 值 |
| Cursor/媒体/用户属性事件 | 原入口快照与 owner 回调；一次性事件不能因 GPU 重试重复派发 |

已接入的外部用户快捷动作需要当前真实输入和现有授权 scope；init/update/伪造指针不取得用户手势。OS 动作与 JS heap 副作用不能随 typed admission 失败假装撤回。不同事件/API 的签名和返回值仍以实际 host 与声明对照，不以“返回 true”代替系统动作成功。

<a id="values"></a>
## 数值、模块与持久状态

当前 value host 提供 Vec2、Vec3 与有界 Mat4，模块数学沿现 module host；Vec4、Mat3 未安装。向量返回与赋值按各入口所需的 x/y/z 分量及数值合同读取，普通对象满足对应分量合同也可被接受。构造与矩阵操作只承诺实际 host 的子集；矩阵、相机和 world 输入共用 canonical frame。

`setTimeout`/`setInterval` 和 jobs 归原 owner、Scene 时间及调用预算。零步长重绘不重复计时事件；清理 owner 时撤 timers/jobs 和句柄使用权。递归、非有限值、错误参数或预算耗尽只影响实际 owner/操作。

localStorage 使用同一 Session 的内存状态、candidate transaction 与原后台持久化。实际 owner 构造后、configure 之前准备一次；普通帧不首次打开或解析 JSON。候选激活会与前任最新 envelope 合并；取消不发布候选写入。screen scope 需要精确单屏身份，不能在多 Surface 时猜一个屏幕。

源码：[ValueHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSValueHost.c)、[ModuleHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSModuleHost.c)、[StorageHost](../../../MyWallpaperX/Core/SteamWorkshopScene/Systems/Script/SceneQuickJSStorageHost.c)。

<a id="failure"></a>
## 失败与退出

错误返回类型、异常或中断拒绝本次受影响 typed 输出和 mutation，不覆盖健康 current；真实 heap 写入不被复制回滚。永久禁用、退休和可恢复失败分开，不能用一次 bad return 取消仍活事件或平台输入。

Destroy 从 committed owner 变化进入原程序退出；资源、VM、活动轨道、声音、粒子和平台订阅各在实际消费边界撤权。停场等待原 worker/媒体/GPU drain，不能因某个 JS callback 返回就宣称资源全部释放。

<a id="limits"></a>
## 当前限制与验证

全部官方 handle/API、任意动态资源 recipe、跨 pass/无真实 target 的 Combined/Event-only 动画、所有复杂骨骼/几何/媒体组合仍未覆盖。缺口和下一资格归[队列](../roadmap/scene-open-breakpoint-queue.md)，不由官方 d.ts 数量计算支持率。

最近行为入口：[真实 QuickJS](../../../script/tests/test_scene_script_quickjs.py)、[owner 预算](../../../script/tests/test_scene_script_quickjs_owner_budget.py)、[动画](../../../script/tests/test_scene_timeline_runtime.py)、[TEX 播放](../../../script/tests/test_scene_texture_animation_script.py)。
