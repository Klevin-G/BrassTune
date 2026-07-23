import { demoProfileTransposition, midiToFrequency, midiToNote, noteLabelToMidi } from './music';

export const INTERVALS = [
  { id: 'unison', label: 'Unison', semitones: 0 },
  { id: 'third', label: 'Major 3rd', semitones: 4 },
  { id: 'fourth', label: 'Perfect 4th', semitones: 5 },
  { id: 'fifth', label: 'Perfect 5th', semitones: 7 },
  { id: 'octave', label: 'Octave', semitones: 12 },
] as const;

export function writtenNoteFrequency(note: string, instrumentId: string, referencePitch = 440, intervalSemitones = 0): number | null {
  const writtenMidi = noteLabelToMidi(`${note}4`) + intervalSemitones;
  const transposition = demoProfileTransposition[instrumentId];
  if (transposition == null || !Number.isFinite(writtenMidi)) return null;
  return midiToFrequency(writtenMidi - transposition, referencePitch);
}

export function intervalNoteLabel(note: string, intervalSemitones: number): string {
  return midiToNote(noteLabelToMidi(`${note}4`) + intervalSemitones).note;
}
