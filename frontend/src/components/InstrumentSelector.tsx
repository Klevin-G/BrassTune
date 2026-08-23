import { useEffect, useRef, useState } from 'react';
import { getInstruments } from '../api/client';
import type { InstrumentProfile } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

const fallbackInstruments: InstrumentProfile[] = [
  { id: 'trumpet', display_name: 'Trumpet in Bb' } as InstrumentProfile,
  { id: 'horn', display_name: 'French Horn in F' } as InstrumentProfile,
  { id: 'trombone', display_name: 'Trombone' } as InstrumentProfile,
  { id: 'euphonium', display_name: 'Euphonium' } as InstrumentProfile,
  { id: 'tuba', display_name: 'Tuba' } as InstrumentProfile,
];

export function InstrumentSelector({ value, onChange, compact = false, label }: { value: string; onChange: (value: string) => void; compact?: boolean; label?: string }) {
  const { t } = useI18n();
  const fieldLabel = label ?? t('instrument.label');
  // Keep a usable control through the first paint and any catalog outage.
  const [instruments, setInstruments] = useState<InstrumentProfile[]>(fallbackInstruments);
  const catalogGenerationRef = useRef(0);
  useEffect(() => {
    const generation = catalogGenerationRef.current + 1;
    catalogGenerationRef.current = generation;
    let active = true;
    let commitFrame: number | null = null;

    const commit = (profiles: InstrumentProfile[]) => {
      // The request can resolve while a NavLink transition is rendering. Wait
      // until the next frame so this update is never a render-phase update.
      commitFrame = window.requestAnimationFrame(() => {
        if (active && catalogGenerationRef.current === generation) {
          setInstruments(profiles.length > 0 ? profiles : fallbackInstruments);
        }
      });
    };

    getInstruments()
      .then(commit)
      .catch(() => commit(fallbackInstruments));
    return () => {
      active = false;
      if (commitFrame !== null) window.cancelAnimationFrame(commitFrame);
    };
  }, []);
  return (
    <label className={`select-wrap ${compact ? 'compact' : ''}`}>
      {!compact && <span>{fieldLabel}</span>}
      <select value={value} onChange={(event) => onChange(event.target.value)} aria-label={compact ? fieldLabel : undefined}>
        {instruments.map((instrument) => (
          <option value={instrument.id} key={instrument.id}>
            {(['trumpet', 'cornet', 'flugelhorn', 'horn', 'french-horn', 'trombone', 'bass-trombone', 'euphonium', 'baritone', 'tuba'].includes(instrument.id)
              ? t(`instrument.${instrument.id}` as MessageId)
              : instrument.display_name)}
          </option>
        ))}
      </select>
    </label>
  );
}
