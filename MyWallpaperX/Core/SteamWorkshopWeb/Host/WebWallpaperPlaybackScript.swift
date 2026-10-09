/// A page execution gate, injected before authored scripts in every frame.
/// Normal playback keeps native scheduling; only explicit pause holds callbacks.
let webWallpaperPlaybackScript = #"""
(() => {
  let paused = __MWX_INITIAL_PAUSED__;
  let nextID = 0;
  const work = new Map();
  const animations = new Set();
  const raf = window.requestAnimationFrame.bind(window);
  const cancelRAF = window.cancelAnimationFrame.bind(window);
  const timeout = window.setTimeout.bind(window);
  const clearTimer = window.clearTimeout.bind(window);
  const now = () => performance.now();
  const arm = (entry) => {
    if (paused) return;
    entry.started = now();
    const fire = (stamp) => {
      entry.nativeID = null;
      if (paused) return;
      if (!entry.repeating) work.delete(entry.id);
      try {
        if (entry.frame) entry.callback.call(window, stamp);
        else if (typeof entry.callback === 'function') entry.callback.apply(window, entry.args);
        else (0, eval)(String(entry.callback));
      } finally {
        if (entry.repeating && work.has(entry.id)) {
          entry.remaining = entry.delay;
          arm(entry);
        }
      }
    };
    entry.nativeID = entry.frame ? raf(fire) : timeout(fire, entry.remaining);
  };
  const schedule = (frame, repeating, callback, delay, args) => {
    const milliseconds = Math.max(0, Number(delay) || 0);
    const entry = { id: ++nextID, frame, repeating, callback, args,
      delay: milliseconds, remaining: milliseconds, nativeID: null, started: now() };
    work.set(entry.id, entry);
    arm(entry);
    return entry.id;
  };
  const cancel = (id) => {
    id = Number(id);
    const entry = work.get(id);
    if (!entry) return;
    if (entry.nativeID !== null) (entry.frame ? cancelRAF : clearTimer)(entry.nativeID);
    work.delete(id);
  };
  window.requestAnimationFrame = callback => schedule(true, false, callback, 0, []);
  window.cancelAnimationFrame = cancel;
  window.setTimeout = (callback, delay, ...args) => schedule(false, false, callback, delay, args);
  window.setInterval = (callback, delay, ...args) => schedule(false, true, callback, delay, args);
  window.clearTimeout = window.clearInterval = cancel;

  const pauseAnimation = Animation.prototype.pause;
  // CSS 动画冻结走样式表（设计：docs/web/css-animation-freeze-redesign.md）：
  // CSSAnimation 一经原生 pause()/play() 即与 animation-play-state 永久解耦
  // （CSS Animations Level 2，WebKit 实证）——策略冻结改注入
  // `animation-play-state: paused !important` 样式表（light DOM + 每个 open
  // shadow root），恢复即移除；作者的 play-state 耦合全程保持。WAAPI/
  // CSSTransition 无该耦合，保留原生 pause/play 集合语义。
  const FREEZE_STYLE_TEXT = '*, *::before, *::after { animation-play-state: paused !important; }';
  const FREEZE_STYLE_FLAG = 'data-mwx-policy-freeze';
  const freezeStyleNodes = new Set();
  let freezeInstalledRoots = new WeakSet();
  const installFreezeStyleInto = (root) => {
    try {
      if (freezeInstalledRoots.has(root)) return;
      const host = root instanceof ShadowRoot ? root : (root.head || root.documentElement);
      if (!host || typeof host.appendChild !== 'function') return;
      const style = document.createElement('style');
      style.setAttribute(FREEZE_STYLE_FLAG, '');
      style.textContent = FREEZE_STYLE_TEXT;
      host.appendChild(style);
      freezeStyleNodes.add(style);
      freezeInstalledRoots.add(root);
    } catch (_) {}
  };
  const collectShadowRoots = (root, visited, found) => {
    if (!root || visited.has(root)) return;
    visited.add(root);
    try {
      if (!root.querySelectorAll) return;
      root.querySelectorAll('*').forEach((element) => {
        if (element && element.shadowRoot) {
          found.push(element.shadowRoot);
          collectShadowRoots(element.shadowRoot, visited, found);
        }
      });
    } catch (_) {}
  };
  const installFreezeStyles = () => {
    installFreezeStyleInto(document);
    const found = [];
    collectShadowRoots(document, new WeakSet(), found);
    for (const shadowRoot of found) installFreezeStyleInto(shadowRoot);
  };
  const removeFreezeStyles = () => {
    for (const style of freezeStyleNodes) {
      try { style.remove(); } catch (_) {}
    }
    freezeStyleNodes.clear();
    freezeInstalledRoots = new WeakSet();
  };
  // 冻结窗口内新建的 shadow root 拿不到注入节点（外层样式表与 MutationObserver
  // 都不穿 shadow 边界，WebKit 实测 animationstart 也不冒泡到 document）——
  // 冻结期用自持原生定时器幂等重扫补挂（≤1s 延迟，恢复即停）。重扫走
  // installFreezeStyles 的 WeakSet 查重，无新根时零 DOM 写入。
  let freezeRescanNativeID = null;
  const startFreezeRescan = () => {
    if (freezeRescanNativeID !== null) return;
    const rescan = () => {
      freezeRescanNativeID = null;
      if (!paused) return;
      installFreezeStyles();
      freezeRescanNativeID = timeout(rescan, 1000);
    };
    freezeRescanNativeID = timeout(rescan, 1000);
  };
  const stopFreezeRescan = () => {
    if (freezeRescanNativeID === null) return;
    clearTimer(freezeRescanNativeID);
    freezeRescanNativeID = null;
  };
  Animation.prototype.pause = function(...args) {
    animations.delete(this); // An authored pause must survive the policy's resume.
    return pauseAnimation.apply(this, args);
  };
  const isCssAnimation = (animation) => {
    try { return animation instanceof CSSAnimation; } catch (_) { return false; }
  };
  const holdAnimations = () => {
    if (!paused) return;
    for (const animation of document.getAnimations()) {
      if (isCssAnimation(animation)) continue; // 样式表统一压住，不入集合。
      if (animation.playState === 'running') {
        animations.add(animation);
        pauseAnimation.call(animation);
      }
    }
  };
  const observer = new MutationObserver(holdAnimations);
  const watchAnimations = () => observer.observe(document, {
    subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style']
  });
  document.addEventListener('animationstart', holdAnimations, true);
  document.addEventListener('transitionrun', holdAnimations, true);
  const playAnimation = Animation.prototype.play;
  Animation.prototype.play = function(...args) {
    const result = playAnimation.apply(this, args);
    // 作者在冻结期对 CSSAnimation 显式 play：样式表压不住（API 调用后
    // play-state 失效），立即回压——该单个动画接受解耦（作者显式对抗
    // 冻结；正常策略周期不产生任何解耦）。
    if (paused) { animations.add(this); pauseAnimation.call(this); }
    return result;
  };
  const animate = Element.prototype.animate;
  Element.prototype.animate = function(...args) {
    const animation = animate.apply(this, args);
    if (paused) { animations.add(animation); pauseAnimation.call(animation); }
    return animation;
  };
  const message = value => ({ mwxPlaybackPaused: value });
  window.__myWallpaperSetPagePaused = value => {
    const next = !!value;
    if (next !== paused) {
      paused = next;
      if (paused) {
        for (const entry of work.values()) {
          if (entry.nativeID === null) continue;
          (entry.frame ? cancelRAF : clearTimer)(entry.nativeID);
          entry.nativeID = null;
          if (!entry.frame) entry.remaining = Math.max(0, entry.remaining - (now() - entry.started));
        }
        installFreezeStyles();
        startFreezeRescan();
        watchAnimations();
        holdAnimations();
      } else {
        stopFreezeRescan();
        removeFreezeStyles();
        observer.disconnect();
        for (const animation of animations) {
          // 集合只含 WAAPI/CSSTransition 与冻结期被作者显式 play 的
          // CSSAnimation（回压入集）；对后者沿用 computed 校验保作者意图。
          if (isCssAnimation(animation) && animation.effect?.target instanceof Element) {
            const style = getComputedStyle(animation.effect.target);
            const names = style.animationName.split(',').map(value => value.trim());
            const states = style.animationPlayState.split(',').map(value => value.trim());
            const index = names.indexOf(animation.animationName);
            if (index >= 0 && states[index % states.length] === 'paused') continue;
          }
          if (animation.playState === 'paused') animation.play();
        }
        animations.clear();
        for (const entry of work.values()) arm(entry);
      }
    }
    for (let i = 0; i < window.frames.length; i++) window.frames[i].postMessage(message(paused), '*');
  };
  window.addEventListener('message', event => {
    if (event.data?.mwxPlaybackStateRequest === true) event.source?.postMessage(message(paused), '*');
    else if (event.source === window.parent && typeof event.data?.mwxPlaybackPaused === 'boolean') {
      window.__myWallpaperSetPagePaused(event.data.mwxPlaybackPaused);
    }
  });
  if (paused) { installFreezeStyles(); startFreezeRescan(); watchAnimations(); holdAnimations(); }
  if (window.parent !== window) window.parent.postMessage({ mwxPlaybackStateRequest: true }, '*');
})();
"""#
