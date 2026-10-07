<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。当前合同见[运行架构](../architecture/runtime-architecture.md)，后续工作只从[断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 自定义图层源材质入口（2026-10-08）

起点 `015ff8d6`。243样本统计刷新后确认：model→material信息虽已保留，普通材质准备只枚举effects，833227004的双纹理flow源因此只显示静态底图。本片补共享入口，不增加flow、tint或样本专用算法，不复制参考项目实现。

## 实施与修正

Resolver/TemplateCompiler共用槽覆盖、uniform投影和ShaderSchema；source身份使用真实layer/model/material/pass，不能伪造EffectKey。source颜色叶与UV/weight数据闭包复用原分析器；data样本不能因RGBA载体而预乘，颜色输入也不能误读为数据。多义用途、branch/mutation/未知helper及颜色/alpha泄漏继续拒绝。DemandAnalysis v3、VariantAnalysis v12使旧purpose/transfer记录安全失效。

`ScenePreparedDeviceResources.makeMaterialRuntime`统一首surface worker与后续surface：同一executor完成variant/pipeline准备，再发布runtime。Rendering只持typed frame binder、资产域及格式；binder捕获原已编译VariantCache，普通帧不编译或建图。源输出复用offscreen pool、mandatory-capacity优先级、MainPass submission pin和原registry/compositor，隐藏且无消费者的源不分配。

实际App暴露并修正了域错误：普通底图已裁到1920×1080，而源Program的两张TEX物理域为2048²。源目标必须从所选slot0资产identity/purpose取得physical/mapped/UV，且全部variant一致；发布后effect capture更新同一UV。只把普通底图尺寸复制到源目标会出现大片灰色留白。rgba16Float也纳入原图像candidate消费合同。

## 有界验证

本机根 `/private/tmp/mwx-material-source-20261008`，完整命令、输入SHA及产品身份保存在各report/fixture manifest。正常签名Debug App，team `H9QWU9XN8R`，非发布或公证验收。

| 输入与身份 | 实际结果 | 证据上限 |
|---|---|---|
| 原833，`runtime-flow-verified`；executable SHA `91ab986037d16ac67bd687cd90f20dc1ae8e0f0cf4794a9aa9c4eb6426f2ca34`，CDHash `e7ec0c6c637899718a0d1b43fef67bdca9ab0c3f` | source prepared/encoded、2048²目标、留白消失；窗口中央60%区域相隔约10秒，93.62%像素变化超过2/255，RGB平均绝对差0.02361 | 源材质真实动态与构图恢复；官方用户截图仅非同步构图参考，不是同时间pixel parity |
| 原833仅新增RGB乘(0.5,0.75,1)后effect，`runtime-after-effect`；executable SHA `108453c0e0a07a708f96b40bc6de25608f855ff88f00dc7278cc3af95fde1f41` | source→effect→GPU completion→publication→compositor→next-frame；相对原源ROI均值比0.50565/0.75119/0.99882，仍有80.62%像素动态变化 | 此App与最终App只差私有可见性/注释整理；两个运行clock不同，仅验证染色方向与动态，不作逐像素等价 |
| 原833仅general.hdr=true，`runtime-hdr-verified`；同最终App | 16F source进入既有compositor，映射完整、多帧动态，benchmark PASS | 不是物理EDR亮度、外屏HDR或全部HDR样本正确 |
| 健康1439846152原pkg，`runtime-builtin-verified`；同最终App | 基础图与粒子继续显示，未产生custom source Program，benchmark PASS | 此输入非回退；不是全部builtin/粒子parity |

`visual-checks.json`记录完整ROI/图名/identity。旧`runtime-flow-1`因ad-hoc包编译工具签名不合合同降级；`runtime-flow-2`虽benchmark PASS但实图域错，均不算验收。首次HDR周期截图间隔2秒短于16F readback处理，出现snapshot失败；相同产品增加采样间隔为5秒后通过，未提高产品超时或修改运行算法。一次最终跑启动早于签名完成被前置检查拒绝，完成签名后重新验证。

独立generic MSL/GPU probe以非线性自有64²输入证明：正确边界的straight/premul结果误差约2.98e-8；数据纹理alpha0/1不改变结果；缺失颜色边界产生0.149468误差；time0/4输出差0.135812。该probe不冒充App PassEncoder证据。

最近合同门：pool 30、template 6、source-purpose 7及最近颜色/默认purpose反例、source transaction/texture candidate/finalizer 39、runtime bridge 14、material state/transform/source publication/source-set 5模块及persistent cache行为门通过。旧bridge harness只允许空source-entry，覆盖协调器回滚/实际Metal生命周期，不用stub宣称source渲染通过。Debug build、结构/依赖/代码与文档门按本次冻结清单检查；未执行全243运行矩阵或release suite。

独立只读审查发现并修正隐藏源预算、HDR candidate、display target预算、VariantAnalysis失效；随后复核域/UV、后effect消费、两个surface构造入口与binder持有关系，无剩余明确阻断。未验named组合、多surface实际运行及所有失败类型，不从静态审查外推运行正确。

## 剩余公共能力与受益边界

原有范围抽取的另外10样本11个custom tint层全部未准入，详见`cross-input/admission-matrix.json`（SHA `686f4a0aa2a8d2e33f1ba75e914f7c20957b430f7261c1af36ee001a3f36c023`）：3层translucent/alphawriting=default、7层动态material常量、1层perspective。不能把统计候选计为实际受益；此批实证受益是833真实源，通用性由共享入口、自有shader/GPU反例及新effect组合证明。

下一片优先裁决3层共同透明state与原compositor的职责，随后将7层动态常量接入已有materialConstant typed通道；不为每个样本新增算法。多pass、instance、user texture、named/history、Puppet/3D、更多UV/state依旧明确开放。全样本缺口全集及旧用户反馈由现役队列拥有，本文件不另建任务表。

## 产物

只保留最终报告、日志、identity、受控输入生成脚本/manifest、必要截图与GPU小probe。证据推广工具因现有cache总预算已满拒绝，`--prune-expired`没有可清已登记包；因此本批精简结果暂留上述任务根，未删除未知归属证据。停止的staged App、样本副本、临时HOME与重试截图清理；连续迭代仅保留 `/private/tmp/mwx-scene-next-build/cache/14d60a183f08e048bc3d072d` 构建缓存。真实媒体只读。
