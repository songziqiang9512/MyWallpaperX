<!-- document-role: historical-evidence -->
# Graph颜色用途协调与历史验证债修复（2026-10-12）

> **历史证据 — 非现役入口**。本页保存本批有界修复及旧fixture更正；现役语义归[运行合同](../architecture/runtime-architecture.md)，剩余样本问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

## 通用语义与实施范围

基线`28ed0c050e85caca9d35394f789c7dadbf6c7ccd`。旧汇总门32项false此前已证明不是Blur准入批引入，本批继续追根修正，没有以baseline免责。首先复用原`SceneResolvedMaterialTextureSlotPurpose`：source-proven straight-color consumer的数学用途，不应与合法graph颜色publication的名义PMA传输用途互斥。选中graph保原publication及实际表示，交给现有Program转换；不新增shader算法、profile、publisher、compositor或缓存版本。只扩direct purpose为PMA且source purpose已证straightAlbedo的graph候选；mask、data、资源身份/代际与最终颜色ABI仍由现有owner检查。

graph与lower资产逐候选校验：合法graph被选中时，不要求未选中的lower噪声/数据资源变成颜色；graph缺席后不兼容lower仍须拒绝。不是全slot任意用途互换，也不把所有graph资源标为颜色。实施前设计落在已有[颜色连续性设计](../roadmap/batch2/hdr-tonemap-edr-design.md)，未新增并行执行链。

## 历史fixture更正依据

原271布尔断言完全不改时，32false降为2false；30项恢复涵盖准备、动态uniform、反馈与局部回退，但不能推导30个真实样本修复。剩余两项由独立自有输入矩阵确认prepare/encode/GPU/visible均成功：

- 旧alpha检查只看2×2纹理首末透明像素，并要求所有中间附件为PMA。实际末stage是typed straightAlpha，四像素为`[255,0,0,0/64/128/0]`；真实生产image片元按表示合成后为`[0,0,0,0]`、`[64,0,0,64]`、`[128,0,0,128]`、`[0,0,0,0]`，最终PMA正确。
- 旧RT default测试把资产缺席与alpha128绑定在同一条件，又用忽略表示的fixtureFragment模拟末合成。分开availability×alpha后，缺席与无候选均在两帧正确发布；alpha128的raw straight颜色255经生产末合成得128，ready资产对照正常选择资源。

修正方向是保留typed中间颜色和隐藏RGB，并在真实生产片元检查全部像素及两帧资源回退；不能为迁就旧fixture回退产品为全PMA中间链。独立probe源码、观察与编译输入身份保于本机`alpha-probe/`，不改产品。

最终原executor模块六门全部通过，437.282秒；271结果键与冻结基线相同，32false全部关闭。Alpha检查全部四texel及真实末合成；default保留三个alias×无候选/缺席/ready×opaque/partial×两帧，共54状态断言。旧大fixture净减35行，未增加常驻收据入口；本轮输出由ignored wrapper在正常六门运行中捕捉。新slot GPU门涵盖变量/资源/等价表达式、8个availability组合、11个候选与实际data反例；相邻6模块通过。独审加强的exact失败断言仅重验同一冻结GPU输出，HARNESS未变，不冒称第二次GPU运行。

## 真实样本与证据上限

以冻结基线App和本批隔离Debug App对照2960821850，并用最终App复验296及未参与修法的2134765860；五次均ready、exit0、surfacesAfter=0、GPU排空。最终Debug构建、原team helper签名/strict检查及App身份已核对；末次源码仅澄清comment，可执行Swift语句未变。296 frame0/1仍23材质、8拒绝、25图级GPU完成、8最终消费；实际画面未见本批改善。215/effect0四节点仍previous-blurred-composite owner未准入，277/effect4是slot2 opacityMask用途拒绝，均不是本批slot0 graph-color冲突；继续留队列。213 frame0/1为37材质、37图级GPU完成、14最终消费，15跳过均作者visibility-disabled，无visual failure；房间布局、灯光与时钟保持。动态输入extent不全相同，不将相同执行计数写成所有帧字段或像素等价。

只查既有新增37份运行及2次启动retry的own日志与triage，精确slot0 graph-content签名无命中，不据此制造真实样本收益。旧日志未必导出全部细节，不能推全库无受益。本批通用语义正确性由自有GPU/最终合成验证，真实原包只证明健康回归；没有官方同相位parity、全交互、长稳、多屏或性能结论。

## 文档与产物

本机证据根`.artifacts/tmp/graph-executor-baseline-repair-20261012/`绑定product源码、Debug App/helpers、只读原件副本、旧门红绿及中性运行收据。原历史记录保留当时红门事实，本页作为后继关闭记录，不把当时失败追改为通过。文档门还发现上批Blur历史页漏索引/入口错误，以及共享就绪、取余、data mip、视频asset的历史索引漏项或authority不同步；本批逐项补齐历史入口，保留原当前合同归属，未把已完成任务留成待办。

历史`.mimosa`仅218字节，为10-08空闲hook metadata，无processing/open handle；精确可逆迁至本批`residue/mimosa-20261008`，SHA保持，residue门恢复。只移动已确认归属对象，未删除未知材料。82个原件hash保持，五次运行及副本/HOME无打开句柄后清理，保留三张必要截图、无损压缩日志/中性收据及身份，约19MiB。八项适用治理门和49个文档门通过，独审收据保于本机证据根；不把已选最近门写成全部39模块执行。连续迭代保留原单份DerivedData；全局证据预算不足不扩预算、不删未知证据。
