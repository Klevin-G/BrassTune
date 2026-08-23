#!/usr/bin/env python3
"""Fail when an owned project Markdown document lacks the creator attribution."""

from __future__ import annotations

from pathlib import Path
import subprocess


ATTRIBUTION = "Kelvin Guo, Arya Salem"
ROOT_DOCUMENTS = (
    "AGENTS.md",
    "README.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "THIRD_PARTY_ASSETS.md",
    "fixtures/README.md",
    "frontend/src/assets/fonts/README.md",
)
OWNED_PATHSPECS = (*ROOT_DOCUMENTS, "docs", "swift/BrassTuneApp")
FALLBACK_IGNORED_PARTS = {
    ".git",
    ".venv",
    "DerivedData",
    "build",
    "coverage",
    "node_modules",
    "playwright-report",
    "test-results",
}


def _git_paths(root: Path, *args: str) -> set[Path] | None:
    """Return repository-relative paths, or None when Git cannot answer."""
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", *args, "--", *OWNED_PATHSPECS],
            check=True,
            capture_output=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    return {Path(raw.decode("utf-8")) for raw in result.stdout.split(b"\0") if raw}


def _fallback_paths(root: Path) -> set[Path]:
    """Conservative inventory for use only outside a usable Git checkout."""
    candidates = {Path(relative) for relative in ROOT_DOCUMENTS}
    for directory, pattern in ((root / "docs", "*.md"), (root / "swift" / "BrassTuneApp", "*.md")):
        if directory.exists():
            candidates.update(path.relative_to(root) for path in directory.rglob(pattern))
    return {
        path
        for path in candidates
        if not (set(path.parts) & FALLBACK_IGNORED_PARTS) and (root / path).is_file()
    }


def owned_markdown(root: Path) -> list[Path]:
    tracked = _git_paths(root)
    untracked = _git_paths(root, "--others", "--exclude-standard")
    if tracked is None or untracked is None:
        relative_paths = _fallback_paths(root)
    else:
        # Ignored artifacts (for example Playwright HTML/Markdown reports) are
        # intentionally absent from this union, while a new ordinary Markdown
        # file is still checked before it is staged.
        relative_paths = tracked | untracked
    return sorted(
        root / path
        for path in relative_paths
        if path.suffix.lower() == ".md" and (root / path).is_file()
    )


def missing_attribution(root: Path) -> list[Path]:
    return [
        path.relative_to(root)
        for path in owned_markdown(root)
        if ATTRIBUTION not in path.read_text(encoding="utf-8")
    ]


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    missing = missing_attribution(root)
    if missing:
        print("documentation credits: FAIL")
        print("missing attribution:")
        print("\n".join(f"- {path}" for path in missing))
        return 1
    print(f"documentation credits: PASS ({len(owned_markdown(root))} owned Markdown files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
