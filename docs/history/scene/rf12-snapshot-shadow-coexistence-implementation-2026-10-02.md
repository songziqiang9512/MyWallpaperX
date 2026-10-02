<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF12：背景快照与模型阴影共存（2026-10-02）

> **历史证据 — 非现役入口**。设计前置提交 `fe048ff3`；本片v2已获独立产品终审ACCEPT，按下列有界范围交付。稳定职责见[架构](../../scene/design/runtime-architecture.md)，后继顺序由[兼容路线](../../scene/scene-compatibility-roadmap.md)决定。

## 断点与实际改动

F6 为保护晚申请的 color-blend/refraction 背景纹理，在存在真实消费者时关闭 optional shadow。另有空粒子批次在原 update 返回成功后仍进入绘制集合，虽最终没有可绘 slot，仍先复制整帧；utility 的背景消费者也被旧 image/solid/text 白名单漏计。

本批沿原 SceneFramebufferSnapshot 单槽、两个 pipeline 原实例与唯一 SceneResourceBudget 准备实际 target 容量。Bloom 与模型/粒子必需资源先于快照，快照先于 optional shadow。嵌套同步作用域仅准备容量；后项失败整组恢复旧槽和计费，原作者顺序绘制仍可重新申请，不能把快照失败扩大为原层硬拒绝。成功准备不代表有像素，每个消费者仍在原位置复制当时背景，不能借环境反射的首次共享前缀。

上传仍先执行 update 以清除旧 current slot，再以该 buffer 的真实 currentDrawState 保留可绘批次；同一集合供后续需求、depth、draw 与取消消费。utility 从现役触发字典和 prepared plan 取实际 enclosing pass；该字典的唯一 producer 已过滤 shouldCapture，不新增同义防御。迟到 publication 不被提前判为 absent。两类实例仍各只有一个实际尺寸/格式槽；不能覆盖同帧实际目标时局部退回无影，不造多槽 registry。

## 反例和工程纠偏

本机证据根 `/private/tmp/mwx-rf12/`。预先冻结的160×96自有输入及camera cover ROI显示：旧App混合区域green64、非零折射blue/零值red均正常，阴影和控制区却均85；新合同要求仅阴影恢复9。停止后的empty粒子实际nonempty=[]，旧App55帧仍55次整帧复制，累计计数约1.3066GB，并关闭阴影；隐藏控制0复制且阴影正常。这是复制字节计数，不是性能测量。

早期大折射位移落黑区、ROI未采用实际cover相机的两次fixture错误保留，不当作产品失败。最终旧App合同测试4方法/6输入中2方法通过、2方法失败（mixed两子项与empty）；utility两输入既有输出通过，证明可达消费者但不证明已预留资源。独立修前/协议审查 `baseline-protocol-review.md` SHA `8e82a495401086853903026837860d33cbf83131d68c704ad3f85d12bf8c85b6` 已重算截图与身份。

v1 Debug构建通过但防御门失败：两个 pipeline 新增相同转发函数使重复组127→128。v2删除转发，内部只读访问原实例，未改基线或新增wrapper；防御门恢复127并通过。v2七产品manifest `implementation/checkpoint-v2-products.json` SHA `ead7a3bf1af75b0be7cc0d661956526cc07b5d190d95dfef62dadb3b33bab95a`；构建前后源码一致，`build-v2/identity.json`保存五项App/helper身份。隔离App已完成本机有效签名及两个编译helper固定Team requirement检查，不属于发布/公证验收。

## 验证与范围

实际新App 4方法/6输入与原F6单方法/3启动共5方法通过（83.247s）；`app-final-v2.log`、`snapshot-shadow-app-5g1d01uq`、`directional-shadow-app-7vdkd737`保存输出。mixed-active为52帧/104次capture/52次completed refraction，原混合green64、折射blue与控制85不变，阴影为9；empty52帧0capture、0refraction且阴影9。utility active/normal都实际完成合成，原控制像素分别64/100。root目检mixed-active截图与ROI一致。资源门如下，最终产品独审已接受。单槽native GPU门与真实App各自证明其范围；prepared输入壳不等同完整renderer admission。未验证完整原包画面、官方parity、性能、多屏、全部group/forward组合；point/spot、动态named caster等仍属后继，不因同帧共存关闭整个D3。

真实未改原包 `3589454154` 再验使用隔离副本及v2签名App：exit0、input/App五项身份不变、frame1完成及安全drain，仍22个模型prepared、零shadow事件，无helper签名拒绝。证据`original-v2/identity.json`、`summary.json`；不计完整原包阴影受益。

后继选已准入hidden image/solid source-only named albedo模型投影。其真实模型显示路径已有记录，但不代表原包开启shadow；先建立同帧named颜色正常而阴影关闭的反例，再经设计把当前publication前移到原dependency owner。未知模型reader差额和point/spot继续以实证定优先级，不能用缺少私有公式跳过。

最终资源组合首轮16方法为14通过/2失败（47.946s）：core4（含最后引用释放）、refraction6、旧F6 frame-owner3、实际upload1通过；新frame两方法在state.arm移交并清空shadow之后才读取布尔，错误记录为false。保留原日志与source，仅把观测移到arm前，不改产品、像素oracle或断言；单frame3方法复验通过（16.858s），日志`frame-final-v2-observation-fix.log`。这个fixture失败不能冒称产品回归，也不能将后续复验拼成首轮全绿。

App独审报告`implementation/app-stage-review-v2.md` SHA `b6c0bb73ba54a4e37b27c3474b2a9c3a5ecdef4ad14d6fe03f53c728beee332c`逐项核输入、包、App及PNG。F6 late-color-blend-active日志只提供surface frame0/1 completion，frame1另有实际graph next-frame/compositorConsumed/GPU completion，不能统一写所有9启动均有surface frame1/2。

最终测试源清单`test-source-final-v2.json`绑定4个本批测试文件。capacity共7方法（core4+frame3），折射邻接6与旧frame-owner3均取得相称通过证据；不会把3方法复验重复累加为新能力数量。core编译实际Snapshot/MainPass/ResourceBudget，验证SDR/HDR两次不同内容捕获、容量不编码、第二owner真实物理配额拒绝与整组回滚、旧identity/内容保留、原lazy capture恢复，以及同queue共享事件阻塞/resize/最终引用释放。frame门编译实际StaticModels/Particles扩展、两pipeline及原pool，prepared资源壳groups=nil；实际utility完整合成由App另验。all-invalid/healthy-peer只证明实际buffer上传结果，empty零复制另由完整App证明，不冒称全部非法输入经过App。

Debug构建、code-health、防御面、design-gate通过；文档门最初缺标准历史banner导致1项失败，补元数据后13方法通过，未修改测试或放宽规则。未增加结构预算。完整App构建和shader未因测试观测修正而变化；无须为测试壳观测点重跑全部App。

## 终审与职责移交

独立终审 **ACCEPT RF12 v2**：`implementation/product-final-review-v2.md` SHA `b98d69fa82c4c3fbc783cc7d460310fd4b39e0cfb2e1cebbee9e7e714346a2ac`，绑定上述7产品manifest与4最终测试SHA。16个不同资源/邻接方法取得有效通过证据，不能把有fixture失败的首轮写成全绿。稳定容量与顺序合同已移交架构，[前置设计](rf12-framebuffer-snapshot-capacity-design-2026-10-02.md)归档并删除唯一窄登记；整个D3不退役。并行历史文档、其角色/导航登记与layout排序不纳入本提交。未推送；证据保留本机精确目录，App/GPU执行已结束。
