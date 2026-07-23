import { demoProfileTransposition, midiToFrequency, midiToNote, noteLabelToMidi } from './music';

export const REFERENCE_TONE_DETUNE_CENTS = 0;

function noteWithDefaultOctave(note: string): string {
  const normalized = note.trim().replace(/♯/g, '#').replace(/♭/g, 'b');
  return /^([A-Ga-g])([#b]?)-?\d+$/.test(normalized) ? normalized : `${normalized}4`;
}

export function referenceToneVoice(frequency: number, index: number): { frequency: number; detuneCents: number; oscillatorType: OscillatorType } | null {
  if (!Number.isFinite(frequency) || frequency <= 0) return null;
  return {
    frequency,
    detuneCents: REFERENCE_TONE_DETUNE_CENTS,
    oscillatorType: index === 0 ? 'sine' : 'triangle',
  };
}

export const INTERVALS = [
  { id: 'unison', label: 'Unison', semitones: 0 },
  { id: 'third', label: 'Major 3rd', semitones: 4 },
  { id: 'fourth', label: 'Perfect 4th', semitones: 5 },
  { id: 'fifth', label: 'Perfect 5th', semitones: 7 },
  { id: 'octave', label: 'Octave', semitones: 12 },
] as const;

export function writtenNoteFrequency(note: string, instrumentId: string, referencePitch = 440, intervalSemitones = 0): number | null {
  const writtenMidi = noteLabelToMidi(noteWithDefaultOctave(note)) + intervalSemitones;
  const transposition = demoProfileTransposition[instrumentId];
  if (transposition == null || !Number.isFinite(writtenMidi) || !Number.isFinite(referencePitch) || referencePitch <= 0) return null;
  return midiToFrequency(writtenMidi - transposition, referencePitch);
}

export function intervalNoteLabel(note: string, intervalSemitones: number): string {
  return midiToNote(noteLabelToMidi(noteWithDefaultOctave(note)) + intervalSemitones).note;
}
