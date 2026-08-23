from dataclasses import asdict, dataclass
from typing import Dict, List


@dataclass(frozen=True)
class InstrumentProfile:
    id: str
    display_name: str
    transposition_semitones: int
    min_frequency_hz: float
    max_frequency_hz: float
    preferred_note_spellings: List[str]
    typical_range_written: str
    common_tuning_tendencies: List[str]
    recommendation_templates: Dict[str, List[str]]
    future_swift_notes: str

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)


BRASS_FLAT_SPELLINGS = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
BRASS_MIXED_SPELLINGS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


INSTRUMENT_PROFILES: Dict[str, InstrumentProfile] = {
    "trumpet": InstrumentProfile(
        id="trumpet",
        display_name="Trumpet in Bb",
        transposition_semitones=2,
        min_frequency_hz=130.0,
        max_frequency_hz=1500.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="F#3-C6",
        common_tuning_tendencies=[
            "Third-valve notes often trend sharp without slide adjustment.",
            "Upper-register notes can rise sharp when embouchure pressure increases.",
            "Long tones with drones help center partials before technical work.",
        ],
        recommendation_templates={
            "sharp": [
                "Check valve combinations and use the third-valve slide where relevant.",
                "Start slightly below pitch, then center upward with steady air.",
                "Release excess mouthpiece pressure before repeating the note.",
            ],
            "flat": [
                "Support the air stream so the pitch does not sag at the end of the tone.",
                "Check that the main tuning slide is not pulled too far.",
                "Practice lip bends back into the center of the pitch.",
            ],
            "unstable": [
                "Hold the note for 8 seconds and aim for minimal needle movement.",
                "Repeat the note from a relaxed breath instead of pinching into it.",
            ],
        },
        future_swift_notes="Represent as an InstrumentProfile struct with semitone transposition and range validation.",
    ),
    "horn": InstrumentProfile(
        id="horn",
        display_name="French Horn in F",
        transposition_semitones=7,
        min_frequency_hz=80.0,
        max_frequency_hz=1200.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="F3-C6",
        common_tuning_tendencies=[
            "Small embouchure changes can produce large pitch movement.",
            "Hand position affects resonance and intonation.",
            "Partial accuracy matters because neighboring partials are close together.",
        ],
        recommendation_templates={
            "sharp": [
                "Check right-hand position and avoid closing the hand too far.",
                "Use slow slurs into the note before sustaining it with a drone.",
                "Let the air carry the pitch instead of squeezing upward.",
            ],
            "flat": [
                "Open the sound with stable air and a resonant vowel shape.",
                "Practice slow drone matching in the middle register.",
            ],
            "unstable": [
                "Repeat slow slurs into the note and listen for partial locking.",
                "Record several full-breath repetitions and compare the release.",
            ],
        },
        future_swift_notes="Keep transposition, written display, and horn-specific coaching in plain data.",
    ),
    "trombone": InstrumentProfile(
        id="trombone",
        display_name="Trombone",
        transposition_semitones=0,
        min_frequency_hz=50.0,
        max_frequency_hz=700.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="E2-Bb4",
        common_tuning_tendencies=[
            "Slide position accuracy is the primary intonation control.",
            "Alternate positions may center some notes better in context.",
        ],
        recommendation_templates={
            "sharp": [
                "Check whether the slide position is slightly too high.",
                "Practice slow glissando-to-center repetitions with a drone.",
            ],
            "flat": [
                "Check whether the slide position is slightly too low.",
                "Support the air so sustained notes do not settle flat.",
            ],
            "unstable": [
                "Move from the neighboring slide position into the pitch slowly, then hold.",
                "Keep the slide still once the tone is centered.",
            ],
        },
        future_swift_notes="Map directly to concert pitch; preserve slide-position recommendation metadata.",
    ),
    "euphonium": InstrumentProfile(
        id="euphonium",
        display_name="Euphonium",
        transposition_semitones=0,
        min_frequency_hz=55.0,
        max_frequency_hz=800.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="E2-Bb4",
        common_tuning_tendencies=[
            "Consistent tone production and air support strongly affect pitch center.",
            "Valve combinations can need compensation depending on the instrument.",
        ],
        recommendation_templates={
            "sharp": [
                "Check valve combinations and release embouchure tension.",
                "Use Remington-style long tones into the note.",
            ],
            "flat": [
                "Keep the tone resonant and the air stream full through the sustain.",
                "Practice long tones with drone matching before moving patterns.",
            ],
            "unstable": [
                "Repeat the note after a full breath and listen for a stable tone core.",
            ],
        },
        future_swift_notes="Concert-pitch euphonium remains distinct from the B-flat treble-clef profile.",
    ),
    "baritone": InstrumentProfile(
        id="baritone",
        display_name="Baritone in Bb (treble)",
        transposition_semitones=14,
        min_frequency_hz=55.0,
        max_frequency_hz=800.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="E3-Bb5",
        common_tuning_tendencies=[
            "Valve combinations can need compensation depending on the instrument.",
            "Steady air support helps keep the low register centered.",
        ],
        recommendation_templates={
            "sharp": ["Check valve combinations and release embouchure tension."],
            "flat": ["Keep the tone resonant and the air stream full through the sustain."],
            "unstable": ["Repeat the note after a full breath and listen for a stable tone core."],
        },
        future_swift_notes="Treble-clef B-flat low brass sounds a major ninth below written pitch.",
    ),
    "euphonium-treble": InstrumentProfile(
        id="euphonium-treble",
        display_name="Euphonium in Bb (treble)",
        transposition_semitones=14,
        min_frequency_hz=55.0,
        max_frequency_hz=800.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="E3-Bb5",
        common_tuning_tendencies=[
            "Valve combinations can need compensation depending on the instrument.",
            "Steady air support helps keep the low register centered.",
        ],
        recommendation_templates={
            "sharp": ["Check valve combinations and release embouchure tension."],
            "flat": ["Keep the tone resonant and the air stream full through the sustain."],
            "unstable": ["Repeat the note after a full breath and listen for a stable tone core."],
        },
        future_swift_notes="Treble-clef B-flat euphonium sounds a major ninth below written pitch.",
    ),
    "tuba": InstrumentProfile(
        id="tuba",
        display_name="Tuba",
        transposition_semitones=0,
        min_frequency_hz=30.0,
        max_frequency_hz=500.0,
        preferred_note_spellings=BRASS_MIXED_SPELLINGS,
        typical_range_written="D1-F4",
        common_tuning_tendencies=[
            "Stable air and resonance matter more than small embouchure corrections.",
            "Low notes need time to speak before pitch can be evaluated reliably.",
        ],
        recommendation_templates={
            "sharp": [
                "Relax the embouchure and keep the tone broad.",
                "Use slow drone work and listen for resonance instead of forcing pitch down.",
            ],
            "flat": [
                "Increase breath support and keep the air moving through the full note.",
                "Center the tone before adding volume.",
            ],
            "unstable": [
                "Hold the note with a steady air column and avoid changing vowel shape.",
            ],
        },
        future_swift_notes="Use the same profile fields on iOS; AVAudioEngine should feed concert pitch frames.",
    ),
}


def get_instrument_profile(instrument_id: str) -> InstrumentProfile:
    try:
        return INSTRUMENT_PROFILES[instrument_id]
    except KeyError:
        return INSTRUMENT_PROFILES["trumpet"]


def is_valid_instrument_id(instrument_id: str) -> bool:
    return instrument_id in INSTRUMENT_PROFILES


def require_instrument_profile(instrument_id: str) -> InstrumentProfile:
    try:
        return INSTRUMENT_PROFILES[instrument_id]
    except KeyError as exc:
        raise ValueError("Unknown instrument_id: %s" % instrument_id) from exc


def get_all_profiles() -> List[InstrumentProfile]:
    return list(INSTRUMENT_PROFILES.values())
