import { demoProfileTransposition, midiToFrequency, midiToNote, noteLabelToMidi } from './music';

export const REFERENCE_TONE_DETUNE_CENTS = 0;
export const WRITTEN_MIDI_MIN = 36;
export const WRITTEN_MIDI_MAX = 84;

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
  { id: 'second', label: 'Major 2nd', semitones: 2 },
  { id: 'third', label: 'Major 3rd', semitones: 4 },
  { id: 'fourth', label: 'Perfect 4th', semitones: 5 },
  { id: 'fifth', label: 'Perfect 5th', semitones: 7 },
  { id: 'octave', label: 'Octave', semitones: 12 },
] as const;

export function isWrittenMidi(value: unknown): value is number {
  return typeof value === 'number'
    && Number.isInteger(value)
    && value >= WRITTEN_MIDI_MIN
    && value <= WRITTEN_MIDI_MAX;
}

export function writtenMidiLabel(writtenMidi: number): string | null {
  if (!isWrittenMidi(writtenMidi)) return null;
  const note = midiToNote(writtenMidi);
  return `${note.note}${note.octave}`;
}

export function writtenMidiFrequency(
  writtenMidi: number,
  instrumentId: string,
  referencePitch = 440,
  intervalSemitones = 0,
): number | null {
  const transposition = demoProfileTransposition[instrumentId];
  if (
    !isWrittenMidi(writtenMidi)
    || transposition == null
    || !Number.isFinite(referencePitch)
    || referencePitch <= 0
    || !Number.isInteger(intervalSemitones)
    || intervalSemitones < 0
    || intervalSemitones > 12
  ) {
    return null;
  }
  return midiToFrequency(writtenMidi + intervalSemitones - transposition, referencePitch);
}

export function writtenNoteFrequency(note: string, instrumentId: string, referencePitch = 440, intervalSemitones = 0): number | null {
  const writtenMidi = noteLabelToMidi(noteWithDefaultOctave(note)) + intervalSemitones;
  return writtenMidiFrequency(writtenMidi - intervalSemitones, instrumentId, referencePitch, intervalSemitones);
}

export function intervalNoteLabel(note: string, intervalSemitones: number): string {
  return midiToNote(noteLabelToMidi(noteWithDefaultOctave(note)) + intervalSemitones).note;
}

export function intervalWrittenMidiLabel(writtenMidi: number, intervalSemitones: number): string | null {
  if (!isWrittenMidi(writtenMidi) || !Number.isInteger(intervalSemitones) || intervalSemitones < 0 || intervalSemitones > 12) return null;
  const note = midiToNote(writtenMidi + intervalSemitones);
  return `${note.note}${note.octave}`;
}
