<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# D3 F6：静态模型方向光阴影（2026-10-02）

> **历史证据 — 非现役入口**。设计前置提交 `22ebc9d2`；目标见 [D3 F6](../../scene/design/2d-lighting-material-design.md#f6-model-directional-shadow)。本片v7已获独立产品终审ACCEPT，按本记录限定范围窄提交。后继顺序仅由[兼容路线](../../scene/scene-compatibility-roadmap.md)拥有。

## 范围与独立实现

公开作者合同与合法语料把旧 image/one-spot 草案纠正为真实静态模型的单方向光投影。现 Format→descriptor→唯一 LightSnapshot 保留灯身份与投影意图，现模型 mesh、world、材质和相机 depth owner 形成候选，原 offscreen pool 持有一张灯深度，原模型 draw 仅衰减被选方向光的直射贡献，再写原 compositor。普通 image、Puppet、粒子、其它光型和动态 provider caster 不因此获得支持；模型 importer 原有上限不被绕过。

第三方只贡献职责和开关边界；投影、深度偏移、采样和硬 cutout 均为本项目独立策略，不声称官方公式或像素 parity。旧实现员在 v2 冻结后误触含 shader 文本的运行证据，立即停止产品写入；未向 root、测试和审查转交表达。后续由新上下文 owner 按正式中性合同和本项目源码接手，v3 修订不消费该原始工件。事故不作为永久跳过能力的理由。

## 反例和纠偏

本机证据位于 `/private/tmp/mwx-2d-shadow/`，不可变 App 与按次隔离内容/HOME 分开保存。

旧 F5 App 的自造合法 MDL 输入已实际显示接收平面与绿色投影者；只改 cast 开关时 ready 全图完全相同，几何预登记阴影 ROI 和控制 ROI 均为 RGB85。两次运行 exit0、frame1 completion、drain、工件身份一致。`old-app-pair-v3/evidence-manifest.json` SHA `91b7ff423ba5b99a88f925c5a7552165bfbd3ff3356856e54a70490494f9ba6e`；独审复算22项身份。更早两版 fixture 的错误原点/绕序不计产品反例。

产品 v1 的基础 App 门通过。v2 仅调整灯投影 basis，却使同一输入的阴影消失，真实 GPU 也失败；已根据实际反例恢复 v1，未调整 oracle 迎合结果。独审另发现作者 scale `1 1 0` 的平面仍能被 shadow 绘制，而原 color draw 因奇异 normal transform 不显示；v3 在原 draw 准备时复用唯一 normalMatrix 准入，局部剔除该层，不把失败扩大为撤销其它合法投影者。消费端无真实生产者的重复 texture guards 同时删除，保留提交/帧/灯身份边界。

扩展门又抓到自影：v3 中投影者平面自身 green 从95降为67；独立同平面正向 ray 的交点为0，应无遮挡。真实GPU新增第32向量仅该项失败，Full红通道0.29370117，实际0.24609375，明显超过两个half ULP，原31向量仍通过。根因是邻域tap共用中心比较深度，未补偿斜面在实际texel中心的深度变化；不能靠增大全局bias吞掉近间隙遮挡。v4按接收平面校正实际nearest texel中心，只保预先固定的8个Float epsilon乘运算量级的数值裕量；38组通过，正间隙0.1/1仍遮挡、负间隙0.1不遮挡。该裕量是项目保守策略，不是全域GPU误差定理。随后两种有限近切面输入分别暴露不同问题：v5 对越过 map 有效域的单 tap 回无影，保九次权重，修复其中一例；极小模型的另一例仍失败。v6 改从 world position 导数变换到灯空间，实测改善梯度精度但单独仍未修复。v7 在同一固定 8 epsilon 裕量中计入实际 world→shadow 变换的运算量级及 XY 误差对斜面深度的传播，没有加入试凑的世界距离常数。最终 42 组独立 GPU 输入通过，新增同一近切面方向前方 0.1 间隙仍遮挡、后方 0.1 间隙不遮挡。该测试范围不推出极端有限输入的全域保证。

## 资源和验证边界

模型 shared/isolated depth、需 depth 的粒子、既有 image/HDR scratch 与 Bloom 中间目标先取得实际容量，再尝试 optional shadow。准备与原绘制消费沿同一 owner；提交后 pin 只在 actual completion 释放，未提交才 cancel。尚未可确定的 late named albedo 或实际 refraction/color-blend snapshot 需求使本帧 shadow 关闭，原路径保留；现 snapshot owner 的实际容量准备是明确后继，不以缺方法无限搁置。

真实池门包含 depth readback、同/跨 command buffer、已提交但被共享事件阻塞的在飞资源、reset/resize/completion/cancel；实际全局预算注入拒绝 shadow 后，原 Bloom encode 和已预留深度仍可执行。这是确定性配额注入，不能称整机 OOM；手动池 acquire/readback 也不单独证明整个 renderer 的一次消费。

独立几何 oracle 在运行前审查，并按保留的真实反例扩至42个输入；真实 GPU 检查遮挡差量、alpha不变、ambient/emission/另一灯正控制和帧/灯/CB错配。首轮清深度与完整 emission-mask 的 harness 错误保留，不冒称产品错误。带透视的向量采用非零 world Z，避免退化成恒定 w=1 的虚覆盖。实际 frame-owner 门已完整编译原 StaticModels/Particles 两个 extension：prepared leases3→3、shared/isolated/particle身份保持；optional物理配额拒绝时四ROI与原路径逐byte一致；mandatory失败后恢复配额，仍leases1→1且失败draw不重新申请。独审确认该门有效，壳提供prepared输入、groups=nil，不能冒称整个SceneMetalRenderer admission。最终 v7 frame-owner 3 方法通过（18.407s），还显式先打开原 MainPass encoder 再调用准备，核验 offscreen 切换。壳仍不等同整个 renderer admission。实际 App 门单独验收。

最终 v7 产品17文件清单 `implementation/checkpoint-v7-products.json` SHA `de58fe903e466f88cf7aa829a6081d7a98ab57e4871b7ac56e9cdb29580e8064`；完整 Debug build 成功且构建前后源码一致。隔离 App 使用本机有效 Developer ID，deep/strict 与两个编译 helper 的固定 Team requirement 检查均通过；身份见 `build-v7/identity.json`。主 executable SHA `eb036d7b369104d9bf1a2e87cfae0883b742c146a4a60648ec2971590aa30bd4`、debug dylib SHA `8112d0c983c92e32b3ae9971557ab539f010081466298d02a7748135bddacf10`、metallib SHA `7f9fef9facfc7f2c1d1244350a837aa9c16c288af68e33321a152412ee23f9ab`。这不是优化性能、签名发布或公证验收。

本机最终证据：`f6-validation/directional-shadow-authored-y8gok614` 为 parser 2 方法/32 检查，`directional-shadow-pool-bsik3sp6` 为资源 3 方法/26 检查；shader 修订后 `directional-shadow-pixels-djeun3yd` 为 2 方法/42 向量，每向量9个实际 draw 对照。主模块共有7方法，不累加重复运行次数。`frame-owner-v7/directional-shadow-frame-owner-b74k4g1a/result.json` SHA `07800f9232994386beaee4a7c13ff0be5c3324fca5018e4a7ea0d3d223248f2e`。code-health、scene-defense、design-gate 在最终 v7 均通过，未增加结构/防御预算。文档门一次误用不存在的模块名已纠正，不能将启动错误记成产品或文档失败。

最终 App 协议包含10方法/22个自造合法输入。第一轮 `f6-validation/directional-shadow-app-07g_zp7i` 实际运行196.774s，9方法通过、移动灯方法失败：测试把静态 JSON 弧度值直接作为 SceneScript 角度返回，既有 VM 边界再度转弧度，导致实际灯近乎垂直。`SceneScriptLayerHandleBridge.swift:4–15` 与 `SceneScriptValueRuntime.swift:608–614` 规定该边界。原日志和失败保留，仅将脚本输入修成±45度，静态值、ROI、容差与产品不变，修正后单方法/两次启动通过（19.766s，`directional-shadow-app-5mey7j7w`）；不能把两次运行写成一次全绿。最终审计 `app-final-v7-audit.json` SHA `13229a0a14da07476370df3ed458518a2764fffeb95146a47a12f0b4eb3a4bb1` 逐项核22输入、包与App身份、frame1/2、完成/退出；阴影ROI由85降到9，未遮挡控制85不变，caster开关前后均95。F1无效投影位置85且另一合法投影9，证明局部剔除。

相邻静态模型6方法通过；旧 harness 在 HEAD 的真实隔离编译已证明缺 SceneResourceBudget 依赖，本批补入实际 source list。删除“整个 shader 不得出现 constexpr sampler”的旧形状断言，因为固定灯深度比较 sampler 与作者底图 sampler 是不同合同，不以源码字符串验证采样行为。instance底图模块5方法通过、App类跳过；新 parser/descriptor/旧 Codable 门另有实际 Swift 输入。

真实 `3589454154` 基线和v3都只有22个模型实际准备成功；v3 exit0、frame1完成、安全drain、工件身份保持，root目检同样的星空/时钟及底部局部模型。没有shadow事件，因此不计该完整原包阴影受益；实际日志存在编译helper签名拒绝导致的effect局部退化，不能以开机掩盖它。后续已查明其边界：此前隔离App用ad-hoc签名，而产品要求helpers属于固定Team；最终staging改用本机该Team的有效签名并逐helper检查同一requirement，不修改产品安全门，也不把验证环境缺陷归为此次阴影实现回归。原包开机、星空和时钟显示不能证明完整作者模型或阴影。完整原场景、官方 golden、性能、多屏及所有阴影光型均不随本片局部门通过而宣称完成。

最终原包 v7 使用同一隔离输入，exit0、frame0/1完成、drain且5项App/helper身份不变，仍准备22个模型；两个编译helper不再签名拒绝。没有 shadow 事件，故仍不计完整原包阴影收益。证据 `original-v7/identity.json` 与 `summary.json`，图像只证明实际开场输出，不能抹去原导入/组合边界。

最终相邻资源门：offscreen pool 29方法通过（11.889s），原static-model pipeline 6方法通过（15.898s）。persistent-color首次以系统Python3.9运行，4方法通过、1方法因测试使用zip(strict=True)报解释器TypeError；改用仓库要求的Python3.12原样重验5方法通过（64.864s），不修改测试或产品来迎合解释器。文档角色13方法通过。

## 终审与移交

独立产品终审 **ACCEPT v7**：`final-review/product-verdict-v7.md` SHA `db619402f21ae24bbdb0774930da6a7c8cf688557d53b1062ac270fa9872139c`，绑定17产品manifest、30文件提交候选、最终测试协议与实际App/GPU结果。F1、投影basis回归、自影与两例近切面finding全部关闭；产品与测试冻结后仅修本文、设计状态、后继路线及窄登记退役。正式源码/测试在同一职责提交中，稳定owner已移交架构；完整D3、其它光型与官方parity不因此关闭。

下一批按[RF12卡](../../scene/design/reference-evidence-implementation-cards.md#rf12-late-snapshot-capacity)给现color-blend/refraction背景快照准备真实必需容量，每个consumer仍在作者顺序的原copy点取得当时背景。当前main/group正常路径同尺寸，先保原实例单槽；不为未证多extent新造registry。实际refraction组合、group/forward App、长期性能、多屏及完整原包阴影仍未验证。所有失败及复验保存在本机精确证据目录供复核；未合入并行任务的历史文档或布局排序，未推送。
