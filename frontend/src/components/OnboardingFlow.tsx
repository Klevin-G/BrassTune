import { ArrowRight, CheckCircle2, Gauge, Mic, Music2, SlidersHorizontal, X } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { InstrumentSelector } from './InstrumentSelector';
import { SelectionChip } from './ui/AppPrimitives';

const steps = [
  { title: 'Choose your brass voice', icon: Music2 },
  { title: 'Set the reference pitch', icon: SlidersHorizontal },
  { title: 'Pick the input mode', icon: Mic },
  { title: 'Read the lock status', icon: Gauge },
  { title: 'Record the first take', icon: CheckCircle2 },
];

export function OnboardingFlow() {
  const {
    instrumentId,
    setInstrumentId,
    referencePitch,
    setReferencePitch,
    demoMode,
    setDemoMode,
    onboardingOpen,
    completeOnboarding,
    closeOnboarding,
  } = useAppSettings();
  const [step, setStep] = useState(0);
  const navigate = useNavigate();
  const CurrentIcon = steps[step].icon;
  const progress = useMemo(() => `${step + 1} / ${steps.length}`, [step]);

  if (!onboardingOpen) return null;

  const finish = () => {
    completeOnboarding();
    navigate('/practice');
  };

  const skip = () => {
    completeOnboarding();
  };

  return (
    <div className="onboarding-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title">
      <section className="onboarding-panel">
        <button className="icon-button onboarding-close" type="button" aria-label="Close onboarding" onClick={closeOnboarding}>
          <X size={18} />
        </button>
        <div className="onboarding-progress">
          {steps.map((item, index) => (
            <span className={index <= step ? 'active' : ''} key={item.title} />
          ))}
        </div>
        <div className="onboarding-heading">
          <span className="insight-icon">
            <CurrentIcon size={20} />
          </span>
          <div>
            <p className="eyebrow">First-run setup {progress}</p>
            <h2 id="onboarding-title">{steps[step].title}</h2>
          </div>
        </div>

        {step === 0 && (
          <div className="onboarding-step">
            <p>BrassTune uses your selected instrument to transpose concert pitch into written notes and to reject pitches outside the expected range.</p>
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
          </div>
        )}

        {step === 1 && (
          <div className="onboarding-step">
            <p>A4 defaults to 440 Hz. Change it only when your ensemble or drone uses a different reference.</p>
            <label className="field">
              <span>A4 reference</span>
              <input type="number" min={430} max={450} step={0.5} value={referencePitch} onChange={(event) => setReferencePitch(Number(event.target.value))} />
            </label>
          </div>
        )}

        {step === 2 && (
          <div className="onboarding-step">
            <p>Demo mode gives repeatable seeded audio. Microphone mode is for real-device tuning validation and physical practice.</p>
            <div className="chip-row">
              <SelectionChip active={demoMode} onClick={() => setDemoMode(true)} tone="gold">Demo mode</SelectionChip>
              <SelectionChip active={!demoMode} onClick={() => setDemoMode(false)} tone="green">Microphone mode</SelectionChip>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="onboarding-step">
            <div className="insight-grid">
              <article className="insight-card tone-amber">
                <h3>No lock</h3>
                <p>The detector confidence is too low, so the frame is not saved into analytics.</p>
              </article>
              <article className="insight-card tone-green">
                <h3>Unstable pitch</h3>
                <p>The detector has a reliable lock, but your cents values vary over time enough to flag stability work.</p>
              </article>
            </div>
          </div>
        )}

        {step === 4 && (
          <div className="onboarding-step">
            <p>Start with a 30-second long-tone take. The tuner is useful now, but the product value comes from learning which notes you consistently miss.</p>
            <div className="onboarding-callout">
              <strong>{instrumentId}</strong>
              <span>A4 {referencePitch} Hz · {demoMode ? 'Demo audio' : 'Microphone mode'}</span>
            </div>
          </div>
        )}

        <div className="onboarding-actions">
          <button className="ghost-button" type="button" onClick={skip}>
            Skip
          </button>
          <div>
            {step > 0 && (
              <button className="ghost-button" type="button" onClick={() => setStep((value) => Math.max(0, value - 1))}>
                Back
              </button>
            )}
            {step < steps.length - 1 ? (
              <button className="primary-button" type="button" onClick={() => setStep((value) => value + 1)}>
                Next
                <ArrowRight size={18} />
              </button>
            ) : (
              <button className="primary-button" type="button" onClick={finish}>
                Start practice take
                <ArrowRight size={18} />
              </button>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
