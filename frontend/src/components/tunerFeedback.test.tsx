import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { LocaleProvider } from '../i18n/LocaleContext';
import type { PitchFrame } from '../domain/types';
import { nextTunerHoldCount } from '../pages/PracticePage';
import { NoteDisplay } from './NoteDisplay';
import { TuningMeter } from './TuningMeter';

function centeredFrame(confidence: number, valid: boolean): PitchFrame {
  return {
    timestamp_ms: 1,
    frequency_hz: 440,
    confidence,
    rms: 0.1,
    midi_note_float: 69,
    nearest_midi: 69,
    concert_note_name: 'A',
    concert_octave: 4,
    written_note_name: 'B',
    written_octave: 4,
    cents_deviation: 0,
    tuning_status: confidence >= 0.95 ? 'in_tune' : 'unstable',
    instrument_id: 'trumpet',
    reference_pitch_hz: 440,
    is_valid_for_recording: valid,
    save_eligibility_reason: valid ? 'valid for recording' : 'confidence below 95%',
  };
}

function render(component: ReturnType<typeof createElement>): string {
  return renderToStaticMarkup(createElement(LocaleProvider, null, component));
}

describe('confidence-aware tuner feedback', () => {
  it('does not render or announce a centered low-confidence frame as in tune', () => {
    const frame = centeredFrame(0.94, false);
    const note = render(createElement(NoteDisplay, { frame }));
    const meter = render(createElement(TuningMeter, { frame, holdFraction: 1 }));

    expect(note).toContain('aria-label="Play a note"');
    expect(note).toContain('note-display-verdict tone-muted">Play a note');
    expect(note).not.toContain('tone-green');
    expect(meter).toContain('aria-valuetext="No note"');
    expect(meter).not.toContain('tuning-meter-reward');
    expect(nextTunerHoldCount(7, frame)).toBe(0);
  });

  it('keeps centered reward behavior for a recording-quality frame', () => {
    const frame = centeredFrame(0.97, true);
    const note = render(createElement(NoteDisplay, { frame }));
    const meter = render(createElement(TuningMeter, { frame, holdFraction: 0.5 }));

    expect(note).toContain('aria-label="B4, In tune"');
    expect(meter).toContain('tuning-meter-reward');
    expect(nextTunerHoldCount(7, frame)).toBe(8);
  });
});
