import { describe, expect, it } from 'vitest';
import { createIntl, createIntlCache } from 'react-intl';
import {
  loadMessagesForLocale,
  localeOptions,
  normalizeLocale,
  productionLocales,
} from './LocaleContext';
import { englishMessages, pseudoLocalizeMessage } from './messages.base';

function messageArguments(message: string) {
  return [...message.matchAll(/\{\s*([A-Za-z][\w]*)\s*(?=[,}])/g)]
    .map((match) => match[1])
    .sort();
}

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

  it('contains no normal English fallback outside invariant names, tokens, and valid loanwords', async () => {
    const invariantKeys = new Set([
      'auth.emailPlaceholder', 'auth.usernamePlaceholder', 'auth.displayNamePlaceholder',
      'common.start', 'common.pause', 'instrument.label', 'instrument.trombone',
      'instrument.euphonium', 'instrument.tuba', 'tuning.noteVerdict',
      'tuning.concertNote', 'tuning.meterValue', 'practice.demo', 'practice.micDeniedAfter',
      'sessionReview.secondsShort', 'settings.actionProgress', 'settings.admin',
      'class.minutesShort', 'class.student', 'locale.pseudo', 'drone.interval.octave',
      'playAlong.title', 'exercise.noteCount', 'playAlong.noteCount', 'onboarding.cents',
    ]);
    for (const locale of productionLocales.filter((value) => value !== 'en')) {
      const messages = await loadMessagesForLocale(locale);
      const identical = Object.keys(englishMessages).filter((key) => messages[key as keyof typeof messages] === englishMessages[key as keyof typeof englishMessages]);
      expect(identical.filter((key) => !invariantKeys.has(key)), locale).toEqual([]);
    }
  });

  it('preserves every ICU argument exactly once per English occurrence', async () => {
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      for (const id of Object.keys(englishMessages) as Array<keyof typeof englishMessages>) {
        expect(messageArguments(messages[id]), `${locale}:${id}`).toEqual(messageArguments(englishMessages[id]));
      }
    }
  });

  it('keeps reviewed Arabic music terms distinct from literal non-music meanings', async () => {
    const messages = await loadMessagesForLocale('ar');
    expect(messages['progress.centsHelp']).toContain('السنتات الموسيقية');
    expect(messages['metronome.timeSignature']).toBe('الميزان الموسيقي');
    expect(messages['metronome.subdivision']).toBe('تقسيم الإيقاع');
    expect(messages['metronome.volume']).toBe('مستوى الصوت');
    expect(messages['noteStats.avgAbs']).toBe('متوسط الانحراف المطلق');
    expect(messages['signal.confidence']).toBe('نسبة الثقة في اكتشاف طبقة الصوت');
    expect(messages['score.captureFailed']).toBe('تعذّر التقاط الصفحة. حاول مرة أخرى.');
  });

  it('guards confirmed musical false friends across production catalogs', async () => {
    const reviewedLocales = ['es', 'zh-Hans', 'zh-Hant', 'ar', 'fr', 'de', 'ru', 'pt-BR', 'ja', 'ko', 'vi'] as const;
    const [es, zhHans, zhHant, ar, fr, de, ru, ptBr, ja, ko, vi] = await Promise.all(
      reviewedLocales.map((locale) => loadMessagesForLocale(locale)),
    );

    expect([
      es['tuning.meterValue'],
      es['sessionReview.centsHelp'],
      es['settings.inTuneHelp'],
      es['progress.centsHelp'],
    ].join(' ')).not.toMatch(/centav/i);

    expect([
      zhHans['practice.droneIntervals'],
      zhHans['packs.daily.drone.label'],
      zhHans['onboarding.tunerBody'],
    ].join(' ')).not.toMatch(/无人机/);
    expect([
      zhHant['practice.droneIntervals'],
      zhHant['packs.daily.drone.label'],
      zhHant['onboarding.tunerBody'],
    ].join(' ')).not.toMatch(/無人機/);
    expect(zhHans['tuning.concertNote']).toBe('音乐会音高 {note}');
    expect(zhHant['tuning.concertNote']).toBe('音樂會音高 {note}');
    expect(zhHant['progress.centsHelp']).toBe('音分表示音符偏高或偏低的程度。越接近零越好。');

    expect(ar['tuning.concertNote']).toBe('النغمة الكونشرتية {note}');
    expect(ar['practice.droneIntervals']).not.toMatch(/طائرة/);
    expect(ar['localMedia.noteEvents']).not.toMatch(/حدث/);

    expect(fr['sessionReview.driftSharp']).toContain('trop haut');
    expect(fr['sessionReview.driftFlat']).toContain('trop bas');
    expect(fr['progress.centsHelp']).not.toMatch(/forte|fort|faible/i);

    expect(de['score.captureFailed']).toBe('Die Seite konnte nicht aufgenommen werden. Versuchen Sie es erneut.');
    expect(ja['score.captureFailed']).toBe('ページを取り込めませんでした。もう一度お試しください。');
    expect(ja['drone.interval']).toBe('音程');
    expect(ko['score.captureFailed']).toBe('페이지를 촬영하지 못했습니다. 다시 시도하세요.');
    expect(ko['drone.interval']).toBe('음정 간격');

    expect(ru['sessionReview.driftSharp']).toBe('Вы имели тенденцию играть выше.');
    expect(ru['sessionReview.driftFlat']).toBe('Вы имели тенденцию играть ниже.');
    expect(ptBr['metronome.timeSignature']).toBe('Compasso');
    expect(vi['practice.droneIntervals']).toBe('Âm nền và quãng');
    expect(vi['drone.interval']).toBe('Quãng');
    expect(vi['score.captureFailed']).toBe('Không thể chụp trang. Hãy thử lại.');
  });

  it('uses musical rather than literal translations for slurs, pitch, drones, scores, and notes', async () => {
    const expected = {
      es: ['Ligaduras relajadas', 'Nota pedal e intervalos', 'Partituras'],
      'zh-Hans': ['放松的连音练习', '持续音与音程', '乐谱'],
      'zh-Hant': ['輕鬆的圓滑奏練習', '持續音與音程', '樂譜'],
      ar: ['تمرين وصلات بالشفاه', 'النغمة المستمرة والمسافات الموسيقية', 'صفحات النوتة الموسيقية'],
      fr: ['Liaisons détendues', 'Bourdon et intervalles', 'Partitions'],
      de: ['Lockere Lippenbindungen', 'Bordun und Intervalle', 'Noten'],
      ru: ['Расслабленное легато', 'Бурдон и интервалы', 'Партитуры'],
      'pt-BR': ['Ligaduras relaxadas', 'Som contínuo e intervalos', 'Partituras'],
      ja: ['やさしいバズィング', '持続音と音程', '音符'],
      ko: ['편안한 슬러 연습', '지속음과 음정 간격', '악보'],
      vi: ['Đúng cao độ', 'Âm nền và quãng', 'Bản nhạc'],
    } as const;
    for (const locale of productionLocales.filter((value) => value !== 'en')) {
      const messages = await loadMessagesForLocale(locale);
      const values = locale === 'ja'
        ? [messages['warmup.buzz.title'], messages['drone.title'], messages['exercise.notes']]
        : locale === 'vi'
          ? [messages['tuning.inTune'], messages['drone.title'], messages['practice.sheetMusic']]
          : [messages['warmup.slur.title'], messages['drone.title'], messages['practice.sheetMusic']];
      expect(values).toEqual(expected[locale]);
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
      email: 'player@example.test',
      error: 'Unavailable',
      action: 'Export',
      note: 'B-flat',
      intervalNote: 'D',
      verdict: 'In tune',
      seconds: 2,
      cents: 4,
      inTune: 6,
      gap: 5,
      when: 'July 22',
      from: 'C',
      to: 'G',
      notes: 'C · G',
      role: 'Student',
      sessions: 3,
      minutes: 45,
      exercise: 'C major',
      size: '2 MB',
      filename: 'take.webm',
      signed: '+2.1',
      absolute: '3.4',
      summary: 'steady',
      attempted: 5,
      saved: 4,
      rejected: 1,
      limit: 64,
      detail: 'A little sharp',
      cue: 'ease down',
    };
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      const formattingErrors: unknown[] = [];
      const intl = createIntl({
        locale,
        messages,
        onError: (error) => formattingErrors.push(error),
      }, createIntlCache());
      for (const id of Object.keys(messages)) {
        const formatted = intl.formatMessage({ id, defaultMessage: '__FORMAT_FALLBACK__' }, values);
        expect(formatted, `${locale}:${id}`).not.toBe('__FORMAT_FALLBACK__');
      }
      expect(formattingErrors, locale).toEqual([]);
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
