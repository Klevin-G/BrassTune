# BrassTune / TonalEnergy brass-practice comparison — October 23, 2026

Project attribution: Kelvin Guo, Arya Salem.

This task implements two concrete gaps: silent-bar pulse training and instrument-specific note history with a direct practice-goal handoff. Source review, core/unit checks, four simulator UI journeys and two physical-phone checks have passed. These local changes are separate from the previously submitted 1.0.8 (20) artifact; this follow-up does not publish a new build.

## Comparison and decision

TonalEnergy evidence below is vendor-documented capability, inspected in its [official iOS user guide](https://www.tonalenergy.com/tet-user-guide-ios) and [product page](https://www.tonalenergy.com/). BrassTune evidence comes from the native source and checks recorded below. No TonalEnergy binary, acoustic accuracy comparison, or student learning trial was run. An undocumented feature is not assumed absent.

| Brass-practice job | TonalEnergy documentation | BrassTune before this task | Result / remaining gap |
| --- | --- | --- | --- |
| Keep pulse without a click | Fixed/random silent bars and tempo progression (Metronome Assistant) | Standard click, count-in, compound meters, presets, duplex tuner | Implemented deterministic audible/silent bars. Random silence and tempo ramps remain absent. |
| Find recurring note tendencies | Per-note tuning statistics and date-range activity (Pitch Tracker / Activity Page) | Detailed analysis of an individual saved take; broad history aggregates | Added instrument/A4-scoped 30-day note evidence and an explicit goal action. This does not establish unique statistics or better accuracy. |
| Brass flexibility exercises | Configurable harmonic-series/lip-slur exercises (Auto Exercise Creator) | Guided warm-ups, scales, custom note sequences | Dedicated harmonic-series generation remains a gap. |
| Tune chords and references | Keyed/custom temperaments and reference sounds (Temperament / Tone Generator) | Equal/just drone intervals and triads; equal-tempered capture metrics | Live keyed/custom temperament and simultaneous native drone/capture remain gaps. |
| Review and integrate recordings | Editing, looping, tempo/pitch playback, MIDI/remote and Ableton options | Local takes, pitch analysis, playback and export | Broader recording and integration capabilities remain gaps. |
| Reach students on other devices | iOS, Android and desktop offerings | Native iOS; unpublished Android guest alpha | A public Android release is still not delivered by this task. |

The implementation priority is a common fundamentals exercise plus a clear evidence-to-next-goal workflow. It improves BrassTune's own brass practice experience and closes selected functional gaps; it is not a claim that BrassTune surpasses TonalEnergy overall.

## Implemented behavior

### Silent-bar trainer

- Persisted, default-off gap settings: 1–4 bars with clicks, followed by 1–4 silent bars.
- The audio graph queues actual PCM bars; silent bars contain zero samples. A monotonic actor-owned queue preserves order without rebuilding the graph at every gap.
- Count-in precedes the cycle. Existing simple/compound meter, subdivisions and accent rules are preserved.
- Silent bars withhold beat numbers, pulsing animation and haptics. The screen supplies a neutral phase cue rather than a substitute metronome.
- Absolute audio-clock indices keep phase correct after coalesced callbacks. Accepted runtime settings remain distinct from pending edits.
- Combined tuner frames are blocked during audio handoffs; stale callbacks cannot reopen the gate. Dense click bars no longer imply that silent bars offer no usable capture window.
- Resident PCM allocation has a 64 MiB preflight ceiling, including replacement overlap and click buffers. Extreme unsupported configurations fail safely rather than allocate without bounds.

### Intonation history and next goal

- Derived locally from completed live captures in the last 30 calendar days, for the selected instrument and current A4 calibration (±0.05 Hz).
- Excludes sample/manual data, invalid metadata, contradictory signal-validity flags, conflicting duplicates, nonfinite values and invalid timing spans. Captures may retain an arbitrary audio-clock offset; only the distinct sample span is compared with wall duration.
- Trims note attacks and requires sufficient stable samples. Each qualifying take contributes one median, so a long recording cannot count as many independent takes.
- Recurring labels require at least three qualifying takes over two days, a displayed median deviation of at least 10 cents, and two-thirds directional agreement. Sparse results expose evidence counts without a recurring direction label.
- Deviations are explicitly relative to equal temperament. Intentional chord tuning can differ. The app does not infer embouchure, valve/slide corrections, natural pitch, or learning gains.
- Prioritizes recurring actionable observations before sparse outliers. Goal creation uses an instrument-labelled, fixed eight-second, listen-first target, with no invented achieved values.
- Existing active goals are reused; completed goals can be reopened explicitly. Guest/account ID collisions preserve both distinct histories and make repeated merges idempotent.
- Analysis is cached and refreshed when source data, instrument, calibration or day changes; event lookup uses timestamp slices rather than rescanning every frame for every event.

## Source ownership

Modified native files: `Models.swift`, `NativeAudioEngine.swift`, `AppModel.swift`, `AppRootView.swift`, `FocusedPracticeViews.swift`, localization catalog, and Xcode project registration. New files: `IntonationHistory.swift`, `IntonationHistoryView.swift`, `GapMetronomeTests.swift`, `IntonationHistoryTests.swift`, and `CompetitivePracticeUITests.swift`.

All earlier dirty work was preserved. No commit, push, App Store submission replacement, backend migration, or website deployment is part of this follow-up.

## Review and validation

Durable evidence: `~/Library/Application Support/BrassTune/ReleaseEvidence/CompetitivePractice-2026-10-23/` (source hashes, summaries, result bundles, logs and review record). Scratch evidence: `/tmp/brasstune-comparison-20261023/` (including baseline patch and earlier failed runs).

Discovery used a Terra Medium documentation researcher and Luna Medium repository scout. Gap-audio implementation requested Sol High because of sample timing and concurrent audio handoffs; intonation implementation requested Terra Medium. Independent audio and scientific reviewers requested Sol High; translation preparation requested Terra Low. Effective Codex child routing was not exposed. Claude Desktop showed Opus 5.5 Medium selected and reviewed both the acceptance contracts and source changes.

Reviews caught and prompted fixes for skipped-clock phase drift, pending-settings/audio mismatch, tuner contamination during handoff, malformed/duplicate evidence, sparse outlier ranking, deterministic-ID history loss, and stale cached session reads. Parser checks alone were not counted as passing builds.

| Check | Result |
| --- | --- |
| Shared core | 12 passed |
| Native unit suite | 378 passed, 0 failed, 0 skipped (`unit-final-r2.xcresult`) |
| Focused UI suite | 4 passed: gap cycle/persistence, empty and populated history to one goal, tempo controls, and denied-microphone recovery (`workflows-r3.xcresult`) |
| Physical USB-device exercises | 2 passed on iPhone 15 Pro Max, iOS 26.6.2: real gap-output cycle/stop (`physical-gap-r2.xcresult`) and microphone start/stop/restart/foreground recovery (`physical-mic-final.xcresult`), both in the `.dev` app |
| Localization | 1,029 static keys; no missing, incomplete, placeholder, terminology or semantic-sentinel violations |
| Xcode project syntax / diff whitespace | Passed |
| Independent source reviews | Audio and scientific reviewers approved; Claude Opus 5.5 Medium closed all source concerns, including independently checking the final publisher-payload cache fix |

A repeatable month-size performance test analyzed 150 takes / 405,000 frames in a mean 0.229 seconds across three measurements on the Mac-hosted simulator. This is not a phone performance result or a competitor benchmark.

Initial test failures were retained: invalid duration/replay unit fixtures were corrected; the seeded UI history was absent because this project does not define `DEBUG`, so it now uses the existing `.dev` fixture guard; physical scrolling was changed to edge gestures to avoid the tempo wheel. The populated-history return journey also requires dismissing the normal guest-account reminder. No failing run is represented as a pass.

Commands: `swift test` in `swift/BrassTuneCore`; XcodeBuildMCP `test_sim` with the native unit target and focused UI methods; `xcodebuild test` with explicit simulator/device destinations for longer UI batches and the physical exercise; `python3 swift/BrassTuneApp/scripts/verify_localization_coverage.py`; `plutil -lint` on the Xcode project; `git diff --check`.

The native suite preceded the final isolated UI-fixture guard and harness adjustments; subsequent simulator/device builds compiled those final changes. The domain/audio implementation was unchanged after the 378-test pass. Backend/web suites were not rerun because this task changes only the native app. No new signed distribution archive or App Store upload was produced.

Remaining limits: the implementation does not detect a musician's rhythmic drift during silence, establish a physiological cause for pitch tendencies, measure teaching effectiveness, or benchmark TonalEnergy's audio accuracy. Platform breadth, automatic tempo training, harmonic-series exercise generation, and full drone/tuner coexistence remain separate work.
