import { describe, expect, it } from 'vitest';
import { resolvePracticeShortcutLabel } from './PracticeShortcuts';
import type { MessageId } from '../../i18n/messages.base';
import type { PracticeTarget } from '../../domain/practiceLibrary';

const translations: Record<string, Partial<Record<MessageId, string>>> = {
  en: {
    'warmup.title': 'Guided 5-minute warm-up',
    'playAlong.majorLabel': '{note} major',
  },
  es: {
    'warmup.title': 'Calentamiento guiado de 5 minutos.',
    'playAlong.majorLabel': '{note} mayor',
  },
};

function translator(locale: keyof typeof translations) {
  return (id: MessageId, values?: Record<string, string | number>) => (
    (translations[locale][id] ?? id).replace('{note}', String(values?.note ?? ''))
  );
}

describe('practice shortcut labels', () => {
  it('re-resolves built-in semantic IDs when the locale changes', () => {
    const warmup: PracticeTarget = { kind: 'warmup', id: 'guided-5', label: 'stale persisted English', href: '/practice#warmup' };
    const scale: PracticeTarget = { kind: 'play-along', id: 'cmaj', label: 'stale persisted English', href: '/practice/play-along?exercise=cmaj' };

    expect(resolvePracticeShortcutLabel(warmup, translator('en'))).toBe('Guided 5-minute warm-up');
    expect(resolvePracticeShortcutLabel(warmup, translator('es'))).toBe('Calentamiento guiado de 5 minutos.');
    expect(resolvePracticeShortcutLabel(scale, translator('en'))).toBe('C major');
    expect(resolvePracticeShortcutLabel(scale, translator('es'))).toBe('C mayor');
  });

  it('preserves user-authored custom exercise titles verbatim', () => {
    const custom: PracticeTarget = { kind: 'play-along', id: 'custom-arya', label: 'A-G Warmup', href: '/practice/play-along?exercise=custom-arya' };
    expect(resolvePracticeShortcutLabel(custom, translator('en'))).toBe('A-G Warmup');
    expect(resolvePracticeShortcutLabel(custom, translator('es'))).toBe('A-G Warmup');
  });
});
