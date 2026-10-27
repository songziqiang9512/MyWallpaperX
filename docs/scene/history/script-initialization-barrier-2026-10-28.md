<!-- document-role: historical-evidence -->
# SceneScript 跨类型初始化：2026-10-28

> **历史证据 — 非现役入口**：当前能力归[脚本合同](../capabilities/scenescript-api-coverage.md)，余项归[队列](../roadmap/scene-open-breakpoint-queue.md)；本记录只保存本批因果与验收边界。

2887099508 的 scalar init-only owners 建立共享种子，vector 更新却先读尚不存在的种子，误走作者删除分支并使场景全灰。不能按样本、变量名或返回值增加例外。原 MediaFrameCoordinator 仅对准备期未初始化 owner 按作者序先执行 init-only，再进入 cursor/各类型更新；原 C init 状态与 pendingInitializationValue、ownerEffects、接纳/撤回及生命周期继续唯一。成功提交后退出待处理索引，不新增普通帧全 owner 扫描或初始化 scheduler。原同步初始化的 text clone 不重跑，其他动态 owner 的扩展不随此片认领。

最近两个真实 C/Swift 行为模块17项通过：跨 family 的共享初始化、init 返回值进入首次 update、只发布一次、副作用保序、失败整 owner 撤回/次帧 retry、timer 与 cursor 邻例。初轮测试把空 script properties 错传为非空 JSON，提前触发了缺 export 的合法异常；仅修夹具后重验，不改产品准入。Root 检查事务与退休链，独立代理复核 pending 提交/拒绝和原世界路径；未发现本init片开放 P1/P2。

真实原包使用相同 project/package、零频谱夹具、固定 pointer、22秒/after18 的隔离 Debug Host：修前最终原图全灰，修后人物、天空、室内、粒子与时钟实际合成可见，正常 exit0，surface 1→0、GPU drained、79 owners quiescent。旧 App 为7933c3921；候选按4398产品输入冻结、构建前后无漂移，内外层签名校验通过。候选中另有未提交 Puppet 冲量切片，本文只认 init 因果与画面，不认其物理能力；实际载入身份随必要证据保存。未建立启动或运行性能收益，不能用旧错误画面耗时作性能基线。

剩余395.init的跨层 getAnimationLayer 与后续普通 Timeline.setFrame、265首次 update 的 get/setCameraTransforms 是独立缺口。它们未因出画面关闭；未找到本机该样本的“截屏”前缀官方截图，不认完整构图、动作或官方同phase parity。HDR/多屏、普通 daemon/原生属性面板及任意动态 owner 未在本片验收。

独立3617056047原包在同候选运行12秒，3D罐体、虚线圆及上下文字实际可见，exit0、12 owners quiescent、surface1→0/GPU drained；只认相邻渲染与退出。一次私有输入漏Scene目录层级使runner在启动App前失败，修正路径后才执行，不归因产品。

必要修前/修后原图、日志、身份、行为门、独审及独立样本归主工作区`.artifacts/scene-evidence/runs/script-init-order-20261028-final/`，本机5GiB/单包32MiB/普通14天。已提取结果后的运行副本与HOME收尾清理，连续迭代保`/private/tmp/mwx-scene-followup-20261028-q5apo4lx/build-cache/`一份构建缓存；本批不推送。
