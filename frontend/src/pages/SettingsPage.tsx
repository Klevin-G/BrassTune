import { BarChart3, Bug, DatabaseBackup, Download, LogIn, LogOut, RefreshCcw, RotateCcw, SlidersHorizontal, Trash2, UserRound } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { clearLocalSessions, downloadExport, friendlyUserFacingError, repairDemoData, resetDemoData } from '../api/client';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { ThemeSelector } from '../components/ThemeSelector';
import { InsightCard, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { guestSessionsExport } from '../domain/guestSessions';
import { clearLocalScoreDocuments } from '../domain/scoreDocuments';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

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

export function SettingsPage() {
  const { instrumentId, setInstrumentId, referencePitch, setReferencePitch, demoMode, setDemoMode, openOnboarding } = useAppSettings();
  const auth = useAuth();
  const internalToolsEnabled = import.meta.env.VITE_ENABLE_INTERNAL_TOOLS === 'true';
  const [maintenanceStatus, setMaintenanceStatus] = useState('Ready');
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [deleteConfirmation, setDeleteConfirmation] = useState('');

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
    if (!window.confirm('This permanently deletes your BrassTune account data and owned ensembles according to the documented policy. Local score pages saved on this device are separate. Continue?')) return;
    setBusyAction('Delete account');
    setMaintenanceStatus('Delete account...');
    try {
      const result = await auth.deleteAccount(deleteConfirmation);
      setMaintenanceStatus(result.deletionStatus && result.deletionStatus !== 'completed' ? 'Account data was removed and this browser was signed out. External identity cleanup is queued.' : 'Account deleted and this browser was signed out.');
      setDeleteConfirmation('');
    } catch (error) {
      setMaintenanceStatus(`Delete account failed: ${friendlyUserFacingError(error, 'Account deletion could not complete. Try again after reconnecting.')}`);
    } finally {
      setBusyAction(null);
    }
  };

  const exportAllData = () => {
    if (auth.isSignedIn) {
      downloadExport('/api/users/me/export.zip', 'brasstune-account-export.zip').catch(() => setMaintenanceStatus('Cloud export is unavailable right now. Try again later.'));
      return;
    }
    downloadTextFile(guestSessionsExport(), 'brasstune-guest-practice-export.json');
    setMaintenanceStatus('Guest practice sessions export downloaded from this device.');
  };

  const clearPreferences = () => {
    if (!window.confirm('Clear BrassTune preferences on this device?')) return;
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .filter((key) => key !== 'brasstune.guestSessions.v1')
      .forEach((key) => localStorage.removeItem(key));
    setMaintenanceStatus('Preferences cleared on this device. Guest sessions were preserved.');
  };

  return (
    <ScreenContainer className="settings-screen">
      <PageHeader
        eyebrow="Settings"
        title="Practice preferences"
        description="Keep the tuner behavior explicit: instrument transposition, reference pitch, guided audio, account access, export, and deletion controls."
        meta={<StatusBadge tone="gold">{instrumentId}</StatusBadge>}
      />
      <div className="two-column-grid">
        <SectionCard className="settings-tuner-card" title="Tuner setup" eyebrow="Core controls">
          <div className="settings-grid">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
            <label className="field">
              <span>Reference pitch</span>
              <input type="number" min={430} max={450} step={0.5} value={referencePitch} onChange={(event) => setReferencePitch(Number(event.target.value))} />
            </label>
            <label className="switch-row">
              <span>Guided audio (practice tones)</span>
              <input type="checkbox" checked={demoMode} onChange={(event) => setDemoMode(event.target.checked)} />
            </label>
            <label className="field">
              <span>In-tune threshold</span>
              <output>+/-5 cents</output>
            </label>
          </div>
        </SectionCard>
        <SectionCard className="settings-profile-card" title="Profile" eyebrow={auth.isSignedIn ? 'Account' : 'Guest practice'}>
          <div className="account-card vertical">
            <span className="insight-icon">
              <UserRound size={18} />
            </span>
            <div>
              <strong>{auth.profile?.display_name ?? auth.user?.email ?? 'Guest player'}</strong>
              <em>{auth.profile?.username ? `@${auth.profile.username}` : 'Sign in to sync sessions and ensemble membership.'}</em>
            </div>
          </div>
          <div className="settings-actions">
            {auth.isSignedIn ? (
              <button className="ghost-button" type="button" onClick={() => auth.signOut().then(() => setMaintenanceStatus('Signed out.')).catch(() => setMaintenanceStatus('Sign-out could not complete. Try again.'))}>
                <LogOut size={18} />
                Sign out
              </button>
            ) : (
              <Link className="primary-button" to={auth.configured ? '/' : '/home'} onClick={!auth.configured ? auth.continueAsGuest : undefined}>
                <LogIn size={18} />
                {auth.configured ? 'Sign in' : 'Continue as guest'}
              </Link>
            )}
          </div>
          <div className="settings-actions">
            <Link className="ghost-button" to="/privacy">Privacy</Link>
            <Link className="ghost-button" to="/terms">Terms</Link>
            <Link className="ghost-button" to="/support">Support</Link>
          </div>
        </SectionCard>
        <SectionCard title="Appearance" eyebrow="Theme">
          <ThemeSelector />
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
        <SectionCard title="Practice tools" eyebrow="Device and data">
          <p className="muted-copy">Microphone diagnostics, reopening the setup tour, exports, and clearing device data.</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/settings/audio-lab">
              <Bug size={18} />
              Open Audio Lab
            </Link>
            <button className="ghost-button" type="button" onClick={openOnboarding}>
              <SlidersHorizontal size={18} />
              Reopen onboarding
            </button>
            <button className="ghost-button" type="button" onClick={exportAllData}>
              <Download size={18} />
              Export all data
            </button>
            <button className="ghost-button" type="button" onClick={clearPreferences}>
              <Trash2 size={18} />
              Clear preferences
            </button>
            <button className="ghost-button" type="button" onClick={() => runMaintenance('Clear local score pages', clearLocalScoreDocuments, 'Remove imported score PDFs and images saved on this device?')}>
              <Trash2 size={18} />
              Clear local score pages
            </button>
          </div>
        </SectionCard>
      </div>
      {internalToolsEnabled && (
        <SectionCard title="Internal data controls" eyebrow="Maintenance">
          <div className="settings-actions">
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
          <p className="settings-status" role="status" aria-live="polite">{maintenanceStatus}</p>
        </SectionCard>
      )}
      {!internalToolsEnabled && <p className="settings-status" role="status" aria-live="polite">{auth.profileError ?? maintenanceStatus}</p>}
      <SectionCard title="Delete account" eyebrow="Account lifecycle">
        <p className="muted-copy">Export your data first. Deletion removes your profile, sessions, pitch samples, note events, recommendations, group memberships, and owned ensembles. Teacher-owned groups are deleted with their memberships and invitations. Local score pages saved on this device are cleared separately.</p>
        <div className="settings-actions">
          <button
            className="ghost-button"
            type="button"
            onClick={auth.isSignedIn ? () => downloadExport('/api/users/me/export.zip', 'brasstune-account-export.zip').catch((error) => setMaintenanceStatus(`Export failed: ${friendlyUserFacingError(error, 'Cloud export is unavailable right now. Try again later.')}`)) : exportAllData}
          >
            <Download size={18} />
            Export account data
          </button>
        </div>
        <label className="field">
          <span>Type delete my account</span>
          <input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} placeholder="delete my account" />
        </label>
        <button className="ghost-button danger-action" type="button" disabled={!auth.isSignedIn || busyAction !== null || deleteConfirmation.trim().toLowerCase() !== 'delete my account'} onClick={deleteAccount}>
          <Trash2 size={18} />
          Delete account
        </button>
      </SectionCard>
      <SectionCard title="Beta limitations" eyebrow="What sync requires">
        <InsightCard
          title="Guest practice stays on this device"
          detail="Sign in to sync"
          body="Account sync, ensemble membership, and cloud exports require beta account access. Guest practice remains available in this browser."
          icon={SlidersHorizontal}
        />
      </SectionCard>
    </ScreenContainer>
  );
}
