<!-- document-role: historical-evidence -->

# Scene 背景色属性热更新（2026-10-15）

> **历史证据 — 非现役入口**

语义与边界归[属性覆盖](../capabilities/runtime-input-property-coverage.md#scene-clear-color-property)，后继归[属性卡](../roadmap/properties-panel-card.md)。本片修复direct Color绑定到Scene清底时被过滤、编辑要求整景重建的问题，不把某个作者键当内建分支。

## 实现与最近门

复用原binding compiler→Program→Host live consumer→typed snapshot→主pass clear。只接general.clearcolor的直接绑定、有效Color定义、clearEnabled=true；脚本/动画冲突、缺consumer或同键任一不支持target仍整批拒绝并保旧revision/值。clearenabled本身未开放热更新；SDR/HDR同用启动解释，逐component复用saturatingFloat，保alpha1、原clear/load和display mapping，不新增gamma或clamp。

9个owned产品/测试路径freeze aggregate `34dd5c882dd757ccea74a29298ed344b78b9f48bd859083d569917e5229ca5d3`；共享ClearColor最终SHA `0f82a33ad4acc7914558180e63a6a64dad414c4279cdcf41235c0d91e3a3dfe9`。20个唯一门通过：11真实parser/Program/Host/LiveState（68新增事实）、5实际Metal输出（28新增事实）和4原service/clear策略门。包含改键/默认/不匹配/类型/script/混合cohort/clear-off、SDR/HDR冷/热同色、Float精度与有限极值、首clear/续load；308个Metal编译输入前后无漂移。旧源Color准入RED已保存。一次GPU并行hook导致的非DEBUG fixture编译错误修复后仅重跑受影响Metal门，不计产品RED。

独审绑定最终9路径SHA，无新增发现。共用[GPU片记录](gpu-stage-timestamp-qualification-2026-10-15.md)的冻结Debug App `3d66673365c6f56435aca0341e1630562c78afd5747c856ed32c67975df440b7`，4298输入无漂移；不重复构建、不冒充每提交独立构建。全局dependency/test-assertions仍有a55ed7dd继承缺口，相关文件未变，未扩baseline放行。

## 普通产品入口与实际画面

293原内容/原属性，在正常下载详情打开属性面板，原来丢失的主题色行可见。为暴露背景，使用作者原光圈与粒子开关关闭这两层，未改源文件。一次实际启动/首帧，session `3D628B90-244D-403D-AEC3-D722C93F6970`、surface1、桌面window36601保持。

首次AX打开的是未绑定的全局颜色面板，改HEX没有改变属性/画面；明确排除。关闭后实际鼠标点击ColorWell，键盘输入HEX/Return才作为有效动作：`00FF00`、`007FFF`两次均改变原属性与实际背景，关闭重开保蓝值和作者开关；全reset恢复黑色及开关默认，再关闭同一作者两层复核黑底。

| 状态 | 背景ROI RGB | 范围 |
|---|---|---|
| 默认/重置后 | (0,0,0) | (32,32)–(288,288)，65536像素均一 |
| green | (117,251,76) | 同ROI；OS颜色管理后值，非作者RGB逐字节golden |
| blue | (55,125,247) | 同ROI；属性保存rgb=(0,.498039,1) |

只对背景ROI核修改后像素；不据此断言每次前景fidelity。独立324原样渲染见紫蓝粒子球、辉光与实时时钟，正常原生面板仍有Color/Bool/Combo/HDR/作者提示；未知token保原文。本轮未编辑324，不计第二clearColor正例、完整粒子兼容或官方parity。

切换及Stop/CmdQ退出0；primary1/1、independent17/17 VM quiescent，failures/timers/jobs/mutations/dynamicLayers=0；parent92882/daemon92894消失。未导出最终pin/drain，不把VM收尾当全部资源归零。未量面板延迟或CPU/GPU/内存百分比；用户收益是此前丢失的合法颜色入口可连续改实际背景且不重建。

## 材料与后继

`.artifacts/tmp/scene-clear-color-live-20261015/proof/`保最近门、独审、原源RED及patch/freeze；`.artifacts/tmp/native-stage-and-clearcolor-20261015/proof/clear-color/`保操作/ROI/必要原图、source unchanged及正常退出，清理收据在共同proof/cleanup.json。3份用户源tree不变；停止使用的样本副本/HOME/tmp/被替代App共清912,734,527B，保当前Debug App、优化诊断基线、连续DerivedData与共享shader cache。截图总约24.07MB，旧唯一大型trace未删除。

后继206的两个effect slot1入口已存在service→catalog demand→资源事务→FrameRegistry→selection链；只读发现不是缺失证明。先核真实prepared slot及替图/reset画面，不再造texture Program或按面板出现/CPU applied推导GPU消费。多屏、clear-off、条件绑定、动画/脚本、颜色空间golden及整面板性能仍开放。
