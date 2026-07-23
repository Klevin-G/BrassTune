import { Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { parseExerciseNotes } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { useI18n } from '../../i18n/LocaleContext';

export function CustomExerciseBuilder({ onSaved }: { onSaved: (id: string) => void }) {
  const { library, saveExercise, deleteExercise } = usePracticeLibrary();
  const { t } = useI18n();
  const [name, setName] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  const submit = () => {
    const parsed = parseExerciseNotes(notes);
    if (!name.trim()) {
      setError(t('exercise.nameRequired'));
      return;
    }
    if (parsed.error) {
      const tokens = notes.split(/[\s,]+/).filter(Boolean);
      const invalid = tokens.find((token) => !/^[A-Ga-g](?:#|b|♯|♭)?$/.test(token));
      setError(invalid ? t('exercise.invalidNote', { note: invalid }) : t('exercise.noteCountError'));
      return;
    }
    const item = saveExercise({ name, notes: parsed.notes, source: 'custom' });
    setName('');
    setNotes('');
    setError('');
    onSaved(item.id);
  };

  return (
    <details className="practice-builder">
      <summary>{t('exercise.builder')}</summary>
      <div className="practice-feature-stack">
        <p className="muted-copy">{t('exercise.help')}</p>
        <label className="field"><span>{t('exercise.name')}</span><input maxLength={60} value={name} onChange={(event) => setName(event.target.value)} placeholder={t('exercise.namePlaceholder')} /></label>
        <label className="field"><span>{t('exercise.notes')}</span><textarea rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="C E G C" /></label>
        <button className="ghost-button" type="button" onClick={submit}><Plus size={17} />{t('exercise.save')}</button>
        {error && <p className="pa-error" role="alert">{error}</p>}
        {library.customExercises.length > 0 && (
          <div className="practice-saved-list" aria-label={t('exercise.saved')}>
            {library.customExercises.map((item) => (
              <div key={item.id}><button className="link-button" type="button" onClick={() => onSaved(item.id)}>{item.name} · {t('exercise.noteCount', { count: item.notes.length })}</button><button className="icon-button" type="button" onClick={() => deleteExercise(item.id)} aria-label={t('exercise.delete', { name: item.name })}><Trash2 size={16} /></button></div>
            ))}
          </div>
        )}
      </div>
    </details>
  );
}
