<!-- document-role: stable-contract -->

# Sampler 缺省输入与显式声明的优先级

Owner：`SceneResolvedMaterialShaderSchema`。状态：设计 approved；限定为既有输入语义纠偏，不扩展作者能力。触发设计前置的原因是修改已冻结的结构推断家族。

`implicitFramebufferSlots` 只补齐未声明 material 角色的 slot 0。显式 material 声明必须由现有 alias、authored candidate 或有完整 effect-input/color-carrier 证明的 dormant 路径裁决；未知 material 不能因位于 slot 0 自动变成 framebuffer。label 本身不提供来源身份，仍走已有 alias 规则。不存在新 registry、第二套绑定逻辑或 sample 分派。

当前偏差是 implicit 推断早于 dormant 事实生成，且忽略 material 声明：`source`、未满足 hidden 条件的历史 key、未知编辑器 key 被错误注入 graph input；有证明的 hidden 任意 key 也丢失 dormant provenance。新增条件的具体产生者是 sampler 注解解析后的 `Sampler.materialKey`，反例位于 finalizer harness 的 `nonFramebufferDoesNotInject`、`historicalFramebufferWithoutHidden`、`historicalFramebufferLabelOnly`、`unknownEditorMaterialAlias`。纠正后失败局限于该材质绑定，保留现有局部视觉失败策略。

同批测试身份纠偏：shader fixture 修改源码必须同时改变内容摘要，持久化分析缓存必须位于测试临时目录；同一份输入冷/热缓存结果必须一致。不得以关闭缓存掩盖错误身份。旧 preflight helper 调用数断言退役，依赖准备顺序、隐藏 provider 与动态 topology 的执行测试承担行为覆盖。

验证要求：无 material 的隐式 slot 0 仍成功；显式合法别名仍成功；未知角色无证据拒绝；有 effect-input 证明的 hidden 任意 slot 保留 dormant provenance；neutral resolution 的错误分量/额外读取必须拒绝。执行 finalizer 的冷/热缓存、相关依赖与拓扑模块，以及 Debug build、code-health、scene-defense、design-gate。门通过后删除临时设计登记；本文保留优先级合同。运行结论不外推至 corpus 或官方 parity。
