import { MIN_RECORDING_CONFIDENCE } from './music';
import type { InstrumentProfile, PitchFrame } from './types';

export type SaveEligibilityCode = 'valid' | 'silence' | 'low_confidence' | 'outside_range' | 'no_pitch_lock';

export interface SaveEligibility {
  code: SaveEligibilityCode;
  label: string;
  detail: string;
  canSave: boolean;
  tone: 'green' | 'gold' | 'amber' | 'red' | 'muted';
}

export function describeSaveEligibility(frame: PitchFrame | null, profile?: InstrumentProfile | null): SaveEligibility {
  if (!frame) {
    return {
      code: 'no_pitch_lock',
      label: 'No lock',
      detail: 'Waiting for a pitch frame.',
      canSave: false,
      tone: 'muted',
    };
  }
  if (frame.is_valid_for_recording && frame.confidence >= MIN_RECORDING_CONFIDENCE) {
    return {
      code: 'valid',
      label: 'Recording-quality lock',
      detail: 'This frame can be saved into session analytics.',
      canSave: true,
      tone: 'green',
    };
  }
  if (frame.save_eligibility_reason === 'outside instrument range') {
    return {
      code: 'outside_range',
      label: 'Outside range',
      detail: profile ? `Expected ${profile.typical_range_written} for ${profile.display_name}.` : 'Pitch is outside the selected instrument range.',
      canSave: false,
      tone: 'red',
    };
  }
  if (frame.tuning_status === 'silence' || frame.rms < 0.01 || frame.save_eligibility_reason === 'silence') {
    return {
      code: 'silence',
      label: 'Silence',
      detail: 'Signal is too quiet to analyze.',
      canSave: false,
      tone: 'muted',
    };
  }
  if (frame.confidence < MIN_RECORDING_CONFIDENCE || frame.save_eligibility_reason === 'confidence below 95%') {
    return {
      code: 'low_confidence',
      label: 'No lock',
      detail: `Detector confidence is below ${Math.round(MIN_RECORDING_CONFIDENCE * 100)}%.`,
      canSave: false,
      tone: 'amber',
    };
  }
  return {
    code: 'no_pitch_lock',
    label: 'Unstable/no pitch lock',
    detail: 'The detector has not found a stable pitch center for this frame.',
    canSave: false,
    tone: 'gold',
  };
}
