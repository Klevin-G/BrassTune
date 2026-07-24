export interface WarmupStep {
  id: string;
  title: string;
  instruction: string;
  seconds: number;
}

export const GUIDED_WARMUP_STEPS: WarmupStep[] = [
  { id: 'breathe', title: 'Easy breaths', instruction: 'Breathe in quietly for 4 counts and release for 8. Keep shoulders loose.', seconds: 45 },
  { id: 'buzz', title: 'Gentle buzz', instruction: 'Buzz a comfortable pitch softly. Rest whenever the sound feels forced.', seconds: 45 },
  { id: 'long-tone', title: 'Centered long tones', instruction: 'Play an easy note with a smooth start and steady air.', seconds: 75 },
  { id: 'slur', title: 'Relaxed slurs', instruction: 'Move between two comfortable notes without pressing the mouthpiece.', seconds: 75 },
  { id: 'scale', title: 'Easy scale', instruction: 'Finish with one slow scale at an even volume.', seconds: 60 },
];

export const GUIDED_WARMUP_SECONDS = GUIDED_WARMUP_STEPS.reduce((total, step) => total + step.seconds, 0);

export function warmupStepAt(elapsedSeconds: number): { index: number; elapsedInStep: number } {
  let remaining = Math.max(0, Math.min(GUIDED_WARMUP_SECONDS, Math.floor(elapsedSeconds)));
  for (let index = 0; index < GUIDED_WARMUP_STEPS.length; index += 1) {
    if (remaining < GUIDED_WARMUP_STEPS[index].seconds) return { index, elapsedInStep: remaining };
    remaining -= GUIDED_WARMUP_STEPS[index].seconds;
  }
  const index = GUIDED_WARMUP_STEPS.length - 1;
  return { index, elapsedInStep: GUIDED_WARMUP_STEPS[index].seconds };
}
