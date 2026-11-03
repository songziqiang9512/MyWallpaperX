# Scene 格式与作者数据

<!-- document-role: current-state -->

<a id="resources"></a>
## 文件与资源

`project.json` 选择 Scene 文档并声明用户属性；`scene.json` 提供 general/camera 与有序 objects。资源经 `SceneResourceView` 的实际所选 Root/entry 读取，loose、package 与 stock 保持原相对路径和来源身份。结构读取与可选播放资源失败分开，不能因无关目录文件或可选缓存变化阻止合法内容。

- `SceneAssetCatalog` 读取实际引用闭包及动态创建需要的模板，不枚举整个作者目录来决定能力。
- Effect definition 的资源类别使用 `effects/**/effect.json`。material 引用独立文件，其 `passes` 继续保序；shader identity 与 `shaders/<identity>.vert/.frag` 对应。
- `SceneStockAssets.bundle/assets/...` 提供原路径资源。Particle、字体及已接入的材质/纹理 consumer 复用它；文件存在不证明该资源类别均有运行消费者。
- 用户纹理、视频、字体、TEX sidecar 与 shader include 沿原资源入口校验一次；帧消费 typed 引用与 generation。

源码：[ResourceView](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceView.swift)、[资源类别](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneResourceIndex.swift)、[AssetCatalog](../../../MyWallpaperX/Core/SteamWorkshopScene/Resources/Assets/SceneAssetCatalog.swift)。

<a id="document"></a>
## Project、Scene 与对象

作者 IR 保留缺席、原始表达、来源及顺序，不把静态 fallback 改写成当前值。未知字段可保留；只有真实 consumer 消费后才有执行意义。

| 数据 | 消费合同 |
|---|---|
| project 用户属性 | 保留定义、类型、默认值、显示条件与绑定；不是扫描效果后猜出的 UI |
| general/camera | 清底、画布、投影、视差及颜色意图进入 typed descriptor |
| objects | 作者顺序进入 render order；parent/children、dependency、attachment 是不同关系 |
| 静态值、user、animation、script 包装 | 先保来源，由属性/Timeline/VM 的目标 compiler 决定可执行组合 |
| `visible` 与 `alpha` | 独立值与独立 consumer；透明、隐藏不能用来删除实例或资源定义 |
| format/client version | 保留作者事实；只有实现明确消费的版本分支参与准入，不把未知版本号当全局播放许可 |

动态创建、排序和销毁改变当前 topology，不能重写原始 SceneDocument。完整 current record 与出生资源分别保存；细节见[SceneScript](scenescript-api-coverage.md#layers)。

<a id="effects"></a>
## Effect definition 与有序图

`passes` 中 material、copy、swap 按作者顺序生成节点。`fbos` 定义 effect-local logical identity、尺寸、格式、clear、unique 与条件。相似名称不能代替真实声明，也不能用 render order 猜依赖。

- `previous` 指该 effect 的输入，即 layer source 或前一个已准入 effect 输出，不是任意时刻的屏幕截图。
- 显式 framebuffer binding 绑定所声明 FBO；颜色/数据用途和 readiness 由实际 sampler 与资源事实共同确定。
- `copy` 复制当前版本；`swap` 交换图中的逻辑版本关系。两者都由原 target/transition/submission owner 管理，不创建独立 history 或 blit owner。
- `compose` 表示有序的 full-frame 合成转换，只在已证明的图形态执行；不是任意节点的通用 blend 开关。
- condition 在准备期消费当时可证明的 combo/provider；被裁掉的 target 或节点不能留下悬空活 binding。
- definition function 是显式调用的动作登记；Shader `[PASS]` 是 shader 变体元数据。两者都不自动成为 graph pass。
- `unique` FBO 可承接跨帧 history。显式 clear 是初始化值，不能误作每帧清空历史；当前 graph 的安全写读和完成关系由 target plan 裁决。

源码：[作者计划](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift)、[GraphAdmission](../../../MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneGraphAdmissionCompiler.swift)。执行与局部失败见[Effect](effect-execution-coverage.md)。

<a id="materials"></a>
## Material definition

Material pass 保留 shader、texture slots、instance 覆盖、user texture、combos、常量和 render state。槽位 hole 与来源 ordinal 不能压缩；effect binding 和 shader default 也不能被合成一个“首张纹理”。

自定义 MaterialProgram 的准备入口要求有效的 blending、depth test/write 和 cull state；缺省是否可用由该实际 consumer 决定。builtin image、source material 和 effect 不能互借默认值或准入结果。当前 typed state 包括 normal/translucent/additive/alpha-to-coverage、enabled/disabled depth、normal/nocull 及独立 alpha-writing。

已声明 `sceneTexture` 的裸 key 在准备入口可形成 property identity；带路径语法的名字仍是 asset，`_rt_` 仍由原词汇表解释。不能用当前属性值、下划线前缀或显示 label 猜来源。

<a id="binary"></a>
## 二进制资产

| 输入 | 当前入口与边界 |
|---|---|
| TEX | `SceneTexContainer` 保 mip、压缩格式、sprite/atlas 与物理尺寸；解码/上传由实际格式 consumer 决定，颜色和数据用途分别保留 |
| TEX lookup volume | 有严格 3D volume 资源上传路径；不据此宣称完整 LUT effect/材质采样已接入 |
| MDL/MDAT | Reader 保 mesh、rig、stream、part、weights、attachment、clip 与未知边界；越界或不支持 framing 不伪造 quad |
| MDLA | Reader 保 TRS、alpha、事件与 auxiliary presence；Selector/Evaluator 决定哪些通道真正进入 pose |

模型和裁剪的限制见[高级对象](advanced-object-coverage.md)。Shader 语法、颜色与采样规则见[Shader/Graph](render-graph-shader-coverage.md)，不在格式层选择视觉算法。
