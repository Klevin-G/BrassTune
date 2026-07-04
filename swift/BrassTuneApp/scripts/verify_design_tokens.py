#!/usr/bin/env python3
"""Verify Swift theme colors still map to the shared BrassTune token contract."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TOKENS_PATH = ROOT / "design" / "brasstune-tokens.json"
SWIFT_THEME_PATH = ROOT / "swift" / "BrassTuneApp" / "BrassTuneApp" / "DesignSystem" / "BrassTuneDesignSystem.swift"
TOLERANCE = 0.012

TOKEN_MAP = {
    "background": ("color", "palette", "navy900"),
    "backgroundTop": ("color", "palette", "navy850"),
    "surface": ("color", "palette", "navy800"),
    "surfaceWarm": ("color", "palette", "tintedGlass"),
    "accent": ("color", "palette", "gold600"),
    "accentSoft": ("color", "palette", "gold400"),
    "secondaryAccent": ("color", "palette", "teal"),
    "success": ("color", "palette", "green"),
    "warning": ("color", "palette", "amber"),
    "danger": ("color", "palette", "red"),
    "blue": ("color", "palette", "blue"),
    "muted": ("statusColors", "unstable"),
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
        return tuple(int(value[i : i + 2], 16) / 255 for i in (1, 3, 5))
    match = re.fullmatch(r"rgba\((\d+),\s*(\d+),\s*(\d+),\s*(?:0|1|0?\.\d+)\)", value)
    if match:
        return tuple(int(component) / 255 for component in match.groups())
    raise ValueError(f"Unsupported color token format: {value}")


def swift_colors(source: str) -> dict[str, tuple[float, float, float]]:
    pattern = re.compile(
        r"static let (?P<name>\w+) = Color\(red: (?P<red>[0-9.]+), green: (?P<green>[0-9.]+), blue: (?P<blue>[0-9.]+)\)"
    )
    return {
        match.group("name"): (
            float(match.group("red")),
            float(match.group("green")),
            float(match.group("blue")),
        )
        for match in pattern.finditer(source)
    }


def main() -> int:
    tokens = json.loads(TOKENS_PATH.read_text())
    swift = swift_colors(SWIFT_THEME_PATH.read_text())
    failures: list[str] = []

    for swift_name, token_path in TOKEN_MAP.items():
        if swift_name not in swift:
            failures.append(f"Missing Swift color BTTheme.{swift_name}")
            continue
        expected = parse_css_color(token_value(tokens, token_path))
        actual = swift[swift_name]
        deltas = tuple(abs(left - right) for left, right in zip(actual, expected))
        if any(delta > TOLERANCE for delta in deltas):
            failures.append(
                f"BTTheme.{swift_name} drifted from {'.'.join(token_path)}: "
                f"actual={actual}, expected={expected}, deltas={deltas}"
            )

    if failures:
        print("Design token verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Verified {len(TOKEN_MAP)} Swift theme colors against {TOKENS_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
