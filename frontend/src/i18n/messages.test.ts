import { describe, expect, it } from 'vitest';
import { createIntl, createIntlCache } from 'react-intl';
import {
  loadMessagesForLocale,
  localeOptions,
  normalizeLocale,
  productionLocaleOptions,
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
      en: ['Tuner', 'Practice Scorer', 'Class'],
      es: ['Afinador', 'Evaluador de práctica', 'Clase'],
      'zh-Hans': ['调音器', '练习评分', '课堂'],
      'zh-Hant': ['調音器', '練習評分', '課堂'],
      ar: ['الموالف', 'مقيّم التدريب', 'الصف'],
      fr: ['Accordeur', 'Évaluation de pratique', 'Classe'],
      de: ['Stimmgerät', 'Übungsbewertung', 'Klasse'],
      ru: ['Тюнер', 'Оценка практики', 'Класс'],
      'pt-BR': ['Afinador', 'Avaliador de prática', 'Turma'],
      ja: ['チューナー', '練習スコア', 'クラス'],
      ko: ['튜너', '연습 평가', '수업'],
      vi: ['Máy lên dây', 'Chấm điểm luyện tập', 'Lớp học'],
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
    expect(zhHans['tuning.concertNote']).toBe('实际音高 {note}');
    expect(zhHant['tuning.concertNote']).toBe('實際音高 {note}');
    expect([
      zhHans['playAlong.majorLabel'],
      zhHans['playAlong.minorLabel'],
      zhHans['drone.interval'],
      zhHans['drone.interval.unison'],
      zhHans['drone.interval.fourth'],
      zhHans['drone.interval.fifth'],
    ]).toEqual(['{note}大调', '{note}小调', '音程', '同度', '纯四度', '纯五度']);
    expect([
      zhHant['playAlong.majorLabel'],
      zhHant['playAlong.minorLabel'],
      zhHant['drone.interval'],
      zhHant['drone.interval.unison'],
      zhHant['drone.interval.fourth'],
      zhHant['drone.interval.fifth'],
    ]).toEqual(['{note}大調', '{note}小調', '音程', '同度', '完全四度', '完全五度']);
    expect([
      zhHans['sessionReview.driftSharp'],
      zhHans['sessionReview.driftFlat'],
      zhHans['sessionReview.sharpFlat'],
      zhHans['sessionReview.centsHelp'],
      zhHans['progress.howSharpFlat'],
    ].join(' ')).not.toMatch(/犀利|平平|尖锐|扁平|锋利/);
    expect([
      zhHant['sessionReview.driftSharp'],
      zhHant['sessionReview.driftFlat'],
      zhHant['sessionReview.sharpFlat'],
      zhHant['sessionReview.centsHelp'],
      zhHant['progress.howSharpFlat'],
    ].join(' ')).not.toMatch(/犀利|平平|尖銳|扁平|鋒利/);
    expect(zhHant['progress.centsHelp']).toBe('音分表示音符偏高或偏低的程度。越接近零越好。');

    expect(ar['tuning.concertNote']).toBe('النغمة الكونشرتية {note}');
    expect(ar['practice.droneIntervals']).not.toMatch(/طائرة/);
    expect(ar['localMedia.noteEvents']).not.toMatch(/حدث/);
    expect([ar['instrument.trumpet'], ar['instrument.cornet']]).toEqual(['ترومبيت في سي بيمول', 'كورنيت في سي بيمول']);
    expect([ar['tuning.sharp'], ar['tuning.flat']]).toEqual(['أعلى من الطبقة المطلوبة', 'أخفض من الطبقة المطلوبة']);
    expect(ar['practice.percentInTune']).toBe('{percent}% في الضبط');

    expect(fr['sessionReview.driftSharp']).toContain('trop haut');
    expect(fr['sessionReview.driftFlat']).toContain('trop bas');
    expect(fr['progress.centsHelp']).not.toMatch(/forte|fort|faible/i);

    expect(de['score.captureFailed']).toBe('Die Seite konnte nicht aufgenommen werden. Versuchen Sie es erneut.');
    expect(ja['score.captureFailed']).toBe('ページを取り込めませんでした。もう一度お試しください。');
    expect(ja['practice.droneIntervals']).toBe('持続音と音程');
    expect(ja['drone.interval']).toBe('音程');
    expect(ja['reflection.title']).toBe('短い練習の振り返り');
    expect([ja['practice.droneIntervals'], ja['reflection.title']].join(' ')).not.toMatch(/インターバル|簡単な/);
    expect(ko['score.captureFailed']).toBe('페이지를 촬영하지 못했습니다. 다시 시도하세요.');
    expect([
      ko['practice.droneIntervals'],
      ko['drone.interval'],
      ko['drone.interval.unison'],
      ko['drone.interval.third'],
      ko['drone.interval.fourth'],
      ko['drone.interval.fifth'],
      ko['reflection.title'],
    ]).toEqual(['지속음과 음정', '음정', '완전1도', '장3도', '완전4도', '완전5도', '짧은 연습 돌아보기']);
    expect([
      ko['sessionReview.driftSharp'],
      ko['sessionReview.driftFlat'],
      ko['sessionReview.centsHelp'],
      ko['progress.howSharpFlat'],
    ].join(' ')).not.toMatch(/날카로운|평평한|플랫하게|샤프 또는 플랫/);

    expect(ru['sessionReview.driftSharp']).toBe('Вы имели тенденцию играть выше.');
    expect(ru['sessionReview.driftFlat']).toBe('Вы имели тенденцию играть ниже.');
    expect(ptBr['metronome.timeSignature']).toBe('Compasso');
    expect(vi['practice.droneIntervals']).toBe('Âm nền và quãng');
    expect(vi['drone.interval']).toBe('Quãng');
    expect(vi['tuning.concertNote']).toBe('Cao độ thực {note}');
    expect([
      vi['playAlong.majorLabel'],
      vi['playAlong.minorLabel'],
      vi['warmup.buzz.title'],
      vi['warmup.slur.title'],
      vi['drone.interval.unison'],
      vi['drone.interval.third'],
      vi['drone.interval.fourth'],
      vi['drone.interval.fifth'],
    ]).toEqual([
      '{note} trưởng',
      '{note} thứ',
      'Rung môi nhẹ nhàng',
      'Luyến môi thư giãn',
      'Đồng âm',
      'Quãng ba trưởng',
      'Quãng bốn đúng',
      'Quãng năm đúng',
    ]);
    expect([
      vi['tuning.concertNote'],
      vi['playAlong.majorLabel'],
      vi['playAlong.minorLabel'],
      vi['warmup.buzz.title'],
      vi['warmup.slur.title'],
    ].join(' ')).not.toMatch(/Buổi hòa nhạc|chính|thứ yếu|Tiếng vang|^Thư giãn$/);
    expect(vi['score.captureFailed']).toBe('Không thể chụp trang. Hãy thử lại.');
  });

  it('uses practice-reflection language instead of physical reflection or reflex terms', async () => {
    const [zhHans, zhHant, vi, ko, ja] = await Promise.all(
      (['zh-Hans', 'zh-Hant', 'vi', 'ko', 'ja'] as const)
        .map((locale) => loadMessagesForLocale(locale)),
    );
    const reflectionKeys = [
      'reflection.title',
      'reflection.eyebrow',
      'reflection.prompt',
      'reflection.save',
      'reflection.saved',
      'reflection.list',
      'reflection.edit',
      'reflection.saveChanges',
      'reflection.cancel',
      'reflection.delete',
      'settings.setupDownloaded',
    ] as const;
    const reflectionCopy = (messages: Awaited<ReturnType<typeof loadMessagesForLocale>>) => (
      reflectionKeys.map((key) => messages[key]).join(' ')
    );

    expect([
      zhHans['reflection.save'],
      zhHans['reflection.list'],
      zhHans['reflection.edit'],
      zhHans['reflection.delete'],
    ]).toEqual(['保存练习心得', '已保存的练习心得', '编辑练习心得', '删除练习心得']);
    expect([
      zhHant['reflection.save'],
      zhHant['reflection.list'],
      zhHant['reflection.edit'],
      zhHant['reflection.delete'],
    ]).toEqual(['儲存練習心得', '已儲存的練習心得', '編輯練習心得', '刪除練習心得']);
    expect([
      vi['reflection.save'],
      vi['reflection.list'],
      vi['reflection.edit'],
      vi['reflection.delete'],
    ]).toEqual([
      'Lưu ghi chú luyện tập',
      'Ghi chú luyện tập đã lưu',
      'Chỉnh sửa ghi chú luyện tập',
      'Xóa ghi chú luyện tập',
    ]);
    expect([
      ko['reflection.save'],
      ko['reflection.list'],
      ko['reflection.edit'],
      ko['reflection.delete'],
    ]).toEqual(['연습 소감 저장', '저장한 연습 소감', '연습 소감 편집', '연습 소감 삭제']);
    expect([
      ja['reflection.save'],
      ja['reflection.list'],
      ja['reflection.edit'],
      ja['reflection.delete'],
    ]).toEqual(['練習メモを保存', '保存した練習メモ', '練習メモを編集', '練習メモを削除']);

    expect(reflectionCopy(zhHans)).not.toMatch(/反射|倒影/);
    expect(reflectionCopy(zhHant)).not.toMatch(/反射|倒影/);
    expect(reflectionCopy(vi)).not.toMatch(/phản xạ|phản ánh/i);
    expect(reflectionCopy(ko)).not.toMatch(/반사|반영/);
    expect(reflectionCopy(ja)).not.toMatch(/反射|反省|反映|リフレクション/);

    for (const messages of [zhHans, zhHant, vi, ko, ja]) {
      expect([
        messages['onboarding.inTune'],
        messages['onboarding.sharp'],
        messages['onboarding.flat'],
      ]).toEqual([
        messages['tuning.inTune'],
        messages['tuning.sharp'],
        messages['tuning.flat'],
      ]);
    }
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
      ko: ['편안한 슬러 연습', '지속음과 음정', '악보'],
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

  it('keeps the QA pseudo-locale programmatically available but out of the production picker', () => {
    expect(localeOptions.map((option) => option.value)).toContain('en-XA');
    expect(productionLocaleOptions.map((option) => option.value)).toEqual(productionLocales);
  });

  it('renders an onboarding save failure from each locale catalog', async () => {
    for (const locale of productionLocales) {
      const messages = await loadMessagesForLocale(locale);
      expect(messages['onboarding.saveFailed']).not.toHaveLength(0);
      if (locale !== 'en') expect(messages['onboarding.saveFailed']).not.toBe(englishMessages['onboarding.saveFailed']);
    }
  });
});
