# Pitch Detection Notes

The MVP supports two backend detection paths.

## Aubio Path

If `aubio` is installed, `PitchDetector` uses Aubio's YIN implementation and asks for frequency in Hz. Aubio generally provides better pitch stability than the simple fallback.

Optional install:

```bash
pip install aubio librosa
```

`librosa` is not required by the current runtime path, but it is useful for future offline analysis and validation notebooks.

## Fallback Path

If Aubio is missing or fails, the app uses a NumPy autocorrelation detector:

1. Convert PCM input to float samples.
2. Remove DC offset.
3. Apply a Hann window.
4. Compute autocorrelation.
5. Search lag range for roughly `30 Hz` to `2000 Hz`.
6. Convert best lag to frequency.
7. Estimate confidence from autocorrelation peak strength.

The fallback is intentionally dependency-light so the local MVP runs on a normal Python setup.

## Signal Handling

Frames are rejected or labeled before recording when:

- RMS is below the silence threshold.
- Confidence is low.
- Frequency is outside the selected instrument range.
- Cents or note data is unavailable.

Valid frames are those classified as `flat`, `in_tune`, or `sharp`.

## Expected Accuracy

With a clean sustained tone and stable microphone signal, Aubio should be able to meet the MVP target of about +/-5 cents. The fallback detector is practical for local testing, but may be less stable with noisy input, vibrato, very low tuba notes, or short attacks.

## Future Work

- Tune YIN thresholds per instrument range.
- Track pitch stability over a rolling window before saving note events.
- Add browser-side noise floor calibration.
- Persist aggregate silence and unstable counts for richer practice feedback.
- Compare native Swift pitch detection fixtures against backend fixtures before port launch.

