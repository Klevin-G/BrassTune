import { Check, Contrast, Monitor, Moon, Sun, type LucideIcon } from 'lucide-react';
import { themeOptions, useTheme, type ThemePreference } from '../state/ThemeContext';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

const themeIcons: Record<ThemePreference, LucideIcon> = {
  system: Monitor,
  'brass-white': Sun,
  'brass-night': Moon,
  'high-contrast': Contrast,
};

export function ThemeSelector({ compact = false }: { compact?: boolean }) {
  const { t } = useI18n();
  const { theme, setTheme, resolvedTheme } = useTheme();

  return (
    <div
      className={compact ? 'theme-picker compact' : 'theme-picker'}
      role="radiogroup"
      aria-label={t('theme.appearance')}
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
                {t(`theme.${option.value}.label` as MessageId)}
              </span>
              <span className="theme-card-hint">
                {showsResolved
                  ? t(resolvedTheme === 'brass-white' ? 'theme.nowLight' : 'theme.nowDark')
                  : t(`theme.${option.value}.hint` as MessageId)}
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
