<!-- document-role: active-plan -->
<!-- retirementCondition: 四类触发点均使用唯一 typed graph transfer 合同，重复路径撤权且 publication 门通过后归档。 -->

# D12 — 四类 copy 触发点的 graph 语义收敛

> 复核基线：2026-10-01，独立工作树 `93b1b85a`。本文是设计裁决，不是当前能力或运行验收；已合入 `codex/engine-refactor-program`；实施时按其最新代码重新核对所列 owner，以下行号仍指向原设计基线。`approved` 仅表示本设计完成，阶段性 unknown 仍受本文准入门约束。

## 目标合同与设计判据

link 名称变化、mip 快照、作者 copy command、post-process 末跳都通过同一个 graph 资源版本与传输合同决策；并非每个“copy”都必须发出物理复制。跨 graph planner、资源 lease、encoder 与 terminal output，触及 hazard、publication 和唯一 compositor。

五判据：横切多个 owner 或主链节点=是；触碰唯一权威合同=是；用户可见且难逆的 API/数据/发布合同=否；触碰机器冻结结构家族=是；依赖官方或平台外部证据=是。

## 当前事实与证据

- `MyWallpaperX/Core/SteamWorkshopScene/Compilation/Graph/SceneAuthoredEffectRenderPlanner.swift:315` 已区分 copy/swap/unknown；`:328` 要求不同且已声明的两端，`:336` 插入有序 node。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Graph/SceneGraphResourcePassEncoder.swift:149` 已有 typed copy operation，先 validCopy 再 encodeCopy。
- `MyWallpaperX/Core/SteamWorkshopScene/Rendering/Targets/SceneGraphRenderTargetPlan+Extent.swift:61` 明确 1×1 probe 不能证明实际 copy extent 兼容；`:81` 检查命令源/目的声明与描述符。
- [Mirage 结构参考](../../development/reference/miragewallpaper-rendering-reference.md) `:208` 的资源版本与 `:500` 的最终 copy/blit 是有限对照；交接 render-9 的四触发点作为审计范围，不代表当前四路都已完整实现。

## owner

现役 authored render planner/graph admission owns transfer intent、作者顺序与版本边；target lease owns storage/lifetime；SceneGraphResourcePassEncoder 是既有 transfer encoding 接口；终端 compositor 唯一 owns final present。禁止新增独立 CopyManager 或副 compositor。

## 方案设计与选型

选择**统一语义 IR、按能力降低为 alias/blit/render transfer**。仅把四处调用包成同名函数不能统一版本语义；把全部 copy 变成全屏 draw 会改变 alpha、颜色与性能，均不采用。

| 触发点 | graph 行为 | 不能采用的捷径 |
|---|---|---|
| link 改名 | 先判断只是同版本逻辑别名还是需要独立快照；后者生成新 target version 与 copy node | 名字不同就复制；或需要 snapshot 却 alias 可写 storage |
| mip 快照 | 固定读取时点、source mip/slice/extent 与目标用途；复制既有 mip，与生成 mip 链分为不同操作 | 用 base mip 假装全部 mip；在 source 后续覆写后才取样 |
| authored copy command | 在作者命令所在次序插入，精确 source version→destination new version | 移到 effect 末尾、把未知 command 当 swap |
| post-process 末跳 | 将最后 graph result 交 terminal compositor；若格式/extent/颜色一致且可直接消费，可省物理 copy | 绕过 terminal compositor 自行 present；在 final copy 再次 blend/tone map |

每个 transfer 描述已有 logical identities、读写版本、subresource、extent、format、content/alpha、读写用途与 completion 要求。兼容 bit-preserving copy 用 blit；缩放/颜色转换是明确 render transfer，独立标注，不能借 copy 暗改数据。mip 生成是依赖 source 的显式 prepared 工作，不由一个 copy Bool 隐式触发。

prepare/invalidation 验证源/目的范围、格式、采样数、mip/slice、history pin 和 alias hazard；runtime 检查实际 allocation generation/physical token 与 descriptor。未声明合法 feedback 的 self-copy 拒绝；需要重叠区域 copy 时先显式准备安全中间 target，不原地赌驱动行为。

allocation 未完成、encoder 创建失败或 command buffer 失败不能 advance committed destination version。相同 buffer 内依有序 graph 消费候选版本；跨帧发布仍受现役 completion/history 协议。resize/reload 使旧 transfer reservation 失效，completion 只能回收自己的 token。

[D8](rt-prefix-admission-design.md) 负责两端名字解释，[D1](composition-render-target-design.md) 组目标作为普通 typed target；[D2](hdr-tonemap-edr-design.md) 显示映射只在末端执行，copy 不重复 tone mapping。

## fallback / route

可选 effect 的 copy 不可用时保留进入 effect 前的 previous-current；有真实必需依赖的后继只拒绝最小闭包，不向其发布旧值冒充新版本。hazard/range/generation/预算违规 hard reject。旧 copy 路由迁移 `observe-only` 比较规划，不能双执行；按触发点转 `generic-only` 后删旧 encoder 分支。

## 纠正门

- 四个触发点分别以自有颜色格、不同 mip、alpha/data 纹理验证读取时点和目标内容；copy 前后插入 source 修改可区分 alias 与 snapshot。
- format/extent mismatch、1×1 probe 假阳性、source=target、mip 越界、history pin、resize、encoder/GPU failure 和反序 completion 都必须有反例。
- bit copy 使用精确字节门；缩放/显示转换使用预声明像素容差；命令顺序、publication version、terminal present 次数与 next-frame identity 要 exact。
- 实施时先盘点四类生产入口与现役 copy owner，再收缩重复路径和结构预算；不能根据“统一了函数名”报告完成，不能把 mirror/第三方输出当官方 golden。

## 退役条件

四类路径完成真实 producer→consumer 追踪和正反门，稳定 graph 合同接管且旧 copy 分支与预算同步下降后归档。未知 mip/颜色 profile 仍由 admission 显式拒绝。
