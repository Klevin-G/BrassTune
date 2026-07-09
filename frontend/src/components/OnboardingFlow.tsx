import { ArrowRight, CheckCircle2, Gauge, Mic, Music2, Palette, SlidersHorizontal, Sparkles, X } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { InstrumentSelector } from './InstrumentSelector';
import { ThemeSelector } from './ThemeSelector';
import { SelectionChip } from './ui/AppPrimitives';

const steps = [
  { title: 'Welcome to BrassTune', icon: Sparkles },
  { title: 'Choose your brass voice', icon: Music2 },
  { title: 'Set the reference pitch', icon: SlidersHorizontal },
  { title: 'Pick the input mode', icon: Mic },
  { title: 'Read the lock status', icon: Gauge },
  { title: 'Make it yours', icon: Palette },
  { title: 'Record the first take', icon: CheckCircle2 },
];

/** A small animated tuner gauge shown on the welcome step. */
function TunerPreview() {
  return (
    <div className="onboarding-hero" aria-hidden="true">
      <svg viewBox="0 0 240 140" className="onboarding-gauge" role="presentation">
        <defs>
          <linearGradient id="ob-arc" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor="var(--red)" />
            <stop offset="0.5" stopColor="var(--green)" />
            <stop offset="1" stopColor="var(--red)" />
          </linearGradient>
        </defs>
        <path d="M24 122 A96 96 0 0 1 216 122" fill="none" stroke="var(--line)" strokeWidth="14" strokeLinecap="round" />
        <path d="M24 122 A96 96 0 0 1 216 122" fill="none" stroke="url(#ob-arc)" strokeWidth="4" strokeLinecap="round" opacity="0.85" />
        {[-60, -40, -20, 0, 20, 40, 60].map((deg) => (
          <line
            key={deg}
            x1="120"
            y1="34"
            x2="120"
            y2={deg === 0 ? '20' : '26'}
            stroke={deg === 0 ? 'var(--green)' : 'var(--muted-2)'}
            strokeWidth={deg === 0 ? 3 : 2}
            transform={`rotate(${deg} 120 122)`}
          />
        ))}
        <g className="onboarding-needle">
          <line x1="120" y1="122" x2="120" y2="40" stroke="var(--gold-soft)" strokeWidth="4" strokeLinecap="round" />
          <circle cx="120" cy="122" r="8" fill="var(--gold)" />
        </g>
      </svg>
      <span className="onboarding-hero-note">A4 · 440 Hz</span>
    </div>
  );
}

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
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const navigate = useNavigate();
  const CurrentIcon = steps[step].icon;
  const progress = useMemo(() => `${step + 1} / ${steps.length}`, [step]);

  useEffect(() => {
    if (!onboardingOpen) return;
    returnFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButtonRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        closeOnboarding();
        return;
      }
      if (event.key !== 'Tab' || !dialogRef.current) return;
      const focusable = Array.from(dialogRef.current.querySelectorAll<HTMLElement>('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      returnFocusRef.current?.focus();
    };
  }, [closeOnboarding, onboardingOpen]);

  if (!onboardingOpen) return null;

  const finish = () => {
    completeOnboarding();
    navigate('/practice');
  };

  const skip = () => {
    completeOnboarding();
  };

  const lastStep = steps.length - 1;

  return (
    <div className="onboarding-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef}>
      <section className="onboarding-panel">
        <button className="icon-button onboarding-close" type="button" aria-label="Close onboarding" onClick={closeOnboarding} ref={closeButtonRef}>
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
            <p className="eyebrow">{step === 0 ? 'Quick tour' : 'First-run setup'} {progress}</p>
            <h2 id="onboarding-title">{steps[step].title}</h2>
          </div>
        </div>

        {step === 0 && (
          <div className="onboarding-step">
            <div className="onboarding-brand">
              <span className="brand-mark"><Music2 size={22} /></span>
              <strong>BrassTune</strong>
            </div>
            <TunerPreview />
            <p>BrassTune listens as you play, shows how sharp or flat each note is in real time, and remembers the notes you keep missing so your practice actually improves. This 60-second tour gets you set up.</p>
            <div className="onboarding-facts">
              <span><Music2 size={15} /> Live tuner</span>
              <span><Gauge size={15} /> Note-by-note accuracy</span>
              <span><Sparkles size={15} /> Progress that sticks</span>
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="onboarding-step">
            <p>Pick your instrument so BrassTune transposes concert pitch into the notes you actually read, and ignores pitches outside its range.</p>
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
          </div>
        )}

        {step === 2 && (
          <div className="onboarding-step">
            <p>A4 defaults to 440 Hz. Only change it if your ensemble or drone tunes to a different reference.</p>
            <label className="field">
              <span>A4 reference</span>
              <input type="number" min={430} max={450} step={0.5} value={referencePitch} onChange={(event) => setReferencePitch(Number(event.target.value))} />
            </label>
          </div>
        )}

        {step === 3 && (
          <div className="onboarding-step">
            <p>Guided mode plays repeatable practice tones. Microphone mode listens to you live as you play.</p>
            <div className="chip-row">
              <SelectionChip active={demoMode} onClick={() => setDemoMode(true)} tone="gold">Guided mode</SelectionChip>
              <SelectionChip active={!demoMode} onClick={() => setDemoMode(false)} tone="green">Microphone mode</SelectionChip>
            </div>
          </div>
        )}

        {step === 4 && (
          <div className="onboarding-step">
            <p>Two labels tell you what the tuner is doing so you can trust every reading:</p>
            <div className="insight-grid">
              <article className="insight-card tone-amber">
                <h3>No lock</h3>
                <p>Confidence is too low to trust the note, so that frame is left out of your analytics.</p>
              </article>
              <article className="insight-card tone-green">
                <h3>Unstable pitch</h3>
                <p>The note is locked in, but your cents wander enough to flag as stability work.</p>
              </article>
            </div>
          </div>
        )}

        {step === 5 && (
          <div className="onboarding-step">
            <p>Choose a look that's easy on your eyes -- bright white, warm daylight, or a dark studio. You can change it anytime in Settings.</p>
            <ThemeSelector />
          </div>
        )}

        {step === lastStep && (
          <div className="onboarding-step">
            <p>You're set. Start with a 30-second long tone -- the tuner helps right away, and the real payoff is seeing which notes you consistently miss.</p>
            <div className="onboarding-callout">
              <strong>{instrumentId}</strong>
              <span>A4 {referencePitch} Hz · {demoMode ? 'Guided audio' : 'Microphone mode'}</span>
            </div>
          </div>
        )}

        <div className="onboarding-actions">
          <button className="ghost-button" type="button" onClick={skip}>
            Skip tour
          </button>
          <div>
            {step > 0 && (
              <button className="ghost-button" type="button" onClick={() => setStep((value) => Math.max(0, value - 1))}>
                Back
              </button>
            )}
            {step < lastStep ? (
              <button className="primary-button" type="button" onClick={() => setStep((value) => value + 1)}>
                {step === 0 ? 'Start tour' : 'Next'}
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
