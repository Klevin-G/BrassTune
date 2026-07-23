import { describe, expect, it } from 'vitest';
import { createIntl, createIntlCache } from 'react-intl';
import {
  loadMessagesForLocale,
  localeOptions,
  normalizeLocale,
  productionLocales,
} from './LocaleContext';
import { englishMessages, pseudoLocalizeMessage } from './messages.base';

describe('web localization', () => {
  it('ships twelve complete production catalogs plus an explicit pseudo-locale', async () => {
    expect(productionLocales).toEqual([
      'en', 'es', 'zh-Hans', 'zh-Hant', 'ar', 'fr', 'de', 'ru', 'pt-BR', 'ja', 'ko', 'vi',
    ]);
    expect(localeOptions).toHaveLength(13);
    expect(localeOptions.map((option) => option.value)).toContain('en-XA');

    const englishKeys = Object.keys(englishMessages).sort();
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      expect(Object.keys(messages).sort()).toEqual(englishKeys);
      expect(Object.values(messages).every((message) => message.trim().length > 0)).toBe(true);
      if (locale !== 'en') {
        const localizedCount = englishKeys.filter((key) => messages[key as keyof typeof messages] !== englishMessages[key as keyof typeof englishMessages]).length;
        expect(localizedCount).toBeGreaterThan(englishKeys.length * 0.8);
      }
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

  it('uses reviewed music and classroom terminology in every production language', async () => {
    const terminology = {
      en: ['Tuner', 'Play-Along', 'Class'],
      es: ['Afinador', 'Tocar juntos', 'Clase'],
      'zh-Hans': ['调音器', '跟练', '课堂'],
      'zh-Hant': ['調音器', '跟練', '課堂'],
      ar: ['الموالف', 'العزف المصاحب', 'الصف'],
      fr: ['Accordeur', 'Accompagnement', 'Classe'],
      de: ['Stimmgerät', 'Mitspielen', 'Klasse'],
      ru: ['Тюнер', 'Игра под аккомпанемент', 'Класс'],
      'pt-BR': ['Afinador', 'Tocar junto', 'Turma'],
      ja: ['チューナー', 'プレイアロング', 'クラス'],
      ko: ['튜너', '함께 연주', '수업'],
      vi: ['Máy lên dây', 'Chơi cùng', 'Lớp học'],
    } as const;
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      expect([messages['nav.tuner'], messages['nav.playAlong'], messages['nav.class']]).toEqual(terminology[locale]);
      expect(messages['auth.lead']).toMatch(/\btuner\b|afinador|调音器|調音器|موالف|accordeur|Stimmgerät|тюнер|チューナー|튜너|lên dây/i);
    }
  });

  it('formats every production ICU message with the shared runtime values', async () => {
    const values = {
      elapsed: 30,
      total: 300,
      date: 'July 20',
      completedMinutes: 45,
      targetMinutes: 60,
      completedSessions: 2,
      targetSessions: 3,
      percent: 75,
      completed: 45,
      target: 60,
      count: 2,
      name: 'C major',
      current: 2,
      value: '+3',
      instrument: 'Trumpet',
    };
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      const intl = createIntl({ locale, messages }, createIntlCache());
      for (const id of Object.keys(messages)) {
        expect(() => intl.formatMessage({ id }, values)).not.toThrow();
      }
    }
  });

  it('normalizes Chinese scripts and regions without selecting QA pseudo automatically', () => {
    expect(normalizeLocale('pt-PT')).toBe('pt-BR');
    expect(normalizeLocale('zh-Hant')).toBe('zh-Hant');
    expect(normalizeLocale('zh_TW')).toBe('zh-Hant');
    expect(normalizeLocale('zh-HK')).toBe('zh-Hant');
    expect(normalizeLocale('zh-MO')).toBe('zh-Hant');
    expect(normalizeLocale('zh-Hans')).toBe('zh-Hans');
    expect(normalizeLocale('zh-CN')).toBe('zh-Hans');
    expect(normalizeLocale('zh-SG')).toBe('zh-Hans');
    expect(normalizeLocale('ar-SA')).toBe('ar');
    expect(normalizeLocale('unknown')).toBeNull();
  });
});
