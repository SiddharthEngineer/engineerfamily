// The homepage demo's motion: each .step fades in as it scrolls into view, the link types itself into the Add-job box,
// the fit score counts up and the tailored lines light up (demo.css). The HTML and CSS are the final state; motion runs
// only if the inline script in index.html put .motion on <html> (JS, IntersectionObserver, no reduced-motion).
(() => {
  const root = document.documentElement;
  if (!root.classList.contains('motion')) return;

  const typed = document.querySelector('#add .typed');
  const score = document.querySelector('#score .fit-num');
  let stopped = false;
  if (typed) {  // keep the box at its full height while it types
    typed.parentElement.style.minHeight = `${typed.parentElement.offsetHeight}px`;
    typed.textContent = '';
  }
  if (score) score.textContent = '0';

  // Types data-text into el, a few characters per frame, once.
  function type(el) {
    const text = el.dataset.text;
    let n = 0;
    const tick = () => {
      if (stopped) return;
      n = Math.min(text.length, n + 2);
      el.textContent = text.slice(0, n);
      if (n < text.length) setTimeout(tick, 30);
      else el.parentElement.style.minHeight = '';
    };
    setTimeout(tick, 400);
  }

  // Counts el up from 0 to data-value over about the fit bar's 1.2 s.
  function countUp(el) {
    const end = Number(el.dataset.value);
    const start = performance.now();
    const frame = (now) => {
      if (stopped) return;
      const t = Math.min(1, (now - start) / 1200);
      el.textContent = String(Math.round(end * (1 - (1 - t) ** 3)));
      if (t < 1) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  const onReveal = {
    add: () => typed && type(typed),
    score: () => score && countUp(score),
  };

  // Threshold 0 with a bottom margin, so a step taller than the viewport still reveals.
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      entry.target.classList.add('is-visible');
      onReveal[entry.target.id]?.();
    }
  }, { rootMargin: '0px 0px -15% 0px' });
  document.querySelectorAll('.step').forEach((step) => observer.observe(step));

  // Reduced motion switched on while the page is open: jump to the final state.
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  reduce.addEventListener('change', () => {
    if (!reduce.matches || stopped) return;
    stopped = true;
    observer.disconnect();
    root.classList.remove('motion');
    if (typed) {
      typed.textContent = typed.dataset.text;
      typed.parentElement.style.minHeight = '';
    }
    if (score) score.textContent = score.dataset.value;
  });
})();
