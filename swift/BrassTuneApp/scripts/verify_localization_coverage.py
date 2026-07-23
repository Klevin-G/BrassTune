#!/usr/bin/env python3
"""Audit native user-facing static literals against the String Catalog."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "BrassTuneApp"
CATALOG_PATH = SOURCE_ROOT / "Resources" / "Localizable.xcstrings"
PRODUCTION_LOCALES = {
    "ar", "de", "en", "es", "fr", "ja", "ko", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"
}

# These keys are intentionally invariant technical tokens, product names,
# autonyms, standard loanwords, or placeholder-only metric layouts.
ALLOWED_SOURCE_ECHOES = {
    "%@ BPM · %@ · %@", "%@ cents", "BPM", "BrassTune", "Classes",
    "Deutsch", "Email", "Español", "Euphonium", "Français", "Horn in F",
    "Instrument", "Meter", "Name", "Octave", "Original", "Page %@", "Photos",
    "Play-Along: %@.", "Português (Brasil)", "Status", "Student", "Subdivision",
    "Tempo", "Triplet", "Trombone", "Tuba", "Version %@ (%@)", "Volume",
}

ALLOWED_DYNAMIC_LITERALS = {
    r"\(count) practice sessions",  # Catalog-backed CLDR plural.
    r"\(names[pitch])\((writtenMIDI / 12) - 1)",  # Internal A-G/octave note ID.
    r"\(note)\(octave)",  # Internal A-G/octave note ID.
}

CALLS = (
    "Text", "Label", "Button", "Picker", "Toggle", "Section", "GroupBox",
    "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue",
    "alert", "confirmationDialog", "TextField", "SecureField", "LabeledContent",
)

DIRECT_PATTERN = re.compile(
    rf"\b(?:{'|'.join(CALLS)})\(\s*\"((?:[^\"\\]|\\.)*)\""
)
LOCALIZED_PATTERN = re.compile(
    r"(?:String\(localized:\s*|NativeLocalization\.(?:string|format)\(\s*)\"((?:[^\"\\]|\\.)*)\""
)
NAMED_COPY_PATTERN = re.compile(
    r"\b(?:eyebrow|title|subtitle|message|detail|practiceNotes)\s*:\s*\"((?:[^\"\\]|\\.)*)\""
)
RETURN_PATTERN = re.compile(r"\breturn\s+\"((?:[^\"\\]|\\.)*)\"")


def decode_swift_literal(value: str) -> str:
    return value.replace(r'\"', '"').replace(r"\n", "\n")


def should_preserve_verbatim(value: str) -> bool:
    return bool(
        not value
        or re.fullmatch(r"[A-G](?:#|b|♯|♭)?", value)
        or re.fullmatch(r"[A-G](?:#|b|♯|♭)?-?[0-9]", value)
        or value.startswith(("/api/", "/auth/", "http://", "https://"))
        or re.fullmatch(r"[a-z0-9_.-]+", value)
    )


def source_keys() -> tuple[set[str], dict[str, list[str]]]:
    static: set[str] = set()
    dynamic: dict[str, list[str]] = {}
    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for pattern in (DIRECT_PATTERN, LOCALIZED_PATTERN, NAMED_COPY_PATTERN, RETURN_PATTERN):
            for match in pattern.finditer(text):
                value = decode_swift_literal(match.group(1))
                if should_preserve_verbatim(value):
                    continue
                line = text.count("\n", 0, match.start()) + 1
                location = f"{path.relative_to(ROOT)}:{line}"
                if r"\(" in value:
                    dynamic.setdefault(value, []).append(location)
                else:
                    static.add(value)
    return static, dynamic


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="Print the discovered static keys as JSON")
    parser.add_argument("--dynamic-json", action="store_true", help="Print interpolated literals and source locations as JSON")
    parser.add_argument("--allow-missing", action="store_true")
    args = parser.parse_args()

    keys, dynamic = source_keys()
    if args.json:
        print(json.dumps(sorted(keys), ensure_ascii=False, indent=2))
        return 0
    if args.dynamic_json:
        print(json.dumps(dynamic, ensure_ascii=False, indent=2, sort_keys=True))
        return 0

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entries = catalog.get("strings", {})
    missing = sorted(keys - entries.keys())
    incomplete: list[str] = []
    source_echoes: list[str] = []
    terminology_violations: list[str] = []
    for key in sorted(keys & entries.keys()):
        localizations = entries[key].get("localizations", {})
        if set(localizations) != PRODUCTION_LOCALES:
            incomplete.append(key)
            continue
        for locale in PRODUCTION_LOCALES - {"en"}:
            unit = localizations[locale].get("stringUnit", {})
            if not unit.get("value"):
                incomplete.append(key)
                break
            if (unit.get("value") == key and key not in ALLOWED_SOURCE_ECHOES
                    and re.search(r"[A-Za-z]{3}", key)):
                source_echoes.append(f"{locale}: {key}")

            value = unit.get("value", "").lower()
            key_lower = key.lower()
            checks: list[tuple[str, tuple[str, ...]]] = []
            if "slur" in key_lower:
                checks += [("es", ("insulto",)), ("ja", ("中傷",))]
            if "drone" in key_lower:
                checks += [
                    ("ar", ("طائرة",)), ("de", ("drohn",)), ("es", ("dron",)),
                    ("fr", ("drone",)), ("pt-BR", ("drone",)), ("ru", ("дрон",)),
                    ("vi", ("máy bay",)), ("zh-Hans", ("无人机",)), ("zh-Hant", ("無人機",)),
                ]
            if re.search(r"\bcents?\b", key_lower):
                checks += [
                    ("es", ("centavo",)), ("fr", ("centime",)), ("pt-BR", ("centavo",)),
                    ("zh-Hans", ("美分",)), ("zh-Hant", ("美分",)),
                ]
                # Vietnamese `xu` is a currency unit, but it is also the prefix of
                # ordinary words such as `xuống`; require an independent word.
                if locale == "vi" and re.search(r"(?<!\w)xu(?!\w)", value):
                    terminology_violations.append(f"{locale}: {key} -> {unit.get('value', '')}")
            if "class" in key_lower:
                checks += [
                    ("ko", ("수업",)), ("zh-Hans", ("课堂", "课程", "类别")),
                    ("zh-Hant", ("課堂", "課程", "類別")),
                ]
            if "guest" in key_lower:
                checks += [("pt-BR", ("visitante",))]
            if "score" in key_lower and key not in {"Your score", "Test score"}:
                checks += [
                    ("es", ("puntuación",)), ("fr", ("score",)), ("pt-BR", ("pontuação", "placar")),
                    ("ru", ("счет", "оценк")), ("vi", ("điểm số", "tỉ số")),
                    ("zh-Hans", ("分数", "比分")), ("zh-Hant", ("分數", "比分")),
                    ("ko", ("점수",)), ("ja", ("スコア",)),
                ]
            for checked_locale, banned_terms in checks:
                if locale == checked_locale and any(term in value for term in banned_terms):
                    terminology_violations.append(f"{locale}: {key} -> {unit.get('value', '')}")

    unexpected_dynamic = sorted(set(dynamic) - ALLOWED_DYNAMIC_LITERALS)

    print(f"Static user-facing keys: {len(keys)}")
    print(f"Catalog entries: {len(entries)}")
    print(f"Dynamic/interpolated literals reviewed separately: {len(dynamic)}")
    print(f"Missing static keys: {len(missing)}")
    print(f"Incomplete locale sets: {len(incomplete)}")
    print(f"Non-English source echoes: {len(source_echoes)}")
    print(f"Terminology violations: {len(terminology_violations)}")
    print(f"Allowed dynamic literal exceptions: {len(dynamic)}")
    if missing:
        print("\nMissing keys:")
        print("\n".join(missing))
    if incomplete:
        print("\nIncomplete keys:")
        print("\n".join(incomplete))
    if source_echoes:
        print("\nSource echoes:")
        print("\n".join(source_echoes))
    if terminology_violations:
        print("\nTerminology violations:")
        print("\n".join(terminology_violations))
    if unexpected_dynamic:
        print("\nUnexpected dynamic literals:")
        print("\n".join(unexpected_dynamic))
    if (missing or incomplete or source_echoes or terminology_violations or unexpected_dynamic) and not args.allow_missing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
