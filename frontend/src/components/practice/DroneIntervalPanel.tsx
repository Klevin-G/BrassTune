import { Play, Square, Volume2 } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { INTERVALS, intervalNoteLabel, writtenNoteFrequency } from '../../domain/referenceTone';
import { useReferenceTone } from '../../hooks/useReferenceTone';
import { useAppSettings } from '../../state/AppSettingsContext';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

const NOTES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

export function DroneIntervalPanel() {
  const [searchParams] = useSearchParams();
  const initialNote = NOTES.includes(searchParams.get('note') ?? '') ? searchParams.get('note')! : 'Bb';
  const [note, setNote] = useState(initialNote);
  const [interval, setInterval] = useState(0);
  const { instrumentId, referencePitch } = useAppSettings();
  const { recordRecent } = usePracticeLibrary();
  const tone = useReferenceTone();
  const intervalLabel = useMemo(() => INTERVALS.find((item) => item.semitones === interval)?.label ?? 'Unison', [interval]);

  const start = async () => {
    const base = writtenNoteFrequency(note, instrumentId, referencePitch);
    const top = interval === 0 ? null : writtenNoteFrequency(note, instrumentId, referencePitch, interval);
    if (base == null || (interval !== 0 && top == null)) return;
    const frequencies = interval === 0 ? [base] : [base, top as number];
    if (await tone.start(frequencies)) {
      recordRecent({ kind: 'drone', id: `${note}-${interval}`, label: interval ? `${note} + ${intervalLabel}` : `${note} drone`, href: `/practice?tool=drone&note=${encodeURIComponent(note)}` });
    }
  };

  return (
    <SectionCard title="Drone and interval tone" eyebrow="Written for your instrument">
      <div className="practice-feature-stack">
        <p className="practice-warning"><Volume2 size={17} /> Start with low volume. Headphones make pitch differences easier to hear and protect people around you.</p>
        <div className="practice-inline-form">
          <label className="field"><span>Written note</span><select value={note} onChange={(event) => { tone.stop(); setNote(event.target.value); }}>{NOTES.map((item) => <option value={item} key={item}>{item}</option>)}</select></label>
          <label className="field"><span>Interval</span><select value={interval} onChange={(event) => { tone.stop(); setInterval(Number(event.target.value)); }}>{INTERVALS.map((item) => <option value={item.semitones} key={item.id}>{item.label}</option>)}</select></label>
        </div>
        {interval > 0 && <p className="muted-copy">You will hear written {note} with {intervalNoteLabel(note, interval)}. Both are transposed to the correct concert pitches.</p>}
        <div className="practice-actions">
          <button className="primary-button" type="button" onClick={tone.playing ? tone.stop : () => void start()}>{tone.playing ? <Square size={18} /> : <Play size={18} />}{tone.playing ? 'Stop tone' : 'Start tone'}</button>
        </div>
      </div>
    </SectionCard>
  );
}
