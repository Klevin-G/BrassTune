import { AlertTriangle, BarChart3, Bug, Check, DatabaseBackup, Download, LogIn, LogOut, Mic, MicOff, RefreshCcw, RotateCcw, Trash2, UserRound } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { clearLocalSessions, downloadExport, friendlyUserFacingError, repairDemoData, resetDemoData } from '../api/client';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { ThemeSelector } from '../components/ThemeSelector';
import { PageHeader, ScreenContainer, SectionCard, SegmentedControl } from '../components/ui/AppPrimitives';
import { GUEST_WORKSPACE_ACCESS, guestSessionsExport } from '../domain/guestSessions';
import { PRACTICE_LIBRARY_PREFIX } from '../domain/practiceLibrary';
import { clearLocalScoreDocuments } from '../domain/scoreDocuments';
import { MAX_REFERENCE_PITCH, MIN_REFERENCE_PITCH, useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { useTheme } from '../state/ThemeContext';
import './SettingsPage.css';
import { gatewayPathWithReturn } from '../domain/authNavigation';
import { LocaleSelector } from '../components/LocaleSelector';
import { useI18n } from '../i18n/LocaleContext';
import { PracticeReflectionCard } from '../components/practice/PracticeReflectionCard';

function downloadTextFile(content: string, filename: string, type = 'application/json') {
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

type MicCheck = 'idle' | 'listening' | 'pass' | 'fail' | 'blocked';

// The server deliberately accepts one stable confirmation phrase. The UI can
// still require the translated phrase before enabling this irreversible action.
export const ACCOUNT_DELETION_BACKEND_CONFIRMATION = 'delete my account';

export function matchesLocalizedDeletionConfirmation(value: string, phrase: string, locale: string) {
  return value.trim().toLocaleLowerCase(locale) === phrase.toLocaleLowerCase(locale);
}

export function SettingsPage() {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode, openOnboarding } = useAppSettings();
  const auth = useAuth();
  const guestAccess = !auth.loading && !auth.isSignedIn && auth.guestMode ? GUEST_WORKSPACE_ACCESS : undefined;
  const location = useLocation();
  const practiceLibrary = usePracticeLibrary();
  const { setTheme } = useTheme();
  const { locale, t } = useI18n();
  const internalToolsEnabled = import.meta.env.VITE_ENABLE_INTERNAL_TOOLS === 'true';
  const [maintenanceStatus, setMaintenanceStatus] = useState('');
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [micCheck, setMicCheck] = useState<MicCheck>('idle');
  const [referencePitchInput, setReferencePitchInput] = useState(() => String(referencePitch));

  useEffect(() => {
    setReferencePitchInput(String(referencePitch));
  }, [referencePitch]);

  const commitReferencePitch = () => {
    const next = Number(referencePitchInput);
    if (Number.isFinite(next)) setReferencePitch(next);
    setReferencePitchInput(String(Math.min(MAX_REFERENCE_PITCH, Math.max(MIN_REFERENCE_PITCH, Number.isFinite(next) ? next : referencePitch))));
  };

  const runMaintenance = async (label: string, action: () => Promise<unknown>, confirmation?: string) => {
    if (confirmation && !window.confirm(confirmation)) return;
    setBusyAction(label);
    setMaintenanceStatus(t('settings.actionProgress', { action: label }));
    try {
      await action();
      setMaintenanceStatus(t('settings.actionComplete', { action: label }));
    } catch (error) {
      setMaintenanceStatus(locale === 'en' ? t('settings.actionFailedDetail', { action: label, error: friendlyUserFacingError(error) }) : t('settings.actionFailed', { action: label }));
    } finally {
      setBusyAction(null);
    }
  };

  const deleteAccount = async () => {
    if (!window.confirm(t('settings.deleteConfirmDialog'))) return;
    setBusyAction(t('settings.deleteAccount'));
    setMaintenanceStatus(t('settings.deletingAccount'));
    try {
      const result = await auth.deleteAccount(ACCOUNT_DELETION_BACKEND_CONFIRMATION);
      setMaintenanceStatus(t(result.deletionStatus && result.deletionStatus !== 'completed' ? 'settings.accountRemoved' : 'settings.accountDeleted'));
      setDeleteConfirmation('');
    } catch (error) {
      setMaintenanceStatus(locale === 'en' ? t('settings.deleteFailedDetail', { error: friendlyUserFacingError(error, t('settings.reconnect')) }) : t('settings.deleteFailed'));
    } finally {
      setBusyAction(null);
    }
  };

  const exportAllData = () => {
    if (auth.isSignedIn) {
      downloadExport('/api/users/me/export.zip', 'brasstune-account-export.zip')
        .then(() => setMaintenanceStatus(t('settings.exportDownloading')))
        .catch(() => setMaintenanceStatus(t('settings.exportUnavailable')));
      return;
    }
    downloadTextFile(guestSessionsExport(guestAccess), 'brasstune-guest-practice-export.json');
    setMaintenanceStatus(t('settings.historyDownloaded'));
  };

  const clearPreferences = () => {
    if (!window.confirm(t('settings.clearPreferencesConfirm'))) return;
    const preservedKeys = new Set([
      'brasstune.guestAccess',
      'brasstune.guestSessions.v1',
      'brasstune.guestOnboardingComplete',
      'brasstune.onboardingComplete',
    ]);
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .filter((key) => !preservedKeys.has(key) && !key.startsWith(PRACTICE_LIBRARY_PREFIX) && !key.startsWith('brasstune.playalong.best.'))
      .forEach((key) => localStorage.removeItem(key));
    setInstrumentId('trumpet');
    setReferencePitch(440);
    setDemoMode(false);
    setTheme('system');
    setMaintenanceStatus(t('settings.preferencesCleared'));
  };

  const runMicCheck = async () => {
    setMicCheck('listening');
    let mediaStream: MediaStream | null = null;
    let audioContext: AudioContext | null = null;
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const AudioCtx = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      audioContext = new AudioCtx();
      if (audioContext.state === 'suspended') await audioContext.resume().catch(() => undefined);
      const source = audioContext.createMediaStreamSource(mediaStream);
      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 2048;
      source.connect(analyser);
      const buffer = new Uint8Array(analyser.fftSize);
      let peak = 0;
      const startedAt = Date.now();
      await new Promise<void>((resolve) => {
        const tick = () => {
          analyser.getByteTimeDomainData(buffer);
          let localPeak = 0;
          for (let i = 0; i < buffer.length; i += 1) {
            localPeak = Math.max(localPeak, Math.abs(buffer[i] - 128));
          }
          peak = Math.max(peak, localPeak);
          if (Date.now() - startedAt >= 2500) {
            resolve();
          } else {
            window.setTimeout(tick, 100);
          }
        };
        tick();
      });
      setMicCheck(peak >= 8 ? 'pass' : 'fail');
    } catch {
      setMicCheck('blocked');
    } finally {
      mediaStream?.getTracks().forEach((track) => track.stop());
      audioContext?.close().catch(() => undefined);
    }
  };

  const statusMessage = (auth.profileError ? t('error.authUnavailable') : null) ?? (maintenanceStatus || null);
  const deleteReady = auth.isSignedIn && busyAction === null && matchesLocalizedDeletionConfirmation(deleteConfirmation, t('settings.deletePhrase'), locale);

  return (
    <ScreenContainer className="settings-screen">
      <PageHeader
        title={t('nav.settings')}
        description={t('settings.description')}
      />

      <div className="two-column-grid">
        <SectionCard className="settings-tuner-card set-group" title={t('nav.tuner')}>
          <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />

          <div className="set-choice">
            <label className="field">
              <span>{t('settings.reference')}</span>
              <input
                type="number"
                min={MIN_REFERENCE_PITCH}
                max={MAX_REFERENCE_PITCH}
                step={0.5}
                value={referencePitchInput}
                inputMode="decimal"
                aria-describedby="a4-reference-help"
                onChange={(event) => setReferencePitchInput(event.target.value)}
                onBlur={commitReferencePitch}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') event.currentTarget.blur();
                }}
              />
            </label>
            <p className="set-hint" id="a4-reference-help">{t('settings.referenceHelp')}</p>
            {referencePitch !== 440 && (
              <button className="ghost-button set-reset" type="button" onClick={() => setReferencePitch(440)}>
                <RotateCcw size={15} />
                {t('settings.reset440')}
              </button>
            )}
          </div>

          <div className="set-choice">
            <SegmentedControl
              ariaLabel={t('settings.soundInput')}
              value={demoMode ? 'demo' : 'mic'}
              onChange={(value) => setDemoMode(value === 'demo')}
              options={[
                { value: 'mic', label: t('settings.useMic') },
                { value: 'demo', label: t('settings.demoMode') },
              ]}
            />
            <p className="set-hint">{t('settings.demoHelp')}</p>
          </div>

          <div className="set-miccheck">
            <div className="set-miccheck-head">
              <strong>{t('settings.micCheck')}</strong>
              <span>{t('settings.micCheckHelp')}</span>
            </div>
            <button className="ghost-button set-miccheck-btn" type="button" onClick={runMicCheck} disabled={micCheck === 'listening'}>
              <Mic size={18} />
              {micCheck === 'listening' ? t('playAlong.listening') : t('settings.testMic')}
            </button>
            {micCheck === 'pass' && (
              <div className="set-miccheck-result is-pass" role="status" aria-live="polite" aria-atomic="true">
                <Check size={22} />
                <div>{t('settings.micPass')}<span>{t('settings.micPassBody')}</span></div>
              </div>
            )}
            {micCheck === 'fail' && (
              <div className="set-miccheck-result is-fail" role="status" aria-live="polite" aria-atomic="true">
                <MicOff size={22} />
                <div>{t('settings.micFail')}<span>{t('settings.micFailBody')}</span></div>
              </div>
            )}
            {micCheck === 'blocked' && (
              <div className="set-miccheck-result is-fail" role="status" aria-live="polite" aria-atomic="true">
                <MicOff size={22} />
                <div>{t('settings.micBlocked')}<span>{t('settings.micBlockedBody')}</span></div>
              </div>
            )}
          </div>

          <p className="set-field-note">
            {t('settings.inTuneHelp')}
          </p>
        </SectionCard>

        <SectionCard className="set-group" title={t('settings.appearance')}>
          <ThemeSelector />
        </SectionCard>
        <SectionCard className="set-group" title={t('locale.title')}>
          <p className="set-hint">{t('locale.hint')}</p>
          <LocaleSelector />
        </SectionCard>
      </div>

      <PracticeReflectionCard />

      <SectionCard className="settings-profile-card set-group" title={t('settings.account')}>
        <div className="account-card vertical">
          <span className="insight-icon">
            <UserRound size={18} />
          </span>
          <div>
            <strong>{auth.profile?.display_name ?? auth.user?.email ?? t('settings.guestPlayer')}</strong>
            <em>{auth.profile?.username ? `@${auth.profile.username}` : t('settings.guestDevice')}</em>
          </div>
        </div>
        {!auth.isSignedIn && (
          <p className="set-hint">{t('settings.guestAccountHelp')}</p>
        )}
        <div className="settings-actions">
          {auth.isSignedIn ? (
            <button className="ghost-button" type="button" onClick={() => auth.signOut().then(() => setMaintenanceStatus(t('settings.signedOut'))).catch(() => setMaintenanceStatus(t('settings.signOutFailed')))}>
              <LogOut size={18} />
              {t('settings.signOut')}
            </button>
          ) : (
            <Link
              className="primary-button"
              to={auth.configured ? gatewayPathWithReturn(`${location.pathname}${location.search}${location.hash}`) : '/home'}
              onClick={auth.configured ? auth.exitGuest : auth.continueAsGuest}
            >
              <LogIn size={18} />
              {auth.configured ? t('nav.signIn') : t('auth.continueGuest')}
            </Link>
          )}
          <button className="ghost-button" type="button" onClick={exportAllData}>
            <Download size={18} />
            {t(auth.isSignedIn ? 'settings.exportMyData' : 'settings.exportGuest')}
          </button>
          <button className="ghost-button" type="button" onClick={() => {
            downloadTextFile(JSON.stringify({ exportedAt: new Date().toISOString(), practiceLibrary: practiceLibrary.library }, null, 2), 'brasstune-practice-library.json');
            setMaintenanceStatus(t('settings.setupDownloaded'));
          }}>
            <DatabaseBackup size={18} />
            {t('settings.exportSetup')}
          </button>
          <button className="ghost-button" type="button" onClick={openOnboarding}>
            <RotateCcw size={18} />
            {t('settings.replayTour')}
          </button>
        </div>
        <div className="set-legal">
          <Link to="/privacy">{t('legal.privacy')}</Link>
          <Link to="/terms">{t('legal.terms')}</Link>
          <Link to="/support">{t('legal.support')}</Link>
        </div>
      </SectionCard>

      {auth.profile?.role === 'admin' && (
        <SectionCard title={t('settings.admin')} eyebrow={t('settings.private')}>
          <p className="muted-copy">{t('settings.adminBody')}</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/admin">
              <BarChart3 size={18} />
              {t('settings.openAdmin')}
            </Link>
          </div>
        </SectionCard>
      )}

      <SectionCard className="set-danger" title={t('settings.danger')}>
        <div className="set-danger-row">
          <strong>{t('settings.clearDevice')}</strong>
          <p>{t('settings.clearDeviceBody')}</p>
          <div className="settings-actions">
            <button className="ghost-button danger-action" type="button" onClick={clearPreferences}>
              <Trash2 size={18} />
              {t('settings.clearPreferences')}
            </button>
            <button className="ghost-button danger-action" type="button" onClick={() => runMaintenance(t('settings.clearScorePages'), clearLocalScoreDocuments, t('settings.clearScoreConfirm'))}>
              <Trash2 size={18} />
              {t('settings.clearSavedScores')}
            </button>
          </div>
        </div>
        {auth.isSignedIn ? (
          <div className="set-danger-row">
            <strong>{t('settings.deleteAccount')}</strong>
            <p>{t('settings.deleteAccountBody')}</p>
            <label className="field set-confirm-field">
              <span>{t('settings.typeDelete')}</span>
              <input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} placeholder={t('settings.deletePhrase')} />
            </label>
            <div className="settings-actions">
              <button className="ghost-button danger-action" type="button" disabled={!deleteReady} onClick={deleteAccount}>
                <AlertTriangle size={18} />
                {t('settings.deleteMyAccount')}
              </button>
            </div>
          </div>
        ) : (
          <div className="set-danger-row">
            <strong>{t('settings.guestRecordings')}</strong>
            <p>{t('settings.guestRecordingsBody')}</p>
            <div className="settings-actions">
              <Link className="ghost-button" to="/sessions">{t('settings.openRecordings')}</Link>
            </div>
          </div>
        )}
      </SectionCard>

      {internalToolsEnabled && (
        <SectionCard title={t('settings.internalControls')} eyebrow={t('settings.maintenance')}>
          <div className="settings-actions">
            <Link className="ghost-button" to="/settings/audio-lab">
              <Bug size={18} />
              {t('settings.openAudioLab')}
            </Link>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance(t('settings.repairDemo'), repairDemoData)}>
              <RefreshCcw size={18} />
              {t('settings.repairDemo')}
            </button>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance(t('settings.resetDemo'), resetDemoData, t('settings.resetDemoConfirm'))}>
              <DatabaseBackup size={18} />
              {t('settings.resetDemo')}
            </button>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance(t('settings.clearSessions'), clearLocalSessions, t('settings.clearSessionsConfirm'))}>
              <RotateCcw size={18} />
              {t('settings.clearSessions')}
            </button>
          </div>
        </SectionCard>
      )}

      {statusMessage && <p className="settings-status" role="status" aria-live="polite">{statusMessage}</p>}
    </ScreenContainer>
  );
}
