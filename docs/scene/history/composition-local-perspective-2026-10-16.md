<!-- document-role: historical-evidence -->

# 无子层composition：平面采集与透视回绘（2026-10-16）

> **历史证据 — 非现役入口**。有界实施证据。 现役合同归[SceneScript覆盖](../capabilities/scenescript-api-coverage.md)，设计归[D1](../roadmap/batch2/composition-render-target-design.md)与[D4](../roadmap/batch2/script-component-api-design.md#prepared-empty-composition)，剩余视觉问题归[队列](../roadmap/scene-open-breakpoint-queue.md)。没有性能结论，也不关闭288音频ROI或整样本。

## 通用语义与实现

普通正交画布中，无parent/成员/依赖、copybackground=true且非passthrough的composition可以保留平面局部采集，以真实perspective输出回绘。原Layer能力判定、CameraFrame、CaptureGeometry共同决定：flat capture矩阵控制affine UV和源extent，output矩阵控制quad、cursor与effect反投影；preflight、utility draw及raw named预留/采集一致。group已含成员world变换，仍沿viewport目标与1:1回绘；native-camera、其他utility和未知形态不扩。不增加homography、shader ABI、相机、资源或compositor owner。

原prepared image/Puppet模板泛化成唯一prepared resource-layer kind，空composition只携可信utility资格，不伪图片、不继承source的effect、成员、脚本或最终纹理。nil/false/true沿原C record/ABI/journal、Swift候选与typed topology保真；未消费的动画、effects、背景/config、parent/children/dependencies出生前拒绝。空组无effect只参与原顺序；原throw/discard、排序、creator退休和GPU completion生命周期不变。动态getInitialLayerConfig仍unavailable，未因本片开放。

## 官方自有正控制与失败边界

固定官方2.8.0.42，exe SHA `daac1ea7c991207fdb6098616757e3dae393850f6862845db55d04921b6bda07`。自有1210×786场景，根origin=(605,393,120)、size=(300,180)、serialized angles=(0,45,0)，背景有非对称标记，effect独立RGB反色。只切perspective；不把raw45称为度数。

四角均由各自像素边界定位，±1px，未由三点补第四角：

| 模式 | TL | TR | BR | BL |
|---|---|---|---|---|
| false | 526,303 | 683,303 | 683,482 | 526,482 |
| true | 353,105 | 681,304 | 681,481 | 353,680 |

true的闭合残差约398px，内部横条变斜。用四角拟合后检查未参与拟合的标记，六处品红边界约1.7px内，22,682个离边缘平坦点RGB吻合false局部内容的回映值，反驳屏幕对齐pullback。这里只裁决外部行为，不认定官方内部RT/pass/算法。

最初helper未找到旧receiver4944，未复制/打开；后续以fresh PID5368/Session1与启动身份执行。第一次截图被终端遮挡；r2自有fragment的单scalar vec3构造触发官方X3014，纯红图不是几何证据。r3改为显式三分量并按公开object-space接口消费MVP后，false正控通过才跑true。只置顶、捕获、关闭exact own窗口；完整client在物理屏幕内，五点窗口归属吻合，receiver前后保留。官方raw帧留仓库外`/private/tmp/mwx-composition-perspective-20261016/`，仓库不提交官方帧或生成blob。

## 原生GPU、真实消费者与未证部分

候选Debug executable SHA `eb306066d3addf648d9977815232f2b6e7b4b19dba16d0b3bee310b98dd9b8de`，dylib `650afc99bd7115b2b8607702206a6c3ae0550bc66ea61094b56d5505ed135eb1`。构建48.083s，4327inputs drift[]，codesign0。

自有相同输入原生false/true实图，经独审独立测四角再数值归一到官方client：四角约1px内，内部品红斜条/蓝竖条保持同一局部纹理的透视重放；边界仍有约2px等效raster/filter差异，不称pixel parity。源extent两臂同为394×450，target230两帧均GPU完成及末合成消费。原生夹具首轮project.file误指容器pkg导致launch-failed，改为scene.json后有效；失败收据保留。

2887542690原包两次constructor literal均own Boolean true，authored286也写true；原层无成员/依赖，默认copybackground=true，两effects不可继承。旧App同原包/四点轨迹/1000Hz PCM在286 init报visible-of-null。候选callback完成，原共同事务接纳，dynamic33→34；286两effects同Program于frame0/1/51/90完成，末effect terminal消费，采集extent随pointer由2048×1152→2048×1163→2048×1152。原右侧外悬蓝条在两次同位置观察中不再出现；这只能算可见变化，不能把其他卡片/人物倾转都归给286。

**音频ROI仍未证。** newproperty5只直接绑定286.visible。最后一次同window45423的true→false→true均accepted，pointer仅±0.00001微移；独审series0000/0001/0003没有找到可重复归属的音频条，旧外悬ROI三张计数均0。可能被后层遮挡或本阶段无可见贡献，不能称图框内音频已恢复，也不以GPUcompleted补证。该资格STOP，不扩大时间/样本矩阵；黑遮挡、字体/偏移、片区布局与完整交互仍未关闭。

独立原包3264246690未参与修法：人物、绷带与DANGER带呈现，0 VM exception，64 completed graph记录/22 terminal；未验该包旧点击换口罩等余项。ready25.644s、total33.142s只为运行身份，不是性能比较。全部有效原生运行exit0、input drift[]、进程组退出、surface1→0及GPUdrained。

## 最近门、独审与材料

几何/camera42项、继承parallax5项通过；创建/初始配置/真实C ABI与factory/层序18项通过（137.795s、182inputs drift[]，其中66个composition事实），原Runtime perspective最近方法1项通过（2.707s、10inputs drift[]）。邻例含普通image/Puppet三态、改名资源、inherited/Proxy/getter、throw/discard/晚拒绝、双实例、排序/退休与native/group边界。历史fixture缺Bloom/metadata依赖、新断言误用unavailable动态配置及缺solid参数的失败均保留，未放宽产品合同。原1016行Runtime测试完整搬迁为Python188行和Swift fixture841行，17个旧test方法AST不变。

一次最终独立源码审查复用同产品hash，后补实际四角/画面、CPU与停止收据；没有以App build/测试数替代上述边界。code-health、defense/dependency/design门通过；未测HDR/多屏/native-camera composition或更广named组合，不推性能/官方全样本parity。

限期证据：`.artifacts/scene-evidence/runs/composition-local-perspective-20261016/`，manifest SHA `7c953b8ccc7fec3240cb9b87537e78c71f126258dd31de0f8c1a3e8700d1d734`，27,242,971B，普通14天保留；ZIP SHA `9077ff4bb6fb3f8efdaefbe780cacfd2a5404788d0e98c136aff610fe070b65d`（117 entries）。报告、哈希、必要PNG、自有输入、失败与最终测试/独审收据压缩归档；原始媒体只读且hash无漂移，Windows四个exact own输入目录及其本次生成shader cache经逐文件核对清理，既有receiver/UI和VM保持运行。本轮归档后清理672,766,659B逻辑字节的临时样本、HOME/cache、重复图及构建日志，只复用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`一份构建缓存。
