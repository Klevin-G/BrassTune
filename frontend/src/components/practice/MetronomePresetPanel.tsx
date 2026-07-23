import { Save, Star, Trash2 } from 'lucide-react';
import { useState } from 'react';
import type { MetronomePreset } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';

export function MetronomePresetPanel({ current, onApply }: { current: Omit<MetronomePreset, 'id' | 'name'>; onApply: (preset: MetronomePreset) => void }) {
  const { t, formatNumber } = useI18n();
  const { library, saveMetronomePreset, deleteMetronomePreset, toggleFavorite, isFavorite } = usePracticeLibrary();
  const [name, setName] = useState('');
  const [message, setMessage] = useState('');
  const save = () => {
    const preset = saveMetronomePreset({ ...current, name });
    if (!preset) {
      setMessage(t('metronomePreset.nameRequired'));
      return;
    }
    setName('');
    setMessage(t('metronomePreset.saved', { name: preset.name }));
  };
  return (
    <SectionCard title={t('metronomePreset.title')} eyebrow={t('metronomePreset.eyebrow')}>
      <div className="practice-feature-stack">
        <form className="practice-inline-form" onSubmit={(event) => { event.preventDefault(); save(); }}>
          <label className="field"><span>{t('metronomePreset.name')}</span><input maxLength={50} value={name} onChange={(event) => { setName(event.target.value); setMessage(''); }} placeholder={t('metronomePreset.placeholder')} /></label>
          <button className="ghost-button" type="submit"><Save size={17} />{t('metronomePreset.save')}</button>
        </form>
        {message && <p role="status" className={name ? 'pa-error' : 'practice-success'}>{message}</p>}
        {library.metronomePresets.length === 0 ? <p className="muted-copy">{t('metronomePreset.empty')}</p> : (
          <div className="practice-preset-list">
            {library.metronomePresets.map((preset) => {
              const target = { kind: 'metronome' as const, id: preset.id, label: `${preset.name} · ${preset.bpm} BPM`, href: `/metronome?preset=${encodeURIComponent(preset.id)}` };
              const favorite = isFavorite(target);
              return (
                <div key={preset.id}>
                  <button className="link-button" type="button" onClick={() => onApply(preset)}><strong>{preset.name}</strong> · {formatNumber(preset.bpm)} BPM · {formatNumber(preset.numerator)}/{formatNumber(preset.denominator)}</button>
                  <button className="icon-button" type="button" aria-pressed={favorite} onClick={() => toggleFavorite(target)} aria-label={t(favorite ? 'metronomePreset.removeFavorite' : 'metronomePreset.addFavorite', { name: preset.name })}><Star size={16} fill={favorite ? 'currentColor' : 'none'} /></button>
                  <button className="icon-button" type="button" onClick={() => deleteMetronomePreset(preset.id)} aria-label={t('metronomePreset.delete', { name: preset.name })}><Trash2 size={16} /></button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </SectionCard>
  );
}
