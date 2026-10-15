# Camera layer FOV 属性脚本热更新

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**

现役能力归[脚本合同](../capabilities/scenescript-api-coverage.md#camera-layer-fov-scalar)，选序归[属性卡](../roadmap/properties-panel-card.md)与[性能卡](../roadmap/performance-convergence-card.md)。

## 通用语义与责任修复

合法 native-perspective default-camera layer 的 FOV 脚本此前留在作者数据中，却没有 prepared scalar target；内部 Slider 因缺实际 consumer 无法进入热更新。修复沿原 property codec、Scalar Program、QuickJS 与 layer-scoped typed snapshot，由唯一 camera-frame 消费当帧 FOV。它只补属性脚本，未开放 ICamera handle setter、direct-FOV user wrapper、FOV Timeline 或其他相机字段，无第二 VM、相机、值表或投影算法。

准入只要求原投影政策及实际 camera layer，不再错误地要求 Scene 备用 Eye/Center/FOV 完整；最终 world pose 和矩阵仍由原相机 owner 验证。authored、VM 返回与 typed 发布共用 Float 可表示的有限 `0<fov<180` 度范围。非法返回拒绝本 owner 本轮值及 bundle 副作用，硬失败保持 previous-current；隐藏只改变选择。真正 topology 退休按实际 Program owner.layerID 撤唯一 Schema 的 stateful 登记，Context 消费当前登记；下一 cadence 回低优先输入，held snapshot 不变。新增收集只在实际 retirement outcome 存在时运行，累计墓碑全部 quiescent 后不再扫描。

## 验证与界限

最终9产品 aggregate `768cf00f6880b153ec080cef1a71caf300de324de6f3ce927ecb22685e109a29`。真实 parser→Program→QuickJS→snapshot→相机聚焦门1方法/59 facts通过，56.459s；含100→80度和矩阵变化、改名等价、缺 Scene fallback、显隐/作者顺序、非法值与 bundle 拒绝、编辑/reset 保 init 和音频平滑、真正退休/失败保留、held snapshot/代次及5次累计墓碑反例。fixture 的早期参数/载体错误单独保留，不当产品失败；门未运行完整 Session 或原生 UI。

最终独审按九产品 SHA 接受；Debug 构建30.822s，4298输入无漂移，App SHA `3ec09e8eeaeba6ac49462c56bc1f5e992968a01cf7fd3e4d249ecbfe9dba2b13`。原生324实际将两个边界先设为0.8/0.8，再设1.2/1.2；每组保存、关闭重开保值，实际时钟/粒子构图由大变小，root与独立执行者均查看实图。相等边界消除此脚本的音频插值项，未用mute；80/120度是作者公式预期值，原生没有导出数值FOV gauge，不把全部动画像素差归因于FOV。实际reset/重开回1/0.95，全程同一session `63F0C46D-EA48-4D56-945E-057F82CCDE3D`，candidate/first-frame/activated各一次。独立304原样可见塔、双人物、星空和时钟；原1128 bad-return仍开放。两case均实际Stop后Quit，18/18及71/71 VM quiescent、待办全零、exit0，四PID全退出。pin终值、完成帧计数、多surface、FOV暂停恢复及完整画面/官方parity未验，不申报CPU/GPU/RAM或延迟百分比。

## 证据与产物

冻结输入、59-facts原数与失败前置、独审、构建/App身份及原生操作收据归 `.artifacts/tmp/camera-layer-fov-live-20261015/`。两份snapshot verify均exit0，原件/副本变化为空，核验前只恢复setup移出的复制品marker且不覆盖新文件；App关键SHA前后相同。已清401760452逻辑B停止runtime副本，保两张FOV对照、一张reset面板与一张独立304实图，共24905618B，以及AX/原日志/小收据。最终验收后聚焦编译产物按归属清理；保当前App与一份连续DerivedData供后继，旧唯一GPU失败证据不动。
