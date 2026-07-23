import { ArrowRight, Music2, X } from 'lucide-react';
import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useI18n } from '../i18n/LocaleContext';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { InstrumentSelector } from './InstrumentSelector';
import './OnboardingFlow.css';

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
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const onboardingSavingRef = useRef(onboardingSaving);
  onboardingSavingRef.current = onboardingSaving;
  const navigate = useNavigate();

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

  return (
    <div className="ob-backdrop" role="dialog" aria-modal="true" aria-labelledby="onboarding-title" ref={dialogRef} tabIndex={-1}>
      <section className="ob-panel">
        <button className="icon-button ob-close" type="button" aria-label={t('onboarding.close')} onClick={closeOnboarding} disabled={onboardingSaving} ref={closeButtonRef}>
          <X size={18} />
        </button>

        <div className="ob-heading">
          <span className="ob-heading-icon"><Music2 size={20} /></span>
          <div>
            <p className="ob-eyebrow">{t('onboarding.eyebrow', { current: 1, total: 1 })}</p>
            <h2 id="onboarding-title">{t('onboarding.title.instrument')}</h2>
          </div>
        </div>

        <div className="ob-step">
          <p className="ob-lead">{t('onboarding.instrumentBody')}</p>
          <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
          <p className="ob-setup-note">{t('onboarding.instrumentHint')}</p>
          <div className="ob-audience-grid">
            {auth.isSignedIn
              ? <div><strong>{t('onboarding.accountTitle')}</strong><span>{t('onboarding.accountBody')}</span></div>
              : <div><strong>{t('onboarding.guestTitle')}</strong><span>{t('onboarding.guestBody')}</span></div>}
            {!auth.configured && (
              <div><strong>{t('onboarding.guestOnlyTitle')}</strong><span>{t('onboarding.guestOnlyBody')}</span></div>
            )}
          </div>
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
          <button className="primary-button" type="button" onClick={() => void finish()} disabled={onboardingSaving}>
            {onboardingSaving ? t('onboarding.saving') : t('onboarding.openTuner')}<ArrowRight size={18} />
          </button>
        </div>
      </section>
    </div>
  );
}
