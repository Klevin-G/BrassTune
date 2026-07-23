import { Minus, Play, Plus, Square, Timer, Volume2, VolumeX } from 'lucide-react';
import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { MetronomePresetPanel } from '../components/practice/MetronomePresetPanel';
import { PageHeader, ScreenContainer, SectionCard, SegmentedControl, StatusBadge } from '../components/ui/AppPrimitives';
import type { MetronomePreset } from '../domain/practiceLibrary';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { buildScheduledTicks, clampBpm, nextRampBpm, normalizeTimeSignature, secondsPerTick, subdivisionFactor, tapTempoBpm, type Subdivision } from '../domain/metronome';
import './MetronomePage.css';

type TimeSignaturePreset = '2/4' | '3/4' | '4/4' | '5/4' | '6/8' | '7/8' | 'custom';

const signaturePresets: Record<Exclude<TimeSignaturePreset, 'custom'>, { numerator: number; denominator: number }> = {
  '2/4': { numerator: 2, denominator: 4 },
  '3/4': { numerator: 3, denominator: 4 },
  '4/4': { numerator: 4, denominator: 4 },
  '5/4': { numerator: 5, denominator: 4 },
  '6/8': { numerator: 6, denominator: 8 },
  '7/8': { numerator: 7, denominator: 8 },
};

function audioContextFactory() {
  const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
  return AudioContextClass ? new AudioContextClass() as AudioContext : null;
}

// Plain-language tempo name shown under the big number for teaching value.
function tempoName(bpm: number): string {
  if (bpm < 40) return 'Grave';
  if (bpm < 60) return 'Largo';
  if (bpm < 66) return 'Larghetto';
  if (bpm < 76) return 'Adagio';
  if (bpm < 108) return 'Andante';
  if (bpm < 120) return 'Moderato';
  if (bpm < 156) return 'Allegro';
  if (bpm < 176) return 'Vivace';
  if (bpm < 200) return 'Presto';
  return 'Prestissimo';
}

export function MetronomePage() {
  const practiceLibrary = usePracticeLibrary();
  const [searchParams] = useSearchParams();
  const [bpm, setBpm] = useState(() => Number(localStorage.getItem('brasstune.metronome.bpm') ?? 96));
  const [running, setRunning] = useState(false);
  const [muted, setMuted] = useState(false);
  const [volume, setVolume] = useState(() => Number(localStorage.getItem('brasstune.metronome.volume') ?? 0.45));
  const [accentDownbeat, setAccentDownbeat] = useState(true);
  const [countIn, setCountIn] = useState(true);
  const [subdivision, setSubdivision] = useState<Subdivision>('quarter');
  const [signaturePreset, setSignaturePreset] = useState<TimeSignaturePreset>('4/4');
  const [customNumerator, setCustomNumerator] = useState(4);
  const [customDenominator, setCustomDenominator] = useState(4);
  const [beat, setBeat] = useState(0);
  const [beatOn, setBeatOn] = useState(false);
  const [tapTimes, setTapTimes] = useState<number[]>([]);
  const [rampEnabled, setRampEnabled] = useState(false);
  const [targetBpm, setTargetBpm] = useState(120);
  const [rampStep, setRampStep] = useState(4);
  const [barsPerStep, setBarsPerStep] = useState(4);
  const [status, setStatus] = useState('Press Start to begin.');
  const [editing, setEditing] = useState(false);
  const [draftBpm, setDraftBpm] = useState('');

  const audioRef = useRef<AudioContext | null>(null);
  const timerRef = useRef<number | null>(null);
  const nextTickTimeRef = useRef(0);
  const beatIndexRef = useRef(0);
  const subdivisionIndexRef = useRef(0);
  const barCountRef = useRef(0);
  const bpmRef = useRef(bpm);
  const volumeRef = useRef(volume);
  const mutedRef = useRef(muted);
  const accentDownbeatRef = useRef(accentDownbeat);
  const rampEnabledRef = useRef(rampEnabled);
  const targetBpmRef = useRef(targetBpm);
  const rampStepRef = useRef(rampStep);
  const barsPerStepRef = useRef(barsPerStep);
  const subdivisionRef = useRef(subdivision);
  const signatureRef = useRef(normalizeTimeSignature(4, 4));
  const holdRef = useRef<{ timeout?: number; interval?: number }>({});
  const scrubRef = useRef({ active: false, startX: 0, startBpm: 0, moved: false });
  const runningRef = useRef(false);
  const startInFlightRef = useRef(false);
  const mountedRef = useRef(true);
  const scheduledClicksRef = useRef(new Set<{ oscillator: OscillatorNode; gain: GainNode }>());
  const visualTimersRef = useRef(new Set<number>());
  const appliedPresetRef = useRef<string | null>(null);

  const signature = signaturePreset === 'custom' ? normalizeTimeSignature(customNumerator, customDenominator) : signaturePresets[signaturePreset];

  const applyPreset = (preset: MetronomePreset) => {
    stop();
    setBpm(preset.bpm);
    setSubdivision(preset.subdivision);
    setAccentDownbeat(preset.accentDownbeat);
    setCountIn(preset.countIn);
    const match = Object.entries(signaturePresets).find(([, value]) => value.numerator === preset.numerator && value.denominator === preset.denominator)?.[0] as Exclude<TimeSignaturePreset, 'custom'> | undefined;
    if (match) setSignaturePreset(match);
    else {
      setCustomNumerator(preset.numerator);
      setCustomDenominator(preset.denominator);
      setSignaturePreset('custom');
    }
    setStatus(`Loaded “${preset.name}”. Press Start when you are ready.`);
  };

  useEffect(() => {
    const presetId = searchParams.get('preset');
    if (presetId) {
      if (appliedPresetRef.current === `preset:${presetId}`) return;
      const preset = practiceLibrary.library.metronomePresets.find((item) => item.id === presetId);
      if (!preset) return;
      appliedPresetRef.current = `preset:${presetId}`;
      applyPreset(preset);
      return;
    }
    if (!searchParams.has('bpm')) return;
    const queryBpm = Number(searchParams.get('bpm'));
    if (!Number.isFinite(queryBpm) || appliedPresetRef.current === `bpm:${queryBpm}`) return;
    appliedPresetRef.current = `bpm:${queryBpm}`;
    setBpm(clampBpm(queryBpm));
  }, [practiceLibrary.library.metronomePresets, searchParams]);

  useEffect(() => {
    bpmRef.current = clampBpm(bpm);
    volumeRef.current = volume;
    mutedRef.current = muted;
    accentDownbeatRef.current = accentDownbeat;
    rampEnabledRef.current = rampEnabled;
    targetBpmRef.current = targetBpm;
    rampStepRef.current = rampStep;
    barsPerStepRef.current = barsPerStep;
    subdivisionRef.current = subdivision;
    signatureRef.current = signature;
    localStorage.setItem('brasstune.metronome.bpm', String(clampBpm(bpm)));
    localStorage.setItem('brasstune.metronome.volume', String(volume));
  }, [accentDownbeat, barsPerStep, bpm, muted, rampEnabled, rampStep, signature, subdivision, targetBpm, volume]);

  const scheduleClick = (context: AudioContext, time: number, accented: boolean, subdivisionHit: boolean) => {
    if (!runningRef.current) return;
    if (mutedRef.current) return;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(accented ? 1568 : subdivisionHit ? 1175 : 880, time);
    gain.gain.setValueAtTime(0.0001, time);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, volumeRef.current * (accented ? 0.9 : 0.55)), time + 0.004);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.055);
    oscillator.connect(gain).connect(context.destination);
    const scheduled = { oscillator, gain };
    scheduledClicksRef.current.add(scheduled);
    oscillator.onended = () => {
      scheduledClicksRef.current.delete(scheduled);
      oscillator.disconnect();
      gain.disconnect();
    };
    oscillator.start(time);
    oscillator.stop(time + 0.065);
  };

  const cancelScheduledOutput = () => {
    visualTimersRef.current.forEach((timer) => window.clearTimeout(timer));
    visualTimersRef.current.clear();
    const stopTime = audioRef.current?.currentTime ?? 0;
    scheduledClicksRef.current.forEach(({ oscillator, gain }) => {
      oscillator.onended = null;
      try {
        oscillator.stop(stopTime);
      } catch {
        // The click may already have ended between the set iteration and stop.
      }
      oscillator.disconnect();
      gain.disconnect();
    });
    scheduledClicksRef.current.clear();
  };

  const scheduleLoop = () => {
    const context = audioRef.current;
    if (!context) return;
    const factor = subdivisionFactor(subdivisionRef.current);
    while (nextTickTimeRef.current < context.currentTime + 0.12) {
      const beatIndex = beatIndexRef.current;
      const subdivisionIndex = subdivisionIndexRef.current;
      const accented = accentDownbeatRef.current && beatIndex === 0 && subdivisionIndex === 0;
      scheduleClick(context, nextTickTimeRef.current, accented, subdivisionIndex > 0);
      const visualDelayMs = Math.max(0, (nextTickTimeRef.current - context.currentTime) * 1000);
      if (subdivisionIndex === 0) {
        const timer = window.setTimeout(() => {
          visualTimersRef.current.delete(timer);
          if (!runningRef.current) return;
          setBeat(beatIndex);
          setBeatOn(true);
          setStatus('Playing');
        }, visualDelayMs);
        visualTimersRef.current.add(timer);
      }
      nextTickTimeRef.current += secondsPerTick(bpmRef.current, signatureRef.current, subdivisionRef.current);
      subdivisionIndexRef.current += 1;
      if (subdivisionIndexRef.current >= factor) {
        subdivisionIndexRef.current = 0;
        beatIndexRef.current += 1;
      }
      if (beatIndexRef.current >= signatureRef.current.numerator) {
        beatIndexRef.current = 0;
        barCountRef.current += 1;
        if (rampEnabledRef.current && barCountRef.current % Math.max(1, barsPerStepRef.current) === 0) {
          setBpm((current) => nextRampBpm(current, targetBpmRef.current, rampStepRef.current));
        }
      }
    }
  };

  const start = async () => {
    if (runningRef.current || startInFlightRef.current) return;
    startInFlightRef.current = true;
    try {
      const context = audioRef.current ?? audioContextFactory();
      if (!context) {
        setStatus("Sorry — the metronome isn't supported in this browser. Try Chrome or Safari.");
        return;
      }
      audioRef.current = context;
      if (context.state !== 'running') {
        await context.resume().catch(() => undefined);
      }
      if (!mountedRef.current || audioRef.current !== context) return;
      if (context.state !== 'running') {
        setStatus('Tap Start again to allow metronome audio in this browser.');
        return;
      }
      cancelScheduledOutput();
      const startTime = context.currentTime + 0.08;
      const countInTicks = countIn ? buildScheduledTicks({ startTime, bpm, signature, subdivision, bars: 1 }) : [];
      nextTickTimeRef.current = countInTicks.length ? countInTicks[countInTicks.length - 1].time + secondsPerTick(bpm, signature, subdivision) : startTime;
      beatIndexRef.current = 0;
      subdivisionIndexRef.current = 0;
      barCountRef.current = 0;
      setBeat(0);
      setBeatOn(false);
      runningRef.current = true;
      for (const tick of countInTicks) {
        scheduleClick(context, tick.time, tick.accented, tick.subdivisionIndex > 0);
      }
      setRunning(true);
      setStatus(countIn ? 'Counting you in…' : 'Playing');
      const preset = practiceLibrary.library.metronomePresets.find((item) => item.id === searchParams.get('preset'));
      practiceLibrary.recordRecent(preset
        ? { kind: 'metronome', id: preset.id, label: `${preset.name} · ${preset.bpm} BPM`, href: `/metronome?preset=${encodeURIComponent(preset.id)}` }
        : { kind: 'metronome', id: `${bpm}-${signature.numerator}-${signature.denominator}`, label: `${bpm} BPM · ${signature.numerator}/${signature.denominator}`, href: `/metronome?bpm=${bpm}` });
      timerRef.current = window.setInterval(scheduleLoop, 25);
    } finally {
      startInFlightRef.current = false;
    }
  };

  const stop = () => {
    runningRef.current = false;
    if (timerRef.current) window.clearInterval(timerRef.current);
    timerRef.current = null;
    cancelScheduledOutput();
    setRunning(false);
    setBeatOn(false);
    setStatus('Stopped');
  };

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      startInFlightRef.current = false;
      runningRef.current = false;
      if (timerRef.current) window.clearInterval(timerRef.current);
      if (holdRef.current.timeout) window.clearTimeout(holdRef.current.timeout);
      if (holdRef.current.interval) window.clearInterval(holdRef.current.interval);
      cancelScheduledOutput();
      const context = audioRef.current;
      audioRef.current = null;
      void context?.close().catch(() => undefined);
    };
  }, []);

  const tap = () => {
    const next = [...tapTimes, performance.now()].slice(-6);
    setTapTimes(next);
    const nextBpm = tapTempoBpm(next);
    if (nextBpm) setBpm(nextBpm);
  };

  // Press-and-hold ±5 nudge that repeats while held.
  const nudge = (delta: number) => setBpm((current) => clampBpm(current + delta));
  const startHold = (delta: number) => {
    nudge(delta);
    holdRef.current.timeout = window.setTimeout(() => {
      holdRef.current.interval = window.setInterval(() => nudge(delta), 90);
    }, 380);
  };
  const stopHold = () => {
    if (holdRef.current.timeout) window.clearTimeout(holdRef.current.timeout);
    if (holdRef.current.interval) window.clearInterval(holdRef.current.interval);
    holdRef.current = {};
  };

  const toggleMuted = () => {
    setMuted((value) => {
      const next = !value;
      mutedRef.current = next;
      if (next) cancelScheduledOutput();
      return next;
    });
  };

  // Tap-to-edit / drag-to-scrub on the big BPM number.
  const beginEdit = () => {
    setDraftBpm(String(clampBpm(bpm)));
    setEditing(true);
  };
  const commitEdit = () => {
    const value = Number(draftBpm);
    setBpm(draftBpm.trim() !== '' && Number.isFinite(value) ? clampBpm(value) : clampBpm(bpm));
    setEditing(false);
  };
  const onBpmPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    scrubRef.current = { active: true, startX: event.clientX, startBpm: clampBpm(bpm), moved: false };
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };
  const onBpmPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const scrub = scrubRef.current;
    if (!scrub.active) return;
    const dx = event.clientX - scrub.startX;
    if (Math.abs(dx) > 3) scrub.moved = true;
    if (scrub.moved) setBpm(clampBpm(scrub.startBpm + Math.round(dx / 3)));
  };
  const onBpmPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    const scrub = scrubRef.current;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    scrub.active = false;
    if (!scrub.moved) beginEdit();
  };
  const onBpmKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'ArrowUp' || event.key === 'ArrowRight') {
      event.preventDefault();
      nudge(1);
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowLeft') {
      event.preventDefault();
      nudge(-1);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      beginEdit();
    }
  };

  const badgeTone = running ? (beatOn ? 'green' : 'gold') : 'muted';
  const badgeLabel = running ? (beatOn ? 'Playing' : 'Counting in') : 'Stopped';

  return (
    <ScreenContainer className="mt-screen">
      <PageHeader
        title="Metronome"
        description="Set your tempo and press start. Tap the tempo to change it, or tap along to find it."
        action={<StatusBadge tone={badgeTone}>{badgeLabel}</StatusBadge>}
      />

      <SectionCard className="mt-stage">
        <div className="mt-beats" role="img" aria-label={`${signature.numerator} beats per bar`}>
          {Array.from({ length: signature.numerator }, (_, index) => (
            <span
              key={index}
              className={`mt-beat${index === 0 ? ' accent' : ''}${beatOn && index === beat ? ' active' : ''}`}
              aria-hidden="true"
            />
          ))}
        </div>

        <div className="mt-tempo">
          <div className="mt-bpm-row">
            <button
              type="button"
              className="ghost-button mt-nudge"
              aria-label="Slower by 5"
              onPointerDown={() => startHold(-5)}
              onPointerUp={stopHold}
              onPointerLeave={stopHold}
              onPointerCancel={stopHold}
            >
              <Minus size={20} />
            </button>

            {editing ? (
              <input
                className="mt-bpm-input"
                type="number"
                min={20}
                max={300}
                autoFocus
                value={draftBpm}
                onChange={(event) => setDraftBpm(event.target.value)}
                onFocus={(event) => event.target.select()}
                onBlur={commitEdit}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') commitEdit();
                  if (event.key === 'Escape') setEditing(false);
                }}
                aria-label="Beats per minute"
              />
            ) : (
              <div
                className="mt-bpm"
                role="button"
                tabIndex={0}
                aria-label={`Tempo ${clampBpm(bpm)} beats per minute. Tap to type, drag to change.`}
                onPointerDown={onBpmPointerDown}
                onPointerMove={onBpmPointerMove}
                onPointerUp={onBpmPointerUp}
                onKeyDown={onBpmKeyDown}
              >
                <span className="mt-bpm-num">{clampBpm(bpm)}</span>
                <span className="mt-bpm-unit">BPM</span>
              </div>
            )}

            <button
              type="button"
              className="ghost-button mt-nudge"
              aria-label="Faster by 5"
              onPointerDown={() => startHold(5)}
              onPointerUp={stopHold}
              onPointerLeave={stopHold}
              onPointerCancel={stopHold}
            >
              <Plus size={20} />
            </button>
          </div>

          <p className="mt-tempo-name">{tempoName(clampBpm(bpm))}</p>

          <input
            className="mt-slider"
            type="range"
            min={20}
            max={300}
            value={clampBpm(bpm)}
            onChange={(event) => setBpm(clampBpm(Number(event.target.value)))}
            aria-label="Tempo"
          />

          <button type="button" className="ghost-button mt-tap" onClick={tap}>
            <Timer size={18} />
            Tap tempo
          </button>
        </div>

        <div className="mt-transport-row">
          <button type="button" className={`mt-transport${running ? ' is-running' : ''}`} onClick={running ? stop : start}>
            {running ? <Square size={22} /> : <Play size={22} />}
            {running ? 'Stop' : 'Start'}
          </button>
          <button
            type="button"
            className="ghost-button mt-mute"
            onClick={toggleMuted}
          >
            {muted ? <VolumeX size={18} /> : <Volume2 size={18} />}
            {muted ? 'Unmute' : 'Mute'}
          </button>
        </div>

        <p className="mt-status" aria-live="polite">{status}</p>

        <div className="mt-quick">
          <div className="mt-quick-group">
            <span className="mt-quick-label">Beat</span>
            <SegmentedControl
              ariaLabel="Time signature"
              value={signaturePreset}
              options={[
                { value: '4/4', label: '4/4' },
                { value: '3/4', label: '3/4' },
              ]}
              onChange={setSignaturePreset}
            />
          </div>
          <div className="mt-quick-group">
            <span className="mt-quick-label">Notes per beat</span>
            <SegmentedControl
              ariaLabel="Subdivision"
              value={subdivision}
              options={[
                { value: 'quarter', label: '1' },
                { value: 'eighth', label: '2' },
                { value: 'triplet', label: '3' },
                { value: 'sixteenth', label: '4' },
              ]}
              onChange={setSubdivision}
            />
          </div>
        </div>
      </SectionCard>

      <MetronomePresetPanel
        current={{ bpm, numerator: signature.numerator, denominator: signature.denominator, subdivision, accentDownbeat, countIn }}
        onApply={applyPreset}
      />

      <details className="mt-advanced">
        <summary>Advanced</summary>
        <div className="mt-advanced-body">
          <div className="mt-adv-block">
            <span className="mt-quick-label">Time signature</span>
            <SegmentedControl
              ariaLabel="All time signatures"
              value={signaturePreset}
              options={[
                { value: '2/4', label: '2/4' },
                { value: '3/4', label: '3/4' },
                { value: '4/4', label: '4/4' },
                { value: '5/4', label: '5/4' },
                { value: '6/8', label: '6/8' },
                { value: '7/8', label: '7/8' },
                { value: 'custom', label: 'Custom' },
              ]}
              onChange={setSignaturePreset}
            />
            {signaturePreset === 'custom' && (
              <div className="two-field-row">
                <label className="field">
                  <span>Beats per bar</span>
                  <input type="number" min={1} max={16} value={customNumerator} onChange={(event) => setCustomNumerator(Number(event.target.value))} />
                </label>
                <label className="field">
                  <span>Note value</span>
                  <select value={customDenominator} onChange={(event) => setCustomDenominator(Number(event.target.value))}>
                    <option value={2}>2</option>
                    <option value={4}>4</option>
                    <option value={8}>8</option>
                    <option value={16}>16</option>
                  </select>
                </label>
              </div>
            )}
          </div>

          <label className="field">
            <span>Volume</span>
            <input type="range" min={0} max={1} step={0.05} value={volume} onChange={(event) => setVolume(Number(event.target.value))} />
          </label>

          <label className="switch-row">
            <span>Accent the first beat</span>
            <input type="checkbox" checked={accentDownbeat} onChange={(event) => setAccentDownbeat(event.target.checked)} />
          </label>
          <label className="switch-row">
            <span>Count me in one bar first</span>
            <input type="checkbox" checked={countIn} onChange={(event) => setCountIn(event.target.checked)} />
          </label>

          <div className="mt-adv-block">
            <label className="switch-row">
              <span>Speed up automatically</span>
              <input type="checkbox" checked={rampEnabled} onChange={(event) => setRampEnabled(event.target.checked)} />
            </label>
            <p className="mt-adv-hint">Start slow and let the tempo climb toward your goal while you play.</p>
            <div className="mt-field-row">
              <label className="field">
                <span>Goal tempo</span>
                <input type="number" min={20} max={300} value={targetBpm} onChange={(event) => setTargetBpm(clampBpm(Number(event.target.value)))} />
              </label>
              <label className="field">
                <span>Speed up by</span>
                <input type="number" min={1} max={30} value={rampStep} onChange={(event) => setRampStep(Number(event.target.value))} />
              </label>
              <label className="field">
                <span>Every N bars</span>
                <input type="number" min={1} max={32} value={barsPerStep} onChange={(event) => setBarsPerStep(Number(event.target.value))} />
              </label>
            </div>
          </div>
        </div>
      </details>
    </ScreenContainer>
  );
}
