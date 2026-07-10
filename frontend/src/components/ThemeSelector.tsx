import { Check, Contrast, Monitor, Moon, Sun, type LucideIcon } from 'lucide-react';
import { themeOptions, useTheme, type ThemePreference } from '../state/ThemeContext';

const themeIcons: Record<ThemePreference, LucideIcon> = {
  system: Monitor,
  'brass-white': Sun,
  'brass-night': Moon,
  'high-contrast': Contrast,
};

export function ThemeSelector({ compact = false }: { compact?: boolean }) {
  const { theme, setTheme, resolvedTheme } = useTheme();

  return (
    <div
      className={compact ? 'theme-picker compact' : 'theme-picker'}
      role="radiogroup"
      aria-label="Appearance theme"
    >
      {themeOptions.map((option) => {
        const Icon = themeIcons[option.value];
        const selected = theme === option.value;
        const showsResolved = option.value === 'system';
        return (
          <label
            key={option.value}
            className={selected ? 'theme-card selected' : 'theme-card'}
            data-theme-swatch={option.value}
          >
            <input
              type="radio"
              name="brasstune-theme"
              value={option.value}
              checked={selected}
              onChange={() => setTheme(option.value)}
            />
            <span
              className="theme-card-preview"
              style={{ background: option.swatch.base }}
              aria-hidden="true"
            >
              <span className="theme-card-surface" style={{ background: option.swatch.surface }}>
                <span className="theme-card-bar" style={{ background: option.swatch.accent }} />
                <span className="theme-card-bar short" style={{ background: option.swatch.ink, opacity: 0.4 }} />
              </span>
              <span className="theme-card-dot" style={{ background: option.swatch.accent }} />
            </span>
            <span className="theme-card-meta">
              <span className="theme-card-name">
                <Icon size={15} />
                {option.label}
              </span>
              <span className="theme-card-hint">
                {showsResolved
                  ? `Now ${resolvedTheme === 'brass-white' ? 'light' : 'dark'}`
                  : option.hint}
              </span>
            </span>
            <span className="theme-card-check" aria-hidden="true">
              <Check size={14} />
            </span>
          </label>
        );
      })}
    </div>
  );
}
