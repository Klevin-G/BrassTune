(() => {
  const allowed = new Set(['system', 'brass-white', 'brass-night', 'high-contrast']);
  let stored = null;
  try { stored = localStorage.getItem('brasstune.theme'); } catch { /* Storage may be unavailable. */ }
  const preference = allowed.has(stored) ? stored : 'brass-white';
  const systemLight = matchMedia('(prefers-color-scheme: light)').matches;
  const resolved = preference === 'system' ? (systemLight ? 'brass-white' : 'brass-night') : preference;
  document.documentElement.dataset.themePreference = preference;
  document.documentElement.dataset.theme = resolved;
})();
