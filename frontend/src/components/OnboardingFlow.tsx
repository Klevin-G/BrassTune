import { ArrowRight, Music2, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '../i18n/LocaleContext';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { InstrumentSelector } from './InstrumentSelector';
import './OnboardingFlow.css';

export function OnboardingFlow() {
  const auth = useAuth();
  const { dir, t } = useI18n();
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
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const headingRef = useRef<HTMLHeadingElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const onboardingSavingRef = useRef(onboardingSaving);
  onboardingSavingRef.current = onboardingSaving;
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const steps = [
    { title: 'onboarding.title.instrument', body: 'onboarding.instrumentBody' },
    { title: 'onboarding.title.tuner', body: 'onboarding.tunerBody' },
    { title: 'onboarding.title.tools', body: 'onboarding.toolsBody' },
    { title: 'onboarding.title.progress', body: 'onboarding.progressBody' },
    { title: 'onboarding.title.settings', body: 'onboarding.settingsBody' },
  ] as const;
  const currentStep = steps[step];

  useEffect(() => {
    if (!onboardingOpen) return undefined;
    setStep(0);
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
      const activeElement = document.activeElement;
      if (!dialogRef.current.contains(activeElement) || activeElement === dialogRef.current) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      } else if (event.shiftKey && activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      returnFocusRef.current?.focus();
    };
  }, [closeOnboarding, onboardingOpen]);

  useEffect(() => {
    if (!onboardingOpen) return;
    const frame = window.requestAnimationFrame(() => headingRef.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, [onboardingOpen, step]);

  useEffect(() => {
    if (!onboardingOpen || !onboardingSaving) return undefined;
    const frame = window.requestAnimationFrame(() => dialogRef.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, [onboardingOpen, onboardingSaving]);

  if (!onboardingOpen) return null;

  const finish = async (retry = false) => {
    const saved = await (retry ? retryOnboardingCompletion() : completeOnboarding());
    if (saved) navigate('/practice');
  };

  return (
    <div className="ob-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef} tabIndex={-1}>
      <section className="ob-panel">
        <button className="icon-button ob-close" type="button" aria-label={t('onboarding.close')} onClick={closeOnboarding} disabled={onboardingSaving} ref={closeButtonRef}>
          <X size={18} />
        </button>

        <div className="ob-heading">
          <span className="ob-heading-icon"><Music2 size={20} /></span>
          <div>
            <p className="ob-eyebrow">{t('onboarding.eyebrow', { current: step + 1, total: steps.length })}</p>
            <h2 id="onboarding-title" ref={headingRef} tabIndex={-1}>{t(currentStep.title)}</h2>
          </div>
        </div>

        <div className="ob-step">
          <p className="ob-lead">{t(currentStep.body)}</p>
          {step === 0 && <><InstrumentSelector value={instrumentId} onChange={setInstrumentId} /><p className="ob-setup-note">{t('onboarding.instrumentHint')}</p></>}
          {step === 4 && <p className="ob-setup-note">{t('onboarding.ready')}</p>}
          {(step === 0 || step === 4) && <div className="ob-audience-grid">
            {auth.isSignedIn ? <div><strong>{t('onboarding.accountTitle')}</strong><span>{t('onboarding.accountBody')}</span></div> : <div><strong>{t('onboarding.guestTitle')}</strong><span>{t('onboarding.guestBody')}</span></div>}
          </div>}
        </div>

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
          {step > 0 && <button className="ghost-button" type="button" onClick={() => setStep((current) => current - 1)} disabled={onboardingSaving}>{t('onboarding.back')}</button>}
          <button className="primary-button" type="button" onClick={() => step === steps.length - 1 ? void finish() : setStep((current) => current + 1)} disabled={onboardingSaving}>
            {onboardingSaving ? t('onboarding.saving') : step === steps.length - 1 ? t('onboarding.openTuner') : t('onboarding.next')}
            <ArrowRight size={18} style={{ transform: dir === 'rtl' ? 'scaleX(-1)' : undefined }} />
          </button>
        </div>
      </section>
    </div>
  );
}
