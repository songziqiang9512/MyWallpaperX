let webCompatibilityScriptDOMLifecyclePointer = #"""
    const pointerEvents = ['pointermove', 'mousemove', 'mouseenter', 'mouseover'];
    pointerEvents.forEach((type) => {
      window.addEventListener(type, (event) => {
        updateCursorState(event);
      }, { passive: true });
    });
    window.addEventListener('mouseleave', () => {
      window.wallpaperEngine_mouseover = false;
    }, { passive: true });
    window.addEventListener('mouseout', (event) => {
      if (!event.relatedTarget) {
        window.wallpaperEngine_mouseover = false;
      }
    }, { passive: true });
    window.addEventListener('mousedown', (event) => {
      updateCursorState(event);
      hostLogger.post('pointer.down', `button=${event.button} buttons=${event.buttons}`);
    }, true);
    window.addEventListener('mouseup', (event) => {
      updateCursorState(event);
      hostLogger.post('pointer.up', `button=${event.button} buttons=${event.buttons}`);
    }, true);
    window.addEventListener('contextmenu', (event) => {
      updateCursorState(event);
      hostLogger.post('pointer.contextmenu', `button=${event.button} buttons=${event.buttons}`);
    }, true);
  });
"""#
