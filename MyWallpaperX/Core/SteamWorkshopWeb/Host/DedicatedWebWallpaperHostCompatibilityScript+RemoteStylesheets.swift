//
//  DedicatedWebWallpaperHostCompatibilityScript+RemoteStylesheets.swift
//  MyWallpaperX
//

let webRemoteStylesheetCompatibilityScript = #"""
(() => {
  if (window.__mwxRemoteStylesheetCompatibilityInstalled === true) return;
  window.__mwxRemoteStylesheetCompatibilityInstalled = true;
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostLog;
  const post = (type, message) => {
    if (!handler || typeof handler.postMessage !== 'function') return;
    try { handler.postMessage({ type, message: `frame=${document.location.href} ${String(message || '')}`.slice(0, 600) }); } catch (_) {}
  };
  const degradedTimeoutMS = 3000;
  const activationTimeoutMS = 5000;
  const retryRequestTimeoutMS = 15000;
  const retryBaseDelayMS = 2000;
  const retryMaximumDelayMS = 30000;
  const maximumRetries = 5;
  const states = new WeakMap();
  const importRecoveryLinks = new Map();
  let styleSheetScanTimer = 0;

  const isLink = (node) => {
    try { return node instanceof HTMLLinkElement; } catch (_) { return false; }
  };
  const hasRel = (link, value) => {
    try { return link.relList.contains(value); } catch (_) { return false; }
  };
  const isDeferredLink = (node) => isLink(node) &&
    node.hasAttribute('data-mwx-deferred-stylesheet') &&
    hasRel(node, 'preload') && String(node.getAttribute('as') || '').toLowerCase() === 'style';
  const resolvedHref = (link) => {
    try { return new URL(link.href, document.location.href).href; } catch (_) { return String(link.href || ''); }
  };
  const hostForHref = (href) => {
    try { return new URL(href, document.location.href).host || 'unknown'; } catch (_) { return 'unknown'; }
  };
  const isCurrentDeferredState = (link, state) => states.get(link) === state &&
    link.isConnected && isDeferredLink(link) && resolvedHref(link) === state.href &&
    link.getAttribute('data-mwx-deferred-stylesheet') === state.originalRel;

  const cancelWork = (state) => {
    window.clearTimeout(state.degradedTimer);
    window.clearTimeout(state.retryTimer);
    window.clearTimeout(state.activationTimer);
    state.degradedTimer = 0;
    state.retryTimer = 0;
    state.activationTimer = 0;
    if (state.cancelProbe) state.cancelProbe();
    state.cancelProbe = null;
  };
  const invalidateState = (link) => {
    const state = states.get(link);
    if (!state) return;
    cancelWork(state);
    state.settled = true;
    state.phase = 'cancelled';
    states.delete(link);
  };
  const markDegraded = (link, state, reason) => {
    if (state.degraded) return;
    state.degraded = true;
    const elapsedMS = Math.max(0, Math.round(performance.now() - state.startedAt));
    post('resource.remote-stylesheet.degraded', `host=${hostForHref(state.href)} reason=${reason} elapsedMs=${elapsedMS}`);
  };
  const ensureState = (link) => {
    if (!isDeferredLink(link)) return null;
    const href = resolvedHref(link);
    const originalRel = link.getAttribute('data-mwx-deferred-stylesheet') || 'stylesheet';
    const existing = states.get(link);
    if (existing && existing.href === href && existing.originalRel === originalRel) return existing;
    if (existing) invalidateState(link);
    const state = {
      authoredHref: href,
      href,
      originalRel,
      startedAt: performance.now(),
      phase: 'initial',
      settled: false,
      degraded: false,
      retryCount: 0,
      degradedTimer: 0,
      retryTimer: 0,
      activationTimer: 0,
      cancelProbe: null
    };
    states.set(link, state);
    state.degradedTimer = window.setTimeout(() => {
      if (isCurrentDeferredState(link, state) && !state.settled) markDegraded(link, state, 'timeout');
    }, degradedTimeoutMS);
    post('resource.remote-stylesheet.deferred', `host=${hostForHref(href)}`);
    return state;
  };

  const restoreAuthoredRel = (link, state) => {
    link.removeAttribute('data-mwx-deferred-stylesheet');
    link.removeAttribute('as');
    link.setAttribute('rel', state.originalRel);
  };
  const finishFinalFailure = (link, state, reason) => {
    if (states.get(link) !== state || state.settled) return;
    const wasDeferred = isCurrentDeferredState(link, state);
    cancelWork(state);
    state.settled = true;
    state.phase = 'failed';
    if (wasDeferred) restoreAuthoredRel(link, state);
    post(
      'resource.remote-stylesheet.failed',
      `host=${hostForHref(state.href)} reason=${reason} attempts=${state.retryCount} authoredRelRestored=${wasDeferred}`
    );
  };
  const finishApplied = (link, state) => {
    if (states.get(link) !== state || state.settled) return;
    cancelWork(state);
    state.settled = true;
    state.phase = 'applied';
    const elapsedMS = Math.max(0, Math.round(performance.now() - state.startedAt));
    post(
      state.degraded ? 'resource.remote-stylesheet.recovered' : 'resource.remote-stylesheet.activated',
      `host=${hostForHref(state.href)} elapsedMs=${elapsedMS} attempts=${state.retryCount} rel=${String(link.rel || '')} applied=true`
    );
  };
  const beginActivation = (link, state) => {
    if (!isCurrentDeferredState(link, state) || state.settled) return;
    cancelWork(state);
    state.phase = 'activating';
    restoreAuthoredRel(link, state);
    const startedAt = performance.now();
    const check = () => {
      if (states.get(link) !== state || state.settled) return;
      if (!link.isConnected || resolvedHref(link) !== state.href || !hasRel(link, 'stylesheet')) {
        invalidateState(link);
        return;
      }
      if (link.sheet) {
        finishApplied(link, state);
        return;
      }
      if ((performance.now() - startedAt) >= activationTimeoutMS) {
        finishFinalFailure(link, state, 'activation_timeout');
        return;
      }
      state.activationTimer = window.setTimeout(check, 50);
    };
    check();
  };

  const copyFetchAttributes = (source, destination) => {
    ['crossorigin', 'integrity', 'referrerpolicy', 'fetchpriority', 'type', 'nonce'].forEach((name) => {
      if (source.hasAttribute(name)) destination.setAttribute(name, source.getAttribute(name) || '');
    });
  };
  const scheduleRetry = (link, state, reason) => {
    if (!isCurrentDeferredState(link, state) || state.settled) return;
    markDegraded(link, state, reason);
    if (state.retryCount >= maximumRetries) {
      finishFinalFailure(link, state, `retry_exhausted:${reason}`);
      return;
    }
    const attempt = state.retryCount + 1;
    const delayMS = Math.min(retryMaximumDelayMS, retryBaseDelayMS * (2 ** (attempt - 1)));
    state.phase = 'waiting-retry';
    post(
      'resource.remote-stylesheet.retry',
      `host=${hostForHref(state.href)} attempt=${attempt}/${maximumRetries} delayMs=${delayMS} reason=${reason}`
    );
    state.retryTimer = window.setTimeout(() => startRetry(link, state, attempt), delayMS);
  };
  const startRetry = (link, state, attempt) => {
    if (!isCurrentDeferredState(link, state) || state.settled || attempt !== state.retryCount + 1) return;
    state.retryCount = attempt;
    state.phase = 'retrying';
    const probe = document.createElement('link');
    const retryURL = new URL(state.authoredHref, document.location.href);
    retryURL.searchParams.set('__mwx_retry', `${attempt}_${Date.now()}`);
    probe.rel = 'preload';
    probe.as = 'style';
    probe.href = retryURL.href;
    probe.setAttribute('data-mwx-remote-stylesheet-probe', String(attempt));
    copyFetchAttributes(link, probe);
    let completed = false;
    let requestTimer = 0;
    const cleanup = () => {
      if (completed) return false;
      completed = true;
      window.clearTimeout(requestTimer);
      probe.removeEventListener('load', loaded);
      probe.removeEventListener('error', failed);
      probe.remove();
      if (state.cancelProbe === cleanup) state.cancelProbe = null;
      return true;
    };
    const loaded = () => {
      const loadedHref = resolvedHref(probe);
      if (!cleanup() || !isCurrentDeferredState(link, state)) return;
      link.setAttribute('href', loadedHref);
      state.href = resolvedHref(link);
      beginActivation(link, state);
    };
    const failed = () => {
      if (!cleanup() || !isCurrentDeferredState(link, state)) return;
      scheduleRetry(link, state, 'retry_error');
    };
    state.cancelProbe = cleanup;
    probe.addEventListener('load', loaded);
    probe.addEventListener('error', failed);
    requestTimer = window.setTimeout(() => {
      if (!cleanup() || !isCurrentDeferredState(link, state)) return;
      scheduleRetry(link, state, 'retry_timeout');
    }, retryRequestTimeoutMS);
    (document.head || document.documentElement).appendChild(probe);
  };
  const finishPreload = (link, succeeded) => {
    if (!isDeferredLink(link)) return;
    const state = ensureState(link);
    if (!state || state.settled || state.phase === 'activating') return;
    if (succeeded) {
      beginActivation(link, state);
    } else if (state.phase === 'initial') {
      window.clearTimeout(state.degradedTimer);
      scheduleRetry(link, state, 'preload_error');
    }
  };

  const queueImportRecovery = (href) => {
    const existing = importRecoveryLinks.get(href);
    if (existing && existing.isConnected) return;
    if (existing) importRecoveryLinks.delete(href);
    const link = document.createElement('link');
    link.rel = 'preload';
    link.as = 'style';
    link.href = href;
    link.setAttribute('data-mwx-deferred-stylesheet', 'stylesheet');
    link.setAttribute('data-mwx-css-import-recovery', '');
    importRecoveryLinks.set(href, link);
    (document.head || document.documentElement).appendChild(link);
  };
  const scanStyleSheets = () => {
    styleSheetScanTimer = 0;
    const visited = new Set();
    const importRuleType = typeof CSSRule === 'undefined' ? 3 : CSSRule.IMPORT_RULE;
    const scanRules = (rules) => Array.from(rules || []).forEach((rule) => {
      try {
        if (rule.type === importRuleType) {
          const href = new URL(rule.href, document.location.href);
          const media = String(rule.media && rule.media.mediaText || '').toLowerCase().replace(/\s+/g, ' ').trim();
          if (href.host === 'fonts.googleapis.com' && /(^|,)\s*not all\s*(,|$)/.test(media)) {
            queueImportRecovery(href.href);
          }
        }
        if (rule.styleSheet) scanSheet(rule.styleSheet);
        if (rule.cssRules) scanRules(rule.cssRules);
      } catch (_) {}
    });
    const scanSheet = (styleSheet) => {
      if (!styleSheet || visited.has(styleSheet)) return;
      visited.add(styleSheet);
      try { scanRules(styleSheet.cssRules); } catch (_) {}
    };
    Array.from(document.styleSheets || []).forEach(scanSheet);
    try { Array.from(document.adoptedStyleSheets || []).forEach(scanSheet); } catch (_) {}
  };
  const scheduleStyleSheetScan = () => {
    if (styleSheetScanTimer) return;
    styleSheetScanTimer = window.setTimeout(scanStyleSheets, 0);
  };
  const isLocalStyleSheetLink = (node) => {
    if (!isLink(node) || !hasRel(node, 'stylesheet')) return false;
    try {
      const target = new URL(node.href, document.location.href);
      const page = new URL(document.location.href);
      return target.protocol === page.protocol && target.host === page.host;
    } catch (_) { return false; }
  };
  const nodeNameOf = (node) => {
    try { return String(node && node.nodeName ? node.nodeName : '').toUpperCase(); } catch (_) { return ''; }
  };
  const observeAddedTree = (root) => {
    // 逐节点入口先做廉价 nodeName 判断，只有 LINK/STYLE 才进入 URL 构造。
    const nodeName = nodeNameOf(root);
    if (nodeName === 'LINK') {
      if (isDeferredLink(root)) ensureState(root);
      if (isLocalStyleSheetLink(root)) scheduleStyleSheetScan();
    } else if (nodeName === 'STYLE') {
      scheduleStyleSheetScan();
    }
    if (root && typeof root.querySelectorAll === 'function') {
      root.querySelectorAll('link[data-mwx-deferred-stylesheet]').forEach(ensureState);
      if (root.querySelector('style,link[rel~="stylesheet"]')) scheduleStyleSheetScan();
    }
  };
  const observeRemovedTree = (root) => {
    if (isLink(root)) {
      invalidateState(root);
      if (root.hasAttribute('data-mwx-css-import-recovery')) scheduleStyleSheetScan();
    }
    if (!root || typeof root.querySelector !== 'function') return;
    // removed 子树只有确实含 <link> 时才逐节点作废：批量 DOM 重建时不再对
    // 每棵移除子树跑全树 querySelectorAll('link')。
    if (!root.querySelector('link')) return;
    root.querySelectorAll('link').forEach(invalidateState);
  };

  document.addEventListener('load', (event) => {
    if (isDeferredLink(event.target)) finishPreload(event.target, true);
    else if (isLocalStyleSheetLink(event.target)) scheduleStyleSheetScan();
  }, true);
  document.addEventListener('error', (event) => finishPreload(event.target, false), true);
  try {
    const observer = new MutationObserver((records) => {
      records.forEach((record) => {
        if (record.type === 'attributes') {
          if (isDeferredLink(record.target)) {
            ensureState(record.target);
          } else {
            const state = states.get(record.target);
            const isExpectedActivation = state && state.phase === 'activating' &&
              record.target.isConnected && resolvedHref(record.target) === state.href &&
              hasRel(record.target, 'stylesheet');
            if (!isExpectedActivation) invalidateState(record.target);
          }
        } else {
          record.removedNodes.forEach(observeRemovedTree);
          record.addedNodes.forEach(observeAddedTree);
        }
      });
    });
    observer.observe(document, {
      attributes: true,
      attributeFilter: ['href', 'rel', 'as', 'data-mwx-deferred-stylesheet'],
      childList: true,
      subtree: true
    });
    observeAddedTree(document);
  } catch (_) {}
  document.addEventListener('DOMContentLoaded', scheduleStyleSheetScan, { once: true });
})();
"""#
