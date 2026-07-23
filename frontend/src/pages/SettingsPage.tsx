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

export function SettingsPage() {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode, openOnboarding } = useAppSettings();
  const auth = useAuth();
  const guestAccess = !auth.loading && !auth.isSignedIn && auth.guestMode ? GUEST_WORKSPACE_ACCESS : undefined;
  const location = useLocation();
  const practiceLibrary = usePracticeLibrary();
  const { setTheme } = useTheme();
  const { t } = useI18n();
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
    setMaintenanceStatus(`${label}...`);
    try {
      await action();
      setMaintenanceStatus(`${label} complete.`);
    } catch (error) {
      setMaintenanceStatus(`${label} failed: ${friendlyUserFacingError(error)}`);
    } finally {
      setBusyAction(null);
    }
  };

  const deleteAccount = async () => {
    if (!window.confirm('This permanently deletes your BrassTune account and your practice history. This cannot be undone. Continue?')) return;
    setBusyAction('Delete account');
    setMaintenanceStatus('Deleting account...');
    try {
      const result = await auth.deleteAccount(deleteConfirmation);
      setMaintenanceStatus(result.deletionStatus && result.deletionStatus !== 'completed' ? 'Your account data was removed and you were signed out.' : 'Account deleted. You were signed out.');
      setDeleteConfirmation('');
    } catch (error) {
      setMaintenanceStatus(`Couldn't delete your account: ${friendlyUserFacingError(error, 'Please try again after reconnecting.')}`);
    } finally {
      setBusyAction(null);
    }
  };

  const exportAllData = () => {
    if (auth.isSignedIn) {
      downloadExport('/api/users/me/export.zip', 'brasstune-account-export.zip')
        .then(() => setMaintenanceStatus('Your data export is downloading.'))
        .catch(() => setMaintenanceStatus('Export is unavailable right now. Please try again later.'));
      return;
    }
    downloadTextFile(guestSessionsExport(guestAccess), 'brasstune-guest-practice-export.json');
    setMaintenanceStatus('Your practice history was downloaded to this device.');
  };

  const clearPreferences = () => {
    if (!window.confirm('Clear BrassTune preferences on this device? Your practice history stays.')) return;
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
    setMaintenanceStatus('Preferences cleared on this device. Your practice history was kept.');
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

  const statusMessage = auth.profileError ?? (maintenanceStatus || null);
  const deleteReady = auth.isSignedIn && busyAction === null && deleteConfirmation.trim().toLowerCase() === 'delete my account';

  return (
    <ScreenContainer className="settings-screen">
      <PageHeader
        title="Settings"
        description="Set your instrument, tuning reference, theme, and account."
      />

      <div className="two-column-grid">
        <SectionCard className="settings-tuner-card set-group" title="Tuner">
          <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />

          <div className="set-choice">
            <label className="field">
              <span>Tuning reference (A4)</span>
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
            <p className="set-hint" id="a4-reference-help">Choose 430–450 Hz. Most bands tune to 440 Hz; change it only when your director asks.</p>
            {referencePitch !== 440 && (
              <button className="ghost-button set-reset" type="button" onClick={() => setReferencePitch(440)}>
                <RotateCcw size={15} />
                Reset to 440
              </button>
            )}
          </div>

          <div className="set-choice">
            <SegmentedControl
              ariaLabel="Sound input"
              value={demoMode ? 'demo' : 'mic'}
              onChange={(value) => setDemoMode(value === 'demo')}
              options={[
                { value: 'mic', label: 'Use my microphone' },
                { value: 'demo', label: 'Demo mode' },
              ]}
            />
            <p className="set-hint">Demo mode plays example tones so you can try the tuner without a microphone. For real feedback on your playing, use your microphone.</p>
          </div>

          <div className="set-miccheck">
            <div className="set-miccheck-head">
              <strong>Mic check</strong>
              <span>Play or sing a note for a couple of seconds to make sure we can hear you.</span>
            </div>
            <button className="ghost-button set-miccheck-btn" type="button" onClick={runMicCheck} disabled={micCheck === 'listening'}>
              <Mic size={18} />
              {micCheck === 'listening' ? 'Listening...' : 'Test my microphone'}
            </button>
            {micCheck === 'pass' && (
              <div className="set-miccheck-result is-pass" role="status" aria-live="polite" aria-atomic="true">
                <Check size={22} />
                <div>We can hear you!<span>Your microphone is working.</span></div>
              </div>
            )}
            {micCheck === 'fail' && (
              <div className="set-miccheck-result is-fail" role="status" aria-live="polite" aria-atomic="true">
                <MicOff size={22} />
                <div>We didn't hear a note<span>Play or sing louder, then test again.</span></div>
              </div>
            )}
            {micCheck === 'blocked' && (
              <div className="set-miccheck-result is-fail" role="status" aria-live="polite" aria-atomic="true">
                <MicOff size={22} />
                <div>We can't reach your microphone<span>Allow microphone access in your browser, then test again.</span></div>
              </div>
            )}
          </div>

          <p className="set-field-note">
            <strong>In tune</strong> means within about 5 cents of the note — a cent is a tiny slice of pitch, and 5 is about a hair's width. The tuner turns green when you're that close.
          </p>
        </SectionCard>

        <SectionCard className="set-group" title="Appearance">
          <ThemeSelector />
        </SectionCard>
        <SectionCard className="set-group" title={t('locale.title')}>
          <p className="set-hint">{t('locale.hint')}</p>
          <LocaleSelector />
        </SectionCard>
      </div>

      <PracticeReflectionCard />

      <SectionCard className="settings-profile-card set-group" title="Account">
        <div className="account-card vertical">
          <span className="insight-icon">
            <UserRound size={18} />
          </span>
          <div>
            <strong>{auth.profile?.display_name ?? auth.user?.email ?? 'Guest player'}</strong>
            <em>{auth.profile?.username ? `@${auth.profile.username}` : 'Practicing as a guest on this device.'}</em>
          </div>
        </div>
        {!auth.isSignedIn && (
          <p className="set-hint">Guest recordings you already made stay in this browser. Sign in to save future practice to your account and join a class.</p>
        )}
        <div className="settings-actions">
          {auth.isSignedIn ? (
            <button className="ghost-button" type="button" onClick={() => auth.signOut().then(() => setMaintenanceStatus('Signed out.')).catch(() => setMaintenanceStatus('Sign-out could not complete. Try again.'))}>
              <LogOut size={18} />
              Sign out
            </button>
          ) : (
            <Link
              className="primary-button"
              to={auth.configured ? gatewayPathWithReturn(`${location.pathname}${location.search}${location.hash}`) : '/home'}
              onClick={auth.configured ? auth.exitGuest : auth.continueAsGuest}
            >
              <LogIn size={18} />
              {auth.configured ? 'Sign in' : 'Continue as guest'}
            </Link>
          )}
          <button className="ghost-button" type="button" onClick={exportAllData}>
            <Download size={18} />
            {auth.isSignedIn ? 'Export my data' : 'Export guest practice'}
          </button>
          <button className="ghost-button" type="button" onClick={() => {
            downloadTextFile(JSON.stringify({ exportedAt: new Date().toISOString(), practiceLibrary: practiceLibrary.library }, null, 2), 'brasstune-practice-library.json');
            setMaintenanceStatus('Your local exercises, presets, goals, and reflections were downloaded.');
          }}>
            <DatabaseBackup size={18} />
            Export practice setup
          </button>
          <button className="ghost-button" type="button" onClick={openOnboarding}>
            <RotateCcw size={18} />
            Replay tour
          </button>
        </div>
        <div className="set-legal">
          <Link to="/privacy">Privacy</Link>
          <Link to="/terms">Terms</Link>
          <Link to="/support">Support</Link>
        </div>
      </SectionCard>

      {auth.profile?.role === 'admin' && (
        <SectionCard title="Admin" eyebrow="Private">
          <p className="muted-copy">Usage metrics for the whole app — user counts, active users, and feature usage.</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/admin">
              <BarChart3 size={18} />
              Open usage dashboard
            </Link>
          </div>
        </SectionCard>
      )}

      <SectionCard className="set-danger" title="Danger zone">
        <div className="set-danger-row">
          <strong>Clear this device</strong>
          <p>Resets your saved preferences on this device. Your practice history stays.</p>
          <div className="settings-actions">
            <button className="ghost-button danger-action" type="button" onClick={clearPreferences}>
              <Trash2 size={18} />
              Clear preferences
            </button>
            <button className="ghost-button danger-action" type="button" onClick={() => runMaintenance('Clear score pages', clearLocalScoreDocuments, 'Remove imported score PDFs and images saved on this device?')}>
              <Trash2 size={18} />
              Clear saved score pages
            </button>
          </div>
        </div>
        {auth.isSignedIn ? (
          <div className="set-danger-row">
            <strong>Delete account</strong>
            <p>This permanently deletes your account, your practice history, and any classes you own. It can't be undone. Export your data first if you want a copy. Score pages saved on this device are cleared separately.</p>
            <label className="field set-confirm-field">
              <span>Type "delete my account" to confirm</span>
              <input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} placeholder="delete my account" />
            </label>
            <div className="settings-actions">
              <button className="ghost-button danger-action" type="button" disabled={!deleteReady} onClick={deleteAccount}>
                <AlertTriangle size={18} />
                Delete my account
              </button>
            </div>
          </div>
        ) : (
          <div className="set-danger-row">
            <strong>Guest recordings</strong>
            <p>Guest takes are not an account. Manage or delete each one from Recordings, or export them first if you want a copy.</p>
            <div className="settings-actions">
              <Link className="ghost-button" to="/sessions">Open Recordings</Link>
            </div>
          </div>
        )}
      </SectionCard>

      {internalToolsEnabled && (
        <SectionCard title="Internal data controls" eyebrow="Maintenance">
          <div className="settings-actions">
            <Link className="ghost-button" to="/settings/audio-lab">
              <Bug size={18} />
              Open Audio Lab
            </Link>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance('Repair demo data', repairDemoData)}>
              <RefreshCcw size={18} />
              Repair demo data
            </button>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance('Reset demo data', resetDemoData, 'Reset generated practice data for this environment?')}>
              <DatabaseBackup size={18} />
              Reset demo data
            </button>
            <button className="ghost-button" type="button" disabled={busyAction !== null} onClick={() => runMaintenance('Clear sessions', clearLocalSessions, 'Delete your saved practice sessions and recordings?')}>
              <RotateCcw size={18} />
              Clear sessions
            </button>
          </div>
        </SectionCard>
      )}

      {statusMessage && <p className="settings-status" role="status" aria-live="polite">{statusMessage}</p>}
    </ScreenContainer>
  );
}
