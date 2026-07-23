import { describe, expect, it } from 'vitest';
import { localeOptions, normalizeLocale } from './LocaleContext';
import { englishMessages, messagesForLocale, pseudoLocalizeMessage } from './messages';

describe('web localization', () => {
  it('ships twelve complete catalogs with an explicit pseudo-locale', () => {
    expect(localeOptions).toHaveLength(12);
    expect(localeOptions.map((option) => option.value)).toContain('en-XA');
    for (const { value } of localeOptions) {
      expect(Object.keys(messagesForLocale(value)).sort()).toEqual(Object.keys(englishMessages).sort());
    }
  });

  it('pseudo-localizes interface copy while preserving ICU placeholders and A–G notes', () => {
    const message = pseudoLocalizeMessage('Play A, Bb, and G for {count} seconds');
    expect(message).toMatch(/^［.*］$/);
    expect(message).toContain('{count}');
    expect(message).toContain('A');
    expect(message).toContain('Bb');
    expect(message).toContain('G');
    expect(message).not.toContain('Play');
  });

  it('normalizes browser language variants without selecting QA pseudo automatically', () => {
    expect(normalizeLocale('pt-PT')).toBe('pt-BR');
    expect(normalizeLocale('zh-Hant')).toBe('zh-CN');
    expect(normalizeLocale('ar-SA')).toBe('ar');
    expect(normalizeLocale('unknown')).toBeNull();
  });
});
