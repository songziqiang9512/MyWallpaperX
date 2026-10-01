# Scene resident resource admission

2026-10-01，设计 approved；实际验证见当前运行证据。属于跨 resources / targets / particles / Session 的预算权威迁移，generic-only。

## 目标与所有权

当前各屏 target pool、粒子 buffer 和 decode cache 分别限额，不能限制多屏或 active + candidate + retiring 的叠加峰值。增加唯一进程级 SceneResourceBudget，作为这些资源的总准入权威；已有本地预算保留为各 owner 的子上限，不是独立总额度。它只记字节和租约，不注册资源 identity、provider 或 graph，不替代它们的生命周期。所有 Scene 原生 Metal 分配及视频导入通过同一入口预留；decode cache 保留操作同时进入该总账。

总上限为 Metal recommended working set 的四分之一，封顶 3 GiB；设备未给建议时用 512 MiB。decoded cache 在此总账内另限总额四分之一，避免可重建缓存吃完 GPU 额度。性能配置降低本地 cache 上限不撤销已被使用的资源，只拒绝新增。此预算是应用可控 resident admission，**不等于进程 RSS 或 OS OOM 保证**：VM/解析对象、解码器瞬态和 AVFoundation 私有缓冲、driver/pipeline 内存、CAMetalLayer drawable 是未计入项；后者保持原有平台/单对象限制，不能在报告称全进程硬上限。

## 分配与释放

GPU 入口先用 Metal heap size-and-alignment 查询所需字节，在加锁总账中预留，再调用原生分配；失败立即释放。租约附在实际 MTLResource 上，资源被 CPU owner 或 command buffer 保留期间持续记账，最终对象析构才返还。不是按 session.stop 或 cache.remove 提前返还；不同屏或 session 共享同一个对象只记一次。视频导入在发布前按 pixel buffer data size 预留，租约附到 backing buffer；各 Metal view 保留 backing，使同一 buffer 的多个 view 只计一次，不在每次 CV 包装时重复记账。解码缓存沿用既有 lease 的 reserve/release，父账先原子准入；没有 payload 哈希或每帧扫描。

预算拒绝沿现有 nil / allocation failure 通道拒绝最小 unsafe unit；不停止健康屏、不挪用仍在飞行的资源、不自动驱逐其他会话。候选不能首帧则按 Session 合同失败并保留 active。旧会话与新会话在 GPU drain 期间一起占额度。低配额或连续请求下可以明确拒绝新候选，禁止靠清空旧画面省预算。

## 机器门与反例

增加 allocation-entry 审计，检查 Scene 产品范围的原生 makeTexture/makeBuffer/CV 导入只存在于总准入入口；这属于所有权架构门，产品测试仍断言行为。新入口是全体原生分配的替换，非第二套产品资源 registry。新 helper 家族登记到 source layout；没有按样本或 provider 类型分派策略。

行为门：并发预留不超额；失败分配返还；decode 与 GPU 竞争同一额度；共享纹理不重复收费；停止/删除 cache 后仍被 GPU 引用的资源不提前释放；GPU terminal 后最终引用释放归零；小预算下拒绝候选而旧输出保留。Debug build 与代表原生播放分开验证。所有产品分配接入、反例通过、文档同步后退役迁移登记；新增分配入口必须经过同一架构门。
