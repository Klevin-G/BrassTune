import { ArrowRight, Clock3, FolderOpen, Gauge, Music2, Settings, Sparkles, Target, TrendingUp, Users, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { InstrumentSelector } from './InstrumentSelector';
import './OnboardingFlow.css';

const STEPS = [
  { title: 'Welcome to BrassTune', icon: Sparkles },
  { title: 'Choose your instrument', icon: Music2 },
  { title: 'Tuner: hear and save', icon: Gauge },
  { title: 'Play-Along: practice steadily', icon: Target },
  { title: 'Metronome and sheet music', icon: Clock3 },
  { title: 'Recordings', icon: FolderOpen },
  { title: 'Progress and practice plan', icon: TrendingUp },
  { title: 'Class', icon: Users },
  { title: 'Settings and your next step', icon: Settings },
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

function FeatureList({ children }: { children: React.ReactNode }) {
  return <ul className="ob-feature-list">{children}</ul>;
}

export function OnboardingFlow() {
  const auth = useAuth();
  const {
    instrumentId,
    setInstrumentId,
    onboardingOpen,
    onboardingSaving,
    onboardingSaveError,
    completeOnboarding,
    retryOnboardingCompletion,
    closeOnboarding,
  } = useAppSettings();
  const [step, setStep] = useState(0);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const onboardingSavingRef = useRef(onboardingSaving);
  onboardingSavingRef.current = onboardingSaving;
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
        if (onboardingSavingRef.current) return;
        closeOnboarding();
        return;
      }
      if (event.key !== 'Tab' || !dialogRef.current) return;
      const focusable = Array.from(
        dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
      if (focusable.length === 0) {
        event.preventDefault();
        dialogRef.current.focus();
        return;
      }
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

  const finish = async (retry = false) => {
    const saved = await (retry ? retryOnboardingCompletion() : completeOnboarding());
    if (saved) navigate('/practice');
  };

  const primaryLabel = step === 0 ? 'Show me around' : step === lastStep ? 'Open the tuner' : 'Next';

  return (
    <div className="ob-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef} tabIndex={-1}>
      <section className="ob-panel">
        <button
          className="icon-button ob-close"
          type="button"
          aria-label="Close for now"
          onClick={closeOnboarding}
          disabled={onboardingSaving}
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
            <p className="ob-eyebrow">App tour · Step {step + 1} of {STEPS.length}</p>
            <h2 id="onboarding-title">{STEPS[step].title}</h2>
          </div>
        </div>

        {step === 0 && (
          <div className="ob-step">
            <TunerHero />
            <p className="ob-lead">BrassTune helps you tune, warm up, practice with a steady beat or drone, play your own exercises, save takes, and see what to work on next.</p>
            <div className="ob-audience-grid">
              <div>
                <strong>Practicing as a guest</strong>
                <span>Your recordings, progress, imported music, and preferences stay in this browser on this device.</span>
              </div>
              {auth.configured ? (
                <div>
                  <strong>Using an account</strong>
                  <span>Practice recorded while you are signed in follows your account. Existing guest takes stay on this device. Signing in also unlocks Class.</span>
                </div>
              ) : (
                <div>
                  <strong>This build is guest-only</strong>
                  <span>Account sync and Class need online account services, which are not configured in this build. All guest tools still work on this device.</span>
                </div>
              )}
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="ob-step">
            <p className="ob-lead">Choose the instrument you play. BrassTune uses it to show the written notes and range that make sense for your part.</p>
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
            <p className="ob-setup-note">You can change this later in the top bar or Settings.</p>
          </div>
        )}

        {step === 2 && (
          <div className="ob-step">
            <p className="ob-lead">The Tuner is your main practice screen.</p>
            <FeatureList>
              <li><strong>Live mic or Demo:</strong> use your microphone for real playing, or sample tones to learn the screen without mic access.</li>
              <li><strong>Pitch guide:</strong> the note, needle, and cents reading tell you whether you are flat, in tune, or sharp.</li>
              <li><strong>A4 reference:</strong> 440 Hz is standard; change it only when your teacher or ensemble uses another tuning reference.</li>
              <li><strong>Record and save:</strong> start a take, play, then stop and save it for playback and note-by-note review.</li>
              <li><strong>Warm-up and drone:</strong> resume a guided five-minute warm-up, or match a correctly transposed drone or interval tone. Stop tones before removing headphones.</li>
            </FeatureList>
          </div>
        )}

        {step === 3 && (
          <div className="ob-step">
            <p className="ob-lead">Play-Along turns scales and exercises into a guided practice round.</p>
            <FeatureList>
              <li><strong>Pick from the catalog:</strong> choose a scale or exercise, then use <em>Hear it</em> to hear the concert pitch you should play.</li>
              <li><strong>Hold the correct note steadily for 2 seconds:</strong> the progress indicator fills before BrassTune moves to the next note, so a brief accidental sound will not advance the exercise.</li>
              <li><strong>Stay in control:</strong> Skip note marks that note skipped; Stop exercise ends the round whenever you need.</li>
              <li><strong>Review the result:</strong> see your score, stars, tuning, and which notes need another try.</li>
              <li><strong>Make it yours:</strong> build a validated 1–32-note exercise, favorite useful drills, and practice evidence-backed transition drills from saved takes.</li>
            </FeatureList>
          </div>
        )}

        {step === 4 && (
          <div className="ob-step">
            <p className="ob-lead">Open these two tools from the Tuner.</p>
            <div className="ob-feature-cards">
              <div>
                <strong>Metronome</strong>
                <span>Set or tap the BPM, start and stop, adjust the beat, and save named presets for tempos you use often.</span>
              </div>
              <div>
                <strong>Sheet Music</strong>
                <span>Import a PDF or photo, scan with the camera, or drag in a file. View pages while you play, with page, zoom, rotate, fit, and focus controls. Imported music stays on this device.</span>
              </div>
            </div>
          </div>
        )}

        {step === 5 && (
          <div className="ob-step">
            <p className="ob-lead">Every saved take appears in Recordings.</p>
            <FeatureList>
              <li><strong>Listen and review:</strong> play back saved audio, open a take, and inspect its tuning summary and note-by-note results.</li>
              <li><strong>Export:</strong> download pitch data, note results, full data, and audio when available.</li>
              <li><strong>Delete:</strong> guest takes can be removed one at a time after a confirmation. Account takes can currently be reviewed and exported, but not deleted individually.</li>
              <li><strong>Know where it lives:</strong> guest takes stay in this browser; account takes are attached to the signed-in account.</li>
            </FeatureList>
          </div>
        )}

        {step === 6 && (
          <div className="ob-step">
            <p className="ob-lead">Progress turns your saved practice into a simple picture of what is improving.</p>
            <FeatureList>
              <li><strong>Charts:</strong> compare tuning accuracy and practice time over your selected date range.</li>
              <li><strong>Heatmap:</strong> choose a note to see where you tend to play sharp, flat, or in tune.</li>
              <li><strong>Practice plan:</strong> follow the short plan and recommended drills built from your results.</li>
              <li><strong>Streak:</strong> see how many days in a row you have practiced.</li>
              <li><strong>Goals and reflections:</strong> set a weekly minute goal and save a short note about what improved or what to try next.</li>
            </FeatureList>
          </div>
        )}

        {step === 7 && (
          <div className="ob-step">
            <p className="ob-lead">
              {auth.configured
                ? 'Class connects students and teachers. You must sign in to use it.'
                : 'Class connects students and teachers when online account services are configured. It is unavailable in this guest-only build.'}
            </p>
            <div className="ob-feature-cards">
              <div>
                <strong>Students</strong>
                <span>Join with a class code or accept an invitation, choose your instrument, view the class, and leave a class when allowed.</span>
              </div>
              <div>
                <strong>Teachers</strong>
                <span>Create a class, share or rotate its code, invite students, manage the roster, review class tuning trends, and print a report.</span>
              </div>
            </div>
          </div>
        )}

        {step === lastStep && (
          <div className="ob-step">
            <p className="ob-lead">Settings keeps the controls and account actions you may need later.</p>
            <FeatureList>
              <li><strong>Sound and look:</strong> change your instrument, A4 reference, microphone or Demo input, run a mic check, and choose a theme.</li>
              <li><strong>Account and data:</strong> export practice, clear preferences or imported score pages, and manage account sign-in or deletion when accounts are available. Guest recordings are managed individually from Recordings.</li>
              <li><strong>Help and choices:</strong> open Privacy, Terms, or Support, and use Replay tour whenever you want to see this guide again.</li>
              <li><strong>Focused packs:</strong> start a step-by-step practice pack from the Tuner. The app shell and pack instructions can work offline after a visit; account sync, microphone permission, and uncached audio keep their normal requirements.</li>
            </FeatureList>
            <div className="ob-first-action">
              <span className="ob-rec-dot" aria-hidden="true" />
              <p>Ready to begin? Open the Tuner, allow microphone access, press Save this take, and hold one comfortable note.</p>
            </div>
            <p className="ob-setup-note">Your instrument: <strong>{instrumentDisplayName(instrumentId)}</strong></p>
          </div>
        )}

        {onboardingSaveError && (
          <div className="ob-save-error" role="alert">
            <span>{onboardingSaveError}</span>
            <button className="ghost-button" type="button" onClick={() => void finish(true)} disabled={onboardingSaving}>
              {onboardingSaving ? 'Saving…' : 'Try saving again'}
            </button>
          </div>
        )}

        <div className="ob-actions">
          <button className="ghost-button" type="button" onClick={closeOnboarding} disabled={onboardingSaving}>
            Dismiss tour for now
          </button>
          <div>
            {step > 0 && (
              <button
                className="ghost-button"
                type="button"
                onClick={() => setStep((value) => Math.max(0, value - 1))}
                disabled={onboardingSaving}
              >
                Back
              </button>
            )}
            {step < lastStep ? (
              <button className="primary-button" type="button" onClick={() => setStep((value) => value + 1)} disabled={onboardingSaving}>
                {primaryLabel}
                <ArrowRight size={18} />
              </button>
            ) : (
              <button className="primary-button" type="button" onClick={() => void finish()} disabled={onboardingSaving}>
                {onboardingSaving ? 'Saving tour…' : primaryLabel}
                <ArrowRight size={18} />
              </button>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
