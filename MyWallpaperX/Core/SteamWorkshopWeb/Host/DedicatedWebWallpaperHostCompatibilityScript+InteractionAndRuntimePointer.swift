let webCompatibilityScriptInteractionAndRuntimePointer = #"""
  window.__myWallpaperState = window.__myWallpaperState || { captureTarget: null, captureButtons: 0, hoverTarget: null, hoverChain: [] };
  window.__myWallpaperEnsureSyntheticHoverStyles = function() {
    try {
      if (document.getElementById('__mwx-synthetic-hover-style')) return;
      if (window.__mwxSyntheticHoverStyleLoading === true) return;
      const rules = [];
      const appendSyntheticHoverStyle = (nextRules) => {
        try {
          if (!Array.isArray(nextRules) || nextRules.length === 0 || document.getElementById('__mwx-synthetic-hover-style')) return false;
          const style = document.createElement('style');
          style.id = '__mwx-synthetic-hover-style';
          style.textContent = nextRules.join('\n');
          (document.head || document.documentElement || document.body).appendChild(style);
          try { hostLogger.post('pointer.hoverStyle.ready', `rules=${nextRules.length}`); } catch (_) {}
          return true;
        } catch (_) {
          return false;
        }
      };
      const inverseHoverDeclarations = function(cssText) {
        const parts = [];
        const text = String(cssText || '');
        if (/(^|;)\s*display\s*:\s*none\s*(!important)?\s*(;|$)/i.test(text)) {
          parts.push('display: revert !important');
        }
        if (/(^|;)\s*visibility\s*:\s*(hidden|collapse)\s*(!important)?\s*(;|$)/i.test(text)) {
          parts.push('visibility: visible !important');
        }
        if (/(^|;)\s*opacity\s*:\s*0(?:\.0+)?\s*(!important)?\s*(;|$)/i.test(text)) {
          parts.push('opacity: revert !important');
        }
        return parts.join('; ');
      };
      const appendSyntheticRule = function(targetRules, selectorText, cssText) {
        const selector = String(selectorText || '');
        const body = String(cssText || '').trim();
        if (!selector.includes(':hover') || !body) return;
        const syntheticSelector = selector.replace(/:hover\b/g, '.__mwx-hover');
        if (syntheticSelector !== selector) {
          targetRules.push(`${syntheticSelector} { ${body} }`);
        }
        if (selector.includes(':not(:hover)')) {
          const inverseSelector = selector.replace(/:not\(:hover\)/g, '.__mwx-hover');
          const inverseBody = inverseHoverDeclarations(body);
          if (inverseSelector !== selector && inverseBody) {
            targetRules.push(`${inverseSelector} { ${inverseBody}; }`);
          }
        }
      };
      const collectRules = (ruleList) => {
        for (const rule of Array.from(ruleList || [])) {
          try {
            if (rule.cssRules) {
              collectRules(rule.cssRules);
              continue;
            }
            const selectorText = String(rule.selectorText || '');
            if (!selectorText.includes(':hover')) continue;
            if (rule.style && rule.style.cssText) {
              appendSyntheticRule(rules, selectorText, rule.style.cssText);
            }
          } catch (_) {}
        }
      };
      for (const sheet of Array.from(document.styleSheets || [])) {
        try { collectRules(sheet.cssRules); } catch (_) {}
      }
      if (appendSyntheticHoverStyle(rules)) return;
      const stylesheetLinks = Array.from(document.querySelectorAll('link[rel~="stylesheet"][href]'));
      if (stylesheetLinks.length === 0 || typeof fetch !== 'function') return;
      window.__mwxSyntheticHoverStyleLoading = true;
      Promise.all(stylesheetLinks.map((link) => {
        try {
          return fetch(link.href).then((response) => response.ok ? response.text() : '');
        } catch (_) {
          return Promise.resolve('');
        }
      })).then((texts) => {
        const fetchedRules = [];
        const hoverRulePattern = /([^{}]+:hover[^{}]*)\{([^{}]*)\}/g;
        for (const text of texts) {
          let match = null;
          while ((match = hoverRulePattern.exec(String(text || ''))) !== null) {
            const selector = String(match[1] || '').trim();
            const body = String(match[2] || '').trim();
            if (!selector || !body) continue;
            appendSyntheticRule(fetchedRules, selector, body);
          }
        }
        appendSyntheticHoverStyle(fetchedRules);
      }).catch((error) => {
        try { hostLogger.post('pointer.hoverStyle.error', error && error.message ? error.message : error); } catch (_) {}
      }).finally(() => {
        window.__mwxSyntheticHoverStyleLoading = false;
      });
    } catch (error) {
      try { hostLogger.post('pointer.hoverStyle.error', error && error.message ? error.message : error); } catch (_) {}
    }
  };
  window.__myWallpaperSetSyntheticHoverChain = function(nextTarget) {
    const wallpaperState = window.__myWallpaperState || (window.__myWallpaperState = { captureTarget: null, captureButtons: 0, hoverTarget: null, hoverChain: [] });
    const previousChain = Array.isArray(wallpaperState.hoverChain) ? wallpaperState.hoverChain : [];
    const nextChain = [];
    let node = nextTarget && nextTarget.nodeType === 1 ? nextTarget : null;
    while (node) {
      nextChain.push(node);
      if (node === document.documentElement) break;
      node = node.parentElement;
    }
    const nextSet = new Set(nextChain);
    previousChain.forEach((element) => {
      try {
        if (element && element.classList && !nextSet.has(element)) {
          element.classList.remove('__mwx-hover');
        }
      } catch (_) {}
    });
    nextChain.forEach((element) => {
      try {
        if (element && element.classList) {
          element.classList.add('__mwx-hover');
        }
      } catch (_) {}
    });
    wallpaperState.hoverChain = nextChain;
  };
  window.__myWallpaperUpdateHoverTarget = function(nextTarget, mouseEventInit) {
    const wallpaperState = window.__myWallpaperState || (window.__myWallpaperState = { captureTarget: null, captureButtons: 0, hoverTarget: null, hoverChain: [] });
    if (!Array.isArray(wallpaperState.hoverChain)) {
      wallpaperState.hoverChain = [];
    }
    const previousTarget = wallpaperState.hoverTarget;
    if (previousTarget === nextTarget) {
      return;
    }
    window.__myWallpaperEnsureSyntheticHoverStyles();
    window.__myWallpaperSetSyntheticHoverChain(nextTarget || null);
    if (previousTarget && typeof MouseEvent === 'function') {
      try {
        previousTarget.dispatchEvent(new MouseEvent('mouseout', { ...mouseEventInit, bubbles: true, cancelable: true, composed: true, relatedTarget: nextTarget || null }));
        previousTarget.dispatchEvent(new MouseEvent('mouseleave', { ...mouseEventInit, bubbles: false, cancelable: false, composed: true, relatedTarget: nextTarget || null }));
      } catch (_) {}
    }
    wallpaperState.hoverTarget = nextTarget || null;
    if (nextTarget && typeof MouseEvent === 'function') {
      try {
        nextTarget.dispatchEvent(new MouseEvent('mouseover', { ...mouseEventInit, bubbles: true, cancelable: true, composed: true, relatedTarget: previousTarget || null }));
        nextTarget.dispatchEvent(new MouseEvent('mouseenter', { ...mouseEventInit, bubbles: false, cancelable: false, composed: true, relatedTarget: previousTarget || null }));
      } catch (_) {}
    }
  };
  const mouseEventInitBase = function(clientX, clientY, buttonValue, buttonsValue) {
    return {
      bubbles: true,
      cancelable: true,
      composed: true,
      clientX,
      clientY,
      button: buttonValue,
      buttons: buttonsValue,
      view: window
    };
  };
  const pointerBootTime = (() => {
    try { return performance.now(); } catch (_) { return Date.now(); }
  })();
  const buttonedPointerTypes = new Set(['pointerdown', 'pointerup', 'pointercancel']);
  const readyInteractiveSelector = [
    'canvas',
    'video',
    'iframe',
    'object',
    'embed',
    'svg',
    'img',
    'button',
    'input',
    'select',
    'textarea',
    'a[href]',
    '[role="button"]',
    '[role="link"]',
    '[onclick]',
    '[tabindex]'
  ].join(',');
  const isVisibleInteractiveContent = function(element) {
    try {
      if (!element || typeof element.getBoundingClientRect !== 'function') return false;
      const rect = element.getBoundingClientRect();
      if (rect.width <= 1 || rect.height <= 1) return false;
      const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
      if (style && (style.display === 'none' || style.visibility === 'hidden' || style.pointerEvents === 'none')) return false;
      return true;
    } catch (_) {
      return false;
    }
  };
  const shouldDeferButtonedPointerEvent = function(type, target) {
    try {
      if (!buttonedPointerTypes.has(String(type))) return false;
      const now = typeof performance !== 'undefined' && typeof performance.now === 'function'
        ? performance.now()
        : Date.now();
      if (now - pointerBootTime > 6000) return false;
      if (!target || target.nodeType !== 1 || typeof target.getBoundingClientRect !== 'function') return false;
      if (target.matches && target.matches(readyInteractiveSelector)) return false;
      const rect = target.getBoundingClientRect();
      const viewportArea = Math.max(1, (window.innerWidth || 1) * (window.innerHeight || 1));
      if ((rect.width * rect.height) < viewportArea * 0.25) return false;
      const readyDescendant = target.querySelector && Array.from(target.querySelectorAll(readyInteractiveSelector)).some(isVisibleInteractiveContent);
      if (readyDescendant) return false;
      return true;
    } catch (_) {
      return false;
    }
  };
  const enrichMouseLikeEvent = function(event, target, clientX, clientY) {
    if (!event || !target || typeof Object.defineProperty !== 'function') {
      return event;
    }
    try {
      const rect = typeof target.getBoundingClientRect === 'function'
        ? target.getBoundingClientRect()
        : { left: 0, top: 0 };
      const offsetX = clientX - Number(rect.left || 0);
      const offsetY = clientY - Number(rect.top || 0);
      const pageX = clientX + (window.scrollX || 0);
      const pageY = clientY + (window.scrollY || 0);
      const define = (name, value) => {
        try {
          Object.defineProperty(event, name, {
            configurable: true,
            enumerable: true,
            get() { return value; }
          });
        } catch (_) {}
      };
      define('offsetX', offsetX);
      define('offsetY', offsetY);
      define('pageX', pageX);
      define('pageY', pageY);
      define('x', clientX);
      define('y', clientY);
    } catch (_) {}
    return event;
  };
  const wallpaperDragPixelThreshold = 4;
  const wallpaperDragEventDataTransfer = () => {
    try {
      return typeof DataTransfer === 'function' ? new DataTransfer() : null;
    } catch (_) {
      return null;
    }
  };
  const wallpaperDragEventInit = (clientX, clientY, dataTransfer) => {
    const init = { bubbles: true, cancelable: true, composed: true, clientX, clientY };
    if (dataTransfer) {
      init.dataTransfer = dataTransfer;
    }
    return init;
  };
  // 拖拽起点判定复用 DOMLifecycleMutation 的交互区域分类先例：
  // 最近的 draggable="true" 祖先或 canvas 才算可拖拽。
  const wallpaperIsDragCapableTarget = (target) => {
    let node = target && target.nodeType === 1 ? target : null;
    while (node) {
      try {
        if (node.getAttribute && String(node.getAttribute('draggable') || '') === 'true') return true;
        if (node.tagName && String(node.tagName).toLowerCase() === 'canvas') return true;
      } catch (_) {}
      node = node.parentElement;
    }
    return false;
  };
  // 指针推送的坐标换算：宿主推送用的是父 frame 视口归一化坐标，子 frame 需要
  // 换算成自身视口的归一化坐标（用 frameElement 在父视口内的位置与尺寸）。
  // 指针落在子 frame 之外时 active 归 false，避免子 frame 的 hover 状态挂住。
  const wallpaperChildPointerArgs = (frame, active, normalizedX, normalizedY, buttons) => {
    try {
      const rect = frame.getBoundingClientRect();
      if (!(rect.width > 0) || !(rect.height > 0)) return null;
      const parentWidth = Math.max(window.innerWidth || 0, 1);
      const parentHeight = Math.max(window.innerHeight || 0, 1);
      const pointX = Number(normalizedX || 0) * parentWidth;
      const pointY = Number(normalizedY || 0) * parentHeight;
      const insideFrame =
        pointX >= rect.left && pointX <= rect.right && pointY >= rect.top && pointY <= rect.bottom;
      return [
        Boolean(active) && insideFrame,
        Math.max(0, Math.min(1, (pointX - rect.left) / rect.width)),
        Math.max(0, Math.min(1, (pointY - rect.top) / rect.height)),
        Number(buttons || 0)
      ];
    } catch (_) {
      return null;
    }
  };
  window.__myWallpaperDispatchMouseEvent = function(type, normalizedX, normalizedY, button, buttons, pointerId) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      const buttonValue = Number(button || 0);
      const buttonsValue = Number(buttons || 0);
      const pointerIdValue = Math.max(1, Number(pointerId || 1));
      const wallpaperState = window.__myWallpaperState || (window.__myWallpaperState = { captureTarget: null, captureButtons: 0 });
      let target = wallpaperState.captureTarget || document.elementFromPoint(clientX, clientY) || document.body || document.documentElement;
      if (!target) return;
      window.__myWallpaperUpdateHoverTarget(target, mouseEventInitBase(clientX, clientY, buttonValue, buttonsValue));
      if (shouldDeferButtonedPointerEvent(type, target)) {
        hostLogger.post('pointer.defer', `${String(type)} target=${target.tagName || 'unknown'} id=${target.id || ''}`.trim());
        if (String(type) === 'pointerup' || String(type) === 'pointercancel' || buttonsValue === 0) {
          wallpaperState.captureTarget = null;
          wallpaperState.captureButtons = 0;
          wallpaperState.dragArmed = false;
          wallpaperState.dragging = false;
          wallpaperState.dragDataTransfer = null;
        }
        return;
      }
      const pointerLikeTypes = new Set(['pointermove', 'pointerdown', 'pointerup', 'pointercancel']);
      const pointerToMouseType = { 'pointerdown': 'mousedown', 'pointerup': 'mouseup', 'pointermove': 'mousemove', 'pointercancel': 'mouseleave' };
      const mouseEventInit = mouseEventInitBase(clientX, clientY, buttonValue, buttonsValue);
      let pointerEvent = null;
      if (pointerLikeTypes.has(String(type)) && typeof PointerEvent === 'function') {
        pointerEvent = new PointerEvent(String(type), {
          ...mouseEventInit,
          pointerId: pointerIdValue,
          pointerType: 'mouse',
          isPrimary: true
        });
      } else if (typeof MouseEvent === 'function') {
        pointerEvent = new MouseEvent(String(type), mouseEventInit);
      }
      if (pointerEvent) {
        enrichMouseLikeEvent(pointerEvent, target, clientX, clientY);
        target.dispatchEvent(pointerEvent);
      }
      if (String(type) === 'pointerdown' && buttonsValue !== 0) {
        wallpaperState.captureTarget = target;
        wallpaperState.captureButtons = buttonsValue;
        if (target && typeof target.setPointerCapture === 'function' && pointerEvent && typeof pointerEvent.pointerId === 'number') {
          try { target.setPointerCapture(pointerEvent.pointerId); } catch (_) {}
        }
        // 拖拽候选先武装、不立即派发：位移超过阈值才把候选变成真实拖拽。
        wallpaperState.dragging = false;
        wallpaperState.dragArmed = typeof DragEvent === 'function' && wallpaperIsDragCapableTarget(target);
        wallpaperState.dragStartX = clientX;
        wallpaperState.dragStartY = clientY;
        wallpaperState.dragDataTransfer = null;
      }
      const mouseTypeName = pointerToMouseType[String(type)];
      if (String(type) === 'pointermove' && wallpaperState.captureTarget && typeof DragEvent === 'function') {
        if (wallpaperState.dragArmed === true && wallpaperState.dragging !== true) {
          const deltaX = clientX - Number(wallpaperState.dragStartX || 0);
          const deltaY = clientY - Number(wallpaperState.dragStartY || 0);
          if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) > wallpaperDragPixelThreshold) {
            wallpaperState.dragging = true;
            wallpaperState.dragDataTransfer = wallpaperDragEventDataTransfer();
            try {
              wallpaperState.captureTarget.dispatchEvent(new DragEvent(
                'dragstart',
                wallpaperDragEventInit(clientX, clientY, wallpaperState.dragDataTransfer)
              ));
            } catch (_) {}
          }
        }
        if (wallpaperState.dragging === true) {
          try {
            // 同一次拖拽共用同一个 dataTransfer：dragstart 里 setData 的数据
            // 在 dragover/drag/drop 监听器中可读。
            const dragDataTransfer = wallpaperState.dragDataTransfer;
            wallpaperState.captureTarget.dispatchEvent(new DragEvent(
              'dragover',
              wallpaperDragEventInit(clientX, clientY, dragDataTransfer)
            ));
            wallpaperState.captureTarget.dispatchEvent(new DragEvent(
              'drag',
              wallpaperDragEventInit(clientX, clientY, dragDataTransfer)
            ));
          } catch (_) {}
        }
      }
      if (mouseTypeName && typeof MouseEvent === 'function') {
        const mouseEvent = enrichMouseLikeEvent(new MouseEvent(mouseTypeName, mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(mouseEvent);
      }
      if (String(type) === 'pointerup' && buttonValue === 0 && typeof MouseEvent === 'function') {
        const clickEvent = enrichMouseLikeEvent(new MouseEvent('click', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(clickEvent);
      }
      if ((String(type) === 'pointerup' || String(type) === 'pointercancel' || buttonsValue === 0) &&
          wallpaperState.captureTarget && wallpaperState.dragging === true && typeof DragEvent === 'function') {
        try {
          const dragDataTransfer = wallpaperState.dragDataTransfer;
          wallpaperState.captureTarget.dispatchEvent(new DragEvent(
            'dragend',
            wallpaperDragEventInit(clientX, clientY, dragDataTransfer)
          ));
          if (String(type) === 'pointerup') {
            wallpaperState.captureTarget.dispatchEvent(new DragEvent(
              'drop',
              wallpaperDragEventInit(clientX, clientY, dragDataTransfer)
            ));
          }
        } catch (_) {}
      }
      if (String(type) === 'pointerup' || String(type) === 'pointercancel' || buttonsValue === 0) {
        if (target && typeof target.releasePointerCapture === 'function' && pointerEvent && typeof pointerEvent.pointerId === 'number') {
          try { target.releasePointerCapture(pointerEvent.pointerId); } catch (_) {}
        }
        wallpaperState.captureTarget = null;
        wallpaperState.captureButtons = 0;
        wallpaperState.dragArmed = false;
        wallpaperState.dragging = false;
        wallpaperState.dragDataTransfer = null;
      }
      if (String(type) === 'pointerup' && buttonValue === 1 && typeof MouseEvent === 'function') {
        const auxClickEvent = enrichMouseLikeEvent(new MouseEvent('auxclick', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(auxClickEvent);
      }
      if (String(type) === 'pointerup' && buttonValue === 2 && typeof MouseEvent === 'function') {
        const contextMenuEvent = enrichMouseLikeEvent(new MouseEvent('contextmenu', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(contextMenuEvent);
      }
      // 同源子 frame 按同一键位参数换算坐标后再派发：iframe 壁纸内部的元素
      // 才会收到真实的合成指针链。指针不在该子 frame 内时不合成派发（否则
      // 会在子 frame 边缘产生出框幻影事件），只有子 frame 自己仍在捕获指针
      // （拖拽续传）时才放行；换算不出的 frame 返回 null 跳过。
      wallpaperRelayHostPushToChildFrames('__myWallpaperDispatchMouseEvent', null, (frame) => {
        const childPointerArgs = wallpaperChildPointerArgs(frame, true, normalizedX, normalizedY, buttonsValue);
        if (!childPointerArgs) return null;
        if (childPointerArgs[0] !== true) {
          const childWindow = wallpaperSameOriginFrameWindow(frame);
          const childCaptureTarget = childWindow && childWindow.__myWallpaperState
            ? childWindow.__myWallpaperState.captureTarget
            : null;
          if (!childCaptureTarget) return null;
        }
        return [type, childPointerArgs[1], childPointerArgs[2], button, buttons, pointerId];
      });
    } catch (error) {
      hostLogger.post('pointer.dispatch.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperDispatchWheelEvent = function(normalizedX, normalizedY, deltaX, deltaY, buttons) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      const target = document.elementFromPoint(clientX, clientY) || document.body || document.documentElement;
      if (!target || typeof WheelEvent !== 'function') return;
      const wheelEvent = new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        composed: true,
        clientX,
        clientY,
        deltaX: Number(deltaX || 0),
        deltaY: Number(deltaY || 0),
        buttons: Number(buttons || 0),
        view: window
      });
      target.dispatchEvent(wheelEvent);
    } catch (error) {
      hostLogger.post('wheel.dispatch.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperSetPassiveMouseState = function(active, normalizedX, normalizedY, buttons) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      window.wallpaperEngine_cursor = {
        x: clientX,
        y: clientY,
        normalizedX: safeX,
        normalizedY: safeY,
        buttons: Number(buttons || 0)
      };
      window.wallpaperEngine_mouseover = Boolean(active);
      if (!active) {
        window.__myWallpaperUpdateHoverTarget(null, mouseEventInitBase(clientX, clientY, 0, 0));
      }
      wallpaperRelayHostPushToChildFrames('__myWallpaperSetPassiveMouseState', null, (frame) => {
        return wallpaperChildPointerArgs(frame, active, normalizedX, normalizedY, buttons);
      });
    } catch (_) {}
  };
"""#
