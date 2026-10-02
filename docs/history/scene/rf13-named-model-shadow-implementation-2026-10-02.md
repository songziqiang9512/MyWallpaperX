<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF13：当前 named albedo 模型参与方向光投影（2026-10-02）

> **历史证据 — 非现役入口**。设计前置提交 `bf73d0b1`，实际 lighting payload 需求补丁 `de72544b`。本机证据根 `/private/tmp/mwx-rf13/`。本片七产品与两个测试已获独立产品终审 **ACCEPT RF13 v4**；稳定职责移交[架构](../../scene/design/runtime-architecture.md)，后继只由[兼容路线](../../scene/scene-compatibility-roadmap.md)排序。

## 用户结果与职责

已准入的 hidden image/solid source-only named albedo 模型，在冷帧也使用当前帧实际纹理、geometry、world 与原 coverage 参与方向光 caster/receiver。此前模型颜色能绘制，但 shadow 准备早于 named publication，而且 caster 还要求静态 albedo 存在；较晚绑定因此无影。未扩 named provider 准入，没有新增 shader、pool、registry 或 compositor。

现 frame owner 保持原完整 forward 一次执行，按原作者资源次序准备 mandatory 资源：source-only 当前捕获、真实模型/粒子 depth、实际 plain scratch、各消费者/utility 快照，最后 Bloom/display 容量，再申请 optional shadow。普通读取背景的 provider 仅提前容量，内容仍在原作者位置复制。相同 epoch 的成功捕获复用原 registry；named 尚未确定时不写空 prepared 数组、不推进 depth plan。失败保留原资源前缀；已尝试失败的 depth 与未访问 mesh 分开，后缀沿原循环继续。无法确定完整 caster 时本帧可关闭阴影，健康颜色仍保留。

## 修前反例与实现纠偏

`baseline-zwnb1ivz` 的原 RF12 App 三输入证明：静态正控 shadow9，named 早/晚两例却85；三者 caster 绿95/control85，named capture/binding 均成功，App/输入不变且首帧、后帧和安全退出完成。协议 SHA `3346dca609aaffff7c42f6cc839424b49a4f5bf079e1ff219d75f03f5b50ea90`，索引 SHA `232ab6e454e952486365919876a28969efed85a11fd678053f159251fa32fa56`。这些为自有合法输入，不是官方像素 golden。

原池 native quota 探针显示，同样只容一份256² target，提前 named 可抢掉较早模型 depth；cancel 不退还缓存物理计费。由此选择完整 mandatory 原序准备，不能用 first-model-only 或 cache-only 规避冷帧及中间 provider。

独审又发现两个 phantom scratch 反例：reflection-only 缺 normal 时原 typed payload miss，本不需要 scratch；非法 colorBlendMode 由原 compositor 拒绝，也不需要 scratch。v1 实际 owner 反例均丢失较晚健康 depth；v4 复用原 payload resolution 和实际 blend supports 准入，恢复健康颜色，并缓存本帧真实 resolution 给原消费入口，避免重复 packLights。environment 闭包仍在原绘制点执行，沿原 F5 准入决定是否可用。

## 冻结身份与验证边界

七产品冻结清单 `implementation/checkpoint-v4-products.json` SHA `c5c963ab3952443a737090e3e2973fb1fc5a30f5c73d48b0b61972e681ba5b0c`；diff SHA `93d9f34f6030f1f1c5856b937d6490156c18cc1d51f3c6044a33ef0947f78bbf`。清单内 verification 字段是冻结时快照，后续实际验证以下述日志为准。完整 Debug 构建通过；不可变签名 App 为 `source-v4.app`，`build-v4/identity.json` 固定五项身份，其中 debug dylib SHA `20fea7ed26332d08c82c3c3ff6a1881bff2bf9c155f3813b33e6fa7cac0b55dd`。本机签名不是公开发布/公证验收。

`named-model-shadow-app-anw8z0bs`：3方法/5输入通过。旧静态、named早、named晚输入逐字节不变，新增中间 image 动态alpha和late solid。新 named shadow9、caster绿95/control85；中间alpha1→0→1时 named shadow9→85→9，而健康静态peer始终9；ready/after整图一致、frame1/2 completion与安全drain、shadow/current named publication/模型binding/terminal消费均可核。独审重算15张PNG，接受该有限App证据。运行测试源码副本为事后按prerun SHA重建匹配，不冒称预执行已保存副本。

forward 附加 App `named-model-shadow-app-hbf7izkb` 使用自有 `own_dim→own_sample` graph：provider31先于consumer50，前者不terminal、后者实际terminal，背景邻区绿100与named阴影9同时成立，frame0/1完成。首轮 `named-model-shadow-app-x2wq_wac` 的坐标fixture错误保留：image作者Y与model worldY方向不同；只改输入坐标，ROI位置/颜色/容差不变，不能把首轮写成产品失败或全绿。

最终测试索引 `test-final-v4.json` SHA `ce71050f4dd679672885d437b6990f0c41b73b6958bdd148c8ad7ff44eb98a56` 绑定两个测试文件、执行副本、全部日志与结果；root逐项复核84个显式文件身份。新测试 SHA `9af3bb8f8936ce593ec7c76e2228e914214b0802b9cec81a17b111779d4a7f00`，旧测试 SHA `d78fe2cdd7bc4b6d3f3a03a0330ea3f7af5cf75ca4af6fe526af5f9bec935722`。最终 native 11方法/23输入行通过（110.092s）；App共5方法/7唯一输入，分3+1+1三次执行，不称单次全量运行。

G3完整App `named-model-shadow-app-zipze1om`：原脚本在frame0将已准入consumer71隐藏，normal composition provider70仍在约3秒恢复前捕获；恢复后当前binding、graph、terminal与next-frame完成，消费区ready背景85→after绿95，原shadow9不变。实际preflight可见性过滤、此完整App相位与native无reservation owner共同约束该边界，不冒称每个隐藏帧的分配次数。native两独立composition provider进一步证明先blue后green的原位内容，重复首provider保留blue，容量阶段red没有被提前发布。

Native owner 门编译实际顺序准备、dependency capture、模型 draw、原 resource pools；prepared route/pose/group/frameplan壳必须与完整 renderer 区分。G1覆盖 cold/真实target resize、source失败后原位重试、同层多mesh ready/failed/unvisited；G2覆盖当前alpha、同epoch幂等、下一epoch恢复、两个cast=false named receiver共享provider且仍接收独立caster阴影，以及SharedEvent阻塞已提交A时B resize/取消后A完成，shadow resident最终归零。该强引用探针不证明named纹理最终析构。

G4 mixed覆盖真实color-blend、粒子depth/refraction、utility触发、原snapshot与Bloom消费者的8行：可选map拒绝保mandatory、中途失败保前缀、失败depth不重试、terminal Bloom容量失败后原encode继续。其activeNamedModels为空，named组合另由G1/App证明；terminal回调不等于完整coordinator/display scratch执行门。

原 FrameOwner3方法通过18.670s：仅适配新接口的未调用壳，原3方法断言不变。因root漏设证据父目录，原执行目录 `directional-shadow-frame-owner-4rtxdkd0` 精确镜像到 `legacy-frame-owner-v4-evidence`，逐文件SHA一致且所有编译源均匹配v4；不因路径重跑GPU。该模块只编译七个改动中的StaticModels。

原完整包3589454154使用已隔离副本运行8秒：exit0、App/输入身份不变、frame1完成、drain、22模型prepared，零shadow；`original-v4/protocol.json` 与 `summary.json`保存结果。仅作既有模型显示邻接，不宣称原包named阴影收益。

code-health通过（1055 Swift、0 locked legacy、8 locked review warnings、240 warnings）；scene-defense通过（0 locked dead、18 canonical、3 swallow），design-gate通过。没有改结构/防御预算。产品独审已接受上述冻结身份；移交时文档角色13方法通过，未放宽测试。

测试壳曾有直接CPU读取private纹理和unsupported控制的两个编译错误；分别改为同CB blit读回、修正重复声明与类型别名。未改产品或像素oracle，不把这些测试基础设施失败计作产品红例；现场与实际v1产品红例由最终索引分别登记。

## 未验范围与下一方向

不宣称官方parity、性能、多屏、App窗口resize、全部model格式、effectful named source、所有group/forward组合或其它光型已完成。native target resize与实际App分别证明各自范围。保留原失败现场，证据不纳入源码提交。

下一主片为真实模型聚光阴影：从cast意图进入唯一typed light到透视投影、当前资源与选中灯贡献闭环，采用本项目独立算法；全向point紧随，不能用单面图冒充。参考资料用于中性输入/生命周期/消费职责，缺私有方法不构成跳过理由。reader 22/24差额先具体归因，不能猜测放宽安全边界。

## 终审与提交边界

独立终审 **ACCEPT RF13 v4**，报告 `product-final-review-v4.md` SHA `36ea4d9a7df371e5a2c768f6b41c6e9ecacfdb7386f66089a5b1dcc2c81a41a8` 接受七产品、两个最终测试及上述有界证据，无剩余产品finding。稳定职责移交架构，[前置设计](rf13-named-model-directional-shadow-design-2026-10-02.md)归档并删除本片窄gate；D3整体仍持续实施。按职责窄提交，不包含并行layout排序；未推送。GPU/App执行已结束，唯一失败现场和精确证据根保留本机。
