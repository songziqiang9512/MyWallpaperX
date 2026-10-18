<!-- document-role: historical-evidence -->

# 粒子覆盖材质原型资格与停止（2026-10-18）

> **历史证据 — 非现役入口**。截止：2026-10-18。原型未采纳，相关产品改动与专用测试已精确撤回。本页保留当时设计取舍；现役范围归[粒子能力表](../capabilities/particle-component-coverage.md)，顺序归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，实际运行归[证据](../capabilities/runtime-evidence-current.md#particle-coverage-qualification-20261018)。本页不授权重启或作为待实施卡。

## 当时要解决的公共语义

原3807668787的958由合法`alphatocoverage`材质首拒而未进入粒子执行。候选尝试沿原typed材质→prepared root/child需求→共享几何/采样→原MetalPipeline→唯一compositor，补有界普通genericparticle Sprite/Rope覆盖输出，拒绝用translucent替代。未按样本、路径、hash或截图分流。

固定官方2.8.0.42自有四行板中，Sprite/Rope的透明、不透明和运动正控成立；三个半透明档的覆盖响应与translucent不同。Apple M4/macOS27的独立Metal板也证sample1下A2C有效，alphaToOne可在覆盖后存alpha1；这些只支持所测输入，不定义通用阈值、边缘、隐藏combo、MSAA数或跨设备保证。

## 候选职责与取舍

- 共享render state保作者枚举；仅既有pass0、无refraction/lighting/cutout/user输入、静态overbright、no-cull/depth-disabled及alpha omitted/default profile进入候选，其余消费者原边界保持。
- Runtime准备期汇总准入root与child templates，包括隐藏及未出生事件child；无需求不增加新函数/PSO。普通帧不扫描拓扑、解析或编译。
- Shader共用几何、UV、跨帧取样；旧透明/叠加/refraction保PMA，coverage在PMA前取straight RGB和texture alpha×particle alpha。candidate只启硬件A2C/alphaToOne、关blend，用sample1原资源链，无MSAA/resolve/pool/第二输出owner。
- 可选coverage PSO分别匹配无depth与共享depth32；缺失只拒该draw，健康旧六状态保持，不暗退translucent。取消、buffer completion与退休继续原owner。

## 为什么没有进入产品

材质变体/反例、准备期需求、实际粒子GPU像素门和独立静态审查成立，正常Debug与独立347画面健康；但原U19候选只取得执行计数，没有证实目标拖尾恢复。官方原包连续pointer两图的短白双线也未唯一归属958；小窗口/离散与连续输入、实际几何与采样alpha仍未闭合。先前以initializer色值推定“青色”不能成为已证官方颜色合同。

因此触发原设计的退出条件：撤回共享blend/准备/Shader/PSO及配套专用测试，保原局部拒绝，冻结全部原型源码/diff、正反例、首失败及真实原图。结构通过不改写为用户画面完成，没有性能收益结论。静态发现的material constant脚本包装判定问题也未随撤回宣称修好。

重启前须取得唯一可归因的官方/原生目标、实际几何与输入时序，或另一真实可见受益消费者；不能重跑同一无区分矩阵、调作者alpha/采样/阈值救图或仅以准入/GPU完成计数交付。更广MSAA、其它材质、HDR与全屏路径不在本片决定内。
