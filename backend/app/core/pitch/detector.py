import time
from collections import deque
from statistics import median
from typing import Deque, Dict, Iterable, List, Optional, Tuple, Union

import numpy as np

from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import PitchFrame, frequency_to_pitch_frame

try:
    import aubio  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    aubio = None


class PitchDetector:
    def __init__(self, sample_rate: int = 48000, frame_size: int = 4096):
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

    def estimate(
        self,
        pcm: Iterable[float],
        sample_rate: Optional[int] = None,
        min_frequency_hz: float = 30.0,
        max_frequency_hz: float = 2000.0,
    ) -> Dict[str, Union[float, str]]:
        samples = np.asarray(list(pcm), dtype=np.float32)
        if samples.size == 0:
            return {"frequency_hz": 0.0, "confidence": 0.0, "rms": 0.0, "detector_source": "none"}
        sr = sample_rate or self.sample_rate
        rms = float(np.sqrt(np.mean(np.square(samples))))
        if rms < 0.005:
            return {"frequency_hz": 0.0, "confidence": 0.0, "rms": rms, "detector_source": "silence"}
        if self._aubio_pitch is not None and sr == self.sample_rate:
            try:
                freq = float(self._aubio_pitch(samples)[0])
                confidence = float(self._aubio_pitch.get_confidence())
                if freq > 0:
                    return {"frequency_hz": freq, "confidence": max(0.0, min(confidence, 1.0)), "rms": rms, "detector_source": "aubio"}
            except Exception:
                pass
        freq, confidence = yin_pitch(samples, sr, min_frequency_hz, max_frequency_hz)
        return {"frequency_hz": freq, "confidence": confidence, "rms": rms, "detector_source": "yin_fallback"}

    def estimate_frame(
        self,
        pcm: Iterable[float],
        sample_rate: Optional[int],
        instrument_id: str,
        reference_pitch_hz: float,
        timestamp_ms: Optional[int] = None,
    ) -> PitchFrame:
        profile = get_instrument_profile(instrument_id)
        estimate = self.estimate(pcm, sample_rate, profile.min_frequency_hz, profile.max_frequency_hz)
        frequency_hz = float(estimate["frequency_hz"])
        freq = frequency_hz if frequency_hz > 0 else None
        return frequency_to_pitch_frame(
            freq,
            float(estimate["confidence"]),
            float(estimate["rms"]),
            int(timestamp_ms if timestamp_ms is not None else time.time() * 1000),
            instrument_id,
            reference_pitch_hz,
            str(estimate["detector_source"]),
        )


def yin_pitch(
    samples: np.ndarray,
    sample_rate: int,
    min_frequency_hz: float = 30.0,
    max_frequency_hz: float = 2000.0,
    threshold: float = 0.14,
) -> Tuple[float, float]:
    samples = samples.astype(np.float32)
    samples = samples - float(np.mean(samples))
    if samples.size < 64:
        return 0.0, 0.0
    peak = float(np.max(np.abs(samples)))
    if peak <= 0:
        return 0.0, 0.0
    samples = samples / peak
    min_tau = max(2, int(sample_rate / max_frequency_hz))
    max_tau = min(samples.size - 2, int(sample_rate / min_frequency_hz))
    if max_tau <= min_tau:
        return 0.0, 0.0

    difference = np.zeros(max_tau + 1, dtype=np.float64)
    for tau in range(1, max_tau + 1):
        delta = samples[:-tau] - samples[tau:]
        difference[tau] = float(np.dot(delta, delta))

    cmnd = np.ones(max_tau + 1, dtype=np.float64)
    cumulative = 0.0
    for tau in range(1, max_tau + 1):
        cumulative += difference[tau]
        cmnd[tau] = difference[tau] * tau / cumulative if cumulative > 0 else 1.0

    tau = 0
    for candidate in range(min_tau, max_tau):
        if cmnd[candidate] < threshold:
            while candidate + 1 <= max_tau and cmnd[candidate + 1] < cmnd[candidate]:
                candidate += 1
            tau = candidate
            break
    if tau == 0:
        search = cmnd[min_tau : max_tau + 1]
        if search.size == 0:
            return 0.0, 0.0
        tau = int(np.argmin(search) + min_tau)
        if cmnd[tau] > 0.55:
            return 0.0, max(0.0, min(1.0 - float(cmnd[tau]), 1.0))

    refined_tau = _parabolic_tau(cmnd, tau)
    if refined_tau <= 0:
        return 0.0, 0.0
    frequency = float(sample_rate / refined_tau)
    confidence = max(0.0, min(1.0 - float(cmnd[tau]), 1.0))
    if confidence < 0.25 or frequency < min_frequency_hz or frequency > max_frequency_hz:
        return 0.0, confidence
    return frequency, confidence


def _parabolic_tau(values: np.ndarray, tau: int) -> float:
    if tau <= 0 or tau >= len(values) - 1:
        return float(tau)
    left = float(values[tau - 1])
    center = float(values[tau])
    right = float(values[tau + 1])
    denominator = left - 2 * center + right
    if abs(denominator) < 1e-12:
        return float(tau)
    return float(tau + 0.5 * (left - right) / denominator)


def autocorrelation_pitch(samples: np.ndarray, sample_rate: int) -> Tuple[float, float]:
    return yin_pitch(samples, sample_rate)


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
