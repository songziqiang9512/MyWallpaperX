# D12：停止无成本依据的复用，闭合 loopback 凭据与 Web 配对形状

<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**
>
> 截止：2026-10-24。顺序与停止条件归[启动专项](../../development/wallpaper-startup-optimization-plan.md)，Web当前所有权归[现役状态](../../web/current-state.md)。本批不重标历史性能卡。

## 实际改动与修前修后

P5a入口审查停止大重构：原W0在selection前已有空daemon hello，spawn/AppKit/IPC已被预备覆盖；fresh Host/view仍需初始化，尚未证明退休daemon能省关键路径。原stop只取消，目录/网络/JS/FD终态不足；现version2又把请求身份绑定进程，安全复用须迁移频谱等消费者。没有净收益依据就不添加drain API、协议或池。P5b公开清场仍不足，转换cache/稳定origin及跨provider OwnedFile缓存也未取得热点资格；P4仅保双真实encoder同key的有界机制资格入口，不认提速。

P6产品仅修改两个原owner。LoopbackServer用原不可变token派生唯一cookie名，名字和值均匹配本server；保token前缀或本cookie的OR准入，原root/grants、SameSite、端口和stop重启不变。Surface持创建时旧server与WK store，在原server.stop和view.stopLoading之后精确删除本name/domain/path；不枚举、不清store、不查询后继surface。此为best-effort回收，迟到HTTP响应可能重植cookie，不能当作drain ACK或跨端口文档隔离。

新增真实WK长期门使用同一nonPersistent WKWebsiteDataStore、两个实际TCP端口、不同作者根和页面。冻结原server/同一harness先红：A在B加载后403，B在A重载后403；固定名只剩一个cookie，删除A还会删除B，18个fact中6个false；编译和native均exit0，原测试按成功marker明确失败。窄修后同harness18/18 true：两向无前缀读取200且各返自己的字节，停A/删A后B仍可读；本前缀无cookie、本cookie无前缀仍允许，无cookie/错误token/旧固定名/无cookie陌生前缀拒绝。

实际API资格先把删除参数从WK返回的A cookie改成产品a.accessCookie并通过18/18；独审发现尚缺A已消失断言后，仅补该fact，最终长期门19/19通过，直接核A精确cookie不存在且B保活。原同harness红绿均完整保留，不以更换夹具覆盖before。原Range门通过，保HEAD/304/416/分块/流水线/撤权/截断及同server stop→start。仅支持这些受控行为，不是完整Host teardown或任意迟到响应清场。

## 配对工具的真实 Web 形状

D11摘要误把所有W0当2行；实际Web runner是首个加六个暖请求，共7行，因此真实Web配对必被拒绝。D12先保原17方法通过与真实7行反例红，再只修summarize_paired：每iteration/arm/App的六个原暖值先取中位，作一个配对观测；Scene保持一暖值，C0/C1一值。输出保原暖点/数量及明确聚合方式，最终count仍是App组数。形状不符、缺失、重复、失败或非有限拒绝完整比较。

最终19/19纯Python通过。数值反例成组配对中位为+4.5ms，池化为-42.5ms、首ordinal为-45ms，防止把相关暖请求当独立App或替换统计量。原summary/runs、计时、运行、隔离与退出函数逐字节保持；首轮一个旧mock期望不符的失败保留后只纠正该夹具期望。未重跑或改写D10/D11历史分布，不授性能验收。

## 唯一 seek 探针与 C1 证据

原14源在任务副本加入同operation的issued/AV completion/main/guard有界标记，仅失败后读取；移除插桩投影还原原源码，保2秒await、12秒child及颜色/texture/generation断言。只执行一次seek6，native exit0/1.273秒，首纹理为蓝、generation1→2、提交前保持旧texture、实际playerTime约6.051；成功不读observer。本次未复现，按既定STOP不再采、不修产品时钟/缓存，D7 discard和D11 first-target失败继续开放。逐命令argv、二进制stdout及输入双SHA均已持久化。

C1仅离线复核既有v2十个C1原点，未新增计时。原总中位682.758→861.350ms；从原日志rounded elapsedMs得Session创建→hello406.0→582.6ms，selection前段约13.703→17.292ms，hello→commit260.360→259.567ms。增量定位到子进程启动/握手窗口，不能细分LS/TCC/调度/QoS，也不归给P1解析或证明修复。v3基线自身漂移和原回退证据均保留。

## 验证、材料和未覆盖

产品两份源码已冻结，签名Debug build成功（389.129秒），全Git输入构建期间SHA稳定，深严格签名通过。exe `01c4a7296936607efea48db3c72cb4e4ebda88baa037277c3285f89013d0256d`，专用Debug.Startup身份，未安装到Applications；后补仅长期测试断言，不改变产品输入。原工具一组隔离资格完成3个App/9次真实请求；全部native行确认highCompatibility/httpLoopback/scopedPersistent，输入/正式偏好不变，正常退出，测试App/HOME自动清理。最初收集检查误等缺省diagnostic日志而返回false；改读原typed native字段后离线核等，无重跑。最终静态门另见包内收据。没有正式启动提速或完整无回归结论。保一份连续DerivedData，其余本轮已停止产物在必要日志/源码/身份提取后精确清理；原失败和跨批唯一证据不删。后续实现未暂存、未提交、未推送，goal保持进行中。
