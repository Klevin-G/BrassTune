import { Minus, Play, Plus, Square, Timer, Volume2, VolumeX } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { InsightCard, MetricTile, PageHeader, ScreenContainer, SectionCard, SegmentedControl, StatusBadge } from '../components/ui/AppPrimitives';
import { buildScheduledTicks, clampBpm, nextRampBpm, normalizeTimeSignature, secondsPerTick, subdivisionFactor, tapTempoBpm, timingStats, type Subdivision } from '../domain/metronome';

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

export function MetronomePage() {
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
  const [subBeat, setSubBeat] = useState(0);
  const [tapTimes, setTapTimes] = useState<number[]>([]);
  const [rampEnabled, setRampEnabled] = useState(false);
  const [targetBpm, setTargetBpm] = useState(120);
  const [rampStep, setRampStep] = useState(4);
  const [barsPerStep, setBarsPerStep] = useState(4);
  const [status, setStatus] = useState('Ready. Start from a button press so the browser allows audio.');
  const [scheduledTimes, setScheduledTimes] = useState<number[]>([]);

  const audioRef = useRef<AudioContext | null>(null);
  const timerRef = useRef<number | null>(null);
  const nextTickTimeRef = useRef(0);
  const beatIndexRef = useRef(0);
  const subdivisionIndexRef = useRef(0);
  const barCountRef = useRef(0);
  const bpmRef = useRef(bpm);
  const volumeRef = useRef(volume);
  const mutedRef = useRef(muted);
  const subdivisionRef = useRef(subdivision);
  const signatureRef = useRef(normalizeTimeSignature(4, 4));
  const scheduledTimesRef = useRef<number[]>([]);

  const signature = signaturePreset === 'custom' ? normalizeTimeSignature(customNumerator, customDenominator) : signaturePresets[signaturePreset];
  const stats = timingStats(scheduledTimes);

  useEffect(() => {
    bpmRef.current = clampBpm(bpm);
    volumeRef.current = volume;
    mutedRef.current = muted;
    subdivisionRef.current = subdivision;
    signatureRef.current = signature;
    localStorage.setItem('brasstune.metronome.bpm', String(clampBpm(bpm)));
    localStorage.setItem('brasstune.metronome.volume', String(volume));
  }, [bpm, volume, muted, subdivision, signature]);

  const scheduleClick = (context: AudioContext, time: number, accented: boolean, subdivisionHit: boolean) => {
    if (mutedRef.current) return;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(accented ? 1568 : subdivisionHit ? 1175 : 880, time);
    gain.gain.setValueAtTime(0.0001, time);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, volumeRef.current * (accented ? 0.9 : 0.55)), time + 0.004);
    gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.055);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(time);
    oscillator.stop(time + 0.065);
  };

  const scheduleLoop = () => {
    const context = audioRef.current;
    if (!context) return;
    const factor = subdivisionFactor(subdivisionRef.current);
    while (nextTickTimeRef.current < context.currentTime + 0.12) {
      const beatIndex = beatIndexRef.current;
      const subdivisionIndex = subdivisionIndexRef.current;
      const accented = accentDownbeat && beatIndex === 0 && subdivisionIndex === 0;
      scheduleClick(context, nextTickTimeRef.current, accented, subdivisionIndex > 0);
      const visualDelayMs = Math.max(0, (nextTickTimeRef.current - context.currentTime) * 1000);
      window.setTimeout(() => {
        setBeat(beatIndex);
        setSubBeat(subdivisionIndex);
      }, visualDelayMs);
      scheduledTimesRef.current = [...scheduledTimesRef.current, nextTickTimeRef.current].slice(-64);
      setScheduledTimes(scheduledTimesRef.current);
      nextTickTimeRef.current += secondsPerTick(bpmRef.current, signatureRef.current, subdivisionRef.current);
      subdivisionIndexRef.current += 1;
      if (subdivisionIndexRef.current >= factor) {
        subdivisionIndexRef.current = 0;
        beatIndexRef.current += 1;
      }
      if (beatIndexRef.current >= signatureRef.current.numerator) {
        beatIndexRef.current = 0;
        barCountRef.current += 1;
        if (rampEnabled && barCountRef.current % Math.max(1, barsPerStep) === 0) {
          setBpm((current) => nextRampBpm(current, targetBpm, rampStep));
        }
      }
    }
  };

  const start = async () => {
    const context = audioRef.current ?? audioContextFactory();
    if (!context) {
      setStatus('This browser does not support Web Audio metronome playback.');
      return;
    }
    audioRef.current = context;
    if (context.state === 'suspended') await context.resume();
    const startTime = context.currentTime + 0.08;
    const countInTicks = countIn ? buildScheduledTicks({ startTime, bpm, signature, subdivision, bars: 1 }) : [];
    nextTickTimeRef.current = countInTicks.length ? countInTicks[countInTicks.length - 1].time + secondsPerTick(bpm, signature, subdivision) : startTime;
    beatIndexRef.current = 0;
    subdivisionIndexRef.current = 0;
    barCountRef.current = 0;
    scheduledTimesRef.current = [];
    setScheduledTimes([]);
    for (const tick of countInTicks) {
      scheduleClick(context, tick.time, tick.accented, tick.subdivisionIndex > 0);
    }
    setRunning(true);
    setStatus(countIn ? 'Count-in scheduled. Main pulse follows on the next bar.' : 'Metronome running on the Web Audio clock.');
    timerRef.current = window.setInterval(scheduleLoop, 25);
  };

  const stop = () => {
    if (timerRef.current) window.clearInterval(timerRef.current);
    timerRef.current = null;
    setRunning(false);
    setStatus('Stopped. Timing stats remain from the latest scheduled run.');
  };

  useEffect(() => () => stop(), []);

  const tap = () => {
    const next = [...tapTimes, performance.now()].slice(-6);
    setTapTimes(next);
    const nextBpm = tapTempoBpm(next);
    if (nextBpm) {
      setBpm(nextBpm);
      setStatus(`Tap tempo set ${nextBpm} BPM.`);
    }
  };

  return (
    <ScreenContainer className="metronome-screen">
      <PageHeader
        eyebrow="Metronome"
        title={`${clampBpm(bpm)} BPM`}
        description="A foreground Web Audio scheduler for count-ins, subdivisions, time signatures, and practice tempo ramps."
        action={<StatusBadge tone={running ? 'green' : 'gold'}>{running ? 'Running' : 'Ready'}</StatusBadge>}
      />
      <div className="metronome-grid">
        <SectionCard className="metronome-stage" title="Pulse" eyebrow={`${signature.numerator}/${signature.denominator} ${subdivision}`}>
          <div className="beat-ring" role="group" aria-label={`Beat ${beat + 1} of ${signature.numerator}`}>
            {Array.from({ length: signature.numerator }, (_, index) => (
              <span key={index} className={index === beat ? 'active' : ''}>{index + 1}</span>
            ))}
          </div>
          <div className="subdivision-dots" role="group" aria-label={`Subdivision ${subBeat + 1}`}>
            {Array.from({ length: subdivisionFactor(subdivision) }, (_, index) => (
              <span key={index} className={index === subBeat ? 'active' : ''} />
            ))}
          </div>
          <div className="settings-actions">
            <button className="primary-button" type="button" onClick={running ? stop : start}>
              {running ? <Square size={18} /> : <Play size={18} />}
              {running ? 'Stop' : 'Start'}
            </button>
            <button className="ghost-button" type="button" onClick={() => setBpm((current) => clampBpm(current - 1))} aria-label="Decrease BPM">
              <Minus size={18} />
              1
            </button>
            <button className="ghost-button" type="button" onClick={() => setBpm((current) => clampBpm(current + 1))} aria-label="Increase BPM">
              <Plus size={18} />
              1
            </button>
            <button className="ghost-button" type="button" onClick={tap}>
              <Timer size={18} />
              Tap tempo
            </button>
            <button className="ghost-button" type="button" onClick={() => setMuted((value) => !value)} aria-label={muted ? 'Unmute metronome' : 'Mute metronome'}>
              {muted ? <VolumeX size={18} /> : <Volume2 size={18} />}
              {muted ? 'Muted' : 'Sound'}
            </button>
          </div>
          <p className="settings-status" aria-live="polite">{status}</p>
        </SectionCard>
        <SectionCard title="Controls" eyebrow="Tempo and meter">
          <div className="settings-grid">
            <label className="field">
              <span>BPM</span>
              <input type="number" min={20} max={300} value={bpm} onChange={(event) => setBpm(clampBpm(Number(event.target.value)))} />
            </label>
            <label className="field">
              <span>Volume</span>
              <input type="range" min={0} max={1} step={0.05} value={volume} onChange={(event) => setVolume(Number(event.target.value))} />
            </label>
            <SegmentedControl
              ariaLabel="Subdivision"
              value={subdivision}
              options={[
                { value: 'quarter', label: 'Quarter' },
                { value: 'eighth', label: 'Eighth' },
                { value: 'triplet', label: 'Triplet' },
                { value: 'sixteenth', label: '16th' },
              ]}
              onChange={setSubdivision}
            />
            <SegmentedControl
              ariaLabel="Time signature"
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
                  <span>Numerator</span>
                  <input type="number" min={1} max={16} value={customNumerator} onChange={(event) => setCustomNumerator(Number(event.target.value))} />
                </label>
                <label className="field">
                  <span>Denominator</span>
                  <select value={customDenominator} onChange={(event) => setCustomDenominator(Number(event.target.value))}>
                    <option value={2}>2</option>
                    <option value={4}>4</option>
                    <option value={8}>8</option>
                    <option value={16}>16</option>
                  </select>
                </label>
              </div>
            )}
            <label className="switch-row">
              <span>Accent downbeat</span>
              <input type="checkbox" checked={accentDownbeat} onChange={(event) => setAccentDownbeat(event.target.checked)} />
            </label>
            <label className="switch-row">
              <span>One-bar count-in</span>
              <input type="checkbox" checked={countIn} onChange={(event) => setCountIn(event.target.checked)} />
            </label>
          </div>
        </SectionCard>
      </div>
      <div className="stats-grid">
        <MetricTile label="Tick interval" value={`${(secondsPerTick(bpm, signature, subdivision) * 1000).toFixed(0)} ms`} detail="scheduled target" tone="gold" />
        <MetricTile label="Measured avg" value={`${stats.averageMs.toFixed(1)} ms`} detail={`${stats.intervals} intervals`} />
        <MetricTile label="Max jitter" value={`${stats.maxJitterMs.toFixed(1)} ms`} detail="scheduled-time spread" tone={stats.maxJitterMs < 2 ? 'green' : 'amber'} />
        <MetricTile label="Target BPM" value={`${targetBpm}`} detail={rampEnabled ? 'ramp enabled' : 'ramp off'} />
      </div>
      <SectionCard title="Practice tempo ramp" eyebrow="Optional">
        <div className="three-card-grid">
          <label className="switch-row">
            <span>Ramp active</span>
            <input type="checkbox" checked={rampEnabled} onChange={(event) => setRampEnabled(event.target.checked)} />
          </label>
          <label className="field">
            <span>Target BPM</span>
            <input type="number" min={20} max={300} value={targetBpm} onChange={(event) => setTargetBpm(clampBpm(Number(event.target.value)))} />
          </label>
          <label className="field">
            <span>Step size</span>
            <input type="number" min={1} max={30} value={rampStep} onChange={(event) => setRampStep(Number(event.target.value))} />
          </label>
          <label className="field">
            <span>Bars per step</span>
            <input type="number" min={1} max={32} value={barsPerStep} onChange={(event) => setBarsPerStep(Number(event.target.value))} />
          </label>
        </div>
      </SectionCard>
      <SectionCard title="Mic coexistence" eyebrow="Release caveat">
        <div className="insight-grid">
          <InsightCard title="Foreground scheduler" detail="Web Audio clock" body="Scheduling uses AudioContext.currentTime with a short lookahead queue. Background tabs can still throttle UI updates." icon={Timer} tone="gold" />
          <InsightCard title="Recording guidance" detail="Click timestamps known" body="Use headphones when recording with the metronome. Native and physical-device bleed rejection still require validation." icon={Volume2} />
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
