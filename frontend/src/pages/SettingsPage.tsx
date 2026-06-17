import { Download, SlidersHorizontal, Trash2 } from 'lucide-react';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { InsightCard, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { useAppSettings } from '../state/AppSettingsContext';

export function SettingsPage() {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode } = useAppSettings();

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Settings"
        title="Practice preferences"
        description="Keep the tuner behavior explicit: instrument transposition, reference pitch, demo mode, and local export utilities."
        meta={<StatusBadge tone="gold">{instrumentId}</StatusBadge>}
      />
      <div className="two-column-grid">
        <SectionCard title="Tuner setup" eyebrow="Core controls">
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
        </SectionCard>
        <SectionCard title="Local utilities" eyebrow="MVP">
          <div className="insight-grid">
            <InsightCard
              title="Export demo session"
              detail="JSON"
              body="Use the seeded demo session as a smoke-test export while iterating locally."
              icon={Download}
              tone="gold"
            />
            <InsightCard
              title="Clear preferences"
              detail="Browser storage"
              body="Resets local UI preferences without touching saved backend sessions."
              icon={Trash2}
              tone="red"
            />
          </div>
          <div className="settings-actions">
            <a className="ghost-button" href="/api/export/session/1.json">
              <Download size={18} />
              Export demo
            </a>
            <button className="ghost-button" type="button" onClick={() => localStorage.clear()}>
              <Trash2 size={18} />
              Clear preferences
            </button>
          </div>
        </SectionCard>
      </div>
      <SectionCard title="Portability note" eyebrow="Swift-ready core">
        <InsightCard
          title="Pure domain logic stays portable"
          detail="Pitch math, profiles, segmentation, analytics"
          body="The frontend controls assume the backend owns microphone persistence and note math, so the same core models can still move toward Swift cleanly."
          icon={SlidersHorizontal}
        />
      </SectionCard>
    </ScreenContainer>
  );
}
