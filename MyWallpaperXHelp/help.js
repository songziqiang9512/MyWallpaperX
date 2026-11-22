/* Search is an enhancement; all chapters and anchors work without JavaScript. */
(() => {
  const search = document.querySelector('#help-search');
  const chapters = [...document.querySelectorAll('.guide-section')];
  const status = document.querySelector('#search-status');
  const message = document.querySelector('#search-message');
  const hero = document.querySelector('.hero');
  const COPY = {
    zh: { found: count => `找到 ${count} 个相关章节`, none: '没有找到相关章节，试试“下载”“暂停”或“Scene”。' },
    ru: { found: count => `Найдено глав: ${count}`, none: 'Совпадающих глав нет. Попробуйте «скачать», «пауза» или «Scene».' },
    de: { found: count => `${count} passende Kapitel`, none: 'Keine passenden Kapitel. Versuchen Sie „Download“, „Pause“ oder „Scene“.' },
    fr: { found: count => `${count} chapitres correspondants`, none: 'Aucun chapitre correspondant. Essayez « télécharger », « pause » ou « Scene ».' },
    en: { found: count => `${count} matching chapters`, none: 'No matching chapters. Try “download”, “pause” or “Scene”.' }
  };
  const copy = COPY[(document.documentElement.lang || 'en').toLowerCase().split('-')[0]] || COPY.en;
  const originalOpen = new Map();
  let wasSearching = false;
  const texts = chapters.map(section => section.textContent.toLocaleLowerCase());
  document.querySelector('.search').hidden = false;
  function filter() {
    const terms = search.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    const isSearching = terms.length > 0;
    if (isSearching && !wasSearching) {
      document.querySelectorAll('details').forEach(item => originalOpen.set(item, item.open));
    }
    let count = 0;
    chapters.forEach((section, index) => {
      section.hidden = !terms.every(term => texts[index].includes(term));
      if (!section.hidden) count++;
      section.querySelectorAll('details').forEach(item => {
        if (isSearching && !section.hidden) item.open = true;
        else if (wasSearching && !isSearching) item.open = originalOpen.get(item);
      });
    });
    hero.hidden = terms.length > 0;
    status.hidden = terms.length === 0;
    wasSearching = isSearching;
    message.textContent = count ? copy.found(count) : copy.none;
  }
  search.addEventListener('input', filter);
  search.addEventListener('keydown', event => {
    if (event.key === 'Escape') { search.value = ''; filter(); }
  });
  document.querySelector('#clear-search').addEventListener('click', () => {
    search.value = ''; filter(); search.focus();
  });
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    link.addEventListener('click', () => {
      search.value = ''; filter();
      document.querySelectorAll('nav a').forEach(item => {
        if (item.hash === link.hash) item.setAttribute('aria-current', 'location');
        else item.removeAttribute('aria-current');
      });
    });
  });
})();
