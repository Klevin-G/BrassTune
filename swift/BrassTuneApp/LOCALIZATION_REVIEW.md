# Native localization terminology review

Reviewed: 2026-07-22

The native String Catalog covers the 12 production locales (`en`, `es`,
`zh-Hans`, `zh-Hant`, `ar`, `fr`, `de`, `ru`, `pt-BR`, `ja`, `ko`, and `vi`).
`System Default` remains a separate app preference rather than a thirteenth
locale. The catalog also contains a real plural/interpolation entry and the
localized microphone permission purpose string.

The 2026-07-22 coverage audit discovers 472 static user-facing source keys and
checks all 482 catalog entries. It reports zero missing keys, incomplete locale
sets, or non-English source echoes. The only three dynamic literal patterns are
the catalog-backed practice-session plural and two internal A–G/octave note-ID
builders; numeric, note, email, class-name, file-type, and other user-authored
insertions are wrapped with Unicode FSI/PDI before entering localized prose.
Arabic practice-session counts define zero, one, two, few, many, and other.

## Second-pass music terminology decisions

- **Tuner** means the pitch-measuring tool, not a person. Translations use the
  standard tool term in each locale.
- **Flat / In tune / Sharp** describe relative pitch direction. They are
  translated as low / centered / high where a literal accidental name would
  be ambiguous.
- **Metronome** remains the standard musical term. BPM stays `BPM`, and A4,
  hertz values, cents, and meter fractions are not translated as prose.
- **Class** means a teacher-managed ensemble, not a software type or classroom
  room. Singular `Class` is used in the tab; plural `Classes` is used for the
  screen title.
- **Practice** is translated as musical practice/rehearsal, not a medical or
  professional practice.
- **Play-Along scorer** terms preserve the product distinction: centered notes
  count as in tune; close notes are accepted for progression but do not count
  as centered.
- Note names A–G, accidentals (`#`, `b`), octaves, imported score titles,
  exercise titles created by the user, class names, email addresses, and other
  user-authored text are preserved verbatim.
- Arabic is the RTL QA locale. The global interface follows RTL while the
  tuning meter remains left-to-right so low pitch stays left and high pitch
  stays right.

## Approved music glossary

These terms were checked as music vocabulary in every non-English locale. The
embouchure term is reserved for future recommendation copy; no current native
source key contains that word.

| Locale | Slur | Flat / sharp pitch | Score / sheet music | Drone | Pitch | Cents | Embouchure |
|---|---|---|---|---|---|---|---|
| es | ligadura / ligado | bajo / alto | partitura | nota pedal | altura / afinación | cents | embocadura |
| zh-Hans | 连音 | 偏低 / 偏高 | 乐谱 | 持续音 | 音高 | 音分 | 口型 |
| zh-Hant | 圓滑奏 | 偏低 / 偏高 | 樂譜 | 持續音 | 音高 | 音分 | 嘴型 |
| ar | ربط النغمات | منخفض / مرتفع | النوتة الموسيقية | نغمة مستمرة | طبقة الصوت | سنت | وضعية الشفتين |
| fr | liaison | trop bas / trop haut | partition | bourdon | hauteur | cents | embouchure |
| de | Bindung | zu tief / zu hoch | Partitur / Noten | Bordun | Tonhöhe | Cent | Ansatz |
| ru | легато | ниже / выше | партитура / ноты | бурдон | высота звука | центы | амбушюр |
| pt-BR | ligado | abaixo / acima | partitura | bordão | altura / afinação | cents | embocadura |
| ja | スラー | 低め / 高め | 楽譜 | ドローン | 音高 | セント | アンブシュア |
| ko | 슬러 | 낮음 / 높음 | 악보 | 드론 | 음높이 | 센트 | 앙부슈어 |
| vi | luyến tiếng | thấp / cao | bản nhạc | âm nền kéo dài | cao độ | cent | khẩu hình |

Runtime-created error, audio, verdict, and accessibility strings use
`NativeLocalization`, which reads the explicit in-app language rather than the
device locale. This prevents an English-system/Arabic-selection mismatch.

## Release follow-up

The structural tests reject any catalog entry missing a production locale.
Before App Store submission, a fluent reviewer should still perform in-context
screenshots on phone and iPad for all 12 locales, with special attention to
German/Russian expansion, Chinese/Japanese line breaks, Arabic RTL navigation,
VoiceOver announcements, legal/support copy, and the less-traveled score and
offline-pack screens. This review is separate from simulator build correctness.
