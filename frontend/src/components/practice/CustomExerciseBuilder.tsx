import { Plus, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { parseExerciseNotes } from '../../domain/practiceLibrary';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';

export function CustomExerciseBuilder({ onSaved }: { onSaved: (id: string) => void }) {
  const { library, saveExercise, deleteExercise } = usePracticeLibrary();
  const [name, setName] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  const submit = () => {
    const parsed = parseExerciseNotes(notes);
    if (!name.trim()) {
      setError('Give this exercise a short name.');
      return;
    }
    if (parsed.error) {
      setError(parsed.error);
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
      <summary>Build a custom exercise</summary>
      <div className="practice-feature-stack">
        <p className="muted-copy">Add 1–32 written notes separated by spaces or commas. Flats and sharps are welcome.</p>
        <label className="field"><span>Exercise name</span><input maxLength={60} value={name} onChange={(event) => setName(event.target.value)} placeholder="My lip slur" /></label>
        <label className="field"><span>Notes</span><textarea rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="C E G C" /></label>
        <button className="ghost-button" type="button" onClick={submit}><Plus size={17} />Save and select</button>
        {error && <p className="pa-error" role="alert">{error}</p>}
        {library.customExercises.length > 0 && (
          <div className="practice-saved-list" aria-label="Saved custom exercises">
            {library.customExercises.map((item) => (
              <div key={item.id}><button className="link-button" type="button" onClick={() => onSaved(item.id)}>{item.name} · {item.notes.length} notes</button><button className="icon-button" type="button" onClick={() => deleteExercise(item.id)} aria-label={`Delete ${item.name}`}><Trash2 size={16} /></button></div>
            ))}
          </div>
        )}
      </div>
    </details>
  );
}
