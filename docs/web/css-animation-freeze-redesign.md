<!-- document-role: active-plan -->
<!-- retirementCondition: 播放门按本设计完成 CSSAnimation 样式表冻结改造且行为断言（冻结/恢复/authored play-state 保持/帧冻结）入库后，若引入替代机制则整体归档。 -->

# Web 播放门 CSS 动画冻结机制重构

> 复核基线：2026-10-10，工作树（批十七 59dabe1d 之后）。本文是设计裁决，不是当前能力或运行验收；实施随批完成。

## 目标合同与设计判据

策略暂停对 CSS 动画的冻结/恢复不得永久破坏页面作者与 `animation-play-state` 的耦合。现行实现（`WebWallpaperPlaybackScript.swift`）对 `document.getAnimations()` 里所有 running 动画调原生 `Animation.prototype.pause()`、恢复时 `.play()`——CSS Animations Level 2 规定 CSSAnimation 一经该 API 调用，`animation-play-state` 对它永久失效（独立 swiftc WKWebView 探针三步实证：基线 frozen class 生效 → pause+play → frozen class 失效）。用户可见缺陷：一次宿主暂停/恢复后，作者的 hover 暂停、`body.freeze` 类切换、可见性暂停等全部失效。

判据：触碰播放门唯一 owner 合同=是；用户可见且不可逆（规范级解耦）=是；按仓库纪律设计先行。

## 当前事实与证据

- 冻结侧 `holdAnimations`（:60-68）：遍历 `document.getAnimations()`，`playState === 'running'` 者入 `animations` 集合并原生 `pauseAnimation.call`；MutationObserver + `animationstart`/`transitionrun` 捕捉暂停窗口内新增。
- 恢复侧（:102-116）：`animations` 集合逐个 `.play()`，CSSAnimation 先做 computed `animation-play-state` 校验跳过作者暂停者；定时器/rAF 同步 `arm`。
- 拦截包装：`Animation.prototype.pause`（作者 pause 时从集合除名，保证策略恢复不复活）、`Animation.prototype.play`（暂停窗口内作者 play → 立即回压）、`Element.prototype.animate`（暂停窗口内新建 → 回压）。
- 探针（2026-10-10，本机 WebKit）：`@keyframes spin` + `.frozen { animation-play-state: paused !important }`；`anim.pause(); anim.play();` 后再加 frozen class，`anim.playState === 'running'`——解耦坐实。

## owner

播放门唯一 owner 不变（`WebWallpaperPlaybackScript.swift`，注入每 frame，`__MWX_INITIAL_PAUSED__` 种子）。本设计只改冻结/恢复的执行机制，不动 rAF/定时器记账、帧间 postMessage 传播、状态请求补齐。

## 方案设计与选型

选 **(a) CSSAnimation 走样式表冻结、WAAPI/CSSTransition 保留原生 API 的双轨制**。候选 (b) 全量继续原生 API + 恢复时重建动画（cancel+重触发）被否决：重建改变动画身份（startTime/effect 关联丢失、作者持有的引用失效），比解耦更破坏页面。

1. **冻结（CSSAnimation）**：向 light DOM 注入 `<style data-mwx-policy-freeze>`（`*, *::before, *::after { animation-play-state: paused !important; }`），并向每个 open shadow root 注入同一文本的 style 节点（外层样式表不穿 shadow 边界——本设计核心难点）。shadow root 集合用与 `wallpaperMediaNodes` 同型的递归遍历（`querySelectorAll('*')` + `shadowRoot` 递归；`contentDocument` 同源 iframe 由该 frame 自身的脚本实例负责，不跨层注入）。样式表冻结不需要捕捉动画进集合：冻结时点已有根内新增的 CSS 动画天然被 `!important` 压住；冻结窗口内新建的 shadow root 由冻结期原生定时器幂等重扫补挂（≤1s；WebKit 实测 shadow 内 animationstart 不冒泡到 document，事件方案不可行）。
2. **恢复（CSSAnimation）**：移除全部注入节点。作者的 `animation-play-state`（含暂停窗口内切到 paused 的）在移除后自然生效——现行恢复侧的 computed 校验（:106-111）对该类不再需要。
3. **WAAPI/CSSTransition**：无 `animation-play-state` 耦合可破坏，保留现行原生 pause/play 与集合语义（含 `transitionrun` 捕捉、play/animate 拦截回压）。
4. **作者 play during freeze（CSSAnimation）**：作者代码调 `anim.play()` 时样式表压不住（规范：API 调用后 play-state 失效）——保留现行 `Animation.prototype.play` 拦截对该类立即回压 `pauseAnimation.call`。该边角接受单动画解耦（作者显式 play 本身就是在与冻结对抗，且现行实现同样如此）；正常策略周期（无人为 play）不再产生任何解耦。
5. **作者 pause during freeze（CSSAnimation）**：无需处理——样式表已压住，作者 pause 后恢复时样式表移除、其 paused 意图由其自身的 play-state/调用状态自然保持。
6. **双轨集合纪律**：`holdAnimations` 遍历时按 `animation instanceof CSSAnimation` 分流——CSSAnimation 不入集合（不原生 pause）；其余入集合。恢复时只对集合成员 `.play()`。`animationstart`/`transitionrun` 监听保留（对 WAAPI/CSSTransition 仍必要；CSSAnimation 事件到达时分流逻辑天然跳过）。

## 失败与退出

- 浏览器不支持 `getAnimations`/`CSSAnimation` 判定时（理论不可达，注入面已存在该 API）：`instanceof` 失败即落入原生轨道，行为回退到现行实现，不更糟。
- 注入 style 节点被作者代码移除：MutationObserver 只观察 class/style 属性，不观察 style 节点删除——冻结可能被作者绕过；这与现行实现（作者可直接对动画调 play 绕过，需拦截）暴露面同级，接受并在设计内声明。策略暂停的强制力由 WebKit 原生媒体门 + rAF/定时器门承担主体，CSS 动画冻结是尽力面。
- 回退条件：实施后真实 WKWebView 行为断言（探针）任一失败——冻结不生效/恢复不跑/解耦仍发生——则回退整批并维持登记。

## 验收

- 行为断言探针（独立 swiftc WKWebView 程序，注入改造后的播放门文本）：(i) 暂停后 CSS 动画 currentTime 停走；(ii) 恢复后继续走；(iii) **关键断言**：恢复后再切 frozen class，动画再次暂停（play-state 耦合保持）；(iv) shadow root 内 CSS 动画同样冻结/恢复；(v) WAAPI（element.animate）冻结/恢复正常。探针产物在临时目录不入库。
- `test_web_playback_pause`（真实 WKWebView，含 AudioContext 暂停回合与 authored-pause 保留断言）与全焦点模块绿；`web_property_persistence_gate` PASS。
- 独立子代理审查：双轨分流完备性（CSSTransition/WAAPI/CSSAnimation 三类矩阵）、shadow 注入的遍历正确性、恢复语义（不再需要 computed 校验的论证）、拦截包装边角、既有计时记账零改动。
