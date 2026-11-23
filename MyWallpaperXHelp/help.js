/* MyWallpaperX field guide — a slow field of dust behind a quiet page. */
(() => {
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- the field ---------- */
  const canvas = document.getElementById('field');
  const ctx = canvas && canvas.getContext('2d');
  let W = 0, H = 0, dpr = 1;
  let dust = [];
  let accent = [125, 211, 252];
  let pointerX = 0, pointerY = 0;
  let targetPointerX = 0, targetPointerY = 0;
  let running = true;

  function parseColor(value) {
    const m = value.match(/rgba?\(([^)]+)\)/);
    if (!m) return accent;
    const parts = m[1].split(/[,\s/]+/).map(Number);
    return [parts[0], parts[1], parts[2]];
  }

  function resize() {
    if (!canvas) return;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = canvas.clientWidth;
    H = canvas.clientHeight;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    seed();
  }

  function seed() {
    const count = Math.max(80, Math.min(240, Math.round((W * H) / 10500)));
    dust = Array.from({ length: count }, () => ({
      x: Math.random() * W,
      y: Math.random() * H,
      r: 0.4 + Math.random() * 1.7,
      vx: (Math.random() - 0.5) * 0.09,
      vy: -0.03 - Math.random() * 0.11,
      a: 0.2 + Math.random() * 0.55,
      phase: Math.random() * Math.PI * 2,
      warm: Math.random() < 0.1
    }));
  }

  function draw(t) {
    if (!ctx) return;
    ctx.clearRect(0, 0, W, H);
    pointerX += (targetPointerX - pointerX) * 0.045;
    pointerY += (targetPointerY - pointerY) * 0.045;

    for (const p of dust) {
      p.x += p.vx;
      p.y += p.vy;
      if (p.y < -8) { p.y = H + 8; p.x = Math.random() * W; }
      if (p.x < -8) p.x = W + 8;
      if (p.x > W + 8) p.x = -8;

      const twinkle = 0.55 + 0.45 * Math.sin(t * 0.0006 + p.phase);
      const px = p.x + pointerX * (p.r * 6);
      const py = p.y + pointerY * (p.r * 6);
      const color = p.warm ? accent : [226, 236, 248];

      ctx.beginPath();
      ctx.fillStyle = `rgba(${color[0]},${color[1]},${color[2]},${(p.a * twinkle).toFixed(3)})`;
      ctx.arc(px, py, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function loop(t) {
    if (!running) return;
    draw(t);
    requestAnimationFrame(loop);
  }

  if (canvas && ctx) {
    resize();
    window.addEventListener('resize', resize, { passive: true });
    window.addEventListener('pointermove', (e) => {
      targetPointerX = (e.clientX / window.innerWidth - 0.5) * 2;
      targetPointerY = (e.clientY / window.innerHeight - 0.5) * 2;
    }, { passive: true });
    document.addEventListener('visibilitychange', () => {
      running = !document.hidden;
      if (running) requestAnimationFrame(loop);
    });
    if (!reduce) requestAnimationFrame(loop);
    else draw(0);
  }

  /* ---------- sections, accent, rail ---------- */
  const sections = [...document.querySelectorAll('.section')];
  const railLinks = [...document.querySelectorAll('.rail a')];
  const railFill = document.querySelector('.rail-scroll span');
  const root = document.documentElement;
  const body = document.body;

  function setAccent(section) {
    const next = section && section.dataset.accent;
    if (!next) return;
    root.style.setProperty('--accent', next);
    root.style.setProperty('--accent-dim', next + '2b');
    accent = parseColor(next);
  }

  function markRail(id) {
    for (const link of railLinks) {
      const on = link.getAttribute('href') === '#' + id;
      if (on) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    }
  }

  let current = sections[0];
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        current = entry.target;
        setAccent(current);
        markRail(current.id);
      }
    }
  }, { rootMargin: '-18% 0px -62% 0px', threshold: 0 });
  sections.forEach((s) => observer.observe(s));

  function onScroll() {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const progress = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
    if (railFill) railFill.style.height = (progress * 100).toFixed(2) + '%';
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* ---------- search ---------- */
  const input = document.getElementById('q');
  const status = document.createElement('p');
  status.className = 'search-status';
  status.setAttribute('role', 'status');
  const doc = document.querySelector('.doc');
  if (doc && input) doc.prepend(status);

  let timer = 0;
  function runSearch(query) {
    const q = query.trim().toLowerCase();
    if (!q) {
      body.classList.remove('is-searching');
      sections.forEach((s) => s.classList.remove('is-hit'));
      status.textContent = '';
      return;
    }
    let hits = 0;
    for (const section of sections) {
      const text = section.textContent.toLowerCase();
      const hit = text.includes(q);
      section.classList.toggle('is-hit', hit);
      if (hit) hits += 1;
    }
    body.classList.add('is-searching');
    status.textContent = hits === 0
      ? 'Nothing in this guide matches “' + query.trim() + '”. Try a menu name such as Playback Modes, or a source such as Workshop.'
      : hits + (hits === 1 ? ' section matches' : ' sections match') + ' “' + query.trim() + '”.';
  }

  if (input) {
    input.addEventListener('input', () => {
      clearTimeout(timer);
      timer = window.setTimeout(() => runSearch(input.value), 120);
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        input.value = '';
        runSearch('');
        input.blur();
      }
    });
  }

  /* ---------- keyboard ---------- */
  document.addEventListener('keydown', (e) => {
    const typing = e.target instanceof HTMLElement &&
      (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable);
    if (e.key === '/' && !typing) {
      if (input) { e.preventDefault(); input.focus(); input.select(); }
      return;
    }
    if (typing) return;
    if (e.key === 'j' || e.key === 'k') {
      const index = sections.indexOf(current);
      const next = sections[index + (e.key === 'j' ? 1 : -1)];
      if (next) { e.preventDefault(); next.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' }); }
    }
  });
})();
