(() => {
  const allowed = new Set(['system', 'brass-night', 'brass-day', 'liquid-clear', 'liquid-tinted', 'high-contrast']);
  const stored = localStorage.getItem('brasstune.theme');
  const preference = allowed.has(stored) ? stored : 'system';
  const systemLight = matchMedia('(prefers-color-scheme: light)').matches;
  const resolved = preference === 'system' ? (systemLight ? 'brass-day' : 'brass-night') : preference;
  document.documentElement.dataset.themePreference = preference;
  document.documentElement.dataset.theme = resolved;
})();
