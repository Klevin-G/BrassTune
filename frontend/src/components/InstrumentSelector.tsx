import { useEffect, useState } from 'react';
import { getInstruments } from '../api/client';
import type { InstrumentProfile } from '../domain/types';

export function InstrumentSelector({ value, onChange, compact = false }: { value: string; onChange: (value: string) => void; compact?: boolean }) {
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
      {!compact && <span>Instrument</span>}
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        {instruments.map((instrument) => (
          <option value={instrument.id} key={instrument.id}>
            {instrument.display_name}
          </option>
        ))}
      </select>
    </label>
  );
}

