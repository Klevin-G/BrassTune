# Native localization terminology review

Reviewed: 2026-07-22

The native String Catalog covers the 12 production locales (`en`, `es`,
`zh-Hans`, `zh-Hant`, `ar`, `fr`, `de`, `ru`, `pt-BR`, `ja`, `ko`, and `vi`).
`System Default` remains a separate app preference rather than a thirteenth
locale. The catalog also contains a real plural/interpolation entry and the
localized microphone permission purpose string.

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

## Release follow-up

The structural tests reject any catalog entry missing a production locale.
Before App Store submission, a fluent reviewer should perform in-context
screenshots on phone and iPad for all 12 locales, with special attention to
German/Russian expansion, Chinese/Japanese line breaks, Arabic RTL navigation,
VoiceOver announcements, legal/support copy, and the less-traveled score and
offline-pack screens. This review is separate from simulator build correctness.
