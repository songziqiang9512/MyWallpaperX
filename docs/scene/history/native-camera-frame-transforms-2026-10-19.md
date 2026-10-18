<!-- document-role: historical-evidence -->
# 原生相机消费当帧层级变换

> **历史证据 — 非现役入口**。2026-10-19有界修复。输入合同归[Camera覆盖](../capabilities/runtime-input-property-coverage.md#3-scene-与-camera-输入)，样本余项归[现役队列](../roadmap/scene-open-breakpoint-queue.md)。不把相机恢复等同盒体遮挡或整景通过。

## 通用语义与职责

旧Renderer向native default camera传初始化world cache；typed相机与父层TRS已经发布，模型消费当前world，相机却不动。现makeCameraFrame必传同阶段world：SimulationFrame先解析projection再构造相机；缩放/重试用已保存projection；粒子发射、骨查询和cursor复用各自现有world，不在相机内另算层级或保存当前相机缓存。默认选择、visibility、FOV、2D origin/zoom与general fallback维持原owner。

callback阶段的surface输入、骨查询、密集cursor事件共享短期每屏world字典，既有空结果亦不重算；各屏附件按display传递。2D且无投影需求不新增层级计算。暂停sound属性事件在同snapshot时复用保存结果，generation变化则用当前base与冻结topology/attachment重新走原resolver，不推进物理/时钟。Debug startup buffer迁到原Debug文件，无行为改变。

## 可执行与实际像素

最近门先冻结旧owner、仅适配调用实参：6个改名/等价正例全部先证明typed来源、动态lane与current world不同于seed，再在旧eye/basis/NDC失败；missing-world反例也抓到旧owner忽略参数。修后6×10事实及7controls全通过。旧default-2D真实VM门7项通过；cursor队列14项通过，含64事件一次解析、无owner原生相机、预置/空结果、跨屏附件不串屏和原捕获/溢出行为。编译输入前后无漂移，原装配缺依赖失败保留，不当产品红。

自有App两arm保持模型、general、材质及authored相机seed完全一致，只改变camera角度脚本返回值。原producer将作者度数转typed弧度；实际发布分别为(0,0,0)、(.2,.3,0)。旧App两个深度标记停在seed位置；修后精确命中预登记旋转投影与RGB，且原标记离开旧位置。两组App均正常完成GPU/停止排空，输入与App无漂移。

原候选像素断言14/16，两个负例误要求旧far ROI必为背景；独立ray-plane计算证明该3×3 ROI上排3点被旋转后另一标记覆盖，预期均值(89.333333,51.666667,36)与原图相同。保原FAIL；不改ROI和正例RGB，只将负例改为“旧标记色已离开”，事后重分析旧App8/16、新App16/16。未重跑App，不把重分析追记成原运行全通过。

原333同8s/after6、30fps、非零PCM、鼠标(.5,.2)自launch固定及newproperty39=false，对照App4与本批候选。两arm camera37首回调均发布非零角度(.0005728725,-.0022051508,0)，修后盒体视角有变化；未取得after精确相机矩阵或同状态官方姿态，不裁决扁盒归因。背面日期/文字仍透过正面，背景缺失仍在；effect CPU、229局部Program passthrough与Rope三项原FAIL保持。两run exit0、无漂移、stop1→0/GPU排空。目录官方仅供余项对照，非同phase数值golden。

独立原343同候选8s/30fps/after6及PCM，无属性/鼠标覆盖：地球、蓝边、银河星空、日期时钟均保留，地表/云层有变化；exit0、runner FAIL[]、输入/App无漂移、stop1→0/GPU排空。独审首读误报clock缺字，原图哈希未变，逐张high重读确认两图文字完整并撤回；不登记伪缺陷。原光影/夜侧与间歇全屏闪烁保持开放。

## 身份、审查与边界

固定a06b09767加38个Scene overlay（本片新增10产品变化）Debug33.822s通过，4313输入/外部输入无漂移，签名验证0。冻结SHA b4c039c0833377f130a44f2313d8188e57304e26332ff214a6407311c945e54f；exe 2f0f23f8af8edb55b38e26164a05b0533aa78cfe6b4d2df9dab26ed4d1c2fdd7，dylib 3186591b6540b41f64405c33d91cfbf152d40d2fa23a0301fef32e871840ff57。未混入并行Steam/UI改动。

非作者的独立审阅分别核对Root九产品与Cursor增量，未发现新增可行动问题；根代理实看自有原图及333两arm/目录官方。仍未证明native camera拓扑/多path选择、完整3D路径生命周期、HDR或多屏App实机交互、全部官方画面与CPU/GPU/内存收益。多屏附件只到真实Cursor批次参数门，不升级成多屏GPU验证。

必要证据归`.artifacts/scene-evidence/runs/native-camera-frame-transforms-20261019/`，普通14天；仅留一份续接App和构建缓存，原媒体只读、VM与官方主客户端保持运行。
