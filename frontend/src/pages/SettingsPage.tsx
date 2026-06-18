import { Bug, DatabaseBackup, Download, LogIn, LogOut, RefreshCcw, RotateCcw, SlidersHorizontal, Trash2, UserRound } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { clearLocalSessions, downloadExport, repairDemoData, resetDemoData } from '../api/client';
import { InstrumentSelector } from '../components/InstrumentSelector';
import { InsightCard, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

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
      const result = await action();
      setMaintenanceStatus(`${label} complete: ${JSON.stringify(result)}`);
    } catch (error) {
      setMaintenanceStatus(`${label} failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setBusyAction(null);
    }
  };

  const deleteAccount = async () => {
    await runMaintenance('Delete account', () => auth.deleteAccount(deleteConfirmation), 'This permanently deletes your BrassTune account data and owned ensembles according to the documented policy. Continue?');
    setDeleteConfirmation('');
  };

  const clearPreferences = () => {
    if (!window.confirm('Clear BrassTune preferences on this device?')) return;
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .forEach((key) => localStorage.removeItem(key));
    setMaintenanceStatus('Preferences cleared on this device.');
  };

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Settings"
        title="Practice preferences"
        description="Keep the tuner behavior explicit: instrument transposition, reference pitch, guided audio, account access, export, and deletion controls."
        meta={<StatusBadge tone="gold">{instrumentId}</StatusBadge>}
      />
      <div className="two-column-grid">
        <SectionCard title="Tuner setup" eyebrow="Core controls">
          <div className="settings-grid">
            <InstrumentSelector value={instrumentId} onChange={setInstrumentId} />
            <label className="field">
              <span>Reference pitch</span>
              <input type="number" min={430} max={450} step={0.5} value={referencePitch} onChange={(event) => setReferencePitch(Number(event.target.value))} />
            </label>
            <label className="switch-row">
              <span>Demo mode</span>
              <input type="checkbox" checked={demoMode} onChange={(event) => setDemoMode(event.target.checked)} />
            </label>
            <label className="field">
              <span>In-tune threshold</span>
              <input type="text" value="+/-5 cents" readOnly />
            </label>
          </div>
        </SectionCard>
        <SectionCard title="Profile" eyebrow={auth.isSignedIn ? 'Account' : 'Guest practice'}>
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
              <button className="ghost-button" type="button" onClick={() => auth.signOut()}>
                <LogOut size={18} />
                Sign out
              </button>
            ) : (
              <Link className="primary-button" to="/auth/sign-in">
                <LogIn size={18} />
                Sign in
              </Link>
            )}
          </div>
          <div className="settings-actions">
            <Link className="ghost-button" to="/privacy">Privacy</Link>
            <Link className="ghost-button" to="/terms">Terms</Link>
            <Link className="ghost-button" to="/support">Support</Link>
          </div>
        </SectionCard>
        <SectionCard title="Practice tools" eyebrow="Device and data">
          <div className="insight-grid">
            <InsightCard
              title="Audio Lab"
              detail="Microphone checks"
              body="Open the calibration readout for microphone checks, save eligibility, and detector diagnostics."
              icon={Bug}
              tone="gold"
            />
            <InsightCard
              title="Onboarding"
              detail="First-run flow"
              body="Reopen instrument setup, reference pitch, input mode, and the No lock versus unstable pitch explanation."
              icon={SlidersHorizontal}
            />
            <InsightCard
              title="Export all local data"
              detail="JSON"
              body="Download the practice data available to this browser or account scope."
              icon={Download}
              tone="gold"
            />
            <InsightCard
              title="Clear preferences"
              detail="Browser storage"
              body="Resets local UI preferences without touching saved backend sessions."
              icon={Trash2}
              tone="red"
            />
          </div>
          <div className="settings-actions">
            <Link className="primary-button" to="/settings/audio-lab">
              <Bug size={18} />
              Open Audio Lab
            </Link>
            <button className="ghost-button" type="button" onClick={openOnboarding}>
              <SlidersHorizontal size={18} />
              Reopen onboarding
            </button>
            <button className="ghost-button" type="button" onClick={() => downloadExport('/api/export/all.zip', 'brasstune-export.zip')}>
              <Download size={18} />
              Export all data
            </button>
            <button className="ghost-button" type="button" onClick={clearPreferences}>
              <Trash2 size={18} />
              Clear preferences
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
          <p className="settings-status" aria-live="polite">{maintenanceStatus}</p>
        </SectionCard>
      )}
      {!internalToolsEnabled && <p className="settings-status" aria-live="polite">{maintenanceStatus}</p>}
      <SectionCard title="Delete account" eyebrow="Account lifecycle">
        <p className="muted-copy">Export your data first. Deletion removes your profile, sessions, pitch samples, note events, recommendations, group memberships, and owned ensembles. Teacher-owned groups are deleted with their memberships and invitations.</p>
        <div className="settings-actions">
          <button className="ghost-button" type="button" onClick={() => downloadExport('/api/users/me/export.zip', 'brasstune-account-export.zip')}>
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
      <SectionCard title="Portability note" eyebrow="Swift-ready core">
        <InsightCard
          title="Pure domain logic stays portable"
          detail="Pitch math, profiles, segmentation, analytics"
          body="The frontend controls assume the backend owns microphone persistence and note math, so the same core models can still move toward Swift cleanly."
          icon={SlidersHorizontal}
        />
      </SectionCard>
    </ScreenContainer>
  );
}
