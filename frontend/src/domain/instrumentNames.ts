// Friendly display names for instrument ids, so the UI never renders a raw
// lowercase slug like "trumpet". Falls back to a title-cased version of the id
// for anything not in the known catalog.
const INSTRUMENT_DISPLAY_NAMES: Record<string, string> = {
  trumpet: 'Trumpet in B♭',
  cornet: 'Cornet in B♭',
  flugelhorn: 'Flugelhorn in B♭',
  horn: 'French Horn in F',
  'french-horn': 'French Horn in F',
  trombone: 'Trombone',
  'bass-trombone': 'Bass Trombone',
  euphonium: 'Euphonium',
  baritone: 'Baritone',
  tuba: 'Tuba',
};

function titleCase(value: string): string {
  return value
    .replace(/[-_]+/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

export function instrumentDisplayName(id: string | null | undefined): string {
  if (!id) return 'Instrument';
  const key = id.trim().toLowerCase();
  return INSTRUMENT_DISPLAY_NAMES[key] ?? titleCase(id.trim());
}
