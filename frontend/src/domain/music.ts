import type { PitchFrame } from './types';

const NOTE_NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const NOTE_INDEX: Record<string, number> = {
  C: 0,
  'C#': 1,
  Db: 1,
  D: 2,
  Eb: 3,
  'D#': 3,
  E: 4,
  Fb: 4,
  'E#': 5,
  F: 5,
  'F#': 6,
  Gb: 6,
  G: 7,
  Ab: 8,
  'G#': 8,
  A: 9,
  Bb: 10,
  'A#': 10,
  B: 11,
  Cb: -1,
  'B#': 12,
};

export const demoProfileTransposition: Record<string, number> = {
  trumpet: 2,
  horn: 7,
  trombone: 0,
  euphonium: 0,
  tuba: 0,
};

export const demoProfileFrequencyRanges: Record<string, { minFrequencyHz: number; maxFrequencyHz: number }> = {
  trumpet: { minFrequencyHz: 130, maxFrequencyHz: 1500 },
  horn: { minFrequencyHz: 80, maxFrequencyHz: 1200 },
  trombone: { minFrequencyHz: 50, maxFrequencyHz: 700 },
  euphonium: { minFrequencyHz: 55, maxFrequencyHz: 800 },
  tuba: { minFrequencyHz: 30, maxFrequencyHz: 500 },
};

export const MIN_RECORDING_CONFIDENCE = 0.95;

export function midiToFrequency(midi: number, referencePitch = 440): number {
  return referencePitch * 2 ** ((midi - 69) / 12);
}

export function frequencyToMidi(frequency: number, referencePitch = 440): number {
  return 69 + 12 * Math.log2(frequency / referencePitch);
}

export function midiToNote(midi: number) {
  const pitchClass = ((midi % 12) + 12) % 12;
  return { note: NOTE_NAMES[pitchClass], octave: Math.floor(midi / 12) - 1 };
}

export function noteLabelToMidi(label: string): number {
  const normalized = label.trim().replace(/♯/g, '#').replace(/♭/g, 'b');
  const accidental = normalized[1] === '#' || normalized[1] === 'b';
  const note = accidental ? normalized.slice(0, 2) : normalized.slice(0, 1);
  const octave = Number(normalized.slice(accidental ? 2 : 1));
  return (octave + 1) * 12 + NOTE_INDEX[note];
}

export function pitchFrameFromFrequency(
  frequency: number | null,
  centsHint: number,
  instrumentId: string,
  referencePitch: number,
  timestampMs: number,
  confidence = 0.97,
  rms = 0.08,
  detectorSource = 'browser_demo',
): PitchFrame {
  if (!frequency || frequency <= 0 || rms < 0.01) {
    return {
      timestamp_ms: timestampMs,
      frequency_hz: frequency,
      confidence,
      rms,
      midi_note_float: null,
      nearest_midi: null,
      concert_note_name: null,
      concert_octave: null,
      written_note_name: null,
      written_octave: null,
      cents_deviation: null,
      tuning_status: rms < 0.01 ? 'silence' : 'unstable',
      instrument_id: instrumentId,
      reference_pitch_hz: referencePitch,
      is_valid_for_recording: false,
      save_eligibility_reason: rms < 0.01 ? 'silence' : 'unstable/no pitch lock',
      detector_source: detectorSource,
    };
  }
  const range = demoProfileFrequencyRanges[instrumentId];
  if (range && (frequency < range.minFrequencyHz || frequency > range.maxFrequencyHz)) {
    return {
      timestamp_ms: timestampMs,
      frequency_hz: frequency,
      confidence,
      rms,
      midi_note_float: null,
      nearest_midi: null,
      concert_note_name: null,
      concert_octave: null,
      written_note_name: null,
      written_octave: null,
      cents_deviation: null,
      tuning_status: 'unstable',
      instrument_id: instrumentId,
      reference_pitch_hz: referencePitch,
      is_valid_for_recording: false,
      save_eligibility_reason: 'outside instrument range',
      detector_source: detectorSource,
    };
  }
  const midi = frequencyToMidi(frequency, referencePitch);
  const nearest = Math.round(midi);
  const concert = midiToNote(nearest);
  const written = midiToNote(nearest + (demoProfileTransposition[instrumentId] ?? 0));
  const status =
    confidence < MIN_RECORDING_CONFIDENCE ? 'unstable' : Math.abs(centsHint) <= 5 ? 'in_tune' : centsHint < -5 ? 'flat' : 'sharp';
  return {
    timestamp_ms: timestampMs,
    frequency_hz: frequency,
    confidence,
    rms,
    midi_note_float: midi,
    nearest_midi: nearest,
    concert_note_name: concert.note,
    concert_octave: concert.octave,
    written_note_name: written.note,
    written_octave: written.octave,
    cents_deviation: centsHint,
    tuning_status: status,
    instrument_id: instrumentId,
    reference_pitch_hz: referencePitch,
    is_valid_for_recording: status === 'flat' || status === 'in_tune' || status === 'sharp',
    save_eligibility_reason: status === 'flat' || status === 'in_tune' || status === 'sharp' ? 'valid for recording' : 'confidence below 95%',
    detector_source: detectorSource,
  };
}
