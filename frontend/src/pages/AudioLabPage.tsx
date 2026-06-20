import { Activity, Bug, Clipboard, Gauge, Mic, Radio, Save, Settings2, Waves } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { getInstruments, pitchWebSocketUrl } from '../api/client';
import { apiBase as runtimeApiBase } from '../api/runtimeConfig';
import { SessionControls } from '../components/SessionControls';
import { SignalMeter } from '../components/SignalMeter';
import { MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { MIN_RECORDING_CONFIDENCE } from '../domain/music';
import { describeSaveEligibility } from '../domain/pitchFrameStatus';
import type { InstrumentProfile } from '../domain/types';
import { usePitchStream } from '../hooks/usePitchStream';
import { useSessionRecorder } from '../hooks/useSessionRecorder';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

function noteLabel(note?: string | null, octave?: number | null) {
  return note ? `${note}${octave}` : '--';
}

function centsLabel(value?: number | null) {
  if (value === null || value === undefined) return '--';
  return `${value > 0 ? '+' : ''}${value.toFixed(1)}c`;
}

export function AudioLabPage() {
  const { instrumentId, referencePitch, demoMode } = useAppSettings();
  const auth = useAuth();
  const [profiles, setProfiles] = useState<InstrumentProfile[]>([]);
  const [permissionState, setPermissionState] = useState('unknown');
  const [wsUrl, setWsUrl] = useState('');
  const apiBase = runtimeApiBase() || `${window.location.origin}`;
  const recorder = useSessionRecorder(instrumentId, referencePitch, { cloudEnabled: auth.isSignedIn });
  const stream = usePitchStream({
    enabled: true,
    demoMode,
    instrumentId,
    referencePitch,
    recording: recorder.recording,
    sessionId: recorder.activeSession?.id,
    persistDemoFramesToBackend: auth.isSignedIn,
    onFrame: recorder.captureFrame,
  });

  useEffect(() => {
    getInstruments().then(setProfiles).catch(() => undefined);
    pitchWebSocketUrl().then(setWsUrl).catch(() => setWsUrl('unavailable'));
    if (navigator.permissions?.query) {
      navigator.permissions.query({ name: 'microphone' as PermissionName }).then((result) => {
        setPermissionState(result.state);
        result.onchange = () => setPermissionState(result.state);
      }).catch(() => setPermissionState('unknown'));
    }
  }, []);

  const profile = useMemo(() => profiles.find((item) => item.id === instrumentId) ?? null, [profiles, instrumentId]);
  const frame = stream.currentFrame;
  const eligibility = describeSaveEligibility(frame, profile);

  const start = async () => {
    try {
      const inputStream = demoMode ? null : await stream.startMicrophone();
      if (!demoMode && !inputStream) {
        recorder.setError('Microphone access is needed for a calibration take. You can switch to guided mode or retry microphone access.');
        return;
      }
      await recorder.start(`Calibration lab ${new Date().toLocaleDateString()}`);
    } catch (error) {
      recorder.setError(String(error));
    }
  };
  const stop = () => recorder.stop().catch((error) => recorder.setError(String(error)));
  const copyDiagnostics = () => {
    const payload = {
      apiBase,
      wsUrl,
      permissionState,
      demoMode,
      micActive: stream.micActive,
      streamInfo: stream.streamInfo,
      frame,
      eligibility,
      instrumentId,
      referencePitch,
    };
    navigator.clipboard?.writeText(JSON.stringify(payload, null, 2)).catch(() => undefined);
  };

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Audio diagnostics"
        title="Audio Calibration Lab"
        description="Check microphone permission, detector confidence, save eligibility, and frame delivery before recording a take."
        meta={
          <>
            <StatusBadge tone="gold">Diagnostics</StatusBadge>
            <StatusBadge tone={eligibility.tone}>{eligibility.label}</StatusBadge>
          </>
        }
      />

      <div className="two-column-grid audio-lab-grid">
        <SectionCard title="Live frame" eyebrow="Detector readout">
          <div className="stats-grid">
            <MetricTile label="Frequency" value={frame?.frequency_hz ? `${frame.frequency_hz.toFixed(1)} Hz` : '--'} detail="current estimate" icon={Waves} tone="gold" />
            <MetricTile label="Written note" value={noteLabel(frame?.written_note_name, frame?.written_octave)} detail={instrumentId} icon={Gauge} tone="green" />
            <MetricTile label="Concert note" value={noteLabel(frame?.concert_note_name, frame?.concert_octave)} detail="pitch model" icon={Radio} />
            <MetricTile label="Cents" value={centsLabel(frame?.cents_deviation)} detail={frame?.tuning_status?.replace('_', ' ') ?? 'waiting'} icon={Activity} tone="amber" />
          </div>

          <div className="calibration-readout">
            <div>
              <span>Raw confidence</span>
              <strong>{frame ? frame.confidence.toFixed(3) : '--'}</strong>
            </div>
            <div>
              <span>Confidence floor</span>
              <strong>{Math.round(MIN_RECORDING_CONFIDENCE * 100)}%</strong>
            </div>
            <div>
              <span>RMS</span>
              <strong>{frame ? frame.rms.toFixed(4) : '--'}</strong>
            </div>
            <div>
              <span>Save eligibility</span>
              <strong>{eligibility.canSave ? 'Saved if recording' : 'Not saved'}</strong>
            </div>
          </div>

          <SignalMeter frame={frame} />
          <p className="calibration-reason">{eligibility.detail}</p>
        </SectionCard>

        <SectionCard title="Audio connection" eyebrow="Microphone readiness">
          <div className="insight-grid">
            <article className="insight-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Radio size={18} />
                </span>
                <div>
                  <h3>Cloud service</h3>
                  <span>{apiBase ? 'Configured' : 'Using app origin'}</span>
                </div>
              </div>
              <p>Practice still works in guest mode if cloud sync is unavailable.</p>
            </article>
            <article className="insight-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Waves size={18} />
                </span>
                <div>
                  <h3>Cloud sync stream</h3>
                  <span>{wsUrl ? 'Ready to check' : 'Checking'}</span>
                </div>
              </div>
              <p>Guest microphone detection runs in this browser; this backend stream is kept for signed sync and hosted smoke checks.</p>
            </article>
            <article className="insight-card tone-gold">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Settings2 size={18} />
                </span>
                <div>
                  <h3>Frame size</h3>
                  <span>{stream.streamInfo.frameSize} samples</span>
                </div>
              </div>
              <p>{stream.streamInfo.sampleRate ? `${stream.streamInfo.sampleRate} Hz input sample rate.` : 'Guest demo mode uses generated pitch frames without microphone input.'}</p>
            </article>
            <article className="insight-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Bug size={18} />
                </span>
                <div>
                  <h3>Pitch source</h3>
                  <span>{stream.streamInfo.detectorSource}</span>
                </div>
              </div>
              <p>{profile ? `${profile.display_name} written range ${profile.typical_range_written}.` : 'Instrument profile is loading.'}</p>
            </article>
            <article className="insight-card">
              <div className="insight-heading">
                <span className="insight-icon">
                  <Mic size={18} />
                </span>
                <div>
                  <h3>Mic permission</h3>
                  <span>{permissionState}</span>
                </div>
              </div>
              <p>{stream.streamInfo.sentFrames} PCM frames analyzed; {stream.streamInfo.droppedFrames} dropped.</p>
            </article>
          </div>

          {!demoMode && !stream.micActive && (
            <button className="primary-button" type="button" onClick={stream.startMicrophone}>
              <Mic size={18} />
              Start microphone monitor
            </button>
          )}
          <details className="developer-diagnostics">
            <summary>Connection diagnostics</summary>
            <dl>
              <dt>Cloud service URL</dt>
              <dd>{apiBase}</dd>
              <dt>Streaming URL</dt>
              <dd>{wsUrl || 'checking'}</dd>
            </dl>
          </details>

          <button className="ghost-button" type="button" onClick={copyDiagnostics}>
            <Clipboard size={18} />
            Copy frame diagnostics
          </button>

          <div className="inline-panel">
            <div className="section-card-heading">
              <div>
                <p className="eyebrow">Optional recording</p>
                <h2>Calibration take</h2>
              </div>
              <StatusBadge tone={recorder.recording ? 'red' : 'muted'}>{recorder.recording ? 'Saving' : 'Observe only'}</StatusBadge>
            </div>
            <p>Calibration frames are not saved unless this recording control is active.</p>
            <SessionControls
              recording={recorder.recording}
              elapsedSeconds={recorder.elapsedSeconds}
              demoMode={demoMode}
              micActive={stream.micActive}
              microphoneLabel={stream.micActive ? 'Listening' : 'Mic'}
              busy={recorder.busy}
              onStart={start}
              onStop={stop}
              onMicStart={stream.startMicrophone}
            />
            {recorder.lastSummary && (
              <div className="saved-session-card">
                <h3>Calibration take saved</h3>
                <p>{recorder.lastSummary.notes_count} note events, {recorder.lastSummary.average_abs_cents.toFixed(1)} cents average absolute error.</p>
              </div>
            )}
            {recorder.error && <div className="alert">{recorder.error}</div>}
          </div>
        </SectionCard>
      </div>

      <SectionCard title="Recent frame trail" eyebrow="Why frames save or drop">
        <div className="table-wrap compact-table-wrap">
          <table>
            <thead>
              <tr>
                <th>Note</th>
                <th>Freq</th>
                <th>Cents</th>
                <th>Confidence</th>
                <th>RMS</th>
                <th>Status</th>
                <th>Save reason</th>
              </tr>
            </thead>
            <tbody>
              {[frame, ...stream.history].filter(Boolean).slice(0, 10).map((item, index) => {
                const row = item!;
                const rowEligibility = describeSaveEligibility(row, profile);
                return (
                  <tr key={`${row.timestamp_ms}-${index}`}>
                    <td>{noteLabel(row.written_note_name, row.written_octave)}</td>
                    <td>{row.frequency_hz ? row.frequency_hz.toFixed(1) : '--'}</td>
                    <td>{centsLabel(row.cents_deviation)}</td>
                    <td>{row.confidence.toFixed(3)}</td>
                    <td>{row.rms.toFixed(4)}</td>
                    <td><span className="trend-pill">{row.tuning_status.replace('_', ' ')}</span></td>
                    <td>{rowEligibility.label}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="calibration-frame-list">
          {[frame, ...stream.history].filter(Boolean).slice(0, 8).map((item, index) => {
            const row = item!;
            const rowEligibility = describeSaveEligibility(row, profile);
            return (
              <article className="note-stat-card" key={`${row.timestamp_ms}-mobile-${index}`}>
                <div className="note-stat-heading">
                  <strong>{noteLabel(row.written_note_name, row.written_octave)}</strong>
                  <span className={`severity-chip ${rowEligibility.canSave ? 'green' : 'yellow'}`}>{rowEligibility.label}</span>
                </div>
                <div className="note-stat-grid">
                  <div><span>Freq</span><b>{row.frequency_hz ? row.frequency_hz.toFixed(1) : '--'}</b></div>
                  <div><span>Cents</span><b>{centsLabel(row.cents_deviation)}</b></div>
                  <div><span>Conf</span><b>{row.confidence.toFixed(3)}</b></div>
                  <div><span>RMS</span><b>{row.rms.toFixed(4)}</b></div>
                </div>
              </article>
            );
          })}
        </div>
      </SectionCard>

      <SectionCard title="Real-device checklist" eyebrow="QA prompts">
        <div className="mini-stat-list">
          {['Lock speed', 'False no-locks', 'Octave jumps', 'Low brass detection', '4096-frame latency', '30-second take density'].map((item) => (
            <div className="mini-stat-row" key={item}>
              <span>{item}</span>
              <strong>Observe</strong>
              <em><Save size={14} /> log during tests</em>
            </div>
          ))}
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
