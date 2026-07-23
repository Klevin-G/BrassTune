import { ArrowRight, Clock3, FolderOpen, Gauge, Music2, Settings, Sparkles, Target, TrendingUp, Users, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { InstrumentSelector } from './InstrumentSelector';
import './OnboardingFlow.css';

const STEPS = [
  { titleId: 'onboarding.title.welcome' as const, icon: Sparkles },
  { titleId: 'onboarding.title.instrument' as const, icon: Music2 },
  { titleId: 'onboarding.title.tuner' as const, icon: Gauge },
  { titleId: 'onboarding.title.playAlong' as const, icon: Target },
  { titleId: 'onboarding.title.tools' as const, icon: Clock3 },
  { titleId: 'onboarding.title.recordings' as const, icon: FolderOpen },
  { titleId: 'onboarding.title.progress' as const, icon: TrendingUp },
  { titleId: 'onboarding.title.class' as const, icon: Users },
  { titleId: 'onboarding.title.settings' as const, icon: Settings },
] as const;

const HERO_FRAMES = [
  { note: 'C', cents: 26 }, { note: 'C', cents: 9 }, { note: 'C', cents: 1 },
  { note: 'G', cents: -24 }, { note: 'G', cents: -7 }, { note: 'G', cents: 0 },
  { note: 'A', cents: 15 }, { note: 'A', cents: 3 }, { note: 'A', cents: 0 },
] as const;

function toneFor(cents: number): 'in-tune' | 'close' | 'off' {
  const offset = Math.abs(cents);
  if (offset <= 5) return 'in-tune';
  if (offset <= 15) return 'close';
  return 'off';
}

function TunerHero() {
  const { formatNumber, t } = useI18n();
  const [reduced] = useState(
    () => typeof window !== 'undefined' && Boolean(window.matchMedia?.('(prefers-reduced-motion: reduce)').matches),
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
  const centsLabel = Math.abs(frame.cents) <= 5
    ? t('onboarding.inTune')
    : frame.cents > 0 ? t('onboarding.sharp') : t('onboarding.flat');
  const formattedCents = `${frame.cents > 0 ? '+' : ''}${formatNumber(frame.cents)}`;

  return (
    <div className={`ob-hero ob-hero--${tone}`}>
      <svg viewBox="0 0 240 154" className="ob-gauge" role="img" aria-label={t('onboarding.gauge')}>
        <path d="M24 122 A96 96 0 0 1 216 122" fill="none" stroke="var(--line)" strokeWidth="14" strokeLinecap="round" />
        <path d="M24 122 A96 96 0 0 1 216 122" fill="none" stroke="var(--green)" strokeWidth="14" strokeLinecap="round" strokeDasharray="34 400" strokeDashoffset="-137" opacity="0.9" />
        {[-48, -32, -16, 0, 16, 32, 48].map((degree) => (
          <line
            key={degree}
            x1="120"
            y1="34"
            x2="120"
            y2={degree === 0 ? '18' : '26'}
            stroke={degree === 0 ? 'var(--green)' : 'var(--muted-2)'}
            strokeWidth={degree === 0 ? 3 : 2}
            transform={`rotate(${degree} 120 122)`}
          />
        ))}
        {tone === 'in-tune' && <circle className="ob-reward" cx="120" cy="122" r="26" fill="none" stroke="var(--green)" strokeWidth="3" />}
        <g className="ob-needle" transform={`rotate(${angle} 120 122)`}>
          <line x1="120" y1="122" x2="120" y2="38" stroke="currentColor" strokeWidth="4" strokeLinecap="round" />
          <circle cx="120" cy="122" r="9" fill="currentColor" />
        </g>
      </svg>
      <div className="ob-hero-readout" dir="ltr">
        <span className="ob-hero-note">{frame.note}</span>
        <span className="ob-hero-words">{centsLabel}</span>
        <span className="ob-hero-cents">{t('onboarding.cents', { value: formattedCents })}</span>
      </div>
    </div>
  );
}

export function OnboardingFlow() {
  const auth = useAuth();
  const { t } = useI18n();
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
        if (!onboardingSavingRef.current) closeOnboarding();
        return;
      }
      if (event.key !== 'Tab' || !dialogRef.current) return;
      const focusable = Array.from(dialogRef.current.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ));
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
  const primaryLabel = step === 0
    ? t('onboarding.show')
    : step === lastStep ? t('onboarding.openTuner') : t('onboarding.next');

  return (
    <div className="ob-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef} tabIndex={-1}>
      <section className="ob-panel">
        <button className="icon-button ob-close" type="button" aria-label={t('onboarding.close')} onClick={closeOnboarding} disabled={onboardingSaving} ref={closeButtonRef}>
          <X size={18} />
        </button>

        <div className="ob-progress" aria-hidden="true">
          {STEPS.map((item, index) => <span className={index <= step ? 'active' : ''} key={item.titleId} />)}
        </div>

        <div className="ob-heading">
          <span className="ob-heading-icon"><CurrentIcon size={20} /></span>
          <div>
            <p className="ob-eyebrow">{t('onboarding.eyebrow', { current: step + 1, total: STEPS.length })}</p>
            <h2 id="onboarding-title">{t(STEPS[step].titleId)}</h2>
          </div>
        </div>

        {step === 0 && (
          <div className="ob-step">
            <TunerHero />
            <p className="ob-lead">{t('onboarding.welcome')}</p>
            <div className="ob-audience-grid">
              <div><strong>{t('onboarding.guestTitle')}</strong><span>{t('onboarding.guestBody')}</span></div>
              {auth.configured
                ? <div><strong>{t('onboarding.accountTitle')}</strong><span>{t('onboarding.accountBody')}</span></div>
                : <div><strong>{t('onboarding.guestOnlyTitle')}</strong><span>{t('onboarding.guestOnlyBody')}</span></div>}
            </div>
          </div>
        )}

        {step === 1 && (
          <div className="ob-step">
            <p className="ob-lead">{t('onboarding.instrumentBody')}</p>
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
            <p className="ob-setup-note">{t('onboarding.instrumentHint')}</p>
          </div>
        )}
        {step === 2 && <div className="ob-step"><p className="ob-lead">{t('onboarding.tunerBody')}</p></div>}
        {step === 3 && <div className="ob-step"><p className="ob-lead">{t('onboarding.playAlongBody')}</p></div>}
        {step === 4 && <div className="ob-step"><p className="ob-lead">{t('onboarding.toolsBody')}</p></div>}
        {step === 5 && <div className="ob-step"><p className="ob-lead">{t('onboarding.recordingsBody')}</p></div>}
        {step === 6 && <div className="ob-step"><p className="ob-lead">{t('onboarding.progressBody')}</p></div>}
        {step === 7 && <div className="ob-step"><p className="ob-lead">{t(auth.configured ? 'onboarding.classAccountBody' : 'onboarding.classGuestBody')}</p></div>}
        {step === lastStep && (
          <div className="ob-step">
            <p className="ob-lead">{t('onboarding.settingsBody')}</p>
            <div className="ob-first-action"><span className="ob-rec-dot" aria-hidden="true" /><p>{t('onboarding.ready')}</p></div>
            <p className="ob-setup-note">{t('onboarding.instrumentSummary', { instrument: t(`instrument.${instrumentId}` as MessageId) })}</p>
          </div>
        )}

        {onboardingSaveError && (
          <div className="ob-save-error" role="alert">
            <span>{t(onboardingSaveError)}</span>
            <button className="ghost-button" type="button" onClick={() => void finish(true)} disabled={onboardingSaving}>
              {onboardingSaving ? t('onboarding.saving') : t('onboarding.retry')}
            </button>
          </div>
        )}

        <div className="ob-actions">
          <button className="ghost-button" type="button" onClick={closeOnboarding} disabled={onboardingSaving}>{t('onboarding.dismiss')}</button>
          <div>
            {step > 0 && (
              <button className="ghost-button" type="button" onClick={() => setStep((value) => Math.max(0, value - 1))} disabled={onboardingSaving}>
                {t('onboarding.back')}
              </button>
            )}
            {step < lastStep ? (
              <button className="primary-button" type="button" onClick={() => setStep((value) => value + 1)} disabled={onboardingSaving}>
                {primaryLabel}<ArrowRight size={18} />
              </button>
            ) : (
              <button className="primary-button" type="button" onClick={() => void finish()} disabled={onboardingSaving}>
                {onboardingSaving ? t('onboarding.saving') : primaryLabel}<ArrowRight size={18} />
              </button>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
