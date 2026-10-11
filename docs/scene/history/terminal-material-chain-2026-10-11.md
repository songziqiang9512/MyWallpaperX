<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前任务从 Scene 路线与断点队列进入。
# 多段终端材质与源尺寸：2026-10-11

稳定职责归[运行架构](../architecture/runtime-architecture.md#terminal-material-raster)，剩余扩域归[断点队列](../roadmap/scene-open-breakpoint-queue.md)与[后继设计](../roadmap/batch2/terminal-material-chain-design.md)。本记录不声明整样本正确。

## 根因与行为

3761619125 下方裙摆 consumer1954 的 author1180×403、scale2，当前工作纹理2048×700；hidden raw provider47真实1188×403。作者 texture_override 的 SCALE0 取slot0/slot1尺寸比例，并在CLAMP1时frac，错误放大的前者导致约1.72倍周期。14段SCALE1作者隔离副本消除了矩形重复，只是因果诊断，不是产品修复；原媒体没有改动。

官方2.8.0.42固定binary SHA `daac1ea7c991207fbd6098616757e3dae393850f6862845db55d04921b6bda07`：自有120×60 solid→identity→probe在三种scale、两个窗口中，xy/512、zw/512均RGB60,30,0，control64,128,191。另10×10、64周期条纹→identity的末段inactive/active，240px线分别119/7次阈值转换。该结果要求区分输入尺寸与末尾材质显示密度，不证明内部实现或任意图。

首轮one-line声明探针、两次自有named TEX探针，以及合法作者TEX的named探针均未通过内容控制，不用于尺寸推断；后者应读RGBA255,183,204却读255,0,0。原始失败、有效作者输入和固定身份均保留。named研究本批停止，不继续猜测尺寸合同。

## 当前实现与证据上限

复用原capability、GraphExecutor、PassEncoder、pool和submission/MainPass。普通正交无依赖simple color chain按源尺寸工作，选最后成功材质；仅真实suffix写冲突保留一份对应输入，不每stage复制，不改Resolution算法或资源identity。原高级混合proof与Candidate要求保留；native3D仍单stage。named依赖尚未扩域，所以376裙摆问题尚未关闭。

最终Debug build和真实App自有输入完成：原生尺寸六个非饱和格从随scale变化变为全部60,30,0；control与饱和控制保持。原生条纹inactive/active分别119/7次转换，对应官方有界结果；两者实际屏幕像素尺寸不同，不算逐像素parity。独立审查指出无Candidate fallback会误扩高级混合，已修正为两种既有输出角色各自的prepared eligibility。

最终生产GraphExecutor、PassEncoder及真实pool的3方法/8个Metal用例通过：inactive、局部失败及连续透传仍保留127次细条纹转换；active identity为7次；必要副本100像素逐字节相同。无覆盖冲突不复制；全inactive保留原输入；预算拒绝安全消费本帧graph输出。另34项pool/budget、5项终端回执、2项publication与49项文档测试通过。宽域graph门32项失败用同一修正ABI的harness回跑修改前全部11个产品文件，结果完全一致（无新增或消失），保留为既有验证缺口，未宣称该门通过。

最终App主程序SHA `c82412fe7664978d37aa53ee1db1eebd179c0654b6c8d2bebf380fd7b69f1b5d`；原3761619125运行71.93秒正常退出，14段texture_override首帧/后帧GPU完成，裙摆重复仍在。11个产品文件独立复审修正高级混合误扩后无P1/P2；证据绑定见`product-independent-review.json`与`terminal-gpu-v5/receipt.json`。这些内部Host短跑不代表真实桌面入口、长稳、性能或完整交互验收。

后继先复验N04的3708363772/3476868923 stage-reference公共断链，沿原绑定编译、依赖所有权与发布链定位；376外部named尺寸/deformer仍保留，待有效合同再扩。相比继续无效named探针或先扩尚未复验的SceneScript API，两个真实consumer拒绝更容易形成有界公共修复。不得直接删除dependency准入守卫。

## 产物

本机固定根：`.artifacts/tmp/effect-texture-extent-20261011/`。`official-bounded-contract.json`指向有效官方测量；`native-r2-after/extent-comparison.json`与`native-density-after/density-measurement.json`记录对照。已清理本轮11个停止使用的副本/HOME/重试目录约202.81MiB，另先前因果实验副本165.33MiB；最终日志、必要截图、失败探针及v5 GPU收据保留。唯一构建缓存复用`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`。
