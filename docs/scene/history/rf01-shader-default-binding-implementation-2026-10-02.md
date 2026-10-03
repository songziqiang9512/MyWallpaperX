<!-- document-role: historical-evidence -->
<!-- commandPolicy: historical-only -->

# RF01 shader-default RT 消费链实施证据（2026-10-02）

> **历史证据 — 非现役入口**。当前权威：[兼容路线](../roadmap/scene-compatibility-roadmap.md)、[能力台账](../capabilities/coverage-ledger.md)、[运行证据](../capabilities/runtime-evidence-current.md)。受保护能力/运行总表及 engine-refactor-program 本批未改，由各自 owner 引用本记录；本文不决定后续任务顺序。

## 冻结职责与修复

基线为主目录 `codex/engine-refactor-program`、HEAD `85415320` 和已验收的 [D2/D3 首片](d2-d3-bounded-output-implementation-2026-10-02.md)。RF01 对应 [D8 设计](../roadmap/batch2/rt-prefix-admission-design.md)，共14个产品文件；最终逐文件SHA在 `/private/tmp/rf01-product-freeze-v2.json`。没有新建分支、提交或推送。后继诊断导出代码不属于本冻结App。

- shader default 在 preparation 交唯一 RT vocabulary，保存作者原拼写及 typed identity，保留同层 a/b/unspecified；FullFrameBuffer 大小写规则不变。typed值贯通purpose、launch format/color/readiness、variant、finalizer及实际binding；移除普通帧对default名字的再次解释。
- 同层 composite default接既有effect graph输入，layer-source/captured-main由原route决定，FullFrameBuffer接既有sceneBackground。未知/跨层default真正需要消费时继续局部拒绝；不扩RT家族、跨层default、registry或compositor。
- 已选中的合法显式candidate不再被闲置unknown default阻塞；readiness不能凭default伪造作者纹理presence，实际publication/identity/purpose仍须通过。
- 独立审查找到两个遗漏并完成修前反例：①作者asset明确absent后，frame selection丢失合法default，现直接选择typed graph及source fact；ready asset、pending和unavailable各维持原行为。②captured-main首个source consumer已由exact explicit previous绑定输入，仍被闲置default拒绝；现仅对同slot、同effect.input、唯一且最高优先的明确previous证明撤销无关限制，不放宽其他source slot。
- 两个存sampler事实的持久层分别退役到Demand v2、Variant v9。下游编译层缓存source/ABI，已有request/graph-input/purpose身份区分；没有仅因新增名字盲目失效所有缓存。

## 修前反例与行为门

证据根 `/private/tmp/`：`rf01-red.log` 记录三种same-layer default被拒绝；`rf01-absent-red.log` 记录明确absent候选后的 `variantSelectionKeyInvariant`；`rf01-captured-idle-red.log` 记录首consumer的 `utility-source-program-unsupported`。修后分别见 `rf01-absent-green.log`、`rf01-captured-idle-green.log`，最终以如下冻结组为准：

| 验证 | 实际结果与证据 |
|---|---|
| 真实Swift finalizer | 33 tests PASS；`rf01-finalizer-review-final.log`。含拼写/三variant、FullFrameBuffer大小写、缺失/ready/pending/unavailable、dead sampler与presence、持久层冷暖恢复 |
| 真实Metal graph | 全组PASS；`rf01-absent-gpu.log`。三variant两帧、ordinary显式candidate压过闲置default、captured-main首consumer、明确absent→default的两帧半透明128/alpha128；检查terminal像素，能区分额外premultiply |
| 独立只读终审 | 首审两项阻塞均有红绿证据，最终14文件SHA全匹配，v2接受；没有把harness当App证据 |
| 静态门 | `rf01-review-code-health-final.log`、`rf01-review-defense-final.json`、`rf01-review-design-final.log`均通过；diff-check通过 |
| 签名Debug App | `/private/tmp/mwx-rf01-closure/build-v2.log` BUILD SUCCEEDED；源码/payload身份分别在同目录build-v2-source-identity.json和build-v2-payload-identity.json |

standalone harness沿原测试环境使用disable-generic；其门证明实际Swift/Metal行为，但正常generic路由由下述完整App另证。普通帧名字解析撤销经静态链确认，现役preparation计数门通过；没有新增每个token的常驻计数器。ABI、resize/stale等更广组合沿现役未修改合同测试，不宣称全部都是本次新建反例。

## 完整 App 正常路由与像素

自有包位于 `/private/tmp/rf01-app-fixture/`，红源与RGB.gbr shader均自行编写；三个default-only正例没有显式纹理绑定遮住默认路径。missing-asset-default确实引用不存在的asset，没有占位文件或注入loader状态；captured-idle-default使用红source与fullscreen utility，唯一effect首consumer显式previous、default未知。每个项目/包SHA冻结在matrix.json及report.json。

运行用Python3.12、12秒/预热5秒，证据 `/private/tmp/mwx-rf01-closure/app-v2/report.json`。App为2.10.0(280)，team `H9QWU9XN8R`，CDHash `6587955b4b92a28a33bbcb6bc87c0c3cdde2eb2b`；launcher SHA `cc345c25cb79bd091ef49bd280f359512aea83da08747cd74141efd9f722ab02`，实际Debug dylib SHA `de53b8914ebe896f95061a5aab680164bbbe7176ceaaea0a0173dd681c269709`。严格签名执行前后均有效；同目录frozen.app留作后继对照。

五个正例通用benchmark PASS；unknown/cross两个负例按通用门报告 `effect execution degraded layer source passthrough`，这是该负例必须出现的局部拒绝，保留NON-PASS，未修改门槛。七项独立颜色/路由oracle均满足：中心50% ROI正例恰为(0,0,255)，负例恰为(255,0,0)，每项ready/after整图像素一致。像素统计见 `app-v2-pixel-oracles.json`。

| 输入 | 像素/行为oracle | 通用benchmark | submitted/completed/failed/presented |
|---|---|---|---|
| positive-a | 蓝；实际执行颜色变换 | PASS | 353/353/0/352 |
| positive-b | 蓝；实际执行颜色变换 | PASS | 353/353/0/352 |
| positive-unspecified | 蓝；实际执行颜色变换 | PASS | 353/353/0/352 |
| unknown | 红；预期局部拒绝 | NON-PASS：预期降级 | 353/353/0/351 |
| cross | 红；预期局部拒绝 | NON-PASS：预期降级 | 353/353/0/352 |
| missing-asset-default | 蓝；实际执行颜色变换 | PASS | 344/344/0/342 |
| captured-idle-default | 蓝；实际执行颜色变换 | PASS | 353/353/0/352 |

五个正例日志均有generic-only接受及实际genericCompilerArtifact消费；graph记录包含first-frame/next-frame、GPU completed、publication与compositorConsumed。两个新增审查反例在真实App也输出蓝色，而非只被parser识别。负例保留源画面及健康呈现，不声称支持unknown或跨层default。

首轮使用系统Python3.9，七项扩展前的五场景运行与PNG完成，但benchmark在清理可重建runtime时因不支持rmtree(onexc)退出，未生成汇总。原日志保留于 `app/`、工具错误在 `app.log`；这不是产品失败，最终结论仅采用Python3.12的v2完整报告。

## 未验证边界与后继

本片不是官方像素parity、HDR/EDR/PBR扩大、性能完成或完整RT名字兼容；短自有输入只闭合该binding链。原真实样本回归属于前一D2/D3冻结身份，没有冒称在本RF01版本重跑。诊断截图仍是现役同步导出，另按批准的诊断生命周期设计修复；不得把这份App的时间统计当后继性能结果。工作卡已完成部分只保留本证据移交指针，剩余未知family仍有前置门。
