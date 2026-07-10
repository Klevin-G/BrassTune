import { ArrowRight, Gauge, Mic, Music2, Sparkles, TrendingUp, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAppSettings } from '../state/AppSettingsContext';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { InstrumentSelector } from './InstrumentSelector';
import './OnboardingFlow.css';

const STEPS = [
  { title: 'Welcome to BrassTune', icon: Sparkles },
  { title: 'Pick your instrument', icon: Music2 },
  { title: 'Record your first note', icon: Mic },
] as const;

// A short, looping demo where a played note pushes the needle sharp/flat and
// finally settles in tune — the core loop, shown not told.
const HERO_FRAMES = [
  { note: 'C', cents: 26 },
  { note: 'C', cents: 9 },
  { note: 'C', cents: 1 },
  { note: 'G', cents: -24 },
  { note: 'G', cents: -7 },
  { note: 'G', cents: 0 },
  { note: 'A', cents: 15 },
  { note: 'A', cents: 3 },
  { note: 'A', cents: 0 },
] as const;

function toneFor(cents: number): 'in-tune' | 'close' | 'off' {
  const off = Math.abs(cents);
  if (off <= 5) return 'in-tune';
  if (off <= 15) return 'close';
  return 'off';
}

function centsWords(cents: number): string {
  if (Math.abs(cents) <= 5) return 'In tune';
  return cents > 0 ? 'A little sharp' : 'A little flat';
}

/** Animated brass tuner hero for the welcome step. */
function TunerHero() {
  const [reduced] = useState(
    () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  );
  const [index, setIndex] = useState(0);
  useEffect(() => {
    if (reduced) return undefined;
    const id = window.setInterval(() => setIndex((value) => (value + 1) % HERO_FRAMES.length), 950);
    return () => window.clearInterval(id);
  }, [reduced]);

  const frame = reduced ? { note: 'A', cents: 0 } : HERO_FRAMES[index];
  const clamped = Math.max(-50, Math.min(50, frame.cents));
  const angle = (clamped / 50) * 48;
  const tone = toneFor(frame.cents);

  return (
    <div className={`ob-hero ob-hero--${tone}`}>
      <svg viewBox="0 0 240 154" className="ob-gauge" role="img" aria-label="Live tuner showing a note in tune">
        <path d="M24 122 A96 96 0 0 1 216 122" fill="none" stroke="var(--line)" strokeWidth="14" strokeLinecap="round" />
        <path
          d="M24 122 A96 96 0 0 1 216 122"
          fill="none"
          stroke="var(--green)"
          strokeWidth="14"
          strokeLinecap="round"
          strokeDasharray="34 400"
          strokeDashoffset="-137"
          opacity="0.9"
        />
        {[-48, -32, -16, 0, 16, 32, 48].map((deg) => (
          <line
            key={deg}
            x1="120"
            y1="34"
            x2="120"
            y2={deg === 0 ? '18' : '26'}
            stroke={deg === 0 ? 'var(--green)' : 'var(--muted-2)'}
            strokeWidth={deg === 0 ? 3 : 2}
            transform={`rotate(${deg} 120 122)`}
          />
        ))}
        {tone === 'in-tune' && <circle className="ob-reward" cx="120" cy="122" r="26" fill="none" stroke="var(--green)" strokeWidth="3" />}
        <g className="ob-needle" transform={`rotate(${angle} 120 122)`}>
          <line x1="120" y1="122" x2="120" y2="38" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
          <circle cx="120" cy="122" r="9" fill="currentColor" />
        </g>
      </svg>
      <div className="ob-hero-readout">
        <span className="ob-hero-note">{frame.note}</span>
        <span className="ob-hero-words">{centsWords(frame.cents)}</span>
        <span className="ob-hero-cents">{frame.cents > 0 ? `+${frame.cents}` : frame.cents} cents</span>
      </div>
    </div>
  );
}

export function OnboardingFlow() {
  const { instrumentId, setInstrumentId, onboardingOpen, completeOnboarding, closeOnboarding } = useAppSettings();
  const [step, setStep] = useState(0);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const navigate = useNavigate();
  const CurrentIcon = STEPS[step].icon;
  const lastStep = STEPS.length - 1;

  useEffect(() => {
    if (onboardingOpen) setStep(0);
  }, [onboardingOpen]);

  useEffect(() => {
    if (!onboardingOpen) return undefined;
    returnFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    closeButtonRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        closeOnboarding();
        return;
      }
      if (event.key !== 'Tab' || !dialogRef.current) return;
      const focusable = Array.from(
        dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
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

  const primaryLabel = step === 0 ? 'Take the tour' : step === lastStep ? 'Start playing' : 'Next';

  return (
    <div className="ob-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef}>
      <section className="ob-panel">
        <button
          className="icon-button ob-close"
          type="button"
          aria-label="Close for now"
          onClick={closeOnboarding}
          ref={closeButtonRef}
        >
          <X size={18} />
        </button>

        <div className="ob-progress" aria-hidden="true">
          {STEPS.map((item, index) => (
            <span className={index <= step ? 'active' : ''} key={item.title} />
          ))}
        </div>

        <div className="ob-heading">
          <span className="ob-heading-icon">
            <CurrentIcon size={20} />
          </span>
          <div>
            <p className="ob-eyebrow">Getting started · Step {step + 1} of {STEPS.length}</p>
            <h2 id="onboarding-title">{STEPS[step].title}</h2>
          </div>
        </div>

        {step === 0 && (
          <div className="ob-step">
            <TunerHero />
            <p className="ob-lead">
              Play along with an exercise and BrassTune scores how in-tune and in-time you were, and shows exactly which
              notes to fix. Let's get you playing in under a minute.
            </p>
            <div className="ob-facts">
              <span><Sparkles size={15} /> AI Play-Along score</span>
              <span><Gauge size={15} /> Live tuner</span>
              <span><TrendingUp size={15} /> Tracks your progress</span>
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="ob-step">
            <p className="ob-lead">Pick your instrument so we show the note names you actually read.</p>
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
          </div>
        )}

        {step === lastStep && (
          <div className="ob-step">
            <p className="ob-lead">Here's where everything lives — you can reach these anytime from the menu.</p>
            <ul className="ob-nav-guide">
              <li>
                <span className="ob-nav-icon"><Gauge size={17} /></span>
                <div>
                  <strong>Tuner</strong>
                  <span>See instantly if you're sharp or flat.</span>
                </div>
              </li>
              <li>
                <span className="ob-nav-icon"><Sparkles size={17} /></span>
                <div>
                  <strong>Play-Along</strong>
                  <span>Play an exercise and get a score.</span>
                </div>
              </li>
              <li>
                <span className="ob-nav-icon"><TrendingUp size={17} /></span>
                <div>
                  <strong>Progress</strong>
                  <span>Watch your tuning improve over time.</span>
                </div>
              </li>
            </ul>
            <div className="ob-first-action">
              <span className="ob-rec-dot" aria-hidden="true" />
              <p>You're ready. Press Record and play any note — you'll see instantly if you're sharp or flat.</p>
            </div>
            <p className="ob-setup-note">Your instrument: <strong>{instrumentDisplayName(instrumentId)}</strong></p>
          </div>
        )}

        <div className="ob-actions">
          <button className="ghost-button" type="button" onClick={completeOnboarding}>
            Skip
          </button>
          <div>
            {step > 0 && (
              <button className="ghost-button" type="button" onClick={() => setStep((value) => Math.max(0, value - 1))}>
                Back
              </button>
            )}
            {step < lastStep ? (
              <button className="primary-button" type="button" onClick={() => setStep((value) => value + 1)}>
                {primaryLabel}
                <ArrowRight size={18} />
              </button>
            ) : (
              <button className="primary-button" type="button" onClick={finish}>
                {primaryLabel}
                <ArrowRight size={18} />
              </button>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
