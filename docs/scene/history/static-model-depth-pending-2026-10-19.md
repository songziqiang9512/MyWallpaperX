<!-- document-role: historical-evidence -->
# 模型深度资源在飞压力与未提交帧

> **历史证据 — 非现役入口**。截止2026-10-19。现行职责归[运行架构](../architecture/runtime-architecture.md)及[F6资源合同](../roadmap/batch2/2d-lighting-material-design.md#mandatory-model-depth-pending)，343的闪烁和光影余项归[队列](../roadmap/scene-open-breakpoint-queue.md)。

旧同一深度池只有三槽，acquire失败统一为nil；其他在飞帧占槽时，模型draw循环直接跳过当前part。冻结生产Frame.depth→pool→draw→MainPass→Metal的自有门实际得到：首帧保持pending时两租约/两draw/绿，后继仅一租约/一draw/红，真实completion后恢复两租约/两draw/绿，9项检查通过。不是依据样本或截图新增隔离算法。

修正只在原资源边界区分其他CB忙、本CB超额、非法extent和真实分配失败。lease保实际CB及匹配归还；原StaticModelFrame的一次plan及busy状态供原位、shadow/reflection准备和late named消费，busy由既有FrameOutcome.deferred取消整份未提交候选。自身超额与永久失败保局部半径，粒子原局部策略保持；没有扩槽、另建plan、改近重合判据、cull、HDR或颜色公式。

新正式pending门一次编译2/2 PASS（19.805s），原位与mandatory准备两臂各17项事实：busy不提交且保持sentinel，completion后恢复完整绿色；四份单帧需求不defer，取消/尺寸、错CB arm、非法extent和实际预算失败保留。最近旧frame-owner门首轮1PASS/2FAIL，定位为非DEBUG计数oracle及旧模型载体方向；保首失败与基线代码/像素，改为真实magenta/clear粒子ROI并补纯绿/蓝模型ROI，原身份/数量/预算失败不重试断言不变，重跑3/3 PASS（16.816s）。新门shell字节未变，未重复。两次独立静态审查及fixture终核GO，六产品全程不漂移；未执行完整Host强制busy或暂停重试的集成门，不以prepared shell冒充它们。

隔离Debug以固定6adabc113加已验相机五源及本片六源构建，4312输入/外部闭包无漂移，27.727s、严格签名0；App `f4638a41…7f53`、dylib `afb69ff8…233f`。343先908×590/30FPS短播，31张稀疏原图ROI缓变；原生screen.frame背板3024×1964/60FPS不resize又跑旧版、候选与同候选一次重复。原生窗口仍是debug floating level，不冒充正式desktop window policy。各App0、输入稳定、stop1→0/GPU排空；截图多次superseded使原runner FAIL保留。用户先确认小窗不闪/全屏闪且光影不同，后确认最新候选全屏不闪；这是有效目视反馈，但稀疏采样和两候选短窗不足以排除偶发时序，不关闭343或证明完整官方parity。

真正未参与本片修法的3617056047原包在同一签名App上显示罐体、圆环及文字，App0/FAIL[]/输入稳定/正常stop和GPU排空；只证明该短窗模型链没有明显回退，不升级其所有交互或官方姿态。343颜色/光影与本片独立，Cloud的Chroma字段消费缺口仍待隔离归因，不用资源修正替代材质修复。

普通14天正式证据为`.artifacts/scene-evidence/runs/static-model-depth-before-20261019/`、`static-model-depth-after-20261019/`及`static-model-depth-repeat-20261019/`。每个原生after PNG约21MB，仅各留一份原字节全尺寸图及日志/原FAIL，分别保持单包32MiB内；重复ready/hover和稀疏series不全留。自有GPU门、首FAIL、冻结/构建/清理收据在`.artifacts/tmp/static-model-depth-pending-20261019/`。短窗测量均非steady-state，未作CPU/GPU、内存、启动或能耗收益声明。
