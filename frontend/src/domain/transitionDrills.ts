export interface TransitionEvent {
  note_label: string;
  avg_signed_cents: number;
}

export type TransitionDrillResult =
  | { ready: true; from: string; to: string; notes: string[]; evidenceCount: number; averageError: number }
  | { ready: false; reason: string };

/** Convert analytics labels such as Bb3 or F♯5 into exercise pitch classes. */
export function normalizeWeakDrillNoteLabel(value: string | null | undefined): string | null {
  if (!value) return null;
  const normalized = value.trim().replace(/♯/g, '#').replace(/♭/g, 'b');
  const match = /^([A-Ga-g])([#b]?)(?:-?\d+)?$/.exec(normalized);
  if (!match) return null;
  return `${match[1].toUpperCase()}${match[2] ?? ''}`;
}

export function generateWeakTransitionDrill(events: TransitionEvent[]): TransitionDrillResult {
  const pairs = new Map<string, { from: string; to: string; count: number; totalError: number }>();
  for (let index = 1; index < events.length; index += 1) {
    const from = normalizeWeakDrillNoteLabel(events[index - 1]?.note_label);
    const to = normalizeWeakDrillNoteLabel(events[index]?.note_label);
    if (!from || !to || from === to) continue;
    const key = `${from}>${to}`;
    const entry = pairs.get(key) ?? { from, to, count: 0, totalError: 0 };
    entry.count += 1;
    entry.totalError += Math.abs(Number(events[index].avg_signed_cents) || 0);
    pairs.set(key, entry);
  }
  const supported = [...pairs.values()].filter((pair) => pair.count >= 3);
  if (supported.length === 0) {
    return { ready: false, reason: 'Play a few more repeated note changes first. BrassTune needs at least three examples of the same transition before suggesting a drill.' };
  }
  supported.sort((left, right) => {
    const errorDifference = right.totalError / right.count - left.totalError / left.count;
    return errorDifference || right.count - left.count || `${left.from}>${left.to}`.localeCompare(`${right.from}>${right.to}`);
  });
  const weakest = supported[0];
  return {
    ready: true,
    from: weakest.from,
    to: weakest.to,
    notes: [weakest.from, weakest.to, weakest.from, weakest.to],
    evidenceCount: weakest.count,
    averageError: Math.round((weakest.totalError / weakest.count) * 10) / 10,
  };
}
