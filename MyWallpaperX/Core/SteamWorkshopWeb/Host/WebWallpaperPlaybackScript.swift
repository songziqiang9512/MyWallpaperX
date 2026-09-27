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
  Animation.prototype.pause = function(...args) {
    animations.delete(this); // An authored pause must survive the policy's resume.
    return pauseAnimation.apply(this, args);
  };
  const holdAnimations = () => {
    if (!paused) return;
    for (const animation of document.getAnimations()) {
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
        watchAnimations();
        holdAnimations();
      } else {
        observer.disconnect();
        for (const animation of animations) {
          // CSS author state can change while the policy holds the animation.
          // Reading it here preserves that intent without overwriting inline styles.
          if (animation instanceof CSSAnimation && animation.effect?.target instanceof Element) {
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
  if (paused) { watchAnimations(); holdAnimations(); }
  if (window.parent !== window) window.parent.postMessage({ mwxPlaybackStateRequest: true }, '*');
})();
"""#
