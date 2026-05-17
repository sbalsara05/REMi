const EXIT_MS = 420;

/** Fades out and removes the static HTML boot splash (#loading-container). */
export function dismissBootSplash() {
  const el = document.getElementById('loading-container');
  if (!el) {
    return;
  }
  el.classList.add('remi-splash--exit');
  window.setTimeout(() => {
    el.remove();
  }, EXIT_MS);
}
