import { Play, Square, Volume2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { INTERVALS, intervalNoteLabel, writtenNoteFrequency } from '../../domain/referenceTone';
import { useReferenceTone } from '../../hooks/useReferenceTone';
import { useAppSettings } from '../../state/AppSettingsContext';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';
import type { MessageId } from '../../i18n/messages.base';

const NOTES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

export interface DroneSelection {
  note: string;
  interval: number;
}

export function droneSelectionFromSearch(search: URLSearchParams): DroneSelection {
  const note = search.get('note');
  const interval = Number(search.get('interval'));
  return {
    note: note && NOTES.includes(note) ? note : 'Bb',
    interval: INTERVALS.some((item) => item.semitones === interval) ? interval : 0,
  };
}

export function droneRecentHref({ note, interval }: DroneSelection) {
  return `/practice?tool=drone&note=${encodeURIComponent(note)}&interval=${interval}`;
}

export function DroneIntervalPanel() {
  const { t } = useI18n();
  const [searchParams] = useSearchParams();
  const selection = droneSelectionFromSearch(searchParams);
  const [note, setNote] = useState(selection.note);
  const [interval, setInterval] = useState(selection.interval);
  const { instrumentId, referencePitch } = useAppSettings();
  const { recordRecent } = usePracticeLibrary();
  const tone = useReferenceTone();
  const intervalItem = useMemo(() => INTERVALS.find((item) => item.semitones === interval) ?? INTERVALS[0], [interval]);
  const intervalLabel = t(`drone.interval.${intervalItem.id}` as MessageId);

  useEffect(() => {
    tone.stop();
    setNote(selection.note);
    setInterval(selection.interval);
  }, [searchParams, selection.interval, selection.note, tone.stop]);

  const start = async () => {
    const base = writtenNoteFrequency(note, instrumentId, referencePitch);
    const top = interval === 0 ? null : writtenNoteFrequency(note, instrumentId, referencePitch, interval);
    if (base == null || (interval !== 0 && top == null)) return;
    const frequencies = interval === 0 ? [base] : [base, top as number];
    if (await tone.start(frequencies)) {
      recordRecent({ kind: 'drone', id: `${note}-${interval}`, label: interval ? `${note} + ${intervalLabel}` : t('drone.recent', { note }), href: droneRecentHref({ note, interval }) });
    }
  };

  return (
    <SectionCard title={t('drone.title')} eyebrow={t('drone.eyebrow')}>
      <div className="practice-feature-stack">
        <p className="practice-warning"><Volume2 size={17} /> {t('drone.warning')}</p>
        <div className="practice-inline-form">
          <label className="field"><span>{t('drone.writtenNote')}</span><select value={note} onChange={(event) => { tone.stop(); setNote(event.target.value); }}>{NOTES.map((item) => <option value={item} key={item}>{item}</option>)}</select></label>
          <label className="field"><span>{t('drone.interval')}</span><select value={interval} onChange={(event) => { tone.stop(); setInterval(Number(event.target.value)); }}>{INTERVALS.map((item) => <option value={item.semitones} key={item.id}>{t(`drone.interval.${item.id}` as MessageId)}</option>)}</select></label>
        </div>
        {interval > 0 && <p className="muted-copy">{t('drone.hearPair', { note, intervalNote: intervalNoteLabel(note, interval) })}</p>}
        <div className="practice-actions">
          <button className="primary-button" type="button" onClick={tone.playing ? tone.stop : () => void start()}>{tone.playing ? <Square size={18} /> : <Play size={18} />}{tone.playing ? t('drone.stop') : t('drone.start')}</button>
        </div>
      </div>
    </SectionCard>
  );
}
