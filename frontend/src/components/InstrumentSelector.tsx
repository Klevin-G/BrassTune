import { useEffect, useState } from 'react';
import { getInstruments } from '../api/client';
import type { InstrumentProfile } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

export function InstrumentSelector({ value, onChange, compact = false, label }: { value: string; onChange: (value: string) => void; compact?: boolean; label?: string }) {
  const { t } = useI18n();
  const fieldLabel = label ?? t('instrument.label');
  const [instruments, setInstruments] = useState<InstrumentProfile[]>([]);
  useEffect(() => {
    getInstruments()
      .then(setInstruments)
      .catch(() => {
        setInstruments([
          { id: 'trumpet', display_name: 'Trumpet in Bb' } as InstrumentProfile,
          { id: 'horn', display_name: 'French Horn in F' } as InstrumentProfile,
          { id: 'trombone', display_name: 'Trombone' } as InstrumentProfile,
          { id: 'euphonium', display_name: 'Euphonium' } as InstrumentProfile,
          { id: 'tuba', display_name: 'Tuba' } as InstrumentProfile,
        ]);
      });
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
