<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF03 作者粒子播放四方法实施证据（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../../scene/scene-compatibility-roadmap.md)、[能力台账](../../scene/semantics/coverage-ledger.md)、[运行证据](../../scene/semantics/runtime-evidence-current.md)。本批未改三个受保护的能力/运行/重构总表。

## 范围与责任

基线为主目录 `codex/engine-refactor-program`、HEAD `85415320` 与先前冻结的 D2/D3、RF01、RF05 未提交实现。依据 [D4](../../scene/design/script-component-api-design.md) 与 [D11](../../scene/design/particle-playback-state-design.md)，开放已准备 root、无 authored child、单个 supported 确定性有限或固定周期 schedule 的 `play/pause/stop/isPlaying`。作者从 thisLayer/现有 layer lookup 调用；particle.instanceoverride.alpha 的 thisObject 仍是属性/组件 scope。emitParticles、reset、多 emitter、children、随机周期继续不支持，不声明完整 SceneScript/粒子兼容。

C handle 镜像和 callback journal 产生带既有 callback epoch/ordinal 的命令；DynamicLayerRuntime 的同一 owner fixed point 保存作者 intent/revision，拒绝 owner 后重算有序计划。Session 对完整同代 surface 实例派生 OR 查询，每屏在模拟前消费同一计划一次。GPU 提交失败不回退 VM/模拟/命令。rebuild 的 committed paused/stopped 在 constructor warm-up 前注入，不重放旧 transition；playing rebuild 不承诺迁移既有 RNG/粒子状态。

pause 仅停自动排放，已有粒子继续老化与死亡。stop 清 live、瞬态出生/事件、年龄/振荡/Trail/step 缓存和 Runtime rope/batch；同时重置局部发射游标，所以 stop→pause→play 不恢复旧游标。play 对未结束 schedule 续播、对停止/自然结束 schedule rearm，保留已有 live ID/年龄、全局模拟时间和随机序列；初次 launch 保留现有预热次序。以上 restart/init 和多surface OR 是项目边界，不宣称官方相位或多屏 parity。

## 反例、修复与独立终审

本机证据统一位于 `/private/tmp/mwx-rf03/`。

- 模拟修前：simulator-before.log 十个行为失败；ordered-stop-before.log 证明 stop→pause→play 恢复了旧游标。修后 simulator-final.log 通过，清理断言使用真实非空缓存/事件前态；runtime-playback-frozen.log 的真实 Metal-backed Runtime 门通过（19.789秒），包括 rope ghost、revision、缺实例、rebuild。
- 独审发现 Session 动态隐藏/alpha=0 被当作缺 runtime，误拒已有 prepared 实例。改为实际实例完整性；hidden prepared query/stop 的真实跨链断言通过。
- 独审发现同 cadence 多 timer、video-ended handlers 与后续 update 共 epoch，查询串入前 callback staged 命令。真实 timer/ended 反例修前失败，修后按实际 callback 推进现有 epoch；所属 microtask 在该 callback 内 drain，导出 journal 和调用顺序保留。
- 独审发现相同 owner 的 cursor/update 分包绕过256总预算。callback-budget-handles-before.log 使用255/256个不同 authored image 的真实 QuickJS handle 写入：256条总命令合法、257条旧版也接受；修后按 owner 合计全部 bundle。早先未经授权层的 fixture 和数字 lookup/index 误用仅作测试排障，不作为漏洞证据。
- typed ended dispatcher 初修漏掉 uncaught 第65条命令的预算错误分类。ended-overflow-before.log 的唯一失败证明该回归；v3 恢复同步异常及微任务失败的现役 overflow 分类，typed timeout/OOM 不丢失。
- 旧 App 的有限 duration=20、非零 startTime、真实 particle alpha 脚本 init.stop 反例见 integration-before-finite.log：实际进入 VM，报 TypeError，红色粒子仍显示。更早 visibility 绑定未入 VM、无 duration fixture 不在开放 profile 的材料均不作本片支持对照；未用通用 benchmark PASS 冒称 API 成功。

最终独立只读终审核对上述修复、新 guard 的真实产生者、完整源码/测试/App 身份及实际输出，接受 v3 限定批次，无剩余阻断 finding。审查者未运行测试或 GPU，运行由实施/root 完成。

## 冻结身份与验证

product-freeze-v3.json 为28个产品路径；test-freeze-v3.json 为14个测试/helper/fixture，另有 root-app-test-freeze-v3.json 的完整 App 门。build-source-v3.json 保存累计78个受改产品源 SHA，构建前后匹配；build-v3.log 为 BUILD SUCCEEDED。build-v3-payload-identity.json 的17个实际 binary/dylib/metallib SHA 与 frozen-v3.app 一致。App 2.10.0(280)，team H9QWU9XN8R，CDHash `005df94fa60f74140647cadfa1d8dd2f051a4b53`，deep/strict 签名校验通过。

- 最终 v3 ended-overflow-after.log：4 tests PASS，62.652秒；包含真实 QuickJS→Swift fixed point→双模拟器的39条行为结果及3项 author 门。覆盖首次 init、staged query、callback/owner顺序、完整surface OR、指针导致实例分歧、whole-owner拒绝、零工作、64/65与256/257、unsupported参数、rebuild和revision不重放。
- adjacent-v2.log：43 tests PASS，318.972秒；前半使用v2，后半v3（差异仅ended错误分类），不能称全套同身份。两处旧独立projection夹具补了新opaque payload类型/字段后真实编译通过。更早 property-vector 25项也通过。
- code-health-v3.log：1044 Swift文件/0错误，237条既有warning；defense-v3.log、design-gate-v3.log 与 owned diff-check通过。结构预算未放宽。
- app-integration-v3.log：同一签名冻结App的6 tests PASS，93.661秒。实际 init.pause 的ready/after live均4，init.stop两图清除红色，stop→play重新出现红色；全部drawable缺失、一屏缺drawable、post-prepare拒绝三门分别验证每surface revision只消费一次、peer安全输出和恢复completion。证据是12张terminal PNG、日志和 app-oracles-v3.json；pause/play红色像素55696、stop为0，稳定green peer均10471。

故障三门执行 stop→play→pause，最终零粒子，签收的是命令唯一消费、安全peer输出、实际surface恢复completion；不将其扩大为带birth/RNG/children的GPU重播验收。多surface为受控合成屏，非物理多屏验收。

## 未验证边界与交接

旧 simulator 回归68/69通过，pointer-control-point-force 的一个失败用实际 HEAD 旧实现复现同结果（simulator-old-pointer.log）；未改断言凑绿。audio5与boids2通过。真实异步GPU error、物理多屏、长稳性能/资源、完整官方行为对照未执行；受控drawable/提交拒绝和CPU seam不替代它们。未暂存、提交或推送。源码/冻结App及唯一失败日志保留，用于后继隔离比较；RF07 是独立下一片，不改变本记录的冻结验收身份。
