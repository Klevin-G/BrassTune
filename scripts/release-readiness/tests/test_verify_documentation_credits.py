#!/usr/bin/env python3
"""Regression coverage for the documentation-credit inventory policy."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify_documentation_credits.py"
SPEC = importlib.util.spec_from_file_location("verify_documentation_credits", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
credits = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(credits)


class DocumentationCreditsInventoryTests(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)
        return root

    @staticmethod
    def write(root: Path, relative: str, text: str) -> Path:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    @staticmethod
    def stage(root: Path, relative: str) -> None:
        subprocess.run(["git", "-C", str(root), "add", "--", relative], check=True)

    def test_ignored_playwright_markdown_is_not_checked(self) -> None:
        root = self.make_repo()
        self.write(root, ".gitignore", "docs/release-readiness/playwright-report/\n")
        self.write(root, "docs/owned.md", credits.ATTRIBUTION)
        self.stage(root, ".gitignore")
        self.stage(root, "docs/owned.md")
        self.write(
            root,
            "docs/release-readiness/playwright-report/data/generated.md",
            "generated artifact without attribution",
        )

        owned = {path.relative_to(root).as_posix() for path in credits.owned_markdown(root)}

        self.assertEqual({"docs/owned.md"}, owned)
        self.assertEqual([], credits.missing_attribution(root))

    def test_nonignored_untracked_markdown_is_checked(self) -> None:
        root = self.make_repo()
        self.write(root, "docs/owned.md", credits.ATTRIBUTION)
        self.stage(root, "docs/owned.md")
        self.write(root, "docs/new-unattributed.md", "ordinary documentation")

        self.assertEqual([Path("docs/new-unattributed.md")], credits.missing_attribution(root))


if __name__ == "__main__":
    unittest.main()
