# Content And Icon System

Updated: 2026-06-20 UTC.

## Product Copy Rules

- Keep user-facing text task-oriented and human. Provider diagnostics belong in docs, logs, or developer surfaces.
- Use "guest practice" only for local/offline device state, not as a substitute for account features.
- Do not call OCR, OMR, printed-note verification, score following, or metronome accuracy complete unless the measured evidence exists.
- Score-practice copy must separate image quality, sheet-music likelihood, audio pitch confidence, score recognition confidence, and alignment confidence.
- Deletion/export copy must make export visible before destructive account deletion.

## Icons And Controls

- Use `lucide-react` icons in command buttons when a clear icon exists.
- Use icon-only buttons for toolbar actions with `aria-label` and `title`; use icon-plus-text for primary commands.
- Current new icons:
  - `Timer` for metronome and tempo tools.
  - `FileText` for score/PDF practice.
  - `Camera`, `Image`, and `Upload` for the three explicit score import actions.
  - `ZoomIn`, `ZoomOut`, `RotateCw`, `Maximize2`, and `Trash2` for score preview controls.
- Selection chips expose `aria-pressed`; the mobile primary nav has an `aria-label`.

## Known Copy/UX Caveats

- "Scan with Camera" is only shown when `getUserMedia` is available and opens a real camera preview.
- "Choose from Photos" and "Choose Files" use browser file pickers; platform availability varies.
- Browser PDF preview currently uses the browser's PDF support, not PDF.js or OMR.
- Metronome timing stats are scheduled-time stats, not a physical acoustic timing certification.
