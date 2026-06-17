import { InstrumentSelector } from '../components/InstrumentSelector';
import { useAppSettings } from '../state/AppSettingsContext';

export function SettingsPage() {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode } = useAppSettings();
  return (
    <section className="panel settings-panel">
      <h2>Settings</h2>
      <div className="settings-grid">
        <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
        <label className="field">
          <span>Reference pitch</span>
          <input type="number" min={430} max={450} step={0.5} value={referencePitch} onChange={(event) => setReferencePitch(Number(event.target.value))} />
        </label>
        <label className="switch-row">
          <span>Demo mode</span>
          <input type="checkbox" checked={demoMode} onChange={(event) => setDemoMode(event.target.checked)} />
        </label>
        <label className="field">
          <span>In-tune threshold</span>
          <input type="text" value="+/-5 cents" readOnly />
        </label>
      </div>
      <div className="settings-actions">
        <a className="ghost-button" href="/api/export/session/1.json">Export demo session</a>
        <button className="ghost-button" type="button" onClick={() => localStorage.clear()}>Clear local preferences</button>
      </div>
    </section>
  );
}

