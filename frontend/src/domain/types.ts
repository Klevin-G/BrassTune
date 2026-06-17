export type TuningStatus = 'flat' | 'in_tune' | 'sharp' | 'unstable' | 'silence';

export interface InstrumentProfile {
  id: string;
  display_name: string;
  transposition_semitones: number;
  min_frequency_hz: number;
  max_frequency_hz: number;
  preferred_note_spellings: string[];
  typical_range_written: string;
  common_tuning_tendencies: string[];
  recommendation_templates: Record<string, string[]>;
  future_swift_notes: string;
}

export interface PitchFrame {
  timestamp_ms: number;
  frequency_hz: number | null;
  confidence: number;
  rms: number;
  midi_note_float: number | null;
  nearest_midi: number | null;
  concert_note_name: string | null;
  concert_octave: number | null;
  written_note_name: string | null;
  written_octave: number | null;
  cents_deviation: number | null;
  tuning_status: TuningStatus;
  instrument_id: string;
  reference_pitch_hz: number;
  is_valid_for_recording: boolean;
}

export interface PracticeSession {
  id: number;
  user_id: number;
  instrument_id: string;
  name: string;
  started_at: string;
  ended_at: string | null;
  duration_seconds: number;
  reference_pitch_hz: number;
  notes_count: number;
  average_signed_cents: number;
  average_abs_cents: number;
  in_tune_percentage: number;
  created_at: string;
}

export interface NoteEvent {
  id: number;
  session_id: number;
  instrument_id: string;
  written_note: string;
  written_octave: number;
  note_label: string;
  concert_note: string;
  concert_octave: number;
  started_at_ms: number;
  ended_at_ms: number;
  duration_ms: number;
  duration_seconds: number;
  sample_count: number;
  avg_signed_cents: number;
  avg_abs_cents: number;
  median_cents: number;
  stddev_cents: number;
  min_cents: number;
  max_cents: number;
  in_tune_percentage: number;
  stability_score: number;
  created_at: string;
}

export interface NoteStats {
  written_note: string;
  written_octave: number;
  note_label: string;
  avg_signed_cents: number;
  avg_abs_cents: number;
  median_cents: number;
  stddev_cents: number;
  in_tune_percentage: number;
  duration_ms: number;
  duration_seconds: number;
  sample_count: number;
  event_count: number;
  stability_score: number;
  trend: string;
  severity: string;
  problem_severity: number;
  severity_color?: 'insufficient' | 'green' | 'yellow' | 'orange' | 'red';
  recommendation_summary?: string;
}

export interface Recommendation {
  title: string;
  message: string;
  severity: string;
  category: string;
  related_note: string;
  suggested_exercises: string[];
  suggested_focus: string;
  explanation: string;
}

export interface ProgressPoint {
  period: string;
  sessions: number;
  practice_minutes: number;
  avg_abs_cents: number;
  in_tune_percentage: number;
}

export interface ProgressMetrics {
  user_id: number;
  total_practice_time_seconds: number;
  session_count: number;
  average_session_length_seconds: number;
  timeseries: ProgressPoint[];
  consistency: {
    current_week_practice_days: number;
    days_in_week: number;
    practice_days_label: string;
    practice_streak_days: number;
  };
  most_improved_notes: Array<NoteStats & { improvement: number; previous_avg_abs_cents: number }>;
  worst_notes: NoteStats[];
  most_consistently_sharp_notes: NoteStats[];
  most_consistently_flat_notes: NoteStats[];
}

export interface PracticePlan {
  title: string;
  focus_notes: string[];
  steps: Array<{ minutes: number; label: string; detail: string }>;
  coach_message: string;
}

