<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。稳定合同归[高级对象](../capabilities/advanced-object-coverage.md#32-puppet-静态权重与几何失败边界)，后续缺口归[断点队列](../roadmap/scene-open-breakpoint-queue.md)。

# Puppet 角色参考姿态补接（2026-10-11）

N02 的三份原包已进入 Puppet draw，但头脸、头发或肢体散开。首错在 MDLS reader：骨骼 bind records 后直接返回，未投影角色组装 reference，多个 additive 因而重复累加相对 atlas bind 的组装位移。沿现 reader → rig → prepared evaluator → 同一 pose / attachment / skinning / compositor 补接；没有按样本选择算法。

## 依据与证据上限

公开 [Character Sheets](https://docs.wallpaperengine.io/en/scene/puppet-warp/charactersheet.html) 描述独立 Reference Pose 用于角色组装与动画起点，未公布二进制或混合公式。只读作者包观察到 MDLS0002 的 `00 00 01` 后为逐骨骼有限 affine 矩阵；这些值独立存储于 bind/clip 之外；282的受控骨骼与分离 bind/reference/frame0 的 native fixture 证明不能从 frame0 推导。原生 CPU 控制仅替换有效 local pose，保留原 inverse-bind、顶点、UV 与权重；重复组装位移随 reference 接入消除。这支持有界实现，不声称恢复私有格式全域或官方数值公式。

官方 2.8.0.42，SHA256 `DAAC1EA7C991207FDB6098616757E3DAE393850F6862845DB55D04921B6BDA07`。尝试在 `MWX-N02` 独立命名窗口运行只暂停/选轨/查询公开骨骼 API 的隔离作者副本，窗口显示组装人物；之后 VM 交互停滞，未取得计划的 getter 数值，不能把它记为数值对照通过。用户原目录 `截屏*.png` 用于确认主体应完整组装；视口、时刻、音源不同，不做逐像素声明。全程没有读取客户端或参考项目私有实现。

## 实现与非回退

- reader 仅消费已识别 MDLS0002 零前置 flag + reference present 的完整矩阵段，范围受 MDLS declared end 约束，后缀未解释数据不猜读。缺尾/无 reference 继续 bind；未知 prefix 保留旧投影并诊断；现代明确 reference present 未验证结构，沿原局部动画失败处理。
- evaluator 准备一次 reference TRS，使用原加权公式；inverse-bind 始终来自原 bind。新增 reference 的非有限、奇异或不可 TRS 重建（含 shear）拒绝，不扩大旧 bind 限制。单/多 clip、隐藏、零权重与空 selection 共用基准。
- reference-only 复用现 PlaybackState 的空 selection。init getter 的 reference 也走同一验证；独立审查发现最初候选把无 reference 的精确 bind getter 改成 TRS 近似，已用实际 getter + 自有 MDL 复现 shear 与小 determinant 两反例并修回。无 reference 初始矩阵保持原字节数值，不新增第二个姿态求值器。
- 先行设计保存在现合同第3.2.1节，实施前快照、红绿及审查收据留在证据根。最终四产品 diff SHA256 `8c7ec8aa834d428de73ac3109ecad6903a0207f4fa1a86af430d5391bb7111fe`，含两份现有测试的六路径 SHA256 `8807b40de8cc8dee9d9e8c760b2208e8a321ba3cee963425bd4af2d3cd7a804c`；隔离基线 `87ea237e`，排除主工作区三份 U06 编译在途文件。

## 验证与画面

自有 native reader → evaluator 输入分离 bind、reference 与 frame0，覆盖单/多轨、零/外推、nil frame、父子骨骼、静态 reference、无 reference、MDLS 越界/非法矩阵、shear 以及实际 init getter。旧权重门在首红保持通过；新增双 additive 反例由错误66恢复预期50。五原包 CPU 检查中三个 reference 模型 TRS 最大相对重建误差小于1.2e-7，两健康模型无 reference；不以数值门代替画面。

最终 Debug App executable SHA256 `e875ee9fcbc1864216e420a80c306dc3875e0bc5a392116ba1f1c3d7c1b1e005`，dylib `98e385fea6c562bbc0a83ef39c9c1db76d0b86405da382cf613cbb6736876d9b`。Debug build通过。Python 3.12综合选择75模块，73首次通过，另两失败为基线已存在的旧Swift stub：补齐`textCenterOffsetY=nil`及保持真实`var tint`后，两模块均通过；原断言未改。结构、依赖、防御、代码健康与文档门通过，独立只读审查无剩余阻断。系统Python 3.9的早先调用错误不计产品失败。

| 原样本 | 已观察画面及独立余项 |
|---|---|
| 2824690710 | 人物13的头脸、头发和双臂回到身体，原分离部件消失；原动画、背景与频谱仍绘制。 |
| 2877855240 | 人物333从大片缺失恢复为完整组装；六段 Skew effect 的原 owner-revoked / CPU fallback 仍属 N03，benchmark 不作整样本 PASS。 |
| 2887542690 | 头370恢复并与身体组装；其他四层继续绘制。34个 origin target 的 TypeError 与矩形片区布局/运动仍留 N06，不能关闭完整交互。 |
| 3698459055 / 3341111071 | 无 reference 的健康双 additive 与无动画静态 mesh 保留，分别作为动态/静态反例。 |

最终五例均exit0/无超时，GPU完成绘制且截图复核三例组装恢复、两例旧路径保留；但首轮及唤醒复核的presented计数为0，benchmark整体未通过。系统记录16:08:57显示器休眠，随后界面工具明确报告Mac锁定、无法自动解锁；`caffeinate`断言不等于已解锁。本批不据此声称实际屏幕呈现时序或性能通过，解锁后的呈现门仍待重跑。

本批不验普通 App→client→daemon 的选择流程、所有属性/交互、长稳、官方 getter 数值与逐像素 parity，也不把视口之外的作者长裙/全身顶点当作缺失。N02 组装首断点与后续 N03/N06 分开记账。

## 产物

证据根为忽略目录 `.artifacts/tmp/puppet-reference-pose-20261011`：固定源码/App/样本身份、原始日志和报告、必要截图、自有实验配方与审查收据。agent 日志注明转录自本轮工具回执，不冒称独立重复执行。原样本只读；基准runner已清理staged App/HOME，保留五份最终截图与压缩原始报告/日志。重复截图、shader重试输出与本批原生临时环境在提取后清理；证据提取降至32 MiB内后仍因全局1 GiB预算已满被拒，未提高预算或删除未知证据，本批最小证据暂留原根。连续迭代只留 `.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData` 一份构建缓存。官方隔离输入因 VM 挂起操作尚未结束暂保留，不强制断电或删除运行中输入。
