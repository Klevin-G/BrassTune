#!/usr/bin/env python3
"""Audit native user-facing static literals against the String Catalog."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "BrassTuneApp"
CATALOG_PATH = SOURCE_ROOT / "Resources" / "Localizable.xcstrings"
SEMANTIC_SENTINELS_PATH = ROOT / "scripts" / "localization_semantic_sentinels.json"
PRODUCTION_LOCALES = {
    "ar", "de", "en", "es", "fr", "ja", "ko", "pt-BR", "ru", "vi", "zh-Hans", "zh-Hant"
}

# These keys are intentionally invariant technical tokens, product names,
# autonyms, standard loanwords, or placeholder-only metric layouts.
ALLOWED_SOURCE_ECHOES = {
    "%@ BPM · %@ · %@", "%@ cents", "A4 %@ Hz", "BPM", "BrassTune", "Classes",
    "5 minutes", "Apple", "Deutsch", "Email", "Español", "Euphonium", "Feedback", "Français", "Horn in F",
    "Instrument", "Local", "Meter", "Name", "Note %@", "Octave", "Original", "Page %@", "Photos",
    "Play-Along: %@.", "Português (Brasil)", "Status", "Student", "Subdivision",
    "Tempo", "Trends", "Triplet", "Trombone", "Tuba", "Version %@ (%@)", "Volume", "BPM %@",
}

ALLOWED_DYNAMIC_LITERALS = {
    r"\(count) practice sessions",  # Catalog-backed CLDR plural.
    r"\(count) pages",  # Catalog-backed CLDR plural.
    r"\(names[pitch])\((writtenMIDI / 12) - 1)",  # Internal A-G/octave note ID.
    r"\(note)\(octave)",  # Internal A-G/octave note ID.
}

CALLS = (
    "Text", "Label", "Button", "ProgressView", "Picker", "Toggle", "Section", "GroupBox",
    "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue",
    "alert", "confirmationDialog", "TextField", "SecureField", "LabeledContent", "Stepper",
)

DIRECT_PATTERN = re.compile(
    rf"\b(?:{'|'.join(CALLS)})\(\s*\"((?:[^\"\\]|\\.)*)\""
)
LOCALIZED_PATTERN = re.compile(
    r"(?:String\(localized:\s*|(?:NativeLocalization|language)\.(?:string|format|localized)\(\s*)\"((?:[^\"\\]|\\.)*)\""
)
NAMED_COPY_PATTERN = re.compile(
    r"\b(?:eyebrow|title|subtitle|message|detail|practiceNotes)\s*:\s*\"((?:[^\"\\]|\\.)*)\""
)
RETURN_PATTERN = re.compile(r"\breturn\s+\"((?:[^\"\\]|\\.)*)\"")
SWIFT_LITERAL_PATTERN = re.compile(r'"((?:[^"\\]|\\.)*)"')
AMBIGUOUS_RUNTIME_COPY_PATTERN = re.compile(
    r"\b(?:Text|Label)\(\s*(?!verbatim\s*:|LocalizedStringKey\(|\")([A-Za-z_][A-Za-z0-9_.]*)"
)
PRINTF_PATTERN = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|f|s|%)")

BTCOPY_ARGUMENTS_BY_CALLEE = {
    "BTPageHeader": {"eyebrow", "title", "subtitle", "trailing"},
    "BTSectionHeader": {"title", "subtitle"},
    "BTMetricTile": {"title", "value", "detail"},
    "BTStatusPill": {"text"},
    "BTEmptyState": {"title", "message"},
    "BTInsightTile": {"title", "detail"},
    "LegalCard": {"title", "messages"},
    "GuidedWarmupPlan": {"title"},
    "GuidedWarmupStep": {"title", "instruction"},
    "PracticePack": {"name", "detail"},
    "PracticePackBlock": {"title", "instruction"},
}

# Arabic has dedicated natural-language forms for exactly zero, one, and two,
# so those CLDR branches intentionally do not interpolate the numeric value.
CLDR_PLACEHOLDER_EXCEPTIONS = {
    ("%lld practice sessions", "ar", "variations.plural.zero"),
    ("%lld practice sessions", "ar", "variations.plural.one"),
    ("%lld practice sessions", "ar", "variations.plural.two"),
    ("%lld pages", "ar", "variations.plural.zero"),
    ("%lld pages", "ar", "variations.plural.one"),
    ("%lld pages", "ar", "variations.plural.two"),
}


def decode_swift_literal(value: str) -> str:
    return value.replace(r'\"', '"').replace(r"\n", "\n")


def should_preserve_verbatim(value: str) -> bool:
    return bool(
        not value
        or re.fullmatch(r"[A-G](?:#|b|♯|♭)?", value)
        or re.fullmatch(r"[A-G](?:#|b|♯|♭)?-?[0-9]", value)
        or value.startswith(("/api/", "/auth/", "http://", "https://"))
        # Accessibility and UI-test identifiers are technical dot-separated
        # tokens, not reader-facing copy. Camel-case suffixes are intentional.
        or re.fullmatch(r"[a-z][A-Za-z0-9]*(?:\.[a-z][A-Za-z0-9]*)+", value)
        or re.fullmatch(r"[a-z0-9_.-]+", value)
    )


def call_arguments(text: str, callee: str) -> list[tuple[str, int]]:
    """Return balanced Swift call arguments, including ternary branches."""
    results: list[tuple[str, int]] = []
    needle = f"{callee}("
    cursor = 0
    while (start := text.find(needle, cursor)) >= 0:
        index = start + len(needle)
        argument_start = index
        depth = 1
        in_string = False
        escaped = False
        while index < len(text) and depth:
            character = text[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
            elif character == '"':
                in_string = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            index += 1
        if depth == 0:
            results.append((text[argument_start:index - 1], start))
        cursor = max(index, start + len(needle))
    return results


def first_call_argument(arguments: str) -> str:
    depth = 0
    in_string = False
    escaped = False
    for index, character in enumerate(arguments):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in "([{":
            depth += 1
        elif character in ")]}" and depth:
            depth -= 1
        elif character == "," and depth == 0:
            return arguments[:index]
    return arguments


def top_level_arguments(arguments: str) -> list[str]:
    """Split a Swift argument list without splitting nested calls/closures."""
    parts: list[str] = []
    start = 0
    depth = 0
    in_string = False
    escaped = False
    for index, character in enumerate(arguments):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif character == "," and depth == 0:
            parts.append(arguments[start:index])
            start = index + 1
    parts.append(arguments[start:])
    return parts


def named_argument(argument: str) -> tuple[str, str] | None:
    match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)\Z", argument, re.DOTALL)
    return (match.group(1), match.group(2)) if match else None


def inside_verbatim_call(expression: str, literal_offset: int) -> bool:
    for arguments, start in call_arguments(expression, ".verbatim"):
        argument_start = start + len(".verbatim(")
        argument_end = argument_start + len(arguments)
        if argument_start <= literal_offset <= argument_end:
            return True
    return False


def placeholder_signature(value: str) -> Counter[str]:
    """Canonicalize printf placeholders while allowing positional reordering."""
    return Counter(match.group(2) for match in PRINTF_PATTERN.finditer(value))


def iter_string_units(node: object, path: tuple[str, ...] = ()):
    if not isinstance(node, dict):
        return
    string_unit = node.get("stringUnit")
    if isinstance(string_unit, dict):
        yield ".".join(path), string_unit
    for key, child in node.items():
        if key != "stringUnit":
            yield from iter_string_units(child, path + (key,))


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
        for callee in (
            "NativeLocalization.string", "NativeLocalization.format",
            "Button",
            "accessibilityLabel", "accessibilityHint", "accessibilityValue",
        ):
            for arguments, start in call_arguments(text, callee):
                first_argument = first_call_argument(arguments)
                for match in SWIFT_LITERAL_PATTERN.finditer(first_argument):
                    value = decode_swift_literal(match.group(1))
                    if should_preserve_verbatim(value):
                        continue
                    line = text.count("\n", 0, start + match.start()) + 1
                    location = f"{path.relative_to(ROOT)}:{line}"
                    if r"\(" in value:
                        dynamic.setdefault(value, []).append(location)
                    else:
                        static.add(value)
        for callee, copy_arguments in BTCOPY_ARGUMENTS_BY_CALLEE.items():
            for arguments, start in call_arguments(text, callee):
                for argument in top_level_arguments(arguments):
                    parsed = named_argument(argument)
                    if not parsed or parsed[0] not in copy_arguments:
                        continue
                    expression = parsed[1]
                    for match in SWIFT_LITERAL_PATTERN.finditer(expression):
                        if inside_verbatim_call(expression, match.start()):
                            continue
                        value = decode_swift_literal(match.group(1))
                        if should_preserve_verbatim(value):
                            continue
                        line = text.count("\n", 0, start + arguments.find(argument) + match.start()) + 1
                        location = f"{path.relative_to(ROOT)}:{line}"
                        if r"\(" in value:
                            dynamic.setdefault(value, []).append(location)
                        else:
                            static.add(value)
    return static, dynamic


def ambiguous_runtime_copy() -> list[str]:
    """Find `Text(variable)`/`Label(variable)` calls that bypass the catalog.

    Design-system fields are statically typed as BTCopy, while AppTab titles are
    LocalizedStringKey. Every other runtime String must be explicitly resolved
    with NativeLocalization and rendered with `verbatim:`.
    """
    findings: list[str] = []
    for path in sorted(SOURCE_ROOT.rglob("*.swift")):
        if path.name == "BrassTuneDesignSystem.swift":
            continue
        text = path.read_text(encoding="utf-8")
        for match in AMBIGUOUS_RUNTIME_COPY_PATTERN.finditer(text):
            expression = match.group(1)
            if expression.startswith("AppTab."):
                continue
            line = text.count("\n", 0, match.start()) + 1
            findings.append(f"{path.relative_to(ROOT)}:{line}: {match.group(0)}")
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="Print the discovered static keys as JSON")
    parser.add_argument("--dynamic-json", action="store_true", help="Print interpolated literals and source locations as JSON")
    parser.add_argument("--allow-missing", action="store_true")
    args = parser.parse_args()

    keys, dynamic = source_keys()
    ambiguous_copy = ambiguous_runtime_copy()
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
    placeholder_violations: list[str] = []
    semantic_violations: list[str] = []
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

    for key, entry in sorted(entries.items()):
        expected = placeholder_signature(key)
        for locale, localization in entry.get("localizations", {}).items():
            for unit_path, unit in iter_string_units(localization):
                actual_value = unit.get("value", "")
                actual = placeholder_signature(actual_value)
                if actual != expected and (key, locale, unit_path) not in CLDR_PLACEHOLDER_EXCEPTIONS:
                    placeholder_violations.append(
                        f"{locale}: {key} [{unit_path}] expected {dict(expected)}, got {dict(actual)} -> {actual_value}"
                    )

    if not SEMANTIC_SENTINELS_PATH.exists():
        semantic_violations.append(f"missing sentinel file: {SEMANTIC_SENTINELS_PATH.relative_to(ROOT)}")
    else:
        sentinels = json.loads(SEMANTIC_SENTINELS_PATH.read_text(encoding="utf-8"))
        for key, locale_values in sorted(sentinels.items()):
            for locale, expected_value in sorted(locale_values.items()):
                actual_value = (entries.get(key, {}).get("localizations", {}).get(locale, {})
                                .get("stringUnit", {}).get("value"))
                if actual_value != expected_value:
                    semantic_violations.append(
                        f"{locale}: {key} expected {expected_value!r}, got {actual_value!r}"
                    )

    unexpected_dynamic = sorted(set(dynamic) - ALLOWED_DYNAMIC_LITERALS)

    print(f"Static user-facing keys: {len(keys)}")
    print(f"Catalog entries: {len(entries)}")
    print(f"Dynamic/interpolated literals reviewed separately: {len(dynamic)}")
    print(f"Missing static keys: {len(missing)}")
    print(f"Incomplete locale sets: {len(incomplete)}")
    print(f"Non-English source echoes: {len(source_echoes)}")
    print(f"Terminology violations: {len(terminology_violations)}")
    print(f"Placeholder violations: {len(placeholder_violations)}")
    print(f"Semantic sentinel violations: {len(semantic_violations)}")
    print(f"Allowed dynamic literal exceptions: {len(dynamic)}")
    print(f"Ambiguous runtime Text/Label calls: {len(ambiguous_copy)}")
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
    if placeholder_violations:
        print("\nPlaceholder violations:")
        print("\n".join(placeholder_violations))
    if semantic_violations:
        print("\nSemantic sentinel violations:")
        print("\n".join(semantic_violations))
    if unexpected_dynamic:
        print("\nUnexpected dynamic literals:")
        print("\n".join(unexpected_dynamic))
    if ambiguous_copy:
        print("\nAmbiguous runtime copy (resolve via NativeLocalization and render verbatim):")
        print("\n".join(ambiguous_copy))
    if (missing or incomplete or source_echoes or terminology_violations or placeholder_violations
            or semantic_violations or unexpected_dynamic or ambiguous_copy) and not args.allow_missing:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
