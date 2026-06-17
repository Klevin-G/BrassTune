import time
from collections import deque
from statistics import median
from typing import Deque, Dict, Iterable, List, Optional, Tuple

import numpy as np

from app.core.music.theory import PitchFrame, frequency_to_pitch_frame

try:
    import aubio  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    aubio = None


class PitchDetector:
    def __init__(self, sample_rate: int = 48000, frame_size: int = 2048):
        self.sample_rate = sample_rate
        self.frame_size = frame_size
        self._aubio_pitch = None
        if aubio is not None:
            try:
                self._aubio_pitch = aubio.pitch("yin", frame_size * 2, frame_size, sample_rate)
                self._aubio_pitch.set_unit("Hz")
                self._aubio_pitch.set_silence(-45)
            except Exception:
                self._aubio_pitch = None

    def estimate(self, pcm: Iterable[float], sample_rate: Optional[int] = None) -> Dict[str, float]:
        samples = np.asarray(list(pcm), dtype=np.float32)
        if samples.size == 0:
            return {"frequency_hz": 0.0, "confidence": 0.0, "rms": 0.0}
        sr = sample_rate or self.sample_rate
        rms = float(np.sqrt(np.mean(np.square(samples))))
        if rms < 0.005:
            return {"frequency_hz": 0.0, "confidence": 0.0, "rms": rms}
        if self._aubio_pitch is not None and sr == self.sample_rate:
            try:
                freq = float(self._aubio_pitch(samples)[0])
                confidence = float(self._aubio_pitch.get_confidence())
                if freq > 0:
                    return {"frequency_hz": freq, "confidence": max(0.0, min(confidence, 1.0)), "rms": rms}
            except Exception:
                pass
        freq, confidence = autocorrelation_pitch(samples, sr)
        return {"frequency_hz": freq, "confidence": confidence, "rms": rms}

    def estimate_frame(
        self,
        pcm: Iterable[float],
        sample_rate: Optional[int],
        instrument_id: str,
        reference_pitch_hz: float,
        timestamp_ms: Optional[int] = None,
    ) -> PitchFrame:
        estimate = self.estimate(pcm, sample_rate)
        freq = estimate["frequency_hz"] if estimate["frequency_hz"] > 0 else None
        return frequency_to_pitch_frame(
            freq,
            estimate["confidence"],
            estimate["rms"],
            int(timestamp_ms if timestamp_ms is not None else time.time() * 1000),
            instrument_id,
            reference_pitch_hz,
        )


def autocorrelation_pitch(samples: np.ndarray, sample_rate: int) -> Tuple[float, float]:
    samples = samples.astype(np.float32)
    samples = samples - float(np.mean(samples))
    if samples.size < 64:
        return 0.0, 0.0
    windowed = samples * np.hanning(samples.size)
    corr = np.correlate(windowed, windowed, mode="full")[samples.size - 1 :]
    if corr[0] <= 0:
        return 0.0, 0.0
    min_freq = 30.0
    max_freq = 2000.0
    min_lag = max(1, int(sample_rate / max_freq))
    max_lag = min(len(corr) - 1, int(sample_rate / min_freq))
    if max_lag <= min_lag:
        return 0.0, 0.0
    segment = corr[min_lag:max_lag]
    if segment.size == 0:
        return 0.0, 0.0
    lag = int(np.argmax(segment) + min_lag)
    peak = float(corr[lag])
    confidence = max(0.0, min(peak / float(corr[0]), 1.0))
    if confidence < 0.25:
        return 0.0, confidence
    return float(sample_rate / lag), confidence


def smooth_pitch_frames(frames: List[PitchFrame], window_size: int = 5) -> List[PitchFrame]:
    recent: Deque[float] = deque(maxlen=window_size)
    smoothed: List[PitchFrame] = []
    for frame in frames:
        if frame.is_valid_for_recording and frame.cents_deviation is not None:
            recent.append(frame.cents_deviation)
            adjusted = PitchFrame(**frame.to_dict())
            adjusted.cents_deviation = float(median(recent))
            smoothed.append(adjusted)
        else:
            smoothed.append(frame)
    return smoothed


def detect_stable_note(frames: List[PitchFrame], required_frames: int = 3) -> Optional[Tuple[str, int]]:
    valid = [f for f in frames[-required_frames:] if f.is_valid_for_recording]
    if len(valid) < required_frames:
        return None
    labels = [(f.written_note_name, f.written_octave) for f in valid]
    first = labels[0]
    if all(label == first for label in labels):
        return first  # type: ignore[return-value]
    return None

