# 作者图层删除与脚本退休记录（2026-10-07）

> **历史证据 — 非现役入口**

当前合同归[运行架构](../architecture/runtime-architecture.md)和[SceneScript API](../capabilities/scenescript-api-coverage.md)，限定表面归[D4](../roadmap/batch2/script-component-api-design.md)，余项归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。此页只保存本批冻结证据，不决定后续选题。

## 首断点与实现

真实 `3791967416` 的 intro 控制器在约3.4秒删除另一个作者层时，旧C自层限制抛错并停用该owner，淡出事务撤回，导致暗幕及Logo残留。隔离关闭spotlight mask或全部后处理仍暗；纯clear色(.5,.18,.75)实际输出RGB(128,46,191)，不支持全局提亮或修改HDR作为修复。用户提供的官方“截屏”只读用于定位视觉差异；截图鼠标、动画时刻与viewport并未完全对齐。

跨层leaf删除复用原C journal→typed plan→共同模拟commit；Boolean只在自毁时改false。接受删除后先完成全部peer journal，再在last-live snapshot退休scalar/string/vector/cursor owner，停止timer/事件/update并清ended roots，borrowed cursor不重复teardown。唯一DynamicLayerRuntime记录动态对象首次创建owner，候选提交同步去掉其副本、值、定义；显式dynamic destroy仍即时去槽。保留GPU资源原residency/completion所有权，没有新增renderer、clock或删除队列。

独立审查修正：同cadence排序先统一还原C的最终原始位置，再投影作者tombstone与creator copies；C接受下一snapshot的tombstone时压缩存活顺序并可discard恢复；creator teardown基于不可变旧顺序压缩，禁止原地rank。审查提出的“拒绝创建peer导致健康sort偏移”经真实C journal discard/replay裁决撤回：重放作者sort参数后的C/Swift顺序一致，不据静态猜测新增算法。

被删named provider不能从启动目录回生。preflight execution closure只接受当前存活ID；single缺源复用typed unavailable，缺成员aggregate及依赖者整体退出对应graph claim，其他visible/model demand继续准备。forward preparation跳过已删除源；identity/epoch、完整ready vector及cycle拒绝保留，不用部分aggregate或旧publication伪装成功。

## 冻结验证

基线 `db68b619`，本批最终19个产品文件SHA见证据根 `product-identity.json`，构建和运行前后均相同；最终签名App CDHash `1a05f2340372c02dec4d26bf2ed363b3ba03e60b`，Debug build及嵌套签名验证通过。

- 原样本25秒正常退出、无脚本exception、GPU失败帧0；6个Puppet层、10个clip，41个graph执行成功，validation failure为0。`scene-series-0001-window.png`直接显示暗幕及Logo退出，人物恢复明亮。benchmark总体仍FAIL，唯一原因是本次固定鼠标的hover变化不足，不把它改成通过或宣称交互验收。
- C/Swift删除、creator归属、原子撤回及排序focused门通过；最终C/VM5项、选择性退休4项覆盖snapshot/discard/内存失败、索引、timer/cursor/update、video roots及健康peer。Runtime36项、owner回归42项属各自冻结门，部分模块交叠，不相加作为成果。精确命令与SHA在第二证据根日志。
- 生产依赖计划29项通过；coordinator14项及GPU passthrough2项通过。实际App前四个named-provider反例通过；第五例初次因截图Y转换错误失败，修正ROI后重跑通过。嵌套aggregate删除后22/44局部退出，12/55仍执行，终端白、健康点绿255、独立消费点绿128。
- 模型named-provider删除以及既有模型graph/albedo/隐藏恢复/坏材质App门共5项通过。首轮旧夹具缺`lightconfig`导致receiver仅ambient，与修复前App一致；本测试明确开启directional、ambient设0、intensity2，按显示域合同180×2×0.30×cos45°预注册receiver76，而非从失败像素改门槛。删除前模型取graph绿50、删除后回到receiver，独立蓝255与动画见证持续。
- 最终App测试日志 `provider-app-final-tests.log.gz` 为6项PASS（第五个named-provider重跑+模型5项）；与前四个named-provider合计覆盖上述10项App测试。16项文档角色/结构检查通过；registry audit无错误。构建、门数与非黑都不证明完整官方兼容。

本次Debug诊断运行约9.07 completed FPS，前批同样本约8.93；两次都非合格性能基线，不能宣称性能改善。非阻断成本后继：累计tombstone仍会扫Program绑定；缺源aggregate路径的两次demand查询会交替刷新单槽memo。先随当前样本正确性收口，再按同输入基线决定如何简化，不能为此新增第二个拓扑或生命周期owner。

## 限制与材料

范围是已准备作者leaf，父子级联、完整IScene、destroy回调新增跨对象绘制副作用、官方精确callback先后及多surface联验仍未完成。销毁清理沿既有合同丢弃新绘制命令，不嵌套开事务。本批不等于样本全部效果、眼部组装、HDR/SDR、重型样本、长稳或性能验收。

证据根 `/private/tmp/mwx-spotlight-output-20261007` 与 `/private/tmp/mwx-authored-retirement-20261007`；连续构建缓存复用 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d`。进程退出后已清理临时App、输入副本、HOME、shader cache及多余截图，精确清单见`retention.json`。最终日志压缩为`.log.gz`，保留报告、身份、原样本最终1张及受控组关键前后图，主证据根约23.8MiB，第二根不足0.1MiB。中央1GiB预算已满，prune无可清登记包，promotion拒绝；未删除未知材料，本批有界结果暂存本地。
