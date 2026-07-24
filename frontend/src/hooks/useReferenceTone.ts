import { useCallback, useEffect, useRef, useState } from 'react';
import { referenceToneVoice } from '../domain/referenceTone';

export function useReferenceTone() {
  const contextRef = useRef<AudioContext | null>(null);
  const oscillatorsRef = useRef<OscillatorNode[]>([]);
  const gainRef = useRef<GainNode | null>(null);
  const [playing, setPlaying] = useState(false);

  const stop = useCallback(() => {
    const context = contextRef.current;
    const now = context?.currentTime ?? 0;
    if (gainRef.current && context) {
      gainRef.current.gain.cancelScheduledValues(now);
      gainRef.current.gain.setTargetAtTime(0.0001, now, 0.025);
    }
    const oscillators = oscillatorsRef.current;
    oscillatorsRef.current = [];
    window.setTimeout(() => {
      oscillators.forEach((oscillator) => {
        try { oscillator.stop(); } catch { /* already stopped */ }
        oscillator.disconnect();
      });
    }, 120);
    setPlaying(false);
  }, []);

  const start = useCallback(async (frequencies: number[]) => {
    stop();
    const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass || frequencies.length === 0) return false;
    const context = contextRef.current ?? new AudioContextClass();
    contextRef.current = context;
    if (context.state !== 'running') await context.resume().catch(() => undefined);
    if (context.state !== 'running') return false;
    const gain = context.createGain();
    gain.gain.setValueAtTime(0.0001, context.currentTime);
    gain.gain.exponentialRampToValueAtTime(frequencies.length > 1 ? 0.035 : 0.055, context.currentTime + 0.08);
    gain.connect(context.destination);
    gainRef.current = gain;
    oscillatorsRef.current = frequencies.flatMap((frequency, index) => {
      const voice = referenceToneVoice(frequency, index);
      if (!voice) return [];
      const oscillator = context.createOscillator();
      oscillator.type = voice.oscillatorType;
      oscillator.frequency.value = voice.frequency;
      oscillator.detune.value = voice.detuneCents;
      oscillator.connect(gain);
      oscillator.start();
      return [oscillator];
    });
    setPlaying(true);
    return true;
  }, [stop]);

  useEffect(() => () => {
    oscillatorsRef.current.forEach((oscillator) => {
      try { oscillator.stop(); } catch { /* already stopped */ }
      oscillator.disconnect();
    });
    oscillatorsRef.current = [];
    const context = contextRef.current;
    contextRef.current = null;
    void context?.close().catch(() => undefined);
  }, []);

  return { playing, start, stop };
}
