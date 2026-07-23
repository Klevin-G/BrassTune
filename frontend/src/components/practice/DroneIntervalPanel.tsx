import { Play, Square, Volume2 } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  INTERVALS,
  WRITTEN_MIDI_MAX,
  WRITTEN_MIDI_MIN,
  intervalWrittenMidiLabel,
  isWrittenMidi,
  writtenMidiFrequency,
  writtenMidiLabel,
} from '../../domain/referenceTone';
import { noteLabelToMidi } from '../../domain/music';
import { PRACTICE_AUDIO_PAUSE_EVENT } from '../../domain/practiceLibrary';
import { useReferenceTone } from '../../hooks/useReferenceTone';
import { useAppSettings } from '../../state/AppSettingsContext';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';
import { useI18n } from '../../i18n/LocaleContext';
import type { MessageId } from '../../i18n/messages.base';

const DEFAULT_WRITTEN_MIDI = noteLabelToMidi('Bb4');
const WRITTEN_NOTES = Array.from(
  { length: WRITTEN_MIDI_MAX - WRITTEN_MIDI_MIN + 1 },
  (_, index) => WRITTEN_MIDI_MIN + index,
);

export interface DroneSelection {
  writtenMidi: number;
  interval: number;
}

export function droneSelectionFromSearch(search: URLSearchParams): DroneSelection {
  const midi = Number(search.get('midi'));
  const legacyNote = search.get('note');
  const legacyMidi = legacyNote ? noteLabelToMidi(`${legacyNote}4`) : Number.NaN;
  const interval = Number(search.get('interval'));
  return {
    writtenMidi: isWrittenMidi(midi)
      ? midi
      : isWrittenMidi(legacyMidi)
        ? legacyMidi
        : DEFAULT_WRITTEN_MIDI,
    interval: INTERVALS.some((item) => item.semitones === interval) ? interval : 0,
  };
}

export function droneRecentHref({ writtenMidi, interval }: DroneSelection) {
  return `/practice?tool=drone&midi=${writtenMidi}&interval=${interval}`;
}

export function DroneIntervalPanel() {
  const { t } = useI18n();
  const [searchParams] = useSearchParams();
  const selection = droneSelectionFromSearch(searchParams);
  const [writtenMidi, setWrittenMidi] = useState(selection.writtenMidi);
  const [interval, setInterval] = useState(selection.interval);
  const { instrumentId, referencePitch } = useAppSettings();
  const { recordRecent } = usePracticeLibrary();
  const tone = useReferenceTone();
  const toneGenerationRef = useRef(0);
  const intervalItem = useMemo(() => INTERVALS.find((item) => item.semitones === interval) ?? INTERVALS[0], [interval]);
  const intervalLabel = t(`drone.interval.${intervalItem.id}` as MessageId);
  const stopTone = useCallback(() => {
    toneGenerationRef.current += 1;
    tone.stop();
  }, [tone.stop]);

  useEffect(() => {
    stopTone();
    setWrittenMidi(selection.writtenMidi);
    setInterval(selection.interval);
  }, [searchParams, selection.interval, selection.writtenMidi, stopTone]);

  useEffect(() => {
    const stopForBackground = () => stopTone();
    const handleVisibility = () => {
      if (document.hidden) stopForBackground();
    };
    document.addEventListener('visibilitychange', handleVisibility);
    window.addEventListener('pagehide', stopForBackground);
    window.addEventListener(PRACTICE_AUDIO_PAUSE_EVENT, stopForBackground);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibility);
      window.removeEventListener('pagehide', stopForBackground);
      window.removeEventListener(PRACTICE_AUDIO_PAUSE_EVENT, stopForBackground);
    };
  }, [stopTone]);

  const start = async () => {
    const base = writtenMidiFrequency(writtenMidi, instrumentId, referencePitch);
    const top = interval === 0 ? null : writtenMidiFrequency(writtenMidi, instrumentId, referencePitch, interval);
    if (base == null || (interval !== 0 && top == null)) return;
    const frequencies = interval === 0 ? [base] : [base, top as number];
    const generation = ++toneGenerationRef.current;
    if (await tone.start(frequencies) && generation === toneGenerationRef.current && !document.hidden) {
      const note = writtenMidiLabel(writtenMidi) ?? '';
      recordRecent({
        kind: 'drone',
        id: `${writtenMidi}-${interval}`,
        label: interval ? `${note} + ${intervalLabel}` : t('drone.recent', { note }),
        href: droneRecentHref({ writtenMidi, interval }),
      });
    } else {
      tone.stop();
    }
  };
  const note = writtenMidiLabel(writtenMidi) ?? '';
  const intervalNote = intervalWrittenMidiLabel(writtenMidi, interval) ?? '';

  return (
    <SectionCard title={t('drone.title')} eyebrow={t('drone.eyebrow')}>
      <div className="practice-feature-stack">
        <p className="practice-warning"><Volume2 size={17} /> {t('drone.warning')}</p>
        <div className="practice-inline-form">
          <label className="field"><span>{t('drone.writtenNote')}</span><select value={writtenMidi} onChange={(event) => { stopTone(); setWrittenMidi(Number(event.target.value)); }}>{WRITTEN_NOTES.map((item) => <option value={item} key={item}>{writtenMidiLabel(item)}</option>)}</select></label>
          <label className="field"><span>{t('drone.interval')}</span><select value={interval} onChange={(event) => { stopTone(); setInterval(Number(event.target.value)); }}>{INTERVALS.map((item) => <option value={item.semitones} key={item.id}>{t(`drone.interval.${item.id}` as MessageId)}</option>)}</select></label>
        </div>
        {interval > 0 && <p className="muted-copy">{t('drone.hearPair', { note, intervalNote })}</p>}
        <div className="practice-actions">
          <button className="primary-button" type="button" onClick={tone.playing ? stopTone : () => void start()}>{tone.playing ? <Square size={18} /> : <Play size={18} />}{tone.playing ? t('drone.stop') : t('drone.start')}</button>
        </div>
      </div>
    </SectionCard>
  );
}
