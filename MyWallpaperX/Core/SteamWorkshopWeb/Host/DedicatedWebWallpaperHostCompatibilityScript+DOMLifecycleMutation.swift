let webCompatibilityScriptDOMLifecycleMutation = #"""
    const installWallpaperShadowObserver = (() => {
      const observedShadowRoots = new WeakSet();
      return (root) => {
        if (!root || observedShadowRoots.has(root)) return;
        observedShadowRoots.add(root);
        attachWallpaperMediaNodesFromRoot(root);
        try {
          const observer = new MutationObserver((mutations) => {
            let shouldRefresh = false;
            for (const mutation of mutations) {
              if (mutation.type === 'childList') {
                mutation.addedNodes.forEach((node) => {
                  attachWallpaperMediaNodesFromRoot(node);
                  if (node && node.nodeType === Node.ELEMENT_NODE) {
                    wallpaperEnsureHostScaffold.install(node);
                  }
                  shouldRefresh = true;
                });
                if (mutation.removedNodes.length > 0) {
                  shouldRefresh = true;
                }
              } else if (mutation.type === 'attributes') {
                shouldRefresh = true;
              }
            }
            if (shouldRefresh) {
              wallpaperRefreshMediaState();
            }
          });
          observer.observe(root, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src', 'poster', 'data-thumbnail']
          });
        } catch (_) {}
      };
    })();
    // window 级 holder：attachShadow 包装器已上移到 MediaObservers 段顶部的
    // document-start 顶层补丁区（F01 收尾），页面解析期（DCL 之前）创建的
    // shadow root 经它回到本作用域的观察器；包装器只读 window 属性，不在
    // 顶层直接引用本回调作用域标识符，避免解析期调用命中 TDZ。
    window.__mwxInstallWallpaperShadowObserver = installWallpaperShadowObserver;
    const mediaNodes = wallpaperImmediateMediaNodes();
    wallpaperEnsureHostScaffold.install(document);
    mediaNodes.forEach(attachWallpaperMediaNode);
    wallpaperRefreshMediaState();
    wallpaperScheduleDeferredDOMBootstrap();
    const wallpaperScheduleLifecycleRefresh = (() => {
      let scheduled = false;
      return () => {
        if (scheduled) return;
        scheduled = true;
        const flush = () => {
          scheduled = false;
          wallpaperRefreshMediaState();
        };
        if (typeof window.requestAnimationFrame === 'function') {
          window.requestAnimationFrame(flush);
        } else {
          window.setTimeout(flush, 16);
        }
      };
    })();
    const wallpaperAutoRegisterInteractiveRegions = () => {
      try {
        if (typeof window.__myWallpaperRegisterInteractiveRegions !== 'function') return;
        const rootWidth = Math.max(window.innerWidth || 0, 1);
        const rootHeight = Math.max(window.innerHeight || 0, 1);
        const selector = [
          'a[href]',
          'button',
          '[role="button"]',
          '[onclick]',
          '[draggable="true"]',
          'input:not([type="hidden"])',
          'select',
          'textarea',
          'canvas'
        ].join(',');
        const candidates = Array.from(document.querySelectorAll(selector)).slice(0, 24);
        const regions = candidates.map((element, index) => {
          if (!element || typeof element.getBoundingClientRect !== 'function') return null;
          const rect = element.getBoundingClientRect();
          if (!rect || rect.width < 12 || rect.height < 12) return null;
          if (rect.right <= 0 || rect.bottom <= 0 || rect.left >= rootWidth || rect.top >= rootHeight) return null;
          const style = window.getComputedStyle ? window.getComputedStyle(element) : null;
          if (style && (style.display === 'none' || style.visibility === 'hidden' || style.pointerEvents === 'none')) return null;
          const left = Math.max(0, Math.min(rootWidth, rect.left));
          const top = Math.max(0, Math.min(rootHeight, rect.top));
          const right = Math.max(0, Math.min(rootWidth, rect.right));
          const bottom = Math.max(0, Math.min(rootHeight, rect.bottom));
          const width = Math.max(0, right - left);
          const height = Math.max(0, bottom - top);
          if (width < 12 || height < 12) return null;
          const tagName = element.tagName ? String(element.tagName).toLowerCase() : 'node';
          const role = element.getAttribute ? String(element.getAttribute('role') || '') : '';
          const draggable = element.getAttribute ? String(element.getAttribute('draggable') || '') === 'true' : false;
          const allowsDrag = draggable || tagName === 'canvas';
          return {
            id: `${tagName || 'node'}-${role || 'default'}-${index + 1}`,
            x: left / rootWidth,
            y: top / rootHeight,
            width: width / rootWidth,
            height: height / rootHeight,
            allowsClick: true,
            allowsDrag
          };
        }).filter(Boolean);
        const signature = regions.map((region) => {
          return [region.id, region.x.toFixed(4), region.y.toFixed(4), region.width.toFixed(4), region.height.toFixed(4), region.allowsDrag ? 1 : 0].join(':');
        }).join('|');
        const currentState = window.__myWallpaperInteractiveRegionState || (window.__myWallpaperInteractiveRegionState = { lastSignature: '', lastAutoRegisterAt: 0 });
        if (signature === currentState.lastSignature) return;
        window.__myWallpaperRegisterInteractiveRegions({
          source: 'dom-auto',
          regions
        });
      } catch (error) {
        hostLogger.post('interactive-regions.auto.error', error && error.message ? error.message : error);
      }
    };
    const wallpaperScheduleInteractiveRegionRefresh = (() => {
      let scheduled = false;
      return () => {
        if (scheduled) return;
        scheduled = true;
        const flush = () => {
          scheduled = false;
          wallpaperAutoRegisterInteractiveRegions();
        };
        if (typeof window.requestAnimationFrame === 'function') {
          window.requestAnimationFrame(flush);
        } else {
          window.setTimeout(flush, 16);
        }
      };
    })();
    const mediaMutationObserver = new MutationObserver((mutations) => {
      let shouldRefresh = false;
      for (const mutation of mutations) {
        if (mutation.type === 'childList') {
          mutation.addedNodes.forEach((node) => {
            attachWallpaperMediaNodesFromRoot(node);
            if (node && node.nodeType === Node.ELEMENT_NODE) {
              wallpaperEnsureHostScaffold.install(node);
            }
            shouldRefresh = true;
          });
          if (mutation.removedNodes.length > 0) {
            shouldRefresh = true;
          }
        } else if (mutation.type === 'attributes' && mutation.target) {
          const target = mutation.target;
          if (target.matches && target.matches('audio,video')) {
            attachWallpaperMediaNode(target);
            shouldRefresh = true;
          }
          if (target.tagName && String(target.tagName).toLowerCase() === 'source') {
            const parentMediaNode = target.parentElement;
            if (parentMediaNode && parentMediaNode.matches && parentMediaNode.matches('audio,video')) {
              attachWallpaperMediaNode(parentMediaNode);
              shouldRefresh = true;
            }
          }
        }
      }
      if (shouldRefresh) {
        wallpaperScheduleLifecycleRefresh();
        wallpaperScheduleInteractiveRegionRefresh();
      }
    });
    mediaMutationObserver.observe(document.documentElement || document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['src', 'poster', 'data-thumbnail']
    });
    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
        });
      });
    } else {
      window.setTimeout(() => {
      }, 32);
    }
    window.setInterval(() => {
      wallpaperScheduleLifecycleRefresh();
      wallpaperScheduleInteractiveRegionRefresh();
    }, 8000);
    document.addEventListener('visibilitychange', () => {
      wallpaperScheduleLifecycleRefresh();
      wallpaperScheduleInteractiveRegionRefresh();
    });
    window.addEventListener('resize', () => {
      wallpaperScheduleLifecycleRefresh();
      wallpaperScheduleInteractiveRegionRefresh();
    });
"""#
