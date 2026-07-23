import { Save, Star, Trash2 } from 'lucide-react';
import { useState } from 'react';
import type { MetronomePreset } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function MetronomePresetPanel({ current, onApply }: { current: Omit<MetronomePreset, 'id' | 'name'>; onApply: (preset: MetronomePreset) => void }) {
  const { library, saveMetronomePreset, deleteMetronomePreset, toggleFavorite, isFavorite } = usePracticeLibrary();
  const [name, setName] = useState('');
  const [message, setMessage] = useState('');
  const save = () => {
    const preset = saveMetronomePreset({ ...current, name });
    if (!preset) {
      setMessage('Give this preset a short name.');
      return;
    }
    setName('');
    setMessage(`Saved “${preset.name}”.`);
  };
  return (
    <SectionCard title="Named presets" eyebrow="Save tempos you use often">
      <div className="practice-feature-stack">
        <form className="practice-inline-form" onSubmit={(event) => { event.preventDefault(); save(); }}>
          <label className="field"><span>Preset name</span><input maxLength={50} value={name} onChange={(event) => { setName(event.target.value); setMessage(''); }} placeholder="Audition tempo" /></label>
          <button className="ghost-button" type="submit"><Save size={17} />Save current setup</button>
        </form>
        {message && <p role="status" className={name ? 'pa-error' : 'practice-success'}>{message}</p>}
        {library.metronomePresets.length === 0 ? <p className="muted-copy">No presets yet.</p> : (
          <div className="practice-preset-list">
            {library.metronomePresets.map((preset) => {
              const target = { kind: 'metronome' as const, id: preset.id, label: `${preset.name} · ${preset.bpm} BPM`, href: `/metronome?preset=${encodeURIComponent(preset.id)}` };
              const favorite = isFavorite(target);
              return (
                <div key={preset.id}>
                  <button className="link-button" type="button" onClick={() => onApply(preset)}><strong>{preset.name}</strong> · {preset.bpm} BPM · {preset.numerator}/{preset.denominator}</button>
                  <button className="icon-button" type="button" aria-pressed={favorite} onClick={() => toggleFavorite(target)} aria-label={`${favorite ? 'Remove' : 'Add'} ${preset.name} ${favorite ? 'from' : 'to'} favorites`}><Star size={16} fill={favorite ? 'currentColor' : 'none'} /></button>
                  <button className="icon-button" type="button" onClick={() => deleteMetronomePreset(preset.id)} aria-label={`Delete ${preset.name}`}><Trash2 size={16} /></button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </SectionCard>
  );
}
