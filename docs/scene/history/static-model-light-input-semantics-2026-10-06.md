<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。光照能量合同（k≈0.30）见[模型光照能量合同](model-light-energy-contract-implementation-2026-10-06.md)；现役代码以 `SceneLightSnapshot`/`SceneStaticModel.metal` 为准。

# 静态模型光照输入语义批（官方黑盒 v2，2026-10-06）

起点 `b50ad32e`。承接光照能量合同的开放边界，用 61 个官方黑盒夹具（Parallels WE 2.8.0.42，二进制 SHA 当日由 `…685F…` 变更为 `…6862…` 同版本字节替换，P4/NA 锚点复现证明行为不变）钉死四项输入语义并落地产品代码。

## 官方黑盒结论（全部 own-fixture，逐帧 PNG+输入 SHA 冻结）

1. **光角度值按弧度直读**：`ldirectional` 的 authored 角度数值不经度→弧度换算直接进入旋转。yaw=1（弧度）时受光方向=(cos1, 0, sin1)（标志性验证：球面三点 134/23/153 与该方向逐点吻合，R 侧内点 n·L=0.999→153=P4 满值）；yaw 细扫（1/1.2/1.4/1.5708/1.8/2/2.4/2.6/2.8/3/4/5/6）与 Jacobian（yaw±0.3、roll±0.3、roll 0.6）一致：**yaw→XZ 平面方位（+Z 为正）、roll→仰角（+Y 为正，0.3rad→17.85° 线性）、pitch 对方向无观测效应**；角度恰为零时官方保持默认朝向 (0,0,−1)（背面，D1/D4 全黑复现）。
2. **ambient 旧拟合已作废**：当时从球面截图估算法线得到 `clamp(0.5 − 0.73·n.y, 0.15, 0.85)`，方向和端点均错误；不能作为现行合同。2026-10-09 直接写入固定单位法线后重新测量，见下方纠正记录。
3. **缺省 ambient 为黑**：ambientcolor 字段省略时与显式 0 0 0 同渲染（ADEF 探针）；旧白回退退役。全语料 207 样本凡带模型均 author ambient/skylight，回退移除零影响。
4. **spot 受 lightconfig 门控，键名 `spot`**：无 lightconfig 全黑（SP1）、`{"spot":1}` 点亮（SP2 中心 150=P4×falloff 家族 k）。spot 朝向约定未探（近全向锥测量不可分辨），保持既有 frame 语义。

**方向光响应曲线（已由精确方向探针改判归档）**：GY90 系估计的方向含误差，其"S 陡曲线"数值表作废；SFR4/SFR1/SBK4（yaw=±π/2 精确 L=(0,0,±1)）改判——官方静态模型方向光响应 = clamp(NdotL,0,1) 过一条**带 0.157 地板的亚线性凸增曲线**：G(t) 在 t≤0.6 恒 0.157，0.75→0.180，0.87→0.212，0.95→0.259，1.0→0.298–0.306；强度严格线性（4×SFR1≈SFR4 逐桶吻合）；背面 SBK4 球面全零（无负绕射/无包裹）。我方线性 clamp(NdotL)×0.30 在包络内：高端（t>0.9）低 2–6%，中段（0.6–0.9）高 6–25%。不猜非闭式 BRDF，维持线性实现；地板与凸增的官方机制未明，登记为精确曲线差距。另 P1 点光垂直剖面（顶 35/中 38，对应 t≈0.85 处 G≈0.275）与方向光 G(0.85)≈0.21 不一致——点光响应或另有点项，未解。包络百分比的比较基准：逐桶中位数对桶标签 t（SFR1 与我方线性 0.30t 逐桶比；t=0.95 我方高 ~10%、t=1.0 低 2%~高 0.7%、t∈[0.6,0.87] 高 23–25%）。SFR/SBK 捕获、逐桶 JSON 与可复现分桶脚本输出打包 `/private/tmp/mwx-light3-20261006/s-response-curve-20261006.zip`（`5bb4cf2a…2dd`，MANIFEST 含逐文件 SHA）。2D lit image（IMG1 截顶，k_2D≥1.1 倍于 3D）、spot 朝向、pitch 效应、2D 路径 ambient 同为开放。另两条已钉定事实的固有边界：零角(0,0,−1)默认与微小非零→≈+X 之间的近零不连续（时间线扫过零角会 90° 跳变，近零区间无官方观测）；方向改按原始角度直读后父链旋转不再作用于光方向（原 frame 路径会继承父旋转，父变换对光方向的影响未探）。

## 落地（6 文件）

- `SceneDocument+General.swift`：`LightClassesDescriptor` 增 `spot` 键。
- `SceneLightSnapshot.swift`：spot 门控接入；白 ambient 回退移除（N 系/ADEF 证据）；`directional()` 改从**原始角度值**（authored `anglesXYZ` + 动态 `.angles` typed 通道，脚本驱动的 3589454154 日照保持实时）按官方公式计算——矩阵回取会丢 wrap 后 cos 符号（yaw≈2.0346/90 弧度族实测黑面即该错误），故不经 frame；正交场景按 frame 反射约定把方向镜像过 Y。
- `SceneStaticModel.metal`（当时实现，已作废）：ambient 乘斜坡 `clamp(0.5−0.73·n.y, 0.15, 0.85)`；符号经 `ambientColor.w` 传入（正交 −1，作者空间 y）。
- `SceneStaticModelPipeline.swift`（当时实现）：`ambientColor.w` 打包空间符号（ABI 无变化，w 原空置）。
- `SceneDynamicLayerValues.swift`：新增 `lightAngles` typed 读取（有限 vector3 胜 authored）。
- 测试：pipeline 模块 harness 迁移新语义（弧度公式断言、spot 门控反例、缺省 ambient 黑）；shadow 家族 stub 补 `lightClasses`/`anglesXYZ`/`camera` 与 `SceneStaticModelMaterialBindings` 源（多为上午批次遗留红的偿清）；named/spot/point 期望值按斜坡合同迁移（255→128 等）。

## 验证

- 单元：`test_scene_static_model_pipeline`（新公式+门控+缺省黑断言）与 shadow 家族 10 模块全绿。
- 实机 A/B（签名 Debug，相机对象夹具，中心像素对公式精确）：yaw 1→129、1.5708→153、2→139、3→22、90(弧度)→137（官方 142=响应曲线差）、零角黑×2；spot 门控 150=官方精确值、未门控黑=官方 SP1；pt I=4→150（官方 153=k 界内）；amb 省略→37（官方 38）。我方渲染视图对 authored 相机存在水平镜像（夹具级现象，太阳系等真实样本交互已用户验证，不属本批）。
- 预存红（非本批）：`test_scene_frame_rejection_fault`/`test_scene_resolved_material_runtime_bridge` 在 HEAD 因 `SceneCompletedColorSourceIdentity`/`hasTerminalMaterialReplay` 源清单漂移（ce0cd7dd 家族提交未同步 harness）。

## 证据

官方 61 夹具+捕获（含锚点 ANCHP4 复现 153）、我方 33 次运行快照/日志/身份，共 627 文件逐 SHA manifest，打包 `/private/tmp/mwx-light2-20261006/static-light-input-semantics-20261006.zip`（`296498bf…41d9`）。


## 2026-10-09：聚光灯发光轴纠正

此前“spot 朝向未探、保持 frame 语义”由本节有界实测补齐。官方 2.8.0.42 黑盒、自有 scene/material 与原作者球体 MDL，未消费私有实现表达。固定球体与光位，逐项更换角度；每项保留独立窗口名、输入和截图 SHA。CUA 曾返回旧帧，恢复 Parallels 窗口显示前的截图全部作废。

- 光源 `(0,0,2)`、球体原点：零角和 yaw `−π/2` 不点亮，yaw `+π/2` 点亮；同位置 parent yaw `+π/2`、child 零角得到同样结果。
- 光源 `(-2,0,0)`：零角与 yaw `0.0001` 均照亮球侧，未出现零角特殊跳变。
- 区分实验：angles `(0,1.2,0.6)`、光位 `(-0.5981335,-0.4092052,1.8640782)`、inner/outer `4/8`、球 scale `0.1`，官方球中心点亮。这支持既有 `Rz*Ry*Rx` 的正 X 轴，排除此前同轴探针无法区分的球面 yaw/elevation 候选。pitch/roll 在 yaw `π/2` 的相同截图不能单独证明全域角度无效。

产品仅将 `SceneLightSnapshot.spot` 的 `−worldFrame.Z` 改为 `+worldFrame.X` 并沿用既有归一化。作者、typed 动态和 parent/attachment 仍由同一 world-frame owner 处理；模型、2D lit payload 和阴影消费同一 snapshot。未新增角度公式、状态、分支或渲染链。独立 volumetric projector 不属于本次修正。

签名 Debug App 的实际相同输入已验证：zero 中心由约147降至0，yaw `+π/2` 由0升至约147；官方相应为黑/约153，幅度差未闭。原 `3477054430` pkg/project 哈希未改，7秒隔离运行含 resize、PCM 输入和正常退出；猫身侧面补光可见，头部鼠标姿态/时间不同，不作整图误差或完整正确率结论。243包静态扫描仅3样本/9个 `lspot` 声明，是潜在覆盖，不代表其他样本视觉已验。

**当时的下个首断点（下节已修）**：同一 ambient-only 球输入，官方上亮下暗，本机上暗下亮；原始 MDL 法线向外，当前静态模型 shader 的环境光响应式方向相反，端点范围也不同。需纠正既有 ambient 响应合同，不能反转整个模型/normal matrix，也不能仅换符号便宣称 parity。U12 月亮视觉、材质脚本/嵌套输入及整体颜色仍开放。

回归：22项现有snapshot/spot/point阴影测试通过。两处旧夹具未同步现有directional projection的optional/receiverBounds接口，已修调用，像素与失败隔离oracle未放宽；结构、依赖、代码/防御/设计与文档门通过。已知218B `.mimosa`未知归属残留保留，不算本批新产物。

证据保留于 `.artifacts/tmp/u12-spot-direction-20261009/`：`valid-observables.json`、输入/PNG哈希、签名构建身份及 `repaired-u12/`。官方父级非均匀/负/零缩放、完整2D/阴影像素 parity 和整样本正确性未覆盖。


## 2026-10-09：模型环境与天空光响应纠正

旧 NA 球面截图拟合的方向、`0.73` 斜率和 `[0.15,0.85]` 上下限作废。官方 2.8.0.42、自有 scene/material 与合法原作者球体 MDL，只覆盖每顶点 normal 字节；8064 个法线逐一回读为指定单位向量，位置、UV、索引及其余模型字节不变。每项独立窗口和四个确切作者文件 SHA 绑定，未消费私有实现表达。半灰材质、无其他灯/雾/Bloom/HDR，球内 30×30 像素均匀：

| 输入 | 法线 Y | 官方 RGB 字节值 |
|---|---|---|
| ambient=1，sky=0，透视 | −1 / −0.5 / 0 / 0.5 / 1 | 0 / 32 / 64 / 96 / 128 |
| ambient=0，sky=1，透视 | −1 / 0 / 1 | 128 / 64 / 0 |
| ambient=1，sky=0，正交 | −1 / 1 | 0 / 128 |
| ambient=(.2,.4,.6)，sky=(.6,.4,.2) | 0 | 51 / 51 / 51 |
| ambient=1，sky=0，法线=(0,0,1) | 0 | 64 / 64 / 64 |

现有 `SceneLightSnapshot` 保留 ambient/skylight 两分量，不能先相加而丢失方向差异。原模型 shader 以 `h=(1+normal.y)/2` 合成 `ambient*h + skylight*(1-h)`，删除经验钳位及额外正交 Y 翻转；沿用原 normalMatrix、光照/发光/雾和最终输出链。Metal 与 Swift 同步增加一个 float4（uniform stride 1312→1328）并更新 ABI 检查。2D lit consumer 明确保留此前两颜色相加的有界行为，本批不声称补齐 2D 光照合同。没有样本选择器、平行算法、逐帧新建图或解析。

原 84 个 emission/fog/PMA 边界输出保留，增加 10 个固定法线与混色的实际模型 GPU 输出。旧实现在四个非零 Y 点的 12 个 RGB 断言失败，替换后全部通过。为同步删除的构造器字段，旧 1168 行 named-shadow 测试中的完整 ordered Swift harness 移入一份 fixture，Python 降至 999 行；拆回字符串逐字节相同，既有 Python oracle 不变。


签名 Debug App 在相同 12 输入的中心区域逐通道精确复现上述字节值；并非整图或所有模型场景 parity。原 U12 pkg/project 未改，7 秒隔离运行包含 resize、PCM 输入及正常退出：屋顶恢复表面亮度，猫身上部/侧面补光改善，底部过亮收敛，窗光保留。鼠标驱动的头部姿态和时间不同，不能据此给整样本正确率。月亮视觉及材质脚本/嵌套输入继续开放，之后按队列处理 HDR/SDR 和重型样本。

光照/阴影/相关消费者 58 项范围内回归完成：初跑暴露的 point 旧“任何法线均有正 ambient”断言改为按独立输入检查具体贡献，朝下时断言相等；直接光/emission 断言保留。snapshot-capacity 旧外壳缺 clip/prepare 接口，改为编译真实 image pipeline，保留仅作输入的 geometry prepare=nil；旧红像素255改为既有能量合同推导的102（`.5*.5+.5*.30=.4`），容量/失败隔离断言不变。相关失败保留原日志，定向重跑通过。文档、结构/依赖/代码/防御/设计门通过；仍保留预存218B `.mimosa`。

最终证据：`.artifacts/tmp/u12-ambient-response-20261009/` 中固定输入及 SHA、`native-fixed-normal-comparison.json`、`u12-visible-comparison.json`、构建/测试身份和独立审查冻结；原样本必要快照/日志另提升到 `.artifacts/scene-evidence/runs/u12-ambient-response-20261009/`。仍不覆盖完整 BRDF/衰减、2D 模型外合同、HDR 或长期性能，不能将这 12 个输入外推为所有样本完成。

<a id="model-distance-fog"></a>
## 2026-10-09 模型距离雾曲线纠正

基线 `d47cf5c5`。U12 同输入、1210×786官方对照证明：关闭距离雾后，后屋顶及月亮平均 RGB 差均降至不足1/255；开启时模型过暗、普通图片月亮却不受雾影响。修复定位到已有 Fog consumer，不改 Bloom。输入保留作者空 camera path、只关闭 shake；早先删除空 path 导致切换机位的探索组已排除。官方2.8.0.42沿公开 CLI，guest逐文件SHA与本机输入一致，未消费私有实现。

固定半灰材质、无Bloom/HDR的官方控制：常密度0/.5分别为RGB128/64；自有平面距雾起终点的¼/½处为120/96，½处中心96、横向内点94，区别于旧线性距离权重及整面顶点常量。独立实现保留逐片元世界距离、区间钳位与密度端点，只将归一化距离权重改为平方；常密度、颜色混合、发光→雾→覆盖及唯一输出顺序不变。GPU回归额外覆盖偏移区间、倍距离、离轴、区间外和非黑雾：旧实现20个RGB断言失败，修正后原材质/发光与新向量均通过。

同一原样本受控副本的签名Debug App中，native减official的固定ROI平均RGB差：前屋顶从(-31.16,-23.79,-22.98)变为(5.10,-1.75,-.85)，后屋顶从(-16.36,-15.56,-15.76)变为(-.26,.12,-.39)，左楼从(-30.50,-30.37,-21.57)变为(1.56,1.99,-3.07)。这是模型暗部恢复；窗区仍有(11.59,10.22,-1.67)残差，月亮仍约+25，普通图片Fog漏接未修，整样本不闭合。后继须先查2D Fog的生效阶段及共享接线，再复验发光/雾组合，不以全局调色补偿。

构建/签名及4239产品源码身份通过，实际App正常退出、surface归零且GPU排空。最终Metal库SHA `7eeb27c10f7a0a20d33cd68cff02480f4736048150accece7a4ac2a49392b15b`；证据与失败探索分存于 `.artifacts/tmp/u12-full-color-20261009`。窗口动画姿态、长期性能、正常UI→daemon、2D Fog及完整官方像素等价均不由此片证明。


<a id="image-distance-fog"></a>
## 2026-10-09 原生透视图片距离雾接线

基线 `382b063a`。已有模型 Fog consumer 保持输出，原生透视世界空间图片复用同帧 camera/model/light snapshot，经 request 的 typed Fog 参数进入原 MainPass；原 source capture、named graph publication 不施可见 Fog，utility 不参与。模型、固定 image 和动态 ColorBlend 共用 `SceneDistanceFog.metalh` 的唯一距离函数，动态 state 仅准备期读取同一打包资源。没有新增 renderer、pass、纹理拷贝、资源表或逐帧编译。范围只确认普通 image，不能扩称 solid terminal replay、所有2D或文字均已等价。

官方2.8.0.42自有输入，10组各9文件guest SHA一致：plain 128→64；常红 effect 经ICC转sRGB为(128,0,1)→(63,1,0)；红tint+蓝Fog为(63,1,129)；Screen源.5/背景.25在alpha1/.5时分别80/56。Fog在effect/tint后，ColorBlend沿既有含style alpha的颜色混合结果再施雾。原图实际为含Display ICC的JPEG，正式量色先转sRGB，约1U8压缩误差；旧段落的原始截图RGB数值不能直接当统一颜色域的误差。正交常密度.5同样64，但range20/2000两组渐变全黑、无可量形状，未确定其eye/距离域；原生透视之外保持原输出，后继合同见F7，不猜相机常量。

独立审查补出shape覆盖反例：clip/vertex为零时不得把背景加雾。沿原blend fragment区分style alpha与shape，blend→Fog后才按shape淡入背景；关闭Fog保持原blend权重，包括原特殊模式。GPU覆盖距离/变换、PMA/straight、非黑雾、关闭/raw默认、Screen阶段及zero/partial shape；暂拟Fog-before-blend的两项真实GPU红结果与最终绿结果分别保留，未复制算法到测试。

同输入、同1210×786的U12对照统一到sRGB后，月亮ROI的native−official从(24.68,25.31,25.06)降到(-.12,-.06,-.32)/255；前后屋顶、窗区和左楼相对本批修前逐像素不变，关雾各固定ROI同样不变。前屋顶约(.10,.01,.12)，窗区仍(9.91,10.56,4.67)，关雾窗区也仍偏亮，因此下一项查窗区材质/发光/后处理残差，不能仅归咎于Fog。完整动画、真实音源、UI→daemon、长期性能与整样本官方等价仍未由本片证明。

实际签名Debug、App/源码/编译Metal库与打包header身份、原生App退出/surface归零/GPU排空分别核验；证据保留 `.artifacts/tmp/u12-image-fog-20261009`。官方自有窗口关闭、本轮guest目录删除，VM已suspended；未处理此前批次目录或其他窗口。

独立审查保留未整改的既有结构问题：`test_scene_resolved_material_graph_executor.py` 10888→10899行、`test_scene_dependency_graph_output_runtime.py` 2686→2694行、`test_scene_texture_candidate.py` 2498→2509行。本批仅同步真实GPU参数及共享header输入，未完成按职责迁移。Swift code-health通过不覆盖这些Python内嵌Swift测试，也不能据此宣称1000行规则全达标；后续需按完整测试职责迁移并保持相同行为反例，不以截断字符串、拆碎harness或删断言过门。
