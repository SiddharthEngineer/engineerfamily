// The homepage demo's motion: each .step fades in as it scrolls into view, the link types itself into the Add-job box,
// the fit score counts up and the tailored lines light up (demo.css). The HTML and CSS are the final state, so with no
// JS, no IntersectionObserver or prefers-reduced-motion: reduce, this does nothing and everything shows at once.
(() => {
  if (!('IntersectionObserver' in window) || matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const typed = document.querySelector('#add .typed');
  const score = document.querySelector('#score .fit-num');
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

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      entry.target.classList.add('is-visible');
      onReveal[entry.target.id]?.();
    }
  }, { threshold: 0.25 });

  document.documentElement.classList.add('motion');
  document.querySelectorAll('.step').forEach((step) => observer.observe(step));
})();
