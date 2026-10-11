<!-- document-role: historical-evidence -->

> **历史证据 — 非现役入口**。后继工作从[当前断点队列](../roadmap/scene-open-breakpoint-queue.md)继续。

# 新增 Scene 样本运行普查（2026-10-11）

本页冻结本次普查证据；后继顺序与开放问题归[断点队列](../roadmap/scene-open-breakpoint-queue.md)，不建立第二条开发路线。

## 范围与判据

相对旧243成员验收快照，当前目录279份：新增37份，3763323436本次目录未见。不是重新验收全部279份。原始媒体只读；隔离副本的project/package身份与matrix逐项核对。

固定代码`d7011982c899abac25c1b5692639594e6f835a95`，Debug executable SHA256 `0729672e1c8d939f8ca8a3deb4babf428bb1544ac79451cf12f824569462a7e4`，dylib SHA256 `d41819d9081eb5b4c48776015ea28544b74745465e10507db56ba71ead27583f`。使用现有benchmark串行运行：默认作者属性、受控PCM频谱、ready后9秒、5秒后截图；首轮进程69秒限时，超时另行以240秒进程预算复验。入口是隔离direct Host，仅证明内部Program/GPU/合成；未验普通App→client→daemon、所有属性/交互、真实外部媒体、长稳或官方同相位效果。

静态复用现有census：37/37解析及身份守恒，24,023 occurrence、1,300 family，其中868与旧库共享、432为新声明形态；新声明不等于新缺口。97条实际MDL引用均resolved，版本0014/0016/0017/0023；其中0023有52条Puppet、8条直接model引用，不能因扩展名或版本号认定3D缺失。

## 每份运行与首断点

首轮37份均已尝试：35份ready并正常退出，2份到69秒限时后终止；后者单独冷HOME、同App延时重试；最终37份均取得ready及GPU排空退出，重试不覆盖首轮。成功进入内部链路不等于完整正确。下表列实际断链与人工画面观察；无已观察拒绝的成员仍未验完整属性、交互和官方效果。

| 样本 | 本轮记录 |
|---|---|
| 2776912698 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 2780710296 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 2807058277 | 隐藏text253/Perspective仅准备降级，本轮无执行；非默认可见故障。 |
| 2824690710 | 人物头脸缺失、头发分离；Puppet13已draw但几何大幅越屏，姿态/变换/UV/alpha待隔离。 |
| 2877855240 | 人物大部分缺失，Puppet333几何越屏；另六段solid/text Skew实际owner-revoked回退，不能互认根因。 |
| 2887542690 | 头脸缺失；五个Puppet层均有origin TypeError，geometry/pose与脚本首错分开核。 |
| 2890473419 | origin脚本TypeError；变换输入链待修。 |
| 2913492057 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 2960821850 | 材质texture-binding拒绝；layer92实际source-coverage-unproven，graph未执行；其他准备拒绝需核实际活跃分支。 |
| 3039882306 | layer1084 user-property基础材质fallback unavailable；沿属性资源到base provider核对。 |
| 3248220186 | 截图全黑；三个visible Sprite被world/perspective与depth/cull profile拒绝，不能据此断言唯一黑图原因。 |
| 3337494481 | 十个实际visible复制粒子RopeTrail不可用；flags1、subdivision=-16超当前profile；另有脚本invalid-argument与source-not-ready待追，原十hidden不计故障。 |
| 3341111071 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3351179520 | 实际effect owner-revoked局部回退，按source/profile扩现有compiler。 |
| 3374523158 | 四段准备拒绝与dependency-provider-rejected；本轮无对应actualgraph首错，激活/依赖需复验。 |
| 3435573282 | 实际source passthrough与局部fallback；22个上游material-template拒绝带来72段准备unsupported，不拆成72算法缺口。 |
| 3471294034 | 两段准备unsupported；本轮未证对应实际执行失败，保留条件分支复验。 |
| 3476868923 | 首轮69秒未ready；延时重试153.425秒ready、出帧后正常退出/GPU排空；冷启动慢仍开放，另105/effect1935 Blend有实际stage-reference回退。 |
| 3507496797 | 首轮69秒未ready；延时重试93.820秒ready、出帧后正常退出/GPU排空；本轮未观察明确执行拒绝。 |
| 3605502569 | 主17 Puppet与waterwaves26/tint48/iris61首/后帧GPU成功，末段最终消费；粒子34出帧。辅助频谱默认hidden，非缺失证明。 |
| 3617056047 | model70 SodaCan已实际显示；未做姿态相位对照，不将缩略图形状误判缺部件。 |
| 3632513108 | 截到天空与大花瓣；作者入场/属性分支及同相位视觉待核，本轮未观察明确执行拒绝。 |
| 3641200550 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3666041758 | fullscreen190两段Blur frontend-envelope回退；主solid138有Program准备但无实际graph；141 visibility owner invalidSource；白点画面根因未隔离。 |
| 3680252478 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3695791724 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3698459055 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3708363772 | layer705/effect560 dependency-stage-reference-unsupported，实际局部回退；221.visibility owner invalidSource另留准备期调用合同待核。 |
| 3722749868 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3761619125 | 人物大片白色缺失；39段实际owner-revoked及origin TypeError，合成/脚本分别定位，未隔离唯一根因。 |
| 3766310551 | visibility脚本TypeError；按同一VM入口追作者调用。 |
| 3781757083 | visibility脚本BAD_RETURN；合法返回/失败保留合同待核。 |
| 3809034761 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3811216799 | 仅灰底与时钟；主17 TEX invalidMipTable，嵌MP4载荷超过静态mip上限，在视频识别前被拒；benchmark PASS漏掉此可见损失。 |
| 3812473896 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3814040466 | 默认短运行未观察明确执行拒绝；完整画面正确性未验收。 |
| 3815761795 | layer233实际unclaimed-visible-effects-publication-unavailable，资源发布/consumer边界待修。 |

## 归并与后继

本批只完成新样本运行、首断点归并与修复入口排序，没有把诊断写成画面修复。现役待办见队列新增N01–N10；具体每条scope、实际/准备阶段和原日志SHA在本批runtime-triage中，不为同一上游拒绝逐effect新增算法。

比较三项：381的嵌MP4入口已有精确字节/代码拒因，修复路径短且符合纹理优先；三份Puppet局部缺失用户影响大且跨样本，但姿态、脚本、UV/alpha尚待隔离；324世界Sprite黑图影响大，仍需depth/world官方合同。故新增修复优先嵌视频资源准入，再Puppet公共姿态/变换，再材质/粒子组合；若首方向需新资源模型，则先落设计并重评成本，不直接加大全局上限。

381的唯一TEX共257,625,327B，TEXB0004 metadataCount=0沿既有TEXB0003有效布局；mip起点91、stored=257,625,236、末端恰好文件末尾，载荷有MP4 ftyp/isom/avc1头。`SceneTexDataReader`在容器末尾识别MP4前，先以静态`maximumMipByteCount=250,000,000`拒绝。属于已定位入口，不是未知TEX版本；后续复用视频provider并保持静态纹理解压/越界安全，不能把整个视频按解码纹理扩大预算。

先前U06的逗号scalar→vector修复仍在独立修改范围冻结，CPU/glslang与只读复审已通过；缓存退旧、Debug/App后验及提交尚未完成。它不在本批运行App内，不能将本批结果算作该修复收益。

## 证据与未覆盖

普查使用原有benchmark、diagnostic report、sample debug archive与census。自动归档状态是工具结构分类，不是视觉裁决；灰底和Puppet缺失证明必须保留人工画面检查。CPU采集/截图归档与静态分析有竞争，本轮不作性能对比；ready耗时仅用于辨别本次是否超过首轮时限。

证据保留在忽略目录`.artifacts/tmp/new-scene-intake-20261011/retained`（约24.6MiB）：首轮原始report无损gzip、紧凑索引、37份运行日志/runtimeInput、2份重试、静态身份与断链投影；日志与JSON压缩无损，截图为1280边界JPEG总览，仅供大面积缺失判断，不作像素parity证据。自动证据提升因全局缓存预算已满拒绝；已运行prune-expired，无可清包，未增大预算或删除未知材料，暂以此最小目录保护未解决问题。

同批大型运行副本、临时HOME、staged App及可再生shader导出在复核后清理；保留一份后继U06构建缓存`.artifacts/tmp/scene-constructor-runtime-20261011/DerivedData`，与本批retained证据分开。真实用户目录始终只读。
