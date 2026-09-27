let webCompatibilityScriptHostBridge = #"""
  window.__myWallpaperRegisterInteractiveRegions = function(payload) {
    try {
      const rawRegions = Array.isArray(payload && payload.regions) ? payload.regions : [];
      const safeRegions = rawRegions.map((region, index) => {
        const raw = region || {};
        const normalizeNumber = (value, fallback) => {
          const numeric = Number(value);
          if (!Number.isFinite(numeric)) return fallback;
          return Math.max(0, Math.min(1, numeric));
        };
        const width = normalizeNumber(raw.width, 0);
        const height = normalizeNumber(raw.height, 0);
        return {
          id: String(raw.id || `region-${index + 1}`),
          x: normalizeNumber(raw.x, 0),
          y: normalizeNumber(raw.y, 0),
          width,
          height,
          allowsClick: raw.allowsClick !== false,
          allowsDrag: raw.allowsDrag === true
        };
      }).filter((region) => region.width > 0 && region.height > 0);
      const messagePayload = {
        source: String((payload && payload.source) || 'page-script'),
        regions: safeRegions
      };
      try {
        window.webkit.messageHandlers.wallpaperHostInteractiveRegions.postMessage(messagePayload);
      } catch (error) {
        hostLogger.post('interactive-regions.post.error', error && error.message ? error.message : error);
      }
      try {
        window.dispatchEvent(new CustomEvent('wallpaper-interactive-regions-registered', { detail: messagePayload }));
      } catch (_) {}
      try {
        window.__myWallpaperInteractiveRegionState.lastSignature = safeRegions.map((region) => {
          return [region.id, region.x, region.y, region.width, region.height, region.allowsClick ? 1 : 0, region.allowsDrag ? 1 : 0].join(':');
        }).join('|');
        window.__myWallpaperInteractiveRegionState.lastAutoRegisterAt = Date.now();
      } catch (_) {}
    } catch (error) {
      hostLogger.post('interactive-regions.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperNormalizePropertyBag = function(properties) {
    const normalizedProperties = {};
    try {
      for (const [key, rawValue] of Object.entries(properties || {})) {
        if (rawValue && typeof rawValue === 'object' && Object.prototype.hasOwnProperty.call(rawValue, 'value')) {
          const boxedValue = Object.assign({}, rawValue);
          try {
            Object.defineProperty(boxedValue, 'valueOf', {
              configurable: true,
              enumerable: false,
              value: function() { return this.value; }
            });
            Object.defineProperty(boxedValue, 'toString', {
              configurable: true,
              enumerable: false,
              value: function() { return String(this.value); }
            });
          } catch (_) {}
          normalizedProperties[key] = boxedValue;
        } else {
          normalizedProperties[key] = rawValue;
        }
      }
      return normalizedProperties;
    } catch (_) {
      return properties || {};
    }
  };
  try {
    const arrayPrototype = Array.prototype;
    if (arrayPrototype.__mwxColorSplitPatched !== true) {
      const originalSplit = arrayPrototype.split;
      Object.defineProperty(arrayPrototype, 'split', {
        configurable: true,
        enumerable: false,
        value(separator) {
          if (this.length >= 3 && this.slice(0, 3).every((item) => Number.isFinite(Number(item)))) {
            return this.map((item) => String(item)).join(' ').split(separator);
          }
          if (typeof originalSplit === 'function') {
            return originalSplit.call(this, separator);
          }
          return String(this).split(separator);
        }
      });
      Object.defineProperty(arrayPrototype, '__mwxColorSplitPatched', {
        configurable: true,
        enumerable: false,
        value: true
      });
    }
  } catch (_) {}
  window.__myWallpaperStablePropertySignature = function(value) {
    try {
      const normalize = (input) => {
        if (Array.isArray(input)) return input.map(normalize);
        if (input && typeof input === 'object') {
          const output = {};
          for (const key of Object.keys(input).sort()) {
            const item = input[key];
            if (typeof item !== 'function') {
              output[key] = normalize(item);
            }
          }
          return output;
        }
        return input;
      };
      return JSON.stringify(normalize(value || {}));
    } catch (_) {
      try { return JSON.stringify(value || {}); } catch (_) { return ''; }
    }
  };
  const myWallpaperPropertyReplayState = window.__myWallpaperPropertyReplayState = window.__myWallpaperPropertyReplayState || {
    pendingProperties: null,
    pendingSignature: '',
    attempt: 0,
    timer: null,
    loadScheduled: false,
    reportedSkips: {}
  };
  const myWallpaperPropertyRetryDelays = [80, 140, 220, 340, 520, 780, 1100, 1400, 1800, 2200, 2600, 3000];
  const myWallpaperPropertyErrorMessage = function(error) {
    if (!error) return '';
    if (error && error.message) return String(error.message);
    try { return String(error); } catch (_) { return ''; }
  };
  const myWallpaperIsPropertyInitializationError = function(error) {
    const message = myWallpaperPropertyErrorMessage(error).toLowerCase();
    if (!message) return false;
    if (
      message.includes('audio.volume') ||
      message.includes('motionintervalmax') ||
      message.includes('.push') ||
      message.includes('push is not a function')
    ) {
      return false;
    }
    return message.includes('undefined is not an object') ||
      message.includes('null is not an object') ||
      message.includes('cannot read properties of undefined') ||
      message.includes('cannot read properties of null') ||
      message.includes('is undefined') ||
      message.includes('has no properties') ||
      message.includes('gl.canvas') ||
      message.includes('this.model.x');
  };
  const myWallpaperColorArrayCompatibleProperty = function(value) {
    try {
      if (!value || typeof value !== 'object' || typeof value.value !== 'string') return null;
      const components = value.value.trim().split(/\s+/).map((component) => Number(component));
      if ((components.length !== 3 && components.length !== 4) || !components.every(Number.isFinite)) return null;
      return Object.assign({}, value, { value: components });
    } catch (_) {
      return null;
    }
  };
  const myWallpaperColorArrayCompatibleBag = function(properties) {
    const compatibleProperties = {};
    const convertedKeys = [];
    for (const [key, value] of Object.entries(properties || {})) {
      const compatibleValue = value && value.type === 'color'
        ? myWallpaperColorArrayCompatibleProperty(value)
        : null;
      compatibleProperties[key] = compatibleValue || value;
      if (compatibleValue) convertedKeys.push(key);
    }
    return { properties: compatibleProperties, convertedKeys };
  };
  const myWallpaperIsColorArrayCompatibilityError = function(error) {
    const message = myWallpaperPropertyErrorMessage(error).toLowerCase();
    return message.includes('.push') || message.includes('push is not a function');
  };
  const myWallpaperInvokeUserPropertyCallback = function(listener, callback, properties) {
    let scheduledAsyncWork = false;
    const originalSetTimeout = window.setTimeout;
    const originalSetInterval = window.setInterval;
    const originalRequestAnimationFrame = window.requestAnimationFrame;
    try {
      window.setTimeout = function(...args) {
        scheduledAsyncWork = true;
        return originalSetTimeout.apply(this, args);
      };
      window.setInterval = function(...args) {
        scheduledAsyncWork = true;
        return originalSetInterval.apply(this, args);
      };
      if (typeof originalRequestAnimationFrame === 'function') {
        window.requestAnimationFrame = function(...args) {
          scheduledAsyncWork = true;
          return originalRequestAnimationFrame.apply(this, args);
        };
      }
    } catch (_) {}
    try {
      callback.call(listener, properties);
      return { completed: true, scheduledAsyncWork };
    } catch (error) {
      return { completed: false, error, scheduledAsyncWork };
    } finally {
      try { window.setTimeout = originalSetTimeout; } catch (_) {}
      try { window.setInterval = originalSetInterval; } catch (_) {}
      try { window.requestAnimationFrame = originalRequestAnimationFrame; } catch (_) {}
    }
  };
  const myWallpaperSchedulePendingPropertyApply = function(delayMS) {
    try {
      if (myWallpaperPropertyReplayState.timer !== null) return;
      myWallpaperPropertyReplayState.timer = window.setTimeout(() => {
        myWallpaperPropertyReplayState.timer = null;
        window.__myWallpaperRunAfterSettledFrames(window.__myWallpaperDrainPendingProperties);
      }, Math.max(0, Number(delayMS) || 0));
    } catch (_) {}
  };
  const myWallpaperDispatchResizeAfterPropertyError = function(reason) {
    try {
      window.__myWallpaperRunAfterSettledFrames(() => {
        try {
          window.dispatchEvent(new Event('resize'));
          hostLogger.post('properties.resize-after-script-failure', reason || 'script error');
        } catch (error) {
          hostLogger.post('properties.resize-after-script-failure.failed', myWallpaperPropertyErrorMessage(error) || error);
        }
      });
    } catch (_) {}
  };
  const myWallpaperReportSkippedProperty = function(signature, key, error) {
    try {
      const message = myWallpaperPropertyErrorMessage(error) || 'unknown error';
      const skipKey = [signature || '', key || '', message].join('|');
      const reported = myWallpaperPropertyReplayState.reportedSkips || {};
      if (reported[skipKey] === true) return;
      reported[skipKey] = true;
      myWallpaperPropertyReplayState.reportedSkips = reported;
      hostLogger.post('properties.skipped', `${key}: ${message}`);
    } catch (_) {}
  };
  const myWallpaperApplyPropertiesIndividually = function(properties, listener, callback, signature) {
    let appliedCount = 0;
    let skippedCount = 0;
    for (const [key, value] of Object.entries(properties || {})) {
      const singleProperty = {};
      singleProperty[key] = value;
      try {
        callback.call(listener, singleProperty);
        appliedCount += 1;
      } catch (error) {
        const compatibleValue = myWallpaperIsColorArrayCompatibilityError(error)
          ? myWallpaperColorArrayCompatibleProperty(value)
          : null;
        if (compatibleValue) {
          try {
            callback.call(listener, { [key]: compatibleValue });
            appliedCount += 1;
            hostLogger.post('properties.compat.color-array', key);
            continue;
          } catch (compatibleError) {
            error = compatibleError;
          }
        }
        skippedCount += 1;
        myWallpaperReportSkippedProperty(signature, key, error);
      }
    }
    return { appliedCount, skippedCount };
  };
  window.__myWallpaperDrainPendingProperties = function() {
    const state = myWallpaperPropertyReplayState;
    if (state.pendingProperties === null && !state.pendingSignature) {
      return;
    }
    const safeProperties = state.pendingProperties || {};
    const signature = state.pendingSignature || window.__myWallpaperStablePropertySignature(safeProperties);
    try {
      if (document.readyState !== 'complete') {
        if (state.loadScheduled !== true) {
          state.loadScheduled = true;
          window.addEventListener('load', () => {
            state.loadScheduled = false;
            myWallpaperSchedulePendingPropertyApply(0);
          }, { once: true });
        }
        return;
      }
    } catch (_) {}
    const hasUserPropertyListener = window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyUserProperties === 'function';
    if (!hasUserPropertyListener) {
      myWallpaperSchedulePendingPropertyApply(80);
      return;
    }
    const listener = window.wallpaperPropertyListener;
    const userPropertyCallback = listener.applyUserProperties;
    if (
      signature &&
      signature === window.__myWallpaperLastAppliedUserPropertySignature &&
      userPropertyCallback === window.__myWallpaperLastAppliedUserPropertyCallback
    ) {
      state.pendingProperties = null;
      state.pendingSignature = '';
      state.attempt = 0;
      return;
    }

    const applyResult = myWallpaperInvokeUserPropertyCallback(listener, userPropertyCallback, safeProperties);
    if (applyResult.completed === true) {
      window.__myWallpaperLastAppliedUserPropertySignature = signature;
      window.__myWallpaperLastAppliedUserPropertyCallback = userPropertyCallback;
      state.pendingProperties = null;
      state.pendingSignature = '';
      state.attempt = 0;
      hostLogger.post('properties.applied', `count=${Object.keys(safeProperties).length}`);
      window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', { detail: safeProperties }));
    } else {
      const error = applyResult.error;
      const isInitializationError = myWallpaperIsPropertyInitializationError(error);
      if (state.attempt === 0 && isInitializationError && applyResult.scheduledAsyncWork === true) {
        window.__myWallpaperLastAppliedUserPropertySignature = signature;
        window.__myWallpaperLastAppliedUserPropertyCallback = userPropertyCallback;
        state.pendingProperties = null;
        state.pendingSignature = '';
        state.attempt = 0;
        try {
          window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', {
            detail: safeProperties
          }));
        } catch (_) {}
        hostLogger.post('properties.deferred-side-effect', myWallpaperPropertyErrorMessage(error) || 'initialization error');
        return;
      }
      if (isInitializationError && state.attempt < myWallpaperPropertyRetryDelays.length) {
        const delay = myWallpaperPropertyRetryDelays[state.attempt] || 3000;
        state.attempt += 1;
        myWallpaperSchedulePendingPropertyApply(delay);
        return;
      }
      if (!isInitializationError) {
        if (myWallpaperIsColorArrayCompatibilityError(error)) {
          const compatibleBag = myWallpaperColorArrayCompatibleBag(safeProperties);
          const compatibleResult = myWallpaperInvokeUserPropertyCallback(
            listener,
            userPropertyCallback,
            compatibleBag.properties
          );
          for (const key of compatibleBag.convertedKeys) {
            hostLogger.post('properties.compat.color-array', key);
          }
          window.__myWallpaperLastAppliedUserPropertySignature = signature;
          window.__myWallpaperLastAppliedUserPropertyCallback = userPropertyCallback;
          state.pendingProperties = null;
          state.pendingSignature = '';
          state.attempt = 0;
          try {
            window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', {
              detail: safeProperties
            }));
          } catch (_) {}
          if (compatibleResult.completed === true) {
            hostLogger.post('properties.applied.compatible', `colors=${compatibleBag.convertedKeys.length}`);
          } else {
            const compatibleError = compatibleResult.error;
            const message = myWallpaperPropertyErrorMessage(compatibleError) || compatibleError;
            hostLogger.post('properties.error', message);
            myWallpaperDispatchResizeAfterPropertyError(message);
          }
          return;
        }
        window.__myWallpaperLastAppliedUserPropertySignature = signature;
        window.__myWallpaperLastAppliedUserPropertyCallback = userPropertyCallback;
        state.pendingProperties = null;
        state.pendingSignature = '';
        state.attempt = 0;
        try {
          window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', {
            detail: safeProperties
          }));
        } catch (_) {}
        const message = myWallpaperPropertyErrorMessage(error) || error;
        hostLogger.post('properties.error', message);
        myWallpaperDispatchResizeAfterPropertyError(message);
        return;
      }

      const isolatedResult = myWallpaperApplyPropertiesIndividually(
        safeProperties,
        listener,
        userPropertyCallback,
        signature
      );
      window.__myWallpaperLastAppliedUserPropertySignature = signature;
      window.__myWallpaperLastAppliedUserPropertyCallback = userPropertyCallback;
      state.pendingProperties = null;
      state.pendingSignature = '';
      state.attempt = 0;
      try {
        window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', {
          detail: safeProperties
        }));
      } catch (_) {}
      if (isolatedResult.skippedCount > 0) {
        hostLogger.post('properties.applied.partial', `applied=${isolatedResult.appliedCount} skipped=${isolatedResult.skippedCount}`);
      }
    }
  };
  window.__myWallpaperApplyProperties = function(properties) {
    const safeProperties = window.__myWallpaperNormalizePropertyBag(properties || {});
    window.__myWallpaperLastUserProperties = safeProperties;
    const signature = window.__myWallpaperStablePropertySignature(safeProperties);
    if (
      signature &&
      signature === window.__myWallpaperLastAppliedUserPropertySignature &&
      window.wallpaperPropertyListener &&
      typeof window.wallpaperPropertyListener.applyUserProperties === 'function' &&
      window.wallpaperPropertyListener.applyUserProperties === window.__myWallpaperLastAppliedUserPropertyCallback
    ) {
      return;
    }
    myWallpaperPropertyReplayState.pendingProperties = safeProperties;
    myWallpaperPropertyReplayState.pendingSignature = signature;
    myWallpaperPropertyReplayState.attempt = 0;
    myWallpaperSchedulePendingPropertyApply(0);
  };
  window.__myWallpaperApplyGeneralProperties = function(properties) {
    const normalizedProperties = window.__myWallpaperNormalizePropertyBag(properties || {});
    window.__myWallpaperLastGeneralProperties = normalizedProperties;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyGeneralProperties === 'function') {
        window.wallpaperPropertyListener.applyGeneralProperties(normalizedProperties);
      }
      window.dispatchEvent(new CustomEvent('wallpaper-general-properties-applied', { detail: normalizedProperties }));
    } catch (error) {
      hostLogger.post('general-properties.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperNotifyDirectoryFilesChanged = function(propertyName, addedOrChangedFiles, removedFiles) {
    const safePropertyName = String(propertyName || '');
    const safeAddedOrChangedFiles = Array.isArray(addedOrChangedFiles) ? addedOrChangedFiles.map((value) => String(value || '')) : [];
    const safeRemovedFiles = Array.isArray(removedFiles) ? removedFiles.map((value) => String(value || '')) : [];
    try {
      const directoryState = window.__myWallpaperDirectoryState || {};
      const previousFiles = Array.isArray(directoryState[safePropertyName]) ? directoryState[safePropertyName] : [];
      const nextFiles = new Set(previousFiles.map((value) => String(value || '')));
      for (const path of safeAddedOrChangedFiles) {
        if (path) {
          nextFiles.add(path);
        }
      }
      for (const path of safeRemovedFiles) {
        nextFiles.delete(path);
      }
      directoryState[safePropertyName] = Array.from(nextFiles).sort();
      window.__myWallpaperDirectoryState = directoryState;
    } catch (_) {}
    try {
      if (
        safeAddedOrChangedFiles.length > 0 &&
        window.wallpaperPropertyListener &&
        typeof window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged === 'function'
      ) {
        window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged(
          safePropertyName,
          safeAddedOrChangedFiles
        );
      }
      if (
        safeRemovedFiles.length > 0 &&
        window.wallpaperPropertyListener &&
        typeof window.wallpaperPropertyListener.userDirectoryFilesRemoved === 'function'
      ) {
        window.wallpaperPropertyListener.userDirectoryFilesRemoved(
          safePropertyName,
          safeRemovedFiles
        );
      }
      window.dispatchEvent(new CustomEvent('wallpaper-directory-files-changed', {
        detail: {
          propertyName: safePropertyName,
          addedOrChangedFiles: safeAddedOrChangedFiles,
          removedFiles: safeRemovedFiles
        }
      }));
    } catch (error) {
      hostLogger.post('directory.notify.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperNotifyDirectoryAccessError = function(propertyName, errorMessage) {
    const safePropertyName = String(propertyName || '');
    const safeErrorMessage = String(errorMessage || '');
    try {
      if (safeErrorMessage) {
        const directoryState = window.__myWallpaperDirectoryState || {};
        if (Object.prototype.hasOwnProperty.call(directoryState, safePropertyName)) {
          delete directoryState[safePropertyName];
          window.__myWallpaperDirectoryState = directoryState;
        }
      }
      window.dispatchEvent(new CustomEvent('wallpaper-directory-access-error', {
        detail: {
          propertyName: safePropertyName,
          errorMessage: safeErrorMessage
        }
      }));
      hostLogger.post('directory.access', `${safePropertyName} ${safeErrorMessage || 'ok'}`.trim());
    } catch (error) {
      hostLogger.post('directory.access.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperPushAudioSpectrum = function(levels) {
    const safeLevels = Array.isArray(levels)
      ? levels.map((value) => {
          const numeric = Number(value);
          return Number.isFinite(numeric) ? Math.max(0, Math.min(1, numeric)) : 0;
        })
      : [];
    if (!hasLoggedAudioSpectrumDelivery && audioListeners.length > 0) {
      const peak = safeLevels.reduce((maximum, value) => Math.max(maximum, value), 0);
      const half = Math.floor(safeLevels.length / 2);
      const stereoDelta = half > 0
        ? safeLevels.slice(0, half).reduce(
            (total, value, index) => total + Math.abs(value - safeLevels[index + half]),
            0
          ) / half
        : 0;
      hostLogger.post(
        'audio.spectrum.dispatched',
        `listeners=${audioListeners.length} bins=${safeLevels.length} peak=${peak.toFixed(4)} stereoDelta=${stereoDelta.toFixed(4)}`
      );
      firstDeliveredAudioSpectrum.splice(0, firstDeliveredAudioSpectrum.length, ...safeLevels);
      hasLoggedAudioSpectrumDelivery = true;
    } else if (
      !hasLoggedAudioSpectrumChange &&
      audioListeners.length > 0 &&
      firstDeliveredAudioSpectrum.length === safeLevels.length &&
      safeLevels.length > 0
    ) {
      const meanDelta = safeLevels.reduce(
        (total, value, index) => total + Math.abs(value - firstDeliveredAudioSpectrum[index]),
        0
      ) / safeLevels.length;
      if (meanDelta >= 0.001) {
        hostLogger.post('audio.spectrum.changed', `meanDelta=${meanDelta.toFixed(4)}`);
        hasLoggedAudioSpectrumChange = true;
      }
    }
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-audio-spectrum', { detail: safeLevels }));
    } catch (_) {}
    for (const listener of audioListeners) {
      try { listener(safeLevels); } catch (_) {}
    }
  };
  window.__myWallpaperSetGlobalVolume = function(value) {
    const volume = Math.max(0, Math.min(1, Number(value) || 0));
    const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
    for (const node of mediaNodes.concat(audioStreams)) {
      if (!node) continue;
      try { node.volume = volume; } catch (_) {}
    }
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-volume-changed', { detail: volume }));
    } catch (_) {}
    for (const listener of volumeListeners) {
      try { listener(volume); } catch (_) {}
    }
  };
  window.__myWallpaperSetPlaybackRate = function(value) {
    const playbackRate = Math.max(0.25, Math.min(2, Number(value) || 1));
    const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
    for (const node of mediaNodes.concat(audioStreams)) {
      if (!node) continue;
      try { node.playbackRate = playbackRate; } catch (_) {}
    }
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-playback-rate-changed', { detail: playbackRate }));
    } catch (_) {}
  };
  window.__myWallpaperSetPaused = function(isPaused, options) {
    const paused = !!isPaused;
    window.__myWallpaperSetPagePaused?.(paused);
    const replayOptions = options || {};
    const shouldNotifyPage =
      !(replayOptions.initialReplay === true && paused === false && window.__myWallpaperLastNotifiedPaused !== true);
    window.wallpaperEngine_paused = paused;
    if (shouldNotifyPage) {
      try {
        if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPaused === 'function') {
          window.wallpaperPropertyListener.setPaused(paused);
        }
        if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPlaybackState === 'function') {
          window.wallpaperPropertyListener.setPlaybackState(paused ? 'paused' : 'playing');
        }
        window.__myWallpaperLastNotifiedPaused = paused;
      } catch (error) {
        hostLogger.post('pause.error', error && error.message ? error.message : error);
      }
    }
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-pause-changed', { detail: paused }));
    } catch (_) {}
    if (!shouldNotifyPage) return;
    for (const listener of playbackStateListeners) {
      try { listener(paused); } catch (_) {}
    }
    for (const context of audioContextInstances) {
      try {
        const contextState = String(context && context.state ? context.state : '').toLowerCase();
        if (contextState === 'closed') continue;
        if (paused && typeof context.suspend === 'function' && contextState !== 'suspended') {
          context.suspend().catch((error) => {
            hostLogger.post('audio.suspend.error', error && error.message ? error.message : error);
          });
        } else if (!paused && typeof context.resume === 'function' && contextState !== 'running') {
          context.resume().catch((error) => {
            hostLogger.post('audio.resume.error', error && error.message ? error.message : error);
          });
        }
      } catch (error) {
        hostLogger.post('audio.context-state.error', error && error.message ? error.message : error);
      }
    }
    const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
    for (const node of mediaNodes.concat(audioStreams)) {
      if (!node) continue;
      try {
        if (paused) {
          node.pause();
        } else if (typeof node.play === 'function') {
          const resolvedSource = String(node.currentSrc || node.src || '').trim();
          const normalizedSource = resolvedSource.toLowerCase();
          if (!resolvedSource || normalizedSource.endsWith('/null') || normalizedSource === 'null') {
            continue;
          }
          const playResult = node.play();
          const wrappedPlayResult = typeof window.__myWallpaperWrapMediaPlayPromise === 'function'
            ? window.__myWallpaperWrapMediaPlayPromise(playResult, node)
            : playResult;
          if (wrappedPlayResult && typeof wrappedPlayResult.catch === 'function') {
            wrappedPlayResult.catch((error) => {
              hostLogger.post('media.play.error', error && error.message ? error.message : error);
            });
          }
        }
      } catch (error) {
        hostLogger.post('media.control.error', error && error.message ? error.message : error);
      }
    }
    wallpaperDispatchMediaPlayback(wallpaperPreferredMediaNode(), paused);
  };
  window.__myWallpaperApplyInitialPausedState = function(isPaused) {
    window.__myWallpaperSetPaused(!!isPaused, { initialReplay: true });
  };
  try {
    window.__myWallpaperSetGlobalVolume(window.__myWallpaperInitialVolume);
    window.__myWallpaperSetPlaybackRate(window.__myWallpaperInitialPlaybackRate);
    window.__myWallpaperApplyInitialPausedState(!!window.__myWallpaperInitialPaused);
    window.__myWallpaperNotifyPluginLoaded('led');
    window.__myWallpaperNotifyPluginLoaded('rgb');
  } catch (error) {
    hostLogger.post('bootstrap.seed.error', error && error.message ? error.message : error);
  }
})();
"""#
