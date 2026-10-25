<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

# Scene 启动 D2：结构资源的同源字节读取

> 截止2026-10-24。实施顺序与退出条件归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，目标边界归[启动合同](../architecture/scene-launch-responsiveness-contract.md)。本批未提交，只结算目录读取边界；全量PKG展开仍在，不认领P2完成或正式提速。

## 实际改动与前后反例

ResourceView 的 authorHandles/reference 投影复用原选择核，读取委托同一Root。Catalog 的model JSON、material、puppet附件和effect改从handle取得Data；EffectDefinition原URL叶退役，JSON5/未知字段/摘要仍由原解析核解释。SourceFacts的直接MDL metadata也从handle读取，保原完整格式验证。完整作者namespace、大小写/遮盖和全局引用优先级保留，不缩成静态场景引用，不改成同root sibling，不新增尺寸阈值。选中来源变化/invalidHandle和现有取消错误穿透；普通缺失/JSON/MDL解析失败仍局部，不重选较低root。

改前保存的是实际D1/v3工作源码，不是HEAD。新真实SourceFacts→ModelBuilder harness在5类文件打开FD后原子换源：model JSON、material、puppet、effect、直接MDL，分别走Facts/Model两caller。四份实际改前产品源码的39项中恰10项换源保护失败；候选同名39项全部通过，包含取消、普通坏内容保peer、恢复完整投影、未静态引用模型的动态链接和坏MDL尾部拒绝。不是源码形状命中或随机文件竞态。

Catalog门撤掉空AttachmentReader替身，直接执行真实附件解析，覆盖改名、package/loose全局puppet优先级与坏MDAT局部。五模块30项先通过；defense指出新增`(try? parse) ?? []`表达式，未放宽预算，改为仅包围已读取Data解析的显式do/catch。最终受影响Catalog7项通过4.409s，SourceFacts39项通过23.213s；其余7个owned输入未变。完整5/8/64段MDL及后段损坏依赖门通过（22.973s）；该门在显式附件catch前执行，所用MDL核未变，不混称最终重跑。Effect三份直接测试caller改在测试边界读取Data，产品无旧URL入口。

## 签名与产品运行

优化Debug/WMO构建335.717s通过，构建前后全部Git可见文件摘要均为`f08dca6aa2f5ab6b05ec47485ae7f03aa3396bd3ed4c52031dfeae598d3076d4`；候选executable SHA `080f17b75c8c9c443853695e8408d96896913e85da2b5df418ca5a3758e4c34c`，CDHash `ebfe4439918099aa088875be6a65cea9070f1a9b`。直接前驱为上批最终v3 SHA `355bdb60b3b72958fa5a64f078bdc94661d67fdd222c907a85da432997c87cf6`。专用bundle `com.songziqiang.MyWallpaperX.Debug.Startup`、Team `H9QWU9XN8R`、2.11.0(283)，deep/strict验签通过；仅未改InspectorBadgeView原NSBox弃用警告。无安装或Release结论。

沿原真实setAsWallpaper入口，30FPS、标准域哨兵、独立HOME/私有suite、原输入和生产偏好双摘要。两个作者Scene和既有自有app_fixture(5)的PKG形式，各一组AB，共18App/24请求均匹配presented及parent finalize，正常退出、无owned child残留，原输入/生产偏好不变。W0只有同App/daemon后继请求纳入。未清系统cache，也没有噪声/CPU/GPU/峰值内存/能耗完整卡。

| 单组资格，ms | C0 前→后 | C1 前→后 | W0 前→后 |
|---|---:|---:|---:|
| 375作者重输入 | 2026.508→1602.166 | 1109.927→1042.677 | 315.820→290.410 |
| 314独立作者输入 | 1390.394→1279.903 | 884.787→893.032 | 131.777→123.888 |
| 自有五段MDL PKG | 1158.781→846.952 | 820.556→820.805 | 89.126→93.206 |

各条件每arm仅一个原点，表格只保对照，不计算正式收益或“无回退”结论；C0的先后/系统缓存因素未消除。未补完整像素、下一帧ROI、长稳、多屏、真实App中sourceChanged竞态或typed daemon drain ACK；parent finalize不能代替drain。上批v2 Web C1未归因证据继续保护，本批未触及Web产品链。

MDL首次补样误用loose目录，现产品isSceneLaunchable要求package，未改前驱在准入阶段拒绝，0请求/daemon身份，候选未执行。按原App测试形式在新ID/目录打PKG后通过；原失败报告与输入manifest保留并标为fixture资格错误，不改产品准入、不删除慢点或并入有效表。

## 后继与产物

目录句柄仍不认证作者字节；完整MDL/puppet几何、Project/SceneDocument、粒子JSON、TEX/直接图片/sidecar/字体和URL媒体尚有原读取叶。当前脚本来自inline JSON，只有内建模块，没有作者.js文件读取叶；LocalStorage属可写状态。下一步按专项闭合剩余消费者，receipt及实际lease/CPU/GPU/provider退出齐备前不激活package backing。

有期限证据包`wallpaper-startup-scene-d2-20261024`保存源码身份、实际before、门禁、构建和全部运行原点，默认14天；batch/report.json的samples[].label映射原路径，实际文件按数字id保存。resolved loose-fixture失败保文本证据，不作为未归因产品失败。旧未归因保护包不动。

当轮raw运行目录、staged App/HOME、CPU编译产物在提取后精确清理；持续goal保留一份DerivedData、固定输入与必要比较App/before-source，精确保留/删除收据在任务根。主工作区干净；实施树未暂存、未提交、未推送，goal仍active。
