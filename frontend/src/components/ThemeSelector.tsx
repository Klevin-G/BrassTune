import { MonitorCog } from 'lucide-react';
import { themeOptions, useTheme } from '../state/ThemeContext';

export function ThemeSelector({ compact = false }: { compact?: boolean }) {
  const { theme, setTheme } = useTheme();

  return (
    <label className={compact ? 'theme-selector compact' : 'theme-selector'}>
      <span>
        <MonitorCog size={compact ? 16 : 18} />
        Theme
      </span>
      <select value={theme} onChange={(event) => setTheme(event.target.value as typeof theme)}>
        {themeOptions.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}
