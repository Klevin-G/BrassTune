#!/usr/bin/env python3
"""Verify the adaptive Swift theme still honors BrassTune's shared token contract."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TOKENS_PATH = ROOT / "design" / "brasstune-tokens.json"
SWIFT_THEME_PATH = ROOT / "swift" / "BrassTuneApp" / "BrassTuneApp" / "DesignSystem" / "BrassTuneDesignSystem.swift"
TOLERANCE = 0.012

REQUIRED_THEME_SYMBOLS = {
    "background",
    "backgroundTop",
    "surface",
    "surfaceWarm",
    "accent",
    "accentSoft",
    "secondaryAccent",
    "success",
    "warning",
    "danger",
    "blue",
    "sharp",
    "flat",
    "unstable",
    "muted",
}

# Content surfaces and status colors deliberately use UIKit semantic colors so
# they adapt to light/dark/high-contrast settings. These declarations are the
# contract; fixed dark-only Color literals are no longer valid.
SEMANTIC_DECLARATIONS = {
    "background": "Color(uiColor: .systemGroupedBackground)",
    "backgroundTop": "Color(uiColor: .systemBackground)",
    "surface": "Color(uiColor: .secondarySystemGroupedBackground)",
    "secondaryAccent": "Color(uiColor: .systemTeal)",
    "success": "Color(uiColor: .systemGreen)",
    "warning": "Color(uiColor: .systemOrange)",
    "danger": "Color(uiColor: .systemRed)",
    "blue": "Color(uiColor: .systemBlue)",
    "sharp": "Color(uiColor: .systemOrange)",
    "flat": "Color(uiColor: .systemBlue)",
    "unstable": "Color(uiColor: .secondaryLabel)",
    "muted": "Color(uiColor: .secondaryLabel)",
}

# Brand-bearing adaptive colors retain exact dark-mode anchors from the shared
# token file while their light variants use higher-contrast values.
ADAPTIVE_DARK_TOKEN_MAP = {
    "surfaceWarm": ("color", "palette", "tintedGlass"),
    "accent": ("color", "palette", "gold600"),
    "accentSoft": ("color", "palette", "gold400"),
}


def token_value(tokens: dict, path: tuple[str, ...]) -> str:
    value = tokens
    for key in path:
        value = value[key]
    if not isinstance(value, str):
        raise TypeError(f"{'.'.join(path)} is not a string token")
    return value


def parse_css_color(value: str) -> tuple[float, float, float]:
    if value.startswith("#") and len(value) == 7:
        return tuple(int(value[index : index + 2], 16) / 255 for index in (1, 3, 5))
    match = re.fullmatch(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*(?:0|1|0?\.\d+)\)", value)
    if match:
        return tuple(int(component) / 255 for component in match.groups())
    raise ValueError(f"Unsupported color token format: {value}")


def declared_theme_symbols(source: str) -> set[str]:
    return set(re.findall(r"\bstatic\s+let\s+(\w+)\s*=", source))


def adaptive_dark_color(source: str, name: str) -> tuple[float, float, float] | None:
    pattern = re.compile(
        rf"static\s+let\s+{re.escape(name)}\s*=\s*adaptive\("
        rf".*?dark:\s*UIColor\(red:\s*(?P<red>[0-9.]+),\s*"
        rf"green:\s*(?P<green>[0-9.]+),\s*blue:\s*(?P<blue>[0-9.]+),",
        re.DOTALL,
    )
    match = pattern.search(source)
    if match is None:
        return None
    return tuple(float(match.group(component)) for component in ("red", "green", "blue"))


def main() -> int:
    tokens = json.loads(TOKENS_PATH.read_text())
    source = SWIFT_THEME_PATH.read_text()
    failures: list[str] = []

    declared = declared_theme_symbols(source)
    for name in sorted(REQUIRED_THEME_SYMBOLS - declared):
        failures.append(f"Missing Swift color BTTheme.{name}")

    for name, initializer in SEMANTIC_DECLARATIONS.items():
        declaration = f"static let {name} = {initializer}"
        if declaration not in source:
            failures.append(f"BTTheme.{name} must use adaptive semantic initializer {initializer}")

    for swift_name, token_path in ADAPTIVE_DARK_TOKEN_MAP.items():
        actual = adaptive_dark_color(source, swift_name)
        if actual is None:
            failures.append(f"BTTheme.{swift_name} must declare an adaptive dark UIColor")
            continue
        expected = parse_css_color(token_value(tokens, token_path))
        deltas = tuple(abs(left - right) for left, right in zip(actual, expected))
        if any(delta > TOLERANCE for delta in deltas):
            failures.append(
                f"BTTheme.{swift_name} drifted from {'.'.join(token_path)} in dark mode: "
                f"actual={actual}, expected={expected}, deltas={deltas}"
            )

    if ".preferredColorScheme(.dark)" in source:
        failures.append("The design system must respect system appearance instead of forcing dark mode")

    required_glass_markers = (
        "if #available(iOS 26.0, *)",
        "GlassEffectContainer",
        ".glassEffect(",
        ".background(.ultraThinMaterial",
    )
    for marker in required_glass_markers:
        if marker not in source:
            failures.append(f"Missing centralized Liquid Glass marker: {marker}")

    if failures:
        print("Design token verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        f"Verified {len(REQUIRED_THEME_SYMBOLS)} adaptive Swift theme colors, "
        f"{len(ADAPTIVE_DARK_TOKEN_MAP)} shared brand anchors, and the centralized glass fallback"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
