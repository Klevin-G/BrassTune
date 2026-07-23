export interface TransitionEvent {
  note_label: string;
  avg_signed_cents: number;
}

export type TransitionDrillResult =
  | { ready: true; from: string; to: string; notes: string[]; evidenceCount: number; averageError: number }
  | { ready: false; reason: string };

export function generateWeakTransitionDrill(events: TransitionEvent[]): TransitionDrillResult {
  const pairs = new Map<string, { from: string; to: string; count: number; totalError: number }>();
  for (let index = 1; index < events.length; index += 1) {
    const from = events[index - 1]?.note_label?.trim();
    const to = events[index]?.note_label?.trim();
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
